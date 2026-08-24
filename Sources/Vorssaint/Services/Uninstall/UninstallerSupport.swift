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

    /// The symbol a finished removal shows. A tick is for a removal that took
    /// everything; anything left behind gets a warning, so a done state cannot
    /// report success over its own survivors.
    static func doneSymbol(hasLeftovers: Bool) -> String {
        hasLeftovers ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    static func verifiedBundleID(_ rawValue: String?) -> String? {
        guard let rawValue,
              CleanerSupport.looksLikeBundleID(rawValue),
              !CleanerSupport.isProtectedBundleID(rawValue) else { return nil }
        return rawValue
    }

    static func isNestedBundle(_ candidateURL: URL?, in appURL: URL) -> Bool {
        guard let candidateURL else { return false }
        let appPath = appURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        return candidatePath.hasPrefix(appPath + "/")
    }

    static func sharedDataIsExclusive(selectedURL: URL,
                                      bundleID: String,
                                      knownApplications: [(url: URL, bundleID: String)]) -> Bool {
        let selectedPath = selectedURL.resolvingSymlinksInPath().standardizedFileURL.path
        return !knownApplications.contains { application in
            let applicationPath = application.url.resolvingSymlinksInPath().standardizedFileURL.path
            return application.bundleID == bundleID
                && applicationPath != selectedPath
                && !applicationPath.hasPrefix(selectedPath + "/")
        }
    }

    static func exclusiveBundleIDs(_ candidates: Set<String>,
                                   selectedURL: URL,
                                   knownApplications: [(url: URL, bundleID: String)]) -> Set<String> {
        Set(candidates.filter {
            sharedDataIsExclusive(selectedURL: selectedURL,
                                  bundleID: $0,
                                  knownApplications: knownApplications)
        })
    }

    static func applicationIsInTrustedInstallRoot(_ url: URL, home: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        return roots.contains { path.hasPrefix($0 + "/") }
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
