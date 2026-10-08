// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

struct MixerInputRouteResolution: Equatable {
    let effectiveUID: String?
    let selectedUnavailable: Bool
    let shouldApplyPreferred: Bool
}

struct MixerOutputPreferences: Equatable {
    let outputDeviceUIDs: [String: String]
    let volumes: [String: Double]
}

/// How a mixer row is identified.
struct MixerRowIdentity: Equatable {
    /// Identifies the row in the list and its engine. Always present.
    let rowID: String
    /// The key the row's volume and route are stored under: the bundle id
    /// when the process has one, otherwise its display name (the only handle
    /// that survives a relaunch — pids recycle, names don't). Nil when the
    /// process offers neither, in which case the row is listed and adjustable
    /// for as long as it runs but stores nothing.
    let persistenceID: String?
}

/// Decides which engine build may be installed when it lands.
///
/// Building a tap takes tens of milliseconds off the main thread, and the
/// mixer can throw every engine away in the meantime (the output device
/// changed, the feature was switched off). Each build carries the token it
/// started with and is installed only while that token is still the row's
/// current one, so a late build is discarded instead of leaving a second live
/// tap on the same app rendering the sound twice.
struct MixerEngineBuilds {
    private var tokens: [String: Int] = [:]
    private var nextToken = 1

    var isEmpty: Bool { tokens.isEmpty }

    /// Claims the row for a build. Nil when one is already in flight, so a
    /// slider being dragged cannot queue a build per tick.
    mutating func begin(_ id: String) -> Int? {
        guard tokens[id] == nil else { return nil }
        let token = nextToken
        nextToken += 1
        tokens[id] = token
        return token
    }

    func isCurrent(_ id: String, token: Int) -> Bool { tokens[id] == token }

    /// Frees the row for the next build. A late build that no longer owns the
    /// row leaves the current one untouched.
    mutating func finish(_ id: String, token: Int) {
        guard tokens[id] == token else { return }
        tokens.removeValue(forKey: id)
    }

    /// Marks everything in flight as stale. Tokens are never reused, so builds
    /// already queued can no longer be installed, while a fresh build for the
    /// same row can start right away.
    mutating func invalidateAll() { tokens.removeAll() }

}

/// Gives one dead audio path a replacement, then keeps that exact path
/// untapped so a persistent HAL failure cannot keep muting it.
struct MixerEngineRecovery {
    struct Configuration: Equatable {
        let objects: [AudioObjectID]
        let outputDeviceUID: String
    }

    private struct Failure {
        let configuration: Configuration
        var count: Int
    }

    private var failures: [String: Failure] = [:]

    func allowsBuild(_ id: String, configuration: Configuration) -> Bool {
        guard let failure = failures[id], failure.configuration == configuration else {
            return true
        }
        return failure.count < 2
    }

    mutating func recordFailure(_ id: String, configuration: Configuration) -> Bool {
        let count = failures[id]?.configuration == configuration
            ? (failures[id]?.count ?? 0) + 1
            : 1
        failures[id] = Failure(configuration: configuration, count: count)
        return count < 2
    }

    mutating func clear(_ id: String) {
        failures.removeValue(forKey: id)
    }

    mutating func clearAll() {
        failures.removeAll()
    }
}

/// Arbitrates the refresh passes that read the audio HAL.
///
/// Reading device and process properties is done off the main thread, because
/// a device being reconfigured can hold a single read for as long as the audio
/// daemon holds that device. What comes back is published on the main thread,
/// and this decides which pass gets to do that.
///
/// Three rules, in the same spirit as the engine build tokens above: only one
/// pass reads at a time, a request that arrives while a pass is reading is
/// remembered and runs once it lands, and a pass whose generation is no longer
/// current is dropped instead of publishing what it saw.
struct MixerRefreshCoordinator {
    private(set) var generation = 0
    private(set) var isReading = false
    private var requestedAgain = false

    /// Claims the slot for a pass, or nil when one is already reading. The
    /// request is remembered either way, so nothing is silently lost.
    mutating func begin() -> Int? {
        guard !isReading else {
            requestedAgain = true
            return nil
        }
        isReading = true
        generation += 1
        return generation
    }

    /// Frees the slot and reports whether this pass may still publish. A pass
    /// from a generation that is gone leaves the slot alone: it belongs to
    /// whatever replaced it.
    mutating func finish(_ generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        isReading = false
        return true
    }

    /// Whether a refresh was asked for while the pass was reading, and clears
    /// the request so it runs exactly once.
    mutating func takeRepeatRequest() -> Bool {
        defer { requestedAgain = false }
        return requestedAgain
    }

    /// Drops whatever is in flight: what it read is already out of date,
    /// because the audio environment just changed on purpose (or is no longer
    /// being watched at all).
    mutating func discardInFlight() {
        generation += 1
        isReading = false
        requestedAgain = false
    }
}

enum MixerRoutingSupport {
    static func observationNeeds(isAvailable: (AppFeature) -> Bool)
        -> (devices: Bool, processes: Bool) {
        let mixer = isAvailable(.mixer)
        return (mixer || isAvailable(.audioPriority) || isAvailable(.soundOutputSwitcher), mixer)
    }

    static let systemDefaultSelectionID = "__system_default__"
    static let finderBundleIdentifier = "com.apple.finder"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)

    static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
    }

    /// The most a tap is ever turned back up: four channel pairs, the widest
    /// loss anyone has measured. Past it the correction would be a guess, and
    /// a guess that is too large plays the app louder than it ever was.
    static let maximumTapLevelCompensation: Double = 4

    /// How much louder a tapped app has to be played to sound as it does
    /// untouched.
    ///
    /// The stereo mixdown tap divides what it hears by the number of channel
    /// pairs of the output an app plays to, a known system issue
    /// (FB13479345). On an eight channel output, like a TV over HDMI or an
    /// audio interface, the app reached the mixer at a quarter of its level,
    /// so 95% sounded far quieter than 100% and even 200% stayed below it. A
    /// stereo output loses nothing, and neither does an aggregate of stereo
    /// devices, because each device inside it is divided on its own.
    ///
    /// `streamChannels` hold, for each output the app plays to right now,
    /// the width of the stream carrying its stereo pair. Only that stream
    /// counts, not every stream of the device. Nobody has measured a device
    /// with several streams, and the narrower count is the safer guess. A
    /// silent app plays nowhere and has nothing to correct. An app on several
    /// outputs gets the smallest correction, since a larger one would lift
    /// the others above their own level. An output that cannot be read (nil)
    /// counts as stereo, so it can only lower the correction, never lift it.
    static func tapLevelCompensation(streamChannels: [Int?]) -> Double {
        guard let fewest = streamChannels.map({ $0 ?? 2 }).filter({ $0 > 0 }).min() else { return 1 }
        return min(max(Double(fewest) / 2, 1), maximumTapLevelCompensation)
    }

    /// What a watch stores before it reads how wide the outputs of a tapped
    /// app are, or nil to keep the correction it has.
    ///
    /// A move stores no correction first. A new output can be slow to answer
    /// while it starts, and no correction is the level that is never too
    /// loud. A silent app keeps its correction while the default output is
    /// still among its last outputs, so it resumes there at the right level
    /// from its first buffer. Otherwise it may resume somewhere else, and no
    /// correction is the safe level again. `defaultOutputDevices` lists the
    /// devices inside the default output when it is an aggregate, the way an
    /// app's own outputs list them, and is empty when it cannot be read.
    static func tapLevelBeforeReading(devices: Set<AudioObjectID>,
                                      lastDevices: Set<AudioObjectID>,
                                      defaultOutputDevices: Set<AudioObjectID>) -> Double? {
        if devices.isEmpty {
            guard !defaultOutputDevices.isEmpty,
                  defaultOutputDevices.isSubset(of: lastDevices) else { return 1 }
            return nil
        }
        return devices == lastDevices ? nil : 1
    }

    /// How long the mixer's own pass waits between two reads of a watch.
    /// The pass only backs up the announced moves, and a slider drag runs it
    /// on every step.
    static let tapLevelBackstopInterval: Double = 1

    static func tapLevelReadIsDue(immediately: Bool, sinceLastRead: Double) -> Bool {
        immediately || sinceLastRead >= tapLevelBackstopInterval
    }

    /// How long a rising correction takes to cross its whole range. Long
    /// enough that the level never jumps between two short buffers.
    static let tapLevelRampDuration: Double = 0.03
    /// How long a falling correction takes to cross it. Much shorter, since
    /// until it lands the app plays louder than it should, but still long
    /// enough not to step the level inside a waveform.
    static let tapLevelDropDuration: Double = 0.005

    /// The correction the audio thread applies in a cycle of `seconds`. It
    /// eases at the same pace in time on every buffer size, quickly on the
    /// way down and gently on the way up, so neither direction jumps the
    /// level. A cycle longer than its ramp moves all the way. The first cycle
    /// takes the value as it is. Each cycle takes the pace of the way it
    /// moves now, with no memory of the last one. So when a move between two
    /// outputs of the same width stores the provisional 1 of
    /// `tapLevelBeforeReading` and the read puts the old value back, the
    /// level dips only for the cycles the 1 lasted and then climbs back at
    /// the gentle pace.
    static func tapLevelRampStep(applied: Float?, target: Float, seconds: Double) -> Float {
        guard let applied, applied > 0 else { return target }
        let duration = target < applied ? tapLevelDropDuration : tapLevelRampDuration
        let limit = Float(pow(maximumTapLevelCompensation, min(max(seconds, 0) / duration, 1)))
        return min(max(target, applied / limit), applied * limit)
    }

    /// An output as an app's own outputs list it: the devices inside it for an
    /// aggregate, down through any aggregate inside it, the device itself
    /// otherwise. An aggregate none of whose devices can be found, or one
    /// nested deeper than anyone builds, keeps its own ID, which no app
    /// lists, so it can only drop a correction, never keep one.
    static func outputDevices(of output: AudioObjectID,
                              subDeviceUIDs: (AudioObjectID) -> [String],
                              deviceForUID: (String) -> AudioObjectID?,
                              depth: Int = 0) -> Set<AudioObjectID> {
        let inside = subDeviceUIDs(output).compactMap(deviceForUID)
        guard !inside.isEmpty, depth < 4 else { return [output] }
        return inside.reduce(into: Set<AudioObjectID>()) { devices, device in
            devices.formUnion(outputDevices(of: device, subDeviceUIDs: subDeviceUIDs,
                                            deviceForUID: deviceForUID, depth: depth + 1))
        }
    }

    /// The engines to read again at once when the audio environment changes:
    /// those whose app still aims at the output they render to. The rest are
    /// rebuilt for their new output and read their own, and a rebuild that
    /// fails reads the engine it keeps.
    static func enginesKeepingTheirOutput(engineOutputs: [String: String],
                                          targets: [String: String]) -> Set<String> {
        Set(engineOutputs.compactMap { id, output in targets[id] == output ? id : nil })
    }

    /// Which processes a level watch has to start and stop listening to so
    /// it hears exactly `wanted`: only the difference, never one it already
    /// hears.
    static func listenerChanges<Object: Hashable>(listened: Set<Object>, wanted: Set<Object>)
        -> (add: Set<Object>, remove: Set<Object>) {
        (wanted.subtracting(listened), listened.subtracting(wanted))
    }

    /// Channels of the stream a stereo app plays into: the one holding the
    /// output's preferred stereo pair, whose left channel counts from 1. A
    /// pair outside every stream falls back to the first stream.
    static func stereoStreamChannels(streamChannels: [Int], preferredLeftChannel: Int) -> Int? {
        var firstChannel = 1
        for channels in streamChannels where channels > 0 {
            if preferredLeftChannel >= firstChannel, preferredLeftChannel < firstChannel + channels {
                return channels
            }
            firstChannel += channels
        }
        return streamChannels.first { $0 > 0 }
    }

    /// Inactive apps with a custom volume or output remain visible so hiding
    /// idle rows can never conceal a setting the user may want to undo.
    static func shouldShowApp(isPlaying: Bool,
                              volume: Double,
                              selectedOutputDeviceUID: String?,
                              hideInactiveApps: Bool) -> Bool {
        guard hideInactiveApps else { return true }
        return isPlaying || !isUnity(volume) || selectedOutputDeviceUID != nil
    }

    /// Turns the text entered beside a mixer slider into its gain. The field
    /// accepts the same optional percent sign it displays, while the caller
    /// supplies the limit (100 for the system output, 200 for an app row).
    static func volumeFraction(fromPercentageText text: String,
                               maximumPercent: Int) -> Double? {
        guard maximumPercent >= 0 else { return nil }
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("%") {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let separator = Locale.current.decimalSeparator, separator != "." {
            normalized = normalized.replacingOccurrences(of: separator, with: ".")
        }
        guard let percent = Double(normalized), percent.isFinite else { return nil }
        return min(max(percent, 0), Double(maximumPercent)) / 100
    }

    static func sanitizedDeviceUID(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    static func sanitizedRouteMap(_ raw: [String: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (rawID, rawUID) in raw {
            guard let appID = sanitizedAppID(rawID),
                  let deviceUID = sanitizedDeviceUID(rawUID) else { continue }
            sanitized[appID] = deviceUID
        }
        return sanitized
    }

    static func effectiveDeviceUID(selectedUID: String?,
                                   availableUIDs: Set<String>,
                                   defaultUID: String?) -> String? {
        if let selectedUID, availableUIDs.contains(selectedUID) {
            return selectedUID
        }
        return defaultUID
    }

    static func selectedDeviceUnavailable(selectedUID: String?,
                                          availableUIDs: Set<String>) -> Bool {
        guard let selectedUID else { return false }
        return !availableUIDs.contains(selectedUID)
    }

    static func preferencesAfterUniversalOutputSwitch(outputDeviceUIDs: [String: String],
                                                      volumes: [String: Double],
                                                      switchSucceeded: Bool) -> MixerOutputPreferences {
        MixerOutputPreferences(outputDeviceUIDs: switchSucceeded ? [:] : outputDeviceUIDs,
                               volumes: volumes)
    }

    /// Vorssaint's own AirPlay entry, streamed through the system route picker.
    /// Exact match only: real AirPlay devices macOS exposes are ordinary outputs
    /// and route through the normal tap, and a device name or UID that merely
    /// mentions AirPlay must never be mistaken for this entry.
    static func isAirPlaySentinel(_ uid: String) -> Bool {
        uid == AirPlayRouteManager.airPlaySentinelUID
    }

    /// The item in an app's output menu that opens the system's speaker list
    /// for every app set to AirPlay, without changing this app's output.
    static let airPlaySpeakerChoiceID = "vorssaint.output.airplay.choose"

    /// Whether a running engine's output is still there to render to. The
    /// AirPlay entry stays listed while no speaker is picked, but an engine
    /// streaming to it then only mutes its app, exactly like one whose
    /// device was unplugged, so it counts as gone. So does one whose clock,
    /// the Mac output it was built on, is gone: its tap stops with it, and
    /// the replacement is built on the output there now.
    static func engineOutputIsPresent(_ uid: String, clockUID: String? = nil, listedUIDs: [String],
                                      airPlayConnected: Bool) -> Bool {
        guard listedUIDs.contains(uid) else { return false }
        guard isAirPlaySentinel(uid) else { return true }
        return airPlayConnected && clockUID.map(listedUIDs.contains) != false
    }

    /// Whether an app's output menu needs its own "Output unavailable" row for
    /// the selected output. Only when that output is not listed anyway (an
    /// unplugged device): a listed one keeps its own row selected, since two
    /// rows sharing a tag would leave the menu ticking the wrong one.
    static func needsUnavailableOutputRow(selectedUID: String?, isUnavailable: Bool,
                                          listedUIDs: [String]) -> Bool {
        guard let selectedUID, isUnavailable else { return false }
        return !listedUIDs.contains(selectedUID)
    }

    /// Outputs an app's audio can go to right now. The AirPlay entry stays in
    /// the list (choosing it opens the picker) but only carries audio while a
    /// speaker is picked; otherwise the app falls back to the default output,
    /// exactly like unplugged headphones.
    static func routableOutputUIDs(_ uids: [String], airPlayConnected: Bool) -> Set<String> {
        Set(uids.filter { airPlayConnected || !isAirPlaySentinel($0) })
    }

    static func nextSelectedOutputDeviceUID(currentUID: String?,
                                            selectedUIDs: [String],
                                            availableUIDs: Set<String>) -> String? {
        var seen = Set<String>()
        let candidates = selectedUIDs.compactMap { rawUID -> String? in
            guard let uid = sanitizedDeviceUID(rawUID),
                  availableUIDs.contains(uid),
                  seen.insert(uid).inserted else { return nil }
            return uid
        }
        guard !candidates.isEmpty else { return nil }
        guard let currentUID,
              let index = candidates.firstIndex(of: currentUID) else {
            return candidates[0]
        }
        guard candidates.count > 1 else { return nil }
        return candidates[(index + 1) % candidates.count]
    }

    static func outputLooksLikeHeadphones(name: String,
                                          uid: String,
                                          dataSourceName: String?) -> Bool {
        let haystack = [name, uid, dataSourceName ?? ""]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        let normalized = haystack.replacingOccurrences(of: #"[^a-z0-9]+"#,
                                                       with: " ",
                                                       options: .regularExpression)
        let directTerms = [
            "headphone", "headphones", "headset",
            "earphone", "earphones", "earbud", "earbuds",
            "airpod", "airpods", "earpod", "earpods",
            "galaxy buds", "pixel buds", "beats", "bose qc",
            "sony wh", "sony wf", "jabra", "soundcore"
        ]
        return directTerms.contains { normalized.contains($0) }
    }

    static func requiresEngine(hasAudioObjects: Bool = true,
                               volume: Double,
                               selectedOutputDeviceUID: String?,
                               targetOutputDeviceUID: String?,
                               defaultOutputDeviceUID: String?,
                               universalOutputRouteUID: String? = nil) -> Bool {
        guard hasAudioObjects else { return false }
        guard let targetOutputDeviceUID else { return false }
        if !isUnity(volume) { return true }
        if let selectedOutputDeviceUID {
            // An explicit route still matters when it happens to be the
            // system default: a Wine game may keep its old device open.
            return selectedOutputDeviceUID == targetOutputDeviceUID
        }
        return universalOutputRouteUID == targetOutputDeviceUID
            && targetOutputDeviceUID == defaultOutputDeviceUID
    }

    /// The last gate before a tap is built: a row is tapped only when the user
    /// adjusted its volume, chose its output, or asked to move all audio to an
    /// output that this process did not follow. Merely listing an app never
    /// makes it part of a tap.
    static func rowMayBeTapped(savedVolume: Double?,
                               savedRouteUID: String?,
                               defaultOutputDeviceUID: String?,
                               universalOutputRouteUID: String? = nil) -> Bool {
        if let savedVolume, !isUnity(savedVolume) { return true }
        if savedRouteUID != nil { return true }
        guard let universalOutputRouteUID else { return false }
        return universalOutputRouteUID == defaultOutputDeviceUID
    }

    /// A universal output choice normally needs only the system default to
    /// change. Processes that keep another device open need a tap as well.
    /// Empty device lists mean silence or an unavailable read, not evidence
    /// that a previously routed process now follows the default. Keep that
    /// route until its same audio objects report where they play again.
    static func requiresUniversalOutputRouting(requestedUID: String?,
                                                defaultUID: String?,
                                                selectedUID: String?,
                                                audioObjects: [AudioObjectID],
                                                previouslyRoutedObjects: [AudioObjectID]?,
                                                processDevices: Set<AudioObjectID>,
                                                defaultDevices: Set<AudioObjectID>) -> Bool {
        guard let requestedUID, requestedUID == defaultUID,
              selectedUID == nil, !audioObjects.isEmpty, !defaultDevices.isEmpty else { return false }
        if processDevices.isEmpty {
            return previouslyRoutedObjects == audioObjects
        }
        return !processDevices.isSubset(of: defaultDevices)
    }

    /// Identity of a row: the bundle id when the app has one, otherwise a
    /// per-process row that saves under its display name. Games and tools
    /// distributed as bare executables have no bundle id, and the name is the
    /// key their volume has always been saved under, so it also brings back
    /// what the user saved on older versions. Two same-named processes stay
    /// separate rows (and engines) but share the saved volume.
    static func rowIdentity(bundleIdentifier: String?,
                            ownerPid: pid_t,
                            displayName: String?) -> MixerRowIdentity {
        guard let bundleID = sanitizedAppID(bundleIdentifier ?? "") else {
            return MixerRowIdentity(rowID: "\(unidentifiedRowPrefix)\(ownerPid)",
                                    persistenceID: sanitizedAppID(displayName ?? ""))
        }
        return MixerRowIdentity(rowID: bundleID, persistenceID: bundleID)
    }

    static let unidentifiedRowPrefix = "process:"

    /// Window used to fold a row's comings and goings into one decision.
    static let engineChurnCoalescingWindow: Double = 0.2

    /// How long to keep an engine whose row has no audio object left; nil
    /// means let it go now.
    ///
    /// An app that recreates its audio unit between clips loses its audio
    /// object and gets a new one moments later, which used to cost a tap
    /// teardown and a rebuild per notification. Nothing is audible in that
    /// gap (there is no live object to attenuate), so the tap is kept for a
    /// short window and the churn folds into a single decision. A row that
    /// still has an object is never delayed: sound is only attenuated while a
    /// tap covers the object that is playing.
    static func engineTeardownDelay(hasAudioObjects: Bool,
                                    lastChangeAt: Double?,
                                    now: Double,
                                    window: Double = engineChurnCoalescingWindow) -> Double? {
        guard !hasAudioObjects else { return nil }
        guard let lastChangeAt else { return window }
        let elapsed = max(0, now - lastChangeAt)
        guard elapsed < window else { return nil }
        return window - elapsed
    }

    /// One look at an engine's render counter: how many IO callbacks it had
    /// completed and when that was seen.
    struct EngineRenderObservation: Equatable {
        let cycles: UInt64
        let at: Double
    }

    enum EngineRenderVerdict: Equatable {
        /// Remember this observation and keep checking while the app plays.
        /// A healthy engine can stall later without another audio event.
        case note(EngineRenderObservation, recheckAfter: Double)
        /// The counter has not moved, but not for long enough to be sure;
        /// keep the previous observation and look again after the remaining
        /// time.
        case stalled(recheckAfter: Double)
        /// The app is playing and the engine rendered nothing for the whole
        /// window: its audio path is dead and only the mute remains.
        case wedged
    }

    /// How long a live engine may go without a single render callback, while
    /// its app is playing, before it counts as wedged. A healthy aggregate
    /// runs its IO proc continuously once started (hundreds of callbacks per
    /// second), so a fraction of this window would already be conclusive.
    static let engineRenderStallWindow: Double = 1.5

    /// Whether an engine is still rendering. Waking from sleep (or a device
    /// renegotiating right after) can leave an aggregate whose IO proc never
    /// runs again while its tap keeps muting the app, and nothing else about
    /// the engine looks wrong. Only a playing app gives a verdict: with no
    /// audio there is nothing to mute, and a counter naturally at rest must
    /// not read as a failure. Nil clears any stored observation.
    static func engineRenderVerdict(previous: EngineRenderObservation?,
                                    cycles: UInt64,
                                    isPlaying: Bool,
                                    now: Double,
                                    window: Double = engineRenderStallWindow) -> EngineRenderVerdict? {
        guard isPlaying else { return nil }
        guard let previous else {
            return .note(EngineRenderObservation(cycles: cycles, at: now), recheckAfter: window)
        }
        guard cycles == previous.cycles else {
            return .note(EngineRenderObservation(cycles: cycles, at: now), recheckAfter: window)
        }
        let elapsed = max(0, now - previous.at)
        guard elapsed >= window else { return .stalled(recheckAfter: window - elapsed) }
        return .wedged
    }

    /// What to put back as the system input device when the app stops steering
    /// it. Nil means leave the system alone: nothing was overridden, something
    /// else has chosen a different input since, or the original device is gone.
    static func restorableInputDeviceUID(originalUID: String?,
                                         appliedUID: String?,
                                         currentUID: String?,
                                         availableUIDs: Set<String>) -> String? {
        guard let originalUID, let appliedUID, originalUID != appliedUID else { return nil }
        guard currentUID == appliedUID else { return nil }
        guard availableUIDs.contains(originalUID) else { return nil }
        return originalUID
    }

    /// A volume the app lowered on its own only goes back up while it is still
    /// the value the app set. Anything else means the volume was changed since,
    /// and that choice wins.
    static func shouldRestoreOutputVolume(appliedVolume: Double, currentVolume: Double?) -> Bool {
        guard let currentVolume else { return false }
        return abs(currentVolume - appliedVolume) < 0.005
    }

    /// Pro audio hosts (DAWs and live rack hosts) own their output device,
    /// clock and latency chain; the mixer's stereo-mixdown tap mutes their
    /// real output and replays it elsewhere, which silences them outright
    /// (issue #170: Logic and rack hosts stopped playing once routed). They
    /// are never tapped, so they keep their own audio path and stay out of
    /// the mixer list.
    private static let proAudioBundlePrefixes = [
        "com.apple.logic",       // Logic Pro
        "com.apple.garageband",
        "com.apple.mainstage",
        "com.ableton.",          // Live
        "com.avid.",             // Pro Tools
        "com.cockos.reaper",
        "com.steinberg.",        // Cubase, Nuendo, Dorico
        "com.presonus.",         // Studio One
        "com.bitwig.",
        "com.image-line.",       // FL Studio
        "com.motu.",             // Digital Performer
    ]

    /// The hidden-apps map as stored: persistence id to display name, both
    /// sanitized. The Finder entry never lives here — its visibility has its
    /// own preference key — so an entry for it (an old backup, a hand-edited
    /// plist) is dropped instead of shadowing that key.
    static func sanitizedHiddenApps(_ raw: [String: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (rawID, rawName) in raw {
            guard let appID = sanitizedAppID(rawID),
                  appID != finderBundleIdentifier,
                  let name = sanitizedAppID((rawName as? String) ?? "") else { continue }
            sanitized[appID] = name
        }
        return sanitized
    }

    /// Every persistence id a refresh must leave out of the list: the apps the
    /// user hid, plus the Finder while its own toggle says so.
    static func hiddenRowIDs(hiddenApps: [String: String], showFinder: Bool) -> Set<String> {
        var ids = Set(hiddenApps.keys)
        if !showFinder { ids.insert(finderBundleIdentifier) }
        return ids
    }

    /// A row without a persistence id cannot be hidden: there is no stable key
    /// to remember it under, so it is always listed while it runs.
    static func isHiddenFromMixer(persistenceID: String?, hiddenIDs: Set<String>) -> Bool {
        guard let persistenceID else { return false }
        return hiddenIDs.contains(persistenceID)
    }

    /// How many parent processes to inspect when the responsible process is
    /// not a regular app. Browser audio helpers are direct children of their
    /// app; a small cap keeps a bad parent chain from being walked forever.
    static let owningAppSearchDepth = 6

    /// The regular app a helper's audio belongs to. Normally that is the
    /// helper's responsible process, but some browsers detach their helpers
    /// from the responsibility chain, macOS reports each one as responsible
    /// for itself, and the browser vanished from the mixer (issue #256). The BSD
    /// parent chain still leads to the app that spawned the helper, so walk
    /// it and bill the helper to the nearest regular app.
    static func owningRegularAppPid(responsiblePid: pid_t,
                                    isRegularApp: (pid_t) -> Bool,
                                    parentPid: (pid_t) -> pid_t) -> pid_t? {
        guard responsiblePid > 0 else { return nil }
        if isRegularApp(responsiblePid) { return responsiblePid }
        var current = responsiblePid
        for _ in 0..<owningAppSearchDepth {
            current = parentPid(current)
            guard current > 1 else { return nil }
            if isRegularApp(current) { return current }
        }
        return nil
    }

    static func needsPersistentFinderRow(showFinder: Bool, hasFinderRow: Bool) -> Bool {
        showFinder && !hasFinderRow
    }

    static func bypassesProcessTap(bundleIdentifier: String?, name: String) -> Bool {
        let bundle = (bundleIdentifier ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        if bundle == "us.zoom.xos" || bundle.hasPrefix("us.zoom.") {
            return true
        }
        if proAudioBundlePrefixes.contains(where: { bundle.hasPrefix($0) }) {
            return true
        }

        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName == "zoom"
            || normalizedName == "zoom.us"
            || normalizedName == "zoom workplace"
    }

    /// Ordering for mixer rows: display name, then id. Swift's sort is not
    /// stable, so two apps with the same display name need the explicit
    /// tie-break or their rows can swap places between two refreshes.
    static func displayOrderedBefore(name: String, id: String,
                                     otherName: String, otherID: String) -> Bool {
        switch name.localizedCaseInsensitiveCompare(otherName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return id < otherID
        }
    }

    /// Ordering for device lists: the default device first, then display name,
    /// then uid — deterministic even for identically named devices (two pairs
    /// of the same headphone model, two identical USB interfaces).
    static func deviceDisplayOrderedBefore(isDefault: Bool, name: String, uid: String,
                                           otherIsDefault: Bool, otherName: String,
                                           otherUID: String) -> Bool {
        if isDefault != otherIsDefault { return isDefault }
        return displayOrderedBefore(name: name, id: uid, otherName: otherName, otherID: otherUID)
    }

    /// Returns the first UID from the ordered priority list that is
    /// currently available. Nil if none are available or the list is empty.
    /// Duplicates are skipped (first occurrence wins) and invalid UIDs are
    /// filtered out — the policy is pure and testable without mocking audio
    /// hardware.
    static func firstAvailablePriorityDeviceUID(
        orderedUIDs: [String],
        availableUIDs: Set<String>
    ) -> String? {
        var seen = Set<String>()
        for rawUID in orderedUIDs {
            guard let uid = sanitizedDeviceUID(rawUID),
                  seen.insert(uid).inserted,
                  availableUIDs.contains(uid) else { continue }
            return uid
        }
        return nil
    }

    /// Where a device goes in a priority list that has not ranked it yet.
    /// Virtual and aggregate devices play or record nothing on their own, so
    /// they never take the place of hardware.
    enum PriorityTier: Int {
        case builtIn, hardware, virtual

        init(transportType: UInt32) {
            switch transportType {
            case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                 kAudioDeviceTransportTypeAutoAggregate: self = .virtual
            default: self = .hardware
            }
        }
    }

    /// The order a first-time list starts in: the device in use, then built-in
    /// devices, where macOS itself falls back, then other hardware, and virtual
    /// or aggregate devices last. Within a tier the available order is kept.
    static func initialPriorityList(availableUIDs: [String],
                                    currentUID: String?,
                                    tier: (String) -> PriorityTier) -> [String] {
        var seen = Set<String>()
        let unique = availableUIDs.compactMap { sanitizedDeviceUID($0) }.filter { seen.insert($0).inserted }
        let lead = unique.filter { $0 == currentUID }
        let rest = unique.enumerated()
            .filter { $0.element != currentUID }
            .sorted { lhs, rhs in
                let (a, b) = (tier(lhs.element).rawValue, tier(rhs.element).rawValue)
                return a == b ? lhs.offset < rhs.offset : a < b
            }
            .map(\.element)
        return lead + rest
    }

    /// Where a device the list has never seen joins it once macOS has settled
    /// on it. The device in use goes first, since macOS or the user just picked
    /// it; any other device goes above the virtual and aggregate entries, or
    /// last when it is one itself. Stored entries keep their order.
    static func placingNewPriorityDevice(_ rawUID: String,
                                         in list: [String],
                                         isCurrent: Bool,
                                         tier: (String) -> PriorityTier) -> [String] {
        guard let uid = sanitizedDeviceUID(rawUID), !list.contains(uid) else { return list }
        if isCurrent { return [uid] + list }
        guard tier(uid) != .virtual,
              let firstVirtual = list.firstIndex(where: { tier($0) == .virtual }) else {
            return list + [uid]
        }
        var placed = list
        placed.insert(uid, at: firstVirtual)
        return placed
    }

    /// Whether a CoreAudio write should be requested: only when the target
    /// exists and differs from the current default. Avoids redundant writes
    /// when the desired device is already active.
    static func shouldSwitchToDevice(targetUID: String?, currentUID: String?) -> Bool {
        guard let targetUID else { return false }
        guard targetUID != currentUID else { return false }
        return true
    }

    /// The first observed set establishes a baseline. Afterwards only an
    /// eligible UID entering or leaving is a priority event; changing the
    /// system default merely changes device metadata and must not count.
    static func deviceAvailabilityChanged(previousUIDs: Set<String>?,
                                          currentUIDs: Set<String>) -> Bool {
        guard let previousUIDs else { return false }
        return previousUIDs != currentUIDs
    }

    static func resolveInputDevice(preferredUID: String?,
                                   availableUIDs: Set<String>,
                                   currentUID: String?,
                                   priorityIsActive: Bool = false,
                                   preferredInputIsActive: Bool = true) -> MixerInputRouteResolution {
        if priorityIsActive || !preferredInputIsActive {
            return MixerInputRouteResolution(effectiveUID: currentUID,
                                             selectedUnavailable: false,
                                             shouldApplyPreferred: false)
        }
        guard let preferredUID else {
            return MixerInputRouteResolution(effectiveUID: currentUID,
                                             selectedUnavailable: false,
                                             shouldApplyPreferred: false)
        }
        guard availableUIDs.contains(preferredUID) else {
            return MixerInputRouteResolution(effectiveUID: currentUID,
                                             selectedUnavailable: true,
                                             shouldApplyPreferred: false)
        }
        return MixerInputRouteResolution(effectiveUID: preferredUID,
                                         selectedUnavailable: false,
                                         shouldApplyPreferred: preferredUID != currentUID)
    }

    static func selectedInputDeviceUID(preferredUID: String?,
                                       currentUID: String?,
                                       priorityIsActive: Bool) -> String? {
        priorityIsActive ? currentUID : preferredUID
    }

    private static func sanitizedAppID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) }) else {
            return nil
        }
        return trimmed
    }
}

/// Presentation preferences use the same lasting identity as saved volumes.
/// Missing apps retain their slots; refreshing audio never rewrites this list.
struct MixerAppArrangement: Codable, Equatable {
    private(set) var order: [String] = []
    private(set) var pinned: [String] = []

    init(rawValue: String = "") {
        if let decoded = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) {
            order = Self.unique(decoded.order)
            pinned = Self.unique(decoded.pinned)
        }
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func isPinned(_ id: String?) -> Bool {
        id.map { pinned.contains($0) } ?? false
    }

    func ordered<T>(_ items: [T], identity: (T) -> String?) -> [T] {
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return items.enumerated().sorted { lhs, rhs in
            let left = identity(lhs.element), right = identity(rhs.element)
            if isPinned(left) != isPinned(right) { return isPinned(left) }
            let leftRank = left.flatMap { ranks[$0] } ?? Int.max
            let rightRank = right.flatMap { ranks[$0] } ?? Int.max
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)
    }

    mutating func togglePin(_ id: String) {
        guard !id.isEmpty else { return }
        if isPinned(id) { pinned.removeAll { $0 == id } }
        else { pinned.append(id) }
    }

    func neighbor(of id: String, offset: Int, visibleIDs: [String]) -> String? {
        let group = visibleIDs.filter { isPinned($0) == isPinned(id) }
        guard let index = group.firstIndex(of: id), group.indices.contains(index + offset) else { return nil }
        return group[index + offset]
    }

    mutating func move(_ id: String, offset: Int, visibleIDs: [String]) {
        guard let neighbor = neighbor(of: id, offset: offset, visibleIDs: visibleIDs) else { return }
        move(id, to: neighbor, after: offset > 0, visibleIDs: visibleIDs)
    }

    mutating func move(_ id: String, to target: String, after: Bool, visibleIDs: [String]) {
        guard id != target, visibleIDs.contains(id), visibleIDs.contains(target),
              isPinned(id) == isPinned(target) else { return }
        var group = Self.unique(visibleIDs.filter { isPinned($0) == isPinned(id) })
        group.removeAll { $0 == id }
        guard let index = group.firstIndex(of: target) else { return }
        group.insert(id, at: index + (after ? 1 : 0))
        let moving = Set(group)
        var reordered = group.makeIterator()
        // Replace only this group's visible slots. Closed and hidden apps,
        // and the other pin group, keep their remembered positions.
        order = Self.unique(order + visibleIDs).map { moving.contains($0) ? reordered.next()! : $0 }
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// The correction as one IO proc applies it, eased by
/// `MixerRoutingSupport.tapLevelRampStep`. Touched only by that IO proc.
/// Each cycle is timed by the host clock, so a device that changes its rate
/// under a running engine keeps the same ramp.
final class TapLevelRamp {
    private var applied: Float?
    private var lastHostTime: UInt64?

    func next(toward target: Float, hostTime: UInt64) -> Float {
        let elapsed = lastHostTime.map { hostTime > $0 ? hostTime - $0 : 0 } ?? 0
        lastHostTime = hostTime
        let value = MixerRoutingSupport.tapLevelRampStep(
            applied: applied, target: target,
            seconds: Double(AudioConvertHostTimeToNanos(elapsed)) / 1_000_000_000)
        applied = value
        return value
    }
}

/// Names Core Audio listener registrations by number.
///
/// A listener registered with a plain callback gets its client pointer back
/// on a HAL thread, and a callback can still be on its way when its owner
/// goes away. The pointer is a number looked up here, never an address, so a
/// late callback finds nothing rather than freed memory, and the owner is
/// held weakly, so a registration the HAL never gives back keeps nothing
/// alive. A listener block is no way out: handing one back for removal is
/// reported done while it keeps firing (measured 2026-10-07).
enum AudioListenerClients {
    private struct Entry {
        weak var owner: AnyObject?
    }

    private static let lock = NSLock()
    private static var entries: [UInt: Entry] = [:]
    private static var counter: UInt = 0

    /// A client pointer no other registration holds. Never dereferenced.
    static func reserve(for owner: AnyObject) -> UnsafeMutableRawPointer {
        lock.withLock {
            counter &+= 1
            if counter == 0 { counter = 1 }
            entries[counter] = Entry(owner: owner)
            // A counter that never reaches zero always makes a usable value.
            return UnsafeMutableRawPointer(bitPattern: counter).unsafelyUnwrapped
        }
    }

    static func owner(of client: UnsafeMutableRawPointer?) -> AnyObject? {
        guard let client else { return nil }
        return lock.withLock { entries[UInt(bitPattern: client)]?.owner }
    }

    static func forget(_ client: UnsafeMutableRawPointer) {
        lock.withLock { entries[UInt(bitPattern: client)] = nil }
    }
}
