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

PORT="${1:-6000}"
LATENCY_MS="${2:-50}"

# rtpjitterbuffer latency=$LATENCY_MS: how long it holds packets waiting for
# reordering before releasing them -- the gst analogue of av1-rcv.sh's
# -reorder_queue_size 0, kept small on purpose for low latency.
#
# drop-on-latency=true: once the buffer is full, drop old packets rather
# than blocking -- this is what gives catch-up behavior when decode falls
# behind, instead of an ever-growing backlog. Unlike av1-rcv.sh's
# desync-then-exit-and-restart design (there's no audio/wall-clock master
# to measure drift against here, and no M-V-style stat to watch for it),
# this pipeline self-recovers in place and never needs the
# `while true; do ./gst-av1-rcv.sh; done` restart wrapper av1-rcv.sh needs.
#
# do-retransmission=false: av1-send.sh is one-way RTP with no RTCP
# feedback loop, so there's nothing on the other end to ask for a resend.
#
# av1parse between the depayloader and decoder: rtpav1depay emits
# alignment=obu (one OBU per buffer) but av1dec requires alignment=tu
# (one full temporal unit per buffer); av1parse does that regrouping.
#
# autovideosink sync=false: don't block the pipeline pacing output to the
# buffer's own timestamps -- render frames as they arrive, same motivation
# as av1-rcv.sh's -sync ext + -framedrop (show live, don't queue).
gst-launch-1.0 -v \
  udpsrc port="$PORT" \
    caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=AV1,payload=96" ! \
  rtpjitterbuffer latency="$LATENCY_MS" drop-on-latency=true do-retransmission=false ! \
  rtpav1depay ! av1parse ! av1dec ! \
  videoconvert ! autovideosink sync=false
