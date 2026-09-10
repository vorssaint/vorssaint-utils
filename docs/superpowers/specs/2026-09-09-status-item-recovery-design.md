# Status item recovery (#1394) — design

**Issue:** #1394 (troubleshooting sticky #1480 points here)  
**Approved:** 2026-09-09

## Problem

macOS sometimes never places the official `com.vorssaint.utils` status item in a visible menu-bar slot. Existing recovery (`recreate` → `bumpPlacementGeneration`) still fails for some users. Diagnostics (#1394):

- Fresh autosave + preferred position + `squareLength` restored the icon for one reporter.
- Zero-height frame at birth is normal; treating it as “hidden” races settlement (~4s).
- `bumpPlacementGeneration` leaves orphaned Visible/Preferred keys and clears the *next* preferred position, so a reset item is born against the notch (first zone a crowded bar drops).

We cannot change the shipping bundle ID.

## Approach

1. **Pure placement helpers** — clean orphans on bump; seed a mid-bar preferred position for the new identity; classify settling vs trustworthy vs hidden frames.
2. **Recovery install** — after identity reset, create with `squareLength`, apply seeded preferred position, keep square until verified (then return to `variableLength` via normal refresh).
3. **Verification** — wait longer while the frame looks unsettled (height 0); more attempts so a 4s settle is not judged “still hidden”.

## Out of scope

- Bundle ID change / separate “fix” product identity
- Killing MenuBarAgent from the app
- Guaranteeing placement when Control Center has permanently wedged a bundle ID (OS-side); we only improve best-effort recovery and avoid self-sabotage
