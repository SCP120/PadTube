#import "TBShortsController.h"
#import <QuartzCore/QuartzCore.h>
#import "TBAccount.h"
#import "TBCommentsController.h"
#import "TBCore.h"
#import "TBImageLoader.h"
#import "TBLog.h"
#import "TBShortsPlayer.h"
#import "TBStyle.h"
#include "tb_http.h"

/* ---------- one action: icon over a short text (portrait column) or beside it (landscape panel) ---------- */

@interface TBShortsAction : UIControl
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) BOOL beside;
@end
@implementation TBShortsAction
- (id)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _icon = [UIImageView new];
    _icon.contentMode = UIViewContentModeCenter;
    _label = [UILabel new];
    _label.font = TBFontBold(12);
    _label.backgroundColor = [UIColor clearColor];
    _label.textAlignment = NSTextAlignmentCenter;
    for (UIView *v in @[_icon, _label]) { v.userInteractionEnabled = NO; [self addSubview:v]; }
    return self;
}
- (void)layoutSubviews {
    CGSize s = self.bounds.size;
    if (_beside) {
        _icon.frame = CGRectMake(0, 0, 30, s.height);
        _label.frame = CGRectMake(32, 0, s.width - 32, s.height);
        _label.textAlignment = NSTextAlignmentLeft;
    } else {
        _icon.frame = CGRectMake(0, 0, s.width, 40);
        _label.frame = CGRectMake(-10, 40, s.width + 20, 16);
        _label.textAlignment = NSTextAlignmentCenter;
    }
}
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; self.alpha = h ? 0.5f : 1; }
@end

/* ---------- one page: cover, video host, texts, actions ---------- */

static UIImage *bottomShade(void) {   /* black 0 -> 65 %, stretched under the portrait texts: no blur pass */
    static UIImage *img;
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 64), NO, 1);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {0, 0, 0, 0, 0, 0, 0, 0.65f};
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextDrawLinearGradient(c, g, CGPointZero, CGPointMake(0, 64), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@interface TBShortsPage : UIView
@property (nonatomic, strong) TBItem *item;
@property (nonatomic) NSInteger index;
@property (nonatomic, strong) UIView *videoHost;
@property (nonatomic, strong) TBShortsAction *like, *comments, *share, *subscribe;
@property (nonatomic, strong) UIImageView *pauseMark;
@property (nonatomic, strong) UILabel *message;
@end
@implementation TBShortsPage {
    UIImageView *_cover, *_shade;
    UIView *_panel;
    UILabel *_channel, *_title, *_views;
    id _token;
    CGSize _coverPx;
}
- (id)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.backgroundColor = [UIColor blackColor];
    _index = -1;
    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFit;
    _cover.backgroundColor = [UIColor blackColor];
    _videoHost = [UIView new];
    _videoHost.backgroundColor = [UIColor clearColor];
    _videoHost.userInteractionEnabled = NO;
    _shade = [[UIImageView alloc] initWithImage:bottomShade()];
    _panel = [UIView new];
    _channel = [UILabel new];
    _title = [UILabel new];
    _views = [UILabel new];
    _title.numberOfLines = 3;
    _pauseMark = [[UIImageView alloc] initWithImage:[TBStyle icon:@"play" size:64 color:[UIColor colorWithWhite:1 alpha:0.8f]]];
    _pauseMark.hidden = YES;
    _message = [UILabel new];
    _message.textColor = [UIColor whiteColor];
    _message.backgroundColor = [UIColor clearColor];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 3;
    _message.font = TBFont(15);
    _like = [TBShortsAction new];
    _comments = [TBShortsAction new];
    _share = [TBShortsAction new];
    _subscribe = [TBShortsAction new];
    for (UIView *v in @[_cover, _videoHost, _shade, _pauseMark, _message, _panel, _channel, _title, _views, _like, _comments, _share, _subscribe]) [self addSubview:v];
    return self;
}

- (BOOL)landscape { return self.bounds.size.width > self.bounds.size.height; }

- (CGRect)videoFrame {
    CGSize s = self.bounds.size;
    CGFloat w = floor(s.height * 9 / 16);
    return CGRectMake([self landscape] ? 0 : floor((s.width - w) / 2), 0, w, s.height);
}

- (void)style {
    BOOL land = [self landscape];
    /* portrait: white texts on the video's dark shade; landscape: the side panel in the theme (D56) */
    UIColor *t1 = land ? [TBStyle text] : [UIColor whiteColor], *t2 = land ? [TBStyle secondary] : [UIColor colorWithWhite:1 alpha:0.85f];
    _panel.backgroundColor = [TBStyle contentBackground];
    _panel.hidden = !land;
    _shade.hidden = land;
    for (UILabel *l in @[_channel, _title, _views]) {
        l.backgroundColor = land ? [TBStyle contentBackground] : [UIColor clearColor];
        l.shadowColor = land ? nil : [UIColor colorWithWhite:0 alpha:0.6f];
        l.shadowOffset = CGSizeMake(0, 1);
    }
    _channel.font = TBFontBold(land ? 17 : 15);
    _channel.textColor = t1;
    _title.font = TBFont(land ? 18 : 14);
    _title.textColor = t1;
    _views.font = TBFont(14);
    _views.textColor = t2;
    UIColor *ic = land ? [TBStyle text] : [UIColor whiteColor];
    for (TBShortsAction *a in @[_like, _comments, _share, _subscribe]) {
        a.beside = land;
        a.label.textColor = ic;
        a.label.font = TBFontBold(land ? 15 : 12);
        a.label.shadowColor = land ? nil : [UIColor colorWithWhite:0 alpha:0.6f];
        a.label.shadowOffset = CGSizeMake(0, 1);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self style];
    CGRect v = [self videoFrame];
    _cover.frame = v;
    _videoHost.frame = v;
    for (UIView *s in _videoHost.subviews) s.frame = _videoHost.bounds;
    _pauseMark.center = CGPointMake(CGRectGetMidX(v), CGRectGetMidY(v));
    _message.frame = CGRectInset(v, 20, v.size.height / 2 - 40);
    if ([self landscape]) {
        CGFloat x = CGRectGetMaxX(v), w = self.bounds.size.width - x, px = x + 22, pw = w - 44, y = 22;
        _panel.frame = CGRectMake(x, 0, w, self.bounds.size.height);
        _title.frame = CGRectMake(px, y, pw, 70);
        [_title sizeToFit];
        _title.frame = CGRectMake(px, y, pw, MIN(_title.frame.size.height, 70));
        y = CGRectGetMaxY(_title.frame) + 8;
        _views.frame = CGRectMake(px, y, pw, 18); y += 34;
        _channel.frame = CGRectMake(px, y, pw, 22); y += 34;
        _subscribe.frame = CGRectMake(px, y, pw, 36); y += 48;
        _like.frame = CGRectMake(px, y, pw, 36); y += 44;
        _comments.frame = CGRectMake(px, y, pw, 36); y += 44;
        _share.frame = CGRectMake(px, y, pw, 36);
    } else {
        /* the actions in the dark bar right of the video (no cover over the picture); texts on the shade */
        CGFloat bar = self.bounds.size.width - CGRectGetMaxX(v), cx = CGRectGetMaxX(v) + MAX(bar, 64) / 2 - (bar < 64 ? 64 : 0);
        CGFloat y = v.size.height - 4 * 76 - 30;
        for (TBShortsAction *a in @[_like, _comments, _share, _subscribe]) { a.frame = CGRectMake(cx - 32, y, 64, 60); y += 76; }
        CGFloat tw = v.size.width - 32;
        _shade.frame = CGRectMake(v.origin.x, CGRectGetMaxY(v) - 150, v.size.width, 150);
        _title.frame = CGRectMake(v.origin.x + 16, 0, tw, 60);
        [_title sizeToFit];
        CGFloat th = MIN(_title.frame.size.height, 54);
        _title.frame = CGRectMake(v.origin.x + 16, CGRectGetMaxY(v) - 18 - th, tw, th);
        _channel.frame = CGRectMake(v.origin.x + 16, _title.frame.origin.y - 24, tw, 20);
        _views.frame = CGRectZero;
    }
    [self loadCover];
}

- (void)loadCover {   /* frame0.jpg at the video frame's pixel size (D55) */
    CGRect v = [self videoFrame];
    CGFloat sc = [UIScreen mainScreen].scale;
    CGSize px = CGSizeMake(floor(v.size.width * sc), floor(v.size.height * sc));
    if (!_item || px.width < 1 || CGSizeEqualToSize(px, _coverPx)) return;
    _coverPx = px;
    [TBImageLoader cancel:_token];
    __weak TBShortsPage *w = self;
    NSString *vid = _item.ident;
    _token = [TBImageLoader load:_item.thumb pixelSize:px done:^(UIImage *img) {
        TBShortsPage *p = w;
        if (p && [p.item.ident isEqualToString:vid]) p->_cover.image = img;
    }];
}

- (void)setItem:(TBItem *)it {
    if (it == _item) return;
    _item = it;
    [TBImageLoader cancel:_token];
    _token = nil;
    _cover.image = nil;
    _coverPx = CGSizeZero;
    _message.hidden = YES;
    _pauseMark.hidden = YES;
    [self showInfo:nil next:nil];
    [self setNeedsLayout];
}

- (void)showInfo:(TBPlayerInfo *)info next:(TBNextInfo *)n {
    _channel.text = n.channel.length ? n.channel : info.author;
    _title.text = info.title ?: n.title;
    _views.text = info.views.length ? info.views : n.views;
    _like.icon.image = [TBStyle icon:@"like" size:26 color:[self landscape] ? [TBStyle text] : [UIColor whiteColor]];
    _like.label.text = n.likes.length ? n.likes : @"Like";
    _comments.icon.image = [TBStyle icon:@"comment" size:26 color:[self landscape] ? [TBStyle text] : [UIColor whiteColor]];
    _comments.label.text = n.commentCount.length ? n.commentCount : @"Comments";
    _share.icon.image = [TBStyle icon:@"share" size:26 color:[self landscape] ? [TBStyle text] : [UIColor whiteColor]];
    _share.label.text = @"Share";
    BOOL subd = n.subscribed == 1;
    _subscribe.icon.image = [TBStyle icon:subd ? @"check" : @"plus" size:24 color:[self landscape] ? [TBStyle text] : [UIColor whiteColor]];
    _subscribe.label.text = subd ? @"Subscribed" : @"Subscribe";
    [self setNeedsLayout];
}
@end

/* ---------- the controller ---------- */

static const int kSlots = 2;               /* current + next: 3 slots (previous kept) were slower in every run: the A5 drops a decoder (D57, MEASURED) */
static const double kSafeAhead = 2;        /* s of the current Short loaded before the next one may load (4 s: too late for 1 s per Short, MEASURED) */
static const CGFloat kPull = 80;           /* pt past the top of the first Short that reloads (iOS 6 Mail-like) */
/* One player call per Short (no second call for the same video while one is on the way). No pacing: the owner
 * cancelled it (2026-11-13); the "not a bot" cause is the logged-out player path (D60). A preload never changes the
 * visitor ID (tb_yt_player_opt). */
static const double kBotRetryMs = 30000;

@interface TBShortsController () <UIScrollViewDelegate>
@end

@implementation TBShortsController {
    NSMutableArray *_items;
    NSArray *_pages;                    /* 3 page views: index % 3 */
    NSArray *_slots;                    /* 2 or 3 TBShortsPlayer (preload window) */
    NSMutableDictionary *_infos, *_nexts;
    NSString *_continuation;
    BOOL _loading, _userPaused, _visible, _prepareNext, _frameLogged, _retryPending;
    double _settleAt, _reloadAt;
    NSUInteger _feedGen;                /* a reload drops the answers of the older feed */
    id _aheadCover;                     /* cover of the Short after the next one (TBImageLoader token) */
    NSMutableDictionary *_infoWaiters;  /* video -> blocks waiting for its player answer (one call per Short) */

    UILabel *_pull;
    UIPopoverController *_sharePop;
    UILabel *_empty;
}

- (id)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.title = @"Shorts";
    _items = [NSMutableArray array];
    _infoWaiters = [NSMutableDictionary dictionary];
    _infos = [NSMutableDictionary dictionary];
    _nexts = [NSMutableDictionary dictionary];
    _index = -1;
    return self;
}

- (NSUInteger)count { return _items.count; }

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 768, 960)];
    v.backgroundColor = [UIColor blackColor];
    _pager = [[UIScrollView alloc] initWithFrame:v.bounds];
    _pager.pagingEnabled = YES;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.alwaysBounceVertical = YES;
    _pager.scrollsToTop = NO;
    _pager.delegate = self;
    _pager.backgroundColor = [UIColor blackColor];
    [v addSubview:_pager];
    NSMutableArray *ps = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        TBShortsPage *p = [TBShortsPage new];
        [p.like addTarget:self action:@selector(likeTapped) forControlEvents:UIControlEventTouchUpInside];
        [p.comments addTarget:self action:@selector(openComments) forControlEvents:UIControlEventTouchUpInside];
        [p.share addTarget:self action:@selector(shareTapped:) forControlEvents:UIControlEventTouchUpInside];
        [p.subscribe addTarget:self action:@selector(subscribeTapped) forControlEvents:UIControlEventTouchUpInside];
        [p addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePause)]];
        p.hidden = YES;
        [_pager addSubview:p];
        [ps addObject:p];
    }
    _pages = ps;
    _empty = [UILabel new];
    _empty.textColor = [UIColor colorWithWhite:1 alpha:0.8f];
    _empty.backgroundColor = [UIColor clearColor];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.font = TBFont(16);
    _empty.text = @"Loading Shorts...";
    [v addSubview:_empty];
    _pull = [UILabel new];
    _pull.textColor = [UIColor colorWithWhite:1 alpha:0.8f];
    _pull.backgroundColor = [UIColor clearColor];
    _pull.textAlignment = NSTextAlignmentCenter;
    _pull.font = TBFontBold(15);
    _pull.hidden = YES;
    [_pager addSubview:_pull];
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak TBShortsController *w = self;
    /* previous + current + next: a step back finds its Short loaded (the window of the owner's preload strategy) */
    int n = (int)([[NSUserDefaults standardUserDefaults] integerForKey:@"TBShortsSlots"] ?: kSlots);
    [TBShortsPlayer makePlayers:n done:^(NSArray *ps) { [w gotPlayers:ps]; }];   /* off the main thread */
    [self loadMore];
}

- (void)gotPlayers:(NSArray *)ps {
    __weak TBShortsController *w = self;
    for (TBShortsPlayer *p in ps) p.changed = ^(TBShortsPlayer *x) { [w slotChanged:x]; };
    _slots = ps;
    if (_items.count && _index < 0) [self pagerSettled];
}

/* The reload button (owner 2026-11-13): a new feed from the start; old Shorts and players are let go. */
- (void)reload {
    for (TBShortsPlayer *p in _slots) [p unload];
    _current = nil;
    _feedGen++;
    [_items removeAllObjects];
    [_infos removeAllObjects];
    [_infoWaiters removeAllObjects];
    [_nexts removeAllObjects];
    _continuation = nil;
    _loading = NO;
    _index = -1;
    _userPaused = NO;
    [TBImageLoader cancel:_aheadCover];
    _aheadCover = nil;
    for (TBShortsPage *p in _pages) { p.hidden = YES; p.index = -1; p.item = nil; }
    _pager.contentOffset = CGPointZero;
    _pager.contentSize = _pager.bounds.size;
    _empty.text = @"Loading Shorts...";
    _empty.hidden = NO;
    _reloadAt = tb_now_ms();
    [self loadMore];
}

- (void)testFeed:(NSArray *)items {
    [self reload];
    _feedGen++;   /* the feed request that reload started is dropped */
    _loading = NO;
    TBPage *p = [TBPage new];
    p.items = items;
    [self gotPage:p];
}

- (UIButton *)headerButton {   /* TBShell puts it left of the search field (2012 header style) */
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[TBStyle icon:@"reload" size:22 color:TBHex(0xAFAFAF)] forState:UIControlStateNormal];
    [b setImage:[TBStyle icon:@"reload" size:22 color:[UIColor whiteColor]] forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
    b.accessibilityLabel = @"Reload Shorts";
    return b;
}

- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    _visible = YES;
    if (_current && !_userPaused) [_current play];
}

- (void)viewWillDisappear:(BOOL)a {
    [super viewWillDisappear:a];
    _visible = NO;
    [_current pause];   /* another tab or the comments screen: no sound behind it */
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    _empty.frame = b;
    if (!CGRectEqualToRect(_pager.frame, b)) {
        _pager.frame = b;
        _pager.contentSize = CGSizeMake(b.size.width, b.size.height * MAX(1, _items.count));
        _pager.contentOffset = CGPointMake(0, b.size.height * MAX(0, _index));
    }
    [self placePages];
}

/* ---------- feed ---------- */

- (void)loadMore {
    if (_loading || (_items.count && !_continuation)) return;
    _loading = YES;
    __weak TBShortsController *w = self;
    NSUInteger gen = _feedGen;
    [TBCore shorts:_continuation done:^(TBPage *p) {
        TBShortsController *s = w;
        if (s && s->_feedGen == gen) [s gotPage:p];
    }];
}

- (void)gotPage:(TBPage *)p {
    _loading = NO;
    NSMutableSet *have = [NSMutableSet set];
    for (TBItem *it in _items) [have addObject:it.ident];
    for (TBItem *it in p.items) if (![have containsObject:it.ident]) { [_items addObject:it]; [have addObject:it.ident]; }
    _continuation = p.continuation;
    _empty.hidden = _items.count > 0;
    if (!_items.count) { _empty.text = p.error.length ? [NSString stringWithFormat:@"Shorts did not load (%@).", p.error] : @"No Shorts."; return; }
    CGRect b = _pager.bounds;
    _pager.contentSize = CGSizeMake(b.size.width, b.size.height * _items.count);
    if (_index < 0 && _slots.count) [self pagerSettled];
    else [self placePages];
}

/* ---------- pages ---------- */

- (TBShortsPage *)pageFor:(NSInteger)i { return i < 0 || i >= (NSInteger)_items.count ? nil : _pages[(NSUInteger)(i % 3)]; }

- (void)placePages {
    CGSize s = _pager.bounds.size;
    NSInteger n = MAX(0, _index);
    for (NSInteger i = n - 1; i <= n + 1; i++) {
        TBShortsPage *p = [self pageFor:i];
        if (!p) continue;
        p.index = i;
        p.item = _items[(NSUInteger)i];
        p.frame = CGRectMake(0, s.height * i, s.width, s.height);
        p.hidden = NO;
        [p showInfo:_infos[p.item.ident] next:_nexts[p.item.ident]];
    }
    for (TBShortsPage *p in _pages) if (p.index < n - 1 || p.index > n + 1) p.hidden = YES;
    for (TBShortsPlayer *p in _slots) [self attach:p];
}

- (void)attach:(TBShortsPlayer *)slot {   /* the slot's video layer goes on the page that shows its Short */
    if (!slot.videoId) return;
    for (TBShortsPage *p in _pages)
        if (!p.hidden && [p.item.ident isEqualToString:slot.videoId]) {
            if (slot.view.superview != p.videoHost) { [p.videoHost addSubview:slot.view]; slot.view.frame = p.videoHost.bounds; }
            return;
        }
}

/* ---------- swipe end: play the prepared player, pause the other, prepare the next (docs/design/shorts.md §2) ---------- */

- (void)scrollViewDidEndDecelerating:(UIScrollView *)s { [self pagerSettled]; }
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)s { [self pagerSettled]; }
- (void)scrollViewDidEndDragging:(UIScrollView *)s willDecelerate:(BOOL)d {
    if (s.contentOffset.y < -kPull && _index <= 0) { [self reload]; return; }   /* pull down at the first Short */
    if (!d) [self pagerSettled];
}

- (void)scrollViewDidScroll:(UIScrollView *)s {
    CGFloat y = s.contentOffset.y;
    _pull.hidden = y >= 0;
    if (y < 0) {
        _pull.text = y < -kPull ? @"Release to reload" : @"Pull to reload";
        _pull.frame = CGRectMake(0, y, s.bounds.size.width, -y);
    }
}

- (TBShortsPlayer *)slotFor:(NSString *)vid {
    if (!vid) return nil;
    for (TBShortsPlayer *p in _slots) if ([p.videoId isEqualToString:vid]) return p;
    return nil;
}

- (NSString *)idAt:(NSInteger)i { return i >= 0 && i < (NSInteger)_items.count ? [_items[(NSUInteger)i] ident] : nil; }

/* a slot to load a Short into: an empty one, else one outside the window, else the previous Short's (with 2
 * slots the next Short wins over a quick step back); never the Short on screen */
- (TBShortsPlayer *)freeSlotKeeping:(NSArray *)keep {
    TBShortsPlayer *outside = nil, *kept = nil;
    NSString *cur = [self idAt:_index];
    for (TBShortsPlayer *p in _slots) {
        if (!p.videoId) return p;
        if ([p.videoId isEqualToString:cur] && p == _current) continue;
        if (![keep containsObject:p.videoId]) outside = p;
        else if (![p.videoId isEqualToString:cur]) kept = p;
    }
    return outside ?: kept;
}

- (void)pagerSettled {
    if (!_items.count || !_slots.count) return;
    CGFloat h = _pager.bounds.size.height;
    NSInteger n = h > 0 ? (NSInteger)lround(_pager.contentOffset.y / h) : 0;
    n = MAX(0, MIN((NSInteger)_items.count - 1, n));
    if (n == _index && _current) return;
    _index = n;
    _settleAt = tb_now_ms();
    _frameLogged = NO;
    _userPaused = NO;
    [self placePages];
    NSString *vid = [self idAt:n], *prev = [self idAt:n - 1], *next = [self idAt:n + 1];
    TBShortsPlayer *cur = [self slotFor:vid];
    _lastWasPrepared = cur.ready && cur.shown;
    if (!cur || cur.errorText) {   /* not in the window (a fast flick, a step back past it) or failed: load it now */
        cur = cur ?: [self freeSlotKeeping:@[prev ?: @"", next ?: @""]];
        cur.preloadOnly = NO;
        [self loadSlot:cur video:vid onScreen:YES];
    }

    /* the window: previous paused and frozen at the data it has, next stays preload-only, the rest let go (their
     * downloads stop: a fast flick wastes nothing more) */
    for (TBShortsPlayer *p in _slots) {
        if (p == cur || !p.videoId) continue;
        if ([p.videoId isEqualToString:prev]) { [p pause]; [p freeze]; }   /* iOS 6 has no AVPlayer volume: only one plays */
        else if ([p.videoId isEqualToString:next]) { [p pause]; p.preloadOnly = YES; }
        else [p unload];
    }
    _current = cur;
    [self attach:cur];
    if (_visible) [cur play];   /* else viewWillAppear plays it */
    _prepareNext = YES;
    if (cur.firstFrameMs >= 0 || cur.errorText) [self prepareNext];
    if (!_nexts[vid]) {
        __weak TBShortsController *w = self;
        [TBCore next:vid done:^(TBNextInfo *ni) { [w gotNext:ni for:vid]; }];
    }
    if (n + 3 >= (NSInteger)_items.count) [self loadMore];   /* the next feed page when 3 Shorts remain */
}

/* After the current Short's first frame, and only when its own data is safe (4 s ahead or all of it), so it never
 * starves on a slow network: the next Short into a slot (segment 0 only), then the metadata and cover of the one
 * after it. */
- (void)prepareNext {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TBShortsNoPrepare"]) { _prepareNext = NO; return; }   /* self-test A/B */
    TBShortsPlayer *cur = _current;
    if (cur && !cur.errorText && cur.bufferedAhead < kSafeAhead && !cur.fullyLoaded) {
        NSInteger at = _index;
        __weak TBShortsController *w = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            TBShortsController *s = w;
            if (s && s->_index == at && s->_prepareNext) [s prepareNext];
        });
        return;
    }
    _prepareNext = NO;
    NSString *prev = [self idAt:_index - 1], *vid = [self idAt:_index + 1], *after = [self idAt:_index + 2];
    if (vid && ![self slotFor:vid]) {
        TBShortsPlayer *p = [self freeSlotKeeping:@[prev ?: @"", [self idAt:_index] ?: @""]];
        if (p && p != cur) {
            TBLog(@"PadTube: Short %@ prepare next (current ahead %.1f s, %.0f ms after the swipe)", vid, cur.bufferedAhead, tb_now_ms() - _settleAt);
            p.preloadOnly = YES;
            [self loadSlot:p video:vid onScreen:NO];
            [self attach:p];
        }
    }
    if (after) [self preloadInfo:after index:_index + 2];
}

/* ---------- player answers: one call per Short, preloads paced (owner bug "not a bot", 2026-11-13) ---------- */

- (void)loadSlot:(TBShortsPlayer *)p video:(NSString *)vid onScreen:(BOOL)now {
    [p reserve:vid];   /* slotFor: finds it while its answer comes */
    __weak TBShortsPlayer *wp = p;
    [self infoFor:vid onScreen:now done:^(TBPlayerInfo *info) {
        TBShortsPlayer *s = wp;
        if (s && [s.videoId isEqualToString:vid] && !s.info) [s load:vid info:info];
    }];
}

- (void)infoFor:(NSString *)vid onScreen:(BOOL)now done:(void (^)(TBPlayerInfo *))done {
    if (_infos[vid]) { done(_infos[vid]); return; }
    NSMutableArray *ws = _infoWaiters[vid];
    if (ws) { [ws addObject:[done copy]]; return; }
    _infoWaiters[vid] = [NSMutableArray arrayWithObject:[done copy]];
    [self fetchInfo:vid preload:!now];
}

- (void)fetchInfo:(NSString *)vid preload:(BOOL)pre {
    __weak TBShortsController *w = self;
    NSUInteger gen = _feedGen;
    [TBCore player:vid visitorReset:!pre done:^(TBPlayerInfo *info) {
        TBShortsController *s = w;
        if (!s) return;
        if (s->_feedGen != gen) { [s->_infoWaiters removeObjectForKey:vid]; return; }
        if ([info.status isEqualToString:@"OK"]) {
            s->_infos[vid] = info;
            for (TBShortsPage *pg in s->_pages) if ([pg.item.ident isEqualToString:vid]) [pg showInfo:info next:s->_nexts[vid]];
        } else TBLog(@"PadTube: Short %@ player answer %@ (%@)", vid, info.status, pre ? @"preload" : @"on screen");
        NSArray *ws = s->_infoWaiters[vid];
        [s->_infoWaiters removeObjectForKey:vid];
        for (void (^b)(TBPlayerInfo *) in ws) b(info);   /* not cached when not OK: asked again on screen */
    }];
}

- (void)preloadInfo:(NSString *)vid index:(NSInteger)i {
    if (!_infos[vid] && !_infoWaiters[vid]) [self infoFor:vid onScreen:NO done:^(TBPlayerInfo *info) {}];
    /* the cover at the page's size, into the image RAM cache: the page shows it at once */
    CGSize v = _pager.bounds.size;
    CGFloat w0 = floor(v.height * 9 / 16), sc = [UIScreen mainScreen].scale;
    TBItem *it = _items[(NSUInteger)i];
    [TBImageLoader cancel:_aheadCover];
    _aheadCover = [TBImageLoader load:it.thumb pixelSize:CGSizeMake(floor(w0 * sc), floor(v.height * sc)) done:^(UIImage *img) {}];
}

- (void)slotChanged:(TBShortsPlayer *)p {
    NSString *vid = p.videoId;
    if (!vid) return;
    if (p.info && !_infos[vid]) {
        _infos[vid] = p.info;
        for (TBShortsPage *pg in _pages) if ([pg.item.ident isEqualToString:vid]) [pg showInfo:p.info next:_nexts[vid]];
    }
    TBShortsPage *page = [self pageFor:_index];
    if (p == _current) {
        BOOL bot = [p.info.status isEqualToString:@"LOGIN_REQUIRED"];
        page.message.hidden = !p.errorText;
        page.message.text = p.errorText;   /* TBPlayerProblem: a plain text for YouTube's bot check */
        if (bot && !_retryPending) {   /* once, later, with the normal path (it may get a new visitor ID, at most every 10 min) */
            _retryPending = YES;
            NSInteger at = _index;
            __weak TBShortsController *w = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBotRetryMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                TBShortsController *s = w;
                if (!s) return;
                s->_retryPending = NO;
                if (s->_index == at && [s->_current.videoId isEqualToString:vid] && s->_current.errorText) {
                    [s loadSlot:s->_current video:vid onScreen:YES];
                    if (s->_visible) [s->_current play];
                }
            });
        }
        if (!_frameLogged && p.firstFrameMs >= 0) {
            _frameLogged = YES;
            _lastSettleToFrameMs = tb_now_ms() - _settleAt;
            if (_reloadAt > 0) { _lastReloadToFrameMs = tb_now_ms() - _reloadAt; _reloadAt = 0; }
            TBLog(@"PadTube: Short %@ first frame %.0f ms after the swipe (play -> frame %.0f ms, prepared %d)", vid,
                  _lastSettleToFrameMs, p.firstFrameMs, _lastWasPrepared);
            if (self.firstFrame) self.firstFrame(self);
        }
        if (_prepareNext && (p.firstFrameMs >= 0 || p.errorText)) [self prepareNext];   /* after the frame: no work in the swipe */
    }
    [self attach:p];
}

- (void)gotNext:(TBNextInfo *)n for:(NSString *)vid {
    if (!n) return;
    _nexts[vid] = n;
    for (TBShortsPage *pg in _pages) if ([pg.item.ident isEqualToString:vid]) [pg showInfo:_infos[vid] next:n];
}

/* ---------- actions ---------- */

- (void)togglePause {
    if (!_current) return;
    _userPaused = _current.wantsPlay;
    if (_userPaused) [_current pause]; else [_current play];
    [self pageFor:_index].pauseMark.hidden = !_userPaused;
}

- (BOOL)needSignIn:(NSString *)what {
    if ([TBAccount signedIn]) return NO;
    [[[UIAlertView alloc] initWithTitle:@"Sign in" message:[NSString stringWithFormat:@"Sign in (Account in the guide) to %@.", what]
                               delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    return YES;
}

- (NSString *)currentId { return _index >= 0 && _index < (NSInteger)_items.count ? [_items[(NSUInteger)_index] ident] : nil; }

- (void)likeTapped {
    NSString *vid = [self currentId];
    if (!vid || [self needSignIn:@"like videos"]) return;
    TBShortsPage *p = [self pageFor:_index];
    [TBAccount like:vid action:1 done:^(BOOL ok) {
        if (ok && [p.item.ident isEqualToString:vid]) p.like.icon.image = [TBStyle icon:@"liked" size:26 color:TBHex(0x5474CF)];
    }];
}

- (void)subscribeTapped {
    NSString *vid = [self currentId];
    TBNextInfo *n = vid ? _nexts[vid] : nil;
    NSString *ch = n.channelId ?: [_infos[vid] channelId];
    if (!ch || [self needSignIn:@"subscribe"]) return;
    BOOL on = n.subscribed != 1;
    [TBAccount subscribe:ch on:on done:^(BOOL ok) {
        if (!ok) return;
        n.subscribed = on;
        [self gotNext:n for:vid];
    }];
}

- (void)openComments {
    NSString *vid = [self currentId];
    TBNextInfo *n = vid ? _nexts[vid] : nil;
    if (!n.commentsToken) {
        [[[UIAlertView alloc] initWithTitle:@"Comments" message:n ? @"Comments are turned off for this Short." : @"Comments are still loading."
                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    TBCommentsController *c = [[TBCommentsController alloc] initWithToken:n.commentsToken title:n.commentCount];
    c.title = n.commentCount.length ? [NSString stringWithFormat:@"Comments (%@)", n.commentCount] : @"Comments";
    [self.navigationController pushViewController:c animated:YES];   /* swipe back returns (D49, D56) */
}

- (void)shareTapped:(UIView *)b {
    NSString *vid = [self currentId];
    if (!vid) return;
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"https://youtube.com/shorts/%@", vid]];
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[u] applicationActivities:nil];
    _sharePop = [[UIPopoverController alloc] initWithContentViewController:a];
    [_sharePop presentPopoverFromRect:b.bounds inView:b permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)share:(BOOL)open {
    if (!open) { [_sharePop dismissPopoverAnimated:NO]; return; }
    TBShortsPage *p = [self pageFor:_index];
    if (p) [self shareTapped:p.share];
}

- (NSDictionary *)testState {
    NSMutableArray *slots = [NSMutableArray array];
    for (TBShortsPlayer *q in _slots)
        [slots addObject:@{@"video": q.videoId ?: @"", @"ready": @(q.ready), @"shown": @(q.shown), @"preload_only": @(q.preloadOnly),
                           @"playing": @(q.wantsPlay), @"load_ms": @(q.loadMs), @"ahead_s": @(q.bufferedAhead), @"error": q.errorText ?: @""}];
    TBShortsPage *p = [self pageFor:_index];
    return @{@"index": @(_index), @"count": @(_items.count), @"video": [self currentId] ?: @"", @"current_slot": @(_current ? [_slots indexOfObject:_current] : 0), @"reload_to_frame_ms": @(_lastReloadToFrameMs),
             @"settle_to_frame_ms": @(_lastSettleToFrameMs), @"prepared": @(_lastWasPrepared), @"paused": @(_userPaused),
             @"title": [_infos[[self currentId] ?: @""] title] ?: @"", @"length": @([_infos[[self currentId] ?: @""] lengthSeconds]), @"has_next_info": @(_nexts[[self currentId] ?: @""] != nil),
             @"page_rect": p ? NSStringFromCGRect([p convertRect:p.bounds toView:nil]) : @"", @"slots": slots, @"share_open": @(_sharePop.popoverVisible)};
}
@end
