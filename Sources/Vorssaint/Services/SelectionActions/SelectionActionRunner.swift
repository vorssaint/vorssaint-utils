// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit

/// Carries out one `SelectionAction` against a captured selection. Actions
/// that only read the selection open a URL (or, for Run in Terminal, an
/// AppleScript event); actions that rewrite it hand the new text to
/// `SyntheticPasteSupport.replaceSelection(with:)` (the pasteboard-swap-and-
/// ⌘V primitive Paste Plain also uses) or, for Cut/Delete, post a synthetic
/// Delete keystroke via `SyntheticPasteSupport.deleteSelection()`. Must be
/// called on the main thread — Run in Terminal's confirmation touches
/// `NSAlert` directly, the same assumption the rest of this feature's UI
/// code makes.
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
        case .convertCurrency:
            convertCurrency(snapshot.text)
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

    private static func formatResult(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var result = String(format: "%.6f", value)
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
