#import "TBShortsPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "TBCore.h"
#import "TBLog.h"
#include "tb_hls.h"
#include "tb_http.h"
#include "tb_stream.h"

static void *kStatusCtx = &kStatusCtx, *kReadyCtx = &kReadyCtx;

/* AVFoundation work that blocks the main thread on the A5 (stall sampler, MEASURED 2026-11-13): an asset's creation
 * (FigAssetRemoteCreateWithURL -> keychain look-up, 115 ms) and the last release of an item (FigBaseObjectFinalize,
 * 101-115 ms). Both are done on this queue. */
static dispatch_queue_t avQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("padtube.shorts.av", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static void releaseLater(id obj) {   /* after the main thread's autorelease pool has let go of it */
    if (!obj) return;
    __block id o = obj;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), avQueue(), ^{ o = nil; });
}

@interface TBShortsLayerView : UIView
@end
@implementation TBShortsLayerView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@implementation TBShortsPlayer {
    AVPlayer *_player;
    AVPlayerItem *_item;
    id _boundary;
    tb_stream *_stream;
    int _gen, _stalls;
    double _loadAt, _playAt;
    BOOL _resumeOnActive;
}

+ (void)makePlayers:(int)n done:(void (^)(NSArray *))done {
    dispatch_async(avQueue(), ^{
        NSMutableArray *av = [NSMutableArray array];
        for (int i = 0; i < n; i++) [av addObject:[AVPlayer new]];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *ps = [NSMutableArray array];
            for (AVPlayer *p in av) [ps addObject:[[TBShortsPlayer alloc] initWithPlayer:p]];
            done(ps);
        });
    });
}

- (id)initWithPlayer:(AVPlayer *)player {
    if (!(self = [super init])) return nil;
    _player = player;
    _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    TBShortsLayerView *v = [TBShortsLayerView new];
    v.userInteractionEnabled = NO;
    v.backgroundColor = [UIColor clearColor];   /* the cover under it shows until the first frame (D55) */
    AVPlayerLayer *l = (AVPlayerLayer *)v.layer;
    l.player = _player;
    l.videoGravity = AVLayerVideoGravityResizeAspect;
    [l addObserver:self forKeyPath:@"readyForDisplay" options:0 context:kReadyCtx];
    _view = v;
    _gen = -1;
    _firstFrameMs = -1;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(resign) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(active) name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self unload];
    [_view.layer removeObserver:self forKeyPath:@"readyForDisplay" context:kReadyCtx];
}

- (void)notify { if (self.changed) self.changed(self); }

- (void)load:(NSString *)videoId { [self load:videoId info:nil]; }

- (void)reserve:(NSString *)videoId {
    BOOL pre = _preloadOnly;
    [self unload];
    _preloadOnly = pre;
    _videoId = [videoId copy];
    _loadAt = tb_now_ms();
}

- (void)load:(NSString *)videoId info:(TBPlayerInfo *)cached {
    /* play may come between reserve: and this load (the answer arrives later): keep it (device bug 2026-11-13) */
    BOOL pre = _preloadOnly, keepPlay = _wantsPlay && [_videoId isEqualToString:videoId];
    double playAt = _playAt, loadAt = [_videoId isEqualToString:videoId] ? _loadAt : tb_now_ms();
    [self unload];
    _preloadOnly = pre;
    _videoId = [videoId copy];
    _loadAt = loadAt;
    if (keepPlay) { _wantsPlay = YES; _playAt = playAt; }
    if (cached) { [self start:cached]; return; }
    __weak TBShortsPlayer *w = self;
    [TBCore player:videoId done:^(TBPlayerInfo *info) {
        TBShortsPlayer *s = w;
        if (!s || ![s->_videoId isEqualToString:videoId]) return;   /* another Short was loaded since */
        [s start:info];
    }];
}

/* Forward-buffer limit (D67): the server serves only segments that start at most this many seconds after the play
 * position. Without it AVPlayer buffers up to about 50 s ahead and a swipe drops it (D66, MEASURED). The value is the
 * result of the iPad A/B in docs/STATUS.md; TBShortsAhead (self-test) overrides it, < 0: no limit. */
static const double kAhead = 10;
static double aheadLimit(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"TBShortsAhead"];
    return v ? [v doubleValue] : kAhead;
}

/* 720 wide at 30 fps or less, else 480 wide (D54); a video that is not vertical: its highest height <= 720 */
static TBFormat *pickFormat(TBPlayerInfo *info) {
    TBFormat *best = nil;
    int maxW = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"TBShortsMaxWidth"] ?: 720;   /* self-test A/B */
    for (TBFormat *f in info.portraitFormats) {
        if (f.width == 720 && f.fps <= 30 && maxW >= 720) return f;
        if (f.width <= 480) best = f;
    }
    return best ?: info.videoFormats.lastObject;
}

- (void)start:(TBPlayerInfo *)info {
    _info = info;
    TBFormat *v = [info.status isEqualToString:@"OK"] ? pickFormat(info) : nil;
    TBFormat *a = nil;
    for (TBFormat *f in info.audioFormats) if (!a || f.audioDefault) a = f;
    if (!v || !a) {
        _errorText = [info.status isEqualToString:@"OK"] ? @"No H.264 / AAC format for this Short." : TBPlayerProblem(info);
        [self notify];
        return;
    }
    tb_stream_fmt vf = {v.itag, (char *)v.url.UTF8String, v.width, v.height, v.bitrate, v.indexEnd, v.contentLength};
    tb_stream_fmt af = {a.itag, (char *)a.url.UTF8String, 0, 0, a.bitrate, a.indexEnd, a.contentLength};
    TBLog(@"PadTube: Short %@ format itag %d %dx%d %d fps %d kbit/s, video %lld B, audio %lld B, %d s", _videoId, v.itag, v.width, v.height,
          v.fps, v.bitrate / 1000, v.contentLength, a.contentLength, info.lengthSeconds);
    _stream = tb_stream_new(&vf, 1, &af);
    _gen = _stream ? tb_hls_add(_stream) : -1;
    if (_gen < 0) { _errorText = @"Player not ready."; [self notify]; return; }
    if (_preloadOnly && gateOn()) tb_hls_limit(_gen, 0);
    [self limitTick:_gen];
    tb_stream_warm(_stream, 0, 0);   /* the first segment downloads now */
    char url[128];
    tb_hls_url_gen(_gen, 0, url, sizeof url);
    NSURL *u = [NSURL URLWithString:TBStr(url)];
    NSString *vid = _videoId;
    __weak TBShortsPlayer *w = self;
    dispatch_async(avQueue(), ^{
        AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:[AVURLAsset URLAssetWithURL:u options:nil]];
        dispatch_async(dispatch_get_main_queue(), ^{
            TBShortsPlayer *s = w;
            if (!s || ![s->_videoId isEqualToString:vid]) { releaseLater(item); return; }
            [s use:item];
        });
    });
    [self notify];
}

/* once a second while this stream is loaded: the time limit follows the play position (a loop starts it again at 0) */
- (void)limitTick:(int)gen {
    if (gen < 0 || gen != _gen) return;
    double a = aheadLimit();
    tb_hls_limit_time(gen, a < 0 ? -1 : self.currentTime + a);
    __weak TBShortsPlayer *w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [w limitTick:gen]; });
}

- (void)stalled:(NSNotification *)n {
    _stalls++;
    TBLog(@"PadTube: Short %@ playback stalled at %.1f s (%.1f s buffered ahead)", _videoId, self.currentTime, self.bufferedAhead);
}

- (void)use:(AVPlayerItem *)item {
    _item = item;
    _stalls = 0;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stalled:) name:AVPlayerItemPlaybackStalledNotification object:_item];
    [_item addObserver:self forKeyPath:@"status" options:0 context:kStatusCtx];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [_player replaceCurrentItemWithPlayerItem:_item];
    __weak TBShortsPlayer *w = self;
    /* the first new frame after the start: 1/20 s is past frame 0 at 24-60 fps */
    _boundary = [_player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:CMTimeMake(1, 20)]] queue:NULL usingBlock:^{
        TBShortsPlayer *s = w;
        if (!s || s->_playAt <= 0 || s->_firstFrameMs >= 0) return;
        s->_firstFrameMs = tb_now_ms() - s->_playAt;
        [s notify];
    }];
    if (_wantsPlay) [_player play];
}

- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    if (ctx == kReadyCtx) {
        _shown = ((AVPlayerLayer *)_view.layer).readyForDisplay && _item;
        [self notify];
        return;
    }
    if (ctx != kStatusCtx || o != _item) { [super observeValueForKeyPath:k ofObject:o change:c context:ctx]; return; }
    TBLog(@"PadTube: Short %@ item status %d after %.0f ms (playing %d)", _videoId, (int)_item.status, tb_now_ms() - _loadAt, _wantsPlay);
    if (_item.status == AVPlayerItemStatusFailed) {
        _errorText = _item.error.localizedDescription ?: @"Playback failed.";
        TBLog(@"PadTube: Short %@ failed: %@", _videoId, _errorText);
        [self notify];
        return;
    }
    if (_item.status != AVPlayerItemStatusReadyToPlay || _ready) return;
    _ready = YES;
    _loadMs = tb_now_ms() - _loadAt;
    [self notify];
    if (_wantsPlay) return;
    NSString *vid = _videoId;
    /* asked for by the owner's strategy; with our HLS stream iOS 6 never calls the handler (MEASURED 2026-11-13), so
     * nothing waits for it */
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TBShortsPreroll"])   /* A/B: shorts_bench.py */
        [_player prerollAtRate:1 completionHandler:^(BOOL finished) { TBLog(@"PadTube: Short %@ preroll handler %d", vid, finished); }];
}

- (void)ended:(NSNotification *)n {   /* loop */
    if (!_wantsPlay) return;
    [_player seekToTime:kCMTimeZero];
    [_player play];
}

- (void)play {
    _wantsPlay = YES;
    _playAt = tb_now_ms();
    _firstFrameMs = -1;
    if (_gen >= 0) tb_hls_limit(_gen, TB_HLS_OPEN);
    _preloadOnly = NO;
    [_player play];
    [self watch:_playAt video:_videoId];
}

/* Watchdog, every 2 s after play until the first new frame. A ready item with no frame (2 of 29 swipes in step 0
 * never got one in 10 s): seek to 0 and play. An item still loading is left alone until 8 s after its load began: a
 * load from zero takes 1.6-3.7 s (MEASURED), and restarting it at 2 s turned one step back into 9.8 s (device 2026-11-13). */
- (void)watch:(double)at video:(NSString *)vid {
    __weak TBShortsPlayer *w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        TBShortsPlayer *s = w;
        if (!s || s->_playAt != at || s->_firstFrameMs >= 0 || !s->_wantsPlay || ![s->_videoId isEqualToString:vid]) return;
        if (s->_ready) {
            TBLog(@"PadTube: Short %@ ready, no frame 2 s after play: seek to 0", vid);
            [s->_player seekToTime:kCMTimeZero];
            [s->_player play];
        } else if (tb_now_ms() - s->_loadAt > 8000) {
            TBLog(@"PadTube: Short %@ not ready 8 s after its load: load again", vid);
            TBPlayerInfo *i = s->_info;
            [s load:vid info:i];
            s->_loadAt = tb_now_ms();
            [s play];
            return;   /* play starts a new watch */
        }
        [s watch:at video:vid];
    });
}

/* the server gate on or off (A/B in shorts_bench.py: a held segment request made AVPlayer start late, MEASURED) */
static BOOL gateOn(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:@"TBShortsGate"]; }

- (void)setPreloadOnly:(BOOL)p {
    _preloadOnly = p;
    if (_gen >= 0) tb_hls_limit(_gen, p && gateOn() ? 0 : TB_HLS_OPEN);
}

- (void)freeze { if (_gen >= 0 && gateOn()) tb_hls_limit(_gen, TB_HLS_FREEZE); }

- (double)bufferedAhead {
    double now = self.currentTime, best = 0;
    for (NSValue *v in _item.loadedTimeRanges) {
        CMTimeRange r = v.CMTimeRangeValue;
        double a = CMTimeGetSeconds(r.start), b = a + CMTimeGetSeconds(r.duration);
        if (now >= a - 0.5 && b > now) best = MAX(best, b - now);
    }
    return best;
}

- (BOOL)fullyLoaded {
    double d = CMTimeGetSeconds(_item.duration);
    if (!isfinite(d) || d <= 0) return NO;
    return self.currentTime + self.bufferedAhead >= d - 0.5;
}

- (void)pause {
    _wantsPlay = NO;
    [_player pause];
}

- (double)currentTime {
    double t = CMTimeGetSeconds(_player.currentTime);
    return isfinite(t) ? t : 0;
}

- (void)resign { _resumeOnActive = _wantsPlay; if (_wantsPlay) [_player pause]; }
- (void)active { if (_resumeOnActive && _wantsPlay) [_player play]; _resumeOnActive = NO; }

- (void)unload {
    if (_stream) {   /* what this Short cost (D65 data check): bytes fetched against what was watched */
        tb_stream_stats st;
        tb_stream_get_stats(_stream, &st);
        double d = CMTimeGetSeconds(_item.duration);
        TBLog(@"PadTube: Short %@ let go: %ld B fetched, %d segments, %.1f s built; at %.1f s, %.1f s buffered ahead, %.1f s long, %d stalls",
              _videoId, st.bytes_fetched, st.segments_built, st.media_s_total, self.currentTime, self.bufferedAhead, isfinite(d) ? d : -1, _stalls);
    }
    [_player pause];
    _wantsPlay = NO;
    if (_boundary) { [_player removeTimeObserver:_boundary]; _boundary = nil; }
    if (_item) {
        [_item removeObserver:self forKeyPath:@"status" context:kStatusCtx];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:_item];
        [_player replaceCurrentItemWithPlayerItem:nil];
        releaseLater(_item);
        _item = nil;
    }
    if (_gen >= 0) { tb_hls_remove(_gen); _gen = -1; }
    if (_stream) { tb_stream_free(_stream); _stream = NULL; }
    _videoId = nil;
    _info = nil;
    _ready = _shown = NO;
    _preloadOnly = NO;
    _errorText = nil;
    _firstFrameMs = -1;
    _playAt = 0;
}
@end
