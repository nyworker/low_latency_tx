#!/bin/bash
# Low latency, low quality SVT-AV1 encode (fast preset, no lookahead, 900k target bitrate).
# Output is .mkv, not .ts: this ffmpeg build's mpegts muxer writes AV1 as an
# unrecognized private-data stream, so mpv/ffplay can't play AV1-in-.ts.
INPUT="${1:-10s.ts}"
OUTPUT="${2:-'-f mpegts udp://127.0.0.1:1234'}"

ffmpeg -i "$INPUT" \
  -c:v libsvtav1 -preset 13 \
  -b:v 200k \
  -svtav1-params rc=2:pred-struct=1:lookahead=0:keyint=60 \
  "$OUTPUT" -y
