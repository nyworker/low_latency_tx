#!/usr/bin/env bash
#
# gst-av1-rcv-macos3.sh [port]
#
# Receiver for gst-av1-send-macos3.sh: one-way, no RTCP, loss-tolerant.
# After a lost packet the depayloader drops everything up to the next
# keyframe (the sender sends one every KEYINT frames), so the picture briefly
# freezes instead of smearing, and the decoder never sees broken data. Unlike
# gst-av1-rcv-macos.sh it does not exit on decode errors; it only exits
# when no packets arrive for NO_PKT_SECS, e.g. because the sender went away.
#
# Environment:
#   LATENCY_MS   jitterbuffer reorder window, ms (default: 0)
#   NO_PKT_SECS  exit when nothing arrives for this long (default: 3; 0 = never)
#   SINK         video sink (default: glimagesink sync=false qos=false)

cd "$(dirname "$0")"
## source ./gst-env.sh >/dev/null

set -uo pipefail

PORT="${1:-6000}"
LATENCY_MS="${LATENCY_MS:-0}"
NO_PKT_SECS="${NO_PKT_SECS:-3}"
SINK="${SINK:-glimagesink sync=false qos=false}"

# Large socket buffer so a keyframe burst is never dropped by the kernel
# (macOS caps this at kern.ipc.maxsockbuf).
gst-launch-1.0 -m \
  udpsrc port="$PORT" buffer-size=4194304 timeout=$((NO_PKT_SECS * 1000000000)) \
    caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=AV1,payload=96" ! \
  rtpjitterbuffer latency="$LATENCY_MS" mode=none drop-on-latency=true \
    do-retransmission=false do-lost=true faststart-min-packets=1 ! \
  rtpav1depay wait-for-keyframe=true request-keyframe=false ! \
  av1parse ! av1dec max-errors=-1 discard-corrupted-frames=true \
    automatic-request-sync-points=false ! \
  $SINK | while IFS= read -r line; do
    case $line in
      *GstUDPSrcTimeout*)
        echo "no packets for ${NO_PKT_SECS}s, quitting" >&2
        pkill -TERM -P $$ -x gst-launch-1.0
        exit 1 ;;
      ERROR*|*"Additional debug info"*)
        echo "$line" >&2 ;;
    esac
  done

