// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import EventKit

private enum NotchSettingsTab: CaseIterable {
    case layout, content, activity, behavior
}

struct NotchSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var notch = NotchService.shared
    @AppStorage(DefaultsKey.notchGesturesEnabled) private var gesturesEnabled = true
    @AppStorage(DefaultsKey.notchKeyboardLight) private var keyboardLight = false
    @AppStorage(DefaultsKey.notchNotificationsEnabled) private var notificationsEnabled = false
    @AppStorage(DefaultsKey.notchDismissNativeNotifications) private var dismissNativeNotifications = false
    @AppStorage(DefaultsKey.notchTimerEnabled) private var timerEnabled = true
    @AppStorage(DefaultsKey.notchTimerSoundEnabled) private var timerSoundEnabled = true
    @AppStorage(DefaultsKey.notchCameraEnabled) private var cameraEnabled = false
    @AppStorage(DefaultsKey.notchAccessoriesEnabled) private var accessoriesEnabled = false
    @AppStorage(DefaultsKey.notchCalendarEnabled) private var calendarEnabled = true
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = false
    @AppStorage(DefaultsKey.notchLyricsOnline) private var lyricsOnline = false
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = false
    @AppStorage(DefaultsKey.notchLiveEqualizer) private var liveEqualizer = false
    @AppStorage(DefaultsKey.notchEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchDisplay) private var display = NotchDisplay.automatic.rawValue
    @AppStorage(DefaultsKey.notchOpenOnHover) private var hover = true
    @AppStorage(DefaultsKey.notchHideUntilHover) private var hideUntilHover = false
    @AppStorage(DefaultsKey.notchHoverDelay) private var hoverDelay = NotchSupport.defaultHoverDelay
    @AppStorage(DefaultsKey.notchReturnHome) private var returnHome = false
    @AppStorage(DefaultsKey.notchHomeModule) private var homeModule = NotchModule.controls.rawValue
    @AppStorage(DefaultsKey.notchHiddenModules) private var hidden = ""
    @AppStorage(DefaultsKey.notchModuleOrder) private var order = ""
    @AppStorage(DefaultsKey.notchVolume) private var volume = true
    @AppStorage(DefaultsKey.notchBrightness) private var brightness = true
    @AppStorage(DefaultsKey.notchBattery) private var battery = true
    @AppStorage(DefaultsKey.notchClipboard) private var clipboard = false
    @AppStorage(DefaultsKey.notchClipboardWindow) private var clipboardWindow = true
    @AppStorage(DefaultsKey.screenshotDefaultAction) private var captureAction = ""
    @AppStorage(DefaultsKey.notchCapture) private var capture = false
    @AppStorage(DefaultsKey.notchShowPlayingMusic) private var showPlayingMusic = true
    @AppStorage(DefaultsKey.notchIdleContent) private var idle = NotchIdleContent.music.rawValue
    @AppStorage(DefaultsKey.notchHiddenControls) private var hiddenControls = NotchControlItem.defaultHidden
    @AppStorage(DefaultsKey.notchControlOrder) private var controlOrder = ""
    @AppStorage(DefaultsKey.notchShowInCaptures) private var showInCaptures = true
    @AppStorage(DefaultsKey.notchSize) private var size = NotchSize.spacious.rawValue
    @AppStorage(DefaultsKey.notchCustomWidth) private var customWidth = NotchSize.defaultWidth
    @AppStorage(DefaultsKey.notchCustomHeight) private var customHeight = NotchSize.defaultHeight
    @AppStorage(DefaultsKey.notchHapticFeedback) private var hapticFeedback = true
    @AppStorage(DefaultsKey.notchShelf) private var shelfWindow = true
    @AppStorage(DefaultsKey.notchDragReveal) private var dragReveal = true
    @AppStorage(DefaultsKey.notchCaptureControls) private var captureControls = true
    @AppStorage(DefaultsKey.notchQuickPanel) private var quickPanel = true
    @AppStorage(DefaultsKey.notchAppPanel) private var appPanel = true
    @AppStorage(DefaultsKey.notchHoverExpands) private var hoverExpand = true
    @AppStorage(DefaultsKey.notchQuickAccessLayout) private var accessData = Data()
    @State private var tab = NotchSettingsTab.layout
    @State private var selectedModule = NotchModule.controls
    @State private var draggingModule: NotchModule?
    @State private var draggingControl: NotchControlItem?
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    private var configuration: [String] {
        [String(enabled), String(calendarEnabled), String(notificationsEnabled), String(dismissNativeNotifications), String(gesturesEnabled), String(lyricsEnabled), String(lyricsOnline), String(queueEnabled), String(liveEqualizer), String(showPlayingMusic), idle, hiddenControls, controlOrder, size,
         String(timerEnabled), String(timerSoundEnabled), String(cameraEnabled), String(accessoriesEnabled), String(customWidth), String(customHeight), String(hapticFeedback), String(shelfWindow), String(dragReveal), String(captureControls), String(quickPanel), String(appPanel), String(hoverExpand), String(hideUntilHover), display, String(hover), hidden, order, String(volume),
         String(brightness), String(keyboardLight), String(battery), String(clipboard), String(clipboardWindow), String(capture), captureAction, String(showInCaptures), String(returnHome), homeModule]
    }

    private var access: Binding<NotchQuickAccessConfiguration> {
        Binding(get: { NotchQuickAccessConfiguration.stored() }, set: { accessData = $0.encoded })
    }

    private var orderedModules: [NotchModule] {
        let stored = order.split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(text.title).font(.title2.bold())
                    Text(text.description).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle(text.enable, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                    .disabled(!AppFeature.notch.isAvailable).accessibilityLabel(text.enable)
            }
            if enabled, AppFeature.notch.isAvailable, !(hover && hideUntilHover), !notch.geometry.isNotched, !permissions.accessibility {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.menuBarAccessHint)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PermissionRow(kind: .accessibility)
                }
            }
            HStack {
                Picker(text.title, selection: $tab) {
                    Text(editor.layout).tag(NotchSettingsTab.layout)
                    Text(editor.content).tag(NotchSettingsTab.content)
                    Text(editor.activity).tag(NotchSettingsTab.activity)
                    Text(editor.behavior).tag(NotchSettingsTab.behavior)
                }.pickerStyle(.segmented).labelsHidden()
                Button { NotchService.shared.open() } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.bordered).disabled(!enabled).help(text.open).accessibilityLabel(text.open)
            }
            ScrollView {
                Group {
                    switch tab {
                    case .layout: layoutPage
                    case .content: contentPage
                    case .activity: activityPage
                    case .behavior: behaviorPage
                    }
                }.padding(.bottom, 22)
            }.id(tab)
        }
        .padding(.horizontal, 22).padding(.top, 22)
        .onChange(of: configuration) { _, _ in sync() }
        .onChange(of: accessData) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: tab) { _, _ in draggingModule = nil; draggingControl = nil }
    }

    private func sync() {
        NotchService.shared.syncWithPreferences()
        if !NotchLyricsSupport.isEnabled() { NotchLyricsService.shared.stop() }
        NotchMusicService.shared.syncQueuePreference()
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private var layoutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            NotchLayoutEditor(configuration: access, size: $size, width: $customWidth, height: $customHeight) {
                selectedModule = .controls; tab = .content
            }
            section(text.size) {
                HStack(spacing: 10) {
                    choice(text.compact, symbol: "rectangle.compress.vertical", selected: size == NotchSize.compact.rawValue) { size = NotchSize.compact.rawValue }
                    choice(text.spacious, symbol: "rectangle.expand.vertical", selected: size == NotchSize.spacious.rawValue) { size = NotchSize.spacious.rawValue }
                    choice(text.custom, symbol: "arrow.up.left.and.arrow.down.right", selected: size == NotchSize.custom.rawValue) { size = NotchSize.custom.rawValue }
                }
                if size == NotchSize.custom.rawValue {
                    dimensionSlider(text.width, value: $customWidth, range: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
                    dimensionSlider(text.maximumHeight, value: $customHeight, range: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
                    Text(text.sizeHint).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var contentPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editor.reorderHint).font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                ForEach(orderedModules) { module in
                    PanelReorderableItem(item: module,
                        order: Binding(get: { orderedModules }, set: { order = $0.map(\.rawValue).joined(separator: ",") }),
                        dragging: $draggingModule) {
                        NotchEditorItem(symbol: module.symbol, title: module.title(l10n.language), included: moduleBinding(module),
                                        selected: selectedModule == module, available: module.isAvailable()) { selectedModule = module }
                    }
                }
            }
            section(selectedModule.title(l10n.language)) {
                if selectedModule.isAvailable() { moduleOptions }
                else { Text(text.disabled).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var moduleOptions: some View {
        switch selectedModule {
        case .controls:
            HStack(spacing: 10) {
                ForEach([NotchControlItem.music, .volume, .brightness]) { item in
                    toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable())
                }
            }
            Text(text.controlShortcuts).font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                ForEach(orderedShortcuts) { item in
                    PanelReorderableItem(item: item,
                        order: Binding(get: { orderedShortcuts }, set: { controlOrder = $0.map(\.rawValue).joined(separator: ",") }),
                        dragging: $draggingControl) {
                        toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable())
                    }
                }
            }
        case .music:
            Toggle(text.playingMusic, isOn: $showPlayingMusic)
            let music = FeatureStrings.notchMusicExtras(l10n.language)
            Toggle(music.enableLyrics, isOn: $lyricsEnabled).disabled(!AppFeature.notchLyrics.isAvailable)
            if lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                Toggle(music.online, isOn: $lyricsOnline)
                Text(music.onlineHint).font(.caption).foregroundStyle(.secondary)
            }
            Toggle(music.enableQueue, isOn: $queueEnabled).disabled(!AppFeature.notchQueue.isAvailable)
            Text(music.queueDescription).font(.caption).foregroundStyle(.secondary)
            Toggle(music.liveEqualizer, isOn: $liveEqualizer)
                .disabled(!NotchAudioLevelSupport.isSupported || !AppFeature.notchLiveEqualizer.isAvailable)
            Text(NotchAudioLevelSupport.isSupported ? music.liveEqualizerHint : music.liveEqualizerUnavailable)
                .font(.caption).foregroundStyle(.secondary)
        case .notifications:
            let notifications = FeatureStrings.notchNotifications(l10n.language)
            Toggle(notifications.dismissSystemBanner, isOn: $dismissNativeNotifications)
            Text(notifications.dismissSystemBannerHint).font(.caption).foregroundStyle(.secondary)
            if notificationsEnabled, !permissions.accessibility { PermissionRow(kind: .accessibility) }
        case .downloads:
            NotchDownloadsSettingsControls()
        case .calendar:
            let calendar = FeatureStrings.notchCalendar(l10n.language)
            Text(calendar.permission).font(.callout).foregroundStyle(.secondary)
            if permissions.calendarAccess == .fullAccess {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(calendar.allow, action: permissions.requestCalendar).disabled(permissions.requestingCalendar)
                Button(calendar.settings, action: permissions.openCalendarSettings)
            }
        case .timer:
            Toggle(FeatureStrings.notchActivities(l10n.language).soundEnabled, isOn: $timerSoundEnabled)
                .disabled(!AppFeature.notchTimer.isAvailable)
        case .camera:
            Text(FeatureStrings.notchActivities(l10n.language).cameraHint).font(.callout).foregroundStyle(.secondary)
            if permissions.camera == .granted {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(l10n.s.permissionRequest, action: permissions.requestCamera)
                Button(l10n.s.permissionOpenSettings, action: permissions.openCameraSettings)
            }
        case .files:
            destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
            if shelfWindow { Toggle(text.dragReveal, isOn: $dragReveal) }
            if AppFeature.mediaTools.isAvailable {
                Text(FeatureStrings.notchFiles(l10n.language).optimizeDropHint)
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .clipboard:
            destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
            Toggle(text.clipboardActivity, isOn: $clipboard)
            Text(text.privacy).font(.caption).foregroundStyle(.secondary)
        case .captures:
            Toggle(text.captureActivity, isOn: $capture).disabled(!AppFeature.screenshot.isAvailable)
            if capture {
                ScreenshotDefaultActionPicker(strings: FeatureStrings.screenshot(l10n.language), selection: $captureAction)
            }
        default:
            Text(editor.reorderHint).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            section(editor.resting) {
                HStack(spacing: 10) {
                    idleChoice(.none, title: text.idleNone, symbol: "minus")
                    idleChoice(.battery, title: text.battery, symbol: "battery.75percent")
                    idleChoice(.music, title: text.music, symbol: "music.note")
                }
            }
            section(editor.feedback) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    toggleCard(text.volume, symbol: "speaker.wave.2", value: $volume, available: AppFeature.mixer.isAvailable)
                    toggleCard(text.brightness, symbol: "sun.max", value: $brightness, available: AppFeature.brightness.isAvailable)
                    toggleCard(FeatureStrings.brightness(l10n.language).keyboardLight, symbol: "light.max", value: $keyboardLight,
                              available: AppFeature.brightness.isAvailable && BrightnessService.keyboardLightIsSupported)
                    toggleCard(text.battery, symbol: "battery.75percent", value: $battery, available: AppFeature.monitorPower.isAvailable)
                    toggleCard(FeatureStrings.notchActivities(l10n.language).accessories, symbol: "headphones", value: $accessoriesEnabled,
                              available: AppFeature.notchAccessories.isAvailable && AppFeature.monitorPower.isAvailable)
                    toggleCard(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboard, available: AppFeature.clipboardHistory.isAvailable)
                    toggleCard(text.captures, symbol: "camera.viewfinder", value: $capture, available: AppFeature.screenshot.isAvailable)
                }
                if accessoriesEnabled { Text(FeatureStrings.notchActivities(l10n.language).accessoryDescription).font(.caption).foregroundStyle(.secondary) }
                if enabled, (volume || brightness || keyboardLight), !permissions.accessibility { PermissionRow(kind: .accessibility) }
            }
        }
    }

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            section(editor.opening) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    choice(editor.clickOpen, symbol: "cursorarrow", selected: !hover) { hideUntilHover = false; hover = false }
                    choice(editor.hoverPreview, symbol: "rectangle.topthird.inset.filled", selected: hover && !hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = false }
                    choice(editor.hoverExpand, symbol: "arrow.up.left.and.arrow.down.right", selected: hover && hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = true }
                    choice(editor.hiddenUntilHover, symbol: "eye.slash", selected: hover && hideUntilHover) { hover = true; hoverExpand = true; hideUntilHover = true }
                }
                if hover { hoverDelayControl }
                Toggle(FeatureStrings.notchGestures(l10n.language).title, isOn: $gesturesEnabled).disabled(!AppFeature.notchGestures.isAvailable)
                if gesturesEnabled { Text(FeatureStrings.notchGestures(l10n.language).hint).font(.caption).foregroundStyle(.secondary) }
                Toggle(text.hapticFeedback, isOn: $hapticFeedback)
                Picker(editor.reopening, selection: Binding(get: {
                    returnHome ? (NotchModule(rawValue: homeModule) ?? .controls).rawValue : ""
                }, set: { value in
                    returnHome = !value.isEmpty
                    if returnHome { homeModule = value }
                })) {
                    Text(editor.lastPage).tag("")
                    ForEach(NotchSupport.modules()) { module in
                        Text(module.title(l10n.language)).tag(module.rawValue)
                    }
                    if let saved = NotchModule(rawValue: homeModule), !NotchSupport.modules().contains(saved) {
                        Text(saved.title(l10n.language)).tag(homeModule).disabled(true)
                    }
                }
            }
            section(text.display) {
                HStack(spacing: 8) {
                    choice(text.automatic, symbol: "display.2", selected: display == NotchDisplay.automatic.rawValue) { display = NotchDisplay.automatic.rawValue }
                    choice(text.builtIn, symbol: "laptopcomputer", selected: display == NotchDisplay.builtIn.rawValue) { display = NotchDisplay.builtIn.rawValue }
                    choice(text.mainDisplay, symbol: "display", selected: display == NotchDisplay.main.rawValue) { display = NotchDisplay.main.rawValue }
                }
            }
            section(editor.destinations) {
                destination(text.panel, symbol: "rectangle.topthird.inset.filled", value: $appPanel)
                destination(text.tools, symbol: "square.grid.2x2", value: $quickPanel, available: AppFeature.quickLauncher.isAvailable)
                destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
                destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
                destination(text.captures, symbol: "camera.viewfinder", value: $captureControls)
            }
            section(editor.privacy) {
                Toggle(text.showInCaptures, isOn: $showInCaptures)
            }
        }
    }

    private var hoverDelayControl: some View {
        let value = Binding(get: { NotchSupport.sanitizedHoverDelay(hoverDelay) },
                            set: { hoverDelay = NotchSupport.sanitizedHoverDelay($0) })
        let formatted = String(format: editor.activationTimeFormat, locale: Locale(identifier: l10n.language.rawValue), value.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(editor.activationTime)
                Spacer()
                Text(formatted).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: NotchSupport.hoverDelayRange, step: 0.05) {
                Text(editor.activationTime)
            }.labelsHidden().accessibilityValue(formatted)
            Text(editor.activationTimeHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.headline)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private func choice(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 68).padding(8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleCard(_ title: String, symbol: String, value: Binding<Bool>, available: Bool) -> some View {
        NotchEditorItem(symbol: symbol, title: title, included: value, available: available) { value.wrappedValue.toggle() }
            .disabled(!available)
    }

    private func idleChoice(_ item: NotchIdleContent, title: String, symbol: String) -> some View {
        Button { idle = item.rawValue } label: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    if item != .none {
                        Image(systemName: symbol).font(.system(size: 11))
                        RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 20, height: 12)
                        if item == .battery { Text("76%").font(.system(size: 9, weight: .medium)) }
                        else { Image(systemName: item == .music ? "waveform" : "minus").font(.system(size: 9)) }
                    } else { Color.clear.frame(width: 50, height: 12) }
                }.foregroundStyle(.white).padding(10).background(.black, in: Capsule())
                Text(title).font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                .background((NotchIdleContent(rawValue: idle) ?? .none) == item ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits((NotchIdleContent(rawValue: idle) ?? .none) == item ? .isSelected : [])
    }

    private func destination(_ title: String, symbol: String, value: Binding<Bool>, available: Bool = true) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.callout).lineLimit(2)
            Spacer(minLength: 10)
            Picker(title, selection: value) {
                Text(text.title).tag(true)
                Text(editor.separate).tag(false)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 238)
        }.disabled(!available)
    }

    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, fallback: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: fallback) },
                              set: { value.wrappedValue = NotchSize.clamped($0, to: range, fallback: fallback) })
        return HStack {
            Slider(value: bounded, in: range, step: 10) { Text(title) }
            Text(Int(bounded.wrappedValue), format: .number)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }
    private var orderedShortcuts: [NotchControlItem] {
        let stored = controlOrder.split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            $0 != .volume && $0 != .brightness && $0 != .music && seen.insert($0).inserted
        }
    }

    private func controlBinding(_ item: NotchControlItem) -> Binding<Bool> {
        Binding {
            !hiddenControls.split(separator: ",").contains(Substring(item.rawValue))
        } set: { shown in
            var values = Set(hiddenControls.split(separator: ",").map(String.init))
            if shown { values.remove(item.rawValue) } else { values.insert(item.rawValue) }
            hiddenControls = values.sorted().joined(separator: ",")
        }
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        Binding {
            (module != .timer || timerEnabled) && (module != .camera || cameraEnabled)
                && (module != .calendar || calendarEnabled) && (module != .notifications || notificationsEnabled)
                && !hidden.split(separator: ",").contains(Substring(module.rawValue))
        } set: { shown in
            if module == .timer { timerEnabled = shown }
            if module == .camera { cameraEnabled = shown }
            if module == .calendar { calendarEnabled = shown }
            if module == .notifications { notificationsEnabled = shown }
            var values = Set(hidden.split(separator: ",").map(String.init))
            if shown { values.remove(module.rawValue) } else { values.insert(module.rawValue) }
            hidden = values.sorted().joined(separator: ",")
        }
    }

}

extension NotchControlItem: PanelOrderItem {}
