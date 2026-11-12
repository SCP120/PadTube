/* YouTube player -> the "preprocessed player" of yt-dlp ejs (D62, option A), made by text operations: no syntax
 * tree, so it fits the A5's memory (the ejs parse needed over 300 MB there, D61). The same steps as ejs 0.8.0
 * preprocessPlayer: the body of the player's (function(g){...})(_yt_player) without its first statement and without
 * top-level calls that are not assignments; every top-level function whose own body has the statement
 * X.y("alr","yes") becomes a candidate; _result.n and _result.sig wrappers (ES5) call all candidates and need one
 * answer. Run the result as ejs does: Function('_result', text)(obj), then obj.n(challenge), obj.sig(challenge). */
#ifndef TB_JSPREP_H
#define TB_JSPREP_H
#include <stddef.h>

/* Returns malloc'd text (NUL-terminated, *out_len bytes), or NULL with a static message in *err.
 * *candidates: how many functions matched (ejs needs at least one). */
char *tb_jsprep(const char *src, size_t len, size_t *out_len, int *candidates, const char **err);
#endif
