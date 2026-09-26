// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// How a level control draws: a full card with its device menu, one slim row
/// inside a shared card, or the inline strip under the player.
enum NotchLevelStyle {
    case card, row, inline
}

struct NotchControlsView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false

    var body: some View {
        let items = NotchSupport.controls()
        let levels = items.filter { $0 == .volume || $0 == .brightness }
        let shortcuts = items.filter { $0 != .volume && $0 != .brightness && $0 != .music }
        let layout = NotchLayout.controls(hasCards: items.contains(.music) || !levels.isEmpty,
                                          shortcutCount: shortcuts.count, width: size.width, height: size.height)
        if items.isEmpty {
            NotchEmptyView(symbol: "slider.horizontal.3", message: FeatureStrings.notch(l10n.language).empty)
        } else {
            VStack(spacing: NotchLayout.rowSpacing) {
                if layout.cardRow > 0 {
                    cards(levels: levels, music: items.contains(.music), height: layout.cardRow)
                }
                if layout.shortcutRows > 0 {
                    NotchRail(items: shortcuts, rows: layout.shortcutRows, itemWidth: NotchLayout.shortcutWidth,
                              width: size.width, spacing: NotchLayout.shortcutSpacing, rowSpacing: NotchLayout.shortcutSpacing) { item in
                        shortcut(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Playback shares the row with the levels: two of them fold into one
    /// slim card beside it, a single one keeps its full card.
    @ViewBuilder private func cards(levels: [NotchControlItem], music: Bool, height: CGFloat) -> some View {
        let musicWidth = NotchLayout.musicCardMinimumWidth(height: height)
        let required = music ? musicWidth + (levels.isEmpty ? 0 : 160 + NotchLayout.rowSpacing) : 0
        if required > size.width {
            ScrollView(.horizontal) {
                cardRow(levels: levels, music: music, height: height).frame(width: required)
            }
            .scrollIndicators(.never)
            .frame(height: height)
        } else {
            cardRow(levels: levels, music: music, height: height)
        }
    }

    private func cardRow(levels: [NotchControlItem], music: Bool, height: CGFloat) -> some View {
        HStack(spacing: NotchLayout.rowSpacing) {
            if music {
                NotchMusicControlsView(notch: service, height: height)
                if levels.count > 1 {
                    VStack(spacing: 6) {
                        ForEach(levels) { level($0, style: .row, showsDevice: false) }
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 160, height: height)
                    .modifier(NotchControlSurface(cornerRadius: 18))
                } else if let single = levels.first {
                    level(single, style: .card, showsDevice: height >= 88).frame(width: 160, height: height)
                }
            } else {
                ForEach(levels) { item in
                    level(item, style: .card, showsDevice: height >= 88).frame(maxWidth: .infinity).frame(height: height)
                }
            }
        }
        .frame(height: height)
    }

    @ViewBuilder private func level(_ item: NotchControlItem, style: NotchLevelStyle, showsDevice: Bool) -> some View {
        if item == .volume {
            NotchAudioControls(notch: service, style: style, showsDevice: showsDevice)
        } else if brightnessEnabled {
            NotchBrightnessControls(style: style, showsDevice: showsDevice)
        } else {
            brightnessSetup(style)
        }
    }

    private func brightnessSetup(_ style: NotchLevelStyle) -> some View {
        let settings = Button(l10n.s.menuSettings) {
            service.perform {
                SettingsRouter.shared.request(AppFeature.brightness.settingsDestination)
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            }
        }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
        return Group {
            if style == .row {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill").font(.system(size: 12, weight: .medium)).frame(width: 18)
                    Text(FeatureStrings.notch(l10n.language).brightness).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    settings
                }
                .frame(height: 28)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label(FeatureStrings.notch(l10n.language).brightness, systemImage: "sun.max.fill")
                        .font(.system(size: 12, weight: .semibold))
                    settings
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .modifier(NotchControlSurface(cornerRadius: 18))
            }
        }
    }

    @ViewBuilder private func shortcut(_ item: NotchControlItem) -> some View {
        switch item {
        case .keepAwake: NotchAwakeButton(notch: service)
        case .microphone: NotchMicButton()
        case .screenshot:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n)) {
                service.perform { ScreenshotService.shared.capture() }
            }
        case .recording: NotchRecorderButton(service: service)
        case .speedTest:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n)) { service.showMetric(.network) }
        case .panel:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n)) { service.openAppPanel() }
        case .mixer:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n)) { service.select(.mixer) }
        case .commandBar:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n)) { service.perform { CommandBarService.shared.show() } }
        case .scratchpad:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n), action: service.openScratchpad)
        case .timer, .calendar:
            NotchActionTile(symbol: item.symbol, title: item.title(l10n)) {
                service.select(item == .timer ? .timer : .calendar)
            }
        case .volume, .brightness, .music: EmptyView()
        }
    }
}

extension NotchControlItem {
    func title(_ l10n: L10n) -> String {
        switch self {
        case .volume: return FeatureStrings.notch(l10n.language).volume
        case .brightness: return FeatureStrings.notch(l10n.language).brightness
        case .keepAwake: return l10n.s.keepAwakeTitle
        case .microphone: return l10n.s.micMuteName
        case .screenshot: return FeatureStrings.recentCaptures(l10n.language).screenshot
        case .recording: return FeatureStrings.recorder(l10n.language).pageTitle
        case .speedTest: return l10n.s.speedTestRun
        case .panel: return FeatureStrings.notch(l10n.language).panel
        case .mixer: return l10n.s.mixerSection
        case .commandBar: return FeatureStrings.commandBar(l10n.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(l10n.language).pageTitle
        case .music: return NotchModule.music.title(l10n.language)
        case .timer: return NotchModule.timer.title(l10n.language)
        case .calendar: return NotchModule.calendar.title(l10n.language)
        }
    }
}

struct NotchAudioControls: View {
    @ObservedObject var notch: NotchService = .shared
    var style: NotchLevelStyle = .card
    var showsDevice = true
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var level: Double? { mixer.systemOutputVolume.map { mixer.systemOutputMuted == true ? 0 : $0 } }
    private var deviceName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name ?? l10n.s.mixerSystemOutputTitle
    }

    var body: some View {
        switch style {
        case .inline:
            HStack(spacing: 10) {
                mute
                slider
                inlineOutputMenu
            }
            .frame(height: NotchLayout.musicControlsRowHeight)
            .help(mixer.outputSwitchError ?? deviceName)
        case .row:
            HStack(spacing: 8) {
                mute
                slider
                readoutMenu
            }
            .frame(height: 28)
            .help(mixer.outputSwitchError ?? deviceName)
        case .card:
            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    mute
                    if showsDevice {
                        Text(FeatureStrings.notch(l10n.language).volume).lineLimit(1)
                        Spacer(minLength: 0)
                        percent
                    } else {
                        Spacer(minLength: 0)
                        readoutMenu
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                slider
                if showsDevice {
                    Group {
                        if let error = mixer.outputSwitchError {
                            Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1).help(error)
                        } else {
                            NotchDeviceMenu(title: l10n.s.mixerSystemOutputTitle, current: deviceName,
                                            width: 154, lines: 1, alignment: .leading, items: outputItems)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            // A short card folds its padding so the readout row, the slider and
            // their gap fit NotchLayout.minimumCardHeight without spilling past the surface.
            .padding(.vertical, showsDevice ? 10 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(NotchControlSurface(cornerRadius: 18))
        }
    }

    @ViewBuilder private var percent: some View {
        if let level {
            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: level)
        }
    }

    /// The level this control sets is already on screen, so the open
    /// header keeps its title instead of repeating it.
    private func adjustOutput(volume: Double? = nil, muted: Bool? = nil) {
        notch.noteOwnVolumeAdjustment()
        mixer.requestOutputAdjustment(volume: volume, muted: muted)
    }

    private var mute: some View {
        Button {
            if let muted = mixer.systemOutputMuted { adjustOutput(muted: !muted) }
        } label: {
            Image(systemName: mixer.systemOutputMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mixer.systemOutputMuted == true ? Color.red : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: mixer.systemOutputMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 6))
        .disabled(mixer.systemOutputMuted == nil)
        .accessibilityLabel(mixer.systemOutputMuted == true ? l10n.s.actionUnmute : l10n.s.actionMute)
    }

    @ViewBuilder private var slider: some View {
        if let level {
            NotchLevelSlider(value: Binding(get: { level }, set: { adjustOutput(volume: $0) }),
                             label: FeatureStrings.notch(l10n.language).volume)
                .frame(height: style == .card ? 28 : 24)
        } else {
            Text(l10n.s.mixerOutputUnavailable).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: style == .card ? 28 : 24, alignment: .leading)
        }
    }

    private var outputItems: [NotchMenuItem] {
        var items = mixer.outputDevices.filter(\.canBeDefaultOutput).map { device in
            NotchMenuItem(title: device.name, checked: device.uid == mixer.currentOutputDeviceUID) {
                _ = mixer.setUniversalOutputDeviceUID(device.uid)
            }
        }
        if notch.modules.contains(.mixer) {
            items.append(.separator)
            items.append(NotchMenuItem(title: l10n.s.mixerSection, symbol: NotchModule.mixer.symbol) { notch.select(.mixer) })
        }
        return items
    }

    private var readoutMenu: some View {
        NotchLevelReadoutMenu(title: l10n.s.mixerSystemOutputTitle, items: outputItems) { percent }
            .help(deviceName)
            .accessibilityValue(deviceName)
    }

    /// Under the player the readout is the slider itself; a glyph opens the chooser.
    private var inlineOutputMenu: some View {
        NotchMenuButton(title: l10n.s.mixerSystemOutputTitle, items: outputItems) {
            HStack(spacing: 5) {
                Image(systemName: "airplay.audio").font(.system(size: 14))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help(deviceName)
        .accessibilityValue(deviceName)
    }
}

/// Where a row or a short card folds its chooser into the readout: the whole
/// percent at the width of "100%" with the menu's chevron beside it. Volume
/// and brightness end on this same column, so their sliders line up.
private struct NotchLevelReadoutMenu<Readout: View>: View {
    let title: String
    let items: [NotchMenuItem]
    @ViewBuilder let readout: () -> Readout

    var body: some View {
        NotchMenuButton(title: title, items: items) {
            HStack(spacing: 5) {
                readout().frame(width: 36, alignment: .trailing)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct NotchBrightnessControls: View {
    var style: NotchLevelStyle = .card
    var showsDevice = true
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: CGDirectDisplayID?
    private var displays: [BrightnessDisplay] { service.displays.filter { $0.isActive && $0.method != nil } }
    private var display: BrightnessDisplay? {
        displays.first(where: { $0.id == selectedID }) ?? displays.first(where: \.isBuiltIn) ?? displays.first
    }

    var body: some View {
        Group {
            if style == .row {
                HStack(spacing: 8) {
                    glyph
                    slider
                    readoutMenu
                }
                .frame(height: 28)
                .help(display?.name ?? FeatureStrings.brightness(l10n.language).noDisplays)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        glyph
                        if showsDevice {
                            Text(FeatureStrings.notch(l10n.language).brightness).lineLimit(1)
                            Spacer(minLength: 0)
                            percent
                        } else {
                            Spacer(minLength: 0)
                            readoutMenu
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    slider
                    if showsDevice, let display {
                        NotchDeviceMenu(title: FeatureStrings.notch(l10n.language).brightness, current: display.name,
                                        width: 154, lines: 1, alignment: .leading, items: displayItems(current: display))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                // Folds like the audio card above, for the same minimum card height.
                .padding(.vertical, showsDevice ? 10 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(NotchControlSurface(cornerRadius: 18))
            }
        }
        .onAppear { service.refresh() }
    }

    /// Volume leads with its mute button; the sun keeps that button's width
    /// so both sliders start on the same line.
    private var glyph: some View {
        Image(systemName: "sun.max.fill").font(.system(size: 12, weight: .medium)).frame(width: 18)
    }

    private func displayItems(current: BrightnessDisplay) -> [NotchMenuItem] {
        displays.map { item in
            NotchMenuItem(title: item.name, checked: item.id == current.id) { selectedID = item.id }
        }
    }

    @ViewBuilder private var readoutMenu: some View {
        if let display {
            NotchLevelReadoutMenu(title: FeatureStrings.notch(l10n.language).brightness,
                                  items: displayItems(current: display)) { percent }
                .help(display.name)
                .accessibilityValue(display.name)
        }
    }

    @ViewBuilder private var percent: some View {
        if let display {
            Text("\(BrightnessSupport.wholePercent(display.brightness))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: display.brightness)
        }
    }

    @ViewBuilder private var slider: some View {
        if let display {
            NotchLevelSlider(value: Binding(get: { display.brightness }, set: {
                service.setBrightness($0, for: display.id, showOSD: true)
            }), label: FeatureStrings.notch(l10n.language).brightness)
                .frame(height: style == .card ? 28 : 24)
        } else {
            Text(FeatureStrings.brightness(l10n.language).noDisplays)
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: style == .card ? 28 : 24, alignment: .leading)
        }
    }
}

/// How an active tile reads. Recording and a muted microphone are states the
/// person has to notice, so they carry their own colour instead of the neutral
/// selection fill.
enum NotchTileAccent {
    case selection, alert, awake

    var fill: Color {
        switch self {
        case .selection: return .white
        case .alert: return .red
        case .awake: return .yellow
        }
    }

    var glyph: Color {
        switch self {
        case .selection, .awake: return .black
        case .alert: return .white
        }
    }
}

/// A glyph in its own circle over a two-line label, the shape every shortcut
/// rail in the island shares.
struct NotchActionTile: View {
    let symbol: String
    let title: String
    var active = false
    var accent: NotchTileAccent = .selection
    var longPressAction: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let longPressAction {
                Button(action: action) { tile }
                    .buttonStyle(NotchLongPressButtonStyle(cornerRadius: 14, longPress: longPressAction))
            } else {
                Button(action: action) { tile }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 14))
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(title)
    }

    private var tile: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? accent.glyph : .white.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .background(active ? accent.fill : Color.white.opacity(0.075), in: Circle())
                .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: symbol)
            Text(title).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(height: 28, alignment: .top)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: NotchLayout.shortcutHeight)
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: active)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct NotchLongPressButtonStyle: PrimitiveButtonStyle {
    var cornerRadius: CGFloat = 14
    let longPress: () -> Void
    @State private var hovered = false
    @State private var pressed = false
    @State private var pressStart: Date?
    @State private var cancelled = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let threshold: TimeInterval = 0.4

    func makeBody(configuration: Configuration) -> some View {
        let active = enabled && hovered
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(active ? 0.09 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (pressed ? 0.8 : 1) : 0.4)
            .scaleEffect(reduceMotion ? 1 : pressed ? 0.965 : (active ? 1.022 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: pressed)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75), value: hovered)
            .onHover { hovered = $0 }
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                let inside = CGRect(origin: .zero, size: geo.size)
                                    .contains(value.location)
                                if !inside {
                                    pressed = false
                                    cancelled = true
                                    return
                                }
                                if cancelled { return }
                                if pressStart == nil { pressStart = Date() }
                                pressed = true
                            }
                            .onEnded { _ in
                                pressed = false
                                guard !cancelled else {
                                    cancelled = false
                                    pressStart = nil
                                    return
                                }
                                let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                                pressStart = nil
                                cancelled = false
                                if held >= threshold { longPress() } else { configuration.trigger() }
                            })
                }
            }
    }
}

private struct NotchAwakeButton: View {
    let notch: NotchService
    @ObservedObject private var service = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                        title: l10n.s.keepAwakeTitle, active: service.isActive,
                        accent: .awake,
                        longPressAction: notch.showKeepAwakeDetail,
                        action: service.toggle)
            .accessibilityAction(named: l10n.s.keepAwakeOptions, notch.showKeepAwakeDetail)
    }
}

struct NotchKeepAwakeView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.keepAwakeAllowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.vorssaint.rawValue
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @State private var untilTime = Date()
    @State private var useEndTime = false
    @State private var showingIconPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pickerTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .trailing),
                                                removal: .move(edge: .trailing)).combined(with: .opacity)
    }

    private var controlsTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .leading),
                                                removal: .move(edge: .leading)).combined(with: .opacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingIconPicker {
                iconPickerPage.transition(pickerTransition)
            } else {
                controlsPage.transition(controlsTransition)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showingIconPicker)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .modifier(NotchControlSurface(cornerRadius: 18))
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            untilTime = Date().addingTimeInterval(3600)
        }
        .onChange(of: awake.isActive) { service.refreshPresentation() }
        .onChange(of: awake.endDate != nil) { service.refreshPresentation() }
        .onChange(of: showingIconPicker) { service.keepAwakeIconPickerVisible = showingIconPicker; service.refreshPresentation() }
        .onDisappear { service.keepKeepAwakeInteractionOpen(false); service.keepAwakeIconPickerVisible = false }
    }

    @ViewBuilder
    private var controlsPage: some View {
        HStack(spacing: 10) {
            Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(awake.isActive ? .yellow : .white.opacity(0.85))
            statusLine
            Spacer(minLength: 8)
            Toggle("", isOn: activeBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(.yellow)
                .accessibilityLabel(l10n.s.keepAwakeTitle)
        }
        if awake.isActive {
            if awake.endDate != nil {
                HStack(spacing: 8) {
                    extendChip(15)
                    extendChip(30)
                    extendChip(60)
                    Spacer(minLength: 0)
                }
            }
        } else {
            Picker(l10n.s.durationLabel, selection: $useEndTime) {
                Text(l10n.s.durationLabel).tag(false)
                Text(l10n.s.keepAwakeUntilLabel).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if useEndTime {
                KeepAwakeEndTimePicker(selection: $untilTime,
                                      onPopoverChange: { service.keepKeepAwakeInteractionOpen($0) })
            } else {
                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DurationPicker(selection: $defaultDuration)
                    Spacer(minLength: 0)
                }
            }
            chip(l10n.s.keepAwakeUntilStart, action: startSession)
                .frame(maxWidth: .infinity)
        }
        Divider().overlay(.white.opacity(0.1))
        optionToggle(icon: "macbook", title: l10n.s.clamshellTitle,
                     caption: clamshellCaption, isOn: $awake.clamshellPreferred,
                     disabled: awake.clamshellSetupInProgress,
                     captionIsError: awake.clamshellSetupFailed)
        optionToggle(icon: "display", title: displaySleepStrings.allowDisplaySleep,
                     isOn: $allowDisplaySleep)
        Divider().overlay(.white.opacity(0.1))
        Button { showingIconPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(l10n.s.keepAwakeActiveIconLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconPickerPage: some View {
        Button { showingIconPicker = false } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(l10n.s.keepAwakeTitle)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon,
                            tintValue: $keepAwakeIconTint,
                            compact: true)
    }

    private var displaySleepStrings: KeepAwakeDisplaySleepStrings {
        FeatureStrings.keepAwakeDisplaySleep(l10n.language)
    }

    private var clamshellCaption: String {
        if awake.clamshellSetupInProgress { return l10n.s.configuring }
        if awake.clamshellSetupFailed { return l10n.s.sudoersFailed }
        if awake.clamshellActive { return l10n.s.clamshellOnCaption }
        if awake.clamshellPreferred { return l10n.s.clamshellNeedsSession }
        return awake.passwordlessClamshell ? l10n.s.clamshellReady : l10n.s.clamshellNeedsPassword
    }

    private func optionToggle(icon: String, title: String, caption: String? = nil,
                              isOn: Binding<Bool>, disabled: Bool = false,
                              captionIsError: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                if let caption {
                    Text(caption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(captionIsError ? Color.red : .secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(disabled)
        }
    }

    private var statusLine: some View {
        Group {
            if awake.isActive {
                if awake.sessionTrigger == .automation {
                    Text(FeatureStrings.keepAwakeAutomation(l10n.language)
                        .activeStatus(for: awake.activeAutomationConditions))
                } else if let end = awake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(l10n.s.keepAwakeEndsIn) \(KeepAwakeCard.remainingText(until: end))")
                            .monospacedDigit()
                    }
                } else {
                    Text(l10n.s.keepAwakeUntilDisabled)
                }
            } else {
                Text(l10n.s.keepAwakeNormalRules)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var activeBinding: Binding<Bool> {
        Binding(get: { awake.isActive },
                set: { on in
                    if on {
                        startSession()
                    } else if awake.isActive {
                        awake.toggle()
                    }
                })
    }

    private func startSession() {
        if useEndTime {
            awake.activate(until: KeepAwakeAutomationSupport.resolvedUntilDate(picked: untilTime, now: Date()))
        } else {
            awake.activate(minutes: defaultDuration)
        }
    }

    private func extendChip(_ minutes: Int) -> some View {
        chip("+\(minutes) min") { awake.extend(minutes: minutes) }
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .foregroundStyle(.yellow)
                .background(.yellow.opacity(0.18), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 13))
        .accessibilityLabel(label)
    }
}

private struct NotchMicButton: View {
    @ObservedObject private var service = MicMuteService.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: service.isMuted ? "mic.slash.fill" : "mic.fill",
                        title: service.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                        active: service.isMuted, accent: .alert, action: service.toggle)
    }
}

private struct NotchRecorderButton: View {
    let service: NotchService
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                        title: FeatureStrings.recorder(l10n.language).pageTitle,
                        active: recorder.isRecording, accent: .alert) {
            service.perform { recorder.toggle() }
        }
    }
}
