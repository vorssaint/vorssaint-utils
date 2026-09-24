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
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(DefaultsKey.notchGesturesEnabled) private var gesturesEnabled = true
    @AppStorage(DefaultsKey.notchKeyboardLight) private var keyboardLight = false
    @AppStorage(DefaultsKey.notchNotificationsEnabled) private var notificationsEnabled = false
    @AppStorage(DefaultsKey.notchDismissNativeNotifications) private var dismissNativeNotifications = false
    @AppStorage(DefaultsKey.notchTimerEnabled) private var timerEnabled = true
    @AppStorage(DefaultsKey.notchTimerSoundEnabled) private var timerSoundEnabled = true
    @AppStorage(DefaultsKey.notchCameraEnabled) private var cameraEnabled = false
    @AppStorage(DefaultsKey.notchAccessoriesEnabled) private var accessoriesEnabled = false
    @AppStorage(DefaultsKey.notchCalendarEnabled) private var calendarEnabled = true
    @AppStorage(DefaultsKey.notchCalendarCountdown) private var calendarCountdown = false
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var agentsEnabled = false
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = false
    @AppStorage(DefaultsKey.notchLyricsOnline) private var lyricsOnline = false
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = false
    @AppStorage(DefaultsKey.notchLiveEqualizer) private var liveEqualizer = false
    @AppStorage(DefaultsKey.notchEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchDisplay) private var display = NotchDisplay.automatic.rawValue
    @AppStorage(DefaultsKey.notchOpenOnHover) private var hover = true
    @AppStorage(DefaultsKey.notchHideInFullscreen) private var hideInFullscreen = false
    @AppStorage(DefaultsKey.notchHideUntilHover) private var hideUntilHover = false
    @AppStorage(DefaultsKey.notchCoversMenus) private var coversMenus = true
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
    @AppStorage(DefaultsKey.notchHidesMenuBarIcon) private var hidesMenuBarIcon = false
    @AppStorage(DefaultsKey.notchScratchpad) private var scratchpad = true
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessControlEnabled = false
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var clipboardHistoryEnabled = false
    @AppStorage(DefaultsKey.notchHoverExpands) private var hoverExpand = true
    @AppStorage(DefaultsKey.notchQuickAccessLayout) private var accessData = Data()
    @State private var tab = NotchSettingsTab.layout
    @State private var selectedModule = NotchModule.controls
    @State private var draggingModule: NotchModule?
    @State private var draggingControl: NotchControlItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    private var configuration: [String] {
        [String(enabled), String(calendarEnabled), String(calendarCountdown), String(notificationsEnabled), String(dismissNativeNotifications), String(gesturesEnabled), String(lyricsEnabled), String(lyricsOnline), String(queueEnabled), String(liveEqualizer), String(showPlayingMusic), idle, hiddenControls, controlOrder, size,
         String(timerEnabled), String(timerSoundEnabled), String(cameraEnabled), String(accessoriesEnabled), String(customWidth), String(customHeight), String(hapticFeedback), String(shelfWindow), String(dragReveal), String(captureControls), String(quickPanel), String(appPanel), String(hoverExpand), String(hideUntilHover), String(hideInFullscreen), String(coversMenus), display, String(hover), hidden, order, String(volume),
         String(brightness), String(keyboardLight), String(battery), String(clipboard), String(clipboardWindow), String(capture), captureAction, String(showInCaptures), String(returnHome), homeModule, String(scratchpad), String(agentsEnabled)]
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
            if tab == .content {
                GeometryReader { proxy in contentEditor(in: proxy.size) }
            } else {
                pageScroll
            }
        }
        .padding(.horizontal, 22).padding(.top, 22)
        .onChange(of: configuration) { _, _ in sync() }
        .onChange(of: accessData) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: tab) { _, _ in draggingModule = nil; draggingControl = nil }
        .onAppear(perform: consumeModuleHint)
        .onChange(of: router.notchModule) { _, _ in consumeModuleHint() }
    }

    private var pageScroll: some View {
        ScrollView {
            Group {
                switch tab {
                case .layout: layoutPage
                case .content: EmptyView()
                case .activity: activityPage
                case .behavior: behaviorPage
                }
            }.padding(.bottom, 22)
        }.id(tab)
    }

    /// A section of the island can ask for its own options; the hint is one-shot.
    private func consumeModuleHint() {
        guard let module = router.notchModule else { return }
        router.notchModule = nil
        selectedModule = module
        tab = .content
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
            SettingsCard(title: text.size) {
                HStack(spacing: 10) {
                    choice(text.compact, symbol: "rectangle.compress.vertical", selected: size == NotchSize.compact.rawValue) { size = NotchSize.compact.rawValue }
                    choice(text.spacious, symbol: "rectangle.expand.vertical", selected: size == NotchSize.spacious.rawValue) { size = NotchSize.spacious.rawValue }
                    choice(text.custom, symbol: "arrow.up.left.and.arrow.down.right", selected: size == NotchSize.custom.rawValue) { size = NotchSize.custom.rawValue }
                }
                if size == NotchSize.custom.rawValue {
                    // One grid starts both sliders at the same edge in every language.
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        dimensionSlider(text.width, value: $customWidth, range: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
                        dimensionSlider(text.maximumHeight, value: $customHeight, range: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
                    }
                    Text(text.sizeHint).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The sections in a list of their own, the chosen one's options beside
    /// it, and the island as it will look. A wide window keeps the preview
    /// in a column that never scrolls away; a narrow one puts it above the
    /// options, so they keep the height of the window either way.
    private func contentEditor(in size: CGSize) -> some View {
        let wide = size.width >= 940
        let listWidth: CGFloat = wide ? 216 : 196
        let previewWidth = wide ? min(560, ((size.width - listWidth - 32) * 0.5).rounded()) : 0
        let detailWidth = max(0, size.width - listWidth - 16 - (wide ? previewWidth + 16 : 0))
        return HStack(alignment: .top, spacing: 16) {
            sectionList
                .frame(width: listWidth, height: size.height, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let module = selectedModule
                    let available = module.isAvailable()
                    NotchSectionHeader(module: module, shown: isShown(module),
                                       reason: available ? nil : moduleFeature(module).map(enableFeatureReason) ?? text.disabled) {
                        SettingsRouter.shared.request(FeatureSettingsDestination(.features), targetFeature: moduleFeature(module))
                    }
                    if !wide { preview(width: detailWidth, limit: 280) }
                    if available, hasOptions(module) {
                        SettingsCard { moduleOptions(module) }
                    } else if available {
                        Text(editor.noOptions).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 22)
            }
            .id(selectedModule)
            .frame(width: detailWidth)
            if wide {
                preview(width: previewWidth, limit: size.height)
                    .frame(width: previewWidth)
            }
        }
    }

    private func preview(width: CGFloat, limit: CGFloat) -> some View {
        NotchIslandPreview(module: selectedModule, hidden: !isShown(selectedModule))
            .frame(height: NotchIslandPreview.height(width: width, limit: limit))
    }

    /// Every section in the island's order, each with the switch that shows it.
    private var sectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editor.sections).font(.headline)
                Text(editor.sectionsHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(orderedModules) { module in
                            NotchSectionListRow(module: module, included: moduleBinding(module), available: module.isAvailable(),
                                                selected: selectedModule == module,
                                                order: Binding(get: { orderedModules },
                                                               set: { order = $0.map(\.rawValue).joined(separator: ",") }),
                                                dragging: $draggingModule) { selectedModule = module }
                                .id(module)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                // A section chosen from the island itself may sit low in the list.
                .onAppear { reader.scrollTo(selectedModule) }
                .onChange(of: selectedModule) { _, module in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { reader.scrollTo(module) }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isShown(_ module: NotchModule) -> Bool {
        module.isAvailable() && moduleBinding(module).wrappedValue
    }

    /// The mixer, the system page and the tools arrange themselves in the island.
    private func hasOptions(_ module: NotchModule) -> Bool {
        ![.mixer, .system, .tools].contains(module)
    }

    @ViewBuilder private func moduleOptions(_ module: NotchModule) -> some View {
        switch module {
        case .controls:
            let primary = [NotchControlItem.music, .volume, .brightness]
            HStack(spacing: 10) {
                ForEach(primary) { item in
                    toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable(),
                               reason: controlReason(item), reservesReason: !primary.allSatisfy { $0.isAvailable() })
                }
            }
            Text(text.controlShortcuts).font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                ForEach(orderedShortcuts) { item in
                    PanelReorderableItem(item: item,
                        order: Binding(get: { orderedShortcuts }, set: { controlOrder = $0.map(\.rawValue).joined(separator: ",") }),
                        dragging: $draggingControl) {
                        toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable(),
                                   reason: controlReason(item), reservesReason: !orderedShortcuts.allSatisfy { $0.isAvailable() })
                    }
                }
            }
        case .music:
            let music = FeatureStrings.notchMusicExtras(l10n.language)
            switchRow("music.note", text.playingMusic, isOn: $showPlayingMusic)
            switchRow("text.quote", music.enableLyrics, isOn: $lyricsEnabled)
                .disabled(!AppFeature.notchLyrics.isAvailable)
            if lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                switchRow("globe", music.online, caption: music.onlineHint, isOn: $lyricsOnline)
                    .padding(.leading, settingsRowTextInset)
            }
            switchRow("list.bullet", music.enableQueue, caption: music.queueDescription, isOn: $queueEnabled)
                .disabled(!AppFeature.notchQueue.isAvailable)
            switchRow("waveform", music.liveEqualizer,
                      caption: NotchAudioLevelSupport.isSupported ? music.liveEqualizerHint : music.liveEqualizerUnavailable,
                      isOn: $liveEqualizer)
                .disabled(!NotchAudioLevelSupport.isSupported || !AppFeature.notchLiveEqualizer.isAvailable)
        case .notifications:
            let notifications = FeatureStrings.notchNotifications(l10n.language)
            switchRow("bell.slash", notifications.dismissSystemBanner, caption: notifications.dismissSystemBannerHint,
                      isOn: $dismissNativeNotifications)
            if notificationsEnabled, !permissions.accessibility { PermissionRow(kind: .accessibility) }
        case .downloads:
            NotchDownloadsSettingsControls()
                .toggleStyle(TrailingSwitchToggleStyle())
        case .calendar:
            let calendar = FeatureStrings.notchCalendar(l10n.language)
            Text(calendar.permission).font(.callout).foregroundStyle(.secondary)
            if permissions.calendarAccess == .fullAccess {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(calendar.allow, action: permissions.requestCalendar).disabled(permissions.requestingCalendar)
                Button(calendar.settings, action: permissions.openCalendarSettings)
            }
            Divider()
            switchRow("calendar.badge.clock", calendar.countdown, caption: calendar.countdownHint,
                      isOn: $calendarCountdown)
        case .timer:
            switchRow("speaker.wave.2", FeatureStrings.notchActivities(l10n.language).soundEnabled, isOn: $timerSoundEnabled)
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
            if shelfWindow { switchRow("hand.draw", text.dragReveal, isOn: $dragReveal) }
            if AppFeature.mediaTools.isAvailable {
                Text(FeatureStrings.notchFiles(l10n.language).optimizeDropHint)
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .clipboard:
            destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
            switchRow("doc.on.clipboard", text.clipboardActivity, caption: text.privacy, isOn: $clipboard)
        case .captures:
            switchRow("camera.viewfinder", text.captureActivity, isOn: $capture).disabled(!AppFeature.screenshot.isAvailable)
            if capture {
                ScreenshotDefaultActionPicker(strings: FeatureStrings.screenshot(l10n.language), selection: $captureAction)
                    .padding(.leading, settingsRowTextInset)
            }
        case .scratchpad:
            destination(FeatureStrings.scratchpad(l10n.language).pageTitle, symbol: "note.text", value: $scratchpad)
        case .agents:
            NotchAgentsSettingsControls()
        case .mixer, .system, .tools:
            EmptyView()
        }
    }

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: editor.resting) {
                HStack(spacing: 10) {
                    idleChoice(.none, title: text.idleNone, symbol: "minus")
                    idleChoice(.battery, title: text.battery, symbol: "battery.75percent")
                    idleChoice(.music, title: text.music, symbol: "music.note")
                    // Offered once the section is on; the island would show nothing before.
                    if offersAgentsResting {
                        idleChoice(.agents, title: FeatureStrings.notchAgents(l10n.language).restingTitle, symbol: "sparkles")
                    }
                }
                switchRow("menubar.rectangle", text.coverMenus, caption: text.coverMenusHint, isOn: $coversMenus)
            }
            SettingsCard(title: editor.feedback) {
                let volumeAvailable = AppFeature.mixer.isAvailable
                let brightnessAvailable = AppFeature.brightness.isAvailable && brightnessControlEnabled
                let keyboardLightAvailable = AppFeature.brightness.isAvailable && BrightnessService.keyboardLightIsSupported
                let batteryAvailable = AppFeature.monitorPower.isAvailable
                let accessoriesAvailable = AppFeature.notchAccessories.isAvailable && AppFeature.monitorPower.isAvailable
                let clipboardAvailable = AppFeature.clipboardHistory.isAvailable && clipboardHistoryEnabled
                    && NotchSupport.modules().contains(.clipboard)
                let capturesAvailable = AppFeature.screenshot.isAvailable && NotchSupport.modules().contains(.captures)
                let reserves = ![volumeAvailable, brightnessAvailable, keyboardLightAvailable, batteryAvailable,
                                 accessoriesAvailable, clipboardAvailable, capturesAvailable].allSatisfy { $0 }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    toggleCard(text.volume, symbol: "speaker.wave.2", value: $volume, available: volumeAvailable,
                               reason: enableFeatureReason(.mixer), reservesReason: reserves)
                    toggleCard(text.brightness, symbol: "sun.max", value: $brightness, available: brightnessAvailable,
                               reason: AppFeature.brightness.isAvailable ? editor.enableSetting(FeatureStrings.brightness(l10n.language).enable) : enableFeatureReason(.brightness),
                               reservesReason: reserves)
                    toggleCard(FeatureStrings.brightness(l10n.language).keyboardLight, symbol: "light.max", value: $keyboardLight,
                              available: keyboardLightAvailable,
                              reason: !AppFeature.brightness.isAvailable ? enableFeatureReason(.brightness) : editor.keyboardLightUnavailable,
                              reservesReason: reserves)
                    toggleCard(text.battery, symbol: "battery.75percent", value: $battery, available: batteryAvailable,
                               reason: enableFeatureReason(.monitorPower), reservesReason: reserves)
                    toggleCard(FeatureStrings.notchActivities(l10n.language).accessories, symbol: "headphones", value: $accessoriesEnabled,
                              available: accessoriesAvailable,
                              reason: enableFeatureReason(AppFeature.monitorPower.isAvailable ? .notchAccessories : .monitorPower),
                              reservesReason: reserves)
                    toggleCard(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboard,
                               available: clipboardAvailable, reason: clipboardFeedbackReason, reservesReason: reserves)
                    toggleCard(text.captures, symbol: "camera.viewfinder", value: $capture, available: capturesAvailable,
                               reason: AppFeature.screenshot.isAvailable ? editor.showPage(text.captures) : enableFeatureReason(.screenshot),
                               reservesReason: reserves)
                }
                if accessoriesEnabled { Text(FeatureStrings.notchActivities(l10n.language).accessoryDescription).font(.caption).foregroundStyle(.secondary) }
                if enabled, (volume || brightness || keyboardLight), !permissions.accessibility { PermissionRow(kind: .accessibility) }
            }
        }
    }

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: editor.opening) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    choice(editor.clickOpen, symbol: "cursorarrow", selected: !hover) { hideUntilHover = false; hover = false }
                    choice(editor.hoverPreview, symbol: "rectangle.topthird.inset.filled", selected: hover && !hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = false }
                    choice(editor.hoverExpand, symbol: "arrow.up.left.and.arrow.down.right", selected: hover && hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = true }
                    choice(editor.hiddenUntilHover, symbol: "eye.slash", selected: hover && hideUntilHover) { hover = true; hoverExpand = true; hideUntilHover = true }
                }
                if hover { hoverDelayControl }
                switchRow("hand.draw", FeatureStrings.notchGestures(l10n.language).title,
                          caption: gesturesEnabled ? FeatureStrings.notchGestures(l10n.language).hint : nil,
                          isOn: $gesturesEnabled)
                    .disabled(!AppFeature.notchGestures.isAvailable)
                switchRow("waveform.path", text.hapticFeedback, isOn: $hapticFeedback)
                SettingsRow(symbol: "arrow.uturn.backward", title: editor.reopening) {
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
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            SettingsCard(title: text.display) {
                switchRow("arrow.up.left.and.arrow.down.right", text.hideInFullscreen, isOn: $hideInFullscreen)
                HStack(spacing: 8) {
                    choice(text.automatic, symbol: "display.2", selected: display == NotchDisplay.automatic.rawValue) { display = NotchDisplay.automatic.rawValue }
                    choice(text.builtIn, symbol: "laptopcomputer", selected: display == NotchDisplay.builtIn.rawValue) { display = NotchDisplay.builtIn.rawValue }
                    choice(text.mainDisplay, symbol: "display", selected: display == NotchDisplay.main.rawValue) { display = NotchDisplay.main.rawValue }
                }
            }
            SettingsCard(title: editor.destinations) {
                destination(text.panel, symbol: "bubble.middle.top", value: $appPanel)
                Text(editor.appPanelHint).font(.caption).foregroundStyle(.secondary)
                switchRow("menubar.rectangle", editor.hideMenuBarIcon, caption: editor.hideMenuBarIconHint,
                          isOn: $hidesMenuBarIcon)
                destination(text.tools, symbol: "square.grid.2x2", value: $quickPanel, available: AppFeature.quickLauncher.isAvailable)
                destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
                destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
                destination(text.captures, symbol: "camera.viewfinder", value: $captureControls)
                destination(FeatureStrings.scratchpad(l10n.language).pageTitle, symbol: "note.text", value: $scratchpad, available: AppFeature.scratchpad.isAvailable)
            }
            SettingsCard(title: editor.privacy) {
                switchRow("camera.viewfinder", text.showInCaptures, isOn: $showInCaptures)
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

    private func enableFeatureReason(_ feature: AppFeature) -> String {
        editor.enableFeature(feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
    }

    /// A control that opens a page is off while that page is hidden, or while
    /// the feature behind it is disabled; the others follow their feature.
    private func controlReason(_ item: NotchControlItem) -> String {
        switch item {
        case .volume: return enableFeatureReason(.mixer)
        case .brightness: return enableFeatureReason(.brightness)
        case .keepAwake: return enableFeatureReason(.keepAwake)
        case .microphone: return enableFeatureReason(.micMute)
        case .screenshot: return enableFeatureReason(.screenshot)
        case .recording: return enableFeatureReason(.screenRecorder)
        case .commandBar: return enableFeatureReason(.commandBar)
        case .scratchpad: return enableFeatureReason(.scratchpad)
        case .panel: return text.disabled
        case .mixer: return pageReason(.mixer, feature: .mixer)
        case .speedTest: return pageReason(.system, feature: .monitorNetwork)
        case .music: return pageReason(.music, feature: nil)
        case .timer: return pageReason(.timer, feature: .notchTimer)
        case .calendar: return pageReason(.calendar, feature: .notchCalendar)
        }
    }

    /// The one feature a page needs; Captures and System accept any of several.
    private func moduleFeature(_ module: NotchModule) -> AppFeature? {
        switch module {
        case .controls, .music, .captures, .system: return nil
        case .mixer: return .mixer
        case .clipboard: return .clipboardHistory
        case .files: return .shelf
        case .tools: return .quickLauncher
        case .calendar: return .notchCalendar
        case .notifications: return .notchNotifications
        case .timer: return .notchTimer
        case .camera: return .cameraPreview
        case .downloads: return .notchDownloads
        case .scratchpad: return .scratchpad
        case .agents: return .notchAgents
        }
    }

    private func pageReason(_ module: NotchModule, feature: AppFeature?) -> String {
        if let feature, !feature.isAvailable { return enableFeatureReason(feature) }
        return editor.showPage(module.title(l10n.language))
    }

    private var clipboardFeedbackReason: String {
        let title = FeatureStrings.clipboard(l10n.language).title
        if !AppFeature.clipboardHistory.isAvailable { return enableFeatureReason(.clipboardHistory) }
        if !clipboardHistoryEnabled { return editor.enableSetting(FeatureStrings.clipboard(l10n.language).enable) }
        return editor.showPage(title)
    }

    private func toggleCard(_ title: String, symbol: String, value: Binding<Bool>, available: Bool, reason: String? = nil,
                            reservesReason: Bool = false) -> some View {
        NotchEditorItem(symbol: symbol, title: title, included: value, available: available,
                        unavailableReason: available ? nil : reason ?? text.disabled,
                        reservesReason: reservesReason) { value.wrappedValue.toggle() }
    }

    private var offersAgentsResting: Bool { agentsEnabled && NotchAgentSupport.isEnabled() }

    /// What the closed island rests with. A saved AI reading waits, unchanged,
    /// while its section is off, and the island rests empty meanwhile.
    private var restingChoice: NotchIdleContent {
        let choice: NotchIdleContent = NotchIdleContent(rawValue: idle) ?? .none
        return choice == .agents && !offersAgentsResting ? .none : choice
    }

    private func idleChoice(_ item: NotchIdleContent, title: String, symbol: String) -> some View {
        Button { idle = item.rawValue } label: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    if item != .none {
                        Image(systemName: symbol).font(.system(size: 11))
                        RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 20, height: 12)
                        if item == .battery || item == .agents { Text(item == .agents ? "62%" : "76%").font(.system(size: 9, weight: .medium)) }
                        else { Image(systemName: item == .music ? "waveform" : "minus").font(.system(size: 9)) }
                    } else { Color.clear.frame(width: 50, height: 12) }
                }.foregroundStyle(.white).padding(10).background(.black, in: Capsule())
                Text(title).font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(restingChoice == item ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(restingChoice == item ? .isSelected : [])
    }

    private func destination(_ title: String, symbol: String, value: Binding<Bool>, available: Bool = true) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Picker(title, selection: value) {
                Text(text.title).tag(true)
                Text(editor.separate).tag(false)
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
        }.disabled(!available)
    }

    /// An option with its icon, one line and a switch, like every other page.
    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, fallback: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: fallback) },
                              set: { value.wrappedValue = NotchSize.clamped($0, to: range, fallback: fallback) })
        return GridRow {
            // The slider carries the name for VoiceOver.
            Text(title).fixedSize().accessibilityHidden(true)
            Slider(value: bounded, in: range, step: 10) { Text(title) }.labelsHidden()
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
                && (module != .agents || agentsEnabled)
                && !hidden.split(separator: ",").contains(Substring(module.rawValue))
        } set: { shown in
            if module == .timer { timerEnabled = shown }
            if module == .camera { cameraEnabled = shown }
            if module == .calendar { calendarEnabled = shown }
            if module == .notifications { notificationsEnabled = shown }
            if module == .agents { agentsEnabled = shown }
            var values = Set(hidden.split(separator: ",").map(String.init))
            if shown { values.remove(module.rawValue) } else { values.insert(module.rawValue) }
            hidden = values.sorted().joined(separator: ",")
        }
    }

}

extension NotchControlItem: PanelOrderItem {}
