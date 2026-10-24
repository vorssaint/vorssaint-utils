# Display Mirror Probe

An opt-in developer experiment for a teleprompter display, not a shipped Vorssaint
feature. It measures the cost of capturing an extended desktop and presenting it
with a horizontal reflection. Product integration needs maintainer agreement and
real display evidence first (see [contributing](../../CONTRIBUTING.md)).

Requires Apple Silicon, macOS 14+, and Xcode Command Line Tools. No dependencies,
virtual display driver, video encoder, network access, or image files. It has its
own app name and bundle identity and does not change Vorssaint preferences.

## Build and validate

From the repository root:

```sh
bash Tools/DisplayMirrorProbe/build.sh
probe="$PWD/build/Display Mirror Probe.app/Contents/MacOS/DisplayMirrorProbe"
"$probe" --selftest
"$probe" --list
```

The optimized build treats compiler warnings as errors. `--selftest` exercises
option validation, concurrent counters, CoreVideo-to-Metal texture mapping, and the actual Metal shader against a
2-by-2 texture with four different colors: unchanged and horizontally reflected.
It needs GPU access, but no Screen Recording permission. This is a correctness
test, **not** a 4K60 performance result.

The app is ad-hoc signed by default. To reuse an existing local signing identity,
set `PROBE_SIGN_IDENTITY` when building. This script does not create certificates.
An ad-hoc rebuild may require granting Screen Recording permission again.

## Run on an external display

Use macOS extended-desktop mode. The probe refuses the primary display, built-in
display, and displays in a mirror set. It never changes resolutions or topology.
Keep Terminal and the menu bar on the primary display. Replace `DISPLAY_ID` below
with the numeric ID from `--list`; IDs may change on reconnect.

```sh
"$probe" --display DISPLAY_ID --fps 60 --seconds 60 --mode flipped
```

The first attempt may ask for Screen Recording permission. Grant it in System
Settings, then rerun. macOS may attribute permission to the Terminal host when
launching the executable this way. The probe does not request Accessibility,
microphone or audio access.

The output covers the same external desktop being captured. ScreenCaptureKit
excludes this application's windows to avoid capturing the overlay recursively;
startup fails if the application cannot be identified in the exclusion list.
The panel ignores mouse events and never becomes the key window. Use the
physical teleprompter mirror to see the corrected picture.

Stop with **Ctrl-C in Terminal**, **Mirror Probe > Stop experiment** on the primary
display, or wait for the automatic timeout (60 seconds by default; maximum 600).
It also stops on capture/GPU failure, display reconfiguration, system sleep, or
session deactivation. There is no automatic restart or persistent enable switch.

**Known limitation:** cursor mirroring is not implemented. The native macOS cursor
stays visible in its original position and the captured image excludes it. This
is a rendering/performance probe, not yet a complete usable mirrored desktop.
It does not hide the cursor or remap input. Full-screen apps, Spaces, screen lock,
unplugging, HDR, protected content, menu-bar coverage and the exclusion behavior
still need on-device verification. The output is SDR sRGB.

## Compare capture, presentation and reflection

Run the same animation or scrolling content on the external desktop for each
case. First record system CPU/GPU activity with the probe stopped. Then compare:

```sh
"$probe" --display DISPLAY_ID --fps 60 --seconds 60 --mode capture > capture.csv
"$probe" --display DISPLAY_ID --fps 60 --seconds 60 --mode plain > plain.csv
"$probe" --display DISPLAY_ID --fps 60 --seconds 60 --mode flipped > flipped.csv
```

`capture` receives frames without an output overlay; `plain` uses exactly the
same render path as `flipped` with the horizontal transform disabled. Keep source
resolution, workload, display settings and duration fixed. Discard the first
five seconds for warm-up. Repeat at 30 fps, then at another capture resolution.
`--width 1920` or `--width 3840` preserves the source aspect ratio and refuses
upscaling. A 1080p monitor cannot establish 4K performance. On a 4K monitor,
`--width 1920` reduces capture work but the final render target remains native 4K.
The default dimensions come from the display mode's pixel dimensions; with macOS
scaling these can exceed the physical panel resolution. Record both separately.

CSV lines beginning with `#` are metadata/status. The measurement columns are:

| Column | Meaning |
| --- | --- |
| `elapsed_s` | Seconds since the capture start request |
| `complete_fps` | Complete ScreenCaptureKit frames received in this interval |
| `submitted_fps` | Frames submitted to the Metal command queue |
| `busy_or_drawable_drops` | Frames this probe skipped because its two slots or a drawable were unavailable |
| `cpu_percent` | This process's CPU time; 100% means one CPU core |
| `resident_mib` | This process's resident memory; -1 means unavailable |
| `gpu_ms_per_completed_frame` | Mean GPU execution time of completed render commands |
| `callback_to_submit_ms` | Mean time from our capture callback to GPU submission |

Empty GPU/delay fields mean no applicable samples, not zero cost. ScreenCaptureKit
can deliver fewer frames for unchanged content; requested fps is a ceiling. The
drop counter cannot detect frames lost upstream. Submitted frames are not a
measurement of actual display refresh/presentation. GPU command time is not total
GPU utilization, and callback-to-submit time excludes capture/compositor delay,
scanout and monitor latency. Do not report it as end-to-end latency.

Use Activity Monitor alongside the CSV to include **WindowServer** and capture
services in the cost comparison. Use a camera-based test for visible latency.
No measurement here includes those other processes automatically.

The capture uses BGRA buffers, a queue depth of three, and at most two queued or
in-flight render submissions. CoreVideo surfaces are mapped to Metal textures
without explicit CPU pixel copies and retained until GPU completion. Reflection
is a texture-coordinate change; the whole capture/compositing path still costs
memory bandwidth and energy. The probe does not claim a zero-copy OS pipeline.

## Evidence to collect before product integration

- Mac model, macOS version, connection, display model, physical/capture/output
  resolutions, refresh rate, scaling, power source and workload.
- No-probe, capture-only, plain and flipped results under both idle and motion.
- CPU including WindowServer, memory stability, GPU activity and visible latency.
- Correct image and no recursive capture on the same display.
- Mouse/cursor behavior through the physical glass, Spaces and full-screen apps.
- Start/stop, denied permission, stream failure, disconnect, sleep/wake and lock.

Only after those measurements should a product change choose a cursor strategy,
feature-catalog integration, permission UI, lifecycle management and localization.
