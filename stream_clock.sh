#!/bin/bash
INPUT="${1:-t.ts}"
OUTPUT="${2:-udp://127.0.0.1:1000}"

ffmpeg -re -i "$INPUT" \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='Wall\: %{localtime\:%T} | PTS\: %{pts\:hms}':\
fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:x=10:y=10" \
  -c:v libx264 -preset ultrafast -tune zerolatency -g 1 \
  -c:a copy -f mpegts - | ffplay -fflags nobuffer -flags low_delay \
    -probesize 32 -analyzeduration 0 -framedrop -sync ext - -x 600
  #c:a copy -f mpegts "$OUTPUT"
