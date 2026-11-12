# Shorts tab

Owner request (2026-11-12, restated 2026-11-13). It replaces the cut "Shorts feed" (PLAN §4; requirements: "Shorts play as normal videos"). Decisions D53-D57.

## 1. Research (2026-11-13, MEASURED on the Mac, logged out)

| Question | Answer | Evidence |
|---|---|---|
| Seed without a video (the Shorts tab) | `navigation/resolve_url` of `/shorts` gives `reelWatchEndpoint {params: "CAw%3D", inputType: REEL_WATCH_INPUT_TYPE_SEEDLESS}`. `reel/reel_item_watch` with those two fields (MWEB, `disablePlayerResponse`) answers in 0.9-1.1 s with `replacementEndpoint.reelWatchEndpoint.videoId` (the first Short) and `sequenceContinuation` | probe; `browse FEshorts` is HTTP 400 for MWEB and WEB |
| The next Shorts | `reel/reel_watch_sequence {sequenceParams: <sequenceContinuation>}`: 8 entries in 0.6-1.0 s; `continuationEndpoint.continuationCommand.token` -> the same call with `{continuation: <token>}` gives the next 8 | probe |
| Per entry | Only `command.reelWatchEndpoint.videoId` and a cover `frame0.jpg`. Title, channel, views: the player answer (VISIONOS, as for any video). Likes, subscribed, comments: `next` (MWEB), as on the watch page | probe |
| Formats (8 Shorts, VISIONOS) | H.264 at 144x256 to 1080x1920 in every one: 360x640 (4D401E), 480x854 (4D401F), 720x1280 at 30 fps (4D401F) or 60 fps (4D4020, Main 3.2), plus AAC. 17-119 s long | probe |
| Cover | `frame0.jpg` = the first frame, 268x480, 8-22 KB. `oar2.jpg` 1080x1920, 74-192 KB. `hq720` is a 16:9 crop | probe (3 Shorts) |
| Playback for a swipe feed on iOS 6 | One MPMoviePlayerController per swipe: `setContentURL` stalls the main thread 177-326 ms and only one can play. Two AVPlayers (current + next), the next prerolled (`prerollAtRate:completionHandler:`, iOS 6.0), make the swipe only a `play` of a ready player | PadTok research-efficiency §3, §5; PT-S R4 (device) |

## 2. Design

- **Feed:** core `tb_shorts(continuation)` does seed + first sequence page in one call, then pages. Items are videos (id, `frame0.jpg` cover). Unit test on a trimmed captured answer.
- **Players:** two `TBShortsPlayer` slots, each an `AVPlayer` + `AVPlayerLayer` with its own local stream (`tb_hls_add`: the HLS server serves more than one stream at a time; the watch page's `tb_hls_set` stream is not touched). Variant: 720x1280 when it is 30 fps or less, else 480x854 (two 60 fps 720p decoders on the A5 are unverified). The slot for the next Short loads and prerolls it while the current one plays. At the swipe's end: `play` the prepared slot, `pause` the old one (iOS 6 has no `AVPlayer.volume`, so the other player must not play), then the free slot loads the next-but-one.
- **Cover:** the `frame0.jpg` under the video layer until the layer is `readyForDisplay`.
- **Loop:** at `AVPlayerItemDidPlayToEndTimeNotification`, seek to 0 and play.
- **Forward buffer (D66, D67):** iOS 6 AVPlayer buffers up to about 50 s ahead and has no setting for it, and a swipe drops that buffer. Each slot sets a time limit on its stream once a second (`tb_hls_limit_time`): the server serves only segments that start at most 10 s after the play position, and holds the other requests until the position moves on.
- **Pager:** a vertical `UIScrollView` with paging, three page views (previous, current, next) that move as the index changes.
- **Layout:** portrait: the video 9:16 at the full height of the content area, centred on black, a column of buttons on the right (Like, Comments, Share, Subscribe) and title + channel at the bottom left. Landscape: the video 9:16 at full height on the left, a side panel on the right with title, channel, views, Subscribe, Like, Comments, Share. The guide works as on the other tabs.
- **Actions:** tap: pause / play. Like, Subscribe: the account calls of the watch page (sign-in needed). Comments: the comments screen is pushed (swipe back returns). Share: the iOS share sheet with `https://youtube.com/shorts/<id>`.
- **Swipe back (D49):** the Shorts tab is a root screen, so swipe back never starts there. The pager scrolls only up and down.

## 3. Gates and tests

| Gate | Target | Test |
|---|---|---|
| Swipe end -> first new frame of the next Short | <= 500 ms | `tests/device/shorts.py`, 20 swipes, both orientations |
| Frames during the swipe | >= 55 fps | same, display link |
| Main-thread pass | <= 50 ms | same, run-loop observer + stall sampler |
| RAM | <= 120 MB steady, <= 180 MB peak | same |
| Dark mode | every Shorts view in both themes | screenshot audit |
