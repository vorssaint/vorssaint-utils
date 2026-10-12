// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

struct DockEnhancementsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.notchIncludeOtherPlayers) private var otherPlayers = true
    var body: some View {
        VStack(spacing: 20) {
            if AppFeature.dockIndicator.isAvailable {
                SettingsCard(title: text(.indicator)) {
                    DockToggle(.indicatorEnabled, .indicator)
                    DockChoice(.indicatorStyle, .indicator, [("line", .line), ("dots", .dots)])
                    DockText(.indicatorColor, .color)
                    DockNumber(.indicatorThickness, .thickness, 1...12)
                    DockNumber(.indicatorLength, .length, 4...128)
                    DockNumber(.indicatorOffset, .offset, -20...20)
                }
            }
            if AppFeature.dockLock.isAvailable {
                SettingsCard(title: text(.dockLock)) {
                    DockToggle(.lockEnabled, .dockLock)
                    Text(text(.lockDescription)).font(.caption).foregroundStyle(.secondary)
                    DockDisplayPicker()
                    DockModifierPicker(option: .lockModifier)
                }
            }
            if AppFeature.dockPreview.isAvailable {
                SettingsCard(title: text(.enhancements)) {
                    DockToggle(.folders, .folders)
                    DockToggle(.folderHiddenFiles, .hiddenFiles)
                    DockToggle(.folderRememberSort, .remember)
                    DockToggle(.mediaWidget, .media)
                    Toggle(FeatureStrings.notchMusicExtras(l10n.language).includeOtherPlayers, isOn: $otherPlayers)
                        .onChange(of: otherPlayers) { changedDockOption() }
                    DockToggle(.widgetLyrics, .lyrics)
                    DockToggle(.calendarWidget, .calendar)
                    if DockOption.calendarWidget.bool, permissions.calendarAccess != .fullAccess {
                        Button(FeatureStrings.notchCalendar(l10n.language).allow, action: permissions.requestCalendar)
                            .disabled(permissions.requestingCalendar)
                    }
                    DockToggle(.nativeCmdTab, "⌘Tab")
                    DockToggle(.compact, .compact)
                    DockInteger(.compactThreshold, .threshold, 0...48)
                    DockChoice(.trigger, .trigger, [("hover", .mouseHover), ("middle", .middleClick), ("modifier", .modifierClick)])
                    DockModifierPicker(option: .triggerModifier)
                    DockChoice(.hoverAction, .hover, [("off", .off), ("activate", .activate), ("full", .fullPreview)])
                    DockNumber(.hoverDelay, .delay, 0...3, step: 0.1)
                    DockToggle(.livePreviews, .live)
                    DockInteger(.liveFrameRate, .fps, 5...120)
                    DockInteger(.liveQuality, .quality, 320...2048, step: 160)
                    DockToggle(.gestures, .gestures)
                    DockChoice(.shakeAction, .shake, [("off", .off), ("minimizeOthers", .shake)])
                    DockToggle(.dockScroll, .scroll)
                    DockToggle(.titleBarScroll, .titleBar)
                    DockToggle(.quickQuit, .quickQuit)
                    DockChoice(.middleClickAction, .middleClick, [("off", text(.off)), ("close", l10n.s.dockPreviewCloseWindow), ("minimize", l10n.s.dockPreviewMinimizeWindow), ("maximize", text(.maximize)), ("fullscreen", text(.fullscreen)), ("quit", text(.quit)), ("hide", text(.hide))])
                    DockToggle(.spaceNumbers, .spaceNumbers)
                    DockToggle(.groupInstances, .groupInstances)
                    DockChoice(.sortOrder, .sort, [("recent", .recent), ("creation", .creation), ("title", .title), ("app", .app)])
                    DockText(.windowTitleFilters, .filters, multiline: true)
                    DockNumber(.cornerRadius, .radius, 0...40)
                    DockNumber(.spacing, .spacing, 0...40)
                    DockInteger(.maxRows, .rows, 1...4)
                    DockInteger(.maxColumns, .columns, 1...4)
                    DockChoice(.controlsPosition, .controls, [("top", "↑"), ("bottom", "↓")])
                    DockChoice(.pointerFollowsFocus, .pointer, [("off", .off), ("display", .display), ("always", .activate)])
                    DockToggle(.automation, .automation)
                }
            }
        }
    }
    private func text(_ term: DockEnhancementStrings.Term) -> String { DockEnhancementStrings.text(term) }
}

struct SwitcherEnhancementsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        SettingsCard(title: DockEnhancementStrings.text(.enhancements)) {
            DockToggle(.switcherLivePreviews, .live)
            DockInteger(.liveFrameRate, .fps, 5...120)
            DockInteger(.liveQuality, .quality, 320...2048, step: 160)
            DockChoice(.sortOrder, .sort, [("recent", .recent), ("creation", .creation), ("title", .title), ("app", .app)])
            DockText(.windowTitleFilters, .filters, multiline: true)
            DockChoice(.pointerFollowsFocus, .pointer, [("off", .off), ("display", .display), ("always", .activate)])
            DockToggle(.trackpadSwitcher, .trackpad)
            DockChoice(.trackpadFingers, "🖐", [("3", "3"), ("4", "4")], integer: true)
            DockChoice(.trackpadDirection, .trackpad, [("horizontal", "↔"), ("vertical", "↕")])
            DockToggle(.vimNavigation, .vim)
            DockInteger(.searchFuzziness, .fuzzy, 0...3)
            DockMinimizeKeyPicker()
        }
    }
}

private func changedDockOption() {
    if AppFeature.dockPreview.isAvailable {
        DockPreviewService.shared.hideAllPreviews()
        DockPreviewService.shared.syncWithPreferences()
    }
    if AppFeature.switcher.isAvailable { AppSwitcher.shared.syncWithPreferences() }
    DockAdditionsRuntime.shared.sync()
}

private struct DockToggle: View {
    let label: String
    @AppStorage private var value: Bool
    init(_ option: DockOption, _ term: DockEnhancementStrings.Term) { self.init(option, DockEnhancementStrings.text(term)) }
    init(_ option: DockOption, _ label: String) { self.label = label; _value = AppStorage(wrappedValue: option.defaultValue as? Bool ?? false, option.key) }
    var body: some View { Toggle(label, isOn: $value).onChange(of: value) { changedDockOption() } }
}

private struct DockChoice: View {
    let option: DockOption, label: String, choices: [(String, String)], integer: Bool
    @AppStorage private var value: String
    init(_ option: DockOption, _ term: DockEnhancementStrings.Term, _ choices: [(String, DockEnhancementStrings.Term)]) {
        self.init(option, DockEnhancementStrings.text(term), choices.map { ($0.0, DockEnhancementStrings.text($0.1)) })
    }
    init(_ option: DockOption, _ term: DockEnhancementStrings.Term, _ choices: [(String, String)]) { self.init(option, DockEnhancementStrings.text(term), choices) }
    init(_ option: DockOption, _ label: String, _ choices: [(String, String)], integer: Bool = false) {
        self.option = option; self.label = label; self.choices = choices; self.integer = integer
        _value = AppStorage(wrappedValue: option.defaultValue as? String ?? "", option.key)
    }
    var body: some View {
        Picker(label, selection: Binding(get: { integer ? String(option.int) : value }, set: {
            if integer { UserDefaults.standard.set(Int($0) ?? 3, forKey: option.key) } else { value = $0 }
            changedDockOption()
        })) { ForEach(choices, id: \.0) { Text($0.1).tag($0.0) } }
    }
}

private struct DockNumber: View {
    let term: DockEnhancementStrings.Term, range: ClosedRange<Double>, step: Double
    @AppStorage private var value: Double
    init(_ option: DockOption, _ term: DockEnhancementStrings.Term, _ range: ClosedRange<Double>, step: Double = 1) {
        self.term = term; self.range = range; self.step = step; _value = AppStorage(wrappedValue: option.double, option.key)
    }
    var body: some View { Stepper(value: $value, in: range, step: step) { Text(DockEnhancementStrings.text(term) + ": " + value.formatted(.number.precision(.fractionLength(0...1)))) }.onChange(of: value) { changedDockOption() } }
}

private struct DockInteger: View {
    let term: DockEnhancementStrings.Term, range: ClosedRange<Int>, step: Int
    @AppStorage private var value: Int
    init(_ option: DockOption, _ term: DockEnhancementStrings.Term, _ range: ClosedRange<Int>, step: Int = 1) {
        self.term = term; self.range = range; self.step = step; _value = AppStorage(wrappedValue: option.int, option.key)
    }
    var body: some View { Stepper(value: $value, in: range, step: step) { Text(DockEnhancementStrings.text(term) + ": " + String(value)) }.onChange(of: value) { changedDockOption() } }
}

private struct DockText: View {
    let term: DockEnhancementStrings.Term, multiline: Bool
    @AppStorage private var value: String
    init(_ option: DockOption, _ term: DockEnhancementStrings.Term, multiline: Bool = false) {
        self.term = term; self.multiline = multiline; _value = AppStorage(wrappedValue: option.string, option.key)
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text(DockEnhancementStrings.text(term))
            TextField("", text: $value, axis: multiline ? .vertical : .horizontal).textFieldStyle(.roundedBorder).lineLimit(multiline ? 3...5 : 1...1)
        }.onChange(of: value) { changedDockOption() }
    }
}

private struct DockDisplayPicker: View {
    @AppStorage(DockOption.lockDisplay.key) private var display = "main"
    var body: some View {
        Picker(DockEnhancementStrings.text(.display), selection: $display) {
            Text(DockEnhancementStrings.text(.automatic)).tag("main")
            ForEach(NSScreen.screens, id: \.self) { screen in Text(screen.localizedName).tag(DockLockService.identifier(screen)) }
            if display != "main", !NSScreen.screens.contains(where: { DockLockService.identifier($0) == display }) { Text(display).tag(display) }
        }.onChange(of: display) { changedDockOption() }
    }
}

private struct DockModifierPicker: View {
    let option: DockOption
    @AppStorage private var value: String
    init(option: DockOption) { self.option = option; _value = AppStorage(wrappedValue: "option", option.key) }
    var body: some View {
        Picker(DockEnhancementStrings.text(.modifier), selection: $value) {
            Text("⌥").tag("option"); Text("⌘").tag("command"); Text("⌃").tag("control"); Text("⇧").tag("shift")
        }.onChange(of: value) { changedDockOption() }
    }
}

private struct DockMinimizeKeyPicker: View {
    @AppStorage(DockOption.minimizeKey.key) private var key = -1
    var body: some View {
        Picker(L10n.shared.s.dockPreviewMinimizeWindow, selection: $key) {
            Text(DockEnhancementStrings.text(.off)).tag(-1); Text("M").tag(46); Text("X").tag(7); Text("N").tag(45)
        }.onChange(of: key) { changedDockOption() }
    }
}
