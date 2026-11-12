#import <UIKit/UIKit.h>

/* Swipe back from the left edge (D49). iOS 6 has no interactive pop gesture: a pan that starts in the left 24 pt
 * of the navigation view drags the top screen right, with the previous screen under it in the host view, and pops
 * past half the width or on a fast right flick. The self-test drives begin/move/end with the same code. */
@interface TBBackSwipe : NSObject
- (id)initWithNav:(UINavigationController *)nav host:(UIView *)host;
/* frame of the previous screen in host coordinates while it is under the drag, and whether the host's own
 * background must be clear for that (the guide shows through on the left) */
@property (nonatomic, copy) CGRect (^underFrame)(UIViewController *prev, BOOL *clearHost);
@property (nonatomic, copy) void (^progress)(CGFloat p);          /* 0 = start, 1 = popped */
@property (nonatomic, copy) void (^finished)(BOOL popped);
@property (nonatomic, copy) void (^willPop)(UIViewController *top); /* at release, when the pop is decided */
@property (nonatomic, readonly) BOOL active;                       /* a drag or its slide runs */
@property (nonatomic, readonly) UIPanGestureRecognizer *pan;
- (BOOL)acceptsTouchAtWindowPoint:(CGPoint)p;                      /* the touch filter, for the self-test */
- (BOOL)begin;
- (void)move:(CGFloat)dx;
- (void)endWithVelocity:(CGFloat)vx;
- (void)abort;                                                     /* back to the start at once (a rotation) */
@end
