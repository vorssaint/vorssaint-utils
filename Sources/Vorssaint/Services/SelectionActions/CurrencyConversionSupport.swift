// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import Foundation

/// Converts a detected amount to another currency via frankfurter.dev — free,
/// keyless, callable directly from the app (verified against its live
/// endpoint and docs, not guessed). Fails silently (nil) on any network or
/// parsing problem: a failed conversion should leave the selection alone,
/// not replace it with garbage.
enum CurrencyConversionSupport {
    static func convert(amount: Double,
                        from source: String,
                        to target: String,
                        completion: @escaping (Double?) -> Void) {
        let from = source.uppercased()
        let to = target.uppercased()
        guard from != to else {
            completion(amount)
            return
        }
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")
        components?.queryItems = [
            URLQueryItem(name: "base", value: from),
            URLQueryItem(name: "symbols", value: to),
        ]
        guard let url = components?.url else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Any],
                  let rate = (rates[to] as? NSNumber)?.doubleValue
            else {
                completion(nil)
                return
            }
            completion(amount * rate)
        }.resume()
    }
}
