#include <string.h>
#include "tb_test.h"
#include "tb_text.h"

/* Golden vectors: owner report 2026-11-12 (titles with new emoji drew empty boxes on iOS 6). */
TB_TEST(test_text_ios6_strips_new_emoji, "BR-TEXT-IOS6") {
    char a[] = "\xF0\x9F\xA4\xAF Mind blown";           /* U+1F92F (Unicode 10): removed, leading space too */
    tb_text_ios6(a);
    CHECK_STR(a, "Mind blown");
    char b[] = "Live \xF0\x9F\x94\xB4 now";               /* U+1F534 red circle (Unicode 6.0): kept */
    tb_text_ios6(b);
    CHECK_STR(b, "Live \xF0\x9F\x94\xB4 now");
    char c[] = "Fam\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9 ily"; /* man ZWJ woman: ZWJ removed, both kept */
    tb_text_ios6(c);
    CHECK_STR(c, "Fam\xF0\x9F\x91\xA8\xF0\x9F\x91\xA9 ily");
    char d[] = "Thumb\xF0\x9F\x91\x8D\xF0\x9F\x8F\xBD!";   /* thumbs up + skin tone (Unicode 8): tone removed */
    tb_text_ios6(d);
    CHECK_STR(d, "Thumb\xF0\x9F\x91\x8D!");
    char e[] = "Ti\xE1\xBA\xBFng Vi\xE1\xBB\x87t";        /* Vietnamese: unchanged */
    tb_text_ios6(e);
    CHECK_STR(e, "Ti\xE1\xBA\xBFng Vi\xE1\xBB\x87t");
}
