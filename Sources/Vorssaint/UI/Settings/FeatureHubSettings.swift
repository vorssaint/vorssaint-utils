// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Features hub. One switch per feature, grouped in plain language: off
/// means the feature disappears from the whole app (Settings, panel, menu
/// bar, shortcuts) and costs nothing; its configuration is kept for its
/// return. The Permissions tab is the transparency portal: what each system
/// permission does, which features use it right now, and a gentle nudge when
/// one is granted with nothing using it.
struct FeatureHubSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var tab: Tab = .features
    @State private var confirmingPreset: FeaturePreset?

    private enum Tab { case features, permissions }

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    var body: some View {
        Form {
            Section {
                Picker("", selection: $tab) {
                    Text(hub.tabFeatures).tag(Tab.features)
                    Text(hub.tabPermissions).tag(Tab.permissions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(tab == .features ? hub.intro : hub.permissionsIntro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if tab == .features {
                    HStack(spacing: 8) {
                        Text(String(format: hub.activeCountFormat,
                                    features.availableCount, AppFeature.allCases.count))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 8)
                        Button(hub.installAllButton) {
                            FeatureRuntime.shared.setAllAvailable(true)
                        }
                        .disabled(features.availableCount == AppFeature.allCases.count)
                        Button(hub.uninstallAllButton) {
                            FeatureRuntime.shared.setAllAvailable(false)
                        }
                        .disabled(features.availableCount == 0)
                    }
                    .controlSize(.small)
                }
            }
            // The restart notice lives at the very top, never behind a
            // scroll: uninstalling anything makes it impossible to miss.
            if features.needsRestartToUnload {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accentColor)
                        Text(hub.restartNote)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 10)
                        Button(hub.restartButton) {
                            FeatureRuntime.shared.relaunchApp()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.accentColor.opacity(0.12))
                }
            }
            if tab == .features {
                presetsSection
                featureSections
            } else {
                PermissionsPortalSections(hub: hub)
            }
        }
        .formStyle(.grouped)
        .alert(confirmingPreset.map { presetName($0) } ?? "",
               isPresented: Binding(get: { confirmingPreset != nil },
                                    set: { if !$0 { confirmingPreset = nil } }),
               presenting: confirmingPreset) { preset in
            Button(hub.presetConfirmApply) {
                withAnimation(.easeOut(duration: 0.22)) {
                    FeatureRuntime.shared.apply(preset)
                }
            }
            Button(hub.presetConfirmCancel, role: .cancel) {}
        } message: { preset in
            Text(String(format: hub.presetConfirmFormat, presetName(preset)))
        }
    }

    /// Three one-click starting points. Nobody arrives wanting 37 decisions;
    /// a preset shapes the app in one move and everything else stays one
    /// click away in the list below.
    private var presetsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                ForEach(FeaturePreset.allCases) { preset in
                    PresetCard(preset: preset,
                               name: presetName(preset),
                               caption: presetDescription(preset),
                               applyTitle: hub.presetApplyButton) {
                        confirmingPreset = preset
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text(hub.presetsTitle)
        } footer: {
            Text(hub.presetsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func presetName(_ preset: FeaturePreset) -> String {
        switch preset {
        case .essential: return hub.presetEssentialName
        case .windows: return hub.presetWindowsName
        case .battery: return hub.presetBatteryName
        }
    }

    private func presetDescription(_ preset: FeaturePreset) -> String {
        switch preset {
        case .essential: return hub.presetEssentialDesc
        case .windows: return hub.presetWindowsDesc
        case .battery: return hub.presetBatteryDesc
        }
    }

    @ViewBuilder
    private var featureSections: some View {
        ForEach(FeatureGroup.allCases, id: \.self) { group in
            Section {
                ForEach(AppFeature.features(in: group), id: \.self) { feature in
                    FeatureHubRow(feature: feature, hub: hub)
                }
                if group == .monitor,
                   !FeatureVisibilitySupport.monitorFeatures.contains(where: \.isAvailable) {
                    Text(hub.monitorAllOffNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(groupTitle(group))
            }
        }
        Section {
            Text(hub.footerNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func groupTitle(_ group: FeatureGroup) -> String {
        switch group {
        case .windowsDock: return hub.groupWindowsDock
        case .mouseKeyboard: return hub.groupMouseKeyboard
        case .clipboardFiles: return hub.groupClipboardFiles
        case .sound: return hub.groupSound
        case .energyDisplay: return hub.groupEnergyDisplay
        case .tools: return hub.groupTools
        case .monitor: return hub.groupMonitor
        }
    }
}

// MARK: - Preset card

private struct PresetCard: View {
    let preset: FeaturePreset
    let name: String
    let caption: String
    let applyTitle: String
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Button(applyTitle, action: onApply)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name). \(caption)")
    }
}

// MARK: - Feature row

private struct FeatureHubRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var working = false
    let feature: AppFeature
    let hub: FeatureHubStrings

    private var installed: Bool { feature.isAvailable }

    private var energyLabel: String {
        switch feature.energyProfile {
        case .idle: return hub.energyIdle
        case .mouse: return hub.energyMouse
        case .keyboard: return hub.energyKeyboard
        case .inputs: return hub.energyInputs
        case .periodic: return hub.energyPeriodic
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(installed
                        ? AnyShapeStyle(Theme.spaceGradient)
                        : AnyShapeStyle(Color.secondary.opacity(0.22)))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: feature.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(installed ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.hubTitle(l10n.s, hub: hub))
                        .foregroundStyle(installed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    ForEach(feature.permissions, id: \.self) { permission in
                        Image(systemName: permission.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .help(permission.name(hub))
                            .accessibilityHidden(true)
                    }
                    Text(energyLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        .help(hub.energyHelp)
                        .accessibilityHidden(true)
                }
                Text(feature.hubDescription(hub))
                    .font(.caption)
                    .foregroundStyle(installed ? Color.secondary : Color.secondary.opacity(0.6))
            }
            Spacer(minLength: 8)
            if working {
                ProgressView()
                    .controlSize(.small)
            } else if installed {
                Button(hub.uninstallButton) { flip(to: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button(hub.installButton) { flip(to: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feature.hubTitle(l10n.s, hub: hub))
        .accessibilityValue(installed ? "1" : "0")
    }

    /// A quick, honest beat of feedback: the spinner shows the action landed,
    /// then the row fades to its new state. The flip itself is instant.
    private func flip(to install: Bool) {
        guard !working else { return }
        working = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.22)) {
                FeatureRuntime.shared.setAvailable(feature, install)
            }
            working = false
        }
    }
}

// MARK: - Permissions portal

private struct PermissionsPortalSections: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    let hub: FeatureHubStrings
    @State private var automation: [Permissions.AutomationTarget: Permissions.AutomationStatus] = [:]

    var body: some View {
        Section {
            ForEach(AppPermission.allCases, id: \.self) { permission in
                PermissionPortalRow(permission: permission,
                                    hub: hub,
                                    status: status(for: permission))
            }
        }
        .onAppear {
            // Statuses that only refresh at launch/activation get a fresh
            // read the moment the portal shows; automation is checked off the
            // main thread because the AE round trip can block briefly.
            permissions.refresh()
            DispatchQueue.global(qos: .userInitiated).async {
                let finder = Permissions.automationStatus(for: .finder)
                let terminal = Permissions.automationStatus(for: .terminal)
                DispatchQueue.main.async {
                    automation = [.finder: finder, .terminal: terminal]
                }
            }
        }
    }

    private func status(for permission: AppPermission) -> PermissionPortalRow.Status {
        switch permission {
        case .accessibility: return permissions.accessibility ? .granted : .missing
        case .screenRecording: return permissions.screenRecording ? .granted : .missing
        case .fullDiskAccess: return permissions.fullDiskAccess ? .granted : .missing
        case .notifications:
            switch permissions.notifications {
            case .granted: return .granted
            case .denied, .undetermined: return .missing
            case .unknown: return .unknown
            }
        case .automationFinder: return automationStatus(.finder)
        case .automationTerminal: return automationStatus(.terminal)
        case .audioCapture:
            // No public check exists for system audio capture; the mixer
            // reports a failed tap, which is the one readable signal.
            if AppFeature.mixer.isAvailable, AppVolumeMixer.shared.needsPermission {
                return .missing
            }
            return .unknown
        }
    }

    private func automationStatus(_ target: Permissions.AutomationTarget) -> PermissionPortalRow.Status {
        switch automation[target] {
        case .granted: return .granted
        case .denied, .undetermined: return .missing
        case .notDeterminable, .none: return .unknown
        }
    }
}

private struct PermissionPortalRow: View {
    enum Status { case granted, missing, unknown }

    @ObservedObject private var l10n = L10n.shared
    let permission: AppPermission
    let hub: FeatureHubStrings
    let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: permission.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(permission.name(hub))
                        .fontWeight(.medium)
                    statusChip
                }
                Text(permission.explainer(hub))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(usedByLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if status == .granted, activeFeatures.isEmpty {
                    unusedCard
                }
                HStack(spacing: 8) {
                    if status != .granted, hasRequestFlow {
                        Button(hub.requestButton) { request() }
                    }
                    Button(hub.openSystemSettings) { openSystemSettings() }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var activeFeatures: [AppFeature] {
        AppFeature.activeFeatures(using: permission)
    }

    private var usedByLine: String {
        let names = activeFeatures.map { $0.hubTitle(l10n.s, hub: hub) }
        guard !names.isEmpty else { return hub.usedByNone }
        return String(format: hub.usedByFormat, names.joined(separator: ", "))
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(chipColor)
                .frame(width: 6, height: 6)
            Text(chipText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chipColor: Color {
        switch status {
        case .granted: return .green
        case .missing: return .orange
        case .unknown: return .secondary
        }
    }

    private var chipText: String {
        switch status {
        case .granted: return hub.statusGranted
        case .missing: return hub.statusMissing
        case .unknown: return hub.statusUnknown
        }
    }

    private var unusedCard: some View {
        Text(hub.unusedBanner)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private var hasRequestFlow: Bool {
        switch permission {
        case .accessibility, .screenRecording, .fullDiskAccess: return true
        case .notifications: return Permissions.shared.notifications == .undetermined
        case .automationFinder, .automationTerminal, .audioCapture: return false
        }
    }

    private func request() {
        switch permission {
        case .accessibility: Permissions.shared.requestAccessibility()
        case .screenRecording: Permissions.shared.requestScreenRecording()
        case .fullDiskAccess: Permissions.shared.requestFullDiskAccess()
        case .notifications:
            Notifier.requestPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Permissions.shared.refresh()
            }
        case .automationFinder, .automationTerminal, .audioCapture:
            break
        }
    }

    private func openSystemSettings() {
        switch permission {
        case .accessibility: Permissions.shared.openAccessibilitySettings()
        case .screenRecording: Permissions.shared.openScreenRecordingSettings()
        case .fullDiskAccess: Permissions.shared.openFullDiskAccessSettings()
        case .notifications: Permissions.shared.openNotificationSettings()
        case .automationFinder, .automationTerminal: Permissions.shared.openAutomationSettings()
        case .audioCapture: Permissions.shared.openAudioCaptureSettings()
        }
    }
}

// MARK: - Titles, descriptions and permission names

extension AppFeature {
    /// Titles reuse the strings users already see across the app; only names
    /// with no clean existing form live in the hub strings.
    func hubTitle(_ s: Strings, hub: FeatureHubStrings) -> String {
        switch self {
        case .switcher: return s.switcherSection
        case .dockPreview: return s.dockPreviewName
        case .dockClick: return hub.titleDockClick
        case .windowMaximizer: return s.windowMaximizeName
        case .windowLayout: return FeatureStrings.windowLayout(L10n.shared.language).title
        case .autoQuit: return s.autoQuitName
        case .scrollInverter: return s.invertMouseScroll
        case .smoothScroll: return s.smoothScrollName
        case .mouseNavigation: return hub.titleMouseNavigation
        case .middleClick: return s.middleClickSection
        case .keyboardDebounce: return s.keyDebounceName
        case .textSnippets: return FeatureStrings.snippets(L10n.shared.language).pageTitle
        case .clipboardHistory: return FeatureStrings.clipboard(L10n.shared.language).title
        case .pastePlain: return s.pastePlainName
        case .finderCutPaste: return s.cutPasteName
        case .shelf: return s.shelfName
        case .urlCleaner: return s.urlCleanerName
        case .mixer: return s.mixerSection
        case .soundOutputSwitcher: return s.soundOutputSwitcherTitle
        case .micMute: return s.micMuteName
        case .musicBlock: return hub.titleMusicBlock
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .extraBrightness: return s.extraBrightnessName
        case .quickLauncher: return s.launcherName
        case .colorPicker: return s.colorPickerName
        case .screenOCR: return s.ocrName
        case .cleaningMode: return s.cleaningMenuItem
        case .mediaTools: return s.mediaName
        case .cleaner: return s.cleanerName
        case .uninstaller: return s.uninstallerName
        case .homebrew: return s.homebrewName
        case .monitorCPU: return s.monitorShowCPU
        case .monitorGPU: return s.monitorShowGPU
        case .monitorMemory: return s.monitorShowMemory
        case .monitorNetwork: return s.monitorShowNetwork
        case .monitorDisk: return s.diskSection
        case .monitorPower: return s.powerSection
        }
    }

    func hubDescription(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .switcher: return hub.descSwitcher
        case .dockPreview: return hub.descDockPreview
        case .dockClick: return hub.descDockClick
        case .windowMaximizer: return hub.descWindowMaximizer
        case .windowLayout: return hub.descWindowLayout
        case .autoQuit: return hub.descAutoQuit
        case .scrollInverter: return hub.descScrollInverter
        case .smoothScroll: return hub.descSmoothScroll
        case .mouseNavigation: return hub.descMouseNavigation
        case .middleClick: return hub.descMiddleClick
        case .keyboardDebounce: return hub.descKeyboardDebounce
        case .textSnippets: return FeatureStrings.snippets(L10n.shared.language).hubDescription
        case .clipboardHistory: return hub.descClipboardHistory
        case .pastePlain: return hub.descPastePlain
        case .finderCutPaste: return hub.descFinderCutPaste
        case .shelf: return hub.descShelf
        case .urlCleaner: return hub.descURLCleaner
        case .mixer: return hub.descMixer
        case .soundOutputSwitcher: return hub.descSoundOutputSwitcher
        case .micMute: return hub.descMicMute
        case .musicBlock: return hub.descMusicBlock
        case .keepAwake: return hub.descKeepAwake
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).hubDescription
        case .extraBrightness: return hub.descExtraBrightness
        case .quickLauncher: return hub.descQuickLauncher
        case .colorPicker: return hub.descColorPicker
        case .screenOCR: return hub.descScreenOCR
        case .cleaningMode: return hub.descCleaningMode
        case .mediaTools: return hub.descMediaTools
        case .cleaner: return hub.descCleaner
        case .uninstaller: return hub.descUninstaller
        case .homebrew: return hub.descHomebrew
        case .monitorCPU: return hub.descMonitorCPU
        case .monitorGPU: return hub.descMonitorGPU
        case .monitorMemory: return hub.descMonitorMemory
        case .monitorNetwork: return hub.descMonitorNetwork
        case .monitorDisk: return hub.descMonitorDisk
        case .monitorPower: return hub.descMonitorPower
        }
    }
}

extension AppPermission {
    func name(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .accessibility: return hub.permAccessibility
        case .screenRecording: return hub.permScreenRecording
        case .fullDiskAccess: return hub.permFullDisk
        case .notifications: return hub.permNotifications
        case .automationFinder: return hub.permAutomationFinder
        case .automationTerminal: return hub.permAutomationTerminal
        case .audioCapture: return hub.permAudioCapture
        }
    }

    func explainer(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .accessibility: return hub.explainAccessibility
        case .screenRecording: return hub.explainScreenRecording
        case .fullDiskAccess: return hub.explainFullDisk
        case .notifications: return hub.explainNotifications
        case .automationFinder: return hub.explainAutomationFinder
        case .automationTerminal: return hub.explainAutomationTerminal
        case .audioCapture: return hub.explainAudioCapture
        }
    }
}
