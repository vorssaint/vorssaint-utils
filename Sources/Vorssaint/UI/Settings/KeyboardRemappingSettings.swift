// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct KeyboardRemappingSettings: View {
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

    private var hasEnabledRiskyRules: Bool {
        rules.contains { $0.enabled && $0.isValid && $0.sourceRisk != nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable system-wide key remapping", isOn: systemEnabledBinding)
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
                        Label("Starting key remapping…", systemImage: "keyboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .active:
                        Label("Key remapping is active", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed:
                        Label("macOS did not allow the keyboard remapping tap to start. Check Vorssaint’s Accessibility permission, then turn remapping off and on to retry.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                if rules.isEmpty {
                    ContentUnavailableView("No Remapping Rules",
                                           systemImage: "keyboard",
                                           description: Text("Add a rule to change or disable a key for all apps or one selected app."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .multilineTextAlignment(.center)
                }
                ForEach($rules) { $rule in
                    ruleEditor(rule: $rule)
                }
                Button {
                    rules.append(KeyboardRemappingRule())
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
                .disabled(!enabled || rules.count >= KeyboardRemappingConfig.maximumRules)
            } header: {
                Text("Rules")
            } footer: {
                Text("Choose what happens when the source key is pressed. An optional bundle identifier limits a rule to that app.")
            }
            .disabled(!enabled)

            if enabled, rules.contains(where: { $0.enabled && $0.isValid }), !permissions.accessibility {
                Section("Permission required") {
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
            "Enable a commonly used key mapping?",
            isPresented: Binding(
                get: { pendingEnable != nil },
                set: { if !$0 { pendingEnable = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Enable mapping anyway", role: .destructive) {
                confirmPendingEnable()
            }
            Button("Cancel", role: .cancel) {
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
            return "One or more enabled rules remap a modifier, letter, or number key. These keys are important for typing and common macOS shortcuts."
        case .rule(let id):
            return rules.first(where: { $0.id == id })?.sourceRisk?.warning
                ?? "This key is commonly used for typing or macOS shortcuts."
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
                         ? "New key rule"
                         : capture.buttonTitle(for: rule.wrappedValue.sourceKeyCode,
                                               modifiers: rule.wrappedValue.sourceModifiers,
                                               placeholder: "Source key"))
                        .font(.headline)
                    Text(rule.wrappedValue.bundleIdentifier.isEmpty ? "All apps" : InstalledApps.name(for: rule.wrappedValue.bundleIdentifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Enable remapping rule",
                       isOn: ruleEnabledBinding(for: rule.wrappedValue.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Enable remapping rule")
                Button(role: .destructive) {
                    rules.removeAll { $0.id == rule.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove rule")
                .accessibilityLabel("Remove rule")
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WHEN PRESSED")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(capture.buttonTitle(for: rule.wrappedValue.sourceKeyCode,
                                               modifiers: rule.wrappedValue.sourceModifiers,
                                               placeholder: "Record source key")) {
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
                        Label(risk.warning, systemImage: "exclamationmark.triangle.fill")
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
                        Text("SEND")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    Picker("Action", selection: Binding(
                        get: { rule.wrappedValue.resolvedActionKind },
                        set: { rule.wrappedValue.actionKind = $0 }
                    )) {
                        Text("Send keys").tag(KeyboardRemappingActionKind.keySequence)
                        Text("Type text").tag(KeyboardRemappingActionKind.typeText)
                        Text("Open link").tag(KeyboardRemappingActionKind.openLink)
                        Text("Open app").tag(KeyboardRemappingActionKind.openApp)
                        Text("Disable shortcut").tag(KeyboardRemappingActionKind.disabled)
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
                    Text("All apps")
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
                Button("Choose app…") {
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
                    .help("Apply to all apps")
                    .accessibilityLabel("Apply to all apps")
                }
            }

            if capture.isCapturing {
                HStack(spacing: 8) {
                    Label("Press a key combination…", systemImage: "keyboard")
                    Spacer()
                    Button("Cancel") { capture.cancel() }
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
                Text("Enter a valid bundle identifier, such as com.apple.Safari.")
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
                    Label("Add key", systemImage: "plus")
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
                                                           placeholder: "Record key")) {
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
                                    .help("Remove output key")
                                    .accessibilityLabel("Remove output key \(index + 1)")
                                }
                            }
                        }
                        Button {
                            rule.wrappedValue.output.append(KeyboardRemappingChord())
                        } label: {
                            Label("Add key", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(rule.wrappedValue.output.count >= KeyboardRemappingConfig.maximumOutputChords)
                    }
                }
                .scrollIndicators(.visible)
            }
        case .typeText:
            TextField("Text to type", text: rule.text, axis: .vertical)
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
                    Text("Choose an app")
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: InstalledApps.icon(for: rule.wrappedValue.appBundleIdentifier))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(InstalledApps.name(for: rule.wrappedValue.appBundleIdentifier))
                        .lineLimit(1)
                }
                Button("Choose…") {
                    appPickerRuleID = rule.wrappedValue.id
                    choosingActionApp = true
                    showingAppPicker = true
                }
                .controlSize(.small)
            }
        case .disabled:
            Label("This shortcut does nothing", systemImage: "slash.circle")
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
                     placeholder: String) -> String {
        if isCapturing { return "Press a key…" }
        guard (0..<128).contains(keyCode) else { return placeholder }
        return GlobalShortcut(keyCode: keyCode, modifiers: modifiers).displayString
    }
}
