// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Mouse & Trackpad page: a legend of every mouse feature and whether it
/// is on, each one a click away from its card, then one card per feature.
struct MouseSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var inverter = ScrollInverter.shared
    @ObservedObject private var smoothScroll = SmoothScrollService.shared
    @ObservedObject private var mouseNavigation = MouseNavigationService.shared
    @ObservedObject private var middleClick = MiddleClickService.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var invertVertical = false
    @AppStorage(DefaultsKey.scrollInverterHorizontalEnabled) private var invertHorizontal = false
    @AppStorage(DefaultsKey.scrollHorizontalEnabled) private var horizontalScrollEnabled = false
    @AppStorage(DefaultsKey.scrollHorizontalModifier) private var horizontalScrollModifier =
        ScrollHorizontalModifier.shift
    @AppStorage(DefaultsKey.focusFollowsMouseEnabled) private var focusFollowsMouseEnabled = false
    @AppStorage(DefaultsKey.focusFollowsMouseDelay) private var focusFollowsMouseDelay =
        FocusFollowsMouseSupport.defaultDelayMilliseconds
    @AppStorage(DefaultsKey.smoothScrollEnabled) private var smoothScrollEnabled = false
    @AppStorage(DefaultsKey.smoothScrollStep) private var smoothScrollStep = SmoothScrollSupport.defaultStep
    @AppStorage(DefaultsKey.mouseAccelerationDisabled) private var mouseAccelerationDisabled = false
    @AppStorage(DefaultsKey.smoothScrollResponse) private var smoothScrollResponse =
        SmoothScrollSupport.defaultResponse
    @AppStorage(DefaultsKey.smoothScrollCoast) private var smoothScrollCoast =
        SmoothScrollSupport.defaultCoast
    @AppStorage(DefaultsKey.mouseNavigationEnabled) private var mouseNavigationEnabled = false
    @AppStorage(DefaultsKey.mouseButtonShortcutsEnabled) private var mouseButtonShortcutsEnabled = false
    @AppStorage(DefaultsKey.mouseSpacesGestureEnabled) private var spacesEnabled = false
    @AppStorage(DefaultsKey.middleClickEnabled) private var middleClickEnabled = false
    @AppStorage(DefaultsKey.middleClickTapFingers) private var middleClickTapFingers = 0
    @AppStorage(DefaultsKey.mouseClickDebounceEnabled) private var mouseClickDebounceEnabled = false
    @AppStorage(DefaultsKey.mouseClickDebounceWindowMs) private var mouseClickDebounceWindow =
        Defaults.defaultMouseClickDebounceWindowMs
    @State private var smoothScrollMoreOptionsExpanded = false

    private var mouseClickDebounceText: MouseClickDebounceStrings {
        FeatureStrings.mouseClickDebounce(l10n.language)
    }

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.s.tabMouse).font(.title2.bold())
                    Text(FeatureStrings.settingsPages(l10n.language).mouseDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !legendFeatures.isEmpty {
                    legendCard
                }
                if AppFeature.scrollInverter.isAvailable || AppFeature.scrollHorizontal.isAvailable {
                    scrollCard
                        .settingsSectionAnchor(.scrollDirection, cornerRadius: 16)
                }
                if AppFeature.focusFollowsMouse.isAvailable {
                    focusFollowsMouseCard
                        .settingsSectionAnchor(.focusFollowsMouse, cornerRadius: 16)
                }
                if AppFeature.smoothScroll.isAvailable {
                    smoothScrollCard
                        .settingsSectionAnchor(.smoothScroll, cornerRadius: 16)
                }
                if AppFeature.mouseAcceleration.isAvailable {
                    accelerationCard
                        .settingsSectionAnchor(.mouseAcceleration, cornerRadius: 16)
                }
                if AppFeature.mouseNavigation.isAvailable {
                    navigationCard
                        .settingsSectionAnchor(.mouseNavigation, cornerRadius: 16)
                }
                if AppFeature.mouseButtonShortcuts.isAvailable {
                    MouseButtonShortcutsSection()
                }
                if AppFeature.mouseClickDebounce.isAvailable {
                    clickDebounceCard
                        .settingsSectionAnchor(.mouseClickDebounce, cornerRadius: 16)
                }
                if AppFeature.middleClick.isAvailable {
                    middleClickCard
                        .settingsSectionAnchor(.middleClick, cornerRadius: 16)
                }
                if accessibilityNoteVisible {
                    SettingsCard(title: l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
        .onAppear {
            MiddleClickService.shared.refreshDragGestureConflict()
        }
    }

    // MARK: - Overview

    /// The mouse features on this page, in page order, for the legend.
    private var legendFeatures: [AppFeature] {
        [.scrollInverter, .scrollHorizontal, .focusFollowsMouse, .smoothScroll, .mouseAcceleration,
         .mouseNavigation, .mouseButtonShortcuts, .mouseClickDebounce, .middleClick]
            .filter(\.isAvailable)
    }

    /// Whether the feature is switched on here, so the legend agrees with
    /// the switches below.
    private func isOn(_ feature: AppFeature) -> Bool {
        switch feature {
        case .scrollInverter: return invertVertical || invertHorizontal
        case .scrollHorizontal: return horizontalScrollEnabled
        case .focusFollowsMouse: return focusFollowsMouseEnabled
        case .smoothScroll: return smoothScrollEnabled
        case .mouseAcceleration: return mouseAccelerationDisabled
        case .mouseNavigation: return mouseNavigationEnabled
        case .mouseButtonShortcuts: return mouseButtonShortcutsEnabled || spacesEnabled
        case .mouseClickDebounce: return mouseClickDebounceEnabled
        case .middleClick: return middleClickEnabled
        default: return false
        }
    }

    /// Every feature with a light for on or off; clicking one lands on its
    /// card, centered and lit, the same way a search result does.
    private var legendCard: some View {
        SettingsCard {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 4)], alignment: .leading, spacing: 2) {
                ForEach(legendFeatures, id: \.self) { feature in
                    let on = isOn(feature)
                    Button {
                        SettingsRouter.shared.request(feature.settingsDestination,
                                                      sidebarFeature: feature)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(on ? Color.accentColor : Color.secondary.opacity(0.35))
                                .frame(width: 8, height: 8)
                            Text(feature.hubTitle(l10n.s, hub: hub))
                                .font(.callout)
                                .foregroundStyle(on ? .primary : .secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Scrolling

    private var scrollCard: some View {
        SettingsCard(title: l10n.s.scrollSection) {
            if AppFeature.scrollInverter.isAvailable {
                SettingsRow(symbol: "arrow.up.arrow.down", title: l10n.s.invertVerticalScroll) {
                    Toggle(l10n.s.invertVerticalScroll, isOn: $invertVertical)
                        .labelsHidden()
                        .onChange(of: invertVertical) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                            if scrollDirectionEnabled { permissions.requestAccessibility() }
                        }
                }
                SettingsRow(symbol: "arrow.left.arrow.right", title: l10n.s.invertHorizontalScroll) {
                    Toggle(l10n.s.invertHorizontalScroll, isOn: $invertHorizontal)
                        .labelsHidden()
                        .onChange(of: invertHorizontal) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                            if scrollDirectionEnabled { permissions.requestAccessibility() }
                        }
                }
            }
            if AppFeature.scrollHorizontal.isAvailable {
                SettingsRow(symbol: "arrow.left.and.right", title: l10n.s.scrollHorizontalName,
                            caption: l10n.s.scrollHorizontalCaption) {
                    Toggle(l10n.s.scrollHorizontalName, isOn: $horizontalScrollEnabled)
                        .labelsHidden()
                        .onChange(of: horizontalScrollEnabled) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                            if scrollDirectionEnabled { permissions.requestAccessibility() }
                        }
                }
                if horizontalScrollEnabled {
                    modifierKeys
                        .padding(.leading, settingsRowTextInset)
                }
            }
            if scrollInversionEnabled, inverter.isRunning {
                activeBadge(l10n.s.scrollActiveNow)
            }
            Text(l10n.s.scrollTrackpadNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if scrollDirectionEnabled {
                MouseExceptionsList(scope: .scrollDirection)
            }
        }
    }

    /// The key to hold, as keycaps: one glance says which key, no menu.
    private var modifierKeys: some View {
        let modifierStrings = FeatureStrings.quitProtection(l10n.language)
        let choices: [(ScrollHorizontalModifier, String, String)] = [
            (.shift, "⇧", modifierStrings.shiftKey),
            (.option, "⌥", modifierStrings.optionKey),
            (.control, "⌃", modifierStrings.controlKey),
            (.command, "⌘", l10n.s.scrollHorizontalCommandKey),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text(l10n.s.scrollHorizontalModifierLabel)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(choices, id: \.0) { modifier, glyph, name in
                    let selected = horizontalScrollModifier == modifier
                    Button {
                        horizontalScrollModifier = modifier
                    } label: {
                        HStack(spacing: 6) {
                            Text(glyph)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(name)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.14),
                                              lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Focus follows mouse

    private var focusFollowsMouseCard: some View {
        SettingsCard {
            SettingsRow(symbol: "macwindow.and.cursorarrow", title: l10n.s.focusFollowsMouseName,
                        caption: l10n.s.focusFollowsMouseCaption) {
                Toggle(l10n.s.focusFollowsMouseName, isOn: $focusFollowsMouseEnabled)
                    .labelsHidden()
                    .onChange(of: focusFollowsMouseEnabled) { _, enabled in
                        FocusFollowsMouseService.shared.syncWithPreferences()
                        if enabled { Permissions.shared.requestAccessibility() }
                    }
            }
            if focusFollowsMouseEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    sliderRow(l10n.s.focusFollowsMouseDelay,
                              value: focusFollowsMouseDelayBinding,
                              range: Double(FocusFollowsMouseSupport.delayRange.lowerBound)
                                  ... Double(FocusFollowsMouseSupport.delayRange.upperBound),
                              step: 50,
                              readout: "\(focusFollowsMouseDelay) ms")
                    MouseExceptionsList(scope: .focusFollowsMouse)
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    // MARK: - Smooth scrolling

    private var smoothScrollCard: some View {
        SettingsCard {
            SettingsRow(symbol: "scroll", title: l10n.s.smoothScrollName, caption: l10n.s.smoothScrollCaption) {
                Toggle(l10n.s.smoothScrollName, isOn: $smoothScrollEnabled)
                    .labelsHidden()
                    .onChange(of: smoothScrollEnabled) { _, enabled in
                        SmoothScrollService.shared.syncWithPreferences()
                        if enabled { permissions.requestAccessibility() }
                    }
            }
            if smoothScrollEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    sliderRow(l10n.s.smoothScrollStepLabel,
                              value: smoothScrollStepBinding,
                              range: Double(SmoothScrollSupport.stepRange.lowerBound)
                                  ... Double(SmoothScrollSupport.stepRange.upperBound),
                              step: 10,
                              readout: "\(SmoothScrollSupport.sanitizedStep(smoothScrollStep))")
                    DisclosureGroup(isExpanded: $smoothScrollMoreOptionsExpanded) {
                        sliderRow(l10n.s.smoothScrollResponseLabel,
                                  value: smoothScrollResponseBinding,
                                  range: Double(SmoothScrollSupport.responseRange.lowerBound)
                                      ... Double(SmoothScrollSupport.responseRange.upperBound),
                                  step: 5,
                                  readout: "\(SmoothScrollSupport.sanitizedResponse(smoothScrollResponse))%")
                            .padding(.top, 6)
                        sliderRow(l10n.s.smoothScrollCoastLabel,
                                  value: smoothScrollCoastBinding,
                                  range: Double(SmoothScrollSupport.coastRange.lowerBound)
                                      ... Double(SmoothScrollSupport.coastRange.upperBound),
                                  step: 5,
                                  readout: "\(SmoothScrollSupport.sanitizedCoast(smoothScrollCoast))%")
                            .padding(.top, 6)
                    } label: {
                        Text(mouseClickDebounceText.moreOptions)
                            .font(.subheadline.weight(.medium))
                    }
                    MouseExceptionsList(scope: .smoothScroll)
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, readout: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(minWidth: 96, alignment: .leading)
            Slider(value: value, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    // MARK: - Acceleration, side buttons, click filter, middle click

    private var accelerationCard: some View {
        SettingsCard {
            SettingsRow(symbol: "cursorarrow.motionlines", title: l10n.s.mouseAccelerationName,
                        caption: l10n.s.mouseAccelerationCaption) {
                Toggle(l10n.s.mouseAccelerationName, isOn: $mouseAccelerationDisabled)
                    .labelsHidden()
                    .onChange(of: mouseAccelerationDisabled) { _, _ in
                        MouseAccelerationService.shared.syncWithPreferences()
                    }
            }
        }
    }

    private var navigationCard: some View {
        SettingsCard(title: l10n.s.mouseNavigationSection) {
            SettingsRow(symbol: "arrowshape.turn.up.left", title: l10n.s.mouseNavigationEnable,
                        caption: l10n.s.mouseNavigationCaption) {
                Toggle(l10n.s.mouseNavigationEnable, isOn: $mouseNavigationEnabled)
                    .labelsHidden()
                    .onChange(of: mouseNavigationEnabled) { _, enabled in
                        MouseNavigationService.shared.syncWithPreferences()
                        if enabled { permissions.requestAccessibility() }
                    }
            }
            if mouseNavigationEnabled, mouseNavigation.isRunning {
                activeBadge(l10n.s.mouseNavigationActiveNow)
            }
            if mouseNavigationEnabled {
                MouseExceptionsList(scope: .navigation)
            }
        }
    }

    private var clickDebounceCard: some View {
        SettingsCard {
            SettingsRow(symbol: "cursorarrow.click.badge.clock", title: mouseClickDebounceText.title,
                        caption: mouseClickDebounceText.caption) {
                Toggle(mouseClickDebounceText.title, isOn: $mouseClickDebounceEnabled)
                    .labelsHidden()
                    .onChange(of: mouseClickDebounceEnabled) { _, enabled in
                        MouseClickDebounceService.shared.syncWithPreferences()
                        if enabled { permissions.requestAccessibility() }
                    }
            }
            if mouseClickDebounceEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: mouseClickDebounceWindowBinding,
                            in: Defaults.allowedMouseClickDebounceWindowRange,
                            step: 1) {
                        HStack {
                            Text(mouseClickDebounceText.windowLabel)
                            Spacer()
                            Text("\(Defaults.sanitizedMouseClickDebounceWindow(mouseClickDebounceWindow)) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(mouseClickDebounceText.windowCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var middleClickCard: some View {
        SettingsCard(title: l10n.s.middleClickSection) {
            SettingsRow(symbol: "hand.tap", title: l10n.s.middleClickEnable,
                        caption: l10n.s.middleClickEnableCaption) {
                Toggle(l10n.s.middleClickEnable, isOn: $middleClickEnabled)
                    .labelsHidden()
                    .onChange(of: middleClickEnabled) { _, enabled in
                        MiddleClickService.shared.syncWithPreferences()
                        if enabled { permissions.requestAccessibility() }
                    }
            }
            if middleClickEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.s.middleClickTapPicker)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        tapChip(0, title: l10n.s.middleClickTapOff, symbol: "hand.raised.slash")
                        tapChip(3, title: l10n.s.middleClickTapThreeFingers, symbol: "hand.tap")
                        tapChip(4, title: l10n.s.middleClickTapFourFingers, symbol: "hand.tap")
                    }
                    Text(l10n.s.middleClickTapCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if middleClick.systemDragGestureConflict {
                        Text(l10n.s.middleClickDragConflict)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, settingsRowTextInset)
                MouseExceptionsList(scope: .middleClick)
            }
        }
    }

    private func tapChip(_ fingers: Int, title: String, symbol: String) -> some View {
        let selected = middleClickTapFingers == fingers
        return Button {
            middleClickTapFingers = fingers
            MiddleClickService.shared.syncWithPreferences()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
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

    private func activeBadge(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(PanelMetricColor.green(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PanelMetricColor.green(for: colorScheme).opacity(0.12), in: Capsule())
    }

    // MARK: - State

    /// Only features that are on AND still available can ask for the
    /// permission note; a hub-disabled one no longer needs anything.
    private var accessibilityNoteVisible: Bool {
        let anyEngaged = scrollDirectionEnabled
            || (focusFollowsMouseEnabled && AppFeature.focusFollowsMouse.isAvailable)
            || (smoothScrollEnabled && AppFeature.smoothScroll.isAvailable)
            || (mouseNavigationEnabled && AppFeature.mouseNavigation.isAvailable)
            || ((mouseButtonShortcutsEnabled || spacesEnabled)
                && AppFeature.mouseButtonShortcuts.isAvailable)
            || (mouseClickDebounceEnabled && AppFeature.mouseClickDebounce.isAvailable)
            || (middleClickEnabled && AppFeature.middleClick.isAvailable)
        return anyEngaged && !permissions.accessibility
    }

    private var scrollInversionEnabled: Bool {
        AppFeature.scrollInverter.isAvailable && (invertVertical || invertHorizontal)
    }

    private var scrollDirectionEnabled: Bool {
        scrollInversionEnabled
            || (AppFeature.scrollHorizontal.isAvailable && horizontalScrollEnabled)
    }

    private var smoothScrollStepBinding: Binding<Double> {
        Binding(
            get: { Double(SmoothScrollSupport.sanitizedStep(smoothScrollStep)) },
            set: { smoothScrollStep = Int($0) }
        )
    }

    private var smoothScrollResponseBinding: Binding<Double> {
        Binding(
            get: { Double(SmoothScrollSupport.sanitizedResponse(smoothScrollResponse)) },
            set: { smoothScrollResponse = Int($0) }
        )
    }

    private var smoothScrollCoastBinding: Binding<Double> {
        Binding(
            get: { Double(SmoothScrollSupport.sanitizedCoast(smoothScrollCoast)) },
            set: { smoothScrollCoast = Int($0) }
        )
    }

    private var focusFollowsMouseDelayBinding: Binding<Double> {
        Binding(
            get: { Double(FocusFollowsMouseSupport.sanitizedDelay(focusFollowsMouseDelay)) },
            set: {
                focusFollowsMouseDelay = Int($0)
                FocusFollowsMouseService.shared.preferencesDidChange()
            }
        )
    }

    private var mouseClickDebounceWindowBinding: Binding<Int> {
        Binding(
            get: { Defaults.sanitizedMouseClickDebounceWindow(mouseClickDebounceWindow) },
            set: {
                mouseClickDebounceWindow = Defaults.sanitizedMouseClickDebounceWindow($0)
                MouseClickDebounceService.shared.syncWithPreferences()
            }
        )
    }
}
