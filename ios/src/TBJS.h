#import <Foundation/Foundation.h>

/* iOS 6's own JavaScriptCore through its C API (dlopen, as PadWeb does): runs on the calling thread, so the player
 * challenge solver (D61) runs off the main thread. One context per object; not thread-safe, use it on one queue. */
@interface TBJS : NSObject
+ (BOOL)available;
- (id)init;                                              /* nil when JavaScriptCore cannot be loaded */
- (void)setString:(NSString *)value forName:(NSString *)name;   /* a global string, without parsing it as a script */
/* evaluates src; returns the result as a string (nil on an exception, then *error is set) */
- (NSString *)eval:(NSString *)src name:(NSString *)name error:(NSString **)error;
@end
