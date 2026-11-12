/* Owner bug 2026-11-12: duplicates on the signed-in Home feed. The TV feed repeats a video across shelves, and a
 * mix comes as a tile (RD + video id) and as a lockup with another id but the same first video. Synthetic fixture
 * with that shape (the captured private feed stays in local/capture: real titles and ids of the owner). */
#include <stdlib.h>
#include "tb_test.h"
#include "tb_yt.h"

static char *slurp3(const char *p, size_t *n) {
    FILE *f = fopen(p, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long z = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)z + 1); *n = fread(b, 1, (size_t)z, f); b[*n] = 0; fclose(f);
    return b;
}

TB_TEST(test_dedupe_tv_home, "BR-LIB-DEDUP") {
    size_t n;
    char *j = slurp3("tests/fixtures/tv_home_dups.json", &n);
    CHECK(j);
    tb_list l;
    CHECK_INT(tb_yt_parse_list(j, n, &l), 0);
    CHECK_INT(l.n, 6);
    CHECK_STR(l.items[1].first_video, "AAAAAAAAAA2");   /* from the RD id */
    CHECK_STR(l.items[4].first_video, "AAAAAAAAAA2");   /* from the thumbnail URL */
    tb_list_dedupe(&l);
    CHECK_INT(l.n, 4);
    CHECK_STR(l.items[0].id, "AAAAAAAAAA1");
    CHECK_STR(l.items[1].id, "RDAAAAAAAAAA2");          /* the first renderer of the mix wins */
    CHECK_STR(l.items[2].id, "AAAAAAAAAA3");
    CHECK_STR(l.items[3].id, "AAAAAAAAAA4");
    tb_list_free(&l);
    free(j);
}

/* The captured private feed, when it exists on this Mac (local/capture is git-ignored). */
TB_TEST(test_dedupe_captured_home, "BR-LIB-DEDUP") {
    tb_list all = {0};
    int pages = 0;
    for (int i = 1; i <= 10; i++) {
        char p[128];
        snprintf(p, sizeof p, "local/capture/dump/browse-%d.json", i);
        size_t n;
        char *j = slurp3(p, &n);
        if (!j) continue;
        pages++;
        tb_list l;
        tb_yt_parse_list(j, n, &l);
        for (int k = 0; k < l.n; k++) {
            if (all.n == all.cap) { all.cap = all.cap ? all.cap * 2 : 64; all.items = realloc(all.items, (size_t)all.cap * sizeof *all.items); }
            all.items[all.n++] = l.items[k];
        }
        free(l.items); l.items = NULL; l.n = 0;
        tb_list_free(&l);
        free(j);
    }
    if (!pages) { tb_list_free(&all); return; } /* no capture on this Mac: nothing to check */
    tb_list_dedupe(&all);
    for (int a = 0; a < all.n; a++)
        for (int b = a + 1; b < all.n; b++) {
            char ka[2][64], kb[2][64];
            tb_item_keys(&all.items[a], ka);
            tb_item_keys(&all.items[b], kb);
            CHECK(strcmp(ka[0], kb[0]) != 0);
            CHECK(!ka[1][0] || strcmp(ka[1], kb[1]) != 0);
        }
    tb_list_free(&all);
}
