#import <UIKit/UIKit.h>

/* Comments (read only), on their own screen, loaded on tap (research-efficiency §9). Replies open the same screen. */
@interface TBCommentsController : UITableViewController
- (id)initWithToken:(NSString *)token title:(NSString *)title;
@end
