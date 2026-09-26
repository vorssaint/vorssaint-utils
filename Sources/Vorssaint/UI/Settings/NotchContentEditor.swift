// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The open island for one section, hanging from a slice of menu bar: the
/// island's own pages at their real size, scaled into Settings, so every
/// option changes the preview the way it changes the island.
struct NotchIslandPreview: View {
    let module: NotchModule
    /// The section is switched off, or the feature behind it is.
    var hidden = false
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monitoring = false
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    private static let captionHeight: CGFloat = 28
    private static let margin: CGFloat = 16

    /// One scale for every section, taken from the tallest island, so the
    /// preview keeps its size and choosing a section never moves the list
    /// under the pointer.
    static func scale(in stage: CGSize) -> CGFloat {
        let largest = NotchService.shared.previewLargestSize
        guard largest.width > 0, largest.height > 0 else { return 1 }
        return max(0.1, min(1, (stage.width - margin * 2) / largest.width, (stage.height - captionHeight) / largest.height))
    }

    /// As tall as the tallest island at the scale that fits the width, within
    /// the limit the page gives it.
    static func height(width: CGFloat, limit: CGFloat) -> CGFloat {
        NotchService.shared.previewLargestSize.height * scale(in: CGSize(width: width, height: limit)) + captionHeight
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = notch.geometry
            let size = notch.previewSize(for: module)
            let scale = Self.scale(in: proxy.size)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.primary.opacity(0.06))
                    .frame(height: geometry.menuBarHeight * scale)
                island(size: size, geometry: geometry)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .top)
                    .opacity(hidden ? 0.4 : 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Label(hidden ? editor.hiddenInIsland : editor.preview, systemImage: hidden ? "eye.slash" : "eye")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: module)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(editor.preview)
        .accessibilityValue(module.title(l10n.language) + (hidden ? ", " + editor.hiddenInIsland : ""))
        .onAppear { monitor(module == .system) }
        .onChange(of: module) { _, value in monitor(value == .system) }
        .onDisappear { monitor(false) }
    }

    /// The system page reads live metrics, which sample only while a surface
    /// shows them; the preview counts as one, like the menu panel.
    private func monitor(_ wanted: Bool) {
        guard wanted != monitoring else { return }
        monitoring = wanted
        if wanted { SystemMonitor.shared.panelDidAppear() } else { SystemMonitor.shared.panelDidDisappear() }
    }

    private var glassSurface: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return glass && !reduceTransparency }
#endif
        return false
    }

    private func island(size: CGSize, geometry: NotchGeometry) -> some View {
        let content = geometry.contentSize(for: size)
        return VStack(spacing: NotchLayout.spacing) {
            header(geometry: geometry, width: content.width)
            NotchPagePreview(module: module, size: content)
                .frame(width: content.width, height: content.height, alignment: .top)
                .clipped()
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, geometry.headerTopInset)
        .padding(.bottom, NotchLayout.bottomInset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height)).fill(.black)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.notchPresentation, true)
        .environment(\.notchGlassSurface, glassSurface)
        .environment(\.notchSettingsPreview, true)
        .allowsHitTesting(false)
    }

    /// The island's title row: the section's name, the camera between the
    /// halves, and the actions that wait for the pointer.
    private func header(geometry: NotchGeometry, width: CGFloat) -> some View {
        let half = geometry.headerCameraGap > 0 ? (width - geometry.headerCameraGap) / 2 : nil
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if !NotchQuickAccessConfiguration.current().actions.contains(.explore) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
                Text(module.title(l10n.language))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: half, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if geometry.headerCameraGap > 0 {
                Color.clear.frame(width: geometry.headerCameraGap)
            }
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 28, height: 28)
                .frame(width: half, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: geometry.headerRowHeight)
    }
}

/// A section's page as the island draws it. The camera and the scratchpad
/// show a still instead: a preview must never turn the camera on or give a
/// text editor the keyboard.
struct NotchPagePreview: View {
    let module: NotchModule
    let size: CGSize
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        switch module {
        case .timer: NotchTimerView(size: size)
        case .camera: camera
        case .notifications: NotchNotificationsView(size: size)
        case .downloads: NotchDownloadsView(size: size)
        case .calendar: NotchCalendarView(size: size)
        case .controls: NotchControlsView(service: notch, size: size)
        case .mixer: NotchMixerView(size: size)
        case .music: NotchMusicView(size: size, extrasHeight: notch.geometry.musicExtrasHeight)
        case .clipboard: NotchClipboardView(service: notch, size: size)
        case .captures: RecentCapturesView(onClose: nil, notchSize: size)
        case .files: NotchFilesView(service: notch)
        case .system: NotchSystemView(size: size) { _ in }
        case .tools: QuickLauncherView(notchSize: size)
        case .scratchpad: NotchScratchpadStill()
        case .agents:
            // Off, nothing reads the logs, so the page would wait forever.
            if NotchAgentSupport.isEnabled() {
                NotchAgentsView(size: size)
            } else {
                NotchEmptyView(symbol: "sparkles", message: FeatureStrings.notchEditor(l10n.language).agentsSummary)
            }
        }
    }

    private var camera: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(FeatureStrings.notchEditor(l10n.language).cameraPreview)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
    }
}

/// The scratchpad page without its editor: the pads' tabs and the current
/// note, or the prompt a new one shows.
private struct NotchScratchpadStill: View {
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.scratchpad(l10n.language)
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                let names = pad.pads.isEmpty ? [text.pageTitle] : pad.pads.map(\.name)
                ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.white.opacity(pad.pads.isEmpty || pad.pads[index].id == pad.selectedPadID ? 0.12 : 0),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Spacer(minLength: 0)
                ForEach(["plus", "eye", "doc.on.doc", "ellipsis"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
            }
            Text(pad.text.isEmpty ? text.placeholder : pad.text)
                .font(.system(size: PlainTextEditor.fontSize))
                .foregroundStyle(.white.opacity(pad.text.isEmpty ? 0.35 : 0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One section in the list beside its options: the box that shows it in the
/// island, its icon and its name. A row drags to a new place; choosing one
/// opens its options and its preview. A box rather than a switch leaves the
/// name its whole line even in the narrowest window.
struct NotchSectionListRow: View {
    let module: NotchModule
    @Binding var included: Bool
    let available: Bool
    let selected: Bool
    @Binding var order: [NotchModule]
    @Binding var dragging: NotchModule?
    let select: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var hovering = false
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    private var title: String { module.title(l10n.language) }

    var body: some View {
        PanelReorderableItem(item: module, order: $order, dragging: $dragging) {
            HStack(spacing: 8) {
                // A section whose feature is off cannot show, whatever was chosen.
                Toggle(title, isOn: available ? $included : .constant(false))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(!available)
                Button(action: select) {
                    HStack(spacing: 8) {
                        NotchSectionTile(module: module, shown: included && available, side: 22)
                        Text(title)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(available ? .primary : .secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 2)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(editor.summary(module))
                .accessibilityLabel(title)
                .accessibilityValue(editor.summary(module))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveUp) { move(by: -1) }
                .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveDown) { move(by: 1) }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(selected ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .opacity(dragging == module ? 0.45 : 1)
        }
    }

    private func move(by offset: Int) {
        guard let index = order.firstIndex(of: module), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
    }
}

/// What the chosen section is, above its options: its icon, name and one
/// line on what it shows, and why it cannot show while its feature is off.
struct NotchSectionHeader: View {
    let module: NotchModule
    let shown: Bool
    /// Why an unavailable section cannot show.
    let reason: String?
    let openFeatures: () -> Void
    @ObservedObject private var l10n = L10n.shared
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NotchSectionTile(module: module, shown: shown, side: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title(l10n.language)).font(.title3.weight(.semibold))
                Text(editor.summary(module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    HStack(spacing: 10) {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(editor.openFeatures, action: openFeatures).controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section's icon on its own color; grey while the section is hidden.
struct NotchSectionTile: View {
    let module: NotchModule
    let shown: Bool
    let side: CGFloat

    var body: some View {
        Image(systemName: module.symbol)
            .font(.system(size: side * 0.46, weight: .semibold))
            .foregroundStyle(shown ? module.settingsGlyph : Color.secondary)
            .frame(width: side, height: side)
            .background(shown ? module.settingsTint : Color.secondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension NotchModule {
    /// A color per section, like the icons of System Settings, so a long list
    /// can be scanned by eye.
    var settingsTint: Color {
        switch self {
        case .controls: return .blue
        case .mixer: return .purple
        case .music: return .pink
        case .clipboard: return .brown
        case .captures: return .indigo
        case .files: return .cyan
        case .system: return .green
        case .tools: return .gray
        case .calendar: return .red
        case .notifications: return .orange
        case .timer: return .mint
        case .camera: return .teal
        case .downloads: return .blue
        case .scratchpad: return .yellow
        case .agents: return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    var settingsGlyph: Color { self == .scratchpad ? .black.opacity(0.75) : .white }
}
