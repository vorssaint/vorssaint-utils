---
name: vorssaint-companion
description: Create an animated face character for the Vorssaint Dynamic Island companion. Generates a high-quality (not pixel art) face with $imagegen, then a sprite sheet per expression grounded on it, cuts the sheets into stabilised square frames, writes companion.json, validates, previews and installs the pack. Use when the user wants a custom companion, character, face, mascot or avatar for Vorssaint's notch/Dynamic Island, or a pack in the companion.json format.
---

# Vorssaint Companion

## What you are making

A **face-only character** for the companion in Vorssaint's Dynamic Island. It
shows about 20 points tall in the closed island and larger in Settings. The
app moves, hops and squashes the face; the frames carry the expressions.

- **Face only:** head, hair and ears. No neck, shoulders, body or hands.
- **High quality, not pixel art:** smooth, detailed, anti-aliased
  illustration, 3D render or photo-real art. Never pixel art, dithering or
  low resolution.
- **Readable small:** large clear eyes and mouth, a strong silhouette, no
  fine text or tiny props.
- **Steady:** the same face, size and position in every frame of every
  state. Only the expression and small head motion change.

The contract is in `docs/COMPANIONS.md` of the Vorssaint repository. The pack
is a folder with `companion.json` plus a folder of PNG frames per state:

| State | Plays when | Loops |
| --- | --- | --- |
| `idle` (required) | At rest: breathing, a blink, a glance | yes |
| `lookRight` | Travelling right on a visit (mirrored for left) | yes |
| `lookLeft` | Optional; only if the face is not symmetric | yes |
| `sleep` | Dozing, yawning, low battery | yes |
| `wink` | Greeting as it passes by | once |
| `happy` | Success, results found, battery full | once |
| `love` | Petted, charger plugged in | once |
| `surprised` | Timer rang, screenshot, event starting | once |
| `sad` | Nothing found, download failed | once |
| `think` | Searching in the Command Bar | yes |
| `busy` | AI agent at work, Keep Awake on | yes |
| `dance` | Music started | yes |

Anything missing falls back toward `idle`, so a small pack (for example
`idle`, `happy`, `sleep`) works too.

## Generation rules

Use `$imagegen` for **every** visual. Load and follow
`${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/SKILL.md`, and stay on
its built-in `image_gen` path unless the user asks for the CLI.

- Pass the prompt files this skill writes as the authoritative spec. Don't
  add extra polish, scenery or props.
- Every state sheet must attach the **canonical base face** (role: identity
  reference) and the state's **layout guide** (role: layout only, never to be
  drawn). A sheet generated without the base face is invalid.
- Never draw, warp, tile, mirror or synthesize face pixels with code. The
  tool only cuts, keys, aligns and scales what `$imagegen` produced; it also
  derives `lookLeft` by mirroring at runtime.
- Prefer a **transparent background**. If `image_gen` returns an opaque
  backdrop anyway, the tool keys out the flat corner color and warns; check
  the edges. For a chroma key instead, prepare with
  `--background "#00FF00"` (or `#FF00FF` for green characters).

## Workflow

Keep a short visible checklist: *Designing the face → Drawing expressions →
Assembling the pack → Installing*.

```bash
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/vorssaint-companion"
# A sandbox may not let Swift write its usual module cache: keep it here.
TOOL="env CLANG_MODULE_CACHE_PATH=$PWD/.swift-cache swift $SKILL_DIR/scripts/companion_tool.swift"
RUN="$PWD/companion-runs/<slug>"
```

When Vorssaint started the run itself, its prompt names the run folder and
asks you to stop before installing: the app installs the pack.

### 1. Plan the run

Infer a short name and a one-sentence concept if the user gave none. Choose a
style that fits, such as "polished 2D digital illustration, soft cel shading",
"soft 3D render like an animated film" or "painterly watercolor".

```bash
$TOOL prepare --name "Mochi" --out "$RUN" \
  --concept "a round cream cat with big amber eyes and a tiny pink nose" \
  --style "polished 2D digital illustration, soft cel shading, gentle highlights" \
  --frames 8 --state-frames idle=12,dance=12
```

- `--states` limits the states (default: all except `lookLeft`). Add
  `lookLeft` only for asymmetric faces: a side part, an eye patch, a logo.
- Frame counts from 2 to 24 per state. The tool picks the grid and image
  size: 6 → 3×2, 8 → 4×2, 12 → 4×3 and 24 → 6×4 on 1536×1024; 16 → 4×4
  on 1024×1024. Fewer frames give bigger, sharper cells. Use 8–12 by
  default, and 24 only when the user asks for it.
- The run gets `run.json`, `prompts/base.txt`, `prompts/<state>.txt` and
  `guides/<state>.png`.

### 2. Generate the base face

Generate `prompts/base.txt` with `$imagegen` (it may be prompt-only, or use
the user's reference images labeled as references). Look at the result: one
centred face, nothing cropped, clean background, not pixel art, appealing at
small size. Iterate until it is right. Copy the chosen original to
`$RUN/base.png`. This is the canonical identity for every sheet.

### 3. Generate one sheet per state

For each state in `run.json`, call `$imagegen` with:

- the prompt in `prompts/<state>.txt`, verbatim
- `$RUN/base.png`, labeled as the identity reference
- `$RUN/guides/<state>.png`, labeled as the layout guide only

Use the image size the prompt names. You may delegate states to subagents in
parallel. Each subagent returns only the chosen image path and a one-line
QA note; the parent runs every tool command.

Before accepting a sheet, check:

- the exact frame count and grid, one face per cell, nothing crossing cells
- the same character as the base: shape, colors, markings, style
- the expression reads as the state, and consecutive frames change a little
- a clean background with no detached effects (floating hearts, Z's,
  sparkles), text or guide lines

Regenerate only the sheet that fails.

### 4. Cut, assemble, check

```bash
$TOOL slice --run "$RUN" --state idle --sheet /path/to/generated/idle.png
# … repeat per state …
$TOOL manifest --run "$RUN"
$TOOL validate --pack "$RUN/pack"
$TOOL preview  --pack "$RUN/pack"     # writes $RUN/qa/
```

- `slice` cuts the grid, makes the background transparent, aligns the
  sheet's median face to the centre at 86% of a 512×512 frame, and writes
  `pack/<state>/0001.png…`. Use `--append` to add a second sheet to the
  same state, for example 24 frames as 2 × 12.
- Treat `slice` warnings about frames touching an edge, jumping or
  changing size as reasons to regenerate that sheet, unless the motion is
  intended (a surprised jolt).
- `validate` must print `VALID`.
- Open `qa/contact-sheet.png`, the `qa/<state>.gif` loops and
  `qa/island-sizes.png`. Block acceptance on identity drift between states,
  jitter, cut-off hair or ears, colored fringes, or a face that doesn't read
  at the island size.

### 5. Install

```bash
$TOOL install --pack "$RUN/pack"            # Vorssaint
$TOOL install --pack "$RUN/pack" --dev      # Vorssaint Developer build
```

`--replace` overwrites a pack with the same id. Then, in Vorssaint, go to
**Settings → Dynamic Island → Companion → Style → Character**, press
**Reload** and pick the character.

Finish by reporting the pack path, its states and frame counts, which states
fall back, and the QA files.
