// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Dock page: Dock Preview, Dock clicks, keeping the Dock on one display
/// and the window previews Dock Preview shares with the switcher.
struct DockSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @ObservedObject private var dockLock = DockDisplayLockService.shared
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.dockPreviewCurrentSpaceOnly) private var dockPreviewCurrentSpaceOnly = false
    @AppStorage(DefaultsKey.dockPreviewBackgroundOpacity) private var dockPreviewBackgroundOpacity = 1.0
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.dockPreviewOpenDelay) private var dockPreviewOpenDelay = DockPreviewSupport.defaultOpenDelayMilliseconds
    @AppStorage(DefaultsKey.dockPreviewQuitAppOnClose) private var dockPreviewQuitAppOnClose = false
    @AppStorage(DefaultsKey.dockPreviewOrderByCreation) private var dockPreviewOrderByCreation = false
    @AppStorage(DefaultsKey.dockPreviewKeepDockVisible) private var dockPreviewKeepDockVisible = false
    @State private var dockPreviewMoreOptionsExpanded = false
    @AppStorage(DefaultsKey.dockClickMinimize) private var dockClickMinimize = false
    @AppStorage(DefaultsKey.dockClickHide) private var dockClickHide = false
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleWindows = false
    @AppStorage(DefaultsKey.spacesOrderEnabled) private var spacesOrderEnabled = false
    @AppStorage(DefaultsKey.dockDisplayLockEnabled) private var dockDisplayLockEnabled = false
    @AppStorage(DefaultsKey.dockDisplayLockTarget) private var dockDisplayLockTarget = DockDisplayLockTarget.mainStorage
    @AppStorage(DefaultsKey.dockDisplayLockReturns) private var dockDisplayLockReturns = false

    private var pages: SettingsPageStrings { FeatureStrings.settingsPages(l10n.language) }
    private var dockPreviewEngaged: Bool { dockPreviewEnabled && AppFeature.dockPreview.isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(pages.dockTitle).font(.title2.bold())
                    Text(pages.dockDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                if AppFeature.spacesOrder.isAvailable {
                    spacesOrderCard
                        .settingsSectionAnchor(.spacesOrder, cornerRadius: 16)
                }
                if AppFeature.dockDisplayLock.isAvailable {
                    dockDisplayLockCard
                        .settingsSectionAnchor(.dockDisplayLock, cornerRadius: 16)
                }
                if AppFeature.dockPreview.isAvailable {
                    WindowPreviewsCard(sizeKey: DefaultsKey.previewSize,
                                       excludedAppsKey: DefaultsKey.windowPreviewExcludedApps)
                }
                if needsAccessibility, !permissions.accessibility {
                    SettingsCard(title: l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
                if dockPreviewEngaged, !permissions.screenRecording {
                    SettingsCard {
                        PermissionRow(kind: .screenRecording)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
    }

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
                            caption: dockPreviewBackgroundIsGlass
                                ? l10n.s.dockPreviewBackgroundOpacityGlassCaption
                                : l10n.s.dockPreviewBackgroundOpacityCaption) {
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
                    .disabled(dockPreviewBackgroundIsGlass)
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

    private var spacesOrderCard: some View {
        SettingsCard {
            SettingsRow(symbol: AppFeature.spacesOrder.symbolName, title: l10n.s.spacesOrderName,
                        caption: l10n.s.spacesOrderCaption) {
                Toggle(l10n.s.spacesOrderName, isOn: $spacesOrderEnabled)
                    .labelsHidden()
                    .onChange(of: spacesOrderEnabled) { _, _ in
                        SpacesOrderHold.shared.syncWithPreferences()
                    }
            }
        }
    }

    private var dockDisplayLockCard: some View {
        let text = FeatureStrings.dockDisplayLock(l10n.language)
        return SettingsCard(title: text.title) {
            SettingsRow(symbol: AppFeature.dockDisplayLock.symbolName, title: text.title,
                        caption: text.enableCaption) {
                Toggle(text.title, isOn: $dockDisplayLockEnabled)
                    .labelsHidden()
                    .onChange(of: dockDisplayLockEnabled) { _, enabled in
                        DockDisplayLockService.shared.syncWithPreferences()
                        if enabled { DockDisplayLockService.shared.moveDockToAnchor() }
                    }
            }
            if dockDisplayLockEnabled {
                SettingsRow(symbol: "display", title: text.displayPicker,
                            caption: dockDisplayLockChoiceIsAway ? text.fallbackNote : nil) {
                    Picker(text.displayPicker, selection: dockDisplayLockTargetBinding) {
                        Text(text.mainDisplay).tag(DockDisplayLockTarget.main)
                        if dockLock.displays.contains(where: \.isBuiltIn) {
                            Text(text.builtInDisplay).tag(DockDisplayLockTarget.builtIn)
                        }
                        ForEach(dockLock.displays) { display in
                            Text(display.name).tag(DockDisplayLockTarget.display(uuid: display.uuid))
                        }
                        if dockDisplayLockChoiceIsAway {
                            Text(text.disconnectedDisplay).tag(dockDisplayLockChoice)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
                dockDisplayLockStatus(text)
                SettingsRow(symbol: "arrow.uturn.backward", title: text.returnsToggle,
                            caption: text.returnsCaption) {
                    Toggle(text.returnsToggle, isOn: $dockDisplayLockReturns)
                        .labelsHidden()
                }
            }
        }
        .onAppear { if dockDisplayLockEnabled { dockLock.refresh() } }
    }

    /// Where the Dock is now, and a way to send it where it belongs when it
    /// is somewhere else.
    @ViewBuilder
    private func dockDisplayLockStatus(_ text: DockDisplayLockStrings) -> some View {
        if dockLock.displays.count < 2 {
            Label(text.singleDisplay, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !NSScreen.screensHaveSeparateSpaces {
            Label(text.spacesOff, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let dock = dockLock.displays.first(where: { $0.id == dockLock.dockDisplayID }) {
            HStack(spacing: 10) {
                Label(String(format: text.dockLocationFormat, dock.name),
                      systemImage: dock.id == dockLock.anchorID ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if dock.id != dockLock.anchorID, permissions.accessibility {
                    Button(text.moveButton) { DockDisplayLockService.shared.moveDockToAnchor() }
                        .disabled(dockLock.isMovingDock)
                }
            }
        }
    }

    private var dockDisplayLockChoice: DockDisplayLockTarget {
        DockDisplayLockTarget(storage: dockDisplayLockTarget)
    }

    /// A display picked by name that is not connected right now: the choice
    /// stays, and the picker says so instead of showing the fallback.
    private var dockDisplayLockChoiceIsAway: Bool {
        guard case let .display(uuid) = dockDisplayLockChoice else { return false }
        return !dockLock.displays.contains { $0.uuid == uuid }
    }

    private var dockDisplayLockTargetBinding: Binding<DockDisplayLockTarget> {
        Binding {
            dockDisplayLockChoice
        } set: { target in
            dockDisplayLockTarget = target.storageValue
            DockDisplayLockService.shared.syncWithPreferences()
            // Once the picker's menu has closed: called while it was still
            // closing, the press on the edge left the Dock where it was.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                DockDisplayLockService.shared.moveDockToAnchor()
            }
        }
    }

    // MARK: - State

    /// Dock Preview and every Dock click action work through Accessibility;
    /// the catalog knows which of them are on right now.
    private var needsAccessibility: Bool {
        FeatureVisibilitySupport.isPermissionNeeded(
            on: .dock, activeFeatures: AppFeature.activeFeatures(using: .accessibility))
    }

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

    /// The slider only fades the classic material. Liquid Glass takes its
    /// transparency from System Settings, so the slider has nothing to change.
    private var dockPreviewBackgroundIsGlass: Bool {
        HUDBackdrop.drawsLiquidGlass(enabled: liquidGlassEnabled, reduceTransparency: reduceTransparency)
    }

    private var dockPreviewBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { DockPreviewSupport.sanitizedBackgroundOpacity(dockPreviewBackgroundOpacity) },
            set: { dockPreviewBackgroundOpacity = DockPreviewSupport.sanitizedBackgroundOpacity($0) }
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

