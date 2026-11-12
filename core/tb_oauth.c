#include "tb_oauth.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tb_http.h"
#include "tb_json.h"

#define TV_UA "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version"
/* Opaline keeps en-US fixed for "OAuth device-flow fingerprint stability" (research-features §4.4). */
#define TV_HEADERS "User-Agent: " TV_UA "\r\nReferer: https://www.youtube.com/tv\r\nAccept-Language: en-US\r\n"

static char *dupn(const char *s, size_t n) {
    char *o = malloc(n + 1);
    memcpy(o, s, n);
    o[n] = 0;
    return o;
}

int tb_oauth_parse_client(const char *js, tb_oauth_client *out) {
    memset(out, 0, sizeof *out);
    /* regex of YouTube.js: clientId:"(?<id>[^"]+)",[^"]*?:"(?<secret>[^"]+)" */
    for (const char *p = strstr(js, "clientId:\""); p; p = strstr(p + 1, "clientId:\"")) {
        const char *id = p + 10, *e = strchr(id, '"');
        if (!e || e == id || e[1] != ',') continue;
        const char *q = e + 2;
        while (*q && *q != '"') q++;
        if (*q != '"' || q[-1] != ':') continue;
        const char *sec = q + 1, *se = strchr(sec, '"');
        if (!se || se == sec) continue;
        out->client_id = dupn(id, (size_t)(e - id));
        out->client_secret = dupn(sec, (size_t)(se - sec));
        return 0;
    }
    return -1;
}

int tb_oauth_get_client(tb_oauth_client *out) {
    memset(out, 0, sizeof *out);
    tb_req q = {.url = "https://www.youtube.com/tv", .headers = TV_HEADERS, .range_start = -1};
    tb_resp r;
    int st = tb_http(&q, &r);
    if (st != 200) { tb_resp_free(&r); return st < 0 ? st : -st; }
    static const char tag[] = "<script id=\"base-js\" src=\"";
    const char *p = strstr(r.body, tag);
    if (!p) { tb_resp_free(&r); return -1; }
    p += sizeof tag - 1;
    const char *e = strchr(p, '"');
    char url[1024];
    snprintf(url, sizeof url, "https://www.youtube.com%.*s", (int)(e - p), p);
    tb_resp_free(&r);
    q.url = url;
    st = tb_http(&q, &r);
    if (st != 200) { tb_resp_free(&r); return st < 0 ? st : -st; }
    int rc = tb_oauth_parse_client(r.body, out);
    tb_resp_free(&r);
    return rc;
}

static int post_json(const char *url, const char *body, yyjson_doc **doc, int *status) {
    tb_req q = {.method = "POST", .url = url, .headers = "Content-Type: application/json\r\n" TV_HEADERS, .body = body,
                .body_len = strlen(body), .range_start = -1};
    tb_resp r;
    *status = tb_http(&q, &r);
    *doc = *status > 0 ? yyjson_read(r.body, r.len, 0) : NULL;
    tb_resp_free(&r);
    return *doc ? 0 : -1;
}

static void jstr(char *dst, size_t cap, const char *s) { /* JSON-escape a short ASCII value */
    size_t n = 0;
    for (; *s && n + 2 < cap; s++) {
        if (*s == '"' || *s == '\\') dst[n++] = '\\';
        dst[n++] = *s;
    }
    dst[n] = 0;
}

int tb_oauth_device_code(const tb_oauth_client *c, const char *device_id, tb_device_code *out) {
    memset(out, 0, sizeof *out);
    char id[256], dev[80], body[1024];
    jstr(id, sizeof id, c->client_id);
    jstr(dev, sizeof dev, device_id);
    snprintf(body, sizeof body,
             "{\"client_id\":\"%s\",\"scope\":\"http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content\","
             "\"device_id\":\"%s\",\"device_model\":\"ytlr::\"}", id, dev);
    yyjson_doc *d;
    int st;
    if (post_json("https://www.youtube.com/o/oauth2/device/code", body, &d, &st)) return st < 0 ? st : -1;
    yyjson_val *root = yyjson_doc_get_root(d);
    const char *uc = tbj_str(root, "user_code", NULL), *vu = tbj_str(root, "verification_url", NULL), *dc = tbj_str(root, "device_code", NULL);
    int rc = -1;
    if (uc && dc) {
        out->user_code = strdup(uc);
        out->verification_url = strdup(vu ? vu : "https://www.google.com/device");
        out->device_code = strdup(dc);
        out->interval = (int)tbj_int(root, "interval", NULL);
        if (out->interval <= 0) out->interval = 5;
        out->expires_in = (int)tbj_int(root, "expires_in", NULL);
        rc = 0;
    }
    yyjson_doc_free(d);
    return rc;
}

static int token_call(const char *body, tb_token *out) {
    memset(out, 0, sizeof *out);
    yyjson_doc *d;
    int st;
    if (post_json("https://www.youtube.com/o/oauth2/token", body, &d, &st)) return st < 0 ? st : -1;
    yyjson_val *root = yyjson_doc_get_root(d);
    /* the youtube.com proxy can answer errors with HTTP 200: read the body (research-features §4.4) */
    const char *err = tbj_str(root, "error", NULL), *at = tbj_str(root, "access_token", NULL);
    int rc;
    if (at) {
        out->access_token = strdup(at);
        const char *rt = tbj_str(root, "refresh_token", NULL);
        out->refresh_token = rt ? strdup(rt) : NULL;
        out->expires_in = (int)tbj_int(root, "expires_in", NULL);
        rc = 0;
    } else if (err && (!strcmp(err, "authorization_pending") || !strcmp(err, "slow_down"))) {
        rc = 1;
    } else {
        out->error = strdup(err ? err : "no token");
        rc = -2;
    }
    yyjson_doc_free(d);
    return rc;
}

int tb_oauth_poll(const tb_oauth_client *c, const char *device_code, tb_token *out) {
    char id[256], sec[128], dc[512], body[1400];
    jstr(id, sizeof id, c->client_id);
    jstr(sec, sizeof sec, c->client_secret);
    jstr(dc, sizeof dc, device_code);
    snprintf(body, sizeof body, "{\"client_id\":\"%s\",\"client_secret\":\"%s\",\"code\":\"%s\",\"grant_type\":\"http://oauth.net/grant_type/device/1.0\"}",
             id, sec, dc);
    return token_call(body, out);
}

int tb_oauth_refresh(const tb_oauth_client *c, const char *refresh_token, tb_token *out) {
    char id[256], sec[128], rt[600], body[1400];
    jstr(id, sizeof id, c->client_id);
    jstr(sec, sizeof sec, c->client_secret);
    jstr(rt, sizeof rt, refresh_token);
    snprintf(body, sizeof body, "{\"client_id\":\"%s\",\"client_secret\":\"%s\",\"refresh_token\":\"%s\",\"grant_type\":\"refresh_token\"}",
             id, sec, rt);
    return token_call(body, out);
}

void tb_oauth_client_free(tb_oauth_client *c) { free(c->client_id); free(c->client_secret); memset(c, 0, sizeof *c); }
void tb_device_code_free(tb_device_code *d) { free(d->user_code); free(d->verification_url); free(d->device_code); memset(d, 0, sizeof *d); }
void tb_token_free(tb_token *t) { free(t->access_token); free(t->refresh_token); free(t->error); memset(t, 0, sizeof *t); }
