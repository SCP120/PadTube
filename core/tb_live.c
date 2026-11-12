#include "tb_live.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tb_http.h"

/* Segments in the local live playlist: 6 x 5 s = 30 s behind the edge at most; the player starts 3 from the end. */
#define LIVE_WINDOW 6
#define MAP_N 64
#define AAC_PER_PES 8

typedef struct { long sq; double dur; char *vurl, *aurl; } seg_t;

struct tb_live {
    pthread_mutex_t mu;
    int refs, max_height, height;
    char *master, *vpl, *apl;   /* URLs */
    seg_t map[MAP_N];
    int nmap;
    double target;
};

static int be16(const uint8_t *p) { return p[0] << 8 | p[1]; }

/* ---------- pure parts ---------- */

int64_t tb_id3_timestamp(const uint8_t *p, size_t n, size_t *id3_len) {
    *id3_len = 0;
    if (n < 10 || memcmp(p, "ID3", 3)) return -1;
    size_t sz = (size_t)(p[6] & 0x7f) << 21 | (size_t)(p[7] & 0x7f) << 14 | (size_t)(p[8] & 0x7f) << 7 | (p[9] & 0x7f);
    *id3_len = 10 + sz;
    static const char key[] = "com.apple.streaming.transportStreamTimestamp";
    for (size_t i = 10; i + sizeof key + 8 <= n && i < 10 + sz; i++)
        if (!memcmp(p + i, key, sizeof key)) { /* key includes its NUL */
            const uint8_t *t = p + i + sizeof key;
            uint64_t v = 0;
            for (int k = 0; k < 8; k++) v = v << 8 | t[k];
            return (int64_t)(v & 0x1ffffffffULL);
        }
    return -1;
}

static const int k_rates[] = {96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350};

int tb_live_merge(const uint8_t *ts, size_t n, const uint8_t *adts, size_t alen, int64_t apts, tb_out *out) {
    if (n < 188 || ts[0] != 0x47) return -1;
    /* PAT -> PMT PID -> video PID, PCR PID */
    int pmt = -1, vpid = -1, pcr = -1;
    for (size_t o = 0; o + 188 <= n && (pmt < 0 || vpid < 0); o += 188) {
        const uint8_t *k = ts + o;
        int pid = (k[1] & 0x1f) << 8 | k[2];
        if (!(k[1] & 0x40)) continue;
        size_t q = 4;
        if (k[3] & 0x20) q += 1 + k[4];
        if (q >= 188) continue;
        q += 1 + k[q]; /* pointer field */
        if (pid == 0 && q + 12 <= 188) pmt = (k[q + 10] & 0x1f) << 8 | k[q + 11];
        else if (pid == pmt && q + 12 <= 188) {
            int seclen = (k[q + 1] & 0x0f) << 8 | k[q + 2];
            pcr = (k[q + 8] & 0x1f) << 8 | k[q + 9];
            int pil = (k[q + 10] & 0x0f) << 8 | k[q + 11];
            size_t e = q + 3 + (size_t)seclen - 4, s = q + 12 + (size_t)pil;
            while (s + 5 <= e && s + 5 <= 188) {
                int type = k[s], spid = (k[s + 1] & 0x1f) << 8 | k[s + 2], il = (k[s + 3] & 0x0f) << 8 | k[s + 4];
                if (type == 0x1b && vpid < 0) vpid = spid;
                s += 5 + (size_t)il;
            }
        }
    }
    if (vpid < 0) return -2;
    int apid = vpid == 0x101 ? 0x102 : 0x101;
    /* ADTS frames -> PES groups */
    typedef struct { size_t off, len; int64_t pts; } grp;
    grp g[512];
    int ng = 0, frames = 0, rate = 44100;
    size_t o = 0, gstart = 0;
    while (o + 7 <= alen && ng < 512) {
        if (adts[o] != 0xff || (adts[o + 1] & 0xf0) != 0xf0) { o++; continue; }
        int fi = (adts[o + 2] >> 2) & 15;
        if (fi < 13) rate = k_rates[fi];
        size_t flen = (size_t)((adts[o + 3] & 3) << 11 | adts[o + 4] << 3 | adts[o + 5] >> 5);
        if (flen < 7 || o + flen > alen) break;
        if (frames % AAC_PER_PES == 0) { gstart = o; g[ng].off = o; g[ng].pts = apts + (int64_t)frames * 1024 * 90000 / rate; g[ng].len = 0; ng++; }
        g[ng - 1].len = o + flen - gstart;
        frames++;
        o += flen;
    }
    if (tb_ts_tables(out, vpid, ng ? apid : 0, pcr > 0 ? pcr : vpid)) return -1;
    int cca = 0, gi = 0;
    for (size_t p = 0; p + 188 <= n; p += 188) {
        const uint8_t *k = ts + p;
        int pid = (k[1] & 0x1f) << 8 | k[2];
        if (pid == 0 || pid == pmt || pid == 0x1fff) continue;
        if (pid != vpid && pid != pcr) continue;
        if (pid == vpid && (k[1] & 0x40)) { /* PES start: put audio that comes before this video PTS */
            size_t q = 4;
            if (k[3] & 0x20) q += 1 + k[4];
            if (q + 14 <= 188 && k[q] == 0 && k[q + 1] == 0 && k[q + 2] == 1 && (k[q + 7] & 0x80)) {
                const uint8_t *t = k + q + 9;
                int64_t vpts = (int64_t)(t[0] & 0x0e) << 29 | t[1] << 22 | (t[2] & 0xfe) << 14 | t[3] << 7 | t[4] >> 1;
                while (gi < ng && g[gi].pts <= vpts) {
                    if (tb_ts_pes(out, apid, &cca, 0xc0, (uint64_t)g[gi].pts, -1, -1, 0, adts + g[gi].off, g[gi].len)) return -1;
                    gi++;
                }
            }
        }
        size_t before = out->len;
        if (out->len + 188 > out->cap) {
            size_t cap = out->cap ? out->cap * 2 : 65536;
            uint8_t *np = realloc(out->p, cap);
            if (!np) return -1;
            out->p = np;
            out->cap = cap;
        }
        memcpy(out->p + before, k, 188);
        out->len += 188;
    }
    for (; gi < ng; gi++)
        if (tb_ts_pes(out, apid, &cca, 0xc0, (uint64_t)g[gi].pts, -1, -1, 0, adts + g[gi].off, g[gi].len)) return -1;
    (void)be16;
    return 0;
}

/* ---------- playlists ---------- */

static char *get(const char *url, size_t *len) {
    tb_req q = {.url = url, .range_start = -1, .timeout_ms = 10000};
    tb_resp r;
    int st = tb_http(&q, &r);
    if (st != 200) { tb_resp_free(&r); return NULL; }
    if (len) *len = r.len;
    return r.body; /* caller frees */
}

static char *attr(const char *line, const char *key) { /* KEY=value or KEY="value" */
    const char *p = strstr(line, key);
    if (!p) return NULL;
    p += strlen(key);
    if (*p == '"') {
        const char *e = strchr(p + 1, '"');
        return e ? strndup(p + 1, (size_t)(e - p - 1)) : NULL;
    }
    size_t l = strcspn(p, ",\r\n");
    return strndup(p, l);
}

/* Choose the variant (highest height <= max, AAC-LC) and its audio rendition from the master playlist. */
static int pick(tb_live *l) {
    size_t n;
    char *m = get(l->master, &n);
    if (!m) return -1;
    int best = -1;
    char *best_url = NULL, *best_group = NULL;
    char *save = NULL;
    char *lines = strdup(m);
    char *prev = NULL;
    for (char *ln = strtok_r(lines, "\n", &save); ln; ln = strtok_r(NULL, "\n", &save)) {
        if (prev && !strncmp(prev, "#EXT-X-STREAM-INF:", 18) && ln[0] != '#') {
            char *res = attr(prev, "RESOLUTION="), *codecs = attr(prev, "CODECS="), *group = attr(prev, "AUDIO=");
            int w = 0, h = 0;
            if (res) sscanf(res, "%dx%d", &w, &h);
            int ok = codecs && strstr(codecs, "mp4a.40.2") && strstr(codecs, "avc1") && h <= l->max_height && h > best;
            if (ok) { best = h; free(best_url); free(best_group); best_url = strdup(ln); best_group = group ? strdup(group) : NULL; }
            free(res); free(codecs); free(group);
        }
        prev = ln;
    }
    /* the audio rendition of that group */
    char *aurl = NULL;
    if (best_group) {
        char want[64];
        snprintf(want, sizeof want, "GROUP-ID=\"%s\"", best_group);
        free(lines);
        lines = strdup(m);
        for (char *ln = strtok_r(lines, "\n", &save); ln; ln = strtok_r(NULL, "\n", &save))
            if (!strncmp(ln, "#EXT-X-MEDIA:", 13) && strstr(ln, "TYPE=AUDIO") && strstr(ln, want)) { aurl = attr(ln, "URI="); break; }
    }
    free(lines);
    free(m);
    free(best_group);
    if (!best_url || !aurl) { free(best_url); free(aurl); return -2; }
    l->vpl = best_url;
    l->apl = aurl;
    l->height = best;
    return 0;
}

tb_live *tb_live_new(const char *master_url, int max_height) {
    tb_live *l = calloc(1, sizeof *l);
    pthread_mutex_init(&l->mu, NULL);
    l->refs = 1;
    l->master = strdup(master_url);
    l->max_height = max_height;
    return l;
}

void tb_live_retain(tb_live *l) { pthread_mutex_lock(&l->mu); l->refs++; pthread_mutex_unlock(&l->mu); }
void tb_live_release(tb_live *l) {
    pthread_mutex_lock(&l->mu);
    int left = --l->refs;
    pthread_mutex_unlock(&l->mu);
    if (left) return;
    for (int i = 0; i < l->nmap; i++) { free(l->map[i].vurl); free(l->map[i].aurl); }
    free(l->master); free(l->vpl); free(l->apl);
    pthread_mutex_destroy(&l->mu);
    free(l);
}
void tb_live_free(tb_live *l) { if (l) tb_live_release(l); }
int tb_live_height(tb_live *l) { return l->height; }

/* media playlist -> (sq, dur, url) list; returns count, fills arrays up to cap (the last `cap` entries) */
static int parse_media(char *text, long *sq, double *dur, char **url, int cap, double *target) {
    long seq = 0;
    double d = 0;
    int n = 0, total = 0;
    long *asq = calloc(4096, sizeof *asq);
    double *adur = calloc(4096, sizeof *adur);
    char **aurl = calloc(4096, sizeof *aurl);
    char *save = NULL;
    for (char *ln = strtok_r(text, "\n", &save); ln; ln = strtok_r(NULL, "\n", &save)) {
        ln[strcspn(ln, "\r")] = 0;
        if (!strncmp(ln, "#EXT-X-MEDIA-SEQUENCE:", 22)) seq = atol(ln + 22);
        else if (!strncmp(ln, "#EXT-X-TARGETDURATION:", 22)) *target = atof(ln + 22);
        else if (!strncmp(ln, "#EXTINF:", 8)) d = atof(ln + 8);
        else if (ln[0] && ln[0] != '#' && total < 4096) {
            asq[total] = seq++;
            adur[total] = d;
            aurl[total] = ln;
            total++;
        }
    }
    int first = total > cap ? total - cap : 0;
    for (int i = first; i < total; i++, n++) { sq[n] = asq[i]; dur[n] = adur[i]; url[n] = strdup(aurl[i]); }
    free(asq); free(adur); free(aurl);
    return n;
}

int tb_live_playlist(tb_live *l, char **out) {
    *out = NULL;
    pthread_mutex_lock(&l->mu);
    if (!l->vpl && pick(l)) { pthread_mutex_unlock(&l->mu); return -1; }
    char *vurl = strdup(l->vpl), *aurl = strdup(l->apl);
    pthread_mutex_unlock(&l->mu);
    char *vt = get(vurl, NULL), *at = get(aurl, NULL);
    free(vurl);
    free(aurl);
    if (!vt || !at) { free(vt); free(at); return -2; }
    long vs[LIVE_WINDOW], as[LIVE_WINDOW + 4];
    double vd[LIVE_WINDOW], ad[LIVE_WINDOW + 4], target = 5;
    char *vu[LIVE_WINDOW], *au[LIVE_WINDOW + 4];
    int nv = parse_media(vt, vs, vd, vu, LIVE_WINDOW, &target);
    int na = parse_media(at, as, ad, au, LIVE_WINDOW + 4, &target);
    free(vt);
    free(at);
    size_t cap = 512 + (size_t)nv * 64, len = 0;
    char *p = malloc(cap);
    pthread_mutex_lock(&l->mu);
    l->target = target;
    int written = 0;
    for (int i = 0; i < nv; i++) {
        int j = -1;
        for (int k = 0; k < na; k++) if (as[k] == vs[i]) j = k;
        if (j < 0) continue; /* audio not published yet for this segment */
        if (written == 0)
            len += (size_t)snprintf(p + len, cap - len, "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:%ld\n",
                                    (int)(target + 0.999), vs[i]);
        len += (size_t)snprintf(p + len, cap - len, "#EXTINF:%.3f,\nlive/%ld.ts\n", vd[i], vs[i]);
        written++;
        /* remember the URLs of this segment */
        seg_t *m = &l->map[l->nmap % MAP_N];
        int found = 0;
        for (int k = 0; k < MAP_N && k < l->nmap; k++) if (l->map[k].sq == vs[i]) found = 1;
        if (!found) {
            if (l->nmap >= MAP_N) { free(m->vurl); free(m->aurl); }
            m->sq = vs[i];
            m->dur = vd[i];
            m->vurl = strdup(vu[i]);
            m->aurl = strdup(au[j]);
            l->nmap++;
        }
    }
    pthread_mutex_unlock(&l->mu);
    for (int i = 0; i < nv; i++) free(vu[i]);
    for (int i = 0; i < na; i++) free(au[i]);
    if (!written) { free(p); return -3; }
    *out = p;
    return 0;
}

int tb_live_segment(tb_live *l, long sq, tb_out *out) {
    char *vurl = NULL, *aurl = NULL;
    pthread_mutex_lock(&l->mu);
    for (int k = 0; k < MAP_N && k < l->nmap; k++)
        if (l->map[k].sq == sq) { vurl = strdup(l->map[k].vurl); aurl = strdup(l->map[k].aurl); }
    pthread_mutex_unlock(&l->mu);
    if (!vurl) return -404;
    size_t vn = 0, an = 0;
    char *v = get(vurl, &vn), *a = get(aurl, &an);
    free(vurl);
    free(aurl);
    int rc = -1;
    if (v && a) {
        size_t id3 = 0;
        int64_t pts = tb_id3_timestamp((uint8_t *)a, an, &id3);
        out->len = 0;
        rc = pts < 0 ? -5 : tb_live_merge((uint8_t *)v, vn, (uint8_t *)a + id3, an - id3, pts, out);
    }
    free(v);
    free(a);
    return rc;
}
