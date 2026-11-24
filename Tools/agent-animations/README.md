# Dynamic Island dot animations (5 × 5)

All files use a 5 × 5 grid, the JSON format from the handoff, and only `0`, `1` and `2` (dim) cells.
No colours: Vorssaint tints the dots.

## Thinking (dropdown order)

| # | File | Name | Frames · fps · loop | Description |
|---|------|------|---------------------|-------------|
| 1 | `thinking-bloom.json` | Bloom | 20 · 10 fps · 2.0 s | Fills out from the centre, hollows to an outline, and fades at the corners as the next bloom begins. |
| 2 | `thinking-snake.json` | Snake | 25 · 12 fps · 2.1 s | A short tail winds along a spiral into the centre, and the next one sets off from the corner. |
| 3 | `thinking-sweep.json` | Sweep | 20 · 10 fps · 2.0 s | A diagonal band glides from corner to corner and back, like a scanner. |
| 4 | `thinking-gears.json` | Gears | 16 · 10 fps · 1.6 s | A comet circles the outer ring while a dim one turns the other way inside; the centre breathes. |
| 5 | `thinking-equalizer.json` | Equalizer | 20 · 10 fps · 2.0 s | Five columns rise and fall at their own pace, like a level meter. |
| 6 | `thinking-rain.json` | Rain | 20 · 10 fps · 2.0 s | Drops with dim trails fall down each column at two speeds. |
| 7 | `thinking-twinkle.json` | Twinkle | 20 · 10 fps · 2.0 s | Dots glow one at a time at their own moment, like stars. |

## Other states

| File | Frames · fps | Description |
|------|--------------|-------------|
| `question.json` | 16 · 10 fps · 1.6 s loop | A steady question mark whose dot slowly dims and returns. |
| `done.json` | 10 · 12 fps · plays once | The tick draws itself dot by dot, then holds on the last frame. |

## Checks

- Every frame has 5 rows of 5 characters, using only `0`, `1` and `2`.
- No dot switches fully on and off more than once a second (the limit is 3).
- Each file's `still` frame works alone: Bloom shows the rounded fill, Snake shows a tail on the spiral, Question shows the full "?" and Done shows the finished tick.

## Files

- `export-swift.py`: checks every JSON file and writes `Sources/Vorssaint/Services/Notch/AgentDotAnimationData.swift`
  (`python3 Tools/agent-animations/export-swift.py`). The app reads that file, not the JSON.
- The shapes were generated with a small Node script, and checked in an HTML preview that plays each file
  at 14 pt and 9 pt with a Reduce Motion toggle. Both live outside this repository:
  https://github.com/nunolilpipmelo/vorssaint-utils/tree/feat/agent-needs-input/Tools/agent-animations
