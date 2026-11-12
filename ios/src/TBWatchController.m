#import "TBWatchController.h"
#import <objc/message.h>
#import "TBAccount.h"
#import "TBCommentsController.h"
#import "TBCore.h"
#import "TBImageLoader.h"
#import "TBItemCell.h"
#import "TBListController.h"
#import "TBPlayerView.h"
#import "TBShell.h"
#import "TBLinks.h"
#import "TBStore.h"
#import "TBStyle.h"
#import "TBSegments.h"
#include "tb_http.h"

static __weak TBWatchController *g_current;

/* Full screen player: presented over everything, landscape only (owner request 2026-11-11). iOS 6 rotates the
 * interface to preferredInterfaceOrientationForPresentation when a controller with these masks is presented. */
@interface TBFullController : UIViewController
@property (nonatomic, strong) UIView *content;
@end
@implementation TBFullController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor blackColor];
}
- (void)viewWillLayoutSubviews { [super viewWillLayoutSubviews]; self.content.frame = self.view.bounds; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    UIInterfaceOrientation o = [UIApplication sharedApplication].statusBarOrientation;
    return UIInterfaceOrientationIsLandscape(o) ? o : UIInterfaceOrientationLandscapeRight;
}
- (BOOL)shouldAutorotate { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return UIInterfaceOrientationIsLandscape(o); }
@end

@interface TBWatchController () <TBPlayerViewDelegate, UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, TBFullWidth, UIGestureRecognizerDelegate>
@end

@implementation TBWatchController {
    NSString *_title;
    double _t0;
    TBPlayerInfo *_info;
    UIImageView *_tabBar;
    TBSegments *_segments;
    UIView *_pane, *_rule;              /* About pane: two columns */
    UIView *_panel;                     /* dark related panel */
    UILabel *_panelTitle;
    UITableView *_related;
    UILabel *_titleLabel, *_dateLabel, *_viewsLabel, *_channelLabel, *_subsLabel;
    UIImageView *_avatar;
    UIButton *_likeB, *_dislikeB, *_saveB, *_chaptersB, *_subB;
    UITextView *_desc;
    TBCommentsController *_comments;
    BOOL _relatedPortrait;
    NSArray *_descLinks;
    UILabel *_noComments;          /* Comments tab with no comments token */            /* links of the description, found off the main thread */
    NSInteger _tab;                     /* 0 About, 1 Comments, 2 Suggested (portrait) */
    BOOL _full, _viewReady, _stopped;
    TBFullController *_fc;
    UIInterfaceOrientation _orientationBeforeFull;
    NSTimer *_saveTimer;
    int _subscribed;
    id _avatarToken;
}

+ (TBWatchController *)current { return g_current; }
- (BOOL)isFullscreen { return _full; }
- (BOOL)wantsFullWidth { return YES; }

- (id)initWithVideoId:(NSString *)videoId title:(NSString *)title {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _videoId = [videoId copy];
    _title = [title copy];
    self.title = title;
    _t0 = tb_now_ms();
    _subscribed = -1;
    __weak TBWatchController *w = self;
    [TBCore player:videoId done:^(TBPlayerInfo *info) { [w gotPlayer:info]; }];
    [TBCore next:videoId done:^(TBNextInfo *n) { [w gotNext:n]; }];
    return self;
}

- (UIButton *)lightButton:(NSString *)title icon:(NSString *)icon action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:[TBStyle lightButtonImage:NO] forState:UIControlStateNormal];
    [b setBackgroundImage:[TBStyle lightButtonImage:YES] forState:UIControlStateHighlighted];
    if (icon) [b setImage:[TBStyle icon:icon size:16 color:[TBStyle tertiary]] forState:UIControlStateNormal];
    if (title) {
        [b setTitle:title forState:UIControlStateNormal];
        [b setTitleColor:[TBStyle dark] ? [TBStyle buttonText] : TBHex(0x555555) forState:UIControlStateNormal];
        b.titleLabel.font = TBFont(14);
        if (icon) b.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    }
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    [_pane addSubview:b];
    return b;
}

static UILabel *paneLabel(CGFloat size, UIColor *c, int lines) {
    UILabel *l = [UILabel new];
    l.font = TBFont(size);
    l.textColor = c;
    l.backgroundColor = [TBStyle contentBackground];
    l.numberOfLines = lines;
    return l;
}

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, 704)];
    v.backgroundColor = [TBStyle contentBackground];
    _player = [[TBPlayerView alloc] initWithFrame:CGRectMake(0, 0, 768, 432)];
    _player.delegate = self;
    [v addSubview:_player];
    /* §8.3 tab bar */
    _tabBar = [[UIImageView alloc] initWithImage:[TBStyle tabBarImage]];
    _tabBar.userInteractionEnabled = YES;
    _segments = [TBSegments new];
    __weak TBWatchController *w = self;
    _segments.changed = ^(NSInteger i) { [w tabChanged:i]; };
    [_tabBar addSubview:_segments];
    [v addSubview:_tabBar];
    /* §8.4 About pane */
    _pane = [UIView new];
    _pane.backgroundColor = [TBStyle contentBackground];
    _titleLabel = paneLabel(20, [TBStyle text], 2);
    _titleLabel.text = _title;
    _dateLabel = paneLabel(15, [TBStyle secondary], 1);
    _viewsLabel = paneLabel(16, [TBStyle text], 1);
    _channelLabel = paneLabel(18, [TBStyle text], 1);
    _channelLabel.userInteractionEnabled = YES;
    [_channelLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openChannel)]];
    _subsLabel = paneLabel(14, [TBStyle secondary], 1);
    _avatar = [UIImageView new];
    _avatar.backgroundColor = [TBStyle placeholder];
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openChannel)]];
    _rule = [UIView new];
    _rule.backgroundColor = [TBStyle dark] ? [TBStyle rule] : TBHex(0xB8B8B8);
    _desc = [UITextView new];
    _desc.editable = NO;
    _desc.font = TBFont(14);
    _desc.textColor = [TBStyle text];
    _desc.backgroundColor = [TBStyle contentBackground];
    _desc.dataDetectorTypes = UIDataDetectorTypeNone; /* links: TBLinks (in the app with PadWeb, not Safari) */
    [_desc addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(descTapped:)]];
    for (UIView *x in @[_titleLabel, _dateLabel, _viewsLabel, _channelLabel, _subsLabel, _avatar, _rule, _desc]) [_pane addSubview:x];
    _likeB = [self lightButton:nil icon:@"like" action:@selector(likeTapped)];
    _dislikeB = [self lightButton:nil icon:@"dislike" action:@selector(dislikeTapped)];
    _saveB = [self lightButton:@"Watch Later" icon:@"later" action:@selector(saveTapped)];
    _chaptersB = [self lightButton:@"Chapters" icon:nil action:@selector(chaptersTapped)];
    _chaptersB.hidden = YES;
    /* no Speed button: iOS 6 ignores the rate for our stream with both players (D42) */
    _subB = [self lightButton:@"Subscribe" icon:nil action:@selector(subTapped)];
    _subB.titleLabel.font = TBFont(16);
    [v addSubview:_pane];
    /* §7.3 related panel */
    _panel = [UIView new];
    _panel.backgroundColor = [TBStyle panel];
    _panelTitle = [UILabel new];
    _panelTitle.text = @"Suggested Videos";
    _panelTitle.font = TBFont(17);
    _panelTitle.textColor = [UIColor whiteColor];
    _panelTitle.backgroundColor = [TBStyle panel];
    [TBStyle styleShadowLabel:_panelTitle];
    [_panel addSubview:_panelTitle];
    _related = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _related.rowHeight = [TBRelatedCell height];
    _related.dataSource = self;
    _related.delegate = self;
    _related.backgroundColor = [TBStyle panel];
    _related.separatorStyle = UITableViewCellSeparatorStyleNone;
    [_related registerClass:[TBRelatedCell class] forCellReuseIdentifier:@"r"];
    [_panel addSubview:_related];
    [v addSubview:_panel];
    /* D52: a swipe across the area under the tab bar changes the tab */
    for (NSNumber *d in @[@(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)]) {
        UISwipeGestureRecognizer *g = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
        g.direction = d.unsignedIntegerValue;
        g.delegate = self;
        [v addGestureRecognizer:g];
    }
    self.view = v;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if (![g isKindOfClass:[UISwipeGestureRecognizer class]]) return YES;
    CGPoint p = [t locationInView:self.view];
    /* under the tab bar, left of the landscape related column, not in the left 24 pt (swipe back, D49) */
    return !_full && p.y >= CGRectGetMaxY(_tabBar.frame) && p.x >= 24 && p.x < CGRectGetMaxX(_tabBar.frame);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return [a isKindOfClass:[UISwipeGestureRecognizer class]];   /* the comment and description scrolls keep working */
}

- (void)swiped:(UISwipeGestureRecognizer *)g {
    [self swipeTab:g.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1];
}

- (NSString *)swipeTab:(int)dir {
    NSInteger i = _segments.selected + dir;
    if (i >= 0 && i < (NSInteger)_segments.titles.count) {
        _segments.selected = i;
        [self tabChanged:i];
    }
    return _segments.titles[(NSUInteger)_segments.selected];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    g_current = self;
    _viewReady = YES;
    [self setTabsForOrientation];
    if (_info) [self startPlayback];
    if (_next) [self showNext];
    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(savePosition) userInfo:nil repeats:YES];
}

- (BOOL)portrait { return self.view.bounds.size.width < self.view.bounds.size.height; }

- (void)setTabsForOrientation {
    NSArray *want = [self portrait] ? @[@"About", @"Suggested", @"Comments"] : @[@"About", @"Comments"];
    if ([_segments.titles isEqualToArray:want]) return;
    NSString *cur = _segments.titles.count ? _segments.titles[(NSUInteger)_segments.selected] : @"About";
    _segments.titles = want;
    NSUInteger i = [want indexOfObject:cur];
    _segments.selected = i == NSNotFound ? 0 : (NSInteger)i;
    [self tabChanged:_segments.selected];
}

- (void)tabChanged:(NSInteger)i {
    NSString *t = _segments.titles[(NSUInteger)i];
    _tab = [t isEqualToString:@"Comments"] ? 1 : [t isEqualToString:@"Suggested"] ? 2 : 0;
    if (_tab == 1 && !_comments && _next.commentsToken) {
        _comments = [[TBCommentsController alloc] initWithToken:_next.commentsToken title:_next.commentCount];
        [self addChildViewController:_comments];
        [self.view addSubview:_comments.view];
        [_comments didMoveToParentViewController:self];
    }
    [self.view setNeedsLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    g_current = self;
    if (_stopped && _info && !_full) { _stopped = NO; _t0 = tb_now_ms(); [self startPlayback]; }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    /* Only when ANOTHER watch page was pushed. Presenting the full screen player also calls viewWillDisappear, and
     * then the top controller is this page itself: stopping here made full screen black and silent (owner bug
     * 2026-11-11). */
    UIViewController *top = self.navigationController.topViewController;
    if (!self.isMovingFromParentViewController && !_full && top != self && [top isKindOfClass:[TBWatchController class]]) {
        [self savePosition];
        [_player stop];
        _stopped = YES;
    }
    if (self.isMovingFromParentViewController) {
        [self savePosition];
        [_saveTimer invalidate];
        [_player stop];
        if (_full) { [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone]; _full = NO; }
    }
}

- (void)backSwipeWillPop {
    [self savePosition];
    [_player stop];   /* viewWillDisappear stops it again at the pop: then a no-op */
}

- (void)dealloc {
    [_saveTimer invalidate];
    [TBImageLoader cancel:_avatarToken];
}

- (void)savePosition {
    double t = _player.currentTime;
    if (t > 1) [TBStore savePosition:t video:_videoId];
}

/* ---------- data ---------- */

- (void)gotPlayer:(TBPlayerInfo *)info {
    _info = info;
    if (!_title.length && info.title) { _title = info.title; self.title = info.title; _titleLabel.text = info.title; }
    [TBStore addHistory:_videoId title:info.title ?: _title channel:info.author length:nil];
    if ([info.status isEqualToString:@"OK"]) [TBAccount reportWatch:_videoId];
    if (_viewReady) [self startPlayback];
}

- (void)startPlayback {
    double resume = [TBStore positionOf:_videoId];
    /* resume only from the middle: not from the first or last 10 s */
    if (resume < 10 || (_info.lengthSeconds && resume > _info.lengthSeconds - 10)) resume = 0;
    [_player playVideo:_videoId info:_info requestedAt:_t0 startAt:resume];
}

- (void)gotNext:(TBNextInfo *)n {
    _next = n;
    if (_viewReady) [self showNext];
}

- (void)showNext {
    TBNextInfo *n = _next;
    if (n.title.length) _titleLabel.text = n.title;
    /* a live or premiere date already has its verb ("Started streaming 3 hours ago"): no "Uploaded" before it */
    BOOL ownVerb = [n.date hasPrefix:@"Started"] || [n.date hasPrefix:@"Streamed"] || [n.date hasPrefix:@"Premiere"] || [n.date hasPrefix:@"Scheduled"];
    _dateLabel.text = !n.date.length ? nil : ownVerb ? n.date : [NSString stringWithFormat:@"Uploaded %@", n.date];
    NSMutableArray *vl = [NSMutableArray array];
    if (n.views.length) [vl addObject:n.views];
    if (n.likes.length) [vl addObject:[NSString stringWithFormat:@"%@ likes", n.likes]];
    _viewsLabel.text = [vl componentsJoinedByString:@"  •  "];
    _channelLabel.text = n.channel;
    _subsLabel.text = n.subscribers.length ? [NSString stringWithFormat:@"%@ subscribers", n.subscribers] : nil;
    _subscribed = n.subscribed;
    [self showSubscribed];
    _chaptersB.hidden = n.chapters.count == 0;
    /* link detection off the main thread (114 ms main stall MEASURED in [TBLinks linksIn:], stall sampler) */
    _desc.text = n.descriptionText;
    _descLinks = nil;
    NSString *text = n.descriptionText ?: @"";
    UIFont *font = TBFont(14);
    UIColor *color = [TBStyle text];
    __weak TBWatchController *ws = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *links = [TBLinks linksIn:text];
        NSAttributedString *styled = [TBLinks styledText:text font:font color:color links:links];
        dispatch_async(dispatch_get_main_queue(), ^{
            TBWatchController *w = ws;
            if (!w || w->_next != n) return;
            w->_descLinks = links;
            w->_desc.attributedText = styled;
        });
    });
    [TBImageLoader cancel:_avatarToken];
    __weak UIImageView *av = _avatar;
    _avatarToken = [TBImageLoader load:n.channelThumb pixelSize:CGSizeMake(50, 50) done:^(UIImage *img) { av.image = img; }];
    [_related reloadData];
    [self.view setNeedsLayout];
}

/* §8.4: subscribed = green check + grey text; not subscribed = blue plus + "Subscribe" */
- (void)showSubscribed {
    BOOL on = _subscribed == 1;
    [_subB setTitle:on ? @"Subscribed" : @"Subscribe" forState:UIControlStateNormal];
    [_subB setImage:[TBStyle icon:on ? @"check" : @"plus" size:24 color:[UIColor whiteColor]] forState:UIControlStateNormal];
    [_subB setTitleColor:on ? [TBStyle secondary] : [TBStyle buttonText] forState:UIControlStateNormal];
    _subB.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
}

/* ---------- layout (§8.1 landscape, §8.5 portrait) ---------- */

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (_full) return; /* the player lives in TBFullController */
    [self setTabsForOrientation];
    CGRect b = self.view.bounds;
    BOOL portrait = [self portrait];
    if (portrait != _relatedPortrait) { _relatedPortrait = portrait; [_related reloadData]; } /* row style follows the place */
    CGFloat pw = portrait ? b.size.width : b.size.width - 256, ph = floor(pw * 9 / 16);
    _player.frame = CGRectMake(0, 0, pw, ph);
    _tabBar.frame = CGRectMake(0, ph, pw, 44);
    CGFloat sw = portrait ? 450 : 298;
    _segments.frame = CGRectMake(floor((pw - sw) / 2), 7, sw, 30);
    CGRect area = CGRectMake(0, ph + 44, pw, b.size.height - ph - 44);
    if (portrait) {
        _panel.frame = area;
        _panel.hidden = _tab != 2;
        _panelTitle.hidden = YES;
        _related.frame = CGRectMake(0, 10, area.size.width, area.size.height - 10);
        _panel.backgroundColor = _related.backgroundColor = [TBStyle contentBackground];
    } else {
        _panel.frame = CGRectMake(pw, 0, 256, b.size.height);
        _panel.hidden = NO;
        _panelTitle.hidden = NO;
        _panelTitle.frame = CGRectMake(12, 8, 230, 24);
        _related.frame = CGRectMake(0, 40, 256, b.size.height - 40);
        _panel.backgroundColor = _related.backgroundColor = [TBStyle panel];
    }
    _pane.frame = area;
    _pane.hidden = _tab != 0;
    _comments.view.frame = area;
    _comments.view.hidden = _tab != 1;
    /* no comments token (a live stream, or comments turned off): a text, not an empty area */
    BOOL none = _tab == 1 && !_comments && _next;
    if (none && !_noComments) {
        _noComments = [UILabel new];
        _noComments.font = TBFont(15);
        _noComments.textColor = [TBStyle secondary];
        _noComments.backgroundColor = [TBStyle contentBackground];
        _noComments.textAlignment = NSTextAlignmentCenter;
        _noComments.numberOfLines = 2;
        [self.view addSubview:_noComments];
    }
    _noComments.text = _info.live ? @"Live chat is not shown in PadTube." : @"Comments are turned off for this video.";
    _noComments.frame = CGRectMake(area.origin.x, area.origin.y, area.size.width, 80);
    _noComments.hidden = !none;
    [self layoutPane:area.size];
}

- (void)layoutPane:(CGSize)s {
    /* §8.4: left column title/date/buttons/views/description; 1 px rule; right column channel */
    CGFloat right = s.width >= 700 ? 256 : 240, lw = s.width - right, x = 20, tw = lw - 40, y = 19;
    _titleLabel.frame = CGRectMake(x, y, tw, 50);
    [_titleLabel sizeToFit];
    _titleLabel.frame = CGRectMake(x, y, tw, MIN(_titleLabel.frame.size.height, 50));
    y = CGRectGetMaxY(_titleLabel.frame) + 2;
    _dateLabel.frame = CGRectMake(x, y, tw, 20); y += 28;
    CGFloat bx = x;
    _likeB.frame = CGRectMake(bx, y, 36, 28); bx += 52;
    _dislikeB.frame = CGRectMake(bx, y, 36, 28); bx += 52;
    for (UIButton *bt in @[_saveB, _chaptersB]) {
        if (bt.hidden) continue;
        CGFloat bw = [[bt titleForState:UIControlStateNormal] sizeWithFont:bt.titleLabel.font].width + (bt.currentImage ? 40 : 24);
        if (bx + bw > x + tw) break;
        bt.frame = CGRectMake(bx, y, bw, 28);
        bx += bw + 10;
    }
    y += 38;
    _viewsLabel.frame = CGRectMake(x, y, tw, 20); y += 26;
    _desc.frame = CGRectMake(x - 8, y, tw + 16, MAX(0, s.height - y - 4));
    _rule.frame = CGRectMake(lw, 12, 1, s.height - 24);
    CGFloat rx = lw + 18;
    _avatar.frame = CGRectMake(rx, 19, 50, 50);
    _channelLabel.frame = CGRectMake(rx + 60, 22, right - 90, 22);
    _subsLabel.frame = CGRectMake(rx + 60, 46, right - 90, 18);
    _subB.frame = CGRectMake(rx, 19 + 50 + 20, MIN(170, right - 36), 38);
}

- (void)toggleFullscreen {
    if (!_full) {
        _full = YES;
        _player.fullscreen = YES;
        _orientationBeforeFull = [UIApplication sharedApplication].statusBarOrientation;
        _fc = [TBFullController new];
        (void)_fc.view; /* load the view before the player moves into it */
        [_fc.view addSubview:_player];
        _fc.content = _player;
        _player.frame = _fc.view.bounds;
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
        [self presentViewController:_fc animated:NO completion:nil];
        return;
    }
    _full = NO;
    _player.fullscreen = NO;
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
    UIInterfaceOrientation before = _orientationBeforeFull;
    [self dismissViewControllerAnimated:NO completion:^{
        [self.view insertSubview:self->_player atIndex:0];
        self->_fc = nil;
        /* back to the orientation from before full screen: first the device's own orientation; if the iPad lies
         * flat it has none, so set the old one (UIDevice -setOrientation:, private, jailbroken personal app). */
        [UIViewController attemptRotationToDeviceOrientation];
        if ([UIApplication sharedApplication].statusBarOrientation != before) {
            SEL sel = NSSelectorFromString(@"setOrientation:");
            if ([[UIDevice currentDevice] respondsToSelector:sel])
                ((void (*)(id, SEL, NSInteger))objc_msgSend)([UIDevice currentDevice], sel, (NSInteger)before);
            [UIViewController attemptRotationToDeviceOrientation];
        }
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

- (void)playerViewToggleFullscreen:(TBPlayerView *)v { [self toggleFullscreen]; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }

/* ---------- actions ---------- */

- (void)descTapped:(UITapGestureRecognizer *)g {
    NSURL *u = [TBLinks linkInTextView:_desc atPoint:[g locationInView:_desc] links:_descLinks];
    if (u) [TBLinks openURL:u from:self];
}

- (void)openChannel {
    if (_next.channelId) [TBRouter openChannel:_next.channelId title:_next.channel from:self];
}

- (BOOL)needSignIn:(NSString *)what {
    if ([TBAccount signedIn]) return NO;
    [[[UIAlertView alloc] initWithTitle:@"Sign in" message:[NSString stringWithFormat:@"Sign in (Account in the guide) to %@.", what]
                               delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    return YES;
}

- (void)likeTapped {
    if ([self needSignIn:@"like videos"]) return;
    [TBAccount like:_videoId action:1 done:^(BOOL ok) {
        if (ok) [self->_likeB setImage:[TBStyle icon:@"liked" size:16 color:TBHex(0x5474CF)] forState:UIControlStateNormal];
    }];
}

- (void)dislikeTapped {
    if ([self needSignIn:@"rate videos"]) return;
    [TBAccount like:_videoId action:-1 done:^(BOOL ok) {
        if (ok) [self->_dislikeB setImage:[TBStyle icon:@"dislike" size:16 color:TBHex(0x5474CF)] forState:UIControlStateNormal];
    }];
}

- (void)subTapped {
    if ([self needSignIn:@"subscribe"] || !_next.channelId) return;
    BOOL on = _subscribed != 1;
    [TBAccount subscribe:_next.channelId on:on done:^(BOOL ok) {
        if (ok) self->_subscribed = on;
        [self showSubscribed];
    }];
}

- (void)saveTapped {
    if ([self needSignIn:@"save videos"]) return;
    [TBAccount addToWatchLater:_videoId done:^(BOOL ok) {
        [self->_saveB setTitle:ok ? @"Saved" : @"Save failed" forState:UIControlStateNormal];
        [self.view setNeedsLayout];
    }];
}

- (void)commentsTapped { [self selectTabTitled:@"Comments"]; } /* self-test entry point */

- (void)selectTabTitled:(NSString *)title { /* self-test entry point: About / Suggested / Comments */
    NSUInteger i = [_segments.titles indexOfObject:title];
    if (i == NSNotFound) return;
    _segments.selected = (NSInteger)i;
    [self tabChanged:(NSInteger)i];
}

- (void)chaptersTapped {
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:@"Chapters" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    s.tag = 1;
    for (NSArray *c in _next.chapters) {
        int t = [c[0] intValue];
        [s addButtonWithTitle:[NSString stringWithFormat:@"%d:%02d  %@", t / 60, t % 60, c[1]]];
    }
    [s showFromRect:_chaptersB.frame inView:_pane animated:YES];
}

- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (i < 0) return;
    if (s.tag == 1) [_player seekTo:[_next.chapters[(NSUInteger)i][0] doubleValue]];
}

/* ---------- related ---------- */

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_next.related.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    TBRelatedCell *c = [tv dequeueReusableCellWithIdentifier:@"r" forIndexPath:ip];
    c.onContent = [self portrait];
    [c showItem:_next.related[(NSUInteger)ip.row]];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [TBRouter openItem:_next.related[(NSUInteger)ip.row] from:self];
}
@end
