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
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        guard !looksLikeDateOrTime(trimmed) else { return nil }
        guard let expression = expressionWithoutTrailingEquals(trimmed) else { return nil }

        guard let parsed = CommandBarExpressions.parse(expression,
                                                       decimalSeparator: decimalSeparator,
                                                       groupingSeparator: groupingSeparator),
              parsed.isCalculation
        else { return nil }

        switch parsed.outcome {
        case .value(let value):
            if let unit = value.unit {
                let display = significantRounded(unit.displayValue(siValue: value.si))
                guard display.isFinite else { return nil }
                return Result(formatted: formatUnit(display, unit: unit, locale: locale),
                              value: display,
                              closingBrackets: parsed.closingBrackets,
                              reusableExpression: reusable(display, unit: unit,
                                                           decimalSeparator: decimalSeparator))
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
            let formatted = formatSplit(larger, split.larger.unit, smaller, split.smaller.unit,
                                        locale: locale)
            return Result(formatted: formatted,
                          value: larger,
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

    /// A quantity's numeric part, at the full precision a conversion needs:
    /// 3.106855961 mi, 7.9375 mm, 0.001 g/cm³.
    private static func unitNumber(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        let magnitude = abs(value)
        if value != 0, magnitude >= 1e12 || magnitude < 1e-6 {
            formatter.numberStyle = .scientific
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 12
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 15
        }
        return formatter.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? String(value)
    }

    private static func formatUnit(_ value: Double,
                                   unit: CommandBarUnitCatalog.Unit,
                                   locale: Locale) -> String {
        if let foundation = unit.foundation {
            let formatter = MeasurementFormatter()
            formatter.locale = locale
            formatter.unitOptions = .providedUnit
            formatter.unitStyle = .medium
            formatter.numberFormatter.locale = locale
            formatter.numberFormatter.minimumFractionDigits = 0
            formatter.numberFormatter.usesGroupingSeparator = true
            formatter.numberFormatter.maximumFractionDigits = 15
            let measurement = Measurement(value: value, unit: foundation)
            return formatter.string(from: measurement)
        }
        return "\(unitNumber(value, locale: locale)) \(unit.symbol)"
    }

    private static func formatSplit(_ larger: Double, _ largerUnit: CommandBarUnitCatalog.Unit,
                                    _ smaller: Double, _ smallerUnit: CommandBarUnitCatalog.Unit,
                                    locale: Locale) -> String {
        // A whole larger unit plus the remainder in the smaller one, each
        // written by Foundation when it has a word for the unit.
        let largerText = formatUnit(larger, unit: largerUnit, locale: locale)
        guard smaller != 0 else { return largerText }
        let smallerText = formatUnit(smaller, unit: smallerUnit, locale: locale)
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
                                 decimalSeparator: String) -> String {
        "\(reusableNumber(value, decimalSeparator: decimalSeparator)) \(unit.symbol)"
    }
}
