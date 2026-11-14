// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A small hand-drawn chart for the next 24 hours, with one metric at a time.
/// `Path` keeps the panel free of Swift Charts, which the Command Line Tools
/// cannot build because of its macro plugin.
struct WeatherGraphView: View {
    let hours: [WeatherHour]
    let preferences: WeatherUnitPreferences
    let timeZoneIdentifier: String
    let locale: Locale
    let temperatureTitle: String
    let precipitationTitle: String
    let windTitle: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var metric: Metric = .temperature

    private enum Metric: CaseIterable {
        case temperature, precipitation, wind
    }

    var body: some View {
        let chartValues = values
        return VStack(alignment: .leading, spacing: 5) {
            selector
            WeatherGraphChart(values: chartValues,
                              color: color,
                              minimumLabel: label(chartValues.min() ?? 0),
                              maximumLabel: label(chartValues.max() ?? 0))
                .frame(height: 62)
            HStack {
                Text(hourLabel(hours.first?.time))
                Spacer()
                Text(hourLabel(hours.last?.time))
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.tertiary)
        }
    }

    private var selector: some View {
        HStack(spacing: 2) {
            ForEach(Metric.allCases, id: \.self) { option in
                Button {
                    metric = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .foregroundStyle(metric == option ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(metric == option ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(metric == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }

    private var values: [Double] {
        switch metric {
        case .temperature:
            return hours.map { preferences.temperatureValue($0.temperature) }
        case .precipitation:
            return hours.map { preferences.precipitationValue($0.precipitation) }
        case .wind:
            return hours.map { preferences.windValue($0.windSpeed) }
        }
    }

    private var color: Color {
        switch metric {
        case .temperature: return PanelMetricColor.orange(for: colorScheme)
        case .precipitation: return PanelMetricColor.cyan(for: colorScheme)
        case .wind: return PanelMetricColor.green(for: colorScheme)
        }
    }

    private func title(_ metric: Metric) -> String {
        switch metric {
        case .temperature: return temperatureTitle
        case .precipitation: return precipitationTitle
        case .wind: return windTitle
        }
    }

    private func label(_ value: Double) -> String {
        switch metric {
        case .temperature:
            return "\(number(value, digits: 0))°"
        case .precipitation:
            return "\(number(value, digits: preferences.precipitation == .inches ? 2 : 1)) \(preferences.precipitationSymbol)"
        case .wind:
            return "\(number(value, digits: preferences.wind == .metersPerSecond ? 1 : 0)) \(preferences.windSymbol)"
        }
    }

    private func hourLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    private func number(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: MetricFormat.locale, value)
    }
}

/// Area line with a zero baseline, a faint mid rule and the range named at the
/// top and bottom, so a value never reads without its scale.
struct WeatherGraphChart: View {
    let values: [Double]
    let color: Color
    let minimumLabel: String
    let maximumLabel: String

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                horizontalRule(at: proxy.size.height / 2, size: proxy.size, dashed: true)
                horizontalRule(at: proxy.size.height - 0.5, size: proxy.size, dashed: false)
                if points.count >= 2 {
                    areaPath(points, height: proxy.size.height)
                        .fill(
                            LinearGradient(colors: [color.opacity(0.22), color.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
            .overlay(alignment: .topLeading) { axisLabel(maximumLabel) }
            .overlay(alignment: .bottomLeading) { axisLabel(minimumLabel) }
        }
    }

    private func horizontalRule(at y: CGFloat, size: CGSize, dashed: Bool) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(Color.secondary.opacity(dashed ? 0.16 : 0.3),
                style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 3] : []))
    }

    private func areaPath(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            let baseline = height - 0.5
            path.move(to: CGPoint(x: points[0].x, y: baseline))
            points.forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baseline))
            path.closeSubpath()
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lower = values.min() ?? 0
        let upper = values.max() ?? 0
        let span = max(upper - lower, 0.1)
        let top: CGFloat = 4
        let bottom = max(top + 1, size.height - 4)
        let plot = bottom - top
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let fraction = min(max((value - lower) / span, 0), 1)
            return CGPoint(x: x, y: bottom - plot * CGFloat(fraction))
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
            .allowsHitTesting(false)
    }
}
