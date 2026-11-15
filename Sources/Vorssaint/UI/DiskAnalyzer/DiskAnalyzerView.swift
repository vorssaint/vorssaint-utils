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
            scanControls
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

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(strings.scanHome) { service.scanHome() }
                    .disabled(service.phase == .scanning)
                Button(strings.scanStartupDisk) { service.scanStartupDisk() }
                    .disabled(service.phase == .scanning)
                Button(strings.chooseFolder) { service.chooseFolderAndScan() }
                    .disabled(service.phase == .scanning)
                Spacer(minLength: 0)
                if service.phase == .scanning {
                    Button(strings.cancel) { service.cancel() }
                } else if service.root != nil {
                    Button(strings.rescan) { service.rescan() }
                }
            }
            .controlSize(.mini)
            .buttonStyle(.bordered)

            if !permissions.fullDiskAccess {
                Label(strings.fullDiskNote, systemImage: "externaldrive.badge.person.crop")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle:
            emptyState
        case .scanning:
            scanningState
        case .failed(let message):
            failedState(message)
        case .ready:
            if service.root != nil {
                analyzerBody
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.emptyTitle)
                .font(.system(size: 12, weight: .semibold))
            Text(strings.emptySubtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var scanningState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(format: strings.scanningFormat,
                            DiskAnalyzerSupport.formatBytes(service.progress.bytes),
                            service.progress.files))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(service.progress.currentPath)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .panelCard()
    }

    private func failedState(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10.5))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .panelCard()
    }

    private var analyzerBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            breadcrumbs
            detailBar
            DiskAnalyzerTreemapView(
                root: service.zoomNode,
                selectedPath: service.selectedPath,
                onSelect: { service.select(path: $0) },
                onActivate: { path in
                    service.select(path: path)
                    if let root = service.root,
                       let node = DiskAnalyzerSupport.node(at: path, in: root),
                       node.isDirectory, !node.isAggregate {
                        service.zoom(to: path)
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: inNotch ? 220 : 200)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .id(service.zoomPath ?? service.root?.path ?? "")

            itemList
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            Button {
                service.zoomOut()
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(!service.canZoomOut)
            .help(strings.goUp)

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
                        .font(.system(size: 10.5, weight: index == service.breadcrumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == service.breadcrumbs.count - 1 ? Color.primary : Color.secondary)
                    }
                }
            }
        }
    }

    private var detailBar: some View {
        Group {
            if let node = service.selectedNode {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(node.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Text(DiskAnalyzerSupport.formatBytes(node.size))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let parentSize = parentSize(for: node), parentSize > 0 {
                            let fraction = Double(node.size) / Double(parentSize)
                            Text(String(format: strings.percentOfParentFormat,
                                        String(format: "%.1f%%", fraction * 100)))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    if !node.isAggregate {
                        Text(node.path)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        if !node.isAggregate {
                            Button(strings.revealInFinder) { service.revealSelection() }
                            Button(strings.copyPath) { service.copySelectionPath() }
                        }
                        if node.isDirectory, !node.isAggregate {
                            Button(strings.zoomIn) { service.zoomIntoSelection() }
                        }
                        if service.canTrashSelection {
                            Button(strings.moveToTrash, role: .destructive) {
                                pendingTrash = true
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.mini)
                    if let error = service.trashError {
                        Text(error)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text(strings.selectedNone)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelCard()
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(strings.itemsInFolder)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(service.listedItems) { item in
                        itemRow(item)
                    }
                }
            }
            .frame(maxHeight: inNotch ? 220 : 200)
        }
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
        .onTapGesture(count: 2) {
            service.select(path: item.path)
            if item.isDirectory, !item.isAggregate {
                service.zoom(to: item.path)
            }
        }
        .onTapGesture {
            service.select(path: item.path)
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

    private func parentSize(for node: DiskAnalyzerSupport.Node) -> Int64? {
        guard let root = service.root else { return nil }
        let parentPath = URL(fileURLWithPath: node.path).deletingLastPathComponent().path
        if parentPath == node.path { return nil }
        return DiskAnalyzerSupport.node(at: parentPath, in: root)?.size
            ?? (service.zoomNode?.path == parentPath ? service.zoomNode?.size : nil)
    }
}
