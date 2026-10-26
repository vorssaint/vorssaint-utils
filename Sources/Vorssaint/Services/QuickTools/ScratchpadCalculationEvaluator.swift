// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Per-line calculation retains the units of variables and aggregate values.
enum ScratchpadCalculationEvaluator {
    struct LineResult: Equatable, Sendable {
        let source: String
        let value: Double?
        let formatted: String?
        let variable: String?
    }

    struct Result: Equatable, Sendable {
        let lines: [LineResult]
        let variables: [String: Double]
        var copyText: String {
            lines.map { line in
                guard let formatted = line.formatted,
                      formatted.caseInsensitiveCompare(line.source.trimmingCharacters(in: .whitespaces)) != .orderedSame
                else { return line.source }
                return "\(line.source)    \(formatted)"
            }.joined(separator: "\n")
        }
    }

    static func evaluate(_ source: String, currencyRates: ScratchpadCurrencyRates? = nil,
                         decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                         groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                         locale: Locale = .current) -> Result {
        var context = Context(rates: currencyRates, decimal: decimalSeparator, grouping: groupingSeparator, locale: locale)
        var results: [LineResult] = []
        var constants: [String: Quantity?] = [:]
        var rendered: [Quantity: String] = [:]
        for line in lines(in: source) {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let match = assignment.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length))
            let name = match.map { (trimmed as NSString).substring(with: $0.range(at: 1)).lowercased() }
            let expression = match.map { (trimmed as NSString).substring(with: $0.range(at: 2)) } ?? trimmed
            let quantity: Quantity?
            if let cached = constants[expression] { quantity = cached }
            else {
                quantity = context.evaluate(expression)
                if !expression.contains(where: { $0.isLetter || $0 == "_" }) {
                    constants.updateValue(quantity, forKey: expression)
                }
            }
            var formatted: String?
            if let quantity {
                formatted = rendered[quantity] ?? context.format(quantity)
                if let formatted { rendered[quantity] = formatted }
                context.record(quantity)
            }
            if let name { context.variables[name] = quantity }
            results.append(LineResult(source: line, value: quantity?.value, formatted: formatted, variable: name))
        }
        return Result(lines: results, variables: context.variables.mapValues(\.value))
    }

    private static let assignment = try! NSRegularExpression(pattern: #"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$"#)
    private static let unitLiteral = try! NSRegularExpression(pattern: #"^(.+?)\s*([A-Za-z°]+|['"])$"#)

    private struct Quantity: Hashable {
        var value: Double
        var unit: String? = nil
    }

    private struct Context {
        let rates: ScratchpadCurrencyRates?
        let decimal: String
        let grouping: String
        let locale: Locale
        var variables: [String: Quantity] = [:]
        var previous: Quantity?
        var total: Quantity?
        var count = 0
        var aggregateValid = true

        mutating func record(_ value: Quantity) {
            previous = value
            if count == 0 { total = value }
            else if aggregateValid, let existing = total { total = adding(existing, value) }
            aggregateValid = total != nil
            count += 1
        }

        func lookup(_ name: String) -> Quantity? {
            if let value = variables[name] { return value }
            switch name {
            case "prev": return previous
            case "sum": return aggregateValid ? total : nil
            case "avg":
                guard aggregateValid, var value = total, count > 0 else { return nil }
                value.value /= Double(count)
                return value
            default: return nil
            }
        }

        func knownUnit(_ symbol: String) -> Bool {
            ScratchpadCurrency.supportedSymbols.contains(symbol) || CommandBarUnits.family(of: symbol) != nil
        }

        func converted(_ quantity: Quantity, to target: String) -> Quantity? {
            guard let source = quantity.unit else { return nil }
            if source == target { return quantity }
            let value: Double?
            if ScratchpadCurrency.supportedSymbols.contains(source), ScratchpadCurrency.supportedSymbols.contains(target) {
                value = rates?.convert(value: quantity.value, from: source, to: target)
            } else { value = CommandBarUnits.convert(value: quantity.value, from: source, to: target, locale: locale)?.value }
            return value.map { Quantity(value: $0, unit: target) }
        }

        func adding(_ left: Quantity, _ right: Quantity) -> Quantity? {
            let adjusted: Quantity
            if let unit = left.unit {
                guard let converted = converted(right, to: unit) else { return nil }
                adjusted = converted
            } else {
                guard right.unit == nil else { return nil }
                adjusted = right
            }
            let value = left.value + adjusted.value
            return value.isFinite ? Quantity(value: value, unit: left.unit) : nil
        }

        func format(_ quantity: Quantity) -> String? {
            guard let unit = quantity.unit else { return CommandBarMath.format(quantity.value, locale: locale) }
            if ScratchpadCurrency.supportedSymbols.contains(unit) {
                return ScratchpadCurrency.format(quantity.value, in: unit, locale: locale)
            }
            return CommandBarUnits.convert(value: quantity.value, from: unit, to: unit, locale: locale)?.formatted
        }

        func evaluate(_ input: String, depth: Int = 0) -> Quantity? {
            guard depth < 32 else { return nil }
            var expression = input.trimmingCharacters(in: .whitespaces)
            if expression.hasSuffix("=") { expression = expression.dropLast().trimmingCharacters(in: .whitespaces) }
            guard !expression.isEmpty, expression.count <= 120, !expression.contains("="),
                  !CommandBarMath.looksLikeDateOrTime(expression) else { return nil }
            if let value = lookup(expression.lowercased()) { return value }
            if let literal = CommandBarMath.literalValue(expression, decimalSeparator: decimal, groupingSeparator: grouping) {
                return Quantity(value: literal)
            }
            if let expanded = scalarExpression(expression),
               let result = CommandBarMath.evaluate(expanded, decimalSeparator: decimal, groupingSeparator: grouping, locale: locale) {
                return Quantity(value: result.value)
            }

            let tokens = CommandBarUnits.tokenize(expression)
            if let target = tokens.last, knownUnit(target), tokens.count >= 3,
               CommandBarUnits.conversionWords.contains(tokens[tokens.count - 2]),
               let value = evaluate(tokens.dropLast(2).joined(separator: " "), depth: depth + 1) {
                return converted(value, to: target)
            }
            // Preserve the launcher's richer literal spellings, including feet/inches.
            if let target = tokens.last, CommandBarUnits.family(of: target) != nil,
               let result = CommandBarUnits.convert(expression, decimalSeparator: decimal, groupingSeparator: grouping, locale: locale) {
                return Quantity(value: result.value, unit: target)
            }
            let characters = Array(expression.replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")"))
            for operators in ["+-", "*/", "^"] {
                if let position = split(characters, operators: operators) {
                    guard let left = evaluate(String(characters[..<position]), depth: depth + 1),
                          let right = evaluate(String(characters[(position + 1)...]), depth: depth + 1) else { return nil }
                    return applying(characters[position], left, right)
                }
                // Unary minus has lower precedence than powers, as in the shared calculator.
                if operators == "*/", let first = characters.first, first == "-" || first == "+",
                   var value = evaluate(String(characters.dropFirst()), depth: depth + 1) {
                    if first == "-" { value.value = -value.value }
                    return value
                }
            }
            if characters.first == "(", characters.last == ")" {
                return evaluate(String(characters.dropFirst().dropLast()), depth: depth + 1)
            }
            if let match = unitLiteral.firstMatch(in: expression, range: NSRange(location: 0, length: (expression as NSString).length)) {
                let source = expression as NSString
                let unit = source.substring(with: match.range(at: 2)).lowercased()
                guard knownUnit(unit), let value = evaluate(source.substring(with: match.range(at: 1)), depth: depth + 1),
                      value.unit == nil else { return nil }
                return Quantity(value: value.value, unit: unit)
            }
            return nil
        }

        func applying(_ operation: Character, _ left: Quantity, _ right: Quantity) -> Quantity? {
            switch operation {
            case "+": return adding(left, right)
            case "-": return adding(left, Quantity(value: -right.value, unit: right.unit))
            case "*":
                guard left.unit == nil || right.unit == nil else { return nil }
                let value = left.value * right.value
                return value.isFinite ? Quantity(value: value, unit: left.unit ?? right.unit) : nil
            case "/":
                guard right.value != 0 else { return nil }
                let result: Quantity
                if let unit = right.unit {
                    guard let adjusted = converted(right, to: left.unit ?? unit), left.unit != nil else { return nil }
                    result = Quantity(value: left.value / adjusted.value)
                } else { result = Quantity(value: left.value / right.value, unit: left.unit) }
                return result.value.isFinite ? result : nil
            case "^":
                guard right.unit == nil, left.unit == nil || right.value == 0 || right.value == 1 else { return nil }
                let value = pow(left.value, right.value)
                return value.isFinite ? Quantity(value: value, unit: right.value == 0 ? nil : left.unit) : nil
            default: return nil
            }
        }

        /// Finds a top-level binary operator, excluding signs and scientific exponents.
        func split(_ characters: [Character], operators: String) -> Int? {
            var depth = 0
            var result: Int?
            var previous: Character?
            for (index, character) in characters.enumerated() {
                if character == "(" { depth += 1 }
                else if character == ")" { depth -= 1 }
                else if depth == 0, operators.contains(character), let before = previous,
                        !"+-*/^(".contains(before) {
                    let exponentSign = (character == "+" || character == "-") && (before == "e" || before == "E")
                        && index >= 2 && characters[index - 2].isNumber
                    if !exponentSign {
                        result = index
                        if operators == "^" { return result }
                    }
                }
                if !character.isWhitespace { previous = character }
            }
            return depth == 0 ? result : nil
        }

        func scalarExpression(_ expression: String) -> String? {
            let characters = Array(expression)
            var output = ""
            var index = 0
            while index < characters.count {
                guard characters[index].isASCII && (characters[index].isLetter || characters[index] == "_") else {
                    output.append(characters[index]); index += 1; continue
                }
                let start = index
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber || characters[index] == "_" { index += 1 }
                let word = String(characters[start..<index])
                if !(start > 0 && (characters[start - 1].isNumber || characters[start - 1] == ".")),
                   let quantity = lookup(word.lowercased()) {
                    guard quantity.unit == nil else { return nil }
                    output += CommandBarMath.reusableExpression(for: .init(formatted: "", value: quantity.value, closingBrackets: ""),
                                                              decimalSeparator: decimal)
                } else { output += word }
            }
            return output
        }
    }

    static func lines(in source: String) -> [String] {
        source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{2029}", with: "\n")
            .components(separatedBy: "\n")
    }
}
