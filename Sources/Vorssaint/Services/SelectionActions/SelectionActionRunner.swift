// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Carries out one `SelectionAction` against a captured selection. Actions
/// that only read the selection open a URL (or, for Run in Terminal, an
/// AppleScript event); actions that rewrite it either hand the new text to
/// `SyntheticPasteSupport.replaceSelection(with:)` (the pasteboard-swap-and-
/// ⌘V primitive Paste Plain also uses) or, for Cut/Delete, post a synthetic
/// Delete keystroke via `SyntheticPasteSupport.deleteSelection()` — pasting
/// an empty string turned out not to reliably clear a selection in every
/// field, where a real Delete keystroke does. Must be called on the main
/// thread — several cases touch AppKit UI (`NSAlert`, `ScratchpadService`)
/// directly, the same assumption the rest of this feature's UI code makes.
enum SelectionActionRunner {
    static func run(_ action: SelectionAction, on snapshot: SelectionSnapshot) {
        switch action {
        case .copy:
            copyToPasteboard(snapshot.text)
        case .cut:
            copyToPasteboard(snapshot.text)
            SyntheticPasteSupport.deleteSelection()
        case .paste:
            guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
            SyntheticPasteSupport.replaceSelection(with: clipboard)
        case .pastePlain:
            guard let plain = PastePlainService.plainText(from: NSPasteboard.general) else { return }
            SyntheticPasteSupport.replaceSelection(with: plain)
        case .delete:
            SyntheticPasteSupport.deleteSelection()
        case .searchWeb:
            open(searchURL(for: snapshot.text))
        case .openLink:
            open(link(in: snapshot.text))
        case .openMail:
            open(mailto(in: snapshot.text))
        case .translate:
            open(translateURL(for: snapshot.text))
        case .sendToAI:
            open(sendToAIURL(for: snapshot.text))
        case .runInTerminal:
            runInTerminal(snapshot.text)
        case .uppercase:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.uppercased())
        case .lowercase:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.lowercased())
        case .capitalize:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.capitalized)
        case .removeSpaces:
            SyntheticPasteSupport.replaceSelection(with: removingAllSpaces(snapshot.text))
        case .underscore:
            SyntheticPasteSupport.replaceSelection(with: underscored(snapshot.text))
        case .joinLines:
            SyntheticPasteSupport.replaceSelection(with: joinedLines(snapshot.text))
        case .commaList:
            SyntheticPasteSupport.replaceSelection(with: commaList(snapshot.text))
        case .sort:
            SyntheticPasteSupport.replaceSelection(with: TextListSupport.sorted(snapshot.text))
        case .reverse:
            SyntheticPasteSupport.replaceSelection(with: TextListSupport.reversed(snapshot.text))
        case .random:
            SyntheticPasteSupport.replaceSelection(with: TextListSupport.shuffled(snapshot.text))
        case .quotes:
            SyntheticPasteSupport.replaceSelection(with: "\"\(snapshot.text)\"")
        case .brackets:
            SyntheticPasteSupport.replaceSelection(with: "(\(snapshot.text))")
        case .urlEncode:
            let encoded = snapshot.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            SyntheticPasteSupport.replaceSelection(with: encoded ?? snapshot.text)
        case .urlDecode:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.removingPercentEncoding ?? snapshot.text)
        case .base64Encode:
            SyntheticPasteSupport.replaceSelection(with: Data(snapshot.text.utf8).base64EncodedString())
        case .base64Decode:
            guard let data = Data(base64Encoded: snapshot.text, options: .ignoreUnknownCharacters),
                  let decoded = String(data: data, encoding: .utf8)
            else { return }
            SyntheticPasteSupport.replaceSelection(with: decoded)
        case .calculate:
            guard let value = ArithmeticEvaluator.evaluate(snapshot.text) else { return }
            SyntheticPasteSupport.replaceSelection(with: formatResult(value))
        case .convertCurrency:
            convertCurrency(snapshot.text)
        case .addToScratchpad:
            ScratchpadService.shared.show()
            let existing = ScratchpadService.shared.text
            let separator = existing.isEmpty ? "" : "\n"
            ScratchpadService.shared.text = existing + separator + snapshot.text
        }
    }

    // MARK: - Clipboard / URLs

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func searchURL(for text: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        return components?.url
    }

    private static func translateURL(for text: String) -> URL? {
        var components = URLComponents(string: "https://translate.google.com/")
        components?.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "op", value: "translate"),
        ]
        return components?.url
    }

    /// Both URLs and both parameter names are exactly what was asked for:
    /// ChatGPT's `prompt`/`temporary-chat` and Claude's `q`.
    private static func sendToAIURL(for text: String) -> URL? {
        let service = SelectionActionsAIService.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.selectionActionsAIService))
        switch service {
        case .chatgpt:
            var items = [URLQueryItem(name: "prompt", value: text)]
            if UserDefaults.standard.bool(forKey: DefaultsKey.selectionActionsAITemporaryChat) {
                items.append(URLQueryItem(name: "temporary-chat", value: "true"))
            }
            var components = URLComponents(string: "https://chatgpt.com/")
            components?.queryItems = items
            return components?.url
        case .claude:
            var components = URLComponents(string: "https://claude.ai/new")
            components?.queryItems = [URLQueryItem(name: "q", value: text)]
            return components?.url
        }
    }

    private static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        else { return nil }
        return match.url
    }

    private static func mailto(in text: String) -> URL? {
        guard let url = link(in: text), url.scheme == "mailto" else { return nil }
        return url
    }

    // MARK: - Run in Terminal

    /// Shows a native confirmation before ever touching the shell, unless
    /// the person switched that off in the action's own settings — this
    /// runs whatever text was selected as a shell command, so the default is
    /// to ask.
    private static func runInTerminal(_ command: String) {
        let strings = FeatureStrings.selectionActions(L10n.shared.language)
        let confirm = UserDefaults.standard.object(forKey: DefaultsKey.selectionActionsTerminalConfirm) as? Bool
            ?? true
        if confirm {
            let alert = NSAlert()
            alert.messageText = strings.terminalConfirmTitle
            alert.informativeText = command
            alert.addButton(withTitle: strings.terminalConfirmRun)
            alert.addButton(withTitle: strings.terminalConfirmCancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        executeInTerminal(command)
    }

    private static func executeInTerminal(_ command: String) {
        let target = SelectionActionsTerminalTarget.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.selectionActionsTerminalTarget))
        DispatchQueue.global(qos: .userInitiated).async {
            let literal = AppleScriptRunner.literal(command)
            let source: String
            switch target {
            case .window:
                source = """
                tell application "Terminal"
                    activate
                    do script \(literal)
                end tell
                """
            case .tab:
                // "in front window" is Terminal's own idiom for a new tab in
                // the existing frontmost window; with no window yet, a plain
                // `do script` opens the first one exactly like Window mode.
                source = """
                tell application "Terminal"
                    activate
                    if (count of windows) = 0 then
                        do script \(literal)
                    else
                        do script \(literal) in front window
                    end if
                end tell
                """
            }
            AppleScriptRunner.run(source)
        }
    }

    // MARK: - Text transforms

    /// Every space and tab, leading, trailing, and between words — not a
    /// collapse-repeats normalize, a full strip.
    private static func removingAllSpaces(_ text: String) -> String {
        text.filter { $0 != " " && $0 != "\t" }
    }

    private static func underscored(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func joinedLines(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Lines become a comma list when the selection has line breaks; a
    /// single word has nothing to list, so it passes through unchanged.
    private static func commaList(_ text: String) -> String {
        if text.contains(where: \.isNewline) {
            let items = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return items.joined(separator: ", ")
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return text }
        return words.joined(separator: ", ")
    }

    // MARK: - Calculate

    private static func formatResult(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var result = String(format: "%.6f", value)
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: - Convert Currency

    private static func convertCurrency(_ text: String) {
        guard let detected = CurrencyDetector.detect(in: text) else { return }
        let target = UserDefaults.standard.string(forKey: DefaultsKey.selectionActionsCurrencyTarget) ?? "USD"
        CurrencyConversionSupport.convert(amount: detected.amount,
                                          from: detected.currencyCode,
                                          to: target) { converted in
            guard let converted else { return }
            DispatchQueue.main.async {
                SyntheticPasteSupport.replaceSelection(with: "\(formatResult(converted)) \(target.uppercased())")
            }
        }
    }
}

/// A tiny, hand-rolled arithmetic evaluator (digits, `+ - * / %` and
/// parentheses) — deliberately not `NSExpression`, whose format-string
/// parser raises an uncaught `NSException` on malformed input (verified:
/// `NSExpression(format: "3++4")` crashes the process; Swift cannot catch an
/// Objective-C exception). Malformed input here just returns nil.
enum ArithmeticEvaluator {
    static func evaluate(_ text: String) -> Double? {
        let chars = Array(text.filter { !$0.isWhitespace })
        var index = 0

        func peek() -> Character? { index < chars.count ? chars[index] : nil }

        func parseNumber() -> Double? {
            var digits = ""
            while let c = peek(), c.isNumber || c == "." {
                digits.append(c)
                index += 1
            }
            return digits.isEmpty ? nil : Double(digits)
        }

        func parseFactor() -> Double? {
            if peek() == "-" {
                index += 1
                guard let value = parseFactor() else { return nil }
                return -value
            }
            if peek() == "+" {
                index += 1
                return parseFactor()
            }
            if peek() == "(" {
                index += 1
                guard let value = parseExpression() else { return nil }
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            return parseNumber()
        }

        func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                switch op {
                case "*": value *= rhs
                case "/":
                    guard rhs != 0 else { return nil }
                    value /= rhs
                default:
                    guard rhs != 0 else { return nil }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        guard let result = parseExpression(), index == chars.count, result.isFinite else { return nil }
        return result
    }
}
