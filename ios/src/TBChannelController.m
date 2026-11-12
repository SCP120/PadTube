#import "TBChannelController.h"
#import "TBAccount.h"
#import "TBCore.h"
#import "TBImageLoader.h"
#import "TBSegments.h"
#import "TBStyle.h"

/* MWEB channel tab params (YouTube.js Channel.ts; checked by tests/e2e test_channel_tabs, 2026-11-12) */
static NSString *const kTabs[3] = {@"EgZ2aWRlb3PyBgQKAjoA", @"EgdzdHJlYW1z8gYECgJ6AA%3D%3D", @"EglwbGF5bGlzdHPyBgQKAkIA"};

/* A view that lays out its children in a block: the table header sizes itself, no relayout of the table. */
@interface TBBlockView : UIView
@property (nonatomic, copy) void (^layout)(CGRect bounds);
@end
@implementation TBBlockView
- (void)layoutSubviews { [super layoutSubviews]; if (self.layout) self.layout(self.bounds); }
@end

@implementation TBChannelController {
    NSString *_channelId;
    NSInteger _tabIndex;
    TBBlockView *_head;
    UIImageView *_bar, *_avatar, *_subBar;
    UILabel *_name, *_subs;
    UIButton *_sub;
    TBSegments *_segments;
    int _subscribed;
    id _avatarToken;
}

- (id)initWithChannel:(NSString *)channelId title:(NSString *)title {
    __weak TBChannelController *w;
    self = [super initWithTitle:title loader:nil];
    w = self;
    _channelId = [channelId copy];
    _subscribed = -1;
    self.cardStyle = TBCardGrid;
    self.loader = ^(NSString *c, void (^done)(TBPage *)) {
        TBChannelController *s = w;
        [TBCore channel:s->_channelId tab:kTabs[s->_tabIndex] continuation:c done:done];
    };
    self.pageLoaded = ^(TBPage *p) { [w showHeader:p]; };
    return self;
}

- (void)dealloc { [TBImageLoader cancel:_avatarToken]; }

- (void)viewDidLoad {
    _head = [[TBBlockView alloc] initWithFrame:CGRectMake(0, 0, 768, 156)];
    _head.backgroundColor = [TBStyle contentBackground];
    _bar = [[UIImageView alloc] initWithImage:[TBStyle cardImage]];
    _bar.userInteractionEnabled = YES;
    _avatar = [UIImageView new];
    _avatar.backgroundColor = [TBStyle placeholder];
    _name = [UILabel new];
    _name.font = TBFont(18);
    _name.textColor = [TBStyle text];
    _name.text = self.title;
    _subs = [UILabel new];
    _subs.font = TBFont(13);
    _subs.textColor = [TBStyle secondary];
    for (UILabel *l in @[_name, _subs]) l.backgroundColor = [TBStyle cardFill];
    _sub = [UIButton buttonWithType:UIButtonTypeCustom];
    [_sub setBackgroundImage:[TBStyle lightButtonImage:NO] forState:UIControlStateNormal];
    [_sub setBackgroundImage:[TBStyle lightButtonImage:YES] forState:UIControlStateHighlighted];
    _sub.titleLabel.font = TBFont(16);
    _sub.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
    [_sub addTarget:self action:@selector(subTapped) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *v in @[_avatar, _name, _subs, _sub]) [_bar addSubview:v];
    _subBar = [[UIImageView alloc] initWithImage:[TBStyle tabBarImage]];
    _subBar.userInteractionEnabled = YES;
    _segments = [TBSegments new];
    _segments.titles = @[@"Videos", @"Live", @"Playlists"];
    __weak TBChannelController *w = self;
    _segments.changed = ^(NSInteger i) { TBChannelController *s = w; s->_tabIndex = i; [s reload]; };
    [_subBar addSubview:_segments];
    [_head addSubview:_bar];
    [_head addSubview:_subBar];
    [self showSubscribed];
    __weak TBChannelController *ws = self;
    _head.layout = ^(CGRect b) { [ws layoutHead:b]; };
    [super viewDidLoad];
    self.tableView.tableHeaderView = _head;
}

- (void)layoutHead:(CGRect)b {
    CGFloat w = b.size.width, cw = MIN(748, w - 20), cx = floor((w - cw) / 2);
    _bar.frame = CGRectMake(cx, 0, cw, 90);
    _avatar.frame = CGRectMake(20, 22, 44, 44);
    _name.frame = CGRectMake(78, 22, cw - 78 - 200, 24);
    _subs.frame = CGRectMake(78, 48, cw - 78 - 200, 18);
    _sub.frame = CGRectMake(cw - 20 - 170, 25, 170, 38);
    _subBar.frame = CGRectMake(0, 102, w, 44);
    _segments.frame = CGRectMake(floor((w - 360) / 2), 7, 360, 30);
}

- (void)showHeader:(TBPage *)p {
    if (p.title.length) { _name.text = p.title; self.title = p.title; }
    if (p.subtitle.length) _subs.text = p.subtitle;
    if (p.subscribed >= 0) { _subscribed = p.subscribed; [self showSubscribed]; }
    if (p.avatar.length && !_avatar.image) {
        __weak UIImageView *av = _avatar;
        _avatarToken = [TBImageLoader load:p.avatar pixelSize:CGSizeMake(44, 44) done:^(UIImage *img) { av.image = img; }];
    }
}

- (void)showSubscribed {
    BOOL on = _subscribed == 1;
    [_sub setTitle:on ? @"Subscribed" : @"Subscribe" forState:UIControlStateNormal];
    [_sub setImage:[TBStyle icon:on ? @"check" : @"plus" size:24 color:[UIColor whiteColor]] forState:UIControlStateNormal];
    [_sub setTitleColor:on ? [TBStyle secondary] : [TBStyle buttonText] forState:UIControlStateNormal];
}

- (void)subTapped {
    if (![TBAccount signedIn]) {
        [[[UIAlertView alloc] initWithTitle:@"Sign in" message:@"Sign in (Account in the guide) to subscribe." delegate:nil
                          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    BOOL on = _subscribed != 1;
    [TBAccount subscribe:_channelId on:on done:^(BOOL ok) {
        if (ok) self->_subscribed = on;
        [self showSubscribed];
    }];
}
@end
