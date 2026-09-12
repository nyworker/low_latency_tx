#!/bin/bash
# mpv equivalent of av1-rcv.sh: receives + decodes the RTP AV1 stream from
# av1-send.sh and displays it. Same .sdp-building approach (payload type 96 /
# clock rate 90000 is what ffmpeg's RTP muxer always assigns for a single AV1
# stream) so the receiver can bind and listen before the sender starts.
#
# mpv generally buffers more aggressively than ffplay (see the commented-out
# "mpv $SDP" line in av1-rcv.sh), so this exists for comparison/fallback
# rather than as the primary receiver.
MPV=/usr/bin/mpv
HOST="${1:-127.0.0.1}"
PORT="${2:-6000}"
SDP=$(mktemp --suffix=.sdp)
trap 'rm -f "$SDP"' EXIT

cat > "$SDP" <<EOF
v=0
o=- 0 0 IN IP4 $HOST
s=av1-rcv-mpv
c=IN IP4 $HOST
t=0 0
m=video $PORT RTP/AVP 96
a=rtpmap:96 AV1/90000
EOF

# --profile=low-latency is mpv's builtin low-latency bundle (1 decode thread,
# no cache-pause, nobuffer, etc. -- see `mpv --show-profile=low-latency`).
#
# --no-config: skip the user's ~/.mpv config so nothing there can re-add
# buffering on top of the low-latency tuning below.
#
# --demuxer-lavf-analyzeduration/-probesize=0/32: same intent as ffplay's
# -analyzeduration 0 -probesize 32 in av1-rcv.sh -- start decoding immediately
# instead of waiting to probe stream parameters.
#
# --demuxer-lavf-o=...: raw libavformat AVOptions, same as av1-rcv.sh's
# ffplay flags. protocol_whitelist is required since mpv's lavf demuxer
# otherwise refuses to open a .sdp that references udp/rtp. fflags
# +discardcorrupt drops partially-decoded frames from packet loss instead of
# spending decode time concealing them (av1-send.sh's keyint=5 means the next
# keyframe is at most 5 frames away, so this is cheap). max_delay=0 and
# reorder_queue_size=0 match av1-rcv.sh: don't wait to reorder RTP packets.
# The %12% prefix is mpv's escape syntax for a list value that itself
# contains the "," list separator (here, "file,udp,rtp").
#
# --framedrop=vo: drop frames that decode late instead of showing them. This
# is mpv's default already, but kept explicit since it's load-bearing here --
# see below.
#
# No audio track means mpv's default --video-sync=audio mode falls back to
# the system clock as its timing source (per `man mpv`: "If audio is
# disabled, this uses the system clock"). Combined with --framedrop=vo, that
# gives the same self-correcting behavior as av1-rcv.sh's "-sync ext
# -framedrop" in ffplay: a decode backlog gets skipped back to "live"
# instead of playing out in slow motion or drifting forever.
#
# Unlike av1-rcv.sh, this doesn't add a hard desync-and-exit watchdog: mpv
# doesn't print an ffplay-style "M-V: <diff>" line to parse, and the
# framedrop-against-system-clock behavior above already continuously
# self-corrects rather than needing an external kill+restart. If a
# bandwidth-starved link still desyncs unrecoverably in practice, wrap this
# in a restart loop the same way, e.g. `while true; do ./av1-rcv-mpv.sh; done`.
"$MPV" --no-config --profile=low-latency \
  --demuxer-lavf-analyzeduration=0 \
  --demuxer-lavf-probesize=32 \
  --demuxer-lavf-o='protocol_whitelist=%12%file,udp,rtp,fflags=+discardcorrupt,max_delay=0,reorder_queue_size=0,rtbufsize=350k' \
  --framedrop=vo \
  --autofit=800 \
  "$SDP"
