# Menu bar organizer

The opt-in Menu Bar Hider uses one hollow circle in both states. Click it to
show or hide the Hidden group. Always Hidden stays concealed in both states;
move an item to another group in Settings to make it available again.

## Arrange icons

Settings shows Visible, Hidden and Always Hidden as three horizontal, scrollable
rows. Icons run left to right in their real menu-bar order, with app names for
detected running apps' menu-bar items. It cannot discover status items
for applications that are not running. Basic hiding needs no permission. On
macOS 14–26, grant Accessibility in the editor to arrange items or use the drawer.
There is no separate advanced-mode switch. Inventory remains read-only without
Accessibility; system-hosted status items may also require that permission for
geometry discovery. Unavailable inventory is reported explicitly. Drag before a tile or onto a group's end; the context menu offers
the same group choices. Undo restores the last successful move. Protected or
ambiguous items stay visible in the editor but cannot be moved. An app with
exactly one AX-proven status item can be arranged even when that item has no
title or identifier; multiple unnamed items remain ambiguous.

The drawer scrolls independently of menu-bar width. Search supports fuzzy
matches, arrow navigation, Return and Escape. Always Hidden items are excluded
from both drawer and search, and the activation service rejects them. Previews capture the actual status-item artwork on each user’s Mac at runtime,
including text indicators. Screen Recording is optional and needed only for these
previews; without it, tiles show a neutral placeholder and retain names and
Accessibility-based arrangement. Captures are limited to validated menu-bar
windows, remain in memory, and are cleared when the editor/drawer closes or
permission is revoked. No captured artwork is bundled or uploaded.

Opening Settings, repeated clicks, Option-click and recovery never reveal
Always Hidden. The two underlying native spacers remain blank; no separator
symbols or style picker are exposed. Legacy icon-style preferences render the
same circle. The Always Hidden spacer is maintained even for older preferences
that had disabled it.

Activating a Hidden item temporarily moves its real status item into Visible,
opens its native menu, then restores its original position and the prior normal
expanded/collapsed state. Crowded notched bars use a reachable insertion slot.
Unknown, duplicate, protected, stale or unresolved identities are refused.
Failures before movement restore the previous state and timer. If a drag may
have displaced an item, recovery keeps normal Hidden items expanded; Always
Hidden remains concealed. Disable, uninstall, quit and permission loss cancel
input and release pending mouse input and cursor suppression. Decoration is
independent of Accessibility.

Window identities are reused during inventory polling; live status-item previews
refresh only while the editor or drawer is visible. Operations
revalidate identities; app, permission, display and wake changes invalidate the
inventory. Stale scans cannot publish results. Motion monitoring is active only
while Command is held.

The organizer backend is adapted from #360. It uses optional WindowServer
queries and synthesized Command-drags, gated before initialization on macOS 27
and later. Missing private geometry queries disable automatic operations. Basic
hiding remains available on newer systems. Stop other menu-bar managers before
arranging items.

## Spacing

Choose 4–32 points and click Apply to change `NSStatusItemSpacing` and
`NSStatusItemSelectionPadding` in the current-host global preference domain.
Applications pick these preferences up when restarted; signing out updates all
items. Vorssaint does not quit or relaunch other apps automatically.

Restore previous spacing restores both prior values, including removing a key
that was originally absent. The first Apply preserves the original values until
Restore succeeds, even across subsequent Apply operations or app restarts.
Restore remains available when the hider is disabled. This recovery state is
local to this Mac and is excluded from settings backup. A failed first Apply
clears its new recovery record only if rollback succeeds; failed rollback keeps
the original values recoverable. Existing malformed recovery data blocks Apply.
Complete uninstall restores spacing first and stops if restoration fails or the recovery data is
unreadable. The command-line uninstaller also keeps outstanding recovery data
when the installed binary is missing or too old to restore it. Clearing
permissions stops organizer input before revoking Accessibility and retains the
spacing choice. The desired spacing and
other organizer preferences participate in normal backups.

## Appearance

Optional decoration adds solid tint or gradient, border, shadow, rounded edges
and separate segments around the camera notch. The overlay ignores mouse input
and sits below the status items. It is removed when the hider or decoration is
disabled. Automatically hidden menu bars are left undecorated.

## Validation boundary

Automated tests cover search, geometry, ambiguity, section/neighbor verification,
platform gates, synchronous input cleanup, activation recovery, overlay teardown,
identity-cache reuse and stale completions, Command-only motion monitoring,
spacing transactions and rollback, settings backup, contextual permission demand
and all fifteen locales. These are
isolated tests; they do not synthesize input or modify the host's global spacing.

Before release, verify the following physically on supported macOS versions:

- Drag between all three sections, reorder within each, and undo including a
  protected neighbor and an empty section.
- Activate items with a native menu and a popover, leave the menu open beyond
  the auto-collapse delay, and check temporary movement and restoration.
- Try a notched display, a display without a notch, multiple displays, Spaces,
  fullscreen, automatic menu bar hiding, wake and a relaunch.
- Revoke Accessibility, disable/uninstall during a drag or click, and check that
  the cursor and mouse button are restored.
- Apply and restore spacing with originally absent/custom values, then restart
  apps and verify the result. No live global preferences were changed by tests.
- Check overlay layering, contrast, notch split, shadow and pointer pass-through
  in light and dark appearance.
- Check macOS 27 basic hiding and that advanced controls stay gated without
  touching the older private backend.

A settings preview demonstrates layout only, not successful desktop interaction.

## Attribution

The branch preserves #2741's commits by @0xJJphy. Inventory, identity resolution,
movement and WindowServer query code are adapted from #360 by @ruvelro and
@frogkingg. The hosted-window event field mapping was informed by
[Ice](https://github.com/jordanbaird/Ice) (GPL-3.0), specifically its
`MenuBarItemManager` event routing. The movement implementation retains
Vorssaint’s bounded drag, input cleanup and post-move verification.

## Display scope and validation limits

The inventory is scoped to the display containing the hider’s divider. A menu
bar on another display is never classified against those dividers. When displays
share the same menu-bar row, offscreen ownership cannot be established from
window geometry alone; ambiguous offscreen items are omitted rather than moved
on the wrong display. Vertically separated bars retain unambiguous offscreen
items. Full multi-display arrangement remains a desktop-QA limitation.

Native input targets the exact hosted status window through the session event
stream, and each move still requires a fresh position check. Undo can use a
locked or unnamed neighbor as an insertion anchor without making that neighbor
a movable source. The current native movement changes still need interactive
QA, especially Always Hidden and Undo; automated checks do not establish that
WindowServer accepted a physical rearrangement.

The basic circle remains permission-free. Automatic Command-drag expansion
while another app is active still depends on Accessibility for global modifier
events. Use the circle to reveal Hidden items first; permission-free global
modifier delivery remains unresolved and is not covered by automated tests.
