# Clamshell gate conditions — implementation plan

> **For agentic workers:** Execute inline with TDD. Push to existing PR #1433.

**Goal:** Replace the single external-display clamshell gate with selectable Display / Power / Network conditions and an Any/All mode.

**Architecture:** Pure gate evaluation in `KeepAwakeAutomationSupport`; `KeepAwakeManager` wires display/power/network observers and calls `syncClamshellWithPolicy`. UI in Energy settings + menu panel Keep Awake card.

**Tech Stack:** Swift, AppKit/SwiftUI, Network (`NWPathMonitor`), MetricsTests, `./build.sh --test`

## Global Constraints

- Refs #1263 only; leave CHANGELOG alone; all locales for new strings
- Rebase onto current `origin/main` before shipping
- Median PR size; prefer extending existing keys over parallel systems

---

### Task 1: Pure gate API + tests

**Files:** `KeepAwakeAutomationSupport.swift`, `MetricsTests.swift`, `Defaults.swift`

- [ ] Failing tests for Any/All × empty/partial/full condition sets
- [ ] `clamshellGatePasses` + update `shouldApplyClamshell` to take `gatePasses`
- [ ] Defaults: `clamshellGatePower`, `clamshellGateNetwork`, `clamshellGateMode`; keep `clamshellExternalDisplay`
- [ ] Backup export keys + registered defaults assertions

### Task 2: Manager wiring

**Files:** `KeepAwakeManager.swift`

- [ ] Enable screen/power/network monitors when corresponding clamshell gate flags are on
- [ ] NWPathMonitor → schedule `syncClamshellWithPolicy`
- [ ] `shouldApplyClamshellNow` uses new API

### Task 3: UI + locales

**Files:** `Localization.swift`, all `Strings+*.swift`, `MenuPanelView.swift`, `SettingsView.swift` (`EnergySettings`), `SettingsDirectory.swift`

- [ ] Replace single toggle with mode picker + three condition toggles
- [ ] All locales; settings search keywords

### Task 4: Verify + push

- [ ] `./build.sh --test`
- [ ] Amend or second commit on `feat/clamshell-external-display`; force-with-lease only if rebased
- [ ] Update PR body; reply already posted to Francesco
