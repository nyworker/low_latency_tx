#!/bin/bash
# GStreamer AV1 RTP receiver for macOS (ARM/x86).
# Receives + decodes the RTP AV1 stream from av1-send.sh and displays it.
#
# The RTP AV1 (de)payloader lives in gst-plugins-rs (Rust), not in any
# Homebrew-packaged GStreamer plugin.  Build and install it:
#   git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git
#   cd gst-plugins-rs/net/rtp
#   cargo cbuild --release --prefix=/usr/local
#   sudo cargo cinstall --release --prefix=/usr/local
# which drops libgstrsrtp.dylib in /usr/local/lib/gstreamer-1.0.
# Homebrew GStreamer also scans /opt/homebrew/lib/gstreamer-1.0 (ARM default).
# If running the production GStreamer build (not Homebrew), lock the plugin
# system path to avoid loading Homebrew's GStreamer plugins into the same
# process, which causes duplicate type registration and crashes.
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

# Ultimate-low-latency tuning (each item removes a buffering stage):
#  - LATENCY_MS default 0 + mode=none: jitterbuffer only reorders by seqnum
#    and never waits on RTP-timestamp/clock-skew pacing (mode=none ignores
#    the wall-clock mapping entirely, so frames are pushed the moment they
#    are complete). faststart-min-packets=1 makes it start on the first pkt.
#  - udpsrc buffer-size small + no extra queues: nothing to accumulate.
#  - av1dec max-errors=0: the first decode error is fatal, so gst-launch
#    exits non-zero instead of limping along on corrupt/stalled frames
#    (restart to catch up to live). Any other pipeline ERROR also exits.
#    Use dav1ddec instead if gst-plugins-bad was built with dav1d support.
#  - sync=false and qos=false on the sink stop it from waiting/dropping
#    on timestamps.
#  - glimagesink renders straight from the decoded frame via OpenGL
#    (GL does the YUV->RGB), avoiding a CPU convert.  Override, e.g.:
#    SINK="autovideosink" ./gst-av1-rcv-macos.sh
PORT="${1:-6000}"
LATENCY_MS="${2:-0}"
SINK="${SINK:-glimagesink sync=false qos=false}"

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
