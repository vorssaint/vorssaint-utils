// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import WidgetKit

struct VorssaintEntry: TimelineEntry {
    enum Content {
        case snapshot(WidgetSnapshot)
    }

    let date: Date
    let content: Content
}

struct VorssaintProvider: TimelineProvider {
    let kind: VorssaintWidgetKind

    func placeholder(in context: Context) -> VorssaintEntry {
        VorssaintEntry(date: Date(), content: .snapshot(.preview))
    }

    func getSnapshot(in context: Context, completion: @escaping (VorssaintEntry) -> Void) {
        if !context.isPreview {
            // WidgetKit asks for a snapshot as soon as a widget is added. The
            // heartbeat wakes the app and turns that into an immediate publish.
            WidgetSharedData.recordRequest(kind)
        }
        let content = context.isPreview ? VorssaintEntry.Content.snapshot(.preview) : currentContent()
        completion(VorssaintEntry(date: Date(), content: content))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VorssaintEntry>) -> Void) {
        WidgetSharedData.recordRequest(kind)
        let entry = VorssaintEntry(date: Date().addingTimeInterval(5), content: currentContent())
        completion(Timeline(entries: [entry], policy: .atEnd))
    }

    /// A widget that has no reading yet renders its normal layout with empty
    /// gauges and zero values, so it never shows a blank card or a message.
    private func currentContent() -> VorssaintEntry.Content {
        .snapshot(WidgetSharedData.loadSnapshot() ?? .placeholder)
    }
}

struct VorssaintWidgetView: View {
    let kind: VorssaintWidgetKind
    let entry: VorssaintEntry

    private var strings: Strings {
        Strings.localized(WidgetSharedData.language())
    }

    var body: some View {
        Group {
            switch entry.content {
            case let .snapshot(snapshot):
                snapshotView(snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private func snapshotView(_ snapshot: WidgetSnapshot) -> some View {
        switch kind {
        case .cpu:
            CPUWidgetView(reading: snapshot.cpu ?? .empty, strings: strings)
        case .gpu:
            GPUWidgetView(reading: snapshot.gpu ?? .empty, strings: strings)
        case .memory:
            MemoryWidgetView(reading: snapshot.memory ?? .empty, strings: strings)
        case .disk:
            DiskWidgetView(reading: snapshot.disk ?? .empty, strings: strings)
        case .network:
            NetworkWidgetView(reading: snapshot.network ?? .empty, strings: strings)
        case .united:
            UnitedWidgetView(snapshot: snapshot, strings: strings)
        }
    }
}

// MARK: - Per-module widgets

private struct CPUWidgetView: View {
    let reading: WidgetCPUReading
    let strings: Strings

    private let systemColor = Color(nsColor: .systemRed)
    private let userColor = Color(nsColor: .systemBlue)
    private let idleColor = Color(nsColor: .systemGray)

    var body: some View {
        VStack(spacing: 10) {
            WidgetDonut(segments: [
                .init(value: reading.system, color: systemColor),
                .init(value: reading.user, color: userColor),
                .init(value: reading.idle, color: idleColor)
            ], centerValue: WidgetFormat.percent(reading.total), centerLabel: strings.cpuLabel,
               height: 84)
            VStack(spacing: 3) {
                WidgetRow(color: systemColor, title: strings.widgetSystem,
                          value: WidgetFormat.percent(reading.system))
                WidgetRow(color: userColor, title: strings.widgetUser,
                          value: WidgetFormat.percent(reading.user))
            }
        }
    }
}

private struct GPUWidgetView: View {
    let reading: WidgetGPUReading
    let strings: Strings

    private let usedColor = Color(nsColor: .systemBlue)
    private let freeColor = Color(nsColor: .systemGray)

    var body: some View {
        VStack(spacing: 10) {
            WidgetDonut(segments: [
                .init(value: reading.usage, color: usedColor),
                .init(value: 1 - reading.usage, color: freeColor)
            ], centerValue: WidgetFormat.percent(reading.usage), centerLabel: strings.gpuLabel,
               height: 84)
            VStack(spacing: 3) {
                WidgetRow(color: nil, title: strings.widgetUsage,
                          value: WidgetFormat.percent(reading.usage))
                WidgetRow(color: nil, title: strings.widgetRenderer,
                          value: reading.renderer.map(WidgetFormat.percent) ?? "—")
                WidgetRow(color: nil, title: strings.widgetTiler,
                          value: reading.tiler.map(WidgetFormat.percent) ?? "—")
            }
        }
    }
}

private struct MemoryWidgetView: View {
    let reading: WidgetMemoryReading
    let strings: Strings

    private let usedColor = Color(nsColor: .systemBlue)
    private let freeColor = Color(nsColor: .systemGray)

    var body: some View {
        VStack(spacing: 10) {
            WidgetDonut(segments: [
                .init(value: reading.usedFraction, color: usedColor),
                .init(value: 1 - reading.usedFraction, color: freeColor)
            ], centerValue: WidgetFormat.percent(reading.usedFraction), centerLabel: strings.widgetMemoryLabel,
               height: 84)
            VStack(spacing: 3) {
                WidgetRow(color: usedColor, title: strings.widgetUsed,
                          value: WidgetFormat.bytes(reading.used))
                WidgetRow(color: freeColor, title: strings.widgetFree,
                          value: WidgetFormat.bytes(reading.free))
                WidgetRow(color: nil, title: strings.widgetPressureLevel,
                          value: "\(reading.pressureLevel)")
            }
        }
    }
}

private struct DiskWidgetView: View {
    let reading: WidgetDiskReading
    let strings: Strings

    private let usedColor = Color(nsColor: .systemBlue)
    private let freeColor = Color(nsColor: .systemGray)

    var body: some View {
        VStack(spacing: 10) {
            WidgetDonut(segments: [
                .init(value: reading.usedFraction, color: usedColor),
                .init(value: 1 - reading.usedFraction, color: freeColor)
            ], centerValue: WidgetFormat.percent(reading.usedFraction), centerLabel: strings.widgetDiskLabel,
               height: 84)
            VStack(spacing: 3) {
                WidgetRow(color: usedColor, title: strings.widgetUsed,
                          value: WidgetFormat.bytes(reading.used))
                WidgetRow(color: freeColor, title: strings.widgetFree,
                          value: WidgetFormat.bytes(reading.free))
            }
        }
    }
}

private struct NetworkWidgetView: View {
    let reading: WidgetNetworkReading
    let strings: Strings

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                speedColumn(title: strings.widgetDownload, value: reading.downText)
                speedColumn(title: strings.widgetUpload, value: reading.upText)
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 3) {
                WidgetRow(color: nil, title: strings.widgetStatus,
                          value: reading.isConnected ? strings.widgetUp : strings.widgetDown)
                if let interface = reading.interfaceName {
                    WidgetRow(color: nil, title: strings.widgetInterface, value: interface)
                }
                if let address = reading.localAddress {
                    WidgetRow(color: nil, title: strings.widgetIP, value: address)
                }
            }
        }
    }

    private func speedColumn(title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .regular))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UnitedWidgetView: View {
    let snapshot: WidgetSnapshot
    let strings: Strings

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private struct Value {
        let title: String
        let fraction: Double
    }

    /// All four gauges stay in place from the first render; a reading that has
    /// not arrived yet simply shows an empty ring instead of leaving a hole.
    private var values: [Value] {
        [
            Value(title: strings.cpuLabel, fraction: snapshot.cpu?.total ?? 0),
            Value(title: strings.gpuLabel, fraction: snapshot.gpu?.usage ?? 0),
            Value(title: strings.widgetMemoryLabel, fraction: snapshot.memory?.usedFraction ?? 0),
            Value(title: strings.widgetDiskLabel, fraction: snapshot.disk?.usedFraction ?? 0)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                UnitedGauge(title: value.title, fraction: value.fraction)
            }
        }
    }
}

// MARK: - Shared pieces

private struct WidgetRow: View {
    let color: Color?
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
            }
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct DonutSegment {
    let value: Double
    let color: Color
}

private struct WidgetDonut: View {
    let segments: [DonutSegment]
    let centerValue: String
    let centerLabel: String
    let height: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.18), lineWidth: 9)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: start(at: index), to: end(at: index))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(centerValue)
                    .font(.system(size: 16, weight: .regular))
                Text(centerLabel)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .frame(width: height, height: height)
        .frame(maxWidth: .infinity, maxHeight: height)
    }

    private var total: Double {
        max(0.0001, segments.reduce(0) { $0 + max(0, $1.value) })
    }

    private func start(at index: Int) -> Double {
        segments.prefix(index).reduce(0) { $0 + max(0, $1.value) } / total
    }

    private func end(at index: Int) -> Double {
        start(at: index) + max(0, segments[index].value) / total
    }
}

private struct UnitedGauge: View {
    let title: String
    let fraction: Double

    private var progress: Double {
        min(1, max(0, fraction))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(nsColor: .controlAccentColor),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 10))
                Text(WidgetFormat.percent(progress))
                    .font(.system(size: 12))
            }
        }
        .frame(width: 60, height: 60)
    }
}
