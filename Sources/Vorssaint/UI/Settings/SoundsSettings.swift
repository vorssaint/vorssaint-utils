// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every sound the app can make for a moment, grouped by the feature whose
/// moments they mark, each with its own switch, sound, loudness and repeats.
struct SoundsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    /// Redraws when a feature with sounds is installed or removed.
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.soundsEnabled) private var enabled = true
    @AppStorage(DefaultsKey.soundsQuietWhileSharing) private var quietWhileSharing = true
    @AppStorage(DefaultsKey.soundsOnlyWhenAway) private var onlyWhenAway = false
    @AppStorage(DefaultsKey.soundsOutput) private var output = AppSoundOutput.current.rawValue
    /// Read so the agents' note follows the AI page while this page is open.
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var agentsEnabled = false
    @AppStorage(DefaultsKey.notchEnabled) private var islandEnabled = false
    /// Bumped when a sound is added, so every menu lists it.
    @State private var libraryVersion = 0

    private var text: SoundStrings { FeatureStrings.sounds(l10n.language) }

    private func sounds(in group: AppSoundGroup) -> [AppSound] {
        group.sounds.filter { features.isAvailable($0.feature) }
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.playSounds, isOn: $enabled)
                Text(text.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    SettingsRow(symbol: "rectangle.inset.filled.and.person.filled", title: text.quietWhileSharing,
                                caption: text.quietWhileSharingCaption) {
                        Toggle(text.quietWhileSharing, isOn: $quietWhileSharing).labelsHidden().toggleStyle(.switch)
                    }
                    if AppSound.allCases.contains(where: { $0.isAgentMoment && features.isAvailable($0.feature) }) {
                        SettingsRow(symbol: "eye.slash", title: text.onlyWhenAway, caption: text.onlyWhenAwayCaption) {
                            Toggle(text.onlyWhenAway, isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                        }
                    }
                    SettingsMenuRow(symbol: "hifispeaker", title: text.playOn, selection: $output) {
                        Text(text.outputCurrent).tag(AppSoundOutput.current.rawValue)
                        Text(text.outputAlerts).tag(AppSoundOutput.alerts.rawValue)
                    }
                }
                .disabled(!enabled)
            }

            ForEach(AppSoundGroup.allCases.filter { !sounds(in: $0).isEmpty }) { group in
                let strings = group.strings(l10n.language)
                Section {
                    if group.noteApplies, let note = strings.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sounds(in: group)) { sound in
                        AppSoundRow(sound: sound, moment: strings.moments[sound], text: text,
                                    language: l10n.language, libraryVersion: libraryVersion, add: addSound)
                    }
                } header: {
                    Text(strings.title)
                }
                .disabled(!enabled)
            }
        }
        .formStyle(.grouped)
    }

    /// Copies a chosen file into ~/Library/Sounds, where macOS and every
    /// moment's menu find it, and returns its choice.
    private func addSound() -> AppSoundChoice? {
        let library = AppSoundService.shared.library
        guard let folder = library.addedFolder else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let target = folder.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: url, to: target)
            }
        } catch {
            NSSound.beep()
            return nil
        }
        library.reload()
        libraryVersion += 1
        let choice = AppSoundChoice(source: .user, name: target.lastPathComponent)
        return library.url(for: choice) == nil ? nil : choice
    }
}

/// One moment: its switch, then the sound, how loud and how many times.
private struct AppSoundRow: View {
    let sound: AppSound
    let moment: SoundMoment?
    let text: SoundStrings
    let language: AppLanguage
    let libraryVersion: Int
    let add: () -> AppSoundChoice?
    @AppStorage private var on: Bool
    @AppStorage private var name: String
    @AppStorage private var volume: Double
    @AppStorage private var repeats: Int

    /// Stands for the menu's last row, which adds a sound rather than
    /// choosing one.
    private static let addTag = "add:"

    init(sound: AppSound, moment: SoundMoment?, text: SoundStrings, language: AppLanguage,
         libraryVersion: Int, add: @escaping () -> AppSoundChoice?) {
        self.sound = sound
        self.moment = moment
        self.text = text
        self.language = language
        self.libraryVersion = libraryVersion
        self.add = add
        _on = AppStorage(wrappedValue: sound.defaultEnabled, sound.enabledKey)
        _name = AppStorage(wrappedValue: sound.defaultChoice, sound.nameKey)
        _volume = AppStorage(wrappedValue: sound.defaultVolume, sound.volumeKey)
        _repeats = AppStorage(wrappedValue: sound.defaultRepeats, sound.repeatsKey)
    }

    private var library: AppSoundLibrary { AppSoundService.shared.library }

    /// The menu's selection: the stored choice as an id, or the add row.
    private var selection: Binding<String> {
        Binding {
            AppSoundChoice(id: name)?.id ?? name
        } set: { value in
            if value == Self.addTag {
                if let added = add() { name = added.id; AppSoundService.shared.preview(sound) }
            } else {
                name = value
                AppSoundService.shared.preview(sound)
            }
        }
    }

    var body: some View {
        SettingsRow(symbol: sound.symbol, title: moment?.title ?? sound.rawValue, caption: moment?.caption) {
            Toggle(moment?.title ?? sound.rawValue, isOn: $on).labelsHidden().toggleStyle(.switch)
                .onChange(of: on) { _, _ in
                    // The snippet sound's switch is read on the keystroke
                    // path from a copy the service keeps.
                    if sound == .snippetExpanded { TextSnippetService.shared.syncExpansionSound() }
                }
        }
        if on {
            SettingsMenuRow(symbol: nil, title: text.sound, selection: selection) {
                soundOptions
            }
            .padding(.leading, settingsRowTextInset)
            .id(libraryVersion)
            HStack(spacing: 10) {
                Text(text.volume)
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $volume, in: AppSoundSupport.minimumVolume...AppSoundSupport.maximumVolume) { editing in
                    if !editing { AppSoundService.shared.preview(sound) }
                }
                .labelsHidden()
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                Text(AgentFormat.percent(volume, locale: language.formattingLocale()))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
                Button(text.play) { AppSoundService.shared.preview(sound) }
            }
            .padding(.leading, settingsRowTextInset)
            SettingsMenuRow(symbol: nil, title: text.repeats, selection: $repeats) {
                ForEach(AppSoundSupport.repeatChoices, id: \.self) { count in
                    Text(text.repeatCount(count)).tag(count)
                }
            }
            .padding(.leading, settingsRowTextInset)
            .onChange(of: repeats) { _, _ in AppSoundService.shared.preview(sound) }
        }
    }

    @ViewBuilder
    private var soundOptions: some View {
        // The sound this moment made before the Sounds page, kept where the
        // library does not list it.
        if let own = AppSoundChoice(id: sound.defaultChoice), own.source == .builtIn, library.url(for: own) != nil {
            Text(AppSoundLibrary.displayName(own, language: language)).tag(own.id)
            Divider()
        }
        ForEach([(AppSoundChoice.Source.tone, text.sourceTones),
                 (.system, text.sourceSystem), (.user, text.sourceYours)], id: \.0) { source, title in
            let choices = library.choices(from: source)
            if !choices.isEmpty {
                Section(title) {
                    ForEach(choices) { choice in
                        Text(AppSoundLibrary.displayName(choice, language: language)).tag(choice.id)
                    }
                }
            }
        }
        // A sound saved on another Mac keeps a row, or the menu would show
        // nothing chosen.
        if let stored = AppSoundChoice(id: name), library.url(for: stored) == nil {
            Text(text.unavailable).tag(stored.id)
        }
        Divider()
        Text(text.addSound).tag(Self.addTag)
    }
}
