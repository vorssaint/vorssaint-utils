// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct KeyboardRemappingSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var remapping = KeyboardRemappingService.shared
    @AppStorage(DefaultsKey.keyboardRemappingEnabled) private var enabled = false
    @AppStorage(DefaultsKey.keyboardRemappingRules) private var rulesRaw = "[]"
    @State private var rules: [KeyboardRemappingRule] = []
    @StateObject private var capture = KeyboardRemappingCapture()
    @State private var showingAppPicker = false
    @State private var appPickerRuleID: UUID?
    @State private var choosingActionApp = false
    @State private var pendingEnable: PendingEnable?

    private enum PendingEnable: Equatable {
        case system
        case rule(UUID)
    }

    private var strings: KeyboardRemappingStrings {
        FeatureStrings.keyboardRemapping(l10n.language)
    }

    private var hasEnabledRiskyRules: Bool {
        rules.contains { $0.enabled && $0.isValid && $0.sourceRisk != nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle(strings[.enabled], isOn: systemEnabledBinding)
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { _, value in
                        remapping.syncWithPreferences()
                        guard value, rules.contains(where: { $0.enabled && $0.isValid }),
                              !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                if enabled {
                    switch remapping.tapStatus {
                    case .inactive:
                        EmptyView()
                    case .starting:
                        Label(strings[.starting], systemImage: "keyboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .active:
                        Label(strings[.active], systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed:
                        Label(strings[.failed], systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                if rules.isEmpty {
                    ContentUnavailableView(strings[.emptyTitle],
                                           systemImage: "keyboard",
                                           description: Text(strings[.emptyDescription]))
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .multilineTextAlignment(.center)
                }
                ForEach($rules) { $rule in
                    ruleEditor(rule: $rule)
                }
                Button {
                    rules.append(KeyboardRemappingRule())
                } label: {
                    Label(strings[.addRule], systemImage: "plus")
                }
                .disabled(!enabled || rules.count >= KeyboardRemappingConfig.maximumRules)
            } header: {
                Text(strings[.rulesTitle])
            } footer: {
                Text(strings[.rulesFooter])
            }
            .disabled(!enabled)

            if enabled, rules.contains(where: { $0.enabled && $0.isValid }), !permissions.accessibility {
                Section(strings[.permissionRequired]) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rules = KeyboardRemappingConfig.decode(rulesRaw)
            remapping.syncWithPreferences()
        }
        .onChange(of: rules) { _, value in
            rulesRaw = KeyboardRemappingConfig.encode(value)
            remapping.syncWithPreferences()
            guard enabled, value.contains(where: { $0.enabled && $0.isValid }),
                  !permissions.accessibility else { return }
            permissions.requestAccessibility()
            permissions.openAccessibilitySettings()
        }
        .onChange(of: rulesRaw) { _, value in
            rules = KeyboardRemappingConfig.decode(value)
            remapping.syncWithPreferences()
        }
        .onDisappear {
            capture.cancel()
        }
        .confirmationDialog(
            strings[.riskDialogTitle],
            isPresented: Binding(
                get: { pendingEnable != nil },
                set: { if !$0 { pendingEnable = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(strings[.enableAnyway], role: .destructive) {
                confirmPendingEnable()
            }
            Button(strings[.cancel], role: .cancel) {
                pendingEnable = nil
            }
        } message: {
            Text(pendingEnableMessage)
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(canBrowseApplications: true, onCancel: {
                showingAppPicker = false
                appPickerRuleID = nil
                choosingActionApp = false
            }, onSelect: { url in
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                    showingAppPicker = false
                    appPickerRuleID = nil
                    choosingActionApp = false
                    return
                }
                setPickedApp(bundleID)
            }, onSelectApp: { app in
                guard let bundleID = app.bundleID else {
                    showingAppPicker = false
                    appPickerRuleID = nil
                    choosingActionApp = false
                    return
                }
                setPickedApp(bundleID)
            }, loadApps: {
                InstalledApps.installedBundleApplications(excluding: [])
            })
        }
    }

    private var systemEnabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { value in
                guard value, !enabled else {
                    enabled = value
                    return
                }
                if hasEnabledRiskyRules {
                    pendingEnable = .system
                } else {
                    enabled = true
                }
            }
        )
    }

    private var pendingEnableMessage: String {
        switch pendingEnable {
        case .system:
            return strings[.systemRiskWarning]
        case .rule(let id):
            guard let risk = rules.first(where: { $0.id == id })?.sourceRisk else {
                return strings[.genericRiskWarning]
            }
            return strings.warning(for: risk)
        case nil:
            return ""
        }
    }

    private func confirmPendingEnable() {
        guard let pendingEnable else { return }
        switch pendingEnable {
        case .system:
            enabled = true
        case .rule(let id):
            if let index = rules.firstIndex(where: { $0.id == id }) {
                rules[index].enabled = true
            }
        }
        self.pendingEnable = nil
    }

    private func ruleEnabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { rules.first(where: { $0.id == id })?.enabled ?? false },
            set: { value in
                guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
                if value, rules[index].sourceRisk != nil {
                    pendingEnable = .rule(id)
                } else {
                    rules[index].enabled = value
                }
            }
        )
    }

    private func ruleEditor(rule: Binding<KeyboardRemappingRule>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.wrappedValue.sourceKeyCode < 0
                         ? strings[.newRule]
                         : capture.buttonTitle(for: rule.wrappedValue.sourceKeyCode,
                                               modifiers: rule.wrappedValue.sourceModifiers,
                                               placeholder: strings[.sourceKey],
                                               strings: strings))
                        .font(.headline)
                    Text(rule.wrappedValue.bundleIdentifier.isEmpty ? strings[.allApps] : InstalledApps.name(for: rule.wrappedValue.bundleIdentifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle(strings[.enableRule],
                       isOn: ruleEnabledBinding(for: rule.wrappedValue.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(strings[.enableRule])
                Button(role: .destructive) {
                    rules.removeAll { $0.id == rule.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(strings[.removeRule])
                .accessibilityLabel(strings[.removeRule])
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(strings[.whenPressed])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(capture.buttonTitle(for: rule.wrappedValue.sourceKeyCode,
                                               modifiers: rule.wrappedValue.sourceModifiers,
                                               placeholder: strings[.recordSource],
                                               strings: strings)) {
                        capture.begin { keyCode, modifiers in
                            let wasEnabled = rule.wrappedValue.enabled
                            let risk = KeyboardRemappingRisk.forSourceKeyCode(keyCode)
                            if wasEnabled, risk != nil {
                                rule.wrappedValue.enabled = false
                            }
                            rule.wrappedValue.sourceKeyCode = keyCode
                            rule.wrappedValue.sourceModifierMask = modifiers.rawValue
                            if wasEnabled, risk != nil {
                                pendingEnable = .rule(rule.wrappedValue.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(width: 155, alignment: .leading)
                    if let risk = rule.wrappedValue.sourceRisk {
                        Label(strings.warning(for: risk), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(strings[.send])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    Picker(strings[.actionPicker], selection: Binding(
                        get: { rule.wrappedValue.resolvedActionKind },
                        set: { rule.wrappedValue.actionKind = $0 }
                    )) {
                        Text(strings[.sendKeys]).tag(KeyboardRemappingActionKind.keySequence)
                        Text(strings[.typeText]).tag(KeyboardRemappingActionKind.typeText)
                        Text(strings[.openLink]).tag(KeyboardRemappingActionKind.openLink)
                        Text(strings[.openApp]).tag(KeyboardRemappingActionKind.openApp)
                        Text(strings[.disableShortcut]).tag(KeyboardRemappingActionKind.disabled)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    }
                    actionEditor(rule: rule)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 8) {
                if rule.wrappedValue.bundleIdentifier.isEmpty {
                    Image(systemName: "app")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text(strings[.allApps])
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: InstalledApps.icon(for: rule.wrappedValue.bundleIdentifier))
                        .resizable()
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(InstalledApps.name(for: rule.wrappedValue.bundleIdentifier))
                            .lineLimit(1)
                        Text(rule.wrappedValue.bundleIdentifier)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button(strings[.chooseApp]) {
                    appPickerRuleID = rule.wrappedValue.id
                    showingAppPicker = true
                }
                .controlSize(.small)
                if !rule.wrappedValue.bundleIdentifier.isEmpty {
                    Button {
                        rule.wrappedValue.bundleIdentifier = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(strings[.applyAllApps])
                    .accessibilityLabel(strings[.applyAllApps])
                }
            }

            if capture.isCapturing {
                HStack(spacing: 8) {
                    Label(strings[.capturePrompt], systemImage: "keyboard")
                    Spacer()
                    Button(strings[.cancel]) { capture.cancel() }
                        .buttonStyle(.borderless)
                }
                .font(.caption)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if !rule.wrappedValue.hasValidBundleIdentifier {
                Text(strings[.invalidBundle])
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func actionEditor(rule: Binding<KeyboardRemappingRule>) -> some View {
        switch rule.wrappedValue.resolvedActionKind {
        case .keySequence:
            if rule.wrappedValue.output.isEmpty {
                Button {
                    rule.wrappedValue.output.append(KeyboardRemappingChord())
                } label: {
                    Label(strings[.addKey], systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(rule.wrappedValue.output.indices), id: \.self) { index in
                            let chord = rule.output[index]
                            HStack(spacing: 4) {
                                Button(capture.buttonTitle(for: chord.wrappedValue.keyCode,
                                                           modifiers: chord.wrappedValue.modifiers,
                                                           placeholder: strings[.recordKey],
                                                           strings: strings)) {
                                    capture.begin { keyCode, modifiers in
                                        chord.wrappedValue.keyCode = keyCode
                                        chord.wrappedValue.modifierMask = modifiers.rawValue
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .frame(minWidth: 108)
                                if rule.wrappedValue.output.count > 1 {
                                    Button {
                                        rule.wrappedValue.output.removeAll { $0.id == chord.wrappedValue.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(strings[.removeOutputKey])
                                    .accessibilityLabel("\(strings[.removeOutputKey]) \(index + 1)")
                                }
                            }
                        }
                        Button {
                            rule.wrappedValue.output.append(KeyboardRemappingChord())
                        } label: {
                            Label(strings[.addKey], systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(rule.wrappedValue.output.count >= KeyboardRemappingConfig.maximumOutputChords)
                    }
                }
                .scrollIndicators(.visible)
            }
        case .typeText:
            TextField(strings[.textField], text: rule.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .frame(maxWidth: 300)
        case .openLink:
            TextField("https://example.com", text: rule.link)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
        case .openApp:
            HStack(spacing: 8) {
                if rule.wrappedValue.appBundleIdentifier.isEmpty {
                    Text(strings[.chooseAnApp])
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: InstalledApps.icon(for: rule.wrappedValue.appBundleIdentifier))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(InstalledApps.name(for: rule.wrappedValue.appBundleIdentifier))
                        .lineLimit(1)
                }
                Button(strings[.chooseEllipsis]) {
                    appPickerRuleID = rule.wrappedValue.id
                    choosingActionApp = true
                    showingAppPicker = true
                }
                .controlSize(.small)
            }
        case .disabled:
            Label(strings[.disabledDescription], systemImage: "slash.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setAppRestriction(_ bundleID: String) {
        if let appPickerRuleID,
           let index = rules.firstIndex(where: { $0.id == appPickerRuleID }) {
            rules[index].bundleIdentifier = bundleID
        }
        showingAppPicker = false
        appPickerRuleID = nil
        choosingActionApp = false
    }

    private func setPickedApp(_ bundleID: String) {
        if choosingActionApp,
           let appPickerRuleID,
           let index = rules.firstIndex(where: { $0.id == appPickerRuleID }) {
            rules[index].appBundleIdentifier = bundleID
        } else {
            setAppRestriction(bundleID)
            return
        }
        showingAppPicker = false
        appPickerRuleID = nil
        choosingActionApp = false
    }
}

@MainActor
private final class KeyboardRemappingCapture: ObservableObject {
    @Published private(set) var isCapturing = false
    private var monitor: Any?
    private var onCapture: ((Int64, GlobalShortcutModifiers) -> Void)?

    func begin(onCapture: @escaping (Int64, GlobalShortcutModifiers) -> Void) {
        cancel()
        self.onCapture = onCapture
        isCapturing = true
        KeyboardRemappingService.shared.setCaptureInProgress(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isCapturing else { return event }
            self.onCapture?(Int64(event.keyCode), GlobalShortcutModifiers(eventFlags: event.modifierFlags))
            self.cancel()
            return nil
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onCapture = nil
        isCapturing = false
        KeyboardRemappingService.shared.setCaptureInProgress(false)
    }

    func buttonTitle(for keyCode: Int64,
                     modifiers: GlobalShortcutModifiers,
                     placeholder: String,
                     strings: KeyboardRemappingStrings) -> String {
        if isCapturing { return strings[.captureButton] }
        guard (0..<128).contains(keyCode) else { return placeholder }
        return GlobalShortcut(keyCode: keyCode, modifiers: modifiers).displayString
    }
}
