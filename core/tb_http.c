#include "tb_http.h"
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>
#include <syslog.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <signal.h>
#include <unistd.h>
#include <zlib.h>
#include <openssl/err.h>
#include <openssl/ssl.h>

/* Idle connections kept per process. The app talks to 3-4 hosts (API, images, googlevideo, suggest). */
#define POOL_MAX 8
/* Google closes idle keep-alive connections after about 4 minutes (MEASURED on the Mac, 2026-11-11, i.ytimg.com);
 * drop ours earlier so a reused socket is rarely dead. */
#define IDLE_MAX_MS 120000.0
#define RBUF 16384
/* First answer byte on a REUSED connection, GET only: a socket that died while the app was suspended (Wi-Fi sleep,
 * NAT) gets no reset, so the wait ran to the full 20 s timeout before the retry (owner bug 2026-11-12: about 30 s of
 * "loading" after a return). A cold googlevideo host answers in about 0.5 s on a NEW connection (MEASURED on the
 * iPad 2026-11-11); a reused one is faster. 6x that, then retry once on a new connection. */
#define REUSED_FIRST_BYTE_MS 3000

typedef struct {
    int fd;
    SSL *ssl;
    char host[128];
    int port, tls;
    double idle_since;
    unsigned char rbuf[RBUF];
    size_t rpos, rlen;
} conn;

static SSL_CTX *g_ctx;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static conn *g_pool[POOL_MAX];
static tb_http_stats g_stats;
/* TLS session per host: resumption skips the full handshake (iOS 6's own stack cannot do this, research §6). */
static struct { char host[128]; SSL_SESSION *s; } g_sess[16];
static int g_sess_idx = -1;

double tb_now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

void tb_log(const char *fmt, ...) {
    char b[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    fprintf(stderr, "%s\n", b);
    syslog(LOG_WARNING, "%s", b);
}

const char *tb_http_strerror(int code) {
    switch (code) {
    case TB_ERR_URL: return "bad URL";
    case TB_ERR_DNS: return "host not found";
    case TB_ERR_CONNECT: return "cannot connect";
    case TB_ERR_TLS: return "TLS failed";
    case TB_ERR_IO: return "connection lost";
    case TB_ERR_PROTO: return "bad HTTP answer";
    case TB_ERR_CANCEL: return "cancelled";
    case TB_ERR_MEM: return "out of memory";
    case TB_ERR_GZIP: return "bad gzip data";
    default: return code >= 0 ? "ok" : "error";
    }
}

static int new_session_cb(SSL *ssl, SSL_SESSION *s) {
    const char *host = SSL_get_ex_data(ssl, g_sess_idx);
    if (!host) return 0;
    pthread_mutex_lock(&g_mu);
    int slot = -1;
    for (int i = 0; i < 16; i++)
        if (strcmp(g_sess[i].host, host) == 0 || (slot < 0 && !g_sess[i].host[0])) { slot = i; if (g_sess[i].host[0]) break; }
    if (slot < 0) slot = 0;
    if (g_sess[slot].s) SSL_SESSION_free(g_sess[slot].s);
    snprintf(g_sess[slot].host, sizeof g_sess[slot].host, "%s", host);
    g_sess[slot].s = s;
    pthread_mutex_unlock(&g_mu);
    return 1; /* we keep the reference */
}

int tb_http_init(const char *ca_file) {
    if (g_ctx) return 0;
    signal(SIGPIPE, SIG_IGN);
    g_ctx = SSL_CTX_new(TLS_client_method());
    if (!g_ctx) return -1;
    SSL_CTX_set_min_proto_version(g_ctx, TLS1_2_VERSION);
    SSL_CTX_set_verify(g_ctx, SSL_VERIFY_PEER, NULL);
    if (SSL_CTX_load_verify_locations(g_ctx, ca_file, NULL) != 1) return -1;
    SSL_CTX_set_session_cache_mode(g_ctx, SSL_SESS_CACHE_CLIENT | SSL_SESS_CACHE_NO_INTERNAL_STORE);
    SSL_CTX_sess_set_new_cb(g_ctx, new_session_cb);
    g_sess_idx = SSL_get_ex_new_index(0, NULL, NULL, NULL, NULL);
    return 0;
}

void tb_http_get_stats(tb_http_stats *out) {
    pthread_mutex_lock(&g_mu);
    *out = g_stats;
    pthread_mutex_unlock(&g_mu);
}

static void conn_free(conn *c) {
    if (!c) return;
    if (c->ssl) { SSL_shutdown(c->ssl); SSL_free(c->ssl); }
    if (c->fd >= 0) close(c->fd);
    free(c);
}

void tb_http_drop_idle(void) {
    pthread_mutex_lock(&g_mu);
    conn *drop[POOL_MAX];
    for (int i = 0; i < POOL_MAX; i++) { drop[i] = g_pool[i]; g_pool[i] = NULL; }
    pthread_mutex_unlock(&g_mu);
    for (int i = 0; i < POOL_MAX; i++) {
        if (!drop[i]) continue;
        if (drop[i]->ssl) SSL_free(drop[i]->ssl);   /* no TLS goodbye: the peer may be gone; a write could block */
        if (drop[i]->fd >= 0) close(drop[i]->fd);
        free(drop[i]);
    }
}

void tb_http_close_idle(void) {
    pthread_mutex_lock(&g_mu);
    conn *drop[POOL_MAX];
    for (int i = 0; i < POOL_MAX; i++) { drop[i] = g_pool[i]; g_pool[i] = NULL; }
    pthread_mutex_unlock(&g_mu);
    for (int i = 0; i < POOL_MAX; i++) conn_free(drop[i]);
}

static conn *pool_take(const char *host, int port, int tls) {
    conn *c = NULL, *stale[POOL_MAX];
    int ns = 0;
    double now = tb_now_ms();
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < POOL_MAX; i++) {
        conn *p = g_pool[i];
        if (!p) continue;
        if (now - p->idle_since > IDLE_MAX_MS) { stale[ns++] = p; g_pool[i] = NULL; continue; }
        if (!c && p->port == port && p->tls == tls && strcmp(p->host, host) == 0) { c = p; g_pool[i] = NULL; }
    }
    pthread_mutex_unlock(&g_mu);
    for (int i = 0; i < ns; i++) conn_free(stale[i]);
    return c;
}

static void pool_put(conn *c) {
    c->idle_since = tb_now_ms();
    conn *old = NULL;
    pthread_mutex_lock(&g_mu);
    int slot = -1;
    double oldest = 1e300;
    for (int i = 0; i < POOL_MAX; i++) {
        if (!g_pool[i]) { slot = i; break; }
        if (g_pool[i]->idle_since < oldest) { oldest = g_pool[i]->idle_since; slot = i; }
    }
    old = g_pool[slot];
    g_pool[slot] = c;
    pthread_mutex_unlock(&g_mu);
    conn_free(old);
}

static void sock_timeouts(int fd, int ms) {
    struct timeval tv = {ms / 1000, (ms % 1000) * 1000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
}

static int wait_fd(int fd, int events, int timeout_ms, volatile int *cancel) {
    double end = tb_now_ms() + timeout_ms;
    for (;;) {
        if (cancel && *cancel) return TB_ERR_CANCEL;
        double left = end - tb_now_ms();
        if (left <= 0) return TB_ERR_IO;
        struct pollfd p = {.fd = fd, .events = (short)events};
        int r = poll(&p, 1, left > 200 ? 200 : (int)left);
        /* a dead or defunct socket: an error state without the wanted event is not "ready" (the read after it blocked
         * until the socket timeout, 20 s, on the iPad after a return: owner bug 2026-11-12) */
        if (r > 0 && ((p.revents & POLLNVAL) || ((p.revents & (POLLERR | POLLHUP)) && !(p.revents & events)))) return TB_ERR_IO;
        if (r > 0) return 0;
        if (r < 0 && errno != EINTR) return TB_ERR_IO;
    }
}

/* RFC 8305 "Connection Attempt Delay" (recommended 250 ms): start the next address when the earlier ones have not
 * connected by then, and keep them open; the first one that connects wins. Trying the addresses one by one with the
 * full timeout each made a return take 20 s on the iPad: an IPv6 address hung, the IPv4 one then connected at once
 * (device run 2026-11-12: "connect 20130 ms"). */
#define ATTEMPT_DELAY_MS 250
#define MAX_ATTEMPTS 8

static int attempt(const struct addrinfo *a) {
    int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (fd < 0) return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    if (connect(fd, a->ai_addr, a->ai_addrlen) != 0 && errno != EINPROGRESS) { close(fd); return -1; }
    return fd;
}

static int dial(const char *host, int port, int timeout_ms, volatile int *cancel) {
    char ps[8];
    snprintf(ps, sizeof ps, "%d", port);
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM}, *res = NULL;
    if (getaddrinfo(host, ps, &hints, &res) != 0 || !res) return TB_ERR_DNS;
    struct pollfd p[MAX_ATTEMPTS];
    int n = 0, won = -1, err = TB_ERR_CONNECT;
    const struct addrinfo *next = res;
    double end = tb_now_ms() + timeout_ms, next_at = 0;
    for (;;) {
        if (cancel && *cancel) { err = TB_ERR_CANCEL; break; }
        double now = tb_now_ms();
        if (now >= end) break;
        if (next && n < MAX_ATTEMPTS && now >= next_at) {   /* start the next address */
            int fd = attempt(next);
            next = next->ai_next;
            if (fd >= 0) { p[n].fd = fd; p[n].events = POLLOUT; p[n].revents = 0; n++; }
            next_at = now + ATTEMPT_DELAY_MS;
            continue;
        }
        int open = 0;
        for (int i = 0; i < n; i++) open += p[i].fd >= 0;
        if (!open && !next) break;                          /* every address failed */
        double until = next ? (next_at < end ? next_at : end) : end;
        int slice = (int)(until - now);
        if (slice > 200) slice = 200;                       /* the cancel flag is checked every 200 ms */
        if (slice < 1) slice = 1;
        if (!open) { usleep((useconds_t)slice * 1000); continue; }
        int r = poll(p, (nfds_t)n, slice);
        if (r < 0 && errno != EINTR) break;
        for (int i = 0; r > 0 && i < n && won < 0; i++) {
            if (p[i].fd < 0 || !p[i].revents) continue;
            int so = 0;
            socklen_t sl = sizeof so;
            getsockopt(p[i].fd, SOL_SOCKET, SO_ERROR, &so, &sl);
            if (so == 0 && (p[i].revents & POLLOUT)) won = i;
            else { close(p[i].fd); p[i].fd = -1; }       /* this address failed; the others go on */
        }
        if (won >= 0) break;
    }
    int fd = won >= 0 ? p[won].fd : -1;
    for (int i = 0; i < n; i++) if (i != won && p[i].fd >= 0) close(p[i].fd);
    freeaddrinfo(res);
    if (fd < 0) return err;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) & ~O_NONBLOCK);
    sock_timeouts(fd, timeout_ms);
    return fd;
}

static conn *conn_open(const char *host, int port, int tls, int timeout_ms, volatile int *cancel, int *err) {
    int fd = dial(host, port, timeout_ms, cancel);
    if (fd < 0) { *err = fd; return NULL; }
    conn *c = calloc(1, sizeof *c);
    if (!c) { close(fd); *err = TB_ERR_MEM; return NULL; }
    c->fd = fd;
    c->port = port;
    c->tls = tls;
    snprintf(c->host, sizeof c->host, "%s", host);
    if (!tls) return c;
    double t0 = tb_now_ms();
    c->ssl = SSL_new(g_ctx);
    SSL_set_ex_data(c->ssl, g_sess_idx, c->host);
    SSL_set_tlsext_host_name(c->ssl, host);
    SSL_set1_host(c->ssl, host);
    SSL_set_fd(c->ssl, fd);
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < 16; i++)
        if (g_sess[i].s && strcmp(g_sess[i].host, host) == 0) { SSL_set_session(c->ssl, g_sess[i].s); break; }
    pthread_mutex_unlock(&g_mu);
    if (SSL_connect(c->ssl) != 1) {
        ERR_clear_error();
        conn_free(c);
        *err = TB_ERR_TLS;
        return NULL;
    }
    pthread_mutex_lock(&g_mu);
    g_stats.handshakes++;
    g_stats.handshake_ms_total += tb_now_ms() - t0;
    pthread_mutex_unlock(&g_mu);
    return c;
}

static int conn_write(conn *c, const void *p, size_t n) {
    const char *s = p;
    while (n > 0) {
        long w = c->ssl ? SSL_write(c->ssl, s, (int)n) : (long)send(c->fd, s, n, 0);
        if (w <= 0) {
            if (!c->ssl && w < 0 && errno == EINTR) continue;
            ERR_clear_error();
            return TB_ERR_IO;
        }
        s += w;
        n -= (size_t)w;
    }
    return 0;
}

/* Fill the read buffer. Returns bytes read, 0 at EOF, < 0 on error. */
static long conn_fill(conn *c, int timeout_ms, volatile int *cancel) {
    if (!(c->ssl && SSL_pending(c->ssl) > 0)) {
        int w = wait_fd(c->fd, POLLIN, timeout_ms, cancel);
        if (w) return w;
    }
    long r;
    if (c->ssl) {
        r = SSL_read(c->ssl, c->rbuf, RBUF);
        if (r <= 0) {
            int e = SSL_get_error(c->ssl, (int)r);
            ERR_clear_error();
            return e == SSL_ERROR_ZERO_RETURN ? 0 : (r == 0 ? 0 : TB_ERR_IO);
        }
    } else {
        do r = recv(c->fd, c->rbuf, RBUF, 0); while (r < 0 && errno == EINTR);
        if (r < 0) return TB_ERR_IO;
    }
    c->rpos = 0;
    c->rlen = (size_t)r;
    return r;
}

typedef struct { char *p; size_t len, cap; } buf;
static int buf_add(buf *b, const void *d, size_t n) {
    if (b->len + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 4096;
        while (cap < b->len + n + 1) cap *= 2;
        char *np = realloc(b->p, cap);
        if (!np) return TB_ERR_MEM;
        b->p = np;
        b->cap = cap;
    }
    memcpy(b->p + b->len, d, n);
    b->len += n;
    b->p[b->len] = 0;
    return 0;
}

/* Read one line (CRLF) into out. Returns length or < 0. */
static long read_line(conn *c, char *out, size_t cap, int tmo, volatile int *cancel) {
    size_t n = 0;
    for (;;) {
        if (c->rpos >= c->rlen) {
            long r = conn_fill(c, tmo, cancel);
            if (r <= 0) return r == 0 ? TB_ERR_IO : r;
        }
        char ch = (char)c->rbuf[c->rpos++];
        if (ch == '\n') {
            if (n && out[n - 1] == '\r') n--;
            out[n] = 0;
            return (long)n;
        }
        if (n + 1 < cap) out[n++] = ch;
    }
}

static int read_exact(conn *c, buf *b, size_t n, int tmo, volatile int *cancel) {
    while (n > 0) {
        if (c->rpos >= c->rlen) {
            long r = conn_fill(c, tmo, cancel);
            if (r <= 0) return r == 0 ? TB_ERR_IO : (int)r;
        }
        size_t take = c->rlen - c->rpos;
        if (take > n) take = n;
        if (b && buf_add(b, c->rbuf + c->rpos, take)) return TB_ERR_MEM;
        c->rpos += take;
        n -= take;
    }
    return 0;
}

static int gunzip(buf *in, buf *out) {
    z_stream z;
    memset(&z, 0, sizeof z);
    if (inflateInit2(&z, 16 + MAX_WBITS) != Z_OK) return TB_ERR_GZIP;
    z.next_in = (unsigned char *)in->p;
    z.avail_in = (unsigned)in->len;
    unsigned char tmp[16384];
    int r;
    do {
        z.next_out = tmp;
        z.avail_out = sizeof tmp;
        r = inflate(&z, Z_NO_FLUSH);
        if (r != Z_OK && r != Z_STREAM_END) { inflateEnd(&z); return TB_ERR_GZIP; }
        if (buf_add(out, tmp, sizeof tmp - z.avail_out)) { inflateEnd(&z); return TB_ERR_MEM; }
    } while (r != Z_STREAM_END && (z.avail_in > 0 || z.avail_out == 0));
    inflateEnd(&z);
    return 0;
}

typedef struct { char host[128]; int port, tls; const char *path; } url_t;
static int parse_url(const char *u, url_t *o) {
    const char *p;
    if (strncmp(u, "https://", 8) == 0) { o->tls = 1; o->port = 443; p = u + 8; }
    else if (strncmp(u, "http://", 7) == 0) { o->tls = 0; o->port = 80; p = u + 7; }
    else return TB_ERR_URL;
    const char *slash = strchr(p, '/');
    size_t hl = slash ? (size_t)(slash - p) : strlen(p);
    if (hl == 0 || hl >= sizeof o->host) return TB_ERR_URL;
    memcpy(o->host, p, hl);
    o->host[hl] = 0;
    char *colon = strchr(o->host, ':');
    if (colon) { *colon = 0; o->port = atoi(colon + 1); }
    o->path = slash ? slash : "/";
    return 0;
}

/* One request on one connection. *keep = connection can be pooled. *fresh_fail = failed before any answer byte. */
static int exchange(conn *c, const tb_req *rq, const url_t *u, tb_resp *rs, char *location, size_t loccap, int *keep,
                    int *fresh_fail) {
    int tmo = rq->timeout_ms > 0 ? rq->timeout_ms : 15000;
    buf h = {0};
    char line[2048];
    const char *method = rq->method ? rq->method : "GET";
    /* the path can be long (field masks are 1-3 KB): add it in pieces, not through the line buffer */
    buf_add(&h, method, strlen(method));
    buf_add(&h, " ", 1);
    buf_add(&h, u->path, strlen(u->path));
    snprintf(line, sizeof line, " HTTP/1.1\r\nHost: %s\r\nAccept-Encoding: gzip\r\nConnection: keep-alive\r\n", u->host);
    buf_add(&h, line, strlen(line));
    if (rq->range_start >= 0) {
        if (rq->range_end >= 0) snprintf(line, sizeof line, "Range: bytes=%lld-%lld\r\n", (long long)rq->range_start, (long long)rq->range_end);
        else snprintf(line, sizeof line, "Range: bytes=%lld-\r\n", (long long)rq->range_start);
        buf_add(&h, line, strlen(line));
    }
    if (rq->body) {
        snprintf(line, sizeof line, "Content-Length: %zu\r\n", rq->body_len);
        buf_add(&h, line, strlen(line));
    }
    if (rq->headers) buf_add(&h, rq->headers, strlen(rq->headers));
    if (buf_add(&h, "\r\n", 2)) { free(h.p); return TB_ERR_MEM; }
    *fresh_fail = 1;
    int first_tmo = rs->reused && !rq->body && tmo > REUSED_FIRST_BYTE_MS ? REUSED_FIRST_BYTE_MS : tmo;
    if (first_tmo < tmo) sock_timeouts(c->fd, first_tmo);   /* blocking SSL calls too, until the first byte */
    int e = conn_write(c, h.p, h.len);
    free(h.p);
    if (!e && rq->body && rq->body_len) e = conn_write(c, rq->body, rq->body_len);
    if (e) return e;
    /* status line */
    long n = read_line(c, line, sizeof line, first_tmo, rq->cancel);
    if (n < 0) return (int)n;
    *fresh_fail = 0;
    if (first_tmo < tmo) sock_timeouts(c->fd, tmo);
    int major = 0, minor = 0, status = 0;
    if (sscanf(line, "HTTP/%d.%d %d", &major, &minor, &status) != 3) return TB_ERR_PROTO;
    int64_t clen = -1;
    int chunked = 0, gz = 0, close_after = (minor == 0);
    rs->content_type[0] = 0;
    location[0] = 0;
    for (;;) {
        n = read_line(c, line, sizeof line, tmo, rq->cancel);
        if (n < 0) return (int)n;
        if (n == 0) break;
        char *v = strchr(line, ':');
        if (!v) continue;
        *v++ = 0;
        while (*v == ' ') v++;
        if (!strcasecmp(line, "content-length")) clen = strtoll(v, NULL, 10);
        else if (!strcasecmp(line, "transfer-encoding") && strcasestr(v, "chunked")) chunked = 1;
        else if (!strcasecmp(line, "content-encoding") && strcasestr(v, "gzip")) gz = 1;
        else if (!strcasecmp(line, "connection") && strcasestr(v, "close")) close_after = 1;
        else if (!strcasecmp(line, "content-type")) snprintf(rs->content_type, sizeof rs->content_type, "%s", v);
        else if (!strcasecmp(line, "location")) snprintf(location, loccap, "%s", v);
    }
    rs->status = status;
    rs->content_length = clen;
    buf body = {0};
    int err = 0;
    int nobody = !strcmp(method, "HEAD") || status == 204 || status == 304 || (status >= 100 && status < 200);
    if (nobody) {
    } else if (chunked) {
        for (;;) {
            n = read_line(c, line, sizeof line, tmo, rq->cancel);
            if (n < 0) { err = (int)n; break; }
            long sz = strtol(line, NULL, 16);
            if (sz <= 0) { /* trailers */
                while ((n = read_line(c, line, sizeof line, tmo, rq->cancel)) > 0) {}
                if (n < 0) err = (int)n;
                break;
            }
            if ((err = read_exact(c, &body, (size_t)sz, tmo, rq->cancel))) break;
            if ((n = read_line(c, line, sizeof line, tmo, rq->cancel)) < 0) { err = (int)n; break; }
        }
    } else if (clen >= 0) {
        err = read_exact(c, &body, (size_t)clen, tmo, rq->cancel);
    } else {
        close_after = 1;
        for (;;) {
            if (c->rpos < c->rlen) {
                if (buf_add(&body, c->rbuf + c->rpos, c->rlen - c->rpos)) { err = TB_ERR_MEM; break; }
                c->rpos = c->rlen;
            }
            long r = conn_fill(c, tmo, rq->cancel);
            if (r == 0) break;
            if (r < 0) { err = (int)r; break; }
        }
    }
    if (err) { free(body.p); return err; }
    pthread_mutex_lock(&g_mu);
    g_stats.bytes_in += (long)body.len;
    pthread_mutex_unlock(&g_mu);
    if (gz && body.len) {
        buf out = {0};
        err = gunzip(&body, &out);
        free(body.p);
        if (err) { free(out.p); return err; }
        body = out;
    }
    if (!body.p) buf_add(&body, "", 0);
    rs->body = body.p;
    rs->len = body.len;
    *keep = !close_after;
    return status;
}

int tb_http(const tb_req *rq, tb_resp *rs) {
    memset(rs, 0, sizeof *rs);
    rs->content_length = -1;
    double t0 = tb_now_ms();
    int tmo = rq->timeout_ms > 0 ? rq->timeout_ms : 15000;
    tb_req cur = *rq;
    char urlbuf[8192], location[4096];
    snprintf(urlbuf, sizeof urlbuf, "%s", rq->url);
    int result = TB_ERR_URL;
    for (int hop = 0; hop < 5; hop++) {
        url_t u;
        if (parse_url(urlbuf, &u)) { result = TB_ERR_URL; break; }
        cur.url = urlbuf;
        for (int attempt = 0; attempt < 2; attempt++) {
            int err = 0;
            conn *c = attempt == 0 ? pool_take(u.host, u.port, u.tls) : NULL;
            rs->reused = c != NULL;
            if (!c) {
                double tc = tb_now_ms();
                c = conn_open(u.host, u.port, u.tls, tmo, rq->cancel, &err);
                rs->ms_connect += tb_now_ms() - tc;
                if (!c) { result = err; break; }
            }
            int keep = 0, fresh_fail = 0;
            free(rs->body);
            rs->body = NULL;
            result = exchange(c, &cur, &u, rs, location, sizeof location, &keep, &fresh_fail);
            if (result >= 0 && keep) pool_put(c); else conn_free(c);
            /* A pooled socket the server already closed fails before any answer: retry once on a new one. */
            if (result < 0 && rs->reused && fresh_fail && result != TB_ERR_CANCEL) continue;
            break;
        }
        if (result >= 300 && result < 400 && location[0] && result != 304) {
            if (location[0] == '/') {
                char base[300];
                snprintf(base, sizeof base, "%s://%s:%d", u.tls ? "https" : "http", u.host, u.port);
                snprintf(urlbuf, sizeof urlbuf, "%s%s", base, location);
            } else snprintf(urlbuf, sizeof urlbuf, "%s", location);
            if (result == 303) { cur.method = "GET"; cur.body = NULL; cur.body_len = 0; }
            continue;
        }
        break;
    }
    pthread_mutex_lock(&g_mu);
    g_stats.requests++;
    if (rs->reused) g_stats.reused++;
    pthread_mutex_unlock(&g_mu);
    rs->status = result;
    if (result < 0) { free(rs->body); rs->body = NULL; rs->len = 0; }
    rs->ms_total = tb_now_ms() - t0;
    return result;
}

void tb_resp_free(tb_resp *r) {
    free(r->body);
    r->body = NULL;
    r->len = 0;
}
