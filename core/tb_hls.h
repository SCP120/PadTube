/* HLS server on 127.0.0.1 for the iOS player. Serves the streams registered with tb_hls_set. */
#ifndef TB_HLS_H
#define TB_HLS_H
#include "tb_live.h"
#include "tb_stream.h"

int tb_hls_start(void);                 /* returns the port, or < 0 */
/* Make s the current stream (the server keeps a reference while it is current or serving; never blocks).
 * order/n: master playlist variant order. Returns the generation used in URLs. */
int tb_hls_set(tb_stream *s, const int *order, int n);
/* Live instead of a stream (the server keeps a reference). */
int tb_hls_set_live(tb_live *l);
/* master=1: http://127.0.0.1:<port>/<gen>/master.m3u8; 0: <vi>.m3u8 (vi = -1: audio only); 2: live.m3u8. */
void tb_hls_url(int vi, int master, char *out, size_t cap);
/* More streams at the same time as the current one (the Shorts players, D54): each gets its own generation, served
 * until tb_hls_remove. Returns the generation, or -1 when all TB_HLS_EXTRA slots are in use. Media playlists only. */
#define TB_HLS_EXTRA 4
int tb_hls_add(tb_stream *s);
void tb_hls_remove(int gen);
void tb_hls_url_gen(int gen, int vi, char *out, size_t cap);   /* http://127.0.0.1:<port>/<gen>/<vi>.m3u8 */
/* Preload gate of an extra stream (Shorts preload window): requests for segments above max_seg wait (no download,
 * no build, no prefetch) until the limit rises or the stream is removed. TB_HLS_OPEN: no limit; TB_HLS_FREEZE: the
 * highest segment served so far. */
#define TB_HLS_OPEN (-1)
#define TB_HLS_FREEZE (-2)
void tb_hls_limit(int gen, int max_seg);
int tb_hls_served_max(int gen);   /* highest segment served, -1 if none or unknown gen */
typedef struct { int requests, segments, errors, last_seg; double last_serve_ms; } tb_hls_stats;
void tb_hls_get_stats(tb_hls_stats *out);
/* Requests since the last tb_hls_set: "<ms> <path> <status> <bytes> <serve ms>" per line. */
int tb_hls_log(char *out, size_t cap);
#endif
