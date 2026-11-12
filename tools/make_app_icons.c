/* App icons from one source tile (owner-approved option A: assets/art/v3/a/icon.png, made with Codex): find the
 * tile (not transparent, not near-black), crop to it, scale, cut rounded corners (radius 18 % of the side) to alpha.
 * The art has its own gloss; Info.plist sets UIPrerenderedIcon so iOS adds none. usage: make_app_icons <src> <out dir> */
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

static void out(CGImageRef src, CGRect crop, int size, const char *dir, const char *name) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t)size, (size_t)size, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGFloat r = size * 0.18;
    CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(0, 0, size, size), r, r, NULL);
    CGContextAddPath(c, p);
    CGContextClip(c);
    CGPathRelease(p);
    CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
    CGImageRef part = CGImageCreateWithImageInRect(src, crop);
    CGContextDrawImage(c, CGRectMake(0, 0, size, size), part);
    CGImageRelease(part);
    CGImageRef img = CGBitmapContextCreateImage(c);
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageDestinationRef d = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(d, img, NULL);
    CGImageDestinationFinalize(d);
    CFRelease(d); CFRelease(u); CGImageRelease(img); CGContextRelease(c);
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)argv[1], (CFIndex)strlen(argv[1]), false);
    CGImageSourceRef s = CGImageSourceCreateWithURL(u, NULL);
    CGImageRef src = s ? CGImageSourceCreateImageAtIndex(s, 0, NULL) : NULL;
    if (!src) { fprintf(stderr, "cannot read %s\n", argv[1]); return 1; }
    /* tile bounds: pixels with alpha > 128 and not near-black (the source has black outside the tile) */
    size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    unsigned char *px = calloc(w * h, 4);
    CGContextRef bc = CGBitmapContextCreate(px, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextDrawImage(bc, CGRectMake(0, 0, w, h), src);
    size_t x0 = w, y0 = h, x1 = 0, y1 = 0;
    for (size_t y = 0; y < h; y++)
        for (size_t x = 0; x < w; x++) {
            unsigned char *p = px + (y * w + x) * 4;
            if (p[3] > 128 && p[0] + p[1] + p[2] > 90) {
                if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
            }
        }
    CGContextRelease(bc);
    free(px);
    /* bitmap rows run top-down here; CGImageCreateWithImageInRect uses the same top-left origin */
    size_t side = (x1 - x0 > y1 - y0 ? x1 - x0 : y1 - y0) + 1;
    CGRect crop = CGRectMake(x0, y0, side, side);
    fprintf(stderr, "tile: x %zu-%zu y %zu-%zu (side %zu of %zu)\n", x0, x1, y0, y1, side, w);
    struct { int size; const char *name; } sizes[] = {
        {57, "PTIcon2.png"}, {114, "PTIcon2@2x.png"}, {72, "PTIcon2-72.png"}, {144, "PTIcon2-72@2x.png"},
        {50, "PTIcon2-Small-50.png"}, {100, "PTIcon2-Small-50@2x.png"}, {29, "PTIcon2-Small.png"}, {58, "PTIcon2-Small@2x.png"}};
    for (size_t i = 0; i < sizeof sizes / sizeof sizes[0]; i++) out(src, crop, sizes[i].size, argv[2], sizes[i].name);
    return 0;
}
