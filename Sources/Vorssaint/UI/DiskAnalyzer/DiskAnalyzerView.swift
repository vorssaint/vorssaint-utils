// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Settings page: preferences only. Scanning and cleanup live in the menu
/// panel / island Utilities section like the other first-party tools.
struct DiskAnalyzerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var permissions = Permissions.shared

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        Form {
            Section {
                Text(strings.openFromUtilities)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle(strings.includeHidden, isOn: $service.includeHidden)
                Text(strings.includeHiddenCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !permissions.fullDiskAccess {
                Section {
                    Label(strings.fullDiskNote, systemImage: "externaldrive.badge.person.crop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shared workspace used by the menu panel / island (compact) layout.
struct DiskAnalyzerWorkspaceView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var permissions = Permissions.shared
    @Environment(\.notchPresentation) private var inNotch
    @State private var pendingTrash = false

    /// When true, fits the menu popover / island: vertical treemap + list.
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
                set: { if !$0 { pendingTrash = false } }
               )) {
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
            Button(strings.moveToTrash, role: .destructive) {
                _ = service.trashSelection()
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
        guard let name = service.selectedNode?.name else { return strings.moveToTrash }
        return String(format: strings.confirmTrashFormat, name)
    }

    private func confirmTrashAboveIsland() {
        let title = pendingTrashTitle
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(
                title,
                message: strings.confirmTrashMessage,
                action: strings.moveToTrash,
                destructive: true,
                cancel: l10n.s.uninstallerCancel
            ) else { return }
            _ = service.trashSelection()
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

    /// Two equal start actions: pick a folder, or scan the startup disk.
    private var startActions: some View {
        VStack(spacing: 8) {
            startButton(
                title: strings.emptyTitle,
                subtitle: strings.emptySubtitle,
                systemImage: "folder",
                accessibility: strings.chooseFolder,
                action: { service.chooseFolderAndScan() }
            )
            startButton(
                title: strings.scanStartupDisk,
                subtitle: nil,
                systemImage: "internaldrive",
                accessibility: strings.scanStartupDisk,
                action: { service.scanStartupDisk() }
            )

            if !permissions.fullDiskAccess {
                Label(strings.fullDiskNote, systemImage: "externaldrive.badge.person.crop")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startButton(title: String,
                             subtitle: String?,
                             systemImage: String,
                             accessibility: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
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
            iconButton("xmark", help: strings.cancel) {
                service.cancel()
            }
        }
        .panelCard()
    }

    private var analyzerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationBar
            DiskAnalyzerTreemapView(
                root: service.zoomNode,
                selectedPath: service.selectedPath,
                onSelect: { path in
                    handleMapSelect(path)
                },
                onActivate: { path in
                    handleMapSelect(path)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: inNotch ? 220 : 200)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .id(service.zoomPath ?? service.root?.path ?? "")

            itemList
        }
    }

    /// Current folder name + size, one up icon, and selection actions as icons.
    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                service.zoomOut()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(service.canZoomOut ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!service.canZoomOut)
            .help(strings.goUp)
            .accessibilityLabel(strings.goUp)

            VStack(alignment: .leading, spacing: 1) {
                Text(currentFolderTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if let node = service.selectedNode, node.path != service.zoomPath {
                    Text("\(node.name) · \(DiskAnalyzerSupport.formatBytes(node.size))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let zoom = service.zoomNode {
                    Text(DiskAnalyzerSupport.formatBytes(zoom.size))
                        .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            iconButton("arrow.clockwise", help: strings.rescan) {
                service.rescan()
            }

            if let node = service.selectedNode, !node.isAggregate {
                iconButton("arrow.up.forward.app", help: strings.revealInFinder) {
                    service.revealSelection()
                }
                if service.canTrashSelection {
                    iconButton("trash", help: strings.moveToTrash, tint: .red) {
                        pendingTrash = true
                    }
                }
            }
        }
        .panelCard()
    }

    private var currentFolderTitle: String {
        let name = service.zoomNode?.name ?? ""
        return name.isEmpty ? "/" : name
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(service.listedItems) { item in
                    itemRow(item)
                }
            }
        }
        .frame(maxHeight: inNotch ? 220 : 200)
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
            if item.isDirectory, !item.isAggregate {
                service.zoom(to: item.path)
            } else {
                service.select(path: item.path)
            }
        }
        .contextMenu {
            if !item.isAggregate {
                Button(strings.revealInFinder) {
                    service.select(path: item.path)
                    service.revealSelection()
                }
                if DiskAnalyzerSupport.canTrash(item.url) {
                    Button(strings.moveToTrash, role: .destructive) {
                        service.select(path: item.path)
                        pendingTrash = true
                    }
                }
            }
        }
    }

    /// Click a map block: directories drill in; files become the selection.
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

    private func iconButton(_ systemName: String,
                            help: String,
                            tint: Color? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
