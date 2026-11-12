#import "TBListController.h"

/* Search results. The query is typed in the header's search pill (TBShell); suggestions show under it. */
@interface TBSearchController : TBListController
@property (nonatomic, readonly) NSString *query;
- (void)search:(NSString *)q;
@end
