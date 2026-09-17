# Vorssaint — Localization Context

## Language surface architecture

Two independent, parallel catalogs cover every user-facing string. Adding a
language means touching both:

1. **Main catalog** — `Sources/Vorssaint/Core/Localization.swift` defines
   `struct Strings` (~900 fields). Each language's content lives in its own
   file under `Sources/Vorssaint/Core/Localizations/` (e.g.
   `Strings+Spanish.swift`), as `extension Strings { static let xx = Strings(...) }`.
   `AppLanguage` (same file) is the source of truth for which languages
   exist; `L10n.s` switches on it to pick the catalog.

2. **Feature catalogs** — 34 files under `Sources/Vorssaint/Core/*Strings.swift`
   (e.g. `BrightnessStrings.swift`, plus `FeatureStrings.swift` itself, which
   holds several catalogs inline) each define their own small `struct
   XxxFeatureStrings`, a `static func xxx(_ language: AppLanguage) -> XxxFeatureStrings`
   dispatcher, and — unlike the main catalog — keep **every** language's
   static block in the *same file* ("one static per language, all in this
   file", per the file's own header comment).

A language is only "real" once both surfaces have a complete entry — the
compiler enforces the main catalog's completeness (missing a field in any
`Strings(...)` init fails the build); the feature catalogs are enforced the
same way per-struct.

`Tests/MetricsTests.swift` also iterates `AppLanguage.allCases` and checks
that certain format strings (e.g. `pasteSelectedFormat`) still contain their
expected placeholders (`%d`, `%@`, …) for every language — a translation must
preserve those exactly.

## Decisions

### Locale identifier: bare `vi`
No dialect/script split to disambiguate (unlike `zh-Hans`/`zh-TW`/`zh-HK` or
`pt-BR`), so Vietnamese follows the plain-ISO-code languages (`es`, `de`,
`fr`, `it`, `ja`, `ko`, `tr`, `ru`).

### Register: neutral, no direct pronoun
Vietnamese UI text avoids addressing the user directly ("bạn"/"anh"/"chị").
Use imperative/descriptive phrasing instead — "Chọn ngôn ngữ…", "Bật…", "Đang
xử lý…" — matching the tone of macOS's own Vietnamese system dialogs (which
is what the user sees right next to Vorssaint's permission prompts).

### Proper nouns
Apple/macOS system terms follow **Apple's own Vietnamese localization**,
not a fresh translation:
- `Dock` → kept as **"Dock"**
- `Finder` → kept as **"Finder"**
- `Trash` → **"Thùng rác"**
- `Homebrew` → kept (brand name)

Vorssaint's own coined feature names get translated naturally and
idiomatically (not word-for-word) — this matches how every existing language
already treats them. Example, `Dock Preview` is the one Vorssaint feature
name every existing language (es/fr/pt-BR) leaves untranslated, because it's
read as a Dock-branded proper noun rather than a description; that precedent
carries over to `vi`.

**Calibration rule for translators (human or agent):** before naming a
recurring feature/concept, grep the field across the other language files
(`Localizations/*.swift` for the main catalog; the sibling `static let xx =`
blocks in the same file for feature catalogs) to see how the other 12
languages already resolved it, and produce a natural Vietnamese equivalent in
that same spirit rather than a literal one.

### Grammatical number
Vietnamese nouns don't inflect for plural. Existing singular/plural field
pairs (e.g. `shelfTooltipImageSingular` / `shelfTooltipImagePlural`) still
both need natural, correct wording — they will often differ only in how the
count is phrased, not in noun form. Every format placeholder (`%d`, `%@`,
etc.) must be preserved exactly, since `MetricsTests.swift` checks for their
presence per language.

### Shipping bar
`vi` is only added to `AppLanguage.allCases` once every field in both catalog
surfaces has a real, hand-quality Vietnamese entry — no partial/WIP language
ships to users. Work itself lands in incremental commits on the
`i18n/vietnamese-localization` branch.
