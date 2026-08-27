// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import NaturalLanguage

/// Pure logic for Live Translation: coordinate conversions between Vision's
/// normalized boxes and panel-local points, language resolution, and the
/// dedupe/interval helpers the capture loop relies on. No AppKit/Vision/
/// Translation imports so the unit test harness compiles it standalone -
/// NaturalLanguage is fine here since, unlike those, it needs no downloaded
/// model or UI context to run.
enum LiveTranslationSupport {

    struct RecognizedLine: Equatable {
        /// Vision's normalized box: origin bottom-left, unit square.
        let boundingBox: CGRect
        let text: String
    }

    struct TranslatedLine: Identifiable, Equatable {
        let id: Int
        /// The union of every source line this entry groups - a paragraph's
        /// worth of lines renders as one box, not one per original line.
        let boundingBox: CGRect
        /// How many source lines `boundingBox` spans, so the renderer can
        /// divide back down to a single line's height for font sizing and
        /// wrap the text across that many rows instead of drawing one giant
        /// line.
        let rowCount: Int
        let original: String
        let translated: String
    }

    /// Converts a Vision-normalized, bottom-left-origin box into panel-local,
    /// top-left-origin points, for placing a chip over the source text.
    static func chipFrame(boundingBox: CGRect, panelSize: CGSize) -> CGRect {
        CGRect(x: boundingBox.minX * panelSize.width,
               y: (1 - boundingBox.maxY) * panelSize.height,
               width: boundingBox.width * panelSize.width,
               height: boundingBox.height * panelSize.height)
    }

    /// How far each chip (indexed the same as `frames`) can grow sideways
    /// before it would run into another chip sitting in a genuinely
    /// different column at a similar height - the mirror of
    /// `maxChipHeights`'s downward cap, but for the case a single-row
    /// chip's own "grow into open space" search otherwise has no way to
    /// know about: a two-column page layout, where a narrow sidebar chip
    /// growing to fill "whatever's to the right, up to the panel edge"
    /// would otherwise run straight into the separate content column
    /// sitting right next to it - that assumption only holds when nothing
    /// else actually occupies that space. A chip's neighbor is whichever
    /// other chip starts to its right *and* vertically overlaps it (so a
    /// line further down the very same column is correctly ignored - only
    /// a same-row, different-column line counts); a chip with no such
    /// neighbor is only capped by the panel's own right edge.
    static func maxChipWidths(frames: [CGRect], panelWidth: CGFloat, gap: CGFloat) -> [CGFloat] {
        frames.indices.map { index in
            let own = frames[index]
            let nextLeft = frames.indices
                .filter { other in
                    other != index && frames[other].minX > own.minX &&
                    max(own.minY, frames[other].minY) < min(own.maxY, frames[other].maxY)
                }
                .map { frames[$0].minX }
                .min()
            let limit = (nextLeft ?? panelWidth) - own.minX - gap
            return max(own.width, limit)
        }
    }

    /// How far each chip (indexed the same as `frames`) can grow downward
    /// before it would run into another chip sitting in the same column -
    /// the vertical mirror of `maxChipWidths`. Growing a chip's font/height
    /// to fit a longer translation is only safe up to whatever real open
    /// space exists below it; past that, it would paint over a chip that's
    /// already there. A chip's neighbor is whichever other chip starts
    /// below it *and* overlaps it horizontally (so a chip further along in
    /// the very same row is correctly ignored - only a same-column chip
    /// further down counts); a chip with no such neighbor is only capped by
    /// the panel's own bottom edge.
    static func maxChipHeights(frames: [CGRect], panelHeight: CGFloat, gap: CGFloat) -> [CGFloat] {
        frames.indices.map { index in
            let own = frames[index]
            let nextTop = frames.indices
                .filter { other in
                    other != index && frames[other].minY > own.minY &&
                    max(own.minX, frames[other].minX) < min(own.maxX, frames[other].maxX)
                }
                .map { frames[$0].minY }
                .min()
            let limit = (nextTop ?? panelHeight) - own.minY - gap
            return max(own.height, limit)
        }
    }

    /// A stable-enough-for-one-run key: two ticks with the same recognized
    /// text (in the same order) skip re-translating, since nothing changed.
    static func joinedTextHash(_ lines: [RecognizedLine]) -> Int {
        var hasher = Hasher()
        for line in lines { hasher.combine(line.text) }
        return hasher.finalize()
    }

    static func sanitizedInterval(_ raw: Double) -> TimeInterval {
        min(max(raw, 0.5), 3.0)
    }

    /// Empty override follows the system's own preferred language (the
    /// caller passes `AppLanguage.systemDefault`, not Vorssaint's own
    /// display language - the two are independent settings, and someone
    /// running Vorssaint's chrome in one language while working in another
    /// should still get a sensible translation target rather than one tied
    /// to an unrelated UI choice). Otherwise the saved language wins as long
    /// as it is still a recognized one.
    static func resolvedTargetLanguage(overrideRaw: String, fallback: AppLanguage) -> AppLanguage {
        overrideRaw.isEmpty ? fallback : (AppLanguage(rawValue: overrideRaw) ?? fallback)
    }

    /// Empty override means auto-detect (nil); Vision/the translator pick the
    /// source language per line.
    static func resolvedSourceLanguage(overrideRaw: String) -> AppLanguage? {
        overrideRaw.isEmpty ? nil : AppLanguage(rawValue: overrideRaw)
    }

    /// Google Cloud Translation's v2 API wants ISO-639-1 base codes for most
    /// languages and a region-qualified code only for Chinese, where the
    /// region is what disambiguates script (confirmed against Google's
    /// supported-languages docs - "zh-CN"/"zh-TW", not the "zh-Hans"/
    /// "zh-Hant" script tags Apple's Translation framework uses).
    static func googleLanguageTag(_ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "zh-CN"
        case .zhTW, .zhHK: return "zh-TW"
        default:
            let base = language.rawValue.split(separator: "-").first ?? Substring(language.rawValue)
            return String(base)
        }
    }

    /// Maps an NLLanguageRecognizer result (a BCP-47-ish code such as "en" or
    /// "zh-Hans") to one of our supported languages. Returns nil for anything
    /// we don't have a dedicated case for, so callers can fall back to
    /// whatever they were already using rather than switching to a guess.
    static func appLanguage(forDetectedCode code: String) -> AppLanguage? {
        switch code {
        case "en": return .enUS
        case "pt": return .ptBR
        case "tr": return .tr
        case "ru": return .ru
        case "es": return .es
        case "de": return .de
        case "fr": return .fr
        case "it": return .it
        case "ja": return .ja
        case "ko": return .ko
        case "zh-Hans": return .zhHans
        case "zh-Hant": return .zhTW
        default: return nil
        }
    }

    /// Detects the dominant language of `text`, restricted to languages this
    /// feature actually supports and gated by both a minimum length and a
    /// minimum confidence. Unconstrained, un-gated detection on short OCR
    /// snippets is exactly what misidentified mixed Chinese/English UI text
    /// as Turkish: a few garbled characters can score highest on a language
    /// nowhere near the source text once every language is a candidate.
    /// Constraining the candidate set to what Vorssaint supports, and
    /// requiring some real signal before trusting the result, are both
    /// standard NLLanguageRecognizer usage for exactly this failure mode.
    static func detectLanguage(from text: String) -> AppLanguage? {
        guard text.count >= minimumDetectionLength else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = supportedNLLanguages
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1)
            .max(by: { $0.value < $1.value }),
            confidence >= minimumDetectionConfidence
        else { return nil }
        return appLanguage(forDetectedCode: language.rawValue)
    }

    private static let minimumDetectionLength = 12
    private static let minimumDetectionConfidence = 0.5
    private static let supportedNLLanguages: [NLLanguage] = [
        "en", "pt", "tr", "ru", "es", "de", "fr", "it", "ja", "ko", "zh-Hans", "zh-Hant",
    ].map(NLLanguage.init(rawValue:))

    /// A line's own script can identify some languages reliably even from
    /// very short text - "首页", two characters, is unambiguously Chinese by
    /// script alone. That's exactly the case `detectLanguage`'s statistical
    /// model struggles with, and checking script first (falling through to
    /// it only for Latin-script/ambiguous text) is what makes per-line
    /// classification actually work for short UI labels instead of only
    /// full sentences.
    static func resolvedLanguage(for text: String) -> AppLanguage? {
        scriptLanguage(for: text) ?? detectLanguage(from: text)
    }

    private static func scriptLanguage(for text: String) -> AppLanguage? {
        var hasKana = false
        var hasHangul = false
        var hasHan = false
        var hasCyrillic = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF: hasKana = true
            case 0xAC00...0xD7A3: hasHangul = true
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: hasHan = true
            case 0x0400...0x04FF: hasCyrillic = true
            default: break
            }
        }
        // Kana is Japan-specific and checked first: Japanese text routinely
        // mixes kanji (Han) with kana, so a line with any kana at all is
        // Japanese regardless of how much Han it also contains.
        if hasKana { return .ja }
        if hasHangul { return .ko }
        if hasCyrillic { return .ru }
        if hasHan {
            // Han-only text is Chinese, but script alone can't tell
            // Simplified from Traditional - defer to the statistical model
            // for just that narrower question (far more reliable than for
            // wide-open language ID), defaulting to Simplified if even that
            // is inconclusive.
            return detectLanguage(from: text) ?? .zhHans
        }
        return nil
    }

    /// Groups OCR lines into paragraphs by geometric proximity: consecutive
    /// lines stacked closely with a shared left edge continue the same
    /// paragraph; a bigger vertical gap or a different starting position
    /// begins a new one. A line with no close neighbor just ends up a
    /// "group of one" - the same mechanism handles a page of dense body text
    /// and a page of short, separated UI labels without a separate mode.
    ///
    /// Vision's own document-layout API (RecognizeDocumentsRequest) does
    /// this natively and far more reliably, but it needs macOS 26 - this
    /// heuristic is what covers this feature's actual floor, macOS 15.
    static func groupIntoParagraphs(_ lines: [RecognizedLine]) -> [[RecognizedLine]] {
        // Vision's box origin is bottom-left, so "topmost" is the largest maxY.
        let sorted = lines.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        var groups: [[RecognizedLine]] = []
        for line in sorted {
            if let lastIndex = groups.indices.last, let last = groups[lastIndex].last,
               continuesParagraph(previous: last, next: line,
                                  groupMaxWidth: groups[lastIndex].map(\.boundingBox.width).max() ?? 0) {
                groups[lastIndex].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups
    }

    /// Vertical proximity and shared left edge alone can't tell a genuinely
    /// wrapped paragraph continuation apart from a tightly-packed vertical
    /// list of separate, complete items (a stack of nav links or button
    /// labels routinely has both) - both look identical on those two signals
    /// alone. The distinguishing signal is *why* a line ended where it did:
    /// a wrapped paragraph line runs most of the way to the block's own
    /// established width before breaking, because it ran out of room: a
    /// short, complete line (each item in a list) stops well short of that
    /// because there was nothing more to say, not because of a width limit.
    /// Requiring `previous` to already span close to the group's widest line
    /// so far is what keeps a paragraph's wrapped lines merging while
    /// leaving a list of short, unrelated-length items correctly split into
    /// separate single-line groups - this is what produced one link's
    /// translation bleeding onto the next as an apparent stray line break,
    /// and squeezed an unrelated block's-worth of translated text into one
    /// font size, before this check existed.
    ///
    /// On a real page mixing headings, body paragraphs, bullet lists, and a
    /// blockquote, that width check alone still isn't enough: a paragraph's
    /// own last line can legitimately be nearly full-width too, so nothing
    /// stops a short heading sitting right below it from getting glued on -
    /// producing one union box spanning two visually and semantically
    /// unrelated blocks, whose translated text then renders as one
    /// overlapping blob across both. A genuine paragraph is typographically
    /// uniform - consecutive lines share the same font size, so their OCR
    /// box heights stay close - while a transition into a differently-styled
    /// block (most often a heading) comes with a real size change. Requiring
    /// `previous` and `next` to be close in height is what catches that
    /// case: it doesn't depend on either line's width, so it still applies
    /// after the width check above has already passed.
    ///
    /// Even that combination can still misfire on a uniform vertical list
    /// (a nav sidebar's own buttons, all one font size, all roughly the same
    /// length) - the height check contributes nothing there, since every
    /// row genuinely is the same size, and moderately-similar-length labels
    /// can occasionally satisfy the width check too. Since real prose in
    /// this feature's actual use (translating a UI/document screenshot) is
    /// reliably far more tightly leaded than an interactive list's own row
    /// padding, and its lines reliably run much closer to true full width
    /// than a list item's short, varying-length label does, these
    /// thresholds are deliberately strict - erring toward leaving a
    /// genuine paragraph line split into its own group (worse: it shows up
    /// translated on its own, a smaller regression) rather than merging
    /// unrelated list rows into one overlapping chip (worse: it visibly
    /// breaks).
    private static func continuesParagraph(previous: RecognizedLine, next: RecognizedLine,
                                           groupMaxWidth: CGFloat) -> Bool {
        let lineHeight = max(previous.boundingBox.height, next.boundingBox.height)
        let verticalGap = previous.boundingBox.minY - next.boundingBox.maxY
        let leftEdgeDelta = abs(previous.boundingBox.minX - next.boundingBox.minX)
        guard verticalGap < lineHeight * 0.5, leftEdgeDelta < 0.04 else { return false }
        guard previous.boundingBox.width >= groupMaxWidth * 0.9 else { return false }
        let heightRatio = min(previous.boundingBox.height, next.boundingBox.height)
            / max(previous.boundingBox.height, next.boundingBox.height)
        return heightRatio >= 0.85
    }

    static func unionBoundingBox(_ lines: [RecognizedLine]) -> CGRect {
        guard let first = lines.first else { return .zero }
        return lines.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    static func joinedParagraphText(_ lines: [RecognizedLine]) -> String {
        lines.map(\.text).joined(separator: " ")
    }

    /// Paragraph groups split for translation: `passthrough` covers any group
    /// already in the target language (shown as-is, nothing to translate)
    /// plus any group in some third, minority language - left out of
    /// `toTranslate` rather than sent through the wrong-language session and
    /// mistranslated, but still returned (not silently dropped) so nothing
    /// disappears from a page that mixes several source languages. Groups
    /// are classified by their own *joined* text, not per-line, since more
    /// text means more reliable detection - exactly what short individual
    /// OCR lines struggled with. `primarySource` comes back nil only when
    /// there's text needing translation but nothing in it could be
    /// confidently classified yet - callers should wait for a clearer OCR
    /// pass rather than starting a session with a guessed source, which is
    /// what used to leave sessions stuck after a resize landed on sparse or
    /// ambiguous content.
    static func classifyParagraphGroups(_ groups: [[RecognizedLine]], target: AppLanguage)
        -> (toTranslate: [[RecognizedLine]], passthrough: [[RecognizedLine]], primarySource: AppLanguage?) {
        guard !groups.isEmpty else { return ([], [], nil) }
        let classified = groups.map { group in
            (group: group, language: resolvedLanguage(for: joinedParagraphText(group)))
        }
        let alreadyTarget = classified.filter { $0.language == target }.map(\.group)
        let needsTranslation = classified.filter { $0.language != target }
        guard !needsTranslation.isEmpty else { return ([], alreadyTarget, nil) }

        var counts: [AppLanguage: Int] = [:]
        for item in needsTranslation {
            guard let language = item.language else { continue }
            counts[language, default: 0] += 1
        }
        guard let primary = counts.max(by: { $0.value < $1.value })?.key else {
            return (needsTranslation.map(\.group), alreadyTarget, nil)
        }
        let toTranslate = needsTranslation
            .filter { $0.language == nil || $0.language == primary }
            .map(\.group)
        let minorityPassthrough = needsTranslation
            .filter { $0.language != nil && $0.language != primary }
            .map(\.group)
        return (toTranslate, alreadyTarget + minorityPassthrough, primary)
    }

    /// A block's own font size: its box height divided back down to a single
    /// row, so a five-line paragraph's box (five rows tall) doesn't inflate
    /// the text the way sizing straight off the box height would.
    static func blockFontSize(chipHeight: CGFloat, rowCount: Int) -> CGFloat {
        max(8, min(96, chipHeight / CGFloat(max(rowCount, 1)) * 0.85))
    }

    /// Converts a chip's rect (top-left-origin, in the panel's own point
    /// space) into the rect to crop from a same-region image at its own
    /// pixel resolution. CGImage's `cropping(to:)` takes top-left-origin
    /// coordinates directly - confirmed against a shipped reference
    /// implementation after this earlier flipped to bottom-left based on a
    /// misremembered convention, which would have cropped the wrong region
    /// vertically. `outset` grows the crop slightly beyond the chip itself,
    /// matching the small margin the visible background pill draws beyond
    /// the text.
    static func blurCropRect(chipRect: CGRect, panelSize: CGSize, imageSize: CGSize, outset: CGFloat) -> CGRect {
        guard panelSize.width > 0, panelSize.height > 0 else { return .zero }
        let scaleX = imageSize.width / panelSize.width
        let scaleY = imageSize.height / panelSize.height
        let expanded = chipRect.insetBy(dx: -outset, dy: -outset)
        let pixelRect = CGRect(x: expanded.minX * scaleX, y: expanded.minY * scaleY,
                               width: expanded.width * scaleX, height: expanded.height * scaleY)
        return pixelRect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// Places the control pill just above the translated region, flipping
    /// below it when there isn't room, and always clamped to the screen's
    /// visible frame. Coordinates are Cocoa's (origin bottom-left).
    static func pillFrame(anchorRect: CGRect, pillSize: CGSize, screenVisibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 10
        let usable = screenVisibleFrame.insetBy(dx: 8, dy: 8)

        var x = anchorRect.midX - pillSize.width / 2
        x = min(max(x, usable.minX), max(usable.minX, usable.maxX - pillSize.width))

        var y = anchorRect.maxY + gap
        if y + pillSize.height > usable.maxY {
            y = anchorRect.minY - gap - pillSize.height
        }
        y = min(max(y, usable.minY), max(usable.minY, usable.maxY - pillSize.height))

        return CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height)
    }
}
