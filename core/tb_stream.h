/* One playback: DASH avc1 + AAC formats -> HLS variant playlists and MPEG-TS segments (1 fragment = 1 segment). */
#ifndef TB_STREAM_H
#define TB_STREAM_H
#include <stdint.h>
#include "tb_ts.h"

typedef struct {
    int itag;
    char *url;                 /* owned copy */
    int width, height, bitrate;
    int64_t index_end;         /* init + sidx are bytes 0..index_end (YouTube puts sidx right after init) */
    int64_t content_length;
} tb_stream_fmt;

typedef struct tb_stream tb_stream;

/* Copies the formats. videos sorted by height ascending is not required. */
tb_stream *tb_stream_new(const tb_stream_fmt *videos, int nv, const tb_stream_fmt *audio);
void tb_stream_free(tb_stream *s);            /* cancels downloads and drops the owner's reference */
void tb_stream_retain(tb_stream *s);          /* extra references (the HLS server holds one per request) */
void tb_stream_release(tb_stream *s);
int tb_stream_nvideo(const tb_stream *s);
const tb_stream_fmt *tb_stream_video(const tb_stream *s, int vi);
/* vi = -1: audio only. Media playlist text (malloc). Fetches init + sidx on first use. */
int tb_stream_playlist(tb_stream *s, int vi, char **out);
/* Master playlist with the given variant order (first = start variant). */
int tb_stream_master(tb_stream *s, const int *order, int n, char **out);
int tb_stream_segment(tb_stream *s, int vi, int seg, tb_out *out);
/* Build the next segment in the background (after the player took seg). */
void tb_stream_prefetch(tb_stream *s, int vi, int seg);
void tb_stream_cancel(tb_stream *s);
/* Stop the downloads that started before t (tb_now_ms): at a return from the background, a download from before the
 * suspension may hang on a dead socket; the player's new requests after the return go on. */
void tb_stream_abort_before(tb_stream *s, double t);
/* At the tap: fetch init + index and build the segment that holds `at` (s) before the player asks for it. */
void tb_stream_warm(tb_stream *s, int vi, double at);
/* 1 when the segment that holds `at` is built (in the cache). Never waits: 0 while a build runs. */
int tb_stream_ready(tb_stream *s, int vi, double at);

typedef struct {
    int segments_built, cache_hits;
    double last_build_ms, last_fetch_ms, last_remux_ms;
    double remux_ms_total, media_s_total;
    long bytes_fetched;
    int last_status;           /* last googlevideo HTTP status */
} tb_stream_stats;
void tb_stream_get_stats(tb_stream *s, tb_stream_stats *out);
#endif
