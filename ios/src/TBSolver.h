#import <Foundation/Foundation.h>

/* YouTube's player challenges (n, sig) for the signed-in path (D62-D64): once per player version the ES5 player is
 * downloaded, turned into ejs's "preprocessed player" in C (tb_jsprep, about 1.8 s and 20 MB on the A5) and cached on
 * disk; it is loaded once into iOS 6's JavaScriptCore (about 1.6 s), which then answers each video in about 10 ms.
 * All calls except warmUp block and run on the solver's own serial queue: never call them on the main thread. */
@interface TBSolver : NSObject
+ (void)warmUp;                                            /* in the background, at a low priority */
+ (BOOL)waitReady:(int *)signatureTimestamp;               /* prepares if needed; NO: no solver (network, player) */
+ (NSDictionary *)solveN:(NSArray *)n sig:(NSArray *)sig error:(NSString **)error;   /* {n: {c: a}, sig: {c: a}} */
+ (void)invalidate;                                        /* check the player version again at the next use */
+ (NSDictionary *)state;                                   /* self-test: version, sts, ready, timings */
@end
