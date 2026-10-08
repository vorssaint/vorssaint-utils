// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SwiftUI
import VMStatisticsCompat

enum ClipboardFeatureTests {
    /// Runs the production `pasteIntoPreviousApp` with a target app, the
    /// Accessibility grant, the beep and the paste all recorded as events.
    final class QuickPasteHost {
        final class App {
            let isTerminated: Bool
            init(isTerminated: Bool) { self.isTerminated = isTerminated }
            func activate(options: [Int]) { host?.events.append("activate") }
        }
        typealias NSRunningApplication = App
        enum Sound {
            static func beep() { host?.events.append("beep") }
        }
        typealias NSSound = Sound
        final class Access {
            static let shared = Access()
            func requestAccessibility() { host?.events.append("prompt") }
        }
        typealias Permissions = Access
        final class Queue {
            static let main = Queue()
            func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) { work() }
        }
        typealias DispatchQueue = Queue
        static var host: QuickPasteHost?
        var events: [String] = []
        var trusted = true
        var promptedForAccessibility = false
        init() { Self.host = self }
        func AXIsProcessTrusted() -> Bool { trusted }
        static func postPasteShortcut() { host?.events.append("paste") }
    }

    /// Runs the production source check against the apps that came to the
    /// front since the last look.
    final class SourceHost {
        var historyIsRunning = true
        var candidates: Set<String> = []
        var lookup: Set<String> = []
        var historyPanelWasKey = false
        let ownBundleID: String? = "com.vorssaint.utils"
        static var front: String?
        static func frontmostBundleID() -> String? { front }
    }

    /// Runs the production link cleaning poll against a private pasteboard
    /// standing in for the general one.
    enum URLCleanerHost {
        enum NSPasteboard { static let general = AppKit.NSPasteboard.withUniqueName() }
        final class PollToken { let isCancelled = false }
        struct PollResult {
            let changeCount: Int
            let cleaned: URLCleaning.Result?
        }
        static let urlType = AppKit.NSPasteboard.PasteboardType("public.url")
        static let rules = URLCleaning.Rules.none
    }

    static func run(_ suite: TestSuite) {
        ClipboardPreviewContract.run(suite)
        let source = SourceHost()
        func sourceCheck(declared: String? = nil, remote: Bool = false,
                         panelIsKey: Bool = false, panelClosing: Bool = false)
            -> (excluded: Bool, bundleID: String?, fromHistoryPanel: Bool) {
            source.sourceSinceLastCheck(declared: declared, remote: remote,
                                        historyPanelIsKey: panelIsKey, historyPanelClosing: panelClosing)
        }
        source.candidates = ["com.apple.Safari"]
        let single = sourceCheck()
        suite.expect(single.bundleID == "com.apple.Safari" && !single.excluded,
                     "a copy made while one app held the front records that app")
        source.candidates = ["com.apple.Safari", "com.apple.Notes"]
        suite.expect(sourceCheck().bundleID == nil,
                     "a copy made while two apps took turns in front records no app rather than a guess")
        SourceHost.front = "com.apple.Notes"
        source.candidates = []
        _ = sourceCheck()
        suite.expect(sourceCheck().bundleID == "com.apple.Notes",
                     "the next check starts from the app in front")
        source.lookup = ["com.example.skipped"]
        source.candidates = ["com.example.skipped"]
        suite.expect(sourceCheck().excluded, "a copy from a skipped app is still left out")
        source.candidates = ["com.example.front"]
        let declaredSkipped = sourceCheck(declared: "com.example.skipped")
        suite.expect(declaredSkipped.excluded,
                     "a copy whose pasteboard names a skipped app is left out even when that app never held the front")
        source.candidates = ["com.example.front"]
        let declaredOther = sourceCheck(declared: "com.example.writer")
        suite.expect(!declaredOther.excluded && declaredOther.bundleID == "com.example.writer",
                     "a copy naming an app that is not skipped is still recorded under that app")
        source.lookup = []
        source.candidates = ["com.apple.Safari"]
        suite.expect(sourceCheck(declared: "com.vorssaint.utils").bundleID == nil,
                     "text Vorssaint copies itself, such as recognized text, is not credited to the app in front")
        source.candidates = ["com.apple.Safari"]
        suite.expect(sourceCheck(declared: "com.apple.Notes").bundleID == "com.apple.Notes",
                     "an app that names itself on the pasteboard is believed over the app in front")
        source.candidates = ["com.example.front"]
        let emptyMark = sourceCheck(declared: "")
        source.candidates = ["com.example.front"]
        let blankMark = sourceCheck(declared: " \n")
        source.candidates = ["com.example.front"]
        let oversizedMark = sourceCheck(declared: String(repeating: "a", count: 256))
        suite.expect(emptyMark.bundleID == "com.example.front" && blankMark.bundleID == "com.example.front"
                     && oversizedMark.bundleID == "com.example.front",
                     "an empty or oversized source mark names no app and leaves the guess to the app in front")
        source.candidates = ["com.example.front"]
        let remoteCopy = sourceCheck(remote: true)
        source.candidates = ["com.example.front"]
        let remoteNamed = sourceCheck(declared: "com.example.writer", remote: true)
        suite.expect(remoteCopy.bundleID == nil && !remoteCopy.excluded && remoteNamed.bundleID == nil,
                     "a copy that came from another device is recorded without naming an app on this Mac")
        source.candidates = ["com.example.front"]
        let panelCopy = sourceCheck(panelIsKey: true)
        suite.expect(panelCopy.bundleID == nil && panelCopy.fromHistoryPanel && !panelCopy.excluded,
                     "a copy made in the history's own panel is not credited to the app behind it")
        source.candidates = ["com.example.front"]
        let closingPanelCopy = sourceCheck(panelIsKey: true, panelClosing: true)
        suite.expect(closingPanelCopy.bundleID == nil && closingPanelCopy.fromHistoryPanel,
                     "a copy made in the panel just before it closed still counts as the panel's")
        source.candidates = ["com.example.front"]
        let afterClosing = sourceCheck()
        suite.expect(afterClosing.bundleID == "com.example.front" && !afterClosing.fromHistoryPanel,
                     "a copy made in the app behind right after the panel closed is credited to that app")
        source.candidates = ["com.example.front"]
        _ = sourceCheck(panelIsKey: true)
        source.candidates = ["com.example.front"]
        let missedClosing = sourceCheck()
        suite.expect(missedClosing.bundleID == nil && missedClosing.fromHistoryPanel,
                     "when the panel closed without its own check, the first check after still counts as the panel's")
        source.candidates = ["com.example.front"]
        let afterPanel = sourceCheck()
        suite.expect(afterPanel.bundleID == "com.example.front" && !afterPanel.fromHistoryPanel,
                     "once the panel is gone the app in front is credited again")
        source.candidates = ["com.example.front"]
        let namedInPanel = sourceCheck(declared: "com.example.writer", panelIsKey: true)
        suite.expect(namedInPanel.bundleID == "com.example.writer" && !namedInPanel.fromHistoryPanel,
                     "an app that names itself is believed even while the panel holds the keys")
        source.historyIsRunning = false
        source.candidates = ["com.apple.Safari"]
        suite.expect(sourceCheck() == (false, nil, false), "nothing is named while the history is off")
        // The link cleaner rewrites a copy in place; the app it named stays.
        let cleanerBoard = URLCleanerHost.NSPasteboard.general
        cleanerBoard.clearContents()
        cleanerBoard.setString("com.example.reader", forType: .source)
        cleanerBoard.setString("https://example.com/path?utm_source=news&id=42", forType: .string)
        let signedRewrite = URLCleanerHost.pollPasteboard(sinceChangeCount: -1, token: URLCleanerHost.PollToken())
        suite.expect(signedRewrite?.cleaned?.url == "https://example.com/path?id=42"
                     && cleanerBoard.string(forType: .string) == "https://example.com/path?id=42"
                     && cleanerBoard.string(forType: .source) == "com.example.reader",
                     "the link cleaner's rewrite keeps the app the copy named as its source")
        cleanerBoard.clearContents()
        cleanerBoard.setString("https://example.com/path?utm_source=news&id=42", forType: .string)
        let unsignedRewrite = URLCleanerHost.pollPasteboard(sinceChangeCount: -1, token: URLCleanerHost.PollToken())
        suite.expect(unsignedRewrite?.cleaned != nil
                     && cleanerBoard.string(forType: .string) == "https://example.com/path?id=42"
                     && cleanerBoard.string(forType: .source) == nil,
                     "a rewritten copy that named no app gains no mark, so the app that copied it is still credited")
        cleanerBoard.releaseGlobally()
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        func expectFormat(_ format: String, _ expected: [String], _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) {
            let actual = TestFormat.parse(format)?.conversions ?? ["invalid format"]
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        // MARK: Clipboard history search

        let clipboardCandidates = [
            ClipboardHistorySearchCandidate(index: 0, text: "Deploy checklist final", isPinned: false),
            ClipboardHistorySearchCandidate(index: 1, text: "Token cleanup note", isPinned: true),
            ClipboardHistorySearchCandidate(index: 2, text: "Final database deploy plan", isPinned: false),
            ClipboardHistorySearchCandidate(index: 3, text: "Reunião com João", isPinned: false),
        ]
        suite.expect(ClipboardHistorySearch.matches("Reunião com João", query: "reuniao joao"),
               "clipboard search ignores case and accents")
        suite.expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "deploy final") == [0, 2],
               "clipboard search matches multiple words in any order and ranks prefix matches first")
        suite.expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "cleanup token") == [1],
               "clipboard search matches pinned entries with reordered query terms")
        suite.expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "missing") == [],
               "clipboard search returns no results for unmatched terms")

        // MARK: Clipboard JSON preview

        let copiedJSON = #"{"b":1.50,"a":[1e3,{},[ ]],"s":"x, {y}: \"z\"","n":null}"#
        let laidOut = #"""
        {
          "b": 1.50,
          "a": [
            1e3,
            {},
            []
          ],
          "s": "x, {y}: \"z\"",
          "n": null
        }
        """#
        expectEqual(ClipboardJSONFormat.pretty(copiedJSON) ?? "nil", laidOut,
                    "copied JSON is laid out with its key order, numbers and strings untouched")
        expectEqual(ClipboardJSONFormat.pretty(laidOut) ?? "nil", laidOut,
                    "laying out JSON twice changes nothing")
        suite.expect(ClipboardJSONFormat.pretty(#"{"a": }"#) == nil
                     && ClipboardJSONFormat.pretty("[1] is the first note") == nil
                     && ClipboardJSONFormat.pretty("42") == nil,
                     "text that is not a JSON object or array keeps its own layout")

        let escapedJSON = #"{"path":"C:\\","name":"café 日本","quote":["\\\"",1]}"#
        let escapedLaidOut = #"""
        {
          "path": "C:\\",
          "name": "café 日本",
          "quote": [
            "\\\"",
            1
          ]
        }
        """#
        expectEqual(ClipboardJSONFormat.pretty(escapedJSON) ?? "nil", escapedLaidOut,
                    "a backslash escaped right before a closing quote ends its string, non-ASCII text intact")

        // Where JSONSerialization takes a trailing comma, the layout keeps it
        // with no empty line before the bracket, whatever the input's breaks.
        let trailingComma = "{\r\n\t\"a\": 1,\r\n\t\"b\": [\r\n\t\t2,\t\r\n\t],\r\n}"
        let takesTrailingComma = (try? JSONSerialization.jsonObject(with: Data(trailingComma.utf8))) != nil
        expectEqual(ClipboardJSONFormat.pretty(trailingComma) ?? "nil",
                    takesTrailingComma ? "{\n  \"a\": 1,\n  \"b\": [\n    2,\n  ],\n}" : "nil",
                    "CRLF and tab layout with a trailing comma keeps the comma and leaves no empty line")

        // The limit counts bytes: two-byte letters just past it are too large
        // even though they are far fewer characters.
        let letters = (ClipboardJSONFormat.maxBytes - 4) / 2
        let atByteLimit = "[\"" + String(repeating: "\u{E9}", count: letters) + "\"]"
        let pastByteLimit = "[\"" + String(repeating: "\u{E9}", count: letters + 1) + "\"]"
        suite.expect(atByteLimit.utf8.count == ClipboardJSONFormat.maxBytes
                     && pastByteLimit.count < ClipboardJSONFormat.maxBytes,
                     "the byte limit fixtures sit at the limit in bytes and far under it in characters")
        suite.expect(ClipboardJSONFormat.pretty(atByteLimit) != nil,
                     "JSON right at the byte limit is still laid out")
        suite.expect(ClipboardJSONFormat.pretty(pastByteLimit) == nil,
                     "JSON past the byte limit keeps its own layout, however few characters it has")

        // Deep nesting indents every line again, so a small input can lay out
        // to many times its size.
        func nestedJSON(_ count: Int) -> String {
            String(repeating: "[", count: 64) + String(repeating: "1,", count: count) + "1"
                + String(repeating: "]", count: 64)
        }
        suite.expect(ClipboardJSONFormat.pretty(nestedJSON(4_000)) != nil,
                     "deeply nested JSON whose layout stays under the output bound is laid out")
        suite.expect(ClipboardJSONFormat.pretty(nestedJSON(12_000)) == nil,
                     "deeply nested JSON whose layout passes the output bound keeps its own layout")

        // MARK: Clipboard image text recognition

        suite.expect(ClipboardImageRecognition.decodeMaxPixelSize(width: 6_016, height: 3_384) == 6_016,
                     "a 6K screenshot is read at full size, as Screen OCR reads its capture")
        let scrollingSide = ClipboardImageRecognition.decodeMaxPixelSize(width: 3_024, height: 20_000)
        let scrollingPixels = Double(scrollingSide) * Double(scrollingSide) * 3_024 / 20_000
        suite.expect(scrollingPixels <= Double(ClipboardImageRecognition.maxPixels),
                     "a picture past the area bound is scaled down to it")
        suite.expect(scrollingPixels > 0.99 * Double(ClipboardImageRecognition.maxPixels),
                     "a picture past the area bound keeps nearly all of that area")

        // MARK: Clipboard history search tokens and highlight ranges

        suite.expect(ClipboardHistorySearch.searchTokens(for: "  deploy   final  ") == ["deploy", "final"],
                     "search tokens split query words and trim whitespace")
        suite.expect(ClipboardHistorySearch.searchTokens(for: "   ").isEmpty,
                     "search tokens for whitespace query is empty")
        suite.expect(ClipboardHistorySearch.searchTokens(for: "").isEmpty,
                     "search tokens for empty query is empty")

        // Exact substring match (e.g. searching "BC" inside "ABCD")
        let abcdRanges = ClipboardHistorySearch.highlightRanges(in: "ABCD", tokens: ["BC"])
        suite.expect(abcdRanges.count == 1 && "ABCD"[abcdRanges[0]] == "BC",
                     "highlight ranges finds exact substring")

        // Multi-token matches
        let deployRanges = ClipboardHistorySearch.highlightRanges(in: "Deploy checklist final", tokens: ["deploy", "final"])
        suite.expect(deployRanges.count == 2
                     && "Deploy checklist final"[deployRanges[0]] == "Deploy"
                     && "Deploy checklist final"[deployRanges[1]] == "final",
                     "highlight ranges finds multiple tokens in any order")

        // Case and accent folding (precomposed and decomposed)
        let accentRanges = ClipboardHistorySearch.highlightRanges(in: "Reunião com João", tokens: ["reuniao", "joao"])
        suite.expect(accentRanges.count == 2
                     && "Reunião com João"[accentRanges[0]] == "Reunião"
                     && "Reunião com João"[accentRanges[1]] == "João",
                     "highlight ranges folds accents and case")
        let decomposedText = "Reunia\u{0303}o"
        let decomposedRanges = ClipboardHistorySearch.highlightRanges(in: decomposedText, tokens: ["reuniao"])
        suite.expect(decomposedRanges.count == 1 && decomposedText[decomposedRanges[0]] == "Reunia\u{0303}o",
                     "highlight ranges folds decomposed accents")

        // German ß / ss matching
        let eszettRanges = ClipboardHistorySearch.highlightRanges(in: "Straße", tokens: ["strasse"])
        suite.expect(eszettRanges.count == 1 && "Straße"[eszettRanges[0]] == "Straße",
                     "highlight ranges matches German eszett with ss")

        // Emoji / grapheme clusters
        let emojiRanges = ClipboardHistorySearch.highlightRanges(in: "🚀 Launch satellite", tokens: ["launch"])
        suite.expect(emojiRanges.count == 1 && "🚀 Launch satellite"[emojiRanges[0]] == "Launch",
                     "highlight ranges handles emojis and grapheme clusters")

        // Overlapping tokens
        let overlapRanges = ClipboardHistorySearch.highlightRanges(in: "abc", tokens: ["ab", "bc"])
        suite.expect(overlapRanges.count == 2
                     && "abc"[overlapRanges[0]] == "ab"
                     && "abc"[overlapRanges[1]] == "bc",
                     "highlight ranges supports overlapping tokens")

        // Edge cases: token longer than text, empty text, empty token, non-matching
        suite.expect(ClipboardHistorySearch.highlightRanges(in: "hi", tokens: ["longerthanhi"]).isEmpty,
                     "highlight ranges returns empty for token longer than text")
        suite.expect(ClipboardHistorySearch.highlightRanges(in: "", tokens: ["test"]).isEmpty,
                     "highlight ranges returns empty for empty text")
        suite.expect(ClipboardHistorySearch.highlightRanges(in: "test", tokens: []).isEmpty,
                     "highlight ranges returns empty for empty tokens")
        suite.expect(ClipboardHistorySearch.highlightRanges(in: "test", tokens: ["", "  "]).isEmpty,
                     "highlight ranges ignores empty/whitespace tokens")
        suite.expect(ClipboardHistorySearch.highlightRanges(in: "test", tokens: ["nomatch"]).isEmpty,
                     "highlight ranges returns empty when no tokens match")

        // Only the matches change style, so the rest of a row keeps the font
        // and color modifiers of its text.
        typealias HighlightColor = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        typealias HighlightFont = AttributeScopes.SwiftUIAttributes.FontAttribute
        let styled = SearchHighlightText.highlighted("Reunião com João", tokens: ["joao"], fontSize: 12)
        let styledRuns = styled.runs.map { (String(styled[$0.range].characters), $0[HighlightColor.self], $0[HighlightFont.self]) }
        suite.expect(styledRuns.count == 2
                     && styledRuns[0].0 == "Reunião com " && styledRuns[0].1 == nil && styledRuns[0].2 == nil
                     && styledRuns[1].0 == "João" && styledRuns[1].1 == Color.accentColor && styledRuns[1].2 != nil,
                     "a highlighted row styles only its matches and leaves the rest to its text's modifiers")
        let weightOnly = SearchHighlightText.highlighted("Reunião com João", tokens: ["joao"], fontSize: 12,
                                                         highlightColor: nil)
        suite.expect(weightOnly.runs.allSatisfy { $0[HighlightColor.self] == nil }
                     && weightOnly.runs.filter { $0[HighlightFont.self] != nil }.count == 1,
                     "without a highlight color a match keeps the text's color and changes only its weight")
        let longPreview = String(repeating: "release notes ", count: 100)
        let longStyled = SearchHighlightText.highlighted(longPreview, tokens: ["release"], fontSize: 12)
        suite.expect(SearchHighlightText.excerpt(longPreview).count == SearchHighlightText.visibleCharacters + 1
                     && SearchHighlightText.excerpt(longPreview).hasSuffix("…")
                     && SearchHighlightText.excerpt("short") == "short"
                     && longStyled.characters.count == SearchHighlightText.visibleCharacters + 1
                     && longStyled.runs.filter { $0[HighlightFont.self] != nil }.count == 36,
                     "a long preview is searched and styled only as far as a row can show")
        // MARK: Clipboard history search cache & ranking parity

        let sampleTexts = [
            "Deploy checklist final",
            "Token cleanup note",
            "Final database deploy plan",
            "Reunião com João",
            "Серверная конфигурация nginx",
            "İstanbul boğazı turu",
            "Lorem ipsum dolor sit amet",
            "Multi\nline\ttext\rwith  extra   whitespace",
            "Exact Match Only",
            "prefix matching candidate",
        ]
        var testEntries = sampleTexts.enumerated().map { index, text in
            ClipboardHistoryEntry(text: text, pinnedAt: index == 1 ? Date() : nil)
        }

        var searchCache = ClipboardHistorySearchCache()
        let initialCandidates = searchCache.candidates(for: testEntries, stamp: 1, imageLabel: "Image")
        suite.expect(searchCache.candidateCount == testEntries.count, "candidates populated")
        suite.expect(searchCache.cachedEntryCount == testEntries.count, "folded entries cached")
        let initialFoldCount = searchCache.foldCount
        suite.expect(initialFoldCount == testEntries.count, "first search folds every entry exactly once")

        let testQueries = ["deploy", "dep", "clean", "joao", "сервер", "istanbul", "exact", "missing", ""]
        for q in testQueries {
            let nextCandidates = searchCache.candidates(for: testEntries, stamp: 1, imageLabel: "Image")
            suite.expect(nextCandidates == initialCandidates, "candidates reused across keystrokes without recreation")
            let ranked = ClipboardHistorySearch.rankedIndexes(candidates: nextCandidates, matching: q)
            let naiveCandidates = testEntries.enumerated().map { index, entry in
                ClipboardHistorySearchCandidate(index: index,
                                                text: entry.searchableText(imageLabel: "Image"),
                                                isPinned: entry.isPinned)
            }
            let naiveRanked = ClipboardHistorySearch.rankedIndexes(candidates: naiveCandidates, matching: q)
            suite.expect(ranked == naiveRanked, "ranking for '\(q)' is identical before and after caching")
        }
        suite.expect(searchCache.foldCount == initialFoldCount,
                     "keystrokes reuse folded entries without refolding a single one")

        let newEntry = ClipboardHistoryEntry(text: "Brand new clipboard item")
        testEntries.append(newEntry)
        let updatedCandidates = searchCache.candidates(for: testEntries, stamp: 2, imageLabel: "Image")
        suite.expect(searchCache.cachedEntryCount == testEntries.count, "cache contains new entry along with existing")
        suite.expect(updatedCandidates.count == testEntries.count, "candidates updated after stamp bump")
        let foldsAfterAppend = searchCache.foldCount
        suite.expect(foldsAfterAppend == initialFoldCount + 1, "appending one entry folds only that entry")

        let removedID = testEntries[0].id
        testEntries.remove(at: 0)
        searchCache.prune(keeping: testEntries)
        suite.expect(!searchCache.isCached(id: removedID), "removed entry evicted immediately from cache without search")
        suite.expect(searchCache.cachedEntryCount == testEntries.count, "cache pruned deleted entry without search")
        suite.expect(searchCache.candidateCount == 0, "candidate count is 0 before next search")
        let prunedCandidates = searchCache.candidates(for: testEntries, stamp: 3, imageLabel: "Image")
        suite.expect(searchCache.cachedEntryCount == testEntries.count, "cache pruned deleted entry")
        suite.expect(prunedCandidates.count == testEntries.count, "candidates match remaining count")
        suite.expect(searchCache.foldCount == foldsAfterAppend, "prune and rebuild add no folds")

        let editedID = testEntries[0].id
        testEntries[0].text = "Refactored token cleanup procedure"
        searchCache.prune(keeping: testEntries)
        suite.expect(!searchCache.isCached(id: editedID), "replaced entry text evicted immediately from cache without search")
        suite.expect(searchCache.cachedEntryCount == testEntries.count - 1, "stale folded entry purged without search")
        suite.expect(searchCache.candidateCount == 0, "candidate count is 0 after text edit before next search")
        let editedCandidates = searchCache.candidates(for: testEntries, stamp: 4, imageLabel: "Image")
        suite.expect(searchCache.isCached(id: editedID), "edited entry re-folded during next search")
        suite.expect(searchCache.foldCount == foldsAfterAppend + 1, "only the edited entry refolds")
        suite.expect(editedCandidates[0].normalizedText.contains("refactored"), "candidate normalizedText updated after text edit")
        suite.expect(editedCandidates[0].words.contains("refactored"), "candidate words set updated after text edit")
        let editedRanked = ClipboardHistorySearch.rankedIndexes(candidates: editedCandidates, matching: "refactored")
        suite.expect(editedRanked == [0], "search finds edited text")

        suite.expect(!testEntries[1].isPinned, "target entry is unpinned before toggle")
        testEntries[1].pinnedAt = Date()
        let pinToggledCandidates = searchCache.candidates(for: testEntries, stamp: 5, imageLabel: "Image")
        suite.expect(pinToggledCandidates[1].isPinned, "candidate reflects updated pinned status")
        let pinRanked = ClipboardHistorySearch.rankedIndexes(candidates: pinToggledCandidates, matching: "deploy")
        suite.expect(pinRanked.first == 1, "pinned entry gets priority boost in search")

        let testImageEntry = ClipboardHistoryEntry(text: "", kind: .image, imageWidth: 1024, imageHeight: 768)
        testEntries.append(testImageEntry)
        let imageCandidatesEN = searchCache.candidates(for: testEntries, stamp: 6, imageLabel: "Image")
        let imageRankedEN = ClipboardHistorySearch.rankedIndexes(candidates: imageCandidatesEN, matching: "image")
        suite.expect(imageRankedEN.contains(testEntries.count - 1), "finds image with English label")

        let imageCandidatesPT = searchCache.candidates(for: testEntries, stamp: 6, imageLabel: "Imagem")
        let imageRankedPT = ClipboardHistorySearch.rankedIndexes(candidates: imageCandidatesPT, matching: "imagem")
        suite.expect(imageRankedPT.contains(testEntries.count - 1), "finds image with Portuguese label after localization switch")

        let emptyCandidates = searchCache.candidates(for: [], stamp: 7, imageLabel: "Image")
        suite.expect(emptyCandidates.isEmpty, "empty entries return empty candidates")
        suite.expect(searchCache.cachedEntryCount == 0, "cache is cleared when entries is empty")
        suite.expect(searchCache.candidateCount == 0, "candidate count is 0 for empty history")

        _ = searchCache.candidates(for: testEntries, stamp: 8, imageLabel: "Image")
        suite.expect(searchCache.cachedEntryCount > 0, "cache populated")

        var clearEntries = testEntries
        var clearCache = ClipboardHistorySearchCache()
        _ = clearCache.candidates(for: clearEntries, stamp: 1, imageLabel: "Image")
        suite.expect(clearCache.cachedEntryCount > 0 && clearCache.candidateCount > 0, "cache populated before clearing history")
        clearEntries.removeAll()
        clearCache.prune(keeping: clearEntries)
        suite.expect(clearCache.cachedEntryCount == 0, "clearing history immediately evicts all cached entries without search")
        suite.expect(clearCache.candidateCount == 0, "candidate count is 0 after clearing history without search")

        var recentAndPinned = [
            ClipboardHistoryEntry(text: "Pinned Item", pinnedAt: Date()),
            ClipboardHistoryEntry(text: "Unpinned Recent Item")
        ]
        var recentCache = ClipboardHistorySearchCache()
        _ = recentCache.candidates(for: recentAndPinned, stamp: 1, imageLabel: "Image")
        suite.expect(recentCache.cachedEntryCount == 2 && recentCache.candidateCount == 2, "cache populated with pinned and unpinned")
        let unpinnedID = recentAndPinned[1].id
        let pinnedID = recentAndPinned[0].id
        recentAndPinned.removeAll { !$0.isPinned }
        recentCache.prune(keeping: recentAndPinned)
        suite.expect(!recentCache.isCached(id: unpinnedID), "clearing recent history immediately evicts unpinned item")
        suite.expect(recentCache.isCached(id: pinnedID), "clearing recent history preserves pinned item")
        suite.expect(recentCache.cachedEntryCount == 1, "only pinned item remains cached")
        suite.expect(recentCache.candidateCount == 0, "candidate count is 0 after clearing recent history")

        var imageAndText = [
            ClipboardHistoryEntry(text: "Text Alpha"),
            ClipboardHistoryEntry(text: "", kind: .image, imageWidth: 800, imageHeight: 600)
        ]
        var imagePruneCache = ClipboardHistorySearchCache()
        _ = imagePruneCache.candidates(for: imageAndText, stamp: 1, imageLabel: "Image")
        suite.expect(imagePruneCache.cachedEntryCount == 2, "cache holds text and image entries")
        let removedImageID = imageAndText[1].id
        imageAndText.remove(at: 1)
        imagePruneCache.prune(keeping: imageAndText, imageLabel: "Image")
        suite.expect(!imagePruneCache.isCached(id: removedImageID), "image entry evicted on deletion without search")
        suite.expect(imagePruneCache.cachedEntryCount == 1, "text entry retained after image entry removal")

        let foldsBeforeSwap = searchCache.foldCount
        testEntries.swapAt(0, 1)
        let swappedCandidates = searchCache.candidates(for: testEntries, stamp: 9, imageLabel: "Image")
        suite.expect(swappedCandidates[0].text == testEntries[0].text, "candidate 0 reflects swapped entry")
        suite.expect(swappedCandidates[1].text == testEntries[1].text, "candidate 1 reflects swapped entry")
        suite.expect(searchCache.cachedEntryCount == testEntries.count, "folded texts reused during swap")
        suite.expect(searchCache.foldCount == foldsBeforeSwap, "reordering entries refolds nothing")

        testEntries[0].copiedAt = Date()
        let touchedCandidates = searchCache.candidates(for: testEntries, stamp: 10, imageLabel: "Image")
        suite.expect(touchedCandidates.count == testEntries.count, "candidates rebuilt after metadata stamp bump")
        suite.expect(searchCache.cachedEntryCount == testEntries.count, "folded texts preserved after metadata stamp bump")
        suite.expect(searchCache.foldCount == foldsBeforeSwap, "metadata-only change refolds nothing")

        for spaceQuery in ["  deploy   plan  ", "   ", "deploy\tplan", "deploy\nplan"] {
            let spaceRanked = ClipboardHistorySearch.rankedIndexes(candidates: touchedCandidates, matching: spaceQuery)
            let naiveCandidates = testEntries.enumerated().map { index, entry in
                ClipboardHistorySearchCandidate(index: index,
                                                text: entry.searchableText(imageLabel: "Image"),
                                                isPinned: entry.isPinned)
            }
            let naiveRanked = ClipboardHistorySearch.rankedIndexes(candidates: naiveCandidates, matching: spaceQuery)
            suite.expect(spaceRanked == naiveRanked, "ranking for whitespace query '\(spaceQuery)' matches naive search")
        }

        searchCache.clear()
        suite.expect(searchCache.cachedEntryCount == 0 && searchCache.candidateCount == 0, "clear resets cache completely")
        _ = searchCache.candidates(for: testEntries, stamp: 11, imageLabel: "Image")
        suite.expect(searchCache.foldCount == foldsBeforeSwap + testEntries.count,
                     "search after clear refolds every entry from scratch")

        var largeEntries: [ClipboardHistoryEntry] = []
        for i in 0..<100 {
            let longText = String(repeating: "Текст для проверки производительности буфера обмена номер \(i). Многострочные логи и документы.\n", count: 50)
            largeEntries.append(ClipboardHistoryEntry(text: longText))
        }
        var largeCache = ClipboardHistorySearchCache()
        let largeCand1 = largeCache.candidates(for: largeEntries, stamp: 1, imageLabel: "Image")
        _ = ClipboardHistorySearch.rankedIndexes(candidates: largeCand1, matching: "производительности")

        for keystroke in ["произ", "произв", "производ", "номер 42"] {
            let largeCandN = largeCache.candidates(for: largeEntries, stamp: 1, imageLabel: "Image")
            let matches = ClipboardHistorySearch.rankedIndexes(candidates: largeCandN, matching: keystroke)
            if keystroke == "номер 42" {
                suite.expect(matches.first == 42, "finds target entry among 100 long entries")
            }
        }

        // MARK: Clipboard history color swatches

        func expectColor(_ text: String, _ expected: ColorValue?, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            let actual = ColorValue(text: text)
            let matches: Bool
            if let actual, let expected {
                matches = [(actual.red, expected.red), (actual.green, expected.green),
                           (actual.blue, expected.blue), (actual.alpha, expected.alpha)]
                    .allSatisfy { abs($0 - $1) < 0.002 }
            } else {
                matches = actual == nil && expected == nil
            }
            suite.expect(matches, "\(label): got \(String(describing: actual)), expected \(String(describing: expected))",
                         file: file, line: line)
        }
        expectColor("#00BC7D", ColorValue(red: 0, green: 188 / 255, blue: 125 / 255),
                    "six digit hex from the request reads as its color")
        expectColor("  #ffffff\n", ColorValue(red: 1, green: 1, blue: 1),
                    "surrounding whitespace and lowercase digits still read as a color")
        expectColor("#f80", ColorValue(red: 1, green: 136 / 255, blue: 0),
                    "three digit hex expands each digit")
        expectColor("#00000080", ColorValue(red: 0, green: 0, blue: 0, alpha: 128 / 255),
                    "eight digit hex carries alpha in the last pair")
        expectColor("#f008", ColorValue(red: 1, green: 0, blue: 0, alpha: 136 / 255),
                    "four digit hex carries alpha in the last digit")
        expectColor("rgb(0, 188, 125)", ColorValue(red: 0, green: 188 / 255, blue: 125 / 255),
                    "the color picker's rgb format reads as a color")
        expectColor("rgba(255 0 0 / 50%)", ColorValue(red: 1, green: 0, blue: 0, alpha: 0.5),
                    "space separated rgba with a slash alpha reads as a color")
        expectColor("hsl(120, 100%, 25%)", ColorValue(red: 0, green: 0.5, blue: 0),
                    "the color picker's hsl format converts to rgb")
        expectColor("hsl(-120deg 100% 50%)", ColorValue(red: 0, green: 0, blue: 1),
                    "negative hue in degrees wraps around the circle")
        expectColor(ColorValue.string(red: 0.2, green: 0.4, blue: 0.6, format: .hsl),
                    ColorValue(red: 0.2, green: 0.4, blue: 0.6),
                    "hsl written by the color picker reads back close to its source")
        expectColor(ColorValue.string(red: 0.2, green: 0.4, blue: 0.6, format: .swiftui),
                    ColorValue(red: 0.2, green: 0.4, blue: 0.6),
                    "SwiftUI code written by the color picker reads back as its color")
        expectColor("Color(red:0.2,green:0.4,blue:0.6)",
                    ColorValue(red: 0.2, green: 0.4, blue: 0.6),
                    "compact SwiftUI code without spaces reads as a color")
        expectColor("Color(red:1, green:0,blue: 0,opacity:0.5)",
                    ColorValue(red: 1, green: 0, blue: 0, alpha: 0.5),
                    "SwiftUI labels read with any spacing after the colon")
        expectColor("Color(red: 1, green: 0, blue: 0, opacity: 0.5)",
                    ColorValue(red: 1, green: 0, blue: 0, alpha: 0.5),
                    "SwiftUI opacity reads as alpha")
        expectColor("Color(red: 0.2509803922, green: 0.5019607843, blue: 0.7529411765, opacity: 0.5)",
                    ColorValue(red: 0.251, green: 0.502, blue: 0.753, alpha: 0.5),
                    "full precision SwiftUI code from Xcode reads as a color")
        for text in ["Color(red: 1, green: 0)", "Color(green: 0, red: 1, blue: 0)",
                     "Color(red: 2, green: 0, blue: 0)", "Color(.red)", "Color(red:1,green:0,blue:0,)",
                     "Color(red 1, green 0, blue 0)", "00BC7D", "#12345", "#GGGGGG", "#00BC7D is the brand green", "color: #00BC7D",
                     "rgb(256, 0, 0)", "rgb(0, 0)", "rgb(0, 0, 0, 2)", "hsl(0, 50, 50%)",
                     "rgb(nan, 0, 0)", "#", "", String(repeating: " ", count: 100) + "#fff"] {
            expectColor(text, nil, "\(text.debugDescription) is not a lone color value")
        }
        suite.expect(ClipboardHistoryEntry(text: "#fff", kind: .files, filePaths: ["/tmp/#fff"]).color == nil
                     && ClipboardHistoryEntry(text: "#fff").color != nil,
                     "only text entries show a color swatch")

        // MARK: Clipboard auto clear preferences

        suite.expect(Defaults.sanitizedClipboardAutoClearDelay(20) == 20,
               "auto clear delay in range passes through")
        suite.expect(Defaults.sanitizedClipboardAutoClearDelay(4) == 5,
               "auto clear delay below the floor clamps up, so a typed 4 does not jump to the default")
        suite.expect(Defaults.sanitizedClipboardAutoClearDelay(0) == 5,
               "auto clear delay of zero clamps up instead of clearing instantly")
        suite.expect(Defaults.sanitizedClipboardAutoClearDelay(99_999) == 3_600,
               "auto clear delay above the ceiling clamps down")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnDelay] as? Bool == false,
               "auto clear is off until asked for")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnSleep] as? Bool == false,
               "clear on computer sleep is off until asked for")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnDisplaySleep] as? Bool == false,
               "clear on display sleep is off until asked for")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnScreenLock] as? Bool == false,
               "clear on screen lock is off until asked for")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearDelay] as? Int == 20,
               "auto clear starts at twenty seconds")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardHistoryQuickPreview] as? Bool == false,
               "clipboard history quick preview is closed by default")

        // MARK: Clipboard menu bar preview

        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardHistoryMenuBarPreview] as? Bool == false,
               "the menu bar clipboard preview is off until asked for")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.clipboardHistoryMenuBarPreviewLength] as? Int == 20,
               "the menu bar clipboard preview starts at twenty characters")
        suite.expect(Defaults.sanitizedClipboardMenuBarPreviewLength(20) == 20,
               "menu bar preview length in range passes through")
        suite.expect(Defaults.sanitizedClipboardMenuBarPreviewLength(1) == 5,
               "menu bar preview length below the floor clamps up, so a typed 1 does not jump to the default")
        suite.expect(Defaults.sanitizedClipboardMenuBarPreviewLength(999) == 50,
               "menu bar preview length above the ceiling clamps down")
        let shortMenuBarPreview = ClipboardHistoryEntry(text: "hi").menuBarText(maxCharacters: 20)
        suite.expect(shortMenuBarPreview == "hi",
               "a copy shorter than the limit shows in full, with no ellipsis")
        let longMenuBarPreview = ClipboardHistoryEntry(text: String(repeating: "a", count: 200))
            .menuBarText(maxCharacters: 20)
        suite.expect(longMenuBarPreview.count == 21 && longMenuBarPreview.hasSuffix("…"),
               "a copy longer than the limit is cut to the limit plus an ellipsis")
        let returnsMenuBarPreview = ClipboardHistoryEntry(text: "one\r\ntwo\rthree\u{2028}four")
            .menuBarText(maxCharacters: 50)
        suite.expect(returnsMenuBarPreview.rangeOfCharacter(from: .newlines) == nil
                && returnsMenuBarPreview.hasSuffix("four"),
               "carriage returns and Unicode line breaks fold into the single menu bar line instead of ending it")
        L10n.shared.language = .enUS
        let imageMenuBarPreview = ClipboardHistoryEntry(text: "", kind: .image,
                                                        imageWidth: 400, imageHeight: 300)
            .menuBarText(maxCharacters: 20)
        suite.expect(imageMenuBarPreview == "Image · 400×300",
               "an image copy is labeled the same way every other image row is, not left as bare dimensions")

        // MARK: Clipboard auto clear timing

        let autoClearCopiedAt = Date(timeIntervalSince1970: 1_000_000)
        suite.expect(ClipboardAutoClearSupport.decide(changeCount: 8,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(600),
                                                delay: 20) == .noteChange,
               "a new change count restarts the clock however long the old content sat there")
        suite.expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(19),
                                                delay: 20) == .wait,
               "unchanged content waits until the delay is up")
        suite.expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(20),
                                                delay: 20) == .clear,
               "unchanged content clears once the delay is exactly up")
        suite.expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(8 * 3_600),
                                                delay: 20) == .clear,
               "waking after hours of sleep clears at once instead of waiting out another delay")
        suite.expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 7,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(600),
                                                delay: 20) == .wait,
               "the count our own clear produced never clears again, so clearing cannot loop")
        suite.expect(ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                           currentGeneration: 3,
                                                           featureIsAvailable: true,
                                                           triggerIsEnabled: true)
               && !ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                                currentGeneration: 4,
                                                                featureIsAvailable: true,
                                                                triggerIsEnabled: true)
               && !ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                                currentGeneration: 3,
                                                                featureIsAvailable: true,
                                                                triggerIsEnabled: false),
               "a queued clear is invalidated when its setting changes before pasteboard access")

        let featureTitles: [(AppLanguage, String, String, String, String)] = [
            (.enUS, "Clipboard", "Window layout", "Utilities", "Alerts"),
            (.ptBR, "Clipboard", "Layout de janelas", "Utilitários", "Alertas"),
            (.tr, "Pano", "Pencere yerleşimi", "Araçlar", "Uyarılar"),
            (.es, "Portapapeles", "Diseño de ventanas", "Utilidades", "Alertas"),
            (.de, "Zwischenablage", "Fensterlayout", "Dienstprogramme", "Warnungen"),
            (.fr, "Presse-papiers", "Disposition des fenêtres", "Utilitaires", "Alertes"),
            (.it, "Appunti", "Layout finestre", "Utilità", "Avvisi"),
            (.ja, "クリップボード", "ウインドウ配置", "ユーティリティ", "アラート"),
            (.ko, "클립보드", "윈도우 정렬", "유틸리티", "알림"),
            (.ru, "Буфер обмена", "Раскладка окон", "Утилиты", "Оповещения"),
            (.zhHans, "剪贴板", "窗口布局", "实用工具", "提醒"),
            (.zhTW, "剪貼簿", "視窗排列", "工具程式", "提醒"),
            (.zhHK, "剪貼簿", "視窗排列", "工具", "提示"),
        ]
        for (language, clipboardTitle, windowTitle, utilitiesTitle, alertsTitle) in featureTitles {
            suite.expect(FeatureStrings.clipboard(language).title == clipboardTitle,
                   "\(language.rawValue) clipboard title is localized")
            suite.expect(FeatureStrings.windowLayout(language).title == windowTitle,
                   "\(language.rawValue) window layout title is localized")
            suite.expect(FeatureStrings.settingsCategories(language).utilities == utilitiesTitle,
                   "\(language.rawValue) settings category title is localized")
            suite.expect(FeatureStrings.monitorAlerts(language).section == alertsTitle,
                   "\(language.rawValue) monitor alert section is localized")
        }
        for language in AppLanguage.allCases {
            let clipboardStrings = FeatureStrings.clipboard(language)
            expectFormat(clipboardStrings.pasteSelectedFormat, ["d"],
                         "\(language.rawValue) paste-selected button format")
            expectFormat(clipboardStrings.copySelectedFormat, ["d"],
                         "\(language.rawValue) copy-selected button format")
            expectFormat(clipboardStrings.clearRecentConfirmFormat, ["d"],
                         "\(language.rawValue) clear-unpinned confirmation format")
            suite.expect(!clipboardStrings.autoClearEnable.isEmpty
                   && !clipboardStrings.autoClearSecondsSuffix.isEmpty
                   && !clipboardStrings.autoClearOnSleep.isEmpty
                   && !clipboardStrings.autoClearOnDisplaySleep.isEmpty
                   && !clipboardStrings.autoClearOnScreenLock.isEmpty
                   && !clipboardStrings.autoClearCaption.isEmpty,
                   "\(language.rawValue) clipboard auto clear labels are localized")
            let layoutStrings = FeatureStrings.windowLayout(language)
            suite.expect(!layoutStrings.sixths.isEmpty
                   && !layoutStrings.topLeftSixth.isEmpty
                   && !layoutStrings.topCenterSixth.isEmpty
                   && !layoutStrings.topRightSixth.isEmpty
                   && !layoutStrings.bottomLeftSixth.isEmpty
                   && !layoutStrings.bottomCenterSixth.isEmpty
                   && !layoutStrings.bottomRightSixth.isEmpty,
                   "\(language.rawValue) window sixth layout labels are localized")
            suite.expect(!layoutStrings.gestureSection.isEmpty
                   && !layoutStrings.gestureEnable.isEmpty
                   && !layoutStrings.gestureCaption.isEmpty
                   && !layoutStrings.gestureModifiers.isEmpty
                   && !layoutStrings.gestureMove.isEmpty
                   && !layoutStrings.gestureResize.isEmpty
                   && !layoutStrings.gestureResizeHint.isEmpty
                   && !layoutStrings.gestureRaiseWindow.isEmpty,
                   "\(language.rawValue) window gesture controls are localized")
            suite.expect(!layoutStrings.edgeSnapEnable.isEmpty
                   && !layoutStrings.edgeSnapCaption.isEmpty
                   && !layoutStrings.edgeSnapSystemConflict.isEmpty
                   && !layoutStrings.edgeSnapOpenSystemSettings.isEmpty
                   && !layoutStrings.edgeSnapWaitingForSystem.isEmpty
                   && !layoutStrings.edgeSnapEnable.contains("—")
                   && !layoutStrings.edgeSnapCaption.contains("—")
                   && !layoutStrings.edgeSnapSystemConflict.contains("—")
                   && !layoutStrings.edgeSnapOpenSystemSettings.contains("—")
                   && !layoutStrings.edgeSnapWaitingForSystem.contains("—"),
                   "\(language.rawValue) window edge snap controls are localized")
            let alertStrings = FeatureStrings.monitorAlerts(language)
            suite.expect(alertStrings.caption.contains("12"),
                   "\(language.rawValue) monitor alert caption explains the sustained alert window")
            expectFormat(alertStrings.cpuBodyFormat, ["d"], "\(language.rawValue) CPU alert format")
            expectFormat(alertStrings.cpuTemperatureBodyFormat, ["@"],
                         "\(language.rawValue) CPU temperature alert format")
            expectFormat(alertStrings.diskBodyFormat, ["@", "d"], "\(language.rawValue) disk alert format")
            expectFormat(alertStrings.batteryBodyFormat, ["d"], "\(language.rawValue) battery alert format")
            expectFormat(alertStrings.batteryTemperatureBodyFormat, ["@"],
                         "\(language.rawValue) battery temperature alert format")
        }
        suite.expect(FeatureStrings.monitorAlerts(.enUS).cooldown == "Repeat the same alert after",
               "English monitor repeat control is explicit")
        suite.expect(FeatureStrings.monitorAlerts(.ptBR).cooldown == "Repetir o mesmo alerta depois de",
               "Portuguese monitor repeat control is explicit")

        // MARK: Settings search navigation

        suite.expect(SettingsSearchSupport.moveSelection(index: 0, delta: -1, count: 3) == 2,
               "Settings search Up wraps from first to last")
        suite.expect(SettingsSearchSupport.moveSelection(index: 2, delta: 1, count: 3) == 0,
               "Settings search Down wraps from last to first")
        suite.expect(SettingsSearchSupport.moveSelection(index: nil, delta: 1, count: 3) == 0,
               "Settings search Down starts a nil selection at the first result")
        suite.expect(SettingsSearchSupport.moveSelection(index: nil, delta: -1, count: 3) == 2,
               "Settings search Up starts a nil selection at the last result")
        suite.expect(SettingsSearchSupport.moveSelection(index: 0, delta: 1, count: 0) == nil,
               "Settings search navigation leaves an empty result set unselected")
        suite.expect(SettingsSearchSupport.moveSelection(index: 0, delta: 10, count: 3) == 1,
               "Settings search navigation wraps large positive deltas")
        suite.expect(SettingsSearchSupport.moveSelection(index: 0, delta: -10, count: 3) == 2,
               "Settings search navigation wraps large negative deltas")
        suite.expect(SettingsSearchSupport.clampedSelection(index: 4, count: 2) == 1,
               "Settings search selection clamps after results shrink")
        suite.expect(SettingsSearchSupport.reconciledSelection(index: 2,
                                                         previousIDs: ["a", "b", "c"],
                                                         resultIDs: ["a", "b"]) == 1,
               "Settings search reconciliation clamps after results shrink")
        suite.expect(SettingsSearchSupport.reconciledSelection(index: nil,
                                                         previousIDs: [String](),
                                                         resultIDs: ["new"]) == 0,
               "Settings search selects the first newly available result")
        suite.expect(SettingsSearchSupport.clampedSelection(index: 0, count: 0) == nil,
               "Settings search clamping clears an empty result set")
        suite.expect(SettingsSearchSupport.reconciledSelection(index: 1,
                                                         previousIDs: ["a", "b", "c"],
                                                         resultIDs: ["b", "a"]) == 0,
               "Settings search selection follows the same result after reranking")

        suite.expect(!ClipboardHistoryPreview.handlesSpace(selectionIsVisible: false, hasModifiers: false),
               "clipboard preview leaves spaces typed into search alone")
        suite.expect(ClipboardHistoryPreview.handlesSpace(selectionIsVisible: true, hasModifiers: false),
               "clipboard preview uses Space after keyboard navigation")
        suite.expect(!ClipboardHistoryPreview.handlesSpace(selectionIsVisible: true, hasModifiers: true),
               "clipboard preview never steals modified Space shortcuts")
        suite.expect(ClipboardHistoryEscape.action(batchCount: 0) == .hideWindow,
               "Esc closes the panel when nothing is selected")
        suite.expect(ClipboardHistoryEscape.action(batchCount: 2) == .clearBatchSelection,
               "Esc clears a batch selection before it closes the panel")
        suite.expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: true,
                                                      isFieldEditor: true,
                                                      isEditable: true),
               "a composing search field keeps Return, the arrows and Esc")
        suite.expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                       isFieldEditor: true,
                                                       isEditable: true),
               "the list keeps its shortcuts over a search field that is not composing")
        suite.expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                      isFieldEditor: false,
                                                      isEditable: true),
               "the multiline editor owns its editing keys")
        suite.expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                       isFieldEditor: false,
                                                       isEditable: false),
               "the read-only preview leaves the list's shortcuts intact")
        suite.expect(ClipboardHistoryEditing.canSave(original: "First draft", draft: "Second draft"),
               "clipboard text can save a real edit")
        suite.expect(!ClipboardHistoryEditing.canSave(original: "Same", draft: "Same"),
               "clipboard text does not save an unchanged draft")
        suite.expect(ClipboardHistoryEditing.storableText("  keep spacing  ") == "  keep spacing  ",
               "clipboard editing preserves intentional outer spacing")
        suite.expect(ClipboardHistoryEditing.storableText(" \n\t ") == nil,
               "clipboard editing rejects an empty text item")
        let largeClipboardText = String(repeating: "long copied text ", count: 10_000)
        suite.expect(ClipboardHistoryEditing.storableText(largeClipboardText) == largeClipboardText,
               "clipboard history keeps copied documents larger than the old short-text bound")
        suite.expect(ClipboardHistoryEditing.storableText(
            String(repeating: "a", count: ClipboardHistoryEditing.maxCharacters + 1)) == nil,
               "clipboard editing keeps the history text size bound")
        let budgetPinned = ClipboardHistoryEntry(text: "123456", pinnedAt: Date())
        let budgetRecentA = ClipboardHistoryEntry(text: "abcd")
        let budgetRecentB = ClipboardHistoryEntry(text: "efgh")
        let budgetedHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetPinned, budgetRecentA, budgetRecentB],
            recentLimit: 10,
            textByteLimit: 10)
        suite.expect(budgetedHistory.map(\.id) == [budgetPinned.id, budgetRecentA.id],
               "clipboard history keeps pinned and newest entries inside one aggregate text budget")
        let protectedPinned = ClipboardHistoryEntry(text: "1234", pinnedAt: Date())
        var enlargedPinned = budgetPinned
        enlargedPinned.text = "12345678"
        let trimmedPinned = ClipboardHistoryEditing.retainedEntries(
            [enlargedPinned, protectedPinned],
            recentLimit: 10,
            textByteLimit: 10)
        suite.expect(!ClipboardHistoryEditing.preservesPinnedEntries(
            from: [budgetPinned, protectedPinned],
            in: trimmedPinned),
               "an edit that would evict another pinned clipboard item is rejected")
        suite.expect(ClipboardHistoryEditing.canLoadEncodedHistory(
            byteCount: ClipboardHistoryEditing.maxEncodedHistoryBytes)
                && !ClipboardHistoryEditing.canLoadEncodedHistory(
                    byteCount: ClipboardHistoryEditing.maxEncodedHistoryBytes + 1)
                && !ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: nil),
               "clipboard history size is checked before its store file is loaded")
        let escapingHistory = (0..<8).map { index in
            ClipboardHistoryEntry(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                text: String(repeating: "\\", count: 1_000),
                copiedAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let encodedHistoryLimit = 5_000
        if let encodedHistory = ClipboardHistoryEditing.encodedHistory(
            escapingHistory, byteLimit: encodedHistoryLimit) {
            suite.expect(encodedHistory.data.count <= encodedHistoryLimit
                    && (try? JSONDecoder().decode([ClipboardHistoryEntry].self,
                                                 from: encodedHistory.data)) == encodedHistory.entries
                    && encodedHistory.entries.count < escapingHistory.count,
                   "clipboard persistence trims against actual escaped JSON before writing")
        } else {
            suite.expect(false, "clipboard persistence encodes a bounded escaped history")
        }
        let oversizedPinnedHistory = escapingHistory.map { entry -> ClipboardHistoryEntry in
            var pinned = entry
            pinned.pinnedAt = Date()
            return pinned
        }
        suite.expect(!ClipboardHistoryEditing.pinnedEntriesFit(oversizedPinnedHistory, byteLimit: encodedHistoryLimit)
                && ClipboardHistoryEditing.pinnedEntriesFit(Array(oversizedPinnedHistory.prefix(2)),
                                                            byteLimit: encodedHistoryLimit)
                && ClipboardHistoryEditing.pinnedEntriesFit(escapingHistory, byteLimit: encodedHistoryLimit),
               "pinned entries are measured as escaped JSON against the saved file, unpinned ones do not count")
        let largeClipboardPreview = ClipboardHistoryEntry(text: largeClipboardText).preview
        suite.expect(largeClipboardPreview.hasSuffix("…")
                && largeClipboardPreview.count <= ClipboardHistoryEditing.previewCharacters + 1,
               "clipboard rows keep very large text previews bounded")
        let snippet = ClipboardHistoryEntry(text: "func run() {\n\treturn\n}")
        expectEqual(snippet.cardPreview, "func run() {\n return\n}",
                    "a card keeps a snippet's line breaks and turns its tabs into spaces")
        expectEqual(snippet.preview, "func run() {  return }",
                    "the one-line preview other lists show still folds line breaks")
        let largeCardPreview = ClipboardHistoryEntry(text: largeClipboardText).cardPreview
        suite.expect(largeCardPreview.hasSuffix("…")
                && largeCardPreview.count <= ClipboardHistoryEditing.previewCharacters + 1,
               "a card keeps very large text previews bounded too")
        suite.expect(Defaults.allowedClipboardHistoryLimits == [20, 50, 100, 250, 500, 1_000, 10_000, 0],
               "clipboard history limits include 10k and unlimited options")
        suite.expect(Defaults.sanitizedClipboardHistoryLimit(10_000) == 10_000
                && Defaults.sanitizedClipboardHistoryLimit(0) == 0
                && Defaults.sanitizedClipboardHistoryLimit(50) == 50
                && Defaults.sanitizedClipboardHistoryLimit(-99) == 50,
               "sanitized clipboard history limits accept 10k and 0 (unlimited)")
        let unlimitedHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetRecentA, budgetRecentB],
            recentLimit: 0,
            textByteLimit: 1_000)
        suite.expect(unlimitedHistory.count == 2,
               "clipboard history retainedEntries preserves all entries when recentLimit is 0 (unlimited)")
        let tenThousandHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetRecentA, budgetRecentB],
            recentLimit: 10_000,
            textByteLimit: 1_000)
        suite.expect(tenThousandHistory.count == 2,
               "clipboard history retainedEntries preserves entries with 10_000 limit")
        let previewID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let nextPreviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let updatedPreview = ClipboardHistoryEntry(id: previewID, text: "updated")
        let nextPreview = ClipboardHistoryEntry(id: nextPreviewID, text: "next")
        suite.expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [updatedPreview, nextPreview],
                                                      selectedEntry: nextPreview)?.text == "updated",
               "clipboard preview resolves the current payload for its UUID")
        suite.expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [nextPreview],
                                                      selectedEntry: nextPreview)?.id == nextPreviewID,
               "clipboard search falls back to the selected visible entry")
        suite.expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [],
                                                      selectedEntry: nil) == nil,
               "clipboard preview clears after removing the final visible entry")
        expectEqual(ClipboardHistoryBatch.combinedText(["First", "Second", "Third"]),
                    "First\nSecond\nThird",
                    "clipboard batch joins selected entries as a single paste")
        suite.expect(ClipboardHistoryBatch.orderedSelectedIndexes(allIDs: ["a", "b", "c", "d"],
                                                           selectedIDs: Set(["d", "b"])) == [1, 3],
               "clipboard batch preserves the visible history order")
        suite.expect(ClipboardHistoryBatch.rangeSelectionIDs(allIDs: ["a", "b", "c", "d"],
                                                       anchor: 3, target: 1) == ["b", "c", "d"],
               "shift-click selects the whole range in either direction")
        suite.expect(ClipboardHistoryBatch.rangeSelectionIDs(allIDs: ["a"], anchor: 9, target: -2) == ["a"],
               "shift-click range clamps out-of-bounds anchors")
        let batchTextA = ClipboardHistoryEntry(text: "alpha")
        let batchTextB = ClipboardHistoryEntry(text: "beta")
        let batchFiles = ClipboardHistoryEntry(text: "", kind: .files,
                                               filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        let batchImage = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "x.png")
        suite.expect(ClipboardHistoryBatch.pasteMode(for: [batchFiles, batchFiles])
                   == .files(["/tmp/a.txt", "/tmp/b.txt", "/tmp/a.txt", "/tmp/b.txt"]),
               "an all-files selection pastes as the files themselves")
        suite.expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchTextB])
                   == .text("alpha\nbeta"),
               "an all-text selection combines as lines")
        suite.expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchFiles])
                   == .text("alpha\n/tmp/a.txt\n/tmp/b.txt"),
               "a mixed selection combines as text with file paths inlined")
        suite.expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchImage])
                   == .rich([.text("alpha"), .image("x.png")]),
               "a selection with an image pastes as rich text with the image embedded")
        suite.expect(ClipboardHistoryBatch.pasteMode(for: [batchImage, batchFiles])
                   == .rich([.image("x.png"), .text("/tmp/a.txt\n/tmp/b.txt")]),
               "files in a rich selection contribute their paths as text")
        suite.expect(ClipboardHistoryBatch.richPlainText([.text("alpha"), .image("x.png"), .text("beta")])
                   == "alpha\nbeta",
               "the plain-text fallback of a rich batch keeps only the text parts")

        let legacyClipboardJSON = Data("""
        [{"text":"hello","copiedAt":700000000}]
        """.utf8)
        if let legacy = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: legacyClipboardJSON) {
            suite.expect(legacy.count == 1 && legacy[0].kind == .text && legacy[0].text == "hello"
                   && legacy[0].sourceBundleID == nil,
                   "clipboard histories saved before images, files and source apps decode as text")
        } else {
            suite.expect(false, "clipboard legacy history decodes")
        }
        var editedTextEntry = ClipboardHistoryEntry(text: "before", pinnedAt: Date(timeIntervalSince1970: 42))
        editedTextEntry.sourceBundleID = "com.apple.TextEdit"
        editedTextEntry.text = ClipboardHistoryEditing.storableText("after") ?? editedTextEntry.text
        if let encoded = try? JSONEncoder().encode([editedTextEntry]),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded) {
            suite.expect(decoded.first?.id == editedTextEntry.id
                   && decoded.first?.text == "after"
                   && decoded.first?.pinnedAt == editedTextEntry.pinnedAt
                   && decoded.first?.sourceBundleID == "com.apple.TextEdit",
                   "clipboard text edits persist without losing item identity, pinning or source app")
        } else {
            suite.expect(false, "clipboard text edit round-trips")
        }
        let imageEntry = ClipboardHistoryEntry(text: "",
                                               kind: .image,
                                               imageFile: "a.png",
                                               imageHash: "h1",
                                               imageWidth: 1470,
                                               imageHeight: 956)
        if let encoded = try? JSONEncoder().encode([imageEntry]),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded) {
            suite.expect(decoded.first?.kind == .image
                       && decoded.first?.imageFile == "a.png"
                       && decoded.first?.imageWidth == 1470,
                   "clipboard image entries round-trip through storage")
        } else {
            suite.expect(false, "clipboard image entry round-trips")
        }
        expectEqual(imageEntry.preview, "1470×956",
                    "clipboard image preview shows the dimensions")
        suite.expect(imageEntry.searchableText(imageLabel: "Imagem").contains("Imagem"),
               "clipboard image entries match the localized image word in search")
        suite.expect(imageEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                   kind: .image,
                                                                   imageFile: "b.png",
                                                                   imageHash: "h1")),
               "clipboard image dedupe matches by content hash, not by file")
        suite.expect(!imageEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                    kind: .image,
                                                                    imageFile: "c.png",
                                                                    imageHash: "h2")),
               "clipboard image dedupe rejects different content")
        suite.expect(!ClipboardHistoryEntry(text: "", kind: .image).matchesContent(
                   of: ClipboardHistoryEntry(text: "", kind: .image)),
               "clipboard image dedupe never matches entries without a hash")
        let filesEntry = ClipboardHistoryEntry(text: "",
                                               kind: .files,
                                               filePaths: ["/Users/a/Documents/Report.pdf",
                                                           "/Users/a/Pictures/Photo.png"])
        expectEqual(filesEntry.preview, "Report.pdf, Photo.png",
                    "clipboard files preview lists the file names")
        suite.expect(filesEntry.searchableText(imageLabel: "Image").contains("Report.pdf"),
               "clipboard files entries are searchable by file name")
        suite.expect(filesEntry.searchableText(imageLabel: "Image").contains("Image"),
               "clipboard files with images include the localized image label in search")
        suite.expect(ClipboardHistoryImageSupport.isImageFileName("screenshot.PNG"),
               "clipboard image file support recognizes png case-insensitively")
        suite.expect(ClipboardHistoryImageSupport.isImageFileName("photo.jpeg")
               && ClipboardHistoryImageSupport.isImageFileName("picture.heic")
               && ClipboardHistoryImageSupport.isImageFileName("art.webp"),
               "clipboard image file support recognizes standard image extensions")
        suite.expect(!ClipboardHistoryImageSupport.isImageFileName("document.pdf")
               && !ClipboardHistoryImageSupport.isImageFileName("archive.zip"),
               "clipboard image file support rejects non-image extensions")
        suite.expect(filesEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                   kind: .files,
                                                                   filePaths: filesEntry.filePaths)),
               "clipboard files dedupe matches the same path set")
        suite.expect(!filesEntry.matchesContent(of: ClipboardHistoryEntry(text: "Report.pdf, Photo.png",
                                                                    kind: .text)),
               "clipboard dedupe never crosses kinds")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "http://localhost:3000/page",
                                                                 plainText: "//localhost:3000/page") ?? "",
                    "http://localhost:3000/page",
                    "clipboard history preserves the scheme for scheme-relative browser URLs")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://example.com/docs",
                                                                 plainText: "example.com/docs") ?? "",
                    "https://example.com/docs",
                    "clipboard history restores the scheme for scheme-stripped browser URLs")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://example.com/docs",
                                                                 plainText: "Open docs") ?? "",
                    "Open docs",
                    "clipboard history keeps ordinary link text when it is not a URL")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "file:///tmp/example.txt",
                                                                 plainText: "/tmp/example.txt") ?? "",
                    "/tmp/example.txt",
                    "clipboard history ignores non-web URL pasteboard types")
        suite.expect(!ClipboardHistorySensitiveText.looksSensitive("http://localhost:3000/page"),
               "clipboard history does not treat normal web URLs as secrets")
        suite.expect(ClipboardHistorySensitiveText.looksSensitive("https://example.com/callback?token=abc"),
               "clipboard history still skips URLs with obvious secret words")
        suite.expect(ClipboardHistorySensitiveText.looksSensitive("abc1234567890-xyz-abc"),
               "clipboard history still skips compact secret-looking text")
        // Issue #423: an identifier code is ordinary content to copy around,
        // and losing it is what stopped people from leaving the skip on.
        suite.expect(!ClipboardHistorySensitiveText.looksSensitive("3f2504e0-4f89-11d3-9a0c-0305e82c3301"),
               "clipboard history keeps a plain identifier code")
        suite.expect(!ClipboardHistorySensitiveText.looksSensitive("3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
               "clipboard history keeps an identifier code written in capitals")
        suite.expect(!ClipboardHistorySensitiveText.looksSensitive("{3f2504e0-4f89-11d3-9a0c-0305e82c3301}"),
               "clipboard history keeps an identifier code wrapped in braces")
        suite.expect(ClipboardHistorySensitiveText.looksSensitive("3f2504e0-4f89-11d3-9a0c-0305e82c33x1"),
               "a string that only resembles an identifier code is still treated as a secret")
        suite.expect(ClipboardHistorySensitiveText.looksSensitive("3f2504e04f8911d39a0c0305e82c3301!x"),
               "dropping the dashes does not turn a secret into an identifier code")
        // The mark an app puts on the pasteboard when it hands over a secret.
        // It travels with every item, so one read of the pasteboard types
        // answers for a mark written on its own item too (measured).
        suite.expect(ClipboardHistorySensitiveText.isConcealed(["public.utf8-plain-text",
                                                          ClipboardHistorySensitiveText
                                                              .concealedPasteboardType]),
               "clipboard history leaves out content an app marked as a secret")
        suite.expect(!ClipboardHistorySensitiveText.isConcealed(["public.utf8-plain-text",
                                                            "NSStringPboardType"]),
               "ordinary copied text carries no secret mark")
        expectEqual(ClipboardHistorySensitiveText.concealedPasteboardType,
                    "org.nspasteboard.ConcealedType",
                    "the secret mark keeps the exact name the apps that write it use")

        // MARK: Separated link copies

        // Issue #2411: links copied together arrive as one block, not one
        // link — a line break from several selected tabs, a tab between the
        // cells of a spreadsheet row — and reading that as a single URL
        // merges and re-encodes it.
        let multiLineLinks = "https://a.example/x?q=1\nhttps://b.example/y?q=2"
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: nil,
                                                                 plainText: multiLineLinks) ?? "",
                    multiLineLinks,
                    "clipboard history keeps a multi-line copy of tab links multi-line instead of collapsing it into one percent-encoded URL")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: nil,
                                                                 plainText: "\nhttps://a.example/path\n") ?? "",
                    "https://a.example/path",
                    "clipboard history still trims a single URL wrapped in surrounding newlines")
        // A spreadsheet row arrives tab-separated rather than one URL per
        // line, and `url` escapes a tab the same way it escapes a break.
        let tabSeparatedLinks = "https://a.example/x?q=1\thttps://b.example/y?q=2"
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: nil,
                                                                plainText: tabSeparatedLinks) ?? "",
                    tabSeparatedLinks,
                    "clipboard history keeps a tab-separated copy of links as copied instead of collapsing it into one percent-encoded URL")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://a.example/x?q=1",
                                                                plainText: multiLineLinks) ?? "",
                    multiLineLinks,
                    "clipboard history keeps every link in a multi-line copy when the first link also arrives as the web URL type instead of replacing the text with just that one link")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: nil,
                                                                plainText: "  https://a.example/path  ") ?? "",
                    "https://a.example/path",
                    "clipboard history still accepts a single URL surrounded by blank spaces")

        for copied in [
            "//a.example/x\n//b.example/y",
            "//a.example/x\r\n//b.example/y",
            "//a.example/x\t//b.example/y",
            "//a.example/x additional text",
            "//a.example/x\u{00A0}//b.example/y",
        ] {
            expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://a.example/x",
                                                                    plainText: copied) ?? "",
                        copied,
                        "a structured URL cannot replace separated scheme-less text with only its first link")
        }
        for path in ["a%20b", "a%0Ab"] {
            let url = "https://a.example/\(path)"
            expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: url,
                                                                    plainText: "//a.example/\(path)") ?? "",
                        url,
                        "a single scheme-less URL with encoded whitespace still restores its scheme")
        }

        ClipboardHistoryWriteTests.run(suite)
        ClipboardHistoryImageEditorTests.run(suite)
        ClipboardHistoryAccessTests.run(suite)

        let pasteboardAccess = GeneralPasteboardAccess(label: "Vorssaint.Tests.PasteboardAccess")
        let pasteboardGroup = DispatchGroup()
        let pasteboardStateLock = NSLock()
        var activePasteboardOperations = 0
        var maximumPasteboardOperations = 0
        for _ in 0..<16 {
            pasteboardGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pasteboardAccess.async {
                    pasteboardStateLock.lock()
                    activePasteboardOperations += 1
                    maximumPasteboardOperations = max(maximumPasteboardOperations,
                                                       activePasteboardOperations)
                    pasteboardStateLock.unlock()
                    usleep(1_000)
                    pasteboardStateLock.lock()
                    activePasteboardOperations -= 1
                    pasteboardStateLock.unlock()
                    pasteboardGroup.leave()
                }
            }
        }
        suite.expect(pasteboardGroup.wait(timeout: .now() + 5) == .success,
               "pasteboard access operations finish without deadlock")
        suite.expect(maximumPasteboardOperations == 1,
               "pasteboard access serializes concurrent service work")

        // The freeze this lane exists to prevent (issue #887): a read stuck
        // behind an app that promised pasteboard content and stopped answering
        // holds the lane, and any caller that waited for it would be frozen
        // with it. Wedge the lane, then ask for work from the main thread: the
        // ask must return at once and the answer must arrive later, on main.
        let wedgeReleased = DispatchSemaphore(value: 0)
        pasteboardAccess.async { wedgeReleased.wait() }
        // Released on its own, so a caller that waited for the lane comes out
        // measurably late instead of hanging the whole test run.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            wedgeReleased.signal()
        }
        var laneAnswer: Int?
        var laneAnsweredOnMain = false
        let askedAt = Date()
        pasteboardAccess.async({ 887 }, then: { value in
            laneAnswer = value
            laneAnsweredOnMain = Thread.isMainThread
        })
        let askDuration = Date().timeIntervalSince(askedAt)
        suite.expect(askDuration < 0.1,
               "asking the wedged pasteboard lane for work returns without waiting "
                   + "(took \(askDuration)s)")
        suite.expect(laneAnswer == nil, "the wedged lane has not answered yet")
        let laneDeadline = Date().addingTimeInterval(5)
        while laneAnswer == nil, Date() < laneDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        suite.expect(laneAnswer == 887, "the queued work runs once the lane comes free")
        suite.expect(laneAnsweredOnMain, "the pasteboard lane answers on the main queue")
        let pastePlainSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/PastePlainService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(pastePlainSource.contains("GeneralPasteboardAccess.shared.async"),
               "paste as plain text reads the clipboard on the lane, not on the main thread")
        // Ordering out keeps a sheet attached, so a Clear unpinned question
        // left open would come back with its old count on the next opening.
        let historySource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift",
            encoding: .utf8)) ?? ""
        let hideBody = historySource.components(separatedBy: "    func hideHistoryWindow() {").dropFirst().first?
            .components(separatedBy: "\n    }\n").first ?? ""
        suite.expect(hideBody.contains("panel.endSheet(sheet)")
                     && (hideBody.range(of: "endSheet")?.lowerBound ?? hideBody.endIndex)
                        < (hideBody.range(of: "orderOut")?.lowerBound ?? hideBody.startIndex)
                     && historySource.contains("event.window === panel, panel.attachedSheet == nil"),
               "the history window ends an open confirmation before hiding and leaves its keys to it")
        suite.expect((hideBody.range(of: "captureIfChanged(historyPanelClosing: true)")?.lowerBound ?? hideBody.endIndex)
                        < (hideBody.range(of: "orderOut")?.lowerBound ?? hideBody.startIndex),
               "the history window reads a copy made in it as its own before it leaves the screen")
        let panelClipboardSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/PanelClipboardView.swift",
            encoding: .utf8)) ?? ""
        suite.expect(panelClipboardSource.contains("if inNotch { confirmClearAboveIsland(ids) } else { clearingIDs = ids }")
                     && panelClipboardSource.contains("NSAlert.confirmAboveIsland("),
               "inside the island the clipboard panel asks above it instead of hanging a sheet from it")
        for (terminated, trusted, expected) in [
            (true, true, ["beep"]),
            (false, false, ["activate", "prompt", "activate", "beep"]),
            (false, true, ["activate", "paste"]),
        ] {
            let host = QuickPasteHost()
            host.trusted = trusted
            let app = QuickPasteHost.App(isTerminated: terminated)
            host.pasteIntoPreviousApp(app)
            if !trusted { host.pasteIntoPreviousApp(app) }
            suite.expect(host.events == expected,
                   "quick paste beeps or asks for Accessibility when it cannot paste, found \(host.events)")
        }
        for trusted in [true, false] {
            let host = QuickPasteHost()
            host.trusted = trusted
            host.pasteIntoPreviousApp(nil)
            suite.expect(host.events.isEmpty,
                   "quick paste with no target app stays a silent copy, found \(host.events)")
        }

    }
}

/// History mutations run their production observer without touching the system
/// pasteboard. A saved-text edit must not claim that the clipboard changed.
enum ClipboardPreviewContract {
    class Fixture {
        func pruneQuickBatchSelection() {}
        var latestPasteboardEntry: ClipboardHistoryEntry?
        var entriesStamp = 0
        var searchCache = ClipboardHistorySearchCache()
        var filterCache: (query: String, stamp: Int, imageLabel: String,
                          result: [ClipboardHistoryEntry])?
        var pendingWrite: ((Bool) -> Void)?
        func writeToPasteboard(_ list: [ClipboardHistoryEntry], completion: @escaping (Bool) -> Void) {
            pendingWrite = completion
        }
        var encodedHistoryByteLimit = ClipboardHistoryEditing.maxEncodedHistoryBytes
        func trimToLimit() {}
        func save() {}
        var quickQuery = ""
        var quickSelectionID: UUID?
        var quickSelectionIsVisible = false
        var quickBatchEntryIDs: Set<UUID> = []
        var keyboardSelectionPointer: NSPoint?
        enum NSCursor { static func setHiddenUntilMouseMoves(_ hidden: Bool) {} }
        enum NSEvent { static let mouseLocation = NSPoint.zero }
        let capturedEntry = PassthroughSubject<ClipboardHistoryEntry, Never>()
        func looksSensitive(_ text: String) -> Bool { false }
    }

    static func run(_ suite: TestSuite) {
        let current = ClipboardHistoryEntry(text: "Actual clipboard text")
        let other = ClipboardHistoryEntry(text: "Another saved copy")
        let service = Service()
        service.setEntries([current, other])
        service.latestPasteboardEntry = current
        suite.expect(service.updateText(other, to: "Edited unrelated item")
                     && service.latestPasteboardEntry == current,
                     "editing another history item preserves the actual latest copy")
        suite.expect(service.updateText(current, to: current.text)
                     && service.latestPasteboardEntry == current,
                     "accepting an unchanged history item preserves its clipboard preview")
        var pinned = current
        pinned.pinnedAt = Date()
        service.setEntries([pinned, other])
        suite.expect(service.latestPasteboardEntry == pinned,
                     "changing pin metadata retains the preview of identical copied content")
        suite.expect(service.updateText(pinned, to: "Edited but never copied")
                     && service.entries.first?.text == "Edited but never copied"
                     && service.latestPasteboardEntry == nil,
                     "editing the current saved item cannot advertise text that was never copied")
        service.setEntries([current, other])
        service.latestPasteboardEntry = current
        service.setEntries([other])
        suite.expect(service.latestPasteboardEntry == nil,
                     "removing the current entry still clears its menu-bar preview")
        service.setEntries([current, other])
        service.latestPasteboardEntry = current
        service.togglePin(current)
        suite.expect(service.latestPasteboardEntry?.text == current.text
                     && service.latestPasteboardEntry?.isPinned == true,
                     "the production pin move restores unchanged clipboard content")
        service.togglePin(service.entries.first { $0.id == current.id }!)
        suite.expect(service.latestPasteboardEntry?.text == current.text
                     && service.latestPasteboardEntry?.isPinned == false,
                     "the production unpin move retains unchanged clipboard content")
        service.latestPasteboardEntry = nil
        service.copy(current) { _ in }
        suite.expect(service.updateText(current, to: "Edited while copy was pending"),
                     "history can be edited while a pasteboard write awaits completion")
        service.pendingWrite?(true)
        service.pendingWrite = nil
        suite.expect(service.latestPasteboardEntry?.text == current.text
                     && service.entries.first { $0.id == current.id }?.text == "Edited while copy was pending",
                     "copy completion advertises exactly the older payload actually written")
        service.togglePin(service.entries.first { $0.id == current.id }!)
        suite.expect(service.latestPasteboardEntry == nil,
                     "pinning after a delayed copy cannot replace its preview with an uncopied edit")
        let a = ClipboardHistoryEntry(text: "A"), b = ClipboardHistoryEntry(text: "B")
        let c = ClipboardHistoryEntry(text: "C"), d = ClipboardHistoryEntry(text: "D")
        var orderSeenByCompletion: [String] = []
        func reuse(_ entries: [ClipboardHistoryEntry], copied: Bool) {
            let done: (Bool) -> Void = { _ in orderSeenByCompletion = service.entries.map(\.text) }
            if entries.count == 1 { service.copy(entries[0], completion: done) } else { service.copy(entries, completion: done) }
            service.pendingWrite?(copied)
            service.pendingWrite = nil
        }
        service.setEntries([a, b, c, d])
        reuse([c], copied: true)
        suite.expect(service.entries.map(\.text) == ["C", "A", "B", "D"],
                     "an entry pasted from the history moves to the top, as copying it again elsewhere does")
        suite.expect(orderSeenByCompletion == ["C", "A", "B", "D"],
                     "the copy's completion already sees the new order, so an open list can scroll to the entry")
        service.setEntries([a, b, c, d])
        reuse([c], copied: false)
        suite.expect(service.entries.map(\.text) == ["A", "B", "C", "D"], "a write that failed leaves the order alone")
        service.setEntries([a, b, c, d])
        let stampBeforeBatch = service.entriesStamp
        reuse([d, b], copied: true)
        suite.expect(service.entries.map(\.text) == ["D", "B", "A", "C"],
                     "a pasted selection moves to the top in the order it was pasted")
        suite.expect(service.entriesStamp == stampBeforeBatch + 1,
                     "a pasted selection reorders the history in one update")
        var p = ClipboardHistoryEntry(text: "P")
        p.pinnedAt = Date()
        service.setEntries([p, a, b])
        reuse([b], copied: true)
        suite.expect(service.entries.map(\.text) == ["P", "B", "A"],
                     "a pasted recent entry tops the recent ones and stays below the pinned")
        let q = ClipboardHistoryEntry(text: "Q", copiedAt: Date(timeIntervalSinceNow: -60), pinnedAt: Date())
        let r = ClipboardHistoryEntry(text: "R", pinnedAt: Date())
        service.setEntries([p, q, r, a, b])
        reuse([q, b], copied: true)
        suite.expect(service.entries.map(\.text) == ["P", "Q", "R", "B", "A"]
                     && service.entries[1].copiedAt > Date(timeIntervalSinceNow: -30),
                     "a pasted pinned entry keeps its place and its shortcut, and only its time changes")
        let image = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "saved.png")
        service.setEntries([image])
        service.latestPasteboardEntry = image
        var pinnedImage = image
        pinnedImage.pinnedAt = Date()
        service.setEntries([pinnedImage])
        suite.expect(service.latestPasteboardEntry == pinnedImage,
                     "immutable image content keeps its preview even when a legacy entry lacks a hash")

        // Escaped backslashes double in the saved file: two of these pinned
        // entries fit in 5,000 bytes and three do not.
        var heavy = (0..<3).map { ClipboardHistoryEntry(text: String(repeating: "\\", count: 1_000 + $0)) }
        heavy[0].pinnedAt = Date()
        heavy[1].pinnedAt = Date()
        service.setEntries(heavy)
        service.encodedHistoryByteLimit = 5_000
        service.togglePin(heavy[2])
        suite.expect(service.entries == heavy,
                     "a pin the saved file cannot hold beside the other pinned items is refused")
        suite.expect(!service.updateText(heavy[0], to: String(repeating: "\\", count: 1_500))
                     && service.entries == heavy,
                     "an edit that makes the pinned items too large for the saved file is refused")
        suite.expect(service.updateText(heavy[2], to: String(repeating: "\\", count: 1_500)),
                     "an unpinned item can still grow, since saving trims it instead")
        service.togglePin(heavy[0])
        suite.expect(service.entries.first { $0.id == heavy[0].id }?.isPinned == false,
                     "unpinning is never refused by the size of the saved file")

        let counted = ClipboardHistoryEntry(text: "Counted by the confirmation")
        let copiedLater = ClipboardHistoryEntry(text: "Copied while the confirmation was open")
        var pinnedLater = ClipboardHistoryEntry(text: "Pinned while the confirmation was open")
        pinnedLater.pinnedAt = Date()
        service.setEntries([pinnedLater, copiedLater, counted])
        service.clearRecent([counted.id, pinnedLater.id])
        suite.expect(service.entries.map(\.id) == [pinnedLater.id, copiedLater.id],
                     "clearing deletes only the unpinned items the confirmation counted")

        var pinnedItem = ClipboardHistoryEntry(text: "Candidate Alpha")
        pinnedItem.pinnedAt = Date()
        let recentItem = ClipboardHistoryEntry(text: "Candidate Beta")
        service.setEntries([pinnedItem, recentItem])
        let zeroCandidates = service.searchCache.candidates(for: service.entries, stamp: service.entriesStamp, imageLabel: "Image")
        let zeroMatches = ClipboardHistorySearch.rankedIndexes(candidates: zeroCandidates, matching: "nomatch")
        suite.expect(zeroMatches.isEmpty, "search finds no matches")
        suite.expect(service.searchCache.cachedEntryCount == 2 && service.searchCache.candidateCount == 2,
                     "search cache retains folded entries and candidates even with no matches")

        service.setEntries(service.entries.filter(\.isPinned))
        suite.expect(!service.searchCache.isCached(id: recentItem.id),
                     "clearing recent history immediately evicts unpinned item without a search")
        suite.expect(service.searchCache.isCached(id: pinnedItem.id),
                     "clearing recent history preserves pinned folded entry in search cache")
        suite.expect(service.searchCache.cachedEntryCount == 1,
                     "search cache retains exactly remaining pinned entry count without search")
        suite.expect(service.searchCache.candidateCount == 0,
                     "service search candidate list cleared on clearing recent history")
        service.filterCache = ("recent", service.entriesStamp, "Image", [recentItem])
        service.setEntries([pinnedItem])
        suite.expect(service.filterCache == nil,
                     "history mutation drops the retained filtered result texts without a search")

        suite.expect(service.updateText(pinnedItem, to: "Modified Alpha content"),
                     "service text edit succeeds")
        suite.expect(!service.searchCache.isCached(id: pinnedItem.id),
                     "service text edit evicts replaced text from search cache without a search")
        suite.expect(service.searchCache.cachedEntryCount == 0,
                     "search cache has no stale folded entries after edit")

        let repopulatedA = ClipboardHistoryEntry(text: "Candidate Gamma")
        let repopulatedB = ClipboardHistoryEntry(text: "Candidate Delta")
        service.setEntries([repopulatedA, repopulatedB])
        _ = service.searchCache.candidates(for: service.entries, stamp: service.entriesStamp, imageLabel: "Image")
        suite.expect(service.searchCache.cachedEntryCount == 2, "search cache repopulated")
        service.setEntries([])
        suite.expect(service.searchCache.cachedEntryCount == 0 && service.searchCache.candidateCount == 0,
                     "clearing service entries immediately purges search cache without performing another search")

        var pinnedNote = ClipboardHistoryEntry(text: "Beta pinned notes")
        pinnedNote.pinnedAt = Date()
        let routerEntry = ClipboardHistoryEntry(text: "Alpha router config")
        let blendEntry = ClipboardHistoryEntry(text: "Gamma alpha blend")
        service.setEntries([pinnedNote, routerEntry, blendEntry])
        let foldsAtStart = service.searchCache.foldCount
        let firstPass = service.filteredEntries(matching: "alpha")
        suite.expect(firstPass.map(\.text) == ["Alpha router config", "Gamma alpha blend"],
                     "production search ranks the prefix match first")
        suite.expect(service.searchCache.foldCount == foldsAtStart + 3, "production search folds each entry exactly once")
        suite.expect(service.searchCache.candidateCount == 3, "production search populates the candidate cache")
        suite.expect(service.filterCache?.query == "alpha", "production search caches its result")
        let keystrokePass = service.filteredEntries(matching: "alph")
        suite.expect(keystrokePass.map(\.text) == firstPass.map(\.text),
                     "keystroke search returns the same ranking")
        suite.expect(service.searchCache.foldCount == foldsAtStart + 3,
                     "keystroke search reuses folded entries without refolding")
        let whitespacePass = service.filteredEntries(matching: "   ")
        suite.expect(whitespacePass.count == 3, "whitespace query returns every entry")
        suite.expect(service.searchCache.foldCount == foldsAtStart + 3, "whitespace query performs no folds")
        suite.expect(service.filterCache?.result.count == 3, "whitespace query caches the full list")
        let nonePass = service.filteredEntries(matching: "nomatch")
        suite.expect(nonePass.isEmpty, "unmatched query returns nothing")
        suite.expect(service.searchCache.cachedEntryCount == 3 && service.searchCache.candidateCount == 3,
                     "unmatched query still holds the folded cache, as the review comment describes")
        service.setEntries([pinnedNote])
        suite.expect(!service.searchCache.isCached(id: routerEntry.id) && !service.searchCache.isCached(id: blendEntry.id),
                     "clearing through the production path evicts deleted text without another search")
        suite.expect(service.searchCache.foldCount == foldsAtStart + 3, "eviction itself performs no folds")
        let pinnedPass = service.filteredEntries(matching: "beta")
        suite.expect(pinnedPass.map(\.text) == ["Beta pinned notes"], "next search finds the surviving entry")
        suite.expect(service.searchCache.foldCount == foldsAtStart + 3, "the survivor's fold is reused by the next search")
        suite.expect(service.updateText(pinnedNote, to: "Beta edited notes"), "edit succeeds")
        let editedPass = service.filteredEntries(matching: "edited")
        suite.expect(editedPass.map(\.text) == ["Beta edited notes"], "search sees the edited text")
        suite.expect(service.searchCache.foldCount == foldsAtStart + 4, "only the edited entry refolds")
        searchFolding(suite)
        quickSelection(suite)
        promotedSource(suite)
    }

    /// A copy taken out of the history's own panel is of an entry already
    /// there, so it must not take away the app that entry shows.
    private static func promotedSource(_ suite: TestSuite) {
        let service = Service()
        var fromEditor = ClipboardHistoryEntry(text: "Copied in an editor")
        fromEditor.sourceBundleID = "com.example.editor"
        let other = ClipboardHistoryEntry(text: "Another copy")
        service.setEntries([other, fromEditor])
        service.promote("Copied in an editor", source: nil, keepsSource: true)
        suite.expect(service.entries.map(\.id) == [fromEditor.id, other.id]
                     && service.entries.first?.sourceBundleID == "com.example.editor",
                     "an entry copied again out of the history panel moves up and keeps the app it came from")
        service.promote("Copied in an editor", source: "com.example.browser", keepsSource: false)
        suite.expect(service.entries.first?.id == fromEditor.id
                     && service.entries.first?.sourceBundleID == "com.example.browser",
                     "an entry copied again in another app takes the app that copied it this time")
        service.promote("Part of an entry", source: nil, keepsSource: true)
        suite.expect(service.entries.first?.text == "Part of an entry"
                     && service.entries.first?.sourceBundleID == nil,
                     "new text copied out of the history panel names no app")
    }

    /// The window's highlight is what Return pastes, so it has to stay on the
    /// entry the arrow keys chose while the history changes under it.
    private static func quickSelection(_ suite: TestSuite) {
        let service = Service()
        let a = ClipboardHistoryEntry(text: "A"), b = ClipboardHistoryEntry(text: "B")
        let c = ClipboardHistoryEntry(text: "C"), fresh = ClipboardHistoryEntry(text: "Copied while open")
        service.setEntries([a, b, c])
        suite.expect(service.selectedQuickEntry == a, "before any arrow key, Return pastes the newest entry")
        service.moveQuickSelection(1)
        service.moveQuickSelection(1)
        suite.expect(service.selectedQuickEntry == b, "the second arrow press highlights the second entry")
        service.setEntries([fresh, a, b, c])
        suite.expect(service.selectedQuickEntry == b,
                     "a copy arriving above the highlight leaves it on the entry Return will paste")
        service.moveQuickSelection(1)
        suite.expect(service.selectedQuickEntry == c, "the next arrow press moves on from where the highlight is")
        service.moveQuickSelection(-1)
        service.removeSelectedQuickEntries()
        suite.expect(service.entries == [fresh, a, c] && service.selectedQuickEntry == c,
                     "deleting the highlighted entry highlights the one that took its place")
    }

    /// #1885: typing searches the history once per keystroke, so the folded
    /// text has to be reused between keystrokes and still rank exactly as a
    /// fresh fold would.
    private static func searchFolding(_ suite: TestSuite) {
        var pinned = ClipboardHistoryEntry(text: "Token CLEANUP\tnote")
        pinned.pinnedAt = Date()
        let texts = ["Deploy checklist final", "Final database\ndeploy plan", "Reunião com João"]
        let entries = [pinned] + texts.map { ClipboardHistoryEntry(text: $0) }
        let service = Service()
        service.setEntries(entries)
        let unfolded = entries.enumerated().map { index, entry in
            ClipboardHistorySearchCandidate(index: index, text: entry.text, isPinned: entry.isPinned)
        }
        for query in ["deploy final", "cleanup token", "reuniao JOAO", "plan deploy", "missing", "", "  "] {
            let expected = ClipboardHistorySearch.rankedIndexes(candidates: unfolded, matching: query)
                .map { entries[$0].id }
            suite.expect(service.filteredEntries(matching: query).map(\.id) == expected,
                         "searching folded history text ranks \"\(query)\" like a fresh fold")
        }

        service.searchCache.clear()
        _ = service.filteredEntries(matching: "")
        suite.expect(service.searchCache.cachedEntryCount == 0,
                     "an empty search lists the history without folding it")

        let foldsBeforeSearch = service.searchCache.foldCount
        _ = service.filteredEntries(matching: "d")
        suite.expect(service.searchCache.foldCount == foldsBeforeSearch + entries.count,
                     "a search folds the history once for the next keystroke")
        _ = service.filteredEntries(matching: "de")
        suite.expect(service.searchCache.foldCount == foldsBeforeSearch + entries.count,
                     "the next keystroke reuses the folded history instead of folding it again")

        let added = ClipboardHistoryEntry(text: "Sentinel copied later")
        service.setEntries(entries + [added])
        suite.expect(service.filteredEntries(matching: "sentinel").map(\.id) == [added.id],
                     "a history change folds the new text and drops the old fold")
        suite.expect(service.searchCache.foldCount == foldsBeforeSearch + entries.count + 1,
                     "only the new entry refolds after a history change")
    }
}
