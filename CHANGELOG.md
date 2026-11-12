# Changelog

## [Unreleased]

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
