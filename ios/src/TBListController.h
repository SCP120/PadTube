#import <UIKit/UIKit.h>
#import "TBItemCell.h"
@class TBPage, TBItem;

typedef void (^TBPageLoader)(NSString *continuation, void (^done)(TBPage *page));

/* A list of videos / channels / playlists with paging. Tapping a row opens it (TBRouter). */
@interface TBListController : UITableViewController
@property (nonatomic, copy) TBPageLoader loader;
@property (nonatomic, strong, readonly) NSMutableArray *items;
@property (nonatomic, copy) NSString *emptyText;
@property (nonatomic, copy) void (^pageLoaded)(TBPage *page);
@property (nonatomic, readonly) double lastLoadMs;     /* request start -> rows on screen */
@property (nonatomic, copy) BOOL (^canDelete)(TBItem *item);
@property (nonatomic, copy) void (^deleteItem)(TBItem *item);
@property (nonatomic) TBCardStyle cardStyle;               /* feed cards (Home, Subscriptions) or list cards */
@property (nonatomic, copy) NSArray * (^reloadLocal)(void); /* local lists: rows again when shown */
- (id)initWithTitle:(NSString *)title loader:(TBPageLoader)loader;
- (void)reload;
- (void)showItems:(NSArray *)items;  /* local lists (history) */
@end

@interface TBRouter : NSObject
+ (void)openItem:(TBItem *)item from:(UIViewController *)vc;
+ (void)openVideo:(NSString *)videoId title:(NSString *)title from:(UIViewController *)vc;
+ (void)openChannel:(NSString *)channelId title:(NSString *)title from:(UIViewController *)vc;
+ (void)openPlaylist:(NSString *)playlistId title:(NSString *)title from:(UIViewController *)vc;
@end
