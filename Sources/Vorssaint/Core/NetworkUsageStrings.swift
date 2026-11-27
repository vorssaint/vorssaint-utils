// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Text for the Network card's daily usage block.
struct NetworkUsageStrings {
    let title: String
    let today: String
    let last7Days: String
    let last30Days: String
    let footnote: String
    let reset: String
    let resetQuestion: String

    /// English for now; other languages fall back to it until translated.
    static func current(_ language: AppLanguage) -> NetworkUsageStrings {
        .enUS
    }

    static let enUS = NetworkUsageStrings(
        title: "Data usage",
        today: "Today",
        last7Days: "Last 7 days",
        last30Days: "Last 30 days",
        footnote: "Counted while the app runs · last 30 days",
        reset: "Reset",
        resetQuestion: "Clear all recorded data usage?")
}
