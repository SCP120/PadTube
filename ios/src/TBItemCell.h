#import <UIKit/UIKit.h>
@class TBItem;

typedef enum { TBCardList = 0, TBCardFeed = 1, TBCardGrid = 2 } TBCardStyle;

/* A paper card row (docs/design/old-youtube-ui.md §7): feed card = thumbnail 313x193 on the right (Home,
 * Subscriptions); list card = thumbnail 276x155 on the left (search, channel, playlist, history).
 * Opaque views only, one stretchable card image, no shadows or masks (55 fps gate). */
@interface TBItemCell : UITableViewCell
@property (nonatomic) TBCardStyle style;
+ (CGFloat)heightForStyle:(TBCardStyle)style;
+ (CGFloat)height;  /* list card */
- (void)showItem:(TBItem *)item;
- (void)applyTheme;
@end

/* Related row on the dark panel of the watch page (§7.3): 236x64 card, 104x64 thumbnail. */
@interface TBRelatedCell : UITableViewCell
+ (CGFloat)height;
/* YES: on the content area (portrait Suggested tab): paper card and content colours, no dark bands between rows. */
@property (nonatomic) BOOL onContent;
- (void)showItem:(TBItem *)item;
@end

/* Compact grid (owner request 2026-11-12): one table row holds 3 (portrait) or 4 (landscape) tiles: thumbnail on
 * top, title (2 lines, ellipsis), channel, views and age. */
@interface TBGridCell : UITableViewCell
+ (CGFloat)heightForWidth:(CGFloat)w columns:(int)cols;
- (void)showItems:(NSArray *)items columns:(int)cols;
@property (nonatomic, copy) void (^tapped)(TBItem *item);
@end
