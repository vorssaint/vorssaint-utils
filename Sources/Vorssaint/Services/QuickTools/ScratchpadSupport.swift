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

/// What the keyboard means while the pad has focus. Tabs mirror the browser:
/// Command-T opens one and Command-W closes one, or hides the pad when only the
/// last tab remains. Command-F is the system's own find, which the text view
/// already knows how to run, and Command-G and Shift-Command-G step through
/// its matches, since no menu in the app carries them. One table, so both
/// pads answer the same keys. `commandOnly` is Command without Control or
/// Option; Shift is its own flag because only G takes it.
enum ScratchpadFocusedShortcut {
    enum Action: Equatable {
        case createPad
        case closeSelectedPad
        case hidePad
        case find
        case findNext
        case findPrevious
    }

    static func action(charactersIgnoringModifiers: String?,
                       commandOnly: Bool,
                       shift: Bool = false,
                       canCreatePad: Bool,
                       canClosePad: Bool) -> Action? {
        guard commandOnly else { return nil }
        switch charactersIgnoringModifiers?.lowercased() {
        case "g":
            return shift ? .findPrevious : .findNext
        case _ where shift:
            return nil
        case "t":
            return canCreatePad ? .createPad : nil
        case "w":
            return canClosePad ? .closeSelectedPad : .hidePad
        case "f":
            return .find
        default:
            return nil
        }
    }
}

enum ScratchpadSupport {
    /// The fill sits over the existing material: zero preserves the familiar
    /// frosted pad, while one fully covers what is behind the window.
    static let backgroundOpacityRange: ClosedRange<Double> = 0...1

    /// The size the whole pad draws at, for anyone who finds the editor's own
    /// 13 small to live in. It is a preference rather than a mark: plain text cannot carry a
    /// point size, so one selection cannot differ from another, and the heading
    /// levels are the format's own way of making words bigger. They step up
    /// from whatever this is set to. Untouched, the pad keeps the 13 it drew
    /// at before there was a choice.
    static let defaultTextSize: Double = 13
    static let textSizeRange: ClosedRange<Double> = 10...22

    static func sanitizedTextSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTextSize }
        return min(max(value.rounded(), textSizeRange.lowerBound), textSizeRange.upperBound)
    }

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
        let firstName = "\(safeBase) 1"
        guard used.contains(safeBase) || used.contains(firstName) else { return firstName }
        for number in 2...ScratchpadDocument.maximumPadCount where !used.contains("\(safeBase) \(number)") {
            return "\(safeBase) \(number)"
        }
        return "\(safeBase) \(existingNames.count + 1)"
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

/// A mark the formatting toolbar can apply. Each one is written as the
/// Markdown a user would have typed by hand, so the pad stays plain text and
/// the preview parser needs nothing new to understand it.
enum ScratchpadMark: String, CaseIterable {
    case bold, italic, strikethrough, heading, bullet
    case numbered, quote, code, link

    /// Inline marks wrap the selection.
    var wrap: String? {
        switch self {
        case .bold: return "**"
        case .italic: return "*"
        case .strikethrough: return "~~"
        case .code: return "`"
        case .heading, .bullet, .numbered, .quote, .link: return nil
        }
    }

    /// Line marks prefix every line the selection touches, and clicking steps
    /// along this list before coming back off. A bullet is only on or off, but
    /// a heading has levels, and the preview draws each at its own size, so the
    /// button walks down them rather than stranding everyone on the largest.
    var lineCycle: [String] {
        switch self {
        case .heading: return ["# ", "## ", "### "]
        case .bullet: return ["- "]
        case .numbered: return ["1. "]
        case .quote: return ["> "]
        case .bold, .italic, .strikethrough, .code, .link: return []
        }
    }

    /// Ordered items are numbered as they are written, so the prefix a line
    /// ends up with is not the prefix the line after it gets.
    var isNumbered: Bool { self == .numbered }

    /// A letter drawn in place of the symbol, where one says the thing better.
    var glyph: String? { self == .heading ? "H" : nil }

    var symbol: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        // Never reached while `glyph` answers for headings, and kept honest in
        // case it stops: every symbol for this reads as font size, which is a
        // different thing, and not one plain Markdown can say.
        case .heading: return "textformat.size"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .quote: return "text.quote"
        case .code: return "chevron.left.slash.chevron.right"
        case .link: return "link"
        }
    }
}

/// One replacement, ready for the text view: what to swap out, what to put
/// there, and where the selection belongs afterwards.
struct ScratchpadMarkEdit: Equatable {
    /// Both ranges are in UTF-16 units, the same units NSTextView selections
    /// use, so nothing has to be converted on the way in or out.
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

extension ScratchpadSupport {
    /// Every mark toggles: applying one to text that already carries it takes
    /// it back off, so a second click on the same button undoes the first.
    static func edit(applying mark: ScratchpadMark,
                     to text: String,
                     selection: NSRange) -> ScratchpadMarkEdit {
        let ns = text as NSString
        let location = min(max(selection.location, 0), ns.length)
        let length = min(max(selection.length, 0), ns.length - location)
        var safe = NSRange(location: location, length: length)
        if mark == .link {
            return linkEdit(in: ns, selection: safe)
        }
        // A drag across words picks up the space after them, and Markdown will
        // not close a mark against a space, so "**word **" would never render.
        if mark.wrap != nil {
            safe = trimmingSpace(from: safe, in: ns)
        }
        if mark == .italic {
            return italicEdit(in: ns, selection: safe)
        }
        if let wrap = mark.wrap {
            return inlineEdit(wrap: wrap, in: ns, selection: safe)
        }
        return linePrefixEdit(mark: mark, in: ns, selection: safe)
    }

    private static func trimmingSpace(from selection: NSRange, in ns: NSString) -> NSRange {
        func isSpace(_ unit: unichar) -> Bool {
            UnicodeScalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
        }
        var start = selection.location
        var end = selection.location + selection.length
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        // Nothing but space selected: there are no words to keep the marks on.
        return start == end ? selection : NSRange(location: start, length: end - start)
    }

    /// What a link needs next is the address, so it goes in as a placeholder
    /// that arrives selected: the first keystroke after the click replaces it.
    /// Asking for the address up front would need a dialog the pad has no room
    /// for, and would stop anyone pasting a link they have not copied yet.
    static let linkPlaceholder = "url"

    private static func linkEdit(in ns: NSString, selection: NSRange) -> ScratchpadMarkEdit {
        // A second click means here what it means for every other mark: take it
        // back off. The first click leaves the address selected, not the whole
        // link, so the link has to be recognised from anywhere inside it.
        if let existing = enclosingLink(in: ns, selection: selection) {
            let label = ns.substring(with: existing.label)
            return ScratchpadMarkEdit(
                range: existing.whole,
                replacement: label,
                selection: NSRange(location: existing.whole.location,
                                   length: (label as NSString).length))
        }
        let selected = ns.substring(with: selection)
        let opening = (selected as NSString).length + 3   // "[" + text + "]("
        return ScratchpadMarkEdit(
            range: selection,
            replacement: "[\(selected)](\(linkPlaceholder))",
            selection: NSRange(location: selection.location + opening,
                               length: (linkPlaceholder as NSString).length))
    }

    private static let linkPattern = try? NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\(([^)]*)\\)")

    /// The link the selection sits in, with the range of its words. A caret has
    /// to be strictly inside one: resting it against either edge is where
    /// someone is about to write a new link, not undo the one behind them.
    private static func enclosingLink(in ns: NSString,
                                      selection: NSRange) -> (whole: NSRange, label: NSRange)? {
        guard let linkPattern else { return nil }
        let matches = linkPattern.matches(in: ns as String,
                                          range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let whole = match.range
            let end = whole.location + whole.length
            if selection.length == 0 {
                guard selection.location > whole.location, selection.location < end else { continue }
            } else {
                guard selection.location >= whole.location,
                      selection.location + selection.length <= end else { continue }
            }
            return (whole, match.range(at: 1))
        }
        return nil
    }

    private static func inlineEdit(wrap: String,
                                   in ns: NSString,
                                   selection: NSRange) -> ScratchpadMarkEdit {
        let markerLength = (wrap as NSString).length
        let selected = ns.substring(with: selection)

        // The markers sit inside the selection, which is what a selection
        // dragged across the whole marked span looks like.
        if selected.count >= wrap.count * 2,
           selected.hasPrefix(wrap), selected.hasSuffix(wrap) {
            let inner = String(selected.dropFirst(wrap.count).dropLast(wrap.count))
            return ScratchpadMarkEdit(
                range: selection,
                replacement: inner,
                selection: NSRange(location: selection.location,
                                   length: (inner as NSString).length))
        }

        // Or just outside it, which is where the second click lands: applying
        // a mark leaves the inner text selected, not the markers.
        let before = NSRange(location: selection.location - markerLength, length: markerLength)
        let after = NSRange(location: selection.location + selection.length, length: markerLength)
        if before.location >= 0,
           after.location + after.length <= ns.length,
           ns.substring(with: before) == wrap,
           ns.substring(with: after) == wrap {
            return ScratchpadMarkEdit(
                range: NSRange(location: before.location,
                               length: markerLength * 2 + selection.length),
                replacement: selected,
                selection: NSRange(location: before.location, length: selection.length))
        }

        // With no selection the pair still goes in, with the caret between the
        // halves, so the button can be clicked before the words are typed.
        return ScratchpadMarkEdit(
            range: selection,
            replacement: wrap + selected + wrap,
            selection: NSRange(location: selection.location + markerLength,
                               length: selection.length))
    }

    /// Italic's marker is a single star, which is also half of bold's pair, so
    /// no one character says whether a star belongs to italic. What settles it
    /// is how many stars run together: an odd run has an italic star on the
    /// inside of however many bold pairs sit outside it. Reading one character
    /// instead left a second click adding a pair rather than removing one, and
    /// bold and italic together grew a star on every click.
    private static func italicEdit(in ns: NSString, selection: NSRange) -> ScratchpadMarkEdit {
        let selected = ns.substring(with: selection)
        let leading = selected.prefix(while: { $0 == "*" }).count
        let trailing = selected.reversed().prefix(while: { $0 == "*" }).count

        // The stars are inside the selection, which is what selecting the whole
        // marked span looks like. Only the innermost pair is italic's.
        if leading % 2 == 1, trailing % 2 == 1, selected.count > leading + trailing - 1 {
            let inner = String(selected.dropFirst().dropLast())
            return ScratchpadMarkEdit(
                range: selection,
                replacement: inner,
                selection: NSRange(location: selection.location,
                                   length: (inner as NSString).length))
        }

        // Or just outside it, which is where the second click lands, since the
        // first leaves the words selected and the markers around them.
        if starRun(in: ns, endingAt: selection.location) % 2 == 1,
           starRun(in: ns, startingAt: selection.location + selection.length) % 2 == 1 {
            let outer = NSRange(location: selection.location - 1, length: selection.length + 2)
            return ScratchpadMarkEdit(
                range: outer,
                replacement: selected,
                selection: NSRange(location: outer.location, length: selection.length))
        }

        return ScratchpadMarkEdit(
            range: selection,
            replacement: "*" + selected + "*",
            selection: NSRange(location: selection.location + 1, length: selection.length))
    }

    private static func starRun(in ns: NSString, endingAt index: Int) -> Int {
        var count = 0
        var cursor = index - 1
        while cursor >= 0, ns.substring(with: NSRange(location: cursor, length: 1)) == "*" {
            count += 1
            cursor -= 1
        }
        return count
    }

    private static func starRun(in ns: NSString, startingAt index: Int) -> Int {
        var count = 0
        var cursor = index
        while cursor < ns.length, ns.substring(with: NSRange(location: cursor, length: 1)) == "*" {
            count += 1
            cursor += 1
        }
        return count
    }

    private static func linePrefixEdit(mark: ScratchpadMark,
                                       in ns: NSString,
                                       selection: NSRange) -> ScratchpadMarkEdit {
        let cycle = mark.lineCycle
        guard !cycle.isEmpty else {
            return ScratchpadMarkEdit(range: selection, replacement: "", selection: selection)
        }
        let lineRange = ns.lineRange(for: selection)
        let block = ns.substring(with: lineRange)
        // lineRange keeps the line terminator. Splitting with it still attached
        // invents a trailing empty line that would collect a prefix of its own.
        let terminator = block.hasSuffix("\n") ? "\n" : ""
        let body = terminator.isEmpty ? block : String(block.dropLast())
        let lines = body.components(separatedBy: "\n")

        // Indentation is what nests a list, so the mark goes after it and the
        // line keeps its depth rather than growing "-   - text".
        func indent(of line: String) -> Substring { line.prefix(while: { $0 == " " || $0 == "\t" }) }
        // Blank lines are skipped rather than marked, except in a pad that is
        // blank altogether, where the click is how the first line gets started.
        let written = lines.map { String($0.dropFirst(indent(of: $0).count)) }.filter { !$0.isEmpty }
        // Where the lines already sit in the cycle, and so what the click
        // means. Past the last step the mark comes off, so a button clicked
        // until something looks right always has an empty rung to land on.
        let step: Int?
        if mark.isNumbered {
            step = !written.isEmpty && written.allSatisfy { numberedPrefix(of: $0) != nil } ? 0 : nil
        } else {
            step = cycle.firstIndex { prefix in
                !written.isEmpty && written.allSatisfy { $0.hasPrefix(prefix) }
            }
        }
        let next = step.map { $0 + 1 < cycle.count ? cycle[$0 + 1] : "" } ?? cycle[0]
        var ordinal = 0
        let updated: [String] = lines.map { line in
            let lead = String(indent(of: line))
            let rest = String(line.dropFirst(lead.count))
            if rest.isEmpty, lines.count > 1 { return line }
            let body = strippingLineMark(from: rest)
            guard !next.isEmpty else { return lead + body }
            guard mark.isNumbered else { return lead + next + body }
            ordinal += 1
            return lead + "\(ordinal). " + body
        }

        let replacement = updated.joined(separator: "\n") + terminator
        let firstDelta = (updated[0] as NSString).length - (lines[0] as NSString).length
        let totalDelta = (replacement as NSString).length - (block as NSString).length
        // Both ends move with the prefixes before them. The start is held at
        // the line's start when a removed prefix would pull it past that, and
        // the end is worked out on its own so that hold is not added to the
        // length, which ran the selection into the text after the lines.
        let start = max(lineRange.location, selection.location + firstDelta)
        let end = max(start, selection.location + selection.length + totalDelta)
        return ScratchpadMarkEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(location: start, length: end - start))
    }

    /// A line already carrying a line mark has it replaced rather than
    /// stacked, whichever mark it was: a heading cannot grow into "# ## text",
    /// and asking a bullet for a heading gives a heading, not "# - text".
    private static func strippingLineMark(from line: String) -> String {
        let hashes = line.prefix(while: { $0 == "#" })
        if !hashes.isEmpty, hashes.count <= 6, line.dropFirst(hashes.count).hasPrefix(" ") {
            return String(line.dropFirst(hashes.count + 1))
        }
        if let first = line.first, "-*+>".contains(first), line.dropFirst().hasPrefix(" ") {
            return String(line.dropFirst(2))
        }
        if let numbered = numberedPrefix(of: line) {
            return String(line.dropFirst(numbered.count))
        }
        return line
    }

    /// "12. " and the like, however many digits the list has run to.
    private static func numberedPrefix(of line: String) -> String? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(line.prefix(digits.count + 2))
    }
}
