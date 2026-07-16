// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct QuickLauncherView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @State private var hoveredItem: QuickLauncherItem?
    @State private var draggingItem: QuickLauncherItem?
    /// Mirrors launcher.editingOptionsItem: the service owns it so Esc can
    /// close the card before leaving edit mode.
    private var optionsItem: QuickLauncherItem? { launcher.editingOptionsItem }
    @AppStorage(DefaultsKey.micMuteMenuBarIndicator) private var micBadgeInMenuBar = false
    @AppStorage(DefaultsKey.colorPickerFormat) private var colorFormat = "hex"
    @AppStorage(DefaultsKey.colorPickerBareHex) private var colorBareHex = false
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var clipboardEnabled = false
    @AppStorage(DefaultsKey.clipboardHistoryLimit) private var clipboardLimit = 50
    @AppStorage(DefaultsKey.cleanerBadgeSeen) private var cleanerBadgeSeen = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: QuickLauncherService.columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let utility = launcher.activeUtility {
                hostedUtility(utility)
            } else if launcher.visibleItems.isEmpty && !launcher.isEditing {
                emptyState
            } else {
                grid
            }
            if launcher.activeUtility == nil, launcher.isEditing,
               let optionsItem, hasQuickOptions(optionsItem) {
                optionsCard(optionsItem)
            }
            if launcher.activeUtility == nil, launcher.isEditing, !launcher.hiddenItems.isEmpty {
                hiddenTray
            }
            footer
        }
        .padding(16)
        .frame(width: 420)
        .background(HUDBackdrop(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: launcher.presentationID) { _, _ in
            hoveredItem = nil
            draggingItem = nil
        }
        .onChange(of: launcher.activeUtility) { _, _ in
            launcher.refreshPanelLayout()
        }
        .onChange(of: launcher.isEditing) { _, _ in
            launcher.editingOptionsItem = nil
            launcher.refreshPanelLayout()
        }
        // The options card changes the panel's height, and the panel is sized
        // by hand (no autoresizing window): recompute after open and close,
        // and also when rows inside the card appear or disappear (the
        // clipboard limit picker and the bare-hex toggle are conditional).
        .onChange(of: launcher.editingOptionsItem) { _, _ in
            launcher.refreshPanelLayout()
        }
        .onChange(of: clipboardEnabled) { _, _ in
            launcher.refreshPanelLayout()
        }
        .onChange(of: colorFormat) { _, _ in
            launcher.refreshPanelLayout()
        }
    }

    /// The utility runs right here inside the launcher; its own close button
    /// and Esc lead back to the grid.
    @ViewBuilder
    private func hostedUtility(_ item: QuickLauncherItem) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                switch item {
                case .homebrew:
                    PanelHomebrewView { launcher.closeUtility() }
                case .media:
                    PanelMediaView { launcher.closeUtility() }
                case .urlCleaner:
                    PanelURLCleanerView { launcher.closeUtility() }
                case .uninstaller:
                    PanelUninstallerView { launcher.closeUtility() }
                case .cleaner:
                    PanelCleanerView { launcher.closeUtility() }
                case .windowLayout:
                    PanelWindowLayoutView { launcher.closeUtility() }
                case .toggles:
                    PanelQuickTogglesView { launcher.closeUtility() }
                default:
                    EmptyView()
                }
            }
        }
        .frame(height: 470)
    }

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                // The same transparent mark the menu panel shows, centered.
                BrandMark(width: 52, tint: colorScheme == .light ? Color(white: 0.03) : .white)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityHidden(true)
                HStack {
                    Button {
                        launcher.hide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.menuClose)
                    .accessibilityLabel(l10n.s.menuClose)
                    Spacer()
                    if launcher.activeUtility != nil {
                        Button {
                            launcher.closeUtility()
                        } label: {
                            Image(systemName: "chevron.backward.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l10n.s.menuClose)
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                launcher.isEditing.toggle()
                            }
                        } label: {
                            Image(systemName: launcher.isEditing ? "checkmark.circle.fill" : "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(launcher.isEditing ? Color.accentColor : Color.secondary)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.s.launcherEditHint)
                        .accessibilityLabel(l10n.s.menuSettings)
                    }
                }
            }
            if launcher.isEditing, launcher.activeUtility == nil {
                Text(l10n.s.launcherEditHint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(launcher.visibleItems) { item in
                PanelReorderableItem(item: item,
                                     isEnabled: launcher.isEditing,
                                     order: launcher.itemOrderBinding,
                                     dragging: $draggingItem) {
                    cell(item)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: QuickLauncherItem) -> some View {
        let index = launcher.visibleItems.firstIndex(of: item)
        let isSelected = !launcher.isEditing && index != nil && index == launcher.selectedIndex
        let isHovered = hoveredItem == item

        Button {
            if launcher.isEditing {
                // In edit mode the tile body opens its inline options (when it
                // has any); a tiny gear badge alone is too small a target and
                // sits outside the tile's hit area.
                if hasQuickOptions(item) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        launcher.editingOptionsItem = optionsItem == item ? nil : item
                    }
                }
            } else {
                launcher.run(item)
            }
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconBackground(item, isSelected: isSelected, isHovered: isHovered))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: icon(for: item))
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(iconColor(item))
                        )
                    if launcher.isEditing {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                launcher.setHidden(item, true)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white, Color.red)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 7, y: -7)
                        .help(l10n.s.panelHideItem)
                        .accessibilityLabel(l10n.s.panelHideItem)
                        if hasQuickOptions(item) {
                            Image(systemName: "gearshape.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white, optionsItem == item ? Color.accentColor : Color.secondary)
                                .frame(width: 46, height: 46, alignment: .topLeading)
                                .offset(x: -7, y: -7)
                                .help(l10n.s.menuSettings)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    } else {
                        if isActive(item) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                        // Red dot pointing at the brand new feature; it
                        // retires everywhere the first time the cleaner opens.
                        if item == .cleaner, !cleanerBadgeSeen {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                                .accessibilityHidden(true)
                        }
                        // Keys 1-9 activate the first nine tiles; the badge is
                        // the only hint that shortcut exists.
                        if let index, index < 9 {
                            Image(systemName: "\(index + 1).circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white, isSelected ? Color.accentColor : Color.secondary.opacity(0.8))
                                .frame(width: 46, height: 46, alignment: .topLeading)
                                .offset(x: -6, y: -6)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Text(title(for: item))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14)
                          : isHovered ? Color.primary.opacity(0.07)
                          : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear,
                                  lineWidth: 1.2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(for: item))
        .onHover { hovering in
            hoveredItem = hovering ? item : (hoveredItem == item ? nil : hoveredItem)
            if hovering, !launcher.isEditing {
                launcher.select(item)
            }
        }
    }

    private var hiddenTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.s.launcherAddSection.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            FlowLayoutLite(spacing: 6) {
                ForEach(launcher.hiddenItems) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            launcher.setHidden(item, false)
                        }
                    } label: {
                        Label(title(for: item), systemImage: "plus.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous).fill(Color.accentColor.opacity(0.13))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        Text(l10n.s.launcherEmptyState)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text(GlobalShortcutRole.quickLauncher.savedShortcut.displayString)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Esc")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Inline options (edit mode)

    /// Tools whose closest settings are worth flipping right here, without a
    /// trip to the Settings window. Curated on purpose: only options that
    /// change what the tile itself does.
    private func hasQuickOptions(_ item: QuickLauncherItem) -> Bool {
        switch item {
        case .keepAwake, .micMute, .colorPicker, .clipboard: return true
        default: return false
        }
    }

    /// Inline card under the grid while a gear is open. A card instead of a
    /// popover on purpose: popovers never present from this borderless
    /// non-activating panel, and the card keeps the whole flow inside the HUD.
    private func optionsCard(_ item: QuickLauncherItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title(for: item), systemImage: icon(for: item))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { launcher.editingOptionsItem = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.menuClose)
            }
            switch item {
            case .keepAwake:
                // Same guard as the panel's Keep awake card: enabling the
                // closed-lid rule can run an admin setup step, and flipping
                // the switch again mid-setup would race it.
                Toggle(l10n.s.clamshellTitle, isOn: $keepAwake.clamshellPreferred)
                    .disabled(keepAwake.clamshellSetupInProgress)
                Picker(l10n.s.defaultDurationLabel, selection: $defaultDuration) {
                    Text(l10n.s.minutes15).tag(15)
                    Text(l10n.s.minutes30).tag(30)
                    Text(l10n.s.hour1).tag(60)
                    Text(l10n.s.hours2).tag(120)
                    Text(l10n.s.hours4).tag(240)
                    Text(l10n.s.hours8).tag(480)
                    Text(l10n.s.indefinite).tag(0)
                }
            case .micMute:
                Toggle(l10n.s.micMuteMenuBarToggle, isOn: $micBadgeInMenuBar)
            case .clipboard:
                Toggle(FeatureStrings.clipboard(l10n.language).enable, isOn: $clipboardEnabled)
                    // Same sync the Settings toggle performs: writing the
                    // default alone does not start or stop the watcher.
                    .onChange(of: clipboardEnabled) { _, _ in
                        ClipboardHistoryService.shared.syncWithPreferences()
                    }
                if clipboardEnabled {
                    Picker(FeatureStrings.clipboard(l10n.language).limit, selection: $clipboardLimit) {
                        ForEach(Defaults.allowedClipboardHistoryLimits, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                }
            case .colorPicker:
                Picker(l10n.s.colorPickerFormatLabel, selection: $colorFormat) {
                    ForEach(ColorCopyFormat.allCases) { format in
                        Text(format.label).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if colorFormat == ColorCopyFormat.hex.rawValue {
                    Toggle(l10n.s.colorPickerBareHexToggle, isOn: $colorBareHex)
                }
            default:
                EmptyView()
            }
        }
        .font(.system(size: 11))
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - Item metadata

    private func title(for item: QuickLauncherItem) -> String {
        switch item {
        case .keepAwake: return l10n.s.keepAwakeTitle
        case .toggles: return FeatureStrings.quickToggles(l10n.language).pageTitle
        case .micMute: return micMute.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName
        case .screenOCR: return l10n.s.ocrName
        case .colorPicker: return l10n.s.colorPickerName
        case .clipboard: return FeatureStrings.clipboard(l10n.language).title
        case .windowLayout: return FeatureStrings.windowLayout(l10n.language).title
        case .cleaning: return l10n.s.cleaningMenuItem
        case .homebrew: return l10n.s.homebrewName
        case .media: return l10n.s.mediaName
        case .urlCleaner: return l10n.s.urlCleanerName
        case .uninstaller: return l10n.s.uninstallerName
        case .cleaner: return l10n.s.cleanerName
        case .screenshot: return FeatureStrings.screenshot(l10n.language).pageTitle
        case .cameraPreview: return FeatureStrings.cameraPreview(l10n.language).pageTitle
        }
    }

    private func icon(for item: QuickLauncherItem) -> String {
        switch item {
        case .keepAwake: return keepAwake.isActive ? "bolt.fill" : "bolt"
        case .toggles: return "togglepower"
        case .micMute: return micMute.isMuted ? "mic.slash.fill" : "mic"
        case .screenOCR: return "text.viewfinder"
        case .colorPicker: return "eyedropper"
        case .clipboard: return "doc.on.clipboard"
        case .windowLayout: return "rectangle.3.group"
        case .cleaning: return "keyboard"
        case .homebrew: return "shippingbox"
        case .media: return "photo.on.rectangle.angled"
        case .urlCleaner: return "link"
        case .uninstaller: return "trash"
        case .cleaner: return "sparkle"
        case .screenshot: return "camera.viewfinder"
        case .cameraPreview: return "web.camera"
        }
    }

    private func isActive(_ item: QuickLauncherItem) -> Bool {
        switch item {
        case .keepAwake: return keepAwake.isActive
        case .micMute: return micMute.isMuted
        default: return false
        }
    }

    private func iconColor(_ item: QuickLauncherItem) -> Color {
        if item == .micMute, micMute.isMuted { return .red }
        if isActive(item) { return .accentColor }
        return .primary.opacity(0.85)
    }

    private func iconBackground(_ item: QuickLauncherItem, isSelected: Bool, isHovered: Bool) -> Color {
        if isActive(item) { return Color.accentColor.opacity(0.18) }
        if isSelected || isHovered { return Color.primary.opacity(0.1) }
        return Color.primary.opacity(0.07)
    }
}

/// Minimal wrapping layout for the hidden-item chips.
struct FlowLayoutLite: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 380
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
