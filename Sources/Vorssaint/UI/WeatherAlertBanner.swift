// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One active US weather alert, shown under a weather hero in the panel and
/// the island so both read the same words.
struct WeatherAlertBanner: View {
    let alert: WeatherAlert
    let strings: WeatherStrings
    let locale: Locale
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(alert.severity.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.event)
                    .font(.system(size: compact ? 10 : 10.5, weight: .semibold))
                    .lineLimit(1)
                Text(alert.headline)
                    .font(.system(size: compact ? 9 : 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let expiry = alert.expires ?? alert.ends {
                    Text(expiryLine(expiry))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = alert.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: compact ? 10 : 11))
                }
                .foregroundStyle(.secondary)
                .help(strings.alertsTitle)
                .accessibilityLabel(strings.alertsTitle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(alert.severity.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func expiryLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return String(format: strings.alertsExpiresFormat, formatter.string(from: date))
    }
}

extension WeatherAlertSeverity {
    /// Colour of the warning mark; the rest of the banner stays neutral.
    var tint: Color {
        switch self {
        case .extreme: return .red
        case .severe: return .orange
        case .moderate: return .yellow
        case .minor: return .blue
        case .unknown: return .secondary
        }
    }
}
