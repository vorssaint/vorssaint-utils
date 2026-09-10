# Clamshell gate conditions — design

**PR:** #1433 · **Issue:** #1263  
**Status:** Approved 2026-09-08

## Problem

Closed-lid mode currently has a single gate: external display. Users (e.g. backpack commute) need selectable conditions: external display, AC power, network — with Any vs All combination.

## Behavior

- Closed-lid still requires `clamshellPreferred && keepAwakeActive && !sessionPaused`.
- **No conditions selected** → gate off (same as today with the display toggle off).
- **Any** → at least one selected condition is currently true.
- **All** → every selected condition is currently true.
- Keep Awake automation is unchanged (separate feature).

## Conditions

| Condition | Source |
|-----------|--------|
| External display | Existing `CGGetOnlineDisplayList` / built-in flags |
| Power | `SystemInfo.batterySnapshot()` → not on battery (same as Keep Awake) |
| Network | `NWPathMonitor` / path `.satisfied` |

## Defaults / migration

- Keep `clamshellExternalDisplay` as the display checkbox (existing users preserve setting).
- Add `clamshellGatePower` (false), `clamshellGateNetwork` (false), `clamshellGateMode` (`"any"`).
- Default mode **any**.

## UI

Energy / Keep Awake closed-lid section (settings + menu panel):

- Caption: allow closed lid only when selected conditions hold; Keep Awake unchanged.
- Segmented Any / All (visible when ≥1 condition on, or always enabled next to checkboxes).
- Checkboxes: External display, Connected to power, Network available.
- Disabled when closed-lid preference is off.

## Pure logic

`KeepAwakeAutomationSupport.clamshellGatePasses(...)` + `shouldApplyClamshell(..., gatePasses:)` — testable without AppKit network I/O.

## Out of scope

- Running-apps condition for clamshell
- Changing Keep Awake auto-start conditions
- New GitHub issue (extends #1263 / #1433)
