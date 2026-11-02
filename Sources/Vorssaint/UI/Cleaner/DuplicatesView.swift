// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Cleaner's duplicates tab: scan the home folder for identical files and
/// move extra copies to the Trash. One copy of each file always stays.
struct DuplicatesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var finder = DuplicateFileFinder.shared
    @State private var minimumSize = DuplicateFileSupport.minimumSizes[1]

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
            Text(l10n.s.duplicatesIntro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(l10n.s.largeFilesMinSize)
                Picker("", selection: $minimumSize) {
                    ForEach(DuplicateFileSupport.minimumSizes, id: \.self) { size in
                        Text(Self.byteString(size)).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            Button(l10n.s.duplicatesScan) { finder.scan(minimumSize: minimumSize) }
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
            if finder.groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(l10n.s.duplicatesNone).foregroundStyle(.secondary)
                    Button(l10n.s.uninstallerCancel) { finder.reset() }
                }
                .padding(40)
            } else {
                List {
                    ForEach(finder.groups) { group in
                        Section {
                            ForEach(group.items) { item in row(item) }
                        } header: {
                            Text("\(Self.byteString(group.size))  ·  "
                                 + String(format: l10n.s.duplicatesCopiesFormat, group.items.count))
                        }
                    }
                }
                .listStyle(.inset)
                Divider()
                footer
            }
        }
    }

    private func row(_ item: DuplicateFileFinder.Item) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { currentlyIncluded(item) },
                set: { finder.setInclude($0, for: item.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text(prettyFolder(item.url))
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
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: l10n.s.uninstallerSelectedFormat,
                            finder.selectedCount, finder.groups.reduce(0) { $0 + $1.items.count }))
                    .font(.system(size: 12, weight: .medium))
                Text(Self.byteString(finder.selectedSize) + "  ·  " + l10n.s.duplicatesKeepNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(finder.selectedCount == 0 ? l10n.s.duplicatesSelectExtras : l10n.s.uninstallerSelectNone) {
                finder.selectExtras(finder.selectedCount == 0)
            }
            Button(l10n.s.uninstallerCancel) { finder.reset() }
            Button(l10n.s.largeFilesMoveToTrash) { finder.trashSelected() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(finder.selectedCount == 0)
        }
        .padding(16)
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

    private func currentlyIncluded(_ item: DuplicateFileFinder.Item) -> Bool {
        for group in finder.groups {
            if let found = group.items.first(where: { $0.id == item.id }) { return found.include }
        }
        return false
    }

    private func prettyFolder(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
