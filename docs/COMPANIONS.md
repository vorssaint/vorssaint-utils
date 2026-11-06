# Companion characters

The Dynamic Island companion can wear a face of your own: a finely drawn,
animated face that takes the place of the drawn shape and eyes. Pick it in
**Settings → Dynamic Island → Companion → Style → Character**.

A character is a folder with a `companion.json` and its frames. It is a
face only: no body, neck or shoulders. Its frames are smooth, high-resolution
illustrations (painted, 3D-rendered or photographic), not pixel art. The
companion moves, hops and squashes the face as it does the drawn one; the
frames carry the expression.

## Where packs live

```text
~/Library/Application Support/com.vorssaint.utils/Companions/<pack>/
├── companion.json
├── idle/0001.png … idle/0024.png
├── happy.png               (a sprite sheet)
└── dance.gif               (an animated image)
```

The Developer build reads `com.vorssaint.utils.dev` instead. **Open Folder**
in Settings creates and shows the folder. **Add…** copies a pack folder into
it, and **Reload** reads the packs again after you edit one. The folder's
name is the pack's id.

## companion.json

```json
{
  "format": 1,
  "name": "Mochi",
  "description": "A sleepy cat who perks up for music.",
  "fps": 12,
  "scale": 1.0,
  "chromaKey": { "color": "#00FF00", "tolerance": 0.16 },
  "animations": {
    "idle":      { "frames": "idle", "fps": 10 },
    "lookRight": { "sheet": "look.png", "columns": 4, "rows": 2, "count": 8 },
    "happy":     { "frames": ["happy/01.png", "happy/02.png"], "durations": [120, 240] },
    "dance":     { "frames": "dance.gif" },
    "think":     { "sheet": "all.png", "columns": 8, "rows": 4, "row": 2, "count": 6, "loop": true }
  }
}
```

| Key | Meaning |
| --- | --- |
| `name` | Shown in Settings. Defaults to the folder's name. |
| `description` | Shown as the tile's tooltip. |
| `fps` | Default frame rate for every animation, 1–60. Default 10. |
| `scale` | Size of the face relative to the drawn companion, 0.5–2. Default 1. |
| `chromaKey` | A `#RRGGBB` backdrop color that is made transparent, with a `tolerance` from 0 to 1. Use it for JPEGs or generated sheets on a flat color. It can also be set per animation. |
| `animations` | Animations by state name (see below). `idle` is required. |

Each animation takes its frames from exactly one source:

- `"frames": "folder"`: every image in the folder, in natural order
  (`2.png` comes before `10.png`).
- `"frames": ["a.png", "b.png"]`: these files, in this order.
- `"frames": "file.gif"`: every frame of an animated GIF, PNG, WebP or HEIC,
  with its own delays unless `fps` or `durations` is given.
- `"sheet": "file.png"` with `columns` (and `rows`, default 1): grid cells
  counted row by row from the top left. `row` restricts it to one row,
  `start` skips cells, and `count` limits how many are read.

Timing and looping:

- `fps` sets the frame rate. `durations` gives milliseconds: one value for
  every frame, or one per frame.
- `loop` defaults to true for `idle`, `lookRight`, `lookLeft`, `sleep`,
  `think`, `busy` and `dance`. The others play once and hold their last
  frame.

Images can be PNG, JPEG, WebP, HEIC, TIFF, BMP or GIF, at most 120 frames
per animation. Every frame is fit, centred, into the shape of the first
`idle` frame. Paths cannot leave the pack's folder.

## States

Anything missing falls back along the arrow, ending at `idle`.

| State | When it plays | Falls back to |
| --- | --- | --- |
| `idle` | At rest: breathing, blinking, small glances. **Required.** | — |
| `lookRight` | Travelling right on a visit. | `idle` |
| `lookLeft` | Travelling left. If missing, `lookRight` is mirrored. | `lookRight` |
| `sleep` | Dozing after a quiet while, yawning, low battery. | `idle` |
| `wink` | A greeting as it passes by. | `happy` |
| `happy` | Results found, focus session done, battery full, waking up. | `idle` |
| `love` | Petted with the pointer, charger plugged in. | `happy` |
| `surprised` | Timer rang, screenshot, event starting. | `idle` |
| `sad` | Nothing matched, download failed. | `idle` |
| `think` | Searching in the Command Bar. | `idle` |
| `busy` | An AI agent at work, Keep Awake on. | `idle` |
| `dance` | Music started. | `happy` |

## Drawing frames that look right

- **Square, face only.** Frames are square, with the face centred and filling
  about 85–90% of the frame. Keep the face the same size and in the same
  place in every frame of every state, so it doesn't jitter.
- **High quality.** Use smooth, anti-aliased, detailed art; the app keeps up
  to 192 px per side and filters it smoothly. Store frames at 512×512 or
  larger.
- **Readable when small.** In the closed island the face is about 20 points
  tall. Bold features and clear expressions read best; avoid fine text and
  tiny accessories.
- **Clean background.** Use a transparent PNG or WebP, or a flat chroma-key
  color that appears nowhere in the face, together with `chromaKey`. Avoid
  shadows, glows, vignettes and scenery. On the black island a JPEG on
  black also works without a key.
- **Loops that close.** The last frame of a looping state should lead back
  into its first.

The `vorssaint-companion` skill in `Tools/skills/` generates a complete pack
with Codex image generation, cuts the sheets into frames, checks them and
installs the pack.
