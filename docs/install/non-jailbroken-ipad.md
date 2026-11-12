# Use PadTube on an iPad that is not jailbroken

This guide takes you from a normal iPad to PadTube on the Home Screen. You do not need to jailbreak the iPad.

**Read this first**

- ⚠️ **We have not run these steps.** Our only test iPad is jailbroken and on iOS 6. The steps come from the [Sideloadly FAQ](https://sideloadly.io/faq) and the [TrollStore README](https://github.com/opa334/TrollStore). If they differ, follow those pages, and please send a [device report](https://github.com/SCP120/PadTube/issues/new?template=device-report.yml).
- ⚠️ **PadTube has run only on iOS 6.1.3.** On other versions it is experimental.
- Apple runs an app only if it has a signature from Apple. A tool on your computer signs PadTube with your Apple Account. With a free account the signature lasts **7 days**, and you must then sign again. Your history and sign-in stay.

## 1. Can your iPad do this?

Open **Settings, General, About** and read the version.

| iOS on your iPad | Route |
|------------------|-------|
| 6 | ❌ **No route.** No tool that we know of signs for iOS 6. Update the iPad (see below), or see the [jailbreak route](README.md#2-jailbroken-ipad) |
| 7 to 15 | ✅ [Sideloadly](#3-install-with-sideloadly) |
| 14.0 to 16.6.1, 16.7 RC (20H18), 17.0 | ✅ Also [TrollStore](#4-or-install-with-trollstore): installs once, with no 7-day limit |
| 16 and later | ✅ Sideloadly, after you turn on **Developer Mode** (step 3.9) |

| iPad | Newest iOS it can run |
|------|-----------------------|
| iPad 2, iPad 3, iPad mini 1 | 9 |
| iPad 4 | 10 |
| iPad Air 1, iPad mini 2, iPad mini 3 | 12 |
| Later iPads | see Apple's list |

The second table comes from Apple's public lists; we did not check it again.

**To update an old iPad:** back it up first, then use **Settings, General, Software Update**. An update cannot be undone.

## 2. What you need

| Item | Notes |
|------|-------|
| The file `PadTube-<version>-iOS7-sideload.ipa` | From the [releases page](https://github.com/SCP120/PadTube/releases) |
| A Mac or a Windows PC | It signs the app, and it must be there again every 7 days |
| A USB cable that carries data | A charge-only cable does not work |
| An Apple Account | A free one is enough. A spare account keeps your main one separate |

Sign in with your Apple Account only on a computer that you own.

## 3. Install with Sideloadly

1. Download Sideloadly from [sideloadly.io](https://sideloadly.io/) only.
2. **Windows only:** install iTunes and iCloud from Apple's website, not from the Microsoft Store.
3. Connect the iPad with the cable. On the iPad, tap **Trust** and enter the passcode.
4. Open Sideloadly and drag the `.ipa` into it.
5. Type your Apple Account email and press **Start**. Enter the password when asked.
6. Wait until it says done.
7. On the iPad, open **Settings, General, Device Management** (on some versions **Profiles** or **VPN & Device Management**).
8. Tap your email, then tap **Trust**.
9. **iOS 16 and later:** open **Settings, Privacy & Security, Developer Mode**, turn it on, and let the iPad restart. After the restart, confirm with **Turn On** and your passcode.

PadTube is now on the Home Screen. Go to [step 5](#5-first-start).

## 4. Or install with TrollStore

Only for iOS 14.0 to 16.6.1, 16.7 RC (20H18) and 17.0. TrollStore says that it will never support 16.7.x (other than 16.7 RC) or 17.0.1 and later.

1. Install TrollStore with the guide for your iOS version on its [README](https://github.com/opa334/TrollStore).
2. Open the `.ipa` with TrollStore and tap **Install**.

A TrollStore app has no 7-day limit. If PadTube stops opening after a restart, open TrollStore and use its **Refresh App Registrations**.

## 5. First start

1. Open PadTube. Home shows popular videos.
2. Optional: open the guide (top left), then **Account**, then **Get a sign-in code**. Enter the code at **google.com/device** on another device.
3. **Account** also has the **Light / Dark** theme.

## 6. Every 7 days (Sideloadly with a free account)

The app stops opening after 7 days: it shows a short flash and closes. This is normal, and your data stays.

1. Connect the iPad to the computer.
2. Open Sideloadly and drag in the same `.ipa`.
3. Press **Start**.

A paid Apple Developer account gives one year instead of 7 days.

## 7. When something goes wrong

| What you see | Likely reason | What to do |
|--------------|---------------|------------|
| "Untrusted Developer" | The profile is not trusted | Do step 3, items 7 and 8 |
| The app flashes and closes | The 7 days ended | Do section 6 |
| "Developer Mode required" (iOS 16 and later) | Developer Mode is off | Do step 3, item 9 |
| Sideloadly does not see the iPad | Cable, trust prompt, or iTunes on Windows | Use another cable, tap **Trust**, install iTunes from Apple's site |
| Apple password refused | Your account uses two-factor login | Follow the Sideloadly page on app-specific passwords |
| "Maximum App ID limit" | A free account has 10 new App IDs in 7 days | Wait, or use another Apple Account |
| A limit of 3 apps | A free account has 3 sideloaded apps on iOS 10 and later | Delete one |
| A video does not play, or the layout is wrong | PadTube has not run on your iOS version | Send a [device report](https://github.com/SCP120/PadTube/issues/new?template=device-report.yml) |

Do not paste your sign-in code, tokens or account name in a report.

## 8. Remove PadTube

1. On the iPad, delete the app. Its history, searches and sign-in go with it.
2. If you signed in: in your Google Account, open **Security**, then **Your connections to third-party apps & services**, and remove the YouTube TV access that PadTube used.
