/* Capture public, signed-out InnerTube answers as parser fixtures (tests/host/test_parsers.c).
 * usage: build/host/capture_fixtures <out dir>   Network: YouTube (Mac only). No account, no cookies.
 * Writes <endpoint>-<n>.json through the dump hook. Before a commit: rename them (see tests/fixtures/yt/) and replace
 * every ip= value in stream URLs with 0.0.0.0 (the network's public IP must not enter the repo).
 * Build: make -s all && xcrun clang -std=c99 -Icore -Ithird_party/vendor -Ithird_party/prefix/macos-arm64/include
 *   tools/capture_fixtures.c build/host/core/*.o build/host/vendor/*.o third_party/prefix/macos-arm64/lib/lib{ssl,crypto}.a
 *   -lz -lsqlite3 -o build/host/capture_fixtures */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tb_http.h"
#include "tb_yt.h"

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: capture_fixtures <out dir>\n"); return 2; }
    if (tb_http_init("/etc/ssl/cert.pem") != 0 || tb_yt_init("build/e2e") != 0) { fprintf(stderr, "init failed\n"); return 1; }
    tb_yt_set_dump_dir(argv[1]);
    tb_list l;
    if (tb_yt_search("3blue1brown", NULL, NULL, &l) == 0) { printf("search %d\n", l.n); tb_list_free(&l); }
    tb_player p;
    if (tb_yt_player("dQw4w9WgXcQ", &p) == 0) { printf("player %d formats %d caps\n", p.nf, p.ncaps); tb_player_free(&p); }
    tb_next n;
    char *tok = NULL;
    if (tb_yt_next("dQw4w9WgXcQ", &n) == 0) {
        printf("next %d related\n", n.related.n);
        if (n.comments_token) tok = strdup(n.comments_token);
        tb_next_free(&n);
    }
    tb_comments c;
    if (tok && tb_yt_comments(tok, &c) == 0) { printf("comments %d\n", c.n); tb_comments_free(&c); }
    free(tok);
    if (tb_yt_channel("UCYO_jab_esuFRV4b17AJtAw", NULL, NULL, &l) == 0) { printf("channel %d\n", l.n); tb_list_free(&l); }
    if (tb_yt_playlist("PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab", NULL, &l) == 0) { printf("playlist %d\n", l.n); tb_list_free(&l); }
    return 0;
}
