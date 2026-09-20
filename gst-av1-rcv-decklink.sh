#!/bin/bash
# Receives an RTP AV1 stream and outputs it to a DeckLink device.
# Usage: ./gst-av1-rcv-decklink.sh [port] [latency_ms]
#
# Environment overrides:
#   DEVICE=0          DeckLink device index (default 0)
#   MODE=1080p2997    DeckLink output mode  (default 1080p2997)
#   PORT=6000         UDP receive port      (default 6000)
#   LATENCY_MS=0      Jitter buffer latency (default 0)
#   NO_PKT_SECS=3     Timeout if no packets (default 3)
#
# Requires the rsrtp plugin (rtpav1depay) from gst-plugins-rs.
# Build: cd gst-plugins-rs/net/rtp && cargo cbuild --release --prefix=/usr/local
#        && sudo cargo cinstall --release --prefix=/usr/local
# which drops libgstrsrtp.dylib in /usr/local/lib/gstreamer-1.0.

# Pin to the production GStreamer to prevent Homebrew GStreamer from being
# loaded into the same process (duplicate type registration -> crash).
if [ -d /Users/txmacadmin/gst-production/lib/gstreamer-1.0 ]; then
  export GST_PLUGIN_SYSTEM_PATH=/Users/txmacadmin/gst-production/lib/gstreamer-1.0
fi

for _dir in \
    /usr/local/lib/gstreamer-1.0 \
    /opt/homebrew/lib/gstreamer-1.0; do
  if [ -f "$_dir/libgstrsrtp.dylib" ]; then
    export GST_PLUGIN_PATH="$_dir${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
    break
  fi
done

PORT="${1:-${PORT:-6000}}"
LATENCY_MS="${2:-${LATENCY_MS:-0}}"
DEVICE="${DEVICE:-0}"
MODE="${MODE:-1080p2997}"
NO_PKT_SECS="${NO_PKT_SECS:-3}"

echo $(date) starting gst-launch on port $PORT with $MODE

# av1dec outputs I420; videoconvert converts to UYVY which DeckLink accepts.
# sync=false on the sink: don't pace to timestamps — output as fast as frames
# arrive so there is no extra latency from the presentation clock.
set -o pipefail
gst-launch-1.0 -m \
  udpsrc port="$PORT" buffer-size=2097152 timeout=$((NO_PKT_SECS * 1000000000)) \
    caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=AV1,payload=96" ! \
  rtpjitterbuffer latency="$LATENCY_MS" mode=none drop-on-latency=true \
    do-retransmission=false faststart-min-packets=1 ! \
  rtpav1depay ! av1parse ! av1dec max-errors=0 ! \
  videoconvert ! \
  decklinkvideosink device-number="$DEVICE" mode="$MODE" sync=false \
  | while IFS= read -r line; do
    case $line in
      *GstUDPSrcTimeout*)
        echo "no packets for ${NO_PKT_SECS}s, quitting" >&2
        pkill -TERM -P $$ -x gst-launch-1.0
        exit 1 ;;
      ERROR*|*"error message"*|*"GstMessageError"*|*"Additional debug info"*)
        echo "$line" >&2 ;;
    esac
  done
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "gst-av1-rcv-decklink: pipeline exited with status $rc" >&2
fi
exit "$rc"
