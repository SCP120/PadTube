#import <Foundation/Foundation.h>

extern NSString *const TBAccountChanged;

/* Sign-in with the OAuth device flow (TV client). Tokens live in the local store; the access token is refreshed
 * before it expires. Every signed-in call uses the TVHTML5 client. */
@interface TBAccount : NSObject
+ (BOOL)signedIn;
+ (void)restore;                                       /* at launch: load and refresh the token */
/* Starts the device flow. code: shown to the person (user code + URL). done: YES when signed in. */
+ (void)beginSignIn:(void (^)(NSString *userCode, NSString *url))code done:(void (^)(BOOL ok, NSString *error))done;
+ (void)cancelSignIn;
+ (NSString *)pendingCode;
+ (void)signOut;
+ (void)like:(NSString *)videoId action:(int)a done:(void (^)(BOOL ok))done;
+ (void)subscribe:(NSString *)channelId on:(BOOL)on done:(void (^)(BOOL ok))done;
+ (void)addToWatchLater:(NSString *)videoId done:(void (^)(BOOL ok))done;
+ (void)removeFromPlaylist:(NSString *)playlistId setVideoId:(NSString *)sv done:(void (^)(BOOL ok))done;
+ (void)reportWatch:(NSString *)videoId;               /* account history (videostats ping) */
@end
