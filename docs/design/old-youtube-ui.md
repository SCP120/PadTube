# Old YouTube for iPad: UI reference for PadTube

Owner rule (2026-11-11): the PadTube UI must match the old official "YouTube" app by Google for iPad, versions 1.x-2.x (September 2012 to 2013). This document gives the references and the values to copy.

Target screen: iPad mini 1, 1024x768 points at 1x, iOS 6. All values in this document are points at 1x. Most iPad references are App Store screenshots at exactly 1024x768. Thus one pixel in those images is one point on the target.

## 1. Version timeline

Data from archive.org copies of the App Store page (`itunes.apple.com/us/app/youtube/id544007664`).

| Version | Date | Change that affects the UI |
|---|---|---|
| 1.0.1.3063 | 2012-09-11 | First release, iPhone only. Dark header, left slide-out guide. |
| 1.1.0.4136 | 2012-12-04 | First iPad layout. App Store iPad screenshots of this version stay the same up to 1.4. |
| 1.3 | 2013-04 | No visible change in the store screenshots. |
| 1.4 | 2013-06-20 | Suggestion overlays at video end, live captions. Cast icon in the header (see `2013-ipad-v14-watch-landscape-1x.png`). |
| 2.0 | 2013-08-20 | New light design: light grey header, red selected row in the guide, picture-in-picture. |
| 2.2.0 | 2013-10-15 | Same store screenshots as 2.0 (the 480 px copies are byte-identical, MD5 check). |

**Decision for the owner.** The owner asks for "the dark/grey header and red accents". Version 1.x has the dark header and a red progress bar. Version 2.x has a light header and a red selected row. This document uses **1.x as the base** (sections 4-10). Section 11 lists the 2.x values as an option. Do not mix the two header styles on one screen.

## 2. Sources

All files are in `reference/` (2.7 MB). They are Google's screenshots, so they are not in the public repository (docs/release.md §2); the links below work only in the private copy. PadTube takes layout sizes from them, not art: it has its own wordmark and icon and no YouTube logo (D47).

| File | Size | Source URL | Version / date | What it shows |
|---|---|---|---|---|
| [2012-ipad-v1-home-landscape.png](reference/2012-ipad-v1-home-landscape.png) | 1024x768, 597 KB | `http://a1.mzstatic.com/us/r1000/116/Purple/v4/55/cf/89/55cf89ce-db9a-8196-191b-d9f3749a3258/mzl.jnnbkgqw.png` (App Store "iPad Screenshot 1", listed in `http://web.archive.org/web/20121207125058/https://itunes.apple.com/us/app/youtube/id544007664?mt=8`) | 1.1, Dec 2012 (no status bar) | **Primary.** Home feed, guide open, header, search field, feed cards. |
| [2012-ipad-v1-watch-landscape.png](reference/2012-ipad-v1-watch-landscape.png) | 1024x768, 560 KB | `http://a1.mzstatic.com/us/r1000/062/Purple/v4/06/ba/5a/06ba5a55-72fb-5134-3c47-f4700ebf1d93/mzl.eukeaunv.png` (App Store "iPad Screenshot 2", same page) | 1.1, Dec 2012 (no status bar) | **Primary.** Watch page landscape: player, controls, About/Comments, info pane, "Suggested Videos" list on the right. |
| [2012-ipad-v1-watch-landscape-statusbar.jpg](reference/2012-ipad-v1-watch-landscape-statusbar.jpg) | 580x435, 50 KB | `https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEgHVfd59APzWWHVG87CsNj2W67x18P4LxKgMKHw6ryk3LXfnvOdoof_arFLwgaukkpkXeirEuuzjS-y3XAaNDVvG74-wzmDMNQBuDSLaEDj14DAnPLU7dG4-1x-Di0EqVmVho3n_A/s0/youtube-ipad-app-video.jpg` (from `https://googlesystem.blogspot.com/2012/12/youtubes-app-for-ipad.html`) | 1.1, Dec 2012 | Watch page while it plays: pause, CC, AirPlay and full screen icons; "Suggested" label; black status bar. |
| [2012-ipad-v1-channel-landscape.jpg](reference/2012-ipad-v1-channel-landscape.jpg) | 580x435, 51 KB | `https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEgHiQfNgr7j-1TaQMJ0oMzcVep-uqAggyUik86iiYzI_Et3VZejWZHC2IYfsb0KbW-UbW931wTggoVCMnkqLIVFGM0PITRgKX5scqxbWPa3y2-Pvk80eKlWn4nG7qPLnf91ebZTug/s0/youtube-ipad-app-channel.jpg` (same blog post) | 1.1, Dec 2012 | Channel page: channel bar, Activity / Videos / Playlists tabs, list rows with the thumbnail on the left. |
| [2012-ipad-v1-search-guide-account.jpg](reference/2012-ipad-v1-search-guide-account.jpg) | 580x435, 54 KB | `https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEiQUQKDXeWHTpmklNl7ryBkuIzQJm8ODywZYoaj6Rzip01aIoyRn72DpZ2ptB4Y2KqyX5uMDA51YKSzolw71yquUeBcH4FtYPLmyvylu5kHCfsHGHZi1280B7ZpeBNO3ROf_8bEHw/s0/youtube-ipad-app-search.jpg` (same blog post) | 1.1, Dec 2012 | Search results (Videos / Channels tabs, filter gear), guide with the Account section open (Uploads, Playlists, Purchases, History, Watch Later, Favorites). |
| [2013-ipad-v14-watch-landscape-1x.png](reference/2013-ipad-v14-watch-landscape-1x.png) | 1024x768, 332 KB | `https://github.com/user-attachments/assets/78e53864-66a9-4554-9fa4-b104d8f2d5e4` (TubeReplacer issue #46, `https://github.com/Preloading/TubeReplacer/issues/46`) | 1.4.0 on iPad 2, iOS 9.3.5, posted 2026-03-28 | True 1x device screenshot with the 20 pt status bar. Confirms the header height. Cast icon, "Subscribe" (not subscribed) button, "Playback error" state. Status bar style is iOS 9, not iOS 6. |
| [2013-ipad-v20-watch-later-guide.jpg](reference/2013-ipad-v20-watch-later-guide.jpg) | 1024x768, 97 KB | `http://web.archive.org/web/20131020204104im_/http://a2.mzstatic.com/us/r30/Purple6/v4/9e/9e/da/9e9eda7f-15b9-1f1a-a6b5-7bd5a8a9805d/screen1024x1024.jpeg` | 2.0, Aug 2013 | 2.x guide with red selected row, light header, list rows, picture-in-picture player. |
| [2013-ipad-v20-watch-landscape.jpg](reference/2013-ipad-v20-watch-landscape.jpg) | 1024x768, 116 KB | `http://web.archive.org/web/20131020204104im_/http://a3.mzstatic.com/us/r30/Purple/v4/91/02/e8/9102e8e0-4224-39f4-f413-ec057589efe5/screen1024x1024.jpeg` | 2.0, Aug 2013 | 2.x watch page: playlist header, channel card, suggestions, comments column. |
| [2013-ipad-v20-playlist.jpg](reference/2013-ipad-v20-playlist.jpg) | 1024x768, 93 KB | `http://web.archive.org/web/20131020204104im_/http://a2.mzstatic.com/us/r30/Purple4/v4/83/74/c6/8374c60d-4edc-01f7-5568-216c15bbe842/screen1024x1024.jpeg` | 2.0, Aug 2013 | 2.x playlist page with "Play All". |
| [2013-ipad-v20-channel.jpg](reference/2013-ipad-v20-channel.jpg) | 1024x768, 118 KB | `http://web.archive.org/web/20131020204104im_/http://a1.mzstatic.com/us/r30/Purple/v4/40/2f/5d/402f5deb-b48d-8e3d-db48-d9de0272b83f/screen1024x1024.jpeg` | 2.0, Aug 2013 | 2.x channel page: banner, ACTIVITY / VIDEOS / PLAYLISTS tabs with red underline. |
| [2012-iphone-v11-home.jpg](reference/2012-iphone-v11-home.jpg) | 577x1024, 149 KB | `http://a1.mzstatic.com/us/r1000/067/Purple/v4/73/86/3c/73863cd5-33ff-fa3a-7992-87af9d376d5c/mzl.btxihkst.png` | 1.1, Dec 2012 (iPhone 5) | Secondary. Feed card with large thumbnail, "uploaded"/"liked" line. |
| [2012-iphone-v11-guide.jpg](reference/2012-iphone-v11-guide.jpg) | 577x1024, 165 KB | `http://a1.mzstatic.com/us/r1000/077/Purple/v4/48/0e/7a/480e7a73-a523-ba18-0cbd-2d773b0753f2/mzl.esnytdcb.png` | 1.1, Dec 2012 | Secondary. Guide slides out from the left and pushes the content to the right. |
| [2012-iphone-v11-watch.jpg](reference/2012-iphone-v11-watch.jpg) | 577x1024, 129 KB | `http://a1.mzstatic.com/us/r1000/076/Purple/v4/52/60/62/52606210-0fa1-63be-9bcd-fecfb38003fa/mzl.idpbdvkv.png` | 1.1, Dec 2012 | Secondary. Portrait watch page: About / Suggested / Comments tabs, like/dislike/share overlay on the video. |
| [2012-iphone-v10-search-suggest.jpg](reference/2012-iphone-v10-search-suggest.jpg) | 682x1024, 130 KB | `http://a1.mzstatic.com/us/r1000/113/Purple/v4/92/a6/76/92a67618-a046-6de7-c16b-7d97e9ce48af/mzl.rdnddeye.png` | 1.0.1, Sep 2012 | Secondary. Search field open, suggestion list with "fill" arrows, mic. |
| [2026-ipad-home-portrait-photo.jpg](reference/2026-ipad-home-portrait-photo.jpg) | 768x1024, 149 KB | `https://github.com/user-attachments/assets/7bab91fe-f7d2-4272-8c8d-186ad225c25f` (TubeReplacer issue #64, `https://github.com/Preloading/TubeReplacer/issues/64`) | Unknown 1.x-2.0, posted 2026-06-15 | Camera photo, glare. Only portrait iPad reference: feed cards fill the width, guide closed. |

Notes on the sources:

- The `mzl.*.png` files are the original App Store uploads. They are still on `a1.mzstatic.com` (checked 2026-11-11). Only the small `320x480`/`480x480` copies are on the archived page.
- The 2.0 full-size files come from archive.org only. The archived App Store page of 2013-08-29 (version 2.0) lists the same four screenshots.
- The TubeReplacer README says the tweak supports app versions 1.0.0-2.0.0. The repository has no screenshots and no wiki pages with images. Only issue attachments had usable images.
- The screenshots contain the YouTube logo and channel art. They are reference material only. Do not copy any part of them into `ios/Resources`. The owner can add `docs/design/reference/` to `.gitignore` if third-party images must stay out of git.

## 3. Method

1. Convert each image to BMP with `sips -s format bmp`.
2. Read pixels with a small Python script (no PIL). The script reports colour runs along a row or a column, the most common colours in a rectangle, and the "ink" bounds of text or icons.
3. Read sizes from the 1024x768 PNG files. Values from JPEG files have an error of about ±3 per colour channel.
4. Font size = cap height / 0.72 (Helvetica Neue cap height is about 0.714 em). Font sizes are thus estimates to ±1 pt.

## 4. Global layout (1.x, landscape 1024x768)

| Area | Frame (x, y, w, h) | Notes |
|---|---|---|
| Status bar | 0, 0, 1024, 20 | iOS 6 black opaque (`UIStatusBarStyleBlackOpaque`). |
| Guide (left menu) | 0, 20, 256, 748 | Open by default in landscape on the home screen. |
| Header bar (content) | 256, 20, 768, 44 | Dark gradient. Same height on the watch page, where it is full width (0-1023). |
| Content | 256, 64, 768, 704 | Light grey `#E6E6E6`. |

The App Store screenshots have no status bar: their header starts at y = 0. The 1.4 device screenshot shows the same header at y = 20-63. Thus the header is 44 pt high below a 20 pt status bar.

Portrait (768x1024): the guide is closed. The content is the full 768 width. The feed card width is then 768 - 2x10 = 748, the same as in landscape (see section 7). The guide opens as a slide-out over or beside the content (iPhone 1.1 pattern: the guide pushes the content to the right, and a 44-56 pt strip of the content stays visible).

## 5. Header bar (1.x)

| Element | Value |
|---|---|
| Height | 44 pt |
| Top line | 1 px `#4E4E4E` (highlight) |
| Fill | Vertical gradient `#313131` (top) to `#232323` (bottom), with a step near the middle: `#313131` y 1-18, `#2A2A2A` y 19-31, `#232323` y 32-42 |
| Bottom line | 1 px `#000000` |
| Shadow on light content | 2 px below the bar: `#939393`, then `#B8B8B8`, then the `#E6E6E6` background |
| Shadow on dark areas | 1 px `#2A2A2A` |
| Guide header (left 256 pt) | Same height. Fill `#363636` (y 0-23) to `#2F2F2F` (y 24-42), bottom line `#191919`, then a 1 px highlight `#585858` |
| Menu button (hamburger) | Icon 25x17 at x = 267 (11 pt from the content edge), y = 13. Three engraved bars, each 3 px fill `#363636` with a 1 px `#000000` line above and below and a 1 px `#555555` highlight under it. Low contrast, "pressed into" the bar. |
| Back button (watch page) | Left arrow, 23x19, at x = 16, y = 11. Colour `#AFAFAF`, with a 1 px black shadow. |
| Title | 1.x shows no text title in the header on home or watch. The wordmark is in the guide header (section 6). |
| Cast icon (1.4 only) | Screen-with-waves outline, about 22x18, light grey, about 230 pt left of the right edge. |

### Search field (in the header, right side)

| Element | Value |
|---|---|
| Frame | x = 776, y = 8, 212x28 (right edge at 987) |
| Shape | Pill, corner radius 14 |
| Fill | `#4D4D4D` |
| Edges | 1 px inner top shade `#434343`, 1 px bottom highlight `#585858` |
| Magnifier glyph | About 11x11 at x = 787, colour `#BCBCBC` |
| Placeholder | "YouTube" in 1.x. For PadTube use "Search". Colour about `#AAAAAA`, Helvetica Neue 15 pt, text starts at x = 809 |
| Microphone | Glyph 16x24 at x = 998, y = 10, colour `#B6B6B6`, black 1 px shadow. PadTube has no voice search: leave the space empty or omit the glyph. |

### Search suggestions (iPhone 1.0 only, no iPad reference)

White list under the field. Rows about 36 pt, text dark grey (`#474747`), Helvetica Neue 15 pt. A "fill" arrow icon (up-left diagonal) at the right end of each row. 1 px light grey separators.

## 6. Guide (left slide-out menu, 1.x)

| Element | Value |
|---|---|
| Width | 256 pt |
| Right edge | 6 px inner shadow: `#2D2D2D`, `#242424`, `#171717` (2 px each) next to the content |
| Header | 44 pt, wordmark centered (ink box in 1.x: 74x31 at x = 91, y = 6) |
| Section header | 22 pt high. Top line 1 px `#575757`, fill `#414141` to `#494949`, bottom line `#313131`. Text left at x = 10, Helvetica Neue 14 pt, `#AFAFAF`, 1 px black shadow above. Sections in 1.x: "Account", "Subscriptions" (iPhone: "Channels"), "From YouTube". |
| Row | 47 pt + 1 px dark line `#222222` + 1 px light line `#555555` = 49 pt pitch |
| Row fill | `#383838` (some rows `#373737` or `#393939`; treat as one colour) |
| Avatar | 30x30 at x = 10, centered in the row, corner radius 2 |
| Icon | 26x26 at x = 13, colour `#B0B0B0`, black 1 px shadow |
| Row text | x = 50, Helvetica Neue 17 pt (cap height 12), colour about `#AAAAAA`, 1 px black shadow |
| Selected row | Fill `#1E1E1E`, line above `#171717`. Text and icon `#FFFFFF`. No red in 1.x. |
| Count badge | 31x26 at right inset 10 (x = 215). Fill gradient `#DBDBDB` to `#AEAEAE`, 1 px white top highlight, 1 px `#000000` border, corner radius 3. Text `#1D1D1D`, Helvetica Neue Bold 14 pt, centered. |

Rows in the 1.x iPad guide (from the references):

- Account: avatar + user name, Uploads, Playlists, Purchases, History, Watch Later, Favorites, Settings, Add Channels.
- Subscriptions: Home Feed (house icon), then one row per channel with its avatar and an unread count badge.
- From YouTube: Popular (star icon), then categories (Film & Animation, Autos & Vehicles, ...).

PadTube wordmark placeholder: do **not** copy the YouTube logo (no "Tube" text in a red rounded box, no play triangle in red). Draw the plain word "PadTube" in white, `HelveticaNeue-Bold` 20 pt, centered in the 256x44 guide header, with a 1 px black shadow above. A small red mark is optional: a 4x16 bar in the accent red (section 10) left of the word.

## 7. Video lists (1.x)

### 7.1 Home feed card (thumbnail on the right)

Content background: `#E6E6E6`.

| Element | Value |
|---|---|
| Card frame | x = 10 from the content edge (266 on screen), width 748, height 193 |
| Card pitch | 213 (gap 18 + 2 px shadow) |
| First card top | 12 pt under the header bottom (y = 56 in the screenshot) |
| Card fill | Light grey paper texture, values `#F0F0F0`-`#FAFAFA` (mean about `#F5F5F5`). Use a small pre-rendered noise tile or a flat `#F5F5F5`. |
| Card edges | 1 px `#D8D8D8` left and right. Bottom: 1 px `#BEBEBE`, then 1 px `#D9D9D9`. No top line. Square corners. |
| Thumbnail | 313x193, flush with the card top, right and bottom edges. Aspect about 1.62: crop the 16:9 image at the sides. Square corners. |
| Duration badge | About 44x23, bottom-right of the thumbnail, inset 10 right and 10 bottom. Fill black about 80% opacity, square corners. Text white, Helvetica Neue 14 pt (digit height 10). |
| Actor avatar | 36x36 at card x + 10, y + 15, corner radius 2 |
| Actor name | x = card + 56, `#333333`, Helvetica Neue 16 pt |
| Action line | "uploaded" / "liked" / "recommends" in `#666666`, then " • 1 minute ago" in `#999999`. Helvetica Neue 13 pt. |
| Divider | y = card + 66, from card x + 10 to the thumbnail minus 10. 1 px `#E5E5E5` with 1 px `#FFFFFF` below (etched line). |
| Video title | One line with "..." at the end. `#333333`, Helvetica Neue 18 pt (cap height 13), x = card + 56, centered near card y + 101 |
| Channel line | `#333333`, Helvetica Neue 14 pt. A 30x30 avatar is shown left of it when the actor is not the uploader. |
| Views line | "138,567 views", `#666666`, Helvetica Neue 14 pt |

### 7.2 Search results and channel video list (thumbnail on the left)

From the blog screenshots (580x435, scale 0.566; values are converted to points, ±3 pt).

| Element | Value |
|---|---|
| Sub-bar under the header | 44 pt, dark, with a centered 2-segment control: "Videos / Channels" (search) or 3 segments "Activity / Videos / Playlists" (channel). Same style as the About/Comments control (section 8.3). A gear icon (filters) at the right end on the search page. |
| Row card | Same card style as 7.1, about 155 pt high, inset 10 from the content edges |
| Thumbnail | About 276x155 (16:9), flush with the card left edge |
| Title | `#333333`, Helvetica Neue 16-17 pt, to the right of the thumbnail, inset about 12 |
| Channel line | 20x20 avatar + name `#333333`, views under it `#666666` |
| Channel page header | Channel bar: avatar 44x44, name 18 pt, subscriber count 13 pt `#666666`, and a "Subscribed" button on the right (section 9). |

### 7.3 Related ("Suggested Videos") rows on the watch page

| Element | Value |
|---|---|
| Panel | x = 768, w = 256, full height under the header. Fill `#363636`. Left edge 2 px `#262626`/`#2C2C2C`. |
| Panel title | "Suggested Videos" (1.1 store) or "Suggested" (blog). White `#FFFFFF`, Helvetica Neue 17 pt, x = 780, cap top at y = header + 13 |
| Row card | 236x64 at x = 778. First card at y = header + 40 (84 in the screenshot). Pitch 74. |
| Card fill | `#F6F6F6`, 1 px `#FFFFFF` top highlight, 2 px `#2C2C2C` shadow under it. Square corners. |
| Thumbnail | 104x64, flush left, top and bottom. Crop to fill. |
| Duration badge | About 40x19, bottom-right of the thumbnail, black about 80% opacity, white Helvetica Neue 13 pt |
| Title | Two lines max, `#252525`, Helvetica Neue 14 pt, x = 888 (10 pt right of the thumbnail) |
| Views | `#686868`, Helvetica Neue 12 pt, under the title |

## 8. Watch page (1.x)

### 8.1 Landscape (reference: `2012-ipad-v1-watch-landscape.png`)

The guide is closed. The header is full width (back arrow on the left, search field on the right).

| Area | Frame (x, y from screen top with status bar, w, h) |
|---|---|
| Header | 0, 20, 1024, 44 |
| Player | 0, 64, 768, 432 (exactly 16:9) |
| Control bar (over the video) | 0, 445, 768, 51 (the bottom 51 pt of the player) |
| Tab bar | 0, 496, 768, 44 |
| Info pane | 0, 541, 768, 227 |
| Related panel | 768, 64, 256, 704 |

Player background: `#000000`. Error text ("Playback error"): white, Helvetica Neue 18 pt, centered in the player.

### 8.2 Player controls (1.x)

| Element | Value |
|---|---|
| Control bar fill | Black-grey gradient over the video: `#2A2A2A` at about 73% opacity (top) to `#1E1E1E` at about 76% (bottom). Values come from the blend over a known video colour. |
| Left button | Play / pause / replay glyph, white, 20x20, at x = 17, centered vertically |
| Elapsed time | "3:30", white, Helvetica Neue 15 pt, at x = 55 |
| Track | x = 94 to about 676, 11 pt high, centered in the bar |
| Played part | Red vertical gradient `#D9000E` (top) to `#7D0109` (bottom) |
| Buffered part | `#808080` |
| Unplayed part | `#201F21` |
| Knob | Circle about 24 pt, light grey gradient (`#F6F6F6` top, `#BABABA` middle, `#FDFDFD` lower rim), 1 px dark outline |
| Remaining / total time | "1:00", white, Helvetica Neue 15 pt, right of the track |
| Right buttons | CC (boxed "CC", 2012 blog), AirPlay (screen + triangle), full screen (four corner arrows, 18x18, white). Full screen sits at x = 732. |

Do not copy the 1.4/2.0 suggestion overlays at the video end.

### 8.3 Tab bar ("About" / "Comments")

| Element | Value |
|---|---|
| Bar | 44 pt. Top line `#5D5D5D`, fill `#474747` (top) to `#383838` (bottom), bottom lines `#1D1D1D` then `#8A8A8A` |
| Segmented control | 298x30, centered on the player (x = 236 to 533), 2 equal segments, corner radius 2 |
| Selected segment | Inset look: gradient `#1A1A1A` to `#282828`, 1 px `#131313` top line. Text `#FFFFFF`. |
| Normal segment | Flat `#363636`, 1 px `#252525` top line and `#232323` bottom line. Text `#BCBCBC`, 1 px black shadow. |
| Under the control | 1 px highlight `#515151` |
| Text | Helvetica Neue 15 pt, centered |

The 1.x iPad watch page has only "About" and "Comments". The related list is always on the right in landscape. There is no "More from" tab in any 1.x-2.0 reference. For "More from this channel", use the channel page.

### 8.4 Info pane ("About" tab)

Background `#E6E6E6`. Two columns, divided by a 1 px vertical line `#B8B8B8` at x = 511.

Left column (x = 0-510, text inset 20):

| Element | Value |
|---|---|
| Title | `#333333`, Helvetica Neue 20 pt, top at pane + 19, up to 2 lines |
| Upload date | "Uploaded Feb 23, 2012", `#666666`, Helvetica Neue 15 pt |
| Action buttons | Three buttons (like, dislike, share), each 36x28, at x = 19, 71, 123 (gap 16). Fill gradient `#FCFCFC` to `#E1E3E7`, 1 px `#BCBBBC` border, 1 px `#FFFFFF` highlight under the bottom edge, corner radius 2. Glyph grey `#D3D3D3`-`#999999`; active "like" glyph blue `#5474CF`. |
| View count | "34,819,387 views", `#333333`, Helvetica Neue 16 pt |
| Like bar | 161x4 at x = 20. Likes part green `#006600` (top 1 px `#004200`), dislikes part red `#D10103`. 1 px `#FFFFFF` line under it. |
| Like text | "508,012 likes, 7,638 dislikes": numbers `#222222`, words `#666666`, Helvetica Neue 14 pt |
| Description | `#333333`, Helvetica Neue 14 pt, links `#3361CC` (no underline) |
| Scroll indicator | Standard iOS dark indicator at the right side of the column |

Right column (x = 512-767):

| Element | Value |
|---|---|
| Channel avatar | 50x50 at x = 530, top at pane + 19, corner radius 2 |
| Channel name | `#333333`, Helvetica Neue 18 pt, x = 590 |
| Subscribers | "1,010,094 subscribers", `#666666`, Helvetica Neue 14 pt |
| Subscribe button | 152x38 at x = 529, about 38 pt under the avatar. Same light gradient and border as the action buttons. Subscribed: green check circle 26x26 `#53A653` with a white check, text "Subscribed" `#666666` 16 pt. Not subscribed (1.4): blue plus circle 24x24, gradient `#638BE0` (top) to `#5175C5` (bottom), white plus, text "Subscribe". |

### 8.5 Portrait watch page (no iPad reference)

No 1.x iPad portrait screenshot was found. Use the iPhone 1.1 pattern, scaled to 768 wide:

- Player at the top: 768x432 under the header.
- Tab bar with three segments: "About / Suggested / Comments" (iPhone 1.1 has exactly these). Segmented control about 450x30, same style as 8.3.
- The tab content fills the rest (768x484). "Suggested" uses the related row style of 7.3, with wider cards (748 wide, thumbnail 104x64 or larger).

Mark this layout as "derived" in the design review. Ask the owner if a real portrait photo appears later.

## 9. Buttons and accent colours

| Use | Colour |
|---|---|
| Progress bar played part (1.x accent) | `#D9000E` to `#7D0109` gradient |
| Dislike part of the like bar | `#D10103` |
| Like part of the like bar | `#006600` |
| Subscribed check | `#53A653` |
| Links | `#3361CC` |
| Liked glyph | `#5474CF` |
| Light button | Fill `#FCFCFC` to `#E4E4E4`, border `#BCBBBC`, white 1 px under the bottom |
| Count badge | `#DBDBDB` to `#AEAEAE`, border `#000000` |
| 2.x selected row / tab underline | `#CD1A18` / `#CE312E` (section 11) |

Red appears in 1.x only in the progress bar and the dislike bar. If the owner wants more red in 1.x style, use `#CD1A18` for the selected guide row (2.x pattern) and keep the dark header.

## 10. Dark and light areas, fonts, icons

### 10.1 Dark vs light

| Area | Tone |
|---|---|
| Header, guide, tab bar, related panel, control bar | Dark (`#232323`-`#494949`) |
| Feed, search and channel lists, info pane | Light (`#E6E6E6` background, `#F5F5F5`/`#F6F6F6` cards) |
| Player | Black |

### 10.2 Fonts

iOS 6 has Helvetica and Helvetica Neue. The glyph shapes in the references (double-storey "a", straight-leg "R", round dots) match Helvetica Neue. The stroke weight matches `HelveticaNeue` (regular). Test `HelveticaNeue-Light` for the video titles on the device and keep the closer match.

| Text | Font | Size | Colour |
|---|---|---|---|
| Video title in feed | HelveticaNeue | 18 | `#333333` |
| Video title on watch page | HelveticaNeue | 20 | `#333333` |
| Related title | HelveticaNeue | 14 | `#252525` |
| Channel / actor name | HelveticaNeue | 16 | `#333333` |
| Metadata (views, date) | HelveticaNeue | 13-14 | `#666666`, time-ago `#999999` |
| Guide row | HelveticaNeue | 17 | `#AAAAAA`, selected `#FFFFFF` |
| Guide section header | HelveticaNeue | 14 | `#AFAFAF` |
| Panel title "Suggested Videos" | HelveticaNeue | 17 | `#FFFFFF` |
| Segmented control | HelveticaNeue | 15 | `#FFFFFF` / `#BCBCBC` |
| Duration badge | HelveticaNeue | 13-14 | `#FFFFFF` |
| Badge count | HelveticaNeue-Bold | 14 | `#1D1D1D` |
| Wordmark "PadTube" | HelveticaNeue-Bold | 20 | `#FFFFFF` |

Text on dark areas has a 1 px black shadow (offset 0, -1). Text on light areas has no shadow.

### 10.3 Icons (draw them ourselves)

Draw all icons as code (Core Graphics) or as our own PNG files. Do not copy icon images from the app.

| Icon | Shape to draw | Size | Colour |
|---|---|---|---|
| Menu | Three horizontal bars, engraved (section 5) | 25x17 | `#363636` with black lines and `#555555` highlight |
| Back | Left arrow: a horizontal stroke with a 90° arrow head, 3 pt stroke | 23x19 | `#AFAFAF` |
| Search | Circle (lens) with a short handle to the lower right | 11x11 in the field | `#BCBCBC` |
| Home | House: square base, triangle roof, small door gap | 26x26 | `#B0B0B0` / white when selected |
| Settings | Gear with 8 teeth and a center hole | 26x26 | `#B0B0B0` |
| Add channels | Circle with a plus inside | 26x26 | `#B0B0B0` |
| Popular | Five-point star | 26x26 | `#B0B0B0` |
| Category (film) | Film reel: circle with 5 small holes | 26x26 | `#B0B0B0` |
| History / Watch later | Clock face | 26x26 | `#B0B0B0` |
| Like / dislike | Thumb up / thumb down outline with filled cuff | 16x16 in a 36x28 button | grey, liked `#5474CF` |
| Share | Box with an arrow out of the top right | 16x16 | grey |
| Play / pause / replay | Triangle / two bars / circular arrow | 20x20 | white |
| Full screen | Four short arrows to the corners | 18x18 | white |
| Subscribed | Circle `#53A653` with a white check | 26x26 | |

## 11. Option: 2.x light style (Aug 2013)

Use only if the owner chooses 2.x. Values come from JPEG files (±3 per channel).

| Element | Value |
|---|---|
| Header | 44 pt, gradient `#FBFBFB` (top) to `#EDEDED`, top line `#E2E2E2`, bottom line `#DBDBDB`, then 1 px `#C5C5C5` shadow. Centered title (for example "Watch Later"), `#393939`, 17 pt (cap height 12). Menu glyph light grey, search magnifier `#666666` on the right (no search field in the bar). |
| Guide | Width 340, rows 49 pt pitch, fill `#303030`-`#333333`, section headers in capitals ("ACCOUNT", "SUBSCRIPTIONS") 10 pt `#6C6C6C` on `#222222` |
| Selected guide row | Fill `#CD1A18`, white text and icon |
| List | White cards on `#EDEDED`, thumbnail about 232x131 on the left, title 17 pt `#333333`, "⋮" overflow at the top right |
| Channel tabs | Capitals "ACTIVITY / VIDEOS / PLAYLISTS", 13 pt grey, selected tab has a 2 px red underline `#CE312E` |
| Buttons | Flat light grey "SUBSCRIBE" / "SUBSCRIBED" with a small icon |

## 12. Elements without a reference

| Element | Status |
|---|---|
| iPad portrait watch page | ❌ No reference. Section 8.5 is derived from the iPhone 1.1 layout. |
| iPad portrait home | ⚠️ Only a camera photo with glare (2026). Card style matches the landscape card. |
| Search suggestion list on iPad | ⚠️ iPhone 1.0 only. |
| "Comments" tab content on the iPad 1.x | ❌ Not shown. 2.0 shows comments in the right column. |
| "More from" tab | ❌ Not in any 1.x-2.0 reference. Use the channel page. |
| Loading state (spinner, empty list) | ⚠️ The 1.4 photo shows a white iOS spinner on the dark related panel. No other reference. |
| Settings, sign-in, quality menu | ❌ No reference found. |
| Exact font names | ⚠️ Inferred from glyph shapes, not read from the app. |

## 13. Smoothness limits

These rules keep the scroll gate of 55 fps on the iPad mini 1 (A5, iOS 6).

- Do not use blur of any kind.
- Do not use `CALayer` shadows unless `shadowPath` is set. Draw the card shadows (section 7) as 1 px lines in the cell image or as plain views.
- Do not use `mask`, `masksToBounds` or `cornerRadius` on cells or on views inside cells. Draw the 2 pt avatar corners into the bitmap after the download.
- Draw gradients (header, guide section header, tab bar, buttons, badge) only as pre-rendered stretchable images (`resizableImageWithCapInsets:`). Do not use `CAGradientLayer` in cells.
- Make the paper texture of the cards a small opaque tile, or use the flat colour `#F5F5F5`.
- Set `opaque = YES` and an opaque background colour on all cell views.
- Pre-render text shadows only on fixed labels. Do not set `shadowOffset` on labels inside table cells.

## 14. Dark theme (owner 2026-11-12)

No 2012 reference has a dark content area, so this theme is **derived**: the 1.x dark chrome (header, guide,
tab bar, segments, related panel, player bar) stays as it is, and the light areas take the tones of that chrome.
The shapes, lines and gradients stay the same; only the tones change.

| Element | Light (§7-§9) | Dark |
|---|---|---|
| Content background | `#E6E6E6` | `#1B1B1B` |
| Card fill (feed, list, grid, info pane) | `#F5F5F5` | `#2A2A2A` |
| Card side lines / bottom lines | `#D8D8D8` / `#BEBEBE`, `#D9D9D9` | `#333333` / `#111111`, `#1B1B1B` |
| Title text / secondary / tertiary | `#333333` / `#666666` / `#999999` | `#E4E4E4` / `#A8A8A8` / `#7E7E7E` |
| Link | `#3361CC` | `#7FA7F2` |
| Thumbnail placeholder | `#CFCFCF` | `#3A3A3A` |
| Rule under a row | `#E5E5E5` + white | `#333333` + `#151515` |
| Light button (Subscribe, Watch Later, ...) | `#FCFCFC` -> `#E1E3E7`, border `#BCBBBC`, text `#444444` | `#4A4A4A` -> `#383838`, border `#151515`, text `#E0E0E0` |
| Related card on the dark panel | `#F6F6F6`, title `#252525`, meta `#686868` | `#2E2E2E`, title `#E4E4E4`, meta `#A0A0A0` |
| Related panel (landscape right column) | `#363636` | `#232323` |
| Suggested tab in portrait (content area) | paper card on `#E6E6E6` | paper card on `#1B1B1B` (no dark panel: no dark bands between rows) |
| Search suggestions list | white, rule `#DDDDDD` | `#2A2A2A`, rule `#3A3A3A` |
| Keyboard (search field in the dark header) | dark ("alert" appearance) | dark |
| QR code on the sign-in screen | black on white | black on white (cameras need it) |
