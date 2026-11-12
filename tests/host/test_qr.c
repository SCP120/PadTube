/* QR code for the sign-in screen (iOS 6 has no CIQRCodeGenerator). Golden values frozen on 2026-11-11. */
#include "qrcodegen.h"
#include "tb_test.h"

TB_TEST(test_qr_device_url, "AC-LOGIN-7") {
    uint8_t qr[qrcodegen_BUFFER_LEN_MAX], tmp[qrcodegen_BUFFER_LEN_MAX];
    CHECK(qrcodegen_encodeText("https://www.google.com/device", tmp, qr, qrcodegen_Ecc_MEDIUM, qrcodegen_VERSION_MIN,
                               qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true));
    int n = qrcodegen_getSize(qr);
    CHECK_INT(n, 29); /* version 3 (29 bytes at ECC level M) */
    unsigned h = 2166136261u; /* FNV-1a over the modules: any change in the encoder or the text shows here */
    int dark = 0;
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++) { int m = qrcodegen_getModule(qr, x, y); dark += m; h = (h ^ (unsigned)m) * 16777619u; }
    CHECK(qrcodegen_getModule(qr, 0, 0) && qrcodegen_getModule(qr, 6, 6) && !qrcodegen_getModule(qr, 7, 7)); /* finder pattern */
    CHECK_INT(dark, 414);
    CHECK_INT(h, 846248851u);
}
