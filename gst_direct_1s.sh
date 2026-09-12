gst-launch-1.0 filesrc location=t.ts ! tsdemux ! \
  queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 ! \
  h264parse ! avdec_h264 direct-rendering=true ! videoconvert ! \
  clockoverlay time-format="%M:%S" ! \
  x264enc key-int-max=1 speed-preset=ultrafast tune=zerolatency ! \
  h264parse ! avdec_h264 direct-rendering=true ! videoconvert ! \
  autovideosink sync=false
