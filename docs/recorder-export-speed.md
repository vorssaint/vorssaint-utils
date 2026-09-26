# Recording export speed

The speedometer beside the recording editor's quality setting controls **export speed**. It defaults to 1×. Presets are 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×, 3× and 4×. The slider and stepper allow custom speeds from 0.25× through 4× in 0.01× increments. The popover shows the resulting duration; Done commits one undoable change, while Cancel discards it.

Speed belongs to the edit document, not a global preference or a visual preset. Older documents default to 1×. The editing preview and timeline continue to run at 1× so existing cuts, cursor motion, zooms, captions, images and blur regions keep their source-time coordinates.

Video exports, copied videos, temporary shared videos and GIFs use the selected speed. Trimming and cuts happen first; export duration is the remaining duration divided by speed. The composition scales video and both audio tracks together, retaining their offsets and gaps. Non-normal video exports request AVFoundation's spectral time-pitch processing. Existing mute and gain settings still apply. GIFs sample the scaled timeline at the selected GIF frame rate; the decoded-frame budget uses the scaled duration rather than shortening frame delays.

The exporter reads but does not retime or rewrite the master recording. Existing recording lifetime and destination replacement behavior are unchanged: the temporary master is deleted when its editor closes. Save a separate 1× export before closing when an enduring normal-speed copy is needed.

## Automated checks

Run on a supported Mac:

```sh
./build.sh --test-suite=recorder
./build.sh --dev
./build/VorssaintDeveloper --selftest
```

`RecorderExportSpeedTests` is registered in the recorder suite and covers legacy decoding, custom-speed persistence, invalid values and bounds, inverse clock conversion, trim/cut ordering, unchanged preview timing, visual presets and GIF budgets. The recorder suite also runs `RecorderExportRenderingTests` through the production AVFoundation exporter. Synthetic video and two audio tracks cover fractional and endpoint speeds, trim and cut boundaries, blur coverage and clear frames, duration, delayed microphone, silence, pitch, gain, mute, GIF frame count and cancellation. These checks do not exercise native control layout or physical capture hardware.

## Manual macOS smoke checks

- Record a visible timer with system audio and microphone cues. Export at 1×, 1.25×, 0.5×, 1.37× and the 0.25×/4× endpoints. Check duration against edited duration / speed within encoder frame granularity, synchronization at the start and end, pitch and each track's mute/gain settings. Include a source with no audio and one with a delayed audio start.
- Trim both ends, cut a middle interval and place zoom, cursor clicks, text, images and privacy blurs on either side. Check the exported frames across the cut and throughout each blur; the output must not lose or delay privacy effects.
- Export a 10-second GIF at 12 fps and 2×: expect 60 sampled frames and approximately 5 seconds. Check slower GIFs against the frame budget and verify cancellation leaves any previous destination intact. Exercise normal save, Save As, copy and sharing.
- Check the speed control in English and Portuguese at the editor's minimum width, with a cut selected. Verify 1.25× / 1,25× labels, 0.01× steps, the duration display, Done, Cancel, undo/redo and disabled controls during export. Changing export speed must not speed up the editing preview or change the master.

Automated export regressions, the installed Developer build, selftest and strict signature verification were validated on macOS during integration. The optimized build and its selftest also passed. Manual control layout and physical capture hardware remain separate smoke checks.
