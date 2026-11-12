#include "tb_jsprep.h"
#include <stdlib.h>
#include <string.h>

enum { T_NAME, T_STR, T_NUM, T_REGEX, T_PUNCT };
typedef struct { int kind, start, end; } tok;
typedef struct { tok *t; int n, cap; } toks;
typedef struct { char *p; size_t len, cap; } buf;

static void put(buf *b, const char *s, size_t n) {
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 3 / 2 + 4096;
        b->p = realloc(b->p, b->cap);
    }
    memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = 0;
}
static void puts_(buf *b, const char *s) { put(b, s, strlen(s)); }

static const char *SRC;
static int is(const tok *t, const char *s) { size_t n = strlen(s); return (size_t)(t->end - t->start) == n && !memcmp(SRC + t->start, s, n); }
static int ident_char(unsigned char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '$' || c >= 0x80; }

/* tokens before which a "/" starts a regular expression (the prototype's set; any other punctuator except ) ] }) */
static int regex_after(const tok *p) {
    static const char *kw[] = {"return", "typeof", "case", "do", "else", "in", "instanceof", "new", "void", "delete", "throw", NULL};
    if (!p) return 1;
    if (p->kind == T_PUNCT) return !(is(p, ")") || is(p, "]") || is(p, "}")) || is(p, "}");
    if (p->kind == T_NAME) for (int i = 0; kw[i]; i++) if (is(p, kw[i])) return 1;
    return 0;
}

static void tokenize(const char *s, int n, toks *out) {
    static const char *mp[] = {">>>=", "===", "!==", ">>>", "<<=", ">>=", "&&", "||", "==", "!=", "<=", ">=", "++", "--", "+=", "-=",
                               "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", NULL};
    int i = 0;
    while (i < n) {
        unsigned char c = (unsigned char)s[i];
        tok t = {0, i, i};
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
        if (c == 0xE2 && i + 2 < n && (unsigned char)s[i + 1] == 0x80 && ((unsigned char)s[i + 2] == 0xA8 || (unsigned char)s[i + 2] == 0xA9)) { i += 3; continue; }
        if (c == 0xEF && i + 2 < n && (unsigned char)s[i + 1] == 0xBB && (unsigned char)s[i + 2] == 0xBF) { i += 3; continue; }
        if (c == '/' && i + 1 < n && s[i + 1] == '/') { while (i < n && s[i] != '\n') i++; continue; }
        if (c == '/' && i + 1 < n && s[i + 1] == '*') {
            const char *e = strstr(s + i + 2, "*/");
            i = e ? (int)(e - s) + 2 : n;
            continue;
        }
        const tok *prev = out->n ? &out->t[out->n - 1] : NULL;
        if (c == '"' || c == '\'' || c == '`') {
            int j = i + 1;
            while (j < n && s[j] != (char)c) j += s[j] == '\\' ? 2 : 1;
            t.kind = T_STR;
            t.end = j + 1 > n ? n : j + 1;
        } else if (c == '/' && regex_after(prev)) {
            int j = i + 1, cls = 0;
            while (j < n) {
                char d = s[j];
                if (d == '\\') { j += 2; continue; }
                if (d == '[') cls = 1;
                else if (d == ']') cls = 0;
                else if (d == '/' && !cls) break;
                j++;
            }
            j++;
            while (j < n && ident_char((unsigned char)s[j]) && s[j] < 0x7f) j++;
            t.kind = T_REGEX;
            t.end = j > n ? n : j;
        } else if (ident_char(c) && !(c >= '0' && c <= '9')) {
            int j = i + 1;
            while (j < n && ident_char((unsigned char)s[j])) j++;
            t.kind = T_NAME;
            t.end = j;
        } else if ((c >= '0' && c <= '9') || (c == '.' && i + 1 < n && s[i + 1] >= '0' && s[i + 1] <= '9')) {
            int j = i;
            if (c == '0' && j + 1 < n && (s[j + 1] == 'x' || s[j + 1] == 'X')) {
                j += 2;
                while (j < n && ((s[j] >= '0' && s[j] <= '9') || (s[j] >= 'a' && s[j] <= 'f') || (s[j] >= 'A' && s[j] <= 'F'))) j++;
            } else {
                while (j < n && s[j] >= '0' && s[j] <= '9') j++;
                if (j < n && s[j] == '.' && j + 1 < n && s[j + 1] >= '0' && s[j + 1] <= '9') { j++; while (j < n && s[j] >= '0' && s[j] <= '9') j++; }
                if (j < n && (s[j] == 'e' || s[j] == 'E')) {
                    int k = j + 1;
                    if (k < n && (s[k] == '+' || s[k] == '-')) k++;
                    if (k < n && s[k] >= '0' && s[k] <= '9') { j = k; while (j < n && s[j] >= '0' && s[j] <= '9') j++; }
                }
            }
            t.kind = T_NUM;
            t.end = j > i ? j : i + 1;
        } else {
            t.kind = T_PUNCT;
            t.end = i + 1;
            for (int k = 0; mp[k]; k++) {
                size_t l = strlen(mp[k]);
                if (i + (int)l <= n && !memcmp(s + i, mp[k], l)) { t.end = i + (int)l; break; }
            }
        }
        if (out->n == out->cap) { out->cap = out->cap ? out->cap * 2 : 65536; out->t = realloc(out->t, (size_t)out->cap * sizeof *out->t); }
        out->t[out->n++] = t;
        i = t.end;
    }
}

static int opens(const tok *t) { return is(t, "(") || is(t, "[") || is(t, "{"); }
static int closes(const tok *t) { return is(t, ")") || is(t, "]") || is(t, "}"); }

/* is the token run [a, b) an expression statement whose top-level operator is an assignment? */
static int is_assignment(const tok *t, int a, int b) {
    static const char *as[] = {"=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", ">>>=", "&=", "|=", "^=", NULL};
    int depth = 0;
    for (int i = a; i < b; i++) {
        if (opens(&t[i])) depth++;
        else if (closes(&t[i])) depth--;
        else if (depth == 0 && t[i].kind == T_PUNCT) {
            for (int k = 0; as[k]; k++) if (is(&t[i], as[k])) return 1;
            if (is(&t[i], ",") || is(&t[i], "?") || is(&t[i], "&&") || is(&t[i], "||")) return 0;
        }
    }
    return 0;
}

static int str_is(const tok *t, const char *v) {
    size_t n = strlen(v);
    return t->kind == T_STR && (size_t)(t->end - t->start) == n + 2 && !memcmp(SRC + t->start + 1, v, n);
}

/* t[o] is a function's "{": does its own body (not nested) hold the statement X.y("alr","yes")? */
static int body_has_marker(const tok *t, int o, int end) {
    int depth = 0;
    for (int i = o; i < end; i++) {
        if (opens(&t[i])) depth++;
        else if (closes(&t[i])) { depth--; if (depth == 0) return 0; }
        if (depth == 1 && t[i].kind == T_NAME && i + 8 < end && (is(&t[i - 1], "{") || is(&t[i - 1], ";") || is(&t[i - 1], "}")) &&
            is(&t[i + 1], ".") && t[i + 2].kind == T_NAME && is(&t[i + 3], "(") && str_is(&t[i + 4], "alr") && is(&t[i + 5], ",") &&
            str_is(&t[i + 6], "yes") && is(&t[i + 7], ")") && (is(&t[i + 8], ";") || is(&t[i + 8], "}")))
            return 1;
    }
    return 0;
}

static int first_brace(const tok *t, int from, int end) {
    for (int i = from; i < end; i++) if (is(&t[i], "{")) return i;
    return -1;
}

static void add_name(buf *names, int *count, const char *s, size_t n) {
    if (*count) puts_(names, "\n");
    put(names, s, n);
    (*count)++;
}

/* the names ejs extract() would find in the statement [a, b) */
static void candidates(const tok *t, int a, int b, buf *names, int *count) {
    if (is(&t[a], "function") && a + 1 < b && t[a + 1].kind == T_NAME) {
        int o = first_brace(t, a, b);
        if (o >= 0 && body_has_marker(t, o, b)) add_name(names, count, SRC + t[a + 1].start, (size_t)(t[a + 1].end - t[a + 1].start));
    } else if (is(&t[a], "var")) {
        int depth = 0;
        for (int i = a + 1; i < b; i++) {
            if (depth == 0 && t[i].kind == T_NAME && (is(&t[i - 1], "var") || is(&t[i - 1], ",")) && i + 2 < b && is(&t[i + 1], "=") && is(&t[i + 2], "function")) {
                int o = first_brace(t, i + 2, b);
                if (o >= 0 && body_has_marker(t, o, b)) add_name(names, count, SRC + t[i].start, (size_t)(t[i].end - t[i].start));
            }
            if (opens(&t[i])) depth++;
            else if (closes(&t[i])) depth--;
        }
    } else {
        int eq = -1;
        for (int i = a; i < b; i++) if (is(&t[i], "=")) { eq = i; break; }
        if (eq > a && eq + 1 < b && is(&t[eq + 1], "function")) {
            for (int i = a; i < eq; i++) if (!(t[i].kind == T_NAME || is(&t[i], "."))) return;
            int o = first_brace(t, eq + 1, b);
            if (o >= 0 && body_has_marker(t, o, b)) {
                buf nm = {0};
                for (int i = a; i < eq; i++) put(&nm, SRC + t[i].start, (size_t)(t[i].end - t[i].start));
                add_name(names, count, nm.p, nm.len);
                free(nm.p);
            }
        }
    }
}

/* ES2015 built-ins iOS 6's JavaScriptCore lacks and the player uses at load time (D62, A5 "Can't find variable:
 * Symbol"): small ES5 stand-ins, only where missing. Symbol values are unique strings (typeof is "string", so the
 * player takes its non-Symbol paths). */
static const char POLYFILL[] =
    "(function (G) {\n"
    "if (typeof G.Symbol === \"undefined\") { var _n = 0, _reg = {}; var S = function (d) { return \"@@sym:\" + (d === undefined ? \"\" : d) + \":\" + (++_n); };"
    " S.iterator = \"@@iterator\"; S.asyncIterator = \"@@asyncIterator\"; S.toStringTag = \"@@toStringTag\"; S.hasInstance = \"@@hasInstance\";"
    " S.species = \"@@species\"; S.toPrimitive = \"@@toPrimitive\"; S.unscopables = \"@@unscopables\";"
    " S[\"for\"] = function (k) { return _reg[k] || (_reg[k] = \"@@sym:\" + k); }; G.Symbol = S; }\n"
    "function def(o, k, v) { if (typeof o[k] === \"undefined\") Object.defineProperty(o, k, { value: v, configurable: true, writable: true, enumerable: false }); }\n"
    "def(Number, \"MAX_SAFE_INTEGER\", 9007199254740991); def(Number, \"MIN_SAFE_INTEGER\", -9007199254740991); def(Number, \"EPSILON\", Math.pow(2, -52));\n"
    "def(Number, \"isFinite\", function (v) { return typeof v === \"number\" && isFinite(v); });\n"
    "def(Number, \"isNaN\", function (v) { return typeof v === \"number\" && v !== v; });\n"
    "def(Number, \"isInteger\", function (v) { return Number.isFinite(v) && Math.floor(v) === v; });\n"
    "def(Number, \"isSafeInteger\", function (v) { return Number.isInteger(v) && Math.abs(v) <= 9007199254740991; });\n"
    "def(Number, \"parseInt\", parseInt); def(Number, \"parseFloat\", parseFloat);\n"
    "def(Math, \"trunc\", function (v) { return v < 0 ? Math.ceil(v) : Math.floor(v); });\n"
    "def(Math, \"sign\", function (v) { v = +v; return v > 0 ? 1 : v < 0 ? -1 : v; });\n"
    "def(Math, \"imul\", function (a, b) { var al = a & 65535, bl = b & 65535; return (al * bl + (((a >>> 16) * bl + al * (b >>> 16)) << 16 >>> 0)) | 0; });\n"
    "def(Math, \"log2\", function (v) { return Math.log(v) / Math.LN2; }); def(Math, \"log10\", function (v) { return Math.log(v) / Math.LN10; });\n"
    "def(Object, \"assign\", function (t) { for (var i = 1; i < arguments.length; i++) { var s = arguments[i]; if (s != null) for (var k in s) if (Object.prototype.hasOwnProperty.call(s, k)) t[k] = s[k]; } return t; });\n"
    "def(Object, \"is\", function (a, b) { return a === b ? a !== 0 || 1 / a === 1 / b : a !== a && b !== b; });\n"
    "def(Object, \"setPrototypeOf\", function (o, p) { o.__proto__ = p; return o; });\n"
    "def(Object, \"entries\", function (o) { return Object.keys(o).map(function (k) { return [k, o[k]]; }); });\n"
    "def(Object, \"values\", function (o) { return Object.keys(o).map(function (k) { return o[k]; }); });\n"
    "def(Array, \"from\", function (a, f) { var r = []; if (a == null) return r; if (typeof a.length === \"number\") { for (var i = 0; i < a.length; i++) r.push(f ? f(a[i], i) : a[i]); return r; }"
    " if (a.forEach) a.forEach(function (v) { r.push(f ? f(v, r.length) : v); }); return r; });\n"
    "def(Array, \"of\", function () { return Array.prototype.slice.call(arguments); });\n"
    "var AP = Array.prototype, SP = String.prototype;\n"
    "def(AP, \"find\", function (f, t) { for (var i = 0; i < this.length; i++) if (f.call(t, this[i], i, this)) return this[i]; });\n"
    "def(AP, \"findIndex\", function (f, t) { for (var i = 0; i < this.length; i++) if (f.call(t, this[i], i, this)) return i; return -1; });\n"
    "def(AP, \"includes\", function (v, s) { for (var i = s || 0; i < this.length; i++) if (this[i] === v || (v !== v && this[i] !== this[i])) return true; return false; });\n"
    "def(AP, \"fill\", function (v, s, e) { var n = this.length; s = s == null ? 0 : s < 0 ? n + s : s; e = e == null ? n : e < 0 ? n + e : e; for (var i = s; i < e; i++) this[i] = v; return this; });\n"
    "def(SP, \"startsWith\", function (s, p) { p = p || 0; return this.substr(p, s.length) === String(s); });\n"
    "def(SP, \"endsWith\", function (s, e) { var t = String(this); e = e === undefined ? t.length : e; return t.slice(e - String(s).length, e) === String(s); });\n"
    "def(SP, \"includes\", function (s, p) { return String(this).indexOf(s, p) >= 0; });\n"
    "def(SP, \"repeat\", function (n) { var r = \"\", t = String(this); while (n-- > 0) r += t; return r; });\n"
    "def(SP, \"padStart\", function (n, f) { var t = String(this); f = f === undefined ? \" \" : String(f); while (t.length < n) t = f + t; return t.slice(t.length - Math.max(n, String(this).length)); });\n"
    "def(SP, \"padEnd\", function (n, f) { var t = String(this); f = f === undefined ? \" \" : String(f); while (t.length < n) t += f; return t.slice(0, Math.max(n, String(this).length)); });\n"
    "function Coll(isSet) { var C = function (it) { this._k = []; this._v = []; var self = this; if (it && it.forEach) it.forEach(function (x) { if (isSet) self.add(x); else self.set(x[0], x[1]); }); };"
    " C.prototype._i = function (k) { for (var i = 0; i < this._k.length; i++) if (this._k[i] === k || (k !== k && this._k[i] !== this._k[i])) return i; return -1; };"
    " C.prototype.has = function (k) { return this._i(k) >= 0; };"
    " C.prototype[\"delete\"] = function (k) { var i = this._i(k); if (i < 0) return false; this._k.splice(i, 1); this._v.splice(i, 1); return true; };"
    " C.prototype.clear = function () { this._k = []; this._v = []; };"
    " C.prototype.forEach = function (f, t) { for (var i = 0; i < this._k.length; i++) f.call(t, this._v[i], this._k[i], this); };"
    " Object.defineProperty(C.prototype, \"size\", { get: function () { return this._k.length; } });"
    " if (isSet) C.prototype.add = function (k) { if (this._i(k) < 0) { this._k.push(k); this._v.push(k); } return this; };"
    " else { C.prototype.get = function (k) { var i = this._i(k); return i < 0 ? undefined : this._v[i]; }; C.prototype.set = function (k, v) { var i = this._i(k); if (i < 0) { this._k.push(k); this._v.push(v); } else this._v[i] = v; return this; }; }"
    " return C; }\n"
    "if (typeof G.Map === \"undefined\") G.Map = Coll(false); if (typeof G.Set === \"undefined\") G.Set = Coll(true);\n"
    "if (typeof G.WeakMap === \"undefined\") G.WeakMap = Coll(false); if (typeof G.WeakSet === \"undefined\") G.WeakSet = Coll(true);\n"
    /* no timers in a JavaScriptCore C-API context: callbacks run from a queue drained at once (load-time use only) */
    "if (typeof G.Promise === \"undefined\") { var Q = [], busy = false; var run = function (f) { Q.push(f); if (busy) return; busy = true; while (Q.length) { try { Q.shift()(); } catch (e) {} } busy = false; };"
    " var P = function (ex) { var self = this; this._s = 0; this._v = undefined; this._q = [];"
    " var settle = function (st, v) { if (self._s) return; if (st === 1 && v && typeof v.then === \"function\") { v.then(function (x) { settle(1, x); }, function (x) { settle(2, x); }); return; }"
    " self._s = st; self._v = v; var q = self._q; self._q = []; q.forEach(function (h) { run(function () { h(); }); }); };"
    " try { ex(function (v) { settle(1, v); }, function (v) { settle(2, v); }); } catch (e) { settle(2, e); } };"
    " P.prototype.then = function (a, b) { var self = this; return new P(function (res, rej) { var h = function () { var f = self._s === 1 ? a : b;"
    " if (typeof f !== \"function\") { (self._s === 1 ? res : rej)(self._v); return; } try { res(f(self._v)); } catch (e) { rej(e); } };"
    " if (self._s) run(h); else self._q.push(h); }); };"
    " P.prototype[\"catch\"] = function (b) { return this.then(undefined, b); };"
    " P.prototype[\"finally\"] = function (f) { return this.then(function (v) { f(); return v; }, function (e) { f(); throw e; }); };"
    " P.resolve = function (v) { return new P(function (r) { r(v); }); }; P.reject = function (v) { return new P(function (r, j) { j(v); }); };"
    " P.all = function (a) { return new P(function (res, rej) { var out = [], n = a.length; if (!n) res(out); a.forEach(function (x, i) { P.resolve(x).then(function (v) { out[i] = v; if (!--n) res(out); }, rej); }); }); };"
    " P.race = function (a) { return new P(function (res, rej) { a.forEach(function (x) { P.resolve(x).then(res, rej); }); }); };"
    " G.Promise = P; }\n"
    /* iOS 6: typed arrays live in WebCore, not in a bare JavaScriptCore context: array-based stand-ins (no value wrap) */
    "if (typeof G.ArrayBuffer === \"undefined\") { G.ArrayBuffer = function (n) { this.byteLength = n | 0; this._b = []; for (var i = 0; i < this.byteLength; i++) this._b.push(0); };"
    " G.ArrayBuffer.prototype.slice = function (s, e) { var r = new G.ArrayBuffer(0); r._b = this._b.slice(s, e); r.byteLength = r._b.length; return r; }; }\n"
    "['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array', 'Int32Array', 'Uint32Array', 'Float32Array', 'Float64Array'].forEach(function (name, i) {"
    " if (typeof G[name] !== \"undefined\") return; var bytes = [1, 1, 1, 2, 2, 4, 4, 4, 8][i];"
    " var T = function (a, off, len) { var r; if (a instanceof G.ArrayBuffer) r = a._b.slice(off || 0, len === undefined ? undefined : (off || 0) + len);"
    " else if (typeof a === \"number\" || a === undefined) { r = []; for (var k = 0; k < (a | 0); k++) r.push(0); } else r = Array.prototype.slice.call(a);"
    " r.__proto__ = T.prototype; r.buffer = a instanceof G.ArrayBuffer ? a : Object.create(G.ArrayBuffer.prototype); if (!(a instanceof G.ArrayBuffer)) { r.buffer._b = r; r.buffer.byteLength = r.length * bytes; } r.byteOffset = 0; r.byteLength = r.length * bytes; return r; };"
    " T.prototype = Object.create(Array.prototype); T.prototype.constructor = T; T.BYTES_PER_ELEMENT = T.prototype.BYTES_PER_ELEMENT = bytes;"
    " T.prototype.set = function (src, o) { o = o || 0; for (var k = 0; k < src.length; k++) this[o + k] = src[k]; };"
    " T.prototype.subarray = function (s, e) { return new T(Array.prototype.slice.call(this, s, e)); };"
    " T.prototype.slice = function (s, e) { return new T(Array.prototype.slice.call(this, s, e)); };"
    " T.from = function (a) { return new T(Array.from(a)); }; T.of = function () { return new T(arguments); }; G[name] = T; });\n"
    "if (typeof G.DataView === \"undefined\") { G.DataView = function (b) { this.buffer = b; this.byteLength = b.byteLength; this.byteOffset = 0; };"
    " G.DataView.prototype.getUint8 = function (i) { return this.buffer._b[i]; }; G.DataView.prototype.setUint8 = function (i, v) { this.buffer._b[i] = v & 255; }; }\n"
    "})(globalThis);\n";
static const char SETUP[] =
    "var globalThis = (function () { return this; })() || (0, eval)(\"this\");\n"
    "if (typeof globalThis.XMLHttpRequest === \"undefined\") { globalThis.XMLHttpRequest = { prototype: {} }; }\n"
    "if (typeof URL === \"undefined\") { globalThis.location = { hash: \"\", host: \"www.youtube.com\", hostname: \"www.youtube.com\", "
    "href: \"https://www.youtube.com/watch?v=yt-dlp-wins\", origin: \"https://www.youtube.com\", password: \"\", pathname: \"/watch\", "
    "port: \"\", protocol: \"https:\", search: \"?v=yt-dlp-wins\", username: \"\" }; }\n"
    "else { globalThis.location = new URL(\"https://www.youtube.com/watch?v=yt-dlp-wins\"); }\n"
    "if (typeof globalThis.document === \"undefined\") { globalThis.document = Object.create(null); }\n"
    "if (typeof globalThis.navigator === \"undefined\") { globalThis.navigator = Object.create(null); }\n"
    "if (typeof globalThis.self === \"undefined\") { globalThis.self = globalThis; }\n"
    "if (typeof globalThis.window === \"undefined\") { globalThis.window = globalThis; }\n";

static void solver(buf *b, const char *name) {
    puts_(b, "(function (_o) { var sig = _o.sig, n = _o.n; var url = (");
    puts_(b, name);
    puts_(b, ")(\"https://youtube.com/watch?v=yt-dlp-wins\", \"s\", sig ? encodeURIComponent(sig) : undefined); url.set(\"n\", n);"
             " var proto = Object.getPrototypeOf(url); var keys = Object.keys(proto).concat(Object.getOwnPropertyNames(proto));"
             " for (var _k = 0; _k < keys.length; _k++) { var key = keys[_k]; if ([\"constructor\", \"set\", \"get\", \"clone\"].indexOf(key) < 0) { url[key](); break; } }"
             " var s = url.get(\"s\"), nn = url.get(\"n\"); return { sig: s ? decodeURIComponent(s) : null, n: nn != null ? nn : null }; })");
}

static void multi(buf *b, const char *field, const char *names) {
    puts_(b, "_result.");
    puts_(b, field);
    puts_(b, " = (function (_input) { var _results = [], errors = [], _g = [");
    const char *p = names;
    int first = 1;
    while (p && *p) {
        const char *e = strchr(p, '\n');
        size_t l = e ? (size_t)(e - p) : strlen(p);
        char *nm = strndup(p, l);
        if (!first) puts_(b, ", ");
        first = 0;
        puts_(b, "function (");
        puts_(b, field);
        puts_(b, ") { return ");
        solver(b, nm);
        puts_(b, "({ ");
        puts_(b, field);
        puts_(b, ": ");
        puts_(b, field);
        puts_(b, " }).");
        puts_(b, field);
        puts_(b, "; }");
        free(nm);
        p = e ? e + 1 : NULL;
    }
    puts_(b, "]; for (var _i = 0; _i < _g.length; _i++) { try { var _r = _g[_i](_input); if (_results.indexOf(_r) < 0) _results.push(_r); } catch (e) { errors.push(e); } }"
             " if (!_results.length) { throw \"no solutions: \" + errors.join(\", \"); }"
             " if (_results.length !== 1) { throw \"invalid solutions: \" + JSON.stringify(_results); }"
             " return _results[0]; });");
}

static int starts_statement_kw(const tok *t) {
    static const char *kw[] = {"var", "function", "if", "try", "for", "while", "do", "switch", "return", "throw", NULL};
    for (int k = 0; kw[k]; k++) if (is(t, kw[k])) return 1;
    return 0;
}

char *tb_jsprep(const char *src, size_t len, size_t *out_len, int *candidates_out, const char **err) {
    *err = NULL;
    *candidates_out = 0;
    SRC = src;
    toks T = {0};
    tokenize(src, (int)len, &T);
    tok *t = T.t;
    int k = -1;
    for (int i = 0; i + 4 < T.n; i++)
        if (is(&t[i], "function") && is(&t[i + 1], "(") && is(&t[i + 3], ")") && is(&t[i + 4], "{")) { k = i; break; }
    if (k < 0) { free(T.t); *err = "no (function(g){...}) in the player"; return NULL; }
    buf out = {0}, names = {0};
    int count = 0;
    puts_(&out, SETUP);
    puts_(&out, POLYFILL);
    puts_(&out, "\n");
    put(&out, src, (size_t)t[k + 4].end);
    int depth = 0, a = k + 5, nst = 0, i = k + 5, tail = -1;
    for (; i < T.n; i++) {
        int end_here = 0;
        if (depth == 0 && is(&t[i], "}")) { tail = i; end_here = 1; }
        else {
            if (opens(&t[i])) depth++;
            else if (closes(&t[i])) {
                depth--;
                if (depth == 0 && is(&t[i], "}") &&
                    (is(&t[a], "function") || is(&t[a], "if") || is(&t[a], "try") || is(&t[a], "for") || is(&t[a], "while") || is(&t[a], "do") || is(&t[a], "switch")) &&
                    !(i + 1 < T.n && (is(&t[i + 1], "else") || is(&t[i + 1], "catch") || is(&t[i + 1], "finally") || is(&t[i + 1], "while"))))
                    end_here = 2;
            } else if (depth == 0 && is(&t[i], ";")) end_here = 2;
        }
        if (end_here) {
            int b = end_here == 1 ? i : i + 1;   /* statement [a, b) */
            if (b > a) {
                nst++;
                if (nst > 1) {   /* ejs drops the first statement (var window=this;) */
                    int expr = !starts_statement_kw(&t[a]);
                    int keep = !expr || (t[a].kind == T_STR && b - a <= 2) || is_assignment(t, a, b);
                    if (keep) {
                        put(&out, "\n", 1);
                        put(&out, src + t[a].start, (size_t)(t[b - 1].end - t[a].start));
                        if (!(is(&t[b - 1], ";") || is(&t[b - 1], "}"))) put(&out, ";", 1);
                        candidates(t, a, b, &names, &count);
                    }
                }
            }
            a = i + 1;
            if (end_here == 1) break;
        }
    }
    if (tail < 0) { free(T.t); free(out.p); free(names.p); *err = "no end of the player body"; return NULL; }
    if (!count) { free(T.t); free(out.p); free(names.p); *err = "no n/sig function found (the player changed)"; return NULL; }
    puts_(&out, "\n");
    multi(&out, "n", names.p);
    puts_(&out, "\n");
    multi(&out, "sig", names.p);
    puts_(&out, "\n");
    put(&out, src + t[tail].start, len - (size_t)t[tail].start);
    free(T.t);
    free(names.p);
    *candidates_out = count;
    *out_len = out.len;
    return out.p;
}
