// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Settings page: preferences and a button that opens the workspace window.
struct DiskAnalyzerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var permissions = Permissions.shared

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        Form {
            Section {
                Button {
                    service.showWindow()
                } label: {
                    Label(strings.openWindow, systemImage: "square.grid.3x3.fill")
                }
                Text(strings.openWindowCaption)
                    .font(.caption)
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

/// Floating workspace: scan controls, details, size-sorted list, and treemap.
struct DiskAnalyzerWorkspaceView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var pendingTrash = false

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(pendingTrashTitle,
               isPresented: $pendingTrash) {
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
            Button(strings.moveToTrash, role: .destructive) {
                _ = service.trashSelection()
            }
        } message: {
            Text(strings.confirmTrashMessage)
        }
    }

    private var pendingTrashTitle: String {
        guard let name = service.selectedNode?.name else { return strings.moveToTrash }
        return String(format: strings.confirmTrashFormat, name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(Color.accentColor)
                Text(strings.pageTitle).font(.headline)
                Spacer()
                if service.phase == .scanning {
                    Button(strings.cancel) { service.cancel() }
                        .controlSize(.small)
                } else if service.root != nil {
                    Button(strings.rescan) { service.rescan() }
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button(strings.scanHome) { service.scanHome() }
                    .disabled(service.phase == .scanning)
                Button(strings.scanStartupDisk) { service.scanStartupDisk() }
                    .disabled(service.phase == .scanning)
                Button(strings.chooseFolder) { service.chooseFolderAndScan() }
                    .disabled(service.phase == .scanning)
                Spacer()
                Toggle(strings.includeHidden, isOn: $service.includeHidden)
                    .toggleStyle(.checkbox)
                    .disabled(service.phase == .scanning)
            }
            .controlSize(.small)

            if !permissions.fullDiskAccess {
                Label(strings.fullDiskNote, systemImage: "externaldrive.badge.person.crop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
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
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(strings.emptyTitle).font(.headline)
            Text(strings.emptySubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text(String(format: strings.scanningFormat,
                        DiskAnalyzerSupport.formatBytes(service.progress.bytes),
                        service.progress.files))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(service.progress.currentPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var analyzerBody: some View {
        VStack(spacing: 0) {
            breadcrumbs
            Divider()
            detailBar
            Divider()
            HSplitView {
                itemList
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                // Identity on the zoom folder so selection changes do not
                // recreate the representable — the NSView caches the bitmap.
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
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                .id(service.zoomPath ?? service.root?.path ?? "")
            }
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 8) {
            Button {
                service.zoomOut()
            } label: {
                Label(strings.goUp, systemImage: "arrow.up.left")
            }
            .controlSize(.small)
            .disabled(!service.canZoomOut)
            .help(strings.goUp)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(service.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var detailBar: some View {
        Group {
            if let node = service.selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(node.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(DiskAnalyzerSupport.formatBytes(node.size))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let parentSize = parentSize(for: node), parentSize > 0 {
                            let fraction = Double(node.size) / Double(parentSize)
                            Text(String(format: strings.percentOfParentFormat,
                                        String(format: "%.1f%%", fraction * 100)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    if !node.isAggregate {
                        Text(node.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 8) {
                        if !node.isAggregate {
                            Button(strings.revealInFinder) { service.revealSelection() }
                            Button(strings.copyPath) { service.copySelectionPath() }
                        }
                        if node.isDirectory, !node.isAggregate {
                            Button(strings.zoomIn) { service.zoomIntoSelection() }
                        }
                        if service.canZoomOut {
                            Button(strings.goUp) { service.zoomOut() }
                        }
                        if service.canTrashSelection {
                            Button(strings.moveToTrash, role: .destructive) {
                                pendingTrash = true
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                    if let error = service.trashError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text(strings.selectedNone)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(strings.itemsInFolder)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            List(selection: Binding(
                get: { service.selectedPath },
                set: { service.select(path: $0) }
            )) {
                ForEach(service.listedItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.isDirectory ? "folder.fill" : (item.isAggregate ? "square.stack.3d.up" : "doc"))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(item.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(DiskAnalyzerSupport.formatBytes(item.size))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(item.path)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        service.select(path: item.path)
                        if item.isDirectory, !item.isAggregate {
                            service.zoom(to: item.path)
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
            }
            .listStyle(.inset)
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
