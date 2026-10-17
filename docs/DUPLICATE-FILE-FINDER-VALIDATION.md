# Duplicate File Finder validation

Local validation on 2026-10-12 used a MacBook Pro (`MacBookPro18,3`), macOS
26.6.2 (25G83), the macOS 26 SDK and Swift 6.3.3. The branch starts at upstream
`fe24c1766d568b132c1c78c554cc422381a3a17d`; it contains no menu-bar organizer
changes, release/version changes or research files.

## Automated and build checks

The `duplicate-finder` suite compiles the production scanner, selection/Trash
policy and session. Disposable fixtures cover exact bytes across different names
and extensions, same-size different content, empty and multi-chunk files,
overlapping roots, hash collisions, mutation and cancellation between read chunks,
hidden descendants, packages and explicitly selected package interiors, Trash,
symlinks, Finder aliases, hard links, resource forks, unavailable/unreadable paths,
dataless flags, stale identities and replaced ancestors. Cloud placeholder testing
uses synthetic flags; it does not exercise a live cloud provider.

Cleanup tests inject the Trash operation. They cover keeping a copy, invalid
selection, confirmation cancellation, replaced targets, changed/missing keepers,
partial failures and cancellation after a move. Session checks cover unchecked
defaults, resetting folders, closing during work, late-result suppression and
refusing operations when the feature is absent. Every new string field and skip
reason is checked in all fifteen locales; these checks do not replace human
translation review.

The validation commands are:

```sh
./build.sh --test-suite=duplicate-finder --test-suite=features --test-suite=settings --test-suite=localization
./build.sh --test
./build.sh
./build/Vorssaint --selftest
./build.sh --dev
./build/VorssaintDeveloper --selftest
./Tools/make-dmg.sh
git diff --check
```

The final focused run passed 9,614 checks, including 86 duplicate-finder checks.
The final full-suite repeat passed 116,028 checks, plus preference cleanup,
uninstall-Spaces and Developer-install isolation checks. An earlier serial full
run passed 116,026 checks before the two streaming-read tests were added. Other
full runs intermittently hit unchanged notch tests: `NotchCompactTests.swift:285`
(distant-selection realization) and `NotchDownloadScanTests.swift:118` (archive
completion). The first run of the final source hit the compact assertion; the
immediate final repeat passed. A clean-upstream notch-only run passed, so those
failures were not reproduced on the baseline. They remain documented rather than
being attributed conclusively to a cause.

Optimized and Developer builds and both selftests passed. DMG packaging passed.
The optimized build was repeated after the final scanner changes. No Swift
compiler warnings were reported. `actool` was unavailable, so the build used the
repository's normal `.icns` fallback. Local signing and packaging are not a
notarized release.

## Native disposable-fixture checks

A separately identified QA copy of the Developer app used its own preferences.
The existing installed app and its preferences were not replaced. Checks performed:

- Settings launch and application-menu launch, with one reusable finder window.
- Native folder picker for two local roots and a mounted HFS+ test disk image.
- Exact matching across all three roots, with every checkbox initially unchecked.
- PNG and text/Markdown Quick Look, file metadata and full paths in the inspector.
- Disabled final-copy checkbox after selecting the other copy in a two-file group.
- Confirmation listing the selected path/count/bytes; cancellation left the file
  in place.
- Moving one uniquely named disposable file through the real Trash operation,
  verifying its original path was absent and its exact Trash path present, then
  using Finder's **Put Back** to restore it.
- Ejecting the disposable mounted image: the next scan reported its inaccessible
  root and still returned duplicates from readable local roots.
- Cancelling a scan of twelve sparse 1 GiB files discarded incomplete groups.
- Closing during scanning and reopening from the application menu produced an
  empty session.
- Light and dark app appearance, and accessibility labels exposed for controls,
  file previews and checkboxes. A Tab press reached the folder list.
- Removing the sole installed feature in the QA app after starting a scan removed
  its Settings page and application-menu entry.

The native UI checks preceded the final downloaded-iCloud/empty-resource-fork
eligibility adjustments and added read-hook tests. Those final changes were
validated by production compilation and automated tests.

## Outstanding evidence

- Upstream Swift 6.0.3 and hosted CI results must be evaluated separately.
- Spoken VoiceOver interaction and a complete keyboard-only workflow have not
  been validated.
- A physical external drive, abrupt hardware disconnection, network filesystems,
  live cloud-provider placeholders and macOS 14 have not been exercised. The
  mounted-image check is not physical external-drive qualification.
- Human review of all translations and unsupported Quick Look formats remains.
- Other applications can modify paths between the final validation and macOS's
  path-based Trash call; no exclusive filesystem lock is claimed.
- This draft is the feature proposal. Maintainer agreement on direction is
  pending; the contributor explicitly chose a direct draft instead of the
  repository's issue-first discussion workflow.
