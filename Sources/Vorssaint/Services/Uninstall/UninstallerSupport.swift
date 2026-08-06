// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure ownership rules for the Uninstaller. Every deeper location is derived
/// from a verified bundle identifier; display names never become paths.
enum UninstallerSupport {
    enum Kind: Equatable {
        case support, caches
    }

    struct Candidate: Equatable {
        let url: URL
        let kind: Kind
    }

    static func verifiedBundleID(_ rawValue: String?) -> String? {
        guard let rawValue,
              CleanerSupport.looksLikeBundleID(rawValue),
              !CleanerSupport.isProtectedBundleID(rawValue) else { return nil }
        return rawValue
    }

    static func exactDeepCandidates(home: URL,
                                    bundleIDs: Set<String>,
                                    darwinCache: URL?,
                                    darwinTemp: URL?) -> [Candidate] {
        var result: [Candidate] = []
        for id in bundleIDs.sorted() {
            result.append(Candidate(url: home.appendingPathComponent(".config/").appendingPathComponent(id),
                                    kind: .support))
            result.append(Candidate(url: home.appendingPathComponent(".cache/").appendingPathComponent(id),
                                    kind: .caches))
            result.append(Candidate(url: home.appendingPathComponent(".local/share/").appendingPathComponent(id),
                                    kind: .support))
            if let darwinCache {
                result.append(Candidate(url: darwinCache.appendingPathComponent(id), kind: .caches))
            }
            if let darwinTemp {
                result.append(Candidate(url: darwinTemp.appendingPathComponent(id), kind: .caches))
            }
        }
        return result
    }

    static func matchesByHostPreference(_ name: String, bundleIDs: Set<String>) -> Bool {
        guard name.hasSuffix(".plist"), CleanerSupport.containsUUIDComponent(name) else { return false }
        return bundleIDs.contains { name.hasPrefix("\($0).") }
    }

    static func matchesGroupContainer(_ name: String, bundleIDs: Set<String>) -> Bool {
        bundleIDs.contains(name) || bundleIDs.contains { name == "group.\($0)" }
    }

    static func matchesLaunchItem(_ name: String, bundleIDs: Set<String>) -> Bool {
        bundleIDs.contains { name == "\($0).plist" }
    }
}
