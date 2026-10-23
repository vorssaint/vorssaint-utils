// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A public historical estimate, kept outside all private quota history.
struct AgentCodexResetForecast {
    let estimatedReset: Date
    let lastReset: Date
    let medianDays: Double
    let fetchedAt: Date
    let expiresAt: Date
    static let source = URL(string: "https://codex-reset.com/")!
    static let endpoint = source
    static let maximumSize = 256 << 10

    /// Use the public reference: the page's observed global reset plus its
    /// published all-time median. A different tracker or statistic changes
    /// the scenario, even when both are described as historical estimates.
    static func decode(_ data: Data, fetchedAt: Date) -> Self? {
        guard data.count <= maximumSize, fetchedAt.timeIntervalSince1970.isFinite,
              let html = String(data: data, encoding: .utf8),
              let rawReset = capture(#"<[a-z][a-z0-9]*\b(?=[^>]*\sid\s*=\s*["']reset-since["'])[^>]*\sdata-reset-at\s*=\s*["']([^"']+)["'][^>]*>"#, in: html),
              let last = date(rawReset), last <= fetchedAt, last.timeIntervalSince1970 > 0,
              let rawMedian = capture(#"<p\b(?=[^>]*\sid\s*=\s*["']live-home-rhythm-trend["'])[^>]*>\s*All-time median gap:\s*([0-9]+(?:\.[0-9]+)?)\s*days\b[^<]*</p\s*>"#, in: html),
              let days = Double(rawMedian), days.isFinite, days > 0, days <= 90 else { return nil }
        let estimate = last.addingTimeInterval(days * 86_400)
        guard estimate > fetchedAt else { return nil }
        return Self(estimatedReset: estimate, lastReset: last, medianDays: days,
                    fetchedAt: fetchedAt, expiresAt: min(estimate, fetchedAt.addingTimeInterval(86_400)))
    }

    /// A missing or ambiguous page field hides the scenario rather than
    /// silently substituting a recent median, banked credit or another feed.
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let match = matches.first,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    func plan(provider: AgentProvider, sample: AgentWeeklyUsage.Sample, now: Date) -> AgentWeeklyPlan? {
        guard provider == .codex, now >= fetchedAt, now < expiresAt,
              let actual = sample.resetsAt, estimatedReset < actual else { return nil }
        return AgentWeeklyPlan(sample: sample, now: now, speculativeReset: estimatedReset)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: text) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
