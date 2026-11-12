/* Local store: SQLite (iOS 6 ships 3.7.13) in WAL mode. Watch history with resume position, recent searches,
 * key/value settings. One transaction per user action (research-efficiency §7). Thread safe (one mutex). */
#ifndef TB_STORE_H
#define TB_STORE_H

typedef struct {
    char *video_id, *title, *channel, *length;
    double position, watched_at;
} tb_hist;

int tb_store_open(const char *path);                 /* 0 = ok */
void tb_store_close(void);
long tb_store_commits(void);                        /* commits since start (BR-HIST-TX test) */
int tb_store_history_add(const char *video_id, const char *title, const char *channel, const char *length);
int tb_store_history_position(const char *video_id, double position);
double tb_store_history_get_position(const char *video_id);   /* 0 if unknown */
int tb_store_history_list(int limit, tb_hist **out, int *n);
int tb_store_history_remove(const char *video_id);
void tb_hist_free(tb_hist *h, int n);
int tb_store_search_add(const char *q);
int tb_store_search_list(int limit, char ***out, int *n);
int tb_store_set(const char *key, const char *value);        /* value NULL deletes */
char *tb_store_get(const char *key);                         /* malloc or NULL */
#endif
