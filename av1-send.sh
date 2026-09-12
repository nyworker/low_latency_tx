#!/bin/bash
# Low latency SVT-AV1 encode, streamed live over RTP/UDP.
# AV1-over-RTP is still an experimental ffmpeg payloader (RFC draft spec),
# hence -strict experimental. Also writes an .sdp file for reference/other
# clients, but av1-rcv.sh builds its own and doesn't need it.
#
# Captures MJPG directly from the camera at the target size/fps instead of
# capturing raw + software-scaling: skips an ffmpeg filter stage (extra
# buffering/copy) and avoids pulling raw YUYV bandwidth off the device.
#
# -bufsize caps SVT-AV1's CBR (rc=2) VBV buffer. Left unset, ffmpeg/SVT-AV1
# defaults it large enough to smooth bitrate over ~2s of frames, which shows
# up as ~2s of steady-state glass-to-glass latency even with lookahead=0.
# 60k bits =~ 1.5 frames at 600kbps/15fps, confirmed via the encoder's
# reported "buffer size" side data matching this value.
#
# -fflags nobuffer on the input cuts demuxer-side read buffering on the v4l2
# capture — confirmed with a plain `ffplay -fflags nobuffer -input_format
# mjpeg /dev/video0` test showing a big drop vs. without it.
#
# -fflags +flush_packets on the output makes the rtp muxer write each packet
# out immediately instead of holding it — ffmpeg's own docs describe this
# flag as reducing latency.
#
# keyint=15 (was 60): the real cause of the >1s (up to ~4s) latency was GOP
# size, not any of the above. keyint=60 at 15fps means a keyframe only every
# 4 seconds. Confirmed by piping the encoder straight into a decoder with no
# RTP/network at all: a decoder attaching mid-GOP had to wait for the *next*
# keyframe before producing any output — up to the full 4s GOP length. Any
# late receiver start, or a dropped/reordered keyframe packet (keyframes are
# far bigger than P-frames, so they fragment across many more RTP packets
# and are the most loss-prone thing in the stream), pays that same wait.
# This is codec-independent — VP8 (-g 60) hit the identical wall — which is
# why swapping codecs never changed the observed latency. keyint=15 (1s)
# bounds the worst case to ~1s at the cost of somewhat higher average
# bitrate from more frequent (larger) keyframes.
HOST="${1:-127.0.0.1}"
PORT="${2:-6000}"
SDP="${3:-/tmp/av1-stream.sdp}"

# drawtext: each ":" inside a %{...} expansion is an argument separator at the
# expansion level *and* an option separator at the filtergraph level, and no
# amount of backslashes survives both (ffmpeg 8 ends the quoted run at "\\:").
# So the clock is built from one expansion per field with the literal colons
# outside the braces, where they only need the single filtergraph-level escape.
OL="drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='%{localtime\:%Y-%m-%d} %{localtime\:%H}\:%{localtime\:%M}\:%{localtime\:%S}':x=w-tw-30:y=h-th-30:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=10"

INPUT='-video_size 640x360 -framerate 30 -i /dev/video0'
INPUT='-input_format mjpeg -video_size 640x360 -framerate 30 -i /dev/video0' # v4l2-ctl -d /dev/video0 --list-formats-ext
INPUT='-re -stream_loop -1 -i t.ts '
ffmpeg -fflags nobuffer $INPUT -vf "$OL" \
  -an -c:v libsvtav1 -preset 13 \
  -b:v 900k -bufsize 1260k \
  -svtav1-params rc=2:pred-struct=1:lookahead=0:keyint=15 \
  -strict experimental -fflags +flush_packets \
  -f rtp -sdp_file "$SDP" "rtp://$HOST:$PORT" -y

