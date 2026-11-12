/* MP4 reader, TS writer, segment builder and HLS server on synthetic fixtures (tests/host/make_fixtures.sh).
 * ffprobe / ffmpeg (Homebrew) are the independent judges of the TS and HLS output. */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include "tb_hls.h"
#include "tb_http.h"
#include "tb_mp4.h"
#include "tb_stream.h"
#include "tb_test.h"
#include "tb_ts.h"

#define FIX "build/fixtures"

static uint8_t *slurp(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *p = malloc((size_t)sz);
    *n = fread(p, 1, (size_t)sz, f);
    fclose(f);
    return p;
}

/* Byte offset of the end of the sidx box (= YouTube's indexRange.end + 1). */
static int64_t sidx_end(const uint8_t *p, size_t n) {
    size_t o = 0;
    while (o + 8 <= n) {
        uint32_t sz = (uint32_t)p[o] << 24 | p[o + 1] << 16 | p[o + 2] << 8 | p[o + 3];
        if (!memcmp(p + o + 4, "sidx", 4)) return (int64_t)(o + sz);
        o += sz;
    }
    return -1;
}

static void ensure_fixtures(void) {
    static int done;
    if (!done) { done = system("tests/host/make_fixtures.sh " FIX) == 0 ? 1 : -1; }
}

TB_TEST(test_mp4_init_video, "BR-PLAY-REMUX") {
    ensure_fixtures();
    size_t n;
    uint8_t *p = slurp(FIX "/v.mp4", &n);
    CHECK(p);
    tb_track t;
    CHECK_INT(tb_mp4_init(p, n, &t), 0);
    CHECK_INT(t.is_video, 1);
    CHECK_INT(t.width, 320);
    CHECK_INT(t.height, 180);
    CHECK_INT(t.nal_len_size, 4);
    CHECK(t.sps_len > 4 && t.pps_len > 0);
    CHECK_INT(t.sps[0] & 31, 7);
    CHECK_INT(t.sps[1], 77); /* Main profile */
    free(p);
}

TB_TEST(test_mp4_init_audio, "BR-PLAY-REMUX") {
    ensure_fixtures();
    size_t n;
    uint8_t *p = slurp(FIX "/a.mp4", &n);
    CHECK(p);
    tb_track t;
    CHECK_INT(tb_mp4_init(p, n, &t), 0);
    CHECK_INT(t.is_video, 0);
    CHECK_INT(t.timescale, 44100);
    CHECK_INT(t.aac_object, 2);     /* AAC-LC */
    CHECK_INT(t.aac_freq_index, 4); /* 44100 */
    CHECK_INT(t.aac_channels, 1);
    free(p);
}

TB_TEST(test_mp4_sidx_and_fragment, "BR-PLAY-REMUX AC-PLAY-2") {
    ensure_fixtures();
    size_t n;
    uint8_t *p = slurp(FIX "/v.mp4", &n);
    CHECK(p);
    tb_track t;
    tb_sidx x;
    CHECK_INT(tb_mp4_init(p, n, &t), 0);
    CHECK_INT(tb_mp4_sidx(p, n, 0, &x), 0);
    CHECK_INT(x.n, 6); /* 12 s / 2 s GOP */
    uint64_t total = 0;
    for (int i = 0; i < x.n; i++) total += x.segs[i].duration;
    CHECK_INT(total * 1000 / x.timescale, 12000);
    CHECK_INT(x.segs[0].offset, sidx_end(p, n));
    CHECK_INT(x.segs[x.n - 1].offset + x.segs[x.n - 1].size, (int64_t)n - 162); /* ffmpeg appends a 162 B mfra */
    tb_frag f;
    CHECK_INT(tb_mp4_frag(p + x.segs[1].offset, x.segs[1].size, &t, &f), 0);
    CHECK_INT(f.n, 60);
    CHECK_INT(f.s[0].key, 1);
    int keys = 0, cto = 0;
    for (int i = 0; i < f.n; i++) { keys += f.s[i].key; cto += f.s[i].cto != 0; }
    CHECK_INT(keys, 1);
    CHECK(cto > 0); /* B-frames give composition offsets */
    CHECK_INT(f.s[0].dts * 1000 / t.timescale, 2000);
    CHECK_INT(f.s[f.n - 1].offset + f.s[f.n - 1].size, x.segs[1].size);
    tb_frag_free(&f);
    tb_sidx_free(&x);
    free(p);
}

TB_TEST(test_ts_segment_is_valid, "BR-PLAY-REMUX AC-PLAY-2") {
    ensure_fixtures();
    size_t vn, an;
    uint8_t *v = slurp(FIX "/v.mp4", &vn), *a = slurp(FIX "/a.mp4", &an);
    CHECK(v && a);
    tb_track vt, at;
    tb_sidx vx, ax;
    CHECK_INT(tb_mp4_init(v, vn, &vt), 0);
    CHECK_INT(tb_mp4_init(a, an, &at), 0);
    CHECK_INT(tb_mp4_sidx(v, vn, 0, &vx), 0);
    CHECK_INT(tb_mp4_sidx(a, an, 0, &ax), 0);
    tb_frag vf, af;
    CHECK_INT(tb_mp4_frag(v + vx.segs[0].offset, vx.segs[0].size, &vt, &vf), 0);
    CHECK_INT(tb_mp4_frag(a + ax.segs[0].offset, ax.segs[0].size, &at, &af), 0);
    /* audio samples of the first 2 s only */
    int na = 0;
    while (na < af.n && af.s[na].dts < 2 * at.timescale) na++;
    tb_ts_input vi = {&vt, v + vx.segs[0].offset, vx.segs[0].size, vf.s, vf.n};
    tb_ts_input ai = {&at, a + ax.segs[0].offset, ax.segs[0].size, af.s, na};
    tb_out o = {0};
    CHECK_INT(tb_ts_segment(&o, &vi, &ai), 0);
    CHECK_INT(o.len % 188, 0);
    for (size_t i = 0; i < o.len; i += 188) CHECK_INT(o.p[i], 0x47);
    FILE *f = fopen(FIX "/seg0.ts", "wb");
    fwrite(o.p, 1, o.len, f);
    fclose(f);
    /* ffprobe must see one H.264 and one AAC stream and decode every frame without an error */
    CHECK_INT(system("test \"$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 " FIX "/seg0.ts | sort -u | grep . | tr '\\n' ' ')\" = 'aac h264 '"), 0);
    CHECK_INT(system("test \"$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 " FIX "/seg0.ts | head -1)\" = 60"), 0);
    CHECK_INT(system("test -z \"$(ffmpeg -v error -i " FIX "/seg0.ts -f null - 2>&1)\""), 0);
    tb_out_free(&o);
    tb_frag_free(&vf);
    tb_frag_free(&af);
    tb_sidx_free(&vx);
    tb_sidx_free(&ax);
    free(v);
    free(a);
}

/* ---- a small file server with Range support, standing in for googlevideo ---- */

static int g_fs_port;
static volatile int g_fs_delay_ms;   /* > 0: wait before each answer (a slow or hung download) */
static void *fs_conn(void *arg) {
    int fd = (int)(intptr_t)arg;
    char req[4096];
    size_t have = 0;
    for (;;) {
        ssize_t r = recv(fd, req + have, sizeof req - 1 - have, 0);
        if (r <= 0) break;
        have += (size_t)r;
        req[have] = 0;
        char *end = strstr(req, "\r\n\r\n");
        if (!end) continue;
        char path[512] = "";
        sscanf(req, "GET %511s", path);
        if (g_fs_delay_ms > 0) usleep((useconds_t)g_fs_delay_ms * 1000);
        long long a = 0, b = -1;
        char *rg = strstr(req, "Range: bytes=");
        if (rg) sscanf(rg + 13, "%lld-%lld", &a, &b);
        char file[600];
        snprintf(file, sizeof file, FIX "%s", path);
        size_t n;
        uint8_t *p = slurp(file, &n);
        char h[256];
        if (!p) {
            int hl = snprintf(h, sizeof h, "HTTP/1.1 404 NF\r\nContent-Length: 0\r\n\r\n");
            send(fd, h, (size_t)hl, 0);
        } else {
            if (b < 0 || b >= (long long)n) b = (long long)n - 1;
            int hl = snprintf(h, sizeof h, "HTTP/1.1 %d OK\r\nContent-Length: %lld\r\n\r\n", rg ? 206 : 200, b - a + 1);
            send(fd, h, (size_t)hl, 0);
            send(fd, p + a, (size_t)(b - a + 1), 0);
            free(p);
        }
        size_t used = (size_t)(end + 4 - req);
        memmove(req, end + 4, have - used + 1);
        have -= used;
    }
    close(fd);
    return NULL;
}
static void *fs_main(void *arg) {
    int ls = (int)(intptr_t)arg;
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) continue;
        pthread_t t;
        pthread_create(&t, NULL, fs_conn, (void *)(intptr_t)fd);
        pthread_detach(t);
    }
    return NULL;
}
static void fs_start(void) {
    if (g_fs_port) return;
    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = {.sin_family = AF_INET};
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    socklen_t sl = sizeof sa;
    bind(ls, (struct sockaddr *)&sa, sizeof sa);
    listen(ls, 8);
    getsockname(ls, (struct sockaddr *)&sa, &sl);
    g_fs_port = ntohs(sa.sin_port);
    pthread_t t;
    pthread_create(&t, NULL, fs_main, (void *)(intptr_t)ls);
    pthread_detach(t);
}

static tb_stream *fixture_stream(void) {
    size_t vn, an;
    uint8_t *v = slurp(FIX "/v.mp4", &vn), *a = slurp(FIX "/a.mp4", &an);
    if (!v || !a) return NULL;
    char vu[128], au[128];
    snprintf(vu, sizeof vu, "http://127.0.0.1:%d/v.mp4", g_fs_port);
    snprintf(au, sizeof au, "http://127.0.0.1:%d/a.mp4", g_fs_port);
    tb_stream_fmt vf = {.itag = 134, .url = vu, .width = 320, .height = 180, .bitrate = 300000, .index_end = sidx_end(v, vn) - 1};
    tb_stream_fmt af = {.itag = 140, .url = au, .bitrate = 128000, .index_end = sidx_end(a, an) - 1};
    free(v);
    free(a);
    return tb_stream_new(&vf, 1, &af);
}

TB_TEST(test_stream_segments_cover_audio_once, "BR-PLAY-REMUX AC-PLAY-2") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    char *pl = NULL;
    CHECK_INT(tb_stream_playlist(s, 0, &pl), 0);
    CHECK(strstr(pl, "#EXT-X-TARGETDURATION:2\n"));
    CHECK(strstr(pl, "0/5.ts") && !strstr(pl, "0/6.ts"));
    CHECK(strstr(pl, "#EXT-X-ENDLIST"));
    free(pl);
    /* all 6 segments, joined, must decode to 12 s with 360 video frames and every audio frame once */
    FILE *f = fopen(FIX "/all.ts", "wb");
    for (int i = 0; i < 6; i++) {
        tb_out o = {0};
        CHECK_INT(tb_stream_segment(s, 0, i, &o), 0);
        fwrite(o.p, 1, o.len, f);
        tb_out_free(&o);
    }
    fclose(f);
    CHECK_INT(system("test \"$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 " FIX "/all.ts | head -1)\" = 360"), 0);
    /* 12 s x 44100 / 1024 = 516.8 -> the AAC encoder wrote 518 frames (517 + priming); every one exactly once */
    CHECK_INT(system("n=$(ffprobe -v error -count_packets -select_streams a -show_entries stream=nb_read_packets -of csv=p=0 " FIX "/all.ts | head -1);"
                     "m=$(ffprobe -v error -count_packets -select_streams a -show_entries stream=nb_read_packets -of csv=p=0 " FIX "/a.mp4 | head -1);"
                     "test \"$n\" = \"$m\""), 0);
    tb_stream_stats st;
    tb_stream_get_stats(s, &st);
    CHECK_INT(st.segments_built, 6);
    tb_stream_free(s);
}

TB_TEST(test_hls_server_plays_in_ffmpeg, "BR-PLAY-REMUX BR-PLAY-START AC-PLAY-3 BR-PLAY-ONE") {
    ensure_fixtures();
    fs_start();
    CHECK(tb_hls_start() > 0);
    tb_stream *s = fixture_stream();
    CHECK(s);
    int order[1] = {0};
    tb_hls_set(s, order, 1);
    char url[128], cmd[512];
    tb_hls_url(0, 1, url, sizeof url);
    tb_req rq = {.url = url, .range_start = -1};
    tb_resp r;
    CHECK_INT(tb_http(&rq, &r), 200);
    CHECK(strstr(r.body, "RESOLUTION=320x180\n0.m3u8"));
    tb_resp_free(&r);
    /* ffmpeg follows master -> media playlist -> 6 segments over our server and must decode all 12 s */
    snprintf(cmd, sizeof cmd, "test \"$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 '%s' | head -1)\" = 360", url);
    CHECK_INT(system(cmd), 0);
    snprintf(cmd, sizeof cmd, "test -z \"$(ffmpeg -v error -i '%s' -f null - 2>&1)\"", url);
    CHECK_INT(system(cmd), 0);
    tb_hls_stats hs;
    tb_hls_get_stats(&hs);
    CHECK(hs.segments >= 6);
    CHECK_INT(hs.errors, 0);
    /* a stale generation is refused once the stream is removed */
    tb_hls_set(NULL, NULL, 0);
    rq.url = url;
    CHECK_INT(tb_http(&rq, &r), 404);
    tb_resp_free(&r);
    tb_stream_free(s);
}

TB_TEST(test_audio_only_playlist, "AC-BG-1") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    char *pl = NULL;
    CHECK_INT(tb_stream_playlist(s, -1, &pl), 0);
    CHECK(strstr(pl, "-1/0.ts") && strstr(pl, "-1/3.ts") && !strstr(pl, "-1/4.ts")); /* 12 s in 3 s audio fragments */
    free(pl);
    FILE *f = fopen(FIX "/audio_only.ts", "wb");
    for (int i = 0; i < 4; i++) {
        tb_out o = {0};
        CHECK_INT(tb_stream_segment(s, -1, i, &o), 0);
        fwrite(o.p, 1, o.len, f);
        tb_out_free(&o);
    }
    fclose(f);
    CHECK_INT(system("test \"$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 " FIX "/audio_only.ts | sort -u | grep . | tr '\\n' ' ')\" = 'aac '"), 0);
    CHECK_INT(system("n=$(ffprobe -v error -count_packets -select_streams a -show_entries stream=nb_read_packets -of csv=p=0 " FIX "/audio_only.ts | head -1);"
                     "m=$(ffprobe -v error -count_packets -select_streams a -show_entries stream=nb_read_packets -of csv=p=0 " FIX "/a.mp4 | head -1);"
                     "test \"$n\" = \"$m\""), 0);
    tb_stream_free(s);
}

TB_TEST(test_segment_cache_and_prefetch, "BR-PLAY-CACHE") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    tb_out o = {0};
    CHECK_INT(tb_stream_segment(s, 0, 0, &o), 0);
    CHECK_INT(tb_stream_segment(s, 0, 0, &o), 0);   /* second time from the cache */
    tb_stream_prefetch(s, 0, 1);
    for (int i = 0; i < 100; i++) { tb_stream_stats st; tb_stream_get_stats(s, &st); if (st.segments_built >= 2) break; usleep(20000); }
    CHECK_INT(tb_stream_segment(s, 0, 1, &o), 0);   /* built by the prefetch: a cache hit */
    for (int i = 2; i < 6; i++) CHECK_INT(tb_stream_segment(s, 0, i, &o), 0);
    tb_stream_stats st;
    tb_stream_get_stats(s, &st);
    CHECK_INT(st.cache_hits, 2);
    CHECK_INT(st.segments_built, 6);                 /* each segment built once */
    CHECK_INT(tb_stream_segment(s, 0, 0, &o), 0);   /* 6 segments > 4 cache slots: segment 0 was dropped */
    tb_stream_get_stats(s, &st);
    CHECK_INT(st.segments_built, 7);
    tb_out_free(&o);
    tb_stream_free(s);
}

TB_TEST(test_warm_builds_start_segment, "BR-PLAY-START") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    tb_stream_warm(s, 0, 4.5); /* resume at 4.5 s: segment 2 (2 s fragments) */
    tb_stream_stats st = {0};
    for (int i = 0; i < 100 && st.segments_built < 1; i++) { usleep(20000); tb_stream_get_stats(s, &st); }
    CHECK_INT(st.segments_built, 1);
    tb_out o = {0};
    CHECK_INT(tb_stream_segment(s, 0, 2, &o), 0);
    tb_stream_get_stats(s, &st);
    CHECK_INT(st.cache_hits, 1); /* the player's first request is served from the warm-up */
    tb_out_free(&o);
    tb_stream_free(s);
}

/* A seek target asked for while a prefetch runs is built right after it (it was dropped before), and
 * tb_stream_ready reports it without waiting. */
TB_TEST(test_warm_during_prefetch_is_kept, "BR-PLAY-SEEK-PREBUILD") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    tb_stream_warm(s, 0, 0.5);           /* segment 0 (2 s fragments) */
    tb_stream_warm(s, 0, 8.5);           /* segment 4, while the first one runs */
    CHECK_INT(tb_stream_ready(s, 0, 8.5), 0);
    int ok = 0;
    for (int i = 0; i < 150 && !ok; i++) { usleep(20000); ok = tb_stream_ready(s, 0, 8.5); }
    CHECK_INT(ok, 1);
    CHECK_INT(tb_stream_ready(s, 0, 0.5), 1);
    tb_stream_stats st = {0};
    tb_stream_get_stats(s, &st);
    CHECK_INT(st.segments_built, 2);
    tb_out o = {0};
    CHECK_INT(tb_stream_segment(s, 0, 4, &o), 0);
    tb_stream_get_stats(s, &st);
    CHECK_INT(st.cache_hits, 1);         /* the player's request is served from the cache */
    tb_out_free(&o);
    tb_stream_free(s);
}

/* At a return from the background the app cancels a hung download, then warms the current segment: the cancel
 * must stop only the old download, not the new warm-up (owner bug 2026-11-12, about 30 s of loading). */
TB_TEST(test_warm_after_cancel_still_builds, "BR-PLAY-BG-PICTURE") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    tb_stream_cancel(s);                 /* nothing runs */
    tb_stream_warm(s, 0, 4.5);
    int ok = 0;
    for (int i = 0; i < 150 && !ok; i++) { usleep(20000); ok = tb_stream_ready(s, 0, 4.5); }
    CHECK_INT(ok, 1);
    tb_stream_warm(s, 0, 0.5);           /* busy case: a prefetch runs, then cancel, then a new warm-up */
    tb_stream_cancel(s);
    tb_stream_warm(s, 0, 8.5);
    ok = 0;
    for (int i = 0; i < 150 && !ok; i++) { usleep(20000); ok = tb_stream_ready(s, 0, 8.5); }
    CHECK_INT(ok, 1);
    tb_stream_free(s);
}

/* Device run 2026-11-12: a cancel at the return also stopped MediaPlayer's new request, and the player did not ask
 * again. abort_before(t) stops only downloads that started before t. */
TB_TEST(test_abort_before_keeps_new_downloads, "BR-PLAY-BG-PICTURE") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    double left_at = tb_now_ms();        /* the app left the front before this download started */
    usleep(2000);
    tb_stream_warm(s, 0, 4.5);
    tb_stream_abort_before(s, left_at);
    int ok = 0;
    for (int i = 0; i < 150 && !ok; i++) { usleep(20000); ok = tb_stream_ready(s, 0, 4.5); }
    CHECK_INT(ok, 1);
    tb_out o = {0};
    CHECK_INT(tb_stream_segment(s, 0, 3, &o), 0);   /* and the player's own request after it works */
    tb_out_free(&o);
    tb_stream_free(s);
}

/* A cancel must stop a download that is already running (each download has its own stop flag since 2026-11-12;
 * the seek path in tb_stream_segment and tb_stream_free use tb_stream_cancel for that). */
TB_TEST(test_cancel_stops_running_download, "BR-PLAY-SEEK-PREBUILD") {
    ensure_fixtures();
    fs_start();
    tb_stream *s = fixture_stream();
    CHECK(s);
    g_fs_delay_ms = 5000;                /* the server hangs for 5 s */
    tb_stream_warm(s, 0, 0.5);
    usleep(100000);
    double t0 = tb_now_ms();
    tb_stream_cancel(s);
    tb_stream_stats st = {0};
    for (int i = 0; i < 100 && st.last_status != TB_ERR_CANCEL; i++) { usleep(20000); tb_stream_get_stats(s, &st); }
    double ms = tb_now_ms() - t0;
    g_fs_delay_ms = 0;
    CHECK_INT(st.last_status, TB_ERR_CANCEL);
    CHECK(ms < 1000);                    /* the stop flag is polled every 200 ms */
    tb_stream_free(s);
}
