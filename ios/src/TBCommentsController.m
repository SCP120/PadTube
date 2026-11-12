#import "TBCommentsController.h"
#import "TBCore.h"
#import "TBStyle.h"
#import "TBLinks.h"
#include "tb_yt.h"

@interface TBComment : NSObject
@property (nonatomic, copy) NSString *author, *text, *meta, *repliesToken;
@property (nonatomic, strong) NSArray *links;                /* found once, off the main thread */
@property (nonatomic, strong) NSAttributedString *styled;
@property (nonatomic) CGFloat height, width;
@end
@implementation TBComment
@end

@interface TBCommentsController () <UIActionSheetDelegate>
@end

@implementation TBCommentsController {
    NSArray *_sheetLinks;
    TBComment *_sheetComment;
    NSString *_token, *_next;
    NSMutableArray *_rows;
    BOOL _loading;
}

- (id)initWithToken:(NSString *)token title:(NSString *)title {
    if (!(self = [super initWithStyle:UITableViewStylePlain])) return nil;
    _token = [token copy];
    _rows = [NSMutableArray array];
    self.title = title.length ? [NSString stringWithFormat:@"Comments (%@)", title] : @"Comments";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [TBStyle contentBackground];
    self.tableView.separatorColor = [TBStyle dark] ? [TBStyle rule] : TBHex(0xD0D0D0);
    [self load:_token];
}

- (void)load:(NSString *)token {
    if (_loading || !token) return;
    _loading = YES;
    dispatch_async([TBCore queue], ^{
        tb_comments c;
        int rc = tb_yt_comments(token.UTF8String, &c);
        NSMutableArray *a = [NSMutableArray array];
        for (int i = 0; rc == 0 && i < c.n; i++) {
            TBComment *m = [TBComment new];
            m.author = TBStr(c.c[i].author) ?: @"";
            m.text = TBStr(c.c[i].text) ?: @"";
            NSMutableArray *meta = [NSMutableArray array];
            if (c.c[i].published) [meta addObject:TBStr(c.c[i].published)];
            if (c.c[i].likes && c.c[i].likes[0]) [meta addObject:[NSString stringWithFormat:@"%s likes", c.c[i].likes]];
            if (c.c[i].reply_count > 0) [meta addObject:[NSString stringWithFormat:@"%d replies ›", c.c[i].reply_count]];
            m.meta = [meta componentsJoinedByString:@" · "];
            m.repliesToken = TBStr(c.c[i].replies_token);
            m.links = [TBLinks linksIn:m.text];
            m.styled = [TBLinks styledText:m.text font:TBFont(15) color:[TBStyle text] links:m.links];
            [a addObject:m];
        }
        NSString *next = rc == 0 ? TBStr(c.continuation) : nil;
        tb_comments_free(&c);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO;
            self->_next = a.count ? next : nil;
            [self->_rows addObjectsFromArray:a];
            [self.tableView reloadData];
        });
    });
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    TBComment *m = _rows[(NSUInteger)ip.row];
    CGFloat w = tv.bounds.size.width - 32;
    if (m.width != w) { /* measured once per width */
        CGSize s = [m.text sizeWithFont:TBFont(15) constrainedToSize:CGSizeMake(w, 2000) lineBreakMode:NSLineBreakByWordWrapping];
        m.height = s.height + 56;
        m.width = w;
    }
    return m.height;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
        for (int i = 0; i < 3; i++) { UILabel *l = [UILabel new]; l.tag = 10 + i; [c.contentView addSubview:l]; }
    }
    TBComment *m = _rows[(NSUInteger)ip.row];
    UILabel *a = (UILabel *)[c.contentView viewWithTag:10], *t = (UILabel *)[c.contentView viewWithTag:11], *x = (UILabel *)[c.contentView viewWithTag:12];
    CGFloat w = tv.bounds.size.width - 32;
    a.frame = CGRectMake(16, 8, w, 18);
    a.text = m.author;
    t.frame = CGRectMake(16, 28, w, m.height - 56);
    t.numberOfLines = 0;
    t.text = m.text;
    x.frame = CGRectMake(16, m.height - 26, w, 18);
    x.text = m.meta;
    UIColor *bg = [TBStyle contentBackground];
    c.backgroundColor = bg;
    c.contentView.backgroundColor = bg;
    for (UILabel *l in @[a, t, x]) l.backgroundColor = bg;
    a.font = TBFontBold(13);
    t.font = TBFont(15);
    x.font = TBFont(13);
    a.textColor = [TBStyle text];
    t.textColor = [TBStyle text];
    x.textColor = [TBStyle secondary];
    c.selectionStyle = m.repliesToken || m.links.count ? UITableViewCellSelectionStyleGray : UITableViewCellSelectionStyleNone;
    t.attributedText = m.styled;
    if ((NSUInteger)ip.row + 5 >= _rows.count) [self load:_next];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    TBComment *m = _rows[(NSUInteger)ip.row];
    NSArray *links = m.links;
    if (!links.count) { [self openReplies:m]; return; }
    if (links.count == 1 && !m.repliesToken) { [TBLinks openURL:[links[0] URL] from:self]; return; }
    /* several choices: each link, and the replies */
    _sheetLinks = links;
    _sheetComment = m;
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSTextCheckingResult *r in links) [s addButtonWithTitle:r.URL.absoluteString];
    if (m.repliesToken) [s addButtonWithTitle:@"Replies"];
    [s showFromRect:[tv rectForRowAtIndexPath:ip] inView:tv animated:YES];
}

- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (i < 0) return;
    if (i < (NSInteger)_sheetLinks.count) [TBLinks openURL:[_sheetLinks[(NSUInteger)i] URL] from:self];
    else [self openReplies:_sheetComment];
}

- (void)openReplies:(TBComment *)m {
    if (!m.repliesToken) return;
    TBCommentsController *r = [[TBCommentsController alloc] initWithToken:m.repliesToken title:nil];
    r.title = [NSString stringWithFormat:@"Replies to %@", m.author];
    UINavigationController *n = self.navigationController ?: self.parentViewController.navigationController;
    [n pushViewController:r animated:YES];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }
@end
