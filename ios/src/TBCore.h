#import <Foundation/Foundation.h>
#include "tb_yt.h"

/* Objective-C side of the C core. Every network call runs on a background queue and calls back on the main queue. */

@interface TBItem : NSObject
@property (nonatomic) int kind;
@property (nonatomic, copy) NSString *ident, *title, *byline, *channelId, *length, *views, *published, *thumb, *setVideoId, *firstVideo;
@property (nonatomic, strong) NSArray *keys;   /* de-duplication keys (tb_item_keys) */
@property (nonatomic, readonly) NSString *meta; /* "views · published" */
+ (NSArray *)itemsFromList:(const tb_list *)l;
@end

@interface TBPage : NSObject
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, copy) NSString *continuation, *title, *subtitle, *avatar, *error;
@property (nonatomic) int subscribed;
@property (nonatomic) double netMs, parseMs;
@end

@interface TBCaptionTrack : NSObject
@property (nonatomic, copy) NSString *url, *lang, *name;
@property (nonatomic) BOOL asr;
@end

@interface TBFormat : NSObject
@property (nonatomic) int itag, width, height, bitrate;
@property (nonatomic) BOOL audio;
@property (nonatomic, copy) NSString *url, *mime, *audioTrackId, *audioTrackName;
@property (nonatomic) BOOL audioDefault;
@property (nonatomic) long long indexEnd, contentLength;
@end

@interface TBPlayerInfo : NSObject
@property (nonatomic, copy) NSString *status, *reason, *title, *author, *channelId, *descriptionText, *views, *hlsUrl;
@property (nonatomic, strong) NSArray *videoFormats; /* avc1, height <= 720, ascending */
@property (nonatomic, strong) NSArray *audioFormats; /* mp4a.40.2 */
@property (nonatomic, strong) NSArray *captionTracks;
@property (nonatomic) int lengthSeconds;
@property (nonatomic) BOOL live;
@property (nonatomic) double netMs;
@end

@interface TBNextInfo : NSObject
@property (nonatomic, copy) NSString *title, *views, *date, *descriptionText, *channel, *channelId, *channelThumb, *subscribers, *likes;
@property (nonatomic, copy) NSString *commentsToken, *commentCount;
@property (nonatomic) int subscribed;
@property (nonatomic, strong) NSArray *related;
@property (nonatomic, strong) NSArray *chapters; /* NSArray of @[start NSNumber, title] */
@end

@interface TBCue : NSObject
@property (nonatomic) double start, end;
@property (nonatomic, copy) NSString *text;
@end

@interface TBCore : NSObject
+ (void)start;                         /* TLS roots, visitor ID, HLS server */
+ (NSString *)stateDir;
+ (dispatch_queue_t)queue;
+ (void)search:(NSString *)q continuation:(NSString *)c done:(void (^)(TBPage *))done;
+ (void)search:(NSString *)q params:(NSString *)params continuation:(NSString *)c done:(void (^)(TBPage *))done;
+ (void)suggest:(NSString *)q done:(void (^)(NSArray *))done;
+ (void)player:(NSString *)videoId done:(void (^)(TBPlayerInfo *))done;
+ (void)next:(NSString *)videoId done:(void (^)(TBNextInfo *))done;
+ (void)captions:(TBCaptionTrack *)t done:(void (^)(NSArray *cues))done;
+ (void)channel:(NSString *)channelId tab:(NSString *)params continuation:(NSString *)c done:(void (^)(TBPage *))done;
+ (void)playlist:(NSString *)playlistId continuation:(NSString *)c done:(void (^)(TBPage *))done;
+ (void)mix:(NSString *)playlistId firstVideo:(NSString *)v continuation:(NSString *)c done:(void (^)(TBPage *))done;
+ (void)tvBrowse:(NSString *)browseId continuation:(NSString *)c done:(void (^)(TBPage *))done;
@end

NSString *TBStr(const char *s);
