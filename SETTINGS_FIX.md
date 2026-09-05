# Fix doc: `vorssaint://run/settings.general` beeps instead of opening Settings

Symptom: `open 'vorssaint://run/settings.general'` only beeps. The docs
(docs/DEEP_LINKS.md, "Settings pages") promise every listed page ID opens its
page, and the reference test passes. Three more IDs fail the same way:
`settings.cleaner`, `settings.uninstaller`, `settings.appUpdates`.

## Trace

1. `vorssaint://run/settings.general` parses fine: `DeepLinkSupport.parse`
   yields `Request(stableKey: "settings.general")`.
2. `runExternalRow` asks `freshFullEntry(forStableKey:)`
   (Sources/Vorssaint/Services/CommandBar/CommandBarService.swift:483), which
   rebuilds the full pool and searches every indexable row. Nothing carries
   the stable key `settings.general`, so the guard falls through to
   `NSSound.beep()` (CommandBarService.swift:484).
3. Why nothing carries it: the Settings rows are built by
   `CommandBarCatalog.settingsEntries` (CommandBarCatalog.swift:799) from
   `SettingsDirectory.searchItems` — and `.general` *is* in the directory
   (SettingsDirectory.swift:67). But the catalog drops it first:
   `pagesCoveredByActions = [.general, .cleaner, .uninstaller, .appUpdates]`
   (CommandBarCatalog.swift:795) filters out any page an action row already
   opens, so the bar does not list `settings.general` next to
   `action.openSettings` leading to the same place.

The filter is a bar-UI dedup decision. Deep links resolve through the same
row pool, so the dedup silently deleted four documented addresses. The beep is
the designed "unknown ID" response — the ID is not unknown, it is unlisted.

## Why the reference test missed it

The "keeping this page true" checks (Tests/MetricsTests.swift) compare the
docs against their sources, never against rows actually emitted:

- The ID check reads the catalog source for literal IDs. `settings.<page>` is
  interpolated, so it only asserts the docs contain the `settings.` family
  prefix.
- The Settings-page check reads the `SettingsPage` enum from
  FeatureVisibilitySupport.swift and requires every page in the docs list.
  `.general` is in the enum, so the docs listing it is "true" — even though no
  row answers to it.

Both checks are honest; their sources just do not know about the dedup filter.

## Secondary gap, same shape

`settingsEntries` also drops a page when
`FeatureVisibilitySupport.isPageVisible` says it is hidden, and drops
`settings.feature.<name>` rows when the feature is off. Those beeps are
closer to defensible — the docs' rules already say a missing setup beeps —
but the docs' Settings list does not say pages can be absent, so a caller
cannot tell "hidden" from "typo". Worth one sentence in the docs either way.

## Fix options

1. **Resolve `settings.<page>` without needing a bar row (recommended).** In
   `runExternalRow`, when no row matches and the key is `settings.<page>` with
   a page in `SettingsPage`, open Settings at that page directly — same
   routing `action.openSettings` uses. The enum stays the single source of
   truth, the bar keeps its dedup, and every documented page ID works. The
   visible-feature question falls out of the same call: open the page and let
   Settings land wherever it lands, or beep for hidden pages to match the
   docs' existing rule.
2. **Give the four pages real rows only for external dispatch.** Builds
   parallel rows outside the bar's pool; two sources for the same addresses,
   and the catalog keeps lying to the test harness.
3. **Docs-only: remove the four IDs.** Also demands reworking the
   Settings-page check, which today *requires* every enum page in the docs.
   The docs would then point `settings.general` callers at
   `action.openSettings` — an inconsistency with no upside, since the page
   exists and opening it is safe.

Option 1 is roughly a dozen lines in CommandBarService.swift plus test pins:
one expectation per affected ID resolvable, one that an unknown page
(`settings.noSuchPage`) still beeps.

## Side observation (corrected after testing on this machine)

`runExternalRow`'s doc comment claims "the Mac's own Settings panes are
refused here rather than opened". No code refuses anything — there is no
`macsettings.` branch in `runExternalRow` or `dispatch` — but `macsettings.*`
links beep anyway, for two compounding reasons that have nothing to do with
the comment:

1. **The IDs are runtime-discovered**, so guessing one fails. The catalog
   builds rows from the `.appex` bundles macOS ships
   (CommandBarSystemSettings.swift:61-94); on this machine the Sound pane is
   `macsettings.com.apple.Sound-Settings.extension`, not `com.apple.sound`.
   An invented ID is an unknown ID, and beeping is correct there.
2. **The pane list is loaded lazily, only when the bar opens.**
   `loadMacSettingsIfNeeded` (CommandBarService.swift:2164) populates
   `macSettingsEntries` on the first bar presentation; `freshFullEntry` — the
   deep link resolver — rebuilds the catalog and running entries but never
   triggers that load. After a fresh launch, `macSettingsEntries` is empty and
   *every* `macsettings.*` link beeps, including perfectly spelled ones, until
   someone opens the bar once. A link that works, then stops working after an
   app restart, is worse than an honest refusal.

So the comment is unenforced either way: the code neither refuses these rows
nor reliably opens them. Fix options when the settings-page work lands:

- Honor the comment deliberately: reject `macsettings.` keys in
  `runExternalRow` with the unknown-ID beep, and say so in the docs — or
- Honor the code: trigger the pane load for external dispatch (or resolve
  panes by bundle ID on demand) and document the `macsettings.` family, since
  these are real, addressable rows that the docs never mention.

Either way the stale comment goes; the current state — accidental beep,
comment claiming intent — is the one state nobody chose. To confirm cause 2
on your machine: launch Vorssaint fresh, run a correctly spelled link (e.g.
`vorssaint://run/macsettings.com.apple.Sound-Settings.extension`), see it
beep, open the Command Bar once, close it, and run the same link again.

## Verification (when you ask for it)

```sh
./build.sh --test
./build/Vorssaint --selftest
open 'vorssaint://run/settings.general'          # expect Settings, General page
open 'vorssaint://run/settings.cleaner'          # expect Settings, Cleaner page
open 'vorssaint://run/settings.noSuchPage'       # expect beep, nothing opens
```

Nothing has been built or run for this doc yet.

---

Possible solution: Okay, I've stashed those changes. Let's take a different approach. Let's rewrite the DEEP_LINKS docs to be very simple and straightforward. Just list all supported DEEP_LINKS and let's get rid of all of the settings pages.




