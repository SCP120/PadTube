#import "TBShell.h"
#import "TBAccount.h"
#import "TBBackSwipe.h"
#import "TBCore.h"
#import "TBItemCell.h"
#import "TBAccountController.h"
#import "TBListController.h"
#import "TBSearchController.h"
#import "TBShortsController.h"
#import "TBStore.h"
#import "TBStyle.h"

/* Guide rows: (section, title, icon). The index is the self-test "tab N" number. */
static NSArray *rows(void) {
    return @[@[@"Subscriptions", @"Home Feed", @"home"], @[@"Subscriptions", @"Subscriptions", @"subs"],
             @[@"Library", @"Search", @"search"], @[@"Library", @"History", @"history"], @[@"Library", @"Watch Later", @"later"],
             @[@"Library", @"Liked Videos", @"like"], @[@"Library", @"Playlists", @"playlist"], @[@"Library", @"YouTube History", @"history"],
             @[@"From YouTube", @"Shorts", @"shorts"], @[@"From YouTube", @"Live", @"star"],
             @[@"Account", @"Account", @"account"]];
}

@interface TBNav : UINavigationController
@end
@implementation TBNav
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotate { return YES; }
@end

@interface TBShell () <UITableViewDataSource, UITableViewDelegate, UINavigationControllerDelegate, UITextFieldDelegate>
@end

static __weak TBShell *g_shell;

@implementation TBShell {
    UITableView *_guide;
    UIImageView *_guideHeader;
    UIView *_content, *_closer;
    UIImageView *_header;
    UIButton *_left;
    UILabel *_title;
    UITableView *_sugg;
    NSArray *_suggestions, *_sections;
    NSMutableDictionary *_roots;
    NSTimer *_debounce;
    CGSize _swipeSize;                  /* shell size when a swipe back began */
    UIButton *_extra;                   /* the top screen's header button */
    __weak UIViewController *_extraOwner;
}

+ (TBShell *)shared { return g_shell; }
- (CGRect)titleFrame { return _title.frame; }
+ (NSArray *)guideTitles { NSMutableArray *a = [NSMutableArray array]; for (NSArray *r in rows()) [a addObject:r[1]]; return a; }

- (id)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    g_shell = self;
    _roots = [NSMutableDictionary dictionary];
    NSMutableArray *sec = [NSMutableArray array];
    for (NSArray *r in rows()) if (![sec containsObject:r[0]]) [sec addObject:r[0]];
    _sections = sec;
    _guideIndex = -1;
    return self;
}

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    v.backgroundColor = TBHex(0x383838);
    /* guide */
    _guideHeader = [[UIImageView alloc] initWithImage:[TBStyle guideHeaderImage]];
    UILabel *mark = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 256, 44)];
    mark.text = @"PadTube"; /* our wordmark (§6): no YouTube logo */
    mark.font = TBFontBold(20);
    mark.textColor = [UIColor whiteColor];
    mark.backgroundColor = [UIColor clearColor];
    mark.textAlignment = NSTextAlignmentCenter;
    [TBStyle styleShadowLabel:mark];
    UIView *red = [[UIView alloc] initWithFrame:CGRectMake(75, 14, 4, 16)];
    red.backgroundColor = TBHex(0xCD1A18);
    [_guideHeader addSubview:red];
    [_guideHeader addSubview:mark];
    [v addSubview:_guideHeader];
    _guide = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _guide.dataSource = self;
    _guide.delegate = self;
    _guide.backgroundColor = TBHex(0x383838);
    _guide.separatorStyle = UITableViewCellSeparatorStyleNone;
    _guide.rowHeight = 49; /* §6: 47 + dark line + light line */
    [v addSubview:_guide];
    /* content: header + navigation stack */
    _content = [UIView new];
    _content.backgroundColor = [TBStyle contentBackground];
    _content.clipsToBounds = YES;
    _header = [[UIImageView alloc] initWithImage:[TBStyle headerImage]];
    _header.userInteractionEnabled = YES;
    _left = [UIButton buttonWithType:UIButtonTypeCustom];
    [_left addTarget:self action:@selector(leftTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_left];
    _title = [UILabel new];
    _title.font = TBFont(18);
    _title.textColor = TBHex(0xD6D6D6);
    _title.backgroundColor = [UIColor clearColor];
    [TBStyle styleShadowLabel:_title];
    [_header addSubview:_title];
    _searchField = [UITextField new];
    _searchField.background = [TBStyle searchFieldImage];
    _searchField.textColor = [UIColor whiteColor];
    _searchField.font = TBFont(15);
    _searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search" attributes:@{NSForegroundColorAttributeName: TBHex(0xAAAAAA)}];
    _searchField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.keyboardAppearance = UIKeyboardAppearanceAlert;
    _searchField.delegate = self;
    UIImageView *lens = [[UIImageView alloc] initWithImage:[TBStyle icon:@"search" size:13 color:TBHex(0xBCBCBC)]];
    lens.contentMode = UIViewContentModeCenter;
    lens.frame = CGRectMake(0, 0, 32, 28);
    _searchField.leftView = lens;
    _searchField.leftViewMode = UITextFieldViewModeAlways;
    [_searchField addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    [_header addSubview:_searchField];
    [_content addSubview:_header];
    _nav = [[TBNav alloc] init];
    _nav.navigationBarHidden = YES;
    _nav.delegate = self;
    [self addChildViewController:_nav];
    [_content addSubview:_nav.view];
    [_nav didMoveToParentViewController:self];
    [self setUpBackSwipe];
    _sugg = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _sugg.dataSource = self;
    _sugg.delegate = self;
    _sugg.rowHeight = 36;
    _sugg.hidden = YES;
    _sugg.separatorColor = [TBStyle popupRule];
    _sugg.backgroundColor = [TBStyle popupFill];
    [_content addSubview:_sugg];
    _closer = [UIView new];
    _closer.backgroundColor = [UIColor clearColor];
    _closer.hidden = YES;
    [_closer addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleGuide)]];
    [_content addSubview:_closer];
    [v addSubview:_content];
    self.view = v;
    [self selectGuideRow:0];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotate { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }

- (BOOL)topWantsFullWidth {
    UIViewController *t = _nav.topViewController;
    return [t respondsToSelector:@selector(wantsFullWidth)] && [(id<TBFullWidth>)t wantsFullWidth];
}

- (void)setUpBackSwipe {
    _backSwipe = [[TBBackSwipe alloc] initWithNav:_nav host:_content];
    __weak TBShell *w = self;
    _backSwipe.underFrame = ^CGRect(UIViewController *prev, BOOL *clearHost) {
        TBShell *s = w;
        CGRect b = s.view.bounds;
        s->_swipeSize = b.size;
        BOOL prevFull = [prev respondsToSelector:@selector(wantsFullWidth)] && [(id<TBFullWidth>)prev wantsFullWidth];
        /* landscape, full-width screen over a list: the list goes where it will be after the pop, the guide shows
         * through on the left (D49) */
        if (b.size.width > b.size.height && [s topWantsFullWidth] && !prevFull) {
            *clearHost = YES;
            return CGRectMake(256, 44, b.size.width - 256, b.size.height - 44);
        }
        return s->_nav.view.frame;
    };
    _backSwipe.progress = ^(CGFloat p) { TBShell *s = w; if (s) s->_title.alpha = 1 - p; };
    _backSwipe.willPop = ^(UIViewController *top) {
        if ([top respondsToSelector:@selector(backSwipeWillPop)]) [(id<TBFullWidth>)top backSwipeWillPop];
    };
    _backSwipe.finished = ^(BOOL popped) {
        TBShell *s = w;
        [s.view setNeedsLayout];
        [s.view layoutIfNeeded];
    };
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    if (_backSwipe.active) { /* the top screen has a transform: no frames now; a turn of the iPad ends the swipe */
        if (CGSizeEqualToSize(b.size, _swipeSize)) return;
        [_backSwipe abort];
    }
    BOOL land = b.size.width > b.size.height, full = [self topWantsFullWidth];
    _guideHeader.frame = CGRectMake(0, 0, 256, 44);
    _guide.frame = CGRectMake(0, 44, 256, b.size.height - 44);
    CGFloat cx;
    if (land && !full) { cx = 256; _guideOpen = NO; }
    else cx = _guideOpen ? 256 : 0;
    CGFloat cw = land && !full ? b.size.width - 256 : b.size.width;
    _content.frame = CGRectMake(cx, 0, cw, b.size.height);
    _closer.frame = _content.bounds;
    _closer.hidden = !_guideOpen;
    _header.frame = CGRectMake(0, 0, cw, 44);
    _nav.view.frame = CGRectMake(0, 44, cw, b.size.height - 44);
    /* §5: menu or back at the left (11 pt in), search pill 212x28 right, 36 pt from the right edge */
    _left.frame = CGRectMake(0, 0, 50, 44);
    _searchField.frame = CGRectMake(cw - 212 - 36, 8, 212, 28);
    _title.frame = CGRectMake(56, 0, cw - 56 - 212 - 50, 44);
    [self updateHeader];
    if (!_sugg.hidden) [self layoutSuggestions];
}

- (void)updateHeader {
    BOOL back = _nav.viewControllers.count > 1;
    BOOL land = self.view.bounds.size.width > self.view.bounds.size.height;
    [_left setImage:back ? [TBStyle icon:@"back" size:24 color:TBHex(0xAFAFAF)] : [TBStyle icon:@"menu" size:25 color:TBHex(0x363636)] forState:UIControlStateNormal];
    _left.hidden = !back && land && ![self topWantsFullWidth]; /* the guide is open: no menu button */
    _title.text = _nav.topViewController.title;
    UIViewController *top = _nav.topViewController;
    if (_extraOwner != top) {
        [_extra removeFromSuperview];
        _extra = [top respondsToSelector:@selector(headerButton)] ? [(id<TBFullWidth>)top headerButton] : nil;
        _extraOwner = top;
        if (_extra) [_header addSubview:_extra];
    }
    _extra.frame = CGRectMake(CGRectGetMinX(_searchField.frame) - 8 - 44, 0, 44, 44);
    /* owner 2026-11-12: a long title must end with "..." before the search field (or the header button), not run under it */
    CGFloat tx = _left.hidden ? 14 : 56, right = _extra ? CGRectGetMinX(_extra.frame) : CGRectGetMinX(_searchField.frame);
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _title.frame = CGRectMake(tx, 0, MAX(0, right - 12 - tx), 44);
}

- (void)navigationController:(UINavigationController *)n didShowViewController:(UIViewController *)vc animated:(BOOL)a {
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)navigationController:(UINavigationController *)n willShowViewController:(UIViewController *)vc animated:(BOOL)a {
    _title.text = vc.title;
}

- (void)leftTapped {
    if (_nav.viewControllers.count > 1) { [_nav popViewControllerAnimated:YES]; return; }
    [self toggleGuide];
}

- (void)toggleGuide {
    _guideOpen = !_guideOpen;
    [UIView animateWithDuration:0.25 animations:^{ [self viewWillLayoutSubviews]; }];
}

/* ---------- guide ---------- */

- (NSArray *)rowsInSection:(NSInteger)s {
    NSMutableArray *a = [NSMutableArray array];
    NSArray *all = rows();
    for (NSUInteger i = 0; i < all.count; i++) if ([all[i][0] isEqualToString:_sections[(NSUInteger)s]]) [a addObject:@(i)];
    return a;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return tv == _sugg ? 1 : (NSInteger)_sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return tv == _sugg ? (NSInteger)_suggestions.count : (NSInteger)[self rowsInSection:s].count;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return tv == _sugg ? 0 : 22; }

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    if (tv == _sugg) return nil;
    UIImageView *h = [[UIImageView alloc] initWithImage:[TBStyle sectionImage]];
    h.frame = CGRectMake(0, 0, 256, 22);
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 240, 22)];
    l.text = _sections[(NSUInteger)s];
    l.font = TBFont(14);
    l.textColor = TBHex(0xAFAFAF);
    l.backgroundColor = [UIColor clearColor];
    [TBStyle styleShadowLabel:l];
    [h addSubview:l];
    return h;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (tv == _sugg) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"s"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"s"];
        c.textLabel.text = _suggestions[(NSUInteger)ip.row];
        c.textLabel.font = TBFont(15);
        c.textLabel.textColor = [TBStyle dark] ? [TBStyle text] : TBHex(0x474747);
        c.backgroundColor = [TBStyle popupFill];
        return c;
    }
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"g"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"g"];
        UIView *dark = [[UIView alloc] initWithFrame:CGRectMake(0, 47, 256, 1)], *light = [[UIView alloc] initWithFrame:CGRectMake(0, 48, 256, 1)];
        dark.backgroundColor = TBHex(0x222222);
        light.backgroundColor = TBHex(0x555555);
        [c.contentView addSubview:dark];
        [c.contentView addSubview:light];
        UIView *sel = [UIView new];
        sel.backgroundColor = TBHex(0x1E1E1E);
        c.selectedBackgroundView = sel;
        c.textLabel.font = TBFont(17);
        c.textLabel.backgroundColor = [UIColor clearColor];
        [TBStyle styleShadowLabel:c.textLabel];
    }
    NSInteger idx = [[self rowsInSection:ip.section][(NSUInteger)ip.row] integerValue];
    NSArray *r = rows()[(NSUInteger)idx];
    BOOL selected = idx == _guideIndex;
    NSString *title = r[1];
    if ([title isEqualToString:@"Account"]) title = [TBAccount signedIn] ? @"Account" : @"Sign In";
    c.textLabel.text = title;
    c.textLabel.textColor = selected ? [UIColor whiteColor] : [TBStyle guideText];
    c.imageView.image = [TBStyle icon:r[2] size:26 color:selected ? [UIColor whiteColor] : TBHex(0xB0B0B0)];
    c.backgroundColor = selected ? TBHex(0x1E1E1E) : [TBStyle guideRow];
    c.contentView.backgroundColor = c.backgroundColor;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    if (tv == _sugg) { [self search:_suggestions[(NSUInteger)ip.row]]; return; }
    [self selectGuideRow:[[self rowsInSection:ip.section][(NSUInteger)ip.row] integerValue]];
}

- (UIViewController *)rootForRow:(NSInteger)i {
    NSString *t = rows()[(NSUInteger)i][1];
    UIViewController *vc = _roots[t];
    if (vc) return vc;
    TBListController *l = nil;
    if ([t isEqualToString:@"Home Feed"]) {
        l = [[TBListController alloc] initWithTitle:@"Home" loader:^(NSString *c, void (^done)(TBPage *)) {
            if ([TBAccount signedIn]) { [TBCore tvBrowse:@"FEwhat_to_watch" continuation:c done:done]; return; }
            /* signed out the home feed is empty (research F8): videos related to the last one watched here */
            NSArray *h = [TBStore history];
            if (c || !h.count) { [TBCore search:@"music" continuation:c done:done]; return; }
            [TBCore next:[h[0] ident] done:^(TBNextInfo *n) { TBPage *p = [TBPage new]; p.items = n.related ?: @[]; done(p); }];
        }];
        l.cardStyle = TBCardGrid;
    } else if ([t isEqualToString:@"Subscriptions"]) {
        l = [[TBListController alloc] initWithTitle:t loader:^(NSString *c, void (^done)(TBPage *)) {
            if (![TBAccount signedIn]) { TBPage *p = [TBPage new]; p.items = @[]; done(p); return; }
            [TBCore tvBrowse:@"FEsubscriptions" continuation:c done:done];
        }];
        l.emptyText = @"Sign in (Account in the guide) to see your subscriptions.";
        l.cardStyle = TBCardGrid;
    } else if ([t isEqualToString:@"Search"]) {
        vc = [TBSearchController new];
    } else if ([t isEqualToString:@"History"]) {
        l = [[TBListController alloc] initWithTitle:@"History on this iPad" loader:nil];
        l.emptyText = @"Videos you watch appear here.";
        l.canDelete = ^BOOL(TBItem *it) { return YES; };
        l.deleteItem = ^(TBItem *it) { [TBStore removeHistory:it.ident]; };
        l.reloadLocal = ^NSArray *{ return [TBStore history]; };
    } else if ([t isEqualToString:@"Live"]) {
        l = [[TBListController alloc] initWithTitle:@"Live" loader:^(NSString *c, void (^done)(TBPage *)) {
            [TBCore search:@"live" params:@"EgJAAQ==" continuation:c done:done];
        }];
        l.cardStyle = TBCardGrid;
    } else if ([t isEqualToString:@"Account"]) {
        vc = [TBAccountController new];
    } else if ([t isEqualToString:@"Shorts"]) {
        vc = [TBShortsController new];
    } else {
        NSString *bid = [t isEqualToString:@"Watch Later"] ? @"VLWL" : [t isEqualToString:@"Liked Videos"] ? @"VLLL"
                      : [t isEqualToString:@"Playlists"] ? @"FEplaylist_aggregation" : @"FEhistory";
        l = [[TBListController alloc] initWithTitle:t loader:^(NSString *c, void (^done)(TBPage *)) {
            if (![TBAccount signedIn]) { TBPage *p = [TBPage new]; p.items = @[]; done(p); return; }
            [TBCore tvBrowse:bid continuation:c done:done];
        }];
        l.emptyText = [NSString stringWithFormat:@"Sign in (Account in the guide) to see %@.", t];
        if ([bid isEqualToString:@"FEplaylist_aggregation"]) l.cardStyle = TBCardGrid;
        if ([bid hasPrefix:@"VL"]) {
            NSString *pl = [bid substringFromIndex:2];
            l.canDelete = ^BOOL(TBItem *it) { return it.setVideoId.length > 0; };
            l.deleteItem = ^(TBItem *it) { [TBAccount removeFromPlaylist:pl setVideoId:it.setVideoId done:nil]; };
        }
    }
    vc = vc ?: l;
    _roots[t] = vc;
    return vc;
}

- (void)selectGuideRow:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)rows().count) return;
    _guideIndex = i;
    UIViewController *vc = [self rootForRow:i];
    if (_nav.viewControllers.firstObject != vc || _nav.viewControllers.count > 1) [_nav setViewControllers:@[vc] animated:NO];
    if ([vc isKindOfClass:[TBListController class]] && [(TBListController *)vc reloadLocal]) [(TBListController *)vc showItems:[(TBListController *)vc reloadLocal]()];
    [_guide reloadData];
    if (_guideOpen) [self toggleGuide];
    [self.view setNeedsLayout];
}

- (void)refreshAccount {
    [_guide reloadData];
    for (NSString *k in @[@"Home Feed", @"Subscriptions", @"Watch Later", @"Liked Videos", @"Playlists", @"YouTube History"]) {
        TBListController *l = _roots[k];
        if ([l isKindOfClass:[TBListController class]] && l.isViewLoaded) [l reload];
    }
}

/* ---------- search ---------- */

- (void)search:(NSString *)q {
    _sugg.hidden = YES;
    [_searchField resignFirstResponder];
    /* the query is shown in the field and the header title: same iOS 6 emoji filter as titles (D34); a pasted
     * new emoji drew a box (followups.py 2026-11-12) */
    _searchField.text = TBStr(q.UTF8String) ?: @"";
    NSInteger i = (NSInteger)[[TBShell guideTitles] indexOfObject:@"Search"];
    [self selectGuideRow:i];
    [(TBSearchController *)[self rootForRow:i] search:q];   /* YouTube gets the exact text */
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (tf.text.length) [self search:tf.text];
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)tf { [self suggest]; }
- (void)textFieldDidEndEditing:(UITextField *)tf { _sugg.hidden = YES; }

- (void)searchChanged {
    [_debounce invalidate];
    /* 250 ms: one request per typing pause, not per key */
    _debounce = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(suggest) userInfo:nil repeats:NO];
}

- (void)suggest {
    NSString *q = _searchField.text;
    if (!q.length) { _suggestions = [TBStore recentSearches]; [self showSuggestions]; return; }
    [TBCore suggest:q done:^(NSArray *a) {
        if (![q isEqualToString:self->_searchField.text] || !self->_searchField.isFirstResponder) return;
        self->_suggestions = a;
        [self showSuggestions];
    }];
}

- (void)showSuggestions {
    _sugg.hidden = !_suggestions.count || !_searchField.isFirstResponder;
    [self layoutSuggestions];
    [_sugg reloadData];
    [_content bringSubviewToFront:_sugg];
}

- (void)layoutSuggestions {
    CGRect f = _searchField.frame;
    CGFloat w = MAX(f.size.width + 120, 340);
    _sugg.frame = CGRectMake(CGRectGetMaxX(f) - w, 44, w, MIN(36 * (CGFloat)_suggestions.count, 36 * 8));
}
@end
