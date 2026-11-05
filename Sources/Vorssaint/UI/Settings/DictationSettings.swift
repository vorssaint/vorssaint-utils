// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct DictationSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var speech = DictationService.shared
    @ObservedObject private var models = DictationModelStore.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.dictationEnabled) private var enabled = false
    @AppStorage(DefaultsKey.dictationActivation) private var activation = "hybrid"
    @AppStorage(DefaultsKey.dictationShortcut) private var shortcut = "fn"
    @AppStorage(DefaultsKey.dictationLanguage) private var language = ""
    @AppStorage(DefaultsKey.dictationTranslate) private var translate = false
    @AppStorage(DefaultsKey.dictationMicrophone) private var microphone = ""
    @AppStorage(DefaultsKey.dictationDelivery) private var delivery = "paste"
    @AppStorage(DefaultsKey.dictationRetainAudio) private var retention = 0
    @AppStorage(DefaultsKey.dictationHistoryLimit) private var historyLimit = 200
    @AppStorage(DefaultsKey.dictationVocabulary) private var vocabulary = ""
    @AppStorage(DefaultsKey.dictationReplacements) private var replacements = ""
    @AppStorage(DefaultsKey.dictationRemoveFillers) private var fillers = false
    @AppStorage(DefaultsKey.dictationTrailingSpace) private var trailingSpace = false
    @AppStorage(DefaultsKey.dictationSound) private var sound = false
    @AppStorage(DefaultsKey.dictationSilenceStop) private var silence = 0.0
    @AppStorage(DefaultsKey.dictationUnload) private var unload = 300.0
    @AppStorage(DefaultsKey.dictationCPUOnly) private var cpu = false
    @AppStorage(DefaultsKey.dictationCleanupEnabled) private var cleanup = false
    @AppStorage(DefaultsKey.dictationCleanupURL) private var cleanupURL = "http://localhost:1234/v1/chat/completions"
    @AppStorage(DefaultsKey.dictationCleanupModel) private var cleanupModel = ""
    @AppStorage(DefaultsKey.dictationCleanupPrompt) private var cleanupPrompt = DictationSupport.defaultCleanupPrompt
    @State private var modelQuery = ""
    @State private var microphones: [DictationRecorder.Microphone] = []
    @State private var tab = "general"
    @State private var apiKey = ""
    @State private var credentialMessage = ""
    @State private var shortcutMessage = ""
    private var text: DictationStrings { .localized(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "mic").font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary).frame(width: 32, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.title).font(.title2.bold())
                    Text("On-device speech recognition").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(text.title, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                    .onChange(of: enabled) { _, _ in speech.syncWithPreferences() }
            }.padding(24)
            Picker(text.title, selection: $tab) {
                Text("General").tag("general")
                Text("Models").tag("models")
                Text(text.history).tag("history")
                Text("Advanced").tag("advanced")
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 18)
            if tab == "history" {
                DictationHistoryView().padding(.horizontal, 24).padding(.bottom, 24)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if tab == "general" { general }
                        else if tab == "models" { modelSettings }
                        else { advanced }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: 808)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { microphones = DictationRecorder.microphones(); models.refresh() }
        .onChange(of: permissions.accessibility) { _, _ in speech.syncWithPreferences() }
        .accessibilityIdentifier("settings.dictation")
    }

    private var general: some View {
        Group {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(models.selected?.name ?? (models.selectedID == "custom" ? "Imported model" : "Choose a speech model")).font(.headline)
                        Text(models.selectedURL == nil ? "Download once, then transcribe offline." : "Ready for local speech recognition.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(speech.phase == .recording ? text.stop : text.start, action: speech.toggle)
                        .disabled(!enabled || models.selectedURL == nil || (speech.phase.isBusy && speech.phase != .recording))
                }
                if let error = speech.error { Text(error).font(.caption).foregroundStyle(.orange) }
                if !NotchSupport.isEnabled() {
                    Button("Enable Dynamic Island for the live microphone and waveform") {
                        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
                    }
                }
                Button("Transcribe an audio file…", action: speech.importAudio).disabled(!enabled || speech.phase.isBusy || models.selectedURL == nil)
                Divider()
                HStack {
                    Button("Open speech history in Dynamic Island") { NotchService.shared.open(.dictation) }
                        .disabled(!NotchSupport.isEnabled())
                    Spacer()
                    Button("Add island quick button") { addHistoryShortcut() }
                        .disabled(!NotchSupport.isEnabled())
                        .accessibilityIdentifier("dictation.addIslandShortcut")
                }
                if !shortcutMessage.isEmpty { Text(shortcutMessage).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "Shortcut") {
                HStack {
                    Text("Activation key")
                    Spacer()
                    if shortcut != "fn" { Button("Use fn / Globe") { shortcut = "fn"; speech.syncWithPreferences() } }
                    ShortcutRecorderButton(shortcut: GlobalShortcut(storageValue: shortcut) ?? GlobalShortcut(keyCode: 2, modifiers: [.control, .option]),
                        isEnabled: !speech.phase.isBusy, waitingTitle: "Press keys", emptyTitle: shortcut == "fn" ? "fn / Globe" : nil,
                        invalidAction: { }, captureAction: { value in shortcut = value.storageValue; speech.syncWithPreferences() })
                        .frame(width: 130)
                }
                Picker("Recording mode", selection: $activation) {
                    Text("Hold to speak").tag("hold")
                    Text("Press to toggle").tag("toggle")
                    Text("Hold or tap").tag("hybrid")
                }.pickerStyle(.segmented)
                Text("Hold fn to speak and release to finish. A quick tap keeps recording until the next tap. Escape cancels. Set macOS Keyboard → Press fn key to → Do Nothing to prevent its system action.")
                    .font(.caption).foregroundStyle(.secondary)
                if !permissions.accessibility { PermissionRow(kind: .accessibility) }
                else if enabled && !speech.shortcutAvailable {
                    Text("The shortcut is unavailable. Check its permissions or choose another combination.").font(.caption).foregroundStyle(.orange)
                    Button("Retry shortcut") { speech.syncWithPreferences() }
                }
            }
            SettingsCard(title: "Input and output") {
                Picker("Microphone", selection: $microphone) {
                    Text("System default").tag("")
                    ForEach(microphones) { Text($0.name).tag($0.id) }
                    if !microphone.isEmpty, !microphones.contains(where: { $0.id == microphone }) { Text("Unavailable microphone").tag(microphone) }
                }
                Button("Refresh microphones") { microphones = DictationRecorder.microphones() }.font(.caption)
                if permissions.microphone != .granted { PermissionRow(kind: .microphone) }
                Picker("Language", selection: $language) {
                    Text("Automatic").tag("")
                    ForEach(availableLanguages, id: \.self) { code in Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code) }
                }
                Toggle("Translate speech to English", isOn: $translate).disabled(models.selected?.capabilities.translate != true && models.selectedID != "custom")
                Picker("After transcription", selection: $delivery) {
                    Text("Copy text").tag("copy")
                    Text("Paste and keep text on clipboard").tag("paste")
                    Text("Paste and restore previous clipboard").tag("pasteAndRestore")
                }
                Text("Pasting requires Accessibility and the original app to remain active. If focus changes, the transcript is copied instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(speech.phase.isBusy)
            SettingsCard(title: "Privacy and history") {
                Picker("Keep transcripts", selection: $historyLimit) {
                    Text("Off").tag(0)
                    ForEach([50, 200, 1000, 5000], id: \.self) { Text("\($0)").tag($0) }
                }.onChange(of: historyLimit) { _, _ in DictationHistoryStore.shared.syncWithPreferences() }
                Picker("Keep recordings", selection: $retention) {
                    Text("Never").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }.onChange(of: retention) { _, _ in DictationHistoryStore.shared.syncWithPreferences() }
                Text("Recognition runs locally. Recordings are discarded by default. Saved text and audio stay in private app storage and are excluded from settings backups. Favorites stay until deleted while history is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var availableLanguages: [String] {
        let languages = models.selected?.languages ?? ["en", "hi", "es", "fr", "de", "ja", "zh", "ko", "pt", "it", "ru"]
        return Array(Set(languages + (language.isEmpty ? [] : [language]))).sorted()
    }

    private func addHistoryShortcut() {
        var configuration = NotchQuickAccessConfiguration.stored()
        guard configuration.addSpeechHistory(label: text.history) else {
            shortcutMessage = "All quick-button positions are occupied. Choose a position in Dynamic Island settings."
            return
        }
        let defaults = UserDefaults.standard
        let hidden = (defaults.string(forKey: DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").filter { $0 != "dictation" }
        defaults.set(hidden.joined(separator: ","), forKey: DefaultsKey.notchHiddenModules)
        defaults.set(configuration.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        NotchService.shared.syncWithPreferences()
        shortcutMessage = "Speech history is now available from the island’s quick buttons."
    }

    private var modelSettings: some View {
        Group {
            SettingsCard {
                TextField("Search models, languages, or families", text: $modelQuery).textFieldStyle(.roundedBorder)
                Text("Models use Handy’s transcribe.cpp engine with Metal acceleration. Downloads are checked against the pinned catalog’s SHA-256. Each model has its own license and language support.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Import a GGUF / GGML model…", action: models.importModel).disabled(models.downloading != nil || speech.phase.isBusy)
                    Spacer()
                    if models.installed.contains("custom") {
                        Button(models.selectedID == "custom" ? "Imported model selected" : "Use imported model") { models.select("custom") }.disabled(speech.phase.isBusy)
                        Button(role: .destructive) { models.remove("custom") } label: { Image(systemName: "trash") }.disabled(speech.phase.isBusy)
                    }
                }
                if let error = models.error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let downloading = models.downloading {
                    HStack {
                        ProgressView(value: models.progress)
                        Text(downloading == "custom" ? "Importing…" : "\(Int(models.progress * 100))%")
                            .font(.caption.monospacedDigit())
                        Button(text.cancel, action: models.cancelDownload)
                    }
                }
            }
            ForEach(models.models.filter { modelQuery.isEmpty || "\($0.name) \($0.family) \($0.languages.joined(separator: " "))".localizedCaseInsensitiveContains(modelQuery) }) { model in
                SettingsCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(model.name).font(.headline)
                                if models.selectedID == model.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                            }
                            Text(model.description).font(.caption).foregroundStyle(.secondary)
                            Text("\(model.family) · \(model.quant) · \(ByteCountFormatter.string(fromByteCount: model.downloadFile?.size ?? 0, countStyle: .file)) · \(model.languages.count) languages")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let url = model.licenseURL { Link(model.license, destination: url).font(.caption2) }
                        }
                        Spacer(minLength: 12)
                        if models.installed.contains(model.id) {
                            Button(models.selectedID == model.id ? "Selected" : "Use") { models.select(model.id) }
                                .disabled(speech.phase.isBusy || models.selectedID == model.id)
                            Button(role: .destructive) { models.remove(model.id) } label: { Image(systemName: "trash") }
                                .disabled(speech.phase.isBusy).help("Delete model")
                        } else {
                            Button("Download") { models.install(model) }.disabled(models.downloading != nil)
                        }
                    }
                }
            }
        }
    }

    private var advanced: some View {
        Group {
            SettingsCard(title: "Recording") {
                Toggle("Play start and finish sounds", isOn: $sound)
                Picker("Finish after silence", selection: $silence) {
                    Text("Manually").tag(0.0)
                    ForEach([2.0, 3.0, 5.0, 10.0], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Text("A volume threshold detects pauses. Recordings stop after 10 minutes, when the Mac locks or sleeps, or if the input device changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "Words and corrections") {
                Text("Vocabulary · one term per line").font(.subheadline)
                TextEditor(text: $vocabulary).font(.body).frame(height: 80).border(.quaternary)
                Text("Vocabulary hints apply to models that support them.").font(.caption).foregroundStyle(.secondary)
                Text("Corrections · heard phrase = preferred phrase").font(.subheadline)
                TextEditor(text: $replacements).font(.body).frame(height: 80).border(.quaternary)
                Toggle("Remove English filler sounds (um, uh, erm)", isOn: $fillers)
                Toggle("Append a space when copying or pasting", isOn: $trailingSpace)
            }
            SettingsCard(title: "Text cleanup · optional") {
                Toggle("Clean up with a language model", isOn: $cleanup)
                Text("When enabled, the transcript is sent to the endpoint below. Use a local server for local-only cleanup. No audio is sent. Cleanup failures keep the original text in history.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Chat completions URL", text: $cleanupURL).textFieldStyle(.roundedBorder)
                TextField("Model identifier", text: $cleanupModel).textFieldStyle(.roundedBorder)
                HStack {
                    SecureField("New API key (stored in Keychain)", text: $apiKey)
                    Button("Save key") {
                        do { try DictationCleanup.setKey(apiKey); apiKey = ""; credentialMessage = "Credential updated." }
                        catch { credentialMessage = error.localizedDescription }
                    }
                    Button("Remove key") {
                        do { try DictationCleanup.setKey(""); credentialMessage = "Credential removed." }
                        catch { credentialMessage = error.localizedDescription }
                    }
                }
                if !credentialMessage.isEmpty { Text(credentialMessage).font(.caption).foregroundStyle(.secondary) }
                Text("Cleanup instructions").font(.subheadline)
                TextEditor(text: $cleanupPrompt).font(.body).frame(height: 90).border(.quaternary)
            }
            SettingsCard(title: "Engine") {
                Toggle("CPU only", isOn: $cpu).onChange(of: cpu) { _, _ in speech.unloadEngine() }
                Picker("Unload model after", selection: $unload) {
                    Text("Each transcription").tag(0.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("Keep loaded").tag(-1.0)
                }
                Button("Unload now", action: speech.unloadEngine)
                Text("Keeping a model warm avoids loading it for each dictation. CPU mode can help with a GPU failure.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Handy and transcribe.cpp acknowledgments", destination: URL(string: "https://github.com/cjpais/Handy")!)
            }.disabled(speech.phase.isBusy)
        }
    }
}
