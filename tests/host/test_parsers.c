/* InnerTube parsers on captured public answers (tests/fixtures/yt/, signed out, captured 2026-11-12 with
 * tools/capture_fixtures.c; the network's IP in stream URLs replaced by 0.0.0.0). Expected values were read from
 * the raw JSON with a separate script (document order), not from these parsers. */
#include <stdlib.h>
#include <string.h>
#include "tb_test.h"
#include "tb_yt.h"

static char *load(const char *name, size_t *n) {
    char p[256];
    snprintf(p, sizeof p, "tests/fixtures/yt/%s", name);
    FILE *f = fopen(p, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long z = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)z + 1); *n = fread(b, 1, (size_t)z, f); b[*n] = 0; fclose(f);
    return b;
}

TB_TEST(test_parse_search_fixture, "AC-SEARCH-1") {
    size_t n; char *j = load("search_3blue1brown.json", &n); CHECK(j);
    tb_list l; CHECK_INT(tb_yt_parse_list(j, n, &l), 0); free(j);
    CHECK_INT(l.n, 20);                                   /* 16 videos, 2 channels, 2 playlists */
    CHECK_INT(l.items[0].kind, TB_KIND_CHANNEL);
    CHECK_STR(l.items[0].id, "UCYO_jab_esuFRV4b17AJtAw");
    CHECK_STR(l.items[0].title, "3Blue1Brown");
    CHECK_INT(l.items[1].kind, TB_KIND_PLAYLIST);
    CHECK_STR(l.items[1].id, "PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab");
    CHECK_STR(l.items[1].title, "Essence of linear algebra");
    CHECK_INT(l.items[2].kind, TB_KIND_VIDEO);
    CHECK_STR(l.items[2].id, "LKrwhjOI8Nc");
    CHECK_STR(l.items[2].title, "There's never been a better time to go into math");
    CHECK_STR(l.items[2].length, "40:44");
    CHECK(l.continuation && l.continuation[0]);
    tb_list_free(&l);
}

TB_TEST(test_parse_player_fixture, "AC-WATCH-1") {
    size_t n; char *j = load("player_dQw4w9WgXcQ.json", &n); CHECK(j);
    tb_player p; CHECK_INT(tb_yt_parse_player(j, n, &p), 0); free(j);
    CHECK_STR(p.status, "OK");
    CHECK_INT(p.length_s, 213);
    CHECK_STR(p.author, "Rick Astley");
    CHECK_STR(p.title, "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)");
    CHECK_INT(p.nf, 27);
    int has134 = 0, has140 = 0;
    for (int i = 0; i < p.nf; i++) { has134 |= p.f[i].itag == 134; has140 |= p.f[i].itag == 140; }
    CHECK(has134 && has140);                              /* 360p H.264 and AAC: the formats PadTube plays */
    CHECK_INT(p.ncaps, 6);                                /* en, en (asr), de-DE, ja, pt-BR, es-419 */
    CHECK_STR(p.caps[0].lang, "en"); CHECK_INT(p.caps[0].asr, 0);
    CHECK_STR(p.caps[1].lang, "en"); CHECK_INT(p.caps[1].asr, 1);
    CHECK_STR(p.caps[5].lang, "es-419");
    CHECK_INT(p.live, 0);
    tb_player_free(&p);
}

TB_TEST(test_parse_next_fixture, "AC-VPAGE-1") {
    size_t n; char *j = load("next_dQw4w9WgXcQ.json", &n); CHECK(j);
    tb_next x; CHECK_INT(tb_yt_parse_next(j, n, &x), 0); free(j);
    CHECK_INT(x.related.n, 9);
    CHECK_STR(x.related.items[0].id, "GIHtHCiNSIQ");
    CHECK(x.comments_token && x.comments_token[0]);
    tb_next_free(&x);
}

TB_TEST(test_parse_comments_fixture, "AC-COMMENTS-1") {
    size_t n; char *j = load("comments_dQw4w9WgXcQ.json", &n); CHECK(j);
    tb_comments c; CHECK_INT(tb_yt_parse_comments(j, n, &c), 0); free(j);
    CHECK_INT(c.n, 20);
    CHECK_STR(c.c[0].author, "@grustache4569");
    CHECK(c.c[0].text && strncmp(c.c[0].text, "I Rick rolled my entire French class", 36) == 0);
    tb_comments_free(&c);
}

TB_TEST(test_parse_channel_fixture, "AC-CHANNEL-1") {
    size_t n; char *j = load("channel_3blue1brown.json", &n); CHECK(j);
    tb_list l; CHECK_INT(tb_yt_parse_list(j, n, &l), 0); free(j);
    CHECK_INT(l.n, 30);
    CHECK_STR(l.items[0].id, "LKrwhjOI8Nc");
    tb_list_free(&l);
}

TB_TEST(test_parse_playlist_fixture, "AC-PLAYLIST-1") {
    size_t n; char *j = load("playlist_linear_algebra.json", &n); CHECK(j);
    tb_list l; CHECK_INT(tb_yt_parse_list(j, n, &l), 0); free(j);
    CHECK_INT(l.n, 16);
    CHECK_INT(l.items[0].kind, TB_KIND_VIDEO);
    CHECK_STR(l.items[0].id, "fNk_zzaMoSs");
    tb_list_free(&l);
}
