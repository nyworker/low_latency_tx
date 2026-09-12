#!/bin/bash
HOST="${1:-127.0.0.1}"

gst-launch-1.0 -v \
  rtpbin name=rtpbin latency=0 drop-on-latency=true do-retransmission=false \
  udpsrc port=5000 \
    caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
    rtpbin.recv_rtp_sink_0 \
  rtpbin. ! rtph264depay ! h264parse ! \
    avdec_h264 direct-rendering=true ! videoconvert ! \
    autovideosink sync=false \
  udpsrc port=5001 ! rtpbin.recv_rtcp_sink_0 \
  rtpbin.send_rtcp_src_0 ! udpsink host="$HOST" port=5005 sync=false async=false
