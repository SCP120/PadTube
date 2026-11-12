/* Real YouTube over the network (no account). These tests depend on YouTube's servers on the day they run. */
#include <stdlib.h>
#include <string.h>
#include "tb_hls.h"
#include "tb_http.h"
#include "tb_stream.h"
#include "tb_test.h"
#include "tb_yt.h"

static int ready(void) {
    static int done = 0;
    if (!done) {
        tb_http_init("/etc/ssl/cert.pem");
        system("mkdir -p build/e2e");
        done = tb_yt_init("build/e2e") == 0 ? 1 : -1;
    }
    return done == 1;
}

TB_TEST(test_search_masked, "AC-SEARCH-1 BR-NET-MASK BR-SEARCH-NO-AVATAR") {
    CHECK(ready());
    tb_list l;
    CHECK_INT(tb_yt_search("lofi music", NULL, NULL, &l), 0);
    tb_yt_stats st;
    tb_yt_get_stats(&st);
    CHECK(l.n >= 10);
    CHECK(l.continuation != NULL);
    int videos = 0;
    for (int i = 0; i < l.n; i++)
        if (l.items[i].kind == TB_KIND_VIDEO) {
            videos++;
            CHECK(l.items[i].id && strlen(l.items[i].id) == 11);
            CHECK(l.items[i].title && l.items[i].title[0]);
            CHECK(l.items[i].thumb && strstr(l.items[i].thumb, "mqdefault.jpg"));
        }
    CHECK(videos >= 10);
    CHECK(st.last_bytes < 14000); /* masked: 10.9 KB decoded, 2.4 KB gzip on the wire (2026-11-11) vs 160 KB unmasked */
    tb_list next;
    char *tok = strdup(l.continuation);
    tb_list_free(&l);
    CHECK_INT(tb_yt_search(NULL, tok, NULL, &next), 0);
    free(tok);
    CHECK(next.n >= 10);
    tb_list_free(&next);
}

TB_TEST(test_suggest, "AC-SEARCH-2") {
    CHECK(ready());
    char **v;
    int n;
    CHECK_INT(tb_yt_suggest("never gonna", &v, &n), 0);
    CHECK(n >= 3);
    tb_strv_free(v, n);
}

TB_TEST(test_player_and_stream, "AC-WATCH-1 BR-PLAY-REMUX BR-PLAY-FORMAT BR-PLAY-NOJS") {
    CHECK(ready());
    tb_player p;
    CHECK_INT(tb_yt_player("dQw4w9WgXcQ", &p), 0);
    CHECK_STR(p.status, "OK");
    CHECK(p.length_s > 200);
    CHECK(p.ncaps >= 2);
    tb_format *v360 = NULL, *a140 = NULL;
    for (int i = 0; i < p.nf; i++) {
        if (p.f[i].itag == 134) v360 = &p.f[i];
        if (p.f[i].itag == 140) a140 = &p.f[i];
    }
    CHECK(v360 && a140);
    tb_stream_fmt vf = {134, v360->url, v360->width, v360->height, v360->bitrate, v360->index_end, v360->content_length};
    tb_stream_fmt af = {140, a140->url, 0, 0, a140->bitrate, a140->index_end, a140->content_length};
    tb_stream *s = tb_stream_new(&vf, 1, &af);
    char *pl = NULL;
    CHECK_INT(tb_stream_playlist(s, 0, &pl), 0);
    CHECK(strstr(pl, "0/0.ts"));
    free(pl);
    system("mkdir -p build/e2e");
    FILE *f = fopen("build/e2e/yt0.ts", "wb");
    for (int i = 0; i < 3; i++) {
        tb_out o = {0};
        CHECK_INT(tb_stream_segment(s, 0, i, &o), 0);
        fwrite(o.p, 1, o.len, f);
        tb_out_free(&o);
    }
    fclose(f);
    tb_stream_stats st;
    tb_stream_get_stats(s, &st);
    fprintf(stderr, "    3 segments: %ld bytes fetched, remux %.1f ms for %.1f s of media\n", st.bytes_fetched, st.remux_ms_total, st.media_s_total);
    CHECK_INT(system("test -z \"$(ffmpeg -v error -i build/e2e/yt0.ts -f null - 2>&1)\""), 0);
    CHECK_INT(system("test \"$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 build/e2e/yt0.ts | sort -u | grep . | tr '\\n' ' ')\" = 'aac h264 '"), 0);
    tb_stream_free(s);
    tb_player_free(&p);
}

TB_TEST(test_captions_srv1, "AC-CAPTIONS-1") {
    CHECK(ready());
    tb_player p;
    CHECK_INT(tb_yt_player("dQw4w9WgXcQ", &p), 0);
    int asr = -1, manual = -1;
    for (int i = 0; i < p.ncaps; i++) {
        if (p.caps[i].asr && asr < 0) asr = i;
        if (!p.caps[i].asr && manual < 0) manual = i;
    }
    CHECK(asr >= 0 && manual >= 0);
    tb_captions c;
    CHECK_INT(tb_yt_captions(p.caps[manual].base_url, &c), 0);
    CHECK(c.n > 20);
    CHECK(c.cues[0].text[0]);
    tb_captions_free(&c);
    CHECK_INT(tb_yt_captions(p.caps[asr].base_url, &c), 0);
    CHECK(c.n > 20);
    tb_captions_free(&c);
    tb_player_free(&p);
}

TB_TEST(test_next_watch_page, "AC-WATCH-2 AC-CHAPTERS-1 AC-COMMENTS-1") {
    CHECK(ready());
    tb_next n;
    CHECK_INT(tb_yt_next("aircAruvnKk", &n), 0);
    tb_yt_stats st;
    tb_yt_get_stats(&st);
    CHECK(st.last_bytes < 30000); /* the mask held: 15 KB decoded vs 325 KB without (2026-11-11) */
    CHECK(n.title && strstr(n.title, "neural network"));
    CHECK_STR(n.channel, "3Blue1Brown");
    CHECK_STR(n.channel_id, "UCYO_jab_esuFRV4b17AJtAw");
    CHECK(n.views && strstr(n.views, "views"));
    CHECK(n.description && strlen(n.description) > 50);
    CHECK(n.likes && n.likes[0]);
    CHECK(n.comments_token);
    CHECK(n.related.n >= 5);
    CHECK(n.nchapters >= 5);
    CHECK(n.chapters[0].start == 0 && n.chapters[1].start > 0);
    tb_comments c;
    CHECK_INT(tb_yt_comments(n.comments_token, &c), 0);
    CHECK(c.n >= 10);
    CHECK(c.c[0].author && c.c[0].text);
    CHECK(c.continuation);
    tb_comments_free(&c);
    tb_next_free(&n);
}

TB_TEST(test_channel_and_playlist, "AC-CHANNEL-1 AC-PLAYLIST-1") {
    CHECK(ready());
    tb_list l;
    CHECK_INT(tb_yt_channel("UCYO_jab_esuFRV4b17AJtAw", NULL, NULL, &l), 0);
    CHECK(l.n >= 10);
    CHECK_STR(l.title, "3Blue1Brown");
    CHECK(l.subtitle && strstr(l.subtitle, "subscribers"));
    CHECK(l.avatar && !strncmp(l.avatar, "https://", 8));
    CHECK(l.continuation);
    tb_list_free(&l);
    CHECK_INT(tb_yt_playlist("PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab", NULL, &l), 0);
    CHECK(l.n >= 10);
    CHECK(l.items[0].kind == TB_KIND_VIDEO && l.items[0].length);
    CHECK_STR(l.title, "Essence of linear algebra");
    tb_list_free(&l);
}

#include "tb_oauth.h"
TB_TEST(test_oauth_device_code_pending, "AC-LOGIN-1 AC-LOGIN-2 BR-LOGIN-POLL") {
    CHECK(ready());
    tb_oauth_client c;
    CHECK_INT(tb_oauth_get_client(&c), 0);
    CHECK(strstr(c.client_id, ".apps.googleusercontent.com"));
    tb_device_code d;
    CHECK_INT(tb_oauth_device_code(&c, "padtube-host-test-0000", &d), 0);
    CHECK(d.user_code && strlen(d.user_code) >= 6);
    CHECK(d.verification_url && strstr(d.verification_url, "google.com/device"));
    tb_token t;
    CHECK_INT(tb_oauth_poll(&c, d.device_code, &t), 1); /* nobody entered the code */
    tb_token_free(&t);
    tb_device_code_free(&d);
    tb_oauth_client_free(&c);
}

/* The signed-in screens use the TVHTML5 client (tile renderers). A channel page answers without a token,
 * so the tile parser is checked here on real data. */
TB_TEST(test_tv_tiles_channel, "AC-LIB-1") {
    CHECK(ready());
    tb_list l;
    CHECK_INT(tb_yt_tv_browse("UCYO_jab_esuFRV4b17AJtAw", NULL, &l), 0);
    CHECK(l.n >= 20);
    int full = 0;
    for (int i = 0; i < l.n; i++) {
        tb_item *it = &l.items[i];
        if (it->kind == TB_KIND_VIDEO && it->title && it->byline && it->length && it->views && strlen(it->id) == 11) full++;
    }
    CHECK(full >= 10);
    tb_yt_stats st;
    tb_yt_get_stats(&st);
    fprintf(stderr, "    TV channel page: %ld bytes decoded, parse %.1f ms, %d items\n", st.last_bytes, st.last_parse_ms, l.n);
    tb_list_free(&l);
}

#include "tb_hls.h"
#include "tb_live.h"
/* A real live stream: find one with the live search filter, merge on the local server, play 6 s in ffmpeg. */
TB_TEST(test_live_merge_real_stream, "AC-LIVE-1 BR-LIVE-MERGE") {
    CHECK(ready());
    tb_list l;
    CHECK_INT(tb_yt_search("live news", NULL, "EgJAAQ==", &l), 0);
    tb_player p = {0};
    int found = 0;
    for (int i = 0; i < l.n && !found; i++) {
        if (!l.items[i].id || strlen(l.items[i].id) != 11) continue;
        if (tb_yt_player(l.items[i].id, &p) == 0 && p.live && p.hls_url) found = 1;
        else tb_player_free(&p);
    }
    tb_list_free(&l);
    CHECK(found);
    tb_live *lv = tb_live_new(p.hls_url, 720);
    char *pl = NULL;
    CHECK_INT(tb_live_playlist(lv, &pl), 0);
    CHECK(strstr(pl, "live/") && !strstr(pl, "ENDLIST"));
    fprintf(stderr, "    live %s at %dp\n", p.title, tb_live_height(lv));
    free(pl);
    CHECK(tb_hls_start() > 0);
    tb_hls_set_live(lv);
    char url[160], cmd[512];
    tb_hls_url(0, 2, url, sizeof url);
    snprintf(cmd, sizeof cmd, "ffmpeg -v error -i '%s' -t 6 -f null - 2>build/e2e/live_err.txt; test ! -s build/e2e/live_err.txt", url);
    CHECK_INT(system(cmd), 0);
    snprintf(cmd, sizeof cmd, "test \"$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 '%s' | sort -u | grep . | tr '\\n' ' ')\" = 'aac h264 '", url);
    CHECK_INT(system(cmd), 0);
    tb_hls_set(NULL, NULL, 0);
    tb_live_free(lv);
    tb_player_free(&p);
}

TB_TEST(test_channel_tabs, "AC-CHANNEL-2") {
    CHECK(ready());
    const char *tabs[3] = {"EgZ2aWRlb3PyBgQKAjoA", "EgdzdHJlYW1z8gYECgJ6AA%3D%3D", "EglwbGF5bGlzdHPyBgQKAkIA"};
    int kinds[3] = {TB_KIND_VIDEO, TB_KIND_VIDEO, TB_KIND_PLAYLIST};
    for (int t = 0; t < 3; t++) {
        tb_list l;
        CHECK_INT(tb_yt_channel("UCYO_jab_esuFRV4b17AJtAw", tabs[t], NULL, &l), 0);
        CHECK(l.n >= 3);
        CHECK_INT(l.items[0].kind, kinds[t]);
        tb_list_free(&l);
    }
}

TB_TEST(test_shorts_feed_live, "BR-SHORTS-FEED") {
    CHECK(ready());
    tb_list a;
    CHECK_INT(tb_yt_shorts(NULL, &a), 0);          /* seed + first page (D53) */
    CHECK(a.n >= 5);
    CHECK(a.continuation && a.continuation[0]);
    for (int i = 0; i < a.n; i++) CHECK(a.items[i].id && strlen(a.items[i].id) == 11);
    tb_list b;
    CHECK_INT(tb_yt_shorts(a.continuation, &b), 0);
    CHECK(b.n >= 4);
    tb_player p;                                    /* a Short plays like any video: H.264 + AAC */
    CHECK_INT(tb_yt_player(a.items[0].id, &p), 0);
    CHECK_STR(p.status, "OK");
    int avc = 0;
    for (int i = 0; i < p.nf; i++) if (p.f[i].mime && strstr(p.f[i].mime, "avc1") && p.f[i].height >= 640) avc++;
    CHECK(avc > 0);
    tb_player_free(&p);
    tb_list_free(&a);
    tb_list_free(&b);
}
