# Software volume: microphone boundaries and verification

## Signal path

For outputs with writable native volume (for example built-in speakers or AirPods), macOS keeps its normal output and volume control. No virtual bridge is needed.

For a fixed-volume output such as a DisplayPort monitor:

`Application output → optional per-app tap/gain → Vorssaint Audio output mix → bounded authorized PCM packets → output-only physical callback/master gain → physical output`

Driver 1.2/build 4 has no input streams and publishes no hidden loopback input. The app obtains raw stereo output PCM through a custom HAL CFData property on a background queue. No property call, signature check, allocation or lock runs on the rendering thread. Rendering uses a bounded local ring with adaptive clock correction, clears unused channels and applies the current native master gain/mute exactly once.

## Transport authorization

Exclusive PID ownership is not sufficient authorization for PCM access. The driver constructs a code requirement from its own signing certificate. Ownership claims and session-key requests require the signed main/developer app identity and matching certificate. A fresh random 256-bit capability is returned only to that owner; every PCM request must carry it and match the owning PID. It is kept only in process memory, rotates with the session and is cleared on release/expiry. Signature checks stay off the 5ms packet path. PID 0, unknown/ad-hoc signers, wrong capabilities and other callers fail closed. This deliberately does not grant arbitrary local programs a new way to capture playback. Per-app taps retain macOS System Audio Recording permission. Explicit volume choices, including reset to 100%, are remembered so a playing application can have its per-app path prepared after restart. Apps without a saved volume or route are left untouched; stopped unity IO can release the path. This processes playback in memory and does not opt physical microphone streams into the callback.

Packets carry a version, session generation, explicit cursor/acknowledgment, bounded frame count and echoed request nonce. Repeated reads do not destructively drain audio. The producer drops new data when full and never overwrites unacknowledged samples. Old-generation frames are silenced after session replacement. No world-readable shared-memory object, network socket or new helper daemon is created.

## Physical microphone isolation

Before starting the physical output IOProc, the bridge sets every physical input stream's `kAudioDevicePropertyIOProcStreamUsage` flag to zero and reads it back. A genuinely output-only device needs no input mask. The output callback ignores its input argument. Per-app engines separately enable only their process-output tap and disable all physical input streams. An incomplete layout or mismatching readback prevents startup; topology changes rebuild the route.

These playback callbacks are configured not to receive/read physical microphone samples. This does not prohibit another app or an explicitly enabled recorder from using a microphone. The supported target behavior is that fallback itself does not light the orange microphone indicator; it must be verified with the installed new app/driver on real macOS, not inferred from unit tests.

## Recording and network scope

The new driver and local software-volume bridge use in-memory PCM buffers. Their processing path has no audio-file writer, recording store, upload, or network client. Device-level preferences save identifiers and volume numbers, not audio.

This statement applies to this processing path. The existing screen recorder can record a microphone when explicitly enabled; explicitly selected AirPlay routing sends playback to the chosen AirPlay output. Those separate features keep their own behavior and permissions. The local validation profile enables the volume mixer only.

## Evidence and limits

Automated checks exercise driver volume/mute, qualified PCM packets, signed caller authorization, owner expiry, input-mask construction, unexpected stream counts, NULL/empty callback buffers, stereo/microphone isolation and output restoration. The app refuses to start these IO paths if the live HAL mask cannot be verified.

The code and tests are reviewable; they are not an independent security certification or a promise about all future changes to the original application. Runtime checks, tested devices and remaining gaps are recorded in the accompanying PR rather than inferred from unit tests.

## Local development signing and audit limits

The installed local driver 1.2.0/build 4 passes strict signature verification. Its HAL directory and ancestors are owned by root, with no writable group/other permissions or symlinks found. The driver runs in a Core Audio host under `_coreaudiod`, rather than in the application's user process. Current driver/PCM/caller-trust source files match the installed Corresponding Source. A fresh untrusted-process probe was denied both the session-key property and a zero-frame PCM request; it recorded no sound or key material.

This Mac uses the repository's self-signed development certificate, not a notarized Developer ID release. The local signing setup makes that key available to this developer account; software that can use the key could sign an allowed app identity and satisfy the driver's certificate policy. The current local installer package is unsigned, although its contained driver and enclosing app have valid local signatures. These facts prevent a strong guarantee against malware with access to this user's signing key or a claim of public-release authenticity. Public distribution needs protected signing keys and an authenticated, appropriately signed release package.

The unit driver harness substitutes a test identity policy; it does not by itself prove production certificate enforcement. The installed signed-owner path and denial to a separate untrusted process were also exercised on this Mac. Same-shaped dynamic microphone topology changes and every future macOS version are not certified by these checks. The physical output callback ignores input samples regardless; the tested hardware microphones remained inactive during playback.
