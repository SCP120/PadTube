/* Public app icon (D47): an old TV set on a teal tile, iOS 6 gloss. No red, no play triangle: it must not be
 * confusable with the YouTube logo. Draws a 1024 px master, then each iOS 6 iPad/iPhone size with rounded corners
 * (radius 18 % of the side, as tools/make_app_icons.c). usage: make_public_icon <out dir> */
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

#define M 1024.0

static void rgb(CGContextRef c, double r, double g, double b) { CGContextSetRGBFillColor(c, r, g, b, 1); }

static void vgrad(CGContextRef c, CGRect r, const CGFloat top[4], const CGFloat bottom[4]) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comp[8] = {bottom[0], bottom[1], bottom[2], bottom[3], top[0], top[1], top[2], top[3]};
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comp, NULL, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMaxY(r)), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

static void rounded(CGContextRef c, CGRect r, CGFloat rad) {
    CGPathRef p = CGPathCreateWithRoundedRect(r, rad, rad, NULL);
    CGContextAddPath(c, p);
    CGPathRelease(p);
}

static void master(CGContextRef c) { /* origin bottom left */
    CGRect all = CGRectMake(0, 0, M, M);
    CGContextSaveGState(c);
    CGContextAddRect(c, all); CGContextClip(c);
    vgrad(c, all, (CGFloat[]){0.20, 0.70, 0.72, 1}, (CGFloat[]){0.03, 0.33, 0.40, 1});
    CGContextRestoreGState(c);

    /* antennas: two rods from the top of the set, with balls */
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetRGBStrokeColor(c, 0.12, 0.14, 0.16, 1);
    CGContextSetLineWidth(c, 26);
    CGContextMoveToPoint(c, 512, 760); CGContextAddLineToPoint(c, 380, 905);
    CGContextMoveToPoint(c, 512, 760); CGContextAddLineToPoint(c, 660, 920);
    CGContextStrokePath(c);
    rgb(c, 0.12, 0.14, 0.16);
    CGContextFillEllipseInRect(c, CGRectMake(350, 875, 60, 60));
    CGContextFillEllipseInRect(c, CGRectMake(630, 890, 60, 60));

    /* shadow under the set, then the cabinet (warm orange wood) */
    CGRect body = CGRectMake(150, 190, 724, 580);
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, -22), 40, CGColorCreateGenericRGB(0, 0, 0, 0.45));
    rgb(c, 0.86, 0.50, 0.18);
    rounded(c, body, 90); CGContextFillPath(c);
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    rounded(c, body, 90); CGContextClip(c);
    vgrad(c, body, (CGFloat[]){0.98, 0.66, 0.30, 1}, (CGFloat[]){0.76, 0.40, 0.12, 1});
    CGContextRestoreGState(c);

    /* feet */
    rgb(c, 0.12, 0.14, 0.16);
    rounded(c, CGRectMake(250, 140, 90, 70), 18); CGContextFillPath(c);
    rounded(c, CGRectMake(684, 140, 90, 70), 18); CGContextFillPath(c);

    /* screen: dark bezel, glowing teal glass, scan lines, glare */
    CGRect bezel = CGRectMake(200, 250, 500, 460);
    rgb(c, 0.10, 0.11, 0.12);
    rounded(c, bezel, 70); CGContextFillPath(c);
    CGRect glass = CGRectInset(bezel, 28, 28);
    CGContextSaveGState(c);
    rounded(c, glass, 56); CGContextClip(c);
    vgrad(c, glass, (CGFloat[]){0.62, 0.95, 0.93, 1}, (CGFloat[]){0.16, 0.52, 0.58, 1});
    CGContextSetRGBFillColor(c, 0, 0, 0, 0.10);
    for (CGFloat y = glass.origin.y; y < CGRectGetMaxY(glass); y += 22) CGContextFillRect(c, CGRectMake(glass.origin.x, y, glass.size.width, 8));
    CGContextSetRGBFillColor(c, 1, 1, 1, 0.30);
    CGContextMoveToPoint(c, glass.origin.x, CGRectGetMaxY(glass));
    CGContextAddLineToPoint(c, glass.origin.x + 260, CGRectGetMaxY(glass));
    CGContextAddLineToPoint(c, glass.origin.x, CGRectGetMaxY(glass) - 230);
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    /* control column: two knobs and a speaker grille */
    for (int i = 0; i < 2; i++) {
        CGRect k = CGRectMake(735, 580 - i * 150, 96, 96);
        rgb(c, 0.12, 0.14, 0.16); CGContextFillEllipseInRect(c, k);
        rgb(c, 0.93, 0.89, 0.80); CGContextFillEllipseInRect(c, CGRectInset(k, 16, 16));
        rgb(c, 0.12, 0.14, 0.16); CGContextFillRect(c, CGRectMake(CGRectGetMidX(k) - 6, CGRectGetMidY(k), 12, 34));
    }
    for (int i = 0; i < 4; i++) { rgb(c, 0.45, 0.22, 0.06); rounded(c, CGRectMake(740, 270 + i * 34, 86, 14), 7); CGContextFillPath(c); }

    /* iOS 6 gloss: a light arc over the top half */
    CGContextSaveGState(c);
    CGContextAddRect(c, all); CGContextClip(c);
    CGContextAddEllipseInRect(c, CGRectMake(-420, 470, M + 840, 1100));
    CGContextClip(c);
    CGRect top = CGRectMake(0, 470, M, M - 470);
    vgrad(c, top, (CGFloat[]){1, 1, 1, 0.42}, (CGFloat[]){1, 1, 1, 0.06});
    CGContextRestoreGState(c);
}

static void save(CGImageRef src, int size, const char *dir, const char *name) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t)size, (size_t)size, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGFloat r = size * 0.18;
    rounded(c, CGRectMake(0, 0, size, size), r);
    CGContextClip(c);
    CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
    CGContextDrawImage(c, CGRectMake(0, 0, size, size), src);
    CGImageRef img = CGBitmapContextCreateImage(c);
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageDestinationRef d = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(d, img, NULL);
    if (!CGImageDestinationFinalize(d)) { fprintf(stderr, "cannot write %s\n", path); }
    CFRelease(d); CFRelease(u); CGImageRelease(img); CGContextRelease(c);
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: make_public_icon <out dir>\n"); return 2; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t)M, (size_t)M, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    master(c);
    CGImageRef m = CGBitmapContextCreateImage(c);
    /* the names in ios/Resources/Info.plist; sizes: iPad 72/144, iPhone 57/114, Spotlight 50/100, Settings 29/58 */
    static const struct { const char *name; int size; } out[] = {
        {"PTIcon2.png", 57}, {"PTIcon2@2x.png", 114}, {"PTIcon2-72.png", 72}, {"PTIcon2-72@2x.png", 144},
        {"PTIcon2-Small-50.png", 50}, {"PTIcon2-Small-50@2x.png", 100}, {"PTIcon2-Small.png", 29}, {"PTIcon2-Small@2x.png", 58},
        {"icon-512.png", 512}};
    for (size_t i = 0; i < sizeof out / sizeof out[0]; i++) save(m, out[i].size, argv[1], out[i].name);
    CGImageRelease(m); CGContextRelease(c);
    return 0;
}
