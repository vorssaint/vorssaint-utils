// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The zones part of the Window Layout page: the switch, how the overlay
/// looks and behaves, the keys, and the layout each display uses.
struct WindowZonesSettingsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var zones = WindowZonesService.shared
    @AppStorage(DefaultsKey.windowZonesEnabled) private var enabled = false
    @AppStorage(DefaultsKey.windowZonesShiftDrag) private var shiftDrag = true
    @AppStorage(DefaultsKey.windowZonesShowAllDisplays) private var showAllDisplays = false
    @AppStorage(DefaultsKey.windowZonesShowNumbers) private var showNumbers = true
    @AppStorage(DefaultsKey.windowZonesFillColor) private var fillColor = WindowZoneColors.standard.fill
    @AppStorage(DefaultsKey.windowZonesBorderColor) private var borderColor = WindowZoneColors.standard.border
    @AppStorage(DefaultsKey.windowZonesHighlightColor) private var highlightColor = WindowZoneColors.standard.highlight
    @AppStorage(DefaultsKey.windowZonesOpacity) private var opacity = WindowZoneColors.standard.opacity
    @AppStorage(DefaultsKey.windowZonesOverlapPolicy) private var overlapPolicy = WindowZoneOverlapPolicy.smallest.rawValue
    @AppStorage(DefaultsKey.windowZonesRestoreSize) private var restoreSize = true
    @AppStorage(DefaultsKey.windowZonesMoveNewWindows) private var moveNewWindows = true
    @AppStorage(DefaultsKey.windowZonesPerSpace) private var perSpace = false
    @AppStorage(DefaultsKey.windowZonesKeyboardEnabled) private var keyboardEnabled = true
    @AppStorage(DefaultsKey.windowZonesAcrossDisplays) private var acrossDisplays = false
    @AppStorage(DefaultsKey.windowZonesQuickSwitchEnabled) private var quickSwitch = true
    @AppStorage(DefaultsKey.windowZonesWheelSwitch) private var wheelSwitch = true
    @AppStorage(DefaultsKey.windowZonesEditorShortcut) private var editorShortcutRaw = GlobalShortcut.windowZonesEditorDefault.storageValue
    @State private var shortcutError: String?
    @State private var displays: [WindowZonesService.DisplaySummary] = []

    private var text: WindowZonesStrings { FeatureStrings.windowZones(l10n.language) }

    var body: some View {
        Group { content }
            .onAppear(perform: reloadDisplays)
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)) { _ in reloadDisplays() }
            .onReceive(zones.$configuration) { _ in reloadDisplays() }
    }

    @ViewBuilder
    private var content: some View {
        Section(text.sectionTitle) {
            Toggle(text.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in WindowLayoutService.shared.syncWithPreferences() }
            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled {
                ForEach(displays) { display in
                    Picker(displays.count > 1 ? "\(text.layout) – \(display.name)" : text.layout,
                           selection: layoutBinding(for: display)) {
                        ForEach(WindowZoneLayoutKind.templates) { kind in
                            Text(WindowZonesLayoutName.name(of: kind, text: text)).tag(LayoutChoice.template(kind))
                        }
                        Text(text.blank).tag(LayoutChoice.template(.blank))
                        if !zones.configuration.customLayouts.isEmpty {
                            Divider()
                            ForEach(zones.configuration.customLayouts) { layout in
                                Text(layout.name).tag(LayoutChoice.custom(layout.id))
                            }
                        }
                    }
                }
                Button(text.openEditor) { WindowZonesEditorWindow.shared.show() }
                Toggle(text.shiftDrag, isOn: $shiftDrag)
                Toggle(text.showAllDisplays, isOn: $showAllDisplays)
                Toggle(text.showNumbers, isOn: $showNumbers)
                Toggle(text.wheelSwitch, isOn: $wheelSwitch)
                Picker(text.overlap, selection: $overlapPolicy) {
                    Text(text.policySmallest).tag(WindowZoneOverlapPolicy.smallest.rawValue)
                    Text(text.policyLargest).tag(WindowZoneOverlapPolicy.largest.rawValue)
                    Text(text.policyPositional).tag(WindowZoneOverlapPolicy.positional.rawValue)
                    Text(text.policyClosestCenter).tag(WindowZoneOverlapPolicy.closestCenter.rawValue)
                }
                Toggle(text.restoreSize, isOn: $restoreSize)
                Toggle(text.moveNewWindows, isOn: $moveNewWindows)
                    .onChange(of: moveNewWindows) { _, _ in WindowLayoutService.shared.syncWithPreferences() }
                Toggle(text.perSpace, isOn: $perSpace)
                    .onChange(of: perSpace) { _, _ in reloadDisplays() }
                if perSpace {
                    Text(text.perSpaceCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if enabled {
            Section(text.colorsTitle) {
                ColorPicker(text.fillColor, selection: colorBinding($fillColor), supportsOpacity: false)
                ColorPicker(text.borderColor, selection: colorBinding($borderColor), supportsOpacity: false)
                ColorPicker(text.highlightColor, selection: colorBinding($highlightColor), supportsOpacity: false)
                LabeledContent(text.opacity) {
                    Slider(value: $opacity, in: 0.1...1)
                        .frame(maxWidth: 220)
                }
                WindowZonesColorPreview(fill: fillColor, border: borderColor, highlight: highlightColor,
                                        opacity: opacity)
                Button(text.resetColors) {
                    fillColor = WindowZoneColors.standard.fill
                    borderColor = WindowZoneColors.standard.border
                    highlightColor = WindowZoneColors.standard.highlight
                    opacity = WindowZoneColors.standard.opacity
                }
                .controlSize(.small)
            }
            Section(text.keyboard) {
                Toggle(text.keyboard, isOn: $keyboardEnabled)
                    .onChange(of: keyboardEnabled) { _, _ in WindowLayoutService.shared.syncWithPreferences() }
                Text(text.keyboardCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.acrossDisplays, isOn: $acrossDisplays)
                    .disabled(!keyboardEnabled)
                Toggle(text.quickSwitch, isOn: $quickSwitch)
                    .onChange(of: quickSwitch) { _, _ in WindowLayoutService.shared.syncWithPreferences() }
                LabeledContent(text.editorShortcut) {
                    ShortcutRecorderButton(shortcut: GlobalShortcut(storageValue: editorShortcutRaw)
                                               ?? .windowZonesEditorDefault,
                                           isEnabled: permissions.accessibility,
                                           waitingTitle: l10n.s.shortcutPressKeys,
                                           notCapturedAction: { shortcutError = l10n.s.shortcutNotCaptured },
                                           recordingChanged: { if $0 { shortcutError = nil } },
                                           invalidAction: { shortcutError = l10n.s.shortcutInvalid },
                                           captureAction: { shortcut in
                                               editorShortcutRaw = shortcut.storageValue
                                               WindowLayoutService.shared.syncWithPreferences()
                                           })
                        .frame(width: 108)
                }
                if let shortcutError {
                    Text(shortcutError).font(.caption).foregroundStyle(.orange)
                }
                if !zones.failedShortcuts.isEmpty {
                    Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private enum LayoutChoice: Hashable {
        case template(WindowZoneLayoutKind)
        case custom(UUID)
    }

    private func reloadDisplays() {
        displays = zones.displaySummaries()
    }

    /// A display's layout as the picker shows it. Picking a template keeps
    /// the zone count and spacing it had when that kind was in use.
    private func layoutBinding(for display: WindowZonesService.DisplaySummary) -> Binding<LayoutChoice> {
        Binding(
            get: {
                display.layout.kind == .custom
                    ? .custom(display.layout.customID ?? UUID())
                    : .template(display.layout.kind)
            },
            set: { choice in
                let layout: WindowZoneLayout
                switch choice {
                case .template(let kind):
                    var next = display.layout
                    next.kind = kind
                    next.customID = nil
                    if display.layout.kind == .custom { next.zoneCount = WindowZoneLayout.defaultZoneCount }
                    layout = next
                case .custom(let id):
                    guard let custom = zones.configuration.customLayouts.first(where: { $0.id == id }) else { return }
                    layout = .custom(custom)
                }
                zones.apply(layout, toDisplay: display.id, currentSpaceOnly: false)
            })
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: {
                guard let parts = WindowZoneColors.components(hex.wrappedValue) else { return .accentColor }
                return Color(.sRGB, red: parts.red, green: parts.green, blue: parts.blue)
            },
            set: { color in
                guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
                hex.wrappedValue = WindowZoneColors.hex(red: converted.redComponent, green: converted.greenComponent,
                                                        blue: converted.blueComponent)
            })
    }
}

/// Two zones, one of them highlighted, in the chosen colors.
struct WindowZonesColorPreview: View {
    let fill: String
    let border: String
    let highlight: String
    let opacity: Double

    private func color(_ hex: String) -> Color {
        guard let parts = WindowZoneColors.components(hex) else { return .accentColor }
        return Color(.sRGB, red: parts.red, green: parts.green, blue: parts.blue)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach([fill, highlight], id: \.self) { tint in
                RoundedRectangle(cornerRadius: 6)
                    .fill(color(tint).opacity(opacity))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(color(border).opacity(min(opacity + 0.3, 1)),
                                                                       lineWidth: 2))
            }
        }
        .frame(height: 54)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.35)))
        .accessibilityHidden(true)
    }
}

enum WindowZonesLayoutName {
    static func name(of kind: WindowZoneLayoutKind, text: WindowZonesStrings) -> String {
        switch kind {
        case .blank: return text.blank
        case .focus: return text.focus
        case .columns: return text.columns
        case .rows: return text.rows
        case .grid: return text.grid
        case .priorityGrid: return text.priorityGrid
        case .custom: return text.untitled
        }
    }
}
