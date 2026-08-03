// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The command bar's inline calculator: whatever looks like a sum is answered
/// on the first row instead of being searched for. Pure and locale aware, so
/// "1.234,5 + 10%" reads the way the person's Mac writes numbers.
///
/// Deliberately narrow: arithmetic, parentheses, powers and percentages. It
/// refuses anything it cannot fully parse, so a search like "1password" or
/// "volume 20" never turns into a wrong answer.
enum CommandBarMath {
    /// Words that read as "percent OF a number" across the languages the app
    /// speaks. Parser vocabulary, not visible text: people type in their own
    /// words regardless of the interface language.
    private static let ofWords: Set<String> = ["of", "de", "da", "do", "von", "di", "del", "dal"]

    struct Result: Equatable {
        /// The value, formatted the way this Mac writes numbers.
        let formatted: String
        let value: Double
    }

    /// The answer for `input`, or nil when it is not an expression. Requires a
    /// digit and a real operation, so plain words and "verb number" commands
    /// are left to the search.
    static func evaluate(_ input: String,
                         decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                         groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                         locale: Locale = .current) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 120, trimmed.contains(where: \.isNumber) else { return nil }
        // A date or a clock time is written with the same characters as a
        // subtraction or a division. Someone looking for what they copied on
        // 2026-07-27 must not be told the answer is 1992.
        guard !looksLikeDateOrTime(trimmed) else { return nil }

        guard let tokens = tokenize(trimmed,
                                    decimalSeparator: Character(decimalSeparator.first.map(String.init) ?? "."),
                                    groupingSeparator: Character(groupingSeparator.first.map(String.init) ?? ","))
        else { return nil }
        // One lonely number is not a question; answering "5 = 5" only pushes
        // real results down. A bare "50%" is not one either.
        guard tokens.contains(where: { $0.isOperation && $0 != .percent }) else { return nil }

        var parser = Parser(tokens: tokens)
        guard let operand = parser.parseExpression(), parser.isAtEnd else { return nil }
        let value = significantRounded(operand.value)
        guard value.isFinite else { return nil }
        guard let formatted = format(value, locale: locale) else { return nil }
        return Result(formatted: formatted, value: value)
    }

    /// Rounds away floating point noise (0.1 + 0.2 must read as 0.3) and
    /// writes the number with the separators of this Mac.
    static func format(_ value: Double, locale: Locale = .current) -> String? {
        let rounded = significantRounded(value)
        guard rounded.isFinite else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        let magnitude = abs(rounded)
        if rounded != 0, magnitude >= 1e12 || magnitude < 1e-6 {
            // Plain digits would print a billionth as "0" and a huge product
            // as a wall of zeros; both read as a wrong answer.
            formatter.numberStyle = .scientific
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 8
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 8
        }
        // -0 is an answer no one asked for.
        return formatter.string(from: NSNumber(value: rounded == 0 ? 0 : rounded))
    }

    /// True for "2026-07-27", "27/07/2026" and "10:30": groups of digits held
    /// together by a single kind of separator, with nothing else around them.
    static func looksLikeDateOrTime(_ input: String) -> Bool {
        for separator in ["-", "/", ":"] as [Character] {
            let parts = input.split(separator: separator, omittingEmptySubsequences: false)
            guard parts.count >= 2, parts.count <= 3 else { continue }
            guard parts.allSatisfy({ part in
                let digits = part.trimmingCharacters(in: .whitespaces)
                return !digits.isEmpty && digits.count <= 4 && digits.allSatisfy(\.isNumber)
            }) else { continue }
            // Two plain numbers around a minus really can be a subtraction, so
            // only the shapes that read as a date or a time are refused.
            if separator == ":" { return true }
            if parts.count == 3 { return true }
        }
        return false
    }

    private static func significantRounded(_ value: Double) -> Double {
        guard value != 0, value.isFinite else { return value }
        let digits = 10.0
        let magnitude = floor(log10(abs(value)))
        let factor = pow(10.0, digits - magnitude - 1)
        guard factor.isFinite, factor != 0 else { return value }
        let scaled = (value * factor).rounded()
        guard scaled.isFinite else { return value }
        return scaled / factor
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case number(Double)
        case plus, minus, times, divide, power, percent
        case leftParen, rightParen
        case ofWord

        var isOperation: Bool {
            switch self {
            case .plus, .minus, .times, .divide, .power, .percent, .ofWord: return true
            case .number, .leftParen, .rightParen: return false
            }
        }
    }

    static func tokenize(_ input: String,
                         decimalSeparator: Character,
                         groupingSeparator: Character) -> [Token]? {
        var tokens: [Token] = []
        var characters = Array(input)
        var index = 0

        func readWord() -> String {
            var word = ""
            while index < characters.count, characters[index].isLetter {
                word.append(characters[index])
                index += 1
            }
            return word.lowercased()
        }

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isNumber || character == decimalSeparator || character == groupingSeparator {
                guard let number = readNumber(&characters, &index,
                                              decimalSeparator: decimalSeparator,
                                              groupingSeparator: groupingSeparator)
                else { return nil }
                tokens.append(.number(number))
                continue
            }
            if character.isLetter {
                let word = readWord()
                // People write "3 x 4" as often as "3 * 4".
                if word == "x", case .number = tokens.last {
                    tokens.append(.times)
                    continue
                }
                guard ofWords.contains(word) else { return nil }
                tokens.append(.ofWord)
                continue
            }
            index += 1
            switch character {
            case "+": tokens.append(.plus)
            case "-", "\u{2212}": tokens.append(.minus)          // also the real minus sign
            case "*", "\u{00D7}": tokens.append(.times)           // and the multiplication sign
            case "/", "\u{00F7}": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "%": tokens.append(.percent)
            case "(", "[": tokens.append(.leftParen)
            case ")", "]": tokens.append(.rightParen)
            case "=": break                                       // a trailing "=" is just habit
            default: return nil
            }
        }
        return tokens.isEmpty ? nil : tokens
    }

    /// Reads one number, deciding what each separator means. When both appear,
    /// the last one is the decimal point. When only one appears, it is grouping
    /// only if it looks the part: the Mac's grouping separator followed by
    /// exactly three digits.
    private static func readNumber(_ characters: inout [Character],
                                   _ index: inout Int,
                                   decimalSeparator: Character,
                                   groupingSeparator: Character) -> Double? {
        var raw = ""
        while index < characters.count {
            let character = characters[index]
            guard character.isNumber || character == decimalSeparator || character == groupingSeparator
            else { break }
            raw.append(character)
            index += 1
        }
        guard !raw.isEmpty else { return nil }

        let hasDecimal = raw.contains(decimalSeparator)
        let hasGrouping = decimalSeparator != groupingSeparator && raw.contains(groupingSeparator)
        var normalized = raw
        if hasDecimal, hasGrouping {
            let lastDecimal = raw.lastIndex(of: decimalSeparator)
            let lastGrouping = raw.lastIndex(of: groupingSeparator)
            if let lastDecimal, let lastGrouping, lastGrouping > lastDecimal {
                normalized = raw.replacingOccurrences(of: String(decimalSeparator), with: "")
                normalized = normalized.replacingOccurrences(of: String(groupingSeparator), with: ".")
            } else {
                normalized = raw.replacingOccurrences(of: String(groupingSeparator), with: "")
                normalized = normalized.replacingOccurrences(of: String(decimalSeparator), with: ".")
            }
        } else if hasGrouping {
            normalized = looksLikeGrouping(raw, separator: groupingSeparator)
                ? raw.replacingOccurrences(of: String(groupingSeparator), with: "")
                : raw.replacingOccurrences(of: String(groupingSeparator), with: ".")
        } else if hasDecimal {
            normalized = raw.replacingOccurrences(of: String(decimalSeparator), with: ".")
        }
        guard normalized.filter({ $0 == "." }).count <= 1 else { return nil }
        return Double(normalized)
    }

    private static func looksLikeGrouping(_ raw: String, separator: Character) -> Bool {
        let parts = raw.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count >= 2, let first = parts.first, !first.isEmpty, first.count <= 3 else { return false }
        return parts.dropFirst().allSatisfy { $0.count == 3 }
    }

    // MARK: - Parser

    /// A parsed value. `percentRaw` remembers that the value was written as a
    /// percentage, which is what makes "480 + 15%" mean 552 instead of 480.15.
    private struct Operand {
        var value: Double
        var percentRaw: Double?
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        /// Depth guard: a wall of "((((" must not recurse the stack away.
        var depth = 0

        var isAtEnd: Bool { index >= tokens.count }

        mutating func parseExpression() -> Operand? {
            guard depth < 32 else { return nil }
            guard var left = parseTerm() else { return nil }
            while let token = peek(), token == .plus || token == .minus {
                advance()
                guard let right = parseTerm() else { return nil }
                // A percentage after + or - is relative to what came before.
                let delta = right.percentRaw.map { left.value * $0 / 100 } ?? right.value
                left = Operand(value: token == .plus ? left.value + delta : left.value - delta,
                               percentRaw: nil)
            }
            return left
        }

        mutating func parseTerm() -> Operand? {
            guard var left = parseFactor() else { return nil }
            while let token = peek() {
                // A number against a parenthesis multiplies, written or not.
                if token == .leftParen {
                    guard let right = parseFactor() else { return nil }
                    left = Operand(value: left.value * right.value, percentRaw: nil)
                    continue
                }
                guard token == .times || token == .divide || token == .ofWord else { break }
                advance()
                if token == .ofWord {
                    // "20% of 480": only a percentage can own an "of".
                    guard left.percentRaw != nil, let right = parseFactor() else { return nil }
                    left = Operand(value: left.value * right.value, percentRaw: nil)
                    continue
                }
                guard let right = parseFactor() else { return nil }
                if token == .divide {
                    guard right.value != 0 else { return nil }
                    left = Operand(value: left.value / right.value, percentRaw: nil)
                } else {
                    left = Operand(value: left.value * right.value, percentRaw: nil)
                }
            }
            return left
        }

        /// A sign applies to the whole power, which is why -2^2 is -4: the
        /// minus is read last, exactly as it is on paper.
        mutating func parseFactor() -> Operand? {
            if let token = peek(), token == .minus || token == .plus {
                advance()
                guard let operand = parseFactor() else { return nil }
                return token == .minus
                    ? Operand(value: -operand.value, percentRaw: operand.percentRaw.map { -$0 })
                    : operand
            }
            return parsePower()
        }

        mutating func parsePower() -> Operand? {
            guard let base = parsePrimary() else { return nil }
            guard peek() == .power else { return base }
            advance()
            // Powers group to the right: 2^3^2 is 2^9.
            guard let exponent = parseFactor() else { return nil }
            let value = pow(base.value, exponent.value)
            guard value.isFinite else { return nil }
            return Operand(value: value, percentRaw: nil)
        }

        mutating func parsePrimary() -> Operand? {
            guard let token = peek() else { return nil }
            switch token {
            case .number(let value):
                advance()
                if peek() == .percent {
                    advance()
                    return Operand(value: value / 100, percentRaw: value)
                }
                return Operand(value: value, percentRaw: nil)
            case .leftParen:
                advance()
                depth += 1
                defer { depth -= 1 }
                guard depth < 32, let inner = parseExpression(), peek() == .rightParen else { return nil }
                advance()
                if peek() == .percent {
                    advance()
                    return Operand(value: inner.value / 100, percentRaw: inner.value)
                }
                return Operand(value: inner.value, percentRaw: nil)
            default:
                return nil
            }
        }

        func peek() -> Token? {
            index < tokens.count ? tokens[index] : nil
        }

        mutating func advance() {
            index += 1
        }
    }
}
