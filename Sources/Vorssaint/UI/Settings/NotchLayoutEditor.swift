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
                let scale = scale(in: proxy.size)
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
                    // Laid out at the island's real size and scaled down, so the
                    // silhouette, type and spacing keep the proportions on screen.
                    islandPreview
                        .background {
                            NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: actualHeight)).fill(.black)
                        }
                        .scaleEffect(scale)
                        .frame(width: frame.width, height: frame.height)
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
                    // A grip on the corner, clear of the page inside the silhouette.
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(.background, in: Circle())
                        .overlay { Circle().strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("island.editor")).onChanged { value in
                            if resizeStart == nil { resizeStart = CGSize(width: actualWidth, height: actualHeight) }
                            guard let start = resizeStart else { return }
                            size = NotchSize.custom.rawValue
                            width = NotchSize.clamped(Double(start.width + value.translation.width / scale), to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
                            height = NotchSize.clamped(Double(start.height + value.translation.height / scale), to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
                        }.onEnded { _ in resizeStart = nil })
                        // A short island slides the grip below the third right slot.
                        .position(x: frame.maxX - 3, y: max(frame.maxY - 3, frame.minY + 139))
                        .accessibilityLabel(text.size)
                }
                .coordinateSpace(name: "island.editor")
            }
            .frame(height: Self.canvasHeight)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: configuration)
            Text(editor.layoutHint).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The preview keeps the island's real proportions at half size, so the
    /// canvas fits the tallest custom island with its bottom drop zone below.
    private static let previewScale: CGFloat = 0.5
    private static let canvasHeight: CGFloat = NotchSize.heightRange.upperBound * previewScale + 20 + 58 + 2
    private var layout: NotchSize { NotchSize(rawValue: size) ?? .compact }
    private var actualWidth: CGFloat {
        NotchLayout.preferredWidth(layout, custom: NotchSize.clamped(width, to: NotchSize.widthRange, fallback: NotchSize.defaultWidth))
    }
    private var actualHeight: CGFloat {
        NotchLayout.nominalHeight(layout, custom: NotchSize.clamped(height, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight))
    }

    /// A narrow window shrinks the whole island rather than only its width.
    private func scale(in canvas: CGSize) -> CGFloat {
        min(Self.previewScale, max(0.2, (canvas.width - 112) / actualWidth))
    }

    private func islandFrame(in canvas: CGSize) -> CGRect {
        let scale = scale(in: canvas)
        let w = actualWidth * scale
        let h = actualHeight * scale
        return CGRect(x: (canvas.width - w) / 2, y: 20, width: w, height: h)
    }

    /// Buttons float clear of the silhouette, as the real ones do.
    private func point(_ index: Int, count: Int, side: NotchQuickAccessSide, island: CGRect) -> CGPoint {
        let slots = max(1, count)
        switch side {
        case .left: return CGPoint(x: island.minX - 18, y: island.minY + 30 + CGFloat(index) * 40)
        case .right: return CGPoint(x: island.maxX + 18, y: island.minY + 30 + CGFloat(index) * 40)
        case .bottom: return CGPoint(x: island.midX + (CGFloat(index) - CGFloat(slots - 1) / 2) * 40, y: island.maxY + 24)
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

    /// The home page as the island lays it out: the same items, rules and
    /// components as the real Controls page, at the island's real size.
    private var islandPreview: some View {
        let items = NotchSupport.controls()
        let levels = items.filter { $0 == .volume || $0 == .brightness }
        let shortcuts = items.filter { $0 != .volume && $0 != .brightness && $0 != .music }
        let contentWidth = max(0, actualWidth - NotchLayout.horizontalInset * 2)
        let contentHeight = max(0, actualHeight - NotchLayout.nominalContentTop - NotchLayout.chromeHeight)
        let controls = NotchLayout.controls(hasCards: items.contains(.music) || !levels.isEmpty,
                                            shortcutCount: shortcuts.count, width: contentWidth, height: contentHeight)
        return Button(action: editContents) {
            Color.clear.contentShape(NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: actualHeight)))
        }
        .buttonStyle(.plain)
        .help(editor.content)
        .accessibilityLabel(editor.content)
        .overlay {
            VStack(spacing: NotchLayout.spacing) {
                HStack {
                    Text(text.controls).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35)).frame(width: 28, height: 28)
                }
                .frame(height: NotchLayout.headerHeight)
                VStack(spacing: NotchLayout.rowSpacing) {
                    if items.isEmpty {
                        NotchEmptyView(symbol: NotchModule.controls.symbol, message: text.empty)
                    } else {
                        if controls.cardRow > 0 { cards(levels, music: items.contains(.music), height: controls.cardRow) }
                        if controls.shortcutRows > 0 {
                            NotchRail(items: shortcuts, rows: controls.shortcutRows, itemWidth: NotchLayout.shortcutWidth,
                                      width: contentWidth, spacing: NotchLayout.shortcutSpacing,
                                      rowSpacing: NotchLayout.shortcutSpacing) { item in
                                NotchActionTile(symbol: item.symbol, title: item.title(l10n)) {}
                            }
                        }
                    }
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .clipped()
            }
            .padding(.horizontal, NotchLayout.horizontalInset)
            .padding(.top, NotchLayout.nominalContentTop)
            .padding(.bottom, NotchLayout.bottomInset)
            .frame(width: actualWidth, height: actualHeight, alignment: .top)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: actualWidth, height: actualHeight)
    }

    /// Playback shares the row with the levels, as on the island: two levels
    /// fold into one slim card beside it, a single one keeps its full card.
    private func cards(_ levels: [NotchControlItem], music: Bool, height: CGFloat) -> some View {
        HStack(spacing: NotchLayout.rowSpacing) {
            if music {
                musicCard(height: height)
                if levels.count > 1 {
                    VStack(spacing: 6) { ForEach(levels) { levelRow($0) } }
                        .padding(.horizontal, 12)
                        .frame(width: 160, height: height)
                        .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
                } else if let single = levels.first {
                    levelCard(single, height: height).frame(width: 160)
                }
            } else {
                ForEach(levels) { levelCard($0, height: height).frame(maxWidth: .infinity) }
            }
        }
        .frame(height: height)
    }

    private func musicCard(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            NotchArtwork(image: nil, size: max(40, height - 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(FeatureStrings.radialMenu(l10n.language).mediaNothingPlaying)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if height >= 84 {
                    Text(text.musicHint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
    }

    private func levelCard(_ item: NotchControlItem, height: CGFloat) -> some View {
        let showsDevice = height >= 88
        return VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: item.symbol).font(.system(size: 12, weight: .medium)).frame(width: 18, height: 18)
                Text(item.title(l10n)).lineLimit(1)
                Spacer(minLength: 0)
                Text(item == .volume ? "45%" : "65%").monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            NotchMeter(value: item == .volume ? 0.45 : 0.65, height: 22)
                .frame(height: 28)
            if showsDevice {
                HStack(spacing: 4) {
                    Text(l10n.s.mixerSystemOutputTitle).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showsDevice ? 10 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
    }

    private func levelRow(_ item: NotchControlItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbol).font(.system(size: 12, weight: .medium)).frame(width: 18, height: 18)
            NotchMeter(value: item == .volume ? 0.45 : 0.65, height: 18).frame(height: 24)
            Text(item == .volume ? "45%" : "65%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .frame(height: 28)
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
        guard action.isAvailable() else { return false }
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
