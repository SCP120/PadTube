#include "tb_stream.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tb_http.h"
#include "tb_mp4.h"

/* Remuxed segments kept in RAM: research §10.2 budget "<= 4 segments (<= 3.5 MB at 720p)". */
#define SEG_CACHE 4
/* First read of an audio fragment: holds the moof of a 10 s AAC fragment (about 470 samples x 8 B = 3.8 KB, MEASURED trun). */
#define AUDIO_HEAD 8192

typedef struct {
    tb_stream_fmt f;
    int ready;
    tb_track track;
    tb_sidx sidx;
} variant;

typedef struct {
    int idx;            /* audio fragment index, -1 = empty */
    uint8_t *buf;
    size_t have, cap;
    tb_frag frag;
    int parsed;
} audio_frag;

typedef struct { int vi, seg; tb_out ts; unsigned long use; } cached;

struct tb_stream {
    pthread_mutex_t mu;            /* builds: one download at a time (research §4.5); held during downloads */
    pthread_mutex_t smu;           /* short state lock: refs and prefetch flags. The main thread takes only this one
                                    * (a main-thread wait on mu lasted 100-930 ms on the iPad, 2026-11-11) */
    variant *v;
    int nv;
    variant a;
    audio_frag af[2];
    cached cache[SEG_CACHE];
    unsigned long tick;
    volatile int cancel;
    int prefetch_running, refs, pf_vi, pf_seg;
    int want, want_vi;             /* smu: a warm-up asked for while a prefetch ran (a seek target): built next */
    struct { volatile int *stop; double t0; } fl[4];  /* smu: downloads running now (build + audio helper) */
    double want_at;
    volatile int dead;             /* owner freed it: no new downloads */
    tb_stream_stats st;
};

static char *dupstr(const char *s) { return s ? strdup(s) : NULL; }

tb_stream *tb_stream_new(const tb_stream_fmt *videos, int nv, const tb_stream_fmt *audio) {
    tb_stream *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    pthread_mutex_init(&s->mu, NULL);
    pthread_mutex_init(&s->smu, NULL);
    s->v = calloc((size_t)(nv ? nv : 1), sizeof *s->v);
    s->nv = nv;
    for (int i = 0; i < nv; i++) { s->v[i].f = videos[i]; s->v[i].f.url = dupstr(videos[i].url); }
    s->a.f = *audio;
    s->a.f.url = dupstr(audio->url);
    for (int i = 0; i < 2; i++) s->af[i].idx = -1;
    for (int i = 0; i < SEG_CACHE; i++) s->cache[i].vi = -9;
    s->refs = 1;
    return s;
}

static void really_free(tb_stream *s) {
    for (int i = 0; i < s->nv; i++) { free(s->v[i].f.url); tb_sidx_free(&s->v[i].sidx); }
    free(s->v);
    free(s->a.f.url);
    tb_sidx_free(&s->a.sidx);
    for (int i = 0; i < 2; i++) { free(s->af[i].buf); tb_frag_free(&s->af[i].frag); }
    for (int i = 0; i < SEG_CACHE; i++) tb_out_free(&s->cache[i].ts);
    pthread_mutex_destroy(&s->mu);
    pthread_mutex_destroy(&s->smu);
    free(s);
}

static void unref(tb_stream *s) {
    pthread_mutex_lock(&s->smu);
    int left = --s->refs;
    pthread_mutex_unlock(&s->smu);
    if (left == 0) really_free(s);
}

void tb_stream_free(tb_stream *s) {
    if (!s) return;
    s->dead = 1;
    tb_stream_cancel(s);   /* also the running downloads (each has its own stop flag) */
    unref(s);
}

void tb_stream_retain(tb_stream *s) {
    pthread_mutex_lock(&s->smu);
    s->refs++;
    pthread_mutex_unlock(&s->smu);
}
void tb_stream_release(tb_stream *s) { unref(s); }

void tb_stream_cancel(tb_stream *s) {
    pthread_mutex_lock(&s->smu);
    s->cancel = 1;
    for (int i = 0; i < 4; i++) if (s->fl[i].stop) *s->fl[i].stop = 1;
    pthread_mutex_unlock(&s->smu);
}

void tb_stream_abort_before(tb_stream *s, double t) {
    pthread_mutex_lock(&s->smu);
    for (int i = 0; i < 4; i++) if (s->fl[i].stop && s->fl[i].t0 < t) *s->fl[i].stop = 1;
    pthread_mutex_unlock(&s->smu);
}
int tb_stream_nvideo(const tb_stream *s) { return s->nv; }
const tb_stream_fmt *tb_stream_video(const tb_stream *s, int vi) { return vi >= 0 && vi < s->nv ? &s->v[vi].f : NULL; }
void tb_stream_get_stats(tb_stream *s, tb_stream_stats *out) {
    /* no lock: builders write these counters under mu, which can be held for a whole download; a torn read of a
     * counter is harmless (reports and logs only) */
    memcpy(out, (const void *)&s->st, sizeof *out);
}

static int fetch(tb_stream *s, const char *url, int64_t a, int64_t b, tb_resp *r) {
    /* own stop flag: tb_stream_cancel stops every download, tb_stream_abort_before only the old ones */
    volatile int stop = 0;
    double t0 = tb_now_ms();
    int slot = -1;
    pthread_mutex_lock(&s->smu);
    stop = s->cancel;
    for (int i = 0; i < 4 && slot < 0; i++) if (!s->fl[i].stop) { slot = i; s->fl[i].stop = &stop; s->fl[i].t0 = t0; }
    pthread_mutex_unlock(&s->smu);
    tb_req q = {.url = url, .range_start = a, .range_end = b, .cancel = &stop, .timeout_ms = 20000};
    int st = tb_http(&q, r);
    pthread_mutex_lock(&s->smu);
    if (slot >= 0) s->fl[slot].stop = NULL;
    pthread_mutex_unlock(&s->smu);
    s->st.last_fetch_ms = tb_now_ms() - t0;
    s->st.last_status = st;
    tb_log("tb_stream: fetch %s %lld-%lld: %d, %zu B, %.0f ms (connect %.0f ms%s)", strstr(url, "itag=140") || strstr(url, "itag%3D140") || strstr(url, "/itag/140") ? "audio" : "video",
           (long long)a, (long long)b, st, r->len, tb_now_ms() - t0, r->ms_connect, r->reused ? ", reused" : "");
    if (st == 200 || st == 206) { s->st.bytes_fetched += (long)r->len; return 0; }
    tb_resp_free(r);
    return st < 0 ? st : -1000 - st;
}

/* Init segment + sidx of one variant, once. Called with mu held. */
static int prepare(tb_stream *s, variant *v) {
    if (v->ready) return 0;
    tb_resp r;
    int e = fetch(s, v->f.url, 0, v->f.index_end, &r);
    if (e) return e;
    e = tb_mp4_init((uint8_t *)r.body, r.len, &v->track);
    if (!e) e = tb_mp4_sidx((uint8_t *)r.body, r.len, 0, &v->sidx);
    tb_resp_free(&r);
    if (e) return -2000 + e;
    v->ready = 1;
    return 0;
}

static variant *var(tb_stream *s, int vi) { return vi < 0 ? &s->a : vi < s->nv ? &s->v[vi] : NULL; }

int tb_stream_playlist(tb_stream *s, int vi, char **out) {
    *out = NULL;
    variant *v = var(s, vi);
    if (!v) return -1;
    pthread_mutex_lock(&s->mu);
    if (s->dead) { pthread_mutex_unlock(&s->mu); return -1; }
    s->cancel = 0;
    int e = prepare(s, v);
    if (!e && vi >= 0) e = prepare(s, &s->a);
    if (e) { pthread_mutex_unlock(&s->mu); return e; }
    size_t cap = 256 + (size_t)v->sidx.n * 48, n = 0;
    char *p = malloc(cap);
    double maxd = 0;
    for (int i = 0; i < v->sidx.n; i++) {
        double d = (double)v->sidx.segs[i].duration / v->sidx.timescale;
        if (d > maxd) maxd = d;
    }
    n += (size_t)snprintf(p + n, cap - n, "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n",
                          (int)(maxd + 0.999));
    for (int i = 0; i < v->sidx.n; i++)
        n += (size_t)snprintf(p + n, cap - n, "#EXTINF:%.3f,\n%d/%d.ts\n", (double)v->sidx.segs[i].duration / v->sidx.timescale, vi, i);
    snprintf(p + n, cap - n, "#EXT-X-ENDLIST\n");
    pthread_mutex_unlock(&s->mu);
    *out = p;
    return 0;
}

int tb_stream_master(tb_stream *s, const int *order, int n, char **out) {
    size_t cap = 128 + (size_t)n * 160, len = 0;
    char *p = malloc(cap);
    len += (size_t)snprintf(p, cap, "#EXTM3U\n");
    for (int i = 0; i < n; i++) {
        const tb_stream_fmt *f = tb_stream_video(s, order[i]);
        if (!f) continue;
        len += (size_t)snprintf(p + len, cap - len, "#EXT-X-STREAM-INF:BANDWIDTH=%d,RESOLUTION=%dx%d\n%d.m3u8\n",
                                f->bitrate + s->a.f.bitrate, f->width, f->height, order[i]);
    }
    *out = p;
    return 0;
}

/* Make sure audio fragment j holds every byte up to `need` (relative to the fragment). Called with mu held. */
static audio_frag *audio_get(tb_stream *s, int j, uint32_t need_hint) {
    audio_frag *f = NULL;
    for (int i = 0; i < 2; i++) if (s->af[i].idx == j) f = &s->af[i];
    if (!f) { /* evict the slot with the lower index (playback goes forward) */
        f = s->af[0].idx < s->af[1].idx ? &s->af[0] : &s->af[1];
        free(f->buf);
        tb_frag_free(&f->frag);
        memset(f, 0, sizeof *f);
        f->idx = j;
    }
    tb_seg *g = &s->a.sidx.segs[j];
    if (!f->parsed) {
        uint32_t want = g->size < AUDIO_HEAD ? g->size : AUDIO_HEAD;
        tb_resp r;
        if (fetch(s, s->a.f.url, g->offset, g->offset + want - 1, &r)) { f->idx = -1; return NULL; }
        f->cap = g->size;
        f->buf = malloc(f->cap);
        memcpy(f->buf, r.body, r.len);
        f->have = r.len;
        tb_resp_free(&r);
        uint32_t moof = tb_mp4_moof_size(f->buf, f->have);
        if (moof == 0 || moof > g->size) { f->idx = -1; return NULL; }
        if (moof > f->have) {
            if (fetch(s, s->a.f.url, g->offset + (int64_t)f->have, g->offset + moof - 1, &r)) { f->idx = -1; return NULL; }
            memcpy(f->buf + f->have, r.body, r.len);
            f->have += r.len;
            tb_resp_free(&r);
        }
        if (tb_mp4_frag(f->buf, f->have, &s->a.track, &f->frag)) { f->idx = -1; return NULL; }
        f->parsed = 1;
    }
    if (need_hint > g->size) need_hint = g->size;
    if (need_hint > f->have) {
        tb_resp r;
        if (fetch(s, s->a.f.url, g->offset + (int64_t)f->have, g->offset + need_hint - 1, &r)) return NULL;
        size_t k = r.len <= f->cap - f->have ? r.len : f->cap - f->have;
        memcpy(f->buf + f->have, r.body, k);
        f->have += k;
        tb_resp_free(&r);
    }
    return f;
}

/* Build segment seg of variant vi (vi = -1: audio fragment seg alone). Called with mu held. */
static int build(tb_stream *s, int vi, int seg, tb_out *out) {
    variant *v = var(s, vi);
    int e = prepare(s, v);
    if (!e && vi >= 0) e = prepare(s, &s->a);
    if (e) return e;
    if (seg < 0 || seg >= v->sidx.n) return -404;
    double t0 = tb_now_ms();
    double fetch_ms = 0;
    tb_ts_input vin = {0}, ain = {0};
    tb_resp vr = {0};
    tb_frag vf = {0};
    tb_sample *as = NULL;
    uint8_t *abuf = NULL;
    int rc = 0;
    double seg_t0, seg_t1;
    if (vi >= 0) {
        tb_seg *g = &v->sidx.segs[seg];
        double tf = tb_now_ms();
        if ((rc = fetch(s, v->f.url, g->offset, g->offset + g->size - 1, &vr))) return rc;
        fetch_ms += tb_now_ms() - tf;
        if (tb_mp4_frag((uint8_t *)vr.body, vr.len, &v->track, &vf)) { tb_resp_free(&vr); return -3000; }
        vin = (tb_ts_input){&v->track, (uint8_t *)vr.body, vr.len, vf.s, vf.n};
        /* Segment 0 starts at -inf: the sidx start is a presentation time (B-frame delay, 2 frames in the
         * fixture), and audio frames before it would otherwise fall into no segment. */
        seg_t0 = seg == 0 ? -1e30 : (double)g->start / v->sidx.timescale;
        seg_t1 = seg + 1 < v->sidx.n ? (double)v->sidx.segs[seg + 1].start / v->sidx.timescale : 1e30;
    } else {
        seg_t0 = (double)s->a.sidx.segs[seg].start / s->a.sidx.timescale;
        seg_t1 = seg + 1 < s->a.sidx.n ? (double)s->a.sidx.segs[seg + 1].start / s->a.sidx.timescale : 1e30;
    }
    /* Audio samples with dts in [seg_t0, seg_t1), copied into one buffer so the TS writer sees one input. */
    uint32_t ats = s->a.sidx.timescale;
    int an = 0, acap = 0;
    size_t alen = 0, abcap = 0;
    for (int j = 0; j < s->a.sidx.n && !rc; j++) {
        tb_seg *g = &s->a.sidx.segs[j];
        double ft0 = (double)g->start / ats, ft1 = (double)(g->start + g->duration) / ats;
        if (ft1 <= seg_t0 || ft0 >= seg_t1) continue;
        double tf = tb_now_ms();
        audio_frag *f = audio_get(s, j, 0);
        if (!f) { rc = -4000; break; }
        /* bytes needed: up to the end of the last sample before seg_t1 */
        uint32_t need = 0;
        for (int k = 0; k < f->frag.n; k++) {
            double t = (double)f->frag.s[k].dts / s->a.track.timescale;
            if (t >= seg_t1) break;
            uint32_t end = f->frag.s[k].offset + f->frag.s[k].size;
            if (end > need) need = end;
        }
        if (need > f->have && !audio_get(s, j, need)) { rc = -4001; break; }
        fetch_ms += tb_now_ms() - tf;
        for (int k = 0; k < f->frag.n; k++) {
            tb_sample *x = &f->frag.s[k];
            double t = (double)x->dts / s->a.track.timescale;
            if (t < seg_t0 || t >= seg_t1) continue;
            if (an == acap) { acap = acap ? acap * 2 : 512; as = realloc(as, (size_t)acap * sizeof *as); }
            if (alen + x->size > abcap) { abcap = (alen + x->size) * 2; abuf = realloc(abuf, abcap); }
            memcpy(abuf + alen, f->buf + x->offset, x->size);
            as[an] = *x;
            as[an].offset = (uint32_t)alen;
            alen += x->size;
            an++;
        }
    }
    if (!rc) {
        ain = (tb_ts_input){&s->a.track, abuf, alen, as, an};
        double tr = tb_now_ms();
        out->len = 0;
        rc = tb_ts_segment(out, vi >= 0 ? &vin : NULL, &ain);
        double rm = tb_now_ms() - tr;
        s->st.last_remux_ms = rm;
        s->st.remux_ms_total += rm;
        s->st.media_s_total += (double)v->sidx.segs[seg].duration / v->sidx.timescale;
    }
    free(as);
    free(abuf);
    tb_frag_free(&vf);
    tb_resp_free(&vr);
    s->st.last_fetch_ms = fetch_ms;
    s->st.last_build_ms = tb_now_ms() - t0;
    if (!rc) s->st.segments_built++;
    tb_log("tb_stream: seg %d/%d built in %.0f ms (fetch %.0f ms, %ld B so far)", vi, seg, s->st.last_build_ms, fetch_ms, s->st.bytes_fetched);
    return rc;
}

static cached *cache_find(tb_stream *s, int vi, int seg) {
    for (int i = 0; i < SEG_CACHE; i++) if (s->cache[i].vi == vi && s->cache[i].seg == seg) return &s->cache[i];
    return NULL;
}

static cached *cache_slot(tb_stream *s) {
    cached *c = &s->cache[0];
    for (int i = 1; i < SEG_CACHE; i++) if (s->cache[i].use < c->use) c = &s->cache[i];
    return c;
}

/* Called with mu held. Returns the cache entry for (vi, seg). */
static cached *get_locked(tb_stream *s, int vi, int seg, int *err) {
    cached *c = cache_find(s, vi, seg);
    if (c) { c->use = ++s->tick; s->st.cache_hits++; return c; }
    c = cache_slot(s);
    c->vi = -9;
    *err = build(s, vi, seg, &c->ts);
    if (*err) return NULL;
    c->vi = vi;
    c->seg = seg;
    c->use = ++s->tick;
    return c;
}

int tb_stream_segment(tb_stream *s, int vi, int seg, tb_out *out) {
    /* A seek: stop a prefetch of another segment so this request does not wait for its download. */
    /* pf_seg -1: a warm-up still reading the index; it builds what the player asks for next, so let it run */
    if (s->prefetch_running && s->pf_seg >= 0 && (s->pf_vi != vi || s->pf_seg != seg)) tb_stream_cancel(s);
    pthread_mutex_lock(&s->mu);
    if (s->dead) { pthread_mutex_unlock(&s->mu); return -1; }
    s->cancel = 0;
    int err = 0;
    cached *c = get_locked(s, vi, seg, &err);
    if (c) {
        out->len = 0;
        if (!out->p || out->cap < c->ts.len) { free(out->p); out->p = malloc(c->ts.len); out->cap = c->ts.len; }
        memcpy(out->p, c->ts.p, c->ts.len);
        out->len = c->ts.len;
    }
    pthread_mutex_unlock(&s->mu);
    return err;
}

typedef struct { tb_stream *s; int vi, seg; double at; } pf_arg;
static void *prepare_audio_main(void *p) {
    tb_stream *s = p;
    return (void *)(intptr_t)prepare(s, &s->a);
}
static void *prefetch_main(void *p) {
    pf_arg *a = p;
again:
    pthread_mutex_lock(&a->s->mu);
    int err = 0;
    variant *v = var(a->s, a->vi);
    if (a->seg < 0 && v && !a->s->cancel) { /* warm: index first, then the segment that holds time `at` */
        /* video and audio index at the same time: on a cold googlevideo host each one waits about 0.5 s for its
         * first byte (MEASURED on the iPad 2026-11-11). The helper touches only the audio variant; mu is held. */
        pthread_t ht;
        int herr = 0, helper = a->vi >= 0 && !a->s->a.ready && pthread_create(&ht, NULL, prepare_audio_main, a->s) == 0;
        err = prepare(a->s, v);
        if (helper) { void *r; pthread_join(ht, &r); herr = (int)(intptr_t)r; }
        if (!err && a->vi >= 0) err = herr ? herr : prepare(a->s, &a->s->a);
        a->seg = 0;
        for (int i = 0; !err && i < v->sidx.n; i++)
            if ((double)v->sidx.segs[i].start / v->sidx.timescale <= a->at) a->seg = i;
        a->s->pf_seg = a->seg;
    }
    if (!err && !a->s->cancel && v && v->ready && a->seg < v->sidx.n) get_locked(a->s, a->vi, a->seg, &err);
    pthread_mutex_unlock(&a->s->mu);
    pthread_mutex_lock(&a->s->smu);
    if (a->s->want && !a->s->dead) {   /* a warm-up came in meanwhile: build its segment now */
        a->s->want = 0;
        a->s->cancel = 0;              /* the download it stopped has ended */
        *a = (pf_arg){a->s, a->s->want_vi, -1, a->s->want_at};
        a->s->pf_vi = a->vi; a->s->pf_seg = -1;
        pthread_mutex_unlock(&a->s->smu);
        goto again;
    }
    a->s->prefetch_running = 0;
    pthread_mutex_unlock(&a->s->smu);
    unref(a->s);
    free(a);
    return NULL;
}

static void start_prefetch(tb_stream *s, int vi, int seg, double at);
void tb_stream_prefetch(tb_stream *s, int vi, int seg) { start_prefetch(s, vi, seg, 0); }
void tb_stream_warm(tb_stream *s, int vi, double at) {
    /* a running prefetch (the next segment) used to make this a no-op: the seek target was then built only when
     * the player asked for it, while the player held its own lock (seek stalls 30-100 ms on the main thread) */
    pthread_mutex_lock(&s->smu);
    int busy = s->prefetch_running && !s->dead;
    int stop_prefetch = busy && s->pf_seg >= 0;   /* a next-segment prefetch: the seek target comes first */
    if (busy) { s->want = 1; s->want_vi = vi; s->want_at = at; }   /* a set cancel still stops the running one */
    else s->cancel = 0;                                            /* nothing runs: an old cancel must not stop this */
    pthread_mutex_unlock(&s->smu);
    /* waiting for that download made a backward seek 1-2.5 s slower (device run 2026-11-12) */
    if (stop_prefetch) tb_stream_cancel(s);
    if (!busy) start_prefetch(s, vi, -1, at);
}

int tb_stream_ready(tb_stream *s, int vi, double at) {
    if (pthread_mutex_trylock(&s->mu) != 0) return 0;   /* a build runs: not ready yet (never wait here) */
    variant *v = var(s, vi);
    int ok = 0;
    if (v && v->ready && v->sidx.n > 0) {
        int seg = 0;
        for (int i = 0; i < v->sidx.n; i++) if ((double)v->sidx.segs[i].start / v->sidx.timescale <= at) seg = i;
        ok = cache_find(s, vi, seg) != NULL;
    }
    pthread_mutex_unlock(&s->mu);
    return ok;
}

double tb_stream_seg_start(tb_stream *s, int vi, int seg) {
    pthread_mutex_lock(&s->mu);
    variant *v = var(s, vi);
    double t = -1;
    if (v && v->ready && seg >= 0 && seg < v->sidx.n) t = seg == 0 ? 0 : (double)v->sidx.segs[seg].start / v->sidx.timescale;
    pthread_mutex_unlock(&s->mu);
    return t;
}

static void start_prefetch(tb_stream *s, int vi, int seg, double at) {
    /* smu only: this runs on the main thread (warm-up at a start); a segment already in the cache is found by
     * the prefetch thread itself (get_locked) */
    pthread_mutex_lock(&s->smu);
    int skip = s->prefetch_running || s->dead;
    if (!skip) { s->prefetch_running = 1; s->refs++; s->pf_vi = vi; s->pf_seg = seg; }
    pthread_mutex_unlock(&s->smu);
    if (skip) return;
    pf_arg *a = malloc(sizeof *a);
    *a = (pf_arg){s, vi, seg, at};
    pthread_t t;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &attr, prefetch_main, a) != 0) {
        pthread_mutex_lock(&s->smu); s->prefetch_running = 0; s->refs--; pthread_mutex_unlock(&s->smu);
        free(a);
    }
    pthread_attr_destroy(&attr);
}
