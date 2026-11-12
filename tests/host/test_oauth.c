#include <stdlib.h>
#include "tb_oauth.h"
#include "tb_test.h"

/* Golden vector: the shape of the 2026-11 TV base.js (values replaced). */
TB_TEST(test_oauth_parse_client, "AC-LOGIN-1") {
    const char *js = "var a={x:1},b={clientId:\"123-abc.apps.googleusercontent.com\",Hx:\"SeCrEt_-xyz\",zz:2};";
    tb_oauth_client c;
    CHECK_INT(tb_oauth_parse_client(js, &c), 0);
    CHECK_STR(c.client_id, "123-abc.apps.googleusercontent.com");
    CHECK_STR(c.client_secret, "SeCrEt_-xyz");
    tb_oauth_client_free(&c);
    CHECK(tb_oauth_parse_client("clientId:\"x\";", &c) != 0);
}
