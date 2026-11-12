#import "TBSolver.h"
#import "TBCore.h"
#import "TBJS.h"
#import "TBLog.h"
#include "tb_http.h"
#include "tb_jsprep.h"
#include "tb_yt.h"

static dispatch_queue_t g_q;
static TBJS *g_js;                       /* the loaded player, on g_q only */
static NSString *g_version;
static int g_sts;
static BOOL g_checked;                   /* the version was checked since launch or the last invalidate */
static double g_prepMs, g_loadMs, g_versionMs;
static NSString *g_lastError;

static NSString *dir(void) {
    NSString *d = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"solver"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    return d;
}

@implementation TBSolver

+ (void)initialize {
    if (self == [TBSolver class]) g_q = dispatch_queue_create("padtube.solver", DISPATCH_QUEUE_SERIAL);
}

/* the preprocessed player of version v: from the disk cache, else made now (and the older ones removed) */
+ (NSString *)preprocessed:(NSString *)v sts:(int *)sts {
    NSString *d = dir(), *pf = [d stringByAppendingPathComponent:[v stringByAppendingPathExtension:@"js"]];
    NSString *sf = [d stringByAppendingPathComponent:[v stringByAppendingPathExtension:@"sts"]];
    NSString *pre = [NSString stringWithContentsOfFile:pf encoding:NSUTF8StringEncoding error:NULL];
    if (pre) { *sts = [[NSString stringWithContentsOfFile:sf encoding:NSUTF8StringEncoding error:NULL] intValue]; if (*sts) return pre; }
    NSString *u = [NSString stringWithFormat:@"https://www.youtube.com/s/player/%@/player_ias.vflset/en_US/base.js", v];
    tb_req q = {.url = u.UTF8String, .range_start = -1, .timeout_ms = 30000};
    tb_resp r;
    double t0 = tb_now_ms();
    if (tb_http(&q, &r) != 200 || !r.len) { tb_resp_free(&r); g_lastError = @"player download failed"; return nil; }
    *sts = tb_js_signature_timestamp(r.body, r.len);
    size_t n = 0;
    int cands = 0;
    const char *err = NULL;
    char *out = tb_jsprep(r.body, r.len, &n, &cands, &err);
    tb_resp_free(&r);
    g_prepMs = tb_now_ms() - t0;
    if (!out || !*sts) { free(out); g_lastError = err ? @(err) : @"no signatureTimestamp"; return nil; }
    pre = [[NSString alloc] initWithBytesNoCopy:out length:n encoding:NSUTF8StringEncoding freeWhenDone:YES];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:d error:NULL])   /* one version kept */
        [[NSFileManager defaultManager] removeItemAtPath:[d stringByAppendingPathComponent:f] error:NULL];
    [pre writeToFile:pf atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSString stringWithFormat:@"%d", *sts] writeToFile:sf atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    TBLog(@"PadTube: solver: player %@ prepared in %.0f ms (%d candidates, sts %d)", v, g_prepMs, cands, *sts);
    return pre;
}

/* on g_q: the current version loaded, or NO */
+ (BOOL)ensure {
    if (g_js && g_checked) return YES;
    double t0 = tb_now_ms();
    char ver[16];
    NSString *v = tb_yt_player_version(ver) == 0 ? @(ver) : nil;
    g_versionMs = tb_now_ms() - t0;
    if (!v) v = g_version;   /* no answer: keep the loaded one, if any */
    if (!v) { g_lastError = @"no player version"; return NO; }
    g_checked = YES;
    if (g_js && [v isEqualToString:g_version]) return YES;
    int sts = 0;
    NSString *pre;
    @autoreleasepool {
        pre = [self preprocessed:v sts:&sts];
        if (!pre) return NO;
        TBJS *js = [TBJS new];
        if (!js) { g_lastError = @"JavaScriptCore not available"; return NO; }
        [js setString:pre forName:@"__pre"];
        pre = nil;
        double l0 = tb_now_ms();
        NSString *err = nil;
        NSString *ok = [js eval:@"var __s = {n: null, sig: null}; Function('_result', __pre)(__s); __pre = null; typeof __s.n + ',' + typeof __s.sig"
                           name:@"player" error:&err];
        g_loadMs = tb_now_ms() - l0;
        if (![ok isEqualToString:@"function,function"]) { g_lastError = err ?: ok ?: @"load failed"; TBLog(@"PadTube: solver: load failed: %@", g_lastError); return NO; }
        g_js = js;   /* the old version's context goes now */
    }
    g_version = v;
    g_sts = sts;
    g_lastError = nil;
    TBLog(@"PadTube: solver: player %@ loaded in %.0f ms", v, g_loadMs);
    return YES;
}

+ (void)warmUp {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        dispatch_sync(g_q, ^{ [self ensure]; });
    });
}

+ (BOOL)waitReady:(int *)sts {
    __block BOOL ok = NO;
    dispatch_sync(g_q, ^{
        ok = [self ensure];
        if (sts) *sts = g_sts;
    });
    return ok;
}

static NSString *jsonOf(id o) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:o options:0 error:NULL];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"[]";
}

+ (NSDictionary *)solveN:(NSArray *)n sig:(NSArray *)sig error:(NSString **)error {
    __block NSDictionary *res = nil;
    __block NSString *err = nil;
    dispatch_sync(g_q, ^{
        if (![self ensure]) { err = g_lastError ?: @"not ready"; return; }
        NSString *src = [NSString stringWithFormat:
            @"(function (ns, ss) { var r = {n: {}, sig: {}}, i; for (i = 0; i < ns.length; i++) r.n[ns[i]] = __s.n(ns[i]);"
            " for (i = 0; i < ss.length; i++) r.sig[ss[i]] = __s.sig(ss[i]); return JSON.stringify(r); })(%@, %@)", jsonOf(n), jsonOf(sig)];
        NSString *out = [g_js eval:src name:@"solve" error:&err];
        if (out) res = [NSJSONSerialization JSONObjectWithData:[out dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if (!res && !err) err = @"bad answer";
    });
    if (error) *error = err;
    return res;
}

+ (void)invalidate { dispatch_async(g_q, ^{ g_checked = NO; }); }

+ (NSDictionary *)state {
    __block NSDictionary *d;
    dispatch_sync(g_q, ^{
        d = @{@"version": g_version ?: @"", @"sts": @(g_sts), @"ready": @(g_js != nil), @"prep_ms": @(g_prepMs), @"load_ms": @(g_loadMs),
              @"version_ms": @(g_versionMs), @"error": g_lastError ?: @""};
    });
    return d;
}
@end
