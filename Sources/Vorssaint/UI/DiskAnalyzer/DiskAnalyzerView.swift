// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Disk Analyzer window: pick a disk, watch the scan, then explore the
/// map and the list side by side.
struct DiskAnalyzerView: View {
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        ZStack {
            switch service.phase {
            case .idle:
                DiskAnalyzerStartView(layout: .window)
                    .transition(.opacity)
            case .scanning:
                DiskAnalyzerScanningView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .results:
                DiskAnalyzerResultsView()
                    .transition(.opacity)
            case .failed:
                failedState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .animation(.easeInOut(duration: 0.25), value: service.phase)
    }

    private var failedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(strings.scanFailed)
                .font(.headline)
            Button(strings.newScan) { service.reset() }
                .controlSize(.large)
        }
    }
}

// MARK: - Start

/// The volume picker, shared by the window and its Settings page.
struct DiskAnalyzerStartView: View {
    enum Layout {
        case window
        case settings
    }

    let layout: Layout
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var volumes: [DiskAnalyzerService.Target] = []

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(volumes) { volume in
                        DiskAnalyzerVolumeCard(target: volume) { start(volume) }
                    }
                    DiskAnalyzerFolderCard(symbol: "house",
                                           title: strings.homeFolder,
                                           detail: DiskAnalyzerService.shared.homeTarget().name) {
                        start(DiskAnalyzerService.shared.homeTarget())
                    }
                    DiskAnalyzerFolderCard(symbol: "folder.badge.plus",
                                           title: strings.chooseFolder,
                                           detail: strings.chooseFolderHint) { chooseFolder() }
                }
                if !permissions.fullDiskAccess {
                    FullDiskAccessNote(reason: strings.fullDiskAccessReason)
                }
            }
            .padding(.horizontal, layout == .window ? 40 : 24)
            .padding(.top, layout == .window ? 44 : 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .onAppear { volumes = DiskAnalyzerService.shared.volumes() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .blue],
                                          center: .center))
                    .frame(width: 46, height: 46)
                Circle()
                    .fill(.background)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(strings.title)
                    .font(.system(size: layout == .window ? 24 : 19, weight: .bold))
                Text(strings.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func start(_ target: DiskAnalyzerService.Target) {
        if layout == .settings {
            DiskAnalyzerWindowController.shared.show(scanning: target.path)
        } else {
            DiskAnalyzerService.shared.scan(target)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = strings.scan
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(DiskAnalyzerService.shared.folderTarget(url))
    }
}

private struct DiskAnalyzerVolumeCard: View {
    let target: DiskAnalyzerService.Target
    let action: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var hovering = false

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }
    private var fraction: Double {
        target.capacity > 0 ? Double(target.used) / Double(target.capacity) : 0
    }
    private var gaugeColor: Color {
        fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(gaugeColor.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: target.kind == .startupDisk ? "internaldrive.fill" : "externaldrive.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if target.kind == .startupDisk {
                        Text(strings.startupDisk)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: strings.usedOfFormat, DiskAnalyzerFormat.bytes(target.used), DiskAnalyzerFormat.bytes(target.capacity)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: strings.availableFormat, DiskAnalyzerFormat.bytes(target.available)))
                        .font(.caption)
                        .foregroundStyle(gaugeColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(hovering ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .frame(minHeight: 84)
            .padding(14)
            .background(cardBackground(hovering: hovering))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(strings.scan)
    }
}

private struct DiskAnalyzerFolderCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.accentColor.opacity(0.1)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 84)
            .padding(14)
            .background(cardBackground(hovering: hovering))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private func cardBackground(hovering: Bool) -> some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.primary.opacity(hovering ? 0.075 : 0.045))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.07), lineWidth: 0.8))
        .animation(.easeOut(duration: 0.12), value: hovering)
}

enum DiskAnalyzerFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }
}

// MARK: - Scanning

private struct DiskAnalyzerScanningView: View {
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var l10n = L10n.shared

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }
    /// Volumes report how much is used, so their scan has a real progress.
    private var fraction: Double? {
        guard let target = service.target, target.isVolume, target.used > 0 else { return nil }
        return min(0.99, Double(service.progress.bytes) / Double(target.used))
    }

    var body: some View {
        VStack(spacing: 26) {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<4, id: \.self) { ring in
                        let width = 30.0 - Double(ring) * 5
                        Circle()
                            .trim(from: 0, to: 0.18 + 0.12 * Double(ring))
                            .stroke(AngularGradient(colors: [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .blue],
                                                    center: .center),
                                    style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .frame(width: 120 + Double(ring) * 70, height: 120 + Double(ring) * 70)
                            .rotationEffect(.degrees(time * (50 + Double(ring) * 22) * (ring.isMultiple(of: 2) ? 1 : -1)))
                            .opacity(0.85 - Double(ring) * 0.15)
                    }
                    VStack(spacing: 4) {
                        Text(DiskAnalyzerFormat.bytes(service.progress.bytes))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(String(format: strings.filesFormat, DiskAnalyzerFormat.count(service.progress.files)))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 340, height: 340)
            }
            VStack(spacing: 10) {
                Text(service.target?.name ?? strings.scanning)
                    .font(.title3.weight(.semibold))
                if let fraction {
                    ProgressView(value: fraction)
                        .frame(width: 320)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 320)
                }
                Text(service.progress.currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
            }
            Button(strings.cancel) { service.cancel() }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// File icons for list rows, looked up once per path.
final class DiskAnalyzerIconCache {
    static let shared = DiskAnalyzerIconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for node: DiskNode) -> NSImage {
        let path = node.path
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

// MARK: - Settings

/// The Settings page: what the tool does and the same picker as the window,
/// which opens the window to show the scan.
struct DiskAnalyzerSettings: View {
    var body: some View {
        DiskAnalyzerStartView(layout: .settings)
    }
}
