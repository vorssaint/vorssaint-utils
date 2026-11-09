// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AutoClickerCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var autoClicker = AutoClickerService.shared

    @AppStorage(DefaultsKey.autoClickerEnabled) private var autoClickerEnabled = false
    @AppStorage(DefaultsKey.autoClickerButton) private var autoClickerButton = "left"
    @AppStorage(DefaultsKey.autoClickerIntervalMs) private var autoClickerIntervalMs = 100
    @AppStorage(DefaultsKey.autoClickerRepeatLimit) private var autoClickerRepeatLimit = 0

    private var text: AutoClickerFeatureStrings { FeatureStrings.autoClicker(l10n.language) }

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "cursorarrow.click.2", title: text.title, caption: text.caption) {
                Toggle("", isOn: $autoClickerEnabled)
                    .labelsHidden()
                    .onChange(of: autoClickerEnabled) { _, newValue in
                        AutoClickerService.shared.syncWithPreferences()
                        if newValue {
                            permissions.requestAccessibility()
                        }
                    }
            }

            if autoClickerEnabled {
                Divider()
                    .padding(.vertical, 4)

                // MARK: - Shortcut

                ShortcutPreferenceRow(
                    role: .autoClicker,
                    isEnabled: autoClickerEnabled,
                    label: text.shortcutSection
                ) {
                    AutoClickerService.shared.syncWithPreferences()
                }
                .padding(.vertical, 2)

                // MARK: - Button Selection

                HStack(spacing: 12) {
                    Text(text.buttonSection)
                        .font(.body)
                    Spacer()
                    Picker("", selection: $autoClickerButton) {
                        Text(text.buttonLeft).tag("left")
                        Text(text.buttonRight).tag("right")
                        Text(text.buttonMiddle).tag("middle")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .onChange(of: autoClickerButton) { _, _ in
                        AutoClickerService.shared.syncWithPreferences()
                    }
                }
                .padding(.vertical, 6)

                // MARK: - Interval

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(text.intervalSection)
                            .font(.body)
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { Double(autoClickerIntervalMs) },
                                set: { autoClickerIntervalMs = Int($0) }
                            ),
                            in: 10...1000,
                            step: 10
                        )
                        .frame(width: 160)
                        .onChange(of: autoClickerIntervalMs) { _, _ in
                            AutoClickerService.shared.syncWithPreferences()
                        }

                        Text("\(autoClickerIntervalMs) ms · \(String(format: text.rateCpsFormat, Int(1000.0 / Double(max(10, autoClickerIntervalMs)))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .trailing)
                    }
                }
                .padding(.vertical, 6)

                // MARK: - Repeat Limit

                HStack(spacing: 12) {
                    Text(text.repeatLimitSection)
                        .font(.body)
                    Spacer()
                    Picker("", selection: $autoClickerRepeatLimit) {
                        Text(text.repeatLimitInfinite).tag(0)
                        Text("10").tag(10)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("500").tag(500)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    .onChange(of: autoClickerRepeatLimit) { _, _ in
                        AutoClickerService.shared.syncWithPreferences()
                    }
                }
                .padding(.vertical, 6)

                // MARK: - Status & Action

                HStack(spacing: 12) {
                    Circle()
                        .fill(autoClicker.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                        .animation(.easeInOut(duration: 0.2), value: autoClicker.isRunning)

                    if autoClicker.isRunning {
                        Text("\(text.statusRunning) · \(autoClicker.clickCount)")
                            .font(.body)
                            .monospacedDigit()
                    } else {
                        Text(text.statusIdle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if autoClicker.isRunning {
                            autoClicker.stop()
                        } else {
                            autoClicker.start()
                        }
                    }) {
                        Text(autoClicker.isRunning ? text.stopAction : text.startAction)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(autoClicker.isRunning ? .red : .accentColor)
                    .controlSize(.large)
                }
                .padding(.vertical, 8)

                // MARK: - Emergency Stop Hint

                Text(text.emergencyStopHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }
}
