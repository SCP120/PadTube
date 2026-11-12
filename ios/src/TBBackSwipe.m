#import "TBBackSwipe.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kEdge = 24;          /* owner request: the left 20-30 pt */
static const CGFloat kFlick = 500;        /* pt/s; D49 start value for "a fast flick" */
static const CGFloat kParallax = 0.3;     /* the screen under starts 30 % to the left (D49) */
static const CGFloat kDim = 0.25;         /* dark layer over the screen under at the start */

@interface TBBackSwipe () <UIGestureRecognizerDelegate>
@end

@implementation TBBackSwipe {
    __weak UINavigationController *_nav;
    __weak UIView *_host;
    UIViewController *_prev;
    UIView *_dim, *_moving;             /* _moving: the nav view's child that holds the top screen */
    UIColor *_hostBackground, *_navBackground;
    CGFloat _dx, _width, _underStart;
    BOOL _popDecided;
}

- (id)initWithNav:(UINavigationController *)nav host:(UIView *)host {
    if (!(self = [super init])) return nil;
    _nav = nav;
    _host = host;
    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    _pan.delegate = self;
    _pan.maximumNumberOfTouches = 1;
    [nav.view addGestureRecognizer:_pan];
    return self;
}

static BOOL inSlider(UIView *v) {
    for (; v; v = v.superview) if ([v isKindOfClass:[UISlider class]]) return YES;
    return NO;
}

- (BOOL)accepts:(UIView *)v at:(CGPoint)p {
    UINavigationController *n = _nav;
    return !_active && n.viewControllers.count > 1 && n.view.window && !n.topViewController.presentedViewController &&
           p.x >= 0 && p.x < kEdge && p.y >= 0 && p.y < n.view.bounds.size.height && [v isDescendantOfView:n.view] && !inSlider(v);
}

- (BOOL)acceptsTouchAtWindowPoint:(CGPoint)p {
    UIView *nv = _nav.view;
    UIView *hit = [nv.window hitTest:p withEvent:nil];
    return [self accepts:hit at:[nv convertPoint:p fromView:nil]];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    return [self accepts:t.view at:[t locationInView:_nav.view]];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    CGPoint v = [_pan velocityInView:_nav.view];
    return v.x > 0 && fabs(v.x) > fabs(v.y);   /* a right move, more across than down: tables keep vertical pans */
}

- (void)panned:(UIPanGestureRecognizer *)g {
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            if ([self begin]) [self move:[g translationInView:_nav.view].x];
            else { g.enabled = NO; g.enabled = YES; }   /* cancels this touch sequence */
            break;
        case UIGestureRecognizerStateChanged: [self move:[g translationInView:_nav.view].x]; break;
        case UIGestureRecognizerStateEnded: [self endWithVelocity:[g velocityInView:_nav.view].x]; break;
        default: if (_prev) [self endWithVelocity:-kFlick - 1]; break; /* cancelled: slide back */
    }
}

- (BOOL)begin {
    UINavigationController *n = _nav;
    UIView *host = _host;
    if (_prev || n.viewControllers.count < 2 || !host) return NO;
    _active = YES;
    _prev = n.viewControllers[n.viewControllers.count - 2];
    UIView *nv = n.view;
    /* iOS 6 throws UIViewControllerHierarchyInconsistency when a child's view goes into a view of another
     * controller (MEASURED: the first build put it in the shell's view). So the previous screen goes into the
     * navigation view, under the view that holds the top screen, and only that view moves. */
    _moving = n.topViewController.view;
    while (_moving.superview && _moving.superview != nv) _moving = _moving.superview;
    if (_moving.superview != nv) { _prev = nil; _active = NO; return NO; }
    _width = nv.bounds.size.width;
    BOOL clear = NO;
    CGRect f = self.underFrame ? [host convertRect:self.underFrame(_prev, &clear) toView:nv] : nv.bounds;
    _hostBackground = host.backgroundColor;
    _navBackground = nv.backgroundColor;
    if (clear) host.backgroundColor = nv.backgroundColor = [UIColor clearColor];
    UIView *pv = _prev.view;   /* loaded and laid out at this size already, unless the iPad turned since */
    pv.transform = CGAffineTransformIdentity;
    pv.frame = f;
    [nv insertSubview:pv belowSubview:_moving];
    _dim = [[UIView alloc] initWithFrame:nv.bounds];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.userInteractionEnabled = NO;
    [nv insertSubview:_dim belowSubview:_moving];
    _underStart = clear ? 0 : -kParallax * f.size.width;   /* next to the guide: no parallax, it would cover the guide */
    CALayer *l = _moving.layer;   /* a shadowPath: no offscreen pass to find the shape */
    l.shadowPath = [UIBezierPath bezierPathWithRect:_moving.bounds].CGPath;
    l.shadowOffset = CGSizeMake(-3, 0);
    l.shadowRadius = 6;
    l.shadowOpacity = 0.35f;
    [self move:0];
    return YES;
}

- (void)apply:(CGFloat)dx {
    CGFloat p = _width > 0 ? dx / _width : 0;
    _moving.transform = CGAffineTransformMakeTranslation(dx, 0);
    _prev.view.transform = CGAffineTransformMakeTranslation(_underStart * (1 - p), 0);
    _dim.alpha = kDim * (1 - p);
    if (self.progress) self.progress(p);
}

- (void)move:(CGFloat)dx {
    if (!_prev) return;
    _dx = MAX(0, MIN(_width, dx));
    [self apply:_dx];
}

- (void)endWithVelocity:(CGFloat)vx {
    if (!_prev) return;
    BOOL pop = vx > kFlick || (_dx > _width / 2 && vx >= -kFlick);
    CGFloat target = pop ? _width : 0;
    /* the rest of the way at the finger's speed, at least 1000 pt/s, 0.1-0.3 s (UIKit's own pop is 0.35 s) */
    NSTimeInterval d = MAX(0.1, MIN(0.3, fabs(target - _dx) / MAX(1000, fabs(vx))));
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    _popDecided = pop;
    if (pop && self.willPop) {
        /* the next pass: this pass commits the slide to the render server first, so a slow stop on the main thread
         * (the player's, MediaPlayer ~110-170 ms MEASURED) does not hold the slide */
        UIViewController *top = _nav.topViewController;
        void (^wp)(UIViewController *) = self.willPop;
        dispatch_async(dispatch_get_main_queue(), ^{ wp(top); });
    }
    [UIView animateWithDuration:d delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ [self apply:target]; }
                     completion:^(BOOL f) {
                         [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                         [self finish:pop];
                     }];
}

- (void)abort { if (_prev) [self finish:_popDecided]; }   /* a decided pop still pops: its player has stopped */

- (void)finish:(BOOL)pop {
    UIViewController *prev = _prev;
    if (!prev) return;
    _prev = nil;
    _popDecided = NO;
    [_dim removeFromSuperview];
    _dim = nil;
    UIView *mv = _moving;
    _moving = nil;
    mv.layer.shadowOpacity = 0;
    mv.layer.shadowPath = NULL;
    prev.view.transform = CGAffineTransformIdentity;
    [prev.view removeFromSuperview];       /* the navigation controller puts it back in its own view on the pop */
    mv.transform = CGAffineTransformIdentity;
    _host.backgroundColor = _hostBackground;
    _nav.view.backgroundColor = _navBackground;
    if (pop) [_nav popViewControllerAnimated:NO];
    if (self.progress) self.progress(0);
    _active = NO;
    if (self.finished) self.finished(pop);
}
@end
