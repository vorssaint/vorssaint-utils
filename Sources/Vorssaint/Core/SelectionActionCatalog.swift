// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
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
    case addToScratchpad

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .cut: return "scissors"
        case .paste: return "clipboard"
        case .pastePlain: return "sparkle.text.clipboard"
        case .delete: return "delete.left"
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
             .urlEncode, .urlDecode, .base64Encode, .base64Decode, .calculate:
            return true
        case .copy, .addToScratchpad:
            return false
        }
    }

    /// Whether this row shows a settings gear beside its on/off switch. The
    /// switch always means on/off; the gear (when present) only ever holds
    /// the action's own configuration.
    var hasSettings: Bool {
        false
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
        // looksLikeExpression is a charset prefilter, not the parser - it
        // rejects prose cheaply, but "50%", "1/0" and "(1+2" all pass it and
        // then return nil from the evaluator. Same shape as the two decode
        // guards below: run the actual operation, don't approximate it.
        case .calculate:
            return SelectionActionCatalog.looksLikeExpression(text) && ArithmeticEvaluator.evaluate(text) != nil
        // Running the actual decode instead of approximating it: a stray
        // "%" (as in "100% sure") isn't valid percent-encoding, and a plain
        // word ("test", "code") is a syntactically valid but meaningless
        // base64 decode. Both guards below run the same operation the
        // action itself would, so a click never no-ops.
        case .urlDecode: return text.removingPercentEncoding.map { $0 != text } ?? false
        case .base64Decode:
            return Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) } != nil
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

enum SelectionActionCatalog {
    /// The everyday actions a fresh install starts with; everything else is
    /// one switch away in Settings rather than cluttering the bar by default.
    static let defaultEnabled: Set<SelectionAction> = [
        .copy, .cut, .paste, .calculate,
    ]

    /// Persisted as the *enabled* set, not the disabled one: a future update
    /// that adds a new `SelectionAction` case must have that case come up
    /// off for anyone who already customized their toggles, not silently on
    /// because it's absent from an old "disabled" string written before the
    /// case existed.
    static func enabledActions(from raw: String) -> Set<SelectionAction> {
        Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(SelectionAction.init(rawValue:)))
    }

    /// Sorted so the same set always writes the same string.
    static func storageValue(for actions: Set<SelectionAction>) -> String {
        actions.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// The default value for `DefaultsKey.selectionActionsEnabledActions`.
    static var defaultEnabledStorageValue: String {
        storageValue(for: defaultEnabled)
    }

    static func isEnabled(_ action: SelectionAction, enabledRaw: String) -> Bool {
        enabledActions(from: enabledRaw).contains(action)
    }

    /// The actions to offer for a selection right now: enabled in Settings,
    /// applicable to this particular text/context, in the person's order.
    static func availableActions(for text: String,
                                 isEditable: Bool,
                                 enabledRaw: String,
                                 orderRaw: String) -> [SelectionAction] {
        let order = Defaults.sanitizedPanelItemOrder(orderRaw,
                                                      defaultOrder: SelectionAction.allCases.map(\.rawValue))
            .compactMap(SelectionAction.init(rawValue:))
        return order.filter {
            isEnabled($0, enabledRaw: enabledRaw) && $0.appliesTo(text: text, isEditable: isEditable)
        }
    }

    /// A conservative "this looks like arithmetic" check: only digits, the
    /// four basic operators, parentheses, decimal points and whitespace —
    /// the same character set `ArithmeticEvaluator` is willing to parse.
    static func looksLikeExpression(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.contains(where: \.isNumber) else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        guard trimmed.contains(where: { "+-*/%".contains($0) }) else { return false }
        // A run of digit groups joined only by hyphens, with no spaces or
        // other operators - 2026-08-26, 555-1234, 10-20 - reads as a date,
        // a phone number or a range far more often than as a subtraction
        // someone wants Calculate to run silently. Syntactically valid
        // arithmetic, rejected anyway.
        return !isHyphenatedDigitGroups(trimmed)
    }

    private static func isHyphenatedDigitGroups(_ text: String) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count >= 2 else { return false }
        return groups.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
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
            // `.newlines` matches `\r` and `\n` as separate members, so
            // splitting a CRLF file on it directly inserts a spurious blank
            // line between every pair of real lines. Normalize first.
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            return .lines(normalized.components(separatedBy: .newlines))
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count > 1 {
            return .words(words)
        }
        return .letters(Array(text))
    }

    /// Locale-aware and numeric-aware: plain `<` sorts by raw Unicode scalar
    /// value, which puts "10" before "2" and capital letters before every
    /// lowercase one - not what someone sorting a list of lines expects.
    static func sorted(_ text: String) -> String {
        switch granularity(of: text) {
        case .lines(let items):
            return items.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .joined(separator: "\n")
        case .words(let items):
            return items.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .joined(separator: " ")
        case .letters(let items):
            return String(items.sorted {
                String($0).localizedStandardCompare(String($1)) == .orderedAscending
            })
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
