// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The command bar calculator engine: tokenizes and evaluates arithmetic that
/// mixes numbers and units. A value is a quantity in SI base units plus the
/// dimensions it carries and the unit it displays in, so `5m + 4m` is `9 m`,
/// `5m * 4m` is `20 m²` and `100km / 2h` is `50 km/h` without a separate
/// conversion path.
///
/// Everything that is not a plain number or a unit is refused, because a
/// launcher that guesses at meaning turns sentences into wrong answers.
enum CommandBarExpressions {
    // MARK: - Values

    /// An evaluated quantity. `si` is the SI base value (Kelvin for the
    /// temperature scales); `unit` is the unit the answer shows in and is nil
    /// for a plain number.
    struct Value {
        var si: Double
        var dims: CommandBarUnitCatalog.Dimensions
        var unit: CommandBarUnitCatalog.Unit?
        /// Retained so `+` and `-` read a percentage relative to the left
        /// operand: 10kg + 20% is 12 kg, while `*` and `/` treat it as a plain
        /// fraction.
        var percentRaw: Double?
        /// Whether the value came from an explicit number rather than a bare
        /// unit. Decides the direction of "in": "cm in 5 inches" converts the
        /// numbered side, "5 inches in cm" converts the bare one.
        var hasNumber: Bool
    }

    /// A duration split into a whole larger unit and a remainder: "5 ft 3 in",
    /// "2 hr 25 min", "14 wk 2 d".
    struct Split {
        let larger: (value: Double, unit: CommandBarUnitCatalog.Unit)
        let smaller: (value: Double, unit: CommandBarUnitCatalog.Unit)
        /// The dimensions of the amount, for the answer's numeric value.
        let dims: CommandBarUnitCatalog.Dimensions
    }

    /// What a parse produced: a single value or a split amount.
    enum Outcome {
        case value(Value)
        case split(Split)
    }

    struct Parsed {
        let outcome: Outcome
        let closingBrackets: String
        /// True when the input carried mathematical intent: an operator, a
        /// function, a fraction, a conversion or a unit pair. A lone "5" or
        /// "5 kg" is a search, not an answer.
        let isCalculation: Bool
    }

    /// Words that mean "convert into", across the languages the app speaks.
    /// Shared with the color converter. "in" is on the list and is also the
    /// inch symbol; the calculator's tokenizer resolves that collision by
    /// reading "in" as inches only right after a number.
    static let conversionWords: Set<String> = [
        "to", "in", "into", "as", "em", "para", "pra", "en", "a", "nach", "zu",
        "à", "su", "->", ">", "→",
    ]

    // MARK: - Entry point

    static func parse(_ input: String,
                      decimalSeparator: String,
                      groupingSeparator: String) -> Parsed? {
        guard let tokens = tokenize(input, decimalSeparator: decimalSeparator,
                                    groupingSeparator: groupingSeparator),
              let closings = virtualClosings(for: tokens)
        else { return nil }
        let all = tokens + closings.map { _ in Token.right }
        var parser = Parser(tokens: all)
        guard let parsed = parser.parseWhole() else { return nil }
        return Parsed(outcome: parsed.outcome,
                      closingBrackets: String(closings),
                      isCalculation: parsed.isCalculation)
    }

    // MARK: - Tokens

    private enum Token: Equatable {
        case number(Double, interesting: Bool)
        case unit(CommandBarUnitCatalog.Unit)
        case plus, minus, times, divide, power, percent, mod
        case left, right
        case function(Function)
        case constant(Double)
        case to                      // to/into/as/->/→ conversion keyword
        case inKeyword               // "in" as a conversion word
        case ofWord, offWord, andWord, comma, baseWord, rootWord
        case squared, cubed, powerWord
        case scaleWord(Double)       // thousand/million/billion/trillion
        case timespan                // "timespan"/"duration" split target

        var startsImplicitProduct: Bool {
            switch self {
            case .constant, .function, .left: return true
            default: return false
            }
        }
    }

    /// Named functions the engine knows. Trig functions use radians; `log` is
    /// base 10 unless a second argument names the base.
    private enum Function: String {
        case sqrt, cbrt, abs, round, floor, ceil, min, max, log
        case sin, cos, tan, asin, acos, atan, ln, exp, log10
    }

    // MARK: - Folding and unit symbols

    private static func fold(_ word: String) -> String {
        CommandBarSearch.normalized(word)
    }

    private static func isUnitSymbol(_ c: Character) -> Bool {
        ["\"", "″", "”", "'", "′", "’", "°"].contains(c)
    }

    // MARK: - Tokenizer

    private static func tokenize(_ input: String,
                                 decimalSeparator: String,
                                 groupingSeparator: String) -> [Token]? {
        var tokens: [Token] = []
        var characters = Array(input)
        var index = 0
        let separators = Separators(decimalSeparator: decimalSeparator,
                                    groupingSeparator: groupingSeparator)

        /// Reads one "word" of a unit: a run of letters, or a lone unit symbol
        /// such as the inch double-prime or the degree sign.
        func readUnitWord(at p: inout Int) -> (raw: String, folded: String)? {
            let start = p
            if p < characters.count, characters[p].isLetter {
                while p < characters.count, characters[p].isLetter { p += 1 }
            } else if p < characters.count, isUnitSymbol(characters[p]) {
                p += 1
            } else {
                return nil
            }
            let raw = String(characters[start..<p])
            return (raw, fold(raw))
        }

        /// Matches the longest unit name starting here, so "fl oz", "square
        /// feet" and "miles per hour" read as one unit and not as words.
        func readUnit() -> (unit: CommandBarUnitCatalog.Unit, raw: String)? {
            var best: (unit: CommandBarUnitCatalog.Unit, end: Int, raw: String)?
            var p = index
            var words: [(raw: String, folded: String)] = []
            while let word = readUnitWord(at: &p) {
                words.append(word)
                let joined = words.map(\.folded).joined(separator: " ")
                let exact = words.count == 1 ? words[0].raw : nil
                if let unit = CommandBarUnitCatalog.unit(named: joined, exact: exact) {
                    best = (unit, p, words[0].raw)
                }
                // Extend only across spaces into another word; "5 feet 3
                // inches" stops because 3 is a digit.
                var probe = p
                let beforeSpace = probe
                while probe < characters.count, characters[probe].isWhitespace { probe += 1 }
                guard probe > beforeSpace, probe < characters.count,
                      characters[probe].isLetter || isUnitSymbol(characters[probe]) else { break }
                p = probe
            }
            if let best {
                index = best.end
                return (best.unit, best.raw)
            }
            return nil
        }

        /// Reads a run of letters and returns the raw text.
        func readLetterRun() -> String {
            let start = index
            while index < characters.count, characters[index].isLetter { index += 1 }
            return String(characters[start..<index])
        }

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if separators.isPart(ofNumber: character) || character.isNumber {
                guard let number = readNumber(&characters, &index, separators: separators)
                else { return nil }
                tokens.append(.number(number.value, interesting: number.interesting))
                continue
            }
            // A letter or a unit symbol: a unit name, an operator word or a
            // filler word.
            if character.isLetter || isUnitSymbol(character) {
                if let matched = readUnit() {
                    // The word "in" is inches only right after a number; between
                    // two units it is the conversion keyword.
                    let afterNumber: Bool
                    if case .some(.number) = tokens.last { afterNumber = true } else { afterNumber = false }
                    if matched.unit.id == "in", fold(matched.raw) == "in", !afterNumber {
                        tokens.append(.inKeyword)
                    } else {
                        tokens.append(.unit(matched.unit))
                    }
                    continue
                }
            }
            if character.isLetter {
                let raw = readLetterRun()
                let lower = fold(raw)
                if let token = wordToken(for: lower, characters: characters, index: &index) {
                    tokens.append(token)
                    continue
                }
                if wordIsFiller(lower) {
                    if lower == "a" || lower == "an" { tokens.append(.number(1, interesting: false)) }
                    continue
                }
                return nil
            }
            index += 1
            switch character {
            case "+": tokens.append(.plus)
            case "-", "\u{2212}": tokens.append(.minus)
            case "*", "\u{00D7}", "x", "X", "\u{00B7}": tokens.append(.times)
            case "/", "\u{00F7}": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "%": tokens.append(.percent)
            case "(": tokens.append(.left)
            case "[": tokens.append(.left)
            case ")": tokens.append(.right)
            case "]": tokens.append(.right)
            case ",", ";": tokens.append(.comma)
            case "π": tokens.append(.constant(Double.pi))
            case ">": tokens.append(.to)
            case "\u{2192}": tokens.append(.to)   // →
            default: return nil
            }
        }
        return tokens.isEmpty ? nil : tokens
    }

    /// Words that carry no meaning for a calculation and are skipped, except
    /// "a"/"an" which stand for one of the unit that follows.
    private static func wordIsFiller(_ lower: String) -> Bool {
        ["what", "is", "are", "how", "many", "much", "the", "calculate", "compute", "convert",
         "a", "an", "of"].contains(lower)
    }

    /// Maps a single word or a short multi-word phrase to a token.
    private static func wordToken(for lower: String,
                                  characters: [Character],
                                  index: inout Int) -> Token? {
        /// True when the next `count` space-separated words match `words`.
        func matchAhead(_ words: [String]) -> Bool {
            var i = index
            for expected in words {
                while i < characters.count, characters[i].isWhitespace { i += 1 }
                let start = i
                while i < characters.count, characters[i].isLetter { i += 1 }
                guard fold(String(characters[start..<i])) == expected else { return false }
            }
            return true
        }
        func consume(_ count: Int) {
            for _ in 0..<count {
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                while index < characters.count, characters[index].isLetter { index += 1 }
            }
        }
        switch lower {
        case "plus": return .plus
        case "minus": return .minus
        case "times": return .times
        case "mod": return .mod
        case "per": return .divide
        case "percent", "percentage": return .percent
        case "squared": return .squared
        case "cubed": return .cubed
        case "and": return .andWord
        case "off": return .offWord
        case "base": return .baseWord
        case "thousand": return .scaleWord(1e3)
        case "million": return .scaleWord(1e6)
        case "billion": return .scaleWord(1e9)
        case "trillion": return .scaleWord(1e12)
        case "quadrillion": return .scaleWord(1e15)
        case "timespan", "duration": return .timespan
        case "into", "as", "em", "para", "pra", "en", "a", "nach", "zu", "à", "su":
            return .to
        case "in": return .inKeyword
        case "raised":
            if matchAhead(["to"]) { consume(1); return .powerWord }
            return nil
        case "divided":
            if matchAhead(["by"]) { consume(1); return .divide }
            return nil
        case "multiplied":
            if matchAhead(["by"]) { consume(1); return .times }
            return nil
        case "exponent":
            return .powerWord
        case "to":
            if matchAhead(["the"]) {
                consume(1)
                if matchAhead(["power"]) { consume(2); return .powerWord }
                return .powerWord
            }
            return .to
        case "square":
            if matchAhead(["root"]) { consume(1); return .rootWord }
            return nil
        case "root":
            return .rootWord
        case "logarithm":
            return .function(.log)
        case "pi": return .constant(Double.pi)
        case "e": return .constant(Foundation.exp(1))
        default:
            if let function = Function(rawValue: lower) { return .function(function) }
            return nil
        }
    }

    // MARK: - Number reading

    /// How this Mac writes numbers, plus the one other separator people type.
    private struct Separators {
        let decimal: Character
        let alternate: Character
        let groupingOnly: Character?

        init(decimalSeparator: String, groupingSeparator: String) {
            let decimal = Character(decimalSeparator.first.map(String.init) ?? ".")
            let grouping = Character(groupingSeparator.first.map(String.init) ?? ",")
            let groupingIsPunctuation = grouping == "." || grouping == ","
            self.decimal = decimal
            if groupingIsPunctuation, grouping != decimal {
                alternate = grouping
                groupingOnly = nil
            } else {
                alternate = decimal == "," ? "." : ","
                groupingOnly = grouping == decimal ? nil : grouping
            }
        }

        func isPart(ofNumber character: Character) -> Bool {
            character.isNumber || character == decimal || character == alternate
                || character == groupingOnly
        }
    }

    private static func readNumber(_ characters: inout [Character],
                                   _ index: inout Int,
                                   separators: Separators) -> (value: Double, interesting: Bool)? {
        var written = ""
        var interesting = false
        while index < characters.count {
            let character = characters[index]
            guard separators.isPart(ofNumber: character) else { break }
            if character == separators.groupingOnly,
               !(index + 1 < characters.count && characters[index + 1].isNumber) { break }
            written.append(character)
            index += 1
        }
        guard !written.isEmpty else { return nil }

        var raw = written
        if let groupingOnly = separators.groupingOnly, written.contains(groupingOnly) {
            let integerPart = written.prefix { $0 != separators.decimal && $0 != separators.alternate }
            guard looksLikeGrouping(String(integerPart), separator: groupingOnly),
                  !written.dropFirst(integerPart.count).contains(groupingOnly) else { return nil }
            raw = written.filter { $0 != groupingOnly }
        }

        var exponent = ""
        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            var exponentIndex = index + 1
            if exponentIndex < characters.count,
               characters[exponentIndex] == "+" || characters[exponentIndex] == "-" {
                exponentIndex += 1
            }
            let digitsStart = exponentIndex
            while exponentIndex < characters.count, characters[exponentIndex].isNumber {
                exponentIndex += 1
            }
            if exponentIndex > digitsStart {
                exponent = String(characters[index..<exponentIndex])
                index = exponentIndex
                interesting = true
            }
        }

        let decimalSeparator = separators.decimal
        let alternateSeparator = separators.alternate
        let hasDecimal = raw.contains(decimalSeparator)
        let hasAlternate = decimalSeparator != alternateSeparator && raw.contains(alternateSeparator)
        var normalized = raw
        if hasDecimal, hasAlternate {
            let lastDecimal = raw.lastIndex(of: decimalSeparator)
            let lastAlternate = raw.lastIndex(of: alternateSeparator)
            if let lastDecimal, let lastAlternate, lastAlternate > lastDecimal {
                normalized = raw.replacingOccurrences(of: String(decimalSeparator), with: "")
                    .replacingOccurrences(of: String(alternateSeparator), with: ".")
            } else {
                normalized = raw.replacingOccurrences(of: String(alternateSeparator), with: "")
                    .replacingOccurrences(of: String(decimalSeparator), with: ".")
            }
        } else if hasAlternate {
            normalized = looksLikeGrouping(raw, separator: alternateSeparator)
                ? raw.replacingOccurrences(of: String(alternateSeparator), with: "")
                : raw.replacingOccurrences(of: String(alternateSeparator), with: ".")
        } else if hasDecimal {
            normalized = raw.replacingOccurrences(of: String(decimalSeparator), with: ".")
        }
        guard normalized.filter({ $0 == "." }).count <= 1,
              let base = Double(normalized + exponent), base.isFinite else { return nil }

        var value = base
        var isWhole = !normalized.contains(".") && exponent.isEmpty

        // A fraction attaches to a number with no space: "5/16", "10/4".
        if isWhole, index < characters.count, characters[index] == "/" {
            var fractionIndex = index + 1
            let denominatorStart = fractionIndex
            while fractionIndex < characters.count, characters[fractionIndex].isNumber {
                fractionIndex += 1
            }
            if fractionIndex > denominatorStart,
               let denominator = Double(String(characters[index + 1..<fractionIndex])),
               denominator != 0 {
                value = value / denominator
                index = fractionIndex
                interesting = true
                isWhole = false
            }
        }
        // A mixed number is a whole number followed by a fraction: "1 1/2".
        if isWhole, index < characters.count, characters[index].isWhitespace {
            var probe = index
            while probe < characters.count, characters[probe].isWhitespace { probe += 1 }
            let numeratorStart = probe
            while probe < characters.count, characters[probe].isNumber { probe += 1 }
            if probe > numeratorStart, probe < characters.count, characters[probe] == "/" {
                var denominatorIndex = probe + 1
                let denominatorStart = denominatorIndex
                while denominatorIndex < characters.count, characters[denominatorIndex].isNumber {
                    denominatorIndex += 1
                }
                if denominatorIndex > denominatorStart,
                   let numerator = Double(String(characters[numeratorStart..<probe])),
                   let denominator = Double(String(characters[probe + 1..<denominatorIndex])),
                   denominator != 0 {
                    value = value + numerator / denominator
                    index = denominatorIndex
                    interesting = true
                }
            }
        }
        // "10k" reads as ten thousand when the k is alone; kg, km and kB are
        // units the parser reads next.
        if index < characters.count, characters[index] == "k" || characters[index] == "K" {
            let after = index + 1
            if after >= characters.count || !characters[after].isLetter {
                value *= 1000
                index = after
                interesting = true
            }
        }
        return (value, interesting)
    }

    private static func looksLikeGrouping(_ raw: String, separator: Character) -> Bool {
        let parts = raw.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count >= 2, let first = parts.first, !first.isEmpty, first.count <= 3,
              first.first != "0" else { return false }
        return parts.dropFirst().allSatisfy { $0.count == 3 }
    }

    // MARK: - Bracket handling

    private static func virtualClosings(for tokens: [Token]) -> String? {
        var stack: [String] = []
        for token in tokens {
            switch token {
            case .left: stack.append(")")
            case .right:
                guard stack.popLast() != nil else { return nil }
            default: break
            }
        }
        return stack.reversed().joined()
    }

    // MARK: - Parser

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var depth = 0
        var isCalculation = false

        func peek(_ offset: Int = 0) -> Token? {
            let i = index + offset
            return i < tokens.count ? tokens[i] : nil
        }

        mutating func advance() { index += 1 }

        mutating func parseWhole() -> (outcome: Outcome, isCalculation: Bool)? {
            guard let outcome = parseConversion() else { return nil }
            guard index >= tokens.count else { return nil }
            return (outcome, isCalculation)
        }

        // MARK: Conversion

        /// Parses an expression and any trailing conversion: "to cm", "in feet
        /// and inches", "to timespan", or a bare unit that sets the answer.
        mutating func parseConversion() -> Outcome? {
            guard var left = parseExpression() else { return nil }
            while true {
                switch peek() {
                case .to:
                    advance()
                    guard let target = parseConversionTarget() else { return nil }
                    guard case .value(let converted) = convert(left, target: target) else { return nil }
                    left = converted
                case .inKeyword:
                    advance()
                    guard let right = parseExpression() else { return nil }
                    guard case .value(let converted) = convertIn(left: left, right: right) else { return nil }
                    left = converted
                case .unit(let unit):
                    advance()
                    guard case .value(let converted) = convert(left, target: .unit(unit)) else { return nil }
                    left = converted
                default:
                    return .value(left)
                }
            }
        }

        private mutating func convertIn(left: Value, right: Value) -> Outcome? {
            guard left.unit != nil || right.unit != nil else { return nil }
            // A numbered amount after "in" is the source: "cm in 5 inches",
            // "feet in a mile". Otherwise the bare unit names the answer.
            if right.hasNumber {
                guard let target = left.unit else { return nil }
                return convert(right, target: .unit(target))
            }
            guard let target = right.unit else { return nil }
            return convert(left, target: .unit(target))
        }

        /// A conversion target: a unit, a compound unit ("km/h"), a split pair
        /// ("feet and inches") or a timespan.
        private mutating func parseConversionTarget() -> Target? {
            if peek() == .timespan {
                advance()
                return .timespan
            }
            guard let first = parseUnitExpression() else { return nil }
            // A second unit (joined by "and" or just a space) splits the answer.
            if peek() == .andWord { advance() }
            if case .unit(let second)? = peek() {
                let key = "\(first.id)|\(second.id)"
                if CommandBarUnitCatalog.splitPairs.contains(key) {
                    advance()
                    return .split(larger: first, smaller: second)
                }
            }
            return .unit(first)
        }

        /// A unit, possibly a compound like "km/h", "kg/m3" or "l/100km".
        mutating func parseUnitExpression() -> CommandBarUnitCatalog.Unit? {
            guard case .unit(let first)? = peek() else { return nil }
            advance()
            guard peek() == .divide else { return first }
            advance()
            // "l/100km": a number follows the slash.
            if case .number(let scale, _)? = peek(), scale != 0 {
                advance()
                guard case .unit(let denom)? = peek() else { return nil }
                advance()
                let combined = CommandBarExpressions.compound(numerator: first, denominator: denom)
                return CommandBarExpressions.scaled(combined, by: 1 / scale)
            }
            guard case .unit(let denom)? = peek() else { return nil }
            advance()
            return CommandBarExpressions.compound(numerator: first, denominator: denom)
        }

        private enum Target {
            case unit(CommandBarUnitCatalog.Unit)
            case split(larger: CommandBarUnitCatalog.Unit, smaller: CommandBarUnitCatalog.Unit)
            case timespan
        }

        // MARK: Expressions

        mutating func parseExpression() -> Value? {
            guard depth < 32, var left = parseTerm() else { return nil }
            while let token = peek(), token == .plus || token == .minus {
                advance()
                isCalculation = true
                guard let right = parseTerm() else { return nil }
                guard let combined = add(left, right, subtract: token == .minus) else { return nil }
                left = combined
            }
            return left
        }

        mutating func parseTerm() -> Value? {
            guard var left = parseFactor() else { return nil }
            while let token = peek() {
                switch token {
                case .times, .divide, .mod:
                    advance()
                    isCalculation = true
                    guard let right = parseFactor() else { return nil }
                    let result: Value?
                    if token == .times { result = multiply(left, right) }
                    else if token == .divide { result = divide(left, right) }
                    else { result = modulo(left, right) }
                    guard let result else { return nil }
                    left = result
                case .ofWord:
                    advance()
                    isCalculation = true
                    guard left.percentRaw != nil else { return nil }
                    guard let right = parseFactor() else { return nil }
                    guard let result = multiply(left, right) else { return nil }
                    left = result
                case .offWord:
                    advance()
                    isCalculation = true
                    guard let right = parseFactor() else { return nil }
                    guard let result = off(left, of: right) else { return nil }
                    left = result
                default:
                    // Implicit product: 2pi, 2(3+4), (2+3)(2+3).
                    guard token.startsImplicitProduct else { return left }
                    guard let right = parseFactor() else { return nil }
                    isCalculation = true
                    guard let result = multiply(left, right) else { return nil }
                    left = result
                }
            }
            return left
        }

        mutating func parseFactor() -> Value? {
            if let token = peek(), token == .minus || token == .plus {
                advance()
                guard let operand = parseFactor() else { return nil }
                if token == .plus { return operand }
                return negate(operand)
            }
            return parsePower()
        }

        mutating func parsePower() -> Value? {
            guard let base = parsePrimary() else { return nil }
            switch peek() {
            case .power:
                advance()
                isCalculation = true
                guard let exponent = parseFactor() else { return nil }
                return power(base, exponent)
            case .squared:
                advance()
                isCalculation = true
                return power(base, Value(si: 2, dims: .none, unit: nil, percentRaw: nil, hasNumber: true))
            case .cubed:
                advance()
                isCalculation = true
                return power(base, Value(si: 3, dims: .none, unit: nil, percentRaw: nil, hasNumber: true))
            case .powerWord:
                advance()
                isCalculation = true
                guard let exponent = parseFactor() else { return nil }
                return power(base, exponent)
            default:
                return base
            }
        }

        mutating func parsePrimary() -> Value? {
            guard let token = peek() else { return nil }
            var base: Value
            switch token {
            case .number(let value, let interesting):
                advance()
                if interesting { isCalculation = true }
                base = Value(si: value, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            case .constant(let value):
                advance()
                base = Value(si: value, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            case .left:
                guard let value = parseBracketed() else { return nil }
                base = Value(si: value, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            case .function(let function):
                advance()
                if function == .log, peek() != .left {
                    // "log 81 base 3": no parentheses, optional base.
                    guard let argument = parseFactor() else { return nil }
                    var arguments = [argument]
                    if peek() == .baseWord {
                        advance()
                        guard let base = parseFactor() else { return nil }
                        arguments.append(base)
                    }
                    guard let value = apply(.log, to: arguments) else { return nil }
                    base = value
                } else {
                    guard let value = parseFunction(function) else { return nil }
                    base = value
                }
            case .rootWord:
                advance()
                guard let value = parseRoot() else { return nil }
                base = value
            case .unit(let unit):
                advance()
                base = Value(si: unit.scale + unit.offset, dims: unit.dimensions,
                             unit: unit, percentRaw: nil, hasNumber: false)
            default:
                return nil
            }

            // A number followed by "root of" is a root: "5 root of 32".
            if base.hasNumber, peek() == .rootWord {
                advance()
                guard peek() == .ofWord else { return nil }
                advance()
                guard let operand = parseFactor() else { return nil }
                guard let result = root(operand, degree: base.si) else { return nil }
                base = result
                isCalculation = true
            }

            // Attach a unit suffix to a number, constant or bracket.
            if base.unit == nil, let unit = peekUnit() {
                advance()
                let si = base.si * unit.scale + unit.offset
                base = Value(si: si, dims: unit.dimensions, unit: unit,
                             percentRaw: nil, hasNumber: base.hasNumber)
                // Mixed pairs: "5 ft 3 in", "1 hr 30 min".
                if let pair = CommandBarUnitCatalog.mixedPairs[unit.id],
                   case .number(let remainderValue, _)? = peek(),
                   case .unit(let remainderUnit)? = peek(1),
                   remainderUnit.id == pair.remainder.id {
                    base.si += remainderValue * pair.remainder.scale
                    advance()
                    advance()
                    isCalculation = true
                }
            }

            if peek() == .percent {
                advance()
                isCalculation = true
                let raw = base.si
                return Value(si: raw / 100, dims: base.dims, unit: base.unit,
                             percentRaw: raw, hasNumber: base.hasNumber)
            }
            if case .scaleWord(let factor)? = peek() {
                advance()
                isCalculation = true
                return Value(si: base.si * factor, dims: base.dims, unit: base.unit,
                             percentRaw: base.percentRaw, hasNumber: base.hasNumber)
            }
            return base
        }

        private func peekUnit() -> CommandBarUnitCatalog.Unit? {
            if case .unit(let unit)? = peek() { return unit }
            return nil
        }

        mutating func parseBracketed() -> Double? {
            guard peek() == .left else { return nil }
            advance()
            depth += 1
            defer { depth -= 1 }
            guard depth < 32, let inner = parseExpression(), peek() == .right else { return nil }
            advance()
            guard inner.unit == nil else { return nil }
            return inner.si
        }

        /// "root N of X" and "square root of X".
        mutating func parseRoot() -> Value? {
            // "root 4 of 81".
            if case .number(let degree, _)? = peek() {
                advance()
                guard peek() == .ofWord else { return nil }
                advance()
                guard let operand = parseFactor() else { return nil }
                return root(operand, degree: degree)
            }
            // "root of 81" = square root.
            guard peek() == .ofWord else { return nil }
            advance()
            guard let operand = parseFactor() else { return nil }
            return root(operand, degree: 2)
        }

        mutating func parseFunction(_ function: Function) -> Value? {
            guard peek() == .left else { return nil }
            advance()
            depth += 1
            defer { depth -= 1 }
            var arguments: [Value] = []
            while true {
                if peek() == .right { break }
                guard let argument = parseExpression() else { return nil }
                arguments.append(argument)
                if peek() == .comma { advance(); continue }
                break
            }
            guard peek() == .right else { return nil }
            advance()
            isCalculation = true
            // "log 81 base 3" has no parentheses; the tokenizer hands the
            // argument list through the infix "base".
            return apply(function, to: arguments)
        }

        // MARK: Arithmetic

        private func add(_ left: Value, _ right: Value, subtract: Bool) -> Value? {
            guard !left.isTemperature && !right.isTemperature else { return nil }
            let si: Double
            if let percent = right.percentRaw {
                let leftValue = displayValue(left)
                let delta = leftValue * percent / 100 * (left.unit?.scale ?? 1)
                si = subtract ? left.si - delta : left.si + delta
            } else {
                guard dimsCompatible(left, right) else { return nil }
                si = subtract ? left.si - right.si : left.si + right.si
            }
            let unit = right.unit ?? left.unit
            let dims = unit?.dimensions ?? left.dims
            return Value(si: si, dims: dims, unit: unit, percentRaw: nil, hasNumber: true)
        }

        private func multiply(_ left: Value, _ right: Value) -> Value? {
            guard !left.isTemperature && !right.isTemperature else { return nil }
            let dims = left.dims * right.dims
            let unit: CommandBarUnitCatalog.Unit?
            if left.unit == nil { unit = right.unit }
            else if right.unit == nil { unit = left.unit }
            else { unit = CommandBarExpressions.productUnit(left.unit!, right.unit!) }
            return Value(si: left.si * right.si, dims: dims, unit: unit,
                         percentRaw: nil, hasNumber: true)
        }

        private func divide(_ left: Value, _ right: Value) -> Value? {
            guard !left.isTemperature && !right.isTemperature else { return nil }
            guard right.si != 0 else { return nil }
            let dims = left.dims / right.dims
            let unit: CommandBarUnitCatalog.Unit?
            if right.unit == nil {
                unit = left.unit
            } else if left.unit == nil {
                unit = CommandBarExpressions.reciprocal(right.unit!)
            } else {
                unit = CommandBarExpressions.quotientUnit(left.unit!, right.unit!)
            }
            return Value(si: left.si / right.si, dims: dims, unit: unit,
                         percentRaw: nil, hasNumber: true)
        }

        private func modulo(_ left: Value, _ right: Value) -> Value? {
            guard !left.isTemperature && !right.isTemperature else { return nil }
            guard left.unit == nil, right.unit == nil, right.si != 0 else { return nil }
            let result = left.si.truncatingRemainder(dividingBy: right.si)
            return Value(si: result, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
        }

        private func off(_ percent: Value, of amount: Value) -> Value? {
            guard percent.unit == nil, let raw = percent.percentRaw else { return nil }
            let fraction = raw / 100
            return Value(si: amount.si * (1 - fraction), dims: amount.dims,
                         unit: amount.unit, percentRaw: nil, hasNumber: true)
        }

        private func power(_ base: Value, _ exponent: Value) -> Value? {
            guard !base.isTemperature, exponent.unit == nil, exponent.dims.isNone else { return nil }
            let value = pow(base.si, exponent.si)
            guard value.isFinite else { return nil }
            if base.unit == nil {
                return Value(si: value, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            }
            if exponent.si == 2, let square = CommandBarUnitCatalog.squaredPartners[base.unit!.id] {
                return Value(si: value, dims: square.dimensions, unit: square,
                             percentRaw: nil, hasNumber: true)
            }
            if exponent.si == 3, let cube = CommandBarUnitCatalog.cubedPartners[base.unit!.id] {
                return Value(si: value, dims: cube.dimensions, unit: cube,
                             percentRaw: nil, hasNumber: true)
            }
            return nil
        }

        private func root(_ operand: Value, degree: Double) -> Value? {
            guard !operand.isTemperature, degree != 0 else { return nil }
            let value: Double
            if operand.si < 0 {
                // Only odd whole roots of a negative are real.
                guard degree == degree.rounded(), Int(degree) % 2 != 0 else { return nil }
                value = -pow(-operand.si, 1.0 / degree)
            } else {
                value = pow(operand.si, 1.0 / degree)
            }
            guard value.isFinite else { return nil }
            guard let unit = operand.unit else {
                return Value(si: value, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            }
            let n = Int(degree)
            guard n >= 2, operand.dims.allDivisible(by: n) else { return nil }
            let dims = operand.dims.dividedExponents(by: n)
            let rootUnit = CommandBarExpressions.rootUnit(unit, degree: n)
            return Value(si: value, dims: dims, unit: rootUnit, percentRaw: nil, hasNumber: true)
        }

        private func negate(_ value: Value) -> Value {
            Value(si: -value.si, dims: value.dims, unit: value.unit,
                  percentRaw: value.percentRaw.map { -$0 }, hasNumber: value.hasNumber)
        }

        private func displayValue(_ value: Value) -> Double {
            guard let unit = value.unit else { return value.si }
            return (value.si - unit.offset) / unit.scale
        }

        private func dimsCompatible(_ left: Value, _ right: Value) -> Bool {
            if left.unit == nil || right.unit == nil { return true }
            return left.dims == right.dims
        }

        // MARK: Conversion

        private mutating func convert(_ value: Value, target: Target) -> Outcome? {
            isCalculation = true
            switch target {
            case .unit(let unit):
                return convert(value, to: unit).map { .value($0) }
            case .split(let larger, let smaller):
                return split(value, larger: larger, smaller: smaller)
            case .timespan:
                return timespan(value)
            }
        }

        private func convert(_ value: Value, to target: CommandBarUnitCatalog.Unit) -> Value? {
            if value.isTemperature {
                guard target.dimensions.temperature == 1, value.dims == target.dimensions else { return nil }
                return Value(si: value.si, dims: target.dimensions, unit: target,
                             percentRaw: nil, hasNumber: value.hasNumber)
            }
            guard value.dims == target.dimensions else {
                // Reciprocal conversion: speed to pace, economy to consumption.
                if value.dims == target.dimensions.negated() {
                    let reciprocal = CommandBarExpressions.reciprocal(target)
                    return Value(si: value.si, dims: reciprocal.dimensions, unit: reciprocal,
                                 percentRaw: nil, hasNumber: value.hasNumber)
                }
                return nil
            }
            return Value(si: value.si, dims: target.dimensions, unit: target,
                         percentRaw: nil, hasNumber: value.hasNumber)
        }

        private func split(_ value: Value,
                           larger: CommandBarUnitCatalog.Unit,
                           smaller: CommandBarUnitCatalog.Unit) -> Outcome? {
            guard value.dims == larger.dimensions, larger.dimensions == smaller.dimensions else { return nil }
            let largerTotal = (value.si - larger.offset) / larger.scale
            let whole = largerTotal >= 0 ? largerTotal.rounded(.down) : largerTotal.rounded(.up)
            let remainderLarger = largerTotal - whole
            let smallerValue = remainderLarger * larger.scale / smaller.scale
            return .split(Split(larger: (whole, larger),
                                smaller: (smallerValue, smaller),
                                dims: value.dims))
        }

        private func timespan(_ value: Value) -> Outcome? {
            guard value.dims == CommandBarUnitCatalog.Dimensions(time: 1) else { return nil }
            let pairs: [(CommandBarUnitCatalog.Unit, CommandBarUnitCatalog.Unit)] = [
                (CommandBarUnitCatalog.unit(byID: "wk")!, CommandBarUnitCatalog.unit(byID: "d")!),
                (CommandBarUnitCatalog.unit(byID: "d")!, CommandBarUnitCatalog.unit(byID: "h")!),
                (CommandBarUnitCatalog.unit(byID: "h")!, CommandBarUnitCatalog.unit(byID: "min")!),
                (CommandBarUnitCatalog.unit(byID: "min")!, CommandBarUnitCatalog.unit(byID: "s")!),
            ]
            for (larger, smaller) in pairs {
                let total = (value.si - larger.offset) / larger.scale
                if total >= 1 {
                    return split(value, larger: larger, smaller: smaller)
                }
            }
            // Below a minute, seconds alone.
            return split(value, larger: CommandBarUnitCatalog.unit(byID: "min")!,
                         smaller: CommandBarUnitCatalog.unit(byID: "s")!)
        }

        // MARK: Functions

        private func apply(_ function: Function, to arguments: [Value]) -> Value? {
            switch function {
            case .sqrt, .cbrt:
                guard arguments.count == 1, let argument = arguments.first else { return nil }
                return root(argument, degree: function == .sqrt ? 2 : 3)
            case .abs:
                guard arguments.count == 1, let argument = arguments.first else { return nil }
                return Value(si: Swift.abs(argument.si), dims: argument.dims,
                             unit: argument.unit, percentRaw: nil, hasNumber: true)
            case .round, .floor, .ceil:
                guard arguments.count == 1, let argument = arguments.first else { return nil }
                let result: Double
                switch function {
                case .round: result = argument.si.rounded()
                case .floor: result = Foundation.floor(argument.si)
                default: result = Foundation.ceil(argument.si)
                }
                return Value(si: result, dims: argument.dims, unit: argument.unit,
                             percentRaw: nil, hasNumber: true)
            case .min, .max:
                guard !arguments.isEmpty else { return nil }
                let unit = arguments.first?.unit
                let dims = arguments.first?.dims ?? .none
                guard arguments.allSatisfy({ $0.unit == unit && $0.dims == dims }) else { return nil }
                let values = arguments.map(\.si)
                let result = function == .min ? values.min()! : values.max()!
                return Value(si: result, dims: dims, unit: unit, percentRaw: nil, hasNumber: true)
            case .log:
                guard arguments.count == 1 || arguments.count == 2 else { return nil }
                guard arguments.allSatisfy({ $0.unit == nil }) else { return nil }
                let value = arguments[0].si
                guard value > 0 else { return nil }
                let base = arguments.count == 2 ? arguments[1].si : 10
                guard base > 0, base != 1 else { return nil }
                return Value(si: Foundation.log(value) / Foundation.log(base),
                             dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            case .log10:
                guard arguments.count == 1, let argument = arguments.first,
                      argument.unit == nil, argument.si > 0 else { return nil }
                return Value(si: Foundation.log10(argument.si), dims: .none,
                             unit: nil, percentRaw: nil, hasNumber: true)
            case .ln:
                guard arguments.count == 1, let argument = arguments.first,
                      argument.unit == nil, argument.si > 0 else { return nil }
                return Value(si: Foundation.log(argument.si), dims: .none,
                             unit: nil, percentRaw: nil, hasNumber: true)
            case .exp:
                guard arguments.count == 1, let argument = arguments.first,
                      argument.unit == nil else { return nil }
                return Value(si: Foundation.exp(argument.si), dims: .none,
                             unit: nil, percentRaw: nil, hasNumber: true)
            case .sin, .cos, .tan, .asin, .acos, .atan:
                guard arguments.count == 1, let argument = arguments.first else { return nil }
                let radians: Double
                if argument.unit == nil {
                    radians = argument.si
                } else if argument.dims == CommandBarUnitCatalog.Dimensions(angle: 1) {
                    radians = argument.si
                } else {
                    return nil
                }
                let result: Double?
                switch function {
                case .sin: result = Foundation.sin(radians)
                case .cos: result = Foundation.cos(radians)
                case .tan: result = Foundation.tan(radians)
                case .asin: result = (-1...1).contains(radians) ? Foundation.asin(radians) : nil
                case .acos: result = (-1...1).contains(radians) ? Foundation.acos(radians) : nil
                case .atan: result = Foundation.atan(radians)
                default: result = nil
                }
                guard let result, result.isFinite else { return nil }
                return Value(si: result, dims: .none, unit: nil, percentRaw: nil, hasNumber: true)
            }
        }
    }
}

// MARK: - Value helpers

extension CommandBarExpressions.Value {
    /// Whether this is an affine temperature reading rather than a length.
    var isTemperature: Bool { unit?.offset != 0 }
}

// MARK: - Unit composition

extension CommandBarExpressions {
    /// Builds a compound unit from a numerator and denominator, preferring an
    /// existing catalog unit whose dimensions and scale match.
    static func compound(numerator: CommandBarUnitCatalog.Unit,
                         denominator: CommandBarUnitCatalog.Unit) -> CommandBarUnitCatalog.Unit {
        let dims = numerator.dimensions / denominator.dimensions
        let scale = numerator.scale / denominator.scale
        return resolve(dims: dims, scale: scale, symbol: "\(numerator.symbol)/\(denominator.symbol)")
    }

    static func reciprocal(_ unit: CommandBarUnitCatalog.Unit) -> CommandBarUnitCatalog.Unit {
        resolve(dims: unit.dimensions.negated(), scale: 1 / unit.scale,
                symbol: "1/\(unit.symbol)")
    }

    static func scaled(_ unit: CommandBarUnitCatalog.Unit,
                       by factor: Double) -> CommandBarUnitCatalog.Unit {
        resolve(dims: unit.dimensions, scale: unit.scale * factor, symbol: unit.symbol)
    }

    static func productUnit(_ left: CommandBarUnitCatalog.Unit,
                            _ right: CommandBarUnitCatalog.Unit) -> CommandBarUnitCatalog.Unit {
        if left.id == right.id, let square = CommandBarUnitCatalog.squaredPartners[left.id] {
            return square
        }
        let dims = left.dimensions * right.dimensions
        let scale = left.scale * right.scale
        return resolve(dims: dims, scale: scale, symbol: "\(left.symbol)·\(right.symbol)")
    }

    static func quotientUnit(_ left: CommandBarUnitCatalog.Unit,
                             _ right: CommandBarUnitCatalog.Unit) -> CommandBarUnitCatalog.Unit {
        let dims = left.dimensions / right.dimensions
        let scale = left.scale / right.scale
        return resolve(dims: dims, scale: scale, symbol: "\(left.symbol)/\(right.symbol)")
    }

    static func rootUnit(_ unit: CommandBarUnitCatalog.Unit,
                         degree: Int) -> CommandBarUnitCatalog.Unit? {
        if let rooted = CommandBarUnitCatalog.rootedPartners[unit.id] {
            return rooted
        }
        let dims = unit.dimensions.dividedExponents(by: degree)
        let scale = pow(unit.scale, 1.0 / Double(degree))
        return resolve(dims: dims, scale: scale, symbol: unit.symbol)
    }

    /// Finds a catalog unit matching the dimensions and scale, or synthesizes
    /// one carrying the composed symbol when no catalog unit fits.
    static func resolve(dims: CommandBarUnitCatalog.Dimensions,
                        scale: Double,
                        symbol: String) -> CommandBarUnitCatalog.Unit {
        for unit in CommandBarUnitCatalog.all
        where unit.offset == 0 && unit.dimensions == dims && scalesMatch(unit.scale, scale) {
            return unit
        }
        return CommandBarUnitCatalog.Unit("composite", dims, scale: scale,
                                          foundation: nil, symbol: symbol, names: [])
    }

    static func scalesMatch(_ a: Double, _ b: Double) -> Bool {
        if a == b { return true }
        let magnitude = max(abs(a), abs(b))
        return magnitude == 0 ? true : abs(a - b) <= magnitude * 1e-9
    }
}
