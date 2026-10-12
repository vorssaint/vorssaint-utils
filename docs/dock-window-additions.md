# Dock and window additions

These options live in **Settings → Dock** and **Settings → Switcher**. New input, capture and widget options are off until enabled. Install **Active app indicator** or **Keep Dock on a display** in the Features hub to enable either independently of Dock Preview.

## Features

| Addition | Behavior and controls |
| --- | --- |
| Active app indicator | An underline marks the foreground app's Dock tile. Set its hex color, length, thickness and offset. The dots style also marks other running apps; a hollow dot means no ordinary Window Server window was found. Bottom, left and right Docks are supported. |
| Dock display lock | Choose a connected display and a bypass modifier. Only exposed edges of other displays are blocked; shared edges remain traversable. A fully covered target edge or disconnected target disables the lock. Relocation waits for the pointer to rest, cancels on real input and restores its original position. Hold the bypass key to move the Dock freely. A failed relocation is not retried continuously. |
| Compact window list | Use titles instead of thumbnails, always or above a chosen window count. Without Screen Recording, Dock Preview automatically uses this list and still reads titles through Accessibility. |
| Live thumbnails | Visible Dock, detached Dock and switcher sessions can use independent ScreenCaptureKit streams. Choose 5–120 FPS and a 320–2048 pixel limit. At most 12 windows stream per surface; other windows retain snapshot previews. Frames coalesce when the UI is busy. No audio or pointer is recorded. |
| Folder browser | Hover a folder in the Dock; browse into subfolders, sort by natural filename, modification time or size, reverse the order, show hidden files and open items. Sort choices can be remembered locally per folder. The browser reads at most 500 entries per directory; the count link opens the complete folder in Finder. Pin the panel to keep it open. |
| Dock media widget | Hover the app currently reported by the Now Playing adapter. Play/pause, skip and seek without enabling Dynamic Island. Other-player support shares the existing media preference. Players requiring Automation offer an explicit permission action. |
| Synced lyrics | Enable lyrics in the Dock player. Local imports and the existing optional online lookup work with a separate lyric session. Online lookup follows the existing explicit consent preference; track metadata is sent to the lyric provider only when consent is enabled. |
| Dock calendar widget | Hover Calendar to view the remainder of today or choose another date. Calendar access is requested only with its permission button. The visible panel refreshes on EventKit changes and once a minute. Existing excluded-calendar choices are respected. |
| Native Command-Tab | Opt in to previews above the highlighted app in macOS's own Command-Tab switcher. Click a window to activate it. This mode observes the native shortcut; use it with Vorssaint's switcher assigned to another shortcut and native Command-Tab takeover disabled. |
| Trackpad switching | Choose three or four fingers and a horizontal or vertical gesture. Coherent travel opens the window switcher; continued travel cycles forward or backward, and lifting commits. macOS gestures using the same finger count and direction can conflict; choose System Settings gestures accordingly. |
| Preview gestures | A two-finger swipe away from the Dock maximizes a window; toward it minimizes/restores. A deliberate shake of a dragged preview minimizes the other listed windows in that app/group. Ordinary drag-to-place remains available. |
| Dock and title-bar scrolling | Scroll up on a Dock app to show it, down to hide it. On the active media app, scrolling adjusts system output volume. Scroll up on an active window title bar to maximize, down to center it; horizontal scrolling or holding Option uses the user's registered Space-navigation shortcut. Momentum events are ignored. |
| Quick quit | Command-right-click on a Dock app asks it to quit. Option-Command-right-click force quits it. Both are available only when this option is enabled. |
| Preview triggers and hover actions | Choose normal hover, middle click, or modifier-click to open previews. Optionally activate a window or show a full-size preview after a configurable hover delay. |
| Window actions | Separate close, minimize, fullscreen and quit controls; maximize, center and bulk actions in the context menu. Middle click can be reassigned or disabled. Bulk close closes windows rather than using the configurable single-card quit action. |
| Layout and navigation | Choose rows/columns, spacing, corners, top/bottom controls, numbered Space badges, title/app/creation sorting, title-substring exclusions, and optional grouping of identical app instances. Optional HJKL navigation and 0–3 allowed search typos extend the switcher. A minimize key is off by default and can be assigned to M, X or N. |
| Pointer following focus | Off by default; optionally move to the focused window's center always, or only when switching displays. |
| App instances | Launcher identity and bounded Parall storage-path matching keep launcher tiles attached to their own process. Ambiguous same-bundle/same-name tiles are left unresolved instead of selecting an arbitrary sibling. |
| AppleScript / CLI | An opt-in, bounded JSON command API queries windows/apps and controls previews, the switcher and windows. See below. |

Accessibility is required for global input and other apps' window control. Screen Recording is required for images, including scripted image requests; compact lists, indicators and display locking do not require it. Browsing protected folders may need Files and Folders access. Calendar and player Automation permissions are independent of Dynamic Island. No feature automatically enables another permission or changes a system gesture/shortcut.

Disabling a feature, uninstalling it, sleeping or leaving the console session tears down its new resources. Closing one media surface does not stop another surface's adapter. Folder paths and display IDs are excluded from portable settings backups; other registered options are portable.

## AppleScript and `osascript`

Enable Dock Preview and **AppleScript API** first. Calls require Accessibility and an active console session. With the built application installed:

```sh
osascript -e 'tell application "Vorssaint" to window command "windows"'
osascript -e 'tell application "Vorssaint" to window command "apps"'
osascript -e 'tell application "Vorssaint" to window command "activeWindow"'
osascript -e 'tell application "Vorssaint" to window command "showSwitcher"'
osascript -e 'tell application "Vorssaint" to window command "hidePreviews"'
```

Commands return JSON text. Parameters use `with parameters` and a JSON object:

```applescript
tell application "Vorssaint"
    window command "showPreview" with parameters "{\"pid\":1234}"
    window command "window" with parameters "{\"id\":42}"
    window command "focus" with parameters "{\"id\":42}"
    window command "move" with parameters "{\"id\":42,\"x\":100,\"y\":100,\"width\":800,\"height\":600}"
    window command "cycleSwitcher" with parameters "{\"delta\":1}"
    window command "commitSwitcher"
end tell
```

Replace example IDs with IDs from `windows` or `apps`; zero, booleans, fractional and stale IDs are refused. IDs are re-resolved against the current window list before each action. Arguments are limited to 16 KiB. Frames use Window Server coordinates (top-left of the primary display; Y increases downward). Offscreen and invalid frames are refused.

`focus`, `close`, `minimize`, `maximize`, `restore`, `fullscreen`, `center`, `hide` and `quit` take an `id`. `minimize` and `fullscreen` toggle the current state; `restore` uses the last frame saved by a maximize action. Actions return `{"accepted":true}` when dispatched/accepted, not a guarantee that an app has finished applying them. `hidePreviews` closes hovered, detached and widget panels. `previewImage` takes an `id` and returns a cached PNG as `pngBase64`; it requires Screen Recording and respects preview exclusions. The API runs no shell commands and writes no files.

## Automated regression coverage

The `dock-enhancements` suite compiles the production resolver, click validation,
session ordering, compact bulk action, placement and lifecycle methods against
inert doubles. It covers duplicate app names and launcher paths, moving or hidden
Dock tiles, overlays, delayed clicks, permission revocation, filtered foreground
windows, parallel/perpendicular gestures, mixed minimized lists, compact session
handover, empty external requests, grouped-window close confirmation, lock-screen
music ownership across unlock, repeated stop/re-enable and all-disabled widgets. No target app is quit
or captured by these checks. These simulations complement the native cases below.

## Manual validation before release

Use the developer app with its own preferences and permissions; keep the installed app's settings intact.

- Exercise underline/dots with all three Dock orientations, magnification and autohide. Confirm no stale overlay when Dock hides or restarts.
- Exercise display locking with adjacent, offset and stacked monitors; disconnected targets, fully covered edges, bypass, real pointer cancellation, and sleep/wake.
- Deny Screen Recording and confirm title-list switching, closing and minimizing still work. Enable it and confirm live frames stop on close, disable, uninstall and session changes; test frontmost preview exclusions.
- Test native Command-Tab above normal/fullscreen desktops without shortcut takeover, and choose windows by mouse. Test three/four-finger open/cycle/lift, diagonal rejection, early lift during enumeration, and existing system-gesture conflicts.
- Select an app with no previewable windows in native Command-Tab and through `showPreview`, including fully filtered lists; normal Dock hovers must still work afterward. With grouping enabled, close a sibling process's window and confirm its card disappears immediately after close confirmation.
- Test overflowing previews with horizontal trackpad scrolling on a bottom Dock and vertical scrolling on side Docks. Check perpendicular gestures still work, compact Minimize all with a mixed list, sorting with a filtered foreground window, and filters excluding every window.
- Test quick quit against disposable apps with duplicate names, a closed pinned launcher, magnification/autohide changes and overlapping preview/widget panels; only the clicked running app may receive quit.
- Test live-to-compact app handover and closing pinned panels; old captures and hover peeks must stop. Grant/revoke Accessibility with only indicator or display lock installed. Confirm all-disabled widgets leave no timer or media consumer.
- Test swipe, shake, middle/modifier triggers, hover activation, full-size peeking, normal drag-to-place, and pinned previews. Test grids on small displays and each Dock edge.
- Test folders with protected access denied, hidden files, subfolders, more than 500 files, remembered sorts, opening items, pin/close and moving off the hover corridor.
- Test media with Music, Spotify and other supported players, paused playback, unavailable Automation, lyrics consent/import/track changes, and simultaneous Dock/Island/lock-screen consumers. Confirm calendar consent and today's events without Dynamic Island.
- Lock and unlock with music enabled, then disable the island. Confirm the adapter stops when no surface needs it, and stays running when a Dock media widget still owns it. Rearrange displays while locked and confirm rebuilding the lock-screen scene preserves playback.
- Compile and execute AppleScript queries and controls against the developer app. Test disabled API, denied Accessibility/capture, stale IDs, bad JSON and excluded preview images.

The gesture detector is adapted from [DockDoor's GPL-3.0-or-later implementation](https://github.com/ejbills/DockDoor/blob/7be384b46da66f380bf3a9bb24ee6c6476bbd0dc/DockDoor/Utilities/TrackpadSwipeTrigger.swift), with its attribution retained. Other additions integrate with Vorssaint's existing window, preview, media, lyrics and calendar services. This comparison covers DockDoor's public/free repository, not DockDoor Pro.
