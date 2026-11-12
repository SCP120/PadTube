#include "tb_mp4.h"
#include <stdlib.h>
#include <string.h>

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint64_t be64(const uint8_t *p) { return (uint64_t)be32(p) << 32 | be32(p + 4); }

typedef struct { const uint8_t *body; size_t len; uint32_t type; size_t total; } box;

/* Read the box at p. Returns 0 if it does not fit. */
static int box_at(const uint8_t *p, size_t n, box *b) {
    if (n < 8) return 0;
    uint64_t sz = be32(p);
    size_t hdr = 8;
    if (sz == 1) {
        if (n < 16) return 0;
        sz = be64(p + 8);
        hdr = 16;
    } else if (sz == 0) sz = n;
    if (sz < hdr || sz > n) return 0;
    b->type = be32(p + 4);
    b->body = p + hdr;
    b->len = (size_t)sz - hdr;
    b->total = (size_t)sz;
    return 1;
}

#define T(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

/* Find the first child box of the given type inside [p, p+n). */
static int child(const uint8_t *p, size_t n, uint32_t type, box *out) {
    box b;
    while (box_at(p, n, &b)) {
        if (b.type == type) { *out = b; return 1; }
        p += b.total;
        n -= b.total;
    }
    return 0;
}

static int parse_avcc(const uint8_t *p, size_t n, tb_track *t) {
    if (n < 7) return -1;
    t->nal_len_size = (p[4] & 3) + 1;
    int nsps = p[5] & 31;
    size_t o = 6;
    for (int i = 0; i < nsps; i++) {
        if (o + 2 > n) return -1;
        int l = be16(p + o);
        o += 2;
        if (o + l > n) return -1;
        if (i == 0 && l <= (int)sizeof t->sps) { memcpy(t->sps, p + o, l); t->sps_len = l; }
        o += l;
    }
    if (o + 1 > n) return -1;
    int npps = p[o++];
    for (int i = 0; i < npps; i++) {
        if (o + 2 > n) return -1;
        int l = be16(p + o);
        o += 2;
        if (o + l > n) return -1;
        if (i == 0 && l <= (int)sizeof t->pps) { memcpy(t->pps, p + o, l); t->pps_len = l; }
        o += l;
    }
    return t->sps_len && t->pps_len ? 0 : -1;
}

/* MPEG-4 descriptor length: up to 4 bytes of 7 bits. */
static size_t desc_len(const uint8_t *p, size_t n, size_t *o) {
    size_t len = 0;
    for (int i = 0; i < 4 && *o < n; i++) {
        uint8_t b = p[(*o)++];
        len = len << 7 | (b & 0x7f);
        if (!(b & 0x80)) break;
    }
    return len;
}

static int parse_esds(const uint8_t *p, size_t n, tb_track *t) {
    size_t o = 4; /* full box header */
    while (o + 2 <= n) {
        uint8_t tag = p[o++];
        size_t len = desc_len(p, n, &o);
        if (tag == 0x03) { /* ES_Descriptor */
            if (o + 3 > n) return -1;
            uint8_t fl = p[o + 2];
            o += 3;
            if (fl & 0x80) o += 2;
            if (fl & 0x40) { if (o >= n) return -1; o += 1 + p[o]; }
            if (fl & 0x20) o += 2;
            continue;
        }
        if (tag == 0x04) { o += 13; continue; } /* DecoderConfigDescriptor: children follow */
        if (tag == 0x05) {
            if (len < 2 || o + 2 > n) return -1;
            t->aac_object = p[o] >> 3;
            t->aac_freq_index = (p[o] & 7) << 1 | p[o + 1] >> 7;
            t->aac_channels = (p[o + 1] >> 3) & 15;
            return 0;
        }
        o += len;
    }
    return -1;
}

int tb_mp4_init(const uint8_t *p, size_t n, tb_track *t) {
    memset(t, 0, sizeof *t);
    box moov, trak, mdia, mdhd, hdlr, minf, stbl, stsd;
    if (!child(p, n, T('m', 'o', 'o', 'v'), &moov)) return -1;
    if (!child(moov.body, moov.len, T('t', 'r', 'a', 'k'), &trak)) return -1;
    if (!child(trak.body, trak.len, T('m', 'd', 'i', 'a'), &mdia)) return -1;
    if (!child(mdia.body, mdia.len, T('m', 'd', 'h', 'd'), &mdhd) || mdhd.len < 24) return -1;
    t->timescale = be32(mdhd.body + (mdhd.body[0] == 1 ? 20 : 12));
    if (!child(mdia.body, mdia.len, T('h', 'd', 'l', 'r'), &hdlr) || hdlr.len < 12) return -1;
    t->is_video = be32(hdlr.body + 8) == T('v', 'i', 'd', 'e');
    if (!child(mdia.body, mdia.len, T('m', 'i', 'n', 'f'), &minf)) return -1;
    if (!child(minf.body, minf.len, T('s', 't', 'b', 'l'), &stbl)) return -1;
    if (!child(stbl.body, stbl.len, T('s', 't', 's', 'd'), &stsd) || stsd.len < 8) return -1;
    box entry;
    if (!box_at(stsd.body + 8, stsd.len - 8, &entry)) return -1;
    if (t->is_video) {
        if (entry.type != T('a', 'v', 'c', '1') && entry.type != T('a', 'v', 'c', '3')) return -2;
        if (entry.len < 78) return -1;
        t->width = be16(entry.body + 24);
        t->height = be16(entry.body + 26);
        box avcc;
        if (!child(entry.body + 78, entry.len - 78, T('a', 'v', 'c', 'C'), &avcc)) return -1;
        return parse_avcc(avcc.body, avcc.len, t);
    }
    if (entry.type != T('m', 'p', '4', 'a') || entry.len < 28) return -2;
    box esds;
    if (!child(entry.body + 28, entry.len - 28, T('e', 's', 'd', 's'), &esds)) return -1;
    return parse_esds(esds.body, esds.len, t);
}

int tb_mp4_sidx(const uint8_t *p, size_t n, int64_t file_offset, tb_sidx *x) {
    memset(x, 0, sizeof *x);
    const uint8_t *start = p;
    box b;
    while (box_at(p, n, &b)) {
        if (b.type == T('s', 'i', 'd', 'x')) break;
        p += b.total;
        n -= b.total;
    }
    if (!box_at(p, n, &b) || b.type != T('s', 'i', 'd', 'x') || b.len < 24) return -1;
    const uint8_t *q = b.body;
    int v = q[0];
    x->timescale = be32(q + 8);
    uint64_t ept, first;
    size_t o;
    if (v == 0) { ept = be32(q + 12); first = be32(q + 16); o = 20; }
    else { if (b.len < 32) return -1; ept = be64(q + 12); first = be64(q + 20); o = 28; }
    int count = be16(q + o + 2);
    o += 4;
    if (o + (size_t)count * 12 > b.len || count <= 0) return -1;
    x->segs = calloc((size_t)count, sizeof *x->segs);
    if (!x->segs) return -1;
    int64_t off = file_offset + (p - start) + (int64_t)b.total + (int64_t)first;
    uint64_t t = ept;
    for (int i = 0; i < count; i++, o += 12) {
        uint32_t ref = be32(q + o);
        if (ref & 0x80000000u) { tb_sidx_free(x); return -1; } /* nested sidx: not used by YouTube */
        x->segs[i].offset = off;
        x->segs[i].size = ref & 0x7fffffff;
        x->segs[i].start = t;
        x->segs[i].duration = be32(q + o + 4);
        off += x->segs[i].size;
        t += x->segs[i].duration;
    }
    x->n = count;
    return 0;
}

uint32_t tb_mp4_moof_size(const uint8_t *p, size_t n) {
    if (n < 8 || be32(p + 4) != T('m', 'o', 'o', 'f')) return 0;
    return be32(p);
}

int tb_mp4_frag(const uint8_t *p, size_t n, const tb_track *t, tb_frag *f) {
    memset(f, 0, sizeof *f);
    box moof, traf, tfhd, tfdt, trun;
    if (!box_at(p, n, &moof) || moof.type != T('m', 'o', 'o', 'f')) return -1;
    f->moof_size = (uint32_t)moof.total;
    if (!child(moof.body, moof.len, T('t', 'r', 'a', 'f'), &traf)) return -1;
    if (!child(traf.body, traf.len, T('t', 'f', 'h', 'd'), &tfhd) || tfhd.len < 8) return -1;
    uint32_t hf = be32(tfhd.body) & 0xffffff, ddur = 0, dsize = 0, dflags = 0;
    size_t o = 8;
    int64_t base = 0; /* default base is the moof start (DASH: default-base-is-moof) */
    if (hf & 0x01) { base = (int64_t)be64(tfhd.body + o); o += 8; }
    if (hf & 0x02) o += 4;
    if (hf & 0x08) { ddur = be32(tfhd.body + o); o += 4; }
    if (hf & 0x10) { dsize = be32(tfhd.body + o); o += 4; }
    if (hf & 0x20) { dflags = be32(tfhd.body + o); o += 4; }
    uint64_t dts = 0;
    if (child(traf.body, traf.len, T('t', 'f', 'd', 't'), &tfdt) && tfdt.len >= 8)
        dts = tfdt.body[0] == 1 && tfdt.len >= 12 ? be64(tfdt.body + 4) : be32(tfdt.body + 4);
    if (!child(traf.body, traf.len, T('t', 'r', 'u', 'n'), &trun) || trun.len < 8) return -1;
    const uint8_t *q = trun.body;
    int ver = q[0];
    uint32_t rf = be32(q) & 0xffffff, count = be32(q + 4);
    o = 8;
    int32_t data_off = 0;
    uint32_t first_flags = 0;
    int has_first = 0;
    if (rf & 0x01) { data_off = (int32_t)be32(q + o); o += 4; }
    if (rf & 0x04) { first_flags = be32(q + o); has_first = 1; o += 4; }
    size_t per = ((rf & 0x100) ? 4 : 0) + ((rf & 0x200) ? 4 : 0) + ((rf & 0x400) ? 4 : 0) + ((rf & 0x800) ? 4 : 0);
    if (count == 0 || o + per * count > trun.len) return -1;
    f->s = calloc(count, sizeof *f->s);
    if (!f->s) return -1;
    int64_t pos = base + data_off;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t dur = ddur, sz = dsize, fl = (i == 0 && has_first) ? first_flags : dflags;
        int32_t cto = 0;
        if (rf & 0x100) { dur = be32(q + o); o += 4; }
        if (rf & 0x200) { sz = be32(q + o); o += 4; }
        if (rf & 0x400) { uint32_t v = be32(q + o); o += 4; if (!(i == 0 && has_first)) fl = v; }
        if (rf & 0x800) { uint32_t v = be32(q + o); o += 4; cto = ver ? (int32_t)v : (int32_t)(v & 0x7fffffff); }
        tb_sample *s = &f->s[i];
        s->offset = (uint32_t)pos;
        s->size = sz;
        s->dts = dts;
        s->cto = cto;
        s->key = t->is_video ? !(fl & 0x10000) : 1;
        pos += sz;
        dts += dur;
    }
    f->n = (int)count;
    f->end_dts = dts;
    return 0;
}

void tb_sidx_free(tb_sidx *x) { free(x->segs); x->segs = NULL; x->n = 0; }
void tb_frag_free(tb_frag *f) { free(f->s); f->s = NULL; f->n = 0; }
