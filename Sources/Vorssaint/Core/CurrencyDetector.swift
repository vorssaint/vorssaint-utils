// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
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
    /// Every value here must be a `knownCodes` member — a symbol whose
    /// currency Convert Currency can't actually convert would detect fine
    /// and then silently do nothing when pressed. Enforced in
    /// `MetricsTests`, not just this comment: internal so the test can see
    /// it.
    static let symbolToCode: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR",
        "₩": "KRW", "₺": "TRY",
        "R$": "BRL", "C$": "CAD", "A$": "AUD",
    ]

    /// Common ISO 4217 codes: a bare 3-letter run next to a number only
    /// counts when it is actually one of these, so "the 100" never reads as
    /// a currency named THE. Also the choices Convert Currency's "Convert
    /// to" picker offers. Constrained to what frankfurter.dev's
    /// `/v1/currencies` actually serves (verified live) — offering a code it
    /// doesn't know about would detect the currency and then have Convert
    /// Currency silently do nothing when pressed.
    static let knownCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "INR", "AUD", "CAD", "CHF", "CNY", "HKD",
        "NZD", "SEK", "KRW", "SGD", "NOK", "MXN", "ZAR", "BRL", "TRY",
        "THB", "MYR", "IDR", "PHP", "PLN", "DKK", "CZK",
        "HUF", "ILS",
    ]

    static let sortedKnownCodes: [String] = knownCodes.sorted()

    /// `Locale.current.currency` can name a code the "Convert to" picker
    /// never offers (e.g. TWD for zh-TW/zh-HK, both shipped languages), which
    /// renders the picker's selection blank. Fall back to USD when that
    /// happens instead of passing through an unlisted code.
    static var defaultTargetCode: String {
        let code = Locale.current.currency?.identifier ?? ""
        return knownCodes.contains(code) ? code : "USD"
    }

    /// Derived from `symbolToCode` rather than written out again: a symbol
    /// added only to the dictionary would otherwise silently never match.
    /// Longer symbols first so "R$" matches before a bare "$" could.
    private static let symbolPattern: String = symbolToCode.keys
        .sorted { $0.count > $1.count }
        .map(NSRegularExpression.escapedPattern(for:))
        .joined(separator: "|")

    static func detect(in text: String) -> DetectedCurrency? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }

        if let match = firstMatch(pattern: #"^(\#(symbolPattern))\s?([0-9][0-9.,]*)$"#, in: trimmed),
           let code = symbolToCode[match.0], let amount = parseAmount(match.1) {
            return DetectedCurrency(amount: amount, currencyCode: code)
        }
        if let match = firstMatch(pattern: #"^([0-9][0-9.,]*)\s?(\#(symbolPattern))$"#, in: trimmed),
           let code = symbolToCode[match.1], let amount = parseAmount(match.0) {
            return DetectedCurrency(amount: amount, currencyCode: code)
        }
        if let match = firstMatch(pattern: #"^([A-Za-z]{3})\s?([0-9][0-9.,]*)$"#, in: trimmed),
           knownCodes.contains(match.0.uppercased()), let amount = parseAmount(match.1) {
            return DetectedCurrency(amount: amount, currencyCode: match.0.uppercased())
        }
        if let match = firstMatch(pattern: #"^([0-9][0-9.,]*)\s?([A-Za-z]{3})$"#, in: trimmed),
           knownCodes.contains(match.1.uppercased()), let amount = parseAmount(match.0) {
            return DetectedCurrency(amount: amount, currencyCode: match.1.uppercased())
        }
        return nil
    }

    /// Convention-agnostic, not locale-bound: the selected text carries
    /// *its own writer's* decimal convention, not necessarily this Mac's -
    /// Convert Currency exists specifically for a price written the other
    /// way. `NumberFormatter(locale: .current)` can only apply one
    /// convention and gets the cross-convention case wrong (silently, by up
    /// to 1000x, in one direction). `CommandBarMath.number` instead infers
    /// the separators' roles from the text's own pattern - not from
    /// `Locale.current`, which is a mismatched source: the regex above
    /// only ever captures digits plus literal `.`/`,`, so those two
    /// characters (never the Mac's own locale separators) are what
    /// `raw` can actually contain.
    private static func parseAmount(_ raw: String) -> Double? {
        CommandBarMath.number(from: raw, decimalSeparator: ".", groupingSeparator: ",")
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
