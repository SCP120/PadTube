/* Owner rule 2026-11-11: no web page for login. D36: web links open in PadWeb's browser; D46: in the public build
 * (no PadWeb) they open in Safari. So: no web view in PadTube's own code, and both the PadWeb browser and the
 * hand-off to Safari only behind TBLinks. */
#include <stdlib.h>
#include "tb_test.h"
TB_TEST(test_no_web_view_in_app, "BR-LOGIN-NOWEB") {
    CHECK_INT(system("! grep -rqE 'UIWebView|WKWebView' ios/src ios/selftest core"), 0);
    CHECK_INT(system("! grep -rlE 'sharedApplication\\] openURL' ios/src ios/selftest core | grep -vE '^ios/src/TBLinks[.]m$' | grep -q ."), 0);
    CHECK_INT(system("! grep -rlE 'PWBrowserController' ios/src ios/selftest | grep -vE '^ios/src/TBLinks[.][hm]$' | grep -q ."), 0);
}
