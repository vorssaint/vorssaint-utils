// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Switcher page: the app switcher chosen from three drawn layouts, its
/// shortcuts and options as rows and chips, then its window previews.
struct SwitcherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherShortcut) private var switcherShortcutStorage = GlobalShortcut.switcherDefault.storageValue
    @AppStorage(DefaultsKey.switcherTakeOverSystemShortcuts) private var switcherTakeOverSystemShortcuts = false
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var switcherSimpleMode = false
    @AppStorage(DefaultsKey.switcherMergeTabs) private var switcherMergeTabs = false
    @AppStorage(DefaultsKey.switcherWindowlessApps) private var switcherWindowlessApps = SwitcherWindowlessApps.fallback.rawValue
    @AppStorage(DefaultsKey.switcherMinimizedPlacement) private var switcherMinimizedPlacement = WindowSwitchMinimizedPlacement.normal.rawValue
    @AppStorage(DefaultsKey.switcherTreatHiddenAppsLikeMinimized) private var switcherTreatHiddenAppsLikeMinimized = true
    @AppStorage(DefaultsKey.switcherShowFullscreenWindows) private var switcherShowFullscreenWindows = true
    @AppStorage(DefaultsKey.switcherScreenPlacement) private var switcherScreenPlacement = SwitcherScreenPlacement.fallback.rawValue
    @AppStorage(DefaultsKey.switcherCurrentDisplayOnly) private var switcherCurrentDisplayOnly = false
    @AppStorage(DefaultsKey.switcherCurrentSpaceOnly) private var switcherCurrentSpaceOnly = false
    @AppStorage(DefaultsKey.switcherSearchPinEnabled) private var switcherSearchPinEnabled = false
    @AppStorage(DefaultsKey.switcherShowShortcutHints) private var switcherShowShortcutHints = true
    @AppStorage(DefaultsKey.switcherAppearanceDelay) private var switcherAppearanceDelay = SwitcherSupport.defaultAppearanceDelayMilliseconds
    private var pages: SettingsPageStrings { FeatureStrings.settingsPages(l10n.language) }
    private var switcherEngaged: Bool { switcherEnabled && AppFeature.switcher.isAvailable }
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
                if AppFeature.switcher.isAvailable {
                    WindowPreviewsCard(sizeKey: DefaultsKey.switcherPreviewSize)
                }
                if switcherEngaged {
                    if !permissions.accessibility {
                        SettingsCard(title: l10n.s.permissionRequired) {
                            PermissionRow(kind: .accessibility)
                        }
                    }
                    if !permissions.screenRecording,
                       SwitcherSupport.capturesPreviews(simpleMode: switcherSimpleMode) {
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
                            (GlobalShortcut(storageValue: switcherShortcutStorage) ?? .switcherDefault).displayString))
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
            if switcherMinimizedPlacement != WindowSwitchMinimizedPlacement.normal.rawValue {
                SettingsRow(symbol: "eye.slash", title: l10n.s.switcherTreatHiddenAppsLikeMinimized) {
                    Toggle(l10n.s.switcherTreatHiddenAppsLikeMinimized,
                           isOn: $switcherTreatHiddenAppsLikeMinimized)
                        .labelsHidden()
                        .onChange(of: switcherTreatHiddenAppsLikeMinimized) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                }
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
            // The three screen choices outgrow the card at the default window
            // width in most languages; wrapping keeps every label whole.
            FlowLayoutLite(spacing: 8) {
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

    // MARK: - State

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
}

/// The window previews card on the Switcher and Dock pages: each page sizes
/// its own previews, while the minimal look and the exclusions are shared.
struct WindowPreviewsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @AppStorage private var previewSize: String

    init(sizeKey: String) {
        _previewSize = AppStorage(wrappedValue: "normal", sizeKey)
    }

    var body: some View {
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
