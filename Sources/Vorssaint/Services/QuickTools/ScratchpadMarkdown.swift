// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Source ranges stay in UTF-16, the same coordinate system as NSTextView.
struct ScratchpadMarkdown {
    struct Span {
        let range: NSRange
        let inline: InlinePresentationIntent
        let heading: Int?
        let code: Bool
        let quote: Bool
        let link: URL?
        let list: ScratchpadMark?

        var marks: Set<ScratchpadMark> {
            var result = Set<ScratchpadMark>()
            if heading != nil { result.insert(.heading) }
            if quote { result.insert(.quote) }
            if code || inline.contains(.code) { result.insert(.code) }
            if inline.contains(.stronglyEmphasized) { result.insert(.bold) }
            if inline.contains(.emphasized) { result.insert(.italic) }
            if inline.contains(.strikethrough) { result.insert(.strikethrough) }
            if link != nil { result.insert(.link) }
            if let list { result.insert(list) }
            return result
        }
    }
    struct Task {
        let prefix: NSRange
        let marker: NSRange
        let line: NSRange
        let content: NSRange
        let checked: Bool
    }
    struct Bullet {
        let prefix: NSRange
        let line: NSRange
    }
    let spans: [Span]
    let markers: [NSRange]
    let tasks: [Task]
    let bullets: [Bullet]

    init(_ source: String) {
        let ns = source as NSString
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible, appliesSourcePositionAttributes: true)
        let parsed = try? AttributedString(markdown: source, options: options)
        var spans: [Span] = []
        var markers: [NSRange] = []
        var tasks: [Task] = []
        var bullets: [Bullet] = []
        // Native source columns count UTF-8 bytes, with an inclusive end.
        // Map each byte to its full UTF-16 scalar once, including CRLF lines.
        let bytes = Array(source.utf8)
        var lineStarts = [0]
        for index in bytes.indices where bytes[index] == 10
            || bytes[index] == 13 && (index + 1 == bytes.count || bytes[index + 1] != 10) {
            lineStarts.append(index + 1)
        }
        var byteRanges: [NSRange] = []
        byteRanges.reserveCapacity(bytes.count)
        var utf16Offset = 0
        for scalar in source.unicodeScalars {
            let length = scalar.value > 0xFFFF ? 2 : 1
            let range = NSRange(location: utf16Offset, length: length)
            byteRanges.append(contentsOf: repeatElement(range, count: String(scalar).utf8.count))
            utf16Offset += length
        }
        func sourceRange(_ position: AttributedString.MarkdownSourcePosition) -> NSRange? {
            guard position.startLine > 0, position.endLine > 0,
                  position.startLine <= lineStarts.count, position.endLine <= lineStarts.count,
                  position.startColumn > 0, position.endColumn > 0 else { return nil }
            let start = lineStarts[position.startLine - 1] + position.startColumn - 1
            let end = lineStarts[position.endLine - 1] + position.endColumn - 1
            guard start <= end, end < byteRanges.count else { return nil }
            return NSRange(location: byteRanges[start].location,
                           length: NSMaxRange(byteRanges[end]) - byteRanges[start].location)
        }
        if let parsed {
            for run in parsed.runs {
                guard let position = run.markdownSourcePosition,
                      let range = sourceRange(position) else { continue }
                var heading: Int?
                var code = false
                var quote = false
                var list: ScratchpadMark?
                for component in run.presentationIntent?.components ?? [] {
                    switch component.kind {
                    case .header(let level): heading = level
                    case .codeBlock: code = true
                    case .blockQuote: quote = true
                    case .unorderedList: list = .bullet
                    case .orderedList: list = .numbered
                    default: break
                    }
                }
                let inline = run.inlinePresentationIntent ?? []
                spans.append(.init(range: range, inline: inline, heading: heading,
                                   code: code, quote: quote, link: run.link, list: list))
                // Only hide paired syntax proven by the native parser. Literal
                // punctuation, escapes and unfinished Markdown stay readable.
                if !code {
                    let wrappers: [(Bool, [String])] = [
                        (inline.contains(.stronglyEmphasized) && inline.contains(.emphasized), ["***", "___"]),
                        (inline.contains(.stronglyEmphasized), ["**", "__"]),
                        (inline.contains(.emphasized), ["*", "_"]),
                        (inline.contains(.strikethrough), ["~~"]),
                        (inline.contains(.code), ["`", "``", "```"])
                    ]
                    for (enabled, candidates) in wrappers where enabled {
                        for token in candidates {
                            let length = (token as NSString).length
                            let before = NSRange(location: range.location - length, length: length)
                            let after = NSRange(location: NSMaxRange(range), length: length)
                            if before.location >= 0, NSMaxRange(after) <= ns.length,
                               ns.substring(with: before) == token, ns.substring(with: after) == token {
                                markers.append(contentsOf: [before, after])
                                break
                            }
                        }
                    }
                    if run.link != nil, let link = ScratchpadSupport.enclosingLink(in: ns, selection: range), !link.isImage {
                        markers.append(NSRange(location: link.label.location - 1, length: 1))
                        markers.append(NSRange(location: NSMaxRange(link.label), length: NSMaxRange(link.whole) - NSMaxRange(link.label)))
                    }
                }
            }
        }
        let prefix = try! NSRegularExpression(pattern: "(?m)^[ \\t]*(#{1,6} +|> +|(?:[-+*]|[0-9]+[.)]) +)")
        for match in prefix.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let range = match.range(at: 1)
            let line = ns.lineRange(for: range)
            let contentStart = NSMaxRange(range)
            let span = spans.first(where: { NSIntersectionRange($0.range, line).length > 0 })
            guard span?.code != true, span != nil || !Self.isInsideFence(source, at: range.location) else { continue }
            if span?.heading != nil || span?.quote == true { markers.append(range) }
            let bullet = ns.substring(with: range).trimmingCharacters(in: .whitespaces)
            if contentStart + 4 <= ns.length {
                let taskMarker = NSRange(location: contentStart, length: 4)
                let token = ns.substring(with: taskMarker)
                if ["-", "*", "+"].contains(bullet), ["[ ] ", "[x] ", "[X] "].contains(token) {
                    let start = NSMaxRange(taskMarker)
                    var end = NSMaxRange(line)
                    while end > start, [10, 13].contains(ns.character(at: end - 1)) { end -= 1 }
                    tasks.append(.init(prefix: range, marker: taskMarker, line: line,
                                       content: NSRange(location: start, length: end - start), checked: token != "[ ] "))
                    markers.append(contentsOf: [range, taskMarker])
                    continue
                }
            }
            if ["-", "*", "+"].contains(bullet) { bullets.append(.init(prefix: range, line: line)) }
        }
        self.spans = spans; self.markers = markers; self.tasks = tasks; self.bullets = bullets
    }

    func activeMarks(at selection: NSRange) -> Set<ScratchpadMark> {
        let selected = spans.filter {
            selection.length == 0 ? selection.location >= $0.range.location && selection.location <= NSMaxRange($0.range)
                : NSIntersectionRange(selection, $0.range).length > 0
        }
        var result = selected.first?.marks ?? []
        for span in selected.dropFirst() { result.formIntersection(span.marks) }
        if tasks.contains(where: {
            selection.location >= $0.line.location && NSMaxRange(selection) <= NSMaxRange($0.line)
                && selection.location < NSMaxRange($0.line)
        }) {
            result.remove(.bullet)
            result.insert(.checklist)
        }
        return result
    }

    static func suggestedTitle(in source: String) -> String? {
        var title: String?
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .byLines) { line, _, _, stop in
            guard let line, !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let task = Self(line).tasks.first
            let content = task.map { (line as NSString).substring(from: $0.content.location) } ?? line
            let parsed = try? AttributedString(markdown: content)
            let name = ScratchpadSupport.sanitizedPadName(parsed.map { String($0.characters) } ?? content)
            if !name.isEmpty { title = name; stop = true }
        }
        return title
    }

    enum ChecklistAction { case uncheckAll, removeCompleted }

    func checklistEdit(_ action: ChecklistAction, in source: String, selection: NSRange) -> ScratchpadMarkEdit? {
        let checked = tasks.filter(\.checked)
        guard !checked.isEmpty else { return nil }
        let changes: [(range: NSRange, replacement: String)] = checked.map {
            switch action {
            case .uncheckAll: return (NSRange(location: $0.marker.location + 1, length: 1), " ")
            case .removeCompleted: return ($0.line, "")
            }
        }
        let result = NSMutableString(string: source)
        for change in changes.reversed() { result.replaceCharacters(in: change.range, with: change.replacement) }
        func mapped(_ position: Int) -> Int {
            var delta = 0
            for change in changes {
                if position < change.range.location { break }
                if position < NSMaxRange(change.range) { return change.range.location + delta }
                delta += (change.replacement as NSString).length - change.range.length
            }
            return min(max(0, position + delta), result.length)
        }
        let start = mapped(selection.location)
        let end = max(start, mapped(NSMaxRange(selection)))
        let range = NSRange(location: changes[0].range.location,
                            length: NSMaxRange(changes[changes.count - 1].range) - changes[0].range.location)
        let delta = result.length - (source as NSString).length
        let replacement = result.substring(with: NSRange(location: range.location, length: range.length + delta))
        return .init(range: range, replacement: replacement,
                     selection: NSRange(location: start, length: end - start))
    }

    static func toggleTask(in source: String, at location: Int) -> ScratchpadMarkEdit? {
        let ns = source as NSString
        guard location >= 0, location <= ns.length,
              let task = Self(source).tasks.first(where: { location >= $0.line.location && (location < NSMaxRange($0.line) || location == ns.length && location == NSMaxRange($0.line)) }) else { return nil }
        return .init(range: NSRange(location: task.marker.location + 1, length: 1),
                     replacement: task.checked ? " " : "x", selection: NSRange(location: location, length: 0))
    }

    static func continueList(in source: String, selection: NSRange) -> ScratchpadMarkEdit? {
        let ns = source as NSString
        guard selection.location <= ns.length, NSMaxRange(selection) <= ns.length,
              !isInsideFence(source, at: selection.location) else { return nil }
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let value = ns.substring(with: line).trimmingCharacters(in: .newlines)
        let regex = try! NSRegularExpression(pattern: "^([ \\t]*)([-+*] |[0-9]+[.)] )(\\[[ xX]\\] )?")
        guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)),
              !Self(source).spans.contains(where: { $0.code && NSIntersectionRange($0.range, line).length > 0 }) else { return nil }
        let contentStart = line.location + match.range.length
        guard selection.location >= contentStart else { return nil }
        if (value as NSString).length == match.range.length {
            return .init(range: NSRange(location: line.location, length: match.range.length), replacement: "",
                         selection: NSRange(location: line.location, length: 0))
        }
        let local = value as NSString
        let indent = local.substring(with: match.range(at: 1))
        var bullet = local.substring(with: match.range(at: 2))
        if let number = Int(bullet.dropLast(2)), number < Int.max { bullet = "\(number + 1)\(bullet.suffix(2))" }
        let task = match.range(at: 3).location == NSNotFound ? "" : "[ ] "
        let replacement = "\n" + indent + bullet + task
        return .init(range: selection, replacement: replacement,
                     selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    static func indentList(in source: String, selection: NSRange, outdent: Bool) -> ScratchpadMarkEdit? {
        let ns = source as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let range = ns.lineRange(for: selection)
        let original = ns.substring(with: range)
        let regex = try! NSRegularExpression(pattern: "^[ \\t]*(?:[-+*] |[0-9]+[.)] )")
        let lines = original.components(separatedBy: "\n")
        guard lines.filter({ !$0.isEmpty }).allSatisfy({
            regex.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil
        }), !Self(source).spans.contains(where: {
            $0.code && NSIntersectionRange($0.range, range).length > 0
                && (!outdent || isInsideFence(source, at: range.location))
        }) else { return nil }
        let changed = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if !outdent { return "    " + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.dropFirst(min(4, line.prefix(while: { $0 == " " }).count)))
        }
        let replacement = changed.joined(separator: "\n")
        let delta = (changed[0] as NSString).length - (lines[0] as NSString).length
        let start = max(range.location, selection.location + delta)
        let end = max(start, NSMaxRange(selection) + (replacement as NSString).length - (original as NSString).length)
        return .init(range: range, replacement: replacement, selection: NSRange(location: start, length: end - start))
    }

    /// Outdent can recover an over-indented list, but never edits fenced code.
    private static func isInsideFence(_ source: String, at location: Int) -> Bool {
        let ns = source as NSString
        let prefix = ns.substring(to: min(location, ns.length))
        var fence: (Character, Int)?
        for line in prefix.components(separatedBy: "\n") {
            let indent = line.prefix(while: { $0 == " " }).count
            guard indent <= 3 else { continue }
            let rest = line.dropFirst(indent)
            guard let first = rest.first, first == "`" || first == "~" else { continue }
            let count = rest.prefix(while: { $0 == first }).count
            guard count >= 3 else { continue }
            if let open = fence {
                if open.0 == first, count >= open.1,
                   rest.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else { fence = (first, count) }
        }
        return fence != nil
    }
}
