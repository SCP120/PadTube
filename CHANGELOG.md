# Changelog

## [Unreleased]

## [0.2.0] - 2026-11-13

### Added
- Shorts tab in the guide: a vertical swipe feed, 9:16 video at full height in portrait and a side panel in landscape, loop, pause, like, comments, subscribe, share; two players so the next Short is ready before the swipe ends; a reload button in the header and pull-to-reload at the first Short.
- Signed-in playback: when YouTube asks to confirm you are not a bot, PadTube plays through your signed-in account (the TV client). It runs YouTube's player challenge in iOS 6's own JavaScriptCore; the player is prepared once per YouTube player version (about 4 s on an iPad mini 1) and each video adds about 10 ms. Signed out, the plain player is used as before.
- Gestures: swipe from the left edge to go back (iOS 6 has no such gesture of its own), swipe down to leave full screen, double tap the left or right side of the video to skip 10 s, swipe to change the tab under the video.

### Fixed
- Grid thumbnails were blurred after the app opened: the first tiles asked for an image of the wrong (too small) size and showed it scaled up.
- Home, Subscriptions and the Library lists refresh the sign-in token before it expires (only account actions did).
- When Google ends the sign-in, PadTube opens the sign-in code at once instead of failing quietly.
- YouTube's "Sign in to confirm you're not a bot" shows as a plain PadTube message with what to do.

## [0.1.0] - 2026-11-12

First public release (pre-release).

### Added
- Home, search with suggestions, channels, playlists, related videos, comments, history and search history on the iPad.
- Playback up to 720p (H.264 + AAC) through iOS's own player, with a local HLS stream; quality menu; captions; live streams; background audio and the lock screen.
- Optional sign-in with a code (google.com/device): Home, Subscriptions, History, Watch Later, Liked Videos and Playlists of your account; like and Watch Later.
- Light and Dark theme.
- Release files: a rootful jailbreak `.deb` (armv7 + arm64, iOS 6 and later), a rootless jailbreak `.deb` (arm64, iOS 15 and later) and a sideload `.ipa` (armv7 + arm64, iOS 7 and later).

### Known limits
- iOS's own player blocks the main thread for 177 to 326 ms at a video start and for up to 100 ms at a seek (iPad mini 1).
- Playback speed is not offered: the iOS player did not change speed with our stream.
- Web links in descriptions open in Safari. On iOS 6, Safari cannot open some modern sites.

Ran on a real iPad mini 1 on iOS 6.1.3 (jailbroken), driven by a script: the speed gates in the README, and the public build (start, search, play, Light and Dark, a web link to Safari). The 64-bit code, other iOS versions, the rootless package and the sideload steps have not run on a device.
