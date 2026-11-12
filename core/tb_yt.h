/* InnerTube client: MWEB for lists, VISIONOS for playback, TVHTML5 + OAuth token for the account. */
#ifndef TB_YT_H
#define TB_YT_H
#include <stddef.h>
#include <stdint.h>

enum { TB_KIND_VIDEO = 1, TB_KIND_CHANNEL = 2, TB_KIND_PLAYLIST = 3, TB_KIND_LIVE = 4, TB_KIND_SHELF = 5 };

typedef struct {
    int kind;
    char *id;            /* video id, channel id (UC...), or playlist id */
    char *title;
    char *byline;        /* channel name */
    char *channel_id;
    char *length;        /* "3:25" */
    char *views;         /* "14M views" or subscriber text */
    char *published;     /* "1 year ago" */
    char *thumb;         /* image URL (mqdefault for videos) */
    char *set_video_id;  /* playlist item id (for remove) */
    char *first_video;   /* playlists and mixes: the first video id (from an RD id or the thumbnail URL) */
} tb_item;

typedef struct {
    tb_item *items;
    int n, cap;
    char *continuation;  /* next page token or NULL */
    char *title;         /* page title (channel, playlist) */
    char *subtitle;
    char *avatar;        /* channel pages: avatar URL */
    int subscribed;      /* channel pages: -1 unknown, 0, 1 */
    char *error;
} tb_list;

typedef struct {
    int itag;
    char *url;
    char *mime;          /* "video/mp4; codecs=..." */
    int width, height, bitrate, fps;
    int64_t init_end, index_start, index_end, content_length;
    int audio;
    char *audio_track_id, *audio_track_name;
    char *sig_s, *sig_sp;   /* signatureCipher (TV client): the challenge and the query key for its answer; url then has n= */
    int audio_default;
} tb_format;

typedef struct {
    char *base_url;
    char *lang;
    char *name;
    int asr;             /* auto-generated */
} tb_ctrack;

/* Order caption tracks for the Subtitles list (owner report 2026-11-12: Arabic came first, YouTube's order):
 * tracks in the device languages first (pref order, "vi" matches "vi-VN"), then English, then the rest by name;
 * in one language the manual track comes before the auto-generated one. Stable. */
void tb_caps_sort(tb_ctrack *caps, int n, const char *const *pref, int npref);

typedef struct {
    char *status;        /* "OK", "LOGIN_REQUIRED", "UNPLAYABLE", "ERROR", ... */
    char *reason;
    tb_format *f;
    int nf;
    tb_ctrack *caps;
    int ncaps;
    char *hls_url;
    int live;
    int length_s;
    int expires_s;
    char *title, *author, *channel_id, *description, *views;
    char *storyboard;
} tb_player;

typedef struct { double start; char *title; } tb_chapter;

typedef struct {
    char *title, *views, *date, *description;
    char *channel, *channel_id, *channel_thumb, *subscribers;
    char *likes;
    int subscribed;      /* -1 unknown */
    tb_list related;
    tb_chapter *chapters;
    int nchapters;
    char *comments_token;
    char *comment_count;
} tb_next;

typedef struct {
    char *author, *text, *published, *likes, *replies_token;
    int reply_count;
} tb_comment;

typedef struct {
    tb_comment *c;
    int n, cap;
    char *continuation;
    char *header;        /* "1.2K Comments" */
} tb_comments;

typedef struct { double start, dur; char *text; } tb_cue;
typedef struct { tb_cue *cues; int n; } tb_captions;

/* state_dir: where the visitor ID cache lives (may be NULL). 0 = ok. */
int tb_yt_init(const char *state_dir);
/* OAuth bearer token for TV calls; NULL = signed out. */
void tb_yt_set_token(const char *access_token);
/* Test-only: write the body of every InnerTube answer to <dir>/<endpoint>-<n>.json (NULL = off). */
void tb_yt_set_dump_dir(const char *dir);

int tb_yt_search(const char *query, const char *continuation, const char *params, tb_list *out);
int tb_yt_suggest(const char *q, char ***out, int *n);
int tb_yt_player(const char *video_id, tb_player *out);
/* allow_visitor_reset 0: a LOGIN_REQUIRED ("not a bot") answer is returned as it is, the visitor ID stays (Shorts
 * preloads). With 1 a new visitor ID is fetched once and the call repeated, at most once per
 * TB_VISITOR_RESET_MIN_MS for the whole app (owner bug 2026-11-13: keep the visitor ID stable). */
int tb_yt_player_opt(const char *video_id, int allow_visitor_reset, tb_player *out);
/* The signed-in path (D64): the tv_samsung client (TVHTML5 5.20260707) with the account token and the player's
 * signatureTimestamp; formats come with signatureCipher and n (solve with tb_jsprep + JavaScriptCore). */
int tb_yt_player_tv(const char *video_id, int signature_timestamp, tb_player *out);
/* The current web player version (8 hex digits) from youtube.com/iframe_api; 0 or < 0 (error). */
int tb_yt_player_version(char out[16]);
/* signatureTimestamp of a player script, or 0 */
int tb_js_signature_timestamp(const char *src, size_t len);
/* query helpers: the decoded value of key (malloc, or NULL); a stream URL with n replaced by n_solved and
 * &<sp>=<sig, escaped> appended (sp NULL: no signature) */
char *tb_url_param(const char *url, const char *key);
char *tb_url_solved(const char *url, const char *n_solved, const char *sp, const char *sig);
#define TB_VISITOR_RESET_MIN_MS (10 * 60 * 1000.0)
int tb_yt_visitor_reset_allowed(double now_ms, double *last_ms);   /* the limiter, pure (unit test) */
typedef struct { long player_calls, login_required, visitor_resets; } tb_yt_counts;
/* Diagnosis (owner bug "not a bot", 2026-11-13): one player call with a named client (VISIONOS, IOS, TVHTML5,
 * TVHTML5_SIMPLY_EMBEDDED_PLAYER), with or without the account token. Reads only. */
typedef struct { int http; char status[32], reason[96]; int formats, avc, direct, ciphered, n_param, hls; } tb_yt_probe;
int tb_yt_probe_player(const char *client, const char *video_id, int with_token, tb_yt_probe *out);
void tb_yt_get_counts(tb_yt_counts *out);
int tb_yt_next(const char *video_id, tb_next *out);
int tb_yt_channel(const char *channel_id, const char *tab_params, const char *continuation, tb_list *out);
int tb_yt_playlist(const char *playlist_id, const char *continuation, tb_list *out);
int tb_yt_comments(const char *token, tb_comments *out);
int tb_yt_captions(const char *base_url, tb_captions *out);

/* Signed in (TV client). browse_id: FEwhat_to_watch, FEsubscriptions, FEhistory, VLWL, VLLL, FEplaylist_aggregation... */
int tb_yt_tv_browse(const char *browse_id, const char *continuation, tb_list *out);
int tb_yt_like(const char *video_id, int action); /* 1 like, -1 dislike, 0 remove */
int tb_yt_subscribe(const char *channel_id, int on);
int tb_yt_playlist_edit(const char *playlist_id, const char *video_id, int add, const char *set_video_id);
/* TV player call for the watch-history ping URLs; fills playback/watchtime URLs (malloc). */
int tb_yt_tracking(const char *video_id, char **playback_url, char **watchtime_url);
int tb_yt_ping(const char *url);

/* De-duplication keys (owner bug 2026-11-12: the TV Home feed repeats items across shelves and pages, and a mix can
 * come as two renderers). key[0]: kind + id; key[1]: "f:" + first video for playlists ("" otherwise). */
void tb_item_keys(const tb_item *it, char key[2][64]);
/* Drop items whose keys were seen in this list (first one wins). */
void tb_list_dedupe(tb_list *l);
/* A mix (playlist id RD...): its queue through next with videoId + playlistId (browse VLRD... gives nothing). */
int tb_yt_mix(const char *playlist_id, const char *first_video, const char *continuation, tb_list *out);

/* "3 hours ago", "Streamed 2 days ago", "1 year ago" -> seconds; -1 if not a relative age. */
long tb_age_seconds(const char *text);
/* Subscriptions feed: drop repeated videos (the TV feed repeats them across shelves), newest first (stable). */
void tb_list_sort_by_age(tb_list *l);
void tb_list_free(tb_list *l);
void tb_player_free(tb_player *p);
void tb_next_free(tb_next *n);
void tb_comments_free(tb_comments *c);
void tb_captions_free(tb_captions *c);
void tb_strv_free(char **v, int n);

/* Parse helpers exposed for host tests (input: a response body). */
int tb_yt_parse_list(const char *json, size_t len, tb_list *out);
/* Shorts (D53): continuation NULL = the seedless first Short + the first page of the sequence, else the next page.
 * Items are videos with a frame0.jpg cover; out->continuation is the next page's token. */
int tb_yt_shorts(const char *continuation, tb_list *out);
int tb_yt_parse_shorts_seed(const char *json, size_t len, char **video_id, char **sequence);
int tb_yt_parse_shorts(const char *json, size_t len, tb_list *out);
int tb_yt_parse_player(const char *json, size_t len, tb_player *out);
int tb_yt_parse_next(const char *json, size_t len, tb_next *out);
int tb_yt_parse_captions(const char *body, size_t len, tb_captions *out);
int tb_yt_parse_comments(const char *json, size_t len, tb_comments *out);

typedef struct { double last_ms, last_parse_ms; long last_bytes; int last_status; } tb_yt_stats;
void tb_yt_get_stats(tb_yt_stats *out);
#endif
