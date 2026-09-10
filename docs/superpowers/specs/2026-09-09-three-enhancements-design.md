# Batch: clipboard sounds, spaces short-click, linked brightness

**Approved:** 2026-09-09  
**Issues:** #1340, #1507, #1504  
**Skipped:** #1495 (already `saveAndCopy`); #1475/#1476 (open PRs exist)

## Designs (short)

### #1340 Clipboard history sounds
Three opt-in Defaults; Pop on capture/paste success; gated failure sound without double-beep vs Command Bar. Mirror FinderCutPasteSoundSupport.

### #1507 Spaces-drag + short-click
Same button may bind spaces-drag and a shortcut. Drag fires spaces; short click without movement fires shortcut (else native replay).

### #1504 Link brightness displays
`brightnessLinkDisplaysEnabled`; delta applied to all adjustable displays via pure `linkedBrightnessLevels`; OSD on source only.

## Worktrees
- `.worktrees/clipboard-history-sounds` → `feat/clipboard-history-sounds`
- `.worktrees/mouse-spaces-short-click` → `feat/mouse-spaces-short-click`
- `.worktrees/brightness-link-displays` → `feat/brightness-link-displays`
