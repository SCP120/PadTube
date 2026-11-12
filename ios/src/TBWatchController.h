#import <UIKit/UIKit.h>
@class TBPlayerView, TBNextInfo;

/* Watch page: player, title, channel, actions, description, related videos. The player request starts in init
 * (at the tap), before the view exists. */
@interface TBWatchController : UIViewController
@property (nonatomic, readonly) NSString *videoId;
@property (nonatomic, readonly) TBPlayerView *player;
@property (nonatomic, readonly) TBNextInfo *next;
- (id)initWithVideoId:(NSString *)videoId title:(NSString *)title;
+ (TBWatchController *)current;
- (void)toggleFullscreen;           /* full screen is always landscape; the old orientation comes back after */
@property (nonatomic, readonly) BOOL isFullscreen;
@end
