#import "TBItemCell.h"
#import "TBCore.h"
#import "TBImageLoader.h"
#import "TBStyle.h"

/* §7.1 duration badge: black about 80%, white HelveticaNeue 14, inset 10 from the bottom-right corner */
static UILabel *badgeLabel(CGFloat size) {
    UILabel *b = [UILabel new];
    b.font = TBFont(size);
    b.textColor = [UIColor whiteColor];
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    b.textAlignment = NSTextAlignmentCenter;
    return b;
}

static void placeBadge(UILabel *b, NSString *text, CGRect thumb, CGFloat inset, CGFloat h) {
    b.hidden = text.length == 0;
    if (!text.length) return;
    b.text = text;
    CGSize s = [text sizeWithFont:b.font];
    b.frame = CGRectMake(CGRectGetMaxX(thumb) - inset - s.width - 10, CGRectGetMaxY(thumb) - inset - h, s.width + 10, h);
}

@implementation TBItemCell {
    UIImageView *_card, *_thumb;
    UILabel *_title, *_byline, *_meta, *_badge;
    UIView *_rule, *_ruleLight;
    id _token;
    NSString *_url;
}

+ (CGFloat)heightForStyle:(TBCardStyle)style { return style == TBCardFeed ? 213 : 167; } /* card + gap (§7.1 pitch 213) */
+ (CGFloat)height { return [self heightForStyle:TBCardList]; }

- (id)initWithStyle:(UITableViewCellStyle)st reuseIdentifier:(NSString *)rid {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [TBStyle contentBackground];
    self.contentView.backgroundColor = [TBStyle contentBackground];
    _card = [[UIImageView alloc] initWithImage:[TBStyle cardImage]];
    _card.opaque = YES;
    [self.contentView addSubview:_card];
    _thumb = [UIImageView new];
    _thumb.opaque = YES;
    _thumb.backgroundColor = [TBStyle placeholder];
    [self.contentView addSubview:_thumb];
    _badge = badgeLabel(14);
    [self.contentView addSubview:_badge];
    _title = [UILabel new];
    _title.numberOfLines = 2;
    _title.textColor = [TBStyle text];
    _byline = [UILabel new];
    _byline.textColor = [TBStyle text];
    _meta = [UILabel new];
    _meta.textColor = [TBStyle secondary];
    for (UILabel *l in @[_title, _byline, _meta]) { l.opaque = YES; l.backgroundColor = [TBStyle cardFill]; [self.contentView addSubview:l]; }
    /* §7.1 etched divider: 1 px #E5E5E5 over 1 px white */
    _rule = [UIView new];
    _rule.backgroundColor = [TBStyle rule];
    _ruleLight = [UIView new];
    _ruleLight.backgroundColor = [TBStyle ruleLight];
    [self.contentView addSubview:_rule];
    [self.contentView addSubview:_ruleLight];
    return self;
}

- (void)applyTheme {}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    /* §7.1: card inset 10 from the content edges, at most 748 wide, centered in a wider content area */
    CGFloat cw = MIN(748, w - 20), cx = floor((w - cw) / 2);
    if (self.style == TBCardFeed) {
        CGFloat ch = 193;
        _card.frame = CGRectMake(cx, 0, cw, ch + 2);
        CGFloat tw = 313;
        _thumb.frame = CGRectMake(cx + cw - tw - 1, 0, tw, ch);
        CGFloat x = cx + 20, tw2 = cw - tw - 40;
        _byline.font = TBFont(16);
        _byline.frame = CGRectMake(x, 16, tw2, 20);
        _rule.hidden = _ruleLight.hidden = YES; /* owner 2026-11-12: read as a stray line */
        _rule.frame = CGRectMake(cx + 10, 66, cw - tw - 20, 1);
        _ruleLight.frame = CGRectMake(cx + 10, 67, cw - tw - 20, 1);
        _title.font = TBFont(18);
        _title.frame = CGRectMake(x, 82, tw2, 46);
        _meta.font = TBFont(14);
        _meta.frame = CGRectMake(x, 138, tw2, 18);
        placeBadge(_badge, _badge.text, _thumb.frame, 10, 23);
    } else {
        CGFloat ch = 155;
        _card.frame = CGRectMake(cx, 0, cw, ch + 2);
        _thumb.frame = CGRectMake(cx + 1, 0, 276, ch);
        CGFloat x = CGRectGetMaxX(_thumb.frame) + 14, tw = cx + cw - x - 14;
        _rule.hidden = _ruleLight.hidden = YES;
        _title.font = TBFont(17);
        _title.frame = CGRectMake(x, 14, tw, 44);
        _byline.font = TBFont(14);
        _byline.frame = CGRectMake(x, 70, tw, 18);
        _meta.font = TBFont(14);
        _meta.frame = CGRectMake(x, 90, tw, 18);
        placeBadge(_badge, _badge.text, _thumb.frame, 10, 21);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [TBImageLoader cancel:_token];
    _token = nil;
    _thumb.image = nil;
}

- (void)showItem:(TBItem *)it {
    _title.text = it.title;
    _byline.text = it.byline;
    if (it.kind == TB_KIND_CHANNEL) _meta.text = it.views;
    else if (it.kind == TB_KIND_PLAYLIST) _meta.text = it.length ? [NSString stringWithFormat:@"Playlist • %@", it.length] : @"Playlist";
    else _meta.text = it.views.length && it.published.length ? [NSString stringWithFormat:@"%@ • %@", it.views, it.published] : (it.views ?: it.published);
    NSString *badge = it.kind == TB_KIND_LIVE ? @"LIVE" : it.kind == TB_KIND_VIDEO ? it.length : nil;
    _badge.text = badge;
    _badge.backgroundColor = it.kind == TB_KIND_LIVE ? TBHex(0xCD1A18) : [UIColor colorWithWhite:0 alpha:0.8];
    [self setNeedsLayout];
    _url = it.thumb;
    __weak TBItemCell *w = self;
    NSString *u = it.thumb;
    CGSize px = self.style == TBCardFeed ? CGSizeMake(313, 193) : CGSizeMake(276, 155);
    _token = [TBImageLoader load:u pixelSize:px done:^(UIImage *img) {
        TBItemCell *c = w;
        if (c && [c->_url isEqualToString:u]) { c->_thumb.image = img; c->_token = nil; }
    }];
}
@end

@implementation TBRelatedCell {
    UIImageView *_card, *_thumb;
    UILabel *_title, *_meta, *_badge;
    id _token;
    NSString *_url;
}

+ (CGFloat)height { return 74; } /* §7.3 pitch 74 */

- (id)initWithStyle:(UITableViewCellStyle)st reuseIdentifier:(NSString *)rid {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [TBStyle panel];
    self.contentView.backgroundColor = [TBStyle panel];
    _card = [[UIImageView alloc] initWithImage:[TBStyle smallCardImage]];
    [self.contentView addSubview:_card];
    _thumb = [UIImageView new];
    _thumb.backgroundColor = TBHex(0x555555);
    [self.contentView addSubview:_thumb];
    _badge = badgeLabel(13);
    [self.contentView addSubview:_badge];
    _title = [UILabel new];
    _title.font = TBFont(14);
    _title.textColor = [TBStyle relatedTitle];
    _title.numberOfLines = 2;
    _meta = [UILabel new];
    _meta.font = TBFont(12);
    _meta.textColor = [TBStyle relatedMeta];
    for (UILabel *l in @[_title, _meta]) { l.backgroundColor = [TBStyle relatedFill]; [self.contentView addSubview:l]; }
    return self;
}

- (void)setOnContent:(BOOL)on {
    if (on == _onContent) return;
    _onContent = on;
    UIColor *bg = on ? [TBStyle contentBackground] : [TBStyle panel];
    self.backgroundColor = self.contentView.backgroundColor = bg;
    _card.image = on ? [TBStyle cardImage] : [TBStyle smallCardImage];
    _title.textColor = on ? [TBStyle text] : [TBStyle relatedTitle];
    _meta.textColor = on ? [TBStyle secondary] : [TBStyle relatedMeta];
    for (UILabel *l in @[_title, _meta]) l.backgroundColor = on ? [TBStyle cardFill] : [TBStyle relatedFill];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, cw = w - 20;
    _card.frame = CGRectMake(10, 0, cw, 67);
    _thumb.frame = CGRectMake(10, 1, 104, 64);
    CGFloat x = 124, tw = cw - 120;
    _title.frame = CGRectMake(x, 4, tw, 36);
    _meta.frame = CGRectMake(x, 42, tw, 16);
    placeBadge(_badge, _badge.text, _thumb.frame, 3, 19);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [TBImageLoader cancel:_token];
    _token = nil;
    _thumb.image = nil;
}

- (void)showItem:(TBItem *)it {
    _title.text = it.title;
    _meta.text = it.kind == TB_KIND_CHANNEL ? it.views : it.views ?: it.byline;
    _badge.text = it.kind == TB_KIND_LIVE ? @"LIVE" : it.length;
    [self setNeedsLayout];
    _url = it.thumb;
    __weak TBRelatedCell *w = self;
    NSString *u = it.thumb;
    _token = [TBImageLoader load:u pixelSize:CGSizeMake(104, 64) done:^(UIImage *img) {
        TBRelatedCell *c = w;
        if (c && [c->_url isEqualToString:u]) { c->_thumb.image = img; c->_token = nil; }
    }];
}
@end

/* One grid tile: card image, 16:9 thumbnail, three text lines at fixed positions (aligned in every tile). */
@interface TBTile : UIControl
@property (nonatomic, strong) TBItem *item;
@end
@implementation TBTile {
    UIImageView *_card, *_thumb, *_plIcon;
    UIView *_plPanel;           /* playlists and mixes: dark panel on the right of the thumbnail (owner 2026-11-12) */
    UILabel *_plCount;
    UILabel *_title, *_byline, *_meta, *_badge;
    id _token;
    NSString *_url;
}
- (id)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.backgroundColor = [TBStyle contentBackground];
    _card = [[UIImageView alloc] initWithImage:[TBStyle cardImage]];
    _thumb = [UIImageView new];
    _thumb.backgroundColor = [TBStyle placeholder];
    _badge = badgeLabel(12);
    _plPanel = [UIView new];
    _plPanel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    _plIcon = [[UIImageView alloc] initWithImage:[TBStyle icon:@"playlist" size:26 color:[UIColor whiteColor]]];
    _plIcon.contentMode = UIViewContentModeCenter;
    _plCount = [UILabel new];
    _plCount.font = TBFontBold(13);
    _plCount.textColor = [UIColor whiteColor];
    _plCount.backgroundColor = [UIColor clearColor];
    _plCount.textAlignment = NSTextAlignmentCenter;
    _plCount.numberOfLines = 2;
    [_plPanel addSubview:_plIcon];
    [_plPanel addSubview:_plCount];
    _title = [UILabel new];
    _title.font = TBFont(14);
    _title.textColor = [TBStyle text];
    _title.numberOfLines = 2;
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _byline = [UILabel new];
    _byline.font = TBFont(12);
    _byline.textColor = [TBStyle secondary];
    _meta = [UILabel new];
    _meta.font = TBFont(12);
    _meta.textColor = [TBStyle tertiary];
    for (UIView *v in @[_card, _thumb, _plPanel, _badge, _title, _byline, _meta]) { v.userInteractionEnabled = NO; [self addSubview:v]; }
    for (UILabel *l in @[_title, _byline, _meta]) { l.backgroundColor = [TBStyle cardFill]; l.opaque = YES; }
    return self;
}
- (void)layoutSubviews {
    CGFloat w = self.bounds.size.width, th = floor(w * 9 / 16);
    _card.frame = CGRectMake(0, 0, w, self.bounds.size.height);
    _thumb.frame = CGRectMake(1, 0, w - 2, th);
    CGFloat x = 8, tw = w - 16, y = th + 6;
    _title.frame = CGRectMake(x, y, tw, 34);
    _byline.frame = CGRectMake(x, y + 36, tw, 15);
    _meta.frame = CGRectMake(x, y + 52, tw, 15);
    placeBadge(_badge, _badge.text, _thumb.frame, 5, 18);
    CGFloat pw = floor((w - 2) * 0.38);
    _plPanel.frame = CGRectMake(w - 1 - pw, 0, pw, th);
    _plIcon.frame = CGRectMake(0, floor(th / 2) - 30, pw, 30);
    _plCount.frame = CGRectMake(2, floor(th / 2) + 2, pw - 4, 34);
}
- (void)setItem:(TBItem *)it {
    _item = it;
    [TBImageLoader cancel:_token];
    _token = nil;
    _thumb.image = nil;
    self.hidden = it == nil;
    if (!it) return;
    _title.text = it.title;
    _title.frame = CGRectMake(_title.frame.origin.x, _title.frame.origin.y, _title.frame.size.width, 34);
    _byline.text = it.kind == TB_KIND_CHANNEL ? it.byline : it.byline;
    NSString *meta;
    if (it.kind == TB_KIND_CHANNEL) meta = it.views;
    else if (it.kind == TB_KIND_PLAYLIST) meta = it.length ? [NSString stringWithFormat:@"Playlist \u2022 %@", it.length] : @"Playlist";
    else meta = it.views.length && it.published.length ? [NSString stringWithFormat:@"%@ \u2022 %@", it.views, it.published] : (it.views ?: it.published);
    _meta.text = meta.length ? meta : @" ";
    NSString *badge = it.kind == TB_KIND_LIVE ? @"LIVE" : it.kind == TB_KIND_VIDEO ? it.length : nil;
    _badge.text = badge;
    _badge.backgroundColor = it.kind == TB_KIND_LIVE ? TBHex(0xCD1A18) : [UIColor colorWithWhite:0 alpha:0.8];
    BOOL pl = it.kind == TB_KIND_PLAYLIST;
    _plPanel.hidden = !pl;
    if (pl) {
        BOOL mix = [it.ident hasPrefix:@"RD"];
        /* "153 videos" -> number and word on two lines: the 4-column tile is too narrow for one line */
        _plCount.text = mix ? @"Mix" : it.length.length ? [it.length stringByReplacingOccurrencesOfString:@" " withString:@"\n" options:0 range:NSMakeRange(0, it.length.length)] : @"Playlist";
        _meta.text = mix ? @"Mix \u2022 Playlist" : @"Playlist";
        _meta.textColor = TBHex(0xCD1A18);  /* visible: not a single video */
        _meta.font = TBFontBold(12);
    } else {
        _meta.textColor = [TBStyle tertiary];
        _meta.font = TBFont(12);
    }
    [self setNeedsLayout];
    _url = it.thumb;
    __weak TBTile *wself = self;
    NSString *u = it.thumb;
    CGFloat w = self.bounds.size.width;
    _token = [TBImageLoader load:u pixelSize:CGSizeMake(floor(w - 2), floor(w * 9 / 16)) done:^(UIImage *img) {
        TBTile *t = wself;
        if (t && [t->_url isEqualToString:u]) { t->_thumb.image = img; t->_token = nil; }
    }];
}
@end

@implementation TBGridCell {
    NSMutableArray *_tiles;
    int _cols;
}
/* tile: 16:9 thumbnail + 6 + title 34 + 2 + byline 15 + 1 + meta 15 + 8 bottom; row gap 10 */
+ (CGFloat)heightForWidth:(CGFloat)w columns:(int)cols {
    CGFloat tw = floor((w - 10 * (cols + 1)) / cols);
    return floor(tw * 9 / 16) + 81 + 10;
}
- (id)initWithStyle:(UITableViewCellStyle)st reuseIdentifier:(NSString *)rid {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [TBStyle contentBackground];
    self.contentView.backgroundColor = [TBStyle contentBackground];
    _tiles = [NSMutableArray array];
    return self;
}
- (void)showItems:(NSArray *)items columns:(int)cols {
    _cols = cols;
    while ((int)_tiles.count < cols) {
        TBTile *t = [TBTile new];
        [t addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:t];
        [_tiles addObject:t];
    }
    [self layoutTiles]; /* frames first: a tile asks for its thumbnail at its own size */
    for (NSUInteger i = 0; i < _tiles.count; i++) {
        TBTile *t = _tiles[i];
        t.item = (int)i < cols && i < items.count ? items[i] : nil;
        t.hidden = (int)i >= cols || !t.item;
    }
}
- (void)layoutTiles {
    CGFloat w = self.contentView.bounds.size.width ?: self.bounds.size.width, tw = floor((w - 10 * (_cols + 1)) / _cols);
    CGFloat h = self.contentView.bounds.size.height - 10;
    for (int i = 0; i < _cols && i < (int)_tiles.count; i++) [_tiles[(NSUInteger)i] setFrame:CGRectMake(10 + i * (tw + 10), 0, tw, h)];
}
- (void)layoutSubviews { [super layoutSubviews]; [self layoutTiles]; }
- (void)tileTapped:(TBTile *)t { if (self.tapped && t.item) self.tapped(t.item); }
@end
