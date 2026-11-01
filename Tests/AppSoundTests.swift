// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation
import IOKit.ps

enum AppSoundTests {
    static func run(_ suite: TestSuite) {
        strings(suite)
        keys(suite)
        preferences(suite)
        library(suite)
        rendering(suite)
        spacing(suite)
        starts(suite)
        rules(suite)
        ruleDefaults(suite)
        agentMoments(suite)
        legacyKeys(suite)
        snippetSoundMigration(suite)
        existingUserDefaults(suite)
        builtInPadlock(suite)
        power(suite)
        groups(suite)
        islandPages(suite)
        eventsSoon(suite)
    }

    private static func rules(_ suite: TestSuite) {
        let cli = AppSoundContext(provider: .claude, place: .terminal)
        let app = AppSoundContext(provider: .claude, place: .app)
        let unsure = AppSoundContext(provider: .codex, place: nil)
        let claudeApp = "com.anthropic.claudefordesktop"
        suite.expect(AppSoundRules.isLooking(at: cli, frontmost: "com.mitchellh.ghostty")
                        && !AppSoundRules.isLooking(at: cli, frontmost: claudeApp),
                     "a command-line session is in view only while a terminal is in front")
        suite.expect(AppSoundRules.isLooking(at: app, frontmost: claudeApp)
                        && !AppSoundRules.isLooking(at: app, frontmost: "com.apple.Terminal"),
                     "an app session is in view only while its own app is in front")
        suite.expect(AppSoundRules.isLooking(at: unsure, frontmost: "com.openai.codex")
                        && AppSoundRules.isLooking(at: unsure, frontmost: "com.googlecode.iterm2")
                        && !AppSoundRules.isLooking(at: unsure, frontmost: claudeApp),
                     "a session whose place is not known counts as in view in a terminal or its agent's app")
        suite.expect(!AppSoundRules.isLooking(at: .none, frontmost: "com.apple.Terminal")
                        && !AppSoundRules.isLooking(at: cli, frontmost: nil),
                     "a moment with no agent, or no app in front, is never in view")

        let terminal = "com.apple.Terminal"
        suite.expect(!AppSoundRules.allows(.agentFinished, context: cli, quietWhileSharing: true, sharing: true,
                                           onlyWhenAway: false, frontmost: nil),
                     "sharing the screen or a call holds a sound back")
        suite.expect(AppSoundRules.allows(.agentFinished, context: cli, quietWhileSharing: false, sharing: true,
                                          onlyWhenAway: false, frontmost: nil),
                     "with the sharing rule off, a call does not hold a sound back")
        suite.expect(!AppSoundRules.allows(.agentFinished, context: cli, quietWhileSharing: true, sharing: false,
                                           onlyWhenAway: true, frontmost: terminal)
                        && !AppSoundRules.allows(.agentStarted, context: cli, quietWhileSharing: true, sharing: false,
                                                 onlyWhenAway: true, frontmost: terminal),
                     "an agent's moments wait while its session is in front")
        suite.expect(AppSoundRules.allows(.agentFinished, context: cli, quietWhileSharing: true, sharing: false,
                                          onlyWhenAway: false, frontmost: terminal)
                        && AppSoundRules.allows(.agentFinished, context: cli, quietWhileSharing: true, sharing: false,
                                                onlyWhenAway: true, frontmost: "com.apple.Safari"),
                     "an agent's moment plays while you look elsewhere, or with the rule off")

        suite.expect(AppSoundRules.othersRecord([(pid: 10, recording: true)], own: 20)
                        && !AppSoundRules.othersRecord([(pid: 20, recording: true), (pid: 10, recording: false)], own: 20),
                     "only another app recording from a microphone counts as a call")
    }

    private static func ruleDefaults(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.soundsQuietWhileSharing] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.soundsOnlyWhenAway] as? Bool == false
                        && Defaults.registeredDefaults[DefaultsKey.soundsOutput] as? String == AppSoundOutput.current.rawValue,
                     "sounds start quiet while sharing, heard while looking, on the current output")
        let name = "vorss.tests.app-sound-rules.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        let cli = AppSoundContext(provider: .claude, place: .terminal)
        var asked = false
        suite.expect(!AppSoundRules.allows(.agentFinished, context: cli, in: defaults, sharing: { true },
                                           frontmost: { asked = true; return nil }) && !asked,
                     "an unset sharing rule holds sounds back, and an unset looking rule never asks what is in front")
        defaults.set(false, forKey: DefaultsKey.soundsQuietWhileSharing)
        defaults.set(true, forKey: DefaultsKey.soundsOnlyWhenAway)
        suite.expect(!AppSoundRules.allows(.agentFinished, context: cli, in: defaults, sharing: { true },
                                           frontmost: { "com.microsoft.VSCode" }),
                     "the stored looking rule holds an agent's sound while its terminal is in front")
        suite.expect(AppSoundRules.output(in: defaults) == .current, "an unset output is the current one")
        defaults.set("alerts", forKey: DefaultsKey.soundsOutput)
        suite.expect(AppSoundRules.output(in: defaults) == .alerts, "the alert device is kept")
        defaults.set("speakers", forKey: DefaultsKey.soundsOutput)
        suite.expect(AppSoundRules.output(in: defaults) == .current, "an unknown output falls back to the current one")
    }

    /// The agent moments beyond starting and finishing: each in the agents
    /// group, off until asked, with its own sound and words.
    private static func agentMoments(_ suite: TestSuite) {
        let added: [AppSound] = [.agentsAllDone, .agentNeedsInput, .agentInterrupted, .agentLimitWarning,
                                 .agentLimitReset, .agentBudgetReached]
        for sound in added {
            suite.expect(sound.group == .agents && sound.feature == .notchAgents
                            && Defaults.registeredDefaults[sound.enabledKey] as? Bool == false,
                         "\(sound.rawValue) is an agent moment, off until asked")
            for language in AppLanguage.allCases {
                let words = AppSoundGroup.agents.strings(language).moments[sound]
                suite.expect(words.map { !$0.title.contains("—") && !$0.caption.contains("—") } == true,
                             "\(sound.rawValue) has its words in \(language.rawValue), without long dashes")
            }
        }
        suite.expect(AppSound.agentNeedsInput.defaultChoice == "tone:Modern/Input"
                        && AppSound.agentNeedsInput.defaultChoice != AppSound.agentFinished.defaultChoice,
                     "a wait reminds with a tone of its own, apart from a finish")
        suite.expect(AppSound.agentInterrupted.defaultChoice == "Basso", "work that stopped sounds low")
        suite.expect(Set(AppSound.allCases.filter { $0.group == .agents }.map(\.defaultChoice)).count
                        == AppSound.allCases.filter { $0.group == .agents }.count,
                     "every agent moment sounds different by default")
    }

    private static func strings(_ suite: TestSuite) {
        let english = Mirror(reflecting: FeatureStrings.sounds(.enUS)).children.count
        for language in AppLanguage.allCases {
            let text = FeatureStrings.sounds(language)
            let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(values.count == english && values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "every Sounds string is written in \(language.rawValue)")
            suite.expect(text.repeatCount(3).contains("3") && !text.repeatCount(1).contains("%"),
                         "repeat counts read in \(language.rawValue)")
            for group in AppSoundGroup.allCases {
                let strings = group.strings(language)
                suite.expect(!strings.title.isEmpty && group.sounds.allSatisfy {
                    guard let moment = strings.moments[$0] else { return false }
                    return !moment.title.isEmpty && !moment.caption.isEmpty
                }, "every \(group.rawValue) moment has its words in \(language.rawValue)")
            }
        }
    }

    private static func keys(_ suite: TestSuite) {
        suite.expect(AppSound.agentFinished.enabledKey == "soundAgentFinished"
                        && AppSound.agentFinished.nameKey == "soundAgentFinishedName"
                        && AppSound.agentFinished.volumeKey == "soundAgentFinishedVolume",
                     "the first release's keys keep their names")
        let all = AppSound.allCases.flatMap { [$0.enabledKey, $0.nameKey, $0.volumeKey, $0.repeatsKey] }
        suite.expect(Set(all).count == all.count, "no two moments share a key")
        for sound in AppSound.allCases {
            suite.expect(Defaults.registeredDefaults[sound.enabledKey] as? Bool == sound.defaultEnabled
                            && Defaults.registeredDefaults[sound.nameKey] as? String == sound.defaultChoice
                            && Defaults.registeredDefaults[sound.volumeKey] as? Double == sound.defaultVolume
                            && Defaults.registeredDefaults[sound.repeatsKey] as? Int == sound.defaultRepeats,
                         "\(sound.rawValue) is registered as it was, with its own sound, loudness and repeats, so backups carry it")
            suite.expect(AppSoundChoice(id: sound.defaultChoice) != nil, "\(sound.rawValue) has a readable default sound")
        }
        suite.expect(AppSound.agentFinished.defaultVolume > AppSound.agentStarted.defaultVolume,
                     "a finished agent rings louder than a starting one")
    }

    private static func preferences(_ suite: TestSuite) {
        let name = "vorss.tests.app-sound.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        let installed: (AppFeature) -> Bool = { _ in true }

        suite.expect(!AppSoundSupport.isOn(.agentFinished, in: defaults, isAvailable: installed),
                     "a sound stays quiet until it is switched on")
        defaults.set(true, forKey: AppSound.agentFinished.enabledKey)
        suite.expect(AppSoundSupport.isOn(.agentFinished, in: defaults, isAvailable: installed),
                     "a sound switched on plays")
        suite.expect(!AppSoundSupport.isOn(.agentFinished, in: defaults, isAvailable: { _ in false }),
                     "a sound whose feature is uninstalled never plays")
        defaults.set(false, forKey: DefaultsKey.soundsEnabled)
        suite.expect(!AppSoundSupport.isOn(.agentFinished, in: defaults, isAvailable: installed),
                     "the page's switch silences every sound")

        suite.expect(AppSoundSupport.volume(.agentStarted, in: defaults) == AppSound.agentStarted.defaultVolume,
                     "an unset loudness is the moment's own")
        defaults.set(0.0, forKey: AppSound.agentStarted.volumeKey)
        suite.expect(AppSoundSupport.volume(.agentStarted, in: defaults) == AppSoundSupport.minimumVolume,
                     "a sound switched on is never silent")
        defaults.set(4.0, forKey: AppSound.agentStarted.volumeKey)
        suite.expect(AppSoundSupport.volume(.agentStarted, in: defaults) == AppSoundSupport.maximumVolume,
                     "a boost tops out at twice full")
        defaults.set(Double.nan, forKey: AppSound.agentStarted.volumeKey)
        suite.expect(AppSoundSupport.volume(.agentStarted, in: defaults) == AppSound.agentStarted.defaultVolume,
                     "a broken loudness reads as the moment's own")

        suite.expect(AppSoundSupport.repeats(.agentStarted, in: defaults) == 1, "a sound plays once unless asked")
        defaults.set(9, forKey: AppSound.agentStarted.repeatsKey)
        suite.expect(AppSoundSupport.repeats(.agentStarted, in: defaults) == 3, "repeats top out at three")
        defaults.set(-2, forKey: AppSound.agentStarted.repeatsKey)
        suite.expect(AppSoundSupport.repeats(.agentStarted, in: defaults) == 1, "a sound always plays at least once")
    }

    private static func library(_ suite: TestSuite) {
        suite.expect(AppSoundChoice(id: "Hero") == AppSoundChoice(source: .system, name: "Hero"),
                     "a bare name from the first release is a macOS alert sound")
        suite.expect(AppSoundChoice(id: "tone:Modern/Chord")?.name == "Modern/Chord"
                        && AppSoundChoice(id: "user:my ding.wav")?.source == .user,
                     "a stored choice reads back its source and name")
        suite.expect(AppSoundChoice(id: "") == nil && AppSoundChoice(id: "tone:") == nil,
                     "an empty choice is no choice")
        suite.expect(AppSoundLibrary.displayName(AppSoundChoice(source: .tone, name: "EncoreInfinitum/Milestone-EncoreInfinitum"),
                                                 language: .enUS) == "Milestone"
                        && AppSoundLibrary.displayName(AppSoundChoice(source: .user, name: "my ding.wav"),
                                                       language: .enUS) == "my ding",
                     "tones and your own sounds show the names a person knows")

        let root = FileManager.default.temporaryDirectory.appending(path: "vorss-sounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appending(path: "system"), tones = root.appending(path: "tones"),
            yours = root.appending(path: "yours")
        for folder in [system, tones.appending(path: "Modern"), tones.appending(path: "Classic"), yours] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for file in [system.appending(path: "Tink.aiff"), system.appending(path: "notes.txt"),
                     tones.appending(path: "Modern/Chord.m4r"), tones.appending(path: "Classic/Bell.m4r"),
                     tones.appending(path: "Effect.caf"), yours.appending(path: "ding.wav")] {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        let found = AppSoundLibrary(systemFolder: system, toneFolder: tones, userFolders: [yours])
        suite.expect(found.choices.map(\.id) == ["system:Tink", "tone:Modern/Chord", "tone:Classic/Bell", "user:ding.wav"],
                     "the library lists alert sounds, then tones by collection, then your own, and skips other files")
        suite.expect(found.url(for: AppSoundChoice(source: .user, name: "ding.wav"))?.resolvingSymlinksInPath().path
                        == yours.appending(path: "ding.wav").resolvingSymlinksInPath().path,
                     "a choice finds its file")

        let name = "vorss.tests.app-sound-choice.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        suite.expect(AppSoundSupport.choice(.agentFinished, in: defaults, library: found)?.id == "tone:Modern/Chord",
                     "an unset sound is the moment's own")
        defaults.set("Tink", forKey: AppSound.agentFinished.nameKey)
        suite.expect(AppSoundSupport.choice(.agentFinished, in: defaults, library: found)?.id == "system:Tink",
                     "a sound chosen in the first release still plays")
        defaults.set("user:gone.wav", forKey: AppSound.agentFinished.nameKey)
        suite.expect(AppSoundSupport.choice(.agentFinished, in: defaults, library: found)?.id == "tone:Modern/Chord",
                     "a sound this Mac lacks falls back to the moment's own")
        let bare = AppSoundLibrary(systemFolder: system, toneFolder: root.appending(path: "none"), userFolders: [])
        suite.expect(AppSoundSupport.choice(.agentFinished, in: defaults, library: bare)?.id == "system:Tink",
                     "without Apple's tones, a moment still plays an alert sound")
    }

    private static func rendering(_ suite: TestSuite) {
        let url = FileManager.default.temporaryDirectory.appending(path: "vorss-sound-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800) else { return }
        buffer.frameLength = 800
        for frame in 0..<800 {
            buffer.floatChannelData?[0][frame] = 0.8
            buffer.floatChannelData?[1][frame] = -0.4
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        } catch {
            suite.expect(false, "the rendering fixture writes its sound: \(error)")
            return
        }
        let once = AppSoundService.render(url, gain: 0.5, repeats: 1)
        suite.expect(once?.frameLength == 800 && abs((once?.floatChannelData?[0][10] ?? 0) - 0.4) < 0.001,
                     "a quieter sound is scaled down")
        let thrice = AppSoundService.render(url, gain: 1, repeats: 3)
        let gap = Int(8000 * AppSoundService.repeatGap)
        suite.expect(thrice.map { Int($0.frameLength) } == 800 * 3 + gap * 2
                        && thrice?.floatChannelData?[0][800 + gap / 2] == 0
                        && abs((thrice?.floatChannelData?[0][800 + gap + 10] ?? 0) - 0.8) < 0.001,
                     "repeats play back to back with a short pause between")
        let loud = AppSoundService.render(url, gain: 2, repeats: 1)
        let peak = (0..<800).map { abs(loud?.floatChannelData?[0][$0] ?? 0) }.max() ?? 0
        let quiet = abs(loud?.floatChannelData?[1][400] ?? 0)
        suite.expect(peak <= BoostLimiter.ceiling + 0.0001 && peak > 0.8,
                     "a boosted sound gets louder but never past the ceiling")
        suite.expect(quiet > 0.4, "a boost lifts the quieter channel too")
        suite.expect(AppSoundService.render(url.deletingLastPathComponent().appending(path: "missing.caf"),
                                            gain: 1, repeats: 1) == nil,
                     "a missing file renders nothing")
    }

    private static func spacing(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        suite.expect(AppSoundSupport.isDue(after: nil, now: now), "the first sound plays")
        suite.expect(!AppSoundSupport.isDue(after: now.addingTimeInterval(-0.5), now: now),
                     "agents starting together are heard once")
        suite.expect(AppSoundSupport.isDue(after: now.addingTimeInterval(-AppSoundSupport.minimumGap), now: now),
                     "a later moment is heard again")
        suite.expect(AppSoundSupport.isDue(after: now.addingTimeInterval(60), now: now),
                     "a clock set back does not silence sounds")
    }

    private static func starts(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = AgentUsageStore()
        var heard: [AgentProvider] = []
        store.turnStarted = { heard.append($0) }

        store.apply([.turnBegan(now)], file: "early", provider: .codex, tracksTurns: true, modified: now, now: now)
        suite.expect(heard.isEmpty, "turns read before transitions are reported, at launch, are history")

        store.reportsTransitions = true
        store.apply([.turnBegan(now)], file: "a", provider: .codex, tracksTurns: true, modified: now, now: now)
        suite.expect(heard == [.codex], "a turn opening is heard")
        store.apply([.turnBegan(now)], file: "a", provider: .codex, tracksTurns: true, modified: now, now: now)
        suite.expect(heard == [.codex], "a log read again from its start opens no second turn")
        store.apply([.turnActive(now)], file: "a", provider: .codex, tracksTurns: true, modified: now, now: now)
        suite.expect(heard == [.codex], "work going on in an open turn is not a start")

        store.apply([.turnActive(now)], file: "b", provider: .claude, tracksTurns: true, modified: now, now: now)
        suite.expect(heard == [.codex, .claude], "work seen before its turn's opening starts it all the same")

        let old = now.addingTimeInterval(-AgentUsageStore.lateEnd - 1)
        store.apply([.turnBegan(old)], file: "c", provider: .codex, tracksTurns: true, modified: now, now: now)
        suite.expect(heard.count == 2, "a turn found late, long after it opened, is not news")

        store.apply([.turnBegan(now)], file: "d", provider: .opencode, tracksTurns: false, modified: now, now: now)
        suite.expect(heard.count == 2, "a subagent's work belongs to its parent's turn")

        store.closeIdleTurns(now: now.addingTimeInterval(NotchAgentSupport.idleTurn), after: NotchAgentSupport.idleTurn)
        store.apply([.turnActive(now.addingTimeInterval(NotchAgentSupport.idleTurn + 1))], file: "a", provider: .codex,
                    tracksTurns: true, modified: now, now: now.addingTimeInterval(NotchAgentSupport.idleTurn + 1))
        suite.expect(heard.count == 2, "work resuming after an approval is the same turn, not a new start")
    }

    private static func legacyKeys(_ suite: TestSuite) {
        suite.expect(AppSound.timerFinished.enabledKey == DefaultsKey.notchTimerSoundEnabled
                        && AppSound.watchFinished.enabledKey == DefaultsKey.notchWatchSound
                        && AppSound.screenLock.enabledKey == DefaultsKey.notchLockSounds
                        && AppSound.snippetExpanded.enabledKey == DefaultsKey.snippetSoundEnabled,
                     "the sounds older pages switched keep their switches, so both pages agree")
        suite.expect(AppSound.snippetExpanded.nameKey == DefaultsKey.snippetSoundName,
                     "the snippet sound keeps the sound chosen on the snippets page")
        suite.expect(AppSound.timerFinished.volumeKey == "soundTimerFinishedVolume"
                        && AppSound.snippetExpanded.repeatsKey == "soundSnippetExpandedRepeats",
                     "a moment with an older switch still gets keys of its own for loudness and repeats")
        let registered = AppSound.registeredDefaults
        suite.expect(AppSound.allCases.compactMap(\.legacyEnabledKey).allSatisfy { registered[$0] == nil }
                        && registered[DefaultsKey.snippetSoundName] == nil,
                     "older pages' keys are left to the pages that register them")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchTimerSoundEnabled] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.notchWatchSound] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.notchLockSounds] as? Bool == false
                        && Defaults.registeredDefaults[DefaultsKey.snippetSoundEnabled] as? Bool == false,
                     "older switches keep their registered defaults")
        let backedUp = SettingsBackupSupport.exportKeys()
        suite.expect(AppSound.allCases.allSatisfy {
            backedUp.isSuperset(of: [$0.enabledKey, $0.nameKey, $0.volumeKey, $0.repeatsKey])
        }, "every moment's keys are backed up")

        let name = "vorss.tests.app-sound-legacy.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        let installed: (AppFeature) -> Bool = { _ in true }
        suite.expect(AppSoundSupport.isOn(.timerFinished, in: defaults, isAvailable: installed)
                        && AppSoundSupport.isOn(.watchFinished, in: defaults, isAvailable: installed),
                     "the alarm and the watch sound, as they always have, before anyone sets them")
        defaults.set(false, forKey: DefaultsKey.notchTimerSoundEnabled)
        suite.expect(!AppSoundSupport.isOn(.timerFinished, in: defaults, isAvailable: installed),
                     "the alarm switched off on the island's page is off on the Sounds page")
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        suite.expect(AppSoundSupport.isOn(.screenLock, in: defaults, isAvailable: installed),
                     "padlock sounds switched on before the Sounds page still play")
    }

    private static func snippetSoundMigration(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appending(path: "vorss-snippet-sound-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in ["Tink.aiff", "Hero.aiff"] {
            FileManager.default.createFile(atPath: root.appending(path: file).path, contents: Data())
        }
        let library = AppSoundLibrary(systemFolder: root, toneFolder: root.appending(path: "none"), userFolders: [],
                                      builtIns: [:])
        let name = "vorss.tests.app-sound-snippet.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }

        suite.expect(AppSoundSupport.choice(.snippetExpanded, in: defaults, library: library)?.id == "system:Tink",
                     "an unset snippet sound is Tink, as it always was")
        defaults.set("Hero", forKey: DefaultsKey.snippetSoundName)
        suite.expect(AppSoundSupport.choice(.snippetExpanded, in: defaults, library: library)?.id == "system:Hero",
                     "a snippet sound chosen on the snippets page plays from the Sounds page")
        defaults.set("Gone", forKey: DefaultsKey.snippetSoundName)
        suite.expect(AppSoundSupport.choice(.snippetExpanded, in: defaults, library: library)?.id == "system:Tink",
                     "a snippet sound this Mac lacks falls back to Tink, as the snippets page did")
        guard let hero = AppSoundSupport.choice(.snippetExpanded, in: defaults, library: library) else { return }
        suite.expect(AppSoundSupport.playsAsAlert(.snippetExpanded, choice: hero, in: defaults),
                     "a snippet sound left at full, once, plays through the sound server as before")
        defaults.set(1.5, forKey: AppSound.snippetExpanded.volumeKey)
        suite.expect(!AppSoundSupport.playsAsAlert(.snippetExpanded, choice: hero, in: defaults),
                     "a boosted snippet sound is rendered so it can be louder")
        defaults.removeObject(forKey: AppSound.snippetExpanded.volumeKey)
        suite.expect(!AppSoundSupport.playsAsAlert(.snippetExpanded, choice: AppSoundChoice(source: .tone, name: "Modern/Chord"),
                                                   in: defaults),
                     "a tone is rendered, since the sound server may not read it")
        suite.expect(!AppSoundSupport.playsAsAlert(.timerFinished, choice: hero, in: defaults),
                     "the alarm keeps playing as it did, outside the sound server")
    }

    private static func existingUserDefaults(_ suite: TestSuite) {
        let name = "vorss.tests.app-sound-existing.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        // Someone who set these pages before the Sounds page and nothing
        // since. Registered values are read from the table rather than
        // registered here, since registration is shared by the whole process.
        let registered = Defaults.registeredDefaults
        defaults.set(true, forKey: DefaultsKey.snippetSoundEnabled)
        defaults.set("Pop", forKey: DefaultsKey.snippetSoundName)
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        func stored(_ key: String) -> Any? { defaults.object(forKey: key) ?? registered[key] }
        for sound in [AppSound.timerFinished, .watchFinished, .screenLock, .snippetExpanded] {
            suite.expect(stored(sound.volumeKey) as? Double == 1 && stored(sound.repeatsKey) as? Int == 1
                            && AppSoundSupport.volume(sound, in: defaults) == 1 && AppSoundSupport.repeats(sound, in: defaults) == 1
                            && AppSoundSupport.isDue(after: Date(), now: Date().addingTimeInterval(0.1), gap: sound.minimumGap),
                         "\(sound.rawValue) plays at full, once, as often as it happens, as it did")
        }
        suite.expect(stored(AppSound.timerFinished.nameKey) as? String == "system:Glass"
                        && stored(AppSound.watchFinished.nameKey) as? String == "system:Glass"
                        && stored(AppSound.screenLock.nameKey) as? String == AppSoundChoice.padlockClosing.id
                        && AppSoundChoice(id: stored(AppSound.snippetExpanded.nameKey) as? String ?? "")?.id == "system:Pop",
                     "each keeps the sound it made: Glass, the padlock and the snippet sound chosen")
        suite.expect(stored(AppSound.snippetExpanded.enabledKey) as? Bool == true
                        && stored(AppSound.screenLock.enabledKey) as? Bool == true
                        && stored(AppSound.timerFinished.enabledKey) as? Bool == true
                        && stored(AppSound.watchFinished.enabledKey) as? Bool == true,
                     "each keeps its switch as it was set or registered")
    }

    private static func builtInPadlock(_ suite: TestSuite) {
        suite.expect(AppSoundChoice(id: AppSoundChoice.padlockClosing.id) == AppSoundChoice.padlockClosing
                        && AppSoundChoice.padlockOpening.source == .builtIn,
                     "the padlock reads back as the app's own sound")
        let root = FileManager.default.temporaryDirectory.appending(path: "vorss-padlock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // The padlock lives outside every folder the library lists.
        let framework = root.appending(path: "framework")
        try? FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let lock = framework.appending(path: "lock.aif"), tink = root.appending(path: "Tink.aiff")
        for file in [lock, tink] { FileManager.default.createFile(atPath: file.path, contents: Data()) }
        let library = AppSoundLibrary(systemFolder: root, toneFolder: root.appending(path: "none"), userFolders: [],
                                      builtIns: [AppSoundChoice.padlockClosing: lock])
        suite.expect(library.choices.map(\.id) == ["system:Tink"],
                     "the padlock is never listed for other moments")
        suite.expect(library.url(for: AppSoundChoice.padlockClosing) == lock,
                     "the padlock is found where macOS keeps it")
        let name = "vorss.tests.app-sound-padlock.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        suite.expect(AppSoundSupport.choice(.screenLock, in: defaults, library: library) == AppSoundChoice.padlockClosing,
                     "locking plays the padlock until another sound is chosen")
        let bare = AppSoundLibrary(systemFolder: root, toneFolder: root.appending(path: "none"), userFolders: [],
                                   builtIns: [:])
        suite.expect(AppSoundSupport.choice(.screenLock, in: defaults, library: bare)?.id == "system:Tink",
                     "without the padlock, locking still makes a sound")
        let real = AppSoundLibrary.builtInSounds()
        suite.expect(real[AppSoundChoice.padlockClosing] == NotchLockScreenSupport.soundURL(locking: true)
                        && real[AppSoundChoice.padlockOpening] == NotchLockScreenSupport.soundURL(locking: false),
                     "the padlock closes on locking and opens on unlocking, as before")
    }

    private static func power(_ suite: TestSuite) {
        let unplugged = PowerSoundReading(chargePercent: 50, externalConnected: false)
        let plugged = PowerSoundReading(chargePercent: 50, externalConnected: true)
        suite.expect(PowerSoundSupport.moments(from: nil, to: plugged).isEmpty,
                     "the state at launch plays nothing")
        suite.expect(PowerSoundSupport.moments(from: unplugged, to: plugged) == [.chargerConnected],
                     "plugging in a charger is heard")
        suite.expect(PowerSoundSupport.moments(from: plugged, to: unplugged) == [.chargerDisconnected],
                     "unplugging the charger is heard")
        suite.expect(PowerSoundSupport.moments(from: plugged, to: plugged).isEmpty,
                     "a reading that changes nothing plays nothing")

        let mark = PowerSoundSupport.lowBatteryPercent
        let above = PowerSoundReading(chargePercent: mark + 1, externalConnected: false)
        let low = PowerSoundReading(chargePercent: mark, externalConnected: false)
        suite.expect(PowerSoundSupport.moments(from: above, to: low) == [.batteryLow],
                     "the battery falling to the mark is heard")
        suite.expect(PowerSoundSupport.moments(from: low, to: PowerSoundReading(chargePercent: mark - 1,
                                                                               externalConnected: false)).isEmpty,
                     "a low battery is heard once, not at every percent")
        suite.expect(PowerSoundSupport.moments(from: PowerSoundReading(chargePercent: mark + 1, externalConnected: true),
                                               to: PowerSoundReading(chargePercent: mark, externalConnected: true)).isEmpty,
                     "a battery low on the charger is not a warning")
        suite.expect(PowerSoundSupport.moments(from: PowerSoundReading(chargePercent: 5, externalConnected: true),
                                               to: PowerSoundReading(chargePercent: 5, externalConnected: false))
                        == [.chargerDisconnected],
                     "unplugging an already low battery plays only the charger")
        suite.expect(PowerSoundSupport.moments(from: PowerSoundReading(chargePercent: nil, externalConnected: false),
                                               to: low).isEmpty,
                     "an unknown charge does not read as a fall")

        suite.expect(!PowerSoundSupport.isWanted(hasBattery: true) { _ in false },
                     "the power sources are not watched while every power sound is off")
        suite.expect(PowerSoundSupport.isWanted(hasBattery: true) { $0 == .chargerConnected },
                     "one power sound switched on is enough to watch")
        suite.expect(!PowerSoundSupport.isWanted(hasBattery: true) { $0 == .keepAwakeEnded },
                     "Keep awake ending does not need the power sources")
        suite.expect(!PowerSoundSupport.isWanted(hasBattery: false) { _ in true },
                     "a Mac without a battery watches nothing")

        let battery: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 3,
                                      kIOPSMaxCapacityKey: 4, kIOPSPowerSourceStateKey: kIOPSACPowerValue]
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 1, kIOPSMaxCapacityKey: 1]
        suite.expect(PowerSoundSupport.internalBattery(in: [ups, battery]).map(PowerSoundSupport.reading(from:))
                        == PowerSoundReading(chargePercent: 75, externalConnected: true),
                     "the internal battery is read, not a UPS")
        suite.expect(PowerSoundSupport.internalBattery(in: [ups]) == nil, "a desktop with a UPS has no battery")
        suite.expect(PowerSoundSupport.reading(from: [kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue])
                        == PowerSoundReading(chargePercent: nil, externalConnected: false),
                     "a battery without a capacity has no charge")

        suite.expect(Set(AppSoundGroup.power.sounds) == Set(PowerSoundSupport.sounds + [.keepAwakeEnded])
                        && AppSound.keepAwakeEnded.feature == .keepAwake
                        && AppSound.allCases.filter { $0.group == .power }.allSatisfy { AppSound.registeredDefaults[$0.enabledKey] as? Bool == false },
                     "the power group holds its four moments, each off at first")
    }

    private static func groups(_ suite: TestSuite) {
        suite.expect(AppSoundGroup.capture.sounds == [.screenshotTaken, .recordingStarted, .recordingStopped]
                        && AppSoundGroup.island.sounds == [.downloadFinished, .calendarEventSoon],
                     "capture and island moments sit in their own sections")
        suite.expect(AppSound.screenshotTaken.feature == .screenshot
                        && AppSound.recordingStopped.feature == .screenRecorder
                        && AppSound.downloadFinished.feature == .notchDownloads
                        && AppSound.calendarEventSoon.feature == .notchCalendar,
                     "each moment shows only while the feature that plays it is installed")
        suite.expect(AppSound.screenshotTaken.enabledKey == "soundScreenshotTaken"
                        && AppSound.calendarEventSoon.repeatsKey == "soundCalendarEventSoonRepeats",
                     "new moments name their keys like the first ones")
        suite.expect(AppSoundGroup.capture.strings(.enUS).note == nil && !AppSoundGroup.capture.noteApplies
                        && AppSoundGroup.island.strings(.enUS).note != nil,
                     "only the island's section waits on another setting")
    }

    private static func islandPages(_ suite: TestSuite) {
        let name = "vorss.tests.island-sound.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        suite.expect(!IslandSoundSupport.waitsOnIsland(in: defaults, isAvailable: { _ in false }),
                     "no note while neither island page is installed")
        suite.expect(IslandSoundSupport.waitsOnIsland(in: defaults, isAvailable: { $0 == .notchDownloads }),
                     "an installed Downloads page that is off holds its sound back")
        suite.expect(!IslandSoundSupport.downloadsOn(in: defaults), "the Downloads page starts off")
    }

    private static func eventsSoon(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 3_000_000)
        func event(_ id: String, start: TimeInterval, allDay: Bool = false) -> NotchCalendarEvent {
            NotchCalendarEvent(id: id, title: id, calendar: "Work", start: now.addingTimeInterval(start),
                               end: now.addingTimeInterval(start + 3600), allDay: allDay, location: "")
        }
        let lead = IslandSoundSupport.calendarLeadTime
        let soon = event("soon", start: lead - 30)
        let later = event("later", start: lead + 600)
        let begun = event("begun", start: -60)
        let allDay = event("day", start: 60, allDay: true)
        let events = [soon, later, begun, allDay]

        let due = IslandSoundSupport.dueEvents(events, now: now, heard: [:])
        suite.expect(due == [soon], "only a timed event inside the lead time sounds")
        let heard = IslandSoundSupport.heard([:], adding: due, now: now)
        suite.expect(IslandSoundSupport.dueEvents(events, now: now.addingTimeInterval(20), heard: heard).isEmpty,
                     "an event sounds once, however often the calendar is read again")
        suite.expect(IslandSoundSupport.dueEvents([event("soon", start: lead - 10)], now: now, heard: heard).isEmpty,
                     "the same event read again is still the one already heard")
        suite.expect(IslandSoundSupport.dueEvents([begun], now: now, heard: [:]).isEmpty,
                     "an event already under way at launch never sounds")
        suite.expect(IslandSoundSupport.dueEvents([allDay], now: now.addingTimeInterval(-lead), heard: [:]).isEmpty,
                     "an all-day event never sounds")
        suite.expect(IslandSoundSupport.nextSound(events, now: now) == later.start.addingTimeInterval(-lead),
                     "the reader wakes when the next event's sound falls due")
        suite.expect(IslandSoundSupport.dueEvents(events, now: later.start.addingTimeInterval(-lead), heard: heard)
                        == [later],
                     "a later event sounds when its moment comes")
        suite.expect(IslandSoundSupport.heard(heard, adding: [], now: soon.start).isEmpty,
                     "an event is forgotten once it begins")
    }
}
