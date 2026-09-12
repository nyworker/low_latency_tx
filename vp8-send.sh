#!/bin/bash
# Low latency VP8 encode via ffmpeg/libvpx, streamed live over RTP/UDP.
# Companion to av1-send.sh for a side-by-side latency comparison: same
# capture setup and transport, much cheaper/more mature codec + decoder path.
#
# -fflags nobuffer cuts demuxer-side read buffering on the v4l2 capture —
# confirmed with a plain `ffplay -fflags nobuffer -input_format mjpeg
# /dev/video0` test showing a big drop vs. without it.
#
# -lag-in-frames 0 -rc_lookahead 0: no encoder lookahead (libvpx defaults
# rc_lookahead to 25 frames, which alone would add well over a second of
# delay at 15fps).
#
# -bufsize caps libvpx's CBR buffer the same way as av1-send.sh's SVT-AV1
# -bufsize: without it, ffmpeg's default is large enough to smooth bitrate
# over roughly a second-plus of frames.
#
# -fflags +flush_packets on the output makes the rtp muxer write each packet
# out immediately instead of holding it.
#
# -g 15 (was 60): the real cause of the >1s (up to ~4s) latency was GOP
# size, not any of the above — see av1-send.sh for the full writeup. -g 60
# at 15fps means a keyframe only every 4 seconds; any late receiver start or
# dropped/reordered keyframe packet stalls playback until the next one. This
# is codec-independent, which is why AV1 and VP8 hit the identical wall.
# -g 15 (1s) bounds the worst case to ~1s.
HOST="${1:-127.0.0.1}"
PORT="${2:-6000}"
SDP="${3:-/tmp/vp8-stream.sdp}"

ffmpeg -fflags nobuffer -f v4l2 -input_format mjpeg -video_size 640x360 -framerate 15 -i /dev/video0 \
  -an -c:v libvpx -deadline realtime -cpu-used 16 -lag-in-frames 0 -rc_lookahead 0 \
  -b:v 600k -bufsize 60k -g 15 -fflags +flush_packets \
  -f rtp -sdp_file "$SDP" "rtp://$HOST:$PORT" -y
