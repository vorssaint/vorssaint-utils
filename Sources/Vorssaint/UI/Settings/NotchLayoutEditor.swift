// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchLayoutEditor: View {
    @Binding var configuration: NotchQuickAccessConfiguration
    @Binding var size: String
    @Binding var width: Double
    @Binding var height: Double
    var editContents: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addingSide: NotchQuickAccessSide?
    @State private var editingID: UUID?
    @State private var editingName = ""
    @State private var draggingID: UUID?
    @State private var translation = CGSize.zero
    @State private var dragLocation: CGPoint?
    @State private var resizeStart: CGSize?
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let frame = islandFrame(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22).fill(.quaternary.opacity(0.35))
                    if draggingID != nil {
                        ForEach(NotchQuickAccessSide.allCases, id: \.self) { side in
                            let target = dropFrame(side, island: frame)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(target.contains(dragLocation ?? .zero) ? 0.15 : 0.04))
                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                                .frame(width: target.width, height: target.height)
                                .position(x: target.midX, y: target.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    islandPreview
                        .frame(width: frame.width, height: frame.height)
                        .background { NotchShape(attached: true, radius: 22).fill(.black) }
                        .position(x: frame.midX, y: frame.midY)
                    ForEach(NotchQuickAccessSide.allCases, id: \.self) { side in
                        let items = configuration.buttons.filter { $0.side == side }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, button in
                            let center = point(index, count: items.count, side: side, island: frame)
                            bubble(button)
                                .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("island.editor"))
                                    .onChanged { value in
                                        editingID = nil
                                        draggingID = button.id
                                        translation = value.translation
                                        dragLocation = value.location
                                    }
                                    .onEnded { value in
                                        move(button, at: value.location, island: frame)
                                        draggingID = nil; translation = .zero; dragLocation = nil
                                    })
                                .offset(draggingID == button.id ? translation : .zero)
                                .position(center)
                                .zIndex(draggingID == button.id ? 3 : 1)
                        }
                        if items.count < NotchQuickAccessConfiguration.maximumPerSide {
                            Button { addingSide = side } label: {
                                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .background(.background, in: Circle())
                                    .overlay { Circle().strokeBorder(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                            }
                            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                            .help(editor.addButton)
                            .accessibilityLabel(editor.addButton + ", " + side.title(l10n))
                            .popover(isPresented: Binding(get: { addingSide == side }, set: { if !$0 { addingSide = nil } }),
                                     arrowEdge: side == .left ? .trailing : side == .right ? .leading : .top) {
                                NotchActionChooser(title: editor.addButton) { action in
                                    guard configuration.buttons.filter({ $0.side == side }).count < NotchQuickAccessConfiguration.maximumPerSide else { return }
                                    configuration.buttons.append(NotchQuickButton(action: action, side: side))
                                    addingSide = nil
                                }
                            }
                            .position(point(items.count, count: items.count, side: side, island: frame))
                        }
                    }
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.white.opacity(0.17), in: Circle())
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("island.editor")).onChanged { value in
                            if resizeStart == nil { resizeStart = CGSize(width: actualWidth, height: NotchSize.clamped(height, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)) }
                            guard let start = resizeStart else { return }
                            size = NotchSize.custom.rawValue
                            width = NotchSize.clamped(Double(start.width + value.translation.width / 0.6), to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
                            height = NotchSize.clamped(Double(start.height + value.translation.height / 0.35), to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
                        }.onEnded { _ in resizeStart = nil })
                        .position(x: frame.maxX - NotchLayout.shoulder - 17, y: frame.maxY - 17)
                        .accessibilityLabel(text.size)
                }
                .coordinateSpace(name: "island.editor")
            }
            .frame(height: 292)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: configuration)
            Text(editor.layoutHint).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actualWidth: CGFloat {
        switch NotchSize(rawValue: size) ?? .compact {
        case .compact: return 480
        case .spacious: return 560
        case .custom: return NotchSize.clamped(width, to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
        }
    }

    private func islandFrame(in canvas: CGSize) -> CGRect {
        let w = min(canvas.width - 112, actualWidth * 0.6)
        let h = min(210, max(150, NotchSize.clamped(height, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight) * 0.35))
        return CGRect(x: (canvas.width - w) / 2, y: 20, width: w, height: h)
    }

    private func point(_ index: Int, count: Int, side: NotchQuickAccessSide, island: CGRect) -> CGPoint {
        let slots = max(1, count)
        switch side {
        case .left: return CGPoint(x: island.minX - 12, y: island.minY + 30 + CGFloat(index) * 40)
        case .right: return CGPoint(x: island.maxX + 12, y: island.minY + 30 + CGFloat(index) * 40)
        case .bottom: return CGPoint(x: island.midX + (CGFloat(index) - CGFloat(slots - 1) / 2) * 40, y: island.maxY + 26)
        }
    }

    private func dropFrame(_ side: NotchQuickAccessSide, island: CGRect) -> CGRect {
        switch side {
        case .left: return CGRect(x: island.minX - 48, y: island.minY, width: 62, height: island.height)
        case .right: return CGRect(x: island.maxX - 14, y: island.minY, width: 62, height: island.height)
        case .bottom: return CGRect(x: island.minX, y: island.maxY, width: island.width, height: 58)
        }
    }

    private func move(_ button: NotchQuickButton, at point: CGPoint, island: CGRect) {
        guard let side = NotchQuickAccessSide.allCases.first(where: { dropFrame($0, island: island).contains(point) }) else { return }
        let siblings = configuration.buttons.filter { $0.side == side && $0.id != button.id }
        let target = siblings.enumerated().first { index, _ in
            let location = self.point(index, count: siblings.count, side: side, island: island)
            return side == .bottom ? location.x > point.x : location.y > point.y
        }?.element.id
        configuration.move(button.id, to: side, before: target)
    }

    private func bubble(_ button: NotchQuickButton) -> some View {
        let title = button.label.isEmpty ? button.action?.title(l10n) ?? editor.editButton : button.label
        return Button { editingName = button.label; editingID = button.id } label: {
            Image(systemName: button.action?.symbol ?? "questionmark")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(.black, in: Circle())
                .overlay { Circle().strokeBorder(editingID == button.id ? Color.accentColor : .white.opacity(0.2), lineWidth: 1.5) }
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(editor.editButton + ", " + title)
        .popover(isPresented: Binding(get: { editingID == button.id }, set: { if !$0 { editingID = nil } }),
                 arrowEdge: button.side == .left ? .trailing : button.side == .right ? .leading : .top) {
            VStack(alignment: .leading, spacing: 14) {
                Text(editor.editButton).font(.headline)
                TextField(editor.buttonName, text: $editingName, prompt: Text(button.action?.title(l10n) ?? ""))
                    .onChange(of: editingName) { _, value in
                        if let index = configuration.buttons.firstIndex(where: { $0.id == button.id }) { configuration.buttons[index].label = value }
                    }
                Picker(editor.position, selection: Binding(get: {
                    configuration.buttons.first { $0.id == button.id }?.side ?? button.side
                }, set: { configuration.move(button.id, to: $0) })) {
                    ForEach(NotchQuickAccessSide.allCases, id: \.self) { side in
                        Text(side.title(l10n)).tag(side)
                            .disabled(side != button.side && configuration.buttons.filter { $0.side == side }.count >= NotchQuickAccessConfiguration.maximumPerSide)
                    }
                }.pickerStyle(.segmented)
                HStack {
                    Button(FeatureStrings.clipboard(l10n.language).moveUp) { reorder(button.id, by: -1) }
                    Button(FeatureStrings.clipboard(l10n.language).moveDown) { reorder(button.id, by: 1) }
                }.controlSize(.small)
                NotchActionChooser(title: "", selected: button.action) { action in
                    if let index = configuration.buttons.firstIndex(where: { $0.id == button.id }) { configuration.buttons[index].actionID = action.id }
                }
                Button(editor.removeButton, role: .destructive) {
                    editingID = nil
                    configuration.buttons.removeAll { $0.id == button.id }
                }
            }.padding(16).frame(width: 340)
        }
    }

    private func reorder(_ id: UUID, by offset: Int) {
        guard let item = configuration.buttons.first(where: { $0.id == id }) else { return }
        let items = configuration.buttons.filter { $0.side == item.side }
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset),
              let from = configuration.buttons.firstIndex(where: { $0.id == id }),
              let to = configuration.buttons.firstIndex(where: { $0.id == items[index + offset].id }) else { return }
        configuration.buttons.swapAt(from, to)
    }

    private var islandPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.controls).font(.system(size: 12, weight: .semibold))
            Button(action: editContents) {
                HStack(spacing: 10) {
                    ForEach([NotchControlItem.volume, .brightness]) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(item.title(l10n), systemImage: item.symbol).font(.system(size: 10, weight: .medium))
                            NotchMeter(value: item == .volume ? 0.45 : 0.65, height: 12)
                        }.padding(10).frame(maxWidth: .infinity)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.buttonStyle(.plain)
            Button(action: editContents) {
                Label(editor.content, systemImage: "square.grid.2x2")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(8)
                    .background(.white.opacity(0.06), in: Capsule())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
        }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 12).foregroundStyle(.white)
    }
}

struct NotchActionChooser: View {
    let title: String
    var selected: NotchQuickAction?
    let choose: (NotchQuickAction) -> Void
    @ObservedObject private var l10n = L10n.shared
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty { Text(title).font(.headline) }
            TextField(editor.findAction, text: $query).textFieldStyle(.roundedBorder).focused($searching)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !NotchQuickAction.optionalActions.contains(where: { matchesQuery($0) }) {
                        Text(FeatureStrings.clipboard(l10n.language).noResults)
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                    }
                    group(editor.sectionActions, actions: [.explore, .settings] + NotchModule.allCases.map(NotchQuickAction.module))
                    group(editor.quickActions, actions: [.pin] + NotchControlItem.allCases.filter { $0 != .volume && $0 != .brightness }.map(NotchQuickAction.control))
                }.padding(2)
            }.frame(height: 200)
        }.padding(title.isEmpty ? 0 : 16).frame(width: title.isEmpty ? nil : 340)
            .onAppear { searching = !title.isEmpty }
    }

    private func matchesQuery(_ action: NotchQuickAction) -> Bool {
        let term = CommandBarSearch.normalized(query)
        return term.isEmpty || CommandBarSearch.normalized(action.title(l10n) + " " + action.id).contains(term)
    }

    @ViewBuilder private func group(_ title: String, actions: [NotchQuickAction]) -> some View {
        let matches = actions.filter(matchesQuery)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(matches) { action in
                        Button { choose(action) } label: {
                            Label(action.title(l10n), systemImage: action.symbol)
                                .font(.system(size: 11)).lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).padding(.horizontal, 8)
                                .background(selected == action ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).disabled(!action.isAvailable())
                    }
                }
            }
        }
    }
}

extension NotchQuickAccessSide {
    func title(_ l10n: L10n) -> String {
        let text = FeatureStrings.notch(l10n.language)
        switch self {
        case .left: return text.quickAccessLeft
        case .right: return text.quickAccessRight
        case .bottom: return FeatureStrings.notchEditor(l10n.language).bottom
        }
    }
}
