#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>
#import "TBAccount.h"
#import "TBLog.h"
#import "TBCore.h"
#import "TBImageLoader.h"
#import "TBShell.h"
#import "TBAccountController.h"
#import "TBSolver.h"
#import "TBPlayerView.h"
#import "TBStore.h"
#import "TBWatchController.h"
#import "TBStyle.h"
#include "tb_http.h"
#ifdef TB_SELFTEST
#import "TBSelfTest.h"
#endif

@interface TBAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TBShell *shell;
@end

@implementation TBAppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    double t0 = tb_now_ms();
    [TBCore start];
    [TBStore open];
    [TBAccount restore];
    /* background audio: playback category keeps the process and the local server alive (UIBackgroundModes=audio) */
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    [app beginReceivingRemoteControlEvents];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.shell = [TBShell new];
    [[NSNotificationCenter defaultCenter] addObserverForName:TBAccountChanged object:nil queue:nil usingBlock:^(NSNotification *note) {
        [self.shell refreshAccount];
        if ([TBAccount signedIn]) [TBSolver warmUp];   /* the signed-in player path needs the solver (D64) */
    }];
    if ([TBAccount signedIn])   /* after the first screen, at a low priority: about 4 s once per player version */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [TBSolver warmUp]; });
    /* owner 2026-11-13: when the session is gone, show the sign-in code at once (no silent failure) */
    [[NSNotificationCenter defaultCenter] addObserverForName:TBAccountSessionLost object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [self.shell selectGuideRow:(NSInteger)[[TBShell guideTitles] indexOfObject:@"Account"]];
        TBAccountController *a = (TBAccountController *)self.shell.nav.topViewController;
        if (![a isKindOfClass:[TBAccountController class]]) return;
        a.notice = @"Your YouTube sign-in ended. Enter this code at google.com/device to sign in again.";
        [a startSignIn];
    }];
    self.window.rootViewController = self.shell;
    self.window.backgroundColor = [UIColor blackColor];
    /* DUC-SET-THEME: a theme change builds the screens again (D39); the Account screen shows again */
    [[NSNotificationCenter defaultCenter] addObserverForName:TBThemeChanged object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[TBWatchController current].player stop];
            self.shell = [TBShell new];
            self.window.rootViewController = self.shell;
            [self.shell selectGuideRow:(NSInteger)[[TBShell guideTitles] indexOfObject:@"Account"]];
        });
    }];
    [self.window makeKeyAndVisible];
    TBLog(@"PadTube: launch %.0f ms", tb_now_ms() - t0);
    /* create the movie player while the person looks at the first screen, not at the first tap */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        double p0 = tb_now_ms();
        [TBPlayerView prewarm];
        TBLog(@"PadTube: movie player made in %.0f ms", tb_now_ms() - p0);
        /* The first scroll after launch had 54-97 ms frames in first-use text work (font files, glyph layout;
         * R1 stall sampler 2026-11-12). The glyph caches are per process: fill them off the main thread. */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            NSString *t = @"Ag 0123456789 views ago • ăâđêôơư ầếệộờựỹ ÀÉÍÓÚ";
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(400, 30), YES, 1);
            for (NSNumber *n in @[@12, @13, @14, @15, @16, @17, @18, @20]) {
                CGFloat z = n.floatValue;
                [t drawAtPoint:CGPointZero withFont:TBFont(z)];
                [t drawAtPoint:CGPointZero withFont:TBFontBold(z)];
            }
            UIGraphicsEndImageContext();
        });
    });
#ifdef TB_SELFTEST
    [TBSelfTest startWithShell:self.shell];
#endif
    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)app {
    [TBImageLoader clearMemory];
    tb_http_close_idle();
}

/* owner bug 2026-11-12 (about 30 s of "loading" after a return): pooled sockets may have died while the app was
 * suspended; drop them all at once (one new TLS handshake: 64-83 ms MEASURED) instead of waiting for a timeout. */
- (void)applicationWillEnterForeground:(UIApplication *)app {
    tb_http_drop_idle();   /* before the player asks for anything; close() only, no TLS write: fast on the main thread */
}

- (void)applicationDidEnterBackground:(UIApplication *)app {
    /* owner rule (PadTube + PadBook together): free caches in the background. Only images no view shows are
     * dropped, so the visible thumbnails stay for the return. */
    [TBImageLoader clearMemory];
    TBWatchController *w = [TBWatchController current];
    TBLog(@"PadTube: background, playing=%d", w.player.isPlaying);
}

/* lock screen and headset buttons */
- (void)remoteControlReceivedWithEvent:(UIEvent *)e {
    TBPlayerView *p = [TBWatchController current].player;
    if (!p) return;
    switch (e.subtype) {
    case UIEventSubtypeRemoteControlTogglePlayPause:
    case UIEventSubtypeRemoteControlPlay:
    case UIEventSubtypeRemoteControlPause: [p togglePlay]; break;
    default: break;
    }
}
- (BOOL)canBecomeFirstResponder { return YES; }
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([TBAppDelegate class]));
    }
}
