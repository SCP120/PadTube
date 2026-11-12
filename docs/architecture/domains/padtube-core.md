# PadTube Core Domain

**Version:** 1.0 · **Date:** 2026-11-11 · **Status:** Approved (owner, 2026-11-11)

This document describes the components of PadTube and their data model. It describes the code that exists in `core/` and `ios/src/` (Phase 0 spike, [D4](../../decisions.md)). The use cases give the behavior: [BUC-WATCH-A-VIDEO](../../use_cases/business/watch-a-video.md), [BUC-SIGN-IN-WITH-CODE](../../use_cases/business/sign-in-with-code.md) and the DUCs under [docs/use_cases/domain/](../../use_cases/domain/).

PadTube is one app on one iPad. There are no services and no API between services. The bounded contexts below are modules in one process with a C API between them.

---

## 1. Bounded Contexts

| Context | Code | Responsibility | Use cases |
|---------|------|----------------|-----------|
| **net** | `core/tb_http.*` | HTTPS / HTTP client on OpenSSL; keep-alive pool per host; gzip; chunked; redirects; Range; cancel flag; counters. Blocking and thread safe. | all |
| **json** | `core/tb_json.*` + yyjson | Path helpers on yyjson; InnerTube text (`simpleText`, `runs`) to C string. | all |
| **innertube** | `core/tb_yt.*` | InnerTube client: MWEB for lists, VISIONOS for playback, TVHTML5 + token for the account. Visitor ID cache. Field masks. Parsers for lists, player, next, comments, captions. | [search](../../use_cases/domain/search/search.md), [playback](../../use_cases/domain/playback/start.md), [captions](../../use_cases/domain/captions/show.md), [library](../../use_cases/domain/library/browse.md), [video page](../../use_cases/domain/video-page/load.md), [history](../../use_cases/domain/history/record.md) |
| **stream / remux** | `core/tb_mp4.*`, `core/tb_ts.*`, `core/tb_stream.*` | fMP4 reader (init, sidx, one fragment); MPEG-TS writer (H.264 Annex B + AAC ADTS); one playback = DASH formats → HLS playlists and TS segments, 1 fragment = 1 segment; segment cache; one background prefetch. | [playback](../../use_cases/domain/playback/start.md) |
| **hls server** | `core/tb_hls.*` | HTTP server on 127.0.0.1 for the iOS player; serves the current stream by generation; refcount per request; never blocks the caller. | [playback](../../use_cases/domain/playback/start.md) |
| **store** | `core/tb_store.*` | SQLite 3.7.13 in WAL mode: watch history with resume position, recent searches, key/value settings. One mutex; one transaction per action. | [history](../../use_cases/domain/history/record.md), [search](../../use_cases/domain/search/search.md), [sign-in](../../use_cases/domain/account/sign-in.md) |
| **oauth** | `core/tb_oauth.*` | Google OAuth 2.0 device flow with the TV client ID from the TV `base.js`; poll; refresh. | [sign-in](../../use_cases/domain/account/sign-in.md) |
| **Objective-C layer** | `ios/src/*` | Thin UIKit layer: wrappers that run the C calls on a background queue and call back on the main queue; screens; player view; captions label; image loader; theme. | all |

### Name map (diagram name → code)

The diagrams use snake_case names. The Objective-C classes map as below.

| Diagram name | Code |
|--------------|------|
| `ui_core` | `TBCore` (+ `TBItem`, `TBPage`, `TBPlayerInfo`, `TBNextInfo`, `TBFormat`, `TBCaptionTrack`, `TBCue`) |
| `ui_account` | `TBAccount` |
| `ui_store` | `TBStore` |
| `ui_list_controller` | `TBListController` (+ `TBRouter`), `TBSearchController`, `TBLibraryController` |
| `ui_watch_controller` | `TBWatchController` |
| `ui_player_view` | `TBPlayerView` |
| `ui_comments_controller` | `TBCommentsController` |
| `ui_image_loader` | `TBImageLoader` |
| `mp_player` | `MPMoviePlayerController` (iOS) |

---

## 2. Component Class Diagram

```mermaid
classDiagram
    direction LR
    class tb_http {
        +init(ca_file) int
        +request(tb_req) tb_resp
        +close_idle()
        +get_stats() tb_http_stats
    }
    class tb_yt {
        +init(state_dir) int
        +set_token(access_token)
        +search(query, continuation, params) tb_list
        +suggest(q) string_list
        +player(video_id) tb_player
        +next(video_id) tb_next
        +channel(channel_id, tab_params, continuation) tb_list
        +playlist(playlist_id, continuation) tb_list
        +comments(token) tb_comments
        +captions(base_url) tb_captions
        +tv_browse(browse_id, continuation) tb_list
        +like(video_id, action) int
        +subscribe(channel_id, on) int
        +playlist_edit(playlist_id, video_id, add, set_video_id) int
        +tracking(video_id) ping_urls
        +ping(url) int
    }
    class tb_mp4 {
        +init(bytes) tb_track
        +sidx(bytes, file_offset) tb_sidx
        +frag(bytes, track) tb_frag
    }
    class tb_ts {
        +segment(video_input, audio_input) tb_out
    }
    class tb_stream {
        +new(videos, nv, audio) tb_stream
        +playlist(vi) string
        +master(order, n) string
        +segment(vi, seg) tb_out
        +prefetch(vi, seg)
        +cancel()
        +retain()
        +release()
        +free()
    }
    class tb_hls {
        +start() int
        +set(stream, order, n) int
        +url(vi, master) string
        +get_stats() tb_hls_stats
    }
    class tb_store {
        +open(path) int
        +history_add(video_id, title, channel, length) int
        +history_position(video_id, position) int
        +history_get_position(video_id) double
        +history_list(limit) tb_hist_list
        +history_remove(video_id) int
        +search_add(q) int
        +search_list(limit) string_list
        +set(key, value) int
        +get(key) string
    }
    class tb_oauth {
        +get_client() tb_oauth_client
        +parse_client(js) tb_oauth_client
        +device_code(client, device_id) tb_device_code
        +poll(client, device_code) tb_token
        +refresh(client, refresh_token) tb_token
    }
    class ui_core
    class ui_account
    class ui_store
    class ui_list_controller
    class ui_watch_controller
    class ui_player_view
    class ui_comments_controller
    class ui_image_loader
    class mp_player

    tb_yt --> tb_http : uses
    tb_oauth --> tb_http : uses
    tb_stream --> tb_http : fetches media
    tb_stream --> tb_mp4 : parses
    tb_stream --> tb_ts : writes
    tb_hls --> tb_stream : serves
    ui_core --> tb_yt : calls on background queue
    ui_account --> tb_oauth : device flow
    ui_account --> tb_yt : set_token, like, subscribe, ping
    ui_account --> ui_store : tokens
    ui_store --> tb_store : wraps
    ui_list_controller --> ui_core : pages
    ui_watch_controller --> ui_core : player and next
    ui_watch_controller --> ui_store : history and position
    ui_watch_controller --> ui_player_view : owns
    ui_watch_controller --> ui_comments_controller : opens
    ui_player_view --> tb_stream : creates
    ui_player_view --> tb_hls : set current stream
    ui_player_view --> mp_player : owns
    mp_player --> tb_hls : HTTP 127.0.0.1
    ui_image_loader --> tb_http : thumbnails
```

### Component rules

| Rule | Description | Source |
|------|-------------|--------|
| Threads | `ui_core` runs every network call on the concurrent queue `padtube.net` and calls back on the main queue. The HLS server serves each request on its own thread. `tb_stream_prefetch` runs on its own thread. | `ios/src/TBCore.m`, `core/tb_hls.c`, `core/tb_stream.c` |
| One current stream | `tb_hls_set` makes one stream current and increments the generation. A request for an old generation gets 404. The server holds one reference per request; `tb_hls_set` never blocks. | BR-PLAY-ONE, [D12](../../decisions.md) |
| Client per call | MWEB: search, next, comments, channel, playlist, visitor ID. VISIONOS: player. TVHTML5 + Bearer: TV browse, like, subscribe, playlist edit, tracking. | BR-LOGIN-TV, [research-features §2 F1, F6](../../research/research-features.md#2-facts-for-2026-that-set-the-design) |
| Masks | Field masks on search, player and next, with a no-mask fallback for search and next. | BR-NET-MASK, [D10, D15](../../decisions.md) |
| Connections | One keep-alive pool per host. iOS 6 has no TLS session tickets, so connection reuse is necessary. `tb_http_close_idle` drops idle connections on a memory warning. | [research-efficiency §6](../../research/research-efficiency.md#6-network) |
| Memory warning | Clear the image RAM cache and close idle connections. | `ios/src/TBAppDelegate.m` |
| Background audio | AVAudioSession category Playback, `UIBackgroundModes=audio`, remote-control events, `MPNowPlayingInfoCenter`. The process and the local server stay alive while audio plays. | [research-features §4.2](../../research/research-features.md#42-background-audio) |

---

## 3. Sequence: Tap Video → First Frame

```mermaid
sequenceDiagram
    actor owner
    participant ui_list_controller
    participant ui_watch_controller
    participant ui_core
    participant tb_yt
    participant youtube_api
    participant ui_store
    participant ui_player_view
    participant tb_stream
    participant tb_hls
    participant mp_player
    participant googlevideo

    owner->>ui_list_controller: tap_row(video_id)
    ui_list_controller->>ui_watch_controller: init_with_video_id(video_id) and t0 = now
    par player request
        ui_watch_controller->>ui_core: player(video_id)
        ui_core->>tb_yt: tb_yt_player(video_id)
        tb_yt->>youtube_api: POST /youtubei/v1/player VISIONOS masked
        youtube_api-->>tb_yt: status, formats, captions, details
        tb_yt-->>ui_core: tb_player
        ui_core-->>ui_watch_controller: got_player(info) on main queue
    and watch page request
        ui_watch_controller->>ui_core: next(video_id)
        ui_core->>tb_yt: tb_yt_next(video_id)
        tb_yt->>youtube_api: POST /youtubei/v1/next MWEB masked
        youtube_api-->>tb_yt: page data
        ui_core-->>ui_watch_controller: got_next(next) on main queue
    end
    ui_watch_controller->>ui_store: add_history(video_id, title, channel)
    ui_watch_controller->>ui_store: position_of(video_id)
    ui_watch_controller->>ui_player_view: play_video(video_id, info, t0, start_at)
    ui_player_view->>tb_stream: tb_stream_new(avc1 formats, aac format)
    ui_player_view->>tb_hls: tb_hls_set(stream, order 360p then 480p)
    ui_player_view->>mp_player: init(master_url) and play
    mp_player->>tb_hls: GET /gen/master.m3u8
    tb_hls-->>mp_player: master playlist
    mp_player->>tb_hls: GET /gen/0.m3u8
    tb_hls->>tb_stream: tb_stream_playlist(0)
    tb_stream->>googlevideo: GET bytes 0..index_end (init and sidx)
    googlevideo-->>tb_stream: init and sidx
    tb_stream-->>tb_hls: media playlist
    tb_hls-->>mp_player: media playlist
    mp_player->>tb_hls: GET /gen/0/0.ts
    tb_hls->>tb_stream: tb_stream_segment(0, 0)
    tb_stream->>googlevideo: GET audio init and sidx, video fragment 0, audio head 8 KB, audio bytes up to last sample
    googlevideo-->>tb_stream: media bytes
    tb_stream->>tb_stream: remux fragment to one ts segment and cache it
    tb_stream-->>tb_hls: ts segment
    tb_hls-->>mp_player: 0.ts
    tb_hls->>tb_stream: tb_stream_prefetch(0, 1)
    mp_player-->>ui_player_view: ready_for_display and playing
    ui_player_view->>ui_player_view: start_ms = now minus t0
```

---

## 4. Data Model

```mermaid
classDiagram
    class tb_list {
        +tb_item[] items
        +int n
        +string continuation
        +string title
        +string subtitle
        +int subscribed
        +string error
    }
    class tb_item {
        +int kind
        +string id
        +string title
        +string byline
        +string channel_id
        +string length
        +string views
        +string published
        +string thumb
        +string set_video_id
    }
    class tb_player {
        +string status
        +string reason
        +tb_format[] f
        +tb_ctrack[] caps
        +string hls_url
        +int live
        +int length_s
        +int expires_s
        +string title
        +string author
        +string channel_id
        +string description
        +string views
        +string storyboard
    }
    class tb_format {
        +int itag
        +string url
        +string mime
        +int width
        +int height
        +int bitrate
        +int fps
        +int64 init_end
        +int64 index_start
        +int64 index_end
        +int64 content_length
        +int audio
        +string audio_track_id
        +string audio_track_name
        +int audio_default
    }
    class tb_ctrack {
        +string base_url
        +string lang
        +string name
        +int asr
    }
    class tb_captions {
        +tb_cue[] cues
        +int n
    }
    class tb_cue {
        +double start
        +double dur
        +string text
    }
    class tb_next {
        +string title
        +string views
        +string date
        +string description
        +string channel
        +string channel_id
        +string channel_thumb
        +string subscribers
        +string likes
        +int subscribed
        +tb_list related
        +tb_chapter[] chapters
        +string comments_token
        +string comment_count
    }
    class tb_chapter {
        +double start
        +string title
    }
    class tb_comments {
        +tb_comment[] c
        +string continuation
        +string header
    }
    class tb_comment {
        +string author
        +string text
        +string published
        +string likes
        +string replies_token
        +int reply_count
    }
    class tb_stream {
        +variant[] videos
        +variant audio
        +cached[4] cache
        +int refs
        +int prefetch_running
        +tb_stream_stats st
        +playlist(vi) string
        +master(order, n) string
        +segment(vi, seg) tb_out
        +prefetch(vi, seg)
    }
    class tb_stream_fmt {
        +int itag
        +string url
        +int width
        +int height
        +int bitrate
        +int64 index_end
        +int64 content_length
    }
    class tb_hist {
        +string video_id
        +string title
        +string channel
        +string length
        +double position
        +double watched_at
    }

    tb_list "1" --> "*" tb_item : items
    tb_player "1" --> "*" tb_format : f
    tb_player "1" --> "*" tb_ctrack : caps
    tb_ctrack ..> tb_captions : fetched as srv1
    tb_captions "1" --> "*" tb_cue : cues
    tb_next "1" --> "1" tb_list : related
    tb_next "1" --> "*" tb_chapter : chapters
    tb_next ..> tb_comments : comments_token
    tb_comments "1" --> "*" tb_comment : c
    tb_format ..> tb_stream_fmt : picked avc1 and aac
    tb_stream "1" --> "*" tb_stream_fmt : copies
    tb_item ..> tb_hist : opened video
```

All strings are `malloc` C strings owned by the struct. Each struct has a free function (`tb_list_free`, `tb_player_free`, `tb_next_free`, `tb_comments_free`, `tb_captions_free`, `tb_hist_free`). The Objective-C layer copies the fields into `TBItem`, `TBPage`, `TBPlayerInfo`, `TBNextInfo` and frees the C struct at once.

---

## tb_item

One row of any list (search, feed, channel, playlist, related).

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| kind | int | Yes | 1 video, 2 channel, 3 playlist, 4 live, 5 shelf |
| id | string | Yes | Video ID (11 characters), channel ID (`UC…`) or playlist ID |
| title | string | Yes | Title |
| byline | string | No | Channel name |
| channel_id | string | No | Channel ID of a video |
| length | string | No | Display length, for example "3:25" |
| views | string | No | View text, or subscriber text for a channel |
| published | string | No | Relative date, for example "1 year ago" |
| thumb | string | No | Image URL; `mqdefault.jpg` for videos (BR-SEARCH-THUMB) |
| set_video_id | string | No | Playlist item ID, used to remove the item (BR-LIB-SETID) |

---

## tb_list

One page of items.

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| items, n, cap | tb_item[], int, int | Yes | Items on this page |
| continuation | string | No | Token for the next page; NULL at the end |
| title, subtitle | string | No | Page title (channel, playlist) |
| subscribed | int | No | Channel pages: -1 unknown, 0, 1 |
| error | string | No | Error text for the UI |

### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| tb_yt_search | query, continuation, params | tb_list | MWEB search, masked ([DUC-SEARCH-SEARCH](../../use_cases/domain/search/search.md)) |
| tb_yt_channel | channel_id, tab_params, continuation | tb_list | MWEB channel page |
| tb_yt_playlist | playlist_id, continuation | tb_list | MWEB playlist page |
| tb_yt_tv_browse | browse_id, continuation | tb_list | TVHTML5 + token ([DUC-LIB-BROWSE](../../use_cases/domain/library/browse.md)) |
| tb_list_free | — | void | Frees all strings and items |

---

## tb_player

The VISIONOS player answer: playability, formats, caption tracks, details.

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| status, reason | string | Yes | `OK`, `LOGIN_REQUIRED`, `UNPLAYABLE`, `ERROR`, …; reason text |
| f, nf | tb_format[], int | Yes | Adaptive formats with plain URLs (no cipher, no `n=`) |
| caps, ncaps | tb_ctrack[], int | No | Caption tracks; `asr` = auto-generated |
| hls_url | string | No | HLS manifest (live) |
| live | int | No | 1 for a live stream |
| length_s | int | Yes | Length in seconds |
| expires_s | int | No | Lifetime of the media URLs |
| title, author, channel_id, description, views, storyboard | string | No | Video details |

### tb_format

| Attribute | Type | Description |
|-----------|------|-------------|
| itag, mime | int, string | Format ID and MIME with codecs |
| url | string | googlevideo URL |
| width, height, bitrate, fps | int | Video properties |
| init_end, index_start, index_end, content_length | int64 | Byte ranges of init, sidx and the file |
| audio, audio_track_id, audio_track_name, audio_default | int, string, string, int | Audio flag and track (dubbed tracks) |

### Business Rules

| Rule | Description | Enforcement |
|------|-------------|-------------|
| BR-PLAY-FORMAT | Keep avc1 ≤ 720 (one per height, lowest bitrate) and mp4a.40.2 (default track) | `ui_core` player wrapper |
| EF-PLAY-1 | `LOGIN_REQUIRED` on the first try: new visitor ID, retry once | `tb_yt_player` |

---

## tb_captions

Cues of one caption track (`fmt=srv1`).

| Attribute | Type | Description |
|-----------|------|-------------|
| cues, n | tb_cue[], int | `start` and `dur` in seconds; `text` unescaped |

Method: `tb_yt_captions(base_url)` ([DUC-CAP-SHOW](../../use_cases/domain/captions/show.md)).

---

## tb_next

The MWEB `next` answer for the watch page.

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| title, views, date, description | string | Yes | Video text |
| channel, channel_id, channel_thumb, subscribers | string | Yes | Channel line |
| likes | string | No | Like count text |
| subscribed | int | No | -1 unknown, 0, 1 |
| related | tb_list | No | Related videos |
| chapters, nchapters | tb_chapter[], int | No | `start` (s), `title` |
| comments_token, comment_count | string | No | Token for `tb_yt_comments`; count text |

Method: `tb_yt_next(video_id)` ([DUC-VPAGE-LOAD](../../use_cases/domain/video-page/load.md)).

---

## tb_comments

| Attribute | Type | Description |
|-----------|------|-------------|
| c, n | tb_comment[], int | `author`, `text`, `published`, `likes`, `replies_token`, `reply_count` |
| continuation | string | Next page |
| header | string | For example "1.2K Comments" |

Method: `tb_yt_comments(token)`; loaded on tap only (BR-VPAGE-COMMENTS).

---

## tb_stream

One playback: DASH avc1 + AAC formats → HLS playlists and MPEG-TS segments. Opaque in `core/tb_stream.h`; the fields below are the internal state in `core/tb_stream.c`.

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| videos[] (variant) | tb_stream_fmt + tb_track + tb_sidx + ready | Yes | One per video format; init and sidx fetched on first use |
| audio (variant) | same | Yes | The AAC format |
| audio fragment buffer | idx, bytes, tb_frag | — | First 8 KB (moof), then bytes up to the needed sample ([D6](../../decisions.md)) |
| cache[4] | (vi, seg, TS bytes, use) | — | LRU of remuxed segments (BR-PLAY-CACHE) |
| refs | int | — | Owner + one per HLS request |
| prefetch_running, pf_vi, pf_seg, cancel | int | — | One background prefetch; a request for another segment cancels it |
| st | tb_stream_stats | — | segments_built, cache_hits, last_build_ms, last_fetch_ms, last_remux_ms, remux_ms_total, media_s_total, bytes_fetched, last_status |

### Methods

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| tb_stream_new | videos, nv, audio | tb_stream | Copies the formats; no download |
| tb_stream_playlist | vi (-1 = audio only) | string | Media playlist; one `#EXTINF` per sidx entry |
| tb_stream_master | order, n | string | Master playlist; first variant = start variant |
| tb_stream_segment | vi, seg | tb_out | Cached or built TS segment |
| tb_stream_prefetch | vi, seg | void | Build the next segment in the background |
| tb_stream_cancel / tb_stream_free | — | void | Stop downloads / drop the owner reference |

### Business Rules

| Rule | Description | Enforcement |
|------|-------------|-------------|
| BR-PLAY-REMUX | 1 fragment = 1 TS segment; audio by DTS; segment 0 from minus infinity ([D5](../../decisions.md)) | `build` |
| BR-PLAY-CACHE | ≤ 4 segments; one prefetch at a time | `get_locked`, `tb_stream_prefetch` |
| BR-PLAY-START | Auto order 360p, 480p | `ui_player_view` → `tb_hls_set` |

---

## tb_hist

One row of the local watch history ([DUC-HIST-RECORD](../../use_cases/domain/history/record.md)).

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| video_id | string | Yes | Key |
| title, channel, length | string | No | NULL on add keeps the stored value |
| position | double | No | Last saved play time (s) |
| watched_at | double | Yes | Unix seconds of the last open |

### Business Rules

| Rule | Description | Enforcement |
|------|-------------|-------------|
| BR-HISTORY-RESUME | Resume only when 10 s ≤ position ≤ length − 10 s | `ui_watch_controller` |
| BR-HIST-TX, BR-HIST-SQL | One transaction per action; SQLite 3.7.13 SQL | `tb_store` |

---

## account (tb_oauth)

| Struct | Fields | Description |
|--------|--------|-------------|
| tb_oauth_client | client_id, client_secret | TV client, read from the TV `base.js`; cached |
| tb_device_code | user_code, verification_url, device_code, interval, expires_in | Device-code answer |
| tb_token | access_token, refresh_token, expires_in, error | Token answer; `error` on failure |

Store keys: `oauth.refresh`, `oauth.expires`, `oauth.device_id`. Poll result: 0 = token, 1 = pending, < 0 = failed ([DUC-ACCT-SIGN-IN](../../use_cases/domain/account/sign-in.md)).

---

## 5. Events

PadTube has no event bus. The Objective-C layer uses two notifications.

| Notification | Sender | Consumers | Effect |
|--------------|--------|-----------|--------|
| `TBAccountChanged` | `ui_account` (sign-in, sign-out) | Home and Subscriptions lists, Library | Reload |
| `TBThemeChanged` | `TBTheme` | All screens | Apply light or dark colors |

---

## 6. References

- Code contracts: `core/tb_http.h`, `core/tb_json.h`, `core/tb_yt.h`, `core/tb_mp4.h`, `core/tb_ts.h`, `core/tb_stream.h`, `core/tb_hls.h`, `core/tb_store.h`, `core/tb_oauth.h`, `ios/src/*.h`
- [PLAN §1–§2](../../../local/PLAN.md); [decisions.md](../../decisions.md)
- [research-efficiency §4, §5, §6, §10](../../research/research-efficiency.md#10-recommended-design-and-budgets); [research-features §4](../../research/research-features.md#4-tier-1-in-depth-exact-request-shapes-and-2026-failure-modes)
- Requirements: [BREQ-PADTUBE](../../business/requirements/padtube.md)
