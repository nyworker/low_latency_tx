#!/bin/bash
# SRT variant of av1-send.sh: same capture/encode chain, but streamed over
# SRT instead of raw RTP/UDP.
#
# Container: ffmpeg's mpegts muxer on this build tags AV1 as an unrecognized
# "private data stream" (confirmed by round-tripping through ffprobe -- it
# comes back as codec_name=bin_data), so mpegts is not an option here, unlike
# the usual SRT-carries-MPEGTS convention. `-f ivf` is used instead: On2's IVF
# is a minimal size+timestamp-prefixed frame container that ffmpeg tags
# correctly as AV01 and that streams fine over a non-seekable socket (the
# frame-count field in its header just stays at the streaming placeholder).
# SRT itself is transport-only and doesn't care what bytes it carries, so any
# self-framing container works -- IVF has near-zero overhead per frame,
# unlike the RTP path's codec-aware AV1 payloader/depayloader.
#
# SRT vs RTP/UDP here: SRT adds a connection handshake (this script connects
# as the "caller", av1-rcv-srt.sh listens as the "connection" acceptor) and
# its own ARQ (automatic retransmit) layer on top of UDP. That trades some of
# the RTP path's "just drop it and wait for the next keyframe" simplicity for
# actual loss recovery, at the cost of the `-latency` buffer below. Keeping
# that buffer small is the whole ballgame for matching the RTP path's
# latency -- see LATENCY_US.
#
# All of the encoder-side latency work from av1-send.sh (mjpeg capture,
# nobuffer, bufsize-capped CBR, short keyint, flush_packets) still applies
# unchanged since it's on the encode side, not the transport.
HOST="${1:-127.0.0.1}"
PORT="${2:-6000}"
# SRT's -latency is its receive buffer for reordering/retransmit (microsec).
# Left at the library default (120ms) it becomes ~120ms of steady-state
# glass-to-glass latency on its own, on top of everything else -- the SRT
# analogue of the -bufsize lesson in av1-send.sh. 60ms is comfortably above
# a LAN/tailnet RTT (so a single retransmit still lands in time) without
# reintroducing that buffering hit. Raise this if the link is lossier/higher
# RTT than a tailnet hop and frames are stalling instead of dropping.
LATENCY_US="${3:-60000}"

FFMPEG=/usr/bin/ffmpeg # must match the libsrt-enabled build; see av1-rcv-srt.sh

# drawtext: each ":" inside a %{...} expansion is an argument separator at the
# expansion level *and* an option separator at the filtergraph level, and no
# amount of backslashes survives both (ffmpeg 8 ends the quoted run at "\\:").
# So the clock is built from one expansion per field with the literal colons
# outside the braces, where they only need the single filtergraph-level escape.
OL="drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='%{localtime\:%Y-%m-%d} %{localtime\:%H}\:%{localtime\:%M}\:%{localtime\:%S}':x=w-tw-30:y=h-th-30:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=10"

INPUT='-video_size 640x360 -framerate 30 -i /dev/video0'
INPUT='-input_format mjpeg -video_size 640x360 -framerate 30 -i /dev/video0' # v4l2-ctl -d /dev/video0 --list-formats-ext
INPUT='-re -stream_loop -1 -i t.ts '

# transtype=live and tlpktdrop=1 are the SRT library's own defaults for this
# use case, but are named explicitly since correctness here depends on them
# (tlpktdrop is what makes SRT skip a packet that missed its delivery
# deadline instead of stalling the whole stream waiting for a retransmit).
SRT_URL="srt://$HOST:$PORT?mode=caller&transtype=live&latency=$LATENCY_US&tlpktdrop=1&nakreport=1"

"$FFMPEG" -fflags nobuffer $INPUT -vf "$OL" \
  -an -c:v libsvtav1 -preset 13 \
  -b:v 900k -bufsize 1260k \
  -svtav1-params rc=2:pred-struct=1:lookahead=0:keyint=15 \
  -strict experimental -fflags +flush_packets \
  -f ivf "$SRT_URL" -y
