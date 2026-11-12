#import <UIKit/UIKit.h>

/* Account: sign in with a code (OAuth device flow, TV client). No web page in the app: the code, the short address
 * google.com/device and a QR code are shown big; the person enters the code on a phone or a computer; the app polls. */
@interface TBAccountController : UIViewController
@property (nonatomic, readonly) NSString *shownCode;   /* for the self-test */
- (void)startSignIn;
@end
