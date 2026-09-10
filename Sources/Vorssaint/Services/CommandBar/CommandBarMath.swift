// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The command bar's inline calculator. It is deliberately strict: input must
/// be entirely mathematical, so commands and searches are never answered as sums.
enum CommandBarMath {
    /// Words that read as "percent OF a number" across the languages the app
    /// speaks. Parser vocabulary, not visible text: people type in their own
    /// words regardless of the interface language.
    private static let ofWords: Set<String> = ["of", "de", "da", "do", "von", "di", "del", "dal"]

    struct Result: Equatable {
        /// The value, formatted the way this Mac writes numbers.
        let formatted: String
        let value: Double
        /// Closing brackets supplied virtually while evaluating an unfinished expression.
        let closingBrackets: String
    }

    /// Evaluates a complete mathematical expression, supplying only missing
    /// closing brackets. Trigonometric functions use radians.
    static func evaluate(_ input: String,
                         decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                         groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                         locale: Locale = .current) -> Result? {
        guard let parsed = parse(input,
                                 decimalSeparator: decimalSeparator,
                                 groupingSeparator: groupingSeparator) else { return nil }
        let value = significantRounded(parsed.operand.value)
        guard value.isFinite, let formatted = format(value, locale: locale) else { return nil }
        return Result(formatted: formatted, value: value, closingBrackets: parsed.closingBrackets)
    }

    /// Returns the closing brackets that can be supplied to make `input`
    /// complete. It returns nil for searches, malformed expressions, mismatched
    /// brackets, and extra closers; an already balanced expression returns "".
    static func closingBrackets(for input: String) -> String? {
        parse(input,
              decimalSeparator: Locale.current.decimalSeparator ?? ".",
              groupingSeparator: Locale.current.groupingSeparator ?? ",")?.closingBrackets
    }

    /// Produces an ungrouped, locale-aware number suitable for putting an
    /// answer back into the calculator. Swift's shortest round-trip spelling
    /// avoids exposing binary noise; brackets preserve negative values under powers.
    static func reusableExpression(for result: Result,
                                   decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> String {
        let number = result.value == 0 ? 0 : result.value
        var ascii = String(number)
        if ascii.hasSuffix(".0") { ascii.removeLast(2) }
        let separator = decimalSeparator.isEmpty ? "." : decimalSeparator
        let localized = ascii.replacingOccurrences(of: ".", with: separator)
        return number < 0 ? "(\(localized))" : localized
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

    /// Keeps ten significant digits so ordinary decimal arithmetic loses binary noise.
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

    // MARK: - Input validation and tokens

    private enum Bracket: Character, Equatable {
        case round = "("
        case square = "["

        var closing: Character { self == .round ? ")" : "]" }
    }

    private enum Token: Equatable {
        case number(Double)
        case constant(Double)
        case function(Function)
        case plus, minus, times, divide, power, percent, ofWord
        case left(Bracket), right(Bracket)

        var isExplicitOperation: Bool {
            switch self {
            case .plus, .minus, .times, .divide, .power, .ofWord: return true
            default: return false
            }
        }

        var endsImplicitProduct: Bool {
            switch self {
            case .number, .constant, .right: return true
            default: return false
            }
        }

        var startsImplicitProduct: Bool {
            switch self {
            case .constant, .function, .left: return true
            default: return false
            }
        }
    }

    /// Named scientific functions supported by the production calculator:
    /// sqrt, abs, sin, cos, tan, asin, acos, atan, ln, log/log10, exp, floor,
    /// ceil and round. Trigonometric functions use radians; log and log10 are base 10.
    private enum Function: String {
        case sqrt, abs, sin, cos, tan, asin, acos, atan, ln, log, exp, floor, ceil, round

        /// Recognizes the explicit function names and the base-10 logarithm alias.
        init?(word: String) {
            guard let function = Self(rawValue: word == "log10" ? "log" : word) else { return nil }
            self = function
        }

        /// Rejects undefined domains and overflow rather than showing invalid answers.
        func apply(to value: Double) -> Double? {
            let result: Double
            switch self {
            case .sqrt:
                guard value >= 0 else { return nil }
                result = Foundation.sqrt(value)
            case .abs: result = Swift.abs(value)
            case .sin: result = Foundation.sin(value)
            case .cos: result = Foundation.cos(value)
            case .tan: result = Foundation.tan(value)
            case .asin:
                guard (-1...1).contains(value) else { return nil }
                result = Foundation.asin(value)
            case .acos:
                guard (-1...1).contains(value) else { return nil }
                result = Foundation.acos(value)
            case .atan: result = Foundation.atan(value)
            case .ln:
                guard value > 0 else { return nil }
                result = Foundation.log(value)
            case .log:
                guard value > 0 else { return nil }
                result = Foundation.log10(value)
            case .exp: result = Foundation.exp(value)
            case .floor: result = Foundation.floor(value)
            case .ceil: result = Foundation.ceil(value)
            case .round: result = value.rounded()
            }
            return result.isFinite ? result : nil
        }
    }

    private struct ParsedInput {
        let operand: Operand
        let closingBrackets: String
    }

    /// The one validation/parsing path shared by evaluation and bracket hints.
    private static func parse(_ input: String,
                              decimalSeparator: String,
                              groupingSeparator: String) -> ParsedInput? {
        guard let expression = expressionWithoutTrailingEquals(input) else { return nil }
        guard expression.count <= 120, !expression.isEmpty, !looksLikeDateOrTime(expression) else { return nil }
        guard var tokens = tokenize(expression,
                                    decimalSeparator: Character(decimalSeparator.first.map(String.init) ?? "."),
                                    groupingSeparator: Character(groupingSeparator.first.map(String.init) ?? ",")),
              isCalculation(tokens),
              let closings = virtualClosings(for: tokens)
        else { return nil }
        tokens += closings.map { .right($0) }
        var parser = Parser(tokens: tokens)
        guard let operand = parser.parseExpression(), parser.isAtEnd, operand.value.isFinite else { return nil }
        return ParsedInput(operand: operand, closingBrackets: String(closings.map(\.closing)))
    }

    /// Accepts one optional trailing equals sign without accepting assignments or equations.
    private static func expressionWithoutTrailingEquals(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let equals = trimmed.firstIndex(of: "=") else { return trimmed }
        guard equals == trimmed.index(before: trimmed.endIndex) else { return nil }
        let expression = String(trimmed[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        return expression.isEmpty ? nil : expression
    }

    /// Requires mathematical intent rather than promoting every lone number to an answer.
    private static func isCalculation(_ tokens: [Token]) -> Bool {
        tokens.contains(where: \.isExplicitOperation)
            || tokens.contains { if case .function = $0 { return true }; return false }
            || zip(tokens, tokens.dropFirst()).contains { $0.endsImplicitProduct && $1.startsImplicitProduct }
    }

    /// Rejects mismatches and surplus closers, then returns only the matching
    /// closers that may safely be appended to the expression.
    private static func virtualClosings(for tokens: [Token]) -> [Bracket]? {
        var stack: [Bracket] = []
        for token in tokens {
            switch token {
            case .left(let bracket): stack.append(bracket)
            case .right(let bracket):
                guard stack.popLast() == bracket else { return nil }
            default: break
            }
        }
        return stack.reversed()
    }

    /// Recognizes only supported mathematical symbols, numbers, and identifiers.
    private static func tokenize(_ input: String,
                                 decimalSeparator: Character,
                                 groupingSeparator: Character) -> [Token]? {
        var tokens: [Token] = []
        var characters = Array(input)
        var index = 0

        /// Reads names without swallowing the operand in 2x3; log10 alone has a numeric suffix.
        func readWord() -> String {
            var word = ""
            while index < characters.count, characters[index].isLetter {
                word.append(characters[index])
                index += 1
            }
            word = word.lowercased()
            if word == "log" {
                while index < characters.count, characters[index].isNumber {
                    word.append(characters[index])
                    index += 1
                }
            }
            return word
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
            if character == "π" {
                tokens.append(.constant(Double.pi))
                index += 1
                continue
            }
            if character.isLetter {
                let word = readWord()
                if word == "x" {
                    tokens.append(.times)
                } else if word == "pi" {
                    tokens.append(.constant(Double.pi))
                } else if word == "e" {
                    tokens.append(.constant(Foundation.exp(1)))
                } else if let function = Function(word: word) {
                    tokens.append(.function(function))
                } else if ofWords.contains(word) {
                    tokens.append(.ofWord)
                } else {
                    return nil
                }
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
            case "(": tokens.append(.left(.round))
            case "[": tokens.append(.left(.square))
            case ")": tokens.append(.right(.round))
            case "]": tokens.append(.right(.square))
            default: return nil
            }
        }
        return tokens.isEmpty ? nil : tokens
    }

    /// Reads one number, deciding what each separator means. When both appear,
    /// the last one is the decimal point. When only one appears, it is grouping
    /// only if it looks the part: the Mac's grouping separator followed by
    /// exactly three digits. An optional ASCII scientific exponent follows.
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

        var exponent = ""
        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            var exponentIndex = index + 1
            if exponentIndex < characters.count, characters[exponentIndex] == "+" || characters[exponentIndex] == "-" {
                exponentIndex += 1
            }
            let digitsStart = exponentIndex
            while exponentIndex < characters.count, characters[exponentIndex].isNumber {
                exponentIndex += 1
            }
            if exponentIndex > digitsStart {
                exponent = String(characters[index..<exponentIndex])
                index = exponentIndex
            }
        }

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
        guard normalized.filter({ $0 == "." }).count <= 1,
              let value = Double(normalized + exponent), value.isFinite else { return nil }
        return value
    }

    /// Distinguishes grouped thousands from a decimal written with the alternate separator.
    private static func looksLikeGrouping(_ raw: String, separator: Character) -> Bool {
        let parts = raw.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count >= 2, let first = parts.first, !first.isEmpty, first.count <= 3 else { return false }
        return parts.dropFirst().allSatisfy { $0.count == 3 }
    }

    // MARK: - Parser

    private struct Operand {
        var value: Double
        /// Retains the written percentage for relative + and - semantics.
        var percentRaw: Double?
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var depth = 0

        var isAtEnd: Bool { index >= tokens.count }

        /// Parses addition and subtraction, retaining calculator-style relative percentages.
        mutating func parseExpression() -> Operand? {
            guard depth < 32, var left = parseTerm() else { return nil }
            while let token = peek(), token == .plus || token == .minus {
                advance()
                guard let right = parseTerm() else { return nil }
                let delta = right.percentRaw.map { left.value * $0 / 100 } ?? right.value
                let value = token == .plus ? left.value + delta : left.value - delta
                guard value.isFinite else { return nil }
                left = Operand(value: value, percentRaw: nil)
            }
            return left
        }

        /// Parses explicit and implicit products, division, and percentage-of expressions.
        mutating func parseTerm() -> Operand? {
            guard var left = parseFactor() else { return nil }
            while let token = peek() {
                let implicit = token.startsImplicitProduct
                guard implicit || token == .times || token == .divide || token == .ofWord else { break }
                if !implicit { advance() }
                if token == .ofWord, left.percentRaw == nil { return nil }
                guard let right = parseFactor() else { return nil }
                let value: Double
                if token == .divide {
                    guard right.value != 0 else { return nil }
                    value = left.value / right.value
                } else {
                    value = left.value * right.value
                }
                guard value.isFinite else { return nil }
                left = Operand(value: value, percentRaw: nil)
            }
            return left
        }

        /// A sign applies to the whole power, so -2^2 is -4.
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

        /// Groups powers to the right, so 2^3^2 is 2^(3^2).
        mutating func parsePower() -> Operand? {
            guard let base = parsePrimary() else { return nil }
            guard peek() == .power else { return base }
            advance()
            guard let exponent = parseFactor() else { return nil }
            let value = pow(base.value, exponent.value)
            guard value.isFinite else { return nil }
            return Operand(value: value, percentRaw: nil)
        }

        /// Reads a number, constant, bracketed expression, or function with an optional percent.
        mutating func parsePrimary() -> Operand? {
            guard let token = peek() else { return nil }
            let base: Operand
            switch token {
            case .number(let value), .constant(let value):
                advance()
                base = Operand(value: value, percentRaw: nil)
            case .left:
                guard let value = parseBracketed() else { return nil }
                base = Operand(value: value, percentRaw: nil)
            case .function(let function):
                advance()
                guard let argument = parseBracketed(), let value = function.apply(to: argument) else { return nil }
                base = Operand(value: value, percentRaw: nil)
            default:
                return nil
            }
            if peek() == .percent {
                advance()
                return Operand(value: base.value / 100, percentRaw: base.value)
            }
            return base
        }

        /// Shares bracket matching and nesting limits between groups and function arguments.
        mutating func parseBracketed() -> Double? {
            guard case .left(let bracket)? = peek() else { return nil }
            advance()
            depth += 1
            defer { depth -= 1 }
            guard depth < 32, let inner = parseExpression(), peek() == .right(bracket) else { return nil }
            advance()
            return inner.value
        }

        /// Inspects the next token without consuming it.
        func peek() -> Token? { index < tokens.count ? tokens[index] : nil }

        /// Consumes the token most recently inspected by the parser.
        mutating func advance() { index += 1 }
    }
}
