// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ArchiveToolsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var archive = ArchiveService.shared
    @AppStorage(DefaultsKey.archiveExcludeDSStore) private var excludesDSStore = false
    @State private var sources: [URL] = []
    @State private var destination: URL?
    @State private var dropTargeted = false

    private var text: ArchiveToolsStrings { FeatureStrings.archiveTools(l10n.language) }
    private var isRunning: Bool { archive.state == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(text.title, systemImage: "archivebox")
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inputCard
                    destinationCard
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(text.excludeDSStore, isOn: $excludesDSStore)
                        Text(text.excludeDSStoreCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .panelCard()
                    actionRow
                    statusCard
                }
                .padding(.trailing, 1)
            }
        }
        .padding(16)
    }

    private var inputCard: some View {
        Button(action: chooseSources) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(inputTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(text.createCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .panelCard()
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(dropTargeted ? Color.accentColor : .clear,
                              lineWidth: dropTargeted ? 1.5 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isRunning else { return false }
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return false }
            setSources(existing)
            return true
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    private var destinationCard: some View {
        Button(action: chooseDestination) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.s.mediaOutput)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(destination?.path ?? l10n.s.mediaChooseOutput)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .panelCard()
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: run) {
                Label(text.startCreate, systemImage: "archivebox.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(sources.isEmpty || destination == nil || isRunning)
            if isRunning {
                Button(action: archive.cancel) {
                    Label(l10n.s.mediaCancel, systemImage: "xmark")
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch archive.state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(l10n.s.mediaRunning).font(.system(size: 11.5, weight: .semibold))
            }
            .panelCard()
        case let .completed(outputURL):
            VStack(alignment: .leading, spacing: 7) {
                Label(l10n.s.mediaCompleted, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.green)
                Text(String(format: text.completedFormat, outputURL.lastPathComponent))
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button(l10n.s.mediaOpenInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
                .controlSize(.small)
            }
            .panelCard()
        case let .failed(failure):
            Label(failureMessage(failure), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .panelCard()
        case .cancelled:
            Label(l10n.s.mediaCancelled, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .panelCard()
        }
    }

    private var inputTitle: String {
        if sources.isEmpty { return text.chooseSources }
        if sources.count == 1 { return sources[0].lastPathComponent }
        return String(format: text.selectedItemsFormat, sources.count)
    }

    private func chooseSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        setSources(panel.urls)
    }

    private func setSources(_ urls: [URL]) {
        sources = urls
        if destination == nil { destination = urls.first?.deletingLastPathComponent() }
        archive.reset()
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        destination = panel.url
        archive.reset()
    }

    private func run() {
        guard let destination else { return }
        archive.create(sources: sources,
                       destinationDirectory: destination,
                       excludesDSStore: excludesDSStore)
    }

    private func failureMessage(_ failure: ArchiveFailure) -> String {
        switch failure {
        case .noInput: return text.noSelection
        case .sourceUnavailable: return text.sourceUnavailable
        case let .duplicateSourceName(name):
            return String(format: text.duplicateSourceFormat, name)
        case let .commandFailed(message): return message
        case .cannotPrepare: return text.cannotPrepare
        case .cannotPublish: return text.cannotPublish
        case .cancelled: return l10n.s.mediaCancelled
        }
    }
}
