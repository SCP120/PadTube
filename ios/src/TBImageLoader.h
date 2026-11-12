#import <UIKit/UIKit.h>

/* Thumbnails: fetched with the C client (keep-alive), decoded and scaled off the main thread into opaque bitmaps,
 * kept in a 12 MB RAM cache (research-efficiency §5) and a disk cache of the original JPEGs. */
@interface TBImageLoader : NSObject
/* Calls done on the main queue (maybe at once from RAM). Returns a token for cancel. */
+ (id)load:(NSString *)url pixelSize:(CGSize)size done:(void (^)(UIImage *img))done;
+ (void)cancel:(id)token;
+ (void)clearMemory;
+ (NSUInteger)memoryBytes;
@end
