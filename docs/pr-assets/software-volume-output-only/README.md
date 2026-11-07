# Prepared screenshots for the software-volume PR

Captured locally on macOS 27.2 with native macOS window/region capture. These are actual application UI, with unrelated applications hidden; no generated or retouched UI.

| File | Suggested caption |
| --- | --- |
| [settings-software-fallback.png](settings-software-fallback.png) | Native master controls through Vorssaint Audio on a fixed-volume Samsung output, with per-app boost and compact settings-only privacy/removal actions. |
| [audio-privacy.png](audio-privacy.png) | Output-only, in-memory processing and the physical microphone boundary. |
| [driver-update-required.png](driver-update-required.png) | Driver update prompt, demonstrated by simulating an outdated installed driver. No driver update was installed during this test. |

The existing [`software-volume-native-slider.png`](../../images/software-volume-native-slider.png) provides the separate native macOS Sound-panel illustration.

The update screenshot uses the real app code with a deliberately simulated bundle requirement of build 5 against installed build 4. It demonstrates the update UI; it does not imply that build 5 has been released or installed. The actual driver was unchanged. The temporary test app was removed after verification.

The visible app title and driver name use Vorssaint branding. The local development app's filename is not part of the captured UI.
