# Lyrics lookup audit

On 2026-10-11, songs with available synchronized lyrics were showing “No matching
lyrics for this recording” in Dynamic Island. The first reproduction was
**Режиссёр**, played through mpv with artist `группа Градусы`, album `Градусы`
and duration 219.3 seconds. LRCLIB has synchronized records under `Градусы`,
including a 219-second compilation record. Exact lookup with the file's tags
returned 404.

## Evidence and sampling

The audit started with seven songs observed in the running official app by using
Next track and opening Lyrics. Three displayed synchronized lyrics; four did not.

A larger sample used `random.Random(20261011).sample(sorted_files, 80)` over 1,104
local audio files, then read title, artist, album and duration with ffprobe.
All 80 had usable tags and represented 76 distinct artist strings. These are
random library tracks, not a representative sample of all music or providers.
The seven desktop reproductions were added separately, giving 87 unique tracks.
No file paths, audio or original lyric text are included in the committed fixture.

Requests used LRCLIB `/api/get`, followed by up to three deduplicated `/api/search`
queries: original title/credits, original title/primary artist, normalized
title/primary artist. Titles retain recording qualifiers. Three concurrent
workers captured responses. Eight initial exact lookups returned 503; a later
sequential recheck returned records for seven, while **ХОЧЕШЬ?** still returned
503 with working search results. The final corpus uses those rechecked responses;
the initial errors are not presented as metadata misses.

The captured responses were evaluated with the production Swift matching and LRC
parser. Before means the existing exact lookup and strict decoder; after includes
canonical metadata decoding and bounded fallback search.

| Sample | Before | After, ±2 seconds | After, ±5 seconds |
| --- | ---: | ---: | ---: |
| Seeded random sample | 57 / 80 | 72 / 80 | 72 / 80 |
| Desktop reproductions | 3 / 7 | 7 / 7 | 7 / 7 |
| Combined | 60 / 87 (69%) | 79 / 87 (91%) | 79 / 87 (91%) |

This is an increase of 19 resolved tracks, with no previously accepted record
lost. A resolved record has usable lyrics and satisfies the metadata rules;
these counts do **not** establish that every recovered timestamp is correct.
The five-second experiment admitted additional candidates for ten tracks but
resolved no additional songs, so the implementation keeps two seconds.

## What failed

- **Exact responses were rejected despite harmless formatting changes.** Examples
  include `Moral of the Story: Chapter 1` versus `Moral of the Story Chapter 1`,
  `ZHU, AlunaGeorge` versus `ZHU/AlunaGeorge`, and `(Extended)` versus `- Extended`.
- **Expanded artist credits missed the catalog's primary artist.** Examples include
  `Порнофильмы, Котляров Владимир Андреевич` and
  `The Weepies, Deb Talan, Steve Tannen`.
- **Different releases shared the same recording.** Compilation album tags could
  prevent exact lookup even when title, artist and duration matched search records.
- **Spelling and punctuation differed.** Examples include Russian `е`/`ё`,
  `5'nizza`/`5nizza`, and collaboration separators/`feat.`.
- **Exact lookup could fail server-side while search still worked.** The persistent
  503 for **ХОЧЕШЬ?** required treating HTTP 5xx differently from an offline network
  error or rate limit.

Eight tracks remain unresolved: six have no eligible candidate under the title,
primary-artist, version and duration rules; two have equally ranked conflicting
payloads (**Zvyozdnoe Leto (Geoffrey Day Remix)** and **Крылья**). These remain
unavailable rather than being selected by API result order.

## Implemented approach

1. Keep the single exact request first. Accept a canonical exact reply when
   punctuation, Latin accents, `е`/`ё` or credit separators differ, while retaining
   album agreement and the two-second duration bound.
2. On a missing/unusable exact reply or HTTP 5xx, search the same consented LRCLIB
   host using at most three deduplicated variants. Network failures, client errors
   and rate limits stop the request chain.
3. Require normalized title agreement, the primary artist (or complete equivalent
   credits), and duration within two seconds. Preserve title qualifiers and reject
   conflicting live/concert/remix/acoustic/instrumental/karaoke album markers.
4. Rank eligible records by album agreement, complete credits, exact title spelling,
   synchronized lyrics and duration proximity. Conflicting payloads with equal
   metadata scores and duration distances less than 0.25 seconds apart are ambiguous.
5. Recheck song identity, generation, visibility and online consent before accepting
   a response or issuing another request. Preserve the original redirect refusal,
   ephemeral sessions, and 128 KiB per-record limit. Search envelopes are limited
   to 1 MiB and twenty records; there are at most four requests per lookup.

No new provider, permission, persistent cache or user setting is introduced.

## Replaying the evidence

`Tests/Fixtures/NotchLyricsCorpus.json` contains the captured metadata, provider
record IDs, queries, synthetic payloads and reviewed before/after decisions.
Original plain text and parsed timed lyrics were replaced by SHA-256-derived
synthetic verses, preserving whether payloads were equal, different, synchronized
or absent. This permits deterministic ambiguity and matching regression tests
without publishing song lyrics. It does not test original timing accuracy.

Run `./build.sh --test-suite=notch-music` to replay all 87 records, compare two and
five seconds, and exercise positive/negative matching, response bounds, fallback
sequencing, server errors and cancellation. The fallback/lifecycle test bodies are
extracted from production sources by `Tests/generate_sources.py`; only the network,
preferences and scheduler are doubles.

`python3 Tools/check-lyrics-live.py` runs the production downloader and lookup methods
sequentially against LRCLIB for 20 tracks: all seven desktop reproductions plus
thirteen seeded library samples. All 20 outcomes agreed with the captured corpus:
18 synchronized matches, one plain-text match, and one unavailable recording.
This checks fresh HTTP responses, not only replayed fixtures.

| Song | Fresh production lookup |
| --- | --- |
| Чужое горе | Synchronized |
| Whatever It Takes | Synchronized |
| Not A Lullaby | Synchronized |
| Jai Ho! (You Are My Destiny) | Synchronized |
| Secrets (feat. Vassy) | Synchronized |
| The Pretender | Synchronized |
| Режиссёр | Synchronized |
| Прекрасное далёко (Film version) | Unavailable, as expected |
| Pocket | Plain text |
| ХОЧЕШЬ? | Synchronized |
| Sun Goes Down (feat. Jasmine Thompson) (Radio Mix) | Synchronized |
| I WANNA BE YOUR SLAVE | Synchronized |
| bellyache | Synchronized |
| Moral of the Story | Synchronized |
| All Star | Synchronized |
| Нас не догонят | Synchronized |
| mr. sunshine | Synchronized |
| Ghost Town | Synchronized |
| I'm Not The Only One | Synchronized |
| Sexy And I Know It | Synchronized |

The probe uses inert playback/window dependencies and does not alter app settings.
The rebuilt Developer app visibly displayed synchronized lyrics in Dynamic Island
for the original failing **Режиссёр**, plus **Little Dark Age** as a control.
A full 20-song island run could not be completed: native desktop automation stopped
returning a window (`cgWindowNotFound`, then timeout). A batch result that retained
an earlier song's outcome was discarded; it is not counted as UI evidence.
The host was an Apple M1 Max MacBook Pro on macOS 27.0.1.
