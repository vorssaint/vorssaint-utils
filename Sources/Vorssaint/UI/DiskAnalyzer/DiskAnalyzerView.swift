// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Disk Analyzer settings page: pick a root, scan into a size tree, and
/// explore it as a colored squarified treemap with inspect / trash actions.
struct DiskAnalyzerView: View {
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
        .onDisappear { service.cancel() }
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
            }
            .controlSize(.small)

            Toggle(strings.includeHidden, isOn: $service.includeHidden)
                .disabled(service.phase == .scanning)
            Text(strings.includeHiddenCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

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
                .frame(maxWidth: 360)
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
                .frame(maxWidth: 420)
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
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var analyzerBody: some View {
        VStack(spacing: 0) {
            breadcrumbs
            Divider()
            HStack(spacing: 0) {
                DiskAnalyzerTreemapView(
                    root: service.zoomNode,
                    selectedPath: service.selectedPath,
                    onSelect: { service.select(path: $0) },
                    onActivate: { path in
                        service.select(path: path)
                        if let node = service.selectedNode, node.isDirectory {
                            service.zoom(to: path)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                detailPanel
                    .frame(width: 240)
            }
        }
    }

    private var breadcrumbs: some View {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let node = service.selectedNode {
                Text(node.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(node.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                labeled(strings.sizeLabel, DiskAnalyzerSupport.formatBytes(node.size))
                if let parentSize = parentSize(for: node), parentSize > 0 {
                    let fraction = Double(node.size) / Double(parentSize)
                    Text(String(format: strings.percentOfParentFormat,
                                String(format: "%.1f%%", fraction * 100)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if node.isDirectory {
                    Text(String(format: strings.filesFormat, node.children.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button(strings.revealInFinder) { service.revealSelection() }
                    Button(strings.open) { service.openSelection() }
                    Button(strings.copyPath) { service.copySelectionPath() }
                    if node.isDirectory {
                        Button(strings.zoomIn) { service.zoomIntoSelection() }
                    }
                    if service.canTrashSelection {
                        Button(strings.moveToTrash, role: .destructive) {
                            pendingTrash = true
                        }
                    }
                }
                .controlSize(.small)

                if let error = service.trashError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(strings.selectedNone)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func parentSize(for node: DiskAnalyzerSupport.Node) -> Int64? {
        guard let root = service.root else { return nil }
        let parentPath = URL(fileURLWithPath: node.path).deletingLastPathComponent().path
        if parentPath == node.path { return nil }
        return DiskAnalyzerSupport.node(at: parentPath, in: root)?.size
            ?? (service.zoomNode?.path == parentPath ? service.zoomNode?.size : nil)
    }
}

struct DiskAnalyzerTreemapView: View {
    let root: DiskAnalyzerSupport.Node?
    let selectedPath: String?
    let onSelect: (String) -> Void
    let onActivate: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let cells = DiskAnalyzerSupport.layoutTreemap(
                root: root ?? DiskAnalyzerSupport.Node(path: "", name: "", size: 0,
                                                       isDirectory: true, children: []),
                in: CGRect(origin: .zero, size: geo.size)
            )
            Canvas { context, _ in
                for cell in cells {
                    let color = Color(nsColor: DiskAnalyzerSupport.color(for: cell.colorIndex,
                                                                         depth: cell.depth))
                    context.fill(Path(cell.rect), with: .color(color))
                    if cell.path == selectedPath {
                        context.stroke(Path(cell.rect.insetBy(dx: 0.5, dy: 0.5)),
                                       with: .color(.white), lineWidth: 2)
                    } else {
                        context.stroke(Path(cell.rect), with: .color(.black.opacity(0.25)),
                                       lineWidth: 0.5)
                    }
                    if cell.rect.width > 48, cell.rect.height > 18, cell.depth <= 1 {
                        let text = Text(cell.name).font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                        context.draw(text, at: CGPoint(x: cell.rect.midX, y: cell.rect.minY + 10),
                                     anchor: .center)
                    }
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let cell = hit(cells, at: value.location) {
                        onSelect(cell.path)
                    }
                }
            )
            .onTapGesture(count: 2) {
                // Double-tap uses last selection; SpatialTapGesture already selected.
                if let path = selectedPath { onActivate(path) }
            }
            .contentShape(Rectangle())
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
    }

    private func hit(_ cells: [DiskAnalyzerSupport.TreemapCell],
                     at point: CGPoint) -> DiskAnalyzerSupport.TreemapCell? {
        // Prefer the deepest (last laid-out nested) cell under the point.
        cells.reversed().first { $0.rect.contains(point) }
    }
}
