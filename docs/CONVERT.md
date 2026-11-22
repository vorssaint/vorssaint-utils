# File converter

Vorssaint's Dynamic Island can convert files, edit them and act on them, all on
your Mac. It combines the interaction of the Mac app Open Tangerine (drag a file,
hold a key, drop on a format) with the feature set of the Windows project
[Convert](https://github.com/signingoff-dubey/convert).

## Two ways in

**Drag and drop.** Drag a file toward the island. Its drop area splits in two:
*Drop files here* (the shelf) and *Convert here*. Drop on *Convert here* and the
island opens at full size.

**Hold a key while you drag.** The island opens on the right page before you
reach it, and you drop straight onto a tile.

| Key while dragging | Page |
|---|---|
| ⇧ Shift | Convert: the formats the file can become |
| ⌘ Command, or ⌥ Option + ⇧ Shift | Tools: edit, compress, merge, split and so on |
| ⌃ Control | Actions: copy, zip, checksum and so on |

Press a different key mid-drag and the page switches. Let go of every key, or end
the drag somewhere else, and the island closes again. Each key can be switched off
in **Settings → Shelf → Convert → Drag keys**. The three small icons at the top of
the page switch between Convert, Tools and Actions after a drop too.

## The pages

**Convert.** Choose a format. Formats with options open a pane first:

| You are making | Options |
|---|---|
| Image (JPG, WebP, HEIC, AVIF) | Quality, longest side |
| Other image formats, PDF | Longest side |
| Video (MP4, MOV, MKV, WebM, AVI, WMV) | Quality, resolution, remove audio |
| GIF | Frames per second, width |
| Audio, or audio from a video | Bitrate |

Everything else converts at once. Picture → TXT reads the text on it (OCR), and a
scanned PDF → TXT does the same.

**Tools.** Each opens a pane for its settings, then runs.

| Kind | Tools |
|---|---|
| Pictures | Compress, resize, rotate and flip, crop, edit (exposure, contrast, saturation, sharpness, vignette, black and white), add a background, collage, upscale 2–4×, remove background, redact faces or text, copy text (OCR), strip metadata |
| PDF | Merge, split (each page, every N, ranges), organize (turn, reverse, remove pages), compress, strip metadata, copy text, images → PDF |
| Video | Trim, crop, change speed, join, save frames (interval, format, stop after N), split into parts, compress |
| Audio | Trim, normalize loudness, mono or swap channels, bleep ranges, compress, turn into a video with a waveform |
| Archives | Extract here |

Not offered: redacting video or audio and editing text inside a PDF, which need a
canvas to draw on.

**Actions.** Reveal in Finder, copy files, copy paths, duplicate, SHA-256, zip,
move to…, copy to…, open in Terminal.

## Progress and results

Work runs one file at a time with a ring, a bar per file and a cancel button.
Cancelling stops ffmpeg and removes the half-written file. When it finishes you
get *Show in Finder*, *Open* and *Again*. Originals are never changed, and a name
already taken becomes `name 2`.

## Settings

**Settings → Shelf → Convert** holds: the on/off switch, the drag keys, where
results go (beside the original, Downloads or Desktop), whether to reveal them,
the default image quality, a switch for every output format, the ffmpeg path and
status, **Test every converter** (the same checks as `--convert-selftest`) and the
last results.

## Engines

Pictures, PDF, text, audio basics and OCR use macOS itself (ImageIO, PDFKit,
AVFoundation, Core Image, Vision). Video, most audio formats, WebM/MKV/GIF and
loudness work use **ffmpeg**, and archives use `zip`, `tar` and **7-Zip**.
`build.sh` bundles ffmpeg, ffprobe and 7-Zip (about 40 MB) inside the app with the
libraries ffmpeg needs, so conversions work offline on any Mac. Without them, the
app looks for `ffmpeg` on your `PATH` (`brew install ffmpeg`) or at the path in
Settings, and the formats that need it say so.

Archives are opened into a private folder and checked before anything is repacked
or moved: an entry naming a path outside it (`../x`, an absolute path) refuses the
whole archive, links that point out of the folder are refused, and the opened size
is capped at 8 GB.

## Testing

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
.build/out/Products/Debug/Vorssaint --convert-selftest
```

builds real files in a temporary folder and runs every converter, tool and action
through the same code the island uses, checking each output by its bytes (and
sizes for options). It covers about 80 conversions, tools and actions, OCR, the
job queue (including one failing job, two requests for one name, and cancelling a
long job), and an archive that tries to escape its folder. It skips, with a note,
what needs an ffmpeg that is not installed.

## Privacy

Nothing leaves your Mac. There is no upload, no account and no network use by the
converter.

## Credits

The converters, format matrix, job queue and drag monitor are adapted from
[Open Tangerine](https://github.com/sintaxerrorpvtltd/Open-Tangerine)
(GPL-3.0-only, Sintax Error Private Limited), which is based on Satsuma
(MIT, plyght). See `NOTICE`. The tools list and settings layout follow
[Convert](https://github.com/signingoff-dubey/convert). Background removal, face
and text finding and OCR use Apple's Vision framework, so no extra machine
learning runtime is needed.
