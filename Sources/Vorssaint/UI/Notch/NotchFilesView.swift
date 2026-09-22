// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchFilesView: View {
    @ObservedObject var service: NotchService
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
        VStack(spacing: NotchLayout.rowSpacing) {
            if service.choosingFileDropDestination, AppFeature.mediaTools.isAvailable {
                HStack(spacing: NotchFileToolsSupport.dropSpacing) {
                    dropDestination(FeatureStrings.notch(l10n.language).files, symbol: "tray.and.arrow.down",
                                    selected: !service.targetsMediaDrop)
                    dropDestination(text.optimizeMedia, symbol: "wand.and.stars", selected: service.targetsMediaDrop,
                                    available: archives.canAcceptMediaDrop)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = archives.mediaSession, archives.mediaPresented, AppFeature.mediaTools.isAvailable {
                MediaWorkspaceView(compact: true, onClose: archives.closeMedia,
                                   media: media, initialInputs: session.inputs,
                                   initialTool: session.tool, preservesServiceState: true,
                                   workspace: archives.mediaSelection,
                                   onContentHeightChange: { mediaHeightChanged($0, id: session.id) },
                                   onToolChange: { service.refreshPresentation(transitionContent: .replace) })
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
                               revealSerial: shelf.addSerial,
                               sideways: true)
                    .frame(maxHeight: .infinity)
                HStack {
                    Text(shelf.selection.isEmpty ? l10n.s.shelfHint
                         : String(format: l10n.s.shelfSelectedFormat, shelf.selection.count))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if AppFeature.mediaTools.isAvailable {
                        NotchIconButton(symbol: "wand.and.stars", title: l10n.s.mediaName) {
                            actionInputs = shelf.fileURLsForActions()
                            supportedTools = MediaTool.allCases.filter { NotchFileToolsSupport.accepts(actionInputs, for: $0) }
                            showingActions = !actionInputs.isEmpty
                        }
                        .disabled(!shelf.hasFilesForActions || !archives.canAcceptMediaDrop)
                        .popover(isPresented: $showingActions) { fileActions.padding(14).frame(width: 270) }
                    }
                    NotchIconButton(symbol: "square.and.arrow.up", title: l10n.s.shelfActionShare) {
                        shareAnchor.present(shelf.fileURLsForActions())
                    }
                    .background(ShelfSharePickerAnchor(anchor: shareAnchor))
                    .disabled(!shelf.hasFilesForActions)
                    // The shelf's trash takes the selection first, the whole
                    // shelf only when nothing is selected.
                    if shelf.selection.isEmpty {
                        clearMenu
                    } else {
                        NotchIconButton(symbol: "trash.fill", title: l10n.s.shelfRemoveSelected) {
                            shelf.removeItems(Array(shelf.selection))
                        }
                        .disabled(archives.isRunning)
                    }
                }
            }
            if !service.choosingFileDropDestination, !archives.mediaPresented, AppFeature.mediaTools.isAvailable {
                archiveStatus
                if archives.mediaSession != nil {
                    Button(action: archives.showMedia) {
                        Label(text.resumeMedia, systemImage: "wand.and.stars")
                    }.controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: archives.mediaSession?.id) {
            service.refreshPresentation()
        }
        .onChange(of: archives.mediaPresented) { service.refreshPresentation() }
        .onChange(of: showingActions || outputPanel != nil) { _, active in service.keepFileInteractionOpen(active) }
        .onDisappear {
            outputPanel?.cancel(nil)
            outputPanel = nil
            service.keepFileInteractionOpen(false)
        }
        .onChange(of: features.revision) {
            if !AppFeature.mediaTools.isAvailable {
                archives.syncWithPreferences()
                showingActions = false
                outputPanel?.cancel(nil)
            }
        }
    }

    private func mediaHeightChanged(_ height: CGFloat, id: UUID) {
        let previous = archives.mediaContentHeight
        archives.updateMediaHeight(id: id, height: height)
        // Start the native resize in the same layout callback. Waiting for a
        // second SwiftUI update leaves the new controls inside the old frame,
        // and an unrelated preference refresh can settle it without animation.
        if archives.mediaContentHeight != previous { service.refreshPresentation() }
    }

    private func dropDestination(_ title: String, symbol: String, selected: Bool, available: Bool = true) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
            Text(title).font(.callout.weight(.medium)).multilineTextAlignment(.center)
            if !available { Text(l10n.s.mediaRunning).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(selected ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(selected ? 0.7 : 0.2), lineWidth: selected ? 1.5 : 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .opacity(available ? 1 : 0.5)
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
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            outputPanel = nil
            guard response == .OK, let destination = panel.url,
                  AppFeature.mediaTools.isAvailable, AppFeature.shelf.isAvailable,
                  NotchSupport.isEnabled() else { return }
            archives.archive(inputs, destination: destination, directory: multiple)
            service.open(.files)
        }
    }

}
