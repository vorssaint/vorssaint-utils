// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Cleaner's large files tab: pick a size (and optionally an age), scan the
/// home folder, tick what to remove and send it to the Trash. Nothing starts
/// ticked.
struct LargeFilesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var finder = LargeFileFinder.shared
    @State private var minimumSize = LargeFileSupport.minimumSizes[1]
    @State private var olderThanDays = 0

    var body: some View {
        Group {
            switch finder.phase {
            case .idle: setup
            case .scanning: busy(l10n.s.uninstallerScanning, cancellable: true)
            case .results: results
            case .removing: busy(l10n.s.uninstallerRemoving, cancellable: false)
            case let .done(freed, failed): done(freed: freed, failed: failed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear { if finder.phase == .scanning { finder.reset() } }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.s.largeFilesIntro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(l10n.s.largeFilesMinSize)
                Picker("", selection: $minimumSize) {
                    ForEach(LargeFileSupport.minimumSizes, id: \.self) { size in
                        Text(Self.byteString(size)).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            HStack(spacing: 10) {
                Text(l10n.s.largeFilesOlderThan)
                Picker("", selection: $olderThanDays) {
                    ForEach(LargeFileSupport.ageFilterDays, id: \.self) { days in
                        Text(ageLabel(days)).tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            Button(l10n.s.largeFilesScan) {
                finder.scan(minimumSize: minimumSize, olderThanDays: olderThanDays)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func busy(_ message: String, cancellable: Bool) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message).foregroundStyle(.secondary)
            if cancellable {
                Button(l10n.s.uninstallerCancel) { finder.reset() }
            }
        }
        .padding(40)
    }

    private var results: some View {
        VStack(spacing: 0) {
            if finder.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(l10n.s.largeFilesNone).foregroundStyle(.secondary)
                    Button(l10n.s.uninstallerCancel) { finder.reset() }
                }
                .padding(40)
            } else {
                List(finder.items) { item in row(item) }
                    .listStyle(.inset)
                Divider()
                footer
            }
        }
    }

    private func row(_ item: LargeFileFinder.Item) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { finder.items.first(where: { $0.id == item.id })?.include ?? false },
                set: { finder.setInclude($0, for: item.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Label(safetyText(item.details.safety), systemImage: safetyIcon(item.details.safety))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(safetyColor(item.details.safety))
                    .lineLimit(1)
                Text(summaryLine(item))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Text(locationLine(item))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help(l10n.s.cleanerRevealInFinder)
            .accessibilityLabel(l10n.s.cleanerRevealInFinder)
            Text(Self.byteString(item.size))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
        .help(detailsHelp(item))
    }

    private var footer: some View {
        let allSelected = finder.items.allSatisfy(\.include)
        let info = VStack(alignment: .leading, spacing: 1) {
            Text(String(format: l10n.s.uninstallerSelectedFormat,
                        finder.items.filter(\.include).count, finder.items.count))
                .font(.system(size: 12, weight: .medium))
            Text(Self.byteString(finder.selectedSize))
                .font(.caption).foregroundStyle(.secondary)
        }
        let buttons = HStack {
            Button(allSelected ? l10n.s.uninstallerSelectNone : l10n.s.uninstallerSelectAll) {
                finder.selectAll(!allSelected)
            }
            Button(l10n.s.uninstallerCancel) { finder.reset() }
            Button(l10n.s.largeFilesMoveToTrash) { finder.trashSelected() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(finder.selectedSize == 0)
        }
        // In a narrow panel the buttons drop under the counts.
        return ViewThatFits(in: .horizontal) {
            HStack { info; Spacer(); buttons }
            VStack(alignment: .leading, spacing: 8) { info; HStack { Spacer(); buttons } }
        }
        .padding(12)
    }

    private func done(freed: Int64, failed: Int) -> some View {
        VStack(spacing: 10) {
            Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(failed == 0 ? .green : .orange)
            Text(l10n.s.uninstallerDoneTitle).font(.title3.bold())
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.byteString(freed)))
                .foregroundStyle(.secondary)
            Button(l10n.s.uninstallerAnother) { finder.reset() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    private func ageLabel(_ days: Int) -> String {
        switch days {
        case 0: return l10n.s.largeFilesAnyAge
        case 365: return l10n.s.largeFilesOneYear
        default: return String(format: l10n.s.largeFilesDaysFormat, days)
        }
    }

    private func lastOpenedText(_ item: LargeFileFinder.Item, time: Date.FormatStyle.TimeStyle) -> String {
        guard let date = item.lastOpened else { return l10n.s.uninstallerNeverUsed }
        return String(format: l10n.s.uninstallerLastUsedFormat,
                      date.formatted(date: .abbreviated, time: time))
    }

    private func safetyText(_ safety: LargeFileSupport.Safety) -> String {
        switch safety {
        case .replaceable: return l10n.s.largeFilesSafeReplaceable
        case .yours: return l10n.s.largeFilesSafeYours
        case .check: return l10n.s.largeFilesSafeCheck
        }
    }

    private func safetyIcon(_ safety: LargeFileSupport.Safety) -> String {
        switch safety {
        case .replaceable: return "arrow.down.circle"
        case .yours: return "person.crop.circle"
        case .check: return "exclamationmark.circle"
        }
    }

    private func safetyColor(_ safety: LargeFileSupport.Safety) -> Color {
        switch safety {
        case .replaceable: return .green
        case .yours: return .blue
        case .check: return .orange
        }
    }

    /// Kind, the app that opens it and when it was last used, in one line.
    private func summaryLine(_ item: LargeFileFinder.Item) -> String {
        var parts: [String] = []
        if let kind = item.details.kind { parts.append(kind) }
        if let app = item.details.opensWith { parts.append(String(format: l10n.s.largeFilesOpensWithFormat, app)) }
        parts.append(lastOpenedText(item, time: .omitted))
        return parts.joined(separator: " · ")
    }

    /// The folder it sits in and, for downloads, the website it came from.
    private func locationLine(_ item: LargeFileFinder.Item) -> String {
        var parts = [prettyFolder(item.url)]
        if let host = item.details.downloadedFrom {
            parts.append(String(format: l10n.s.largeFilesDownloadedFromFormat, host))
        }
        return parts.joined(separator: " · ")
    }

    /// Everything known about the file, shown when hovering over its row.
    private func detailsHelp(_ item: LargeFileFinder.Item) -> String {
        var lines = [item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                     safetyText(item.details.safety), summaryLine(item), lastOpenedText(item, time: .shortened)]
        if let host = item.details.downloadedFrom {
            lines.append(String(format: l10n.s.largeFilesDownloadedFromFormat, host))
        }
        if let added = item.details.added {
            lines.append(String(format: l10n.s.largeFilesAddedFormat,
                                added.formatted(date: .abbreviated, time: .omitted)))
        }
        return lines.joined(separator: "\n")
    }

    private func prettyFolder(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
