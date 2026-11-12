/* Owner bug 2026-11-12: about 30 s of "loading" after a return. A pooled socket that died while the app was
 * suspended gets no reset; the request waited for the full read timeout. Local server: answers the first request on
 * a connection, then stays silent on that connection (a dead peer); a new connection is answered at once. */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "tb_http.h"
#include "tb_test.h"

static int g_port;

static void *conn_thread(void *arg) {
    int fd = (int)(intptr_t)arg;
    char b[4096];
    int served = 0;
    for (;;) {
        ssize_t n = recv(fd, b, sizeof b, 0);
        if (n <= 0) break;
        if (served++ == 0) {
            const char *r = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok";
            send(fd, r, strlen(r), 0);
        }   /* later requests on this connection: no answer, as a socket that died in the background */
    }
    close(fd);
    return NULL;
}

static void *server(void *arg) {
    int ls = (int)(intptr_t)arg;
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) continue;
        pthread_t t;
        pthread_create(&t, NULL, conn_thread, (void *)(intptr_t)fd);
        pthread_detach(t);
    }
    return NULL;
}

static void start_server(void) {
    if (g_port) return;
    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {.sin_family = AF_INET};
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    socklen_t al = sizeof a;
    bind(ls, (struct sockaddr *)&a, sizeof a); listen(ls, 8); getsockname(ls, (struct sockaddr *)&a, &al);
    g_port = ntohs(a.sin_port);
    pthread_t t;
    pthread_create(&t, NULL, server, (void *)(intptr_t)ls);
    pthread_detach(t);
}

TB_TEST(test_reused_dead_socket_retries_fast, "BR-PLAY-BG-PICTURE") {
    start_server();
    tb_http_close_idle();
    char url[64];
    snprintf(url, sizeof url, "http://127.0.0.1:%d/seg", g_port);
    tb_req q = {.url = url, .range_start = -1, .timeout_ms = 20000};   /* the stream's timeout */
    tb_resp r;
    CHECK_INT(tb_http(&q, &r), 200);
    CHECK_INT(r.reused, 0);
    tb_resp_free(&r);
    double t0 = tb_now_ms();
    CHECK_INT(tb_http(&q, &r), 200);                 /* pooled socket is silent: retry on a new one */
    double ms = tb_now_ms() - t0;
    tb_resp_free(&r);
    CHECK(ms >= 2900 && ms < 4500);                  /* about REUSED_FIRST_BYTE_MS, not the 20 s timeout */
}
