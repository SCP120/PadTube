#import "TBListController.h"

/* Channel page (docs/design/old-youtube-ui.md §7.2): channel bar (avatar, name, subscribers, Subscribe) and a
 * dark sub-bar with Videos / Live / Playlists, then list cards. */
@interface TBChannelController : TBListController
- (id)initWithChannel:(NSString *)channelId title:(NSString *)title;
@end
