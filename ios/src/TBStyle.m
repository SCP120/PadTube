#import "TBStyle.h"

UIColor *TBHex(unsigned v) {
    return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1];
}
/* Fonts are cached by size: a name lookup per label showed in grid cell creation stalls (R1, 2026-11-12).
 * Main thread and background (link styling) both call these, so the cache has a lock. */
static UIFont *font(NSString *name, CGFloat s, BOOL bold) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    static NSLock *lock;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; lock = [NSLock new]; });
    NSString *key = [NSString stringWithFormat:@"%@%.1f", name, s];
    [lock lock];
    UIFont *f = cache[key];
    if (!f) {
        f = [UIFont fontWithName:name size:s] ?: (bold ? [UIFont boldSystemFontOfSize:s] : [UIFont systemFontOfSize:s]);
        cache[key] = f;
    }
    [lock unlock];
    return f;
}
UIFont *TBFont(CGFloat s) { return font(@"HelveticaNeue", s, NO); }
UIFont *TBFontBold(CGFloat s) { return font(@"HelveticaNeue-Bold", s, YES); }

NSString *const TBThemeChanged = @"TBThemeChanged";
static NSMutableDictionary *g_cache;
static int g_dark = -1;   /* -1: not read yet */

static BOOL isDark(void) {
    if (g_dark < 0) g_dark = [[NSUserDefaults standardUserDefaults] boolForKey:@"TBDark"] ? 1 : 0;
    return g_dark == 1;
}
/* one colour per theme */
static UIColor *T(unsigned light, unsigned dark) { return TBHex(isDark() ? dark : light); }

static UIImage *cached(NSString *key, UIImage * (^make)(void)) {
    if (!g_cache) g_cache = [NSMutableDictionary dictionary];
    key = [key stringByAppendingString:isDark() ? @".d" : @".l"];
    UIImage *i = g_cache[key];
    if (!i) { i = make(); if (i) g_cache[key] = i; }
    return i;
}

static void fill(CGContextRef c, unsigned rgb, CGRect r) { [TBHex(rgb) setFill]; CGContextFillRect(c, r); }

static void vgradient(CGContextRef c, CGRect r, unsigned top, unsigned bottom, CGFloat alphaTop, CGFloat alphaBottom) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8] = {((top >> 16) & 255) / 255.0, ((top >> 8) & 255) / 255.0, (top & 255) / 255.0, alphaTop,
                        ((bottom >> 16) & 255) / 255.0, ((bottom >> 8) & 255) / 255.0, (bottom & 255) / 255.0, alphaBottom};
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextSaveGState(c);
    CGContextClipToRect(c, r);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, r.origin.y), CGPointMake(0, CGRectGetMaxY(r)), 0);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

static UIImage *draw(CGSize s, BOOL opaque, UIEdgeInsets caps, void (^body)(CGContextRef c)) {
    UIGraphicsBeginImageContextWithOptions(s, opaque, 1);
    body(UIGraphicsGetCurrentContext());
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [i resizableImageWithCapInsets:caps resizingMode:UIImageResizingModeStretch];
}

@implementation TBStyle

+ (BOOL)dark { return isDark(); }
+ (void)setDark:(BOOL)dark {
    if (dark == isDark()) return;
    [[NSUserDefaults standardUserDefaults] setBool:dark forKey:@"TBDark"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    g_dark = dark ? 1 : 0;
    [g_cache removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBThemeChanged object:nil];
}
+ (UIColor *)contentBackground { return T(0xE6E6E6, 0x1B1B1B); }
+ (UIColor *)cardFill { return T(0xF5F5F5, 0x2A2A2A); }
+ (UIColor *)text { return T(0x333333, 0xE4E4E4); }
+ (UIColor *)secondary { return T(0x666666, 0xA8A8A8); }
+ (UIColor *)tertiary { return T(0x999999, 0x7E7E7E); }
+ (UIColor *)placeholder { return T(0xCFCFCF, 0x3A3A3A); }
+ (UIColor *)rule { return T(0xE5E5E5, 0x333333); }
+ (UIColor *)ruleLight { return T(0xFFFFFF, 0x151515); }
+ (UIColor *)buttonText { return T(0x444444, 0xE0E0E0); }
+ (UIColor *)relatedFill { return T(0xF6F6F6, 0x2E2E2E); }
+ (UIColor *)relatedTitle { return T(0x252525, 0xE4E4E4); }
+ (UIColor *)relatedMeta { return T(0x686868, 0xA0A0A0); }
+ (UIColor *)popupFill { return T(0xFFFFFF, 0x2A2A2A); }
+ (UIColor *)popupRule { return T(0xDDDDDD, 0x3A3A3A); }
+ (UIColor *)panel { return T(0x363636, 0x232323); }
+ (UIColor *)guideRow { return TBHex(0x383838); }
+ (UIColor *)guideText { return TBHex(0xAAAAAA); }
+ (UIColor *)link { return T(0x3361CC, 0x7FA7F2); }

/* §5: 1 px #4E4E4E top line, #313131 / #2A2A2A / #232323 steps, 1 px black bottom line. */
+ (UIImage *)headerImage {
    return cached(@"header", ^{
        return draw(CGSizeMake(4, 44), YES, UIEdgeInsetsMake(43, 0, 1, 0), ^(CGContextRef c) {
            fill(c, 0x4E4E4E, CGRectMake(0, 0, 4, 1));
            vgradient(c, CGRectMake(0, 1, 4, 42), 0x313131, 0x232323, 1, 1);
            fill(c, 0x000000, CGRectMake(0, 43, 4, 1));
        });
    });
}

+ (UIImage *)guideHeaderImage {
    return cached(@"gheader", ^{
        return draw(CGSizeMake(4, 44), YES, UIEdgeInsetsMake(43, 0, 1, 0), ^(CGContextRef c) {
            vgradient(c, CGRectMake(0, 0, 4, 43), 0x363636, 0x2F2F2F, 1, 1);
            fill(c, 0x191919, CGRectMake(0, 43, 4, 1));
        });
    });
}

/* §6: section header 22 pt, top #575757, fill #414141 -> #494949, bottom #313131. */
+ (UIImage *)sectionImage {
    return cached(@"section", ^{
        return draw(CGSizeMake(4, 22), YES, UIEdgeInsetsMake(1, 0, 1, 0), ^(CGContextRef c) {
            fill(c, 0x575757, CGRectMake(0, 0, 4, 1));
            vgradient(c, CGRectMake(0, 1, 4, 20), 0x414141, 0x494949, 1, 1);
            fill(c, 0x313131, CGRectMake(0, 21, 4, 1));
        });
    });
}

/* §7.1: card fill #F5F5F5, 1 px #D8D8D8 left/right, bottom #BEBEBE then #D9D9D9, square corners. */
+ (UIImage *)cardImage {
    return cached(@"card", ^{
        return draw(CGSizeMake(6, 6), YES, UIEdgeInsetsMake(1, 1, 2, 1), ^(CGContextRef c) {
            BOOL d = isDark();
            fill(c, d ? 0x1B1B1B : 0xE6E6E6, CGRectMake(0, 0, 6, 6));
            fill(c, d ? 0x2A2A2A : 0xF5F5F5, CGRectMake(1, 0, 4, 4));
            fill(c, d ? 0x333333 : 0xD8D8D8, CGRectMake(0, 0, 1, 4));
            fill(c, d ? 0x333333 : 0xD8D8D8, CGRectMake(5, 0, 1, 4));
            fill(c, d ? 0x111111 : 0xBEBEBE, CGRectMake(0, 4, 6, 1));
            fill(c, d ? 0x1B1B1B : 0xD9D9D9, CGRectMake(0, 5, 6, 1));
        });
    });
}

/* §7.3: related card #F6F6F6, 1 px white top highlight, 2 px #2C2C2C below. */
+ (UIImage *)smallCardImage {
    return cached(@"scard", ^{
        return draw(CGSizeMake(4, 6), YES, UIEdgeInsetsMake(1, 0, 2, 0), ^(CGContextRef c) {
            BOOL d = isDark();
            fill(c, d ? 0x3A3A3A : 0xFFFFFF, CGRectMake(0, 0, 4, 1));
            fill(c, d ? 0x2E2E2E : 0xF6F6F6, CGRectMake(0, 1, 4, 3));
            fill(c, d ? 0x151515 : 0x2C2C2C, CGRectMake(0, 4, 4, 2));
        });
    });
}

/* §5 search field: pill r14, fill #4D4D4D, inner top shade #434343, bottom highlight #585858. */
+ (UIImage *)searchFieldImage {
    return cached(@"search", ^{
        return draw(CGSizeMake(30, 28), NO, UIEdgeInsetsMake(14, 14, 13, 14), ^(CGContextRef c) {
            [TBHex(0x585858) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 1, 30, 27) cornerRadius:14] fill];
            [TBHex(0x434343) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 30, 27) cornerRadius:14] fill];
            [TBHex(0x4D4D4D) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 1, 30, 26) cornerRadius:13] fill];
        });
    });
}

/* §8.4 light button: #FCFCFC -> #E1E3E7, 1 px #BCBBBC border, 1 px white under the bottom, r2. */
+ (UIImage *)lightButtonImage:(BOOL)pressed {
    return cached(pressed ? @"lbtn1" : @"lbtn0", ^{
        return draw(CGSizeMake(10, 30), NO, UIEdgeInsetsMake(4, 4, 4, 4), ^(CGContextRef c) {
            BOOL d = isDark();
            [TBHex(d ? 0x2A2A2A : 0xFFFFFF) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 1, 10, 29) cornerRadius:2] fill];
            [TBHex(d ? 0x151515 : 0xBCBBBC) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 10, 29) cornerRadius:2] fill];
            UIBezierPath *in = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, 8, 27) cornerRadius:1.5];
            CGContextSaveGState(c);
            [in addClip];
            if (pressed) vgradient(c, CGRectMake(1, 1, 8, 27), d ? 0x2E2E2E : 0xD5D7DB, d ? 0x404040 : 0xEDEDED, 1, 1);
            else vgradient(c, CGRectMake(1, 1, 8, 27), d ? 0x4A4A4A : 0xFCFCFC, d ? 0x383838 : 0xE1E3E7, 1, 1);
            CGContextRestoreGState(c);
        });
    });
}

/* §8.3 tab bar: top #5D5D5D, #474747 -> #383838, bottom #1D1D1D then #8A8A8A. */
+ (UIImage *)tabBarImage {
    return cached(@"tabbar", ^{
        return draw(CGSizeMake(4, 44), YES, UIEdgeInsetsMake(1, 0, 2, 0), ^(CGContextRef c) {
            fill(c, 0x5D5D5D, CGRectMake(0, 0, 4, 1));
            vgradient(c, CGRectMake(0, 1, 4, 41), 0x474747, 0x383838, 1, 1);
            fill(c, 0x1D1D1D, CGRectMake(0, 42, 4, 1));
            fill(c, 0x8A8A8A, CGRectMake(0, 43, 4, 1));
        });
    });
}

/* §8.3 segments: selected inset #1A1A1A -> #282828; normal flat #363636 with #252525 / #232323 lines. */
+ (UIImage *)segmentImage:(BOOL)sel {
    return cached(sel ? @"seg1" : @"seg0", ^{
        return draw(CGSizeMake(6, 30), YES, UIEdgeInsetsMake(2, 2, 2, 2), ^(CGContextRef c) {
            fill(c, 0x232323, CGRectMake(0, 0, 6, 30));
            if (sel) { fill(c, 0x131313, CGRectMake(1, 1, 4, 1)); vgradient(c, CGRectMake(1, 2, 4, 27), 0x1A1A1A, 0x282828, 1, 1); }
            else { fill(c, 0x252525, CGRectMake(1, 1, 4, 1)); fill(c, 0x363636, CGRectMake(1, 2, 4, 26)); fill(c, 0x232323, CGRectMake(1, 28, 4, 1)); }
        });
    });
}

/* §8.2 control bar: #2A2A2A at 73% -> #1E1E1E at 76% over the video. */
+ (UIImage *)controlBarImage {
    return cached(@"ctrl", ^{
        return draw(CGSizeMake(4, 51), NO, UIEdgeInsetsMake(0, 0, 0, 0), ^(CGContextRef c) {
            vgradient(c, CGRectMake(0, 0, 4, 51), 0x2A2A2A, 0x1E1E1E, 0.73, 0.76);
        });
    });
}

/* §8.2 track: played red #D9000E -> #7D0109; buffered #808080; unplayed #201F21; 11 pt high. */
+ (UIImage *)trackImage:(int)kind {
    return cached([NSString stringWithFormat:@"track%d", kind], ^{
        return draw(CGSizeMake(6, 11), NO, UIEdgeInsetsMake(0, 2, 0, 2), ^(CGContextRef c) {
            if (kind == 0) vgradient(c, CGRectMake(0, 0, 6, 11), 0xD9000E, 0x7D0109, 1, 1);
            else fill(c, kind == 1 ? 0x808080 : 0x201F21, CGRectMake(0, 0, 6, 11));
        });
    });
}

/* §8.2 knob: 24 pt circle, #F6F6F6 / #BABABA / #FDFDFD, 1 px dark outline. */
+ (UIImage *)knobImage {
    return cached(@"knob", ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 1);
        CGContextRef c = UIGraphicsGetCurrentContext();
        [TBHex(0x202020) setFill];
        CGContextFillEllipseInRect(c, CGRectMake(0, 0, 24, 24));
        CGContextAddEllipseInRect(c, CGRectMake(1, 1, 22, 22));
        CGContextClip(c);
        vgradient(c, CGRectMake(1, 1, 22, 11), 0xF6F6F6, 0xBABABA, 1, 1);
        vgradient(c, CGRectMake(1, 12, 22, 11), 0xBABABA, 0xFDFDFD, 1, 1);
        UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return i;
    });
}

+ (UIImage *)badgeImage {
    return cached(@"badge", ^{
        return draw(CGSizeMake(10, 26), NO, UIEdgeInsetsMake(4, 4, 4, 4), ^(CGContextRef c) {
            [TBHex(0x000000) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 10, 26) cornerRadius:3] fill];
            CGContextSaveGState(c);
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, 8, 24) cornerRadius:2.5] addClip];
            vgradient(c, CGRectMake(1, 1, 8, 24), 0xDBDBDB, 0xAEAEAE, 1, 1);
            fill(c, 0xFFFFFF, CGRectMake(1, 1, 8, 1));
            CGContextRestoreGState(c);
        });
    });
}

+ (void)styleShadowLabel:(UILabel *)l {
    l.shadowColor = [UIColor blackColor];
    l.shadowOffset = CGSizeMake(0, -1);
}

/* ---------- icons (our own drawings, §10.3) ---------- */

static void star(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat r) {
    for (int i = 0; i < 10; i++) {
        CGFloat a = (CGFloat)(-M_PI / 2 + i * M_PI / 5), rr = i % 2 ? r * 0.42 : r;
        CGPoint p = CGPointMake(cx + rr * (CGFloat)cos(a), cy + rr * (CGFloat)sin(a));
        if (i == 0) CGContextMoveToPoint(c, p.x, p.y); else CGContextAddLineToPoint(c, p.x, p.y);
    }
    CGContextClosePath(c);
    CGContextFillPath(c);
}

static void thumb(CGContextRef c, CGFloat s, BOOL down) {
    CGContextSaveGState(c);
    if (down) { CGContextTranslateCTM(c, 0, s); CGContextScaleCTM(c, 1, -1); }
    CGFloat k = s / 16;
    CGContextFillRect(c, CGRectMake(1 * k, 7 * k, 3 * k, 8 * k));        /* cuff */
    CGContextMoveToPoint(c, 5 * k, 7 * k);
    CGContextAddLineToPoint(c, 8 * k, 1.5 * k);
    CGContextAddLineToPoint(c, 9.5 * k, 2 * k);
    CGContextAddLineToPoint(c, 9 * k, 6 * k);
    CGContextAddLineToPoint(c, 14.5 * k, 6 * k);
    CGContextAddLineToPoint(c, 15 * k, 7.5 * k);
    CGContextAddLineToPoint(c, 13.5 * k, 15 * k);
    CGContextAddLineToPoint(c, 5 * k, 15 * k);
    CGContextClosePath(c);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
}

+ (UIImage *)icon:(NSString *)n size:(CGFloat)s color:(UIColor *)tint {
    NSString *key = [NSString stringWithFormat:@"i.%@.%.0f.%@", n, s, tint.description];
    return cached(key, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        [tint setFill];
        [tint setStroke];
        CGFloat k = s / 26;
        CGContextSetLineCap(c, kCGLineCapRound);
        CGContextSetLineJoin(c, kCGLineJoinRound);
        if ([n isEqualToString:@"menu"]) { /* §5: three engraved bars */
            for (int i = 0; i < 3; i++) {
                CGFloat y = 2 * k + i * 8 * k;
                fill(c, 0x000000, CGRectMake(0, y, s, 1));
                fill(c, 0x363636, CGRectMake(0, y + 1, s, 3 * k));
                fill(c, 0x000000, CGRectMake(0, y + 1 + 3 * k, s, 1));
                fill(c, 0x555555, CGRectMake(0, y + 2 + 3 * k, s, 1));
            }
        } else if ([n isEqualToString:@"back"]) {
            CGContextSetLineWidth(c, 3 * k);
            CGContextMoveToPoint(c, 23 * k, 13 * k); CGContextAddLineToPoint(c, 4 * k, 13 * k);
            CGContextMoveToPoint(c, 12 * k, 5 * k); CGContextAddLineToPoint(c, 4 * k, 13 * k); CGContextAddLineToPoint(c, 12 * k, 21 * k);
            CGContextStrokePath(c);
        } else if ([n isEqualToString:@"search"]) {
            CGContextSetLineWidth(c, 2.4 * k);
            CGContextStrokeEllipseInRect(c, CGRectMake(3 * k, 3 * k, 14 * k, 14 * k));
            CGContextSetLineWidth(c, 3.4 * k);
            CGContextMoveToPoint(c, 15 * k, 15 * k); CGContextAddLineToPoint(c, 23 * k, 23 * k);
            CGContextStrokePath(c);
        } else if ([n isEqualToString:@"home"]) {
            CGContextMoveToPoint(c, 13 * k, 3 * k); CGContextAddLineToPoint(c, 25 * k, 13 * k); CGContextAddLineToPoint(c, 21 * k, 13 * k);
            CGContextAddLineToPoint(c, 21 * k, 24 * k); CGContextAddLineToPoint(c, 15 * k, 24 * k); CGContextAddLineToPoint(c, 15 * k, 17 * k);
            CGContextAddLineToPoint(c, 11 * k, 17 * k); CGContextAddLineToPoint(c, 11 * k, 24 * k); CGContextAddLineToPoint(c, 5 * k, 24 * k);
            CGContextAddLineToPoint(c, 5 * k, 13 * k); CGContextAddLineToPoint(c, 1 * k, 13 * k); CGContextClosePath(c);
            CGContextFillPath(c);
        } else if ([n isEqualToString:@"subs"]) { /* stacked frames with a play mark */
            CGContextFillRect(c, CGRectMake(3 * k, 9 * k, 20 * k, 15 * k));
            CGContextFillRect(c, CGRectMake(5 * k, 6 * k, 16 * k, 2 * k));
            CGContextFillRect(c, CGRectMake(7 * k, 3 * k, 12 * k, 2 * k));
            [TBHex(0x383838) setFill];
            CGContextMoveToPoint(c, 11 * k, 12 * k); CGContextAddLineToPoint(c, 17 * k, 16.5 * k); CGContextAddLineToPoint(c, 11 * k, 21 * k);
            CGContextFillPath(c);
        } else if ([n isEqualToString:@"history"] || [n isEqualToString:@"later"]) { /* clock face */
            CGContextSetLineWidth(c, 2.2 * k);
            CGContextStrokeEllipseInRect(c, CGRectMake(3 * k, 3 * k, 20 * k, 20 * k));
            CGContextMoveToPoint(c, 13 * k, 7 * k); CGContextAddLineToPoint(c, 13 * k, 13 * k);
            CGContextAddLineToPoint(c, [n isEqualToString:@"later"] ? 18 * k : 9 * k, 16 * k);
            CGContextStrokePath(c);
        } else if ([n isEqualToString:@"playlist"]) {
            for (int i = 0; i < 3; i++) CGContextFillRect(c, CGRectMake(3 * k, (5 + i * 6) * k, 13 * k, 2.4 * k));
            CGContextMoveToPoint(c, 18 * k, 14 * k); CGContextAddLineToPoint(c, 24 * k, 18 * k); CGContextAddLineToPoint(c, 18 * k, 22 * k);
            CGContextFillPath(c);
        } else if ([n isEqualToString:@"like"] || [n isEqualToString:@"liked"]) {
            thumb(c, s, NO);
        } else if ([n isEqualToString:@"dislike"]) {
            thumb(c, s, YES);
        } else if ([n isEqualToString:@"star"]) {
            star(c, 13 * k, 14 * k, 11 * k);
        } else if ([n isEqualToString:@"gear"]) {
            for (int i = 0; i < 8; i++) {
                CGContextSaveGState(c);
                CGContextTranslateCTM(c, 13 * k, 13 * k);
                CGContextRotateCTM(c, (CGFloat)(i * M_PI / 4));
                CGContextFillRect(c, CGRectMake(-2.2 * k, -12 * k, 4.4 * k, 6 * k));
                CGContextRestoreGState(c);
            }
            CGContextFillEllipseInRect(c, CGRectMake(5 * k, 5 * k, 16 * k, 16 * k));
            CGContextSetBlendMode(c, kCGBlendModeClear);
            CGContextFillEllipseInRect(c, CGRectMake(10 * k, 10 * k, 6 * k, 6 * k));
        } else if ([n isEqualToString:@"account"]) {
            CGContextFillEllipseInRect(c, CGRectMake(8 * k, 2 * k, 10 * k, 10 * k));
            CGContextFillEllipseInRect(c, CGRectMake(3 * k, 14 * k, 20 * k, 18 * k));
        } else if ([n isEqualToString:@"shorts"]) { /* a tall 9:16 frame with a play mark (guide row, D53) */
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7 * k, 2 * k, 12 * k, 22 * k) cornerRadius:3 * k] fill];
            CGContextSetBlendMode(c, kCGBlendModeClear);
            CGContextMoveToPoint(c, 11 * k, 9 * k); CGContextAddLineToPoint(c, 16.5 * k, 13 * k); CGContextAddLineToPoint(c, 11 * k, 17 * k);
            CGContextFillPath(c);
            CGContextSetBlendMode(c, kCGBlendModeNormal);
        } else if ([n isEqualToString:@"reload"]) { /* circular arrow (Shorts header) */
            CGContextSetLineWidth(c, 2.6 * k);
            CGContextAddArc(c, 13 * k, 13 * k, 9 * k, (CGFloat)(-M_PI * 0.35), (CGFloat)(M_PI * 1.45), 0);
            CGContextStrokePath(c);
            CGContextMoveToPoint(c, 15 * k, 1 * k); CGContextAddLineToPoint(c, 23 * k, 5 * k); CGContextAddLineToPoint(c, 16 * k, 10 * k);
            CGContextFillPath(c);
        } else if ([n isEqualToString:@"comment"]) { /* speech bubble */
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2 * k, 3 * k, 22 * k, 15 * k) cornerRadius:4 * k] fill];
            CGContextMoveToPoint(c, 7 * k, 17 * k); CGContextAddLineToPoint(c, 7 * k, 24 * k); CGContextAddLineToPoint(c, 14 * k, 17 * k);
            CGContextFillPath(c);
        } else if ([n isEqualToString:@"share"]) { /* curved arrow to the right */
            CGContextMoveToPoint(c, 15 * k, 3 * k); CGContextAddLineToPoint(c, 25 * k, 12 * k); CGContextAddLineToPoint(c, 15 * k, 21 * k);
            CGContextFillPath(c);
            CGContextSetLineWidth(c, 4 * k);
            CGContextMoveToPoint(c, 16 * k, 12 * k);
            CGContextAddCurveToPoint(c, 9 * k, 12 * k, 3 * k, 14 * k, 2 * k, 23 * k);
            CGContextStrokePath(c);
        } else if ([n isEqualToString:@"play"]) {
            CGContextMoveToPoint(c, 6 * k, 3 * k); CGContextAddLineToPoint(c, 23 * k, 13 * k); CGContextAddLineToPoint(c, 6 * k, 23 * k);
            CGContextFillPath(c);
        } else if ([n isEqualToString:@"pause"]) {
            CGContextFillRect(c, CGRectMake(5 * k, 3 * k, 6 * k, 20 * k));
            CGContextFillRect(c, CGRectMake(15 * k, 3 * k, 6 * k, 20 * k));
        } else if ([n isEqualToString:@"full"]) {
            CGContextSetLineWidth(c, 2.6 * k);
            CGFloat a = 3 * k, b = 23 * k, l = 7 * k;
            CGContextMoveToPoint(c, a, a + l); CGContextAddLineToPoint(c, a, a); CGContextAddLineToPoint(c, a + l, a);
            CGContextMoveToPoint(c, b - l, a); CGContextAddLineToPoint(c, b, a); CGContextAddLineToPoint(c, b, a + l);
            CGContextMoveToPoint(c, b, b - l); CGContextAddLineToPoint(c, b, b); CGContextAddLineToPoint(c, b - l, b);
            CGContextMoveToPoint(c, a + l, b); CGContextAddLineToPoint(c, a, b); CGContextAddLineToPoint(c, a, b - l);
            CGContextStrokePath(c);
        } else if ([n isEqualToString:@"check"]) { /* §8.4 subscribed: green circle, white check */
            [TBHex(0x53A653) setFill];
            CGContextFillEllipseInRect(c, CGRectMake(0, 0, s, s));
            [[UIColor whiteColor] setStroke];
            CGContextSetLineWidth(c, 3 * k);
            CGContextMoveToPoint(c, 7 * k, 13.5 * k); CGContextAddLineToPoint(c, 11.5 * k, 18 * k); CGContextAddLineToPoint(c, 19 * k, 8.5 * k);
            CGContextStrokePath(c);
        } else if ([n isEqualToString:@"plus"]) { /* §8.4 subscribe: blue circle, white plus */
            [TBHex(0x5A80D3) setFill];
            CGContextFillEllipseInRect(c, CGRectMake(0, 0, s, s));
            [[UIColor whiteColor] setFill];
            CGContextFillRect(c, CGRectMake(11.5 * k, 6 * k, 3 * k, 14 * k));
            CGContextFillRect(c, CGRectMake(6 * k, 11.5 * k, 14 * k, 3 * k));
        }
        UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return i;
    });
}
@end
