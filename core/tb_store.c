#include "tb_store.h"
#include <pthread.h>
#include <sqlite3.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

static sqlite3 *g_db;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
/* History kept: enough for months of use; trimmed on add. */
#define HISTORY_MAX 2000
#define SEARCH_MAX 50

static double now_s(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec + tv.tv_usec / 1e6; }

static long g_commits;   /* BR-HIST-TX check: one commit per owner action */
static int count_commit(void *arg) { (void)arg; g_commits++; return 0; }

int tb_store_open(const char *path) {
    pthread_mutex_lock(&g_mu);
    if (g_db) { pthread_mutex_unlock(&g_mu); return 0; }
    int rc = sqlite3_open(path, &g_db);
    if (rc == SQLITE_OK)
        rc = sqlite3_exec(g_db,
                          "PRAGMA journal_mode=WAL;"
                          "PRAGMA synchronous=NORMAL;"
                          "CREATE TABLE IF NOT EXISTS history(video_id TEXT PRIMARY KEY, title TEXT, channel TEXT, length TEXT,"
                          " position REAL DEFAULT 0, watched_at REAL);"
                          "CREATE INDEX IF NOT EXISTS history_at ON history(watched_at);"
                          "CREATE TABLE IF NOT EXISTS searches(q TEXT PRIMARY KEY, at REAL);"
                          "CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT);",
                          NULL, NULL, NULL);
    if (rc != SQLITE_OK && g_db) { sqlite3_close(g_db); g_db = NULL; }
    if (g_db) sqlite3_commit_hook(g_db, count_commit, NULL);
    pthread_mutex_unlock(&g_mu);
    return rc == SQLITE_OK ? 0 : -rc;
}

long tb_store_commits(void) { return g_commits; }

void tb_store_close(void) {
    pthread_mutex_lock(&g_mu);
    if (g_db) sqlite3_close(g_db);
    g_db = NULL;
    pthread_mutex_unlock(&g_mu);
}

/* Run one statement with text/double binds: fmt chars 't' = const char *, 'd' = double. */
static int exec(const char *sql, const char *fmt, ...) {
    if (!g_db) return -1;
    sqlite3_stmt *st;
    if (sqlite3_prepare_v2(g_db, sql, -1, &st, NULL) != SQLITE_OK) return -1;
    va_list ap;
    va_start(ap, fmt);
    for (int i = 0; fmt && fmt[i]; i++) {
        if (fmt[i] == 't') { const char *s = va_arg(ap, const char *); if (s) sqlite3_bind_text(st, i + 1, s, -1, SQLITE_TRANSIENT); else sqlite3_bind_null(st, i + 1); }
        else sqlite3_bind_double(st, i + 1, va_arg(ap, double));
    }
    va_end(ap);
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    return rc == SQLITE_DONE || rc == SQLITE_ROW ? 0 : -1;
}

/* BR-HIST-TX: the statements of one owner action share one transaction (one journal sync on flash, not one per
 * statement). Called with g_mu held. */
static void tx_begin(void) { if (g_db) sqlite3_exec(g_db, "BEGIN", NULL, NULL, NULL); }
static int tx_end(int rc) {
    if (g_db) sqlite3_exec(g_db, rc == 0 ? "COMMIT" : "ROLLBACK", NULL, NULL, NULL);
    return rc;
}

int tb_store_history_add(const char *id, const char *title, const char *channel, const char *length) {
    pthread_mutex_lock(&g_mu);
    /* keep the saved position when the same video is opened again */
    /* INSERT OR IGNORE, not UPSERT: iOS 6 has SQLite 3.7.13 (UPSERT is 3.24+) */
    tx_begin();
    int rc = exec("INSERT OR IGNORE INTO history(video_id,title,channel,length,watched_at) VALUES(?,?,?,?,?)",
                  "ttttd", id, title, channel, length, now_s());
    if (rc == 0) rc = exec("UPDATE history SET watched_at=?, title=COALESCE(?,title), channel=COALESCE(?,channel),"
                           " length=COALESCE(?,length) WHERE video_id=?", "dtttt", now_s(), title, channel, length, id);
    if (rc == 0) rc = exec("DELETE FROM history WHERE video_id IN (SELECT video_id FROM history ORDER BY watched_at DESC LIMIT -1 OFFSET ?)", "d", (double)HISTORY_MAX);
    tx_end(rc);
    pthread_mutex_unlock(&g_mu);
    return rc;
}

int tb_store_history_position(const char *id, double pos) {
    pthread_mutex_lock(&g_mu);
    int rc = exec("UPDATE history SET position=? WHERE video_id=?", "dt", pos, id);
    pthread_mutex_unlock(&g_mu);
    return rc;
}

double tb_store_history_get_position(const char *id) {
    double p = 0;
    pthread_mutex_lock(&g_mu);
    sqlite3_stmt *st;
    if (g_db && sqlite3_prepare_v2(g_db, "SELECT position FROM history WHERE video_id=?", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, id, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(st) == SQLITE_ROW) p = sqlite3_column_double(st, 0);
        sqlite3_finalize(st);
    }
    pthread_mutex_unlock(&g_mu);
    return p;
}

static char *col(sqlite3_stmt *st, int i) {
    const unsigned char *t = sqlite3_column_text(st, i);
    return t ? strdup((const char *)t) : NULL;
}

int tb_store_history_list(int limit, tb_hist **out, int *n) {
    *out = NULL;
    *n = 0;
    pthread_mutex_lock(&g_mu);
    sqlite3_stmt *st;
    int rc = -1;
    if (g_db && sqlite3_prepare_v2(g_db, "SELECT video_id,title,channel,length,position,watched_at FROM history ORDER BY watched_at DESC LIMIT ?",
                                   -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_int(st, 1, limit);
        *out = calloc((size_t)limit + 1, sizeof **out);
        while (sqlite3_step(st) == SQLITE_ROW && *n < limit) {
            tb_hist *h = &(*out)[(*n)++];
            h->video_id = col(st, 0);
            h->title = col(st, 1);
            h->channel = col(st, 2);
            h->length = col(st, 3);
            h->position = sqlite3_column_double(st, 4);
            h->watched_at = sqlite3_column_double(st, 5);
        }
        sqlite3_finalize(st);
        rc = 0;
    }
    pthread_mutex_unlock(&g_mu);
    return rc;
}

int tb_store_history_remove(const char *id) {
    pthread_mutex_lock(&g_mu);
    int rc = exec("DELETE FROM history WHERE video_id=?", "t", id);
    pthread_mutex_unlock(&g_mu);
    return rc;
}

void tb_hist_free(tb_hist *h, int n) {
    for (int i = 0; i < n; i++) { free(h[i].video_id); free(h[i].title); free(h[i].channel); free(h[i].length); }
    free(h);
}

int tb_store_search_add(const char *q) {
    pthread_mutex_lock(&g_mu);
    tx_begin();
    int rc = exec("INSERT OR REPLACE INTO searches(q,at) VALUES(?,?)", "td", q, now_s());
    if (rc == 0) rc = exec("DELETE FROM searches WHERE q IN (SELECT q FROM searches ORDER BY at DESC LIMIT -1 OFFSET ?)", "d", (double)SEARCH_MAX);
    tx_end(rc);
    pthread_mutex_unlock(&g_mu);
    return rc;
}

int tb_store_search_list(int limit, char ***out, int *n) {
    *out = NULL;
    *n = 0;
    pthread_mutex_lock(&g_mu);
    sqlite3_stmt *st;
    int rc = -1;
    if (g_db && sqlite3_prepare_v2(g_db, "SELECT q FROM searches ORDER BY at DESC LIMIT ?", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_int(st, 1, limit);
        *out = calloc((size_t)limit + 1, sizeof **out);
        while (sqlite3_step(st) == SQLITE_ROW && *n < limit) (*out)[(*n)++] = col(st, 0);
        sqlite3_finalize(st);
        rc = 0;
    }
    pthread_mutex_unlock(&g_mu);
    return rc;
}

int tb_store_set(const char *k, const char *v) {
    pthread_mutex_lock(&g_mu);
    int rc = v ? exec("INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)", "tt", k, v) : exec("DELETE FROM kv WHERE k=?", "t", k);
    pthread_mutex_unlock(&g_mu);
    return rc;
}

char *tb_store_get(const char *k) {
    char *v = NULL;
    pthread_mutex_lock(&g_mu);
    sqlite3_stmt *st;
    if (g_db && sqlite3_prepare_v2(g_db, "SELECT v FROM kv WHERE k=?", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, k, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(st) == SQLITE_ROW) v = col(st, 0);
        sqlite3_finalize(st);
    }
    pthread_mutex_unlock(&g_mu);
    return v;
}
