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

struct MixerDiscoveredOutputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let bluetoothAddress: String?
}

struct MixerVolumeEndpointSelection: Equatable {
    enum Group: Equatable {
        case master
        case channels
    }

    let group: Group
    let indexes: [Int]
    let isSettable: Bool
}

enum MixerRoutingSupport {
    static let systemDefaultSelectionID = "__system_default__"
    static let bluetoothSelectionPrefix = "Bluetooth:"
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

    static func bluetoothAudioOutputs(fromSystemProfilerJSON data: Data) -> [MixerDiscoveredOutputDevice] {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [Any] else {
            return []
        }

        var devices: [MixerDiscoveredOutputDevice] = []
        for controllerValue in controllers {
            guard let controller = dictionary(from: controllerValue) else { continue }
            for key in ["device_connected", "device_not_connected", "device_paired", "device_recently_used"] {
                guard let entries = controller[key] as? [Any] else { continue }
                for entryValue in entries {
                    guard let entry = dictionary(from: entryValue) else { continue }
                    for (name, propertiesValue) in entry {
                        guard let properties = dictionary(from: propertiesValue),
                              bluetoothLooksLikeAudio(name: name, properties: properties) else { continue }
                        let address = normalizedBluetoothAddress(string(from: properties["device_address"]))
                        let id = address
                            .map { bluetoothSelectionPrefix + $0 }
                            ?? "BluetoothName:\(name.lowercased())"
                        devices.append(MixerDiscoveredOutputDevice(id: id, name: name, bluetoothAddress: address))
                    }
                }
            }
        }
        return sortedDiscoveredOutputs(devices)
    }

    static func bluetoothAddress(fromSelectionID id: String) -> String? {
        guard id.hasPrefix(bluetoothSelectionPrefix) else { return nil }
        return normalizedBluetoothAddress(String(id.dropFirst(bluetoothSelectionPrefix.count)))
    }

    static func outputMatchesDiscoveredBluetooth(name: String,
                                                 uid: String,
                                                 route: MixerDiscoveredOutputDevice) -> Bool {
        if let address = route.bluetoothAddress {
            return embeddedBluetoothAddress(in: uid) == address
        }
        return normalizedOutputName(name) == normalizedOutputName(route.name)
    }

    static func embeddedBluetoothAddress(in raw: String) -> String? {
        let separatedPattern = #"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])"#
        if let range = raw.range(of: separatedPattern, options: .regularExpression) {
            return normalizedBluetoothAddress(String(raw[range]))
        }

        let compactPattern = #"(?i)(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])"#
        guard let range = raw.range(of: compactPattern, options: .regularExpression) else { return nil }
        return normalizedBluetoothAddress(String(raw[range]))
    }

    static func outputDeviceIsStable(previousUID: String?, candidateUID: String?) -> Bool {
        guard let candidateUID else { return false }
        return previousUID == candidateUID
    }

    static func outputVolumeEndpointSelection(masterReadable: [Bool],
                                              masterSettable: [Bool],
                                              channelReadable: [Bool],
                                              channelSettable: [Bool]) -> MixerVolumeEndpointSelection? {
        if let index = masterReadable.indices.first(where: {
            masterReadable[$0] && masterSettable.indices.contains($0) && masterSettable[$0]
        }) {
            return MixerVolumeEndpointSelection(group: .master, indexes: [index], isSettable: true)
        }

        let readableChannels = channelReadable.indices.filter { channelReadable[$0] }
        if !readableChannels.isEmpty,
           readableChannels.allSatisfy({ channelSettable.indices.contains($0) && channelSettable[$0] }) {
            return MixerVolumeEndpointSelection(group: .channels,
                                                indexes: readableChannels,
                                                isSettable: true)
        }

        if let index = masterReadable.firstIndex(of: true) {
            return MixerVolumeEndpointSelection(group: .master, indexes: [index], isSettable: false)
        }
        guard !readableChannels.isEmpty else { return nil }
        return MixerVolumeEndpointSelection(group: .channels,
                                            indexes: readableChannels,
                                            isSettable: false)
    }

    static func effectiveOutputVolume(base: Double, master: Double) -> Double {
        min(max(base, 0), 1) * min(max(master, 0), 1)
    }

    static func baseOutputVolume(effective: Double,
                                 master: Double,
                                 previousBase: Double) -> Double {
        let clampedMaster = min(max(master, 0), 1)
        guard clampedMaster > 0.001 else { return min(max(previousBase, 0), 1) }
        return min(max(effective / clampedMaster, 0), 1)
    }

    static func normalizedBluetoothAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hex = raw.lowercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        return stride(from: 0, to: 12, by: 2)
            .map { index in
                let start = hex.index(hex.startIndex, offsetBy: index)
                let end = hex.index(start, offsetBy: 2)
                return String(hex[start..<end])
            }
            .joined(separator: "-")
    }

    static func normalizedOutputName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func bluetoothLooksLikeAudio(name: String, properties: [String: Any]) -> Bool {
        let minorType = string(from: properties["device_minorType"])
        let majorType = string(from: properties["device_majorType"])
        let haystack = [name, minorType, majorType]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        let terms = ["audio", "speaker", "headphone", "headset", "airpods", "buds", "stereo", "sonos"]
        return terms.contains { haystack.contains($0) }
    }

    private static func sortedDiscoveredOutputs(_ devices: [MixerDiscoveredOutputDevice]) -> [MixerDiscoveredOutputDevice] {
        var seen = Set<String>()
        return devices
            .filter { seen.insert($0.id).inserted }
            .sorted { displayOrderedBefore(name: $0.name, id: $0.id, otherName: $1.name, otherID: $1.id) }
    }

    private static func dictionary(from value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? NSDictionary {
            return dictionary as? [String: Any]
        }
        return nil
    }

    private static func string(from value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
