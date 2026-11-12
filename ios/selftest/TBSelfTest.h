#import <UIKit/UIKit.h>

/* Test-only (SELFTEST=1 builds): a line protocol on 127.0.0.1:5130-5134 that the Mac reaches through iproxy.
 * Drives the real UI and reports measured numbers (start time, scroll fps, main-thread stalls, memory). */
@class TBShell;
@interface TBSelfTest : NSObject
+ (void)startWithShell:(TBShell *)shell;
@end
