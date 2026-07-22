// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
    static let systemDefaultSelectionID = "__system_default__"
    static let finderBundleIdentifier = "com.apple.finder"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)

    static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
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
                               defaultOutputDeviceUID: String?) -> Bool {
        guard hasAudioObjects else { return false }
        guard let targetOutputDeviceUID else { return false }
        if !isUnity(volume) { return true }
        guard let selectedOutputDeviceUID else { return false }
        guard let defaultOutputDeviceUID else { return true }
        return selectedOutputDeviceUID != defaultOutputDeviceUID
            && targetOutputDeviceUID != defaultOutputDeviceUID
    }

    /// The last gate before a tap is built: a row is tapped only when the user
    /// actually adjusted it, either to a volume other than 100% or to an output
    /// other than the system default. An app that is merely listed is never
    /// part of any tap, so the mixer can neither mute it nor re-render its
    /// sound.
    static func rowMayBeTapped(savedVolume: Double?,
                               savedRouteUID: String?,
                               defaultOutputDeviceUID: String?) -> Bool {
        if let savedVolume, !isUnity(savedVolume) { return true }
        guard let savedRouteUID else { return false }
        guard let defaultOutputDeviceUID else { return true }
        return savedRouteUID != defaultOutputDeviceUID
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

    static func isHiddenFromMixer(bundleIdentifier: String?, showFinder: Bool) -> Bool {
        bundleIdentifier == finderBundleIdentifier && !showFinder
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

    static func resolveInputDevice(preferredUID: String?,
                                   availableUIDs: Set<String>,
                                   currentUID: String?) -> MixerInputRouteResolution {
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

    private static func sanitizedAppID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) }) else {
            return nil
        }
        return trimmed
    }
}
