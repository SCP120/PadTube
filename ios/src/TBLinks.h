#import <UIKit/UIKit.h>

/* Web links in descriptions and comments (owner 2026-11-12): YouTube links open in PadTube; every other link opens
 * inside the app with PadWeb's browser (PWBrowserController), never in Safari. */
@interface TBLinks : NSObject
+ (NSArray *)linksIn:(NSString *)text;                              /* NSTextCheckingResult, in order */
+ (NSAttributedString *)styledText:(NSString *)text font:(UIFont *)font color:(UIColor *)color links:(NSArray *)links; /* links: +linksIn: */
+ (void)openURL:(NSURL *)url from:(UIViewController *)vc;
/* The link under a point of a text view, or nil. links: the result of +linksIn: for tv.text (found off the main
 * thread: the first detection loads the language model, 114 ms MEASURED on the iPad 2026-11-12). */
+ (NSURL *)linkInTextView:(UITextView *)tv atPoint:(CGPoint)p links:(NSArray *)links;
@end
