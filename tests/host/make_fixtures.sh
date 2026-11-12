#!/bin/bash
# Synthetic DASH-style fragmented MP4s with the same box layout as YouTube's (ftyp, moov, sidx, moof+mdat...).
# Video: H.264 Main, 2 s GOP = 2 s fragments, B-frames (composition offsets). Audio: AAC-LC 44.1 kHz, 3 s fragments.
set -euo pipefail
D="${1:-build/fixtures}"
mkdir -p "$D"
if [ ! -s "$D/v.mp4" ] || [ ! -s "$D/a.mp4" ]; then
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc=size=320x180:rate=30 -t 12 -pix_fmt yuv420p -c:v libx264 \
  -profile:v main -g 60 -keyint_min 60 -sc_threshold 0 -bf 2 -an -movflags +frag_keyframe+empty_moov+default_base_moof+global_sidx "$D/v.mp4"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i sine=frequency=440:sample_rate=44100 -t 12 -c:a aac -b:a 128k \
  -frag_duration 3000000 -movflags +empty_moov+default_base_moof+global_sidx "$D/a.mp4"
fi
# Live-like pieces: a video-only MPEG-TS segment (like YouTube live) and ADTS audio (packed audio, no ID3 here).
[ -s "$D/live_v.ts" ] || ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc=size=320x180:rate=30 -t 5 -pix_fmt yuv420p -c:v libx264 \
  -profile:v main -g 150 -bf 0 -an -f mpegts "$D/live_v.ts"
[ -s "$D/live_a.aac" ] || ffmpeg -hide_banner -loglevel error -y -f lavfi -i sine=frequency=440:sample_rate=44100 -t 5 -c:a aac -b:a 128k -f adts "$D/live_a.aac"
