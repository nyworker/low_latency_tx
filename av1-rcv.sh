#!/bin/bash
# Receives + decodes the RTP AV1 stream from av1-send.sh and displays it.
# Builds its own .sdp (payload type 96 / clock rate 90000 is what ffmpeg's
# RTP muxer always assigns for a single AV1 stream) instead of depending on
# the file av1-send.sh writes, so the receiver can bind and listen before
# the sender even starts.
#
# Uses /usr/bin/ffplay explicitly: this machine also has an older custom
# ffmpeg build on PATH (~/ffmpeg-ndi/bin) whose ffplay can't parse the AV1
# RTP depacketization, so it must match the ffmpeg used to encode/send.
FFPLAY=/usr/bin/ffplay
HOST="${1:-127.0.0.1}"
PORT="${2:-6000}"
DESYNC_LIMIT="${3:-2.0}"
SDP=$(mktemp --suffix=.sdp)
trap 'rm -f "$SDP"' EXIT

cat > "$SDP" <<EOF
v=0
o=- 0 0 IN IP4 $HOST
s=av1-rcv
c=IN IP4 $HOST
t=0 0
m=video $PORT RTP/AVP 96
a=rtpmap:96 AV1/90000
EOF

# mpv $SDP # even more latency!

# -sync ext: with no audio track, ffplay's default master clock is the video
# stream's own clock, so -framedrop has nothing external to fall behind —
# it never triggers and a decode backlog from bad network just plays out in
# slow motion instead of catching up. Locking sync to the system wall clock
# gives -framedrop a real target: any frame that decodes late gets skipped
# instead of shown, so playback snaps back to "live" instead of drifting.
#
# -fflags discardcorrupt: packet loss under a bad connection produces
# partially-decoded (corrupt) frames. Displaying/concealing those costs
# decode time and adds artifacts; dropping them outright is cheap here since
# av1-send.sh's keyint=5 means the next keyframe is at most 5 frames away.
#
# Bandwidth-starved network (encoder outrunning the link) can desync faster
# than -framedrop can claw back: most keyframes arrive corrupt, so decode
# never gets a clean point to catch up from and playback just falls further
# and further behind. Rather than let that drift grow unbounded, watch
# ffplay's own -stats line: with -sync ext and a video-only stream it prints
# "M-V: <diff>" = master(wall clock) vs video clock, which grows in
# magnitude (confirmed by test: went from -0.07 to -1.16 over 10s of a
# stalled feed — it drifts negative here, not positive) whenever decode
# falls behind live. Once |diff| exceeds $DESYNC_LIMIT seconds, kill ffplay.
#
# ffmpeg's RTP AV1 depacketizer (rtpdec_av1.c) also logs
# "AV1 RTP frag packet sequence mismatch (X != Y), dropping temporal unit"
# when a fragmented OBU's pieces arrive out of order/with a gap. That
# reassembly state lives inside ffplay's demuxer and can't be reset from the
# outside, so the only way to clear it is the same kill-and-relaunch used for
# desync above.
#
# Rather than exiting the whole script on either condition (which used to
# require an external `while true; do ./av1-rcv.sh; done` to recover), both
# triggers just kill this ffplay instance and the loop below relaunches it
# against the same $SDP — the app keeps running and only the player restarts.
# Ctrl+C (or ffplay quitting cleanly via 'q'/window close, exit 0) still ends
# the script for good.
run_ffplay() {
  "$FFPLAY" -protocol_whitelist file,udp,rtp \
    -fflags nobuffer+discardcorrupt -flags low_delay \
    -probesize 32 -analyzeduration 0 -framedrop -sync ext -stats \
    -rtbufsize 350k -threads 1 \
    -max_delay 0 -reorder_queue_size 0 \
    -i "$SDP" -x 800 \
    2> >(tee /dev/stderr | tr '\r' '\n' | while IFS= read -r line; do
          if grep -q 'frag packet sequence mismatch' <<< "$line"; then
            echo "av1-rcv: RTP fragment sequence mismatch, resetting input" >&2
            pkill -f "$SDP"
            break
          fi
          diff=$(grep -oP 'M-V:\s*\K-?[0-9.]+' <<< "$line") || continue
          awk -v d="$diff" -v lim="$DESYNC_LIMIT" 'BEGIN{ad = d<0?-d:d; exit !(ad>lim)}' || continue
          echo "av1-rcv: ${diff}s behind live (> ${DESYNC_LIMIT}s), resetting input" >&2
          pkill -f "$SDP"
          break
        done)
}

while true; do
  run_ffplay
  status=$?
  [[ $status -eq 0 ]] && break
  sleep 0.2
done
