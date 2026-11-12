/* HTTPS/HTTP client: OpenSSL, keep-alive pool per host, gzip, chunked, redirects. Blocking; thread safe. */
#ifndef TB_HTTP_H
#define TB_HTTP_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    const char *method;      /* "GET" (default) or "POST" */
    const char *url;         /* http://host[:port]/path or https://... */
    const char *headers;     /* extra header lines, each ending in \r\n, or NULL */
    const void *body;
    size_t body_len;
    int64_t range_start;     /* >= 0: send Range: bytes=start-end */
    int64_t range_end;       /* inclusive; -1 = open end */
    volatile int *cancel;    /* optional: set to 1 from another thread to stop */
    int timeout_ms;          /* per read/write; 0 = 15000 */
} tb_req;

typedef struct {
    int status;              /* HTTP status, or < 0 = tb_http error */
    char *body;              /* malloc, decoded (gunzipped), NUL-terminated; free with tb_resp_free */
    size_t len;
    char content_type[96];
    int64_t content_length;  /* from the header, -1 if none */
    double ms_total;         /* wall time of the whole request */
    double ms_connect;       /* 0 if a pooled connection was reused */
    int reused;
} tb_resp;

enum { TB_ERR_URL = -1, TB_ERR_DNS = -2, TB_ERR_CONNECT = -3, TB_ERR_TLS = -4, TB_ERR_IO = -5,
       TB_ERR_PROTO = -6, TB_ERR_CANCEL = -7, TB_ERR_MEM = -8, TB_ERR_GZIP = -9 };

/* ca_file: PEM bundle of trusted roots. Call once before any request. 0 = ok. */
int tb_http_init(const char *ca_file);
int tb_http(const tb_req *req, tb_resp *resp);   /* returns resp->status */
void tb_resp_free(tb_resp *r);
void tb_http_close_idle(void);                  /* drop pooled connections (memory warning, background) */
void tb_http_drop_idle(void);                   /* same, without the TLS goodbye: at a return (sockets may be dead) */
const char *tb_http_strerror(int code);
double tb_now_ms(void);
/* Log line to stderr and the system log (the iPad's syslog shows it; stderr does not reach it on iOS 6). */
void tb_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

/* Counters for tests and the self-test report. */
typedef struct { long requests, handshakes, reused, bytes_in; double handshake_ms_total; } tb_http_stats;
void tb_http_get_stats(tb_http_stats *out);
#endif
