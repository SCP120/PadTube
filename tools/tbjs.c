/* JS solver helper (Phase 0 spike of the fallback path; never on the play path): runs one script with QuickJS-NG
 * in its own process and reports time and peak memory. usage: tbjs <script.js> [out.txt] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include "quickjs.h"

static FILE *g_out;

static JSValue js_log(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    for (int i = 0; i < argc; i++) {
        const char *s = JS_ToCString(ctx, argv[i]);
        fprintf(g_out, "%s%s", i ? " " : "", s ? s : "?");
        JS_FreeCString(ctx, s);
    }
    fputc('\n', g_out);
    return JS_UNDEFINED;
}

static double now_ms(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0; }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: tbjs script.js [out.txt]\n"); return 2; }
    g_out = argc > 2 ? fopen(argv[2], "w") : stdout;
    if (!g_out) return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc((size_t)n + 1);
    fread(src, 1, (size_t)n, f);
    src[n] = 0;
    fclose(f);
    double t0 = now_ms();
    JSRuntime *rt = JS_NewRuntime();
    JS_SetMaxStackSize(rt, 4 * 1024 * 1024);
    JSContext *ctx = JS_NewContext(rt);
    JSValue g = JS_GetGlobalObject(ctx), con = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, con, "log", JS_NewCFunction(ctx, js_log, "log", 1));
    JS_SetPropertyStr(ctx, g, "console", con);
    JS_FreeValue(ctx, g);
    JSValue r = JS_Eval(ctx, src, (size_t)n, argv[1], JS_EVAL_TYPE_GLOBAL);
    int rc = 0;
    if (JS_IsException(r)) {
        JSValue e = JS_GetException(ctx);
        const char *s = JS_ToCString(ctx, e);
        fprintf(g_out, "exception: %s\n", s ? s : "?");
        JS_FreeCString(ctx, s);
        JS_FreeValue(ctx, e);
        rc = 1;
    }
    JS_FreeValue(ctx, r);
    double ms = now_ms() - t0;
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    /* ru_maxrss: bytes on Darwin */
    fprintf(g_out, "tbjs: %.0f ms, max rss %.1f MB\n", ms, ru.ru_maxrss / 1048576.0);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    if (g_out != stdout) fclose(g_out);
    return rc;
}

/* The 9.3 SDK armv7 stubs omit memset_pattern16 (clang emits it for fill loops); a local copy links on its own. */
void memset_pattern16(void *b, const void *pattern16, size_t len) {
    volatile unsigned char *d = b; /* volatile: the compiler must not turn this loop back into memset_pattern16 */
    const unsigned char *p = pattern16;
    for (size_t i = 0; i < len; i++) d[i] = p[i & 15];
}
