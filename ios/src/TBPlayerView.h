#import <UIKit/UIKit.h>
@class TBPlayerInfo, TBPlayerView;

@protocol TBPlayerViewDelegate <NSObject>
- (void)playerViewToggleFullscreen:(TBPlayerView *)v;
@optional
- (void)playerViewDidFinish:(TBPlayerView *)v;
@end

/* Video player: MPMoviePlayerController on the local HLS server, own controls, captions drawn on top. */
@interface TBPlayerView : UIView
@property (nonatomic, weak) id<TBPlayerViewDelegate> delegate;
@property (nonatomic, readonly) NSString *videoId;
@property (nonatomic, readonly) TBPlayerInfo *info;
@property (nonatomic, readonly) int quality;            /* 0 = Auto (master, 720p first), else a height; default 720 */
@property (nonatomic, readonly) NSString *captionLang;  /* nil = off */
@property (nonatomic) BOOL fullscreen;
@property (nonatomic, readonly) double startMs;         /* play request -> first frame, -1 until then */
@property (nonatomic, readonly) NSString *errorText;
@property (nonatomic, readonly) BOOL ended;
@property (nonatomic, readonly) long startBytes;          /* media bytes downloaded before the first frame */
- (long)fetchedBytes;
- (BOOL)audioOnly;
- (BOOL)engineIsAV;                   /* TBEngine = 1: AVPlayer; else MPMoviePlayerController */                    /* playing the audio-only playlist (background) */               /* played to the end */
+ (void)prewarm;                     /* create the shared movie player (main thread, about 240 ms once) */
- (void)playVideo:(NSString *)videoId info:(TBPlayerInfo *)info requestedAt:(double)t0 startAt:(double)start;
- (void)stop;
- (void)setQuality:(int)height;
- (void)selectCaptionIndex:(NSInteger)i;               /* -1 = off */
- (void)seekTo:(double)seconds;
- (void)setRate:(float)rate;
- (double)currentTime;
- (double)duration;
- (BOOL)isPlaying;
- (void)togglePlay;
- (NSString *)currentCaption;
- (NSArray *)availableHeights;
@end
