# Dynamic Island card expansion

## Interaction

Information bubbles open by clicking anywhere on their passive surface. The expand icon remains a keyboard-accessible shortcut; `+N` is only a count of omitted rows, never a requirement for expansion. A card with one item can still open to reveal a truncated name or explanation. Empty lists have no extra content to open.

Cards gently enlarge under the pointer. **Settings → Dynamic Island → Behavior → Enlarge cards on hover** controls this independently of the island’s own hover opening. It starts enabled; Reduce Motion suppresses enlargement.

The larger bubble grows from its source, above its neighbours, and stays within the visible page. Its surface reuses the source radius, selection tint and fill. AI headings and information rows are shared between the compact and expanded views. Text results retain their original fonts, including monospaced OCR and URL text. A raised glass surface retains the source’s white tint; the opaque fallback uses that same palette with a backing that stops peer text showing through.

Close, Escape and the dimmed backdrop close the reader. One reader opens at a time. Its content follows current data; it closes when its source disappears, leaves the viewport or the page changes. Expanded content scrolls and allows text selection where useful. Buttons within an informational card retain their actions.

Cards whose primary click already pastes, activates a window, opens a file or edits content keep that action. A separate reader is offered when there is useful hidden information; existing detail views are reused elsewhere.

## App-wide assessment

This inventory covers the rendered card families across all 15 Dynamic Island modules, their compact/notice variants, menu panels, standalone tools and settings. Repeated instances of the same component share the decision below. “Existing detail” means the information is already reachable through the named interaction, not that a new floating reader was added.

### Dynamic Island

| Bubble/card family | Result and reason | Source under `Sources/Vorssaint/UI/` |
| --- | --- | --- |
| AI provider limits | Click to read every current window and full scope label; provider mark, plan chip, meter colours and stale state remain. | `Notch/NotchAgentsView.swift` |
| AI Now | Whole bubble click shows every active session, full project/model labels and the live clocks. | `Notch/NotchAgentsView.swift` |
| AI Models / Projects | Whole bubble click shows every share, even without overflow; same coloured bars and numeric styles. | `Notch/NotchAgentsView.swift` |
| AI Spending | Card click opens provider costs, tokens, cache and savings information. The period menu remains a menu. | `Notch/NotchAgentsView.swift` |
| AI Trend / Activity | Card click retains the chart/map and adds its dated values; hover charts remain available. | `Notch/NotchAgentsView.swift` |
| AI Resets | Card click reveals its explanation, count and all known expiry dates. Redeeming still uses the existing confirmation buttons. The service can supply fewer expiry records than the count; the reader shows only known dates. | `Notch/NotchAgentsView.swift` |
| Notifications | Passive surface click opens the full message with the original message fonts. Open/dismiss remain separate actions. | `Notch/NotchNotificationsView.swift` |
| Notification hover banner | Existing detail: already displays the service-measured message and actions. Navigation opens the notification page. | `Notch/NotchNotificationsView.swift` |
| Clipboard | Explicit read-only reader for text, images and file paths, retaining pinned tint. Primary card click still pastes/copies. | `Notch/NotchClipboardView.swift` |
| Music metadata | Click the metadata bubble to read the complete title, artist and album. Source selector, artwork/app opening and transport keep their actions. | `Notch/NotchMusicView.swift` |
| Music lyrics / queue | Existing detail: full scrolling lyrics and queue; selection/seek actions remain. | `Notch/NotchLyricsView.swift`, `Notch/NotchQueueView.swift` |
| Downloads | Passive card click reveals the complete name/path and available status, progress and byte count. Finder/Shelf buttons retain their actions. | `Notch/NotchDownloadsView.swift` |
| System metrics | Existing detail: metric cards already open full detail pages. Battery device details now include all devices rather than the compact five-item prefix. | `Notch/NotchSystemView.swift`, `MenuPanel/MetricDetailView.swift` |
| Controls | Existing controls: sliders, device/menu choices, Keep Awake and fan actions. No omitted information collection needs a second reader. | `Notch/NotchControlsView.swift` |
| Mixer | Existing detail: full scrollable app rail, route menus and per-app volume controls. | `Notch/NotchMixerView.swift` |
| Calendar events / month cells | Existing detail: event click opens Calendar; title/time wrap. Location/calendar metadata is available in Calendar. Month/day clicks navigate the agenda and countdown choices remain actions. | `Notch/NotchCalendarView.swift`, `Notch/NotchCalendarMonthView.swift` |
| Files / Shelf | Existing detail: batch expansion, previews and path tooltips. Primary selection, open and drag interactions remain. | `Notch/NotchFilesView.swift`, `Shelf/` |
| Recent captures | Existing detail: Restore/Open exposes the complete capture; recorder/capture buttons keep their actions. | `MenuPanel/PanelRecentCapturesView.swift`, `Notch/NotchCaptureControlsView.swift` |
| Scratchpad / snippets | Existing detail: scrolling editor, formatting preview and snippet editor/library. Card click must keep editing possible. | `Notch/NotchScratchpadView.swift`, `SnippetLibraryView.swift` |
| Timer | Existing detail: timer/ruler controls expose the current timer and editing. Presets start timers. | `Notch/NotchTimerView.swift`, `Notch/NotchTimerRuler.swift` |
| Camera | Existing detail: live preview and device/mirror choices. | `Notch/NotchCameraView.swift` |
| Explore / quick access / section tiles | Existing navigation: tiles choose modules or perform actions; pages expose the destination content. | `Notch/NotchSectionsView.swift`, `Notch/NotchQuickAccessView.swift` |
| Compact strips / activity capsules / notices | Existing navigation: select the related page or perform the notice action. Compact display is intentional; no duplicate floating reader. | `Notch/Notch*Strip.swift`, `Notch/NotchCapsuleViews.swift`, `Notch/NotchNoticeView.swift` |
| Mirrors / lock screen | Passive/private display by design; interaction and content limits remain intentional. | `Notch/NotchMirrorView.swift`, `Notch/NotchLockScreenView.swift` |

### Tools and menu panels

| Bubble/card family | Result and reason | Source under `Sources/Vorssaint/UI/` |
| --- | --- | --- |
| Cleaned URLs | Click result bubble for the complete selectable monospaced URL; copy remains available. | `MenuPanel/PanelURLCleanerView.swift` |
| OCR results | Click result bubble for full selectable monospaced text with a copy action. | `Media/MediaWorkspaceView.swift` |
| Completed media batch failures | Click the failure summary for all retained failure paths/messages, keeping the same subdued typography. This covers completed batches with partial failures. All-output-failed service behaviour is unchanged and does not retain a completed batch. | `Media/MediaWorkspaceView.swift` |
| Media input/settings/progress/success | Existing scrolling workspace, configuration controls and output-file actions. | `Media/MediaWorkspaceView.swift` |
| Uninstaller failure note | Click summary to read every remaining item and path; outside the island a native disclosure exposes the same list. Full Disk Access action remains separate. | `SharedUI.swift` |
| Uninstaller app/leftover cards | Existing selection, full scrolling leftover list, scan/removal details and confirmation actions. | `MenuPanel/PanelUninstallerView.swift`, `Uninstall/UninstallerView.swift` |
| Homebrew package/detail cards | Existing row selection opens package details. Descriptions and error messages wrap in their scrolling detail page. | `MenuPanel/PanelHomebrewView.swift` |
| Homebrew operation status | Existing Show Details provides a scrolling, copyable operation log. | `HomebrewOperationStatusView.swift` |
| Port Manager | Existing full process/port list, selection and termination confirmation. | `MenuPanel/PanelPortManagerView.swift` |
| Window Layout | Existing layout selection/editor and application actions. | `MenuPanel/PanelWindowLayoutView.swift` |
| App updates | Existing full scrolling app list, release notes/detail destinations and update actions. | `MenuPanel/PanelAppUpdatesView.swift`, `AppUpdates/AppUpdatesListView.swift` |
| System / disk / network / power / processes | Existing metric details and scrolling process/device lists. Shared detail cards keep their navigation. | `MenuPanel/*Section.swift`, `MenuPanel/MetricDetailView.swift`, `MenuPanel/ProcessUsageRow.swift` |
| Fan / brightness / mixer / audio priority / Keep Awake / quick toggles / wallpaper | Existing curves, sliders, menus, rule editors or actions expose the relevant settings. | `MenuPanel/*Section.swift`, `MenuPanel/MenuPanelView.swift`, `KeepAwakeAutomationView.swift` |
| Menu panel clipboard | Existing preview sidebar already reads full text/images/files. Preserve paste/copy actions. | `MenuPanel/PanelClipboardView.swift`, `MenuPanel/ClipboardEntryPreviewContent.swift` |

### Other app surfaces

| Bubble/card family | Result and reason | Source under `Sources/Vorssaint/UI/` |
| --- | --- | --- |
| Switcher / Dock window cards | Existing window selection/activation plus close/minimize. Primary click has a window action. | `Switcher/` |
| Shelf tiles / groups | Existing batch expansion, file previews, tooltips and native sharing. Keep selection/drag actions. | `Shelf/` |
| Settings cards / presets / trust cards | Settings, navigation and confirmation controls; explanations already wrap. Keep control interaction. | `Settings/SettingsCard.swift`, `Settings/FeatureHubSettings.swift`, `Settings/HomebrewSettings.swift` |
| Layout/settings previews | Existing editing/dragging/selecting in preview canvases. These are configuration surfaces. | `Settings/Notch*Editor.swift`, `Settings/PanelLayoutEditor.swift`, `Settings/RadialMenuVisualCanvas.swift` |
| Screenshot / recorder / camera editors | Existing full editors and media previews. | `Screenshot/`, `Recorder/`, `CameraPreview/` |
| Cleaner / Kill Process / Command Bar | Existing scrolling results, selection and explicit actions/confirmations. | `Cleaner/`, `KillProcess/`, `CommandBar/` |
| Permission cards / onboarding / update highlights / alerts / feedback HUDs | Existing explanations/actions or transient feedback, with no hidden collection to reveal. | `PermissionGuideOverlay.swift`, `Onboarding/`, `UpdateHighlightsView.swift`, `NonModalAlert.swift`, `QuitProtection/`, `Finder/` |

## Verification and preview

Build the app and run the focused Dynamic Island and Agents suites. Check bounded popup geometry, source removal, the independent hover setting and Reduce Motion. In the native sample preview, click the middle of a Now/Models bubble, repeat with a single item and no `+N`, compare headers/row colours in both states, and verify Close/Escape, scrolling and selectable OCR text. Check nested buttons keep their original actions.

The preview uses extracted production AI cards and OCR result markup with the shared presenter, surfaces and TextKit reader, plus isolated sample data. Its surrounding window is a demonstration shell; copy/service actions use demo implementations. Capture the native compositor so glass is represented accurately. Store screenshots and the runnable app before requesting permission to publish.

### Current review status

The app and native component preview build. After integrating current main, the optimized app build and selftest pass; the focused Dynamic Island suite passes 74,151 checks, including the source-to-reader transition geometry regression, and the Agents suite passes 476 checks. Verification ran on Mac14,9 with macOS 26.6.2. The user reviewed the native sample previews in English and confirmed the revised interaction and motion.

Each reader has its own identity inside a stable overlay. A native geometry effect maps the actual reader frame onto its own source in page coordinates for both opening and closing. This avoids scaling around the page centre or carrying another reader’s layout into the transition. The idle presenter passes pointer events through to the cards.

The preview uses sample data and implemented components. The rest of the assessed app surfaces have code/build coverage rather than a complete manual walkthrough. Computer Use remains off; the user’s recordings supplied the visual feedback.
