#import "TBStore.h"
#import "TBLog.h"
#import "TBCore.h"
#include "tb_store.h"

@implementation TBStore
+ (void)open {
    NSString *p = [[TBCore stateDir] stringByAppendingPathComponent:@"padtube.db"];
    if (tb_store_open(p.fileSystemRepresentation)) TBLog(@"PadTube: store did not open");
}
+ (void)addHistory:(NSString *)v title:(NSString *)t channel:(NSString *)c length:(NSString *)l {
    tb_store_history_add(v.UTF8String, t.UTF8String, c.UTF8String, l.UTF8String);
}
+ (void)savePosition:(double)pos video:(NSString *)v { tb_store_history_position(v.UTF8String, pos); }
+ (double)positionOf:(NSString *)v { return tb_store_history_get_position(v.UTF8String); }
+ (NSArray *)history {
    tb_hist *h;
    int n;
    NSMutableArray *a = [NSMutableArray array];
    /* 200 rows on screen at most; older entries stay in the database */
    if (tb_store_history_list(200, &h, &n)) return a;
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    for (int i = 0; i < n; i++) {
        TBItem *it = [TBItem new];
        it.kind = TB_KIND_VIDEO;
        it.ident = TBStr(h[i].video_id);
        it.title = TBStr(h[i].title) ?: @"";
        it.byline = TBStr(h[i].channel);
        it.length = TBStr(h[i].length);
        it.thumb = [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", it.ident];
        it.published = [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:h[i].watched_at]];
        [a addObject:it];
    }
    tb_hist_free(h, n);
    return a;
}
+ (void)removeHistory:(NSString *)v { tb_store_history_remove(v.UTF8String); }
+ (void)addSearch:(NSString *)q { tb_store_search_add(q.UTF8String); }
+ (NSArray *)recentSearches {
    char **v;
    int n;
    NSMutableArray *a = [NSMutableArray array];
    /* 10 rows fit the suggestion list */
    if (tb_store_search_list(10, &v, &n)) return a;
    for (int i = 0; i < n; i++) { [a addObject:TBStr(v[i])]; free(v[i]); }
    free(v);
    return a;
}
+ (NSString *)valueFor:(NSString *)k {
    char *v = tb_store_get(k.UTF8String);
    NSString *s = TBStr(v);
    free(v);
    return s;
}
+ (void)setValue:(NSString *)v forKey:(NSString *)k { tb_store_set(k.UTF8String, v.UTF8String); }
@end
