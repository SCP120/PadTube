/* Text that iOS 6 can draw: Apple Color Emoji on iOS 6 covers the Unicode 6.0 emoji only. Newer emoji (U+1F900 and
 * up, skin tones, ZWJ sequences, tag sequences, U+1F6D0 and up...) draw as empty boxes, so they are removed. */
#ifndef TB_TEXT_H
#define TB_TEXT_H
#include <stddef.h>
/* Filter UTF-8 in place; returns the new length. Text with no 4-byte sequence and no ZWJ is unchanged. */
size_t tb_text_ios6(char *s);
#endif
