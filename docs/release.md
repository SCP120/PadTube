# PadTube public release

Owner order, 2026-11-12: release PadTube on GitHub in the same way as PadTerm. This order replaces the old rule "personal use, never published" (D44).

## 1. Research (2026-11-12)

| Source | What we take |
|---|---|
| PadTerm (github.com/SCP120/PadTerm, v0.1.2) | README layout, `docs/install/` (one guide per route, plus a non-jailbroken guide), CHANGELOG, SECURITY, MIT LICENSE with the holder "<name> contributors", `scripts/check_release.py` with a git-ignored word list, CI (gitleaks + host unit tests), fat armv7 + arm64 packages from `scripts/package_all.sh`, release assets with a `SHA256SUMS.txt` |
| PadTerm `docs/design/ios-version-support.md` | armv7 for iOS 6 to 10 (9.3 SDK, `-mno-thumb`); arm64 with the theos iPhoneOS16.5 SDK; `lipo` into one binary; `ldid -S`. Compile with ARC, link without `-fobjc-arc` (no `libarclite` in Command Line Tools) |
| [TrollStore README](https://github.com/opa334/TrollStore) | Permanent install of an ldid-signed IPA on iOS 14.0 beta 2 to 16.6.1, 16.7 RC (20H18) and 17.0. Never 16.7.x or 17.0.1 and later |
| [Sideloadly FAQ](https://sideloadly.io/faq) | iOS 7 to 26. Since iOS 16, Developer Mode must be on. A free Apple Account signs for 7 days, 3 apps |
| PadTube audit of the tracked tree | No token, no key, no UDID, no LAN address. Problems found: YouTube app screenshots and one photo of the owner's iPad in `docs/design/reference/`; local paths in `docs/research/`; owner test logs in `tests/artifacts/`; the icon option A (red rounded tile, white play triangle) is close to the YouTube logo; the app links the private PadWeb library from `~/padweb` |

## 2. What is published

**Repository:** `github.com/SCP120/PadTube`, public, MIT, holder "PadTube contributors".

**History:** the private repository keeps its history. `scripts/export_public.sh` copies the tracked files, without the private ones, to a separate clean repository (`build/public-repo`). Each release is one commit there (D45). Reason: the private history holds owner reports, test logs and files that the export leaves out, and a rewrite of 56 commits is harder to check than one tree.

**Left out of the public tree:**

| Path | Why |
|---|---|
| `local/` | Owner brief, captured Home feed, probes (already git-ignored) |
| `docs/STATUS.md` | Owner reports, owner actions, test dates |
| `docs/design/reference/` | Screenshots of Google's YouTube apps, and a photo of the owner's iPad |
| `docs/research/` | Local folder paths of research sessions |
| `tests/artifacts/` | Device logs of the owner's iPad |
| `tests/device/joint_padbook.py` | Test with the owner's private app |
| `assets/icons/owner/`, `assets/art/v3/` | Icon option A: owner's build only (section 4) |

## 3. Builds and release assets

| Asset | Code | For | Signed by |
|---|---|---|---|
| `PadTube-<v>-iOS6-jailbreak-rootful.deb` | armv7 + arm64 | Rootful jailbreaks, iOS 6 to 14 (`/Applications`) | ldid |
| `PadTube-<v>-iOS15-jailbreak-rootless.deb` | arm64 | Rootless jailbreaks, iOS 15 and later (`/var/jb/Applications`) | ldid |
| `PadTube-<v>-iOS7-sideload.ipa` | armv7 + arm64 | Not jailbroken: Sideloadly (iOS 7 to 26), TrollStore (iOS 14.0 to 16.6.1, 16.7 RC, 17.0) | the user's tool |
| `SHA256SUMS.txt` | | `shasum -a 256 -c` | |

- armv7: the existing build (9.3 SDK, minimum iOS 6.0, `-mno-thumb`). Runs on 32-bit iPads, iOS 6 to 10.
- arm64: the same source with the iPhoneOS16.5 SDK, minimum iOS 7.0, OpenSSL built for arm64 by `scripts/build_deps_arm64.sh`. iOS 11 and later run only this part.
- The public build has no PadWeb (it is private). In it, a web link in a description opens in Safari. The owner's build keeps PadWeb when `~/padweb` exists and `PUBLIC=1` is not set (D46).
- iPhone: the layout is for iPad. The packages say iPad only.

## 4. Brand

- The public icon is new and drawn by code (`tools/make_public_icon.c`): an old TV set on a teal tile. No red, no play triangle in a rounded tile, no Google logo. Option A stays only in the owner's build (D47).
- The header shows the word "PadTube" in our own type, no YouTube logo (design §6).
- README, install guide and the package text say: "PadTube is not affiliated with, endorsed by or sponsored by Google or YouTube. YouTube is a trademark of Google LLC."

## 5. Release gate (before any push)

`scripts/check_release.py` (from PadTerm, extended) fails on:

1. A key, token or password pattern (private keys, GitHub, Google API key `AIza…`, OAuth refresh token `1//…`, JWT, URL with password).
2. A word of the git-ignored `build/release_denylist.txt`: owner name, iPad UDID and serial number, Wi-Fi names, LAN addresses, Mac names, the owner's YouTube account name.
3. A home path, a LAN address, a `.local` machine name.
4. A file under `local/`, `tests/artifacts/`, `docs/design/reference/`, `docs/STATUS.md`, or a key or credential file name.
5. An image that is not on the list of public images (icons, launch images, README screenshots).
6. Icon option A or the PadWeb library in a package; self-test code in a package; a package older than the newest source; a tar owner that is not root.
7. A git identity that is not a GitHub noreply address.

The gate runs on the export tree and on every file in `dist/`. CI runs gitleaks and the host unit tests on each push.

## 6. Tests (2026-11-12)

| Test | Where | Result |
|---|---|---|
| Host unit tests, private tree | Mac | ✅ 62 of 62 (`scripts/run_tests.sh`: unit, e2e, armv7 binary checks; the owner's build) |
| Host unit tests, **export tree alone** | Mac, `build/public-repo` | ✅ 39 of 39 unit tests; only the built OpenSSL was copied in |
| Release files built from the export tree | Mac | ✅ `scripts/package_all.sh` downloads and checks OpenSSL, builds armv7 (min iOS 6.0) and arm64 (min iOS 7.0), passes the armv7 binary checks; no PadWeb, no local path, public icon |
| Release gate on the export and its `dist/` | Mac | ✅ `scripts/check_release.py`: nothing found. Trap test: 10 of 10 planted problems found (tokens, home path, LAN address, denylist words, a private file, an image, icon option A) |
| gitleaks on the export | Mac | ✅ no leaks, with `.gitleaks.toml` (public YouTube paging tokens only; a planted Google API key is still found) |
| Public build on the iPad mini 1, iOS 6.1.3 | iPad, `ipad-lock`, 2 short sessions | ✅ Self-test copy of the public build (`PUBLIC=1 BUNDLE_ID=dev.padtube.public`, own empty data, the owner's app untouched): start, signed-out Home 20 rows in 1.08 s, search 0.72 s, 720p start 2.28 s and 1.46 s, Light and Dark, landscape, RAM 24.9 MB (peak 36.4 MB), a web link opened Safari and PadTube went to the background; no crash (`tests/device/public_build.py`, `public_shots.py`) |
| The exact release files on a device | none | ⚠️ **Not installed:** they carry the bundle `dev.padtube.app`, so an install would replace the owner's own build. They differ from the tested copy only by the self-test code and the bundle ID |
| arm64, iOS 7 and later, rootless, sideload, TrollStore | none | ⚠️ **Not run**: no 64-bit device. Said in README, install guide, release notes |

## 7. Steps

1. Plan and decisions (this file, D44 to D48).
2. PadWeb switch, public icon, build without `~/padweb`.
3. `build_deps.sh`, `build_deps_arm64.sh`, `package_all.sh`.
4. README, LICENSE, NOTICE (third-party licences), CHANGELOG, SECURITY, CONTRIBUTING, `docs/install/`, issue template, CI.
5. `check_release.py` + denylist + `export_public.sh`.
6. Device tests and screenshots.
7. Gate passes → create the repository, push, publish the release `v0.1.0` (pre-release, like PadTerm) with the assets.
8. X post draft in `local/marketing/x-post-draft.md` (not posted).
