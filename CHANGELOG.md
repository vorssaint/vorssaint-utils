# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [3.1.16]

### Summary
Vorssaint 3.1.16 cleans up the sound of boosted apps and repairs maximizing
and window layout in browsers where windows moved without taking their new
size.

### Fixed
- Boosting an app's volume above 100% no longer adds a crackling noise while
  the sound is loud. The boost now eases the peaks down for a moment instead
  of chopping them off.
- Maximizing with the green button no longer leaves some windows parked at
  the left edge of the screen with their old size. Browsers that take a
  moment to resize now fill the screen properly.
- Window layout shortcuts, the panel buttons and the drag gesture now resize
  those same browsers correctly instead of moving the window and leaving its
  size behind.

## [3.1.15] - 2026-07-21

### Summary
Vorssaint 3.1.15 fixes starts that could leave the app with no menu bar icon
or quit it right away, freezes where the app stopped responding, a crash
while choosing a screenshot area, and an external display that could go dark
and stay dark. It also gives back the clicks that moving windows by dragging
was taking from other apps, repairs smooth scrolling, the brightness keys and
the shortcut recorder, and brings the window switcher back on the first
press.

### Fixed
- Moving and resizing windows by dragging no longer takes the modifier click
  away from other apps. A click that does not move now goes to the app as
  usual, and the window only follows the pointer once you actually drag.
- The window switcher opens on the first press again after you close every
  window of an app or move to another desktop. With nothing left to switch to,
  the shortcut now stays quiet instead of falling back to the system switcher.
- Smooth scrolling moves the right distance on mice that report the wheel
  continuously, and the speed setting now works on them.
- Smooth scrolling no longer reverses the scroll direction on its own.
  Inverting the direction works alongside it, and so does Shift to scroll
  sideways.
- The app could start with no menu bar icon and quit a few seconds later.
  It now starts reliably, including on a Mac whose display was still waking
  up.
- The app could quit at startup right after an update, while the tour of the
  new features was opening. The tour now keeps the same size on every page.
- The app could stop responding for a while at a time, often right when
  headphones or another audio device connected. It no longer waits on the
  audio system, on other apps that are busy, or on commands that never
  answer, and it stops watching audio properly when the mixer or the mic
  mute is switched off instead of leaving watchers behind.
- An external display could go dark while its brightness was adjusted and
  stay dark until it was unplugged. It recovers now, and a screen switched
  off here comes back at the next start.
- Choosing a screenshot area no longer quits the app when the drag ends with
  more than one finger leaving the trackpad. Cancelling with Escape is safe
  too. Thanks to @lei1024.
- Window Switcher previews show the whole window. A window pushed over the
  edge of the screen used to appear as a thin strip.
- Brightness keys follow the pointer on keyboards other than the built-in
  one, including with the lid closed.
- Per-app volume no longer jumps loud or quiet when an app changes what it
  is playing. Quitting or switching the mixer off puts back the input
  device and the volume it changed.
- The panel stays under its icon when the menu bar is set to hide itself.
  Switching tabs no longer moves it to the edge of the screen.
- Recording a shortcut captures it instead of running it. Delete clears the
  shortcut, more keys can be recorded, and the field no longer overlaps the
  text beside it while it listens.
- The radial menu settings now say whether the app can see the mouse button
  you picked, so a button the mouse itself has taken over is obvious.

## [3.1.14] - 2026-07-18

### Summary
Vorssaint 3.1.14 adds a radial menu that puts your favorite actions on a
wheel around the pointer, Camera preview, a floating mirror for video
calls, and a scratchpad that keeps quick notes in a floating window and
saves as you type. A short tour presents the highlights once after the
update. Screenshots gain a pixel loupe, QR code reading and
solid color blocks, the clipboard history can keep up to 1000 items, and a
long round of fixes covers typing lag with the App Switcher on, brightness
keys on external monitors, Launch at Login, the Volume Mixer and more.

### Added
- A new radial menu puts your favorite actions on a wheel around the
  pointer, from apps and links to media controls. Hold the shortcut or an
  optional side mouse button, point and release. Off by default in Settings
  under Radial menu.
- Camera preview opens a small floating mirror with your webcam from the
  panel, the quick panel or a shortcut. It picks between cameras when more
  than one is connected and closes when you click away.
- A scratchpad keeps quick notes in a small floating window that saves as
  you type. It opens from the panel, the quick panel or a shortcut, and can
  clear itself after days unused.
- The optional brightness overlay shows the percentage after brightness
  changes on the Mac screen and external monitors. Off by default in
  Settings under Energy.
- Screenshots can skip the floating preview and open straight in the
  annotation editor. Off by default in Settings under Screenshot.
- The screenshot selection now has a pixel loupe for precise captures.
  Press Z to show or hide it and scroll to zoom. Thanks to @ruvelro.
- Copy text from screen now reads QR codes and shows their content so you
  can copy it or open the link. The same works from a screenshot's preview
  and editor. You can turn it off in Settings.
- The Disks panel now shows each drive's file system format, like APFS or
  exFAT, next to the drive name.
- The clipboard history can now keep up to 1000 items. Pick the size in
  Settings under Clipboard. Thanks to @ruvelro.
- A short tour opens once after the update, showing the new features with
  a button to set up or try each one right away.

### Changed
- Dock Preview now works with Dock magnification enabled, so the zoom effect
  no longer needs to be turned off.
- The black bar in the screenshot editor is now a solid block that can use
  any of the palette colors.
- Window Switcher now moves to the last item in a shorter next row when the
  down arrow has no item directly below.

### Fixed
- Typing no longer lags in demanding apps while the App Switcher is on.
  Under heavy load, key presses could arrive late and then land all at
  once.
- Brightness keys now really follow the pointer on external monitors that
  macOS drives natively, including with the lid closed. Presses used to
  land only on the built-in display.
- Vorssaint no longer crashes right after launch when macOS returns no power
  source data for the battery readings.
- Closed lid mode no longer asks for the administrator password on every
  toggle. The one-time setup is now verified for real and repaired with a
  single prompt when it stops working.
- Smooth scrolling now works with mice that report the wheel as continuous
  scrolling. Their events were mistaken for a trackpad and skipped.
- Apps that run through a compatibility layer now show up in the Window
  Switcher. Focusing one no longer makes the shortcut fall back to the
  system switcher.
- Browsers that play sound through helper processes now show up in the
  Volume Mixer. macOS does not credit that sound to the app, so the mixer
  traces it back on its own.
- Back/Forward mouse buttons now reach apps that handle them natively, like
  browsers, virtual machines and remote screens, instead of being captured.
  Finder and other apps keep the converted navigation.
- The Shelf area under the menu bar icon no longer appears while a window is
  being moved or resized. It only opens for a real file or content drag.
- Launch at Login no longer turns itself off after the app restarts. The app
  restores the setting when macOS drops it and now explains when it runs from
  a place that cannot open at login.
- Extra Brightness no longer drops briefly as video enters or leaves fullscreen.
- Monitor blocks in the menu bar, including the usage bars, no longer sit a
  couple of pixels above the other status icons on macOS 26 (Tahoe).
- Settings sidebar rows no longer slide over the search field while
  scrolling on macOS 26 (Tahoe).
- The macOS permission prompts now appear in the language the app speaks
  instead of English only.

## [3.1.13] - 2026-07-15

### Summary
Vorssaint 3.1.13 adds a screenshot tool with a quick preview and optional
editor, brightness and power controls for
all your displays, a Quick toggles tab, automatic Keep Awake rules and compact
usage bars in the menu bar. It also keeps Extra Brightness steady around
fullscreen video and returns Finder to the Volume Mixer.

### Added
- Screenshot captures an area, window or screen. A compact
  preview offers copy, save, delete and editing, with stickers, annotations,
  precise crop, optional shadows and backgrounds in the editor.
- Display controls for the Mac screen and external monitors in the menu bar
  panel and Settings. Adjust brightness, turn a display on or off and
  optionally let the keyboard brightness keys follow the pointer. Enable
  Displays under Energy settings.
- A new Quick toggles tab offers one-click actions such as switching between
  light and dark mode, emptying the Trash, ejecting all disks and hiding
  desktop icons. It appears in the menu bar panel and in the quick panel.
- The battery's estimated time remaining can appear in the menu bar and the
  Power panel. The menu bar reading is off by default and can be enabled in
  Settings.
- Keep Awake can start with an external display or while connected to power.
  Combine both conditions in Options or Energy settings.
- Keep Awake can use the Vorssaint, coffee, eye, moon or lightbulb icon while
  active. Choose the icon and its color in Options or Energy settings.
- Window Layout moves and resizes windows from any point with a trackpad or
  mouse. Drag with chosen modifiers to move, add Shift to resize, or use the
  mouse's right button. It is off by default in the panel and Settings.
- CPU, GPU, memory and disk use can appear as compact bars in the menu bar.
  Choose Values or Bars and adjust their colors and medium and high limits in
  Monitor settings.
- Cleaning Mode now blacks out every display while the keyboard is locked.
- Korean is now available throughout the app and can be selected in Settings.
  Thanks to hyo.c (@pshyomin) for the translation.

### Changed
- Package updates now stay at the top of the installed list, with clearly
  labeled controls in the panel.
- Monitor alerts now explain when limits trigger a notification, when short CPU
  spikes are ignored and that the time setting only delays repeated alerts.

### Fixed
- ⌘Tab now falls back to the system switcher when a fullscreen app does not
  expose a switchable window.
- Smooth Scrolling now moves horizontally while Shift is held.
- Dock click to minimize now reacts immediately in more apps and no longer
  opens unrelated windows.
- Closed lid mode now asks for the administrator password only once.
- Extra Brightness no longer flashes when video enters or leaves fullscreen.
- App Switcher now includes apps that draw their windows separately, with
  working previews.
- Finder stays available in the Volume Mixer for Quick Look audio. A switch
  at the bottom can hide it.
- Clipboard History no longer crashes when automatic URL cleaning inspects the
  same copy.

## [3.1.12] - 2026-07-11

### Highlight
Vorssaint is massively optimized, with up to 95 percent less CPU and
energy use than 3.1.11. Cooler, quieter and easier on your battery.

### Summary
Vorssaint 3.1.12 adds a Features hub with one click bundles and honest
energy badges, an onboarding that sets the app up from one answer, a
floating permission guide, text snippets, settings backup and a cleaner
that reaches the storage macOS calls Other. It is also far lighter on
CPU and fixes extra brightness during HDR video, Dock icon dragging and
Dock clicks on Java apps.

### Added
- A Features hub in Settings installs and uninstalls whole features.
  What you uninstall disappears from the entire app and stops loading,
  so it uses no CPU, memory or energy. Nothing is deleted and installing
  brings it back as it was. Its Permissions tab shows which features use
  each permission and flags granted ones nothing is using.
- Start with a bundle. Three one click packs in the hub shape the app
  for volume, windows or battery, and every feature now wears an honest
  energy badge telling what it keeps alive while on.
- Onboarding now ends asking what brought you here. One answer applies
  the matching bundle and setup finishes already shaped for it.
- A small floating guide appears when a permission needs a trip to
  System Settings. It shows the three steps and notices the grant by
  itself.
- Text snippets turn a short trigger into your text, right away or
  after a space, with date, time and clipboard variables. Off by
  default, in the panel's keyboard controls and in Settings.
- The cleaner now reaches the storage macOS calls Other. Old iPhone and
  iPad backups appear with device and date, never preselected, and
  stale Xcode DeviceSupport caches join the developer junk.
- Settings backup exports your whole setup to a file and imports it on
  another Mac. In the Advanced settings.

### Changed
- Deep energy work across the app. Mouse movement, typing, menu bar
  metrics and permission checks stop repeating work they had already
  done. Everything looks and behaves exactly the same, just cooler.

### Fixed
- Extra brightness no longer flickers or drops out while HDR video plays
  or goes fullscreen. The boost now holds steady and follows the panel
  smoothly.
- Clicking the Dock icon to minimize now works with Java apps such as
  DBeaver. Windows the system reports slowly or not at all get a second
  look, and apps without a Minimize All menu use their plain Minimize.
- Dock icons can be dragged and reordered again while Dock clicks are
  on. The click now acts when the button lifts, so press and hold turns
  into a normal drag.
- The side buttons option no longer shows the invert scrolling text
  while active.
- The menu bar panel opens centered under the app icon again. Newer
  macOS builds could strand it against the screen edge until the tabs
  changed.
- Hovering a Dock preview can no longer pull a minimized window back
  out. A window whose state cannot be verified now stays untouched, and
  a Dock that restarts while previews are blocked is picked up again.

## [3.1.11] - 2026-07-10

### Summary
Vorssaint 3.1.11 adds Cleaner, a simpler switcher, more useful Shelf
controls, sixth screen layouts and mouse side button navigation. It also
keeps extra brightness steady, blocks unwanted Music launches and lets
paste as plain text use Command V.

### Added
- The Cleaner finds leftovers from uninstalled apps, caches and logs.
  You review everything first, removed items go
  to the Trash, and the safe part can also run on its own daily or
  weekly. In the quick panel and the menu bar panel.
- Stop Music from opening on its own. With the option on, pressing a
  media key no longer brings up the Music app, and another app of your
  choice can open instead. Off by default, in the General settings.
- The app switcher has a simple app layout with window titles but no
  previews or screen capture, while still restoring minimized windows.
  Off by default in the App Switcher settings.
- Window Layout can place the active window in any cell of a six part
  grid. Each action can receive its own shortcut in Settings.
- Mouse side buttons can navigate back and forward in Finder, browsers
  and compatible apps. Off by default in Mouse settings and the panel.

### Changed
- The Shelf can close and remove items after a successful drop, stay open
  when pinned and ignore automatic opening in chosen apps. File tiles also
  offer Open With and AirDrop from the right click menu.

### Fixed
- Extra brightness no longer fades back a moment after turning on. The
  boost now holds steady and adapts to what the display can sustain.
- Paste as plain text now works when its shortcut is set to Command V.

## [3.1.10] - 2026-07-09

### Summary
Vorssaint 3.1.10 fixes extra brightness, which showed as unavailable on
the MacBook Pro models it was made for.

### Fixed
- Extra brightness is now available on every MacBook Pro with an XDR
  display. It stayed marked as unavailable on those Macs.

## [3.1.9] - 2026-07-08

### Summary
Vorssaint 3.1.9 gives the shelf a home under the menu bar icon, adds
smooth mouse scrolling and extra brightness for XDR displays, and makes
the Settings window resizable. It also fixes typing freezes while a
password prompt is open.

### Added
- Drag a file toward the menu bar and the shelf opens under the app icon
  to catch it. Dropped items stay in a small mark there that opens with a
  click and leaves once the shelf is empty. On when the shelf is on, with
  a switch in the shelf settings.
- The XDR display of MacBook Pro models can now go past its maximum
  brightness, using the reserve the panel saves for HDR. Off by default,
  in the Energy settings, with an intensity slider.
- Mouse wheel scrolling can glide smoothly instead of jumping line by
  line. Off by default, in the Mouse settings, with an adjustable step.
- The dock click to cycle windows option now has a toggle in the menu bar
  panel too, next to the other quick controls.

### Changed
- The Settings window is now resizable, opens tall enough to show the
  whole sidebar and remembers the size you choose.
- Holding the switcher key now stops at the end of the list instead of
  wrapping around, like the system switcher.

### Fixed
- Typing no longer freezes for a few seconds while an app shows a password
  prompt, such as an unsigned app asking for the Keychain.
- The switcher shortcut for windows now works in the plain grid too,
  jumping between the selected app's windows while the switcher is open.
- The extra key on ISO keyboards, such as the caret key on German ones,
  can now be recorded as a shortcut.
- Paste as plain text now asks for the Accessibility permission it needs
  instead of silently swallowing the shortcut when it is missing, and the
  paste lands more reliably once the shortcut keys are released.
- Sidebar items no longer show through the Settings search field while
  scrolling.
- Updating Homebrew packages from a third party tap no longer fails
  silently, offering a one click step to trust the tap and continue.
- Finder no longer shows up in the Volume Mixer.

## [3.1.8] - 2026-07-07

### Summary
Vorssaint 3.1.8 polishes the whole app. The Settings window gains a search
field and clearer groups, the menu bar metrics learn a compact spacing and
can stand alone without the app icon, and the image converter now produces
PDFs. Community requests came along: an optional mute indicator beside the
menu bar icon, a progress bar when files move to another disk, and HEX
colors copied without the # sign. Under the hood, in app updates now
install reliably and show download progress, the shelf keeps its items
across restarts and updates, the quick panel works properly with file
dialogs and drag and drop, and the menu bar panel no longer flickers on
the Volume Mixer page on Macs with busy audio activity.

### Added
- The quick panel now has a close button, so it can be dismissed with the
  mouse as well as with Esc. The first nine tiles also show a small number
  badge, since pressing 1 to 9 launches them straight from the keyboard.
- The quick panel's edit mode now adjusts tools in place: tiles with a gear
  badge (Keep awake, Mute microphone, Color picker and Clipboard) open a
  small card with their closest options, like keeping the Mac going with
  the lid closed, the default duration, the muted mic indicator in the menu
  bar, the copied color format and the clipboard history limit, with no
  trip to the Settings window.
- The window layout grid can now hide the arrangements you never use: a
  tune button in its header switches the buttons to visibility toggles, and
  hidden actions leave the grid while their keyboard shortcuts keep
  working. Most people use a handful of layouts; now the grid can look
  like it.
- Clicking the Dock icon of the app you are using can now cycle through
  its open windows, like the Command backtick shortcut but with the mouse,
  thanks to a community contribution. Off by default, next to the Dock
  click to minimize option; with both turned on, apps with several windows
  cycle and apps with a single window still minimize.
- Middle click can now also fire from a light trackpad tap, without
  pressing: choose three or four fingers next to the middle click option in
  the Mouse settings. Off by default; sliding touches never count, and the
  four-finger choice sidesteps the macOS three-finger drag gesture entirely.
- The menu bar icon now shows when the microphone is muted: a red
  crossed-out mic appears beside it while the mute is on, so a live call
  never catches you guessing. On by default and invisible until you
  actually mute; the switch lives next to the Mute microphone option in
  the Quick Tools settings.
- Cut and paste in Finder now shows progress when files move to a different
  disk: the floating card gains a progress bar with the file name and the
  position in the batch while the copy is still running. Moves inside the
  same disk stay instant and skip the bar.
- The Color Picker can copy HEX values without the leading # sign, for
  design tools that reject it. The option appears under the format choice in
  the Quick Tools settings whenever HEX is selected.
- The image converter can now turn any image into a PDF, following a user
  request: PDF joins JPEG, HEIC and PNG in the format choice, handy when a
  form or service only accepts PDF documents. The quality and maximum size
  controls keep working, so a photo can be shrunk into a small PDF before
  it is submitted. With PDF chosen the start button says Convert to PDF,
  and whenever a result comes out bigger than the original the done card
  says so, since growth is normal for a small photo wrapped in a document.
- The Settings window gained a search field at the top of the sidebar:
  type a few letters and only the matching pages remain, accents and case
  ignored. It also searches by what lives inside each page, so "lid" finds
  Energy and "quick panel" finds Quick tools. With over twenty pages,
  finding the right one no longer depends on remembering which group it
  lives in.
- In app updates now show download progress: the panel banner gets a real
  progress bar with a percentage while the new version downloads, and the
  About page shows the same percentage, so a slow connection no longer
  looks like a stuck update.
- Window layout shortcuts can now be removed one by one, following user
  feedback: most people use a handful of layouts, and every assigned
  shortcut occupies a system-wide key combo other apps then cannot use. A
  new remove button next to each layout clears its shortcut (the button
  shows None), Reset brings the original back, and cleared shortcuts are
  simply never registered.
- Monitor alerts can now fire as often as every 2 minutes, following user
  feedback that 5 minutes was too long to wait for a memory pressure
  warning. And when notifications for Vorssaint are turned off in System
  Settings, the alerts section now says so, instead of leaving enabled
  alerts silently dead.
- A new Keyboard shortcuts page in Settings lists every global shortcut
  currently active in one place, including the window layout combos, so
  nobody has to remember which feature page holds which one. Each shortcut
  keeps being configured where its feature lives.
- The app icon can now step aside while metrics are in the menu bar,
  following user feedback: a new option in the Monitor settings hides the
  icon so only your readings take up space, whether they sit next to the
  icon or as separate items. The icon comes back by itself whenever it is
  needed, when metrics leave the bar and when there is something to show
  you, like a ready update or the muted microphone indicator.
- Menu bar metrics gained a spacing choice, following user feedback that
  the gaps between readings looked too wide. The new Compact look is the
  default: it hugs the numbers, making the whole strip about a quarter
  narrower while still holding enough room that readings can move between
  one and two digits without the bar wobbling. The Standard option in the
  Monitor settings keeps the old behavior of reserving room for each
  metric's largest value.

### Changed
- The app reads much better with VoiceOver: the quick panel tiles, the
  edit badges, the inline option switches and the window layout controls
  now carry proper spoken labels instead of announcing only "button".
- Esc in the quick panel now steps back one layer at a time, closing the
  open options card first, then leaving edit mode, then hiding the panel.
  And a quick panel with every tool hidden now explains how to bring them
  back instead of showing an unrelated hint.
- Panel rows now show their feature's keyboard shortcut in a quiet badge
  when one is active, so the quick panel, Clipboard, Copy text from screen,
  Color picker and Mute microphone remind you of the faster way in. The
  quick panel row also moved to the top of the Utilities section by
  default; a custom order stays as you arranged it.
- The Settings sidebar got clearer groups: a new Files section gathers the
  Clipboard, Cut and paste, Shelf and Media pages, window features stay
  together under Window controls, and Utilities keeps the quick tools. The
  same pages, in places that are easier to guess.
- The introduction now presents the quick panel on its own page, with the
  shortcut and a button to open it right away. It is the fastest way into
  the app's tools and used to be easy to miss.
- The introduction was tightened from sixteen pages to ten: the separate
  tour pages for Cut and paste, Quit on close, the Uninstaller and the
  Temporary area became simple switches on the Optional features page, and
  each feature's own Settings page keeps the full explanation. Installing
  the app should take half a minute, not a slideshow.
- The memory pressure dot option now sits directly under the Memory row in
  the Monitor settings, next to the metric it controls, matching the
  Network row's inline option. Contributed by Games55k.
- App icons in the Volume Mixer are much bigger now, sitting beside each
  app's name and volume slider, so rows are easier to recognize at a glance.
- Selecting several clipboard items now works the Finder way, following
  user feedback: ⌘-click or ⇧-click select rows (an empty checkbox appears
  on hover), and with a selection active the window shows Paste and Copy
  buttons with the count. ⌘C copies the selection without pasting, ready
  for ⌘V wherever you are; Enter and a plain click still paste directly,
  ⌘A selects all visible results and Esc clears the selection first.
  Copied files and images can join a selection too: a files-only selection
  pastes the files themselves, a selection with images pastes as rich text
  with the images embedded (Notes, Mail and TextEdit take everything
  together, plain apps receive the text), and text with file paths combines
  as text.
  Modifier clicks on rows also work reliably now: the window used to treat
  ⌘-click as a window-drag grab, so it never reached the row.

### Removed
- The List navigation mode of the panel is gone: the panel always navigates
  by sections now. Sections were the default and where all the attention
  goes; keeping a second layout of the same panel doubled the ways it
  could break.

### Fixed
- The introduction could get stuck on the menu bar metrics page: the list
  of metrics outgrew the window and pushed the Continue button out of it.
  Every introduction page now scrolls when needed, and the navigation
  buttons always stay visible.
- Per app memory in the Monitor now matches Activity Monitor: it shows the
  same physical footprint figure Activity Monitor uses, instead of a raw
  measure that counts shared memory twice and reads far too high for many
  apps.
- Zoom and music production apps now appear in the Volume Mixer again as
  informational rows saying the app manages its own audio, instead of
  silently missing from the list. They are still never touched by the
  mixer, which is what keeps their calls and sessions working.
- The switcher could miss many apps on busy Macs, including the app in
  front of you and freshly opened ones. The switcher keeps at most 24
  entries, but the cut used to happen in the window server's raw order,
  which puts windows parked on other Spaces before visible ones; now every
  window is collected first, sorted by most recent use, and only then
  trimmed, so the apps you actually use always make the list.
- Routing a music production app through the Volume Mixer could leave it
  producing no sound at all: apps like Logic Pro, Ableton Live, Cubase,
  Studio One, Pro Tools, REAPER and other DAWs drive their own audio device
  and clock, which the mixer's tap cannot do for them. The mixer now leaves
  these apps untouched, the same way it already does for Zoom, so their
  audio always keeps playing; use the DAW's own output settings to route
  them.
- Memory use now stays flat over long sessions, answering reports of the
  app growing to several gigabytes after days of heavy use. Window
  thumbnails for the switcher and Dock Preview are copied into the app's
  own memory instead of holding on to system graphics surfaces, respect a
  memory budget besides the entry count, and are released automatically
  when the Mac runs low on memory; clipboard image previews and the menu
  bar metric renders got hard memory ceilings; and the Volume Mixer lets
  go of its per app audio listeners when apps quit.
- The Show menu bar icon button now places the rebuilt icon beside the
  clock, the last spot macOS hides when the menu bar runs out of room. It
  used to put the icon back at the end near the notch, the first spot to be
  hidden, so on crowded menu bars the button looked like it did nothing. And
  when the icon still cannot appear, the app now explains why (a full menu
  bar, or a menu bar manager like Ice or Bartender keeping it in its hidden
  section) instead of staying silent.
- A drawing bug made icons render at half their intended size across the
  app, in the Volume Mixer, in the Monitor process rows and in shelf tiles.
  Icons now draw at their full size.
- Updating from inside the app could close it without applying the new
  version and without any explanation. Now, when your user account cannot
  write to the Applications folder, the app asks for an administrator
  password instead of failing silently; with Gatekeeper turned off, the
  update no longer fails its safety check by mistake; running from the disk
  image, the app explains it needs to be moved to Applications first; and if
  an update still cannot be applied, the app tells you why after it
  restarts, brings the offer right back, and routes the next attempt
  through the administrator password when the failure looked like a
  permission problem, instead of leaving you on the old version without a
  word.
- Choosing a file from a tool in the quick panel now works. The file dialog
  used to come up unresponsive (folders would not open, files could not be
  selected and only Cancel reacted), and any click inside it could close the
  quick panel in the middle of the selection.
- The quick panel no longer closes on its own while a tool is open inside
  it. Clicking another app to drag a file into Media, answering a system
  prompt from the Uninstaller, or leaving Homebrew working no longer
  dismisses the panel. With just the launcher grid showing, clicking outside
  still closes it, as before.
- Items placed on the shelf (files, images, text and links) were erased
  whenever the app restarted, including on every update. The shelf now
  remembers its items: they are saved as you add and remove them and come
  back after a restart or an update. Images and GIFs pasted straight into
  the shelf are stored safely for this too, and an item whose file no longer
  exists on disk is skipped instead of coming back as a broken tile.
- The menu bar panel no longer flickers repeatedly while the Volume Mixer
  page is open. The panel used to redraw for every audio system event, even
  when nothing visible changed, so on Macs with busy audio activity (wireless
  audio devices renegotiating, apps opening and closing audio connections)
  it flickered constantly while open. The mixer now updates only when
  something on screen actually changes, and bursts of audio events are
  folded into a single update.
- Two apps with the same name in the Volume Mixer, or two audio devices with
  the same name in the output and microphone lists, could swap places with
  each other whenever the list refreshed. Rows now keep a stable order.

## [3.1.7] - 2026-07-04

### Summary
Vorssaint 3.1.7 adds the quick panel, a floating hub that opens anywhere with
one shortcut and holds your favorite tools, lets a click on the Dock icon
minimize an app's windows, adds a real middle click for the trackpad, saves
copied images and files in Clipboard History, and adds four new tools: copy
text from screen, color picker, mute microphone and paste as plain text. It
also adds Russian and Traditional Chinese (Hong Kong and Taiwan), completes
the window layout shortcuts, organizes the panel Controls into categories,
improves Debounce, keeps Monitor lighter on battery, steadies the RAM menu
bar metric, makes Quit on close safer when switching Desktop spaces, makes
mouse scroll inversion more reliable and improves Dock Preview, menu bar icon
recovery and App Switcher previews.

### Added
- The quick panel: press the shortcut (^⌘V) anywhere and a small floating
  panel appears with your favorite tools, one click or key away: Keep Awake,
  mute microphone, copy text from screen, color picker, Clipboard, window
  layout, Cleaning Mode, Homebrew, Media, Clean URL and the Uninstaller.
  Every tool opens and runs inside the panel itself. Fully customizable in
  place: hide, bring back and drag tools around, with arrow-key navigation
  and 1 to 9 opening items directly.
- Clicking the Dock icon of the app you are using can now minimize its
  windows, like traditional taskbars. Off by default, next to Dock Preview in
  Settings.
- Middle click on the trackpad: pressing with three fingers now works like a
  mouse wheel click. Only a real press counts, so taps, swipes and resting
  fingers never trigger it, and accidental double clicks from tap-to-click
  are filtered out. While the macOS three-finger drag gesture is enabled it
  owns three-finger touches, so the middle click waits and Settings explains
  how to free the gesture. Off by default, in the Mouse tab in Settings.
- Clipboard history now saves copied images and files alongside text. Images
  show a thumbnail and paste back as images; files are remembered as links to
  their location and paste back as the files themselves. Both can be pinned,
  searched and reordered like any text item, and a new toggle in the Clipboard
  settings turns this off.
- Copy text from screen: select any area and the text in it is recognized
  offline and copied, ready to paste. In the panel and in the new Quick tools
  page in Settings, with an optional global shortcut.
- Color picker: grab the color of any pixel with the system loupe and copy it
  as HEX, RGB, HSL or SwiftUI code. In the panel and in Quick tools.
- Mute microphone: one click or a global shortcut cuts the Mac's input in
  every app, and the muted state survives switching input devices.
- Paste as plain text: an optional shortcut pastes what you copied without
  colors, fonts or formatting, and the original formatting stays on the
  clipboard for later pastes. In the Clipboard settings.
- Window layout shortcuts now cover every action. Next Display, thirds and
  two-thirds join the existing halves, quarters, maximize, center and restore,
  and each action row in Settings has its own shortcut recorder.
- Russian is now available throughout the app, thanks to Artur.
- Traditional Chinese (Hong Kong and Taiwan) is now available throughout the
  app, thanks to Jensen.

### Changed
- Vorssaint now updates on a weekly rhythm so every feature arrives better
  tested and more polished; critical fixes still ship right away. The short
  note shown after updating explains it and links to where previews of
  upcoming features are posted.
- The menu panel is cleaner and keeps layout options in Settings.
- The Controls section in the panel is now organized into collapsible
  categories with an at-a-glance count of what is on, so it stays short as
  features grow. Dock click to minimize and the trackpad middle click are now
  right there too, next to everything else.

### Fixed
- Debounce is more responsive while filtering duplicate key presses.
- Monitor uses much less energy while showing live menu bar metrics.
- The RAM metric in the menu bar no longer blinks during brief monitor refresh gaps.
- Quit on close no longer treats Desktop space switching as closing an app window.
- Mouse scroll inversion now works with more external mouse wheels, and no
  longer cancels itself out on mice that report smooth, pixel-precise
  scrolling. Toggling it now visibly changes direction for those mice too.
- Monitor now wakes only when the next reading is due while the panel is
  closed and only slow metrics are shown, instead of waking every refresh
  just to skip the work.
- The menu bar icon recovery can bring the icon back after macOS keeps it hidden.
- App Switcher window thumbnails no longer look skewed while Stage Manager is
  on. Windows parked in the Stage Manager strip get an upright preview right
  away and a sharper one as soon as they become active.
- Longer descriptions in the panel and in Settings are no longer cut off
  mid-sentence, in every language.

## [3.1.6] - 2026-06-30

### Summary
Vorssaint 3.1.6 adds Turkish, makes Clipboard History quicker to use from the quick window, lets Mixer choose how low speaker volume goes after headphones disconnect, adds faster App Switcher back navigation, adds a Network menu bar order option, steadies the Network menu bar metric, cleans up the in app update preview and corrects the menu bar monitor layout so pinned metrics sit centered beside the app icon.

### Added
- Turkish is now available throughout the app, thanks to Abdurrahman.

### Changed
- Clipboard History quick window rows can now be clicked to paste that item into
  the previous app, with Command click copying only.
- Mixer can now choose the volume used after wired or Bluetooth headphones
  disconnect.
- App Switcher can now move backward with Shift while the switcher is open.
- Monitor can now place upload above download in the Network menu bar metric.

### Fixed
- The update preview no longer shows install instructions meant for the download
  page.
- Network speed in the menu bar no longer changes the item width as live traffic
  updates.
- Menu bar monitor metrics now sit centered beside the app icon.

## [3.1.5] - 2026-06-29

### Summary
Vorssaint 3.1.5 adds multi-item paste to Clipboard History, makes Quit on close exceptions easier to set up from installed apps, adds per-app network activity and optional peripheral battery status to Monitor, adds keyboard debounce for duplicate key presses, improves Mixer compatibility with Zoom calls, improves localized feature labels, and improves App Switcher order and shortcuts.

### Added
- Clipboard History can now mark multiple items in the quick window and paste or
  copy them together as one stack.
- Monitor can now show recent per-app network traffic, with download and upload
  activity in the Network panel and the Network detail view.
- Monitor can now show connected keyboard, mouse, trackpad and Bluetooth audio
  device battery in the menu bar and System panel when enabled, with updates
  within a few seconds as devices connect or disconnect.
- Debounce can now filter very fast duplicate keyboard presses, with a 10 ms
  global window adjustable from the panel and optional per-key windows in
  milliseconds.
- The large-icon App Switcher now has a separate configurable shortcut for
  moving between windows of the selected app.

### Changed
- Quit on close exceptions can now be added from installed apps instead of only
  apps that are currently running.

### Fixed
- Clipboard History now preserves the full scheme when a copied web address is
  also provided as a structured URL by the source app.
- Zoom is kept on the normal system audio path so joining calls no longer hangs
  when Mixer boost settings are active.
- The Disk selector in Monitor no longer stops vertical panel scrolling when
  the pointer is over it.
- The large-icon App Switcher now keeps the selected app's window previews
  aligned with the selected icon.
- The App Switcher now reliably returns to the previous app when used twice in
  a row.
- Apps that were running but missing from the old running-app picker, such as
  Signal, can now be added to Quit on close exceptions.
- Feature names, Clipboard controls, Window Layout labels and Monitor alert
  labels now stay localized across all supported app languages instead of
  falling back to English.

## [3.1.4] - 2026-06-27

### Summary
Vorssaint 3.1.4 makes Homebrew in Settings more stable and easier to browse, adds package updates from Homebrew, adds a large-icon ⌘Tab view with visible shortcuts, adds finer Window Layout placement options, improves App Switcher and Dock Preview navigation, expands Monitor menu bar metrics and makes Clipboard History faster to use from the keyboard.

### Added
- Window Layout can now place the active window into left, center and right
  thirds, left or right two-thirds layouts, and the next display.
- Dock Preview can now pin the current preview panel, show position when an app
  has multiple windows, and reliably minimize or restore windows directly from
  each preview card or its context menu. Multi-window previews can also move to
  the previous or next window from the preview header, and pinned previews can
  be dragged to a better position on screen. Multiple pinned previews can stay
  on screen at once while you keep using other apps. The selected preview stays
  visible while navigating long rows of windows, and pinned previews stay open
  until you close or unpin them from the header.
- App Switcher can now show a large icon row with one entry per app, with the
  selected app's window previews above it so a specific window can still be
  chosen directly.
- Monitor can now show disk usage and live disk activity in the menu bar, if
  enabled.

### Changed
- Homebrew now shows package counts in filters and sections, making long
  installed lists easier to scan.
- Homebrew now marks installed packages that have updates available, shows a
  compact update count, can refresh Homebrew itself and can update one package
  directly from the list, the context menu, the detail view or all available
  updates at once. Operation logs and fallback commands can also be copied.
- Clipboard History's quick window now targets the previous item first when no
  items are pinned, supports arrow-key selection, copy-without-paste, keyboard
  pin/delete actions, full-text tooltips and multi-word search.
- App Switcher now filters windows as you type while switching, and App Switcher
  plus Dock Preview show the app name under titles when it helps distinguish
  similar windows.
- The large-icon App Switcher now shows the current app-switching shortcut and
  the shortcut for moving between windows of the selected app.
- What's New and the update preview now show the short summary at the top of the
  release notes.
- Monitor's per-app CPU, GPU, memory and energy lists can now bring a listed app
  forward directly.

### Fixed
- Homebrew in Settings no longer destabilizes the Settings navigation when it
  loads many installed packages.

## [3.1.3] - 2026-06-25

### Summary
Vorssaint 3.1.3 makes Cleaning Mode, Keep Awake, Monitor, Clipboard History and the Window Switcher more reliable, improves readability in the panel and adds optional pointer movement for Keep Awake sessions.

### Added
- Keep Awake can now move the pointer slightly at a chosen interval during
  active sessions, if enabled.

### Fixed
- Cleaning Mode now blocks brightness, media, volume and lock keys while the
  keyboard is locked.
- Keep Awake option text no longer gets cut off in the panel or Energy settings.
- Keep Awake closed-lid mode now handles failed password-free setup more clearly
  and can fall back to the macOS password prompt when needed.
- Battery health now follows the same maximum capacity value shown by macOS when
  that value is available.
- Monitor text in the panel now has better contrast, with steadier alignment for
  power and battery rows.
- Monitor Alerts controls now live in Settings instead of appearing both in
  Settings and the main panel.
- Clipboard History's shortcut toggle can now be turned off even when Clipboard
  History itself is currently disabled.
- The Network menu bar metric is now better centered and easier to read.
- The Window Switcher now focuses only the selected browser profile window,
  including when that selected window is minimized afterward.

## [3.1.2] - 2026-06-24

### Summary
Vorssaint 3.1.2 improves GIF handling in Media and Shelf, adds more Keep Awake control in the panel, lets Monitor metrics use separate menu bar items with focused detail views and expands the Volume Mixer with speaker protection and shortcut-based output switching.

### Added
- Keep Awake can now choose the active menu bar icon color directly from the
  panel, including an option to keep the normal adaptive icon with no active
  color.
- Keep Awake can now start automatically when Vorssaint opens, if enabled from
  the panel or Energy settings.
- Monitor metrics can now use separate menu bar items, so each active metric can
  be positioned independently on crowded or notched menu bars. Clicking a metric
  opens a focused detail view for CPU, GPU, RAM, network, battery or power.
- Volume Mixer can now lower speaker volume automatically when wired or
  Bluetooth headphones disconnect, if enabled.
- Volume Mixer can now cycle through selected system outputs with a global
  shortcut, if enabled.

### Changed
- Monitor and Shelf now use lighter thumbnails and temporary caches, reducing
  memory use while browsing metrics and dragging items.

### Fixed
- GIFs created by Media now stay visible in Finder, including outputs from
  source files whose names start with a dot.
- Panel sections and folded controls now open instantly without extra transition
  animations.
- Folded panel setup sections now open when clicking either the arrow or the
  section title.
- The System panel now shows the separate menu bar items control only when at
  least one menu bar metric is active.
- Shelf now preserves animated GIF data when macOS provides a GIF file or GIF
  data, instead of flattening it into a still image.

## [3.1.1] - 2026-06-23

### Summary
Vorssaint 3.1.1 makes Homebrew package loading more reliable, keeps Clipboard History from disrupting the app you are pasting into and adds direct window closing in App Switcher.

### Added
- App Switcher cards now show a close button on hover, so you can close a
  specific window without leaving the switcher.

### Fixed
- Clipboard History no longer activates Vorssaint when opening the quick history
  window, so paste actions keep their target in apps like Excel.
- Closing a window from Dock Preview or App Switcher now triggers Quit on Close
  when that was the app's last window.
- Homebrew now keeps loading installed packages when Homebrew prints warnings
  before or after its package list.

## [3.1.0] - 2026-06-23

### Summary
Vorssaint 3.1.0 adds three optional tools: Clipboard History for saving and reusing copied text locally, Window Layout for arranging the active window with shortcuts, and Monitor Alerts for notifying you when selected system limits need attention. It also makes Settings easier to browse and improves menu bar metric readability on light and dark wallpapers.

### Added
- Clipboard History, with local text history, pinned items, search, manual order,
  clear controls, sensitive-text skip and quick paste shortcuts.
- Window Layout, with actions for halves, corners, center, maximize, restore and
  optional global shortcuts.
- Monitor Alerts, with optional notifications for high CPU, CPU temperature,
  memory pressure, disk space and battery, configurable from Settings and the
  System panel.

### Changed
- Settings are now grouped into clearer categories.
- Homebrew and Dock Preview no longer show beta labels in the app.
- Clipboard and Window Layout are available in the Utilities panel and can be
  hidden or reordered.
- Menu bar metric text now adapts better to light and dark wallpapers.
- What's New no longer opens again after installing an update, because the
  update flow already shows the changelog before download.

## [3.0.10] - 2026-06-21

### Summary
- This update adds disk monitoring to the System Monitor, with per-disk storage,
  activity, SMART details when available and safe eject controls for external
  drives.
- App Switcher is steadier with multiple windows and fullscreen apps, including
  games.
- App Switcher now has a Finder visibility option for users who prefer not to
  show Finder when it has no open windows.

### Added
- System Monitor now has a Disks section with storage usage, live read/write
  activity, session totals, SMART details when macOS exposes them, per-disk
  selection and Finder-style decimal storage values.
- Disks can now be selected individually, with per-disk details, an Eject action,
  an Eject all action for external drives and safety guards that block eject
  actions for the internal system disk.
- App Switcher can now hide Finder when it has no open windows, while keeping
  Finder windows visible when they exist.

### Fixed
- App Switcher now returns to the exact window you last used in apps with
  multiple windows, instead of letting the app choose a different window.
- App Switcher now switches more reliably when entering or leaving fullscreen
  apps and games.

## [3.0.9] - 2026-06-20

### Summary
- This update focuses on making Vorssaint feel lighter, steadier and more
  reliable during everyday use.
- Menu bar readings for CPU, GPU, RAM and temperatures stay visible through
  brief refresh gaps, while the monitor does less background work when the panel
  is closed or only a few metrics are visible.
- The Volume Mixer is easier to control with one output selection for the system
  and apps, while per-app volume, mute and boost settings stay intact.
- Media tools are more responsive with larger videos and more reliable when
  reading video details or creating GIFs.

### Changed
- The Volume Mixer can now send the whole system and apps to one audio output at
  once.
- The system monitor and menu bar now do less background work, especially when
  the panel is closed or only a few metrics are visible.
- Live monitor updates are smoother and avoid unnecessary redraws while values
  are refreshing.
- Media tools are more responsive with large videos and handle video details and
  GIF creation more reliably.

### Fixed
- GPU temperature, RAM and CPU readings in the menu bar now stay visible through
  quick moments when a value is unavailable instead of disappearing and coming
  back.
- The Network panel now starts measuring correctly when opened directly on
  Network.
- GPU usage in the menu bar now avoids brief spikes when opening the panel,
  while still showing real sustained activity.

## [3.0.8] - 2026-06-20

### Added
- CPU, GPU and battery temperatures can now be pinned to the menu bar as
  metrics, using the selected Celsius or Fahrenheit setting.
- Menu bar temperatures now combine with matching usage or battery charge by
  default, with a setting to split them into separate CPU°C, GPU°C and BAT°C
  blocks.

![Menu bar temperature metrics](https://raw.githubusercontent.com/vorssaint/vorssaint-utils/main/Resources/Images/menu-bar-temperature-metrics.png)

## [3.0.7] - 2026-06-20

### Added
- Utilities now includes Media for local video compression, GIF creation, image
  compression and text extraction from images, with drag and drop, simple
  controls and local-only processing.
- Dock Preview cards now include a red close button on the left for closing the
  real window directly from its preview, and the panel stays correctly sized as
  windows are closed.
- Pending Finder cut operations now include a close button to cancel the cut and
  dismiss the floating HUD.

### Changed
- Menu bar metrics now use a cleaner compact layout with clearer CPU, GPU, RAM,
  battery, power and network readings, custom ordering, persisted choices and
  steadier widths.
- The menu panel uses a subtler glass surface so text and controls stay readable
  across different backgrounds.

## [3.0.6] - 2026-06-20

### Added
- Global shortcuts for Keep Awake, Shelf and App Switcher can now be changed or
  turned off.

### Fixed
- Closed Vorssaint Settings windows no longer linger in App Switcher.
- Minimized windows now stay open and remain available in App Switcher and Dock
  Preview.

## [3.0.5] - 2026-06-19

### Added
- When installing an update, a preview of the new version's changelog is shown
  first, so you can decide whether the update is worth it before downloading.
- After updating, a What's New window summarizes everything since your previous
  version. You can turn it off in Settings > What's New, or with "Don't show
  again".
- The app switcher and Dock previews now have a size option (Normal, Large or
  Extra large) so windows stay easy to identify on large displays.

### Fixed
- Closed-lid mode now reliably brings up the administrator password prompt when
  it is being set up on a Mac that has not granted permission yet, and no longer
  becomes unstable when the request is retried.
- "Clear all permissions" could freeze the Mac's input; it now stops the app's
  event taps before resetting permissions, and feature event taps no longer
  block when Accessibility is revoked.
- Cut & paste for files in Finder (⌘X) shows its on-screen confirmation again:
  Finder Automation is now requested in-process and re-requested if it was lost
  after an update, instead of failing silently.
- When closed-lid mode cannot be turned on, the message now clearly says to
  switch it off and on again to try, instead of a confusing note that pointed at
  your password even when no password was involved.

## [3.0.4] - 2026-06-18

### Added
- Utilities now includes a Homebrew manager for searching, installing and
  uninstalling formulae and casks from the menu panel, with popularity-sorted
  search results and a guided setup flow when Homebrew is not installed.
- The Volume Mixer can now route each app to the system default output or a
  specific speaker, display or audio device.
- The Volume Mixer now includes a global microphone picker that remembers a
  preferred input and restores it when the device reconnects.
- Dock Preview can now show window previews when hovering over open apps in the
  Dock, with a temporary peek before selecting a window.
- This update includes a one-time Dock Preview intro with a short demo and beta
  note.

### Changed
- Panel edit mode now has a clearer OK button, reset control and drag handles
  for reordering items.
- Utilities now defaults to Homebrew first, followed by Uninstaller, Clean URL
  and Cleaning Mode.

### Fixed
- App Switcher now keeps fullscreen windows available when they are on another
  Space.
- App Switcher thumbnails now try a secondary ScreenCaptureKit match for native
  fullscreen windows on another Space.
- Green-button maximization now avoids falling through to native fullscreen when
  the custom resize path cannot run.
- Quit on close now ignores stale AX windows after a real close-button request
  when WindowServer confirms there is no visible app window left.
- Quit on close now follows explicit close-button clicks in apps that do not
  always emit standard window-close callbacks.
- Settings now opens beside the menu panel instead of starting underneath it.

## [3.0.3] - 2026-06-18

### Changed
- The Shelf is easier to grab and move from the header and empty space, while
  still accepting dropped items in the empty area.
- Shelf close and clear controls now have larger hit areas, clearer spacing and
  a danger hover state for clearing items.
- The menu panel footer now uses full button hit areas and handles longer
  translations without overlapping.
- Settings now uses a shorter What's New sidebar label, and update controls live
  in About with the other app details.

### Fixed
- The custom green-button maximize option now animates window resizing instead
  of jumping instantly.
- Window-control click monitoring now avoids slow accessibility checks unless a
  click is actually on a window control, reducing stalls in other apps.

## [3.0.2] - 2026-06-18

### Fixed
- Opening Clean URL or Uninstaller from the menu panel is now more stable on
  macOS 15.

## [3.0.1] - 2026-06-18

### Fixed
- Quit on close now handles apps that keep delayed window records after the last
  standard window is closed, including Spotify and Discord.
- The app switcher no longer shows recently closed Ghostty terminal windows.
- Finder can now be selected from the app switcher even when no Finder window is
  open.
- Finder stays locked in Quit on close exceptions and cannot be quit from the app
  switcher.

## [3.0.0] - 2026-06-18

### Added
- Clean URL is now available in Utilities and Settings, with optional automatic
  cleaning for copied links.
- Panel sections can now be customized inline from the panel: the edit control
  keeps the real panel visible, shows hidden items as muted rows and lets them
  be restored from the same place.
- Utilities now includes an optional green-button window maximizer that keeps
  windows in the current Space and restores the previous size on the next click.
- The menu panel now has a Controls section next to Utilities for quickly
  turning feature-style options on or off.

### Changed
- Menu bar metrics now use a more compact layout with short labels, tighter
  values, a steadier reserved width and an automatic two-line stack when several
  metrics are enabled.
- Menu bar metric labels can now be switched between compact and classic styles
  from Monitor settings.
- Updates no longer open a What's New window for existing users. Release notes
  are available in Settings.
- The Buy Me a Coffee shortcut was removed from the menu panel and first-run
  introduction. It remains in Settings > Support.
- Monitor graphs now include a zero baseline so current levels are easier to
  read.

### Fixed
- The Uninstaller app chooser now stays inside Vorssaint instead of opening the
  system file picker, avoiding unexpected language changes.

## [2.17.3] - 2026-06-17

### Website
- Official site: [vorssaint.com](https://vorssaint.com).

### Added
- Every update now opens a What's New window with the latest release notes and a
  discreet vorssaint.com link.
- The Uninstaller is now available directly in the menu panel's Utilities
  section, with drag-and-drop and Choose app support.
- The menu panel header now includes a Buy Me a Coffee shortcut.

### Changed
- Settings and What's New windows can now be focused from the window switcher.
- The menu bar icon no longer bounces when opening the panel.
- The README now uses focused screenshots and GIFs for each feature.

### Fixed
- Quit on close now detects the last-window close more reliably for apps like
  Safari and WhatsApp.
- The post-update What's New window now opens centered on screen.

## [2.17.2] - 2026-06-17

### Fixed
- Shelf and Cut & Paste HUDs no longer use the native rectangular panel shadow,
  avoiding extra outlines on some macOS display/window configurations.

## [2.17.1] - 2026-06-17

### Fixed
- The release build now uses the macOS 26 runner so the Volume Mixer slider uses
  the same Liquid Glass effect as the Developer build on macOS 26 and later.

## [2.17.0] - 2026-06-17

### Added
- The Battery section now shows apps with significant current energy use.
- The Volume Mixer uses a compact Liquid Glass slider on macOS 26 and later,
  while older macOS versions keep the standard slider.

### Changed
- The Keep Awake status under the app name is now a clearer state indicator.
- Panel metric colors now adapt between Light Mode and Dark Mode for better
  contrast.

### Fixed
- Update notices in section navigation mode now count toward the panel height
  instead of cutting off the content.
- The Settings window now opens in a normal centered position after relaunch,
  instead of appearing under the menu panel.
- Volume Mixer sliders now track system accent color changes more reliably.
- The menu panel no longer opens with its header clipped during first-launch
  layout timing.

## [2.16.1] - 2026-06-16

### Fixed
- Memory usage now matches Activity Monitor's Memory Used total more closely.
- Network readings now ignore another local virtual interface so totals stay focused on real network traffic.

## [2.16.0] - 2026-06-16

### Added
- The menu panel now has an optional section navigation mode, with section icons
  placed below the app header and a centered List/Sections switch in the footer.
- The section navigation mode is introduced during the update flow and is enabled
  by default so existing users can try it right away.
- Shelf drops can now be kept as batches, and loose items can be added into an
  existing stack by dropping them onto it.
- Battery can now be shown as an optional menu bar metric.
- A Fan Control beta entry can be enabled in Monitor settings. Manual control
  remains disabled until Mac models are validated.

### Changed
- Cleaning Mode now lives in a dedicated Utilities section inside the panel.
- The menu panel now fades and slides when opening or closing.
- The section navigation panel now grows only as much as the active section needs,
  instead of reserving a large empty area for shorter sections.

### Fixed
- The Shelf stays visible while it contains files, instead of auto-hiding while
  the user is still collecting items.
- The app switcher now handles apps on other Spaces more reliably when focusing a
  selected window.

## [2.15.2] - 2026-06-16

### Fixed
- The menu panel now resizes smoothly as sections collapse and expand, without
  stale empty space or unnecessary scrolling.
- The Settings window now stays open when clicking outside it, and only closes
  when the user closes it intentionally.
- Clicking the Settings window now hides the menu panel only when the panel is
  overlapping it, while still allowing Settings and the panel to stay open side
  by side for live layout changes.
- App updates no longer open the language chooser or Buy Me a Coffee support
  prompt automatically.

## [2.15.1] - 2026-06-16

### Fixed
- The menu panel opens fully expanded again after updating, instead of restoring
  an old collapsed layout that made it look unexpectedly tiny.

## [2.15.0] - 2026-06-16

### Added
- **Shelf now gets out of the way.** After it appears, it fades away on its own
  after a few seconds if you are not interacting with it.
- **Shelf feels more balanced.** The panel is more square, with a comfortable
  three-column grid instead of a tight horizontal strip.

### Changed
- The menu bar icon now stays full strength while idle, turns amber while Keep
  Awake is active, and still turns blue when an update is available.

### Fixed
- Shaking a file dragged from a Dock stack now opens the Shelf, matching the
  behavior of files dragged from Finder.

## [2.14.0] - 2026-06-15

### Added
- **Now in eight languages.** The interface is available in English, Português,
  Español, Deutsch, Français, Italiano, 日本語 and 简体中文. Choose yours in
  Settings › General; a one-time chooser also appears after updating.

### Fixed
- The Battery label in the system monitor no longer wraps onto a second line.
- The menu bar panel now stays centered with even margins instead of leaving a gap
  on the right when macOS is set to always show scroll bars.

## [2.13.1] - 2026-06-15

### Fixed
- The System monitor step in the welcome tour now scrolls, so its content is never
  clipped at the bottom on shorter windows.

## [2.13.0] - 2026-06-15

### Added
- **Make the panel yours.** Collapse any section you don't use with a tap on its
  header, and drag to reorder the sections from Settings › Monitor. The panel shows
  what matters to you first, with less scrolling.

### Changed
- Cleaning Mode moved into the panel's footer, alongside Settings and Quit.

### Fixed
- **Keyboard shortcuts work in the Settings window.** Cmd+W, Cmd+M, Cmd+H and Cmd+Q,
  plus cut, copy, paste and select all in text fields, now respond as expected.
- Removed an occasional extra outline around the Shelf, and evened out the panel's
  spacing so it no longer sits closer to one edge.

## [2.12.0] - 2026-06-15

### Added
- **Support the project.** A new Support tab in Settings, and a brief one-time note
  when you update, let you back Vorssaint with a coffee if you'd like. It stays
  free, with no subscription, always.

### Fixed
- **Battery health matches macOS.** The health percentage now lines up with the
  "Maximum Capacity" shown in System Information.
- **The menu bar icon is recoverable.** macOS can hide menu bar icons when the bar
  runs out of room, common on Macs with a notch. Now reopening Vorssaint from
  Applications brings the icon back, a new "Show menu bar icon" button in Settings
  rebuilds it, and the icon remembers its position.
- Fixed the Support tab hiding the rest of the Settings sidebar.

## [2.11.0] - 2026-06-15

### Added
- **Cleaning Mode.** Locks the keyboard so you can wipe it down without typing
  anything by accident. Unlock by pressing the same key five times in a row, by
  clicking Unlock on the overlay, or just by waiting, since it releases on its own
  after a minute. Start it from the panel or the icon's menu.

### Fixed
- **Battery health now matches macOS.** The health percentage lines up with the
  "Maximum Capacity" shown in System Information.
- **Removing the menu bar icon no longer locks you out.** The icon can't be dragged
  off the bar by accident, it always comes back on launch, and reopening the app
  from Finder or Spotlight restores it and opens the panel.
- The icon's right-click menu now opens reliably even when the panel is already open.

## [2.10.0] - 2026-06-15

### Added
- **System monitor, expanded.** The panel now shows live network speed (download
  and upload) with session totals; power draw, broken into what the Mac consumes,
  what it pulls from the adapter, and the battery's flow, health, charge and cycle
  count; and history graphs for CPU, GPU, memory, network, power and battery. A
  system uptime line is included too.
- **Metrics in the menu bar.** Pin any of CPU, GPU, RAM, Network or Power next to
  the icon, updated live. Memory can show as a colored pressure dot, a percentage,
  or both. Everything is opt-in, and the text keeps a fixed width so the icon
  never shifts as the numbers change.
- **Internet speed test.** Measure download, upload and latency on demand from the
  Network block.
- **Pick exactly what you see.** Choose which blocks appear in the panel and which
  items appear inside each block, both in Settings and during setup. New options
  default to on, so nothing changes until you tune it.
- **Update notifications.** When a new version is available the menu bar icon turns
  blue and a banner offers it at the top of the panel. Automatic checks are more
  frequent and also run when you reopen the app, so updates surface on their own.

### Fixed
- Fixed two mach port leaks in the CPU and memory sampling that could slowly
  accumulate while the panel was open.

## [2.9.1] - 2026-06-14

### Changed
- The switcher's grouping option now shows **one entry per app**, collapsing all
  of an app's windows into a single entry instead of one per window. Turn it on
  for an app-level switcher rather than a window-level one.

## [2.9.0] - 2026-06-14

### Added
- **Switcher option to merge an app's tabs.** A new setting makes the window
  switcher treat the tabs of one window as a single entry, so apps like Finder
  and Terminal with many tabs no longer flood the switcher. It is off by default;
  when on, only the active tab of each tabbed window is shown.

## [2.8.1] - 2026-06-14

### Fixed
- The mixer slider no longer stays amber after a boosted app returns to 100% or
  below. It goes back to the normal color as soon as the volume is no longer
  above 100%.

## [2.8.0] - 2026-06-14

### Added
- **Volume boost in the mixer.** Each app's volume now goes up to 200%, for when a
  video or call plays too quietly. Above 100% the slider and the percentage turn
  amber so a boost is never mistaken for normal volume, and a one-tap reset button
  returns that app to 100%. At 100% the audio stays bit-perfect passthrough.

## [2.7.3] - 2026-06-14

### Fixed
- The ⌃⌥⌘K shortcut toggles "Keep awake" reliably again. When the temporary shelf
  was also enabled, its global shortcut could swallow the ⌃⌥⌘K key press, so
  nothing happened; the two shortcuts no longer interfere.

## [2.7.2] - 2026-06-14

### Fixed
- On the "Quit on last window close" onboarding illustration, the red close
  button now sits aligned with the other window buttons, instead of off in the
  corner of the window.

## [2.7.1] - 2026-06-14

### Changed
- **The brand badge now sits on a solid black background** instead of the
  previous purple-tinted one, for a cleaner, more neutral look. It affects the
  menu bar panel header, the About tab and the onboarding screens.

## [2.7.0] - 2026-06-14

### Fixed
- **Quit on last window close** no longer quits an app when you leave full screen
  with the green button. Exiting full screen briefly leaves the app without a
  window for a moment, which was being read as the last window closing; it now
  confirms the app is really window-less, after the transition settles, before
  quitting it.

### Added
- **Advanced settings page** with two clean-up tools, each behind a confirmation:
  - **Clear all permissions** resets every permission you granted Vorssaint
    (Accessibility, Screen Recording, Full Disk Access and the rest) and removes
    its login item and closed-lid rule, leaving the app in place. Good for a fresh
    start or before uninstalling.
  - **Uninstall Vorssaint completely** does all of that, removes the preferences,
    moves the app to the Trash and quits, leaving nothing behind. You can
    reinstall anytime.

## [2.6.0] - 2026-06-14

### Changed
- **Vorssaint is now signed with an Apple Developer ID and notarized.** The
  first-launch security warning is gone: downloads open normally, with nothing to
  click around. Releases are notarized and stapled automatically.

### Migration
- **You will grant permissions once on this update.** Notarization requires a
  different signing certificate, which changes the app's code identity, so macOS
  asks you to re-allow Accessibility, Screen Recording and the like a single
  time. After this update the identity is stable again (now an Apple-issued one),
  so future updates keep your permissions as before. Your settings and data are
  untouched.

## [2.5.4] - 2026-06-13

### Changed
- **Less idle background work.** The Full Disk Access check no longer runs on the
  recurring permission poll. That access cannot change while the app is running
  (only across a relaunch), so it is now checked at launch and when the app is
  reactivated instead. This removes a steady stream of denied file accesses for
  anyone who has not granted it, with no change in behavior

## [2.5.3] - 2026-06-13

### Fixed
- **The uninstaller no longer keeps asking for Full Disk Access after you grant
  it.** The app detected access by reading the TCC database, but that file does
  not exist on every macOS version, so the check always failed and the banner
  stayed even with access granted and the app reopened. It now also confirms
  access by listing a protected folder that exists (Safari, Mail, Messages and
  the like), which is reliable across versions. No need to re-grant: the banner
  clears on its own once you are on this version

## [2.5.2] - 2026-06-13

### Fixed
- **Granting Full Disk Access from the uninstaller is reliable now.** The app
  registered itself with the system and opened the settings pane in the same
  instant, so it was often missing from the list. It now reads the always-present
  TCC database (the dependable trigger) and waits for the system to record the
  request before opening the pane. The hint also explains the sure path: if the
  app is not listed, add it with the list's "+" button from Applications

## [2.5.1] - 2026-06-13

### Fixed
- **A 2.5.0 install updated from an older version could move itself to the
  Trash on first launch.** The startup cleanup compared bundle locations too
  strictly and mistook the just-updated app (still at the old path, because the
  previous updater installs in place) for a leftover copy. It now renames that
  bundle to `Vorssaint.app` through a helper that runs only after the app quits,
  always reopening the app, and the leftover cleanup only runs for a bundle that
  is provably not the one running. Recover a trashed copy by reinstalling from
  the DMG: the bundle id is unchanged, so permissions and settings return intact

## [2.5.0] - 2026-06-13

### Changed
- **The app is now "Vorssaint" everywhere the system shows it.** The app file is
  renamed to `Vorssaint.app` and its executable to `Vorssaint`, so Spotlight, the
  Applications list, Login Items, notifications, the permission panes and system
  dialogs all read "Vorssaint", with no trace of the old name
- Internal names follow suit (the audio mixer device, the closed-lid rule file,
  the diagnostics binary) and the source tree moved to `Sources/Vorssaint`

### Migration
- **Updating keeps your permissions, settings and data, with nothing to do.** The
  bundle identifier is unchanged, so every granted permission (Accessibility,
  Screen Recording, Full Disk Access, Automation), your preferences and the login
  item carry over untouched. The update installs `Vorssaint.app` and removes the
  old `Vorssaint Utils.app`; if a copy is ever left behind (for example after a
  manual install), the app moves it to the Trash on its next launch. The
  closed-lid rule file is renamed the next time that toggle is used

## [2.4.7] - 2026-06-13

### Changed
- **The switcher is window-based.** ⌘Tab now moves between windows, including
  multiple windows of the same app, and a quick flick returns to the last window
  you used. The browser-tabs entries were removed

### Fixed
- **Full Disk Access banner** no longer lingers after you grant it: the app
  re-checks when it regains focus and offers a Relaunch button (the access only
  applies to a freshly launched app)
- **Onboarding**: shortcut keys no longer overlap their description text

## [2.4.6] - 2026-06-12

### Changed
- The app is now called simply **Vorssaint** everywhere you see it (menu bar,
  About, onboarding, notifications). The bundle id, signing identity and app
  filename are unchanged, so this update keeps your granted permissions
- README rewritten around what each feature gets you, with the free, local,
  no-account stance up front

## [2.4.5] - 2026-06-12

### Fixed
- **Uninstaller**: apps the system protects (root-owned, installer-based) are
  now removed through Finder, which asks for the administrator password and
  moves them to the Trash like a drag would. The scan also hardens against
  hostile bundle ids and never lists anything outside ~/Library, /Library or
  the picked app

### Changed
- The uninstaller lives directly inside Settings: drop an app on the page, no
  separate window, no enable toggle
- The display now always stays on while a keep-awake session is active; the
  separate toggle is gone
- Cleaner wording across the app and the documentation

## [2.4.4] - 2026-06-12

Stability pass over the whole project: same behavior, fewer ways to fail.

### Fixed
- **Self-update is fail-safe**: the new version is fully copied next to the app
  before the old one is removed, so a failed download/copy can never leave you
  without an app
- **Uninstaller**: scan results landing after you picked a different app are
  discarded (files of app A can no longer be listed under app B); display names
  only strip a trailing ".app"
- **Cut & paste**: an unexpected Accessibility value can no longer crash the
  app from inside the keyboard tap, and a cut superseded by a copy elsewhere
  now dismisses its HUD instead of lingering
- **Shelf**: an image dragged from a web page is kept as an image, not as a
  link to the page

### Changed
- Periodic timers gained tolerances so macOS can coalesce wakeups (less power)
- Internal dedup: one screen-under-mouse helper and one HUD backdrop shared by
  all floating panels; CI workflows moved to the actions' Node 24 lines

## [2.4.3] - 2026-06-12

### Changed
- **Shelf**: tiles are now AppKit-backed so you can select several items (click
  to select) and drag them all out in a single drag

### Fixed
- **Shelf**: you can move the panel again: drag its top bar to reposition it,
  while grabbing a tile still drags the item
- **Shelf**: dropping item(s) somewhere now removes them from the shelf
  automatically (a cancelled drag keeps them)

## [2.4.2] - 2026-06-12

### Fixed
- **Uninstaller**: granting Full Disk Access now actually works. The app
  registers itself with the system first, so it appears (with a toggle) in the
  System Settings list instead of opening to a list it isn't in, and a short
  hint explains how to enable it

## [2.4.1] - 2026-06-12

### Fixed
- **Shelf**: dragging an item out of the shelf now works. The panel no longer
  moves with the pointer, so grabbing a tile starts an item drag instead of
  dragging the whole window
- **Shelf**: shaking the mouse while *moving a window* no longer summons the
  shelf; it appears only when something droppable (a file, image, text or link)
  is actually being dragged

## [2.4.0] - 2026-06-12

### Added
- **Cut & paste files in Finder**: ⌘X cuts the current selection and ⌘V moves it
  into the folder you're viewing, with a floating HUD showing the held items.
  Text fields keep their normal shortcuts. Opt-in
- **Quit on last window close**: when an app that had a window closes its last
  one, it quits, with a per-app exception list (Finder excepted by default).
  Opt-in
- **Complete app uninstaller**: drag an app (or pick one) to find the caches,
  preferences, logs, containers and other files it leaves behind, each with its
  size, then move the selected ones to the Trash and see the space recovered.
  Opt-in
- **Temporary shelf**: a floating area, summoned at the cursor with ⌃⌥⌘D or by
  shaking the mouse mid-drag, that holds files, images, text and links to drag
  back out into any app later; needs no permissions. Opt-in
- A visual onboarding page for each new feature; people updating from an earlier
  version see a one-time "what's new" pass to discover and configure them

### Changed
- Settings moved from a tab bar to a System-Settings-style sidebar, giving every
  feature its own page with room for examples and options

## [2.3.0] - 2026-06-12

### Added
- **Per-app volume mixer** in the panel: set the volume of each app holding an
  audio connection (CoreAudio process taps, macOS 14.4+). A live indicator marks
  apps playing now; volumes persist per app; 100% is untouched passthrough
- **Browser tabs are first-class in the switcher**: each Safari/Chrome/Edge/
  Brave/Vivaldi tab is its own entry

### Changed
- **Switcher is instant**: a browser tab now raises its window immediately
  instead of waiting on the tab-select script, and the panel only appears after
  a short delay so quick flicks switch with no UI
- **Tab-granular toggle**: the switcher tracks a most-recently-used order of
  individual items, so ⌘Tab toggles between two tabs of the same browser just
  like between two apps
- The CPU/GPU/memory breakdown consolidates helper processes under their app
  (one Safari row, not a dozen Web Content rows)

### Removed
- The quick-utilities panel section (hide desktop icons, show hidden files, turn
  off display, eject disks, empty Trash)

## [2.1.0] - 2026-06-12

### Added
- **Per-app resource breakdown**: tapping CPU, GPU or Memory in the panel's
  System section expands the top consumers of that resource. CPU and memory
  come from the process table; per-app GPU% is computed from the accelerator's
  per-process GPU-time counters, sampled as deltas
- **Browser tabs in the switcher**: every Safari/Chrome/Edge/Brave/Vivaldi tab
  appears as its own ⌘Tab entry (the active tab keeps the window thumbnail);
  selecting one focuses that exact tab. Toggleable in Settings › Switcher;
  macOS asks for Automation consent once per browser

## [2.0.2] - 2026-06-12

### Fixed
- **Permissions now survive updates.** Builds are signed with a stable
  self-signed identity (`Tools/setup-signing.sh` locally, shared certificate in
  CI), giving the bundle a constant designated requirement, so macOS keeps
  granted Accessibility and Screen Recording permissions across updates instead
  of dropping them. Falls back to ad-hoc signing on a fresh clone.

### Changed
- The installer **DMG is styled**: a window with the app icon, an arrow and the
  Applications folder for a proper drag-and-drop install.

### Docs
- README/switcher wording updated to ⌘Tab-only (the ⌥Tab option is gone).

## [2.0.1] - 2026-06-12

### Added
- **Automatic updates**: the app checks GitHub Releases (toggle in Settings ›
  General, plus a "Check for updates" menu item), and can download the new DMG
  and self-install with a single click

### Changed
- The window switcher now **always replaces ⌘Tab** (the ⌥Tab option was removed)
- Switcher selection follows a real most-recently-used app order, so a quick
  ⌘Tab→release toggles back to the previous app, matching the system switcher

### Added (switcher)
- Press **Q** while the switcher is open to quit the highlighted app

## [2.0.0] - 2026-06-12

The app was renamed from **Vorss** to **Vorssaint Utils** and prepared for
open source distribution.

### Added
- **System monitor**: CPU/GPU/battery temperatures (SMC), CPU/GPU usage and a
  traffic-light memory pressure indicator in the panel
- **Inverted mouse scrolling**: invert the mouse wheel only, trackpad untouched,
  live toggle (Accessibility)
- **Window switcher**: ⌥Tab (or ⌘Tab takeover) with real window thumbnails
  (ScreenCaptureKit), multi-window support, Spaces/Mission Control friendly
- **Onboarding** in 7 steps: language, Accessibility, Screen Recording,
  monitor tour, optional features, status verification, summary
- **Bilingual interface** (pt-BR / en-US) with live language switching
- New black hole identity: app icon and menu bar glyph with distinct
  active/inactive states and a click micro-interaction
- `--sensors` diagnostic flag (SMC dump for porting to new chips)
- `--uninstall` flag and `Tools/uninstall.sh` for a clean removal (login item,
  TCC permissions, preferences, sudoers rule, no dead entries left behind)
- CI build workflow and automated DMG releases

### Changed
- Renamed to **Vorssaint Utils** (`com.vorssaint.utils`); legacy `Vorss.app`
  is removed by `./build.sh --install`
- The System section now shows only temperatures, usage and memory pressure
- Settings reorganized into General / Energy / Mouse / Switcher / About
- Project restructured into App / Core / Services / UI / Support layers

### Removed
- Clipboard history (and its settings)
- "Sleep now" quick action

## [1.1] - 2026-06-11

Initial internal release as **Vorss**: keep-awake sessions with closed-lid
mode, battery protection, clipboard history, quick utilities and system info.
