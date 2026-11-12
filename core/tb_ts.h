/* MPEG-TS writer for HLS: H.264 (Annex B) + AAC (ADTS) in one segment. */
#ifndef TB_TS_H
#define TB_TS_H
#include <stddef.h>
#include <stdint.h>
#include "tb_mp4.h"

typedef struct { uint8_t *p; size_t len, cap; } tb_out;

typedef struct {
    const tb_track *track;
    const uint8_t *data;     /* fragment buffer the samples point into */
    size_t data_len;
    const tb_sample *s;
    int n;
} tb_ts_input;

/* Write PAT, PMT, then video and audio PES in time order. Times: track timescale -> 90 kHz + 1.4 s offset.
 * video or audio may have n == 0 (audio-only or video-only segment). Returns 0 or < 0. */
int tb_ts_segment(tb_out *out, const tb_ts_input *video, const tb_ts_input *audio);
void tb_out_free(tb_out *o);
/* Low-level parts for the live merge: PAT + PMT (PMT PID 0x1000; pid 0 = absent) and one PES. */
int tb_ts_tables(tb_out *out, int video_pid, int audio_pid, int pcr_pid);
int tb_ts_pes(tb_out *out, int pid, int *cc, int stream_id, uint64_t pts, int64_t dts, int64_t pcr, int rai,
              const uint8_t *payload, size_t len);
#endif
