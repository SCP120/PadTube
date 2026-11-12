/* Live streams: YouTube's live HLS has video-only MPEG-TS segments and a separate packed-AAC audio rendition
 * (research-features §6.2). This merges both into one TS per segment and serves a live playlist of the edge.
 * Video and audio media playlists use the same sequence numbers (MEASURED 2026-11-11). */
#ifndef TB_LIVE_H
#define TB_LIVE_H
#include <stddef.h>
#include <stdint.h>
#include "tb_ts.h"

typedef struct tb_live tb_live;

tb_live *tb_live_new(const char *master_url, int max_height);   /* AAC-LC audio group; video <= max_height */
void tb_live_free(tb_live *l);
void tb_live_retain(tb_live *l);
void tb_live_release(tb_live *l);
/* Local playlist of the last segments: "live/<sq>.ts" entries, no ENDLIST. Refetches YouTube's playlists. */
int tb_live_playlist(tb_live *l, char **out);
int tb_live_segment(tb_live *l, long sq, tb_out *out);
int tb_live_height(tb_live *l);

/* Pure parts, exposed for tests. */
/* PTS (90 kHz) from the ID3 PRIV com.apple.streaming.transportStreamTimestamp; *id3_len = tag bytes; -1 if none. */
int64_t tb_id3_timestamp(const uint8_t *p, size_t n, size_t *id3_len);
/* Merge one video-only TS segment with ADTS audio (first frame at audio_pts) into out. */
int tb_live_merge(const uint8_t *ts, size_t ts_len, const uint8_t *adts, size_t adts_len, int64_t audio_pts, tb_out *out);
#endif
