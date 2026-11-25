// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuickLook
import SwiftUI

/// The explored map: the chart and an action bar for the selected item on
/// the left, the list on the right, and a bar for items marked to go to the
/// Trash together.
struct DiskAnalyzerResultsView: View {
    @ObservedObject private var service = DiskAnalyzerService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var hovered: DiskNode?
    @State private var listMode = ListMode.contents
    @State private var pendingTrash: [DiskNode] = []
    @State private var trashError: String?
    @State private var quickLook: URL?
    @State private var reviewingMarks = false

    private enum ListMode: Hashable {
        case contents, largest, suggestions
    }

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        if let root = service.root, let focus = service.focus {
            VStack(spacing: 0) {
                toolbar(focus: focus)
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        chart(focus: focus)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .top) { trashReceipt }
                        Divider()
                        actionBar(for: service.selected ?? focus)
                    }
                    Divider()
                    sidebar(focus: focus)
                        .frame(width: 360)
                }
                if !service.marked.isEmpty {
                    Divider()
                    markedBar
                }
                Divider()
                footer(root: root)
            }
            .quickLookPreview($quickLook)
            .background(shortcuts(focus: focus))
            .alert(trashTitle, isPresented: Binding(get: { !pendingTrash.isEmpty },
                                                    set: { if !$0 { pendingTrash = [] } })) {
                Button(strings.moveToTrash, role: .destructive) {
                    trash(pendingTrash)
                    pendingTrash = []
                }
                Button(strings.cancel, role: .cancel) { pendingTrash = [] }
            } message: {
                Text(String(format: strings.trashMessageFormat,
                            DiskAnalyzerFormat.bytes(pendingTrash.reduce(0) { $0 + $1.size })))
            }
            .alert(trashError ?? "", isPresented: Binding(get: { trashError != nil },
                                                          set: { if !$0 { trashError = nil } })) {
                Button("OK") { trashError = nil }
            }
            .animation(.easeOut(duration: 0.2), value: service.marked.isEmpty)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: service.lastTrash?.id)
        }
    }

    private var trashTitle: String {
        if pendingTrash.count == 1, let node = pendingTrash.first {
            return String(format: strings.trashTitleFormat, node.name)
        }
        return String(format: strings.trashManyTitleFormat, DiskAnalyzerFormat.count(pendingTrash.count))
    }

    // MARK: Toolbar

    private func toolbar(focus: DiskNode) -> some View {
        HStack(spacing: 10) {
            Button {
                service.reset()
            } label: {
                Label(strings.newScan, systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            Divider().frame(height: 16)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(focus.lineage.enumerated()), id: \.offset) { index, node in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            Button {
                                service.focus(on: node)
                            } label: {
                                Text(index == 0 ? (service.target?.name ?? node.name) : node.name)
                                    .font(.system(size: 12, weight: node === focus ? .semibold : .regular))
                                    .foregroundStyle(node === focus ? .primary : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 5)
                                        .fill(node === focus ? Color.primary.opacity(0.07) : .clear))
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onChange(of: ObjectIdentifier(focus)) { _, _ in
                    withAnimation { reader.scrollTo(focus.lineage.count - 1, anchor: .trailing) }
                }
            }
            Spacer(minLength: 8)
            if service.rescanning {
                ProgressView().controlSize(.small)
            }
            Button {
                service.rescanFocus()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(strings.rescan)
            .accessibilityLabel(strings.rescan)
            .disabled(service.rescanning)
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 38)
    }

    // MARK: Chart

    private func chart(focus: DiskNode) -> some View {
        let shown = hovered ?? service.selected ?? focus
        let share = focus.size > 0 ? Double(shown.size) / Double(focus.size) : 0
        let caption: String
        if shown === focus {
            caption = String(format: strings.filesFormat, DiskAnalyzerFormat.count(focus.fileCount))
        } else {
            caption = share.formatted(.percent.precision(.fractionLength(share < 0.1 ? 1 : 0)))
        }
        return SunburstChart(focus: focus,
                             revision: service.revision,
                             centerTitle: displayName(shown),
                             centerDetail: DiskAnalyzerFormat.bytes(shown.size),
                             centerCaption: caption,
                             canGoUp: focus.parent != nil,
                             selected: service.selected,
                             marked: service.marked,
                             hovered: $hovered,
                             onSelect: chartSelect,
                             onUp: { service.focusParent() })
            .contextMenu {
                if let node = hovered { menu(for: node) }
            }
    }

    /// Folders open on click, the way the map is explored; anything else
    /// becomes the selection the action bar works on.
    private func chartSelect(_ node: DiskNode) {
        if node.canDrillDown {
            service.focus(on: node)
        } else {
            service.selected = node
        }
    }

    // MARK: Action bar

    private func actionBar(for node: DiskNode) -> some View {
        HStack(spacing: 10) {
            DiskAnalyzerIcon(node: node)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(node))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(node.isFileSystemItem ? node.path : DiskAnalyzerFormat.bytes(node.size))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if node.isFileSystemItem {
                Text(DiskAnalyzerFormat.bytes(node.size))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    actionButton(strings.quickLook, symbol: "eye") { quickLook = node.url }
                    actionButton(strings.revealInFinder, symbol: "folder") { service.reveal(node) }
                    if node.isDirectory {
                        actionButton(strings.openInTerminal, symbol: "terminal") { service.openInTerminal(node) }
                    } else {
                        actionButton(strings.open, symbol: "arrow.up.forward.app") { service.open(node) }
                    }
                    if service.canTrash(node) {
                        let marked = service.isMarked(node)
                        actionButton(marked ? strings.unmark : strings.mark,
                                     symbol: marked ? "checkmark.circle.fill" : "checkmark.circle",
                                     tint: marked ? .red : nil) { service.toggleMark(node) }
                        Button(role: .destructive) {
                            pendingTrash = [node]
                        } label: {
                            Label(strings.moveToTrash, systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .help(strings.moveToTrash + "  ⌘⌫")
                    }
                }
                .controlSize(.regular)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private func actionButton(_ title: String, symbol: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(tint ?? .primary)
        }
        .buttonStyle(.bordered)
        .help(title)
        .accessibilityLabel(title)
    }

    /// Keys for the selection: Space previews, Command-Delete trashes,
    /// Command-R reveals, Command-Up goes up and Escape clears.
    private func shortcuts(focus: DiskNode) -> some View {
        let target = service.selected ?? focus
        return ZStack {
            Button("") { if target.isFileSystemItem { quickLook = quickLook == nil ? target.url : nil } }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { if service.canTrash(target) { pendingTrash = [target] } }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("") { service.reveal(target) }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { service.focusParent() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("") { service.selected = nil }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Trash receipt

    @ViewBuilder
    private var trashReceipt: some View {
        if let receipt = service.lastTrash {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.secondary)
                Text(String(format: strings.movedFormat, DiskAnalyzerFormat.bytes(receipt.bytes)))
                    .font(.system(size: 12, weight: .medium))
                Button(strings.undo) { undo() }
                    .buttonStyle(.borderless)
                Button(strings.openTrash) { service.openTrash() }
                    .buttonStyle(.borderless)
                Button {
                    service.dismissTrashReceipt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: receipt.id) {
                try? await Task.sleep(for: .seconds(20))
                if service.lastTrash?.id == receipt.id { service.dismissTrashReceipt() }
            }
        }
    }

    private func undo() {
        let failed = service.undoLastTrash()
        if let name = failed.first {
            trashError = String(format: strings.undoFailedFormat, name)
        }
    }

    // MARK: Marked items

    private var markedBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.red)
            Text(String(format: strings.markedFormat, DiskAnalyzerFormat.count(service.marked.count),
                        DiskAnalyzerFormat.bytes(service.markedBytes)))
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
            Spacer()
            Button(strings.review) { reviewingMarks.toggle() }
                .popover(isPresented: $reviewingMarks, arrowEdge: .top) { markedReview }
            Button(strings.clearMarks) { service.clearMarks() }
            Button(role: .destructive) {
                pendingTrash = service.marked
            } label: {
                Label(strings.moveToTrash, systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.red.opacity(0.06))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var markedReview: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(service.marked) { node in
                    HStack(spacing: 10) {
                        DiskAnalyzerIcon(node: node)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(node.parent?.path ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Spacer(minLength: 8)
                        Text(DiskAnalyzerFormat.bytes(node.size))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Button {
                            service.toggleMark(node)
                            if service.marked.isEmpty { reviewingMarks = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(strings.unmark)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { service.reveal(node) }
                }
            }
            .padding(8)
        }
        .frame(width: 380)
        .frame(maxHeight: 360)
    }

    // MARK: Sidebar

    private func sidebar(focus: DiskNode) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $listMode) {
                Text(strings.contents).tag(ListMode.contents)
                Text(strings.largestFiles).tag(ListMode.largest)
                Text(strings.suggestions).tag(ListMode.suggestions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    switch listMode {
                    case .contents:
                        contentsRows(focus: focus)
                    case .largest:
                        let files = service.largestFiles(in: focus)
                        let top = files.first?.size ?? 1
                        ForEach(files) { node in
                            row(node, name: node.name, color: .accentColor,
                                share: Double(node.size) / Double(max(1, top)),
                                detail: node.parent?.path)
                        }
                    case .suggestions:
                        suggestionRows(focus: focus)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .id(listMode == .contents ? "contents" : "\(listMode)-\(ObjectIdentifier(focus).hashValue)-\(service.revision)")
        }
    }

    @ViewBuilder
    private func contentsRows(focus: DiskNode) -> some View {
        let rows = coloredChildren(of: focus)
        if rows.isEmpty {
            Text(strings.emptyFolder)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
        }
        ForEach(rows, id: \.node.id) { item in
            row(item.node, name: displayName(item.node), color: item.color,
                share: focus.size > 0 ? Double(item.node.size) / Double(focus.size) : 0, detail: nil)
        }
    }

    @ViewBuilder
    private func suggestionRows(focus: DiskNode) -> some View {
        let folders = service.rebuildableFolders(in: focus)
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.suggestionsHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if folders.count > 1 {
                HStack {
                    Button(strings.markAll) {
                        for folder in folders where !service.isMarked(folder.node) { service.toggleMark(folder.node) }
                    }
                    .controlSize(.small)
                    Spacer()
                    Text(DiskAnalyzerFormat.bytes(folders.reduce(0) { $0 + $1.node.size }))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        if folders.isEmpty {
            Text(strings.suggestionsEmpty)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 30)
        }
        let top = folders.first?.node.size ?? 1
        ForEach(folders, id: \.node.id) { folder in
            row(folder.node, name: folder.node.name, color: .orange,
                share: Double(folder.node.size) / Double(max(1, top)),
                detail: (folder.node.parent?.name ?? "") + " · " + reason(folder.kind),
                detailTruncation: .tail)
        }
    }

    private func reason(_ kind: DiskAnalyzerSupport.Rebuildable) -> String {
        switch kind {
        case .nodeModules: return strings.rebuildNodeModules
        case .derivedData: return strings.rebuildDerivedData
        case .dartTool: return strings.rebuildDartTool
        case .gradle: return strings.rebuildGradle
        case .pods: return strings.rebuildPods
        case .pythonCache: return strings.rebuildPythonCache
        case .webBuildCache: return strings.rebuildWebCache
        case .deviceSupport: return strings.rebuildDeviceSupport
        }
    }

    private func row(_ node: DiskNode, name: String, color: Color, share: Double, detail: String?,
                     detailTruncation: Text.TruncationMode = .head) -> some View {
        DiskAnalyzerRow(node: node, name: name, color: color, share: share, detail: detail,
                        detailTruncation: detailTruncation,
                        selected: service.selected === node,
                        highlighted: hovered === node,
                        marked: service.isMarked(node),
                        coveredByMark: service.isCoveredByMark(node),
                        canTrash: service.canTrash(node),
                        hovered: $hovered,
                        onZoom: { service.focus(on: node) },
                        onReveal: { service.reveal(node) },
                        onToggleMark: { service.toggleMark(node) },
                        onTrash: { pendingTrash = [node] })
            // Selecting stays instant; a second click on the same row then
            // opens a folder or previews a file.
            .onTapGesture { service.selected = node }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if node.canDrillDown {
                    service.focus(on: node)
                } else if node.isFileSystemItem {
                    quickLook = node.url
                }
            })
            .contextMenu { menu(for: node) }
    }

    /// The focus's children with the same colours the chart gives them.
    private func coloredChildren(of focus: DiskNode) -> [(node: DiskNode, color: Color)] {
        guard focus.size > 0 else { return [] }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var cursor = 0.0
        return focus.children.filter { $0.size > 0 }.map { child in
            let span = Double(child.size) / Double(focus.size)
            defer { cursor += span }
            return (child, SunburstPalette.color(for: child.kind, mid: cursor + span / 2, depth: 1, dark: dark))
        }
    }

    @ViewBuilder
    private func menu(for node: DiskNode) -> some View {
        if node.canDrillDown {
            Button(strings.zoomIn) { service.focus(on: node) }
        }
        if node.isFileSystemItem {
            Button(strings.quickLook) { quickLook = node.url }
            Button(strings.revealInFinder) { service.reveal(node) }
            Button(strings.open) { service.open(node) }
            Button(strings.openInTerminal) { service.openInTerminal(node) }
            Button(strings.copyPath) { service.copyPath(node) }
            if service.canTrash(node) {
                Divider()
                Button(service.isMarked(node) ? strings.unmark : strings.mark) { service.toggleMark(node) }
                Button(strings.moveToTrash, role: .destructive) { pendingTrash = [node] }
            }
        }
    }

    private func trash(_ nodes: [DiskNode]) {
        if let hovered, nodes.contains(where: { $0 === hovered || $0.isAncestor(of: hovered) }) {
            self.hovered = nil
        }
        let receipt = service.moveToTrash(nodes)
        if let failed = receipt.failed.first {
            trashError = String(format: strings.trashFailedFormat, failed)
        }
    }

    // MARK: Footer

    private func footer(root: DiskNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(String(format: strings.summaryFormat, DiskAnalyzerFormat.count(service.progress.files),
                        duration(service.scanSeconds)))
                .font(.caption)
                .foregroundStyle(.secondary)
            if service.progress.unreadable > 0 {
                Text("·").foregroundStyle(.tertiary)
                Label(String(format: strings.unreadableFormat, DiskAnalyzerFormat.count(service.progress.unreadable)),
                      systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(strings.fullDiskAccessReason)
            }
            Spacer()
            if !permissions.fullDiskAccess {
                Button(strings.allowFullDiskAccess) { permissions.requestFullDiskAccess() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private func displayName(_ node: DiskNode) -> String {
        switch node.kind {
        case .smallFiles: return String(format: strings.smallFilesFormat, DiskAnalyzerFormat.count(node.fileCount))
        case .hidden: return strings.hiddenSpace
        case .directory, .file:
            return node.parent == nil ? (service.target?.name ?? node.name) : node.name
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(1, seconds.rounded())) ?? ""
    }
}

/// One list row: icon, name, size and a bar for its share. Hovering shows
/// quick actions; a marked row keeps its mark visible.
private struct DiskAnalyzerRow: View {
    let node: DiskNode
    let name: String
    let color: Color
    let share: Double
    let detail: String?
    let detailTruncation: Text.TruncationMode
    let selected: Bool
    let highlighted: Bool
    let marked: Bool
    let coveredByMark: Bool
    let canTrash: Bool
    @Binding var hovered: DiskNode?
    let onZoom: () -> Void
    let onReveal: () -> Void
    let onToggleMark: () -> Void
    let onTrash: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var hovering = false

    private var strings: DiskAnalyzerFeatureStrings { FeatureStrings.diskAnalyzer(l10n.language) }

    var body: some View {
        HStack(spacing: 10) {
            DiskAnalyzerIcon(node: node)
                .frame(width: 26, height: 26)
                .opacity(coveredByMark ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .strikethrough(marked || coveredByMark, color: .red.opacity(0.7))
                    if node.unreadable {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .help(strings.unreadableHelp)
                    } else if node.cloudOnly {
                        Image(systemName: "icloud")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .help(strings.cloudOnlyHelp)
                    }
                    Spacer(minLength: 4)
                    if hovering && node.isFileSystemItem {
                        quickActions
                    } else {
                        Text(DiskAnalyzerFormat.bytes(node.size))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(detailTruncation)
                        .help(detail)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule().fill((marked ? Color.red : color).gradient)
                            .frame(width: max(3, proxy.size.width * min(1, share)))
                    }
                }
                .frame(height: 4)
            }
            if marked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            } else if node.canDrillDown {
                Button(action: onZoom) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.zoomIn)
                .accessibilityLabel(strings.zoomIn)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.16)
                  : Color.primary.opacity(highlighted || hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { hovered = node } else if hovered === node { hovered = nil }
        }
        .help(node.kind == .hidden ? strings.hiddenSpaceHelp : node.collapsed ? strings.collapsedHelp : "")
    }

    private var quickActions: some View {
        HStack(spacing: 2) {
            rowButton(strings.revealInFinder, symbol: "folder", action: onReveal)
            if canTrash {
                rowButton(marked ? strings.unmark : strings.mark,
                          symbol: marked ? "checkmark.circle.fill" : "checkmark.circle",
                          tint: marked ? .red : nil, action: onToggleMark)
                rowButton(strings.moveToTrash, symbol: "trash", tint: .red, action: onTrash)
            }
        }
    }

    private func rowButton(_ title: String, symbol: String, tint: Color? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A Finder icon for real items, a symbol for folded and hidden space.
struct DiskAnalyzerIcon: View {
    let node: DiskNode

    var body: some View {
        switch node.kind {
        case .smallFiles:
            Image(systemName: "square.stack.3d.down.right")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        case .hidden:
            Image(systemName: "eye.slash")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        case .directory, .file:
            Image(nsImage: DiskAnalyzerIconCache.shared.icon(for: node))
                .resizable()
                .interpolation(.high)
        }
    }
}
