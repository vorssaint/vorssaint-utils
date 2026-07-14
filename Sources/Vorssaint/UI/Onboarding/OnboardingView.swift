// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ServiceManagement
import SwiftUI

/// First-run experience, also reachable later through Settings › About.
/// Covers welcome and language, permissions, monitor setup, optional features,
/// status verification and the final summary.
enum OnboardingMode {
    case full

    var steps: [OnboardingStep] {
        // Ten pages on purpose: setup and permissions first, the quick panel
        // right after the panel pages (it is the app's fastest entry point),
        // and one single page that turns the optional features on. The old
        // per-feature showcase pages moved into that page as plain toggles;
        // each feature's Settings page still teaches the details.
        [.welcome, .accessibility, .screenRecording, .monitor, .menuBarSetup,
         .panelSetup, .quickPanel, .optionalFeatures, .purpose,
         .status, .done]
    }

    func title(_ strings: Strings) -> String {
        strings.obStepWelcomeTitle
    }
}

enum OnboardingStep {
    case welcome, accessibility, screenRecording, monitor, menuBarSetup, panelSetup, optionalFeatures
    case quickPanel
    case purpose
    case status, done
}

struct OnboardingView: View {
    var mode: OnboardingMode = .full
    var onFinish: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    /// Persisted so the flow resumes where it stopped — macOS relaunches the
    /// app when Screen Recording is granted mid-onboarding.
    @AppStorage(DefaultsKey.onboardingStep) private var index = 0

    private var steps: [OnboardingStep] { mode.steps }
    private var current: OnboardingStep { steps[min(max(0, index), steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable so a step taller than the window (the menu bar
            // metrics list outgrew it, issue #176) can never push the
            // navigation bar out of the fixed frame — without a scroll, the
            // footer was clipped away and the flow looked stuck.
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider()
            navigationBar
        }
        .frame(width: 540, height: 600)
        .onAppear {
            if !steps.indices.contains(index) { index = 0 }
            // Onboarding narrates the permission trip itself; the floating
            // guide card would just double the voice.
            PermissionGuideOverlay.suppressed = true
        }
        .onDisappear {
            PermissionGuideOverlay.suppressed = false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch current {
        case .welcome: WelcomeStep()
        case .accessibility: PermissionStep(kind: .accessibility,
                                            icon: "accessibility",
                                            title: l10n.s.obStepAccessibilityTitle,
                                            body: l10n.s.obStepAccessibilityBody,
                                            why: l10n.s.obAccessibilityWhy)
        case .screenRecording: PermissionStep(kind: .screenRecording,
                                              icon: "rectangle.dashed.badge.record",
                                              title: l10n.s.obStepRecordingTitle,
                                              body: l10n.s.obStepRecordingBody,
                                              why: l10n.s.obRecordingWhy)
        case .monitor: MonitorStep()
        case .menuBarSetup: MenuBarSetupStep()
        case .panelSetup: PanelSetupStep()
        case .quickPanel: QuickPanelShowcaseStep()
        case .optionalFeatures: OptionalFeaturesStep()
        case .purpose: PurposeStep()
        case .status: StatusStep()
        case .done: DoneStep()
        }
    }

    private var navigationBar: some View {
        HStack {
            Button(l10n.s.obBack) {
                withAnimation(.easeInOut(duration: 0.2)) { index = max(0, index - 1) }
            }
            .disabled(index == 0)

            Spacer()

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: i == index ? 18 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
                }
            }

            Spacer()

            Button(primaryButtonTitle) {
                if index >= steps.count - 1 {
                    index = 0
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var primaryButtonTitle: String {
        if index >= steps.count - 1 { return l10n.s.obStart }
        switch current {
        case .accessibility where !permissions.accessibility,
             .screenRecording where !permissions.screenRecording:
            return l10n.s.obSkipStep
        default:
            return l10n.s.obContinue
        }
    }
}

// MARK: - Step 1: welcome & language

private struct WelcomeStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.spaceGradient
                VStack(spacing: 10) {
                    BrandMark(width: 130)
                    Text(AppInfo.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(l10n.s.obStepWelcomeBody)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 12)
            }
            .frame(height: 220)

            VStack(alignment: .leading, spacing: 16) {
                Picker(l10n.s.obLanguageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                // A menu (not segmented): with nine languages a segmented control
                // would overflow, and several names are in their own script.
                .pickerStyle(.menu)

                featureRow(icon: "bolt.fill",
                           title: l10n.s.obWelcomeBullet1Title,
                           text: l10n.s.obWelcomeBullet1Body)
                featureRow(icon: "gauge.with.dots.needle.50percent",
                           title: l10n.s.obWelcomeBullet2Title,
                           text: l10n.s.obWelcomeBullet2Body)
                featureRow(icon: "rectangle.on.rectangle",
                           title: l10n.s.obWelcomeBullet3Title,
                           text: l10n.s.obWelcomeBullet3Body)
            }
            .padding(24)
        }
    }

    private func featureRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.spaceGradient)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Steps 2–3: permissions

private struct PermissionStep: View {
    @ObservedObject private var l10n = L10n.shared
    let kind: PermissionKind
    let icon: String
    let title: String
    let body_: String
    let why: String

    init(kind: PermissionKind, icon: String, title: String, body: String, why: String) {
        self.kind = kind
        self.icon = icon
        self.title = title
        self.body_ = body
        self.why = why
    }

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: icon, title: title, subtitle: body_)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(kind: kind)
                Text(l10n.s.permissionRestartNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Text(why)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)

            Spacer()
        }
    }
}

// MARK: - Purpose step: one answer shapes the whole app

/// "What brought you here?" — the answers are the hub's own bundles, same
/// names and descriptions, so onboarding and the Features hub speak one
/// language. One click applies the bundle and the app leaves setup already
/// shaped for it. Skipping keeps everything at hand.
private struct PurposeStep: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var chosen: FeaturePreset?

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: "sparkles.rectangle.stack",
                       title: l10n.s.obPurposeTitle,
                       subtitle: l10n.s.obPurposeBody)

            VStack(spacing: 8) {
                ForEach(FeaturePreset.allCases) { preset in
                    bundleCard(preset)
                }
            }
            .padding(.horizontal, 28)

            Text(l10n.s.obPurposeSkip)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func name(_ preset: FeaturePreset) -> String {
        switch preset {
        case .essential: return hub.presetEssentialName
        case .windows: return hub.presetWindowsName
        case .battery: return hub.presetBatteryName
        }
    }

    private func caption(_ preset: FeaturePreset) -> String {
        switch preset {
        case .essential: return hub.presetEssentialDesc
        case .windows: return hub.presetWindowsDesc
        case .battery: return hub.presetBatteryDesc
        }
    }

    private func bundleCard(_ preset: FeaturePreset) -> some View {
        let selected = chosen == preset
        return Button {
            guard !selected else { return }
            chosen = preset
            withAnimation(.easeOut(duration: 0.2)) {
                FeatureRuntime.shared.apply(preset)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(preset))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    Text(caption(preset))
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.05)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: chosen)
    }
}

// MARK: - Step 4: system monitor

private struct MonitorStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        // The live System preview is the tallest step and can exceed the window,
        // so it scrolls. The navigation bar lives outside `content`, so Back and
        // Continue stay pinned and visible regardless of scroll position.
        ScrollView {
            VStack(spacing: 18) {
                StepHeader(icon: "gauge.with.dots.needle.50percent",
                           title: l10n.s.obStepMonitorTitle,
                           subtitle: l10n.s.obStepMonitorBody)

                // A live taste of the panel's System section.
                SystemSection()
                    .frame(width: 320)
                    .onAppear { SystemMonitor.shared.panelDidAppear() }
                    .onDisappear { SystemMonitor.shared.panelDidDisappear() }

                Text(l10n.s.obMonitorNoPermission)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Menu bar setup (live preview + toggles)

/// New-feature step: a live preview of the menu bar with the toggles right
/// there, so people choose what to pin before they ever open Settings. Shown in
/// the first-run flow and as the one-time "what's new" pass for updaters.
private struct MenuBarSetupStep: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.menuBarCPU) private var cpu = false
    @AppStorage(DefaultsKey.menuBarGPU) private var gpu = false
    @AppStorage(DefaultsKey.menuBarMemory) private var memory = false
    @AppStorage(DefaultsKey.menuBarCPUTemperature) private var cpuTemperature = false
    @AppStorage(DefaultsKey.menuBarGPUTemperature) private var gpuTemperature = false
    @AppStorage(DefaultsKey.menuBarBatteryTemperature) private var batteryTemperature = false
    @AppStorage(DefaultsKey.menuBarNetwork) private var network = false
    @AppStorage(DefaultsKey.menuBarDiskUsage) private var diskUsage = false
    @AppStorage(DefaultsKey.menuBarDiskActivity) private var diskActivity = false
    @AppStorage(DefaultsKey.menuBarBattery) private var battery = false
    @AppStorage(DefaultsKey.menuBarBatteryTime) private var batteryTime = false
    @AppStorage(DefaultsKey.menuBarPeripheralBattery) private var peripheralBattery = false
    @AppStorage(DefaultsKey.menuBarPower) private var power = false

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(icon: "menubar.rectangle",
                       title: l10n.s.obStepMenuBarTitle,
                       subtitle: l10n.s.obStepMenuBarBody)

            MenuBarMetricsPreview()
                .padding(.horizontal, 28)

            VStack(spacing: 0) {
                toggle(l10n.s.monitorShowCPU, $cpu)
                Divider()
                toggle(l10n.s.monitorShowGPU, $gpu)
                Divider()
                toggle(l10n.s.monitorShowMemory, $memory)
                Divider()
                toggle(l10n.s.monitorShowCPUTemperature, $cpuTemperature)
                Divider()
                toggle(l10n.s.monitorShowGPUTemperature, $gpuTemperature)
                Divider()
                toggle(l10n.s.monitorShowBatteryTemperature, $batteryTemperature)
                Divider()
                toggle(l10n.s.monitorShowNetwork, $network)
                Divider()
                toggle(l10n.s.monitorItemDiskUsage, $diskUsage)
                Divider()
                toggle(l10n.s.monitorItemDiskActivity, $diskActivity)
                Divider()
                toggle(l10n.s.batteryLabel, $battery)
                Divider()
                toggle(FeatureStrings.batteryTime(l10n.language).title, $batteryTime)
                Divider()
                toggle(l10n.s.monitorShowPeripheralBattery, $peripheralBattery)
                Divider()
                toggle(l10n.s.monitorShowPowerLabel, $power)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Text(l10n.s.obStepMenuBarNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)

            Spacer()
        }
    }

    private func toggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.vertical, 6)
    }
}

// MARK: - Panel setup (what's in the panel — expandable per-section config)

private struct PanelSetupStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(icon: "rectangle.stack",
                       title: l10n.s.obStepPanelTitle,
                       subtitle: l10n.s.obStepPanelBody)
            Form {
                MonitorPanelConfig()
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Step 5: optional features

private struct OptionalFeaturesStep: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var cutPasteEnabled = false
    @AppStorage(DefaultsKey.autoQuitEnabled) private var autoQuitEnabled = false
    @AppStorage(DefaultsKey.shelfEnabled) private var shelfEnabled = false

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: "slider.horizontal.3",
                       title: l10n.s.obStepOptionalTitle,
                       subtitle: l10n.s.obStepOptionalBody)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(l10n.s.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.invertMouseScroll, isOn: $inverterEnabled)
                        .onChange(of: inverterEnabled) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                        }
                    Text(l10n.s.scrollTrackpadNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.switcherEnable, isOn: $switcherEnabled)
                        .onChange(of: switcherEnabled) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                    Text(l10n.s.switcherEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.cutPasteEnable, isOn: $cutPasteEnabled)
                        .onChange(of: cutPasteEnabled) { _, _ in
                            FinderCutPaste.shared.syncWithPreferences()
                        }
                    Text(l10n.s.cutPasteEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.autoQuitEnable, isOn: $autoQuitEnabled)
                        .onChange(of: autoQuitEnabled) { _, _ in
                            AutoQuitService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.autoQuitEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.shelfEnable, isOn: $shelfEnabled)
                        .onChange(of: shelfEnabled) { _, _ in
                            ShelfService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.shelfEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Spacer()
        }
    }
}

// MARK: - Step 6: status verification

private struct StatusStep: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var cutPasteEnabled = false
    @AppStorage(DefaultsKey.autoQuitEnabled) private var autoQuitEnabled = false

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: "checklist",
                       title: l10n.s.obStepStatusTitle,
                       subtitle: l10n.s.obStepStatusBody)

            VStack(spacing: 0) {
                statusRow(name: l10n.s.permissionAccessibility,
                          // Cut and paste and quit on close moved into the
                          // optional-features page; both need accessibility.
                          needed: inverterEnabled || switcherEnabled
                              || cutPasteEnabled || autoQuitEnabled,
                          granted: permissions.accessibility)
                Divider().padding(.vertical, 8)
                statusRow(name: l10n.s.permissionScreenRecording,
                          needed: switcherEnabled,
                          granted: permissions.screenRecording)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Button(l10n.s.obStatusRecheck) {
                permissions.refresh()
            }
            .controlSize(.small)

            Text(l10n.s.permissionRestartNote)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private func statusRow(name: String, needed: Bool, granted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill"
                                      : (needed ? "exclamationmark.circle.fill" : "minus.circle"))
                .foregroundStyle(granted ? .green : (needed ? .orange : .secondary))
            Text(name)
            Spacer()
            Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                .font(.caption)
                .foregroundStyle(granted ? .green : (needed ? .orange : .secondary))
        }
    }
}

// MARK: - Step 7: done

private struct DoneStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.spaceGradient
                VStack(spacing: 14) {
                    BrandMark(width: 150)
                    Text(l10n.s.obStepDoneTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(l10n.s.obStepDoneBody)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(height: 300)

            VStack(spacing: 10) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text(l10n.s.obDoneHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
            .padding(.top, 36)

            Spacer()
        }
    }
}

// MARK: - Shared header

private struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.spaceGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 19, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 48)
        }
        .padding(.top, 30)
    }
}
