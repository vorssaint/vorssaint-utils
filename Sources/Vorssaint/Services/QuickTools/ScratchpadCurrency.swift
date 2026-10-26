// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Exchange rates for calculation mode. The date is the rate provider's own
/// calendar date, not the day the download happened, so a weekend rate still
/// reads as Friday. An empty date marks the copy that ships with the app.
struct ScratchpadCurrencyRates: Codable, Equatable, Sendable {
    let date: String
    let base: String
    let rates: [String: Double]

    /// A cautious fallback so a calculation line still answers without a
    /// network connection. These are rounded reference rates, deliberately
    /// labelled as built-in rather than presented as today's market.
    static let bundled = ScratchpadCurrencyRates(
        date: "",
        base: "USD",
        rates: [
            "AUD": 1.52, "BGN": 1.80, "BRL": 5.00, "CAD": 1.36, "CHF": 0.88,
            "CNY": 7.24, "CZK": 23.2, "DKK": 6.90, "EUR": 0.92, "GBP": 0.79,
            "HKD": 7.80, "HUF": 360, "IDR": 15_800, "ILS": 3.70, "INR": 83.5,
            "ISK": 138, "JPY": 150, "KRW": 1_330, "MXN": 17.0, "MYR": 4.70,
            "NOK": 10.7, "NZD": 1.65, "PHP": 56.5, "PLN": 4.00, "RON": 4.58,
            "SEK": 10.5, "SGD": 1.35, "THB": 36.0, "TRY": 32.0, "ZAR": 18.5,
        ])

    var isBundled: Bool {
        date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Converts through the provider's base currency, so both directions work
    /// even though the response does not repeat the base in its rate table.
    func convert(value: Double, from: String, to: String) -> Double? {
        guard value.isFinite else { return nil }
        let source = from.uppercased()
        let target = to.uppercased()
        let base = base.uppercased()
        guard source == base || isUsableRate(rates[source]),
              target == base || isUsableRate(rates[target]) else { return nil }
        let inBase = source == base ? value : value / rates[source]!
        let converted = target == base ? inBase : inBase * rates[target]!
        return converted.isFinite ? converted : nil
    }

    /// The provider's date written the way this Mac writes dates. Nil for the
    /// built-in table, which has no honest date to show.
    func localizedDate(locale: Locale) -> String? {
        guard !isBundled else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let parsed = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: parsed)
    }

    private func isUsableRate(_ rate: Double?) -> Bool {
        guard let rate else { return false }
        return rate.isFinite && rate > 0
    }
}

enum ScratchpadCurrency {
    /// The currencies the rate provider supports. Kept as lowercase parser
    /// vocabulary; the UI only ever shows the uppercased ISO code.
    static let supportedSymbols: Set<String> = [
        "aud", "bgn", "brl", "cad", "chf", "cny", "czk", "dkk", "eur", "gbp",
        "hkd", "huf", "idr", "ils", "inr", "isk", "jpy", "krw", "mxn", "myr",
        "nok", "nzd", "php", "pln", "ron", "sek", "sgd", "thb", "try", "usd",
        "zar",
    ]

    static func convert(_ input: String, rates: ScratchpadCurrencyRates,
                        decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                        groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                        locale: Locale = .current) -> (value: Double, formatted: String)? {
        let tokens = input.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count == 4, tokens[2] == "to",
              supportedSymbols.contains(tokens[1]), supportedSymbols.contains(tokens[3]),
              let value = number(tokens[0], decimalSeparator: decimalSeparator,
                                 groupingSeparator: groupingSeparator),
              let converted = rates.convert(value: value, from: tokens[1], to: tokens[3]),
              converted.isFinite else { return nil }
        return (converted, format(converted, in: tokens[3], locale: locale))
    }

    static func format(_ value: Double, in symbol: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = zeroDecimalCurrencies.contains(symbol.lowercased()) ? 0 : 2
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(value)
        return "\(formatted) \(symbol.uppercased())"
    }

    /// Currencies conventionally written without a fractional part, so a yen
    /// answer does not read as "1,234.00 JPY".
    private static let zeroDecimalCurrencies: Set<String> = ["huf", "idr", "isk", "jpy", "krw"]

    private static func number(_ input: String, decimalSeparator: String,
                               groupingSeparator: String) -> Double? {
        var normalized = input
        if !groupingSeparator.isEmpty, groupingSeparator != decimalSeparator {
            normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
        }
        if decimalSeparator != "." {
            normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        }
        guard !normalized.isEmpty, normalized.filter({ $0 == "." }).count <= 1,
              normalized.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Double(normalized)
    }
}
