#import "TBSelfTest.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#include <arpa/inet.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/socket.h>
#include <spawn.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#import "TBAccount.h"
#import "TBCore.h"
#import "TBListController.h"
#import "TBPlayerView.h"
#import "TBSearchController.h"
#import "TBShell.h"
#import "TBBackSwipe.h"
#import "TBShortsController.h"
#import "TBJS.h"
#import "TBSolver.h"
#import "TBShortsPlayer.h"
#import "TBAccountController.h"
#import "TBWatchController.h"
#import "TBStyle.h"
#import "TBLinks.h"
#import "TBLog.h"
#include "tb_hls.h"
#include "tb_http.h"
#include "tb_jsprep.h"
#include "tb_yt.h"
#include "yyjson.h"

/* 5125-5129: an old build (no quit command) may still hold 5124 in the background. The bound port is logged as
 * "PTSELFTEST port N"; scripts/ipad_session.sh reads it from the device log. */
enum { PORT_FIRST = 5130, PORT_LAST = 5134 }; /* 5124/5125 belong to PadBook's self-test (shared iPad, 2026-11-12) */

#define g_shell [TBShell shared]   /* follows the rebuild after a theme change */
static double g_peakMB;
/* main-thread stall: longest run-loop pass (after waiting -> before waiting) since the last reset */
static double g_passStart, g_maxPass;
static CFRunLoopObserverRef g_obs;

static double residentMB(void) {
    struct task_basic_info info;
    mach_msg_type_number_t n = TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return -1;
    return info.resident_size / 1048576.0;
}

static void *memSampler(void *a) {
    for (;;) @autoreleasepool {
        double m = residentMB();
        if (m > g_peakMB) g_peakMB = m;
        usleep(100000);
    }
    return NULL;
}

/* Stall sampler: when the main thread is inside one run-loop pass for over 100 ms, suspend it, walk its frame
 * pointers (r7 chain on armv7) and log the symbols once per pass. Shows what blocks the main thread. */
static mach_port_t g_main_thread;
static volatile double g_pass_begin;
static volatile double g_stall_ms = 100;   /* 'stallms N' lowers it for one test (R1: grid frames of 25-100 ms) */
static void *stallSampler(void *arg) {
    double logged_for = 0;
    for (;;) {
        usleep(g_stall_ms < 100 ? 5000 : 20000);
        double b = g_pass_begin;
        if (b <= 0 || b == logged_for || tb_now_ms() - b < g_stall_ms) continue;
        logged_for = b;
        if (thread_suspend(g_main_thread) != KERN_SUCCESS) continue;
        uintptr_t pcs[24];
        int n = 0;
#if defined(__arm__)
        arm_thread_state_t st;
        mach_msg_type_number_t cnt = ARM_THREAD_STATE_COUNT;
        if (thread_get_state(g_main_thread, ARM_THREAD_STATE, (thread_state_t)&st, &cnt) == KERN_SUCCESS) {
            pcs[n++] = st.__pc;
            pcs[n++] = st.__lr;
            uintptr_t fp = st.__r[7];
            while (fp && n < 24) {
                uintptr_t *f = (uintptr_t *)fp;
                vm_size_t got = 0;
                uintptr_t pair[2];
                if (vm_read_overwrite(mach_task_self(), (vm_address_t)f, sizeof pair, (vm_address_t)pair, &got) != KERN_SUCCESS) break;
                if (!pair[1]) break;
                pcs[n++] = pair[1];
                if (pair[0] <= fp) break;
                fp = pair[0];
            }
        }
#endif
        thread_resume(g_main_thread);
        NSMutableString *m = [NSMutableString stringWithFormat:@"PTSTALL %.0f ms:", tb_now_ms() - b];
        for (int i = 0; i < n; i++) {
            Dl_info d;
            if (dladdr((void *)pcs[i], &d) && d.dli_sname) [m appendFormat:@" | %s+%lu", d.dli_sname, (unsigned long)(pcs[i] - (uintptr_t)d.dli_saddr)];
            else [m appendFormat:@" | %p", (void *)pcs[i]];
        }
        NSLog(@"%@", m);
    }
    return NULL;
}

static void loopObserver(CFRunLoopObserverRef o, CFRunLoopActivity act, void *info) {
    double now = tb_now_ms();
    if (act == kCFRunLoopAfterWaiting) { g_passStart = now; g_pass_begin = now; }
    else if (act == kCFRunLoopBeforeWaiting && g_passStart > 0) {
        g_pass_begin = 0;
        double d = now - g_passStart;
        if (d > g_maxPass) g_maxPass = d;
        g_passStart = 0;
    }
}

@interface TBScroller : NSObject
@property (nonatomic, strong) UIScrollView *view;
@property (nonatomic) double speed, endAt, last, maxGap, start;
@property (nonatomic) int frames, slow, direction;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, copy) void (^done)(NSString *);
@end
@implementation TBScroller
- (void)tick:(CADisplayLink *)l {
    double now = tb_now_ms();
    if (self.last > 0) {
        double gap = now - self.last;
        if (gap > self.maxGap) self.maxGap = gap;
        /* a frame over 20 ms missed the 16.7 ms vsync */
        if (gap > 20) self.slow++;
        self.frames++;
        UIScrollView *v = self.view;
        CGFloat y = v.contentOffset.y + self.direction * (CGFloat)(self.speed * gap / 1000.0);
        CGFloat maxY = MAX(0, v.contentSize.height - v.bounds.size.height);
        if (y >= maxY) { y = maxY; self.direction = -1; }
        if (y <= 0) { y = 0; self.direction = 1; }
        v.contentOffset = CGPointMake(0, y);
    } else self.start = now;
    self.last = now;
    if (now >= self.endAt) {
        [l invalidate];
        double secs = (now - self.start) / 1000.0;
        self.done([NSString stringWithFormat:@"{\"frames\":%d,\"seconds\":%.2f,\"fps\":%.1f,\"slow_frames\":%d,\"max_frame_ms\":%.1f,\"max_main_ms\":%.1f,\"rows\":%ld}",
                   self.frames, secs, self.frames / secs, self.slow, self.maxGap, g_maxPass,
                   (long)([self.view isKindOfClass:[UITableView class]] ? [(UITableView *)self.view numberOfRowsInSection:0] : 0)]);
    }
}
@end

/* Drives a swipe back (D49) frame by frame with the code the pan calls: begin, move to `frac` of the width in `ms`,
 * release with `vx` pt/s, then waits for the slide to end. Frame times as TBScroller. */
@interface TBSwipeDriver : NSObject
@property (nonatomic) double ms, frac, vx, start, last, maxGap, width, dragFps, dragMaxGap, dragMain, releaseAt;
@property (nonatomic) int frames, slow, before, dragSlow;
@property (nonatomic) BOOL released, hold;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, copy) void (^done)(NSString *);
@end
@implementation TBSwipeDriver
- (void)tick:(CADisplayLink *)l {
    double now = tb_now_ms();
    if (self.last > 0) {
        double gap = now - self.last;
        if (gap > self.maxGap) self.maxGap = gap;
        if (gap > 20) self.slow++;   /* over 20 ms: missed the 16.7 ms vsync */
        self.frames++;
    } else self.start = now;
    self.last = now;
    TBBackSwipe *bs = g_shell.backSwipe;
    if (!self.released) {
        double f = MIN(1, (now - self.start) / MAX(1, self.ms));
        [bs move:(CGFloat)(self.frac * self.width * f)];
        if (f >= 1) {
            if (self.hold) { [l invalidate]; self.done([self report:NO]); return; }
            double secs = (now - self.start) / 1000.0;   /* the drag ends here: the finger phase, main thread driven */
            self.dragFps = secs > 0 ? self.frames / secs : 0;
            self.dragMaxGap = self.maxGap;
            self.dragMain = g_maxPass;
            self.dragSlow = self.slow;
            self.releaseAt = now;
            g_maxPass = 0;
            self.released = YES;
            [bs endWithVelocity:(CGFloat)self.vx];
        }
        return;
    }
    if (bs.active) return;
    [l invalidate];
    self.done([self report:YES]);
}
- (NSString *)report:(BOOL)ended {
    double secs = (self.last - self.start) / 1000.0;
    UINavigationController *n = g_shell.nav;
    NSDictionary *d = @{@"frames": @(self.frames), @"seconds": @(secs), @"fps": @(secs > 0 ? self.frames / secs : 0), @"slow_frames": @(self.slow),
                        @"max_frame_ms": @(self.maxGap), @"max_main_ms": @(MAX(g_maxPass, self.dragMain)), @"ended": @(ended),
                        @"drag_fps": @(self.dragFps), @"drag_max_frame_ms": @(self.dragMaxGap), @"drag_max_main_ms": @(self.dragMain), @"drag_slow_frames": @(self.dragSlow),
                        @"slide_max_main_ms": @(self.releaseAt > 0 ? g_maxPass : 0), @"slide_ms": @(self.releaseAt > 0 ? self.last - self.releaseAt : 0),
                        @"popped": @((int)n.viewControllers.count < self.before), @"depth": @(n.viewControllers.count),
                        @"top": NSStringFromClass([n.topViewController class]), @"title": n.topViewController.title ?: @""};
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:d options:0 error:NULL] encoding:NSUTF8StringEncoding];
}
@end
static TBSwipeDriver *g_swiper;
static NSString *json(NSDictionary *d);

/* Drives one Shorts swipe frame by frame (D53 gates): a finger drag over `drag` ms to 35 % of the page, then an
 * ease-out to the next page over `snap` ms, then the swipe end (the same call as the scroll view's end). Frame times
 * as TBScroller; then waits for the next Short's first new frame. */
@interface TBShortsSwiper : NSObject
@property (nonatomic, strong) TBShortsController *ctl;
@property (nonatomic) double drag, snap, start, last, maxGap, y0, h, swipeMain;
@property (nonatomic) int dir, frames, slow;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, copy) void (^done)(NSString *);
@end
@implementation TBShortsSwiper
- (void)tick:(CADisplayLink *)l {
    double now = tb_now_ms();
    if (self.last > 0) {
        double gap = now - self.last;
        if (gap > self.maxGap) self.maxGap = gap;
        if (gap > 20) self.slow++;   /* over 20 ms: missed the 16.7 ms vsync */
        self.frames++;
    } else self.start = now;
    self.last = now;
    double t = now - self.start, y;
    if (t < self.drag) y = self.y0 + self.dir * self.h * 0.35 * (t / self.drag);
    else {
        double f = MIN(1, (t - self.drag) / self.snap), e = 1 - (1 - f) * (1 - f) * (1 - f);   /* ease out */
        y = self.y0 + self.dir * self.h * (0.35 + 0.65 * e);
    }
    self.ctl.pager.contentOffset = CGPointMake(0, (CGFloat)y);
    if (t < self.drag + self.snap) return;
    [l invalidate];
    self.swipeMain = g_maxPass;
    g_maxPass = 0;
    double secs = (now - self.start) / 1000.0;
    __weak TBShortsSwiper *w = self;
    __block BOOL answered = NO;
    void (^reply)(BOOL) = ^(BOOL timedOut) {
        TBShortsSwiper *s = w;
        if (!s || answered) return;
        answered = YES;
        s.ctl.firstFrame = nil;
        NSMutableDictionary *d = [[s.ctl testState] mutableCopy];
        [d addEntriesFromDictionary:@{@"fps": @(secs > 0 ? s.frames / secs : 0), @"frames": @(s.frames), @"slow_frames": @(s.slow), @"max_frame_ms": @(s.maxGap),
                                      @"swipe_max_main_ms": @(s.swipeMain), @"to_frame_max_main_ms": @(g_maxPass), @"timed_out": @(timedOut)}];
        s.done(json(d));
    };
    self.ctl.firstFrame = ^(TBShortsController *c) { reply(NO); };
    [self.ctl pagerSettled];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ reply(YES); });
}
@end
static TBShortsSwiper *g_shorts;
static NSDictionary *thumbCounts(void);

static UINavigationController *curNav(void) { return g_shell.nav; }
static UIViewController *topVC(void) { return curNav().topViewController; }

static NSString *json(NSDictionary *d) {
    NSData *j = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    return j ? [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] : @"{}";
}

static NSString *playerState(void) {
    TBWatchController *w = [TBWatchController current];
    TBPlayerView *p = w.player;
    tb_hls_stats hs;
    tb_hls_get_stats(&hs);
    tb_http_stats ns;
    tb_http_get_stats(&ns);
    return json(@{@"video": w.videoId ?: @"", @"signed_in_path": @(p.info.signedIn), @"t": @(p.currentTime), @"dur": @(p.duration), @"playing": @(p.isPlaying), @"start_ms": @(p.startMs),
                  @"error": p.errorText ?: @"", @"ended": @(p.ended), @"audio_only": @([p audioOnly]), @"engine": [p engineIsAV] ? @"av" : @"mp", @"start_bytes": @(p.startBytes), @"fetched_bytes": @([p fetchedBytes]), @"caption": p.currentCaption ?: @"", @"cc": p.captionLang ?: @"", @"cc_tracks": [[p.info.captionTracks valueForKey:@"lang"] componentsJoinedByString:@","] ?: @"", @"quality": @(p.quality),
                  @"heights": p.availableHeights ?: @[], @"hls_segments": @(hs.segments), @"hls_errors": @(hs.errors), @"last_seg": @(hs.last_seg),
                  @"last_serve_ms": @(hs.last_serve_ms), @"tls_handshakes": @(ns.handshakes), @"tls_ms_avg": @(ns.handshakes ? ns.handshake_ms_total / ns.handshakes : 0),
                  @"requests": @(ns.requests), @"reused": @(ns.reused), @"mb_in": @(ns.bytes_in / 1048576.0),
                  @"chapters": @(w.next.chapters.count), @"related": @(w.next.related.count), @"mem_mb": @(residentMB())});
}

/* Parse cost of real responses on this CPU (Phase 0 open item: A5 JSON parse speed). */
static NSString *parseBench(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    const char *queries[2] = {"masked", "raw"};
    for (int k = 0; k < 2; k++) {
        NSString *url = k == 0 ? @"https://www.youtube.com/youtubei/v1/search?prettyPrint=false&fields=contents(sectionListRenderer(contents(itemSectionRenderer(contents(videoWithContextRenderer(videoId,headline(runs(text)),shortBylineText(runs(text)),lengthText(runs(text)),shortViewCountText(runs(text)),publishedTimeText(runs(text))))))))"
                               : @"https://www.youtube.com/youtubei/v1/search?prettyPrint=false";
        url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        const char *body = "{\"context\":{\"client\":{\"clientName\":\"MWEB\",\"clientVersion\":\"2.20260708.05.00\",\"hl\":\"en\",\"gl\":\"US\"}},\"query\":\"lofi music\"}";
        tb_req q = {.method = "POST", .url = url.UTF8String, .headers = "Content-Type: application/json\r\n", .body = body, .body_len = strlen(body), .range_start = -1};
        tb_resp r;
        int st = tb_http(&q, &r);
        if (st != 200) { tb_resp_free(&r); continue; }
        int reps = 20;
        double t0 = tb_now_ms();
        for (int i = 0; i < reps; i++) { yyjson_doc *d = yyjson_read(r.body, r.len, 0); yyjson_doc_free(d); }
        double dom = (tb_now_ms() - t0) / reps;
        t0 = tb_now_ms();
        for (int i = 0; i < reps; i++) { tb_list l; tb_yt_parse_list(r.body, r.len, &l); tb_list_free(&l); }
        double full = (tb_now_ms() - t0) / reps;
        out[@(queries[k])] = @{@"bytes": @(r.len), @"yyjson_ms": @(dom), @"parse_items_ms": @(full), @"net_ms": @(r.ms_total)};
        tb_resp_free(&r);
    }
    return json(out);
}

/* TLS: a new connection to each Google host (Phase 0 open item: handshake cost on the A5). */
static NSString *tlsBench(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *u in @[@"https://www.youtube.com/generate_204", @"https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg", @"https://suggestqueries.google.com/complete/search?client=firefox&q=a"]) {
        NSMutableArray *a = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            tb_http_close_idle();
            tb_http_stats s0, s1;
            tb_http_get_stats(&s0);
            tb_req q = {.url = u.UTF8String, .range_start = -1};
            tb_resp r;
            int st = tb_http(&q, &r);
            tb_http_get_stats(&s1);
            [a addObject:@{@"status": @(st), @"connect_ms": @(r.ms_connect), @"total_ms": @(r.ms_total),
                           @"handshake_ms": @(s1.handshake_ms_total - s0.handshake_ms_total)}];
            tb_resp_free(&r);
        }
        out[[[NSURL URLWithString:u] host]] = a;
    }
    return json(out);
}

/* Phase 0: the JS solver helper in its own process (posix_spawn from the app sandbox). */
extern char **environ;
static NSString *jsBench(NSString *name) {
    NSString *exe = [[NSBundle mainBundle] pathForResource:@"tbjs" ofType:nil];
    NSString *js = [[[NSBundle mainBundle] resourcePath] stringByAppendingFormat:@"/js/%@", name];
    NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tbjs_out.txt"];
    if (!exe) return @"{\"error\":\"no helper\"}";
    char *argv[] = {(char *)exe.fileSystemRepresentation, (char *)js.fileSystemRepresentation, (char *)out.fileSystemRepresentation, NULL};
    pid_t pid;
    double t0 = tb_now_ms();
    int rc = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    if (rc) return json(@{@"error": [NSString stringWithFormat:@"posix_spawn %d %s", rc, strerror(rc)]});
    int st = 0;
    struct rusage ru;
    wait4(pid, &st, 0, &ru);
    double ms = tb_now_ms() - t0;
    NSString *text = [NSString stringWithContentsOfFile:out encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    return json(@{@"wall_ms": @(ms), @"exit": @(WIFEXITED(st) ? WEXITSTATUS(st) : -WTERMSIG(st)), @"child_maxrss_mb": @(ru.ru_maxrss / 1048576.0),
                  @"output": text, @"app_mb": @(residentMB())});
}

static TBScroller *g_scroller;

/* Runs on the main thread. Returns the reply, or nil when the reply comes later through `later`. */
static NSString *handle(NSString *line, void (^later)(NSString *)) {
    NSArray *p = [line componentsSeparatedByString:@" "];
    NSString *cmd = p[0], *arg = p.count > 1 ? [line substringFromIndex:cmd.length + 1] : @"";
    if ([cmd isEqualToString:@"ping"]) return @"pong";
    if ([cmd isEqualToString:@"whoami"]) return @"padtube";
    if ([cmd isEqualToString:@"cpu"]) { /* user+system CPU seconds of this process so far, and app state */
        struct task_thread_times_info tt;
        mach_msg_type_number_t n = TASK_THREAD_TIMES_INFO_COUNT;
        task_info(mach_task_self(), TASK_THREAD_TIMES_INFO, (task_info_t)&tt, &n);
        struct task_basic_info bi;
        mach_msg_type_number_t n2 = TASK_BASIC_INFO_COUNT;
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&bi, &n2);
        double live = tt.user_time.seconds + tt.user_time.microseconds / 1e6 + tt.system_time.seconds + tt.system_time.microseconds / 1e6;
        double dead = bi.user_time.seconds + bi.user_time.microseconds / 1e6 + bi.system_time.seconds + bi.system_time.microseconds / 1e6;
        return json(@{@"cpu_s": @(live + dead), @"state": @([UIApplication sharedApplication].applicationState), @"mb": @(residentMB())});
    } /* scripts quit only an app that answers this */
    if ([cmd isEqualToString:@"quit"]) { /* the next install must not find this process alive in the background */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ exit(0); });
        return @"bye";
    }
    if ([cmd isEqualToString:@"mem"]) return json(@{@"mb": @(residentMB()), @"peak_mb": @(g_peakMB)});
    if ([cmd isEqualToString:@"mempeakreset"]) { g_peakMB = residentMB(); return @"ok"; }
    if ([cmd isEqualToString:@"stallreset"]) { g_maxPass = 0; return @"ok"; }
    if ([cmd isEqualToString:@"stalls"]) return json(@{@"max_main_ms": @(g_maxPass)});
    if ([cmd isEqualToString:@"state"]) {
        UIViewController *t = topVC();
        return json(@{@"tab": @(g_shell.guideIndex), @"guide_open": @(g_shell.guideOpen), @"top": NSStringFromClass([t class]), @"title": t.title ?: @"",
                      @"rows": @([t isKindOfClass:[TBListController class]] ? [(TBListController *)t items].count :
                                [t isKindOfClass:[UITableViewController class]] ? [[(UITableViewController *)t tableView] numberOfRowsInSection:0] : 0),
                      @"signed_in": @([TBAccount signedIn]), @"dark": @([TBStyle dark]), @"code": [TBAccount pendingCode] ?: @"",
                      @"orientation": @([UIApplication sharedApplication].statusBarOrientation),
                      @"full": @([TBWatchController current].isFullscreen),
                      @"player_rect": [TBWatchController current].player.window ? NSStringFromCGRect([[TBWatchController current].player convertRect:[TBWatchController current].player.bounds toView:nil]) : @"", @"presented": NSStringFromClass([g_shell.presentedViewController class]) ?: @""});
    }
    if ([cmd isEqualToString:@"tab"]) {
        [g_shell selectGuideRow:arg.intValue];
        return @"ok";
    }
    if ([cmd isEqualToString:@"back"]) { [curNav() popViewControllerAnimated:NO]; return @"ok"; }
    if ([cmd isEqualToString:@"backbutton"]) { g_maxPass = 0; [curNav() popViewControllerAnimated:YES]; return @"ok"; } /* as the header's back button */
    if ([cmd isEqualToString:@"root"]) { [curNav() popToRootViewControllerAnimated:NO]; return @"ok"; }
    if ([cmd isEqualToString:@"dump"]) { /* dump on|off: InnerTube answers to Documents/dump (pulled with afcclient) */
        NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"dump"];
        [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
        tb_yt_set_dump_dir([arg isEqualToString:@"on"] ? d.fileSystemRepresentation : NULL);
        return json(@{@"dir": d});
    }
    if ([cmd isEqualToString:@"reloadtop"]) { /* reload the top list (fresh first page) */
        UIViewController *t = topVC();
        if ([t isKindOfClass:[TBListController class]]) [(TBListController *)t reload];
        return @"ok";
    }
    if ([cmd isEqualToString:@"items"]) { /* the ids and titles of the top list, in order */
        UIViewController *t = topVC();
        if (![t isKindOfClass:[TBListController class]]) return @"error: no list";
        NSMutableArray *a = [NSMutableArray array];
        for (TBItem *it in [(TBListController *)t items]) [a addObject:@[it.ident ?: @"", @(it.kind), it.title ?: @""]];
        return json(@{@"items": a});
    }
    if ([cmd isEqualToString:@"header"]) { /* the title must end before the search field (owner 2026-11-12) */
        CGRect t = [g_shell titleFrame], f = g_shell.searchField.frame;
        return json(@{@"title_max_x": @(CGRectGetMaxX(t)), @"search_min_x": @(CGRectGetMinX(f)), @"ok": @(CGRectGetMaxX(t) <= CGRectGetMinX(f))});
    }
    if ([cmd isEqualToString:@"guide"]) { [g_shell toggleGuide]; return @"ok"; }
    if ([cmd isEqualToString:@"orient"]) { /* orient 1|3|4: turn the interface as the device would (private setter) */
        ((void (*)(id, SEL, NSInteger))objc_msgSend)([UIDevice currentDevice], NSSelectorFromString(@"setOrientation:"), (NSInteger)arg.intValue);
        [UIViewController attemptRotationToDeviceOrientation];
        return json(@{@"orientation": @([UIApplication sharedApplication].statusBarOrientation)});
    }
    if ([cmd isEqualToString:@"search"]) {
        [g_shell selectGuideRow:(NSInteger)[[TBShell guideTitles] indexOfObject:@"Search"]];
        TBSearchController *s = (TBSearchController *)curNav().topViewController;
        g_maxPass = 0;
        __weak TBSearchController *ws = s;
        s.pageLoaded = ^(TBPage *page) {
            ws.pageLoaded = nil;
            later(json(@{@"rows": @(page.items.count), @"ms": @(ws.lastLoadMs), @"net_ms": @(page.netMs), @"parse_ms": @(page.parseMs),
                         @"error": page.error ?: @"", @"max_main_ms": @(g_maxPass)}));
        };
        [g_shell search:arg];
        return nil;
    }
    if ([cmd isEqualToString:@"openvideo"]) { /* tap the first video row of the top list */
        UIViewController *t = topVC();
        if (![t isKindOfClass:[TBListController class]]) return @"error: no list";
        for (TBItem *it in [(TBListController *)t items])
            if (it.kind == TB_KIND_VIDEO) { [TBRouter openItem:it from:t]; return json(@{@"opened": it.ident}); }
        return @"error: no video row";
    }
    if ([cmd isEqualToString:@"openlist"]) { /* openlist <row>: tap a row of the top list */
        UIViewController *t = topVC();
        if (![t isKindOfClass:[TBListController class]]) return @"error: no list";
        TBListController *l = (TBListController *)t;
        NSUInteger r = (NSUInteger)arg.intValue;
        if (r >= l.items.count) return @"error: no row";
        [TBRouter openItem:l.items[r] from:l];
        return json(@{@"opened": [l.items[r] ident] ?: @""});
    }
    if ([cmd isEqualToString:@"stallms"]) { g_stall_ms = MAX(10, arg.doubleValue); return @"ok"; }
    if ([cmd isEqualToString:@"type"]) { /* type <text>: type into the search field (suggestions + keyboard) */
        [g_shell.searchField becomeFirstResponder];
        g_shell.searchField.text = arg;
        [g_shell.searchField sendActionsForControlEvents:UIControlEventEditingChanged];
        return @"ok";
    }
    if ([cmd isEqualToString:@"endtype"]) { [g_shell.searchField resignFirstResponder]; g_shell.searchField.text = @""; [g_shell.searchField sendActionsForControlEvents:UIControlEventEditingChanged]; return @"ok"; }
    if ([cmd isEqualToString:@"link"]) { /* link <url>: as a tap on a web link in a description */
        [TBLinks openURL:[NSURL URLWithString:arg] from:topVC()];
        return @"ok";
    }
    if ([cmd isEqualToString:@"dismiss"]) { [g_shell dismissViewControllerAnimated:NO completion:nil]; return @"ok"; }
    if ([cmd isEqualToString:@"open"]) { /* open <videoId>: as a tap on a row */
        g_maxPass = 0;
        [TBRouter openVideo:arg title:nil from:topVC()];
        return @"ok";
    }
    if ([cmd isEqualToString:@"waitplay"]) { /* waitplay <timeout s> */
        double end = tb_now_ms() + arg.doubleValue * 1000;
        __block void (^poll)(void);
        __block __weak void (^wpoll)(void);
        poll = ^{
            TBPlayerView *pv = [TBWatchController current].player;
            if ((pv.startMs >= 0 && pv.currentTime > 0.3) || pv.errorText.length || tb_now_ms() > end) { later(playerState()); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), wpoll);
        };
        wpoll = poll;
        poll();
        return nil;
    }
    if ([cmd isEqualToString:@"player"]) return playerState();
    if ([cmd isEqualToString:@"comments"]) { /* the Comments button of the current watch page */
        TBWatchController *w = [TBWatchController current];
        SEL sel = NSSelectorFromString(@"commentsTapped");
        if (!w || ![w respondsToSelector:sel]) return @"error: no watch page";
        ((void (*)(id, SEL))objc_msgSend)(w, sel);
        return @"ok";
    }
    if ([cmd isEqualToString:@"wtab"]) { /* wtab About|Suggested|Comments on the current watch page */
        TBWatchController *w = [TBWatchController current];
        SEL sel = NSSelectorFromString(@"selectTabTitled:");
        if (!w || ![w respondsToSelector:sel]) return @"error: no watch page";
        ((void (*)(id, SEL, id))objc_msgSend)(w, sel, arg);
        return @"ok";
    }
    if ([cmd isEqualToString:@"empty"]) { /* the empty-list text of the top list */
        UIViewController *t = topVC();
        if (![t isKindOfClass:[TBListController class]]) return @"error: no list";
        for (UIView *v in [(TBListController *)t tableView].subviews)
            if ([v isKindOfClass:[UILabel class]] && !v.hidden) return json(@{@"text": [(UILabel *)v text] ?: @""});
        return json(@{@"text": @""});
    }
    if ([cmd isEqualToString:@"engine"]) { /* engine av|mp: player engine for the next video */
        [[NSUserDefaults standardUserDefaults] setInteger:[arg isEqualToString:@"av"] ? 1 : 0 forKey:@"TBEngine"];
        return @"ok";
    }
    if ([cmd isEqualToString:@"acct"]) { /* acct like <vid> <1|0|-1> | acct wladd <vid> | acct wlrm <vid> | acct wlhas <vid> */
        NSArray *q = [arg componentsSeparatedByString:@" "];
        NSString *op = q[0], *vid = q.count > 1 ? q[1] : @"";
        if ([op isEqualToString:@"like"]) {
            [TBAccount like:vid action:q.count > 2 ? [q[2] intValue] : 1 done:^(BOOL ok) { later(json(@{@"ok": @(ok)})); }];
            return nil;
        }
        if ([op isEqualToString:@"wladd"]) { [TBAccount addToWatchLater:vid done:^(BOOL ok) { later(json(@{@"ok": @(ok)})); }]; return nil; }
        [TBCore tvBrowse:@"VLWL" continuation:nil done:^(TBPage *p) {
            TBItem *hit = nil;
            for (TBItem *it in p.items) if ([it.ident isEqualToString:vid]) hit = it;
            if ([op isEqualToString:@"wlhas"] || !hit) { later(json(@{@"has": @(hit != nil), @"rows": @(p.items.count), @"set_video_id": hit.setVideoId ?: @""})); return; }
            [TBAccount removeFromPlaylist:@"WL" setVideoId:hit.setVideoId done:^(BOOL ok) { later(json(@{@"ok": @(ok), @"removed": vid})); }];
        }];
        return nil;
    }
    if ([cmd isEqualToString:@"setq"]) { /* saved quality for the next video: 0 = Auto */
        [[NSUserDefaults standardUserDefaults] setInteger:arg.intValue forKey:@"TBQuality"];
        return @"ok";
    }
    if ([cmd isEqualToString:@"hlslog"]) {
        static char buf[8192];
        tb_hls_log(buf, sizeof buf);
        return json(@{@"log": TBStr(buf) ?: @""});
    }
    if ([cmd isEqualToString:@"seek"]) { [[TBWatchController current].player seekTo:arg.doubleValue]; return @"ok"; }
    if ([cmd isEqualToString:@"quality"]) { [[TBWatchController current].player setQuality:arg.intValue]; return @"ok"; }
    if ([cmd isEqualToString:@"cc"]) { [[TBWatchController current].player selectCaptionIndex:arg.integerValue]; return @"ok"; }
    if ([cmd isEqualToString:@"rate"]) { [[TBWatchController current].player setRate:arg.floatValue]; return @"ok"; }
    if ([cmd isEqualToString:@"pause"]) { [[TBWatchController current].player togglePlay]; return @"ok"; }
    if ([cmd isEqualToString:@"full"]) { [[TBWatchController current] toggleFullscreen]; return @"ok"; }
    if ([cmd isEqualToString:@"shorts"]) { /* open the Shorts tab; answers at the first Short's first frame (or 30 s) */
        double t0 = tb_now_ms();
        g_maxPass = 0;
        [g_shell selectGuideRow:(NSInteger)[[TBShell guideTitles] indexOfObject:@"Shorts"]];
        TBShortsController *c = (TBShortsController *)topVC();
        if (![c isKindOfClass:[TBShortsController class]]) return @"error: no Shorts tab";
        if (c.current && c.current.firstFrameMs >= 0) return json([c testState]);
        __block BOOL answered = NO;
        void (^reply)(void) = ^{
            if (answered) return;
            answered = YES;
            c.firstFrame = nil;
            NSMutableDictionary *d = [[c testState] mutableCopy];
            d[@"open_to_frame_ms"] = @(tb_now_ms() - t0);
            d[@"max_main_ms"] = @(g_maxPass);
            later(json(d));
        };
        c.firstFrame = ^(TBShortsController *x) { reply(); };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), reply);
        return nil;
    }
    if ([cmd isEqualToString:@"sfeed"]) { /* sfeed <id,id,...>: the Shorts tab with a fixed list; answers at the first frame */
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *v in [arg componentsSeparatedByString:@","]) {
            if (!v.length) continue;
            TBItem *it = [TBItem new];
            it.ident = v;
            it.title = v;
            [items addObject:it];
        }
        if (!items.count) return @"error: no ids";
        double t0 = tb_now_ms();
        [g_shell selectGuideRow:(NSInteger)[[TBShell guideTitles] indexOfObject:@"Shorts"]];
        TBShortsController *c = (TBShortsController *)topVC();
        if (![c isKindOfClass:[TBShortsController class]]) return @"error: no Shorts tab";
        __block BOOL answered = NO;
        void (^reply)(void) = ^{
            if (answered) return;
            answered = YES;
            c.firstFrame = nil;
            NSMutableDictionary *d = [[c testState] mutableCopy];
            d[@"open_to_frame_ms"] = @(tb_now_ms() - t0);
            later(json(d));
        };
        c.firstFrame = ^(TBShortsController *x) { reply(); };
        [c testFeed:items];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), reply);
        return nil;
    }
    if ([cmd isEqualToString:@"sswipe"]) { /* sswipe <1|-1> [drag ms] [snap ms] */
        TBShortsController *c = (TBShortsController *)topVC();
        if (![c isKindOfClass:[TBShortsController class]]) return @"error: not on Shorts";
        g_shorts = [TBShortsSwiper new];
        g_shorts.ctl = c;
        g_shorts.dir = [p[1] intValue] < 0 ? -1 : 1;
        g_shorts.drag = p.count > 2 ? [p[2] doubleValue] : 150;
        g_shorts.snap = p.count > 3 ? [p[3] doubleValue] : 250;
        g_shorts.h = c.pager.bounds.size.height;
        g_shorts.y0 = c.pager.contentOffset.y;
        g_shorts.done = later;
        g_maxPass = 0;
        g_shorts.link = [CADisplayLink displayLinkWithTarget:g_shorts selector:@selector(tick:)];
        [g_shorts.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        return nil;
    }
    if ([cmd isEqualToString:@"sstate"]) {
        TBShortsController *c = (TBShortsController *)topVC();
        if (![c isKindOfClass:[TBShortsController class]]) return @"error: not on Shorts";
        NSMutableDictionary *d = [[c testState] mutableCopy];
        d[@"mb"] = @(residentMB());
        d[@"peak_mb"] = @(g_peakMB);
        d[@"t"] = @(c.current.currentTime);
        return json(d);
    }
    if ([cmd isEqualToString:@"sab"]) { /* sab <prepare 0|1> <max width> [slots] [gate] [preroll] [ahead s]: Shorts A/B switches (slots: next Shorts tab) */
        [[NSUserDefaults standardUserDefaults] setBool:[p[1] intValue] == 0 forKey:@"TBShortsNoPrepare"];
        [[NSUserDefaults standardUserDefaults] setInteger:[p[2] intValue] forKey:@"TBShortsMaxWidth"];
        [[NSUserDefaults standardUserDefaults] setInteger:p.count > 3 ? [p[3] intValue] : 0 forKey:@"TBShortsSlots"];
        [[NSUserDefaults standardUserDefaults] setBool:p.count > 4 && [p[4] intValue] == 1 forKey:@"TBShortsGate"];
        [[NSUserDefaults standardUserDefaults] setBool:p.count > 5 && [p[5] intValue] == 1 forKey:@"TBShortsPreroll"];
        if (p.count > 6) [[NSUserDefaults standardUserDefaults] setDouble:[p[6] doubleValue] forKey:@"TBShortsAhead"];   /* < 0: no limit */
        else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TBShortsAhead"];   /* the built-in value */
        return @"ok";
    }
    if ([cmd isEqualToString:@"sreload"]) { /* the reload button; answers at the first new Short's first frame */
        TBShortsController *c = (TBShortsController *)topVC();
        if (![c isKindOfClass:[TBShortsController class]]) return @"error: not on Shorts";
        NSString *old = [c testState][@"video"];
        g_maxPass = 0;
        __block BOOL answered = NO;
        void (^reply)(BOOL) = ^(BOOL timedOut) {
            if (answered) return;
            answered = YES;
            c.firstFrame = nil;
            NSMutableDictionary *d = [[c testState] mutableCopy];
            d[@"old_video"] = old;
            d[@"max_main_ms"] = @(g_maxPass);
            d[@"timed_out"] = @(timedOut);
            later(json(d));
        };
        c.firstFrame = ^(TBShortsController *x) { reply(NO); };
        [c reload];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ reply(YES); });
        return nil;
    }
    if ([cmd isEqualToString:@"spull"]) { /* a pull down past the first Short and a release: the scroll view's own calls */
        TBShortsController *c = (TBShortsController *)topVC();
        if (![c isKindOfClass:[TBShortsController class]]) return @"error: not on Shorts";
        NSString *old = [c testState][@"video"];
        c.pager.contentOffset = CGPointMake(0, -100);
        [(id<UIScrollViewDelegate>)c scrollViewDidScroll:c.pager];
        [(id<UIScrollViewDelegate>)c scrollViewDidEndDragging:c.pager willDecelerate:NO];
        c.pager.contentOffset = CGPointZero;
        __block BOOL answered = NO;
        void (^reply)(BOOL) = ^(BOOL timedOut) {
            if (answered) return;
            answered = YES;
            c.firstFrame = nil;
            NSMutableDictionary *d = [[c testState] mutableCopy];
            d[@"old_video"] = old;
            d[@"timed_out"] = @(timedOut);
            later(json(d));
        };
        c.firstFrame = ^(TBShortsController *x) { reply(NO); };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ reply(YES); });
        return nil;
    }
    if ([cmd isEqualToString:@"solver"]) { /* TBSolver state; "solver wait" prepares first (background) */
        if ([arg isEqualToString:@"wait"]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                double t0 = tb_now_ms();
                int sts = 0;
                BOOL ok = [TBSolver waitReady:&sts];
                NSMutableDictionary *d = [[TBSolver state] mutableCopy];
                d[@"wait_ms"] = @(tb_now_ms() - t0);
                d[@"ok"] = @(ok);
                NSString *o = json(d);
                dispatch_async(dispatch_get_main_queue(), ^{ later(o); });
            });
            return nil;
        }
        return json([TBSolver state]);
    }
    if ([cmd isEqualToString:@"solverbench"]) { /* D62 option A on the A5: C preprocess (tb_jsprep) + iOS 6 JavaScriptCore */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            NSMutableDictionary *R = [NSMutableDictionary dictionary];
            double t, mb0 = residentMB();
            tb_req q = {.url = "https://www.youtube.com/iframe_api", .range_start = -1, .timeout_ms = 15000};
            tb_resp r;
            NSString *ver = nil;
            if (tb_http(&q, &r) == 200) {
                NSString *b = [[NSString alloc] initWithBytes:r.body length:r.len encoding:NSUTF8StringEncoding];
                NSRange m = [b rangeOfString:@"player\\\\/[0-9a-f]{8}\\\\/" options:NSRegularExpressionSearch];
                if (m.location != NSNotFound) ver = [b substringWithRange:NSMakeRange(m.location + 8, 8)];
            }
            tb_resp_free(&r);
            R[@"player_version"] = ver ?: @"";
            char *pre = NULL;
            size_t plen = 0;
            if (ver) {
                NSString *u = [NSString stringWithFormat:@"https://www.youtube.com/s/player/%@/player_ias.vflset/en_US/base.js", ver];
                tb_req pq = {.url = u.UTF8String, .range_start = -1, .timeout_ms = 30000};
                t = tb_now_ms();
                if (tb_http(&pq, &r) == 200) {
                    R[@"player_download_ms"] = @(tb_now_ms() - t);
                    R[@"player_bytes"] = @(r.len);
                    int cands = 0;
                    const char *perr = NULL;
                    g_peakMB = residentMB();
                    t = tb_now_ms();
                    pre = tb_jsprep(r.body, r.len, &plen, &cands, &perr);
                    R[@"prep_ms"] = @(tb_now_ms() - t);
                    R[@"prep_peak_mb"] = @(g_peakMB - mb0);
                    R[@"prep_candidates"] = @(cands);
                    R[@"prep_error"] = perr ? @(perr) : @"";
                    R[@"preprocessed_bytes"] = @(plen);
                }
                tb_resp_free(&r);
            }
            if (pre) @autoreleasepool {
                NSString *ps = [[NSString alloc] initWithBytesNoCopy:pre length:plen encoding:NSUTF8StringEncoding freeWhenDone:YES];
                NSString *err = nil;
                TBJS *js = [TBJS new];
                [js setString:ps forName:@"__pre"];
                ps = nil;
                g_peakMB = residentMB();
                t = tb_now_ms();
                NSString *ok = [js eval:@"var __s = {n: null, sig: null}, __r; try { Function('_result', __pre)(__s); __r = typeof __s.n + ',' + typeof __s.sig; }"
                                         " catch (e) { var L = __pre.split('\\n'), k = (e.line || 1) - 1; __r = 'LOAD ERROR ' + e + ' line ' + e.line + ' :: ' +"
                                         " [k - 2, k - 1, k, k + 1].map(function (i) { return i + ':' + String(L[i]).slice(0, 160); }).join(' || '); } __pre = null; __r"
                                    name:@"load" error:&err];
                R[@"load_ms"] = @(tb_now_ms() - t);
                R[@"load_peak_mb"] = @(g_peakMB - mb0);
                R[@"load_result"] = ok ?: @"";
                for (int i = 0; i < 3; i++) {
                    t = tb_now_ms();
                    NSString *v = [js eval:[NSString stringWithFormat:@"__s.n('Btt65kkPiCOu5L_xK%d') + '|' + __s.sig('AE0s2JYwRQIgRqKqaFZu_n-QDzU3SYnfW_6c83=WD-TJPdju1fStmPsCIQDfAQAb3GbBgPamHV0jR-lm6VQzFqNiPxrPrXj8I40P3w=Aw=o=o')", i]
                                  name:@"solve" error:&err];
                    R[[NSString stringWithFormat:@"solve_%d_ms", i]] = @(tb_now_ms() - t);
                    if (i == 0) R[@"solve_result"] = v ?: @"";
                }
                R[@"steady_mb"] = @(residentMB() - mb0);
                R[@"error"] = err ?: @"";
            }
            NSString *out = json(R);
            dispatch_async(dispatch_get_main_queue(), ^{ later(out); });
        });
        return nil;
    }
    if ([cmd isEqualToString:@"lostsim"]) { /* the "session lost" path without signing out: the code must show at once */
        [[NSNotificationCenter defaultCenter] postNotificationName:TBAccountSessionLost object:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIViewController *t = topVC();
            NSString *code = [TBAccount pendingCode] ?: @"";
            later(json(@{@"top": NSStringFromClass([t class]), @"code_shown": @(code.length > 0), @"signed_in": @([TBAccount signedIn])}));
        });
        return nil;
    }
    if ([cmd isEqualToString:@"cancelsignin"]) { [TBAccount cancelSignIn]; return @"ok"; }
    if ([cmd isEqualToString:@"authcheck"]) { /* sign-in state, token expiry, one refresh, one TV list call; no secret is returned */
        NSDictionary *before = [TBAccount authState];
        dispatch_async([TBCore queue], ^{
            BOOL refreshed = [TBAccount signedIn] ? [TBAccount refreshNow] : NO;
            tb_list l;
            int rc = [TBAccount signedIn] ? tb_yt_tv_browse("FEwhat_to_watch", NULL, &l) : -1;
            int rows = rc == 0 ? l.n : 0;
            if (rc == 0) tb_list_free(&l);
            NSDictionary *after = [TBAccount authState];
            dispatch_async(dispatch_get_main_queue(), ^{
                later(json(@{@"before": before, @"refresh_ok": @(refreshed), @"after": after, @"tv_home_rc": @(rc), @"tv_home_rows": @(rows)}));
            });
        });
        return nil;
    }
    if ([cmd isEqualToString:@"pprobe"]) { /* pprobe <videoId>: each client with and without the account token */
        NSString *vid = arg;
        dispatch_async([TBCore queue], ^{
            NSMutableArray *rows = [NSMutableArray array];
            for (NSString *c in @[@"VISIONOS", @"IOS", @"TVHTML5", @"TVHTML5_SIMPLY_EMBEDDED_PLAYER"])
                for (int tok = 0; tok < 2; tok++) {
                    tb_yt_probe pr;
                    tb_yt_probe_player(c.UTF8String, vid.UTF8String, tok, &pr);
                    [rows addObject:@{@"client": c, @"token": @(tok), @"http": @(pr.http), @"status": TBStr(pr.status) ?: @"", @"reason": TBStr(pr.reason) ?: @"",
                                      @"formats": @(pr.formats), @"avc": @(pr.avc), @"direct": @(pr.direct), @"ciphered": @(pr.ciphered), @"n_param": @(pr.n_param), @"hls": @(pr.hls)}];
                }
            dispatch_async(dispatch_get_main_queue(), ^{ later(json(@{@"video": vid, @"rows": rows})); });
        });
        return nil;
    }
    if ([cmd isEqualToString:@"sheader"]) { /* the header button of the top screen: its frame and action (for the Shorts reload) */
        UIViewController *t = topVC();
        BOOL has = [t respondsToSelector:@selector(headerButton)];
        return json(@{@"has_button": @(has), @"title_frame": NSStringFromCGRect([g_shell titleFrame])});
    }
    if ([cmd isEqualToString:@"net"]) { /* bytes from the network so far (all tb_http requests) and CPU seconds */
        tb_http_stats ns;
        tb_http_get_stats(&ns);
        struct task_thread_times_info tt;
        mach_msg_type_number_t n = TASK_THREAD_TIMES_INFO_COUNT;
        task_info(mach_task_self(), TASK_THREAD_TIMES_INFO, (task_info_t)&tt, &n);
        struct task_basic_info bi;
        mach_msg_type_number_t n2 = TASK_BASIC_INFO_COUNT;
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&bi, &n2);
        double cpu = tt.user_time.seconds + tt.user_time.microseconds / 1e6 + tt.system_time.seconds + tt.system_time.microseconds / 1e6 +
                     bi.user_time.seconds + bi.user_time.microseconds / 1e6 + bi.system_time.seconds + bi.system_time.microseconds / 1e6;
        UIDevice *d = [UIDevice currentDevice];
        d.batteryMonitoringEnabled = YES;
        tb_yt_counts yc;
        tb_yt_get_counts(&yc);
        TBLog(@"PadTube: net mark %@ %lld B", arg, (long long)ns.bytes_in);   /* finds the window in the syslog */
        return json(@{@"bytes_in": @(ns.bytes_in), @"requests": @(ns.requests), @"cpu_s": @(cpu), @"battery": @(d.batteryLevel), @"battery_state": @(d.batteryState),
                      @"player_calls": @(yc.player_calls), @"login_required": @(yc.login_required), @"visitor_resets": @(yc.visitor_resets)});
    }
    if ([cmd isEqualToString:@"stap"]) { [(TBShortsController *)topVC() togglePause]; return @"ok"; }
    if ([cmd isEqualToString:@"scomments"]) { [(TBShortsController *)topVC() openComments]; return @"ok"; }
    if ([cmd isEqualToString:@"sshare"]) { /* sshare open|close */
        UIViewController *t = topVC();
        if (![t isKindOfClass:[TBShortsController class]]) return @"error: not on Shorts";
        [(TBShortsController *)t share:![arg isEqualToString:@"close"]];
        return @"ok";
    }
    if ([cmd isEqualToString:@"thumbs"]) return json(thumbCounts());   /* visible grid tiles: images smaller than the tile */
    if ([cmd isEqualToString:@"bswipe"]) { /* bswipe <ms> <frac> <vx> | bswipe hold <frac> <ms> | bswipe release <vx> */
        TBBackSwipe *bs = g_shell.backSwipe;
        BOOL release = [p[1] isEqualToString:@"release"], hold = [p[1] isEqualToString:@"hold"];
        if (release) {
            if (!bs.active || !g_swiper) return @"error: no swipe held";
            g_swiper.released = YES;
            g_swiper.hold = NO;
            g_swiper.last = 0; g_swiper.frames = 0; g_swiper.slow = 0; g_swiper.maxGap = 0;   /* time the slide only */
            g_swiper.done = later;
            g_maxPass = 0;
            [bs endWithVelocity:(CGFloat)[p[2] doubleValue]];
            g_swiper.link = [CADisplayLink displayLinkWithTarget:g_swiper selector:@selector(tick:)];
            [g_swiper.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            return nil;
        }
        if (p.count < 4) return @"error: usage";
        g_maxPass = 0;
        int before = (int)curNav().viewControllers.count;
        if (![bs begin]) return [NSString stringWithFormat:@"error: swipe did not begin (depth %lu, active %d, top %@)",
                                 (unsigned long)curNav().viewControllers.count, bs.active, NSStringFromClass([topVC() class])];
        g_swiper = [TBSwipeDriver new];
        g_swiper.before = before;
        g_swiper.width = curNav().view.bounds.size.width;
        g_swiper.hold = hold;
        g_swiper.frac = [p[2] doubleValue];
        g_swiper.ms = hold ? [p[3] doubleValue] : [p[1] doubleValue];
        g_swiper.vx = hold ? 0 : [p[3] doubleValue];
        g_swiper.done = later;
        g_swiper.link = [CADisplayLink displayLinkWithTarget:g_swiper selector:@selector(tick:)];
        [g_swiper.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        return nil;
    }
    if ([cmd isEqualToString:@"edgecheck"]) { /* edgecheck <x> <y>: would a touch there start a swipe back? (interface points) */
        CGPoint pt = CGPointMake([p[1] doubleValue], [p[2] doubleValue]);
        CGPoint w = [g_shell.view convertPoint:pt toView:nil];
        UIView *hit = [g_shell.view.window hitTest:w withEvent:nil];
        return json(@{@"accept": @([g_shell.backSwipe acceptsTouchAtWindowPoint:w]), @"view": NSStringFromClass([hit class]) ?: @""});
    }
    if ([cmd isEqualToString:@"dtap"]) { /* dtap <x fraction>: a double tap at that place across the player */
        TBPlayerView *pv = [TBWatchController current].player;
        double t = pv.currentTime;
        int s = [pv doubleTapAt:CGPointMake(pv.bounds.size.width * (CGFloat)arg.doubleValue, pv.bounds.size.height / 2)];
        return json(@{@"skipped": @(s), @"t_before": @(t)});
    }
    if ([cmd isEqualToString:@"fswipe"]) { /* a swipe down on the video */
        return json(@{@"handled": @([[TBWatchController current].player swipedDown])});
    }
    if ([cmd isEqualToString:@"wswipe"]) { /* wswipe 1|-1: a swipe left (next tab) or right on the watch page */
        TBWatchController *w = [TBWatchController current];
        if (!w) return @"error: no watch page";
        return json(@{@"tab": [w swipeTab:arg.intValue]});
    }
    if ([cmd isEqualToString:@"scroll"]) { /* scroll <seconds> <points per second> */
        UIViewController *t = topVC();
        UIScrollView *v = [t isKindOfClass:[UITableViewController class]] ? [(UITableViewController *)t tableView] : nil;
        if ([t isKindOfClass:[TBWatchController class]]) {
            for (UIView *s in t.view.subviews) if ([s isKindOfClass:[UITableView class]]) v = (UIScrollView *)s;
        }
        if (!v) return @"error: no table";
        g_scroller = [TBScroller new];
        g_scroller.view = v;
        g_scroller.speed = p.count > 2 ? [p[2] doubleValue] : 1500;
        g_scroller.direction = 1;
        g_scroller.endAt = tb_now_ms() + [p[1] doubleValue] * 1000;
        g_scroller.done = later;
        g_maxPass = 0;
        g_scroller.link = [CADisplayLink displayLinkWithTarget:g_scroller selector:@selector(tick:)];
        [g_scroller.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        return nil;
    }
    if ([cmd isEqualToString:@"theme"]) { /* theme 0|1: Light / Dark (DUC-SET-THEME); answers after the rebuild */
        [TBStyle setDark:arg.intValue == 1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            later(json(@{@"dark": @([TBStyle dark]), @"tab": @(g_shell.guideIndex)}));
        });
        return nil;
    }
    if ([cmd isEqualToString:@"suspend"]) { /* background the app as the home button does (private UIApplication call) */
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        return @"ok";
    }
    if ([cmd isEqualToString:@"signin"]) { /* opens the Account screen and taps "Get a sign-in code" */
        [g_shell selectGuideRow:(NSInteger)[[TBShell guideTitles] indexOfObject:@"Account"]];
        TBAccountController *ac = (TBAccountController *)curNav().topViewController;
        if (![ac isKindOfClass:[TBAccountController class]]) return @"error: no account screen";
        [ac startSignIn];
        __block int tries = 0;
        __block __weak void (^wp)(void);
        void (^p)(void) = ^{
            if (ac.shownCode.length || ++tries > 100) { later(json(@{@"code": ac.shownCode ?: @"", @"signed_in": @([TBAccount signedIn])})); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), wp);
        };
        wp = p;
        p();
        return nil;
    }
    if ([cmd isEqualToString:@"parsebench"]) {
        dispatch_async([TBCore queue], ^{ NSString *r = parseBench(); dispatch_async(dispatch_get_main_queue(), ^{ later(r); }); });
        return nil;
    }
    if ([cmd isEqualToString:@"jsbench"]) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{ NSString *r = jsBench(arg); dispatch_async(dispatch_get_main_queue(), ^{ later(r); }); });
        return nil;
    }
    if ([cmd isEqualToString:@"tlsbench"]) {
        dispatch_async([TBCore queue], ^{ NSString *r = tlsBench(); dispatch_async(dispatch_get_main_queue(), ^{ later(r); }); });
        return nil;
    }
    return [@"error: unknown " stringByAppendingString:cmd];
}

static void *controlThread(void *a) {
    @autoreleasepool {
    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = {.sin_family = AF_INET};
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    int port = 0;
    for (int tries = 0; !port && tries < 20; tries++) { /* an old instance that is quitting frees its port soon */
        for (int p = PORT_FIRST; p <= PORT_LAST && !port; p++) {
            sa.sin_port = htons(p);
            if (bind(ls, (struct sockaddr *)&sa, sizeof sa) == 0) port = p;
        }
        if (!port) usleep(500000);
    }
    if (!port) { NSLog(@"PTSELFTEST listen failed"); return NULL; }
    NSLog(@"PTSELFTEST port %d", port);
    listen(ls, 4);
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) continue;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        FILE *in = fdopen(dup(fd), "r");
        char buf[2048];
        while (fgets(buf, sizeof buf, in)) @autoreleasepool {
            buf[strcspn(buf, "\r\n")] = 0;
            NSString *line = [NSString stringWithUTF8String:buf] ?: @"";
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block NSString *reply = nil;
            void (^later)(NSString *) = ^(NSString *r) { reply = r; dispatch_semaphore_signal(sem); };
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *r = handle(line, later);
                if (r) later(r);
            });
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            NSString *out = [reply stringByAppendingString:@"\n"];
            send(fd, out.UTF8String, strlen(out.UTF8String), 0);
        }
        fclose(in);
        close(fd);
    }
    }
    return NULL;
}

@implementation TBSelfTest
/* Launch thumbnail sampler (owner bug 2026-11-13 "thumbnails blurred for a few seconds"): every 100 ms for 15 s,
 * the visible grid tiles of the top list: how many show an image, and how many images have fewer pixels than the
 * tile (shown scaled up = blurred). Logged as PTTHUMBS when a number changes. */
static NSDictionary *thumbCounts(void) {
    UIViewController *t = topVC();
    UITableView *tv = [t isKindOfClass:[UITableViewController class]] ? [(UITableViewController *)t tableView] : nil;
    int tiles = 0, img = 0, small = 0, minW = 9999, maxTile = 0;
    Class tileClass = NSClassFromString(@"TBTile");
    for (UITableViewCell *c in tv.visibleCells)
        for (UIView *v in c.contentView.subviews) {
            if (![v isKindOfClass:tileClass] || v.hidden) continue;
            UIImageView *th = [v valueForKey:@"_thumb"];
            tiles++;
            int tw = (int)(th.bounds.size.width * [UIScreen mainScreen].scale);
            maxTile = MAX(maxTile, tw);
            if (!th.image) continue;
            img++;
            int iw = (int)(th.image.size.width * th.image.scale);
            minW = MIN(minW, iw);
            if (iw < tw - 2) small++;
        }
    return @{@"tiles": @(tiles), @"img": @(img), @"small": @(small), @"min_img_px": @(img ? minW : 0), @"tile_px": @(maxTile)};
}

static void sampleThumbs(double t0, NSString *last) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        double t = tb_now_ms() - t0;
        NSDictionary *d = thumbCounts();
        NSString *line = [NSString stringWithFormat:@"tiles=%@ img=%@ small=%@ min_img_px=%@ tile_px=%@", d[@"tiles"], d[@"img"], d[@"small"], d[@"min_img_px"], d[@"tile_px"]];
        if (![line isEqualToString:last]) NSLog(@"PTTHUMBS t=%.0f %@", t, line);
        if (t < 15000) sampleThumbs(t0, line);
    });
}

+ (void)startWithShell:(TBShell *)shell {
    (void)shell;
    sampleThumbs(tb_now_ms(), @"");
    g_obs = CFRunLoopObserverCreate(NULL, kCFRunLoopAfterWaiting | kCFRunLoopBeforeWaiting, true, 0, loopObserver, NULL);
    CFRunLoopAddObserver(CFRunLoopGetMain(), g_obs, kCFRunLoopCommonModes);
    pthread_t t;
    pthread_create(&t, NULL, controlThread, NULL);
    pthread_create(&t, NULL, memSampler, NULL);
    g_main_thread = mach_thread_self();
    pthread_create(&t, NULL, stallSampler, NULL);

}
@end
