#!/bin/bash
# SRT variant of av1-rcv.sh: receives + decodes the IVF/AV1-over-SRT stream
# from av1-send-srt.sh and displays it.
#
# Unlike RTP/UDP, an SRT "listener" socket really does bind to the host given
# in its URL (it's a real connection-oriented accept(), not just a
# datagram sink), so HOST here isn't cosmetic the way it is in av1-rcv.sh's
# SDP -- it changes what can actually connect. Defaults to 0.0.0.0 (all
# interfaces) rather than av1-rcv.sh's 127.0.0.1 default, since the real
# usage pattern (see note) is running this with no arguments while the
# sender is a different machine on the tailnet; pass 127.0.0.1 explicitly for
# a loopback-only test.
#
# Uses /usr/bin/ffplay explicitly: this machine also has an older custom
# ffmpeg build on PATH (~/ffmpeg-ndi/bin) that isn't built with libsrt at
# all (no srt:// protocol support), so it must match the ffmpeg used to
# encode/send.
FFPLAY=/usr/bin/ffplay
HOST="${1:-0.0.0.0}"
PORT="${2:-6000}"
DESYNC_LIMIT="${3:-2.0}"
# Must be set the same as av1-send-srt.sh's LATENCY_US -- SRT negotiates the
# two peers' configured latency and effectively uses the larger one, so
# mismatched values just make this side's setting a no-op.
LATENCY_US="${4:-60}"

SRT_URL="srt://$HOST:$PORT?mode=listener&transtype=live&latency=$LATENCY_US&tlpktdrop=1&nakreport=1"

# -sync ext: with no audio track, ffplay's default master clock is the video
# stream's own clock, so -framedrop has nothing external to fall behind --
# it never triggers and a decode backlog from bad network just plays out in
# slow motion instead of catching up. Locking sync to the system wall clock
# gives -framedrop a real target: any frame that decodes late gets skipped
# instead of shown, so playback snaps back to "live" instead of drifting.
#
# Bandwidth-starved network (encoder outrunning the link) can desync faster
# than -framedrop can claw back. Rather than let that drift grow unbounded,
# watch ffplay's own -stats line: with -sync ext and a video-only stream it
# prints "M-V: <diff>" = master(wall clock) vs video clock, which grows in
# magnitude whenever decode falls behind live (see av1-rcv.sh for the
# original measurement). Once |diff| exceeds $DESYNC_LIMIT seconds, kill
# ffplay.
#
# There's no RTP fragment-reassembly failure mode to watch for here (SRT
# retransmits or drops whole packets below the codec level instead of
# leaving partial OBUs for the depacketizer to choke on), so this loop only
# needs the M-V desync trigger, not av1-rcv.sh's second grep for AV1 RTP
# frag-sequence mismatches.
#
# Deliberately NOT using av1-rcv.sh's `-fflags nobuffer`: measured here to
# cause ~1s of "Error parsing OBU data" from libdav1d at every connect (the
# stream resyncs on its own after that, but it's a real, repeatable glitch).
# nobuffer disables ffmpeg's input-side read buffering, and something about
# reading IVF's length-prefixed frames off the still-ramping-up SRT socket
# in the smaller chunks that implies desyncs the frame boundary briefly.
# Unlike raw RTP/UDP (one recv() = one packet, so nobuffer is free there),
# IVF-over-SRT actually needs that buffering to reassemble frames cleanly,
# and dropping it costs nothing latency-wise here: SRT's own `latency`
# setting above is what actually governs end-to-end delay, not this.
# `-analyzeduration 0` was also tested and made no difference either way
# once nobuffer was removed, so it's left out too rather than added back.
#
# Rather than exiting the whole script on desync (which used to require an
# external `while true; do ./av1-rcv-srt.sh; done` to recover), the trigger
# just kills this ffplay instance and the loop below relaunches it against
# the same SRT listener -- the app keeps running and only the player
# restarts. Ctrl+C (or ffplay quitting cleanly via 'q'/window close, exit 0)
# still ends the script for good.
run_ffplay() {
  "$FFPLAY" -protocol_whitelist file,udp,rtp,srt \
    -fflags discardcorrupt -flags low_delay \
    -probesize 4096 -framedrop -sync ext -stats \
    -rtbufsize 350k -threads 1 \
    -i "$SRT_URL" -x 800 \
    2> >(tee /dev/stderr | tr '\r' '\n' | while IFS= read -r line; do
          diff=$(grep -oP 'M-V:\s*\K-?[0-9.]+' <<< "$line") || continue
          awk -v d="$diff" -v lim="$DESYNC_LIMIT" 'BEGIN{ad = d<0?-d:d; exit !(ad>lim)}' || continue
          echo "av1-rcv-srt: ${diff}s behind live (> ${DESYNC_LIMIT}s), resetting input" >&2
          pkill -f "$SRT_URL"
          break
        done)
}

while true; do
  run_ffplay
  status=$?
  [[ $status -eq 0 ]] && break
  sleep 0.2
done
