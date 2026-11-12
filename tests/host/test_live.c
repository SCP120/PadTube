/* Live merge: video-only TS + ADTS -> one TS with both streams (ffprobe/ffmpeg judge the output). */
#include <stdlib.h>
#include "tb_live.h"
#include "tb_test.h"

static uint8_t *slurp2(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *p = malloc((size_t)sz);
    *n = fread(p, 1, (size_t)sz, f);
    fclose(f);
    return p;
}

TB_TEST(test_id3_timestamp, "BR-LIVE-MERGE") {
    /* ID3v2.4 header + PRIV frame "com.apple.streaming.transportStreamTimestamp" + 8-byte PTS (golden: 0x1BFD09C14) */
    uint8_t b[128] = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 63, 'P', 'R', 'I', 'V', 0, 0, 0, 53, 0, 0};
    const char key[] = "com.apple.streaming.transportStreamTimestamp";
    memcpy(b + 20, key, sizeof key);
    const uint8_t ts[8] = {0, 0, 0, 1, 0xbf, 0xd0, 0x9c, 0x14};
    memcpy(b + 20 + sizeof key, ts, 8);
    size_t len;
    CHECK_INT(tb_id3_timestamp(b, sizeof b, &len), 0x1bfd09c14LL);
    CHECK_INT(len, 73);
    CHECK_INT(tb_id3_timestamp((const uint8_t *)"xxxx", 4, &len), -1);
}

TB_TEST(test_live_merge_has_both_streams, "BR-LIVE-MERGE") {
    system("tests/host/make_fixtures.sh build/fixtures");
    size_t vn, an;
    uint8_t *v = slurp2("build/fixtures/live_v.ts", &vn), *a = slurp2("build/fixtures/live_a.aac", &an);
    CHECK(v && a);
    tb_out o = {0};
    /* ffmpeg's mpegts muxer starts video at PTS 1.4 s (126000) */
    CHECK_INT(tb_live_merge(v, vn, a, an, 126000, &o), 0);
    CHECK_INT(o.len % 188, 0);
    FILE *f = fopen("build/fixtures/live_merged.ts", "wb");
    fwrite(o.p, 1, o.len, f);
    fclose(f);
    CHECK_INT(system("test \"$(ffprobe -v error -show_entries stream=codec_name -of csv=p=0 build/fixtures/live_merged.ts | sort -u | grep . | tr '\\n' ' ')\" = 'aac h264 '"), 0);
    CHECK_INT(system("test -z \"$(ffmpeg -v error -i build/fixtures/live_merged.ts -f null - 2>&1)\""), 0);
    CHECK_INT(system("n=$(ffprobe -v error -count_packets -select_streams a -show_entries stream=nb_read_packets -of csv=p=0 build/fixtures/live_merged.ts | head -1);"
                     "m=$(ffprobe -v error -count_packets -select_streams a -show_entries stream=nb_read_packets -of csv=p=0 build/fixtures/live_a.aac | head -1);"
                     "test \"$n\" = \"$m\""), 0);
    CHECK_INT(system("test \"$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 build/fixtures/live_merged.ts | head -1)\" = 150"), 0);
    tb_out_free(&o);
    free(v);
    free(a);
}
