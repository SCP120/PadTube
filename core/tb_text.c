#include "tb_text.h"
#include <string.h>

/* Supplementary-plane emoji present in Unicode 6.0 (iOS 6 Apple Color Emoji). Ranges from the Unicode 6.0
 * emoji data (emoji-data.txt, version 1.0), merged where adjacent. */
static const unsigned k_v6[][2] = {
    {0x1F004, 0x1F004}, {0x1F0CF, 0x1F0CF}, {0x1F170, 0x1F251}, {0x1F300, 0x1F320}, {0x1F330, 0x1F335},
    {0x1F337, 0x1F37C}, {0x1F380, 0x1F393}, {0x1F3A0, 0x1F3C4}, {0x1F3C6, 0x1F3CA}, {0x1F3E0, 0x1F3F0},
    {0x1F400, 0x1F43E}, {0x1F440, 0x1F440}, {0x1F442, 0x1F4F7}, {0x1F4F9, 0x1F4FC}, {0x1F500, 0x1F53D},
    {0x1F550, 0x1F567}, {0x1F5FB, 0x1F640}, {0x1F645, 0x1F64F}, {0x1F680, 0x1F6C5}};

static int drawable(unsigned cp) {
    if (cp == 0x200D) return 0;                         /* zero width joiner: newer sequences */
    if (cp >= 0xE0000 && cp <= 0xE007F) return 0;       /* tag characters (flags of regions) */
    if (cp < 0x10000) return 1;
    if (cp >= 0x1F000 && cp <= 0x1FAFF) {
        for (size_t i = 0; i < sizeof k_v6 / sizeof k_v6[0]; i++)
            if (cp >= k_v6[i][0] && cp <= k_v6[i][1]) return 1;
        return 0;
    }
    return 1; /* other planes (CJK extension B and so on): leave to the font fallback */
}

size_t tb_text_ios6(char *s) {
    unsigned char *r = (unsigned char *)s, *w = (unsigned char *)s;
    while (*r) {
        unsigned cp = *r;
        int n = 1;
        if (cp >= 0xF0 && cp < 0xF8) { n = 4; cp &= 7; }
        else if (cp >= 0xE0) { n = 3; cp &= 15; }
        else if (cp >= 0xC0) { n = 2; cp &= 31; }
        int ok = 1;
        for (int i = 1; i < n; i++) {
            if ((r[i] & 0xC0) != 0x80) { ok = 0; n = i; break; }
            cp = cp << 6 | (r[i] & 63);
        }
        if (ok && n > 1 && !drawable(cp)) { r += n; continue; }
        /* a variation selector right after a removed emoji stays harmless (it draws as nothing) */
        memmove(w, r, (size_t)n);
        w += n;
        r += n;
    }
    *w = 0;
    /* drop spaces left at the start by a removed leading emoji */
    unsigned char *b = (unsigned char *)s;
    while (*b == ' ') b++;
    size_t len = (size_t)(w - b);
    if (b != (unsigned char *)s) memmove(s, b, len + 1);
    return len;
}
