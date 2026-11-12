#import <Foundation/Foundation.h>

/* Objective-C face of core/tb_store (SQLite WAL): local watch history, resume positions, recent searches, settings. */
@interface TBStore : NSObject
+ (void)open;
+ (void)addHistory:(NSString *)videoId title:(NSString *)title channel:(NSString *)channel length:(NSString *)length;
+ (void)savePosition:(double)pos video:(NSString *)videoId;
+ (double)positionOf:(NSString *)videoId;
+ (NSArray *)history;            /* TBItem, newest first */
+ (void)removeHistory:(NSString *)videoId;
+ (void)addSearch:(NSString *)q;
+ (NSArray *)recentSearches;
+ (NSString *)valueFor:(NSString *)key;
+ (void)setValue:(NSString *)v forKey:(NSString *)key;
@end
