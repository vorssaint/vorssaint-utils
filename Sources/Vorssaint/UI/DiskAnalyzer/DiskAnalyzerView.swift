// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Settings page for Disk Analyzer preferences. The utility itself lives in
/// the menu panel / island Utilities section.
struct DiskAnalyzerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var permissions = Permissions.shared

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        Form {
            Section {
                Text(strings.settingsIntro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    service.presentInMenuPanel()
                } label: {
                    Label(strings.openInUtilities, systemImage: "square.grid.3x3.fill")
                }
            }

            Section(strings.scanOptionsSection) {
                Toggle(strings.includeHidden, isOn: $service.includeHidden)
                Text(strings.includeHiddenCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(strings.confirmTrash, isOn: $service.confirmTrash)
                Text(strings.confirmTrashCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(strings.displaySection) {
                Toggle(strings.showItemList, isOn: $service.showItemList)
                Text(strings.showItemListCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(strings.nestingDepth, selection: $service.nestingDepth) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                Text(strings.nestingDepthCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(strings.permissionsSection) {
                if permissions.fullDiskAccess {
                    Label(strings.fullDiskGranted, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text(strings.fullDiskNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(strings.grantFullDiskAccess) {
                        Permissions.shared.requestFullDiskAccess()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Compact Utilities workspace: map-first, click to drill in, right-click for
/// Reveal / Trash, chevron + breadcrumbs to go up.
struct DiskAnalyzerWorkspaceView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var pendingTrash = false
    @State private var pendingTrashPath: String?

    var compact: Bool = true

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(pendingTrashTitle,
               isPresented: Binding(
                get: { pendingTrash && !inNotch },
                set: { if !$0 { pendingTrash = false; pendingTrashPath = nil } }
               )) {
            Button(l10n.s.uninstallerCancel, role: .cancel) {
                pendingTrashPath = nil
            }
            Button(strings.moveToTrash, role: .destructive) {
                commitTrash()
            }
        } message: {
            Text(strings.confirmTrashMessage)
        }
        .onChange(of: pendingTrash) { _, isPending in
            guard isPending, inNotch else { return }
            pendingTrash = false
            confirmTrashAboveIsland()
        }
    }

    private var pendingTrashTitle: String {
        let name = pendingTrashPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? service.selectedNode?.name
        guard let name else { return strings.moveToTrash }
        return String(format: strings.confirmTrashFormat, name)
    }

    private func requestTrash(path: String) {
        service.select(path: path)
        guard service.canTrashSelection else { return }
        if service.confirmTrash {
            pendingTrashPath = path
            pendingTrash = true
        } else {
            pendingTrashPath = path
            commitTrash()
        }
    }

    private func commitTrash() {
        if let path = pendingTrashPath {
            service.select(path: path)
        }
        _ = service.trashSelection()
        pendingTrashPath = nil
    }

    private func confirmTrashAboveIsland() {
        let title = pendingTrashTitle
        let path = pendingTrashPath
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(
                title,
                message: strings.confirmTrashMessage,
                action: strings.moveToTrash,
                destructive: true,
                cancel: l10n.s.uninstallerCancel
            ) else {
                pendingTrashPath = nil
                return
            }
            pendingTrashPath = path
            commitTrash()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle:
            startActions
        case .scanning:
            scanningState
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .panelCard()
                startActions
            }
        case .ready:
            if service.root != nil {
                analyzerBody
            } else {
                startActions
            }
        }
    }

    private var startActions: some View {
        VStack(spacing: 8) {
            startButton(
                title: strings.emptyTitle,
                systemImage: "folder",
                accessibility: strings.chooseFolder,
                action: { service.chooseFolderAndScan() }
            )
            startButton(
                title: strings.scanStartupDisk,
                systemImage: "internaldrive",
                accessibility: strings.scanStartupDisk,
                action: { service.scanStartupDisk() }
            )
            startButton(
                title: strings.scanHome,
                systemImage: "house",
                accessibility: strings.scanHome,
                action: { service.scanHome() }
            )
        }
    }

    private func startButton(title: String,
                             systemImage: String,
                             accessibility: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var scanningState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(String(format: strings.scanningFormat,
                        DiskAnalyzerSupport.formatBytes(service.progress.bytes),
                        service.progress.files))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                service.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(strings.cancel)
        }
        .panelCard()
    }

    private var analyzerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationBar
            DiskAnalyzerTreemapView(
                root: service.zoomNode,
                selectedPath: service.selectedPath,
                nestingDepth: service.nestingDepth,
                onSelect: handleMapSelect,
                onReveal: { path in
                    service.select(path: path)
                    service.revealSelection()
                },
                onTrash: requestTrash
            )
            .frame(maxWidth: .infinity)
            .frame(height: inNotch ? 240 : 220)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .id("\(service.zoomPath ?? service.root?.path ?? "")-\(service.nestingDepth)")

            if service.showItemList {
                itemList
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 6) {
            Button {
                service.zoomOut()
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(service.canZoomOut ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!service.canZoomOut)
            .help(strings.goUp)
            .accessibilityLabel(strings.goUp)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(service.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button(node.name.isEmpty ? "/" : node.name) {
                            service.zoom(to: node.path)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: index == service.breadcrumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == service.breadcrumbs.count - 1 ? Color.primary : Color.secondary)
                    }
                }
            }

            if let zoom = service.zoomNode {
                Text(DiskAnalyzerSupport.formatBytes(zoom.size))
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                service.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(strings.rescan)
            .accessibilityLabel(strings.rescan)

            Button {
                service.startNewScan()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(strings.newScan)
            .accessibilityLabel(strings.newScan)
        }
        .panelCard()
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(service.listedItems) { item in
                    itemRow(item)
                }
            }
        }
        .frame(maxHeight: inNotch ? 200 : 180)
    }

    private func itemRow(_ item: DiskAnalyzerSupport.Node) -> some View {
        let selected = service.selectedPath == item.path
        return HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : (item.isAggregate ? "square.stack.3d.up" : "doc"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(DiskAnalyzerSupport.formatBytes(item.size))
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleMapSelect(item.path)
        }
        .contextMenu {
            if !item.isAggregate {
                Button(strings.revealInFinder) {
                    service.select(path: item.path)
                    service.revealSelection()
                }
                if DiskAnalyzerSupport.canTrash(item.url) {
                    Button(strings.moveToTrash, role: .destructive) {
                        requestTrash(path: item.path)
                    }
                }
            }
        }
    }

    /// Click: directories drill in; files select.
    private func handleMapSelect(_ path: String) {
        guard let root = service.root,
              let node = DiskAnalyzerSupport.node(at: path, in: root) else {
            service.select(path: path)
            return
        }
        if node.isDirectory, !node.isAggregate {
            service.zoom(to: path)
        } else {
            service.select(path: path)
        }
    }
}
