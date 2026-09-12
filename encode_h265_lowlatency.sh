#!/bin/bash
# Low latency, low quality H.265/HEVC encode (ultrafast preset, zerolatency tune, no B-frames, 200k target bitrate).
# Unlike AV1, HEVC muxes fine into .ts, so output stays .ts.
INPUT="${1:-10s.ts}"
OUTPUT="${2:-/tmp/t1.ts}"

ffmpeg -i "$INPUT" \
  -c:v libx265 -preset ultrafast -tune zerolatency \
  -b:v 200k \
  -x265-params "bframes=0:keyint=60:min-keyint=60:scenecut=0" \
  "$OUTPUT" -y
