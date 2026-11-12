/* Host check of the play path for one real video: player request -> local HLS on 127.0.0.1 -> print the URL.
 * Then it waits; an external client (ffmpeg) plays it. Prints the googlevideo bytes fetched every second.
 * usage: hls_probe <videoId> <height> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "tb_hls.h"
#include "tb_http.h"
#include "tb_yt.h"
int main(int argc, char **argv) {
    tb_http_init("/etc/ssl/cert.pem");
    tb_yt_init("build/e2e");
    double t0 = tb_now_ms();
    tb_player p;
    if (tb_yt_player(argv[1], &p) || strcmp(p.status, "OK")) { fprintf(stderr, "player failed\n"); return 1; }
    int want = atoi(argv[2]);
    tb_format *v = NULL, *a = NULL;
    for (int i = 0; i < p.nf; i++) {
        if (strstr(p.f[i].mime, "avc1") && p.f[i].height == want && !v) v = &p.f[i];
        if (strstr(p.f[i].mime, "mp4a.40.2") && !a) a = &p.f[i];
    }
    if (!v || !a) return 1;
    tb_stream_fmt vf = {v->itag, v->url, v->width, v->height, v->bitrate, v->index_end, v->content_length};
    tb_stream_fmt af = {a->itag, a->url, 0, 0, a->bitrate, a->index_end, a->content_length};
    tb_stream *s = tb_stream_new(&vf, 1, &af);
    tb_hls_start();
    int order = 0;
    tb_hls_set(s, &order, 1);
    char url[160];
    tb_hls_url(0, 0, url, sizeof url);
    printf("URL %s (player answer %.0f ms, length %d s)\n", url, tb_now_ms() - t0, p.length_s);
    fflush(stdout);
    for (int i = 0; i < 40; i++) {
        sleep(1);
        tb_stream_stats st;
        tb_stream_get_stats(s, &st);
        printf("t=%2d s: fetched %ld KB, segments %d\n", i + 1, st.bytes_fetched / 1024, st.segments_built);
        fflush(stdout);
    }
    return 0;
}
