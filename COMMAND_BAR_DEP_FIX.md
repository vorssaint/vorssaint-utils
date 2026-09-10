# Fix doc: deep links into prompted rows silently do nothing when the Command Bar is off

Symptom: with the Command Bar feature disabled, `open
'vorssaint://run/action.emptyTrash'` does nothing at all — no trash
confirmation, no beep. The same row clicked in the menu bar's Quick Toggles
asks its question from there, because Quick Toggles owns its own prompt. The
docs promise "a row that would confirm a destructive step still asks", with no
mention of the bar being a precondition.

## Trace

1. `runExternalRow` finds the row (the catalog builds regardless of the bar's
   enabled state) and hands it to `dispatch`
   (Sources/Vorssaint/Services/CommandBar/CommandBarService.swift:494).
2. `dispatch` sees `needsPrompt` and calls `show(promptingFor:)` — the bar's
   confirm mode is the prompt surface (CommandBarService.swift:503).
3. `show` opens with `guard AppFeature.commandBar.isAvailable else { return }`
   (CommandBarService.swift:248). Silent return. No beep, no prompt, no
   fallback. The deep link dies in a guard clause.

The design fact underneath: prompting lives in the *surface*, not the
*service*. The bar prompts in its own field (`confirmationPrompt`), the menu
bar and radial menu prompt through the owning service's NSAlert
(`QuickTogglesService.emptyTrash()`, QuickTogglesService.swift:85-96, which
then calls the same `emptyTrashConfirmed()`), and the deep link — which owns
no surface of its own — borrows the bar's.

## Everything the silence swallows

`needsPrompt` (CommandBarCatalog.swift:83) is true for three classes, so all
of these are silent no-ops via deep link with the bar off:

| Class | Fixed IDs affected |
|---|---|
| Confirmation rows | `action.emptyTrash`, `action.clipboardClearRecent`, `action.power.restart`, `action.power.shutDown`, `action.power.logOut` |
| Mandatory numeric rows, bare link (no `v`) | `action.volume`, `action.brightness` |
| Missing-setup rows (`needsSetup` trouble) | brightness when off, clipboard rows when history is off, shelf when off |

Two of these classes are already fine with an argument present:
`action.volume?v=40` skips the prompt entirely (`dispatch` finishes the row
directly, CommandBarService.swift:498-502). Only the bare link asks.

Row shortcuts never hit this — they are registered only while the bar feature
is on. Deep links are the only external surface, and the docs promise them
unconditionally.

## Fix suggestions

### 1. Missing-setup rows: open Settings directly, no bar (clear win)

The docs already promise "opens the Settings page where that row lives" —
nothing about that needs a bar. When `entry.trouble` is `.needsSetup(_, page)`
on external dispatch, route straight to `SettingsRouter.shared.request` +
`openSettingsWindow()`, exactly what the `settings.<page>` fix now does.
About five lines, deletes a whole class from the problem.

### 2. Confirmation rows: generic alert fallback (recommended)

When external dispatch meets `confirmationPrompt != nil` and the bar cannot
appear, present a minimal `NSAlert` built from data the entry already carries:
row title as `messageText`, the confirmation prompt as `informativeText`, and
one shared localized Run / Cancel button pair. Confirming runs the row's
existing `run` closure; cancelling does nothing. Precedent for the surface is
the Quick Toggles alert, which already appears over whatever app is
frontmost.

- Uniform: every confirming row is covered, including future ones, with no
  per-row work.
- Small: one alert builder in `CommandBarService` plus one branch in
  `dispatch`; only new strings are the two buttons (verify a reusable pair
  does not already exist in the common strings before adding any).
- Honest mismatch: the ask looks like an alert, not like the bar's in-field
  confirm. For an external caller that is the right shape anyway — there is
  no bar to confirm in.

An alternative shape is an optional `externalFallback` closure on
`CommandBarEntry` pointing at the owning service's own prompt
(`QuickTogglesService.shared.emptyTrash()` and friends). It reuses each
service's exact wording, but adds a per-row field and per-row wiring, and
rows whose owner has no prompt (the power actions confirm only in the bar)
still need the generic alert. The generic alert alone covers everything for
less surface.

### 3. Bare numeric links: beep, and say so in the docs

`action.volume` without `v` genuinely cannot run: there is no number to act
on, and inventing a prompt surface for one row class is not worth it. Beep
(honest failure, same as an unknown ID) and add one docs sentence: a row that
needs a number needs the number in the link, or the Command Bar to ask in.
The `?v=` parameter already exists and is documented — this just closes the
bare-link gap.

### 4. The wholesale alternative, not recommended

Declare deep links a Command Bar feature: when the bar is off, every link
beeps and the docs say so. Simplest possible code, but it severs the promise
for a real user — someone who disabled the bar because they drive Vorssaint
from the menu bar, radial menu, or Raycast still owns every tool the link
names. The docs' own framing ("reach any installed tool") is the better
contract.

## Shape of the whole fix

Options 1 + 2 + 3 together: a `needsSetup` bypass, one alert fallback, one
beep, one docs paragraph. Roughly forty lines and two button strings. The
silent `return` in `show` (CommandBarService.swift:248) stays correct for its
internal callers; the external path just stops routing prompts into it.

## Verification (when you ask for it)

```sh
./build.sh --test
./build/Vorssaint --selftest
```

With the Command Bar feature off, from Terminal:

```sh
open 'vorssaint://run/action.emptyTrash'        # expect alert, confirm empties
open 'vorssaint://run/action.power.shutDown'    # expect alert, cancel does nothing
open 'vorssaint://run/action.brightness'        # brightness on: expect beep
open 'vorssaint://run/action.brightness?v=40'   # expect brightness set, no bar
# shelf feature off, then:
open 'vorssaint://run/action.shelf'             # expect Settings, shelf page
```

Nothing has been built or run for this doc yet.
