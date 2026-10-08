// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct InputSoundsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = InputSoundsService.shared
    @AppStorage(DefaultsKey.inputSoundsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.inputSoundsClicks) private var clicks = true
    @AppStorage(DefaultsKey.inputSoundsClickPack) private var clickPack = InputSoundLibrary.defaultPackID
    @AppStorage(DefaultsKey.inputSoundsVolume) private var volume = Defaults.defaultInputSoundsVolume
    @AppStorage(DefaultsKey.inputSoundsKeyboard) private var keyboard = false
    @AppStorage(DefaultsKey.inputSoundsKeyboardPack) private var keyboardPack = "desk.thock"
    @AppStorage(DefaultsKey.inputSoundsKeyboardVolume) private var keyboardVolume = Defaults.defaultInputSoundsVolume
    @AppStorage(DefaultsKey.inputSoundsModifierKeys) private var modifierKeys = true
    @AppStorage(DefaultsKey.inputSoundsTypingCombo) private var typingCombo = false
    @AppStorage(DefaultsKey.inputSoundsScroll) private var scroll = false
    @AppStorage(DefaultsKey.inputSoundsScrollStyle) private var scrollStyle = InputScrollStyle.tick.rawValue
    @AppStorage(DefaultsKey.inputSoundsDoubleClick) private var doubleClick = false
    @AppStorage(DefaultsKey.inputSoundsLongPress) private var longPress = false
    @AppStorage(DefaultsKey.inputSoundsDrag) private var drag = false
    @AppStorage(DefaultsKey.inputSoundsStereo) private var stereo = false
    @AppStorage(DefaultsKey.inputSoundsQuietDuringMicrophone) private var quietDuringMicrophone = true
    @AppStorage(DefaultsKey.inputSoundsQuietApps) private var quietAppsRaw = ""
    @AppStorage(DefaultsKey.inputSoundsPreset) private var presetRaw = ""
    @State private var customRevision = 0
    @State private var importFailed = false

    private var text: InputFeedbackStrings { FeatureStrings.inputFeedback(l10n.language) }

    /// Every value the service reads; any change re-syncs it once.
    private var signature: String {
        [enabled, clicks, keyboard, modifierKeys, typingCombo, scroll, doubleClick, longPress, drag,
         stereo, quietDuringMicrophone].map { $0 ? "1" : "0" }.joined()
            + clickPack + keyboardPack + scrollStyle + quietAppsRaw
            + "\(volume)\(keyboardVolume)"
    }

    var body: some View {
        Form {
            Section(text.soundsTitle) {
                Toggle(text.soundsEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.soundsPrivacy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    Text(text.notRunningCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PermissionRow(kind: .accessibility)
                }
            }

            Section(text.presetsSection) {
                HStack(spacing: 6) {
                    ForEach(InputFeedbackPreset.allCases) { preset in
                        Button(text.presetName(preset)) { apply(preset) }
                            .buttonStyle(.bordered)
                            .tint(InputSoundPicker.tint(presetRaw == preset.rawValue))
                    }
                }
                Text(text.presetsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(text.clicksSection) {
                Toggle(text.clicksToggle, isOn: $clicks)
                InputSoundPicker(selection: $clickPack, keyboard: false, text: text,
                                 allowsCustom: true)
                    .disabled(!clicks)
                volumeSlider($volume)
                    .disabled(!clicks && !scroll)
            }

            Section(text.keyboardSection) {
                Toggle(text.keyboardToggle, isOn: $keyboard)
                Text(text.keyboardCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                InputSoundPicker(selection: $keyboardPack, keyboard: true, text: text,
                                 allowsCustom: true)
                    .disabled(!keyboard)
                volumeSlider($keyboardVolume)
                    .disabled(!keyboard)
                Toggle(text.modifierKeysToggle, isOn: $modifierKeys)
                    .disabled(!keyboard)
                Button(text.matchKeyboardButton) { matchKeyboard() }
                    .disabled(InputSoundLibrary.pack(id: keyboardPack) == nil)
                Toggle(text.typingComboToggle, isOn: $typingCombo)
                Text(text.typingComboCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(text.scrollSection) {
                Toggle(text.scrollToggle, isOn: $scroll)
                Picker(text.scrollStyleLabel, selection: $scrollStyle) {
                    ForEach(InputScrollStyle.allCases) { style in
                        Text(style.name).tag(style.rawValue)
                    }
                }
                .disabled(!scroll)
                .onChange(of: scrollStyle) { _, raw in
                    if let style = InputScrollStyle(rawValue: raw) {
                        InputSoundsService.shared.previewScroll(style)
                    }
                }
            }

            Section(text.extrasSection) {
                Toggle(text.doubleClickToggle, isOn: $doubleClick)
                Toggle(text.longPressToggle, isOn: $longPress)
                Toggle(text.dragToggle, isOn: $drag)
                Toggle(text.stereoToggle, isOn: $stereo)
            }
            .disabled(!clicks)

            Section(text.quietSection) {
                Toggle(text.quietMicrophoneToggle, isOn: $quietDuringMicrophone)
                Text(text.quietMicrophoneCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AppBundleList(title: text.quietAppsLabel,
                              caption: text.quietAppsCaption,
                              addTitle: text.addAppButton,
                              removeLabel: text.removeButton,
                              bundleIDs: InputSoundsSupport.decodeBundleIDs(quietAppsRaw),
                              reachesEveryApp: true,
                              onAdd: { id in
                                  quietAppsRaw = InputSoundsSupport.encodeBundleIDs(
                                      InputSoundsSupport.decodeBundleIDs(quietAppsRaw) + [id])
                              },
                              onRemove: { id in
                                  quietAppsRaw = InputSoundsSupport.encodeBundleIDs(
                                      InputSoundsSupport.decodeBundleIDs(quietAppsRaw).filter { $0 != id })
                              })
            }

            Section(text.customSection) {
                Text(text.customCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(InputSoundCustomSlot.allCases) { slot in
                    customRow(slot)
                }
                .id(customRevision)
                if importFailed {
                    Label(text.importFailed, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: signature) { _, _ in
            InputSoundsService.shared.syncWithPreferences()
        }
    }

    private func volumeSlider(_ value: Binding<Double>) -> some View {
        HStack {
            Text(text.volumeLabel)
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: value, in: 0...1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
    }

    private func customRow(_ slot: InputSoundCustomSlot) -> some View {
        let url = InputSoundCustomStore.url(for: slot)
        return HStack {
            Text(text.customSlotName(slot))
            Spacer()
            if let url {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(text.removeButton) {
                    InputSoundsService.shared.removeCustomSound(slot)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { customRevision += 1 }
                }
            }
            Button(text.chooseFileButton) { chooseFile(for: slot) }
        }
    }

    private func chooseFile(for slot: InputSoundCustomSlot) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        InputSoundsService.shared.importCustomSound(from: url, slot: slot) { success in
            importFailed = !success
            customRevision += 1
            if success, slot == .press { InputSoundsService.shared.preview(packID: InputSoundsSupport.customPackID,
                                                                           keyboard: false) }
        }
    }

    private func apply(_ preset: InputFeedbackPreset) {
        preset.apply(highlightAvailable: AppFeature.clickHighlight.isAvailable)
        presetRaw = preset.rawValue
        enabled = true
        InputSoundsService.shared.syncWithPreferences()
        if AppFeature.clickHighlight.isAvailable {
            ClickHighlightService.shared.syncWithPreferences()
        }
        if let pack = preset.values[DefaultsKey.inputSoundsClickPack] as? String {
            InputSoundsService.shared.preview(packID: pack, keyboard: false)
        }
    }

    /// One tap matches clicks and scrolling to the keyboard's family.
    private func matchKeyboard() {
        guard let pack = InputSoundLibrary.pack(id: keyboardPack) else { return }
        clickPack = pack.id
        scrollStyle = pack.family.matchingScrollStyle.rawValue
        InputSoundsService.shared.preview(packID: pack.id, keyboard: false)
    }
}

/// Families as a row of chips and the chosen family's sounds below them.
/// Choosing a family switches to its first sound and plays it; choosing a
/// sound plays it too.
struct InputSoundPicker: View {
    @Binding var selection: String
    let keyboard: Bool
    let text: InputFeedbackStrings
    let allowsCustom: Bool

    private var selectedFamily: InputSoundFamily? {
        InputSoundLibrary.pack(id: selection)?.family
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(InputSoundFamily.allCases) { family in
                        chip(text.familyName(family), selected: selectedFamily == family) {
                            if let first = InputSoundLibrary.packs(in: family).first { choose(first.id) }
                        }
                    }
                    if allowsCustom {
                        chip(text.familyCustom, selected: selection == InputSoundsSupport.customPackID) {
                            choose(InputSoundsSupport.customPackID)
                        }
                    }
                }
            }
            if let family = selectedFamily {
                HStack(spacing: 6) {
                    ForEach(InputSoundLibrary.packs(in: family)) { pack in
                        Button {
                            choose(pack.id)
                        } label: {
                            Label(pack.name, systemImage: selection == pack.id ? "speaker.wave.2.fill" : "speaker")
                        }
                        .buttonStyle(.bordered)
                        .tint(Self.tint(selection == pack.id))
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Self.tint(selected))
    }

    static func tint(_ selected: Bool) -> Color? {
        selected ? Color.accentColor : nil
    }

    private func choose(_ id: String) {
        selection = id
        InputSoundsService.shared.preview(packID: id, keyboard: keyboard)
    }
}
