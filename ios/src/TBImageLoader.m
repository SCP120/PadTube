#import "TBImageLoader.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#include "tb_http.h"
#include <pthread.h>

/* 12 MB = 54 decoded mqdefault thumbnails (research-efficiency §5, RetroTube's totalCostLimit). */
static const NSUInteger kRamLimit = 12 * 1024 * 1024;
/* Disk: 1,600-4,000 JPEGs at 10-25 KB each (MEASURED sizes); trimmed at start, oldest first. */
static const unsigned long long kDiskLimit = 40ULL * 1024 * 1024;

/* One request. Not an NSOperation: reading NSOperationQueue.operations on the main thread waited 31-40 ms on the
 * queue lock during grid scrolls (stall sampler, R1 2026-11-12). */
@interface TBImageOp : NSObject
@property (atomic) BOOL cancelled, started;
@property (nonatomic, copy) NSString *url, *key;
@property (nonatomic) CGSize size;
@property (nonatomic, strong) NSMutableArray *waiters;
@end

static NSCache *g_ram;
/* LIFO worker pool: the main thread pushes under a short mutex; workers take the newest request first
 * (earlier ones are for rows that scrolled away). 4 at once: iOS 6 NSURLConnection stalls at 5 (research-efficiency §6). */
static const int kWorkers = 4;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray *g_stack;   /* waiting ops, newest last; g_mu */
static int g_running;             /* workers alive; g_mu */
static NSMutableDictionary *g_ops; /* key -> op, main thread only */
static NSString *g_dir;
static NSUInteger g_ramBytes;

static NSString *hashName(NSString *s) {
    unsigned char d[CC_SHA1_DIGEST_LENGTH];
    NSData *b = [s dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA1(b.bytes, (CC_LONG)b.length, d);
    NSMutableString *o = [NSMutableString string];
    for (int i = 0; i < 10; i++) [o appendFormat:@"%02x", d[i]];
    return o;
}

static UIImage *decode(NSData *data, CGSize px) {
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    CGImageRef raw = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!raw) return nil;
    size_t w = (size_t)px.width, h = (size_t)px.height;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(raw); return nil; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    /* aspect fill: crop the letterbox of 4:3 images */
    double iw = CGImageGetWidth(raw), ih = CGImageGetHeight(raw), s = MAX(w / iw, h / ih);
    CGRect r = CGRectMake((w - iw * s) / 2, (h - ih * s) / 2, iw * s, ih * s);
    CGContextDrawImage(ctx, r, raw);
    CGImageRelease(raw);
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    UIImage *img = [UIImage imageWithCGImage:out scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(out);
    return img;
}

@implementation TBImageOp
- (void)run {
    if (self.cancelled) return;
    NSString *path = [g_dir stringByAppendingPathComponent:hashName(self.url)];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        tb_req q = {.url = self.url.UTF8String, .range_start = -1, .timeout_ms = 10000};
        tb_resp r;
        if (tb_http(&q, &r) == 200 && r.len > 0) {
            data = [NSData dataWithBytes:r.body length:r.len];
            [data writeToFile:path atomically:NO];
        }
        tb_resp_free(&r);
    }
    if (self.cancelled) return;
    UIImage *img = data ? decode(data, self.size) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (img) {
            NSUInteger cost = (NSUInteger)(self.size.width * self.size.height * 4);
            [g_ram setObject:img forKey:self.key cost:cost];
            g_ramBytes += cost;
        }
        [g_ops removeObjectForKey:self.key];
        for (void (^w)(UIImage *) in self.waiters) w(img);
    });
}
@end

@implementation TBImageLoader

+ (void)initialize {
    if (self != [TBImageLoader class]) return;
    g_ram = [NSCache new];
    g_ram.totalCostLimit = kRamLimit;
    g_stack = [NSMutableArray array];
    g_ops = [NSMutableDictionary dictionary];
    g_dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"img"];
    [[NSFileManager defaultManager] createDirectoryAtPath:g_dir withIntermediateDirectories:YES attributes:nil error:NULL];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{ [self trimDisk]; });
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearMemory) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

+ (void)trimDisk {
    NSFileManager *fm = [NSFileManager new];
    NSArray *names = [fm contentsOfDirectoryAtPath:g_dir error:NULL];
    NSMutableArray *files = [NSMutableArray array];
    unsigned long long total = 0;
    for (NSString *n in names) {
        NSString *p = [g_dir stringByAppendingPathComponent:n];
        NSDictionary *a = [fm attributesOfItemAtPath:p error:NULL];
        total += a.fileSize;
        [files addObject:@[a.fileModificationDate ?: [NSDate distantPast], p, @(a.fileSize)]];
    }
    if (total <= kDiskLimit) return;
    [files sortUsingComparator:^NSComparisonResult(NSArray *x, NSArray *y) { return [x[0] compare:y[0]]; }];
    for (NSArray *f in files) {
        if (total <= kDiskLimit * 3 / 4) break;
        [fm removeItemAtPath:f[1] error:NULL];
        total -= [f[2] unsignedLongLongValue];
    }
}

+ (id)load:(NSString *)url pixelSize:(CGSize)size done:(void (^)(UIImage *))done {
    if (!url.length) { done(nil); return nil; }
    NSString *key = [NSString stringWithFormat:@"%@#%dx%d", url, (int)size.width, (int)size.height];
    UIImage *img = [g_ram objectForKey:key];
    if (img) { done(img); return nil; }
    TBImageOp *op = g_ops[key];
    void (^w)(UIImage *) = [done copy];
    if (op) { [op.waiters addObject:w]; return @[op, w]; }
    op = [TBImageOp new];
    op.url = url;
    op.key = key;
    op.size = size;
    op.waiters = [NSMutableArray arrayWithObject:w];
    g_ops[key] = op;
    BOOL spawn;
    pthread_mutex_lock(&g_mu);
    [g_stack addObject:op];
    spawn = g_running < kWorkers;
    if (spawn) g_running++;
    pthread_mutex_unlock(&g_mu);
    if (spawn) dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self work]; });
    return @[op, w];
}

/* worker: newest waiting op first, until none is left */
+ (void)work {
    for (;;) {
        pthread_mutex_lock(&g_mu);
        TBImageOp *op = g_stack.lastObject;
        if (op) { [g_stack removeLastObject]; op.started = YES; }
        else g_running--;
        pthread_mutex_unlock(&g_mu);
        if (!op) return;
        @autoreleasepool { [op run]; }
    }
}

+ (void)cancel:(id)token {
    if (!token) return;
    TBImageOp *op = token[0];
    [op.waiters removeObject:token[1]];
    if (op.waiters.count) return;
    pthread_mutex_lock(&g_mu);
    BOOL waiting = !op.started;
    if (waiting) [g_stack removeObjectIdenticalTo:op];
    pthread_mutex_unlock(&g_mu);
    if (!waiting) return;   /* running: it finishes and fills the cache */
    op.cancelled = YES;
    [g_ops removeObjectForKey:op.key];
}

+ (void)clearMemory {
    [g_ram removeAllObjects];
    g_ramBytes = 0;
}

+ (NSUInteger)memoryBytes { return MIN(g_ramBytes, kRamLimit); }
@end
