// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KeyboardRemapSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = KeyboardRemapService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.keyboardRemapEnabled) private var enabled = false
    @AppStorage(DefaultsKey.keyboardRemapKeyRules) private var keyStorage = "[]"
    @AppStorage(DefaultsKey.keyboardRemapShortcutRules) private var shortcutStorage = "[]"
    @State private var editingKey: KeyboardRemapKeyRule?
    @State private var editingShortcut: KeyboardRemapShortcutRule?
    @State private var selectedPreset: KeyboardRemapPreset?

    private func text(_ key: String) -> String { KeyboardRemapStrings.text(key, language: l10n.language) }
    private var config: KeyboardRemapConfiguration {
        var result = KeyboardRemapConfiguration()
        result.keyRules = KeyboardRemapConfiguration.decode(keyStorage) ?? []
        result.shortcutRules = KeyboardRemapConfiguration.decode(shortcutStorage) ?? []
        return result
    }
    private func save(_ value: KeyboardRemapConfiguration) {
        keyStorage = KeyboardRemapConfiguration.encode(value.keyRules)
        shortcutStorage = KeyboardRemapConfiguration.encode(value.shortcutRules)
        service.syncWithPreferences()
    }

    var body: some View {
        Form {
            Section(text("pageTitle")) {
                Toggle(text("enable"), isOn: $enabled)
                Text(text("genericNote")).font(.caption).foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(text("active"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let status = service.statusKey {
                    Label(text(status), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if service.statusKey == "modifierConflict" {
                    HStack {
                        Button(text("keyboardSettings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button(text("retry")) { service.syncWithPreferences() }
                    }
                }
                if let error = config.validationKey {
                    Text(text(error)).font(.caption).foregroundStyle(.orange)
                }
            }
            Section(text("keyRules")) {
                Text(text("keyRulesNote")).font(.caption).foregroundStyle(.secondary)
                ForEach(config.keyRules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(get: { rule.enabled }, set: { value in
                            var next = config
                            if let index = next.keyRules.firstIndex(where: { $0.id == rule.id }) { next.keyRules[index].enabled = value }
                            save(next)
                        })).labelsHidden().accessibilityLabel(KeyboardRemapKey.named(rule.source)?.displayLabel ?? rule.source)
                        Text(KeyboardRemapKey.named(rule.source)?.displayLabel ?? rule.source)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(KeyboardRemapRuleLabel.target(rule.target))
                        Spacer()
                        Button(text("edit")) { editingKey = rule }
                        Button { var next = config; next.keyRules.removeAll { $0.id == rule.id }; save(next) }
                            label: { Image(systemName: "trash") }.help(text("removeRule"))
                    }
                }
                Button(text("addKeyRule")) {
                    let source = KeyboardRemapKey.all.first { key in !config.keyRules.contains { $0.source == key.id } }?.id ?? "fn"
                    editingKey = .init(source, .key(source == "leftCommand" ? "leftControl" : "leftCommand"))
                }
            }
            Section(text("shortcutRules")) {
                Text(text("shortcutRulesNote")).font(.caption).foregroundStyle(.secondary)
                ForEach(config.shortcutRules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(get: { rule.enabled }, set: { value in
                            var next = config
                            if let index = next.shortcutRules.firstIndex(where: { $0.id == rule.id }) { next.shortcutRules[index].enabled = value }
                            save(next)
                        })).labelsHidden().accessibilityLabel(rule.source.label)
                        Text(rule.source.label)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(KeyboardRemapRuleLabel.target(rule.target))
                        Spacer()
                        Button(text("edit")) { editingShortcut = rule }
                        Button { var next = config; next.shortcutRules.removeAll { $0.id == rule.id }; save(next) }
                            label: { Image(systemName: "trash") }.help(text("removeRule"))
                    }
                }
                Button(text("addShortcutRule")) { editingShortcut = .init(.init(40, [.control, .option]), .none) }
            }
            Section(text("suggestion")) {
                Text(text("suggestionNote")).font(.caption).foregroundStyle(.secondary)
                ForEach(KeyboardRemapPreset.allCases) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(text(preset.titleKey))
                            Text(text(preset.noteKey)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(text("viewSuggestion")) { selectedPreset = preset }
                            .accessibilityLabel(text("viewSuggestion") + " " + text(preset.titleKey))
                    }
                }
            }
            Section(text("preview")) {
                if config.isEmpty { Text(text("emptyRules")).foregroundStyle(.secondary) }
                ForEach(config.keyRules.filter(\.enabled)) { rule in
                    LabeledContent(KeyboardRemapKey.named(rule.source)?.displayLabel ?? rule.source, value: KeyboardRemapRuleLabel.target(rule.target))
                }
                ForEach(config.shortcutRules.filter(\.enabled)) { rule in
                    LabeledContent(rule.source.label, value: KeyboardRemapRuleLabel.target(rule.target))
                }
                Text(enabled ? text("restored") : text("inactive")).font(.caption).foregroundStyle(.secondary)
                Button(text("clearRules")) { save(KeyboardRemapConfiguration()) }
                    .disabled(config.keyRules.isEmpty && config.shortcutRules.isEmpty)
            }
            Section(text("compatibility")) {
                Text(text("genericHardware")).font(.caption).foregroundStyle(.secondary)
                Text(text("genericActions")).font(.caption).foregroundStyle(.secondary)
            }
            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) { PermissionRow(kind: .accessibility) }
            }
        }
        .formStyle(.grouped)
        .onAppear { service.syncWithPreferences() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.syncWithPreferences()
        }
        .onChange(of: enabled) { _, value in
            service.syncWithPreferences()
            if value, !permissions.accessibility {
                permissions.requestAccessibility(); permissions.openAccessibilitySettings()
            }
        }
        .sheet(item: $editingKey) { rule in
            KeyboardRemapKeyEditor(rule: rule, config: config) { updated in
                var next = config
                if let index = next.keyRules.firstIndex(where: { $0.id == updated.id }) { next.keyRules[index] = updated }
                else { next.keyRules.append(updated) }
                save(next)
            }
        }
        .sheet(item: $editingShortcut) { rule in
            KeyboardRemapShortcutEditor(rule: rule, config: config) { updated in
                var next = config
                if let index = next.shortcutRules.firstIndex(where: { $0.id == updated.id }) { next.shortcutRules[index] = updated }
                else { next.shortcutRules.append(updated) }
                save(next)
            }
        }
        .sheet(item: $selectedPreset) { preset in
            KeyboardRemapPresetPreview(preset: preset) {
                var next = config
                next.addSuggestion(preset)
                save(next)
            }
        }
    }
}

private struct KeyboardRemapPresetPreview: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    let preset: KeyboardRemapPreset
    let onAdd: () -> Void

    private func text(_ key: String) -> String {
        KeyboardRemapStrings.text(key, language: l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text(preset.titleKey)).font(.title2)
            Text(text(preset.noteKey)).foregroundStyle(.secondary)
            let suggested = preset.configuration
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text(text("from")).font(.caption).foregroundStyle(.secondary)
                    Color.clear.frame(width: 16, height: 1)
                    Text(text("to")).font(.caption).foregroundStyle(.secondary)
                }
                Divider().gridCellColumns(3)
                ForEach(suggested.keyRules) { rule in
                    previewRow(KeyboardRemapKey.named(rule.source)?.readableLabel ?? rule.source, target: rule.target)
                }
                ForEach(suggested.shortcutRules) { rule in
                    previewRow(rule.source.readableLabel, target: rule.target)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text(text("suggestionMerge")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(text("cancel")) { dismiss() }
                Spacer()
                Button(text("addSuggestion")) {
                    onAdd()
                    dismiss()
                }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
    }

    private func previewRow(_ source: String, target: KeyboardRemapTarget) -> some View {
        GridRow {
            Text(source)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(KeyboardRemapRuleLabel.previewTarget(target))
        }
    }

}

private enum KeyboardRemapRuleLabel {
    static func previewTarget(_ target: KeyboardRemapTarget) -> String {
        if case .key(let id) = target { return KeyboardRemapKey.named(id)?.readableLabel ?? id }
        return self.target(target)
    }

    static func target(_ target: KeyboardRemapTarget) -> String {
        if case .application(let id) = target {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url.deletingPathExtension().lastPathComponent
            }
            return id.isEmpty ? KeyboardRemapStrings.text("chooseApp") : id
        }
        return target.label
    }
}

private struct KeyboardRemapKeyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State var rule: KeyboardRemapKeyRule
    let config: KeyboardRemapConfiguration
    let onSave: (KeyboardRemapKeyRule) -> Void
    private func text(_ key: String) -> String { KeyboardRemapStrings.text(key, language: l10n.language) }
    private var validation: String? {
        var next = config; next.keyRules.removeAll { $0.id == rule.id }; next.keyRules.append(rule)
        return next.validationKey
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("keyRules")).font(.title2)
            Form {
                Picker(text("from"), selection: $rule.source) {
                    ForEach(KeyboardRemapKey.all) { Text($0.displayLabel).tag($0.id) }
                }
                KeyboardRemapTargetEditor(target: $rule.target, allowKey: true, config: config)
                Toggle(text("ruleEnabled"), isOn: $rule.enabled)
            }
            if let validation { Text(text(validation)).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button(text("cancel")) { dismiss() }
                Spacer()
                Button(text("save")) { onSave(rule); dismiss() }.disabled(validation != nil).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500)
    }
}

private struct KeyboardRemapShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State var rule: KeyboardRemapShortcutRule
    let config: KeyboardRemapConfiguration
    let onSave: (KeyboardRemapShortcutRule) -> Void
    private func text(_ key: String) -> String { KeyboardRemapStrings.text(key, language: l10n.language) }
    private var validation: String? {
        var next = config; next.shortcutRules.removeAll { $0.id == rule.id }; next.shortcutRules.append(rule)
        return next.validationKey
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("shortcutRules")).font(.title2)
            Form {
                Section(text("from")) { KeyboardRemapChordEditor(chord: $rule.source, allowCaps: true, config: config) }
                Section(text("to")) { KeyboardRemapTargetEditor(target: $rule.target, allowKey: false, config: config) }
                Toggle(text("ruleEnabled"), isOn: $rule.enabled)
            }
            if let validation { Text(text(validation)).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button(text("cancel")) { dismiss() }
                Spacer()
                Button(text("save")) { onSave(rule); dismiss() }.disabled(validation != nil).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}

private struct KeyboardRemapChordEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var chord: KeyboardRemapChord
    let allowCaps: Bool
    let config: KeyboardRemapConfiguration
    @State private var recordError: String?
    var body: some View {
        Picker(KeyboardRemapStrings.text("key"), selection: Binding(get: { chord.keyCode }, set: { chord.keyCode = $0; chord.character = nil })) {
            ForEach(KeyboardRemapKey.all.filter {
                (!$0.isModifier || (allowCaps && config.actionSources.contains($0)))
                    && (allowCaps || $0.id != "capsLock")
            }) {
                Text($0.displayLabel).tag($0.code)
            }
        }
        HStack {
            ForEach([GlobalShortcutModifiers.control, .option, .shift, .command], id: \.rawValue) { modifier in
                Toggle(modifier.keyCaps.joined(), isOn: Binding(get: { chord.shortcut.modifiers.contains(modifier) }, set: { value in
                    var modifiers = chord.shortcut.modifiers
                    if value { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
                    chord.modifiers = modifiers.rawValue
                })).toggleStyle(.button)
            }
            Spacer()
            ShortcutRecorderButton(shortcut: chord.shortcut, isEnabled: true, waitingTitle: l10n.s.shortcutPressKeys,
                                   requiresModifier: false, invalidAction: { recordError = l10n.s.shortcutInvalid }, captureAction: { shortcut in
                let source = allowCaps ? config.triggers.first { $0.trigger.code == shortcut.keyCode }?.source.code : nil
                chord = .init(source ?? shortcut.keyCode, shortcut.modifiers)
                recordError = nil
            }).frame(width: 130)
        }
        if let character = chord.character {
            Text(KeyboardRemapStrings.text("layoutNote") + " " + character.uppercased()).font(.caption).foregroundStyle(.secondary)
        }
        if let recordError { Text(recordError).font(.caption).foregroundStyle(.orange) }
    }
}

private struct KeyboardRemapTargetEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var target: KeyboardRemapTarget
    let allowKey: Bool
    let config: KeyboardRemapConfiguration
    private func text(_ key: String) -> String { KeyboardRemapStrings.text(key, language: l10n.language) }
    private var kind: Binding<String> {
        Binding(get: { target.kind }, set: {
            switch $0 {
            case "key": target = .key("escape")
            case "shortcut": target = .shortcut(.init(53))
            case "inputSource": target = .inputSource
            case "capsLock": target = .capsLock
            case "application": target = .application("")
            default: target = .none
            }
        })
    }
    var body: some View {
        Picker(text("to"), selection: kind) {
            if allowKey { Text(text("key")).tag("key") }
            Text(text("shortcut")).tag("shortcut")
            Text(text("doNothing")).tag("none")
            Text(text("nextLanguage")).tag("inputSource")
            Text(text("toggleCaps")).tag("capsLock")
            Text(text("openApp")).tag("application")
        }
        switch target {
        case .key(let id):
            Picker(text("key"), selection: Binding(get: { id }, set: { target = .key($0) })) {
                ForEach(KeyboardRemapKey.all) { Text($0.displayLabel).tag($0.id) }
            }
        case .shortcut(let chord):
            KeyboardRemapChordEditor(chord: Binding(get: { chord }, set: { target = .shortcut($0) }), allowCaps: false, config: config)
        case .application:
            HStack {
                Text(KeyboardRemapRuleLabel.target(target))
                Spacer()
                Button(text("chooseApp")) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.applicationBundle]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
                        target = .application(id)
                    }
                }
            }
        default: EmptyView()
        }
    }
}
