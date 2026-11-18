# Output-layout and software-volume screenshots

These are actual application UI on macOS 27.2, without generated or retouched controls. Stereo/menu, Settings and search captures were refreshed on 15 November 2026 using the installed build-6 driver; the original HDMI 5.1 capture is from 7 November.

- `menu-stereo.png`: isolated menu-panel capture on Mac Studio with Stereo beside Output, Options expanded, and the new Perceptual volume curve checkbox visible and enabled. Vorssaint Audio routes to Samsung Odyssey G85SB.
- `menu-hdmi-5.1.jpg`: original user-provided MacBook Pro capture during direct HDMI playback to Samsung QCQ90S. The panel shows 5.1; its diagnostic log confirmed six-channel, 48 kHz PCM transport. It includes the system menu bar and a cropped panel bottom, and does not verify individual physical surround speakers.
- `settings-options.png`: isolated Settings-window capture with the Stereo output badge, expanded Options, the new curve checkbox, and the settings-only privacy/removal actions. Samsung fallback is active.
- `settings-search.png`: isolated Settings-window capture with the Software volume fallback query and its matching result. Volume mixer is enabled in this capture; unavailable-feature routing to its installation card is covered by automated tests in all supported languages.

Stereo and 5.1 illustrate different selected output configurations. The search image shows the discovery flow rather than an additional settings configuration. Voice recordings and diagnostic logs are excluded.
