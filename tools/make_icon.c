/* Launch images for PadTube (Mac, CoreGraphics). usage: make_icon <out dir> */
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

static void save(CGContextRef c, const char *dir, const char *name) {
    CGImageRef img = CGBitmapContextCreateImage(c);
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageDestinationRef d = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(d, img, NULL);
    CGImageDestinationFinalize(d);
    CFRelease(d); CFRelease(u); CGImageRelease(img);
}

static CGContextRef ctx(int w, int h) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    return c;
}

static void launch(const char *dir, int w, int h, const char *name) {
    CGContextRef c = ctx(w, h);
    CGContextSetRGBFillColor(c, 0.94, 0.94, 0.94, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    save(c, dir, name);
    CGContextRelease(c);
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : ".";
    /* app icons: assets/icons (Codex art, tools/make_app_icons.c); this tool makes the launch images only */
    launch(dir, 768, 1004, "Default-Portrait~ipad.png");
    launch(dir, 1024, 748, "Default-Landscape~ipad.png");
    return 0;
}
