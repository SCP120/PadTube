#import "TBListController.h"
#import "TBLog.h"
#import "TBCore.h"
#import "TBItemCell.h"
#import "TBStyle.h"
#import "TBWatchController.h"
#import "TBChannelController.h"
#import "TBAccount.h"
#include "tb_http.h"

@implementation TBListController {
    NSString *_continuation;
    BOOL _loading;
    UILabel *_empty;
    UIActivityIndicatorView *_spin;
    NSUInteger _generation;
    int _cols;
    CGFloat _gridWidth;
    NSMutableSet *_seen;     /* keys of the items shown: later pages repeat earlier ones (owner bug 2026-11-12) */
    NSMutableArray *_spareCells; /* grid cells made while idle: a new cell in a scroll cost 30-40 ms (R1) */
}

- (BOOL)grid { return self.cardStyle == TBCardGrid; }
/* owner request 2026-11-12: 3 tiles in portrait, 4 in landscape */
- (int)columns { return UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation) ? 4 : 3; }

- (id)initWithTitle:(NSString *)title loader:(TBPageLoader)loader {
    if (!(self = [super initWithStyle:UITableViewStylePlain])) return nil;
    self.title = title;
    _loader = [loader copy];
    _items = [NSMutableArray array];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = [self grid] ? 200 : [TBItemCell heightForStyle:self.cardStyle];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [TBStyle contentBackground];
    /* §7.1: first card 12 pt under the header */
    self.tableView.contentInset = UIEdgeInsetsMake(12, 0, 0, 0);
    [self.tableView registerClass:[TBItemCell class] forCellReuseIdentifier:@"i"];
    [self.tableView registerClass:[TBGridCell class] forCellReuseIdentifier:@"g"];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spin.color = [TBStyle secondary];
    _spin.hidesWhenStopped = YES;
    _spin.frame = CGRectMake(0, 0, 320, 44);
    _empty = [UILabel new];
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    _empty.font = [UIFont systemFontOfSize:17];
    _empty.hidden = YES;
    [self.tableView addSubview:_empty];
    if (self.loader) {
        UIRefreshControl *rc = [UIRefreshControl new];
        [rc addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
        self.refreshControl = rc;
    }
    _empty.textColor = [TBStyle secondary];
    _empty.backgroundColor = [TBStyle contentBackground];
    _empty.font = TBFont(17);
    if (self.loader && !_items.count) [self reload];
}


- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if ([self grid]) {
        int cols = [self columns];
        CGFloat w = self.tableView.bounds.size.width;
        if (cols != _cols || w != _gridWidth) {
            _cols = cols;
            _gridWidth = w;
            self.tableView.rowHeight = [TBGridCell heightForWidth:w columns:cols];
            [self.tableView reloadData];
        }
    }
    _empty.frame = CGRectMake(20, 80, self.tableView.bounds.size.width - 40, 60);
}

- (void)reload {
    _continuation = nil;
    _generation++;
    _loading = NO;
    [self loadMore:YES];
}

- (void)showItems:(NSArray *)items {
    [_items setArray:items];
    [self.tableView reloadData];
    _empty.text = self.emptyText;
    _empty.hidden = _items.count > 0 || !self.emptyText;
}

/* 3 spare grid cells (a new row mid-scroll needs 2-3 before the reuse queue fills), one per run-loop turn
 * and only while the list does not move, so the making itself never lands in a scroll frame. */
- (void)makeSpareCells {
    if (!_spareCells) _spareCells = [NSMutableArray array];
    if (_spareCells.count >= 3) return;
    __weak TBListController *w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        TBListController *s = w;
        if (!s || ![s grid]) return;
        if (s.tableView.isDragging || s.tableView.isDecelerating) { [s makeSpareCells]; return; }
        [s->_spareCells addObject:[[TBGridCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"g"]];
        [s makeSpareCells];
    });
}

- (void)loadMore:(BOOL)first {
    if (_loading || !self.loader) return;
    if (!first && !_continuation) return;
    _loading = YES;
    NSUInteger gen = _generation;
    double t0 = tb_now_ms();
    if (first && !self.refreshControl.refreshing) { self.tableView.tableFooterView = _spin; [_spin startAnimating]; }
    __weak TBListController *w = self;
    self.loader(first ? nil : _continuation, ^(TBPage *p) {
        TBListController *s = w;
        if (!s || gen != s->_generation) return;
        s->_loading = NO;
        [s->_spin stopAnimating];
        s.tableView.tableFooterView = nil;
        [s.refreshControl endRefreshing];
        if (first) { [s->_items removeAllObjects]; s->_seen = [NSMutableSet set]; }
        NSUInteger before = s->_items.count;
        for (TBItem *it in p.items) {
            BOOL dup = NO;
            for (NSString *k in it.keys) if ([s->_seen containsObject:k]) dup = YES;
            if (dup) continue;
            [s->_seen addObjectsFromArray:it.keys ?: @[]];
            [s->_items addObject:it];
        }
        s->_continuation = p.items.count ? p.continuation : nil;
        if (first || before == 0) [s.tableView reloadData];
        else if ([s grid]) {
            /* a new page: refill the last, partial row and add rows; a full reload here cost 35-43 ms frames */
            NSUInteger c = (NSUInteger)(s->_cols ?: [s columns]), oldRows = (before + c - 1) / c, newRows = (s->_items.count + c - 1) / c;
            NSMutableArray *ins = [NSMutableArray array];
            for (NSUInteger r = oldRows; r < newRows; r++) [ins addObject:[NSIndexPath indexPathForRow:(NSInteger)r inSection:0]];
            [s.tableView beginUpdates];
            if (before % c) [s.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)(oldRows - 1) inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            if (ins.count) [s.tableView insertRowsAtIndexPaths:ins withRowAnimation:UITableViewRowAnimationNone];
            [s.tableView endUpdates];
        } else {
            NSMutableArray *ips = [NSMutableArray array];
            for (NSUInteger i = before; i < s->_items.count; i++) [ips addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
            [s.tableView insertRowsAtIndexPaths:ips withRowAnimation:UITableViewRowAnimationNone];
        }
        if (first && p.title.length && !s.title.length) s.title = p.title;
        s->_empty.text = p.error ? [NSString stringWithFormat:@"Could not load.\n%@", p.error] : s.emptyText ?: @"Nothing here.";
        s->_empty.hidden = s->_items.count > 0;
        if (first && [s grid]) [s makeSpareCells];
        if (first) {
            /* time to rows on screen: measured after the table has laid out the new rows */
            [s.tableView layoutIfNeeded];
            s->_lastLoadMs = tb_now_ms() - t0;
            TBLog(@"PadTube: list '%@' %lu rows in %.0f ms (net %.0f, parse %.1f)", s.title, (unsigned long)p.items.count, s->_lastLoadMs, p.netMs, p.parseMs);
        }
        if (s.pageLoaded) s.pageLoaded(p);
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if ([self grid]) { int c = _cols ?: [self columns]; return (NSInteger)((_items.count + (NSUInteger)c - 1) / (NSUInteger)c); }
    return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self grid]) {
        int c = _cols ?: [self columns];
        TBGridCell *g = [tv dequeueReusableCellWithIdentifier:@"g"];
        if (!g && _spareCells.count) { g = _spareCells.lastObject; [_spareCells removeLastObject]; }
        if (!g) g = [tv dequeueReusableCellWithIdentifier:@"g" forIndexPath:ip];
        /* a new or spare cell is 320 pt wide until the table lays it out: give it the row's size first, so each tile
         * asks for its thumbnail at the size it is shown at (owner bug 2026-11-13, blurred thumbnails at launch) */
        g.frame = CGRectMake(0, g.frame.origin.y, tv.bounds.size.width, tv.rowHeight);
        [g layoutIfNeeded];
        NSUInteger from = (NSUInteger)ip.row * (NSUInteger)c, n = MIN((NSUInteger)c, _items.count - from);
        [g showItems:[_items subarrayWithRange:NSMakeRange(from, n)] columns:c];
        __weak TBListController *w = self;
        g.tapped = ^(TBItem *it) { [TBRouter openItem:it from:w]; };
        if (from + n + 8 >= _items.count) [self loadMore:NO];
        return g;
    }
    TBItemCell *c = [tv dequeueReusableCellWithIdentifier:@"i" forIndexPath:ip];
    c.style = self.cardStyle;
    [c showItem:_items[(NSUInteger)ip.row]];
    if ((NSUInteger)ip.row + 8 >= _items.count) [self loadMore:NO];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self grid]) return; /* tiles handle their taps */
    [TBRouter openItem:_items[(NSUInteger)ip.row] from:self];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ![self grid] && self.canDelete && self.canDelete(_items[(NSUInteger)ip.row]);
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    TBItem *it = _items[(NSUInteger)ip.row];
    [_items removeObjectAtIndex:(NSUInteger)ip.row];
    [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    if (self.deleteItem) self.deleteItem(it);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }
@end

@implementation TBRouter
+ (void)openItem:(TBItem *)it from:(UIViewController *)vc {
    if (it.kind == TB_KIND_VIDEO || it.kind == TB_KIND_LIVE) [self openVideo:it.ident title:it.title from:vc];
    else if (it.kind == TB_KIND_CHANNEL) [self openChannel:it.ident title:it.title from:vc];
    else if (it.kind == TB_KIND_PLAYLIST && [it.ident hasPrefix:@"RD"]) { /* a mix: its queue through next */
        NSString *pl = it.ident, *v = it.firstVideo;
        TBListController *l = [[TBListController alloc] initWithTitle:it.title loader:^(NSString *c, void (^done)(TBPage *)) {
            [TBCore mix:pl firstVideo:v continuation:c done:done];
        }];
        l.cardStyle = TBCardGrid;
        [vc.navigationController pushViewController:l animated:YES];
    } else if (it.kind == TB_KIND_PLAYLIST) [self openPlaylist:it.ident title:it.title from:vc];
}

+ (void)openVideo:(NSString *)videoId title:(NSString *)title from:(UIViewController *)vc {
    TBWatchController *w = [[TBWatchController alloc] initWithVideoId:videoId title:title];
    [vc.navigationController pushViewController:w animated:YES];
}

+ (void)openChannel:(NSString *)channelId title:(NSString *)title from:(UIViewController *)vc {
    [vc.navigationController pushViewController:[[TBChannelController alloc] initWithChannel:channelId title:title] animated:YES];
}

+ (void)openPlaylist:(NSString *)playlistId title:(NSString *)title from:(UIViewController *)vc {
    /* Owner report 2026-11-12: a private playlist opened empty. The web client has no account; signed in, the TV
     * client with the account token sees the owner's private playlists (VL<id>, as Watch Later). Its continuation
     * tokens only work with the same client, so the client is fixed after the first page. */
    __block BOOL tv = [TBAccount signedIn];
    TBListController *l = [[TBListController alloc] initWithTitle:title loader:^(NSString *c, void (^done)(TBPage *)) {
        if (!tv) { [TBCore playlist:playlistId continuation:c done:done]; return; }
        [TBCore tvBrowse:[@"VL" stringByAppendingString:playlistId] continuation:c done:^(TBPage *p) {
            if (c || (p.items.count && !p.error)) { done(p); return; }
            tv = NO;   /* nothing from the TV client: the public web page */
            [TBCore playlist:playlistId continuation:nil done:done];
        }];
    }];
    l.cardStyle = TBCardGrid;
    [vc.navigationController pushViewController:l animated:YES];
}
@end
