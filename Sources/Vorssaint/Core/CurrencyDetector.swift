// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A money amount found in a selection, ready to convert.
struct DetectedCurrency: Equatable {
    let amount: Double
    let currencyCode: String
}

/// Finds a currency symbol or ISO code next to a number in a short piece of
/// text, e.g. "$100", "100 USD", "₹4,500.50". Deliberately conservative: no
/// match beats a wrong one, since a wrong source currency silently produces
/// a wrong converted amount.
enum CurrencyDetector {
    private static let symbolToCode: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR",
        "₩": "KRW", "₽": "RUB", "₴": "UAH", "₺": "TRY", "₫": "VND",
        "R$": "BRL", "C$": "CAD", "A$": "AUD",
    ]

    /// Common ISO 4217 codes: a bare 3-letter run next to a number only
    /// counts when it is actually one of these, so "the 100" never reads as
    /// a currency named THE. Also the choices Convert Currency's "Convert
    /// to" picker offers.
    static let knownCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "INR", "AUD", "CAD", "CHF", "CNY", "HKD",
        "NZD", "SEK", "KRW", "SGD", "NOK", "MXN", "ZAR", "BRL", "RUB", "TRY",
        "AED", "SAR", "THB", "MYR", "IDR", "PHP", "VND", "PLN", "DKK", "CZK",
        "HUF", "ILS", "EGP", "NGN", "PKR", "BDT", "UAH", "ARS", "CLP", "COP",
        "PEN", "KWD", "QAR",
    ]

    static let sortedKnownCodes: [String] = knownCodes.sorted()

    static func detect(in text: String) -> DetectedCurrency? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }

        if let match = firstMatch(pattern: #"^(R\$|C\$|A\$|[$€£¥₹₩₽₴₺₫])\s?([0-9][0-9,]*\.?[0-9]*)$"#, in: trimmed),
           let code = symbolToCode[match.0], let amount = parseAmount(match.1) {
            return DetectedCurrency(amount: amount, currencyCode: code)
        }
        if let match = firstMatch(pattern: #"^([0-9][0-9,]*\.?[0-9]*)\s?(R\$|C\$|A\$|[$€£¥₹₩₽₴₺₫])$"#, in: trimmed),
           let code = symbolToCode[match.1], let amount = parseAmount(match.0) {
            return DetectedCurrency(amount: amount, currencyCode: code)
        }
        if let match = firstMatch(pattern: #"^([A-Za-z]{3})\s?([0-9][0-9,]*\.?[0-9]*)$"#, in: trimmed),
           knownCodes.contains(match.0.uppercased()), let amount = parseAmount(match.1) {
            return DetectedCurrency(amount: amount, currencyCode: match.0.uppercased())
        }
        if let match = firstMatch(pattern: #"^([0-9][0-9,]*\.?[0-9]*)\s?([A-Za-z]{3})$"#, in: trimmed),
           knownCodes.contains(match.1.uppercased()), let amount = parseAmount(match.0) {
            return DetectedCurrency(amount: amount, currencyCode: match.1.uppercased())
        }
        return nil
    }

    private static func parseAmount(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    private static func firstMatch(pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges == 3,
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text)
        else { return nil }
        return (String(text[r1]), String(text[r2]))
    }
}
