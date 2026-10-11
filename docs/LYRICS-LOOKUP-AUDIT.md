# Lyrics lookup audit

On 2026-10-11, **Режиссёр** was unavailable in Dynamic Island while mpv supplied artist `группа Градусы`, album `Градусы` and duration 219.3 seconds. LRCLIB has synchronized records under `Градусы`, including a 219-second compilation record. Exact lookup with the file tags returned 404.

## Corpus and comparison

The original cohort contains 80 seeded random samples from 1,104 local audio files (`random.Random(20261011)` over sorted files), plus seven desktop reproductions. The random subset has 76 distinct artist strings. A further 59 metadata samples cover German (8), Italian (8), Chinese (12), French (6), Japanese (5), Latvian (3) and Spanish (1) artists, plus version/title formatting (8) and long collaboration credits (8). These groups describe selection context, not an automatic classification of sung language. Some metadata variants can refer to the same audio recording. This is a varied regression corpus, not a representative population estimate.

Before uses the upstream exact lookup and strict decoder at `21eb10b8`; after runs the production matching logic, including verified artist aliases. Captured responses are replayed with the production parser. No previously accepted record is lost.

| Cohort | Before | After, ±2 seconds | After, ±5 seconds |
| --- | ---: | ---: | ---: |
| Original 87 samples | 60 | 81 | 81 |
| Additional 59 samples | 32 | 52 | 53 |
| Combined 146 samples | 92 (63%) | 133 (91%) | 134 (92%) |

Five seconds adds only **Blow Your Mind** (file 208 seconds; catalog 212 seconds, with different release metadata). This modest gain does not justify weakening recording agreement globally. Two seconds remains the default. Accepted metadata and usable lyrics do not establish that every timestamp is correct.

The first collection had eight exact 503 responses. Sequential rechecks recovered seven; **ХОЧЕШЬ?** retained a 503 with working search results. The additional collection retained exact 503 responses for **踩着云 (踩云彩)** and **Dis-moi que tu m'aimes**, even on recheck. Counts therefore include captured provider availability as well as metadata differences.

## Failure patterns and generic fixes

- Formatting differs: punctuation, Latin accents, Russian `е`/`ё`, collaboration separators and `(Extended)` versus `- Extended`.
- File tags expand the artist credits while the catalog lists only the primary artist.
- Compilation album tags prevent exact lookup for the same title, artist and duration.
- Native names, English names and transliterations differ. Generic MusicBrainz identity verification recovers **殘酷月光** (`林宥嘉` → `Yoga Lin`), **遇见** (`Sun Yan-Zi` → `Stefanie Sun`) and **Polzat'** (`LSP` → `ЛСП`). There is no runtime artist/song allowlist or library-specific mapping.
- Exact HTTP 5xx can coexist with usable search results. Network failures, rate limits and other client failures stop rather than creating a retry storm.

## Remaining 13 samples

Three have equally ranked conflicting lyric payloads and remain ambiguous: **Zvyozdnoe Leto (Geoffrey Day Remix)**, **Крылья**, and the Coopex cover **Smells Like Teen Spirit**. **Blow Your Mind** exceeds the two-second duration bound. The other nine have no eligible candidate within the bounded title, primary artist, recording-version and duration rules:

- **Прекрасное далёко (Film version)** — Татьяна Дасковская
- **Hell Is Empty** — Glum Aleks
- **Safety Net** — Bea
- **Alive** — Enzalla
- **踩着云 (踩云彩)** — 闵成珺
- **Guren no Yumiya (YouTube edit)** — Linked Horizon
- **Aiz Azara** — Tautumeitas
- **Everything Gonna Be Better (feat. Joe Michel) (Extended Mix)** — Silience, Joe Michel
- **Pastlives** — sapientdream

A YouTube edit, film version or extended mix must not silently inherit lyrics/timing from a different recording. Remaining options are better catalog coverage, corrected source tags, independently resolving conflicting records, or importing a local LRC. This implementation does not scrape arbitrary lyric sites or guess artists from search scores.

## Request budget, matching and privacy

Exact lookup stays first: an ordinary hit needs one request. Otherwise there are at most three deduplicated LRCLIB searches. All candidates require normalized title/primary artist agreement, compatible recording qualifiers and duration within two seconds. Album agreement, full credits, exact title spelling, synchronized lyrics and duration proximity rank candidates. Equal metadata scores and duration distances less than 0.25 seconds apart with different lyrics are ambiguous.

Artist identity lookup happens only after catalog matching fails without an eligible candidate or provider error. Known same-artist/title records with wrong duration skip alias lookup. Exact normalized membership in MusicBrainz names/aliases is required; fuzzy search scores cannot prove identity. A broad or ambiguous artist result also needs exact album agreement and an independently verified artist identity. Metadata replies are limited to 128 KiB, five entities and bounded alias lists. At most two metadata requests and two additional LRCLIB alias queries are permitted: eight total requests in the worst case.

MusicBrainz calls are spaced at least 1.05 seconds apart, following its [rate limit and identification guidance](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting). Queries use its documented [search API](https://musicbrainz.org/doc/MusicBrainz_API/Search). There are no automatic retries. A maximum of 32 artist/album identities is kept in memory: positive entries expire in an hour, absent identities in ten minutes and provider failures in fifteen seconds. Reopening an unavailable song is suppressed for sixty seconds; failed requests for fifteen seconds. Explicit Retry bypasses the relevant negative cache. Positive lyrics are reused for the current song. Hiding, changing tracks or revoking consent cancels both pending and active work, with generation checks before issuing or accepting requests.

All requests use ephemeral sessions without cookies, credentials or disk caches and refuse redirects. LRCLIB search envelopes are limited to 1 MiB/twenty records, individual lyric records to 128 KiB. The online hint in all fifteen languages and privacy documentation disclose both hosts and that artist/album metadata can reach MusicBrainz. Audio and lyrics are never sent to MusicBrainz. Disabling the feature clears in-memory caches.

## Reproducible checks

The two committed fixtures contain public track metadata and provider record IDs, with original lyrics replaced by SHA-256-derived synthetic payloads. Equality, ambiguity, usable timed/plain payloads and response bounds are preserved; audio and private file paths are excluded. `./build.sh --test-suite=notch-music` passes 1,668 checks, including all 146 decisions, prior accepted records, duration experiments, generic fictional alias cases, negative caching, request bounds and cancellation. Tests extract lookup methods from production; network, settings and scheduling are doubles.

`python3 Tools/check-lyrics-live.py --all` uses the actual downloader and lookup methods sequentially against current services. Initial results: 121 synchronized, 11 plain, 11 unavailable and three provider failures. A separate targeted recheck of the three failures produced synchronized **Head Up**, unavailable film-version **Прекрасное далёко**, and unavailable YouTube-edit **Guren no Yumiya**, all matching corpus expectations. These are documented rechecks, not retries hidden in the app. The helper supports repeatable `--title` filters and allows the full bounded request chain time to complete.

## Native Dynamic Island comparison

The baseline Developer app was built from upstream `21eb10b8`; all 666 source files were byte-compared against that commit with no differences. Each test switches the same mpv playlist position, opens Lyrics, verifies the displayed title and records the settled island outcome. Only one app version runs at a time. Temporary independent `caffeinate` keeps the desktop awake across restarts. The host is an Apple M1 Max MacBook Pro on macOS 27.0.1.

All 22 titles were individually verified. Baseline: five synchronized matches and seventeen unavailable. Updated: eighteen synchronized matches, one plain-text match and three unavailable; no provider failures during this comparison.

| Song | Upstream island | Updated island |
| --- | --- | --- |
| Feuer frei! | Synchronized | Synchronized |
| Tanz aus der Reihe! (feat. Weekend) | Unavailable | Synchronized |
| Notte di Natale | Unavailable | Synchronized |
| Sarà perché ti amo | Unavailable | Synchronized |
| 很愛很愛你 | Synchronized | Synchronized |
| 殘酷月光 | Unavailable | Synchronized |
| 無眠 | Synchronized | Synchronized |
| 私奔到月球 | Unavailable | Synchronized |
| Voyage, voyage | Unavailable | Synchronized |
| Amour plastique | Unavailable | Synchronized |
| Guren no Yumiya (YouTube edit) | Unavailable | Unavailable |
| 勇者 | Synchronized | Synchronized |
| Ja tikai uz mani tu paskatītos | Unavailable | Plain text |
| Kaķēns, kurš atteicās no jūrasskolas | Unavailable | Synchronized |
| Disfruto | Synchronized | Synchronized |
| Everything Gonna Be Better (feat. Joe Michel) (Extended Mix) | Unavailable | Unavailable |
| Blow Your Mind | Unavailable | Unavailable |
| Режиссёр | Unavailable | Synchronized |
| Not A Lullaby | Unavailable | Synchronized |
| Jai Ho! (You Are My Destiny) | Unavailable | Synchronized |
| 遇见 | Unavailable | Synchronized |
| Polzat' | Unavailable | Synchronized |

An earlier twenty-song island run also completed with sixteen synchronized, one plain-text and three unavailable results, before the alias extension. The comparison above uses the final alias implementation on the same twenty-two songs as the baseline. Controlled replay temporarily unshuffles the test playlist; the user’s `play-music` alias already includes `--shuffle` and is unchanged. The complete library is restored and shuffled after testing.

Release and Developer builds and both self-tests pass. The unfiltered local run has 115,490 checks with one failure at `Tests/NotchCompactTests.swift:218`; a fresh clean-upstream notch run reproduces exactly that calendar-layout failure (70,516 checks). The focused `notch-music` alias is omitted from the unfiltered runner because those fixtures already run inside `notch`; executing the subset twice caused stateful adapter fixtures to fail in the previous CI run.


Conclusion: canonical metadata plus bounded search solves most misses. Verified artist identity adds cross-script coverage without embedding personal-library mappings. Wider duration tolerance has little benefit in this corpus and weakens recording checks. Request caps, shared alias caching and short negative caching keep the improvement bounded.
