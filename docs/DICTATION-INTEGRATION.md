# Local dictation

Dictation is an opt-in Sound feature that records speech, recognizes it locally,
and inserts the result into the original active application. The recording and
result surfaces use the existing native Dynamic Island host. Handy does not
need to be installed or running.

## User workflow

1. Enable Dictation in Features and in its dedicated Settings page.
2. Download or import a compatible model, then select the microphone and language.
3. Grant Microphone permission for recording and Accessibility for the global
   shortcut and automatic paste. Set the system Fn action to Do Nothing when
   using Fn/Globe, and avoid assigning Handy the same activation key.
4. Hold the shortcut to speak and release it to finish, or select toggle/hybrid
   activation. Escape cancels. The island shows a stationary audio-reactive
   waveform, elapsed recording time, and finish/cancel controls.
5. Text is pasted when the original application remains active. Copy-only and
   paste-and-restore modes are also available. Focus changes fall back to copy.

The island history widget supports search, favorites, copying, editing and
export. Optional retained audio adds playback and retry. A quick-access button
can be added without replacing existing island buttons. Copy confirmation stays
inside the widget. Dictation-origin clipboard writes do not trigger the separate
clipboard notice or interrupt the island's collapse. History ages use whole
minutes/hours/days, refreshed once per minute while visible, without per-second
relative-date subscriptions. Silence and empty results collapse quietly.

## Recognition and lifecycle

- `DictationService` owns recording, recognition, cleanup and delivery. Generation
  tokens reject stale completions. Lock, sleep, session deactivation and input
  reconfiguration stop capture. Disabling the feature removes its shortcut and
  observers and terminates its worker.
- `DictationRecorder` writes owner-only CAF files and uses a stateful
  `AVAudioConverter` to stream 16 kHz mono float32 samples. The spectrum uses a
  Hann-windowed 512-sample DFT, 31 fixed mirrored bars, and audio-time attack/release
  smoothing. Audio time drives the display; it does not scroll with elapsed time.
- `DictationEngine` serializes inference in `VorssaintDictationWorker`, a separate
  process linked to transcribe.cpp. Models load when recording starts; supported
  models process samples during speech and finalize on release. Unsupported
  models, failed feeds and empty streaming output retry the complete recording
  in batch. Imports use the same batch converter.
- Per-utterance identities and worker lifetime tokens isolate cancelled jobs.
  Discarding a recording resets streaming state while preserving the warm model;
  processing cancellation/timeouts can kill the worker. Model unload time and
  CPU-only inference are configurable. Parakeet Unified uses its trained balanced
  560/560 ms chunk/right-context preset.
- The island host retains responsibility for geometry and animation. Dictation's
  surface is opaque and does not take keyboard focus from the receiving app.
- Private history persists text, original text, timestamps, model/language,
  duration, processing time and favorites. Audio retention is optional and bounded.

## Privacy, permissions and delivery

Recognition runs locally. No model is downloaded automatically. Models are
installed from the pinned catalog only after size and SHA-256 verification;
explicit imports remain unverified local models. Recordings are discarded by
default and the microphone is closed when idle. Transcripts, retained audio,
input/model selections and private vocabulary/corrections are excluded from
settings backups; API keys use Keychain.

Automatic paste requires Accessibility, no Secure Event Input, and the original
recipient application to remain active. Both paste modes wait for held modifiers
and recheck focus immediately before posting Command-V. Clipboard restoration
occurs only if nothing else has replaced the clipboard. “Text pasted” means the
shortcut was posted; destination applications do not provide an insertion receipt.

Optional text cleanup is disabled by default. When enabled, transcript text is
sent to the explicitly configured OpenAI-compatible chat-completions endpoint.
HTTPS is required except for loopback local servers. This path never sends audio.
A cleanup failure preserves the transcript and reports the failure.

Dictation tags its own serialized clipboard writes with
`com.vorssaint.dictation-origin`. Clipboard history still captures eligible
persistent text but omits its external-copy notice. Normal copies retain their
existing notices. Paste-and-restore continues to exclude transient text from
clipboard history.

## Dependency provenance and build impact

The integration was developed against Handy commit
`7bfb2e2c934b798bcf6e3627653aed2439996f89` and transcribe.cpp 0.4.0 commit
`f1dcd15858c4bbba87ca97862b4e448b2cf15b8f`. The model catalog is an offline pinned
snapshot; model-license links and dependency notices ship with the app. The Tauri
application and model weights are not bundled.

CMake is required in addition to the existing Apple command-line tools. The
first build clones the pinned engine source into ignored `.build`; subsequent
builds reuse it. `build.sh` compiles, packages and signs the statically linked
worker alongside the app. The native worker currently targets Apple Silicon
and macOS 14+. The Swift package remains an editor/indexing aid; use `build.sh`
for a runnable bundle with worker and resources.

## Verification

```sh
./build.sh
./build/Vorssaint --selftest
./build.sh --test
./build.sh --dev
./build/VorssaintDeveloper --dictation-presentation-test
python3 Tests/dictation-engine-smoke.py /path/to/model.gguf \
  .build/transcribe-cpp-source/samples/jfk.wav
```

Optional full capture-format/live conversion integration tests use explicitly
provided public audio and a locally installed model:

```sh
VORSSAINT_DICTATION_TEST_MODEL=/path/to/model.gguf \
VORSSAINT_DICTATION_TEST_AUDIO=/path/to/public-speech.wav \
  ./build.sh --test-suite=features
```

Tests cover CAF close/EOF/resampling at 8, 16, 44.1 and 48 kHz, mono/stereo input,
streaming resampler tails, spectrum stability and silence, late callbacks after
cancellation, model-preserving stream reset, unsupported-streaming fallback,
quick-button preservation, timestamp granularity, clipboard-notice policy, text
corrections, history retention, paths and serialization. The development view
probe asserts empty recognition returns to idle and exports inert native view
fixtures without microphone capture or input synthesis.

The personal development tree passed 117,874 regression checks, optimized and
Developer app selftests, native view fixtures, real-model public-speech smoke
checks and silent-audio checks on Mac16,12/macOS 27.2 with the macOS 26 SDK.
Parakeet Unified Q8_0's public fixture finalized in approximately 0.13–0.21 s
with audio fed in real time; these measurements exclude paste dispatch. The
user reported successful physical Fn capture and automatic insertion. Native UI
inspection verified whole-minute history labels and inline copy confirmation.
These observations do not establish behavior on every input device, display,
Spaces configuration or supported macOS/Swift version.

## Scope and remaining work

This is local-model dictation integrated into Vorssaint, rather than complete
Handy application parity. Apple Speech, interim transcription text, Silero VAD,
advanced long-form chunking, per-channel/clamshell overrides, always-on buffers,
playback muting, automatic submission, direct typing, external-script delivery,
multiple cleanup profiles and migration of Handy settings/history are not included.
Core labels and microphone permission descriptions cover supported locales;
advanced settings and some diagnostics currently remain English. Broader
hardware, multi-display and minimum-toolchain acceptance remain outstanding.
