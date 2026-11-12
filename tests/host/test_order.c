#include <stdlib.h>
#include <string.h>
#include "tb_test.h"
#include "tb_yt.h"

TB_TEST(test_age_seconds, "BR-SUBS-ORDER BR-LIB-SUBS-ORDER") {
    CHECK_INT(tb_age_seconds("3 hours ago"), 3 * 3600);
    CHECK_INT(tb_age_seconds("1 day ago"), 86400);
    CHECK_INT(tb_age_seconds("Streamed 2 weeks ago"), 2 * 604800);
    CHECK_INT(tb_age_seconds("5 minutes ago"), 300);
    CHECK_INT(tb_age_seconds("11 months ago"), 11 * 2629800L);
    CHECK_INT(tb_age_seconds("1.2M views"), -1);
    CHECK_INT(tb_age_seconds(NULL), -1);
}

static tb_item mk(const char *id, const char *pub) {
    tb_item it = {.kind = TB_KIND_VIDEO};
    it.id = strdup(id);
    it.published = pub ? strdup(pub) : NULL;
    return it;
}

TB_TEST(test_sort_by_age_dedupes, "BR-SUBS-ORDER BR-LIB-SUBS-ORDER") {
    tb_list l = {0};
    l.items = calloc(5, sizeof *l.items);
    l.items[0] = mk("aaa", "2 days ago");
    l.items[1] = mk("bbb", "3 hours ago");
    l.items[2] = mk("aaa", "2 days ago"); /* repeated in another shelf */
    l.items[3] = mk("ccc", NULL);         /* no age: last */
    l.items[4] = mk("ddd", "1 hour ago");
    l.n = 5;
    tb_list_sort_by_age(&l);
    CHECK_INT(l.n, 4);
    CHECK_STR(l.items[0].id, "ddd");
    CHECK_STR(l.items[1].id, "bbb");
    CHECK_STR(l.items[2].id, "aaa");
    CHECK_STR(l.items[3].id, "ccc");
    tb_list_free(&l);
}
