/* DUC-SET-THEME guards (D39): theme colours come from TBStyle only; the sign-in QR stays black on white. */
#include <stdlib.h>
#include "tb_test.h"

TB_TEST(test_theme_light_colours_only_in_style, "BR-THEME-ONE-PLACE") {
    /* the light content tones of design §7-§9 must not be set directly in a view (they would stay light in Dark) */
    CHECK_INT(system("! grep -rnE 'TBHex\\(0x(E6E6E6|F5F5F5|333333|CFCFCF|E5E5E5|F6F6F6|252525|686868|444444)\\)' "
                     "ios/src --include='*.m' | grep -v '^ios/src/TBStyle.m:' | grep -q ."), 0);
}

TB_TEST(test_theme_qr_black_on_white, "BR-THEME-QR") {
    /* the QR image is drawn white first, then black modules, with no theme colour */
    CHECK_INT(system("grep -A3 'UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), YES, 1)' ios/src/TBAccountController.m "
                     "| grep -q 'whiteColor'"), 0);
    CHECK_INT(system("! sed -n '/qrImage/,/^}/p' ios/src/TBAccountController.m | grep -q 'TBStyle'"), 0);
}
