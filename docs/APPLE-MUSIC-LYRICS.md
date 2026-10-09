# Native Apple Music and TTML lyrics

Settings → Dynamic Island → Content → Now Playing provides a **Lyrics provider**
menu under **Show lyrics**. LRCLIB remains the default. With **Find lyrics online**
enabled, the experimental Apple Music provider retrieves lyrics for the current
song in Music.app, using the Apple Music account configured on the Mac and an
active subscription. Apple mode queries Apple only; it does not fall back to LRCLIB.

Local LRC and TTML imports remain available with either provider and with online
lookup off. Translation, romanization, a lyric editor and in-app account management
are outside this change. The native presentation follows source timing and singer
metadata; it does not promise identical behavior to every Apple Music version.

## Account access

**Enable Apple Music access…** requests the native macOS permission through
MusicKit. Settings shows **Access enabled** or **Access disabled**, with one
corresponding enable/disable button. A pending permission request disables the
button and shows progress. Permission status is refreshed when the app becomes
active again.

Access enabled means the app preference is on and macOS authorization is granted.
It does not establish that a subscription check or lyric request succeeded. The
current-song result, loading state, subscription requirement and request errors
are shown separately. Imported lyrics do not count as verified Apple access.

**Disable Apple Music access** cancels requests and clears the provider's tokens
in memory. It does not sign out Music.app or revoke the macOS permission. Re-enabling
uses the existing permission when available. To change accounts, use Music.app,
then disable and enable access in Vorssaint so it requests a user token again.
There is no separate logout button.

The macOS permission is optional; LRCLIB and local import do not require it.
See [Permissions](PERMISSIONS.md#media--apple-music) and [Privacy](PRIVACY.md).

## Experimental requests

MusicAuthorization and MusicUserTokenProvider supply native authorization and
subscriber-token access. URLSession performs the provider's HTTPS requests. The
app does not embed a WebView or execute JavaScript for lyrics.

This integration also depends on Apple's public web assets and private lyric
endpoints. The provider downloads the public page and its referenced asset as
text, selects an unexpired AMPWebPlay developer token, and passes it to MusicKit
when requesting a subscriber token. No copied token or Apple script is bundled.
This dependency can break independently of the native MusicKit authorization;
acceptance and maintenance of the experimental provider need maintainer review.

The provider checks subscription and storefront, resolves the recording from a
separate catalog identifier or a single matching search result, then requests:

```text
GET /v1/catalog/{storefront}/songs/{catalogID}/syllable-lyrics
GET /v1/catalog/{storefront}/songs/{catalogID}/lyrics
```

The second endpoint is tried when the first returns 404 or no lyric content.
Other request errors are surfaced. Search results must match the recording's
metadata and duration; ambiguous results are not guessed. Requests use ephemeral
sessions without stored cookies, credentials or URL caches. Redirects must keep
the same HTTPS host. Public bootstrap responses are limited to 8 MiB each;
account, catalog and lyric responses use the 128 KiB lyric-response bound.

Authentication tokens stay in process memory, apart from the cache managed by
MusicKit itself. They are not logged, written to preferences or exported in
settings backups. The selected provider is a portable preference; the local
access-enabled flag is excluded from backups.

## Timing and local import

**Import lyrics…** accepts .lrc, .ttml and XML files. A successful import replaces
lyrics for the current recording and displays the filename. A pending provider
request cannot overwrite that import. Changing recordings or providers clears
it; hiding the panel preserves that recording's lyrics and timing adjustment.
Imports have byte and line limits, and XML external entities are disabled.
UTF-8 and UTF-16 BOMs and XML encoding declarations are supported.

TTML preserves paragraph and span begin/end times, Unicode text ranges, explicit
line breaks, singer agents and background vocals. Adjacent syllable spans remain parts of the same
word; word boundaries are not invented. LRC uses line timing, and untimed lyrics
use plain text. Missing word timing is not synthesized. The existing timing
adjustment applies to both lyrics and instrumental indicators.

When available, TTML songwriter metadata supplies a **Written By** footer in
source order, with duplicate names removed. Catalog composerName is the fallback.
The footer is omitted when the source supplies no credits.

## Native presentation and lifecycle

SwiftUI Canvas uses AppKit TextKit to shape and draw glyphs. Playback position
controls progressive syllable fill, word lift and sustained-word emphasis.
Main vocals use 22 pt bold, background vocals 16 pt bold, untimed lyrics 15 pt
medium and credits 12 pt medium. Inactive synchronized lines use 93% visual scale
without changing text layout. Person agents retain opposite sides, groups center,
and overlapping vocals retain their own active intervals.

Empty timing cues do not appear as musical-note rows. Known intros and explicit
silent intervals longer than nine seconds show three dots; ordinary LRC without
an end/blank cue does not establish a vocal gap. Short pauses hold the completed
verse readable. Middle-song indicators become the scroll target when they begin.

The dots grow from small on entrance, breathe together, and make a continuous
grow-then-shrink pulse over the final 1.5 seconds before vocals. They fade during
the final 0.3 seconds. A middle-song slot opens over 0.4 seconds; the complete
42 pt slot and spacing release over 0.5 seconds after vocals enter. Future gaps
do not reserve invisible space in the document.

NSScrollView interpolates the clip offset toward measured lyric anchors. Ordinary
verse changes start scrolling even if those rectangles have not changed. The
handoff begins 0.3 seconds before vocals and runs for 0.8 seconds. One bounded
main-run-loop clock drives scrolling and slot reflow. The viewport is transparent
and preserves the island's existing material, blur and Liquid Glass preference.

Reduced Motion uses discrete updates and suppresses the dot pulse and word
transforms. Paused or finished voices do not keep a continuous animation clock.
Hiding Lyrics or disabling online lookup cancels lookup work. Track/provider
changes invalidate obsolete results, and disabling lyrics clears the lyric cache.

## Automated checks

Run on a supported Mac:

```sh
./build.sh --test-suite=notch --test-suite=utilities --test-suite=settings
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh
./build/Vorssaint --selftest
```

The last two commands exercise the optimized build. These commands describe the
required checks, not a claim that every configuration has already been tested.
See [CONTRIBUTING](../CONTRIBUTING.md#validation) for repository validation rules.

The Notch suite covers matching, token filtering, TTML/LRC parsing, Unicode ranges,
voices, credits, bounds and stale request handling. Production TextKit bitmap
captures check progressive fill, wrapping and alignment. Native viewport tests
sample real scroll and document-height transitions, including a playback clock
that advances without replacing the root view. Normal verse changes, transparent
backgrounds, explicit TTML breaks and hidden-view re-enabling are regression cases.
A production-method token-cache test delivers a reply after cancellation to verify
that it cannot refill the cache cleared by disabling access. Utilities checks cover
the shared catalog-ID path and legacy/invalid adapter metadata. Settings checks
cover preference and backup behavior; string checks cover all fifteen locales.

Optional `VORSSAINT_KARAOKE_SNAPSHOT_DIR` exports synthetic bitmap captures.
No subscriber token or complete fetched song lyrics are bundled as test fixtures.

## Recorded validation and remaining gaps

Local validation used macOS 27.2 on an arm64 Mac17,3. The Developer build and its
selftest passed. After rebasing onto upstream main, the latest Notch run passed 70,635 checks,
Utilities passed 444, and Settings passed 494. These are assertion counts across the suites, not independent manual
scenarios. The optimized build, its selftest and strict verification of the locally
signed bundle also passed. Official Developer ID signing/notarization and other
supported macOS runtimes remain unverified for this change.

A repeated authenticated probe after the token-cache fix, using the production
native provider/parser, retrieved Helium Balloon with 87 cues, 356 timed spans
and eight writer entries.

An authenticated probe using the production native provider/parser and the
Developer bundle/signing identity retrieved MALU MALU (1851140685), with 66
timeline cues and 353 timed spans. Helium Balloon (1884348005) supplied writer
metadata and the interval from 42.114 to 53.781 seconds. These requests establish
native access on this Mac, not availability on all accounts or recordings.

Installed English Settings was checked through access enabled → disabled →
enabled: one action was shown at a time, and re-enabling used the existing grant
without another login. Live presentation was compared with Music.app and revised
for scroll, dot transitions and material. Synthetic captures supplement those
checks; complete manual coverage of all playback paths, locales and window sizes
is still required. A temporarily unresponsive provider dropdown was reported and
later cleared by the user as a window issue; no dropdown patch or confirmed cause
is claimed.

A warm-process measurement with Hurt So Good playing continuously sampled physical
footprint at one-second intervals for 10–12 seconds per state, omitting the first
two samples. Median app-plus-Now-Playing-helper footprint was 158.9 MiB with Lyrics
closed, 218.5 MiB open and 216.5 MiB reopened. The observed 57.6–59.6 MiB difference
includes panel/render/animation/cache costs and is not an isolated parser
allocation, a cold-start benchmark or a release-build result.

## Manual macOS smoke checks

- Test native authorization, denied access, subscription/network errors and
  enable/disable/re-enable behavior. Confirm that permission and fetched-lyric
  status are distinguishable and that disabling does not sign out Music.app.
- Play through an intro, ordinary verses, an overlapping duet and a middle-song
  interval. Check indicator entrance, the final pulse, handoff, stable wrapping,
  preserved material and absence of phantom spacing. Do not disable animation
  merely to validate its layout.
- Pause/resume and seek before, inside and after a vocal interval or gap. Adjust
  timing and confirm highlights, indicators and scroll use the same offset.
- Change song/player/provider while a request is pending. Hide/reopen Lyrics,
  disable lookup and disable the feature; stale results must not reappear.
- Exercise LRCLIB, imported LRC and imported TTML with online lookup off. Include
  UTF-16, untimed content, absent word timing and writer metadata.
- Check Settings and its provider dropdown at minimum window width, after closing
  and reopening the window, and in several locales. Check Reduced Motion separately.
- Check other supported macOS versions and the official release signing/packaging
  configuration. Record untested cases explicitly in the PR verification section.
