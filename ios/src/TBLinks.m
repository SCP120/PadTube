#import "TBLinks.h"
#ifndef TB_NO_PADWEB
#import "PWBrowserController.h"
#import "PadWeb.h"
#endif
#import "TBListController.h"
#import "TBStyle.h"

@implementation TBLinks

+ (NSArray *)linksIn:(NSString *)text {
    if (!text.length) return @[];
    static NSDataDetector *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL]; });
    return [d matchesInString:text options:0 range:NSMakeRange(0, text.length)];
}

+ (NSAttributedString *)styledText:(NSString *)text font:(UIFont *)font color:(UIColor *)color links:(NSArray *)links {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:text ?: @""
                                                                          attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}];
    for (NSTextCheckingResult *r in links) [a addAttribute:NSForegroundColorAttributeName value:[TBStyle link] range:r.range];
    return a;
}

static NSString *query(NSURL *u, NSString *key) {
    for (NSString *kv in [u.query componentsSeparatedByString:@"&"]) {
        NSArray *p = [kv componentsSeparatedByString:@"="];
        if (p.count == 2 && [p[0] isEqualToString:key]) return p[1];
    }
    return nil;
}

+ (void)openURL:(NSURL *)url from:(UIViewController *)vc {
    NSString *host = url.host.lowercaseString ?: @"", *path = url.path ?: @"";
    NSArray *parts = [path.pathComponents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != '/'"]];
    BOOL yt = [host hasSuffix:@"youtube.com"];
    NSString *vid = nil;
    if (yt && [path isEqualToString:@"/watch"]) vid = query(url, @"v");
    else if (yt && parts.count >= 2 && ([parts[0] isEqualToString:@"shorts"] || [parts[0] isEqualToString:@"live"])) vid = parts[1];
    else if ([host isEqualToString:@"youtu.be"] && parts.count >= 1) vid = parts[0];
    if (vid.length == 11) { [TBRouter openVideo:vid title:nil from:vc]; return; }
    if (yt && parts.count >= 2 && [parts[0] isEqualToString:@"channel"] && [parts[1] hasPrefix:@"UC"]) {
        [TBRouter openChannel:parts[1] title:nil from:vc];
        return;
    }
    if (![url.scheme hasPrefix:@"http"]) return;
#ifdef TB_NO_PADWEB
    /* public build (D46): PadWeb is private, so a web page opens in Safari */
    [[UIApplication sharedApplication] openURL:url];
#else
    static BOOL started;
    if (!started) started = [PadWeb start]; /* started at the first link, not at launch: no RAM until it is used */
    PWBrowserController *b = [PWBrowserController presentURL:url from:vc];
    if (![TBStyle dark]) return;
    /* DUC-SET-THEME: black iOS 6 bars in Dark; the page itself is the site's own */
    b.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    for (UIView *v in b.view.subviews) if ([v isKindOfClass:[UIToolbar class]]) ((UIToolbar *)v).barStyle = UIBarStyleBlack;
#endif
}

+ (NSURL *)linkInTextView:(UITextView *)tv atPoint:(CGPoint)p links:(NSArray *)links {
    UITextPosition *pos = [tv closestPositionToPoint:p];
    if (!pos) return nil;
    NSInteger i = [tv offsetFromPosition:tv.beginningOfDocument toPosition:pos];
    for (NSTextCheckingResult *r in links)
        if (i >= (NSInteger)r.range.location && i <= (NSInteger)NSMaxRange(r.range)) return r.URL;
    return nil;
}
@end
