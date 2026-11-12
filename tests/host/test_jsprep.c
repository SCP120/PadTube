/* D62 option A: the ejs "preprocessed player" made by text operations (core/tb_jsprep.c). The C output was
 * byte-identical to an independent Python prototype on 9 real players (7 of them pass ejs's own golden n/sig vectors,
 * docs/STATUS.md); this fixture pins each rule on a small hand-written player. */
#include <stdlib.h>
#include <string.h>
#include "tb_jsprep.h"
#include "tb_test.h"

static const char PLAYER[] =
    "var _yt_player={};(function(g){var window=this;/* c */\n"
    "'use strict';\n"
    "var aa=function(a){return a.split(\"\")}, Wx=function(a,b){var c=new XYZ(a);c.set(\"alr\",\"yes\");return c}, bb=/[}{'\"]/g;\n"
    "Ca(1,2);\n"
    "g.U=function(a){a.set(\"alr\",\"yes\");return a};\n"
    "function Fx(a){if(a){b.c(\"alr\",\"yes\")}return a}\n"
    "function Gx(a){a.k('alr','yes');}\n"
    "Q.prototype.m=function(){return 1/2/3};\n"
    "})(_yt_player);\n";

TB_TEST(test_jsprep_rules, "BR-SOLVER-PREP") {
    size_t n;
    int c;
    const char *err;
    char *o = tb_jsprep(PLAYER, strlen(PLAYER), &n, &c, &err);
    CHECK(o != NULL);
    CHECK_INT(c, 3);                                            /* Wx (var), g.U (assignment), Gx (declaration) */
    CHECK(strstr(o, "var window=this") == NULL);                /* ejs drops the first statement */
    CHECK(strstr(o, "Ca(1,2)") == NULL);                        /* and top-level calls */
    CHECK(strstr(o, "\n'use strict';\n") != NULL);
    CHECK(strstr(o, "bb=/[}{'\"]/g;") != NULL);                 /* braces and quotes inside a regex are not code */
    CHECK(strstr(o, "\nQ.prototype.m=function(){return 1/2/3};") != NULL);   /* division, not a regex */
    CHECK(strstr(o, "var url = (Wx)(") && strstr(o, "var url = (g.U)(") && strstr(o, "var url = (Gx)("));
    CHECK(strstr(o, "var url = (Fx)(") == NULL);                /* its marker is nested in an if block */
    CHECK(strstr(o, "_result.n = (function (_input) {") && strstr(o, "_result.sig = (function (_input) {"));
    CHECK(strncmp(o, "var globalThis = (function () { return this; })()", 49) == 0);   /* iOS 6 has no globalThis */
    CHECK(n >= 16 && strcmp(o + n - 16, "})(_yt_player);\n") == 0);
    free(o);
}

TB_TEST(test_jsprep_refuses_unknown_players, "BR-SOLVER-PREP") {
    size_t n;
    int c;
    const char *err;
    const char *none = "var x=1;";
    CHECK(tb_jsprep(none, strlen(none), &n, &c, &err) == NULL);
    CHECK(err != NULL);
    const char *nomarker = "(function(g){var window=this;var a=function(){return 1};})(_yt_player);";
    CHECK(tb_jsprep(nomarker, strlen(nomarker), &n, &c, &err) == NULL);
    CHECK(strstr(err, "player changed") != NULL);
}
