#import <UIKit/UIKit.h>

/* The app frame of YouTube for iPad 1.x (docs/design/old-youtube-ui.md §4-6): a 256 pt dark guide on the left
 * (open in landscape on list screens, a slide-out in portrait), one dark 44 pt header with the menu or back
 * button and the search pill, and a navigation stack for the content below the header. */

@protocol TBFullWidth <NSObject>
@optional
- (BOOL)wantsFullWidth;    /* the watch page: header and content over the whole width, guide closed */
@end

@interface TBShell : UIViewController
+ (TBShell *)shared;
@property (nonatomic, readonly) UINavigationController *nav;
@property (nonatomic, readonly) NSInteger guideIndex;        /* selected guide row */
@property (nonatomic, readonly) BOOL guideOpen;
@property (nonatomic, readonly) UITextField *searchField;
- (void)selectGuideRow:(NSInteger)row;                       /* rows in the order of +guideTitles */
+ (NSArray *)guideTitles;
- (void)search:(NSString *)q;
- (void)toggleGuide;
- (void)refreshAccount;                                      /* sign-in state changed */
- (CGRect)titleFrame;                                         /* header title, for the self-test */
@end
