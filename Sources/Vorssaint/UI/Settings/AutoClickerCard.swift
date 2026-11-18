// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AutoClickerCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var autoClicker = AutoClickerService.shared

    @AppStorage(DefaultsKey.autoClickerEnabled) private var autoClickerEnabled = false
    @AppStorage(DefaultsKey.autoClickerMode) private var autoClickerMode = "single"
    @AppStorage(DefaultsKey.autoClickerButton) private var autoClickerButton = "left"
    @AppStorage(DefaultsKey.autoClickerIntervalMs) private var autoClickerIntervalMs = 100
    @AppStorage(DefaultsKey.autoClickerRepeatLimit) private var autoClickerRepeatLimit = 0
    @AppStorage(DefaultsKey.autoClickerTargetMode) private var autoClickerTargetMode = "cursor"
    @AppStorage(DefaultsKey.autoClickerTargetX) private var autoClickerTargetX = 0.0
    @AppStorage(DefaultsKey.autoClickerTargetY) private var autoClickerTargetY = 0.0

    private var text: AutoClickerFeatureStrings { FeatureStrings.autoClicker(l10n.language) }

    private var isMacroMode: Bool {
        autoClickerMode == AutoClickerMode.macro.rawValue
    }

    private var canStart: Bool {
        if autoClicker.isRunning { return true }
        if isMacroMode {
            return !(autoClicker.selectedMacro?.steps.isEmpty ?? true)
        }
        return true
    }

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

                // MARK: - Mode

                HStack(spacing: 12) {
                    Text(text.modeSection)
                        .font(.body)
                    Spacer()
                    Picker("", selection: $autoClickerMode) {
                        Text(text.modeSingle).tag(AutoClickerMode.single.rawValue)
                        Text(text.modeMacro).tag(AutoClickerMode.macro.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(autoClicker.isRunning)
                }
                .padding(.vertical, 6)

                // MARK: - Shortcut

                ShortcutPreferenceRow(
                    role: .autoClicker,
                    isEnabled: autoClickerEnabled,
                    label: text.shortcutSection
                ) {
                    AutoClickerService.shared.syncWithPreferences()
                }
                .padding(.vertical, 2)

                if isMacroMode {
                    macroConfigurationSection
                } else {
                    singleClickConfigurationSection
                }

                Divider()
                    .padding(.vertical, 4)

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
                    .disabled(!canStart)
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

    // MARK: - Single Click Mode

    @ViewBuilder
    private var singleClickConfigurationSection: some View {
        // Button Selection
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

        // Click Location
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(text.targetSection)
                    .font(.body)
                Spacer()
                Picker("", selection: $autoClickerTargetMode) {
                    Text(text.targetCursor).tag(AutoClickerTargetMode.cursor.rawValue)
                    Text(text.targetFixedPoint).tag(AutoClickerTargetMode.fixedPoint.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

            if autoClickerTargetMode == AutoClickerTargetMode.fixedPoint.rawValue {
                HStack(spacing: 10) {
                    Text(String(format: text.coordinatesFormat, Int(autoClickerTargetX.rounded()), Int(autoClickerTargetY.rounded())))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button(action: pickSingleLocation) {
                        Label(text.pickLocationAction, systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(autoClicker.isRunning)
                }
            }
        }
        .padding(.vertical, 6)

        // Interval
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

        // Repeat Limit
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
    }

    // MARK: - Macro Mode

    @ViewBuilder
    private var macroConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(text.macroSection)
                    .font(.body)

                Spacer()

                if !autoClicker.macros.isEmpty {
                    Picker("", selection: Binding(
                        get: { autoClicker.selectedMacro?.id ?? autoClicker.macros.first?.id ?? UUID() },
                        set: { autoClicker.selectMacro(id: $0) }
                    )) {
                        ForEach(autoClicker.macros) { macro in
                            Text(macro.name).tag(macro.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .disabled(autoClicker.isRunning)
                }

                Button(action: {
                    autoClicker.createMacro(name: "Macro \(autoClicker.macros.count + 1)")
                }) {
                    Label(text.macroNewAction, systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(autoClicker.isRunning)

                if let selected = autoClicker.selectedMacro {
                    Button(role: .destructive, action: {
                        autoClicker.deleteMacro(id: selected.id)
                    }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(text.macroDeleteAction)
                    .disabled(autoClicker.isRunning)
                }
            }
            .padding(.top, 6)

            if let macro = autoClicker.selectedMacro {
                // Macro name + Repeat cycles
                HStack(spacing: 12) {
                    TextField(text.macroNamePlaceholder, text: Binding(
                        get: { macro.name },
                        set: { newName in
                            var updated = macro
                            updated.name = newName
                            autoClicker.updateMacro(updated)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(autoClicker.isRunning)

                    Spacer()

                    Text(text.macroRepeatSection)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { macro.repeatCount == 0 ? 0 : 1 },
                        set: { mode in
                            var updated = macro
                            updated.repeatCount = mode == 0 ? 0 : max(1, macro.repeatCount == 0 ? 1 : macro.repeatCount)
                            autoClicker.updateMacro(updated)
                        }
                    )) {
                        Text(text.repeatLimitInfinite).tag(0)
                        Text("N×").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                    .disabled(autoClicker.isRunning)

                    if macro.repeatCount > 0 {
                        TextField("", value: Binding(
                            get: { macro.repeatCount },
                            set: { newRepeat in
                                var updated = macro
                                updated.repeatCount = max(1, newRepeat)
                                autoClicker.updateMacro(updated)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospacedDigit())
                        .frame(width: 56)
                        .disabled(autoClicker.isRunning)
                    }
                }

                // Record & Clear actions
                HStack(spacing: 8) {
                    Button(action: { recordSteps(for: macro) }) {
                        Label(text.macroRecordStepsAction, systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(autoClicker.isRunning)

                    if !macro.steps.isEmpty {
                        Button(action: {
                            var updated = macro
                            updated.steps.removeAll()
                            autoClicker.updateMacro(updated)
                        }) {
                            Text(text.macroClearStepsAction)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(autoClicker.isRunning)
                    }

                    Spacer()
                }

                // Steps List
                if macro.steps.isEmpty {
                    Text(text.macroEmptyHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                            macroStepRow(index: index, step: step, in: macro)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func macroStepRow(index: Int, step: AutoClickerMacroStep, in macro: AutoClickerMacro) -> some View {
        let isActiveStep = autoClicker.isRunning && autoClicker.currentMacroStepIndex == index

        HStack(spacing: 8) {
            Text("#\(index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .frame(width: 26, alignment: .leading)
                .foregroundStyle(isActiveStep ? Color.accentColor : Color.secondary)

            Text(String(format: text.coordinatesFormat, Int(step.x.rounded()), Int(step.y.rounded())))
                .font(.caption.monospacedDigit())
                .frame(width: 110, alignment: .leading)

            Picker("", selection: Binding(
                get: { step.button },
                set: { newButton in
                    updateStep(step.id, in: macro) { $0.button = newButton }
                }
            )) {
                Text(text.buttonLeft).tag(AutoClickerButton.left)
                Text(text.buttonRight).tag(AutoClickerButton.right)
                Text(text.buttonMiddle).tag(AutoClickerButton.middle)
            }
            .labelsHidden()
            .frame(width: 85)
            .disabled(autoClicker.isRunning)

            Picker("", selection: Binding(
                get: { step.clickCount },
                set: { newCount in
                    updateStep(step.id, in: macro) { $0.clickCount = newCount }
                }
            )) {
                Text(text.macroSingleClick).tag(1)
                Text(text.macroDoubleClick).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 68)
            .disabled(autoClicker.isRunning)

            Spacer()

            Text(text.macroStepDelayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("", value: Binding(
                get: { Double(step.delayAfterMs) / 1000.0 },
                set: { newSeconds in
                    updateStep(step.id, in: macro) {
                        $0.delayAfterMs = AutoClickerCoordinates.clampedDelayMs(Int((newSeconds * 1000.0).rounded()))
                    }
                }
            ), format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospacedDigit())
            .frame(width: 58)
            .disabled(autoClicker.isRunning)

            Button(action: {
                autoClicker.removeStep(stepId: step.id, from: macro.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(autoClicker.isRunning)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActiveStep ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Helpers

    private func updateStep(_ stepId: UUID, in macro: AutoClickerMacro, mutate: (inout AutoClickerMacroStep) -> Void) {
        var updated = macro
        guard let idx = updated.steps.firstIndex(where: { $0.id == stepId }) else { return }
        mutate(&updated.steps[idx])
        autoClicker.updateMacro(updated)
    }

    private func pickSingleLocation() {
        AutoClickerScreenPicker.shared.pickSinglePoint { point in
            guard let point else { return }
            autoClickerTargetX = Double(point.x.rounded())
            autoClickerTargetY = Double(point.y.rounded())
            autoClickerTargetMode = AutoClickerTargetMode.fixedPoint.rawValue
        }
    }

    private func recordSteps(for macro: AutoClickerMacro) {
        AutoClickerScreenPicker.shared.recordMacroSteps(existingCount: macro.steps.count) { newSteps in
            autoClicker.appendSteps(newSteps, to: macro.id)
        }
    }
}
