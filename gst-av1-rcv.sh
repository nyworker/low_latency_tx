#!/bin/bash
# GStreamer equivalent of av1-rcv.sh: receives + decodes the RTP AV1 stream
# from av1-send.sh and displays it.
#
# Stock GStreamer (1.28.2, this machine) ships no RTP AV1 (de)payloader at
# all -- gst-plugins-good's "rtp" plugin has rtpvp8depay/rtpvp9depay/etc but
# no rtpav1depay, and there's no avdec_av1/dav1d decoder either, only the
# aom-based av1dec. The payloader/depayloader exist upstream in
# gst-plugins-rs (Rust), just not packaged by Ubuntu. Built+installed here:
#   git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git
#   cd gst-plugins-rs/net/rtp && cargo cbuild --release --prefix=/usr/local \
#     && sudo cargo cinstall --release --prefix=/usr/local
# which drops libgstrsrtp.so in /usr/local/lib/x86_64-linux-gnu/gstreamer-1.0
# -- not a directory GStreamer scans by default, hence GST_PLUGIN_PATH below.
RSRTP_PLUGIN_DIR=/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0
if [ -f "$RSRTP_PLUGIN_DIR/libgstrsrtp.so" ]; then
  export GST_PLUGIN_PATH="$RSRTP_PLUGIN_DIR${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
fi

# Ultimate-low-latency tuning (each item removes a buffering stage):
#  - LATENCY_MS default 0 + mode=none: jitterbuffer only reorders by seqnum
#    and never waits on RTP-timestamp/clock-skew pacing (mode=none ignores
#    the wall-clock mapping entirely, so frames are pushed the moment they
#    are complete). faststart-min-packets=1 makes it start on the first pkt.
#  - udpsrc buffer-size small + no extra queues: nothing to accumulate.
#  - av1dec max-errors=0: the first decode error is fatal, so gst-launch
#    exits non-zero instead of limping along on corrupt/stalled frames
#    (restart to catch up to live). Any other pipeline ERROR (depay, sink,
#    socket) also makes gst-launch exit. sync=false and qos=false on the
#    sink stop it from waiting/dropping on timestamps.
#  - videoconvert only if needed; glimagesink renders straight from the
#    decoded I420 frame (GL does the YUV->RGB), avoiding a CPU convert.
#  - GST_DEBUG kept quiet and -v dropped: per-buffer caps logging costs time.
PORT="${1:-6000}"
LATENCY_MS="${2:-0}"
# Fullscreen: this is a Wayland session and glimagesink has no fullscreen
# property, so use waylandsink fullscreen=true (compositor scales the
# 640x360 stream up, keeping aspect ratio, no extra CPU convert).
# Override, e.g. windowed: SINK="glimagesink sync=false qos=false" ./gst-av1-rcv.sh
SINK="${SINK:-waylandsink fullscreen=true sync=false}"

# udpsrc timeout (ns) only posts a "GstUDPSrcTimeout" element message, not an
# error, so run with -m and have the reader kill gst-launch when it appears.
# NB: also triggers if the sender isn't up yet within NO_PKT_SECS of start.
NO_PKT_SECS="${NO_PKT_SECS:-3}"
set -o pipefail
gst-launch-1.0 -m \
  udpsrc port="$PORT" buffer-size=2097152 timeout=$((NO_PKT_SECS * 1000000000)) \
    caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=AV1,payload=96" ! \
  rtpjitterbuffer latency="$LATENCY_MS" mode=none drop-on-latency=true \
    do-retransmission=false faststart-min-packets=1 ! \
  rtpav1depay ! av1parse ! av1dec max-errors=0 ! \
  $SINK | while IFS= read -r line; do
    case $line in
      *GstUDPSrcTimeout*)
        echo "no packets for ${NO_PKT_SECS}s, quitting" >&2
        pkill -TERM -P $$ -x gst-launch-1.0
        exit 1 ;;
      # stdout is swallowed by this reader, so surface error text (and the
      # "Additional debug info" / "Execution ended" lines that follow) here.
      ERROR*|*"error message"*|*"GstMessageError"*|*"Additional debug info"*)
        echo "$line" >&2 ;;
    esac
  done
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "gst-av1-rcv: pipeline exited with status $rc" >&2
fi
exit "$rc"
