/* Fragmented MP4 (DASH) reader: init segment, sidx, one moof+mdat fragment. No allocation except the sample table. */
#ifndef TB_MP4_H
#define TB_MP4_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    int is_video;
    uint32_t timescale;
    /* video */
    uint8_t sps[256], pps[256];
    int sps_len, pps_len, nal_len_size;
    int width, height;
    /* audio: AudioSpecificConfig fields for ADTS */
    int aac_object, aac_freq_index, aac_channels;
} tb_track;

typedef struct {
    int64_t offset;     /* byte offset of the fragment in the file */
    uint32_t size;      /* moof + mdat bytes */
    uint64_t start;     /* presentation start, track timescale */
    uint32_t duration;
} tb_seg;

typedef struct {
    uint32_t timescale;
    tb_seg *segs;       /* malloc */
    int n;
} tb_sidx;

typedef struct {
    uint32_t offset;    /* byte offset in the fragment buffer */
    uint32_t size;
    uint64_t dts;       /* track timescale */
    int32_t cto;        /* composition offset */
    int key;
} tb_sample;

typedef struct {
    tb_sample *s;       /* malloc */
    int n;
    uint32_t moof_size; /* bytes before the first sample's box (useful for partial fetches) */
    uint64_t end_dts;   /* dts after the last sample */
} tb_frag;

int tb_mp4_init(const uint8_t *p, size_t n, tb_track *t);               /* 0 = ok */
/* sidx box found anywhere at top level of p; file_offset = position of p in the file. */
int tb_mp4_sidx(const uint8_t *p, size_t n, int64_t file_offset, tb_sidx *x);
/* Parse moof (+ mdat if present). Samples whose bytes are past n are kept but flagged by offset+size > n. */
int tb_mp4_frag(const uint8_t *p, size_t n, const tb_track *t, tb_frag *f);
/* Bytes needed from the fragment start to hold the moof (0 if p is too short to tell; then fetch more). */
uint32_t tb_mp4_moof_size(const uint8_t *p, size_t n);
void tb_sidx_free(tb_sidx *x);
void tb_frag_free(tb_frag *f);
#endif
