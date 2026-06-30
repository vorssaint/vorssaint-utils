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

enum MixerRoutingSupport {
    static let systemDefaultSelectionID = "__system_default__"

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

    static func requiresEngine(volume: Double,
                               selectedOutputDeviceUID: String?,
                               targetOutputDeviceUID: String?,
                               defaultOutputDeviceUID: String?) -> Bool {
        guard let targetOutputDeviceUID else { return false }
        if !isUnity(volume) { return true }
        guard let selectedOutputDeviceUID else { return false }
        guard let defaultOutputDeviceUID else { return true }
        return selectedOutputDeviceUID != defaultOutputDeviceUID
            && targetOutputDeviceUID != defaultOutputDeviceUID
    }

    static func bypassesProcessTap(bundleIdentifier: String?, name: String) -> Bool {
        let bundle = (bundleIdentifier ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        if bundle == "us.zoom.xos" || bundle.hasPrefix("us.zoom.") {
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
