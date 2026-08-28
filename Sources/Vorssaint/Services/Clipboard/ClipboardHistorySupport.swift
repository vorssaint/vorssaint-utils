// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClipboardHistoryEntryKind: String, Codable {
    case text
    case image
    case files
}

struct ClipboardHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    /// The content for text entries; empty for images and files, whose display
    /// strings are derived so they never go stale in storage.
    var text: String
    var copiedAt: Date
    var pinnedAt: Date?
    let kind: ClipboardHistoryEntryKind
    /// Absolute paths for `.files` entries, in the order they were copied.
    let filePaths: [String]
    /// PNG file name inside the clipboard image store for `.image` entries.
    let imageFile: String?
    /// SHA-256 of the PNG data, so re-copying the same image refreshes the
    /// existing entry instead of storing a duplicate file.
    let imageHash: String?
    let imageWidth: Int?
    let imageHeight: Int?

    init(id: UUID = UUID(),
         text: String,
         copiedAt: Date = Date(),
         pinnedAt: Date? = nil,
         kind: ClipboardHistoryEntryKind = .text,
         filePaths: [String] = [],
         imageFile: String? = nil,
         imageHash: String? = nil,
         imageWidth: Int? = nil,
         imageHeight: Int? = nil) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.pinnedAt = pinnedAt
        self.kind = kind
        self.filePaths = filePaths
        self.imageFile = imageFile
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    var isPinned: Bool {
        pinnedAt != nil
    }

    var fileNames: [String] {
        filePaths.map { ($0 as NSString).lastPathComponent }
    }

    var imageDimensionsLabel: String {
        guard let imageWidth, let imageHeight else { return "" }
        return "\(imageWidth)×\(imageHeight)"
    }

    var preview: String {
        switch kind {
        case .text:
            let prefix = text.prefix(ClipboardHistoryEditing.previewCharacters)
            let collapsed = prefix
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = collapsed.isEmpty ? String(prefix) : collapsed
            return prefix.endIndex == text.endIndex ? visible : visible + "…"
        case .image:
            return imageDimensionsLabel
        case .files:
            return fileNames.joined(separator: ", ")
        }
    }

    /// Same clipboard content, regardless of when it was copied: re-copying
    /// refreshes the existing entry instead of duplicating it.
    func matchesContent(of other: ClipboardHistoryEntry) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return imageHash != nil && imageHash == other.imageHash
        case .files: return filePaths == other.filePaths
        }
    }

    /// What the search box can match. Image entries carry the localized label
    /// plus dimensions so typing "image"/"imagem" finds them.
    func searchableText(imageLabel: String) -> String {
        switch kind {
        case .text: return text
        case .image: return "\(imageLabel) png \(imageDimensionsLabel)"
        case .files:
            let names = fileNames.joined(separator: " ")
            let hasImage = filePaths.contains { ClipboardHistoryImageSupport.isImageFileName($0) }
            return hasImage ? "\(imageLabel) \(names)" : names
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, copiedAt, pinnedAt, kind, filePaths, imageFile, imageHash, imageWidth, imageHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        copiedAt = try container.decodeIfPresent(Date.self, forKey: .copiedAt) ?? Date()
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        // Histories written before images and files existed decode as text.
        kind = try container.decodeIfPresent(ClipboardHistoryEntryKind.self, forKey: .kind) ?? .text
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        imageFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
    }
}

enum ClipboardHistoryEditing {
    /// A copied document should stay available, while a pathological
    /// pasteboard payload still has a firm in-memory and on-disk bound.
    static let maxCharacters = 1_000_000
    static let maxStoredTextUTF8Bytes = 64 * 1_024 * 1_024
    static let maxEncodedHistoryBytes = 96 * 1_024 * 1_024
    /// Rows only need enough text to fill their three visible lines. Keeping
    /// this bounded prevents a very large saved document from being copied
    /// again merely to draw its list preview.
    static let previewCharacters = 2_000

    struct EncodedHistory {
        let entries: [ClipboardHistoryEntry]
        let data: Data
    }

    static func storableText(_ text: String) -> String? {
        guard text.count <= maxCharacters,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    static func canSave(original: String, draft: String) -> Bool {
        guard let text = storableText(draft) else { return false }
        return text != original
    }

    static func retainedEntries(_ entries: [ClipboardHistoryEntry],
                                recentLimit: Int,
                                textByteLimit: Int = maxStoredTextUTF8Bytes) -> [ClipboardHistoryEntry] {
        var remainingBytes = max(0, textByteLimit)
        func retained(_ candidates: [ClipboardHistoryEntry], limit: Int?) -> [ClipboardHistoryEntry] {
            var result: [ClipboardHistoryEntry] = []
            for entry in candidates {
                if let limit, result.count >= limit { break }
                let byteCount = entry.kind == .text ? entry.text.utf8.count : 0
                guard byteCount <= remainingBytes else { continue }
                remainingBytes -= byteCount
                result.append(entry)
            }
            return result
        }
        let pinned = retained(entries.filter(\.isPinned), limit: nil)
        let recentLimitOrNil = recentLimit <= 0 ? nil : recentLimit
        let recent = retained(entries.filter { !$0.isPinned }, limit: recentLimitOrNil)
        return pinned + recent
    }

    static func preservesPinnedEntries(from original: [ClipboardHistoryEntry],
                                       in retained: [ClipboardHistoryEntry]) -> Bool {
        let retainedIDs = Set(retained.map(\.id))
        return original.lazy.filter(\.isPinned).allSatisfy { retainedIDs.contains($0.id) }
    }

    static func canLoadEncodedHistory(byteCount: Int?) -> Bool {
        guard let byteCount else { return false }
        return byteCount >= 0 && byteCount <= maxEncodedHistoryBytes
    }

    /// Encodes a readable snapshot without ever writing a file the next
    /// launch would reject. JSON escaping can make stored data much larger
    /// than the raw UTF-8 text budget, so the encoded bound must be enforced
    /// on the actual bytes rather than estimated from the strings.
    static func encodedHistory(_ entries: [ClipboardHistoryEntry],
                               byteLimit: Int = maxEncodedHistoryBytes) -> EncodedHistory? {
        guard byteLimit >= 2 else { return nil }
        let encoder = JSONEncoder()
        let ordered = entries.filter(\.isPinned) + entries.filter { !$0.isPinned }
        var retained: [ClipboardHistoryEntry] = []
        var encodedEntries: [Data] = []
        var encodedSize = 2 // Opening and closing brackets.

        for entry in ordered {
            guard let encoded = try? encoder.encode(entry) else { return nil }
            let addedSize = encoded.count + (encodedEntries.isEmpty ? 0 : 1)
            guard encodedSize + addedSize <= byteLimit else { continue }
            retained.append(entry)
            encodedEntries.append(encoded)
            encodedSize += addedSize
        }

        var data = Data(capacity: encodedSize)
        data.append(0x5B)
        for (index, encoded) in encodedEntries.enumerated() {
            if index > 0 { data.append(0x2C) }
            data.append(encoded)
        }
        data.append(0x5D)
        return EncodedHistory(entries: retained, data: data)
    }
}

struct ClipboardHistorySearchCandidate {
    var index: Int
    var text: String
    var isPinned: Bool
}

enum ClipboardHistorySearch {
    static func rankedIndexes(candidates: [ClipboardHistorySearchCandidate],
                              matching query: String) -> [Int] {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return candidates.map(\.index) }

        return candidates
            .compactMap { candidate -> (index: Int, score: Int, originalOrder: Int)? in
                let text = normalized(candidate.text)
                guard tokens.allSatisfy({ text.contains($0) }) else { return nil }
                return (candidate.index,
                        score(for: text,
                              normalizedQuery: normalizedQuery,
                              tokens: tokens,
                              isPinned: candidate.isPinned),
                        candidate.index)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.originalOrder < $1.originalOrder
            }
            .map(\.index)
    }

    static func matches(_ text: String, query: String) -> Bool {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return true }
        let normalizedText = normalized(text)
        return tokens.allSatisfy { normalizedText.contains($0) }
    }

    private static func score(for text: String,
                              normalizedQuery: String,
                              tokens: [String],
                              isPinned: Bool) -> Int {
        var score = isPinned ? 30 : 0
        if text == normalizedQuery { score += 1_200 }
        if text.hasPrefix(normalizedQuery) { score += 900 }
        if text.contains(normalizedQuery) { score += 700 }

        let words = Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
        for token in tokens {
            if words.contains(token) {
                score += 140
            } else if words.contains(where: { $0.hasPrefix(token) }) {
                score += 80
            } else {
                score += 40
            }
        }
        return score
    }

    private static func queryTokens(_ normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClipboardHistorySelection {
    static func initialIndex(totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        return 0
    }

    static func previewEntry(preferredID: UUID?,
                             visibleEntries: [ClipboardHistoryEntry],
                             selectedEntry: ClipboardHistoryEntry?) -> ClipboardHistoryEntry? {
        if let preferredID,
           let entry = visibleEntries.first(where: { $0.id == preferredID }) {
            return entry
        }
        return selectedEntry
    }
}

enum ClipboardHistoryPreview {
    static func handlesSpace(selectionIsVisible: Bool, hasModifiers: Bool) -> Bool {
        selectionIsVisible && !hasModifiers
    }
}

enum ClipboardHistoryEscape {
    enum Action: Equatable {
        case clearBatchSelection
        case hideWindow
    }

    /// Esc backs out one layer at a time - selection, then the window.
    /// Preview is a persistent view setting, not a layer: only clicking its
    /// own toggle turns it off (or Space, but only once arrow-key navigation
    /// has made a row's selection visible - see `ClipboardHistoryPreview
    /// .handlesSpace`; while the search field has focus, Space just types),
    /// so a keystroke meant to close the panel can never silently re-hide
    /// it first.
    static func action(batchCount: Int) -> Action {
        batchCount > 0 ? .clearBatchSelection : .hideWindow
    }
}

enum ClipboardHistoryBatch {
    static func combinedText(_ texts: [String]) -> String {
        texts.joined(separator: "\n")
    }

    static func orderedSelectedIndexes<ID: Hashable>(allIDs: [ID], selectedIDs: Set<ID>) -> [Int] {
        allIDs.indices.filter { selectedIDs.contains(allIDs[$0]) }
    }

    /// The ids a shift-click covers, Finder style: from the anchor row (the
    /// last one the user touched) to the clicked one, inclusive, in either
    /// direction.
    static func rangeSelectionIDs<ID>(allIDs: [ID], anchor: Int, target: Int) -> [ID] {
        guard !allIDs.isEmpty else { return [] }
        let low = min(max(min(anchor, target), 0), allIDs.count - 1)
        let high = min(max(max(anchor, target), 0), allIDs.count - 1)
        return Array(allIDs[low...high])
    }

    /// How a multi-item selection travels on the pasteboard. A selection made
    /// only of file items pastes as the files themselves, so Finder receives
    /// real files. A selection with any image in it pastes as rich text with
    /// the images embedded (Notes, Mail and TextEdit take both together),
    /// with the text parts doubling as the plain-text fallback. Anything else
    /// combines as text, file items contributing their paths.
    enum PasteMode: Equatable {
        case files([String])
        case text(String)
        case rich([RichPart])
    }

    enum RichPart: Equatable {
        case text(String)
        /// The image store file name for an `.image` entry.
        case image(String)
    }

    static func pasteMode(for entries: [ClipboardHistoryEntry]) -> PasteMode? {
        guard !entries.isEmpty else { return nil }
        if entries.allSatisfy({ $0.kind == .files }) {
            return .files(entries.flatMap(\.filePaths))
        }
        if entries.contains(where: { $0.kind == .image }) {
            let parts = entries.compactMap { entry -> RichPart? in
                switch entry.kind {
                case .text: return .text(entry.text)
                case .files: return .text(entry.filePaths.joined(separator: "\n"))
                case .image: return entry.imageFile.map(RichPart.image)
                }
            }
            return parts.isEmpty ? nil : .rich(parts)
        }
        let texts = entries.map { entry in
            entry.kind == .files ? entry.filePaths.joined(separator: "\n") : entry.text
        }
        return .text(combinedText(texts))
    }

    /// Whether a window-level ⌘C/⌘A belongs to the entry list instead of the
    /// search field. Only an explicit multi-selection claims the shortcut:
    /// arrow-key highlight alone must not steal copy or select-all from text
    /// editing in the field (⇧Enter still copies the highlighted row).
    /// ⌘A additionally falls to the list while the query is empty, where the
    /// field has nothing to select.
    static func listOwnsCopyShortcut(batchCount: Int) -> Bool {
        batchCount > 0
    }

    static func listOwnsSelectAllShortcut(batchCount: Int, queryIsEmpty: Bool) -> Bool {
        batchCount > 0 || queryIsEmpty
    }

    /// The plain-text side of a rich batch, for targets that only take text.
    static func richPlainText(_ parts: [RichPart]) -> String {
        combinedText(parts.compactMap { part in
            if case let .text(text) = part { return text }
            return nil
        })
    }
}

enum ClipboardHistoryCapturePolicy {
    static func isCopiedScreenshot(_ paths: [String], in directory: URL?) -> Bool {
        guard paths.count == 1,
              let directory else { return false }
        return ScreenshotSupport.isCopiedScreenshot(URL(fileURLWithPath: paths[0]), in: directory)
    }
}

enum ClipboardHistoryPasteboardText {
    static func preferredText(webURLString: String?, plainText: String?) -> String? {
        let plain = trimmed(plainText)
        if let plain,
           let normalizedPlain = normalizedWebURL(plain) {
            return normalizedPlain
        }

        guard let webURL = normalizedWebURL(webURLString) else { return plain }
        guard let plain else { return webURL }
        return shouldPreferWebURL(webURL, over: plain) ? webURL : plain
    }

    private static func shouldPreferWebURL(_ webURL: String, over plain: String) -> Bool {
        if plain.hasPrefix("//") { return true }
        let stripped = stripWebScheme(webURL)
        return plain == stripped.withSlashes || plain == stripped.withoutSlashes
    }

    private static func normalizedWebURL(_ raw: String?) -> String? {
        guard let text = trimmed(raw),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url.absoluteString
    }

    private static func stripWebScheme(_ value: String) -> (withSlashes: String, withoutSlashes: String) {
        let lower = value.lowercased()
        let withSlashes: String
        if lower.hasPrefix("http://") {
            withSlashes = "//" + String(value.dropFirst("http://".count))
        } else if lower.hasPrefix("https://") {
            withSlashes = "//" + String(value.dropFirst("https://".count))
        } else {
            withSlashes = value
        }
        return (withSlashes, String(withSlashes.drop { $0 == "/" }))
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

enum ClipboardHistorySensitiveText {
    /// The mark an app puts on the pasteboard to say the content is a secret
    /// and must not be recorded anywhere. It is a shared convention rather
    /// than a system feature, and the apps that keep passwords write it when
    /// they hand one over, so honoring it is the only way to leave a password
    /// out that does not depend on guessing what the text looks like.
    static let concealedPasteboardType = "org.nspasteboard.ConcealedType"

    /// Whether the pasteboard is carrying that mark. `NSPasteboard.types`
    /// already gathers the types of every item on it, so one read covers a
    /// mark written on its own item as well as one written next to the text.
    static func isConcealed(_ types: [String]) -> Bool {
        types.contains(concealedPasteboardType)
    }

    static func looksSensitive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let obviousWords = ["password", "passwd", "secret", "token", "apikey", "api_key", "authorization"]
        if obviousWords.contains(where: lowered.contains) { return true }
        if isWebURL(text) { return false }
        // An identifier code is nobody's secret, and it fits the shape below
        // exactly: long, unbroken, letters and digits with dashes between
        // them. Copying one around is ordinary work, so it stays (issue #423).
        if isIdentifierCode(text) { return false }

        guard text.count >= 20, text.count <= 160, !text.contains(where: { $0.isWhitespace }) else {
            return false
        }
        let hasLetter = text.contains { $0.isLetter }
        let hasDigit = text.contains { $0.isNumber }
        let hasSymbol = text.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        return hasLetter && hasDigit && hasSymbol
    }

    /// The one shape every system uses for a generated identifier: thirty-two
    /// hex digits in five dashed groups, optionally wrapped in braces. Kept
    /// strict on purpose, so nothing that merely resembles one gets a pass.
    private static func isIdentifierCode(_ text: String) -> Bool {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("{"), value.hasSuffix("}") {
            value = String(value.dropFirst().dropLast())
        }
        let groups = value.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy { $0.allSatisfy(\.isHexDigit) }
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }
}

enum ClipboardHistoryImageSupport {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp", "ico", "icns", "svg", "avif"
    ]

    static func isImageFileName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    static func isImageFilePath(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard isImageFileName(path) else { return false }
        return fileManager.fileExists(atPath: path)
    }
}
