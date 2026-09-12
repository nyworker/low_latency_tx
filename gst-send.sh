#!/bin/bash
INPUT="${1:-t.ts}"
HOST="${2:-127.0.0.1}"

gst-launch-1.0 -v \
  rtpbin name=rtpbin \
  filesrc location="$INPUT" ! tsdemux name=d \
  d. ! queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 ! \
    h264parse ! avdec_h264 direct-rendering=true ! videoconvert ! \
    clockoverlay time-format="%H:%M:%S" \
      font-desc="DejaVu Sans Bold 28" \
      halignment=left valignment=top xpad=10 ypad=10 ! \
    x264enc key-int-max=30 speed-preset=ultrafast tune=zerolatency bitrate=6000 ! \
    rtph264pay config-interval=1 pt=96 ! rtpbin.send_rtp_sink_0 \
  rtpbin.send_rtp_src_0  ! udpsink host="$HOST" port=5000 \
  rtpbin.send_rtcp_src_0 ! udpsink host="$HOST" port=5001 sync=false async=false \
  udpsrc port=5005 ! rtpbin.recv_rtcp_sink_0
