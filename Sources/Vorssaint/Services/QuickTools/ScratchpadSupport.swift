// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How long each scratchpad keeps text that nobody edits. The check runs only
/// when the panel opens, against the stored edit dates, so the feature needs
/// no timer at all.
enum ScratchpadRetention: String, CaseIterable {
    case never
    case day
    case week
    case month

    /// Seconds the text may sit unedited before it clears; nil keeps forever.
    var maxIdleInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }

    /// Corrupt or unknown stored values fall back to keeping the text.
    static func sanitized(_ rawValue: String?) -> ScratchpadRetention {
        guard let rawValue,
              let retention = ScratchpadRetention(rawValue: rawValue) else {
            return .never
        }
        return retention
    }
}

struct ScratchpadMarkdownBlock {
    enum Kind: Equatable {
        case paragraph
        case heading(Int)
        case unorderedListItem(depth: Int)
        case orderedListItem(ordinal: Int, depth: Int)
        case quote(depth: Int)
        case code
        case thematicBreak
    }

    let kind: Kind
    let containerID: Int?
    let text: AttributedString
}

struct ScratchpadPad: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var text: String
    var modifiedAt: Date?
}

/// The whole scratchpad state travels as one small document. Stable ids keep
/// selection independent from names, while array order is the tab order.
struct ScratchpadDocument: Codable, Equatable {
    /// Keeps the tab strip and Settings backup deliberately small without
    /// imposing a limit on the text inside any pad.
    static let maximumPadCount = 12
    static let maximumNameLength = 40

    var pads: [ScratchpadPad]
    var selectedID: UUID

    static func initial(defaultName: String,
                        id: UUID = UUID(),
                        text: String = "",
                        modifiedAt: Date? = nil) -> ScratchpadDocument {
        let name = ScratchpadSupport.nextPadName(defaultName: defaultName, existingNames: [])
        let pad = ScratchpadPad(id: id,
                                name: name,
                                text: text,
                                modifiedAt: text.isEmpty ? nil : modifiedAt)
        return ScratchpadDocument(pads: [pad], selectedID: pad.id)
    }

    static func decoded(_ data: Data?, defaultName: String) -> ScratchpadDocument? {
        guard let data,
              let decoded = try? JSONDecoder().decode(ScratchpadDocument.self, from: data)
        else { return nil }
        return decoded.sanitized(defaultName: defaultName)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    func sanitized(defaultName: String) -> ScratchpadDocument {
        var seen = Set<UUID>()
        var cleanPads: [ScratchpadPad] = []
        for pad in pads.prefix(Self.maximumPadCount) where seen.insert(pad.id).inserted {
            let fallback = ScratchpadSupport.nextPadName(defaultName: defaultName,
                                                         existingNames: cleanPads.map(\.name))
            let name = ScratchpadSupport.sanitizedPadName(pad.name)
            cleanPads.append(ScratchpadPad(id: pad.id,
                                           name: name.isEmpty ? fallback : name,
                                           text: pad.text,
                                           modifiedAt: pad.text.isEmpty ? nil : pad.modifiedAt))
        }
        guard !cleanPads.isEmpty else { return .initial(defaultName: defaultName) }
        let selection = cleanPads.contains(where: { $0.id == selectedID })
            ? selectedID : cleanPads[0].id
        return ScratchpadDocument(pads: cleanPads, selectedID: selection)
    }

    func addingPad(defaultName: String, id: UUID = UUID()) -> ScratchpadDocument? {
        guard pads.count < Self.maximumPadCount else { return nil }
        var next = self
        let name = ScratchpadSupport.nextPadName(defaultName: defaultName,
                                                 existingNames: pads.map(\.name))
        next.pads.append(ScratchpadPad(id: id, name: name, text: "", modifiedAt: nil))
        next.selectedID = id
        return next
    }

    func selecting(_ id: UUID) -> ScratchpadDocument? {
        guard pads.contains(where: { $0.id == id }) else { return nil }
        var next = self
        next.selectedID = id
        return next
    }

    func renaming(_ id: UUID, to proposedName: String) -> ScratchpadDocument? {
        let name = ScratchpadSupport.sanitizedPadName(proposedName)
        guard !name.isEmpty, let index = pads.firstIndex(where: { $0.id == id }) else { return nil }
        var next = self
        next.pads[index].name = name
        return next
    }

    func removing(_ id: UUID) -> ScratchpadDocument? {
        guard pads.count > 1, let index = pads.firstIndex(where: { $0.id == id }) else { return nil }
        var next = self
        next.pads.remove(at: index)
        if selectedID == id {
            next.selectedID = next.pads[min(index, next.pads.count - 1)].id
        }
        return next
    }

    mutating func updateSelectedText(_ text: String, modifiedAt: Date) {
        guard let index = pads.firstIndex(where: { $0.id == selectedID }),
              pads[index].text != text else { return }
        pads[index].text = text
        pads[index].modifiedAt = text.isEmpty ? nil : modifiedAt
    }

    mutating func applyRetention(_ retention: ScratchpadRetention, now: Date) {
        for index in pads.indices where ScratchpadSupport.shouldClear(
            lastEdited: pads[index].modifiedAt, now: now, retention: retention
        ) {
            pads[index].text = ""
            pads[index].modifiedAt = nil
        }
    }
}

enum ScratchpadSupport {
    /// The fill sits over the existing material: zero preserves the familiar
    /// frosted pad, while one fully covers what is behind the window.
    static let backgroundOpacityRange: ClosedRange<Double> = 0...1

    static func sanitizedBackgroundOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return backgroundOpacityRange.upperBound }
        return min(max(value, backgroundOpacityRange.lowerBound), backgroundOpacityRange.upperBound)
    }

    static func dismissesOnOutsideClick(isPinned: Bool, exportModalActive: Bool) -> Bool {
        !isPinned && !exportModalActive
    }

    /// Rendering is on demand and never changes the stored plain text. Native
    /// presentation intents keep headings, lists and quotes semantic without a
    /// second Markdown parser or any work while the preview is closed.
    static func markdownPreview(_ text: String) -> [ScratchpadMarkdownBlock] {
        guard !text.isEmpty else { return [] }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return [ScratchpadMarkdownBlock(kind: .paragraph,
                                            containerID: nil,
                                            text: AttributedString(text))]
        }

        var blocks: [ScratchpadMarkdownBlock] = []
        var currentID: Int?
        var currentKind = ScratchpadMarkdownBlock.Kind.paragraph
        var currentContainerID: Int?
        var currentText = AttributedString()

        func finishBlock() {
            guard currentID != nil else { return }
            if currentKind == .code {
                while currentText.characters.last?.isNewline == true {
                    currentText.characters.removeLast()
                }
            }
            blocks.append(ScratchpadMarkdownBlock(kind: currentKind,
                                                  containerID: currentContainerID,
                                                  text: currentText))
            currentText = AttributedString()
        }

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let blockID = components.first?.identity ?? 0
            if blockID != currentID {
                finishBlock()
                currentID = blockID
                let presentation = markdownBlockPresentation(components)
                currentKind = presentation.kind
                currentContainerID = presentation.containerID
            }
            currentText.append(AttributedString(parsed[run.range]))
        }
        finishBlock()

        return blocks.isEmpty
            ? [ScratchpadMarkdownBlock(kind: .paragraph,
                                       containerID: nil,
                                       text: AttributedString(text))]
            : blocks
    }

    private static func markdownBlockPresentation(
        _ components: [PresentationIntent.IntentType]
    ) -> (kind: ScratchpadMarkdownBlock.Kind, containerID: Int?) {
        var listDepth = 0
        var listIsOrdered: Bool?
        var listOrdinal = 1
        var quoteDepth = 0
        var containerID: Int?

        for component in components {
            switch component.kind {
            case .header(let level):
                return (.heading(level), nil)
            case .codeBlock:
                return (.code, nil)
            case .thematicBreak:
                return (.thematicBreak, nil)
            case .listItem(let ordinal):
                if listDepth == 0 { listOrdinal = ordinal }
            case .orderedList:
                listDepth += 1
                if listIsOrdered == nil { listIsOrdered = true }
                containerID = component.identity
            case .unorderedList:
                listDepth += 1
                if listIsOrdered == nil { listIsOrdered = false }
                containerID = component.identity
            case .blockQuote:
                quoteDepth += 1
                containerID = component.identity
            case .paragraph, .table, .tableHeaderRow, .tableRow, .tableCell:
                break
            @unknown default:
                break
            }
        }

        if listIsOrdered == true {
            return (.orderedListItem(ordinal: listOrdinal, depth: max(1, listDepth)), containerID)
        }
        if listIsOrdered == false {
            return (.unorderedListItem(depth: max(1, listDepth)), containerID)
        }
        if quoteDepth > 0 { return (.quote(depth: quoteDepth), containerID) }
        return (.paragraph, nil)
    }

    static func sanitizedPadName(_ name: String) -> String {
        let words = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return String(words.joined(separator: " ").prefix(ScratchpadDocument.maximumNameLength))
    }

    static func nextPadName(defaultName: String, existingNames: [String]) -> String {
        let base = sanitizedPadName(defaultName)
        let safeBase = base.isEmpty ? "Scratchpad" : base
        let used = Set(existingNames)
        guard used.contains(safeBase) else { return safeBase }
        for number in 2...ScratchpadDocument.maximumPadCount where !used.contains("\(safeBase) \(number)") {
            return "\(safeBase) \(number)"
        }
        return "\(safeBase) \(existingNames.count + 1)"
    }

    static func migratedLegacyDocument(text: String,
                                       lastEdited: Date?,
                                       defaultName: String,
                                       retention: ScratchpadRetention,
                                       now: Date,
                                       id: UUID = UUID()) -> ScratchpadDocument {
        var document = ScratchpadDocument.initial(defaultName: defaultName,
                                                  id: id,
                                                  text: text,
                                                  modifiedAt: lastEdited)
        document.applyRetention(retention, now: now)
        return document
    }

    static func requiresCloseConfirmation(_ pad: ScratchpadPad) -> Bool {
        !pad.text.isEmpty
    }

    /// Whether the saved text expired: it only clears when a retention period
    /// is chosen and the last edit is older than that period. No saved text
    /// (or a clock that moved backwards) never clears.
    static func shouldClear(lastEdited: Date?, now: Date, retention: ScratchpadRetention) -> Bool {
        guard let limit = retention.maxIdleInterval, let lastEdited else { return false }
        let idle = now.timeIntervalSince(lastEdited)
        return idle > limit
    }

    /// Suggested name for the exported file, like "Scratchpad 2026-07-17.txt".
    static func exportFileName(title: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let safeTitle = sanitizedPadName(title)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeTitle) \(formatter.string(from: date)).txt"
    }
}
