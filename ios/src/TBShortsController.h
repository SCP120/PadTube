#import <UIKit/UIKit.h>
@class TBShortsPlayer;

/* Shorts tab (D53-D56, docs/design/shorts.md): a vertical pager of Shorts, two players (current + next prepared). */
@interface TBShortsController : UIViewController
@property (nonatomic, readonly) UIScrollView *pager;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) TBShortsPlayer *current;
@property (nonatomic, readonly) double lastSettleToFrameMs;   /* the end of the last swipe -> the first new frame */
@property (nonatomic, readonly) BOOL lastWasPrepared;          /* that Short was prerolled before the swipe ended */
@property (nonatomic, copy) void (^firstFrame)(TBShortsController *c);   /* self-test: after each settle's first frame */
- (void)pagerSettled;
- (void)reload;                                                 /* reload button and pull at the first Short */
@property (nonatomic, readonly) double lastReloadToFrameMs;                                          /* the swipe ended (also called by the self-test) */
- (void)togglePause;
- (void)openComments;
- (void)share:(BOOL)open;                                      /* self-test: the share sheet of the Short on screen */
- (NSDictionary *)testState;
@end
