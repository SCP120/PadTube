#import <UIKit/UIKit.h>
#import "TBAccount.h"
#import "TBLog.h"
#import "TBCore.h"
#import "TBStore.h"
#include "tb_oauth.h"
#include "tb_yt.h"

NSString *const TBAccountChanged = @"TBAccountChanged";
NSString *const TBAccountSessionLost = @"TBAccountSessionLost";

static NSString *g_access, *g_refresh, *g_cid, *g_secret, *g_pending;
static double g_expires; /* unix seconds */
static BOOL g_cancel;

@implementation TBAccount

+ (BOOL)signedIn { return g_refresh.length > 0; }
+ (NSDictionary *)authState {
    double now = [[NSDate date] timeIntervalSince1970];
    return @{@"signed_in": @(g_refresh.length > 0), @"has_access": @(g_access.length > 0), @"expires_in_s": @(g_expires - now)};
}
+ (NSString *)pendingCode { return g_pending; }

+ (void)saveToken {
    [TBStore setValue:g_refresh forKey:@"oauth.refresh"];
    [TBStore setValue:g_access forKey:@"oauth.access"];
    [TBStore setValue:[NSString stringWithFormat:@"%.0f", g_expires] forKey:@"oauth.expires"];
    tb_yt_set_token(g_access.UTF8String);
}

/* Client ID and secret from the TV page, cached in the store (the page script is 1.1 MB). Background queue only. */
+ (BOOL)loadClient {
    if (g_cid.length) return YES;
    g_cid = [TBStore valueFor:@"oauth.client_id"];
    g_secret = [TBStore valueFor:@"oauth.client_secret"];
    if (g_cid.length && g_secret.length) return YES;
    tb_oauth_client c;
    if (tb_oauth_get_client(&c)) return NO;
    g_cid = TBStr(c.client_id);
    g_secret = TBStr(c.client_secret);
    tb_oauth_client_free(&c);
    [TBStore setValue:g_cid forKey:@"oauth.client_id"];
    [TBStore setValue:g_secret forKey:@"oauth.client_secret"];
    return YES;
}

/* Background queue only. */
+ (BOOL)refreshNow {
    if (!g_refresh.length || ![self loadClient]) return NO;
    tb_oauth_client c = {(char *)g_cid.UTF8String, (char *)g_secret.UTF8String};
    tb_token t;
    int rc = tb_oauth_refresh(&c, g_refresh.UTF8String, &t);
    if (rc == 0) {
        g_access = TBStr(t.access_token);
        g_expires = [[NSDate date] timeIntervalSince1970] + (t.expires_in > 0 ? t.expires_in : 3600);
        [self saveToken];
    } else {
        TBLog(@"PadTube: token refresh failed %d %s", rc, t.error ?: "");
        if (t.error && strstr(t.error, "invalid_grant")) {   /* the session is gone (revoked, expired): no silent failure */
            dispatch_async(dispatch_get_main_queue(), ^{
                [self signOut];
                [[NSNotificationCenter defaultCenter] postNotificationName:TBAccountSessionLost object:nil];
            });
        }
    }
    tb_token_free(&t);
    return rc == 0;
}

+ (void)ensureFresh {
    /* refresh 5 minutes before expiry */
    if (g_refresh.length && [[NSDate date] timeIntervalSince1970] > g_expires - 300) [self refreshNow];
}

+ (void)restore {
    g_refresh = [TBStore valueFor:@"oauth.refresh"];
    g_access = [TBStore valueFor:@"oauth.access"];
    g_expires = [[TBStore valueFor:@"oauth.expires"] doubleValue];
    if (!g_refresh.length) return;
    tb_yt_set_token(g_access.UTF8String);
    dispatch_async([TBCore queue], ^{ [self ensureFresh]; });
}

+ (void)beginSignIn:(void (^)(NSString *, NSString *))code done:(void (^)(BOOL, NSString *))done {
    g_cancel = NO;
    /* keep polling when another app comes to the front: iOS 6 gives a background task about 10 minutes */
    __block UIBackgroundTaskIdentifier bg = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:bg];
        bg = UIBackgroundTaskInvalid;
    }];
    void (^userDone)(BOOL, NSString *) = done;
    done = ^(BOOL ok, NSString *err) {
        userDone(ok, err);
        if (bg != UIBackgroundTaskInvalid) { [[UIApplication sharedApplication] endBackgroundTask:bg]; bg = UIBackgroundTaskInvalid; }
    };
    dispatch_async([TBCore queue], ^{
        if (![self loadClient]) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(NO, @"Could not read the TV sign-in client."); });
            return;
        }
        tb_oauth_client c = {(char *)g_cid.UTF8String, (char *)g_secret.UTF8String};
        NSString *dev = [TBStore valueFor:@"oauth.device_id"];
        if (!dev) { dev = [[NSProcessInfo processInfo] globallyUniqueString]; [TBStore setValue:dev forKey:@"oauth.device_id"]; }
        BOOL ok = NO;
        NSString *err = @"The code expired.";
        /* A code lives about 30 minutes. When it expires, ask for a new one and show it: no step for the person.
         * 12 rounds = about 6 hours, then stop (the screen offers "Get a sign-in code" again). */
        for (int round = 0; round < 12 && !ok && !g_cancel; round++) {
            tb_device_code d;
            if (tb_oauth_device_code(&c, dev.UTF8String, &d)) {
                err = @"Google did not give a sign-in code.";
                [NSThread sleepForTimeInterval:10];
                continue;
            }
            NSString *uc = TBStr(d.user_code), *url = TBStr(d.verification_url);
            g_pending = uc;
            TBLog(@"PadTube: sign-in code %@ at %@ (round %d)", uc, url, round + 1);
            dispatch_async(dispatch_get_main_queue(), ^{ code(uc, url); });
            double end = [[NSDate date] timeIntervalSince1970] + (d.expires_in > 0 ? d.expires_in : 1800);
            BOOL expired = NO;
            while (!g_cancel && !expired && [[NSDate date] timeIntervalSince1970] < end) {
                [NSThread sleepForTimeInterval:d.interval];
                tb_token t;
                int rc = tb_oauth_poll(&c, d.device_code, &t);
                if (rc == 0) {
                    g_access = TBStr(t.access_token);
                    g_refresh = TBStr(t.refresh_token);
                    g_expires = [[NSDate date] timeIntervalSince1970] + (t.expires_in > 0 ? t.expires_in : 3600);
                    [self saveToken];
                    ok = YES;
                    tb_token_free(&t);
                    break;
                }
                if (rc == -2) {
                    err = TBStr(t.error);
                    expired = t.error && !strcmp(t.error, "expired_token");
                    tb_token_free(&t);
                    if (!expired) { tb_device_code_free(&d); goto out; } /* access_denied and other final answers */
                    break;
                }
                tb_token_free(&t); /* pending, or a network error: keep polling */
            }
            tb_device_code_free(&d);
        }
    out:
        g_pending = nil;
        if (g_cancel) err = @"Cancelled.";
        dispatch_async(dispatch_get_main_queue(), ^{
            done(ok, ok ? nil : err);
            [[NSNotificationCenter defaultCenter] postNotificationName:TBAccountChanged object:nil];
        });
    });
}

+ (void)cancelSignIn { g_cancel = YES; }

+ (void)signOut {
    g_access = g_refresh = nil;
    g_expires = 0;
    [TBStore setValue:nil forKey:@"oauth.refresh"];
    [TBStore setValue:nil forKey:@"oauth.access"];
    tb_yt_set_token(NULL);
    [[NSNotificationCenter defaultCenter] postNotificationName:TBAccountChanged object:nil];
}

+ (void)run:(int (^)(void))call done:(void (^)(BOOL))done {
    dispatch_async([TBCore queue], ^{
        [self ensureFresh];
        int rc = call();
        if (rc == -401 && [self refreshNow]) rc = call(); /* 401: the token expired early */
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(rc == 0); });
    });
}

+ (void)like:(NSString *)v action:(int)a done:(void (^)(BOOL))done {
    [self run:^int { return tb_yt_like(v.UTF8String, a); } done:done];
}
+ (void)subscribe:(NSString *)ch on:(BOOL)on done:(void (^)(BOOL))done {
    [self run:^int { return tb_yt_subscribe(ch.UTF8String, on); } done:done];
}
+ (void)addToWatchLater:(NSString *)v done:(void (^)(BOOL))done {
    [self run:^int { return tb_yt_playlist_edit("WL", v.UTF8String, 1, NULL); } done:done];
}
+ (void)removeFromPlaylist:(NSString *)pl setVideoId:(NSString *)sv done:(void (^)(BOOL))done {
    [self run:^int { return tb_yt_playlist_edit(pl.UTF8String, NULL, 0, sv.UTF8String); } done:done];
}

+ (void)reportWatch:(NSString *)videoId {
    if (![self signedIn]) return;
    [self run:^int {
        char *pb = NULL, *wt = NULL;
        int rc = tb_yt_tracking(videoId.UTF8String, &pb, &wt);
        if (rc == 0 && pb) {
            /* fresh 16-char cpn per playback: a reused cpn drops later history entries (Opaline WatchtimeTracker) */
            static const char abc[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
            char cpn[17];
            for (int i = 0; i < 16; i++) cpn[i] = abc[arc4random_uniform(64)];
            cpn[16] = 0;
            NSString *u = [NSString stringWithFormat:@"%s&ver=2&cpn=%s&fmt=251&rtn=0&rt=0", pb, cpn];
            u = [u stringByReplacingOccurrencesOfString:@"https://s.youtube.com" withString:@"https://www.youtube.com"];
            rc = tb_yt_ping(u.UTF8String);
        }
        free(pb);
        free(wt);
        return rc;
    } done:nil];
}
@end
