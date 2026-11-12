#include "tb_ts.h"
#include <stdlib.h>
#include <string.h>

enum { PID_PMT = 0x1000, PID_VIDEO = 0x100, PID_AUDIO = 0x101 };
/* Added to every PTS/DTS so B-frame composition offsets never go negative: 1.4 s at 90 kHz. */
#define TS_OFFSET 126000ULL
/* AAC frames per PES: 8 x 1024 samples = 186 ms at 44.1 kHz. Fewer PES headers, still fine-grained. */
#define AAC_PER_PES 8

static int out_reserve(tb_out *o, size_t more) {
    if (o->len + more <= o->cap) return 0;
    size_t cap = o->cap ? o->cap : 65536;
    while (cap < o->len + more) cap *= 2;
    uint8_t *p = realloc(o->p, cap);
    if (!p) return -1;
    o->p = p;
    o->cap = cap;
    return 0;
}
static int out_add(tb_out *o, const void *d, size_t n) {
    if (out_reserve(o, n)) return -1;
    memcpy(o->p + o->len, d, n);
    o->len += n;
    return 0;
}
void tb_out_free(tb_out *o) { free(o->p); memset(o, 0, sizeof *o); }

static uint32_t crc32_mpeg(const uint8_t *p, size_t n) {
    uint32_t c = 0xffffffffu;
    while (n--) {
        c ^= (uint32_t)*p++ << 24;
        for (int i = 0; i < 8; i++) c = c & 0x80000000u ? c << 1 ^ 0x04c11db7u : c << 1;
    }
    return c;
}

/* One PSI section (PAT or PMT) in one packet. */
static int write_psi(tb_out *o, int pid, const uint8_t *sec, size_t n) {
    uint8_t pkt[188];
    memset(pkt, 0xff, sizeof pkt);
    pkt[0] = 0x47;
    pkt[1] = 0x40 | (uint8_t)(pid >> 8);
    pkt[2] = (uint8_t)pid;
    pkt[3] = 0x10;
    pkt[4] = 0; /* pointer field */
    memcpy(pkt + 5, sec, n);
    uint32_t crc = crc32_mpeg(sec, n);
    pkt[5 + n] = (uint8_t)(crc >> 24);
    pkt[6 + n] = (uint8_t)(crc >> 16);
    pkt[7 + n] = (uint8_t)(crc >> 8);
    pkt[8 + n] = (uint8_t)crc;
    return out_add(o, pkt, 188);
}

int tb_ts_tables(tb_out *o, int video_pid, int audio_pid, int pcr_pid) {
    const uint8_t pat[] = {0x00, 0xb0, 0x0d, 0x00, 0x01, 0xc1, 0x00, 0x00, 0x00, 0x01, 0xe0 | (PID_PMT >> 8), PID_PMT & 0xff};
    if (write_psi(o, 0, pat, sizeof pat)) return -1;
    uint8_t pmt[32];
    size_t n = 0;
    pmt[n++] = 0x02;
    n += 2;
    pmt[n++] = 0x00; pmt[n++] = 0x01; pmt[n++] = 0xc1; pmt[n++] = 0x00; pmt[n++] = 0x00;
    pmt[n++] = 0xe0 | (uint8_t)(pcr_pid >> 8); pmt[n++] = (uint8_t)pcr_pid;
    pmt[n++] = 0xf0; pmt[n++] = 0x00;
    if (video_pid > 0) { pmt[n++] = 0x1b; pmt[n++] = 0xe0 | (uint8_t)(video_pid >> 8); pmt[n++] = (uint8_t)video_pid; pmt[n++] = 0xf0; pmt[n++] = 0; }
    if (audio_pid > 0) { pmt[n++] = 0x0f; pmt[n++] = 0xe0 | (uint8_t)(audio_pid >> 8); pmt[n++] = (uint8_t)audio_pid; pmt[n++] = 0xf0; pmt[n++] = 0; }
    size_t seclen = n - 3 + 4;
    pmt[1] = 0xb0 | (uint8_t)(seclen >> 8);
    pmt[2] = (uint8_t)seclen;
    return write_psi(o, PID_PMT, pmt, n);
}

static int write_tables(tb_out *o, int has_video, int has_audio) {
    const uint8_t pat[] = {0x00, 0xb0, 0x0d, 0x00, 0x01, 0xc1, 0x00, 0x00, 0x00, 0x01, 0xe0 | (PID_PMT >> 8), PID_PMT & 0xff};
    if (write_psi(o, 0, pat, sizeof pat)) return -1;
    uint8_t pmt[32];
    int pcr = has_video ? PID_VIDEO : PID_AUDIO;
    size_t n = 0;
    pmt[n++] = 0x02;
    n += 2; /* length below */
    pmt[n++] = 0x00; pmt[n++] = 0x01; pmt[n++] = 0xc1; pmt[n++] = 0x00; pmt[n++] = 0x00;
    pmt[n++] = 0xe0 | (uint8_t)(pcr >> 8); pmt[n++] = (uint8_t)pcr;
    pmt[n++] = 0xf0; pmt[n++] = 0x00;
    if (has_video) { pmt[n++] = 0x1b; pmt[n++] = 0xe0 | (PID_VIDEO >> 8); pmt[n++] = PID_VIDEO & 0xff; pmt[n++] = 0xf0; pmt[n++] = 0; }
    if (has_audio) { pmt[n++] = 0x0f; pmt[n++] = 0xe0 | (PID_AUDIO >> 8); pmt[n++] = PID_AUDIO & 0xff; pmt[n++] = 0xf0; pmt[n++] = 0; }
    size_t seclen = n - 3 + 4;
    pmt[1] = 0xb0 | (uint8_t)(seclen >> 8);
    pmt[2] = (uint8_t)seclen;
    return write_psi(o, PID_PMT, pmt, n);
}

static void put_ts(uint8_t *p, int tag, uint64_t t) {
    t &= 0x1ffffffffULL;
    p[0] = (uint8_t)(tag << 4 | ((t >> 29) & 0x0e) | 1);
    p[1] = (uint8_t)(t >> 22);
    p[2] = (uint8_t)(((t >> 14) & 0xfe) | 1);
    p[3] = (uint8_t)(t >> 7);
    p[4] = (uint8_t)(((t << 1) & 0xfe) | 1);
}

/* Packetize one PES. pcr >= 0: put a PCR in the first packet. */
int tb_ts_pes(tb_out *o, int pid, int *cc, int stream_id, uint64_t pts, int64_t dts, int64_t pcr, int rai,
              const uint8_t *payload, size_t plen) {
    uint8_t hdr[19];
    size_t hl = 0;
    hdr[hl++] = 0; hdr[hl++] = 0; hdr[hl++] = 1; hdr[hl++] = (uint8_t)stream_id;
    int with_dts = dts >= 0 && (uint64_t)dts != pts;
    size_t optl = with_dts ? 10 : 5;
    size_t pes_len = 3 + optl + plen;
    if (stream_id == 0xe0 || pes_len > 0xffff) pes_len = 0; /* video: unbounded is allowed */
    hdr[hl++] = (uint8_t)(pes_len >> 8); hdr[hl++] = (uint8_t)pes_len;
    hdr[hl++] = 0x80;
    hdr[hl++] = with_dts ? 0xc0 : 0x80;
    hdr[hl++] = (uint8_t)optl;
    put_ts(hdr + hl, with_dts ? 3 : 2, pts); hl += 5;
    if (with_dts) { put_ts(hdr + hl, 1, (uint64_t)dts); hl += 5; }

    size_t total = hl + plen, done = 0;
    int first = 1;
    while (done < total) {
        if (out_reserve(o, 188)) return -1;
        uint8_t *pkt = o->p + o->len;
        pkt[0] = 0x47;
        pkt[1] = (uint8_t)((first ? 0x40 : 0) | pid >> 8);
        pkt[2] = (uint8_t)pid;
        size_t af = 0; /* adaptation field bytes including its length byte */
        uint8_t afb[188];
        if (first && (pcr >= 0 || rai)) {
            afb[1] = (uint8_t)((rai ? 0x40 : 0) | (pcr >= 0 ? 0x10 : 0));
            af = 2;
            if (pcr >= 0) {
                uint64_t b = (uint64_t)pcr & 0x1ffffffffULL;
                afb[2] = (uint8_t)(b >> 25); afb[3] = (uint8_t)(b >> 17); afb[4] = (uint8_t)(b >> 9);
                afb[5] = (uint8_t)(b >> 1); afb[6] = (uint8_t)((b & 1) << 7 | 0x7e); afb[7] = 0;
                af = 8;
            }
        }
        size_t room = 184 - af, left = total - done;
        if (left < room) { /* stuffing */
            size_t stuff = room - left;
            if (af == 0) {
                if (stuff == 1) { af = 1; }
                else { afb[1] = 0; memset(afb + 2, 0xff, stuff - 2); af = stuff; }
            } else { memset(afb + af, 0xff, stuff); af += stuff; }
            room = left;
        }
        pkt[3] = (uint8_t)((af ? 0x30 : 0x10) | (*cc & 15));
        *cc = (*cc + 1) & 15;
        if (af) { afb[0] = (uint8_t)(af - 1); memcpy(pkt + 4, afb, af); }
        uint8_t *dst = pkt + 4 + af;
        size_t take = room;
        /* copy from header then payload */
        while (take > 0) {
            if (done < hl) {
                size_t k = hl - done < take ? hl - done : take;
                memcpy(dst, hdr + done, k); dst += k; done += k; take -= k;
            } else {
                memcpy(dst, payload + (done - hl), take); done += take; dst += take; take = 0;
            }
        }
        o->len += 188;
        first = 0;
    }
    return 0;
}

static uint64_t to90k(uint64_t t, uint32_t ts) { return t * 90000ULL / ts; }

/* Annex B access unit: AUD, SPS+PPS on keyframes, then the NAL units of the sample. */
static int build_au(tb_out *au, const tb_track *t, const uint8_t *p, size_t n, int key) {
    static const uint8_t sc[4] = {0, 0, 0, 1}, aud[2] = {0x09, 0xf0};
    au->len = 0;
    if (out_add(au, sc, 4) || out_add(au, aud, 2)) return -1;
    if (key) {
        if (out_add(au, sc, 4) || out_add(au, t->sps, (size_t)t->sps_len)) return -1;
        if (out_add(au, sc, 4) || out_add(au, t->pps, (size_t)t->pps_len)) return -1;
    }
    size_t o = 0;
    int ls = t->nal_len_size;
    while (o + (size_t)ls <= n) {
        uint32_t len = 0;
        for (int i = 0; i < ls; i++) len = len << 8 | p[o + i];
        o += (size_t)ls;
        if (len == 0 || o + len > n) break;
        int type = p[o] & 31;
        if (type != 9 && !(key && (type == 7 || type == 8))) {
            if (out_add(au, sc, 4) || out_add(au, p + o, len)) return -1;
        }
        o += len;
    }
    return 0;
}

static int adts_frame(tb_out *o, const tb_track *t, const uint8_t *p, size_t n) {
    size_t len = n + 7;
    uint8_t h[7] = {0xff, 0xf1,
                    (uint8_t)(((t->aac_object - 1) & 3) << 6 | (t->aac_freq_index & 15) << 2 | (t->aac_channels >> 2 & 1)),
                    (uint8_t)((t->aac_channels & 3) << 6 | (len >> 11 & 3)),
                    (uint8_t)(len >> 3), (uint8_t)((len & 7) << 5 | 0x1f), 0xfc};
    return out_add(o, h, 7) || out_add(o, p, n) ? -1 : 0;
}

int tb_ts_segment(tb_out *out, const tb_ts_input *v, const tb_ts_input *a) {
    int hv = v && v->n > 0, ha = a && a->n > 0;
    if (!hv && !ha) return -1;
    if (write_tables(out, hv, ha)) return -1;
    int ccv = 0, cca = 0;
    int vi = 0, ai = 0;
    tb_out au = {0}, pes = {0};
    int rc = 0;
    while ((hv && vi < v->n) || (ha && ai < a->n)) {
        double tv = hv && vi < v->n ? (double)v->s[vi].dts / v->track->timescale : 1e30;
        double ta = ha && ai < a->n ? (double)a->s[ai].dts / a->track->timescale : 1e30;
        if (tv <= ta) {
            const tb_sample *s = &v->s[vi++];
            if ((size_t)s->offset + s->size > v->data_len) { rc = -2; break; }
            if (build_au(&au, v->track, v->data + s->offset, s->size, s->key)) { rc = -1; break; }
            uint64_t dts = to90k(s->dts, v->track->timescale) + TS_OFFSET;
            int64_t cto90 = (int64_t)s->cto * 90000 / (int64_t)v->track->timescale;
            uint64_t pts = (uint64_t)((int64_t)dts + cto90);
            if (tb_ts_pes(out, PID_VIDEO, &ccv, 0xe0, pts, (int64_t)dts, (int64_t)dts - 9000, s->key, au.p, au.len)) { rc = -1; break; }
        } else {
            const tb_sample *s0 = &a->s[ai];
            pes.len = 0;
            int k = 0;
            for (; k < AAC_PER_PES && ai < a->n; k++, ai++) {
                const tb_sample *s = &a->s[ai];
                if (hv && vi < v->n && k > 0 && (double)s->dts / a->track->timescale > tv) break;
                if ((size_t)s->offset + s->size > a->data_len) { rc = -2; break; }
                if (adts_frame(&pes, a->track, a->data + s->offset, s->size)) { rc = -1; break; }
            }
            if (rc) break;
            uint64_t pts = to90k(s0->dts, a->track->timescale) + TS_OFFSET;
            if (tb_ts_pes(out, PID_AUDIO, &cca, 0xc0, pts, -1, hv ? -1 : (int64_t)pts - 9000, 0, pes.p, pes.len)) { rc = -1; break; }
        }
    }
    tb_out_free(&au);
    tb_out_free(&pes);
    return rc;
}
