#import <UIKit/UIKit.h>

/* Segmented control of the 1.x tab bar (docs/design/old-youtube-ui.md §8.3), drawn from two stretchable images. */
@interface TBSegments : UIView
@property (nonatomic, strong) NSArray *titles;
@property (nonatomic) NSInteger selected;
@property (nonatomic, copy) void (^changed)(NSInteger i);
@end
