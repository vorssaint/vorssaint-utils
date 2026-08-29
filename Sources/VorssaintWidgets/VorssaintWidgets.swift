// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import WidgetKit

/// The desktop widgets.
///
/// This process is sandboxed and cannot read a single sensor, so it does no
/// sampling of its own: every value comes from the snapshot Vorssaint writes
/// (`WidgetSnapshotStore`). When the app is not running the file goes stale and
/// the widgets say so rather than presenting frozen numbers as current.

struct MetricsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// Vorssaint has not written in a while: it is closed, or its monitor
    /// stopped. Either way the numbers on screen are history.
    var isStale: Bool {
        guard let snapshot else { return true }
        return Date().timeIntervalSince(snapshot.capturedAt) > WidgetSnapshotStore.staleAfter
    }
}

struct MetricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MetricsEntry {
        MetricsEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricsEntry) -> Void) {
        // The widget gallery preview runs before the user has ever placed one,
        // so there may be no file yet; show plausible values rather than dashes.
        let snapshot = context.isPreview ? Self.sample : (WidgetSnapshotStore.read() ?? Self.sample)
        completion(MetricsEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricsEntry>) -> Void) {
        // Vorssaint samples only while a widget is placed, and the system tells
        // it nothing when one appears. Announcing every timeline request is how
        // a freshly dropped widget gets data without waiting for the app to
        // next ask: it starts the sampling that fills the very file being read.
        WidgetPresenceSignal.post()
        let now = Date()
        let snapshot = WidgetSnapshotStore.read()
        // Two entries, one reload. The second is timed to the moment the
        // current reading goes stale, so a widget left behind by a closed app
        // starts saying so on time instead of showing old numbers as current
        // until the next refresh comes round.
        var entries = [MetricsEntry(date: now, snapshot: snapshot)]
        if let capturedAt = snapshot?.capturedAt {
            let goesStaleAt = capturedAt.addingTimeInterval(WidgetSnapshotStore.staleAfter)
            // Only if it is still ahead of us: an entry dated in the past is
            // not a second entry, it is an out-of-order timeline.
            if goesStaleAt > now {
                entries.append(MetricsEntry(date: goesStaleAt, snapshot: snapshot))
            }
        }
        // The app pushes reloads as it samples; this is only the fallback for
        // when it is not running, and asking faster just burns the system's
        // refresh budget without producing fresher data.
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private static var sample: WidgetSnapshot {
        var snapshot = WidgetSnapshot(capturedAt: Date())
        snapshot.cpuUsage = 0.23
        snapshot.gpuUsage = 0.11
        snapshot.memoryUsed = 11_500_000_000
        snapshot.memoryTotal = 16_000_000_000
        snapshot.memoryPressure = "normal"
        snapshot.diskUsed = 340_000_000_000
        snapshot.diskTotal = 500_000_000_000
        return snapshot
    }
}

// MARK: - Shared pieces

enum WidgetFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    static func celsius(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    /// Decimal units, matching how macOS reports storage.
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useTB]
        return formatter.string(fromByteCount: Int64(value))
    }

    static func fraction(_ used: UInt64?, _ total: UInt64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }
}

/// One labelled bar. The bar is the reason to glance at a widget at all, so it
/// stays legible at small sizes: value on the right, no decorations.
struct MetricRow: View {
    let label: String
    let value: String
    let fraction: Double?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * (fraction ?? 0)))
                }
            }
            .frame(height: 4)
            .opacity(fraction == nil ? 0.35 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Shown instead of numbers when the snapshot is missing or stale.
struct StaleOverlay: View {
    var body: some View {
        Text("Abre Vorssaint")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - System metrics

struct MetricsWidgetView: View {
    var entry: MetricsEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sistema", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.isStale { StaleOverlay() }
            }
            MetricRow(label: "CPU",
                      value: WidgetFormat.percent(snapshot?.cpuUsage),
                      fraction: snapshot?.cpuUsage,
                      tint: .blue)
            MetricRow(label: "GPU",
                      value: WidgetFormat.percent(snapshot?.gpuUsage),
                      fraction: snapshot?.gpuUsage,
                      tint: .purple)
            MetricRow(label: "RAM",
                      value: WidgetFormat.bytes(snapshot?.memoryUsed),
                      fraction: WidgetFormat.fraction(snapshot?.memoryUsed, snapshot?.memoryTotal),
                      tint: memoryTint)
            MetricRow(label: "SSD",
                      value: WidgetFormat.bytes(snapshot?.diskUsed),
                      fraction: WidgetFormat.fraction(snapshot?.diskUsed, snapshot?.diskTotal),
                      tint: .teal)
        }
        .opacity(entry.isStale ? 0.5 : 1)
    }

    /// Memory pressure is the one reading where the colour carries information
    /// the bar cannot: a nearly full bar under normal pressure is fine.
    private var memoryTint: Color {
        switch entry.snapshot?.memoryPressure {
        case "critical": return .red
        case "warning": return .orange
        default: return .green
        }
    }
}

struct VorssaintMetricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VorssaintMetrics", provider: MetricsProvider()) { entry in
            MetricsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .padding(2)
        }
        .configurationDisplayName("Rendimiento")
        .description("CPU, GPU, memoria y disco de tu Mac.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct VorssaintWidgetBundle: WidgetBundle {
    var body: some Widget {
        VorssaintMetricsWidget()
    }
}
