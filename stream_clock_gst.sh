#!/bin/bash
INPUT="${1:-t-g1.ts}"

gst-launch-1.0 -v \
  filesrc location="$INPUT" ! tsdemux name=d \
  d. ! queue ! mpegvideoparse ! avdec_mpeg2video ! videoconvert ! \
    clockoverlay time-format="%H:%M:%S" \
      font-desc="DejaVu Sans Bold 28" \
      halignment=left valignment=top xpad=10 ypad=10 ! \
    timeoverlay \
      font-desc="DejaVu Sans Bold 28" \
      halignment=left valignment=top xpad=10 ypad=50 ! \
    x264enc bitrate=8000 key-int-max=1 speed-preset=ultrafast tune=zerolatency ! \
    h264parse ! avdec_h264 ! videoconvert ! \
    autovideosink \
  d. ! queue ! mpegaudioparse ! avdec_mp2float ! audioconvert ! autoaudiosink
