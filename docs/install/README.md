# Install guide

PadTube runs on **iPad, iOS 6 and later**. It needs no computer after the install, no server and no account. A YouTube sign-in is optional.

**What has been tested**

| Part | State |
|------|-------|
| iPad mini 1, iOS 6.1.3, jailbroken | ✅ Start, Home, search, playback up to 720p, background audio, Light and Dark, links, with the speed gates of the README. A script drives the screen in these tests: no finger test |
| Any other iPad or iOS version (all 64-bit code) | ⚠️ **Experimental: never run on a device.** Built and checked on a Mac only. Please send a [device report](https://github.com/SCP120/PadTube/issues/new?template=device-report.yml) |
| The rootless package, the sideload steps, TrollStore | ⚠️ Not run by us |

## 1. Pick your route

Open **Settings, General, About** on the iPad and read the version.

| Your iPad | Route | File |
|-----------|-------|------|
| Not jailbroken, iOS 7 or later | **[Step-by-step guide for a non-jailbroken iPad](non-jailbroken-ipad.md)** (Sideloadly; TrollStore on some versions) | `PadTube-<version>-iOS7-sideload.ipa` |
| Rootful jailbreak, any iOS from 6 (apps in `/Applications`) | [Jailbreak route](#2-jailbroken-ipad) | `PadTube-<version>-iOS6-jailbreak-rootful.deb` |
| Rootless jailbreak, iOS 15 or later (apps in `/var/jb/Applications`, for example Dopamine or palera1n rootless) | [Jailbreak route](#2-jailbroken-ipad) | `PadTube-<version>-iOS15-jailbreak-rootless.deb` |
| Not jailbroken, iOS 6 | **No known route.** Update the iPad and sideload, or jailbreak it | |

Get the files from the [releases page](https://github.com/SCP120/PadTube/releases). Check them: `shasum -a 256 -c SHA256SUMS.txt`.

The `.ipa` and the rootful `.deb` hold two kinds of code: 32-bit code for iPad 2, 3, 4 and mini 1 (iOS 6 to 10), and 64-bit code for iPad Air, iPad mini 2 and later (iOS 7 and later). iOS picks the right one. **iPhone is not supported:** the app is for iPad only.

## 2. Jailbroken iPad

This guide gives no jailbreak steps. For your device see https://ios.cfw.guide/ and https://theapplewiki.com/ .

1. Copy the `.deb` for your jailbreak type to the iPad, or download it there.
2. Install it with your package manager (Cydia, Sileo, Zebra), or with `dpkg -i <file>` as root.
3. If the icon does not show, run `uicache` (or restart SpringBoard).

An iPad that accepts unsigned apps through the normal install service (the iOS 6 test iPad does) can also install from a Mac over USB: `brew install libimobiledevice ideviceinstaller`, then `scripts/ipad_deploy.sh <file.deb>`. Install a new version on top of the old one; do not uninstall first.

## 3. First start

1. Open PadTube. Home shows popular videos.
2. Optional: tap the guide button (top left), then **Account**, then **Get a sign-in code**. Enter the code at **google.com/device** on a phone or computer. Your Home, Subscriptions, History, Watch Later, Liked Videos and Playlists then show your account. No password is typed on the iPad.
3. **Account** also has the **Light / Dark** theme.

## 4. Routes that do not work

| Route | Why |
|-------|-----|
| App Store, TestFlight | They need a current Xcode build and App Review. None exists |
| Enterprise certificates | They are for a company's own staff. Apple revokes certificates sold to the public |
| iPhone | The app is for iPad only |

## 5. Build it yourself

See [the README](../../README.md#build-macos-apple-silicon-command-line-tools-only).
