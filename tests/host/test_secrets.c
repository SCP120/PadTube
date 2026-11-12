/* NFR-09 / BR-LOGIN-PRIVATE: no OAuth token in tracked files (Google access tokens start "ya29.", refresh tokens "1//0"). */
#include <stdlib.h>
#include "tb_test.h"
TB_TEST(test_no_tokens_in_repo, "BR-LOGIN-PRIVATE") {
    CHECK_INT(system("! git grep -qE 'ya29\\.[0-9A-Za-z_-]{20}|1//0[0-9A-Za-z_-]{30}' -- ':!tests/host/test_secrets.c'"), 0);
}
