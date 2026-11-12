/* BR-CAP-NO-TRANSLATE: no auto-translated caption tracks (tlang gives HTTP 429 in 2026, research-features F9). */
#include <stdlib.h>
#include "tb_test.h"
TB_TEST(test_no_translated_captions, "BR-CAP-NO-TRANSLATE") {
    CHECK_INT(system("! grep -rqE 'tlang' core ios/src"), 0);
}
