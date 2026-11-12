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
typedef struct { int requests, segments, errors, last_seg; double last_serve_ms; } tb_hls_stats;
void tb_hls_get_stats(tb_hls_stats *out);
/* Requests since the last tb_hls_set: "<ms> <path> <status> <bytes> <serve ms>" per line. */
int tb_hls_log(char *out, size_t cap);
#endif
