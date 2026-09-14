// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchFilesView: View {
    let service: NotchService
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var shareAnchor = ShelfSharePickerAnchor.Anchor()
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var archives = NotchFileToolsService.shared
    @ObservedObject private var media = NotchFileToolsService.shared.media
    @State private var actionInputs: [URL] = []
    @State private var supportedTools: [MediaTool] = []
    @State private var showingActions = false
    @State private var outputPanel: NSSavePanel?
    private var text: NotchFilesStrings { FeatureStrings.notchFiles(l10n.language) }

    var body: some View {
        VStack(spacing: 12) {
            if let session = archives.mediaSession, AppFeature.mediaTools.isAvailable {
                MediaWorkspaceView(compact: true, onClose: archives.closeMedia,
                                   media: media, initialInputs: session.inputs,
                                   initialTool: session.tool, preservesServiceState: true,
                                   workspace: archives.mediaSelection)
                    .id(session.id)
            } else if shelf.items.isEmpty {
                NotchEmptyView(symbol: "tray.and.arrow.down", message: FeatureStrings.notch(l10n.language).dropHint)
                    .frame(maxHeight: .infinity)
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.75, dash: [4, 5])) }
            } else {
                ShelfTilesView(items: shelf.visibleItems,
                               contentRevision: shelf.contentRevision,
                               selection: shelf.selection,
                               expandedBatches: shelf.expandedBatches,
                               revealID: shelf.revealTargetID,
                               revealSerial: shelf.addSerial)
                    .frame(maxHeight: .infinity)
                HStack {
                    Text(l10n.s.shelfHint).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if AppFeature.mediaTools.isAvailable {
                        NotchIconButton(symbol: "wand.and.stars", title: l10n.s.mediaName) {
                            service.pinned = true
                            actionInputs = shelf.fileURLsForActions()
                            supportedTools = MediaTool.allCases.filter { NotchFileToolsSupport.accepts(actionInputs, for: $0) }
                            showingActions = !actionInputs.isEmpty
                        }
                        .disabled(!shelf.hasFilesForActions || archives.isRunning)
                        .popover(isPresented: $showingActions) { fileActions.padding(14).frame(width: 270) }
                    }
                    NotchIconButton(symbol: "square.and.arrow.up", title: l10n.s.shelfActionShare) {
                        service.pinned = true
                        shareAnchor.present(shelf.fileURLsForActions())
                    }
                    .background(ShelfSharePickerAnchor(anchor: shareAnchor))
                    .disabled(!shelf.hasFilesForActions)
                    clearMenu
                }
            }
            if archives.mediaSession == nil, AppFeature.mediaTools.isAvailable { archiveStatus }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: archives.mediaSession?.id) {
            service.objectWillChange.send()
            service.refreshPresentation()
        }
        .onDisappear {
            outputPanel?.cancel(nil)
            outputPanel = nil
        }
        .onChange(of: features.revision) {
            if !AppFeature.mediaTools.isAvailable {
                archives.syncWithPreferences()
                showingActions = false
                outputPanel?.cancel(nil)
            }
        }
    }

    // A sheet dims the window's transparent margins. A native menu keeps the
    // explicit confirmation beside its trigger and uses the existing menu tracking.
    private var clearMenu: some View {
        Menu {
            Button(l10n.s.shelfClearAll, role: .destructive) { shelf.clear() }
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(archives.isRunning)
        .help(l10n.s.shelfClearAll)
        .accessibilityLabel(l10n.s.shelfClearAll)
    }

    private var fileActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showingActions = false; chooseArchiveDestination() } label: {
                Label(text.archive, systemImage: "doc.zipper")
            }
            Text(text.archiveHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !supportedTools.isEmpty {
                Divider()
                ForEach(supportedTools) { tool in
                    Button {
                        showingActions = false
                        archives.openMedia(tool, inputs: actionInputs)
                        service.pinned = true
                    } label: { Text(toolTitle(tool)) }
                }
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var archiveStatus: some View {
        if archives.isRunning {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("\(text.archive) · \(archives.completed)/\(archives.total)")
                    .font(.caption).monospacedDigit()
                Spacer()
                Button(l10n.s.uninstallerCancel, action: archives.cancel)
                    .controlSize(.small).disabled(archives.wasCancelled)
            }
        } else if let failure = archives.failure {
            Text(failure).font(.caption).foregroundStyle(.orange).lineLimit(3)
        } else if !archives.outputURLs.isEmpty {
            HStack {
                Label(text.saved, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button(l10n.s.mediaOpenInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting(archives.outputURLs)
                }
            }.font(.caption).controlSize(.small)
        } else if archives.wasCancelled {
            Text(l10n.s.mediaCancelled).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toolTitle(_ tool: MediaTool) -> String {
        switch tool {
        case .videoCompressor: return l10n.s.mediaToolVideo
        case .gifMaker: return l10n.s.mediaToolGIF
        case .imageCompressor: return l10n.s.mediaToolImage
        case .textExtractor: return l10n.s.mediaToolText
        }
    }

    private func chooseArchiveDestination() {
        guard outputPanel == nil, !actionInputs.isEmpty, AppFeature.mediaTools.isAvailable else { return }
        let inputs = actionInputs
        let multiple = inputs.count > 1
        let panel: NSSavePanel
        if multiple {
            let folder = NSOpenPanel()
            folder.canChooseFiles = false
            folder.canChooseDirectories = true
            folder.allowsMultipleSelection = false
            panel = folder
        } else {
            panel = NSSavePanel()
            panel.allowedContentTypes = [.zip]
            panel.nameFieldStringValue = MediaSupport.uniqueOutputURL(
                in: inputs[0].deletingLastPathComponent(), baseName: inputs[0].lastPathComponent,
                fileExtension: "zip").lastPathComponent
        }
        panel.directoryURL = inputs[0].deletingLastPathComponent()
        panel.message = text.archiveHint
        outputPanel = panel
        service.pinned = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            outputPanel = nil
            guard response == .OK, let destination = panel.url,
                  AppFeature.mediaTools.isAvailable, AppFeature.shelf.isAvailable,
                  NotchSupport.isEnabled() else { return }
            archives.archive(inputs, destination: destination, directory: multiple)
            service.open(.files, pinned: true)
        }
    }

}
