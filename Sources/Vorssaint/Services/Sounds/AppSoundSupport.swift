// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A moment the app can mark with a sound. Each has its own switch, sound,
/// loudness and repeat count, so a moment worth looking up for can ring out
/// while a routine one only ticks.
///
/// Adding a moment: a case here, its group, feature, symbol and defaults
/// below, and its title and caption in its group's strings. Its preference
/// keys follow from the case name.
enum AppSound: String, CaseIterable, Identifiable {
    /// An agent's turn ends: the work is done and waits for you.
    case agentFinished
    /// An agent's turn opens.
    case agentStarted
    /// The last of several agents working together finishes.
    case agentsAllDone
    /// An agent waits on your answer or approval, and at each reminder.
    case agentNeedsInput
    /// An agent's turn is interrupted, or an error stops it.
    case agentInterrupted
    /// An agent nears a plan limit, or one renews.
    case agentLimitWarning
    case agentLimitReset
    /// The day's API value passes its budget.
    case agentBudgetReached
    /// The island's timer reaches zero; its alarm repeats until dismissed.
    case timerFinished
    /// A window the island watches finishes or stalls.
    case watchFinished
    /// The Mac locks or unlocks: the padlock closing, then opening.
    case screenLock
    /// A typed trigger expands into its snippet.
    case snippetExpanded
    /// The battery falls to the low mark while on battery.
    case batteryLow
    /// A charger is plugged in.
    case chargerConnected
    /// The charger is unplugged.
    case chargerDisconnected
    /// A timed Keep Awake session runs out.
    case keepAwakeEnded
    /// A screenshot is taken, by any capture mode.
    case screenshotTaken
    /// A screen recording begins capturing.
    case recordingStarted
    /// A screen recording ends with its take written.
    case recordingStopped
    /// A download in the island's folder finishes.
    case downloadFinished
    /// A timed event is about to start.
    case calendarEventSoon

    var id: String { rawValue }

    var group: AppSoundGroup {
        switch self {
        case .agentFinished, .agentStarted, .agentsAllDone, .agentNeedsInput, .agentInterrupted,
             .agentLimitWarning, .agentLimitReset, .agentBudgetReached: return .agents
        case .timerFinished, .watchFinished, .screenLock: return .alerts
        case .snippetExpanded: return .typing
        case .batteryLow, .chargerConnected, .chargerDisconnected, .keepAwakeEnded: return .power
        case .screenshotTaken, .recordingStarted, .recordingStopped: return .capture
        case .downloadFinished, .calendarEventSoon: return .island
        }
    }

    /// The feature whose events play it; it is offered only while installed.
    var feature: AppFeature {
        switch self {
        case .agentFinished, .agentStarted, .agentsAllDone, .agentNeedsInput, .agentInterrupted,
             .agentLimitWarning, .agentLimitReset, .agentBudgetReached: return .notchAgents
        case .timerFinished: return .notchTimer
        case .watchFinished: return .notchWatch
        case .screenLock: return .notch
        case .snippetExpanded: return .textSnippets
        case .batteryLow, .chargerConnected, .chargerDisconnected: return .monitorPower
        case .keepAwakeEnded: return .keepAwake
        case .screenshotTaken: return .screenshot
        case .recordingStarted, .recordingStopped: return .screenRecorder
        case .downloadFinished: return .notchDownloads
        case .calendarEventSoon: return .notchCalendar
        }
    }

    var symbol: String {
        switch self {
        case .agentFinished: return "checkmark.circle"
        case .agentStarted: return "play.circle"
        case .agentsAllDone: return "checklist.checked"
        case .agentNeedsInput: return "hand.raised"
        case .agentInterrupted: return "pause.circle"
        case .agentLimitWarning: return "exclamationmark.triangle"
        case .agentLimitReset: return "arrow.clockwise"
        case .agentBudgetReached: return "dollarsign.circle"
        case .timerFinished: return "timer"
        case .watchFinished: return "eye"
        case .screenLock: return "lock"
        case .snippetExpanded: return "text.append"
        case .batteryLow: return "battery.25percent"
        case .chargerConnected: return "bolt.fill"
        case .chargerDisconnected: return "bolt.slash"
        case .keepAwakeEnded: return "cup.and.saucer"
        case .screenshotTaken: return "camera.viewfinder"
        case .recordingStarted: return "record.circle"
        case .recordingStopped: return "stop.circle"
        case .downloadFinished: return "arrow.down.circle"
        case .calendarEventSoon: return "calendar.badge.clock"
        }
    }

    /// A choice from `AppSoundLibrary`: a full chime for work that is done,
    /// a lighter one for work beginning, a reminding one for a wait, and a
    /// low one for work that stopped. A low battery gets an alert, the
    /// charger a short click each way. A capture gets a short swish, since
    /// it may come in bursts; an event about to start, a longer call. The
    /// sounds the app made before the
    /// Sounds page keep playing as they did.
    var defaultChoice: String {
        switch self {
        case .agentFinished: return "tone:Modern/Chord"
        case .agentStarted: return "tone:Modern/Aurora"
        case .agentsAllDone: return "tone:Modern/Complete"
        case .agentNeedsInput: return "tone:Modern/Input"
        case .agentInterrupted: return "Basso"
        case .agentLimitWarning: return "tone:Modern/Pulse"
        case .agentLimitReset: return "tone:Modern/Hello"
        case .agentBudgetReached: return "tone:Modern/Note"
        case .timerFinished, .watchFinished: return "system:Glass"
        case .screenLock: return AppSoundChoice.padlockClosing.id
        // Stored bare, as the snippets page always has.
        case .snippetExpanded: return Defaults.defaultSnippetSoundName
        case .batteryLow: return "tone:Classic/Alert"
        case .chargerConnected: return "tone:Modern/Bamboo"
        case .chargerDisconnected: return "tone:Modern/Keys"
        case .keepAwakeEnded: return "tone:Classic/Descent"
        case .screenshotTaken: return "tone:Classic/Swish"
        case .recordingStarted: return "tone:EncoreInfinitum/Portal-EncoreInfinitum"
        case .recordingStopped: return "tone:EncoreInfinitum/Passage-EncoreInfinitum"
        case .downloadFinished: return "tone:EncoreInfinitum/Droplet-EncoreInfinitum"
        case .calendarEventSoon: return "tone:Modern/Circles"
        }
    }

    var defaultVolume: Double {
        switch self {
        case .agentFinished, .agentsAllDone, .agentNeedsInput: return 1.5
        case .agentStarted, .agentInterrupted, .agentLimitWarning, .agentLimitReset, .agentBudgetReached: return 1
        case .timerFinished, .watchFinished, .screenLock, .snippetExpanded: return 1
        case .batteryLow: return 1.5
        case .chargerConnected, .chargerDisconnected, .keepAwakeEnded: return 1
        case .calendarEventSoon: return 1.5
        case .screenshotTaken, .recordingStarted, .recordingStopped, .downloadFinished: return 1
        }
    }

    var defaultRepeats: Int { 1 }

    /// Whether it plays before anyone switches it on, as the alarm and the
    /// watch always have.
    var defaultEnabled: Bool {
        switch self {
        case .timerFinished, .watchFinished: return true
        case .agentFinished, .agentStarted, .agentsAllDone, .agentNeedsInput, .agentInterrupted,
             .agentLimitWarning, .agentLimitReset, .agentBudgetReached, .screenLock, .snippetExpanded,
             .batteryLow, .chargerConnected, .chargerDisconnected, .keepAwakeEnded,
             .screenshotTaken, .recordingStarted, .recordingStopped, .downloadFinished, .calendarEventSoon: return false
        }
    }

    /// Played by the sound server like the Mac's own alerts, on the sound
    /// effects output at the alert volume, while it is set as it came: the
    /// padlock and the snippet sound always played that way.
    var playsAsAlert: Bool {
        switch self {
        case .screenLock, .snippetExpanded: return true
        case .agentFinished, .agentStarted, .agentsAllDone, .agentNeedsInput, .agentInterrupted,
             .agentLimitWarning, .agentLimitReset, .agentBudgetReached, .timerFinished, .watchFinished,
             .batteryLow, .chargerConnected, .chargerDisconnected, .keepAwakeEnded,
             .screenshotTaken, .recordingStarted, .recordingStopped, .downloadFinished, .calendarEventSoon: return false
        }
    }

    /// How soon it may sound again. Snippets typed in a row each tick, and
    /// the alarm rings on its own beat.
    var minimumGap: TimeInterval {
        switch self {
        case .agentFinished, .agentStarted, .agentsAllDone, .agentNeedsInput, .agentInterrupted,
             .agentLimitWarning, .agentLimitReset, .agentBudgetReached,
             .batteryLow, .chargerConnected, .chargerDisconnected, .keepAwakeEnded,
             .screenshotTaken, .recordingStarted, .recordingStopped, .downloadFinished, .calendarEventSoon: return AppSoundSupport.minimumGap
        case .timerFinished, .watchFinished, .screenLock, .snippetExpanded: return 0
        }
    }

    // MARK: Keys

    /// The switch and sound a moment had on its own page before the Sounds
    /// page, still read and written so both pages agree and nobody's
    /// choice is lost. Their defaults stay registered with their pages.
    var legacyEnabledKey: String? {
        switch self {
        case .timerFinished: return DefaultsKey.notchTimerSoundEnabled
        case .watchFinished: return DefaultsKey.notchWatchSound
        case .screenLock: return DefaultsKey.notchLockSounds
        case .snippetExpanded: return DefaultsKey.snippetSoundEnabled
        case .agentFinished, .agentStarted, .agentsAllDone, .agentNeedsInput, .agentInterrupted,
             .agentLimitWarning, .agentLimitReset, .agentBudgetReached,
             .batteryLow, .chargerConnected, .chargerDisconnected, .keepAwakeEnded,
             .screenshotTaken, .recordingStarted, .recordingStopped, .downloadFinished, .calendarEventSoon: return nil
        }
    }

    var legacyNameKey: String? {
        self == .snippetExpanded ? DefaultsKey.snippetSoundName : nil
    }

    /// `soundAgentFinished`, and the same with `Name`, `Volume` and `Repeats`.
    var enabledKey: String { legacyEnabledKey ?? baseKey }
    var nameKey: String { legacyNameKey ?? baseKey + "Name" }
    var volumeKey: String { baseKey + "Volume" }
    var repeatsKey: String { baseKey + "Repeats" }

    private var baseKey: String { "sound" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Every moment starts as it was, with its own sound, loudness and
    /// repeats. A key an older page registers is left to it.
    static var registeredDefaults: [String: Any] {
        var values: [String: Any] = [:]
        for sound in allCases {
            if sound.legacyEnabledKey == nil { values[sound.enabledKey] = sound.defaultEnabled }
            if sound.legacyNameKey == nil { values[sound.nameKey] = sound.defaultChoice }
            values[sound.volumeKey] = sound.defaultVolume
            values[sound.repeatsKey] = sound.defaultRepeats
        }
        return values
    }
}

/// A section of the Sounds page, in page order.
enum AppSoundGroup: String, CaseIterable, Identifiable {
    case agents
    /// The island's alarm, watch and padlock.
    case alerts
    /// Text snippets.
    case typing
    case power
    case capture
    case island

    var id: String { rawValue }

    var sounds: [AppSound] { AppSound.allCases.filter { $0.group == self } }

    /// Whether the section's note shows: its sounds wait on a setting
    /// elsewhere.
    var noteApplies: Bool {
        switch self {
        case .agents: return !NotchAgentSupport.isEnabled()
        case .alerts: return !NotchSupport.isEnabled()
        case .typing: return !UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled)
        case .power: return !PowerSoundSupport.hasInternalBattery
        case .capture: return false
        case .island: return IslandSoundSupport.waitsOnIsland()
        }
    }

    /// Its section title and each moment's words.
    func strings(_ language: AppLanguage) -> SoundGroupStrings {
        switch self {
        case .agents: return FeatureStrings.agentSounds(language)
        case .alerts: return FeatureStrings.alertSounds(language)
        case .typing: return FeatureStrings.typingSounds(language)
        case .power: return FeatureStrings.powerSounds(language)
        case .capture: return FeatureStrings.captureSounds(language)
        case .island: return FeatureStrings.islandSounds(language)
        }
    }
}

enum AppSoundSupport {
    /// The quietest a sound may be set: quieter reads as broken, and the
    /// switch is there to silence it.
    static let minimumVolume = 0.05
    /// Above full, the sound is boosted and held under the output's ceiling.
    static let maximumVolume = 2.0
    static let repeatChoices = [1, 2, 3]
    /// Several agents starting or finishing together are heard once.
    static let minimumGap: TimeInterval = 1.5

    static func isOn(_ sound: AppSound, in defaults: UserDefaults = .standard,
                     isAvailable: (AppFeature) -> Bool = { $0.isAvailable }) -> Bool {
        isAvailable(sound.feature)
            && defaults.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true
            && defaults.object(forKey: sound.enabledKey) as? Bool ?? sound.defaultEnabled
    }

    /// Whether a moment plays as an alert now: an alert sound or the
    /// padlock, at full and once, so it sounds as it always did.
    static func playsAsAlert(_ sound: AppSound, choice: AppSoundChoice, in defaults: UserDefaults = .standard) -> Bool {
        sound.playsAsAlert && (choice.source == .system || choice.source == .builtIn)
            && volume(sound, in: defaults) == 1 && repeats(sound, in: defaults) == 1
    }

    /// The stored choice, or this moment's own when the stored one is not
    /// on this Mac, as when settings came from another.
    static func choice(_ sound: AppSound, in defaults: UserDefaults = .standard,
                       library: AppSoundLibrary = .shared) -> AppSoundChoice? {
        if let stored = defaults.string(forKey: sound.nameKey).flatMap(AppSoundChoice.init(id:)),
           library.url(for: stored) != nil {
            return stored
        }
        if let own = AppSoundChoice(id: sound.defaultChoice), library.url(for: own) != nil { return own }
        return library.choices.first
    }

    static func volume(_ sound: AppSound, in defaults: UserDefaults = .standard) -> Double {
        let value = defaults.object(forKey: sound.volumeKey) as? Double ?? sound.defaultVolume
        return value.isFinite ? min(maximumVolume, max(minimumVolume, value)) : sound.defaultVolume
    }

    static func repeats(_ sound: AppSound, in defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: sound.repeatsKey) as? Int ?? sound.defaultRepeats
        return min(repeatChoices.last ?? 1, max(1, value))
    }

    static func isDue(after last: Date?, now: Date, gap: TimeInterval = minimumGap) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= gap || now < last
    }
}
