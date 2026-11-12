#include "tb_json.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

static yyjson_val *step(yyjson_val *v, const char *k) {
    if (!v || !k) return NULL;
    if (yyjson_is_arr(v)) {
        for (const char *c = k; *c; c++) if (*c < '0' || *c > '9') return NULL;
        return yyjson_arr_get(v, (size_t)atoi(k));
    }
    return yyjson_is_obj(v) ? yyjson_obj_get(v, k) : NULL;
}

static yyjson_val *walk(yyjson_val *v, const char *first, va_list ap) {
    const char *k = first;
    while (k && v) {
        v = step(v, k);
        k = va_arg(ap, const char *);
    }
    return v;
}

yyjson_val *tbj_vget(yyjson_val *v, const char *first, ...) {
    va_list ap;
    va_start(ap, first);
    v = walk(v, first, ap);
    va_end(ap);
    return v;
}

const char *tbj_str(yyjson_val *v, ...) {
    va_list ap;
    va_start(ap, v);
    v = walk(v, va_arg(ap, const char *), ap);
    va_end(ap);
    return yyjson_is_str(v) ? yyjson_get_str(v) : NULL;
}

int64_t tbj_int(yyjson_val *v, ...) {
    va_list ap;
    va_start(ap, v);
    v = walk(v, va_arg(ap, const char *), ap);
    va_end(ap);
    if (yyjson_is_int(v)) return yyjson_get_sint(v);
    if (yyjson_is_real(v)) return (int64_t)yyjson_get_real(v);
    if (yyjson_is_str(v)) return strtoll(yyjson_get_str(v), NULL, 10);
    return 0;
}

int tbj_bool(yyjson_val *v, ...) {
    va_list ap;
    va_start(ap, v);
    v = walk(v, va_arg(ap, const char *), ap);
    va_end(ap);
    return yyjson_is_true(v);
}

char *tbj_text(yyjson_val *v) {
    if (!v) return NULL;
    if (yyjson_is_str(v)) return strdup(yyjson_get_str(v));
    const char *s = tbj_str(v, "simpleText", NULL);
    if (!s) s = tbj_str(v, "content", NULL);
    if (s) return strdup(s);
    yyjson_val *runs = yyjson_obj_get(v, "runs");
    if (!yyjson_is_arr(runs)) return NULL;
    size_t total = 0, i, max;
    yyjson_val *r;
    yyjson_arr_foreach(runs, i, max, r) {
        const char *t = tbj_str(r, "text", NULL);
        if (t) total += strlen(t);
    }
    char *out = malloc(total + 1), *w = out;
    yyjson_arr_foreach(runs, i, max, r) {
        const char *t = tbj_str(r, "text", NULL);
        if (t) { size_t n = strlen(t); memcpy(w, t, n); w += n; }
    }
    *w = 0;
    return out;
}
