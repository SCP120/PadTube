/* Small yyjson path helpers. Path arguments end with NULL; an all-digit key indexes an array. */
#ifndef TB_JSON_H
#define TB_JSON_H
#include <stdint.h>
#include "yyjson.h"

yyjson_val *tbj_vget(yyjson_val *v, const char *first, ...);
#define tbj_get(v, ...) tbj_vget((v), __VA_ARGS__)
const char *tbj_str(yyjson_val *v, ...);   /* NULL if missing or not a string */
int64_t tbj_int(yyjson_val *v, ...);       /* numbers and numeric strings; 0 if missing */
int tbj_bool(yyjson_val *v, ...);
/* InnerTube text: {simpleText}, {runs:[{text}]}, {content}, or a plain string. malloc or NULL. */
char *tbj_text(yyjson_val *v);
#endif
