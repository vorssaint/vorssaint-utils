// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The zone editor's window, opened from the settings or its shortcut.
final class WindowZonesEditorWindow {
    static let shared = WindowZonesEditorWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WindowZonesEditorView())
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 860, height: 600))
            window.minSize = NSSize(width: 720, height: 500)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.title = FeatureStrings.windowZones(L10n.shared.language).editorTitle
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WindowZonesEditorView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var zones = WindowZonesService.shared
    @AppStorage(DefaultsKey.windowZonesPerSpace) private var perSpace = false
    @State private var displays: [WindowZonesService.DisplaySummary] = []
    @State private var displayID: String?
    @State private var selection: Selection = .template(.priorityGrid)
    @State private var drafts: [WindowZoneLayoutKind: WindowZoneLayout] = [:]
    @State private var currentSpaceOnly = true

    private enum Selection: Hashable {
        case template(WindowZoneLayoutKind)
        case custom(UUID)
    }

    private var text: WindowZonesStrings { FeatureStrings.windowZones(l10n.language) }
    private var display: WindowZonesService.DisplaySummary? {
        displays.first { $0.id == displayID } ?? displays.first
    }
    private var aspect: CGFloat {
        guard let size = display?.size, size.height > 0 else { return 16.0 / 10.0 }
        return size.width / size.height
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { reload(selectingCurrent: true) }
        .onReceive(zones.$configuration) { _ in reload(selectingCurrent: false) }
    }

    /// Opening the editor shows the display's current layout; later changes
    /// keep whatever the user is looking at unless it was deleted.
    private func reload(selectingCurrent: Bool) {
        displays = zones.displaySummaries()
        if displayID == nil || !displays.contains(where: { $0.id == displayID }) { displayID = displays.first?.id }
        guard let layout = display?.layout else { return }
        if layout.kind != .custom, drafts[layout.kind] == nil || selectingCurrent { drafts[layout.kind] = layout }
        if selectingCurrent {
            selection = layout.kind == .custom ? layout.customID.map(Selection.custom) ?? .template(.priorityGrid)
                                               : .template(layout.kind)
        } else if case .custom(let id) = selection,
                  !zones.configuration.customLayouts.contains(where: { $0.id == id }) {
            selection = .template(.priorityGrid)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { selection }, set: { if let value = $0 { selection = value } })) {
            if displays.count > 1 {
                Picker(text.layout, selection: Binding(get: { displayID ?? "" }, set: { displayID = $0 })) {
                    ForEach(displays) { Text($0.name).tag($0.id) }
                }
            }
            Section(text.templates) {
                ForEach(WindowZoneLayoutKind.templates) { kind in
                    row(title: WindowZonesLayoutName.name(of: kind, text: text),
                        layout: draft(for: kind), custom: [])
                        .tag(Selection.template(kind))
                }
            }
            Section(text.customLayouts) {
                ForEach(zones.configuration.customLayouts) { layout in
                    row(title: layout.name, layout: .custom(layout), custom: [layout])
                        .tag(Selection.custom(layout.id))
                }
                HStack {
                    Button(text.newGrid) { addCustom(.grid(.uniform(rows: 1, columns: 2))) }
                    Button(text.newCanvas) {
                        let size = display?.size ?? CGSize(width: 1600, height: 1000)
                        let width = Int(size.width), height = Int(size.height)
                        addCustom(.canvas(WindowZoneCanvas(
                            referenceWidth: width, referenceHeight: height,
                            zones: [WindowZoneRect(left: width / 10, top: height / 10,
                                                   right: width / 2, bottom: height * 9 / 10)])))
                    }
                }
                .controlSize(.small)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(title: String, layout: WindowZoneLayout, custom: [WindowZoneCustomLayout]) -> some View {
        HStack(spacing: 10) {
            WindowZonesPreview(zones: previewZones(layout, custom: custom), aspect: aspect)
                .frame(width: 64, height: 64 / aspect)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if display?.layout.isSameLayout(as: layout) == true {
                    Text(text.inUse).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func previewZones(_ layout: WindowZoneLayout, custom: [WindowZoneCustomLayout]) -> [CGRect] {
        let width = 1000, height = max(Int(1000 / aspect), 1)
        var scaled = layout
        scaled.spacing = max(layout.effectiveSpacing / 4, layout.effectiveSpacing > 0 ? 6 : 0)
        let customs = custom.isEmpty ? zones.configuration.customLayouts : custom
        return (WindowZoneGeometry.relativeZones(for: scaled, width: width, height: height, customLayouts: customs) ?? [])
            .map { CGRect(x: CGFloat($0.left) / 1000, y: CGFloat($0.top) / CGFloat(height),
                          width: CGFloat($0.width) / 1000, height: CGFloat($0.height) / CGFloat(height)) }
    }

    private func draft(for kind: WindowZoneLayoutKind) -> WindowZoneLayout {
        drafts[kind] ?? WindowZoneLayout(kind: kind, zoneCount: kind == .focus ? 3 : WindowZoneLayout.defaultZoneCount)
    }

    private func addCustom(_ shape: WindowZoneCustomShape) {
        let layout = WindowZoneCustomLayout(id: UUID(), name: text.untitled, shape: shape)
        zones.updateConfiguration { $0.customLayouts.append(layout) }
        selection = .custom(layout.id)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selection {
            case .template(let kind):
                templateDetail(kind)
            case .custom(let id):
                if let index = zones.configuration.customLayouts.firstIndex(where: { $0.id == id }) {
                    customDetail(index)
                } else {
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    private func usageBar(layout: WindowZoneLayout) -> some View {
        HStack {
            Picker(text.quickKey, selection: quickKeyBinding(for: layout)) {
                Text(text.none).tag("")
                ForEach(0..<10, id: \.self) { Text("⌃⌥⇧\($0)").tag(String($0)) }
            }
            .frame(maxWidth: 240)
            Spacer()
            if perSpace, display?.space != nil {
                Toggle(text.currentSpaceOnly, isOn: $currentSpaceOnly)
            }
            Button(display?.layout.isSameLayout(as: layout) == true ? text.inUse : text.apply) {
                guard let display else { return }
                zones.apply(layout, toDisplay: display.id, currentSpaceOnly: currentSpaceOnly)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func quickKeyBinding(for layout: WindowZoneLayout) -> Binding<String> {
        Binding(
            get: { zones.configuration.quickLayouts.first { $0.value.isSameLayout(as: layout) }?.key ?? "" },
            set: { key in
                zones.updateConfiguration { configuration in
                    configuration.quickLayouts = configuration.quickLayouts.filter { !$0.value.isSameLayout(as: layout) }
                    if !key.isEmpty { configuration.quickLayouts[key] = layout }
                }
                WindowLayoutService.shared.syncWithPreferences()
            })
    }

    private func templateDetail(_ kind: WindowZoneLayoutKind) -> some View {
        let layout = draft(for: kind)
        let binding = Binding<WindowZoneLayout>(get: { draft(for: kind) }, set: { drafts[kind] = $0 })
        return VStack(alignment: .leading, spacing: 12) {
            Text(WindowZonesLayoutName.name(of: kind, text: text)).font(.title2)
            WindowZonesPreview(zones: previewZones(layout, custom: []), aspect: aspect, numbered: true)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Form {
                Stepper("\(text.zoneCount): \(layout.zoneCount)", value: binding.zoneCount,
                        in: 1...WindowZoneLayout.maximumZoneCount)
                spacingControls(spacing: binding.spacing, show: binding.showSpacing, radius: binding.sensitivityRadius)
                    .disabled(kind == .focus)
            }
            .formStyle(.grouped)
            .frame(height: 170)
            usageBar(layout: layout)
        }
    }

    private func spacingControls(spacing: Binding<Int>, show: Binding<Bool>, radius: Binding<Int>) -> some View {
        Group {
            Toggle(text.spacing, isOn: show)
            if show.wrappedValue {
                Stepper("\(text.spacing): \(spacing.wrappedValue)", value: spacing, in: 0...100, step: 2)
            }
            Stepper("\(text.sensitivity): \(radius.wrappedValue)", value: radius, in: 0...100, step: 5)
        }
    }

    private func customDetail(_ index: Int) -> some View {
        let custom = zones.configuration.customLayouts[index]
        let binding = Binding<WindowZoneCustomLayout>(
            get: { zones.configuration.customLayouts.indices.contains(index)
                ? zones.configuration.customLayouts[index] : custom },
            set: { value in
                zones.updateConfiguration { configuration in
                    guard configuration.customLayouts.indices.contains(index) else { return }
                    configuration.customLayouts[index] = value
                    // A layout in use follows its own spacing and zone count.
                    let refreshed = WindowZoneLayout.custom(value)
                    configuration.displayLayouts = configuration.displayLayouts.mapValues {
                        $0.customID == value.id ? refreshed : $0
                    }
                    configuration.spaceLayouts = configuration.spaceLayouts.mapValues {
                        $0.mapValues { $0.customID == value.id ? refreshed : $0 }
                    }
                    configuration.quickLayouts = configuration.quickLayouts.mapValues {
                        $0.customID == value.id ? refreshed : $0
                    }
                }
            })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(text.name, text: binding.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button(text.duplicate) {
                    var copy = custom
                    copy.id = UUID()
                    copy.name = "\(custom.name) 2"
                    zones.updateConfiguration { $0.customLayouts.append(copy) }
                    selection = .custom(copy.id)
                }
                Button(text.delete, role: .destructive) {
                    zones.updateConfiguration { $0.removeCustomLayout(custom.id) }
                    selection = .template(.priorityGrid)
                }
            }
            switch custom.shape {
            case .grid(let grid):
                WindowZonesGridEditor(grid: grid, aspect: aspect, mergeTitle: text.merge, help: text.gridHelp) {
                    var next = binding.wrappedValue
                    next.shape = .grid($0)
                    binding.wrappedValue = next
                }
            case .canvas(let canvas):
                WindowZonesCanvasEditor(canvas: canvas, aspect: aspect, addTitle: text.addZone,
                                        deleteTitle: text.delete, help: text.canvasHelp) {
                    var next = binding.wrappedValue
                    next.shape = .canvas($0)
                    binding.wrappedValue = next
                }
            }
            HStack {
                if case .grid = custom.shape {
                    Toggle(text.spacing, isOn: binding.showSpacing)
                    Stepper("\(binding.wrappedValue.spacing)", value: binding.spacing, in: 0...100, step: 2)
                        .disabled(!custom.showSpacing)
                }
                Stepper("\(text.sensitivity): \(custom.sensitivityRadius)", value: binding.sensitivityRadius,
                        in: 0...100, step: 5)
            }
            usageBar(layout: .custom(custom))
        }
    }
}

/// A layout's zones drawn small, as fractions of the display.
struct WindowZonesPreview: View {
    let zones: [CGRect]
    let aspect: CGFloat
    var numbered = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                ForEach(Array(zones.enumerated()), id: \.offset) { index, zone in
                    let rect = CGRect(x: zone.minX * proxy.size.width, y: zone.minY * proxy.size.height,
                                      width: zone.width * proxy.size.width, height: zone.height * proxy.size.height)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
                        .overlay(numbered ? Text("\(index + 1)").font(.title3.weight(.semibold)) : nil)
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Splits, merges and border drags on a custom grid.
struct WindowZonesGridEditor: View {
    let grid: WindowZoneGrid
    let aspect: CGFloat
    let mergeTitle: String
    let help: String
    let onChange: (WindowZoneGrid) -> Void
    @State private var selected: Set<Int> = []
    @State private var dragStart: WindowZoneGrid?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let size = proxy.size
                let zones = WindowZoneGeometry.grid(width: Int(size.width), height: Int(size.height),
                                                    grid: grid, spacing: 0) ?? []
                ZStack(alignment: .topLeading) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, zone in
                        Rectangle()
                            .fill(Color.accentColor.opacity(selected.contains(index) ? 0.6 : 0.25))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                            .overlay(Text("\(index + 1)").font(.title3.weight(.semibold)))
                            .frame(width: CGFloat(zone.width), height: CGFloat(zone.height))
                            .offset(x: CGFloat(zone.left), y: CGFloat(zone.top))
                            .onTapGesture(coordinateSpace: .named("grid")) { location in
                                tap(zone: index, at: location, size: size)
                            }
                    }
                    borders(size: size)
                }
                .coordinateSpace(name: "grid")
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(help).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(mergeTitle) {
                    onChange(WindowZoneGridEditor.merge(grid, zones: selected))
                    selected = []
                }
                .disabled(selected.count < 2)
            }
        }
        .onChange(of: grid) { _, _ in selected = selected.filter { $0 < grid.zoneCount } }
    }

    private func tap(zone: Int, at location: CGPoint, size: CGSize) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selected.contains(zone) { selected.remove(zone) } else { selected.insert(zone) }
            return
        }
        selected = []
        let vertical = flags.contains(.option)
        let fraction = vertical ? location.x / max(size.width, 1) : location.y / max(size.height, 1)
        onChange(WindowZoneGridEditor.split(grid, zone: zone, at: fraction, horizontal: !vertical))
    }

    /// One handle per border segment that separates two different zones.
    private func borders(size: CGSize) -> some View {
        let rowEdges = edges(grid.rowPercents, total: size.height)
        let columnEdges = edges(grid.columnPercents, total: size.width)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<max(grid.rows - 1, 0), id: \.self) { row in
                ForEach(0..<grid.columns, id: \.self) { column in
                    if grid.cells[row][column] != grid.cells[row + 1][column] {
                        handle(horizontal: true, index: row, total: size.height)
                            .frame(width: columnEdges[column + 1] - columnEdges[column], height: 8)
                            .offset(x: columnEdges[column], y: rowEdges[row + 1] - 4)
                    }
                }
            }
            ForEach(0..<max(grid.columns - 1, 0), id: \.self) { column in
                ForEach(0..<grid.rows, id: \.self) { row in
                    if grid.cells[row][column] != grid.cells[row][column + 1] {
                        handle(horizontal: false, index: column, total: size.width)
                            .frame(width: 8, height: rowEdges[row + 1] - rowEdges[row])
                            .offset(x: columnEdges[column + 1] - 4, y: rowEdges[row])
                    }
                }
            }
        }
    }

    private func edges(_ percents: [Int], total: CGFloat) -> [CGFloat] {
        var running = 0
        return [0] + percents.map { percent -> CGFloat in
            running += percent
            return CGFloat(running) / CGFloat(WindowZoneGrid.multiplier) * total
        }
    }

    private func handle(horizontal: Bool, index: Int, total: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .overlay(Rectangle().fill(Color.accentColor).frame(width: horizontal ? nil : 2,
                                                               height: horizontal ? 2 : nil))
            .onHover { inside in
                if inside { (horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() }
                else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let start = dragStart ?? grid
                if dragStart == nil { dragStart = grid }
                let moved = horizontal ? value.translation.height : value.translation.width
                let delta = Int((moved / max(total, 1)) * CGFloat(WindowZoneGrid.multiplier))
                onChange(WindowZoneGridEditor.moveBorder(start, after: index, horizontal: horizontal, delta: delta))
            }.onEnded { _ in dragStart = nil })
    }
}

/// Free-form zones: drag to move, drag the corner to resize.
struct WindowZonesCanvasEditor: View {
    let canvas: WindowZoneCanvas
    let aspect: CGFloat
    let addTitle: String
    let deleteTitle: String
    let help: String
    let onChange: (WindowZoneCanvas) -> Void
    @State private var selected: Int?
    @State private var dragStart: WindowZoneRect?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let sx = proxy.size.width / CGFloat(max(canvas.referenceWidth, 1))
                let sy = proxy.size.height / CGFloat(max(canvas.referenceHeight, 1))
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.secondary.opacity(0.12))
                        .onTapGesture { selected = nil }
                    ForEach(Array(canvas.zones.enumerated()), id: \.offset) { index, zone in
                        zoneView(index: index, zone: zone, sx: sx, sy: sy)
                    }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(help).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(addTitle) {
                    var next = canvas
                    let w = canvas.referenceWidth, h = canvas.referenceHeight
                    let offset = (canvas.zones.count % 5) * w / 40
                    next.zones.append(WindowZoneRect(left: w / 4 + offset, top: h / 4 + offset,
                                                     right: w * 3 / 4 + offset, bottom: h * 3 / 4 + offset))
                    onChange(next)
                    selected = next.zones.count - 1
                }
                Button(deleteTitle) {
                    guard let selected, canvas.zones.indices.contains(selected) else { return }
                    var next = canvas
                    next.zones.remove(at: selected)
                    onChange(next)
                    self.selected = nil
                }
                .disabled(selected == nil)
            }
        }
    }

    private func zoneView(index: Int, zone: WindowZoneRect, sx: CGFloat, sy: CGFloat) -> some View {
        let isSelected = selected == index
        return Rectangle()
            .fill(Color.accentColor.opacity(isSelected ? 0.55 : 0.3))
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: isSelected ? 2 : 1))
            .overlay(Text("\(index + 1)").font(.title3.weight(.semibold)))
            .overlay(alignment: .bottomTrailing) {
                Rectangle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        update(index, value.translation, sx: sx, sy: sy, resizing: true)
                    }.onEnded { _ in dragStart = nil })
            }
            .frame(width: CGFloat(zone.width) * sx, height: CGFloat(zone.height) * sy)
            .offset(x: CGFloat(zone.left) * sx, y: CGFloat(zone.top) * sy)
            .onTapGesture { selected = index }
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                update(index, value.translation, sx: sx, sy: sy, resizing: false)
            }.onEnded { _ in dragStart = nil })
    }

    private func update(_ index: Int, _ translation: CGSize, sx: CGFloat, sy: CGFloat, resizing: Bool) {
        guard canvas.zones.indices.contains(index) else { return }
        selected = index
        let start = dragStart ?? canvas.zones[index]
        if dragStart == nil { dragStart = start }
        let dx = Int(translation.width / max(sx, 0.0001)), dy = Int(translation.height / max(sy, 0.0001))
        let width = canvas.referenceWidth, height = canvas.referenceHeight
        var zone = start
        if resizing {
            zone.right = min(max(start.right + dx, start.left + width / 20), width)
            zone.bottom = min(max(start.bottom + dy, start.top + height / 20), height)
        } else {
            let left = min(max(start.left + dx, 0), width - start.width)
            let top = min(max(start.top + dy, 0), height - start.height)
            zone = WindowZoneRect(left: left, top: top, right: left + start.width, bottom: top + start.height)
        }
        var next = canvas
        next.zones[index] = zone
        onChange(next)
    }
}
