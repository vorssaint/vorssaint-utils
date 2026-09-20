// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Switcher page: the app switcher chosen from three drawn layouts, its
/// shortcuts and options as rows and chips, then Dock Preview, Dock clicks
/// and the window previews both share.
struct SwitcherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherTakeOverSystemShortcuts) private var switcherTakeOverSystemShortcuts = false
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var switcherSimpleMode = false
    @AppStorage(DefaultsKey.switcherMergeTabs) private var switcherMergeTabs = false
    @AppStorage(DefaultsKey.switcherWindowlessApps) private var switcherWindowlessApps = SwitcherWindowlessApps.fallback.rawValue
    @AppStorage(DefaultsKey.switcherMinimizedPlacement) private var switcherMinimizedPlacement = WindowSwitchMinimizedPlacement.normal.rawValue
    @AppStorage(DefaultsKey.switcherShowFullscreenWindows) private var switcherShowFullscreenWindows = true
    @AppStorage(DefaultsKey.switcherScreenPlacement) private var switcherScreenPlacement = SwitcherScreenPlacement.fallback.rawValue
    @AppStorage(DefaultsKey.switcherCurrentDisplayOnly) private var switcherCurrentDisplayOnly = false
    @AppStorage(DefaultsKey.switcherCurrentSpaceOnly) private var switcherCurrentSpaceOnly = false
    @AppStorage(DefaultsKey.switcherSearchPinEnabled) private var switcherSearchPinEnabled = false
    @AppStorage(DefaultsKey.switcherShowShortcutHints) private var switcherShowShortcutHints = true
    @AppStorage(DefaultsKey.switcherAppearanceDelay) private var switcherAppearanceDelay = SwitcherSupport.defaultAppearanceDelayMilliseconds
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.dockPreviewCurrentSpaceOnly) private var dockPreviewCurrentSpaceOnly = false
    @AppStorage(DefaultsKey.dockPreviewBackgroundOpacity) private var dockPreviewBackgroundOpacity = 1.0
    @AppStorage(DefaultsKey.dockPreviewOpenDelay) private var dockPreviewOpenDelay = DockPreviewSupport.defaultOpenDelayMilliseconds
    @AppStorage(DefaultsKey.dockPreviewQuitAppOnClose) private var dockPreviewQuitAppOnClose = false
    @AppStorage(DefaultsKey.dockPreviewOrderByCreation) private var dockPreviewOrderByCreation = false
    @AppStorage(DefaultsKey.dockPreviewKeepDockVisible) private var dockPreviewKeepDockVisible = false
    @State private var dockPreviewMoreOptionsExpanded = false
    @AppStorage(DefaultsKey.dockClickMinimize) private var dockClickMinimize = false
    @AppStorage(DefaultsKey.dockClickHide) private var dockClickHide = false
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleWindows = false
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @AppStorage(DefaultsKey.previewSize) private var previewSize = "normal"

    private var pages: SettingsPageStrings { FeatureStrings.settingsPages(l10n.language) }
    private var switcherEngaged: Bool { switcherEnabled && AppFeature.switcher.isAvailable }
    private var dockPreviewEngaged: Bool { dockPreviewEnabled && AppFeature.dockPreview.isAvailable }
    private var switcherWindowlessAppsSelection: Binding<String> {
        Binding(
            get: {
                SwitcherWindowlessApps.mode(
                    storedValue: switcherWindowlessApps,
                    takeOverSystemShortcuts: switcherTakeOverSystemShortcuts).rawValue
            },
            set: { value in
                if !switcherTakeOverSystemShortcuts { switcherWindowlessApps = value }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.s.tabSwitcher).font(.title2.bold())
                    Text(pages.switcherDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if AppFeature.switcher.isAvailable {
                    switcherCard
                        .settingsSectionAnchor(.switcher, cornerRadius: 16)
                    switcherOptionsCard
                        .disabled(!switcherEnabled)
                }
                if AppFeature.dockPreview.isAvailable {
                    dockPreviewCard
                        .settingsSectionAnchor(.dock, cornerRadius: 16)
                }
                // Clicking a Dock icon is its own installable feature in the
                // hub, so it gets its own card here.
                if AppFeature.dockClick.isAvailable {
                    dockClickCard
                        .settingsSectionAnchor(.dockClick, cornerRadius: 16)
                }
                if AppFeature.switcher.isAvailable || AppFeature.dockPreview.isAvailable {
                    previewsCard
                }
                if switcherEngaged || dockPreviewEngaged {
                    if !permissions.accessibility {
                        SettingsCard(title: l10n.s.permissionRequired) {
                            PermissionRow(kind: .accessibility)
                        }
                    }
                    if !permissions.screenRecording,
                       SwitcherSupport.needsScreenRecording(switcherEnabled: switcherEngaged,
                                                            simpleMode: switcherSimpleMode,
                                                            dockPreviewEnabled: dockPreviewEngaged) {
                        SettingsCard {
                            PermissionRow(kind: .screenRecording)
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
    }

    // MARK: - App switcher

    private var layout: SwitcherLayout {
        if switcherSimpleMode { return .simple }
        return switcherIconRowMode ? .icons : .windows
    }

    private func choose(_ layout: SwitcherLayout) {
        switch layout {
        case .windows:
            switcherSimpleMode = false
            switcherIconRowMode = false
        case .icons:
            switcherSimpleMode = false
            switcherIconRowMode = true
        case .simple:
            switcherSimpleMode = true
        }
        AppSwitcher.shared.syncWithPreferences()
    }

    private var switcherCard: some View {
        SettingsCard(title: l10n.s.switcherSection) {
            SettingsRow(symbol: "rectangle.on.rectangle", title: l10n.s.switcherEnable,
                        caption: l10n.s.switcherEnableCaption) {
                Toggle(l10n.s.switcherEnable, isOn: $switcherEnabled)
                    .labelsHidden()
                    .onChange(of: switcherEnabled) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
            }
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text(FeatureStrings.notchEditor(l10n.language).layout)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 10) {
                        SwitcherLayoutChoice(layout: .windows, title: pages.switcherLayoutWindows,
                                             caption: pages.switcherLayoutWindowsCaption, selected: layout == .windows) {
                            choose(.windows)
                        }
                        SwitcherLayoutChoice(layout: .icons, title: pages.switcherLayoutIcons,
                                             caption: l10n.s.switcherIconRowModeCaption, selected: layout == .icons) {
                            choose(.icons)
                        }
                        SwitcherLayoutChoice(layout: .simple, title: pages.switcherLayoutSimple,
                                             caption: l10n.s.switcherSimpleModeCaption, selected: layout == .simple) {
                            choose(.simple)
                        }
                    }
                }
                Divider()
                ShortcutPreferenceRow(role: .switcher,
                                      isEnabled: switcherEnabled,
                                      label: l10n.s.switcherShortcutHintApps,
                                      symbolName: "app.dashed") {
                    AppSwitcher.shared.syncWithPreferences()
                }
                ShortcutPreferenceRow(role: .switcherWindow,
                                      isEnabled: switcherEnabled,
                                      label: l10n.s.switcherShortcutHintWindows,
                                      symbolName: "macwindow.on.rectangle") {
                    AppSwitcher.shared.syncWithPreferences()
                }
                Text(l10n.s.switcherWindowShortcutCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsRow(symbol: "command", title: l10n.s.switcherTakeOverSystemShortcuts,
                            caption: l10n.s.switcherTakeOverSystemShortcutsCaption) {
                    Toggle(l10n.s.switcherTakeOverSystemShortcuts, isOn: $switcherTakeOverSystemShortcuts)
                        .labelsHidden()
                        .onChange(of: switcherTakeOverSystemShortcuts) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                }
                Text(String(format: l10n.s.switcherUsageHintFormat,
                            GlobalShortcutRole.switcher.savedShortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!switcherEnabled)
        }
    }

    private var switcherOptionsCard: some View {
        SettingsCard(title: l10n.s.keepAwakeOptions) {
            SettingsRow(symbol: "timer", title: l10n.s.switcherAppearanceDelay,
                        caption: l10n.s.switcherAppearanceDelayCaption) {
                HStack(spacing: 8) {
                    Slider(value: switcherAppearanceDelayBinding,
                           in: Double(SwitcherSupport.appearanceDelayMillisecondsRange.lowerBound)
                               ... Double(SwitcherSupport.appearanceDelayMillisecondsRange.upperBound),
                           step: 25)
                        .frame(width: 140)
                    Text("\(sanitizedSwitcherAppearanceDelay) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            SettingsRow(symbol: "magnifyingglass", title: l10n.s.switcherSearchPin,
                        caption: l10n.s.switcherSearchPinCaption) {
                Toggle(l10n.s.switcherSearchPin, isOn: $switcherSearchPinEnabled).labelsHidden()
            }
            if switcherSimpleMode || switcherIconRowMode {
                SettingsRow(symbol: "keyboard", title: l10n.s.switcherShowShortcutHints,
                            caption: l10n.s.switcherShowShortcutHintsCaption) {
                    Toggle(l10n.s.switcherShowShortcutHints, isOn: $switcherShowShortcutHints).labelsHidden()
                }
            }
            SettingsRow(symbol: "square.stack", title: l10n.s.switcherMergeTabs,
                        caption: l10n.s.switcherMergeTabsCaption) {
                Toggle(l10n.s.switcherMergeTabs, isOn: $switcherMergeTabs).labelsHidden()
            }
            SettingsRow(symbol: "arrow.down.right.and.arrow.up.left", title: l10n.s.switcherShowFullscreenWindows) {
                Toggle(l10n.s.switcherShowFullscreenWindows, isOn: $switcherShowFullscreenWindows)
                    .labelsHidden()
                    .onChange(of: switcherShowFullscreenWindows) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
            }
            Divider()
            chipRow(symbol: "arrow.down.to.line", title: l10n.s.switcherMinimizedPlacementLabel, caption: nil,
                    selection: $switcherMinimizedPlacement,
                    choices: [(WindowSwitchMinimizedPlacement.normal.rawValue, l10n.s.switcherMinimizedPlacementNormal),
                              (WindowSwitchMinimizedPlacement.end.rawValue, l10n.s.switcherMinimizedPlacementEnd),
                              (WindowSwitchMinimizedPlacement.hidden.rawValue, l10n.s.switcherMinimizedPlacementHidden)])
                .onChange(of: switcherMinimizedPlacement) { _, _ in
                    AppSwitcher.shared.syncWithPreferences()
                }
            chipRow(symbol: "display.2", title: l10n.s.switcherScreenPlacementLabel,
                    caption: l10n.s.switcherScreenPlacementCaption,
                    selection: $switcherScreenPlacement,
                    choices: [(SwitcherScreenPlacement.pointer.rawValue, l10n.s.switcherScreenPlacementPointer),
                              (SwitcherScreenPlacement.menuBar.rawValue, l10n.s.switcherScreenPlacementMenuBar),
                              (SwitcherScreenPlacement.activeWindow.rawValue, l10n.s.switcherScreenPlacementActiveWindow)])
            SettingsRow(symbol: "display", title: l10n.s.switcherCurrentDisplayOnly,
                        caption: l10n.s.switcherCurrentDisplayOnlyCaption) {
                Toggle(l10n.s.switcherCurrentDisplayOnly, isOn: $switcherCurrentDisplayOnly).labelsHidden()
            }
            SettingsRow(symbol: "rectangle.3.group", title: l10n.s.switcherCurrentSpaceOnly,
                        caption: l10n.s.switcherCurrentSpaceOnlyCaption) {
                Toggle(l10n.s.switcherCurrentSpaceOnly, isOn: $switcherCurrentSpaceOnly).labelsHidden()
            }
            Divider()
            chipRow(symbol: "app.dashed", title: l10n.s.switcherWindowlessApps,
                    caption: l10n.s.switcherWindowlessAppsCaption,
                    selection: switcherWindowlessAppsSelection,
                    choices: [(SwitcherWindowlessApps.off.rawValue, l10n.s.switcherWindowlessAppsOff),
                              (SwitcherWindowlessApps.finder.rawValue, l10n.s.switcherWindowlessAppsFinder),
                              (SwitcherWindowlessApps.all.rawValue, l10n.s.switcherWindowlessAppsAll)])
                .disabled(switcherTakeOverSystemShortcuts)
            // Per-app rules can be prepared while the switcher is off, as
            // before the redesign; the card's disabled state stops here.
            SwitcherAppRulesList()
                .environment(\.isEnabled, true)
        }
    }

    /// An icon, a title and one chip per choice, so the options read at a
    /// glance instead of hiding in a menu.
    private func chipRow(symbol: String, title: String, caption: String?, selection: Binding<String>,
                         choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(symbol: symbol, title: title, caption: caption) { EmptyView() }
            HStack(spacing: 8) {
                ForEach(choices, id: \.0) { value, label in
                    let selected = selection.wrappedValue == value
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Color.accentColor : .primary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.leading, settingsRowTextInset)
        }
    }

    // MARK: - Dock

    private var dockPreviewCard: some View {
        SettingsCard(title: l10n.s.dockPreviewName) {
            SettingsRow(symbol: "dock.rectangle", title: l10n.s.dockPreviewEnable, caption: dockPreviewCaption) {
                Toggle(l10n.s.dockPreviewEnable, isOn: $dockPreviewEnabled)
                    .labelsHidden()
                    .onChange(of: dockPreviewEnabled) { _, _ in
                        DockPreviewService.shared.syncWithPreferences()
                    }
            }
            if dockPreviewEnabled {
                SettingsRow(symbol: "rectangle.3.group", title: l10n.s.switcherCurrentSpaceOnly,
                            caption: l10n.s.dockPreviewCurrentSpaceOnlyCaption) {
                    Toggle(l10n.s.switcherCurrentSpaceOnly, isOn: $dockPreviewCurrentSpaceOnly)
                        .labelsHidden()
                        .onChange(of: dockPreviewCurrentSpaceOnly) { _, _ in
                            DockPreviewService.shared.syncWithPreferences()
                        }
                }
                SettingsRow(symbol: "timer", title: l10n.s.dockPreviewOpenDelay,
                            caption: l10n.s.dockPreviewOpenDelayCaption) {
                    HStack(spacing: 6) {
                        TextField("", value: dockPreviewOpenDelayBinding,
                                  formatter: Self.dockPreviewOpenDelayFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Stepper("", value: dockPreviewOpenDelayBinding,
                                in: DockPreviewSupport.openDelayMillisecondsRange,
                                step: 50)
                            .labelsHidden()
                        Text(verbatim: "ms")
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsRow(symbol: "circle.lefthalf.filled", title: l10n.s.dockPreviewBackgroundOpacity,
                            caption: l10n.s.dockPreviewBackgroundOpacityCaption) {
                    HStack(spacing: 8) {
                        Slider(value: dockPreviewBackgroundOpacityBinding,
                               in: DockPreviewSupport.backgroundOpacityRange,
                               step: 0.05)
                            .frame(width: 140)
                        Text("\(dockPreviewBackgroundOpacityPercent)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                SettingsRow(symbol: "xmark.circle", title: l10n.s.dockPreviewQuitAppOnClose,
                            caption: l10n.s.dockPreviewQuitAppOnCloseCaption) {
                    Toggle(l10n.s.dockPreviewQuitAppOnClose, isOn: $dockPreviewQuitAppOnClose).labelsHidden()
                }
                DisclosureGroup(isExpanded: $dockPreviewMoreOptionsExpanded) {
                    SettingsRow(symbol: "dock.rectangle", title: l10n.s.dockPreviewKeepDockVisible,
                                caption: l10n.s.dockPreviewKeepDockVisibleCaption) {
                        Toggle(l10n.s.dockPreviewKeepDockVisible, isOn: $dockPreviewKeepDockVisible)
                            .labelsHidden()
                            .disabled(!DockAutohideHold.isSupported && !dockPreviewKeepDockVisible)
                            .onChange(of: dockPreviewKeepDockVisible) { _, _ in
                                dockPreview.syncWithPreferences()
                            }
                    }
                    .padding(.top, 6)
                    SettingsRow(symbol: "clock.arrow.circlepath", title: l10n.s.dockPreviewOrderByCreation,
                                caption: l10n.s.dockPreviewOrderByCreationCaption) {
                        Toggle(l10n.s.dockPreviewOrderByCreation, isOn: $dockPreviewOrderByCreation).labelsHidden()
                    }
                } label: {
                    Text(FeatureStrings.recorder(l10n.language).moreOptions)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private var dockClickCard: some View {
        SettingsCard(title: FeatureStrings.hub(l10n.language).titleDockClick) {
            SettingsRow(symbol: "dock.arrow.down.rectangle", title: l10n.s.dockClickMinimize,
                        caption: l10n.s.dockClickMinimizeCaption) {
                Toggle(l10n.s.dockClickMinimize, isOn: $dockClickMinimize)
                    .labelsHidden()
                    .onChange(of: dockClickMinimize) { _, enabled in
                        if enabled { dockClickHide = false }
                        DockClickService.shared.syncWithPreferences()
                    }
            }
            SettingsRow(symbol: "eye.slash", title: l10n.s.dockClickHide, caption: l10n.s.dockClickHideCaption) {
                Toggle(l10n.s.dockClickHide, isOn: $dockClickHide)
                    .labelsHidden()
                    .onChange(of: dockClickHide) { _, enabled in
                        if enabled { dockClickMinimize = false }
                        DockClickService.shared.syncWithPreferences()
                    }
            }
            SettingsRow(symbol: "arrow.triangle.2.circlepath", title: l10n.s.dockClickCycleWindows,
                        caption: l10n.s.dockClickCycleWindowsCaption) {
                Toggle(l10n.s.dockClickCycleWindows, isOn: $dockClickCycleWindows)
                    .labelsHidden()
                    .onChange(of: dockClickCycleWindows) { _, _ in
                        DockClickService.shared.syncWithPreferences()
                    }
            }
        }
    }

    // MARK: - Window previews

    private var previewsCard: some View {
        SettingsCard(title: FeatureStrings.windowPreviewExclusions(l10n.language).sectionTitle) {
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.s.previewSizeLabel)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 10) {
                    sizeChoice("small", title: l10n.s.previewSizeSmall, scale: 0.5)
                    sizeChoice("normal", title: l10n.s.previewSizeNormal, scale: 0.66)
                    sizeChoice("large", title: l10n.s.previewSizeLarge, scale: 0.83)
                    sizeChoice("xlarge", title: l10n.s.previewSizeXLarge, scale: 1)
                }
            }
            SettingsRow(symbol: "rectangle.dashed", title: l10n.s.minimalWindowPreviews,
                        caption: l10n.s.minimalWindowPreviewsCaption) {
                Toggle(l10n.s.minimalWindowPreviews, isOn: $minimalPreviews).labelsHidden()
            }
            WindowPreviewExclusionsList()
        }
    }

    /// A preview thumbnail drawn at the size it stands for.
    private func sizeChoice(_ value: String, title: String, scale: CGFloat) -> some View {
        let selected = previewSize == value
        return Button {
            previewSize = value
            AppSwitcher.shared.syncWithPreferences()
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.3))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.secondary.opacity(0.6))
                            .frame(height: 4)
                            .padding(3)
                    }
                    .frame(width: 60 * scale, height: 42 * scale)
                    .frame(height: 42)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - State

    private var dockPreviewCaption: String {
        guard dockPreviewEnabled else { return l10n.s.dockPreviewEnableCaption }
        if !permissions.accessibility { return "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)" }
        if !permissions.screenRecording { return "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)" }
        switch dockPreview.blockedReason {
        case .dockUnavailable: return l10n.s.dockPreviewDockUnavailable
        default:
            return l10n.s.dockPreviewEnableCaption
        }
    }

    private var dockPreviewBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { DockPreviewSupport.sanitizedBackgroundOpacity(dockPreviewBackgroundOpacity) },
            set: { dockPreviewBackgroundOpacity = DockPreviewSupport.sanitizedBackgroundOpacity($0) }
        )
    }

    private var sanitizedSwitcherAppearanceDelay: Int {
        SwitcherSupport.sanitizedAppearanceDelay(milliseconds: switcherAppearanceDelay)
    }

    private var switcherAppearanceDelayBinding: Binding<Double> {
        Binding(
            get: { Double(sanitizedSwitcherAppearanceDelay) },
            set: {
                switcherAppearanceDelay = SwitcherSupport.sanitizedAppearanceDelay(
                    milliseconds: Int($0.rounded()))
            }
        )
    }

    private var dockPreviewBackgroundOpacityPercent: Int {
        Int((DockPreviewSupport.sanitizedBackgroundOpacity(dockPreviewBackgroundOpacity) * 100).rounded())
    }

    private var dockPreviewOpenDelayBinding: Binding<Int> {
        Binding(
            get: { DockPreviewSupport.sanitizedOpenDelay(milliseconds: dockPreviewOpenDelay) },
            set: { dockPreviewOpenDelay = DockPreviewSupport.sanitizedOpenDelay(milliseconds: $0) }
        )
    }

    /// Bounded here as well as in the binding: the field rejects an out-of-range
    /// number as it is typed rather than silently snapping it afterwards.
    private static let dockPreviewOpenDelayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: DockPreviewSupport.openDelayMillisecondsRange.lowerBound)
        formatter.maximum = NSNumber(value: DockPreviewSupport.openDelayMillisecondsRange.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

/// One of the three switcher layouts, drawn as the switcher would look:
/// window previews, one large icon per app under its previews, or a plain
/// list of icons and titles.
private struct SwitcherLayoutChoice: View {
    let layout: SwitcherLayout
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                sketch
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var sketch: some View {
        switch layout {
        case .windows:
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    window(selected: index == 0)
                        .frame(width: 34, height: 26)
                }
            }
        case .icons:
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(spacing: 4) {
                        window(selected: index == 0)
                            .frame(width: 26, height: 18)
                            .opacity(index == 0 ? 1 : 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index == 0 ? Color.accentColor : Color.white.opacity(0.35))
                            .frame(width: 16, height: 16)
                    }
                }
            }
        case .simple:
            // The real one: the selected app's title in a strip, then one
            // icon per app in a row underneath.
            VStack(spacing: 7) {
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 44, height: 4)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index == 0 ? Color.accentColor : Color.white.opacity(0.35))
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
    }

    private func window(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white.opacity(selected ? 0.9 : 0.4))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(height: 4)
                    .padding(.horizontal, 1)
                    .padding(.top, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
    }
}

/// The three ways the switcher can look; `simple` wins over `icons` when
/// both keys are set, as the switcher itself decides.
private enum SwitcherLayout: Hashable {
    case windows, icons, simple
}
