/* Local store on a temp file. SQL must run on SQLite 3.7.13 (iOS 6): no UPSERT, no window functions. */
#include <stdlib.h>
#include <unistd.h>
#include "tb_store.h"
#include "tb_test.h"

TB_TEST(test_store_history_and_position, "AC-HISTORY-1 BR-HISTORY-RESUME BR-HIST-ONE BR-HIST-SQL") {
    unlink("build/test_store.db");
    CHECK_INT(tb_store_open("build/test_store.db"), 0);
    CHECK_INT(tb_store_history_add("aaaaaaaaaaa", "First", "Ch", "1:00"), 0);
    usleep(2000);
    CHECK_INT(tb_store_history_add("bbbbbbbbbbb", "Second", "Ch", "2:00"), 0);
    CHECK_INT(tb_store_history_position("aaaaaaaaaaa", 42.5), 0);
    usleep(2000);
    /* opening again moves it to the top and keeps the position */
    CHECK_INT(tb_store_history_add("aaaaaaaaaaa", "First", NULL, NULL), 0);
    tb_hist *h;
    int n;
    CHECK_INT(tb_store_history_list(10, &h, &n), 0);
    CHECK_INT(n, 2);
    CHECK_STR(h[0].video_id, "aaaaaaaaaaa");
    CHECK_STR(h[0].channel, "Ch");
    CHECK(h[0].position == 42.5);
    tb_hist_free(h, n);
    CHECK(tb_store_history_get_position("aaaaaaaaaaa") == 42.5);
    CHECK_INT(tb_store_history_remove("aaaaaaaaaaa"), 0);
    CHECK_INT(tb_store_history_list(10, &h, &n), 0);
    CHECK_INT(n, 1);
    tb_hist_free(h, n);
    tb_store_close();
}

TB_TEST(test_store_searches_and_kv, "AC-SEARCH-3 BR-SEARCH-RECENT BR-HIST-SQL") {
    unlink("build/test_store2.db");
    CHECK_INT(tb_store_open("build/test_store2.db"), 0);
    tb_store_search_add("one");
    usleep(2000);
    tb_store_search_add("two");
    usleep(2000);
    tb_store_search_add("one");
    char **v;
    int n;
    CHECK_INT(tb_store_search_list(10, &v, &n), 0);
    CHECK_INT(n, 2);
    CHECK_STR(v[0], "one");
    for (int i = 0; i < n; i++) free(v[i]);
    free(v);
    CHECK_INT(tb_store_set("k", "v1"), 0);
    char *s = tb_store_get("k");
    CHECK_STR(s, "v1");
    free(s);
    tb_store_set("k", NULL);
    CHECK(tb_store_get("k") == NULL);
    tb_store_close();
}

TB_TEST(test_store_one_commit_per_action, "BR-HIST-TX") {
    unlink("build/test_store_tx.db");
    CHECK_INT(tb_store_open("build/test_store_tx.db"), 0);
    long c0 = tb_store_commits();
    CHECK_INT(tb_store_history_add("ccccccccccc", "Third", "Ch", "3:00"), 0);   /* 3 statements */
    CHECK_INT((int)(tb_store_commits() - c0), 1);
    CHECK_INT(tb_store_search_add("lofi"), 0);                                  /* 2 statements */
    CHECK_INT((int)(tb_store_commits() - c0), 2);
    CHECK_INT(tb_store_history_position("ccccccccccc", 42), 0);                  /* 1 statement */
    CHECK_INT((int)(tb_store_commits() - c0), 3);
    tb_store_close();
}
