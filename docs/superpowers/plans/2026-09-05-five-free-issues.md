# Five free issues — implementation plan

> **For agentic workers:** Inline execution. One branch + one PR per issue.

**Goal:** Ship five small, already-scoped enhancements as separate PRs.

**Architecture:** Extend existing mechanisms only (layout enum, menu-bar draw, MouseExceptionScope, KeepAwakeAutomationCondition). No new subsystems.

**Tech Stack:** Swift / AppKit / SwiftUI, MetricsTests, `./build.sh`

## Global Constraints

- One topic per PR; title `type(scope): lowercase imperative`
- `Refs #N` only (never Closes/Fixes)
- Leave CHANGELOG alone
- All user strings in every locale
- TDD: failing test first; verify red then green
- Verify: `./build.sh`, `./build/Vorssaint --selftest`, `./build.sh --test`
- Median size target: well under +1000 lines; prefer +200–400

---

### Task 1: #1187 Center two-thirds

**Files:** WindowLayoutSupport.swift, Defaults.swift, FeatureStrings.swift, PanelWindowLayoutView.swift, WindowLayoutSettings.swift, MetricsTests.swift

- Add `centerTwoThirds` to enum; geometry centered 2/3 width; shortcutID 56; default shortcut nil; cleared storage default
- Strings all locales: "Center 2/3" etc.
- Test: rect for visibleFrame 1440×860 → x=240, w=960

### Task 2: #815 Center half

Same pattern as Task 1 with `centerHalf` (shortcutID 57), in halves section.

### Task 3: #389 Memory pressure whole-block color

MenuBarRenderer: when pressure passed, tint label+value (and optional fill) with `nsColor(for:)`, not only the dot.

### Task 4: #741 Super Key app exclusions

Add `MouseExceptionScope.superKey`; `excludesFrontmostApplication`; wire SuperKeySettings + SuperKeyService.handle; setSourceTracking.

### Task 5: #630 Keep Awake running-apps condition

Add `runningApps` to KeepAwakeAutomationCondition; Defaults list; AppBundleList UI; matching via running bundle IDs.
