// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The three groups are always visible; permission gates actions, not discovery.
struct MenuBarOrganizerEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarOrganizerService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.menuBarHiderEnabled) private var hiderEnabled = false
    @State private var pageVisible = false
    @State private var query = ""
    @State private var hoveredItem: MenuBarItemIdentity?
    @State private var targetedSection: MenuBarOrganizerSection?
    private var text: MenuBarOrganizerStrings { FeatureStrings.menuBarOrganizer(l10n.language) }
    private var labels: MenuBarEditorStrings { FeatureStrings.menuBarEditor(l10n.language) }
    private var hiderText: MenuBarHiderStrings { FeatureStrings.menuBarHider(l10n.language) }
    private var canArrange: Bool { hiderEnabled && service.isRunning && permissions.accessibility && !service.isBusy }

    var body: some View {
        SettingsCard(title: text.arrange) {
            Text(labels.inventory).font(.callout).foregroundStyle(.secondary)
            if !MenuBarOrganizerPolicy.supportsAdvancedBackend {
                Text(text.unsupported).font(.caption).foregroundStyle(.secondary)
            } else if hiderEnabled && !permissions.accessibility {
                PermissionRow(kind: .accessibility)
                Text(text.permission).font(.caption).foregroundStyle(.secondary)
            }
            if !MenuBarOrganizerPolicy.conflictingManagers().isEmpty {
                Text(text.conflict).font(.caption).foregroundStyle(.orange)
            }
            if service.inventoryUnavailable {
                Text(labels.unavailable).font(.caption).foregroundStyle(.secondary)
            }
            if MenuBarOrganizerPolicy.supportsAdvancedBackend && hiderEnabled && !permissions.screenRecording {
                PermissionRow(kind: .screenRecording)
                Text(labels.previewPermission).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField(text.placeholder, text: $query).textFieldStyle(.roundedBorder)
                Button(text.refresh) { service.refresh() }.disabled(!service.isRunning || service.isBusy)
                Button(text.undo) { service.undoLastMove() }.disabled(!canArrange || !service.canUndo)
            }
            VStack(spacing: 16) {
                ForEach(MenuBarOrganizerSection.allCases) { section in
                    category(section)
                }
            }
            HStack {
                Button(text.drawer) { service.showDrawer() }
                Button(text.search) { service.showDrawer(search: true) }
                if service.isBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            .disabled(!canArrange)
            if let message = service.message {
                Text(message).font(.caption).foregroundStyle(.secondary).accessibilityLabel(message)
            }
        }
        .onAppear { pageVisible = true; service.setEditorVisible(true) }
        .onDisappear { pageVisible = false; service.setEditorVisible(false) }
        .onReceive(SettingsWindowVisibility.shared.$isVisible) { if pageVisible { service.setEditorVisible($0) } }
    }

    private func title(_ section: MenuBarOrganizerSection) -> String {
        switch section {
        case .visible: return hiderText.diagramVisible
        case .hidden: return hiderText.diagramHidden
        case .alwaysHidden: return hiderText.diagramAlwaysHidden
        }
    }

    private func caption(_ section: MenuBarOrganizerSection) -> String {
        switch section {
        case .visible: return labels.visible
        case .hidden: return labels.hidden
        case .alwaysHidden: return labels.alwaysHidden
        }
    }

    private func category(_ section: MenuBarOrganizerSection) -> some View {
        let items = MenuBarOrganizerSupport.orderedItems(service.items, in: section)
        let matches = items.filter { MenuBarOrganizerPolicy.searchScore(query: query, name: $0.displayName) != nil }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(section)).font(.subheadline.weight(.semibold))
                Text(items.count, format: .number).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(caption(section)).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        if matches.isEmpty {
                            Text(query.isEmpty ? labels.drop : text.empty)
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(matches) { item in itemCell(item, section: section) }
                            // A trailing landing area also permits appending after the last icon.
                            Color.clear.frame(width: 20, height: 32)
                        }
                    }
                    .frame(minWidth: max(0, geometry.size.width - 12), minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            }
            .frame(height: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(targetedSection == section ? Color.accentColor : Color.primary.opacity(0.14),
                                  lineWidth: targetedSection == section ? 2 : 1)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { values, _ in
                drop(values, before: nil, section: section)
            } isTargeted: { targeted in
                if targeted { targetedSection = section }
                else if targetedSection == section { targetedSection = nil }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title(section))
    }

    @ViewBuilder private func itemCell(_ item: ManagedMenuBarItem, section: MenuBarOrganizerSection) -> some View {
        let tile = MenuBarItemThumbnail(item: item).frame(width: min(140, max(18, item.frame.width)), height: 24)
                .overlay(alignment: .bottomTrailing) {
                    if !item.isMovable {
                        Image(systemName: "lock.fill").font(.system(size: 6))
                            .padding(1).background(.background, in: Circle())
                    }
                }
        .frame(width: min(148, max(32, item.frame.width + 8)), height: 32)
        .background(hoveredItem == item.id ? Color.primary.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredItem = item.id }
            else if hoveredItem == item.id { hoveredItem = nil }
        }
        .help(item.isMovable ? item.displayName : "\(item.displayName) — \(labels.locked)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            ForEach(MenuBarOrganizerSection.allCases) { destination in
                Button(title(destination)) { service.move(id: item.id, before: nil, to: destination) }
                    .disabled(!canArrange || !item.isMovable || destination == section)
            }
        }
        .dropDestination(for: String.self) { values, _ in drop(values, before: item.id, section: section) }
        if canArrange && item.isMovable {
            tile.draggable(encoded(item.id))
        } else { tile }
    }

    private func encoded(_ id: MenuBarItemIdentity) -> String {
        (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func drop(_ values: [String], before target: MenuBarItemIdentity?, section: MenuBarOrganizerSection) -> Bool {
        guard canArrange, values.count == 1, let value = values.first?.data(using: .utf8),
              let id = try? JSONDecoder().decode(MenuBarItemIdentity.self, from: value),
              service.items.contains(where: { $0.id == id && $0.isMovable }) else { return false }
        service.move(id: id, before: target, to: section)
        return true
    }
}

struct MenuBarOrganizerOptions: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarOrganizerService.shared
    @AppStorage(DefaultsKey.menuBarHiderEnabled) private var hiderEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerSpacing) private var spacing = 16
    @AppStorage(DefaultsKey.menuBarOrganizerAppearance) private var appearance = false
    @AppStorage(DefaultsKey.menuBarOrganizerGradient) private var gradient = false
    @AppStorage(DefaultsKey.menuBarOrganizerBorder) private var border = false
    @AppStorage(DefaultsKey.menuBarOrganizerShadow) private var shadow = false
    @AppStorage(DefaultsKey.menuBarOrganizerRounded) private var rounded = true
    @AppStorage(DefaultsKey.menuBarOrganizerSplit) private var split = true
    @AppStorage(DefaultsKey.menuBarOrganizerFirstColor) private var first = "#303038"
    @AppStorage(DefaultsKey.menuBarOrganizerSecondColor) private var second = "#606070"
    @AppStorage(DefaultsKey.menuBarOrganizerOpacity) private var opacity = 0.25
    private var text: MenuBarOrganizerStrings { FeatureStrings.menuBarOrganizer(l10n.language) }

    var body: some View {
        SettingsCard(title: text.spacing) {
            Text(text.spacingCaption).font(.caption).foregroundStyle(.secondary)
            HStack {
                Slider(value: Binding(get: { Double(spacing) }, set: { spacing = Int($0.rounded()) }), in: 4...32, step: 1)
                    .accessibilityLabel(text.spacing)
                Text("\(MenuBarGlobalSpacing.sanitized(spacing)) pt").monospacedDigit().frame(width: 48)
                Button(text.apply) { service.applySpacing() }
                    .disabled(!hiderEnabled || !MenuBarOrganizerPolicy.supportsAdvancedBackend)
                Button(text.restore) { service.applySpacing(restore: true) }
                    .disabled(!service.canRestoreSpacing)
            }
        }
        SettingsCard(title: text.appearance) {
            SettingsRow(symbol: "paintpalette", title: text.appearance) {
                Toggle(text.enable, isOn: $appearance).labelsHidden()
            }
            if appearance {
                MenuBarAppearancePreview(style: MenuBarAppearanceStyle()).frame(height: 28)
                HStack {
                    ColorPicker(text.firstColor, selection: colorBinding($first), supportsOpacity: false)
                    if gradient { ColorPicker(text.secondColor, selection: colorBinding($second), supportsOpacity: false) }
                }
                HStack {
                    Text(text.opacity)
                    Slider(value: $opacity, in: 0...1).accessibilityLabel(text.opacity)
                }
                HStack {
                    Toggle(text.gradient, isOn: $gradient)
                    Toggle(text.border, isOn: $border)
                    Toggle(text.shadow, isOn: $shadow)
                }
                HStack {
                    Toggle(text.rounded, isOn: $rounded)
                    Toggle(text.split, isOn: $split)
                }
            }
        }
        .disabled(!hiderEnabled)
        .onChange(of: appearance) { _, _ in service.syncWithPreferences() }
        .onChange(of: gradient) { _, _ in service.syncWithPreferences() }
        .onChange(of: border) { _, _ in service.syncWithPreferences() }
        .onChange(of: shadow) { _, _ in service.syncWithPreferences() }
        .onChange(of: rounded) { _, _ in service.syncWithPreferences() }
        .onChange(of: split) { _, _ in service.syncWithPreferences() }
        .onChange(of: first) { _, _ in service.syncWithPreferences() }
        .onChange(of: second) { _, _ in service.syncWithPreferences() }
        .onChange(of: opacity) { _, _ in service.syncWithPreferences() }
    }

    private func colorBinding(_ storage: Binding<String>) -> Binding<Color> {
        Binding(get: { MenuBarAppearanceStyle.color(storage.wrappedValue) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            storage.wrappedValue = MenuBarUsageBarSupport.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        })
    }
}
