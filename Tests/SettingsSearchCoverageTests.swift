// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every label a Settings page shows on a row or a card can be found in
/// Settings search. The pages and the search directory are separate lists, so
/// this reads both from source and names each label the directory misses. A
/// title it cannot follow back to a localized string fails too, so a new
/// shape is noticed rather than skipped.
enum SettingsSearchCoverageTests {
    /// The Settings components whose `title:` is a label on the page.
    static let components = ["SettingsRow", "SettingsCard", "SettingsChoiceRow",
                             "SettingsMenuRow", "SettingsFeatureSwitchRow"]

    /// Where Settings search gets its words. `selfType` names the strings
    /// type whose own members a region lists without a receiver.
    private static let searchSources: [(path: String, declaration: String, selfType: String?)] = [
        ("Sources/Vorssaint/UI/Settings/SettingsDirectory.swift", "    static func searchItems(", nil),
        ("Sources/Vorssaint/UI/Settings/SettingsDirectory.swift", "    static func sections(", nil),
        ("Sources/Vorssaint/UI/Settings/SettingsSearchSupport.swift",
         "    static func keyboardBrightnessShortcutItem(", nil),
        ("Sources/Vorssaint/UI/Settings/SettingsSearchSupport.swift",
         "    static func screenCaptureFeatureKeywords(", nil),
        // Every feature's name is a search result of its own.
        ("Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift", "    func hubTitle(", nil),
        ("Sources/Vorssaint/Core/NotchMascotStrings.swift", "    var searchKeywords:", "NotchMascotStrings"),
    ]

    /// Labels that name no setting, so a search for them has nowhere to go.
    private static let exemptions: [String: String] = [
        "Strings.permissionRequired": "a banner asking for a missing permission",
        "FeatureHubStrings.neverUsedTitle": "a suggestion that shows only while some features stay unused",
    ]

    static func run(_ suite: TestSuite) {
        let resolver = Resolver(sourceRoot: "Sources/Vorssaint")
        var indexed = Set<String>()
        for source in searchSources {
            let words = (try? String(contentsOfFile: source.path, encoding: .utf8)).flatMap {
                resolver.searchWords(in: SwiftSource(path: source.path, text: $0),
                                     declaration: source.declaration, selfType: source.selfType)
            }
            suite.expect(words?.isEmpty == false, "\(source.path) gives Settings search its words")
            indexed.formUnion(words ?? [])
        }

        var shown = Set<String>()
        var labelCount = 0
        for source in resolver.settingsSources() {
            for site in source.titleSites() {
                do {
                    for label in try resolver.labels(site, in: source) {
                        labelCount += 1
                        shown.insert(label.reference)
                        suite.expect(indexed.contains(label.reference) || exemptions[label.reference] != nil,
                                     "\(source.path):\(source.line(at: label.offset)): \(label.reference) "
                                        + "is shown in Settings but Settings search cannot find it")
                    }
                } catch {
                    suite.expect(false, "\(source.path):\(source.line(at: site.lowerBound)): cannot follow "
                                    + "the title `\(source.text(site))` to a localized string (\(error))")
                }
            }
        }
        suite.expect(labelCount > 150, "the coverage scan finds the Settings labels (\(labelCount))")
        for reference in exemptions.keys.sorted() {
            suite.expect(shown.contains(reference), "the search exemption \(reference) still names a label")
        }

        let sample = SwiftSource(path: "Sample.swift", text: """
            struct Sample: View {
                @AppStorage("size") private var size = 1
                private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
                var body: some View {
                    SettingsCard(title: text.size) {
                        // SettingsRow(symbol: "x", title: text.hidden) {}
                        let size = SampleStrings.localized(l10n.language)
                        SettingsChoiceRow(symbol: "a.b(", selection: $value,
                                          title: size
                                              .entrySize) { Text("}") }
                        switchRow("c", l10n.s.launchAtLogin, isOn: $isOn)
                        SettingsRow(symbol: "d", title: item.name) {}
                    }
                }
                private func switchRow(_ symbol: String, _ title: String, caption: String? = nil,
                                       isOn: Binding<Bool>) -> some View {
                    SettingsRow(symbol: symbol, title: title, caption: caption) { EmptyView() }
                }
            }
            """)
        var sampleLabels: [String] = []
        var sampleFailures: [String] = []
        for site in sample.titleSites() {
            do {
                sampleLabels += try resolver.labels(site, in: sample).map(\.reference)
            } catch {
                sampleFailures.append(sample.text(site))
            }
        }
        suite.expect(sampleLabels.sorted() == ["NotchStrings.size", "SampleStrings.entrySize", "Strings.launchAtLogin"],
                     "the coverage scan follows aliases, shadowing, line breaks and helpers: \(sampleLabels)")
        suite.expect(sampleFailures == ["item.name"],
                     "the coverage scan fails on a title it cannot follow: \(sampleFailures)")
        let built = SwiftSource(path: "Built.swift", text: """
            static func sections() -> [[String]] {
                var left: [String] = []
                left = [FeatureStrings.notch(language).size]
                let kept = [FeatureStrings.notch(language).title]
                return [kept]
            }
            """)
        let builtWords = resolver.searchWords(in: built, declaration: "static func sections(", selfType: nil)
        suite.expect(builtWords == ["NotchStrings.title"],
                     "a label in a local that no keyword list reads is not a search word: \(builtWords ?? [])")
    }

    struct Unresolved: Error, CustomStringConvertible {
        let description: String
    }

    struct Label {
        let reference: String
        let offset: Int
    }

    /// Follows a title back to `Type.member` of a localized strings type, the
    /// same name whichever alias reaches it.
    struct Resolver {
        let sourceRoot: String
        /// The type each `FeatureStrings.name(language)` provider returns.
        private let providers: [String: Set<String>]

        init(sourceRoot: String) {
            self.sourceRoot = sourceRoot
            var providers: [String: Set<String>] = [:]
            let declaration = try! NSRegularExpression(pattern: #"static func (\w+)\(_ \w+: AppLanguage\) -> (\w+)"#)
            for path in Self.swiftFiles(in: sourceRoot) {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                      text.contains("AppLanguage) ->") else { continue }
                let nsText = text as NSString
                for match in declaration.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                    providers[nsText.substring(with: match.range(at: 1)), default: []]
                        .insert(nsText.substring(with: match.range(at: 2)))
                }
            }
            self.providers = providers
        }

        private static func swiftFiles(in root: String) -> [String] {
            let paths = FileManager.default.enumerator(atPath: root)?.compactMap { $0 as? String } ?? []
            return paths.filter { $0.hasSuffix(".swift") }.sorted().map { root + "/" + $0 }
        }

        /// The files that draw Settings rows. The menu bar panel reuses the
        /// components for its own controls, and SettingsCard.swift defines them.
        func settingsSources() -> [SwiftSource] {
            Self.swiftFiles(in: sourceRoot).compactMap { path in
                guard !path.contains("/UI/MenuPanel/"), !path.hasSuffix("/SettingsCard.swift"),
                      let text = try? String(contentsOfFile: path, encoding: .utf8),
                      components.contains(where: { text.contains($0 + "(") }) else { return nil }
                return SwiftSource(path: path, text: text)
            }
        }

        /// Every strings member that one declaration's body names, or nil
        /// when the declaration is gone. A local the body never reads gives
        /// no words, as no keyword list includes it.
        func searchWords(in source: SwiftSource, declaration: String, selfType: String?) -> Set<String>? {
            guard let offset = source.uniqueOffset(of: declaration),
                  let body = source.blocks.filter({ $0.open > offset }).min(by: { $0.open < $1.open })
            else { return nil }
            let unread = source.unreadWrites(in: body.open..<body.close)
            var words = Set<String>()
            for match in source.matches(#"(?<![\w.$])[A-Za-z_]\w*"#, in: body.open..<body.close)
                where !unread.contains(where: { $0.contains(match.range.location) }) {
                let links = source.chain(from: match.range.location).links
                if let selfType, links.count == 1, case .name(let member) = links[0] {
                    words.insert("\(selfType).\(member)")
                }
                for end in links.indices.dropFirst() {
                    guard case .name(let member) = links[end],
                          let type = type(of: Array(links[..<end]), at: match.range.location, in: source)
                    else { continue }
                    words.insert("\(type).\(member)")
                }
            }
            return words
        }

        /// The strings members a title shows. A title passed through a
        /// helper's parameter resolves at each call to that helper.
        func labels(_ expression: Range<Int>, in source: SwiftSource, depth: Int = 0) throws -> [Label] {
            guard depth < 4 else { throw Unresolved(description: "passed through too many helpers") }
            let start = source.skipSpace(from: expression.lowerBound)
            let chain = source.chain(from: start)
            guard !chain.links.isEmpty, source.skipSpace(from: chain.end) >= expression.upperBound else {
                throw Unresolved(description: "not a property of a strings value")
            }
            if chain.links.count == 1, case .name(let name) = chain.links[0] {
                switch source.declaration(of: name, visibleAt: start) {
                case .variable(_, _, let initializer?)?:
                    return try labels(initializer, in: source, depth: depth + 1)
                case .parameter(let function, let index)?:
                    let calls = source.calls(to: function)
                    guard !calls.isEmpty else { throw Unresolved(description: "\(function.name) has no calls") }
                    return try calls.flatMap { call -> [Label] in
                        guard let argument = SwiftSource.argument(for: index, of: function.parameters, in: call)
                        else { throw Unresolved(description: "a call to \(function.name) passes no \(name)") }
                        return try labels(argument, in: source, depth: depth + 1)
                    }
                default:
                    throw Unresolved(description: "\(name) has no value to follow")
                }
            }
            guard case .name(let member) = chain.links[chain.links.count - 1],
                  let type = type(of: Array(chain.links.dropLast()), at: start, in: source) else {
                throw Unresolved(description: "not a property of a strings value")
            }
            return [Label(reference: "\(type).\(member)", offset: start)]
        }

        /// The strings type a receiver evaluates to: `l10n.s`, a
        /// `FeatureStrings` provider, a `localized(_:)` factory, or a value
        /// declared as one of those.
        private func type(of links: [SwiftSource.Link], at offset: Int, in source: SwiftSource,
                          depth: Int = 0) -> String? {
            if links == [.name("l10n"), .name("s")] || links == [.name("L10n"), .name("shared"), .name("s")] {
                return "Strings"
            }
            if links.count == 3, links[2] == .call, case .name(let root) = links[0],
               case .name(let factory) = links[1] {
                if root == "FeatureStrings", let types = providers[factory], types.count == 1 {
                    return types.first
                }
                return factory == "localized" ? Self.stringsType(root) : nil
            }
            guard depth < 4, links.count == 1, case .name(let name) = links[0] else { return nil }
            switch source.declaration(of: name, visibleAt: offset) {
            case .parameter(let function, let index)?:
                return function.parameters[index].type.flatMap(Self.stringsType)
            case .variable(let declared, let type, let initializer)?:
                if let type { return Self.stringsType(type) }
                guard let initializer else { return nil }
                let chain = source.chain(from: source.skipSpace(from: initializer.lowerBound))
                guard source.skipSpace(from: chain.end) >= initializer.upperBound else { return nil }
                return self.type(of: chain.links, at: declared, in: source, depth: depth + 1)
            case nil:
                return nil
            }
        }

        private static func stringsType(_ name: String) -> String? {
            name.first?.isUppercase == true && name.hasSuffix("Strings")
                && name.allSatisfy({ $0.isLetter || $0.isNumber }) ? name : nil
        }
    }
}

extension SettingsSearchCoverageTests {
    /// A Swift file reduced to its code. Comments, the insides of string
    /// literals and any other non-ASCII byte are blanked to spaces byte for byte,
    /// so an offset is a UTF-8 offset in the file and every brace, comma and
    /// parenthesis left is syntax.
    struct SwiftSource {
        enum Link: Equatable {
            case name(String)
            case call
        }

        struct Argument {
            let label: String?
            let range: Range<Int>
        }

        struct Parameter {
            let label: String?
            let name: String
            let type: String?
            let hasDefault: Bool
        }

        struct Function {
            let name: String
            let offset: Int
            let parameters: [Parameter]
            let body: (open: Int, close: Int)
        }

        enum Declaration {
            case variable(offset: Int, type: String?, initializer: Range<Int>?)
            case parameter(Function, index: Int)
        }

        let path: String
        let blocks: [(open: Int, close: Int)]
        private let bytes: [UInt8]
        private let code: NSString
        private let lineStarts: [Int]
        /// `let` and `var` declarations by name, at the offset of the keyword.
        private let variables: [String: [(start: Int, nameEnd: Int)]]
        private var functions: [Function] = []

        init(path: String, text: String) {
            self.path = path
            let bytes = Self.mask(Array(text.utf8))
            self.bytes = bytes
            code = String(decoding: bytes, as: UTF8.self) as NSString
            lineStarts = [0] + bytes.indices.filter { bytes[$0] == UInt8(ascii: "\n") }.map { $0 + 1 }
            var open: [Int] = []
            var blocks: [(open: Int, close: Int)] = []
            for (offset, byte) in bytes.enumerated() {
                if byte == UInt8(ascii: "{") { open.append(offset) }
                if byte == UInt8(ascii: "}"), let start = open.popLast() { blocks.append((start, offset)) }
            }
            self.blocks = blocks
            var variables: [String: [(start: Int, nameEnd: Int)]] = [:]
            let declaration = try! NSRegularExpression(pattern: #"\b(?:let|var)\s+([A-Za-z_]\w*)\b"#)
            for match in declaration.matches(in: code as String, range: NSRange(location: 0, length: code.length)) {
                let name = match.range(at: 1)
                variables[code.substring(with: name), default: []]
                    .append((match.range.location, name.location + name.length))
            }
            self.variables = variables
            functions = parseFunctions()
        }

        func text(_ range: Range<Int>) -> String {
            code.substring(with: NSRange(location: range.lowerBound, length: range.count))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        func line(at offset: Int) -> Int {
            lineStarts.lastIndex { $0 <= offset }.map { $0 + 1 } ?? 1
        }

        /// Where `text` stands in the code, when it stands there once.
        func uniqueOffset(of text: String) -> Int? {
            let parts = (code as String).components(separatedBy: text)
            return parts.count == 2 ? parts[0].utf8.count : nil
        }

        /// The declaration and assignments of each local declared in `range`
        /// that `range` only writes and never reads.
        func unreadWrites(in range: Range<Int>) -> [Range<Int>] {
            variables.flatMap { name, declarations -> [Range<Int>] in
                let local = declarations.filter { range.contains($0.start) }
                guard !local.isEmpty else { return [] }
                var writes = local.map { $0.start..<statementEnd(from: $0.nameEnd) }
                for match in matches(#"(?<![\w.$])"# + name + #"\b"#, in: range)
                    where !local.contains(where: { $0.nameEnd == match.range.location + name.count }) {
                    let next = skipSpace(from: match.range.location + name.count, newlines: false)
                    guard next + 1 < bytes.count, bytes[next] == UInt8(ascii: "="),
                          bytes[next + 1] != UInt8(ascii: "=") else { return [] }
                    writes.append(match.range.location..<statementEnd(from: next + 1))
                }
                return writes
            }
        }

        func matches(_ pattern: String, in range: Range<Int>? = nil) -> [NSTextCheckingResult] {
            let range = range ?? 0..<bytes.count
            return try! NSRegularExpression(pattern: pattern)
                .matches(in: code as String, range: NSRange(location: range.lowerBound, length: range.count))
        }

        /// The `title:` argument of each call to a Settings component.
        func titleSites() -> [Range<Int>] {
            let pattern = #"\b(?:"# + components.joined(separator: "|") + #")\s*\("#
            return matches(pattern).compactMap { match in
                arguments(at: match.range.location + match.range.length - 1)?
                    .arguments.first { $0.label == "title" }?.range
            }
        }

        /// The comma-separated parts of the list that opens at `paren`, and the
        /// offset of its closing parenthesis.
        private func parts(at paren: Int) -> (ranges: [Range<Int>], close: Int)? {
            var ranges: [Range<Int>] = []
            var depth = 0
            var start = paren + 1
            for offset in (paren + 1)..<bytes.count {
                switch bytes[offset] {
                case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"):
                    depth += 1
                case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"):
                    if depth == 0 {
                        ranges.append(start..<offset)
                        return (ranges.filter { skipSpace(from: $0.lowerBound) < $0.upperBound }, offset)
                    }
                    depth -= 1
                case UInt8(ascii: ",") where depth == 0:
                    ranges.append(start..<offset)
                    start = offset + 1
                default:
                    break
                }
            }
            return nil
        }

        func arguments(at paren: Int) -> (arguments: [Argument], close: Int)? {
            parts(at: paren).map { parts in
                (parts.ranges.map { range in
                    let start = skipSpace(from: range.lowerBound)
                    let name = identifier(at: start)
                    let colon = skipSpace(from: start + name.count, newlines: false)
                    guard !name.isEmpty, colon + 1 < range.upperBound, bytes[colon] == UInt8(ascii: ":"),
                          bytes[colon + 1] != UInt8(ascii: ":") else { return Argument(label: nil, range: range) }
                    return Argument(label: name, range: (colon + 1)..<range.upperBound)
                }, parts.close)
            }
        }

        /// A postfix chain such as `FeatureStrings.notch(l10n.language).title`,
        /// with the line breaks Swift allows before its dots.
        func chain(from start: Int) -> (links: [Link], end: Int) {
            let head = identifier(at: start)
            guard let first = head.first, !first.isNumber else { return ([], start) }
            var links: [Link] = [.name(head)]
            var end = start + head.count
            while true {
                let next = skipSpace(from: end)
                guard next < bytes.count else { break }
                if bytes[next] == UInt8(ascii: ".") {
                    let memberStart = skipSpace(from: next + 1)
                    let member = identifier(at: memberStart)
                    guard !member.isEmpty else { break }
                    links.append(.name(member))
                    end = memberStart + member.count
                } else if next == end, bytes[next] == UInt8(ascii: "("), let call = parts(at: next) {
                    links.append(.call)
                    end = call.close + 1
                } else {
                    break
                }
            }
            return (links, end)
        }

        func skipSpace(from offset: Int, newlines: Bool = true) -> Int {
            var offset = offset
            while offset < bytes.count, bytes[offset] == UInt8(ascii: " ") || bytes[offset] == UInt8(ascii: "\t")
                    || (newlines && bytes[offset] == UInt8(ascii: "\n")) {
                offset += 1
            }
            return offset
        }

        private func identifier(at offset: Int) -> String {
            var end = offset
            while end < bytes.count {
                let byte = bytes[end]
                let letter = (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
                let digit = byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
                guard letter || digit || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$") else { break }
                end += 1
            }
            return String(decoding: bytes[offset..<end], as: UTF8.self)
        }

        private func innermostBlock(containing offset: Int) -> (open: Int, close: Int)? {
            blocks.filter { $0.open < offset && offset < $0.close }.max { $0.open < $1.open }
        }

        /// Functions with a body. Between the parameter list and the body only
        /// effects and a return type may stand, so a requirement without a body
        /// never borrows the next block.
        private func parseFunctions() -> [Function] {
            matches(#"\bfunc\s+(\w+)\s*(?:<[^>{]*>)?\s*\("#).compactMap { match in
                guard let list = parts(at: match.range.location + match.range.length - 1),
                      let body = blocks.filter({ $0.open > list.close }).min(by: { $0.open < $1.open })
                else { return nil }
                let signature = text((list.close + 1)..<body.open)
                guard signature.isEmpty || ["->", "async", "throws", "rethrows", "where"]
                    .contains(where: { signature.hasPrefix($0) }),
                      !["func ", "var ", "let ", "}"].contains(where: { signature.contains($0) }) else { return nil }
                return Function(name: code.substring(with: match.range(at: 1)), offset: match.range.location,
                                parameters: list.ranges.map(parameter), body: body)
            }
        }

        /// `_ title: String`, `symbol: String` or `caption: String? = nil`.
        private func parameter(_ range: Range<Int>) -> Parameter {
            let parts = text(range).split(separator: ":", maxSplits: 1).map(String.init)
            let names = parts[0].split(separator: " ").map(String.init).filter { !$0.hasPrefix("@") }
            let typeAndDefault = parts.count > 1 ? parts[1] : ""
            let type = typeAndDefault.split(separator: "=", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let name = names.last ?? ""
            let label = names.count > 1 ? names[0] : name
            return Parameter(label: label == "_" ? nil : label, name: name, type: type,
                             hasDefault: typeAndDefault.contains("="))
        }

        /// The declaration of `name` that code at `offset` sees. The innermost
        /// scope wins. Within one scope a local declared before `offset` wins
        /// over a parameter, which wins over a member declared further down.
        func declaration(of name: String, visibleAt offset: Int) -> Declaration? {
            var candidates: [(scope: Int, rank: Int, declaration: Declaration)] = []
            for variable in variables[name] ?? [] {
                let scope = innermostBlock(containing: variable.start)
                guard scope.map({ $0.open < offset && offset < $0.close }) ?? true else { continue }
                var cursor = skipSpace(from: variable.nameEnd, newlines: false)
                var type: String?
                if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ":") {
                    let typeStart = skipSpace(from: cursor + 1, newlines: false)
                    type = identifier(at: typeStart)
                    cursor = skipSpace(from: typeStart + (type?.count ?? 0), newlines: false)
                }
                var initializer: Range<Int>?
                if cursor + 1 < bytes.count, bytes[cursor] == UInt8(ascii: "="),
                   bytes[cursor + 1] != UInt8(ascii: "=") {
                    initializer = (cursor + 1)..<statementEnd(from: cursor + 1)
                }
                candidates.append((scope?.open ?? -1, variable.start < offset ? variable.start : -variable.start - 2,
                                   .variable(offset: variable.start, type: type, initializer: initializer)))
            }
            for function in functions where function.body.open < offset && offset < function.body.close {
                if let index = function.parameters.firstIndex(where: { $0.name == name }) {
                    candidates.append((function.body.open, -1, .parameter(function, index: index)))
                }
            }
            return candidates.max { ($0.scope, $0.rank) < ($1.scope, $1.rank) }?.declaration
        }

        /// Where an initializer ends: a line break, `;` or `,`, or a bracket that
        /// closes around it. A line that starts with `.` continues the chain.
        private func statementEnd(from start: Int) -> Int {
            var depth = 0
            var offset = start
            while offset < bytes.count {
                switch bytes[offset] {
                case UInt8(ascii: "("), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"), UInt8(ascii: "{"):
                    if depth == 0 { return offset }
                    depth -= 1
                case UInt8(ascii: ";"), UInt8(ascii: ","):
                    if depth == 0 { return offset }
                case UInt8(ascii: "\n"):
                    let next = skipSpace(from: offset)
                    if depth == 0, next >= bytes.count || bytes[next] != UInt8(ascii: ".") { return offset }
                default:
                    break
                }
                offset += 1
            }
            return offset
        }

        /// The arguments of every call to `function` inside the type that
        /// declares it.
        func calls(to function: Function) -> [[Argument]] {
            let owner = innermostBlock(containing: function.offset)
            let range = owner.map { ($0.open + 1)..<$0.close } ?? 0..<bytes.count
            return matches(#"(?<![\w.])(?:self\.)?"# + function.name + #"\s*\("#, in: range).compactMap { match in
                guard !(function.offset..<function.body.open).contains(match.range.location) else { return nil }
                return arguments(at: match.range.location + match.range.length - 1)?.arguments
            }
        }

        /// The argument a call passes for `parameters[index]`: labels match in
        /// order, and a parameter with a default may be left out.
        static func argument(for index: Int, of parameters: [Parameter], in call: [Argument]) -> Range<Int>? {
            var next = 0
            for (position, parameter) in parameters.enumerated() {
                if next < call.count, call[next].label == parameter.label {
                    if position == index { return call[next].range }
                    next += 1
                } else if !parameter.hasDefault || position == index {
                    return nil
                }
            }
            return nil
        }

        private static func mask(_ input: [UInt8]) -> [UInt8] {
            enum Mode {
                case code
                case interpolation(depth: Int)
                case string(delimiter: Int, pounds: Int)
            }
            let quote = UInt8(ascii: "\""), pound = UInt8(ascii: "#"), slash = UInt8(ascii: "/")
            let star = UInt8(ascii: "*"), newline = UInt8(ascii: "\n")
            var output = input.map { $0 < 0x80 ? $0 : UInt8(ascii: " ") }
            var modes: [Mode] = [.code]
            var index = 0
            func byte(_ offset: Int) -> UInt8 { offset < input.count ? input[offset] : 0 }
            func count(_ value: UInt8, from offset: Int) -> Int {
                var end = offset
                while byte(end) == value { end += 1 }
                return end - offset
            }
            func blank(_ range: Range<Int>) {
                for offset in range where offset < input.count && input[offset] != newline {
                    output[offset] = UInt8(ascii: " ")
                }
            }
            while index < input.count {
                let start = index
                let insideLiteral = modes.count > 1
                if case .string(let delimiter, let pounds) = modes[modes.count - 1] {
                    if input[index] == UInt8(ascii: "\\"), count(pound, from: index + 1) >= pounds {
                        index += 1 + pounds
                        if byte(index) == UInt8(ascii: "(") { modes.append(.interpolation(depth: 0)) }
                        index += 1
                    } else if input[index] == quote, count(quote, from: index) >= delimiter,
                              count(pound, from: index + delimiter) >= pounds {
                        modes.removeLast()
                        index += delimiter + pounds
                    } else {
                        index += 1
                    }
                    blank(start..<index)
                    continue
                }
                if input[index] == slash, byte(index + 1) == slash {
                    while index < input.count, input[index] != newline { index += 1 }
                    blank(start..<index)
                    continue
                }
                if input[index] == slash, byte(index + 1) == star {
                    var depth = 0
                    repeat {
                        if byte(index) == slash, byte(index + 1) == star {
                            depth += 1
                            index += 2
                        } else if byte(index) == star, byte(index + 1) == slash {
                            depth -= 1
                            index += 2
                        } else {
                            index += 1
                        }
                    } while depth > 0 && index < input.count
                    blank(start..<index)
                    continue
                }
                let pounds = count(pound, from: index)
                if byte(index + pounds) == quote {
                    let delimiter = count(quote, from: index + pounds) >= 3 ? 3 : 1
                    modes.append(.string(delimiter: delimiter, pounds: pounds))
                    index += pounds + delimiter
                    if insideLiteral { blank(start..<index) }
                    continue
                }
                if case .interpolation(let depth) = modes[modes.count - 1] {
                    if input[index] == UInt8(ascii: "(") {
                        modes[modes.count - 1] = .interpolation(depth: depth + 1)
                    } else if input[index] == UInt8(ascii: ")") {
                        modes[modes.count - 1] = .interpolation(depth: depth - 1)
                        if depth == 0 { modes.removeLast() }
                    }
                }
                index += 1
                if insideLiteral { blank(start..<index) }
            }
            return output
        }
    }
}
