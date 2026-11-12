#import <Foundation/Foundation.h>

/* Log line written on a background serial queue. On iOS 6 NSLog and syslog() write synchronously: 43-44 ms on
 * the main thread in a grid scroll (stall sampler, R1 2026-11-12). The text is formatted on the caller's thread,
 * so the order of lines from one thread stays the same. */
void TBLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
