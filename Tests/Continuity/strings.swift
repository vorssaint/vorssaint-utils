// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct ContinuityStringsTests {
    static func main() {
        var checked = 0
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.continuity(language)
            // Reflect every stored string so newly added copy is covered automatically.
            for field in Mirror(reflecting: strings).children {
                guard let value = field.value as? String else {
                    fatalError("Unexpected non-string field: \(field.label ?? "unknown")")
                }
                let context = "\(language.rawValue).\(field.label ?? "unknown")"
                precondition(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                             "Empty translation: \(context)")
                if field.label == "countdown" {
                    precondition(value.components(separatedBy: "%d").count == 2,
                                 "Countdown must contain exactly one %d: \(context)")
                    precondition(!value.replacingOccurrences(of: "%d", with: "").contains("%"),
                                 "Unexpected countdown format token: \(context)")
                    precondition(String(format: value, 5).contains("5"),
                                 "Countdown did not format the seconds: \(context)")
                } else {
                    precondition(!value.contains("%"), "Unexpected format token: \(context)")
                }
                checked += 1
            }
        }
        print("Continuity translations passed: \(AppLanguage.allCases.count) languages, \(checked) strings")
    }
}
