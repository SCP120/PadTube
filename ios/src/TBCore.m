#import "TBCore.h"
#import "TBAccount.h"
#import "TBSolver.h"
#import "TBLog.h"
#include "tb_hls.h"
#include "tb_http.h"

#include "tb_text.h"

/* Every core string goes through the iOS 6 emoji filter on its way to the UI (owner report 2026-11-12). */
NSString *TBStr(const char *s) {
    if (!s) return nil;
    BOOL wide = NO;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++)
        if (*p >= 0xF0 || (p[0] == 0xE2 && p[1] == 0x80 && p[2] == 0x8D)) { wide = YES; break; }
    if (!wide) return [NSString stringWithUTF8String:s];
    char *c = strdup(s);
    tb_text_ios6(c);
    NSString *r = [NSString stringWithUTF8String:c];
    free(c);
    return r;
}

@implementation TBItem
+ (NSArray *)itemsFromList:(const tb_list *)l {
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:(NSUInteger)l->n];
    for (int i = 0; i < l->n; i++) {
        const tb_item *c = &l->items[i];
        TBItem *it = [TBItem new];
        it.kind = c->kind;
        it.ident = TBStr(c->id);
        it.title = TBStr(c->title) ?: @"";
        it.byline = TBStr(c->byline);
        it.channelId = TBStr(c->channel_id);
        it.length = TBStr(c->length);
        it.views = TBStr(c->views);
        it.published = TBStr(c->published);
        it.thumb = TBStr(c->thumb);
        it.setVideoId = TBStr(c->set_video_id);
        it.firstVideo = TBStr(c->first_video);
        char k[2][64];
        tb_item_keys(c, k);
        it.keys = k[1][0] ? @[TBStr(k[0]), TBStr(k[1])] : @[TBStr(k[0])];
        [a addObject:it];
    }
    return a;
}
- (NSString *)meta {
    if (self.views.length && self.published.length) return [NSString stringWithFormat:@"%@ · %@", self.views, self.published];
    return self.views ?: self.published ?: @"";
}
@end

@implementation TBPage
@end
@implementation TBCaptionTrack
@end
@implementation TBFormat
@end
@implementation TBPlayerInfo
@end
@implementation TBNextInfo
@end
@implementation TBCue
@end

static TBPage *pageFrom(tb_list *l, int rc) {
    TBPage *p = [TBPage new];
    p.items = [TBItem itemsFromList:l];
    p.continuation = TBStr(l->continuation);
    p.title = TBStr(l->title);
    p.subtitle = TBStr(l->subtitle);
    p.avatar = TBStr(l->avatar);
    p.subscribed = l->subscribed;
    p.error = TBStr(l->error);
    if (rc && !p.error) p.error = [NSString stringWithFormat:@"Error %d", rc];
    tb_yt_stats st;
    tb_yt_get_stats(&st);
    p.netMs = st.last_ms;
    p.parseMs = st.last_parse_ms;
    return p;
}

NSString *TBPlayerProblem(TBPlayerInfo *info) {
    if ([info.status isEqualToString:@"LOGIN_REQUIRED"] && [info.reason rangeOfString:@"bot"].location != NSNotFound)
        return [TBAccount signedIn]
            ? @"YouTube refused this video also for your signed-in account (its bot check). Try again later."
            : @"YouTube asks to sign in for this video (its bot check). Sign in under Account in the guide with a code; then PadTube plays it.";
    return info.reason.length ? info.reason : [NSString stringWithFormat:@"This video cannot play (%@).", info.status ?: @"error"];
}

@implementation TBCore

+ (dispatch_queue_t)queue {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("padtube.net", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

+ (NSString *)stateDir {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"PadTube"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    return dir;
}

+ (void)start {
    NSString *roots = [[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"];
    if (tb_http_init(roots.fileSystemRepresentation) != 0) TBLog(@"PadTube: TLS roots not loaded");
    tb_hls_start();
    dispatch_async([self queue], ^{ tb_yt_init([self stateDir].fileSystemRepresentation); });
}

+ (void)run:(dispatch_block_t)work {
    dispatch_async([self queue], work);
}

+ (void)search:(NSString *)q continuation:(NSString *)c done:(void (^)(TBPage *))done {
    [self search:q params:nil continuation:c done:done];
}

+ (void)search:(NSString *)q params:(NSString *)params continuation:(NSString *)c done:(void (^)(TBPage *))done {
    [self run:^{
        tb_list l;
        int rc = tb_yt_search(q.UTF8String, c.UTF8String, params.UTF8String, &l);
        TBPage *p = pageFrom(&l, rc);
        tb_list_free(&l);
        dispatch_async(dispatch_get_main_queue(), ^{ done(p); });
    }];
}

+ (void)shorts:(NSString *)c done:(void (^)(TBPage *))done {
    [self run:^{
        tb_list l;
        int rc = tb_yt_shorts(c.UTF8String, &l);
        TBPage *p = pageFrom(&l, rc);
        tb_list_free(&l);
        dispatch_async(dispatch_get_main_queue(), ^{ done(p); });
    }];
}

+ (void)suggest:(NSString *)q done:(void (^)(NSArray *))done {
    [self run:^{
        char **v = NULL;
        int n = 0;
        tb_yt_suggest(q.UTF8String, &v, &n);
        NSMutableArray *a = [NSMutableArray array];
        for (int i = 0; i < n; i++) [a addObject:TBStr(v[i])];
        tb_strv_free(v, n);
        dispatch_async(dispatch_get_main_queue(), ^{ done(a); });
    }];
}

+ (void)player:(NSString *)videoId done:(void (^)(TBPlayerInfo *))done { [self player:videoId visitorReset:YES done:done]; }

/* The n and sig answers for the formats infoFrom keeps (D64): each distinct challenge once. */
static BOOL keepFormat(const tb_format *f) {
    BOOL avc = strstr(f->mime, "avc1") != NULL, aac = strstr(f->mime, "mp4a.40.2") != NULL;
    BOOL portrait = avc && f->width <= 720 && f->height > f->width;
    return ((avc && f->height <= 720) || aac || portrait) && f->index_end > 0;
}

static BOOL solveFormats(tb_player *p, NSString **err) {
    NSMutableOrderedSet *ns = [NSMutableOrderedSet orderedSet], *ss = [NSMutableOrderedSet orderedSet];
    for (int i = 0; i < p->nf; i++) {
        if (!keepFormat(&p->f[i])) continue;
        char *n = tb_url_param(p->f[i].url, "n");
        if (n) [ns addObject:TBStr(n)];
        free(n);
        if (p->f[i].sig_s) [ss addObject:TBStr(p->f[i].sig_s)];
    }
    NSDictionary *r = [TBSolver solveN:ns.array sig:ss.array error:err];
    if (!r) return NO;
    NSDictionary *rn = r[@"n"], *rs = r[@"sig"];
    for (int i = 0; i < p->nf; i++) {
        tb_format *f = &p->f[i];
        if (!keepFormat(f)) continue;
        char *n = tb_url_param(f->url, "n");
        NSString *nAns = n ? rn[TBStr(n)] : nil, *sAns = f->sig_s ? rs[TBStr(f->sig_s)] : nil;
        free(n);
        if ((n && !nAns) || (f->sig_s && !sAns)) { if (err) *err = @"missing answer"; return NO; }
        char *u = tb_url_solved(f->url, nAns.UTF8String, f->sig_s ? f->sig_sp : NULL, sAns.UTF8String);
        free(f->url);
        f->url = u;
    }
    return YES;
}

/* tb_player -> TBPlayerInfo (H.264 <= 720p, portrait <= 720 wide, AAC-LC; captions in the device's languages first) */
static TBPlayerInfo *infoFrom(tb_player *pp, int rc, double netMs) {
    tb_player p = *pp;
    TBPlayerInfo *info = [TBPlayerInfo new];
    info.netMs = netMs;
    if (rc) {
        info.status = @"ERROR";
        info.reason = rc < 0 && rc > -100 ? TBStr(tb_http_strerror(rc)) : [NSString stringWithFormat:@"Server error %d", -rc];
    } else {
        info.status = TBStr(p.status);
        info.reason = TBStr(p.reason);
        info.title = TBStr(p.title);
        info.author = TBStr(p.author);
        info.channelId = TBStr(p.channel_id);
        info.descriptionText = TBStr(p.description);
        info.views = TBStr(p.views);
        info.hlsUrl = TBStr(p.hls_url);
        info.lengthSeconds = p.length_s;
        info.live = p.live;
        NSMutableArray *v = [NSMutableArray array], *a = [NSMutableArray array], *c = [NSMutableArray array], *pv = [NSMutableArray array];
        for (int i = 0; i < p.nf; i++) {
            tb_format *f = &p.f[i];
            /* A5 decodes H.264 only (research-efficiency §9): drop VP9/AV1/Opus and HE-AAC; no 1080p. */
            BOOL avc = strstr(f->mime, "avc1") != NULL, aac = strstr(f->mime, "mp4a.40.2") != NULL;
            BOOL portrait = avc && f->width <= 720 && f->height > f->width;   /* 720x1280 etc. (D54) */
            if (!(avc && f->height <= 720) && !aac && !portrait) continue;
            if (f->index_end <= 0) continue;
            TBFormat *o = [TBFormat new];
            o.itag = f->itag; o.width = f->width; o.height = f->height; o.bitrate = f->bitrate; o.audio = f->audio; o.fps = f->fps;
            o.url = TBStr(f->url); o.mime = TBStr(f->mime); o.indexEnd = f->index_end; o.contentLength = f->content_length;
            o.audioTrackId = TBStr(f->audio_track_id); o.audioTrackName = TBStr(f->audio_track_name); o.audioDefault = f->audio_default;
            if (portrait) [pv addObject:o];
            if (avc && f->height <= 720) [v addObject:o];
            else if (aac) [a addObject:o];
        }
        [pv sortUsingComparator:^NSComparisonResult(TBFormat *x, TBFormat *y) { return x.width < y.width ? NSOrderedAscending : x.width > y.width ? NSOrderedDescending : NSOrderedSame; }];
        info.portraitFormats = pv;
        [v sortUsingComparator:^NSComparisonResult(TBFormat *x, TBFormat *y) { return x.height < y.height ? NSOrderedAscending : x.height > y.height ? NSOrderedDescending : NSOrderedSame; }];
        /* one format per height (the lowest bitrate) */
        NSMutableArray *uniq = [NSMutableArray array];
        for (TBFormat *f in v) if (!uniq.count || [uniq.lastObject height] != f.height) [uniq addObject:f];
        info.videoFormats = uniq;
        info.audioFormats = a;
        {   /* device languages first, then English (tb_caps_sort) */
            NSArray *langs = [NSLocale preferredLanguages];
            int np = (int)MIN(langs.count, (NSUInteger)8);
            const char *pref[8];
            for (int i = 0; i < np; i++) pref[i] = [langs[(NSUInteger)i] UTF8String];
            tb_caps_sort(p.caps, p.ncaps, pref, np);
        }
        for (int i = 0; i < p.ncaps; i++) {
            TBCaptionTrack *t = [TBCaptionTrack new];
            t.url = TBStr(p.caps[i].base_url); t.lang = TBStr(p.caps[i].lang); t.name = TBStr(p.caps[i].name); t.asr = p.caps[i].asr;
            [c addObject:t];
        }
        info.captionTracks = c;
        tb_player_free(&p);
    }
    return info;
}

+ (void)player:(NSString *)videoId visitorReset:(BOOL)reset done:(void (^)(TBPlayerInfo *))done {
    [self run:^{
        TBPlayerInfo *info = nil;
        /* D64: signed in, the account's TV path first (YouTube bot-checks signed-out requests, D60) */
        if ([TBAccount signedIn]) info = [self signedInPlayer:videoId];
        if (!info || ![info.status isEqualToString:@"OK"]) {
            tb_player p;
            double t0 = tb_now_ms();
            int rc = tb_yt_player_opt(videoId.UTF8String, reset ? 1 : 0, &p);
            TBPlayerInfo *v = infoFrom(&p, rc, tb_now_ms() - t0);
            TBLog(@"PadTube: player answer %@ (signed out) %@ in %.0f ms", videoId, v.status, v.netMs);
            if ([v.status isEqualToString:@"OK"] || !info) info = v;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(info); });
    }];
}

/* The signed-in path (D64): fresh token, the solver ready (TBSolver), tv_samsung with the token and the player's
 * signatureTimestamp, then the n and sig answers in the URLs of the formats PadTube uses. nil: no answer, try the
 * signed-out path. Background queue only. */
+ (TBPlayerInfo *)signedInPlayer:(NSString *)videoId {
    double t0 = tb_now_ms();
    [TBAccount ensureFresh];
    int sts = 0;
    if (![TBSolver waitReady:&sts]) { TBLog(@"PadTube: signed-in player %@: solver not ready", videoId); return nil; }
    double tReady = tb_now_ms();
    tb_player p;
    int rc = tb_yt_player_tv(videoId.UTF8String, sts, &p);
    if (rc == -401 && [TBAccount refreshNow]) rc = tb_yt_player_tv(videoId.UTF8String, sts, &p);   /* the token expired early */
    double tAnswer = tb_now_ms();
    if (rc || !p.status || strcmp(p.status, "OK")) {
        TBPlayerInfo *e = infoFrom(&p, rc, tAnswer - t0);
        TBLog(@"PadTube: signed-in player %@: %@ %@", videoId, e.status, e.reason);
        return e;
    }
    NSString *err = nil;
    if (!solveFormats(&p, &err)) {
        TBLog(@"PadTube: signed-in player %@: solve failed: %@", videoId, err);
        tb_player_free(&p);
        [TBSolver invalidate];   /* a new player version, maybe: look again next time */
        return nil;
    }
    TBPlayerInfo *info = infoFrom(&p, 0, tb_now_ms() - t0);
    info.signedIn = YES;
    TBLog(@"PadTube: signed-in player %@ OK: solver wait %.0f ms, answer %.0f ms, solve %.0f ms", videoId, tReady - t0, tAnswer - tReady, tb_now_ms() - tAnswer);
    return info;
}

+ (void)next:(NSString *)videoId done:(void (^)(TBNextInfo *))done {
    [self run:^{
        tb_next n;
        int rc = tb_yt_next(videoId.UTF8String, &n);
        TBNextInfo *i = [TBNextInfo new];
        if (rc == 0) {
            i.title = TBStr(n.title); i.views = TBStr(n.views); i.date = TBStr(n.date); i.descriptionText = TBStr(n.description);
            i.channel = TBStr(n.channel); i.channelId = TBStr(n.channel_id); i.channelThumb = TBStr(n.channel_thumb);
            i.subscribers = TBStr(n.subscribers); i.likes = TBStr(n.likes); i.subscribed = n.subscribed;
            i.commentsToken = TBStr(n.comments_token); i.commentCount = TBStr(n.comment_count);
            i.related = [TBItem itemsFromList:&n.related];
            NSMutableArray *ch = [NSMutableArray array];
            for (int k = 0; k < n.nchapters; k++) [ch addObject:@[@(n.chapters[k].start), TBStr(n.chapters[k].title) ?: @""]];
            i.chapters = ch;
            tb_next_free(&n);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(rc == 0 ? i : nil); });
    }];
}

+ (void)captions:(TBCaptionTrack *)t done:(void (^)(NSArray *))done {
    [self run:^{
        tb_captions c;
        int rc = tb_yt_captions(t.url.UTF8String, &c);
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:(NSUInteger)c.n];
        for (int i = 0; rc == 0 && i < c.n; i++) {
            TBCue *q = [TBCue new];
            q.start = c.cues[i].start;
            q.end = c.cues[i].start + c.cues[i].dur;
            q.text = TBStr(c.cues[i].text) ?: @"";
            [a addObject:q];
        }
        tb_captions_free(&c);
        dispatch_async(dispatch_get_main_queue(), ^{ done(a); });
    }];
}

+ (void)channel:(NSString *)channelId tab:(NSString *)params continuation:(NSString *)c done:(void (^)(TBPage *))done {
    [self run:^{
        tb_list l;
        int rc = tb_yt_channel(channelId.UTF8String, params.UTF8String, c.UTF8String, &l);
        TBPage *p = pageFrom(&l, rc);
        tb_list_free(&l);
        dispatch_async(dispatch_get_main_queue(), ^{ done(p); });
    }];
}

+ (void)playlist:(NSString *)playlistId continuation:(NSString *)c done:(void (^)(TBPage *))done {
    [self run:^{
        tb_list l;
        int rc = tb_yt_playlist(playlistId.UTF8String, c.UTF8String, &l);
        TBPage *p = pageFrom(&l, rc);
        tb_list_free(&l);
        dispatch_async(dispatch_get_main_queue(), ^{ done(p); });
    }];
}

+ (void)mix:(NSString *)playlistId firstVideo:(NSString *)v continuation:(NSString *)c done:(void (^)(TBPage *))done {
    [self run:^{
        tb_list l;
        int rc = tb_yt_mix(playlistId.UTF8String, v.UTF8String, c.UTF8String, &l);
        TBPage *p = pageFrom(&l, rc);
        tb_list_free(&l);
        dispatch_async(dispatch_get_main_queue(), ^{ done(p); });
    }];
}

+ (void)tvBrowse:(NSString *)browseId continuation:(NSString *)c done:(void (^)(TBPage *))done {
    [self run:^{
        tb_list l;
        /* the account lists need a live token too, not only the account actions (owner 2026-11-13: an app alive for
         * over an hour sent an expired token) */
        [TBAccount ensureFresh];
        int rc = tb_yt_tv_browse(browseId.UTF8String, c.UTF8String, &l);
        if (rc == -401 && [TBAccount refreshNow]) { tb_list_free(&l); rc = tb_yt_tv_browse(browseId.UTF8String, c.UTF8String, &l); }
        if (rc == 0) tb_list_dedupe(&l); /* one page: the TV feed repeats items across shelves (owner bug 2026-11-12) */
        /* research-features §4.4: the TV subscriptions feed is relevance-first; show it newest first */
        if (rc == 0 && [browseId isEqualToString:@"FEsubscriptions"]) tb_list_sort_by_age(&l);
        TBPage *p = pageFrom(&l, rc);
        tb_list_free(&l);
        dispatch_async(dispatch_get_main_queue(), ^{ done(p); });
    }];
}

@end
