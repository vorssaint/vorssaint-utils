# Status item recovery — implementation plan

> **For agentic workers:** Inline TDD in `.worktrees/status-item-recovery`. PR Refs #1394.

**Goal:** Make “Show menu bar icon” recovery more likely to succeed without racing unsettled frames or parking a reset item against the notch.

**Architecture:** Extend `StatusItemPlacementSupport` (pure) + wire `StatusItemController` / `AppDelegate.verifyIconReappeared`.

**Tech Stack:** Swift / AppKit, MetricsTests, `./build.sh --test`

## Global Constraints

- Refs #1394 only; leave CHANGELOG; no bundle-id change
- Prefer extending existing recovery over new subsystems

---

### Task 1: Pure placement + settle helpers (TDD)

**Files:** `MenuBarSpacingSupport.swift` (`StatusItemPlacementSupport`), `StatusItemAnchorSupport.swift`, `MetricsTests.swift`

- [ ] Tests: bump cleans orphan keys for prior generations; seeds preferred position on new identity
- [ ] Tests: settling frame (h=0) vs trustworthy vs off-band
- [ ] Implement helpers; update tests that asserted “no hardcoded preferred position”

### Task 2: Wire recovery install + verify loop

**Files:** `StatusItemController.swift`, `AppDelegate.swift`

- [ ] Identity reset installs with squareLength + uses seeded position
- [ ] Verify waits while settling; more attempts after reset
- [ ] After on-screen, allow variableLength via refresh

### Task 3: Verify + PR

- [ ] `./build.sh --test`
- [ ] Push fork; `gh pr create`; comment #1394 and #1480
