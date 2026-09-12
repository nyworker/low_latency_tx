#!/bin/bash
# Receives + decodes the RTP VP8 stream from vp8-send.sh and displays it.
# Builds its own .sdp (payload type 96 / clock rate 90000 is what ffmpeg's
# RTP muxer assigns for a single VP8 stream, same convention as AV1/H264)
# instead of depending on the file vp8-send.sh writes, so the receiver can
# bind and listen before the sender even starts. See av1-rcv.sh for the AV1
# equivalent.
FFPLAY=/usr/bin/ffplay
HOST="${1:-127.0.0.1}"
PORT="${2:-6000}"
SDP=$(mktemp --suffix=.sdp)
trap 'rm -f "$SDP"' EXIT

cat > "$SDP" <<EOF
v=0
o=- 0 0 IN IP4 $HOST
s=vp8-rcv
c=IN IP4 $HOST
t=0 0
m=video $PORT RTP/AVP 96
a=rtpmap:96 VP8/90000
EOF

"$FFPLAY" -protocol_whitelist file,udp,rtp \
  -fflags nobuffer -flags low_delay \
  -probesize 32 -analyzeduration 0 -framedrop \
  -rtbufsize 100k -threads 1 \
  -max_delay 0 -reorder_queue_size 0 \
  -i "$SDP" -x 600
