/* Owner report 2026-11-12: the Subtitles list started with Arabic (YouTube's order). Golden order below. */
#include <string.h>
#include "tb_test.h"
#include "tb_yt.h"

static void order(tb_ctrack *c, int n, const char *const *pref, int np, char *out, size_t cap) {
    tb_caps_sort(c, n, pref, np);
    out[0] = 0;
    for (int i = 0; i < n; i++) {
        strncat(out, c[i].lang, cap - strlen(out) - 1);
        if (c[i].asr) strncat(out, "*", cap - strlen(out) - 1);
        if (i + 1 < n) strncat(out, ",", cap - strlen(out) - 1);
    }
}

TB_TEST(test_caption_order_device_language_first, "AC-CAP-ORDER") {
    tb_ctrack c[] = {{"u", "ar", "Arabic", 0}, {"u", "de", "German", 0}, {"u", "en", "English (auto-generated)", 1},
                     {"u", "en-GB", "English (United Kingdom)", 0}, {"u", "vi", "Vietnamese", 0}, {"u", "zh-Hans", "Chinese (Simplified)", 0}};
    const char *pref[] = {"vi-VN", "en"};
    char got[128];
    order(c, 6, pref, 2, got, sizeof got);
    CHECK_STR(got, "vi,en-GB,en*,ar,zh-Hans,de");
}

TB_TEST(test_caption_order_english_when_no_device_match, "AC-CAP-ORDER") {
    tb_ctrack c[] = {{"u", "ar", "Arabic", 0}, {"u", "fr", "French", 1}, {"u", "en", "English", 0}, {"u", "fr", "French", 0}};
    const char *pref[] = {"ja"};
    char got[128];
    order(c, 4, pref, 1, got, sizeof got);
    CHECK_STR(got, "en,ar,fr,fr*");
}
