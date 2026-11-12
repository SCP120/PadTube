#import <UIKit/UIKit.h>
@class TBPlayerInfo;

/* One Shorts player slot (D54): an AVPlayer with its own stream on the local HLS server (tb_hls_add). load: asks
 * for the player answer, builds the stream and prerolls at rate 1, so play is one call when the swipe ends. */
@interface TBShortsPlayer : NSObject
@property (nonatomic, readonly) UIView *view;             /* the video layer; put it on the page of videoId */
@property (nonatomic, readonly) NSString *videoId;
@property (nonatomic, readonly) TBPlayerInfo *info;
@property (nonatomic, readonly) BOOL ready;               /* the item is ready to play (HLS: the preroll handler never
                                                            * runs on iOS 6, MEASURED, so this is the item status) */
@property (nonatomic, readonly) BOOL shown;               /* the layer has a picture (readyForDisplay) */
@property (nonatomic, readonly) BOOL wantsPlay;
@property (nonatomic, readonly) double firstFrameMs;      /* play -> the first new frame; -1 until then */
@property (nonatomic, readonly) double loadMs;            /* load -> prerolled */
@property (nonatomic, readonly) NSString *errorText;
@property (nonatomic, copy) void (^changed)(TBShortsPlayer *p);
/* Makes n players on a background queue (the first AVPlayer asks MediaRemote for the audio routes: 115 ms on the
 * main thread, MEASURED), then calls done on the main queue. */
+ (void)makePlayers:(int)n done:(void (^)(NSArray *players))done;
- (void)load:(NSString *)videoId;
- (void)load:(NSString *)videoId info:(TBPlayerInfo *)info;   /* info: a cached player answer (no request) */
- (void)reserve:(NSString *)videoId;                            /* unload, hold the id until load:info: comes */
/* Preload window (owner strategy): preloadOnly = the server gives segment 0 only (TB_HLS gate); freeze = no more
 * segments than it has (the previous Short); NO = no limit (the Short on screen). */
@property (nonatomic) BOOL preloadOnly;
- (void)freeze;
- (double)bufferedAhead;          /* seconds loaded ahead of the play position */
- (BOOL)fullyLoaded;
- (void)play;
- (void)pause;
- (void)unload;
- (double)currentTime;
@end
