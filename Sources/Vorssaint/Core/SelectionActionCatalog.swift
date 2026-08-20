// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// One action the Selection Actions bar can offer. Raw values are storage
/// ids for the list of actions the person switched off and the order they
/// dragged them into, so they never change. Declaration order is the
/// canonical/default order, used the first time (and whenever a future case
/// is appended) — see `PanelLayout.itemOrder`.
enum SelectionAction: String, CaseIterable, Identifiable, PanelOrderItem {
    case copy
    case cut
    case paste
    case pastePlain
    case delete
    case searchWeb
    case openLink
    case openMail
    case translate
    case sendToAI
    case runInTerminal
    case uppercase
    case lowercase
    case capitalize
    case removeSpaces
    case underscore
    case joinLines
    case commaList
    case sort
    case reverse
    case random
    case quotes
    case brackets
    case urlEncode
    case urlDecode
    case base64Encode
    case base64Decode
    case calculate
    case convertCurrency
    case addToScratchpad

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .cut: return "scissors"
        case .paste: return "clipboard"
        case .pastePlain: return "sparkle.text.clipboard"
        case .delete: return "delete.left"
        case .searchWeb: return "magnifyingglass"
        case .openLink: return "link"
        case .openMail: return "envelope"
        case .translate: return "translate"
        case .sendToAI: return "sparkles"
        case .runInTerminal: return "greaterthanorequalto"
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .capitalize: return "textformat.abc"
        case .removeSpaces: return "eraser.line.dashed"
        case .underscore: return "underline"
        case .joinLines: return "arrow.triangle.merge"
        case .commaList: return "list.bullet.badge.ellipsis"
        case .sort: return "arrow.up.arrow.down"
        case .reverse: return "arrow.triangle.swap"
        case .random: return "shuffle"
        case .quotes: return "quote.opening"
        case .brackets: return "parentheses"
        case .urlEncode: return "arrow.right.to.line"
        case .urlDecode: return "arrow.left.to.line"
        case .base64Encode: return "chevron.right.2"
        case .base64Decode: return "chevron.left.2"
        case .calculate: return "function"
        case .convertCurrency: return "dollarsign.arrow.circlepath"
        case .addToScratchpad: return "note.text"
        }
    }

    /// Rewrites the selection in place (needs an editable focused element)
    /// rather than just reading it.
    var isTransform: Bool {
        switch self {
        case .cut, .paste, .pastePlain, .delete,
             .uppercase, .lowercase, .capitalize, .removeSpaces, .underscore,
             .joinLines, .commaList, .sort, .reverse, .random, .quotes, .brackets,
             .urlEncode, .urlDecode, .base64Encode, .base64Decode, .calculate, .convertCurrency:
            return true
        case .copy, .searchWeb, .openLink, .openMail, .translate, .sendToAI,
             .runInTerminal, .addToScratchpad:
            return false
        }
    }

    /// Whether this row shows a settings gear beside its on/off switch. The
    /// switch always means on/off; the gear (when present) only ever holds
    /// the action's own configuration.
    var hasSettings: Bool {
        switch self {
        case .sendToAI, .runInTerminal, .convertCurrency: return true
        default: return false
        }
    }

    /// Whether this action makes sense for the given selection right now.
    /// Every transform needs an editable target; a few actions also need the
    /// text itself (or something else) to look a particular way. An empty
    /// selection (an editable field with nothing selected in it, offered so
    /// there's still a way to Paste without a keyboard) rules out everything
    /// except Paste itself.
    func appliesTo(text: String, isEditable: Bool) -> Bool {
        if isTransform, !isEditable { return false }
        if text.isEmpty, self != .paste, self != .pastePlain { return false }
        switch self {
        case .paste, .pastePlain:
            return NSPasteboard.general.string(forType: .string) != nil
        case .openLink: return SelectionActionCatalog.looksLikeLink(text)
        case .openMail: return SelectionActionCatalog.looksLikeEmail(text)
        case .calculate: return SelectionActionCatalog.looksLikeExpression(text)
        case .convertCurrency: return CurrencyDetector.detect(in: text) != nil
        case .addToScratchpad: return AppFeature.scratchpad.isAvailable
        default: return true
        }
    }
}

/// Whether the bar shows each action as an icon or as a short word.
enum SelectionActionsDisplayStyle: String {
    case icon
    case word

    static func sanitized(_ raw: String?) -> SelectionActionsDisplayStyle {
        SelectionActionsDisplayStyle(rawValue: raw ?? "") ?? .icon
    }
}

/// Which service "Send to AI" opens.
enum SelectionActionsAIService: String {
    case chatgpt
    case claude

    static func sanitized(_ raw: String?) -> SelectionActionsAIService {
        SelectionActionsAIService(rawValue: raw ?? "") ?? .chatgpt
    }
}

/// Where "Run in Terminal" runs the command.
enum SelectionActionsTerminalTarget: String {
    case tab
    case window

    static func sanitized(_ raw: String?) -> SelectionActionsTerminalTarget {
        SelectionActionsTerminalTarget(rawValue: raw ?? "") ?? .tab
    }
}

enum SelectionActionCatalog {
    /// The everyday actions a fresh install starts with; everything else is
    /// one switch away in Settings rather than cluttering the bar by default.
    static let defaultEnabled: Set<SelectionAction> = [
        .copy, .cut, .paste, .searchWeb, .openLink, .openMail, .translate, .calculate,
    ]

    static func disabledActions(from raw: String) -> Set<SelectionAction> {
        Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(SelectionAction.init(rawValue:)))
    }

    /// Sorted so the same set always writes the same string.
    static func storageValue(for actions: Set<SelectionAction>) -> String {
        actions.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// The default value for `DefaultsKey.selectionActionsDisabledActions`:
    /// every action that isn't in `defaultEnabled`.
    static var defaultDisabledStorageValue: String {
        storageValue(for: Set(SelectionAction.allCases).subtracting(defaultEnabled))
    }

    static func isEnabled(_ action: SelectionAction, disabledRaw: String) -> Bool {
        !disabledActions(from: disabledRaw).contains(action)
    }

    /// The actions to offer for a selection right now: enabled in Settings,
    /// applicable to this particular text/context, in the person's order.
    static func availableActions(for text: String,
                                 isEditable: Bool,
                                 disabledRaw: String,
                                 orderRaw: String) -> [SelectionAction] {
        let order = Defaults.sanitizedPanelItemOrder(orderRaw,
                                                      defaultOrder: SelectionAction.allCases.map(\.rawValue))
            .compactMap(SelectionAction.init(rawValue:))
        return order.filter {
            isEnabled($0, disabledRaw: disabledRaw) && $0.appliesTo(text: text, isEditable: isEditable)
        }
    }

    static func looksLikeLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return false }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range), match.range == range else {
            return false
        }
        return match.url != nil
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return false }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range), match.range == range,
              let url = match.url, url.scheme == "mailto"
        else { return false }
        return true
    }

    /// A conservative "this looks like arithmetic" check: only digits, the
    /// four basic operators, parentheses, decimal points and whitespace —
    /// the same character set `ArithmeticEvaluator` is willing to parse.
    static func looksLikeExpression(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.contains(where: \.isNumber) else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return trimmed.contains(where: { "+-*/%".contains($0) })
    }
}

/// The smallest meaningful list inside a selection: lines when there are
/// line breaks, else space-separated words, else the individual characters
/// of a single word — so "Reverse" on one word reverses its letters instead
/// of doing nothing.
enum TextListGranularity {
    case lines([String])
    case words([String])
    case letters([Character])
}

enum TextListSupport {
    static func granularity(of text: String) -> TextListGranularity {
        if text.contains(where: \.isNewline) {
            return .lines(text.components(separatedBy: .newlines))
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count > 1 {
            return .words(words)
        }
        return .letters(Array(text))
    }

    static func sorted(_ text: String) -> String {
        switch granularity(of: text) {
        case .lines(let items): return items.sorted().joined(separator: "\n")
        case .words(let items): return items.sorted().joined(separator: " ")
        case .letters(let items): return String(items.sorted())
        }
    }

    static func reversed(_ text: String) -> String {
        switch granularity(of: text) {
        case .lines(let items): return items.reversed().joined(separator: "\n")
        case .words(let items): return items.reversed().joined(separator: " ")
        case .letters(let items): return String(items.reversed())
        }
    }

    static func shuffled(_ text: String) -> String {
        switch granularity(of: text) {
        case .lines(let items): return items.shuffled().joined(separator: "\n")
        case .words(let items): return items.shuffled().joined(separator: " ")
        case .letters(let items): return String(items.shuffled())
        }
    }
}
