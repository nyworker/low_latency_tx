# low_latency_tx

Scripts for getting glass-to-glass video latency as low as possible over
RTP/UDP, using ffmpeg/SVT-AV1 (and a few codec/toolchain alternatives for
comparison). The current best result, measured against an iPhone camera as
the source, is **~0.3s glass-to-glass**.

## The working pipeline

- **`av1-send.sh`** — captures/encodes with `libsvtav1` (CBR, no lookahead,
  short GOP) and streams RTP/UDP to a host:port.
- **`av1-rcv.sh`** — builds its own SDP and plays the stream with `ffplay`,
  watching for decode desync or corrupted RTP fragments and transparently
  restarting `ffplay` when either happens, so playback snaps back to live
  instead of drifting or hanging. This is the receiver to use.

```sh
# sender
./av1-send.sh <host> [port]

# receiver
./av1-rcv.sh [host] [port] [desync-limit-seconds]
```

Both default to `127.0.0.1:6000` when the arguments are omitted, which is
useful for a same-host loopback test before trying it over a real network
(e.g. a Tailscale link between two machines).

### Why it's fast

The scripts are heavily commented with what was tried and measured, but the
short version:

- **GOP size (`keyint`), not buffering flags, was the dominant source of
  latency.** A long GOP means a receiver that joins mid-stream, or loses a
  keyframe packet, has to wait up to a full GOP for the next one. This was
  confirmed to be codec-independent (AV1 and VP8 hit the identical wall) and
  is why `av1-send.sh` uses `keyint=15` (1s worst case) instead of the
  default 60.
- **`-bufsize`** caps the encoder's CBR/VBV buffer. Left at ffmpeg's default,
  it smooths bitrate over ~2s of frames — which shows up directly as ~2s of
  steady-state latency even with encoder lookahead disabled.
- **`-fflags nobuffer`** (input) and **`+flush_packets`** (output) cut
  demuxer-side read buffering and make the RTP muxer flush each packet
  immediately instead of holding it.
- **On the receiver**, `ffplay -sync ext -framedrop` locks playback to the
  wall clock instead of the video's own clock, so a decode backlog gets
  skipped forward to "live" instead of playing out in slow motion.
  `av1-rcv.sh` also greps `ffplay`'s `-stats` output for the M-V (master vs.
  video) drift and for AV1 RTP fragment-reassembly errors, and kills +
  restarts `ffplay` against the same SDP when either fires — recovering
  automatically instead of needing an external restart loop.

## Alternative receivers (for comparison)

- **`av1-rcv-mpv.sh`** — same idea via `mpv --profile=low-latency` instead of
  `ffplay`. Kept as a fallback/comparison; `mpv` generally buffers more
  aggressively.
- **`gst-av1-rcv.sh`** — GStreamer equivalent (`rtpjitterbuffer` +
  `rtpav1depay` + `av1parse` + `av1dec`). Stock Ubuntu GStreamer has no AV1
  RTP (de)payloader; this needs `gst-plugins-rs`'s `rtp` plugin built and
  installed separately (see comments in the script for the build steps).

## Codec/tooling comparisons

- **`vp8-send.sh` / `vp8-rcv.sh`** — same capture/transport approach as the
  AV1 pipeline, but with `libvpx`/VP8, for a side-by-side comparison against
  a cheaper, more mature codec + decoder path.
- **`encode_svtav1_lowlatency.sh` / `encode_h265_lowlatency.sh` / `e1.sh`** —
  offline (file-to-file) low-latency encode presets used while tuning
  encoder settings before wiring them into the live RTP pipeline.
- **`gst-send.sh` / `gst-rcv.sh` / `gst-rcv.port5666.sh` /
  `gst_direct_1s.sh`** — earlier GStreamer + H.264/RTP experiments (via
  `rtpbin`), from before the pipeline settled on ffmpeg + AV1/VP8.
- **`stream_clock.sh` / `stream_clock_gst.sh`** — burn a wall-clock overlay
  into the video so glass-to-glass latency can be measured by eye against a
  reference clock, independent of any codec/network round-trip.

## Testing under a constrained network

**`policing.sh`** applies an ingress rate limit (`tc`) on an interface so the
pipeline's behavior under a bandwidth-starved link can be observed before/after,
without needing a second machine or real network conditions.

## Requirements

- `ffmpeg` built with `libsvtav1` and `libvpx`. The receiver scripts assume
  a build whose `ffplay` can parse the RTP AV1 depacketizer — if you have
  multiple ffmpeg builds on `PATH`, point `FFPLAY` in `av1-rcv.sh` /
  `av1-rcv-mpv.sh` at the right one.
- `mpv`, for `av1-rcv-mpv.sh`.
- `gstreamer` (+ `gst-plugins-rs`'s `rtp` plugin for AV1 support), for the
  `gst-*` scripts.
