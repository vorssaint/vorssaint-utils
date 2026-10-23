# Duplicate File Finder

Install **Duplicate File Finder** under **Features → Clipboard and files**. It is
uninstalled by default. Open its workspace from Settings or Vorssaint’s menu.

Add one or more folders and select **Scan**. Contents are compared within and
across the selected folders, including mounted external drives. Select a file row
to preview it or reveal it in Finder. Check individual unwanted copies, select
**Move Selected to Trash**, and review the complete list before confirming.
Nothing is selected automatically, and at least one copy must remain per group.

## Matching and exclusions

Matches require identical main-file bytes, confirmed with a byte comparison after
streaming SHA-256 hashing. Names and extensions may differ. A matching file may
still be needed at both locations; review paths and metadata before moving it.

Only visible, ordinary, locally available files are scanned. Hidden descendants,
packages (including application and photo-library contents), Trash folders,
symbolic links, Finder aliases, hard links, cloud-only/dataless files and files
with resource forks are skipped. Skipped paths and reasons are available in the
workspace. Inaccessible folders do not stop readable folders from being scanned.
No cloud downloads or administrator access are requested.

File and ancestor identities and nanosecond timestamps are checked during reads
and again before each Trash operation. A remaining copy must still match. Changes,
replacements, missing files or unavailable volumes cause the affected operation
to be skipped. Other applications can still change a file between the last check
and macOS’s path-based Trash call; this tool does not lock other applications.

## Space, recovery and privacy

Displayed bytes are logical content sizes. They do not predict physical space
reclaimed from compressed, sparse or cloned files. Moving a file to Trash does not
immediately free its space. Use Finder to restore files from Trash. The tool does
not permanently delete files, empty Trash or offer an in-app Undo in this version.

Partial failures are reported per file. Cancel stops subsequent moves after the
current filesystem operation finishes. A failed group must be scanned again.
Closing the workspace cancels pending work and discards the session. Uninstalling
the feature also closes the workspace and releases its resources.

Folder selections, hashes, results and previews are held only in memory for the
window session. Contents are read locally and never uploaded. File paths and
contents are excluded from settings backup and application diagnostics. Only the
feature’s availability is saved. Folder access is contextual; Full Disk Access is
not required. There are no scheduled scans or idle background tasks.
