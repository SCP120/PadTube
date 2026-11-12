#import "TBSearchController.h"
#import "TBCore.h"
#import "TBStore.h"

@implementation TBSearchController

- (id)init {
    __weak TBSearchController *w;
    self = [super initWithTitle:@"Search" loader:nil];
    w = self;
    self.loader = ^(NSString *c, void (^done)(TBPage *)) {
        TBSearchController *s = w;
        if (!s.query.length) { TBPage *p = [TBPage new]; p.items = @[]; done(p); return; }
        [TBCore search:s.query continuation:c done:done];
    };
    self.emptyText = @"Type in the search field at the top right.";
    self.cardStyle = TBCardGrid;
    return self;
}

- (void)search:(NSString *)q {
    _query = [q copy];
    [TBStore addSearch:q];
    self.title = TBStr(q.UTF8String) ?: @"";   /* iOS 6 emoji filter for the header title (D34) */
    [self reload];
}
@end
