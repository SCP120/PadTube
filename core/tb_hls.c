#include "tb_hls.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include "tb_http.h"
#include "tb_live.h"

static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static int g_port = -1, g_gen;
static tb_stream *g_stream;
static tb_live *g_live;
static int g_order[8], g_norder;
/* extra streams (tb_hls_add): their own generation numbers, far from g_gen so the two never meet */
static struct { int gen; tb_stream *s; int limit, served; } g_extra[TB_HLS_EXTRA];
static pthread_cond_t g_gate = PTHREAD_COND_INITIALIZER;   /* a limit rose or a stream was removed */
static int g_xgen = 1000000;
static tb_hls_stats g_st;
/* Request log for the device tests: what the iOS player asks for, and when (ms after tb_hls_set). */
#define LOG_N 64
static struct { double t, serve_ms; long bytes; char path[48]; int status; } g_log[LOG_N];
static int g_log_n;
static double g_set_at;
static void log_req(const char *path, double t0, long bytes, int status) {
    pthread_mutex_lock(&g_mu);
    int i = g_log_n++ % LOG_N;
    g_log[i].t = t0 - g_set_at;
    g_log[i].serve_ms = tb_now_ms() - t0;
    g_log[i].bytes = bytes;
    g_log[i].status = status;
    snprintf(g_log[i].path, sizeof g_log[i].path, "%s", path);
    pthread_mutex_unlock(&g_mu);
}

int tb_hls_log(char *out, size_t cap) {
    pthread_mutex_lock(&g_mu);
    size_t n = 0;
    int first = g_log_n > LOG_N ? g_log_n - LOG_N : 0;
    for (int k = first; k < g_log_n && n + 120 < cap; k++) {
        int i = k % LOG_N;
        n += (size_t)snprintf(out + n, cap - n, "%.0f %s %d %ld %.0f\n", g_log[i].t, g_log[i].path, g_log[i].status, g_log[i].bytes, g_log[i].serve_ms);
    }
    out[n] = 0;
    pthread_mutex_unlock(&g_mu);
    return (int)n;
}

static int send_all(int fd, const void *p, size_t n) {
    const char *c = p;
    while (n) {
        ssize_t w = send(fd, c, n, 0);
        if (w <= 0) return -1;
        c += w;
        n -= (size_t)w;
    }
    return 0;
}

static void reply(int fd, int code, const char *type, const void *body, size_t n, int head_only) {
    char h[256];
    const char *msg = code == 200 ? "OK" : code == 404 ? "Not Found" : code == 503 ? "Service Unavailable" : "Bad Gateway";
    int hl = snprintf(h, sizeof h, "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n",
                      code, msg, type, n);
    if (send_all(fd, h, (size_t)hl) == 0 && n && !head_only) send_all(fd, body, n);
}

static tb_stream *acquire(int gen) {
    pthread_mutex_lock(&g_mu);
    tb_stream *s = gen == g_gen ? g_stream : NULL;
    for (int i = 0; !s && i < TB_HLS_EXTRA; i++) if (g_extra[i].s && g_extra[i].gen == gen) s = g_extra[i].s;
    if (s) tb_stream_retain(s);
    pthread_mutex_unlock(&g_mu);
    return s;
}

static void serve(int fd, const char *path, int head_only) {
    int gen = 0, vi = 0, seg = 0;
    char tail[64] = "";
    double t0 = tb_now_ms();
    pthread_mutex_lock(&g_mu);
    g_st.requests++;
    pthread_mutex_unlock(&g_mu);
    if (sscanf(path, "/%d/%63s", &gen, tail) != 2) { reply(fd, 404, "text/plain", "", 0, 0); return; }
    long sq = 0;
    if (!strcmp(tail, "live.m3u8") || sscanf(tail, "live/%ld.ts", &sq) == 1) {
        pthread_mutex_lock(&g_mu);
        tb_live *l = gen == g_gen ? g_live : NULL;
        if (l) tb_live_retain(l);
        pthread_mutex_unlock(&g_mu);
        if (!l) { reply(fd, 404, "text/plain", "", 0, 0); return; }
        int e;
        if (sq) {
            tb_out o = {0};
            e = tb_live_segment(l, sq, &o);
            if (!e) reply(fd, 200, "video/mp2t", o.p, o.len, head_only);
            log_req(path, t0, (long)o.len, e ? e : 200);
            tb_out_free(&o);
        } else {
            char *pl = NULL;
            e = tb_live_playlist(l, &pl);
            if (!e) reply(fd, 200, "application/vnd.apple.mpegurl", pl, strlen(pl), head_only);
            log_req(path, t0, pl ? (long)strlen(pl) : 0, e ? e : 200);
            free(pl);
        }
        tb_live_release(l);
        if (e) { tb_log("tb_hls: %s -> error %d", path, e); reply(fd, e == -404 ? 404 : 502, "text/plain", "", 0, 0); }
        return;
    }
    tb_stream *s = acquire(gen);
    if (!s) { reply(fd, 404, "text/plain", "", 0, 0); return; }
    int err = 0;
    if (!strcmp(tail, "master.m3u8")) {
        char *pl = NULL;
        int order[8], n;
        pthread_mutex_lock(&g_mu);
        n = g_norder;
        memcpy(order, g_order, sizeof order);
        pthread_mutex_unlock(&g_mu);
        tb_stream_master(s, order, n, &pl);
        reply(fd, 200, "application/vnd.apple.mpegurl", pl, strlen(pl), head_only);
        log_req(path, t0, (long)strlen(pl), 200);
        free(pl);
    } else if (sscanf(tail, "%d/%d.ts", &vi, &seg) == 2) {
        int open = 1, slot = -1;   /* preload gate: wait while seg is above the stream's limit */
        pthread_mutex_lock(&g_mu);
        for (;;) {
            slot = -1;
            for (int i = 0; i < TB_HLS_EXTRA; i++) if (g_extra[i].s == s && g_extra[i].gen == gen) slot = i;
            if (slot < 0 || g_extra[slot].limit < 0 || seg <= g_extra[slot].limit) break;
            struct timespec ts;
            struct timeval tv;
            gettimeofday(&tv, NULL);
            ts.tv_sec = tv.tv_sec + 1;
            ts.tv_nsec = tv.tv_usec * 1000;
            pthread_cond_timedwait(&g_gate, &g_mu, &ts);   /* rechecked at least once a second */
        }
        if (slot < 0 && gen != g_gen) open = 0;   /* removed while waiting */
        int lim = slot >= 0 ? g_extra[slot].limit : -1;
        pthread_mutex_unlock(&g_mu);
        if (!open) { tb_stream_release(s); reply(fd, 404, "text/plain", "", 0, 0); return; }
        tb_out o = {0};
        err = tb_stream_segment(s, vi, seg, &o);
        if (!err) {
            reply(fd, 200, "video/mp2t", o.p, o.len, head_only);
            if (lim < 0 || seg + 1 <= lim) tb_stream_prefetch(s, vi, seg + 1);   /* not past the gate */
            pthread_mutex_lock(&g_mu);
            if (slot >= 0 && g_extra[slot].s == s && seg > g_extra[slot].served) g_extra[slot].served = seg;
            pthread_mutex_unlock(&g_mu);
        }
        log_req(path, t0, (long)o.len, err ? err : 200);
        tb_out_free(&o);
        pthread_mutex_lock(&g_mu);
        g_st.segments++;
        g_st.last_seg = seg;
        g_st.last_serve_ms = tb_now_ms() - t0;
        pthread_mutex_unlock(&g_mu);
    } else if (sscanf(tail, "%d.m3u8", &vi) == 1) {
        char *pl = NULL;
        err = tb_stream_playlist(s, vi, &pl);
        if (!err) reply(fd, 200, "application/vnd.apple.mpegurl", pl, strlen(pl), head_only);
        log_req(path, t0, pl ? (long)strlen(pl) : 0, err ? err : 200);
        free(pl);
    } else err = -404;
    tb_stream_release(s);
    if (err) {
        pthread_mutex_lock(&g_mu);
        g_st.errors++;
        pthread_mutex_unlock(&g_mu);
        tb_log("tb_hls: %s -> error %d", path, err);
        reply(fd, err == -404 ? 404 : 502, "text/plain", "", 0, 0);
    }
}

static void *conn_main(void *arg) {
    int fd = (int)(intptr_t)arg;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    char buf[4096];
    size_t have = 0;
    for (;;) {
        ssize_t r = recv(fd, buf + have, sizeof buf - 1 - have, 0);
        if (r <= 0) break;
        have += (size_t)r;
        buf[have] = 0;
        char *end;
        while ((end = strstr(buf, "\r\n\r\n"))) {
            char method[8] = "", path[512] = "";
            sscanf(buf, "%7s %511s", method, path);
            char *q = strchr(path, '?');
            if (q) *q = 0;
            serve(fd, path, !strcmp(method, "HEAD"));
            size_t used = (size_t)(end + 4 - buf);
            memmove(buf, end + 4, have - used + 1);
            have -= used;
        }
        if (have >= sizeof buf - 1) break;
    }
    close(fd);
    return NULL;
}

/* A listening socket of an app iOS suspended can come back defunct: accept() then fails at once on every call
 * (the old loop spun and the player got no answer). Open it again on the same port, so the playlist URLs stay. */
static int listen_on(int port) {
    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    if (ls < 0) return -1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (bind(ls, (struct sockaddr *)&a, sizeof a) || listen(ls, 16)) { close(ls); return -1; }
    return ls;
}

static void *accept_main(void *arg) {
    int ls = (int)(intptr_t)arg;
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            tb_log("tb_hls: accept failed (errno %d): listen again on port %d", errno, g_port);
            close(ls);
            while ((ls = listen_on(g_port)) < 0) usleep(100000);   /* 10 tries per second until the port is free */
            continue;
        }
        pthread_t t;
        pthread_attr_t at;
        pthread_attr_init(&at);
        pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&t, &at, conn_main, (void *)(intptr_t)fd) != 0) close(fd);
        pthread_attr_destroy(&at);
    }
    return NULL;
}

int tb_hls_start(void) {
    pthread_mutex_lock(&g_mu);
    if (g_port > 0) { pthread_mutex_unlock(&g_mu); return g_port; }
    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = 0};
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    socklen_t al = sizeof a;
    if (bind(ls, (struct sockaddr *)&a, sizeof a) || listen(ls, 16) || getsockname(ls, (struct sockaddr *)&a, &al)) {
        close(ls);
        pthread_mutex_unlock(&g_mu);
        return -1;
    }
    g_port = ntohs(a.sin_port);
    pthread_t t;
    pthread_create(&t, NULL, accept_main, (void *)(intptr_t)ls);
    pthread_detach(t);
    pthread_mutex_unlock(&g_mu);
    return g_port;
}

int tb_hls_set_live(tb_live *l) {
    tb_hls_set(NULL, NULL, 0);
    pthread_mutex_lock(&g_mu);
    if (g_live) tb_live_release(g_live);
    g_live = l;
    if (l) tb_live_retain(l);
    int gen = g_gen;
    pthread_mutex_unlock(&g_mu);
    return gen;
}

int tb_hls_set(tb_stream *s, const int *order, int n) {
    pthread_mutex_lock(&g_mu);
    if (g_live) { tb_live_release(g_live); g_live = NULL; }
    if (g_stream) { if (g_stream != s) tb_stream_cancel(g_stream); tb_stream_release(g_stream); }
    g_gen++;
    g_set_at = tb_now_ms();
    g_log_n = 0;
    if (s) tb_stream_retain(s);
    g_stream = s;
    g_norder = n > 8 ? 8 : n;
    if (order && g_norder) memcpy(g_order, order, (size_t)g_norder * sizeof *order);
    int gen = g_gen;
    pthread_mutex_unlock(&g_mu);
    return gen;
}

void tb_hls_url(int vi, int master, char *out, size_t cap) {
    pthread_mutex_lock(&g_mu);
    if (master == 2) snprintf(out, cap, "http://127.0.0.1:%d/%d/live.m3u8", g_port, g_gen);
    else if (master) snprintf(out, cap, "http://127.0.0.1:%d/%d/master.m3u8", g_port, g_gen);
    else snprintf(out, cap, "http://127.0.0.1:%d/%d/%d.m3u8", g_port, g_gen, vi);
    pthread_mutex_unlock(&g_mu);
}

int tb_hls_add(tb_stream *s) {
    int gen = -1;
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < TB_HLS_EXTRA && s; i++)
        if (!g_extra[i].s) {
            tb_stream_retain(s);
            g_extra[i].s = s;
            g_extra[i].limit = TB_HLS_OPEN;
            g_extra[i].served = -1;
            gen = g_extra[i].gen = ++g_xgen;
            break;
        }
    pthread_mutex_unlock(&g_mu);
    return gen;
}

void tb_hls_remove(int gen) {
    tb_stream *s = NULL;
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < TB_HLS_EXTRA; i++)
        if (g_extra[i].s && g_extra[i].gen == gen) { s = g_extra[i].s; g_extra[i].s = NULL; break; }
    pthread_cond_broadcast(&g_gate);
    pthread_mutex_unlock(&g_mu);
    if (s) { tb_stream_cancel(s); tb_stream_release(s); }   /* a request being served keeps its own reference */
}

void tb_hls_limit(int gen, int max_seg) {
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < TB_HLS_EXTRA; i++)
        if (g_extra[i].s && g_extra[i].gen == gen) g_extra[i].limit = max_seg == TB_HLS_FREEZE ? (g_extra[i].served < 0 ? 0 : g_extra[i].served) : max_seg;
    pthread_cond_broadcast(&g_gate);
    pthread_mutex_unlock(&g_mu);
}

int tb_hls_served_max(int gen) {
    int r = -1;
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < TB_HLS_EXTRA; i++) if (g_extra[i].s && g_extra[i].gen == gen) r = g_extra[i].served;
    pthread_mutex_unlock(&g_mu);
    return r;
}

void tb_hls_url_gen(int gen, int vi, char *out, size_t cap) {
    pthread_mutex_lock(&g_mu);
    snprintf(out, cap, "http://127.0.0.1:%d/%d/%d.m3u8", g_port, gen, vi);
    pthread_mutex_unlock(&g_mu);
}

void tb_hls_get_stats(tb_hls_stats *out) {
    pthread_mutex_lock(&g_mu);
    *out = g_st;
    pthread_mutex_unlock(&g_mu);
}
