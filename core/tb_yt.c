#include "tb_yt.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "tb_http.h"
#include "tb_json.h"

/* Client versions: research-features §4.1 (VISIONOS 1.02 = yt-dlp), §4.4 (TVHTML5 = Opaline), MWEB = RetroTube. */
#define MWEB_VERSION "2.20260708.05.00"
#define VISIONOS_VERSION "1.02"
#define TV_VERSION "7.20260311.12.00"
#define API "https://www.youtube.com/youtubei/v1/"
#define VISIONOS_UA "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
#define TV_UA "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version"

static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static char g_visitor[256];
static char g_token[2048];
static char g_state[512];
static tb_yt_stats g_st;
static char g_dump[512];
static int g_dump_n;
void tb_yt_set_dump_dir(const char *d) { pthread_mutex_lock(&g_mu); snprintf(g_dump, sizeof g_dump, "%s", d ? d : ""); pthread_mutex_unlock(&g_mu); }

void tb_yt_get_stats(tb_yt_stats *out) {
    pthread_mutex_lock(&g_mu);
    *out = g_st;
    pthread_mutex_unlock(&g_mu);
}

void tb_yt_set_token(const char *t) {
    pthread_mutex_lock(&g_mu);
    snprintf(g_token, sizeof g_token, "%s", t ? t : "");
    pthread_mutex_unlock(&g_mu);
}

/* ---------- JSON string building ---------- */

typedef struct { char *p; size_t len, cap; } sb;
static void sb_add(sb *b, const char *s, size_t n) {
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 2;
        b->p = realloc(b->p, b->cap);
    }
    memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = 0;
}
static void sb_str(sb *b, const char *s) { sb_add(b, s, strlen(s)); }
static void sb_json(sb *b, const char *s) { /* quoted, escaped */
    sb_add(b, "\"", 1);
    for (; s && *s; s++) {
        unsigned char c = (unsigned char)*s;
        char e[8];
        if (c == '"' || c == '\\') { e[0] = '\\'; e[1] = (char)c; sb_add(b, e, 2); }
        else if (c < 0x20) { snprintf(e, sizeof e, "\\u%04x", c); sb_add(b, e, 6); }
        else sb_add(b, (const char *)&c, 1);
    }
    sb_add(b, "\"", 1);
}
static void url_escape(sb *b, const char *s) {
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') sb_add(b, (char *)&c, 1);
        else { char e[4]; snprintf(e, sizeof e, "%%%02X", c); sb_add(b, e, 3); }
    }
}

enum { CL_MWEB, CL_VISIONOS, CL_TV };

static void context(sb *b, int client) {
    pthread_mutex_lock(&g_mu);
    char vis[256];
    snprintf(vis, sizeof vis, "%s", g_visitor);
    pthread_mutex_unlock(&g_mu);
    sb_str(b, "{\"context\":{\"client\":{");
    if (client == CL_MWEB) sb_str(b, "\"clientName\":\"MWEB\",\"clientVersion\":\"" MWEB_VERSION "\"");
    else if (client == CL_VISIONOS)
        sb_str(b, "\"clientName\":\"VISIONOS\",\"clientVersion\":\"" VISIONOS_VERSION "\",\"deviceMake\":\"Apple\","
                  "\"deviceModel\":\"RealityDevice17,1\",\"osName\":\"visionOS\",\"osVersion\":\"26.5.23O471\"");
    else sb_str(b, "\"clientName\":\"TVHTML5\",\"clientVersion\":\"" TV_VERSION "\",\"platform\":\"TV\"");
    sb_str(b, ",\"hl\":\"en\",\"gl\":\"US\"");
    if (vis[0]) { sb_str(b, ",\"visitorData\":"); sb_json(b, vis); }
    sb_str(b, "}}");
}

/* POST an InnerTube endpoint. body_tail: the JSON members after the context, starting with ','. */
static int call(int client, const char *endpoint, const char *body_tail, const char *mask, tb_resp *r) {
    sb url = {0}, body = {0}, hdr = {0};
    sb_str(&url, API);
    sb_str(&url, endpoint);
    sb_str(&url, "?prettyPrint=false");
    if (mask) { sb_str(&url, "&fields="); url_escape(&url, mask); }
    context(&body, client);
    sb_str(&body, body_tail ? body_tail : "");
    sb_str(&body, "}");
    pthread_mutex_lock(&g_mu);
    sb_str(&hdr, "Content-Type: application/json\r\n");
    if (g_visitor[0]) { sb_str(&hdr, "X-Goog-Visitor-Id: "); sb_str(&hdr, g_visitor); sb_str(&hdr, "\r\n"); }
    if (client == CL_VISIONOS) sb_str(&hdr, "User-Agent: " VISIONOS_UA "\r\nX-YouTube-Client-Name: 101\r\nX-YouTube-Client-Version: " VISIONOS_VERSION "\r\n");
    else if (client == CL_TV) {
        sb_str(&hdr, "User-Agent: " TV_UA "\r\nX-YouTube-Client-Name: 7\r\nX-YouTube-Client-Version: " TV_VERSION "\r\n");
        if (g_token[0]) { sb_str(&hdr, "Authorization: Bearer "); sb_str(&hdr, g_token); sb_str(&hdr, "\r\n"); }
    } else sb_str(&hdr, "X-YouTube-Client-Name: 2\r\nX-YouTube-Client-Version: " MWEB_VERSION "\r\n");
    pthread_mutex_unlock(&g_mu);
    tb_req q = {.method = "POST", .url = url.p, .headers = hdr.p, .body = body.p, .body_len = body.len, .range_start = -1};
    int st = tb_http(&q, r);
    pthread_mutex_lock(&g_mu);
    if (g_dump[0] && r->body) {
        char path[700], ep[64];
        snprintf(ep, sizeof ep, "%s", endpoint);
        for (char *c = ep; *c; c++) if (*c == '/') *c = '_';
        snprintf(path, sizeof path, "%s/%s-%d.json", g_dump, ep, ++g_dump_n);
        FILE *f = fopen(path, "wb");
        if (f) { fwrite(r->body, 1, r->len, f); fclose(f); }
    }
    g_st.last_ms = r->ms_total;
    g_st.last_bytes = (long)r->len;
    g_st.last_status = st;
    pthread_mutex_unlock(&g_mu);
    free(url.p);
    free(body.p);
    free(hdr.p);
    return st;
}

static char *xstr(const char *s) { return s ? strdup(s) : NULL; }

int tb_yt_init(const char *state_dir) {
    char path[600] = "";
    if (state_dir) {
        snprintf(g_state, sizeof g_state, "%s", state_dir);
        snprintf(path, sizeof path, "%s/visitor_id", state_dir);
        FILE *f = fopen(path, "r");
        if (f) {
            char buf[256] = "";
            if (fgets(buf, sizeof buf, f)) {
                buf[strcspn(buf, "\r\n")] = 0;
                pthread_mutex_lock(&g_mu);
                snprintf(g_visitor, sizeof g_visitor, "%s", buf);
                pthread_mutex_unlock(&g_mu);
            }
            fclose(f);
            if (g_visitor[0]) return 0;
        }
    }
    tb_resp r;
    int st = call(CL_MWEB, "visitor_id", "", NULL, &r);
    if (st != 200) { tb_resp_free(&r); return st < 0 ? st : -st; }
    yyjson_doc *d = yyjson_read(r.body, r.len, 0);
    const char *v = tbj_str(yyjson_doc_get_root(d), "responseContext", "visitorData", NULL);
    int rc = -1;
    if (v) {
        pthread_mutex_lock(&g_mu);
        snprintf(g_visitor, sizeof g_visitor, "%s", v);
        pthread_mutex_unlock(&g_mu);
        rc = 0;
        if (path[0]) { FILE *f = fopen(path, "w"); if (f) { fprintf(f, "%s\n", v); fclose(f); } }
    }
    yyjson_doc_free(d);
    tb_resp_free(&r);
    return rc;
}

/* "Sign in to confirm you're not a bot": research-features §4.1 says get a new visitor ID once and retry. */
static void reset_visitor(void) {
    pthread_mutex_lock(&g_mu);
    g_visitor[0] = 0;
    pthread_mutex_unlock(&g_mu);
    if (g_state[0]) { char p[600]; snprintf(p, sizeof p, "%s/visitor_id", g_state); remove(p); }
    tb_yt_init(g_state[0] ? g_state : NULL);
}

/* ---------- lists ---------- */

/* first video of a playlist: RD + 11-char video id (a mix of that video), else /vi/<id>/ in its thumbnail */
static char *first_video_of(const tb_item *it) {
    if (it->kind != TB_KIND_PLAYLIST || !it->id) return NULL;
    if (!strncmp(it->id, "RD", 2) && strlen(it->id) == 13) return strdup(it->id + 2);
    const char *v = it->thumb ? strstr(it->thumb, "/vi/") : NULL;
    if (!v) v = it->thumb ? strstr(it->thumb, "/vi_webp/") : NULL;
    if (!v) return NULL;
    v = strchr(v + 1, '/') + 1;
    const char *e = strchr(v, '/');
    return e && e - v == 11 ? strndup(v, 11) : NULL;
}

static void list_add(tb_list *l, tb_item *it) {
    if (!it->first_video) it->first_video = first_video_of(it);
    if (l->n == l->cap) {
        l->cap = l->cap ? l->cap * 2 : 32;
        l->items = realloc(l->items, (size_t)l->cap * sizeof *l->items);
    }
    l->items[l->n++] = *it;
}

static char *vthumb(const char *id) {
    char b[96];
    snprintf(b, sizeof b, "https://i.ytimg.com/vi/%s/mqdefault.jpg", id);
    return strdup(b);
}

static char *img_url(yyjson_val *thumbs, int want_w) { /* thumbnails[] -> the smallest with width >= want_w */
    yyjson_val *best = NULL;
    size_t i, max;
    yyjson_val *t;
    int bw = 0;
    yyjson_arr_foreach(thumbs, i, max, t) {
        int w = (int)tbj_int(t, "width", NULL);
        if (!best || (bw < want_w && w > bw) || (w >= want_w && w < bw)) { best = t; bw = w; }
    }
    const char *u = tbj_str(best, "url", NULL);
    if (!u) return NULL;
    if (u[0] == '/' && u[1] == '/') { char *s = malloc(strlen(u) + 7); sprintf(s, "https:%s", u); return s; }
    return strdup(u);
}

static void item_video(tb_list *l, yyjson_val *v) {
    const char *id = tbj_str(v, "videoId", NULL);
    if (!id) return;
    tb_item it = {.kind = TB_KIND_VIDEO};
    it.id = strdup(id);
    it.title = tbj_text(tbj_get(v, "headline", NULL));
    if (!it.title) it.title = tbj_text(tbj_get(v, "title", NULL));
    yyjson_val *by = tbj_get(v, "shortBylineText", NULL);
    if (!by) by = tbj_get(v, "longBylineText", NULL);
    it.byline = tbj_text(by);
    it.channel_id = xstr(tbj_str(by, "runs", "0", "navigationEndpoint", "browseEndpoint", "browseId", NULL));
    it.length = tbj_text(tbj_get(v, "lengthText", NULL));
    it.views = tbj_text(tbj_get(v, "shortViewCountText", NULL));
    if (!it.views) it.views = tbj_text(tbj_get(v, "viewCountText", NULL));
    it.published = tbj_text(tbj_get(v, "publishedTimeText", NULL));
    it.set_video_id = xstr(tbj_str(v, "setVideoId", NULL));
    if (!it.length) { /* live: no length; a LIVE badge or overlay style */
        const char *st = tbj_str(v, "thumbnailOverlays", "0", "thumbnailOverlayTimeStatusRenderer", "style", NULL);
        if (st && !strcmp(st, "LIVE")) it.kind = TB_KIND_LIVE;
    }
    it.thumb = vthumb(id);
    list_add(l, &it);
}

static void item_channel(tb_list *l, yyjson_val *v) {
    const char *id = tbj_str(v, "channelId", NULL);
    if (!id) return;
    tb_item it = {.kind = TB_KIND_CHANNEL};
    it.id = strdup(id);
    it.title = tbj_text(tbj_get(v, "displayName", NULL));
    if (!it.title) it.title = tbj_text(tbj_get(v, "title", NULL));
    it.views = tbj_text(tbj_get(v, "videoCountText", NULL));      /* MWEB puts the subscriber count here */
    it.byline = tbj_text(tbj_get(v, "subscriberCountText", NULL)); /* and the @handle here */
    it.thumb = img_url(tbj_get(v, "thumbnail", "thumbnails", NULL), 88);
    list_add(l, &it);
}

static void item_playlist(tb_list *l, yyjson_val *v) {
    const char *id = tbj_str(v, "playlistId", NULL);
    if (!id) return;
    tb_item it = {.kind = TB_KIND_PLAYLIST};
    it.id = strdup(id);
    it.title = tbj_text(tbj_get(v, "title", NULL));
    it.byline = tbj_text(tbj_get(v, "shortBylineText", "runs", "0", NULL));
    if (!it.byline) it.byline = tbj_text(tbj_get(v, "shortBylineText", NULL));
    it.length = tbj_text(tbj_get(v, "videoCountShortText", NULL));
    if (!it.length) it.length = tbj_text(tbj_get(v, "videoCountText", NULL));
    it.thumb = img_url(tbj_get(v, "thumbnail", "thumbnails", NULL), 320);
    list_add(l, &it);
}

/* lockupViewModel (2025+ playlists, mixes, and the videos of MWEB playlists). */
static void item_lockup(tb_list *l, yyjson_val *v) {
    const char *id = tbj_str(v, "contentId", NULL), *type = tbj_str(v, "contentType", NULL);
    if (!id || !type) return;
    tb_item it = {0};
    yyjson_val *meta = tbj_get(v, "metadata", "lockupMetadataViewModel", NULL);
    it.title = xstr(tbj_str(meta, "title", "content", NULL));
    yyjson_val *rows = tbj_get(meta, "metadata", "contentMetadataViewModel", "metadataRows", NULL);
    it.byline = xstr(tbj_str(rows, "0", "metadataParts", "0", "text", "content", NULL));
    if (!strcmp(type, "LOCKUP_CONTENT_TYPE_VIDEO")) {
        it.kind = TB_KIND_VIDEO;
        it.thumb = vthumb(id);
        it.views = xstr(tbj_str(rows, "1", "metadataParts", "0", "text", "content", NULL));
        it.published = xstr(tbj_str(rows, "1", "metadataParts", "1", "text", "content", NULL));
        it.length = xstr(tbj_str(v, "contentImage", "thumbnailViewModel", "overlays", "0", "thumbnailBottomOverlayViewModel",
                                 "badges", "0", "thumbnailBadgeViewModel", "text", NULL));
    } else if (!strcmp(type, "LOCKUP_CONTENT_TYPE_PLAYLIST") || !strcmp(type, "LOCKUP_CONTENT_TYPE_PODCAST")) {
        it.kind = TB_KIND_PLAYLIST;
        yyjson_val *pt = tbj_get(v, "contentImage", "collectionThumbnailViewModel", "primaryThumbnail", "thumbnailViewModel", NULL);
        it.thumb = img_url(tbj_get(pt, "image", "sources", NULL), 320);
        it.length = xstr(tbj_str(pt, "overlays", "0", "thumbnailOverlayBadgeViewModel", "thumbnailBadges", "0", "thumbnailBadgeViewModel", "text", NULL));
    } else { free(it.title); free(it.byline); return; }
    it.id = strdup(id);
    list_add(l, &it);
}

/* TV tileRenderer (signed-in TVHTML5 feeds). Layout from YouTube.js parser/classes/Tile*.ts. */
static void item_tile(tb_list *l, yyjson_val *v) {
    const char *type = tbj_str(v, "contentType", NULL), *id = tbj_str(v, "contentId", NULL);
    yyjson_val *cmd = tbj_get(v, "onSelectCommand", NULL);
    tb_item it = {0};
    if (type && strstr(type, "VIDEO")) {
        it.kind = TB_KIND_VIDEO;
        if (!id) id = tbj_str(cmd, "watchEndpoint", "videoId", NULL);
    } else if (type && strstr(type, "CHANNEL")) {
        it.kind = TB_KIND_CHANNEL;
        if (!id) id = tbj_str(cmd, "browseEndpoint", "browseId", NULL);
    } else if (type && strstr(type, "PLAYLIST")) {
        it.kind = TB_KIND_PLAYLIST;
        const char *b = tbj_str(cmd, "browseEndpoint", "browseId", NULL);
        if (!id && b) id = !strncmp(b, "VL", 2) ? b + 2 : b;
    } else return;
    if (!id) return;
    it.id = strdup(id);
    yyjson_val *md = tbj_get(v, "metadata", "tileMetadataRenderer", NULL);
    it.title = tbj_text(tbj_get(md, "title", NULL));
    yyjson_val *lines = tbj_get(md, "lines", NULL);
    size_t i, max;
    yyjson_val *ln;
    int li = 0;
    yyjson_arr_foreach(lines, i, max, ln) {
        yyjson_val *items = tbj_get(ln, "lineRenderer", "items", NULL);
        size_t j, jm;
        yyjson_val *x;
        yyjson_arr_foreach(items, j, jm, x) {
            char *t = tbj_text(tbj_get(x, "lineItemRenderer", "text", NULL));
            if (!t || !t[0] || !strcmp(t, " \u2022 ") || !strcmp(t, "\u2022")) { free(t); continue; }
            if (li == 0 && !it.byline) it.byline = t;
            else if (!it.views) it.views = t;
            else if (!it.published) it.published = t;
            else free(t);
        }
        li++;
    }
    yyjson_val *hdr = tbj_get(v, "header", "tileHeaderRenderer", NULL);
    yyjson_val *ov = tbj_get(hdr, "thumbnailOverlays", NULL);
    yyjson_arr_foreach(ov, i, max, ln) {
        yyjson_val *ts = tbj_get(ln, "thumbnailOverlayTimeStatusRenderer", NULL);
        if (!ts) continue;
        it.length = tbj_text(tbj_get(ts, "text", NULL));
        const char *st = tbj_str(ts, "style", NULL);
        if (st && !strcmp(st, "LIVE") && it.kind == TB_KIND_VIDEO) it.kind = TB_KIND_LIVE;
    }
    it.thumb = it.kind == TB_KIND_VIDEO || it.kind == TB_KIND_LIVE ? vthumb(id) : img_url(tbj_get(hdr, "thumbnail", "thumbnails", NULL), 160);
    list_add(l, &it);
}

/* Walk any response and collect known item renderers, in document order. Does not descend into a found item. */
static void walk(yyjson_val *v, tb_list *l, int depth) {
    if (!v || depth > 40) return;
    if (yyjson_is_arr(v)) {
        size_t i, max;
        yyjson_val *x;
        yyjson_arr_foreach(v, i, max, x) walk(x, l, depth + 1);
        return;
    }
    if (!yyjson_is_obj(v)) return;
    size_t i, max;
    yyjson_val *k, *x;
    yyjson_obj_foreach(v, i, max, k, x) {
        const char *key = yyjson_get_str(k);
        if (!strcmp(key, "videoWithContextRenderer") || !strcmp(key, "compactVideoRenderer") || !strcmp(key, "videoRenderer") ||
            !strcmp(key, "gridVideoRenderer") || !strcmp(key, "playlistVideoRenderer") || !strcmp(key, "playlistPanelVideoRenderer"))
            item_video(l, x);
        else if (!strcmp(key, "compactChannelRenderer") || !strcmp(key, "channelRenderer") || !strcmp(key, "gridChannelRenderer"))
            item_channel(l, x);
        else if (!strcmp(key, "compactPlaylistRenderer") || !strcmp(key, "playlistRenderer") || !strcmp(key, "gridPlaylistRenderer"))
            item_playlist(l, x);
        else if (!strcmp(key, "lockupViewModel")) item_lockup(l, x);
        else if (!strcmp(key, "pageHeaderViewModel") && !l->title) {
            l->title = xstr(tbj_str(x, "title", "dynamicTextViewModel", "text", "content", NULL));
            yyjson_val *rows = tbj_get(x, "metadata", "contentMetadataViewModel", "metadataRows", NULL);
            const char *a = tbj_str(rows, "1", "metadataParts", "0", "text", "content", NULL);
            if (!a) a = tbj_str(rows, "0", "metadataParts", "1", "text", "content", NULL);
            l->subtitle = xstr(a);
            l->avatar = xstr(tbj_str(x, "image", "decoratedAvatarViewModel", "avatar", "avatarViewModel", "image", "sources", "0", "url", NULL));
            walk(x, l, depth + 1);
        } else if (!strcmp(key, "subscribeButtonRenderer") && l->subscribed < 0) {
            l->subscribed = tbj_bool(x, "subscribed", NULL);
        }
        else if (!strcmp(key, "tileRenderer")) item_tile(l, x);
        else if (!strcmp(key, "continuationCommand") || !strcmp(key, "nextContinuationData") || !strcmp(key, "reloadContinuationData")) {
            const char *t = tbj_str(x, "token", NULL);
            if (!t) t = tbj_str(x, "continuation", NULL);
            if (t && !l->continuation) l->continuation = strdup(t);
        } else if (!strcmp(key, "engagementPanels") || !strcmp(key, "frameworkUpdates") || !strcmp(key, "responseContext")) {
        } else walk(x, l, depth + 1);
    }
}

int tb_yt_parse_list(const char *json, size_t len, tb_list *out) {
    memset(out, 0, sizeof *out);
    out->subscribed = -1;
    out->n = 0;
    double t0 = tb_now_ms();
    yyjson_doc *d = yyjson_read(json, len, 0);
    if (!d) return -1;
    walk(yyjson_doc_get_root(d), out, 0);
    yyjson_doc_free(d);
    pthread_mutex_lock(&g_mu);
    g_st.last_parse_ms = tb_now_ms() - t0;
    pthread_mutex_unlock(&g_mu);
    return 0;
}

/* Field masks (research-efficiency §1.2: 74x fewer bytes). The parser does not depend on them: if a mask
 * returns nothing, the call is repeated without it. */
#define R_ "(runs(text))"
#define M_VIDEO "videoWithContextRenderer(videoId,headline" R_ ",shortBylineText(runs(text,navigationEndpoint(browseEndpoint(browseId)))),lengthText" R_ ",shortViewCountText" R_ ",publishedTimeText" R_ ",thumbnailOverlays(thumbnailOverlayTimeStatusRenderer(style)))"
#define M_CHANNEL "compactChannelRenderer(channelId,displayName" R_ ",videoCountText" R_ ",subscriberCountText" R_ ",thumbnail(thumbnails(url,width)))"
#define M_PLAYLIST "compactPlaylistRenderer(playlistId,title" R_ ",shortBylineText" R_ ",videoCountShortText" R_ ",thumbnail(thumbnails(url,width)))"
#define M_ITEMS "itemSectionRenderer(contents(" M_VIDEO "," M_CHANNEL "," M_PLAYLIST ")),continuationItemRenderer(continuationEndpoint(continuationCommand(token)))"
#define MASK_SEARCH "contents(sectionListRenderer(contents(" M_ITEMS ")))"
#define MASK_SEARCH_CONT "onResponseReceivedCommands(appendContinuationItemsAction(continuationItems(" M_ITEMS ")))"

static int list_call(int client, const char *ep, const char *tail, const char *mask, tb_list *out) {
    for (int attempt = 0; attempt < 2; attempt++) {
        tb_resp r;
        int st = call(client, ep, tail, attempt == 0 ? mask : NULL, &r);
        if (st != 200) {
            memset(out, 0, sizeof *out);
            char e[96];
            snprintf(e, sizeof e, "%s (%d)", st < 0 ? tb_http_strerror(st) : "server error", st);
            out->error = strdup(e);
            tb_resp_free(&r);
            return st < 0 ? st : -st;
        }
        tb_yt_parse_list(r.body, r.len, out);
        tb_resp_free(&r);
        if (out->n > 0 || !mask || attempt == 1) return 0;
        tb_list_free(out); /* mask matched nothing: the layout changed; ask again without it */
    }
    return 0;
}

int tb_yt_search(const char *query, const char *continuation, const char *params, tb_list *out) {
    sb t = {0};
    if (continuation) { sb_str(&t, ",\"continuation\":"); sb_json(&t, continuation); }
    else {
        sb_str(&t, ",\"query\":");
        sb_json(&t, query);
        if (params && *params) { sb_str(&t, ",\"params\":"); sb_json(&t, params); }
    }
    int rc = list_call(CL_MWEB, "search", t.p, continuation ? MASK_SEARCH_CONT : MASK_SEARCH, out);
    free(t.p);
    return rc;
}

/* ---------- player ---------- */

#define MASK_PLAYER "playabilityStatus(status,reason),streamingData(expiresInSeconds,hlsManifestUrl,adaptiveFormats(itag,url,mimeType,bitrate,width,height,fps,initRange,indexRange,contentLength,audioTrack)),captions(playerCaptionsTracklistRenderer(captionTracks(baseUrl,name,languageCode,kind))),videoDetails(title,author,channelId,lengthSeconds,isLive,viewCount,shortDescription),storyboards"

int tb_yt_parse_player(const char *json, size_t len, tb_player *p) {
    memset(p, 0, sizeof *p);
    yyjson_doc *d = yyjson_read(json, len, 0);
    if (!d) return -1;
    yyjson_val *root = yyjson_doc_get_root(d);
    p->status = xstr(tbj_str(root, "playabilityStatus", "status", NULL));
    p->reason = xstr(tbj_str(root, "playabilityStatus", "reason", NULL));
    yyjson_val *sd = tbj_get(root, "streamingData", NULL);
    p->expires_s = (int)tbj_int(sd, "expiresInSeconds", NULL);
    p->hls_url = xstr(tbj_str(sd, "hlsManifestUrl", NULL));
    yyjson_val *af = tbj_get(sd, "adaptiveFormats", NULL);
    size_t i, max;
    yyjson_val *f;
    p->f = calloc(yyjson_arr_size(af) + 1, sizeof *p->f);
    yyjson_arr_foreach(af, i, max, f) {
        const char *url = tbj_str(f, "url", NULL), *mime = tbj_str(f, "mimeType", NULL);
        if (!url || !mime) continue; /* signatureCipher formats need JS: not used */
        tb_format *o = &p->f[p->nf++];
        o->itag = (int)tbj_int(f, "itag", NULL);
        o->url = strdup(url);
        o->mime = strdup(mime);
        o->width = (int)tbj_int(f, "width", NULL);
        o->height = (int)tbj_int(f, "height", NULL);
        o->bitrate = (int)tbj_int(f, "bitrate", NULL);
        o->fps = (int)tbj_int(f, "fps", NULL);
        o->init_end = tbj_int(f, "initRange", "end", NULL);
        o->index_start = tbj_int(f, "indexRange", "start", NULL);
        o->index_end = tbj_int(f, "indexRange", "end", NULL);
        o->content_length = tbj_int(f, "contentLength", NULL);
        o->audio = strncmp(mime, "audio/", 6) == 0;
        o->audio_track_id = xstr(tbj_str(f, "audioTrack", "id", NULL));
        o->audio_track_name = xstr(tbj_str(f, "audioTrack", "displayName", NULL));
        o->audio_default = tbj_bool(f, "audioTrack", "audioIsDefault", NULL);
    }
    yyjson_val *ct = tbj_get(root, "captions", "playerCaptionsTracklistRenderer", "captionTracks", NULL);
    p->caps = calloc(yyjson_arr_size(ct) + 1, sizeof *p->caps);
    yyjson_arr_foreach(ct, i, max, f) {
        const char *u = tbj_str(f, "baseUrl", NULL);
        if (!u) continue;
        tb_ctrack *c = &p->caps[p->ncaps++];
        c->base_url = strdup(u);
        c->lang = xstr(tbj_str(f, "languageCode", NULL));
        c->name = tbj_text(tbj_get(f, "name", NULL));
        const char *kind = tbj_str(f, "kind", NULL);
        c->asr = kind && !strcmp(kind, "asr");
    }
    yyjson_val *vd = tbj_get(root, "videoDetails", NULL);
    p->title = xstr(tbj_str(vd, "title", NULL));
    p->author = xstr(tbj_str(vd, "author", NULL));
    p->channel_id = xstr(tbj_str(vd, "channelId", NULL));
    p->description = xstr(tbj_str(vd, "shortDescription", NULL));
    p->views = xstr(tbj_str(vd, "viewCount", NULL));
    p->length_s = (int)tbj_int(vd, "lengthSeconds", NULL);
    p->live = tbj_bool(vd, "isLive", NULL);
    p->storyboard = xstr(tbj_str(root, "storyboards", "playerStoryboardSpecRenderer", "spec", NULL));
    yyjson_doc_free(d);
    return 0;
}

int tb_yt_player(const char *video_id, tb_player *out) {
    sb t = {0};
    sb_str(&t, ",\"videoId\":");
    sb_json(&t, video_id);
    sb_str(&t, ",\"contentCheckOk\":true,\"racyCheckOk\":true");
    int rc = -1;
    for (int attempt = 0; attempt < 2; attempt++) {
        tb_resp r;
        int st = call(CL_VISIONOS, "player", t.p, MASK_PLAYER, &r);
        if (st != 200) { tb_resp_free(&r); memset(out, 0, sizeof *out); rc = st < 0 ? st : -st; break; }
        double t0 = tb_now_ms();
        rc = tb_yt_parse_player(r.body, r.len, out);
        pthread_mutex_lock(&g_mu);
        g_st.last_parse_ms = tb_now_ms() - t0;
        pthread_mutex_unlock(&g_mu);
        tb_resp_free(&r);
        if (rc == 0 && attempt == 0 && out->status && !strcmp(out->status, "LOGIN_REQUIRED")) {
            tb_player_free(out);
            reset_visitor();
            continue;
        }
        break;
    }
    free(t.p);
    return rc;
}

/* ---------- suggestions ---------- */

int tb_yt_suggest(const char *q, char ***out, int *n) {
    *out = NULL;
    *n = 0;
    sb u = {0};
    /* Plain JSON variant (research-features P7): ["q",["s1","s2",...]] */
    sb_str(&u, "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=en&q=");
    url_escape(&u, q);
    tb_req rq = {.url = u.p, .range_start = -1, .timeout_ms = 8000};
    tb_resp r;
    int st = tb_http(&rq, &r);
    free(u.p);
    if (st != 200) { tb_resp_free(&r); return st < 0 ? st : -st; }
    yyjson_doc *d = yyjson_read(r.body, r.len, 0);
    yyjson_val *arr = yyjson_arr_get(yyjson_doc_get_root(d), 1);
    size_t i, max;
    yyjson_val *x;
    *out = calloc(yyjson_arr_size(arr) + 1, sizeof(char *));
    yyjson_arr_foreach(arr, i, max, x) if (yyjson_is_str(x)) (*out)[(*n)++] = strdup(yyjson_get_str(x));
    yyjson_doc_free(d);
    tb_resp_free(&r);
    return 0;
}

/* ---------- captions (srv1 XML: <text start="1.2" dur="3.4">...</text>) ---------- */

static void xml_unescape(char *s) {
    char *w = s;
    while (*s) {
        if (*s == '&') {
            if (!strncmp(s, "&amp;", 5)) { *w++ = '&'; s += 5; continue; }
            if (!strncmp(s, "&lt;", 4)) { *w++ = '<'; s += 4; continue; }
            if (!strncmp(s, "&gt;", 4)) { *w++ = '>'; s += 4; continue; }
            if (!strncmp(s, "&quot;", 6)) { *w++ = '"'; s += 6; continue; }
            if (!strncmp(s, "&#39;", 5) || !strncmp(s, "&apos;", 6)) { *w++ = '\''; s += s[1] == '#' ? 5 : 6; continue; }
            if (s[1] == '#') {
                char *end;
                long cp = s[2] == 'x' ? strtol(s + 3, &end, 16) : strtol(s + 2, &end, 10);
                if (*end == ';' && cp > 0 && cp < 0x110000) {
                    if (cp < 0x80) *w++ = (char)cp;
                    else if (cp < 0x800) { *w++ = (char)(0xc0 | cp >> 6); *w++ = (char)(0x80 | (cp & 63)); }
                    else if (cp < 0x10000) { *w++ = (char)(0xe0 | cp >> 12); *w++ = (char)(0x80 | (cp >> 6 & 63)); *w++ = (char)(0x80 | (cp & 63)); }
                    else { *w++ = (char)(0xf0 | cp >> 18); *w++ = (char)(0x80 | (cp >> 12 & 63)); *w++ = (char)(0x80 | (cp >> 6 & 63)); *w++ = (char)(0x80 | (cp & 63)); }
                    s = end + 1;
                    continue;
                }
            }
        }
        *w++ = *s++;
    }
    *w = 0;
}

int tb_yt_parse_captions(const char *body, size_t len, tb_captions *out) {
    memset(out, 0, sizeof *out);
    int cap = 0;
    const char *p = body, *end = body + len;
    while (p < end && (p = strstr(p, "<text")) != NULL) {
        const char *gt = strchr(p, '>');
        if (!gt) break;
        const char *close = strstr(gt, "</text>");
        double start = 0, dur = 0;
        const char *a = strstr(p, "start=\"");
        if (a && a < gt) start = strtod(a + 7, NULL);
        a = strstr(p, "dur=\"");
        if (a && a < gt) dur = strtod(a + 5, NULL);
        if (gt[-1] == '/' || !close) { p = gt + 1; continue; }
        size_t n = (size_t)(close - gt - 1);
        char *t = malloc(n + 1);
        memcpy(t, gt + 1, n);
        t[n] = 0;
        xml_unescape(t);
        xml_unescape(t); /* srv1 text is escaped twice (&amp;#39;) */
        if (out->n == cap) { cap = cap ? cap * 2 : 256; out->cues = realloc(out->cues, (size_t)cap * sizeof *out->cues); }
        out->cues[out->n++] = (tb_cue){start, dur, t};
        p = close + 7;
    }
    return 0;
}

int tb_yt_captions(const char *base_url, tb_captions *out) {
    sb u = {0};
    sb_str(&u, base_url);
    sb_str(&u, "&fmt=srv1"); /* smallest format: 3.6 KB vs 14.8 KB vtt (research-features §4.3) */
    tb_req rq = {.url = u.p, .range_start = -1};
    tb_resp r;
    int st = tb_http(&rq, &r);
    free(u.p);
    if (st != 200) { tb_resp_free(&r); memset(out, 0, sizeof *out); return st < 0 ? st : -st; }
    int rc = tb_yt_parse_captions(r.body, r.len, out);
    tb_resp_free(&r);
    return rc;
}


/* ---------- watch page (MWEB next) ---------- */

static void find_key(yyjson_val *v, const char *key, yyjson_val **out, int depth) {
    if (*out || !v || depth > 40) return;
    size_t i, max;
    yyjson_val *k, *x;
    if (yyjson_is_arr(v)) { yyjson_arr_foreach(v, i, max, x) find_key(x, key, out, depth + 1); return; }
    if (!yyjson_is_obj(v)) return;
    yyjson_obj_foreach(v, i, max, k, x) {
        if (!strcmp(yyjson_get_str(k), key)) { *out = x; return; }
        find_key(x, key, out, depth + 1);
        if (*out) return;
    }
}
static yyjson_val *find1(yyjson_val *v, const char *key) { yyjson_val *o = NULL; find_key(v, key, &o, 0); return o; }

static void parse_chapters(yyjson_val *root, tb_next *n) {
    /* playerOverlays ... markersMap[].value.chapters[].chapterRenderer {title, timeRangeStartMillis} */
    yyjson_val *mm = find1(tbj_get(root, "playerOverlays", NULL), "markersMap");
    size_t i, max;
    yyjson_val *e;
    yyjson_arr_foreach(mm, i, max, e) {
        yyjson_val *ch = tbj_get(e, "value", "chapters", NULL);
        if (!yyjson_is_arr(ch) || !yyjson_arr_size(ch)) continue;
        n->chapters = calloc(yyjson_arr_size(ch), sizeof *n->chapters);
        size_t j, jm;
        yyjson_val *c;
        yyjson_arr_foreach(ch, j, jm, c) {
            yyjson_val *r = tbj_get(c, "chapterRenderer", NULL);
            if (!r) continue;
            n->chapters[n->nchapters].start = (double)tbj_int(r, "timeRangeStartMillis", NULL) / 1000.0;
            n->chapters[n->nchapters].title = tbj_text(tbj_get(r, "title", NULL));
            n->nchapters++;
        }
        return;
    }
}

int tb_yt_parse_next(const char *json, size_t len, tb_next *n) {
    memset(n, 0, sizeof *n);
    n->subscribed = -1;
    n->related.subscribed = -1;
    yyjson_doc *d = yyjson_read(json, len, 0);
    if (!d) return -1;
    yyjson_val *root = yyjson_doc_get_root(d);
    yyjson_val *res = tbj_get(root, "contents", "singleColumnWatchNextResults", "results", "results", "contents", NULL);
    yyjson_val *info = find1(res, "slimVideoInformationRenderer");
    n->title = tbj_text(tbj_get(info, "title", NULL));
    /* expandedSubtitle runs: "1,234 views", " · ", "3 days ago" - the order and count vary between A/B layouts */
    yyjson_val *sub = tbj_get(info, "expandedSubtitle", "runs", NULL), *run;
    size_t ri, rmax;
    yyjson_arr_foreach(sub, ri, rmax, run) {
        const char *t = tbj_str(run, "text", NULL);
        if (!t || strlen(t) < 3) continue;
        if (!n->views && strstr(t, "view")) n->views = strdup(t);
        else if (!n->date && !strstr(t, "view")) n->date = strdup(t);
    }
    yyjson_val *own = find1(res, "slimOwnerRenderer");
    n->channel = tbj_text(tbj_get(own, "title", NULL));
    n->channel_id = xstr(tbj_str(own, "navigationEndpoint", "browseEndpoint", "browseId", NULL));
    n->channel_thumb = img_url(tbj_get(own, "thumbnail", "thumbnails", NULL), 88);
    n->subscribers = tbj_text(tbj_get(own, "expandedSubtitle", NULL));
    yyjson_val *sbr = find1(own, "subscribeButtonRenderer");
    if (sbr) n->subscribed = tbj_bool(sbr, "subscribed", NULL);
    yyjson_val *like = find1(res, "likeButtonViewModel");
    if (tbj_get(like, "likeButtonViewModel", NULL)) like = tbj_get(like, "likeButtonViewModel", NULL);
    n->likes = xstr(tbj_str(like, "toggleButtonViewModel", "toggleButtonViewModel", "defaultButtonViewModel", "buttonViewModel", "title", NULL));
    yyjson_val *panels = tbj_get(root, "engagementPanels", NULL);
    size_t i, max;
    yyjson_val *p;
    yyjson_arr_foreach(panels, i, max, p) {
        yyjson_val *ep = tbj_get(p, "engagementPanelSectionListRenderer", NULL);
        const char *id = tbj_str(ep, "panelIdentifier", NULL);
        if (!id) continue;
        if (!strcmp(id, "engagement-panel-comments-section")) {
            yyjson_val *cc = find1(tbj_get(ep, "content", NULL), "continuationCommand");
            n->comments_token = xstr(tbj_str(cc, "token", NULL));
            yyjson_val *ctx = tbj_get(ep, "header", "engagementPanelTitleHeaderRenderer", "contextualInfo", NULL);
            n->comment_count = tbj_text(ctx);
        } else if (!strcmp(id, "video-description-ep-identifier") && !n->description) {
            yyjson_val *body = find1(ep, "expandableVideoDescriptionBodyRenderer");
            n->description = tbj_text(tbj_get(body, "attributedDescriptionBodyText", NULL));
            if (!n->description) n->description = tbj_text(tbj_get(body, "descriptionBodyText", NULL));
            yyjson_val *hdr = find1(ep, "videoDescriptionHeaderRenderer");
            if (hdr) {
                char *date = tbj_text(tbj_get(hdr, "publishDate", NULL));
                if (date) { free(n->date); n->date = date; }
                if (!n->views) n->views = tbj_text(tbj_get(hdr, "views", NULL));
            }
        }
    }
    /* related videos: every list item in the results (skips the metadata section's own renderers) */
    walk(res, &n->related, 0);
    parse_chapters(root, n);
    yyjson_doc_free(d);
    return 0;
}

/* Watch page mask: 44 KB -> 4.9 KB gzip, 325 KB -> 15 KB JSON (MEASURED 2026-11-11, aircAruvnKk). */
#define M_LIKE "slimVideoActionBarRenderer(buttons(slimMetadataButtonRenderer(button(segmentedLikeDislikeButtonViewModel(likeButtonViewModel(likeButtonViewModel(toggleButtonViewModel(toggleButtonViewModel(defaultButtonViewModel(buttonViewModel(title)))))))))))"
#define M_META "slimVideoMetadataSectionRenderer(contents(slimVideoInformationRenderer(title" R_ ",expandedSubtitle" R_ "),slimOwnerRenderer(title" R_ ",navigationEndpoint(browseEndpoint(browseId)),thumbnail(thumbnails(url,width)),expandedSubtitle" R_ ",subscribeButton(subscribeButtonRenderer(subscribed)))," M_LIKE "))"
#define M_RES "contents(singleColumnWatchNextResults(results(results(contents(" M_META ",itemSectionRenderer(contents(" M_VIDEO ",continuationItemRenderer(continuationEndpoint(continuationCommand(token))))))))))"
#define M_PANELS "engagementPanels(engagementPanelSectionListRenderer(panelIdentifier,header(engagementPanelTitleHeaderRenderer(contextualInfo)),content(sectionListRenderer(contents(itemSectionRenderer(contents(continuationItemRenderer(continuationEndpoint(continuationCommand(token))))))),structuredDescriptionContentRenderer(items(videoDescriptionHeaderRenderer(publishDate,views),expandableVideoDescriptionBodyRenderer(attributedDescriptionBodyText(content)))))))"
#define M_CHAPTERS "playerOverlays(playerOverlayRenderer(decoratedPlayerBarRenderer(decoratedPlayerBarRenderer(playerBar(multiMarkersPlayerBarRenderer(markersMap(key,value(chapters(chapterRenderer(title" R_ ",timeRangeStartMillis))))))))))"
#define MASK_NEXT M_RES "," M_PANELS "," M_CHAPTERS

int tb_yt_next(const char *video_id, tb_next *out) {
    sb t = {0};
    sb_str(&t, ",\"videoId\":");
    sb_json(&t, video_id);
    int rc = -1;
    for (int attempt = 0; attempt < 2; attempt++) {
        tb_resp r;
        int st = call(CL_MWEB, "next", t.p, attempt == 0 ? MASK_NEXT : NULL, &r);
        if (st != 200) { tb_resp_free(&r); memset(out, 0, sizeof *out); rc = st < 0 ? st : -st; break; }
        double t0 = tb_now_ms();
        rc = tb_yt_parse_next(r.body, r.len, out);
        pthread_mutex_lock(&g_mu);
        g_st.last_parse_ms = tb_now_ms() - t0;
        pthread_mutex_unlock(&g_mu);
        tb_resp_free(&r);
        if (rc == 0 && (out->title || attempt == 1)) break;
        tb_next_free(out); /* the mask matched nothing: the layout changed; ask again without it */
    }
    free(t.p);
    return rc;
}

/* ---------- comments (MWEB next continuation; commentThreadRenderer / commentRenderer) ---------- */

static void comment_add(tb_comments *c, yyjson_val *cr) {
    if (c->n == c->cap) { c->cap = c->cap ? c->cap * 2 : 32; c->c = realloc(c->c, (size_t)c->cap * sizeof *c->c); }
    tb_comment *o = &c->c[c->n++];
    memset(o, 0, sizeof *o);
    o->author = tbj_text(tbj_get(cr, "authorText", NULL));
    o->text = tbj_text(tbj_get(cr, "contentText", NULL));
    o->published = tbj_text(tbj_get(cr, "publishedTimeText", NULL));
    o->likes = tbj_text(tbj_get(cr, "voteCount", NULL));
    o->reply_count = (int)tbj_int(cr, "replyCount", NULL);
}

static void walk_comments(yyjson_val *v, tb_comments *c, int depth) {
    if (!v || depth > 30) return;
    size_t i, max;
    yyjson_val *k, *x;
    if (yyjson_is_arr(v)) { yyjson_arr_foreach(v, i, max, x) walk_comments(x, c, depth + 1); return; }
    if (!yyjson_is_obj(v)) return;
    yyjson_obj_foreach(v, i, max, k, x) {
        const char *key = yyjson_get_str(k);
        if (!strcmp(key, "commentThreadRenderer")) {
            yyjson_val *cr = tbj_get(x, "comment", "commentRenderer", NULL);
            if (cr) {
                comment_add(c, cr);
                yyjson_val *rep = find1(tbj_get(x, "replies", NULL), "continuationCommand");
                c->c[c->n - 1].replies_token = xstr(tbj_str(rep, "token", NULL));
            }
        } else if (!strcmp(key, "commentRenderer")) {
            comment_add(c, x);
        } else if (!strcmp(key, "commentsHeaderRenderer")) {
            c->header = tbj_text(tbj_get(x, "countText", NULL));
        } else if (!strcmp(key, "continuationItemRenderer")) {
            yyjson_val *cc = find1(x, "continuationCommand");
            const char *t = tbj_str(cc, "token", NULL);
            if (t) { free(c->continuation); c->continuation = strdup(t); }
        } else walk_comments(x, c, depth + 1);
    }
}

int tb_yt_parse_comments(const char *json, size_t len, tb_comments *out) {
    memset(out, 0, sizeof *out);
    yyjson_doc *d = yyjson_read(json, len, 0);
    if (!d) return -1;
    walk_comments(yyjson_doc_get_root(d), out, 0);
    yyjson_doc_free(d);
    return 0;
}

int tb_yt_comments(const char *token, tb_comments *out) {
    sb t = {0};
    sb_str(&t, ",\"continuation\":");
    sb_json(&t, token);
    tb_resp r;
    int st = call(CL_MWEB, "next", t.p, NULL, &r);
    free(t.p);
    if (st != 200) { tb_resp_free(&r); memset(out, 0, sizeof *out); return st < 0 ? st : -st; }
    int rc = tb_yt_parse_comments(r.body, r.len, out);
    tb_resp_free(&r);
    return rc;
}

/* ---------- channel and playlist (MWEB browse) ---------- */

int tb_yt_channel(const char *channel_id, const char *tab_params, const char *continuation, tb_list *out) {
    sb t = {0};
    if (continuation && *continuation) { sb_str(&t, ",\"continuation\":"); sb_json(&t, continuation); }
    else {
        sb_str(&t, ",\"browseId\":");
        sb_json(&t, channel_id);
        /* Videos tab (research-features §5.4, RetroTube) unless another tab is asked for */
        sb_str(&t, ",\"params\":");
        sb_json(&t, tab_params && *tab_params ? tab_params : "EgZ2aWRlb3PyBgQKAjoA");
    }
    int rc = list_call(CL_MWEB, "browse", t.p, NULL, out);
    free(t.p);
    return rc;
}

int tb_yt_playlist(const char *playlist_id, const char *continuation, tb_list *out) {
    sb t = {0};
    if (continuation && *continuation) { sb_str(&t, ",\"continuation\":"); sb_json(&t, continuation); }
    else {
        char id[160];
        snprintf(id, sizeof id, "%s%s", strncmp(playlist_id, "VL", 2) ? "VL" : "", playlist_id);
        sb_str(&t, ",\"browseId\":");
        sb_json(&t, id);
    }
    int rc = list_call(CL_MWEB, "browse", t.p, NULL, out);
    free(t.p);
    return rc;
}

int tb_yt_mix(const char *playlist_id, const char *first_video, const char *continuation, tb_list *out) {
    sb t = {0};
    if (continuation && *continuation) { sb_str(&t, ",\"continuation\":"); sb_json(&t, continuation); }
    else {
        sb_str(&t, ",\"playlistId\":");
        sb_json(&t, playlist_id);
        if (first_video && *first_video) { sb_str(&t, ",\"videoId\":"); sb_json(&t, first_video); }
    }
    tb_resp r;
    int st = call(CL_MWEB, "next", t.p, NULL, &r);
    free(t.p);
    memset(out, 0, sizeof *out);
    out->subscribed = -1;
    if (st != 200) { tb_resp_free(&r); return st < 0 ? st : -st; }
    yyjson_doc *d = yyjson_read(r.body, r.len, 0);
    yyjson_val *root = yyjson_doc_get_root(d);
    /* only the queue: contents...playlist.playlist (the related list of the watch page is not part of the mix) */
    yyjson_val *pl = find1(tbj_get(root, "contents", NULL), "playlist");
    if (tbj_get(pl, "playlist", NULL)) pl = tbj_get(pl, "playlist", NULL);
    out->title = tbj_text(tbj_get(pl, "title", NULL));
    walk(tbj_get(pl, "contents", NULL), out, 0);
    yyjson_doc_free(d);
    tb_resp_free(&r);
    return 0;
}

/* ---------- signed in (TVHTML5 + OAuth bearer) ---------- */

int tb_yt_tv_browse(const char *browse_id, const char *continuation, tb_list *out) {
    sb t = {0};
    if (continuation && *continuation) { sb_str(&t, ",\"continuation\":"); sb_json(&t, continuation); }
    else { sb_str(&t, ",\"browseId\":"); sb_json(&t, browse_id); }
    int rc = list_call(CL_TV, "browse", t.p, NULL, out);
    free(t.p);
    return rc;
}

static int action(const char *ep, const char *tail) {
    tb_resp r;
    int st = call(CL_TV, ep, tail, NULL, &r);
    tb_resp_free(&r);
    return st == 200 ? 0 : st < 0 ? st : -st;
}

int tb_yt_like(const char *video_id, int a) {
    sb t = {0};
    sb_str(&t, ",\"target\":{\"videoId\":");
    sb_json(&t, video_id);
    sb_str(&t, "}");
    int rc = action(a > 0 ? "like/like" : a < 0 ? "like/dislike" : "like/removelike", t.p);
    free(t.p);
    return rc;
}

int tb_yt_subscribe(const char *channel_id, int on) {
    sb t = {0};
    sb_str(&t, ",\"channelIds\":[");
    sb_json(&t, channel_id);
    sb_str(&t, "]");
    int rc = action(on ? "subscription/subscribe" : "subscription/unsubscribe", t.p);
    free(t.p);
    return rc;
}

int tb_yt_playlist_edit(const char *playlist_id, const char *video_id, int add, const char *set_video_id) {
    sb t = {0};
    sb_str(&t, ",\"playlistId\":");
    sb_json(&t, playlist_id);
    if (add) { sb_str(&t, ",\"actions\":[{\"action\":\"ACTION_ADD_VIDEO\",\"addedVideoId\":"); sb_json(&t, video_id); }
    else { sb_str(&t, ",\"actions\":[{\"action\":\"ACTION_REMOVE_VIDEO\",\"setVideoId\":"); sb_json(&t, set_video_id ? set_video_id : ""); }
    sb_str(&t, "}]");
    int rc = action("browse/edit_playlist", t.p);
    free(t.p);
    return rc;
}

int tb_yt_tracking(const char *video_id, char **playback_url, char **watchtime_url) {
    *playback_url = *watchtime_url = NULL;
    sb t = {0};
    sb_str(&t, ",\"videoId\":");
    sb_json(&t, video_id);
    tb_resp r;
    int st = call(CL_TV, "player", t.p, "playbackTracking(videostatsPlaybackUrl,videostatsWatchtimeUrl)", &r);
    free(t.p);
    if (st != 200) { tb_resp_free(&r); return st < 0 ? st : -st; }
    yyjson_doc *d = yyjson_read(r.body, r.len, 0);
    yyjson_val *pt = tbj_get(yyjson_doc_get_root(d), "playbackTracking", NULL);
    *playback_url = xstr(tbj_str(pt, "videostatsPlaybackUrl", "baseUrl", NULL));
    *watchtime_url = xstr(tbj_str(pt, "videostatsWatchtimeUrl", "baseUrl", NULL));
    yyjson_doc_free(d);
    tb_resp_free(&r);
    return *playback_url ? 0 : -1;
}

int tb_yt_ping(const char *url) {
    sb h = {0};
    pthread_mutex_lock(&g_mu);
    sb_str(&h, "User-Agent: " TV_UA "\r\n");
    if (g_token[0]) { sb_str(&h, "Authorization: Bearer "); sb_str(&h, g_token); sb_str(&h, "\r\n"); }
    pthread_mutex_unlock(&g_mu);
    tb_req q = {.url = url, .headers = h.p, .range_start = -1};
    tb_resp r;
    int st = tb_http(&q, &r);
    tb_resp_free(&r);
    free(h.p);
    return st >= 200 && st < 300 ? 0 : st < 0 ? st : -st;
}

/* ---------- de-duplication ---------- */

void tb_item_keys(const tb_item *it, char key[2][64]) {
    char k = it->kind == TB_KIND_CHANNEL ? 'c' : it->kind == TB_KIND_PLAYLIST ? 'p' : 'v'; /* live = video */
    snprintf(key[0], 64, "%c:%s", k, it->id ? it->id : "");
    if (it->kind == TB_KIND_PLAYLIST && it->first_video) snprintf(key[1], 64, "f:%s", it->first_video);
    else key[1][0] = 0;
}

void tb_list_dedupe(tb_list *l) {
    int n = 0;
    for (int i = 0; i < l->n; i++) {
        char ki[2][64];
        tb_item_keys(&l->items[i], ki);
        int dup = 0;
        for (int j = 0; j < n && !dup; j++) {
            char kj[2][64];
            tb_item_keys(&l->items[j], kj);
            dup = !strcmp(ki[0], kj[0]) || (ki[1][0] && !strcmp(ki[1], kj[1]));
        }
        if (dup) {
            tb_item *it = &l->items[i];
            free(it->id); free(it->title); free(it->byline); free(it->channel_id); free(it->length);
            free(it->views); free(it->published); free(it->thumb); free(it->set_video_id); free(it->first_video);
            continue;
        }
        l->items[n++] = l->items[i];
    }
    l->n = n;
}

/* ---------- subscriptions order ---------- */

long tb_age_seconds(const char *t) {
    if (!t) return -1;
    static const struct { const char *unit; long s; } U[] = {
        {"second", 1}, {"minute", 60}, {"hour", 3600}, {"day", 86400}, {"week", 604800}, {"month", 2629800}, {"year", 31557600}};
    for (const char *p = t; *p; p++) {
        if (*p < '0' || *p > '9') continue;
        char *end;
        long n = strtol(p, &end, 10);
        while (*end == ' ') end++;
        for (size_t i = 0; i < sizeof U / sizeof U[0]; i++)
            if (!strncmp(end, U[i].unit, strlen(U[i].unit)) && strstr(end, "ago")) return n * U[i].s;
        p = end - 1;
    }
    return -1;
}

typedef struct { tb_item it; long age; int idx; } aged;
static int by_age(const void *a, const void *b) {
    const aged *x = a, *y = b;
    long ax = x->age < 0 ? 0x7fffffffL : x->age, ay = y->age < 0 ? 0x7fffffffL : y->age;
    if (ax != ay) return ax < ay ? -1 : 1;
    return x->idx - y->idx;
}

void tb_list_sort_by_age(tb_list *l) {
    aged *a = calloc((size_t)l->n + 1, sizeof *a);
    int n = 0;
    for (int i = 0; i < l->n; i++) {
        int dup = 0;
        for (int k = 0; k < n && !dup; k++) dup = a[k].it.id && l->items[i].id && !strcmp(a[k].it.id, l->items[i].id);
        if (dup) {
            tb_item *it = &l->items[i];
            free(it->id); free(it->title); free(it->byline); free(it->channel_id); free(it->length);
            free(it->views); free(it->published); free(it->thumb); free(it->set_video_id); free(it->first_video);
            continue;
        }
        a[n].it = l->items[i];
        a[n].age = tb_age_seconds(l->items[i].published);
        a[n].idx = n;
        n++;
    }
    qsort(a, (size_t)n, sizeof *a, by_age);
    for (int i = 0; i < n; i++) l->items[i] = a[i].it;
    l->n = n;
    free(a);
}

/* ---------- free ---------- */


void tb_list_free(tb_list *l) {
    for (int i = 0; i < l->n; i++) {
        tb_item *it = &l->items[i];
        free(it->id); free(it->title); free(it->byline); free(it->channel_id); free(it->length);
        free(it->views); free(it->published); free(it->thumb); free(it->set_video_id); free(it->first_video);
    }
    free(l->items); free(l->continuation); free(l->title); free(l->subtitle); free(l->avatar); free(l->error);
    memset(l, 0, sizeof *l);
}

void tb_player_free(tb_player *p) {
    for (int i = 0; i < p->nf; i++) {
        free(p->f[i].url); free(p->f[i].mime); free(p->f[i].audio_track_id); free(p->f[i].audio_track_name);
    }
    for (int i = 0; i < p->ncaps; i++) { free(p->caps[i].base_url); free(p->caps[i].lang); free(p->caps[i].name); }
    free(p->f); free(p->caps); free(p->status); free(p->reason); free(p->hls_url);
    free(p->title); free(p->author); free(p->channel_id); free(p->description); free(p->views); free(p->storyboard);
    memset(p, 0, sizeof *p);
}

void tb_captions_free(tb_captions *c) {
    for (int i = 0; i < c->n; i++) free(c->cues[i].text);
    free(c->cues);
    memset(c, 0, sizeof *c);
}

void tb_strv_free(char **v, int n) {
    for (int i = 0; i < n; i++) free(v[i]);
    free(v);
}

void tb_next_free(tb_next *n) {
    free(n->title); free(n->views); free(n->date); free(n->description); free(n->channel); free(n->channel_id);
    free(n->channel_thumb); free(n->subscribers); free(n->likes); free(n->comments_token); free(n->comment_count);
    tb_list_free(&n->related);
    for (int i = 0; i < n->nchapters; i++) free(n->chapters[i].title);
    free(n->chapters);
    memset(n, 0, sizeof *n);
}

void tb_comments_free(tb_comments *c) {
    for (int i = 0; i < c->n; i++) {
        free(c->c[i].author); free(c->c[i].text); free(c->c[i].published); free(c->c[i].likes); free(c->c[i].replies_token);
    }
    free(c->c); free(c->continuation); free(c->header);
    memset(c, 0, sizeof *c);
}

/* ---------- caption track order ---------- */

static int lang_matches(const char *lang, const char *pref) {   /* primary subtag equal: "en-GB" ~ "en" */
    size_t a = strcspn(lang, "-_"), b = strcspn(pref, "-_");
    return a == b && strncasecmp(lang, pref, a) == 0;
}

static int cap_rank(const tb_ctrack *t, const char *const *pref, int npref) {
    const char *lang = t->lang ? t->lang : "";
    for (int i = 0; i < npref; i++)
        if (lang_matches(lang, pref[i])) return i * 2 + (t->asr ? 1 : 0);
    if (lang_matches(lang, "en")) return npref * 2 + (t->asr ? 1 : 0);
    return npref * 2 + 2;   /* the rest: by name, then manual before auto */
}

void tb_caps_sort(tb_ctrack *caps, int n, const char *const *pref, int npref) {
    for (int i = 1; i < n; i++) {   /* insertion sort: stable, n is small (tens) */
        tb_ctrack t = caps[i];
        int rt = cap_rank(&t, pref, npref), j = i - 1;
        while (j >= 0) {
            int rj = cap_rank(&caps[j], pref, npref), c = rj - rt;
            if (c == 0 && rt == npref * 2 + 2) {
                c = strcmp(caps[j].name ? caps[j].name : "", t.name ? t.name : "");
                if (c == 0) c = (caps[j].asr ? 1 : 0) - (t.asr ? 1 : 0);
            }
            if (c <= 0) break;
            caps[j + 1] = caps[j];
            j--;
        }
        caps[j + 1] = t;
    }
}
