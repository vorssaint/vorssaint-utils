// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The command bar calculator: the facade the catalog and the service call. It
/// runs `CommandBarExpressions` and writes the answer the way this Mac writes
/// numbers — grouped thousands, a scientific exponent for very large or small
/// values, and a localized unit from Foundation when one exists.
enum CommandBarCalculator {
    struct Result: Equatable {
        /// The answer, written the way this Mac writes numbers.
        let formatted: String
        /// The numeric value shown, or nil when the answer is a split amount
        /// whose parts do not combine into one number.
        let value: Double?
        /// Closing brackets supplied virtually while an expression was
        /// unfinished: "([2+3" reports "])".
        let closingBrackets: String
        /// A round-trippable form to put back in the field: the number for a
        /// plain result, "value symbol" for a unit result, nil for a split.
        let reusableExpression: String?
    }

    static func evaluate(_ input: String,
                         locale: Locale = .current,
                         decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                         groupingSeparator: String = Locale.current.groupingSeparator ?? ",") -> Result? {
        let trimmed = CommandBarSearch.strippingInvisibles(input)
            .folding(options: .widthInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let expression = expressionWithoutTrailingEquals(trimmed),
              expression.count <= 120, !looksLikeDateOrTime(expression) else { return nil }

        guard let parsed = CommandBarExpressions.parse(expression,
                                                       decimalSeparator: decimalSeparator,
                                                       groupingSeparator: groupingSeparator)
        else { return nil }
        guard parsed.isCalculation else {
            // These two useful bare measurements have established answers in
            // the launcher: a meter as feet and inches, and an hour as minutes.
            // Keep other lone quantities as searches rather than answering
            // every number-plus-unit phrase.
            guard case .value(let value) = parsed.outcome, value.hasNumber,
                  let unit = value.unit
            else { return nil }
            let target: String
            switch unit.id {
            case "m": target = "feet and inches"
            case "h": target = "minutes"
            default: return nil
            }
            return evaluate("\(expression) to \(target)",
                            locale: locale,
                            decimalSeparator: decimalSeparator,
                            groupingSeparator: groupingSeparator)
        }

        switch parsed.outcome {
        case .value(let value):
            if let unit = value.unit {
                let display = significantRounded(unit.displayValue(siValue: value.si))
                guard display.isFinite else { return nil }
                return Result(formatted: formatUnit(display, unit: unit, locale: locale),
                              value: display,
                              closingBrackets: parsed.closingBrackets,
                              reusableExpression: reusable(display, unit: unit, si: value.si,
                                                           decimalSeparator: decimalSeparator,
                                                           groupingSeparator: groupingSeparator))
            }
            let display = significantRounded(value.si)
            guard display.isFinite, let formatted = format(display, locale: locale) else { return nil }
            return Result(formatted: formatted,
                          value: display,
                          closingBrackets: parsed.closingBrackets,
                          reusableExpression: reusableNumber(display, decimalSeparator: decimalSeparator))
        case .split(let split):
            let larger = significantRounded(split.larger.value)
            let smaller = significantRounded(split.smaller.value)
            guard larger.isFinite, smaller.isFinite else { return nil }
            let formatted = formatSplit(larger, split.larger.unit, smaller, split.smaller.unit,
                                        locale: locale)
            return Result(formatted: formatted,
                          value: nil,
                          closingBrackets: parsed.closingBrackets,
                          reusableExpression: nil)
        }
    }

    /// Rejects "2026-07-27", "27/07/2026" and "10:30": groups of digits held
    /// together by a single kind of separator with nothing else around them.
    static func looksLikeDateOrTime(_ input: String) -> Bool {
        for separator in ["-", "/", ":"] as [Character] {
            let parts = input.split(separator: separator, omittingEmptySubsequences: false)
            guard parts.count >= 2, parts.count <= 3 else { continue }
            guard parts.allSatisfy({ part in
                let digits = separator == ":" ? part.trimmingCharacters(in: .whitespaces) : String(part)
                return !digits.isEmpty && digits.count <= 4 && digits.allSatisfy(\.isNumber)
            }) else { continue }
            if separator == ":" { return true }
            if parts.count == 3 { return true }
        }
        return false
    }

    private static func expressionWithoutTrailingEquals(_ input: String) -> String? {
        guard let equals = input.firstIndex(of: "=") else { return input }
        guard equals == input.index(before: input.endIndex) else { return nil }
        let expression = String(input[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        return expression.isEmpty ? nil : expression
    }

    // MARK: - Number formatting

    /// Keeps ten significant digits so ordinary decimal arithmetic loses binary
    /// noise, but never fewer than a large number's whole digits plus two
    /// decimals. Fifteen is the most, since that many significant digits always
    /// survive a round trip through a Double.
    static func significantRounded(_ value: Double) -> Double {
        guard value != 0, value.isFinite else { return value }
        let magnitude = floor(log10(abs(value)))
        let digits = min(15, max(10, magnitude + 3))
        let exponent = digits - magnitude - 1
        if exponent < 0 {
            let divisor = pow(10.0, -exponent)
            let rounded = (value / divisor).rounded() * divisor
            return rounded.isFinite ? rounded : value
        }
        let factor = pow(10.0, exponent)
        guard factor.isFinite, factor != 0 else { return value }
        let scaled = (value * factor).rounded()
        guard scaled.isFinite else { return value }
        return scaled / factor
    }

    /// A plain number, grouped and with a scientific exponent when it would
    /// otherwise read as zero or a wall of zeros.
    static func format(_ value: Double, locale: Locale = .current) -> String? {
        let rounded = significantRounded(value)
        guard rounded.isFinite else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        let magnitude = abs(rounded)
        if rounded != 0, magnitude >= 1e12 || magnitude < 1e-6 {
            formatter.numberStyle = .scientific
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 8
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 8
        }
        return formatter.string(from: NSNumber(value: rounded == 0 ? 0 : rounded))
    }

    /// Writes a quantity the way this Mac writes numbers, with the system's
    /// own word for the unit when it has one. Precision follows the size of the
    /// number: small ones keep their decimals, big ones lose the noise.
    private static func formatUnit(_ value: Double,
                                   unit: CommandBarUnitCatalog.Unit,
                                   locale: Locale) -> String {
        // Feet are the one unit people read as a pair, so a length of a foot or
        // more is written as whole feet and the inches left over.
        if unit.id == "ft", value >= 1, value != value.rounded(.down),
           let feet = CommandBarUnitCatalog.unit(byID: "ft"),
           let inches = CommandBarUnitCatalog.unit(byID: "in") {
            return feetAndInches(value, feet: feet, inches: inches, locale: locale)
        }
        return measured(value, unit: unit, locale: locale, maximumFractionDigits: nil)
    }

    /// Full precision, for the amounts of a split answer: the person asked for
    /// "feet and inches", not for a rounded pair.
    private static func formatUnitPrecisely(_ value: Double,
                                            unit: CommandBarUnitCatalog.Unit,
                                            locale: Locale) -> String {
        measured(value, unit: unit, locale: locale, maximumFractionDigits: 15)
    }

    private static func measured(_ value: Double,
                                 unit: CommandBarUnitCatalog.Unit,
                                 locale: Locale,
                                 maximumFractionDigits: Int?) -> String {
        let number = NumberFormatter()
        number.locale = locale
        number.minimumFractionDigits = 0
        number.usesGroupingSeparator = true
        let magnitude = abs(value)
        if let maximumFractionDigits {
            number.numberStyle = .decimal
            number.maximumFractionDigits = maximumFractionDigits
        } else if magnitude != 0, magnitude < 0.001, unit.dimensions.temperature != 1 {
            // Four decimals would print a millionth as "0", which reads as a
            // wrong answer, so a tiny value keeps its significant digits.
            number.numberStyle = .decimal
            number.usesSignificantDigits = true
            number.maximumSignificantDigits = 4
        } else {
            // Temperature offsets can leave a tiny remainder at zero; keep the
            // decimal precision instead of exposing it.
            number.numberStyle = .decimal
            number.maximumFractionDigits = fractionDigits(for: value)
        }

        guard let foundation = unit.foundation else {
            let text = number.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? String(value)
            return "\(text) \(unit.symbol)"
        }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        // The unit asked for is the unit shown; nobody types "to mb" hoping for
        // gigabytes.
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        // Foundation here words the number from the system locale it carries
        // itself, so the prepared formatter is handed over whole.
        formatter.numberFormatter = number
        return formatter.string(from: Measurement(value: value == 0 ? 0 : value, unit: foundation))
    }

    /// Small numbers keep their decimals, big ones lose the noise.
    private static func fractionDigits(for value: Double) -> Int {
        let magnitude = abs(value)
        if magnitude == 0 { return 0 }
        if magnitude < 1 { return 4 }
        if magnitude < 100 { return 2 }
        return 1
    }

    /// A whole number of feet plus the inches left over, with the inches that
    /// round up to twelve carried into the next foot.
    private static func feetAndInches(_ value: Double,
                                      feet: CommandBarUnitCatalog.Unit,
                                      inches: CommandBarUnitCatalog.Unit,
                                      locale: Locale) -> String {
        var wholeFeet = value.rounded(.down)
        let rawInches = (value - wholeFeet) * 12
        let scale = pow(10, Double(fractionDigits(for: rawInches)))
        var shownInches = (rawInches * scale).rounded() / scale
        if shownInches >= 12 {
            wholeFeet += 1
            shownInches = 0
        }
        let feetText = formatUnit(wholeFeet, unit: feet, locale: locale)
        guard shownInches != 0 else { return feetText }
        return "\(feetText) \(formatUnit(shownInches, unit: inches, locale: locale))"
    }

    private static func formatSplit(_ larger: Double, _ largerUnit: CommandBarUnitCatalog.Unit,
                                    _ smaller: Double, _ smallerUnit: CommandBarUnitCatalog.Unit,
                                    locale: Locale) -> String {
        // A whole larger unit plus the remainder in the smaller one, each
        // written by Foundation when it has a word for the unit.
        let largerText = formatUnitPrecisely(larger, unit: largerUnit, locale: locale)
        guard smaller != 0 else { return largerText }
        let smallerText = formatUnitPrecisely(smaller, unit: smallerUnit, locale: locale)
        return "\(largerText) \(smallerText)"
    }

    // MARK: - Reuse

    /// Swift's shortest round-trip spelling, so the reused number loses no
    /// precision and exposes no binary noise; brackets preserve negatives.
    private static func reusableNumber(_ value: Double, decimalSeparator: String) -> String {
        let number = value == 0 ? 0 : value
        var ascii = String(number)
        if ascii.hasSuffix(".0") { ascii.removeLast(2) }
        let separator = decimalSeparator.isEmpty ? "." : decimalSeparator
        let localized = ascii.replacingOccurrences(of: ".", with: separator)
        return number < 0 ? "(\(localized))" : localized
    }

    private static func reusable(_ value: Double,
                                 unit: CommandBarUnitCatalog.Unit,
                                 si: Double,
                                 decimalSeparator: String,
                                 groupingSeparator: String) -> String? {
        let number = reusableNumber(abs(value), decimalSeparator: decimalSeparator)
        let symbol = unit.reuseSymbol
        let quantity = "\(value < 0 ? "-" : "")\(number) \(symbol)"
        if unit.id == "composite" {
            // A composed label can contain a reciprocal, radical or ambiguous
            // unit symbol. Only put it back in the field if it parses identically.
            let parsed = CommandBarExpressions.parse(quantity, decimalSeparator: decimalSeparator,
                                                      groupingSeparator: groupingSeparator)
            if case .value(let read)? = parsed?.outcome, let readUnit = read.unit,
               read.dims == unit.dimensions, readUnit.scale == unit.scale,
               significantRounded(readUnit.displayValue(siValue: read.si)) == value,
               quantity.count <= 118 {
                return "(\(quantity))"
            }
            let dims = unit.dimensions
            let factors = [("m", dims.length), ("kg", dims.mass), ("s", dims.time),
                           ("kelvin", dims.temperature), ("bit", dims.data),
                           ("rad", dims.angle), ("amp", dims.current)]
            var expression = reusableNumber(si, decimalSeparator: decimalSeparator)
            for (name, exponent) in factors where exponent != 0 {
                let factor = exponent > 0 ? " * (1 \(name))" : " / (1 \(name))"
                expression += String(repeating: factor, count: abs(exponent))
            }
            return expression.count <= 118 ? "(\(expression))" : nil
        }
        // Group the entire quantity before a subsequent power or division.
        if value < 0 || symbol.contains(where: { "/·*".contains($0) }) {
            return "(\(quantity))"
        }
        return quantity
    }
}
