# Finder Tools

Finder Tools is an optional feature in the Files and Clipboard group. Enable it
in Features, then open its workspace from Cut and Paste settings or add Finder
Tools to a radial-menu profile. The native Finder menu requires enabling the
bundled Finder extension in macOS System Settings. The workspace also accepts
files and folders through the system file chooser.

## Files and documents

The workspace operates on an explicit selection and destination. Reorder the
selection before combining PDFs or images. For background replacement, the first
image is the subject and the second is the replacement background.

- Create text, RTF, JSON, Markdown, Word, Excel, PowerPoint, HTML, XML, CSS,
  JavaScript, Python and shell files. Office files contain minimal Open XML
  documents. Custom templates copy a selected file or package without replacing
  an existing destination. Save iWork templates as custom template actions.
- Copy paths, names, Markdown links, text, directory trees, summaries and SHA-256
  hashes. Tree depth is configurable. Text output is bounded to 8 MB.
- Copy, move, create aliases, group and flatten folders; hide, lock and rename
  items. Flatten removes only the empty source folder after moving its children.
  Batch rename supports `{n}`, `{name}`, `{stem}` and `{ext}` and previews the
  results. Encoding repair previews a lossless Windows-1252, Latin-1 or Mac Roman
  reinterpretation as UTF-8 before applying the same rename transaction.
- Search filenames and find duplicate content without following symbolic links.
  Search stops at 100,000 examined items or 5,000 matches. Duplicate scans compare
  file sizes before streaming SHA-256.
- Create ZIP archives or disk images. Encrypted disk images use AES-256;
  passwords go to `hdiutil` through stdin and are never saved in settings or
  passed in process arguments. This is not password-protected ZIP output.
- Paste clipboard text, Markdown, PNG images, files, aliases or ZIP archives.
  Clipboard content is read only by the selected paste action.
- Preview, reveal, show information, inspect package contents, eject, share,
  trash or permanently delete. Permanent deletion starts hidden in the native
  menu and always requires confirmation in the host workspace.
- Set or restore file/folder icons, extract PNG icons, choose an application,
  change the default application for a file type, and set a desktop wallpaper.
- Merge PDFs and images, split PDFs into pages, add a text watermark and reduce
  PDF size with the system Quartz filter. Locked or copy-protected PDFs fail
  explicitly. Compression publishes an output only if it is smaller.
- Rotate, stitch, recolor, recognize QR codes, remove a foreground image's
  background or replace it using Vision. Limits are 64 megapixels and 16,384
  pixels per edge. Background replacement requires macOS 14's Vision support.
- Extract audio to M4A. Image/video conversion, resizing, image watermarks, OCR
  and the screenshot editor use existing Vorssaint workspaces, with their feature
  availability checks. The editor supports cropping external images.
- Record a microphone to M4A or a camera to MOV with an optional microphone.
  Recording starts only after choosing an output file and resolving the system
  permission prompt. Closing an active recording stops it and keeps the window
  open until its output is finalized. Disabling Finder Tools stops and saves an
  active recording. Quitting while recording stops capture and keeps the app
  open to finish saving; quit again after it finishes.

Creation operations choose a unique name. Copy/move, ZIP, document exports and
rename transactions refuse to replace existing destinations. Batch operations
report completed outputs and per-item failures. Closing the feature stops its
cancellable jobs; a filesystem call already in progress must finish before a
new mutation can start.

Creation settings can open a completed file, hide its extension, play a sound,
and disable numbered collision names. Disabling numbering reports the conflict
without replacing the original. These options participate in settings backup.

## Menu and saved actions

The menu can be grouped, reordered, hidden per action and given custom titles,
SF Symbols and Shift-Command keyboard equivalents. Duplicate shortcuts go to the
first visible action in the configured order. These equivalents operate within
the menu; they are not global hotkeys. Radial-menu profiles provide existing
Vorssaint global shortcuts and mouse gestures.

Saved actions open folders, applications and websites; copy templates; apply
icons; or execute a selected shell, AppleScript or Python file. Script arguments
are individual selected paths. The working directory is the chosen destination,
falling back to the script's parent. Scripts have a 60-second timeout and an 8 MB
output limit. The user confirms a saved action before it runs. Receiving an
external `vorssaint-files:` URL only prepares a workspace; it cannot execute an
action automatically.
Saved actions can be edited, reordered and placed in named submenus.

Terminal integration offers native Terminal Services for a new window or tab,
iTerm and Ghostty scripting, Kaku's bundled CLI, and a new cmux workspace. Missing
applications or rejected automation permissions produce an error. The adapters
have compiled successfully; their third-party runtime behavior is unverified.

Menu configuration and saved actions participate in the existing settings backup.
No iCloud synchronization is included.

## Local sharing

Local sharing starts only after pressing Start Sharing in its own window. It
binds a private IPv4 address on Wi-Fi/Ethernet, generates a random download token,
and presents a link and QR code. Anyone with the link on that network can download
the explicitly selected regular files. Transfers use unencrypted HTTP. Archive
folders before sharing them.

The server accepts GET requests for the selection list or a selected file index.
It never maps request paths to arbitrary filesystem paths. Host checks, header
limits, escaped filenames and four concurrent connections bound the exposed
surface. File descriptors refer to the originally selected files, even if those
paths are later replaced. Edits to an opened file's contents can affect a live
transfer. Downloads stream in 64 KB chunks. Idle connections expire after 30
seconds; the whole session stops after ten minutes, closing its window, or
uninstalling the feature. No cloud service receives the files.

## Build and signing

`./build.sh --dev --ad-hoc` builds an isolated Developer app without creating a
keychain identity. Its scheme is `vorssaint-dev-files:` and its Finder extension
has a separate bundle identifier. Nested code is signed before the containing
application and verified strictly.

Developer ID builds derive a macOS application-group identifier from the signing
team and the app bundle ID. Both the host and extension receive that entitlement.
Only the menu snapshot (titles, order, visibility, icon/shortcut settings and saved
action IDs) crosses this boundary. Script locations, file selections and clipboard
content stay in the host.

Ad-hoc and legacy self-signed builds have no application-group entitlement. They
use the default native menu; workspace customization and saved actions still
work, but cannot propagate to the Finder extension. Changing shared native-menu
configuration requires a Developer ID build. App-group behavior still needs
validation with a real signing identity.

## Verification and remaining parity

Tests cover file preservation, collisions, rename rollback, symlink exclusions,
selection URL validation, configuration round trips, script argument quoting,
PDF/image operations, Office ZIP packages, M4A export, encrypted disk-image
verification and local-sharing request boundaries. macOS UI validation is
recorded separately; a passing unit test is not evidence that Finder enabled an
extension or granted a permission.

The current implementation is not complete MouseBoost parity. Still open:
optional system-context-menu replacement; QSpace/Path Finder/custom-manager
selection adapters; every reference terminal's tab/window modes; built-in iWork
and proprietary WPS formats; presentation compression; encrypted ZIP; direct WeChat routing beyond the system share
picker. Signed app-group preference sharing,
foreground segmentation and microphone/camera recording also need runtime validation.
A native Finder menu action was verified to open the Developer workspace with
the selected synthetic file and SHA-256 action. The extension was disabled after
the authorized test. Finder serializes menu items, so action requests are retained
in the extension and resolved by unique tags instead of `representedObject`.
A local-sharing download of a generated DOCX was verified byte-for-byte; the
session stop control closed its listener. These
items must remain visible in the aggregate PR until resolved or explicitly
excluded by the requester.
