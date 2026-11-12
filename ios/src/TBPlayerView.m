#import "TBPlayerView.h"
#import "TBLog.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMedia/CoreMedia.h>
#import "TBCore.h"
#import "TBStyle.h"
#import "TBImageLoader.h"
#include "tb_hls.h"
#include "tb_http.h"
#include "tb_stream.h"

static NSString *timeText(double t) {
    if (!(t >= 0) || isinf(t)) t = 0;
    int s = (int)t, h = s / 3600, m = s / 60 % 60;
    s %= 60;
    return h ? [NSString stringWithFormat:@"%d:%02d:%02d", h, m, s] : [NSString stringWithFormat:@"%d:%02d", m, s];
}

@interface TBPlayerView () <UIActionSheetDelegate, UIGestureRecognizerDelegate>
@end

/* A view whose layer is an AVPlayerLayer (the AVPlayer engine draws the video here). */
@interface TBAVView : UIView
@end
@implementation TBAVView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

static void *kItemCtx = &kItemCtx, *kLayerCtx = &kLayerCtx;

@implementation TBPlayerView {
    MPMoviePlayerController *_mp;
    tb_stream *_stream;
    tb_live *_live;
    BOOL _liveDirect, _audioOnly, _wasPlaying, _interruptedWhilePlaying;
    BOOL _wantPlay;   /* the user's intent; MediaPlayer pauses itself before resign-active */
    double _resignedAt, _resumeT0;
    double _fgAt, _fgClock, _fgPlayAt; /* return log: return time, clock then, play tap after a paused return */
    BOOL _fgPending;
    UIImageView *_poster;
    /* AVPlayer engine (TBEngine = 1): asynchronous seek; background audio by detaching the layer (Apple QA1668) */
    BOOL _useAV;
    AVPlayer *_av;
    AVPlayerItem *_avItem;
    TBAVView *_avView;
    double _avStartAt;
    int _variant;          /* the variant the player plays (fixed) or starts on (Auto) */
    UIImageView *_bar;
    UIButton *_play, *_cc, *_q, *_full;
    UISlider *_slider;
    UILabel *_now, *_end, *_caption, *_message;
    UIActivityIndicatorView *_spin;
    NSTimer *_timer;
    NSArray *_cues;
    NSInteger _cueIdx;
    BOOL _scrubbing, _controlsShown;
    double _t0, _hideAt;
    NSArray *_heights;
    float _rate;
    /* gestures (D50, D51) */
    UITapGestureRecognizer *_tap, *_doubleTap;
    UISwipeGestureRecognizer *_swipeDown;
    UILabel *_skip;
    BOOL _tapPrevShown;
    double _lastTapMs;
}

- (id)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.backgroundColor = [UIColor blackColor];
    self.clipsToBounds = YES;
    _startMs = -1;
    _rate = 1;
    /* Owner decision 2026-11-11: default 720p; the last choice is kept for the next videos (0 = Auto). */
    _useAV = [[NSUserDefaults standardUserDefaults] integerForKey:@"TBEngine"] == 1;
    NSNumber *q = [[NSUserDefaults standardUserDefaults] objectForKey:@"TBQuality"];
    _quality = q ? q.intValue : 720;
    _caption = [UILabel new];
    _caption.numberOfLines = 3;
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.textColor = [UIColor whiteColor];
    _caption.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75]; /* the 2012 app: white text on a dark box */
    _caption.font = TBFont(20);
    _caption.hidden = YES;
    _message = [UILabel new];
    _message.numberOfLines = 0;
    _message.textAlignment = NSTextAlignmentCenter;
    _message.textColor = [UIColor whiteColor];
    _message.backgroundColor = [UIColor blackColor];
    _message.font = [UIFont systemFontOfSize:15];
    _message.hidden = YES;
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spin.hidesWhenStopped = YES;
    _bar = [[UIImageView alloc] initWithImage:[TBStyle controlBarImage]]; /* §8.2 */
    _bar.userInteractionEnabled = YES;
    _play = [UIButton buttonWithType:UIButtonTypeCustom];
    [_play setImage:[TBStyle icon:@"pause" size:20 color:[UIColor whiteColor]] forState:UIControlStateNormal];
    [_play addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
    _full = [UIButton buttonWithType:UIButtonTypeCustom];
    [_full setImage:[TBStyle icon:@"full" size:20 color:[UIColor whiteColor]] forState:UIControlStateNormal];
    [_full addTarget:self action:@selector(fullTapped) forControlEvents:UIControlEventTouchUpInside];
    _cc = [self textButton:@"CC" action:@selector(ccTapped)];
    _q = [self textButton:@"720p" action:@selector(qualityTapped)];
    [_q setTitle:_quality ? [NSString stringWithFormat:@"%dp", _quality] : @"Auto" forState:UIControlStateNormal];
    _now = [self timeLabel];
    _end = [self timeLabel];
    _slider = [UISlider new];
    [_slider setMinimumTrackImage:[TBStyle trackImage:0] forState:UIControlStateNormal];
    [_slider setMaximumTrackImage:[TBStyle trackImage:2] forState:UIControlStateNormal];
    [_slider setThumbImage:[TBStyle knobImage] forState:UIControlStateNormal];
    [_slider addTarget:self action:@selector(scrubStart) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubMove) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(scrubEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    for (UIView *v in @[_play, _now, _slider, _end, _cc, _q, _full]) [_bar addSubview:v];
    [self addSubview:_caption];
    [self addSubview:_message];
    [self addSubview:_spin];
    [self addSubview:_bar];
    _controlsShown = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(willResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    /* iOS 6: an alarm or a call interrupts; headphones out changes the route (owner 2026-11-12) */
    [nc addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [nc addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    _tap.delegate = self;
    [self addGestureRecognizer:_tap];
    _doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    _doubleTap.numberOfTapsRequired = 2;
    _doubleTap.delegate = self;
    [self addGestureRecognizer:_doubleTap];
    _swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedDown)];
    _swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    _swipeDown.delegate = self;
    _swipeDown.enabled = NO;   /* full screen only */
    [self addGestureRecognizer:_swipeDown];
    _skip = [UILabel new];
    _skip.font = TBFontBold(20);
    _skip.textColor = [UIColor whiteColor];
    _skip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6f];
    _skip.textAlignment = NSTextAlignmentCenter;
    _skip.alpha = 0;
    [self addSubview:_skip];
    return self;
}

- (UIButton *)textButton:(NSString *)t action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = TBFontBold(14);
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UILabel *)timeLabel {
    UILabel *l = [UILabel new];
    l.font = TBFont(15);
    l.textColor = [UIColor whiteColor];
    l.backgroundColor = [UIColor clearColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.text = @"0:00";
    return l;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _mp.view.frame = b;
    _avView.frame = b;
    CGFloat bh = 51; /* §8.2: the bottom 51 pt of the player */
    _bar.frame = CGRectMake(0, b.size.height - bh, b.size.width, bh);
    CGFloat x = 6;
    _play.frame = CGRectMake(x, 0, 44, bh); x += 44;
    _now.frame = CGRectMake(x, 0, 52, bh); x += 52;
    CGFloat right = b.size.width - 6;
    _full.frame = CGRectMake(right - 44, 0, 44, bh); right -= 44;
    _q.frame = CGRectMake(right - 54, 0, 54, bh); right -= 54;
    _cc.frame = CGRectMake(right - 40, 0, 40, bh); right -= 40;
    _end.frame = CGRectMake(right - 56, 0, 56, bh); right -= 56;
    _slider.frame = CGRectMake(x + 4, 0, right - x - 8, bh);
    _spin.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    _message.frame = CGRectInset(b, 20, 20);
    [self layoutCaption];
}

- (void)layoutCaption {
    if (_caption.hidden) return;
    CGRect b = self.bounds;
    CGFloat maxw = b.size.width * 0.8;
    CGSize s = [_caption.text sizeWithFont:_caption.font constrainedToSize:CGSizeMake(maxw, 80) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat bottom = b.size.height - (_controlsShown ? 58 : 12);
    _caption.frame = CGRectMake((b.size.width - s.width - 12) / 2, bottom - s.height - 6, s.width + 12, s.height + 6);
}

/* ---------- playback ---------- */

- (void)showMessage:(NSString *)m {
    _errorText = m;
    _message.text = m;
    _message.hidden = m == nil;
    if (m) [_spin stopAnimating];
    [self bringSubviewToFront:_message];
}

- (NSArray *)availableHeights { return _heights ?: @[]; }

- (void)playVideo:(NSString *)videoId info:(TBPlayerInfo *)info requestedAt:(double)t0 startAt:(double)start {
    [self stop];
    _videoId = [videoId copy];
    _info = info;
    _t0 = t0;
    _startMs = -1;
    _ended = NO;
    _cues = nil;
    _captionLang = nil;
    _caption.hidden = YES;
    [self showMessage:nil];
    if (![info.status isEqualToString:@"OK"]) {
        [self showMessage:TBPlayerProblem(info)];
        return;
    }
    if (info.live) {
        if (!info.hlsUrl.length) { [self showMessage:@"This live stream has no HLS manifest."]; return; }
        /* Live: YouTube sends video-only TS + packed AAC renditions; the core merges them into one TS per segment
         * on 127.0.0.1 (core/tb_live.c), because separate audio renditions are unverified on iOS 6 (research §6.2).
         * If that fails, the player gets YouTube's own manifest (see finished:). */
        _heights = @[];
        [_spin startAnimating];
        _live = tb_live_new(info.hlsUrl.UTF8String, _quality ? _quality : 720);
        tb_hls_set_live(_live);
        char url[160];
        tb_hls_url(0, 2, url, sizeof url);
        [self startURL:[NSURL URLWithString:TBStr(url)] at:0];
        return;
    }
    TBFormat *audio = nil;
    for (TBFormat *a in info.audioFormats) if (!audio || a.audioDefault) audio = a;
    if (!info.videoFormats.count || !audio) { [self showMessage:@"No H.264 / AAC format for this video."]; return; }
    NSUInteger nv = info.videoFormats.count;
    tb_stream_fmt *vf = calloc(nv, sizeof *vf);
    NSMutableArray *hs = [NSMutableArray array];
    for (NSUInteger i = 0; i < nv; i++) {
        TBFormat *f = info.videoFormats[i];
        vf[i] = (tb_stream_fmt){f.itag, (char *)f.url.UTF8String, f.width, f.height, f.bitrate, f.indexEnd, f.contentLength};
        [hs addObject:@(f.height)];
    }
    tb_stream_fmt af = {audio.itag, (char *)audio.url.UTF8String, 0, 0, audio.bitrate, audio.indexEnd, audio.contentLength};
    _stream = tb_stream_new(vf, (int)nv, &af);
    free(vf);
    _heights = hs;
    [_spin startAnimating];
    [self startAt:start];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:@{MPMediaItemPropertyTitle: info.title ?: @"",
                                                                 MPMediaItemPropertyArtist: info.author ?: @"",
                                                                 MPMediaItemPropertyPlaybackDuration: @(info.lengthSeconds)}];
}

- (int)indexForHeight:(int)h {
    for (NSUInteger i = 0; i < _heights.count; i++) if ([_heights[i] intValue] == h) return (int)i;
    return -1;
}

/* Fixed quality: the chosen height, else the highest one below it, else the lowest (a video without 720p).
 * Auto: master playlist with the variants from 720p down, 720p first (the iOS player starts on the first one
 * and moves down when the link is slow). */
- (int)indexAtOrBelow:(int)h {
    int best = -1;
    for (NSUInteger i = 0; i < _heights.count; i++) if ([_heights[i] intValue] <= h) best = (int)i;
    return best >= 0 ? best : 0;
}

- (void)startAt:(double)t {
    char url[160];
    if (_audioOnly) { /* background: AAC only (audio fragments as segments) */
        tb_hls_set(_stream, NULL, 0);
        tb_hls_url(-1, 0, url, sizeof url);
        tb_stream_warm(_stream, -1, t);
    } else if (_quality == 0) {
        int order[8], n = 0;
        for (NSInteger i = (NSInteger)_heights.count - 1; i >= 0 && n < 4; i--)
            if ([_heights[(NSUInteger)i] intValue] <= 720 && [_heights[(NSUInteger)i] intValue] >= 240) order[n++] = (int)i;
        if (!n) order[n++] = 0;
        tb_hls_set(_stream, order, n);
        tb_hls_url(0, 1, url, sizeof url);
        _variant = order[0];
        tb_stream_warm(_stream, order[0], t); /* the player starts on the first variant */
    } else {
        int i = [self indexAtOrBelow:_quality];
        tb_hls_set(_stream, &i, 1);
        tb_hls_url(i, 0, url, sizeof url);
        _variant = i;
        tb_stream_warm(_stream, i, t);
    }
    [self startURL:[NSURL URLWithString:TBStr(url)] at:t];
}

/* One MPMoviePlayerController for the whole app: creating one costs 224-247 ms on the main thread on the A5
 * (MEASURED 2026-11-11), over the 50 ms stall gate. It is made once after launch and reused (new contentURL). */
static MPMoviePlayerController *g_mp;
static AVPlayer *g_av;
+ (void)prewarm {
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"TBEngine"] == 1) { if (!g_av) g_av = [AVPlayer new]; return; }
    if (!g_mp) g_mp = [[MPMoviePlayerController alloc] init];
}

- (BOOL)engineIsAV { return _useAV; }

- (void)startAV:(NSURL *)url at:(double)t {
    double m0 = tb_now_ms();
    [self teardownPlayer];
    if (!g_av) g_av = [AVPlayer new];
    _av = g_av;
    if (!_avView) {
        _avView = [[TBAVView alloc] initWithFrame:self.bounds];
        _avView.userInteractionEnabled = NO;
        _avView.backgroundColor = [UIColor blackColor];
        [_avView.layer addObserver:self forKeyPath:@"readyForDisplay" options:0 context:kLayerCtx];
    }
    _avView.frame = self.bounds;
    [self insertSubview:_avView atIndex:0];
    ((AVPlayerLayer *)_avView.layer).player = _av;
    _avItem = [AVPlayerItem playerItemWithURL:url];
    _avStartAt = t;
    [_avItem addObserver:self forKeyPath:@"status" options:0 context:kItemCtx];
    [_avItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:0 context:kItemCtx];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(avEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_avItem];
    [nc addObserver:self selector:@selector(avFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_avItem];
    double m1 = tb_now_ms();
    [_av replaceCurrentItemWithPlayerItem:_avItem];
    [_av play];
    if (_rate != 1) _av.rate = _rate;
    TBLog(@"PadTube: AV start: setup %.0f ms, play %.0f ms", m1 - m0, tb_now_ms() - m1);
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self showControls];
}

- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    if (ctx != kItemCtx && ctx != kLayerCtx) { [super observeValueForKeyPath:kp ofObject:o change:c context:ctx]; return; }
    if (o == _avItem && [kp isEqualToString:@"status"]) {
        if (_avItem.status == AVPlayerItemStatusReadyToPlay && _avStartAt > 0) {
            [_av seekToTime:CMTimeMakeWithSeconds(_avStartAt, 600)];
            _avStartAt = 0;
        } else if (_avItem.status == AVPlayerItemStatusFailed) {
            [self playbackFailed:_avItem.error];
        }
    }
    if (o == _avItem && [kp isEqualToString:@"playbackLikelyToKeepUp"]) {
        if (_avItem.playbackLikelyToKeepUp) [_spin stopAnimating]; else if (_startMs >= 0) [_spin startAnimating];
    }
    if (o == _avView.layer && [kp isEqualToString:@"readyForDisplay"] && ((AVPlayerLayer *)_avView.layer).readyForDisplay) [self tick];
}

- (void)avEnded:(NSNotification *)n {
    _ended = YES;
    if ([self.delegate respondsToSelector:@selector(playerViewDidFinish:)]) [self.delegate playerViewDidFinish:self];
}

- (void)avFailed:(NSNotification *)n { [self playbackFailed:n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]]; }

- (void)playbackFailed:(NSError *)e {
    if (_live && !_liveDirect && _info.hlsUrl) {
        TBLog(@"PadTube: local live failed (%@); trying YouTube's manifest", e);
        _liveDirect = YES;
        [self startURL:[NSURL URLWithString:_info.hlsUrl] at:0];
        return;
    }
    [self showMessage:[NSString stringWithFormat:@"Playback failed. %@", e.localizedDescription ?: @""]];
}

- (void)startURL:(NSURL *)url at:(double)t {
    _wantPlay = YES;
    if (_useAV) { [self startAV:url at:t]; return; }
    double m0 = tb_now_ms();
    [self teardownPlayer];
    double m1 = tb_now_ms();
    [TBPlayerView prewarm];
    _mp = g_mp;
    _mp.contentURL = url;
    double m2 = tb_now_ms();
    _mp.movieSourceType = MPMovieSourceTypeStreaming;
    _mp.controlStyle = MPMovieControlStyleNone;
    _mp.shouldAutoplay = YES;
    _mp.allowsAirPlay = NO;
    _mp.view.backgroundColor = [UIColor blackColor];
    _mp.initialPlaybackTime = t > 0 ? t : -1;
    _mp.view.frame = self.bounds;
    _mp.view.userInteractionEnabled = NO;
    [self insertSubview:_mp.view atIndex:0];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(stateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:_mp];
    [nc addObserver:self selector:@selector(stateChanged:) name:MPMoviePlayerLoadStateDidChangeNotification object:_mp];
    [nc addObserver:self selector:@selector(stateChanged:) name:MPMoviePlayerReadyForDisplayDidChangeNotification object:_mp];
    [nc addObserver:self selector:@selector(finished:) name:MPMoviePlayerPlaybackDidFinishNotification object:_mp];
    double m3 = tb_now_ms();
    [_mp prepareToPlay];
    [_mp play];
    if (_rate != 1) _mp.currentPlaybackRate = _rate;
    TBLog(@"PadTube: player start: teardown %.0f ms, create %.0f ms, setup %.0f ms, play %.0f ms", m1 - m0, m2 - m1, m3 - m2, tb_now_ms() - m3);
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self showControls];
}

- (void)teardownPlayer {
    if (_avItem) {
        [_avItem removeObserver:self forKeyPath:@"status" context:kItemCtx];
        [_avItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:kItemCtx];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_avItem];
        if (_av.currentItem == _avItem) { [_av pause]; [_av replaceCurrentItemWithPlayerItem:nil]; }
        _avItem = nil;
    }
    _av = nil;
    if (!_mp) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_mp];
    /* the shared player may already belong to another page: stop it only while it is ours */
    if (_mp.view.superview == self) {
        [_mp stop];
        [_mp.view removeFromSuperview];
    }
    _mp = nil;
}

- (void)stop {
    _wantPlay = NO;
    [_timer invalidate];
    _timer = nil;
    [self teardownPlayer];
    if (_stream || _live) tb_hls_set(NULL, NULL, 0);
    if (_stream) { tb_stream_free(_stream); _stream = NULL; }
    if (_live) { tb_live_free(_live); _live = NULL; }
    _liveDirect = NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stop];
    if (_avView) [_avView.layer removeObserver:self forKeyPath:@"readyForDisplay" context:kLayerCtx];
}

/* Background audio. If iOS pauses the video track when the app leaves the screen, play on from the same time with
 * the audio-only playlist; back on screen, the video again. */
/* MPMoviePlayerController pauses a video when the app leaves the screen, BEFORE didEnterBackground arrives
 * (MEASURED on the iPad 2026-11-12: playing=0 at that point, so the sound stopped and iOS suspended the app).
 * The playing state is taken here, at resign-active, which comes first. */
- (void)willResignActive {
    _wasPlaying = _wantPlay && !_ended;
    _resignedAt = tb_now_ms();
    TBLog(@"PadTube: resign active: playing=%d t=%.1f", _wasPlaying, self.currentTime);
}

- (void)didEnterBackground {
    TBLog(@"PadTube: background: was playing=%d now playing=%d t=%.1f (+%.0f ms)", _wasPlaying, self.isPlaying, self.currentTime, tb_now_ms() - _resignedAt);
    if (!_wasPlaying) return;
    if (_useAV && _av) { /* QA1668: a player without a layer keeps playing the audio in the background */
        ((AVPlayerLayer *)_avView.layer).player = nil;
        if (_av.rate == 0) [_av play];
        return;
    }
    if (!_stream) return;
    /* 1) the same item on: the shortest gap if iOS lets the video item play without a screen */
    [_mp play];
    double t0 = tb_now_ms();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1000 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground || !self->_stream) return;
        if (self.isPlaying) { TBLog(@"PadTube: background: video item plays on (%.0f ms)", tb_now_ms() - t0); return; }
        /* 2) else the audio-only playlist from the same time */
        TBLog(@"PadTube: background: video item paused; audio only from %.1f s", self.currentTime);
        self->_audioOnly = YES;
        [self startAt:self.currentTime];
    });
}

- (void)willEnterForeground {
    TBLog(@"PadTube: foreground: audioOnly=%d playing=%d t=%.1f", _audioOnly, self.isPlaying, self.currentTime);
    _fgAt = tb_now_ms(); _fgClock = self.currentTime; _fgPlayAt = 0; _fgPending = YES;
    if (_useAV && _av) { ((AVPlayerLayer *)_avView.layer).player = _av; return; }
    if (!_stream) return;
    /* a download that ran when iOS suspended the app waits on a dead socket until its 20 s timeout: stop it (polled
     * every 200 ms). Only downloads from before the app left: MediaPlayer may already ask for the current segment
     * (a cancel of everything stopped that request, and the player did not ask again: device run 2026-11-12). */
    tb_stream_abort_before(_stream, _resignedAt);
    if (_audioOnly) {
        /* back to the video: build its segment at once and show the thumbnail (not black) until the first frame */
        _audioOnly = NO;
        double t = self.currentTime;
        tb_stream_warm(_stream, _variant, t);
        [self showPoster];
        _resumeT0 = tb_now_ms();
        [self startAt:t];
    } else if (_wasPlaying && !self.isPlaying) {
        [_mp play];
    } else if (_wasPlaying) {
        /* the video renderer stopped in the background and waits for the next keyframe (one per segment): black
         * for 1.5-2.8 s after return (MEASURED 2026-11-12). A seek in place decodes from the keyframe before t.
         * At once, not after the segment wait of -seekTo: the wait made the picture later here (2.7 s vs 1.8 s). */
        double t = self.currentTime;
        tb_stream_warm(_stream, _variant, t);
        [self applySeek:t];
    }
}

/* The video thumbnail in place of a black player while the video track starts again. */
- (void)showPoster {
    if (!_poster) {
        _poster = [UIImageView new];
        _poster.contentMode = UIViewContentModeScaleAspectFit;
        _poster.backgroundColor = [UIColor blackColor];
        _poster.userInteractionEnabled = NO;
    }
    _poster.frame = self.bounds;
    [self insertSubview:_poster aboveSubview:_mp.view ?: _avView];
    _poster.hidden = NO;
    __weak UIImageView *pv = _poster;
    [TBImageLoader load:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", _videoId] pixelSize:CGSizeMake(320, 180)
                   done:^(UIImage *img) { if (img) pv.image = img; }];
}

- (BOOL)audioOnly { return _audioOnly; }

/* Alarm / call: pause; when it ends with "should resume", play on from the same place. */
- (void)audioInterrupted:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        _interruptedWhilePlaying = self.isPlaying;
        TBLog(@"PadTube: audio interruption began (playing=%d)", _interruptedWhilePlaying);
    } else {
        NSUInteger opt = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        TBLog(@"PadTube: audio interruption ended (resume=%d)", (int)(opt & AVAudioSessionInterruptionOptionShouldResume));
        if (_interruptedWhilePlaying && (opt & AVAudioSessionInterruptionOptionShouldResume)) {
            [[AVAudioSession sharedInstance] setActive:YES error:NULL];
            if (!self.isPlaying) [self togglePlay];
        }
        _interruptedWhilePlaying = NO;
    }
}

/* Headphones out: pause, as the system player does (the sound must not move to the speaker). */
- (void)routeChanged:(NSNotification *)n {
    NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason != AVAudioSessionRouteChangeReasonOldDeviceUnavailable) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        TBLog(@"PadTube: audio route lost (headphones out): pause");
        if (self.isPlaying) [self togglePlay];
    });
}

- (void)stateChanged:(NSNotification *)n {
    if (_mp.loadState & (MPMovieLoadStatePlayable | MPMovieLoadStatePlaythroughOK)) [_spin stopAnimating];
    if (_mp.loadState & MPMovieLoadStateStalled) [_spin startAnimating];
    if (_startMs < 0 && _mp.readyForDisplay && _mp.playbackState == MPMoviePlaybackStatePlaying) {
        _startMs = tb_now_ms() - _t0;
        [self noteStartBytes];
        TBLog(@"PadTube: first frame %.0f ms", _startMs);
        [_spin stopAnimating];
    }
    [_play setImage:[TBStyle icon:_mp.playbackState == MPMoviePlaybackStatePlaying ? @"pause" : @"play" size:20 color:[UIColor whiteColor]] forState:UIControlStateNormal];
}

- (void)finished:(NSNotification *)n {
    int reason = [n.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] intValue];
    if (reason == MPMovieFinishReasonPlaybackError && _live && !_liveDirect && _info.hlsUrl) {
        TBLog(@"PadTube: local live failed (%@); trying YouTube's manifest", n.userInfo[@"error"]);
        _liveDirect = YES;
        [self startURL:[NSURL URLWithString:_info.hlsUrl] at:0];
        return;
    }
    if (reason == MPMovieFinishReasonPlaybackError) {
        NSError *e = n.userInfo[@"error"];
        [self showMessage:[NSString stringWithFormat:@"Playback failed. %@", e.localizedDescription ?: @""]];
    } else if (reason == MPMovieFinishReasonPlaybackEnded) {
        _ended = YES;
        _wantPlay = NO;
        if ([self.delegate respondsToSelector:@selector(playerViewDidFinish:)]) [self.delegate playerViewDidFinish:self];
    }
}

/* One line per return in Documents/padtube_returns.log (owner lock-screen tests L1-L5: the device keeps only a
 * short log in memory). Read with scripts/read_return_log.sh. Written on a background queue. */
- (void)noteReturn:(NSString *)result {
    _fgPending = NO;
    NSString *line = [NSString stringWithFormat:@"%@ away=%.0fs playing=%d %@\n",
                      [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle],
                      _resignedAt > 0 ? (_fgAt - _resignedAt) / 1000 : -1, _wasPlaying, result];
    TBLog(@"PadTube: return: %@", [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"padtube_returns.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    });
}

- (void)tick {
    if (!_mp && !_av) return;
    if (_fgPending) {   /* the clock moves again after a return */
        double now = tb_now_ms();
        if (self.isPlaying && self.currentTime > _fgClock + 0.3)
            [self noteReturn:_fgPlayAt > 0 ? [NSString stringWithFormat:@"moves=%.0fms after_play_tap=%.0fms", now - _fgAt, now - _fgPlayAt]
                                           : [NSString stringWithFormat:@"moves=%.0fms", now - _fgAt]];
        else if (_wasPlaying && now - _fgAt > 60000) [self noteReturn:@"moves=NO_60s"];
    }
    if (_poster && !_poster.hidden && self.isPlaying && self.currentTime > 0.05) {
        BOOL frame = _av ? ((AVPlayerLayer *)_avView.layer).readyForDisplay : _mp.readyForDisplay;
        if (frame) {
            _poster.hidden = YES;
            if (_resumeT0 > 0) { TBLog(@"PadTube: picture back %.0f ms after foreground", tb_now_ms() - _resumeT0); _resumeT0 = 0; }
        }
    }
    double t = self.currentTime, d = self.duration;
    BOOL frame = _av ? ((AVPlayerLayer *)_avView.layer).readyForDisplay : YES;
    if (_startMs < 0 && t > 0.05 && self.isPlaying && frame) {
        _startMs = tb_now_ms() - _t0;
        [self noteStartBytes];
        TBLog(@"PadTube: first frame (time) %.0f ms", _startMs);
        [_spin stopAnimating];
    }
    if (_controlsShown && !_scrubbing) {
        _now.text = timeText(t);
        _end.text = timeText(d);
        _slider.maximumValue = d > 0 ? (float)d : 1;
        _slider.value = (float)t;
    }
    if (_controlsShown && _hideAt > 0 && tb_now_ms() > _hideAt && self.isPlaying) [self hideControls];
    if (_av) [_play setImage:[TBStyle icon:self.isPlaying ? @"pause" : @"play" size:20 color:[UIColor whiteColor]] forState:UIControlStateNormal];
    [self updateCaption:t];
}

/* MPMoviePlayerController answers NaN before it knows the time and after the end */
- (void)noteStartBytes {
    if (!_stream) return;
    tb_stream_stats st;
    tb_stream_get_stats(_stream, &st);
    _startBytes = st.bytes_fetched;
}

- (long)fetchedBytes {
    if (!_stream) return 0;
    tb_stream_stats st;
    tb_stream_get_stats(_stream, &st);
    return st.bytes_fetched;
}

- (double)currentTime {
    double t = _av ? CMTimeGetSeconds(_av.currentTime) : _mp ? _mp.currentPlaybackTime : 0;
    return isfinite(t) && t > 0 ? t : 0;
}
- (double)duration {
    double d = _av ? (_avItem && CMTIME_IS_NUMERIC(_avItem.duration) ? CMTimeGetSeconds(_avItem.duration) : 0) : _mp ? _mp.duration : 0;
    return isfinite(d) && d > 0 ? d : _info.lengthSeconds;
}
- (BOOL)isPlaying {
    if (_av) return _av.rate > 0 && _avItem.status == AVPlayerItemStatusReadyToPlay;
    return _mp.playbackState == MPMoviePlaybackStatePlaying;
}

- (void)togglePlay {
    if (_fgPending && _fgPlayAt == 0) _fgPlayAt = tb_now_ms();
    if (_av) { _wantPlay = _av.rate == 0; if (_av.rate > 0) [_av pause]; else { [_av play]; if (_rate != 1) _av.rate = _rate; } [self showControls]; return; }
    if (!_mp) return;
    _wantPlay = _mp.playbackState != MPMoviePlaybackStatePlaying;
    if (_wantPlay) [_mp play]; else [_mp pause];
    [self showControls];
}

- (void)seekTo:(double)s {
    if (_av) { /* asynchronous: no main-thread wait */
        double t0 = tb_now_ms();
        [_av seekToTime:CMTimeMakeWithSeconds(s, 600)];
        TBLog(@"PadTube: AV seek call %.0f ms", tb_now_ms() - t0);
        _cueIdx = 0;
        return;
    }
    if (!_mp) return;
    _cueIdx = 0;
    /* build the target segment at once (a running next-segment prefetch is stopped for it), then move the player.
     * A wait for the built segment before the move was measured (2026-11-12, 3 variants): no reliable stall gain,
     * seeks up to 1 s slower; the stall is inside MediaPlayer (R6). */
    if (_stream && !_audioOnly) tb_stream_warm(_stream, _variant, s);
    [self applySeek:s];
}

- (void)applySeek:(double)s {
    double t0 = tb_now_ms();
    _mp.currentPlaybackTime = s;
    TBLog(@"PadTube: seek call %.0f ms", tb_now_ms() - t0);
}

- (void)setRate:(float)rate {
    _rate = rate;
    if (_av) { if (_av.rate > 0) _av.rate = rate; }
    else if (_mp) _mp.currentPlaybackRate = rate;
}

- (void)setQuality:(int)h {
    _quality = h;
    [[NSUserDefaults standardUserDefaults] setInteger:h forKey:@"TBQuality"];
    _startMs = -1; /* the switch is timed like a start */
    _t0 = tb_now_ms();
    [_q setTitle:h ? [NSString stringWithFormat:@"%dp", h] : @"Auto" forState:UIControlStateNormal];
    if (!_stream) return;
    double t = self.currentTime;
    [_spin startAnimating];
    [self startAt:t];
}

/* ---------- captions ---------- */

- (void)selectCaptionIndex:(NSInteger)i {
    _cues = nil;
    _caption.hidden = YES;
    if (i < 0 || i >= (NSInteger)_info.captionTracks.count) { _captionLang = nil; [_cc setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; return; }
    TBCaptionTrack *t = _info.captionTracks[(NSUInteger)i];
    _captionLang = t.lang;
    [_cc setTitleColor:[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1] forState:UIControlStateNormal];
    NSString *vid = _videoId;
    [TBCore captions:t done:^(NSArray *cues) {
        if (![vid isEqualToString:self->_videoId]) return;
        self->_cues = cues;
        self->_cueIdx = 0;
    }];
}

- (NSString *)currentCaption { return _caption.hidden ? nil : _caption.text; }

- (void)updateCaption:(double)t {
    if (!_cues.count) { if (!_caption.hidden) _caption.hidden = YES; return; }
    /* cues are sorted; walk from the last index (playback moves forward), restart on a jump back */
    NSInteger n = (NSInteger)_cues.count, i = _cueIdx;
    if (i >= n || ((TBCue *)_cues[(NSUInteger)i]).start > t) i = 0;
    while (i + 1 < n && ((TBCue *)_cues[(NSUInteger)(i + 1)]).start <= t) i++;
    _cueIdx = i;
    TBCue *c = _cues[(NSUInteger)i];
    BOOL on = c.start <= t && t < c.end && c.text.length;
    if (on) {
        if (_caption.hidden || ![_caption.text isEqualToString:c.text]) {
            _caption.text = c.text;
            _caption.hidden = NO;
            [self layoutCaption];
        }
    } else if (!_caption.hidden) _caption.hidden = YES;
}

/* ---------- controls ---------- */

- (void)tapped:(UITapGestureRecognizer *)g {
    double now = tb_now_ms();
    /* the first tap of a possible double tap: remember the controls (UIKit's double tap waits about 350 ms) */
    if (now - _lastTapMs > 400) _tapPrevShown = _controlsShown;
    _lastTapMs = now;
    if (_controlsShown) [self hideControls]; else [self showControls];
}

/* ---------- gestures: double tap to skip (D51), swipe down to leave full screen (D50) ---------- */

- (void)setFullscreen:(BOOL)f { _fullscreen = f; _swipeDown.enabled = f; }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if (g == _tap) return YES;
    return _bar.hidden || ![t.view isDescendantOfView:_bar];   /* the control bar keeps its own touches */
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return (a == _tap && b == _doubleTap) || (a == _doubleTap && b == _tap);   /* single taps act at once */
}

- (void)doubleTapped:(UITapGestureRecognizer *)g { [self doubleTapAt:[g locationInView:self]]; }

- (int)doubleTapAt:(CGPoint)p {
    if (_tapPrevShown) [self showControls]; else [self hideControls];   /* undo the two single taps */
    CGFloat w = self.bounds.size.width;
    int s = p.x < w / 3 ? -10 : p.x > w * 2 / 3 ? 10 : 0;
    double d = self.duration;
    if (!s || _info.live || d <= 0) return 0;
    [self seekTo:MAX(0, MIN(d - 1, self.currentTime + s))];
    _skip.text = s < 0 ? @"-10 s" : @"+10 s";
    CGRect b = self.bounds;
    _skip.frame = CGRectMake(s < 0 ? b.size.width / 6 - 50 : b.size.width * 5 / 6 - 50, b.size.height / 2 - 22, 100, 44);
    [self bringSubviewToFront:_skip];
    [_skip.layer removeAllAnimations];
    _skip.alpha = 1;
    [UIView animateWithDuration:0.25 delay:0.75 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ self->_skip.alpha = 0; } completion:nil];
    return s;
}

- (BOOL)swipedDown {
    if (!_fullscreen) return NO;
    [self.delegate playerViewToggleFullscreen:self];
    return YES;
}

- (void)showControls {
    _controlsShown = YES;
    _bar.hidden = NO;
    _hideAt = tb_now_ms() + 4000;
    [self tick];
    [self layoutCaption];
}

- (void)hideControls {
    _controlsShown = NO;
    _bar.hidden = YES;
    _hideAt = 0;
    [self layoutCaption];
}

- (void)scrubStart { _scrubbing = YES; _hideAt = 0; }
- (void)scrubMove { _now.text = timeText(_slider.value); }
- (void)scrubEnd {
    _scrubbing = NO;
    [self seekTo:_slider.value];
    _hideAt = tb_now_ms() + 4000;
}

- (void)fullTapped { [self.delegate playerViewToggleFullscreen:self]; _hideAt = tb_now_ms() + 4000; }

- (void)ccTapped {
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:@"Subtitles" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    s.tag = 1;
    [s addButtonWithTitle:@"Off"];
    for (TBCaptionTrack *t in _info.captionTracks) [s addButtonWithTitle:t.asr ? [NSString stringWithFormat:@"%@ (auto-generated)", t.name] : t.name];
    [s showFromRect:_cc.frame inView:_bar animated:YES];
    _hideAt = 0;
}

- (void)qualityTapped {
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:@"Quality" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    s.tag = 2;
    [s addButtonWithTitle:@"Auto (720p first)"];
    for (NSNumber *h in _heights) [s addButtonWithTitle:[NSString stringWithFormat:@"%@p", h]];
    [s showFromRect:_q.frame inView:_bar animated:YES];
    _hideAt = 0;
}

- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    _hideAt = tb_now_ms() + 4000;
    if (i < 0) return;
    if (s.tag == 1) [self selectCaptionIndex:i - 1];
    else [self setQuality:i == 0 ? 0 : [_heights[(NSUInteger)(i - 1)] intValue]];
}
@end
