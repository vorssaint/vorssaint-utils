// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// The installed browsers and which one macOS opens web links with. The
/// state lives in Launch Services, so nothing here is stored.
enum DefaultBrowserSupport {
    struct Browser: Identifiable, Equatable {
        let bundleID: String
        let name: String
        let url: URL
        var id: String { bundleID }
    }

    private static let probe = URL(string: "https://example.com")!

    static var current: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    /// Browsers by name, one row per bundle id even when several copies are
    /// installed; Launch Services lists its preferred copy first.
    static func installed() -> [Browser] {
        let htmlViewers = Set(NSWorkspace.shared.urlsForApplications(toOpen: .html).map(\.standardizedFileURL))
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> Browser? in
            let url = url.standardizedFileURL
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  isBrowser(at: url, info: bundle.infoDictionary ?? [:], htmlViewers: htmlViewers),
                  seen.insert(bundleID).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
            return Browser(bundleID: bundleID, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                           url: url)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Apps other than browsers claim web links too: a terminal as a
    /// fallback, an assistant for its sign-in, test browsers that automation
    /// tools keep in hidden folders. A browser also opens HTML files and does
    /// not rank itself as a mere alternate for web links.
    static func isBrowser(at appURL: URL, info: [String: Any], htmlViewers: Set<URL>) -> Bool {
        guard htmlViewers.contains(appURL),
              !appURL.pathComponents.contains(where: { $0.hasPrefix(".") }) else { return false }
        let webTypes = (info["CFBundleURLTypes"] as? [[String: Any]] ?? []).filter {
            let schemes = ($0["CFBundleURLSchemes"] as? [String] ?? []).map { $0.lowercased() }
            return schemes.contains("http") || schemes.contains("https")
        }
        return !webTypes.contains { ["Alternate", "None"].contains($0["LSHandlerRank"] as? String ?? "") }
    }

    /// The browser the shortcut switches to: the one after `current` among
    /// the chosen browsers that are still installed, wrapping around. With
    /// nothing chosen, every installed browser takes part. Nil when there is
    /// no other browser to switch to.
    static func next(after current: String?, chosen: [String], installed: [String]) -> String? {
        let candidates = chosen.isEmpty ? installed : chosen.filter(installed.contains)
        guard !candidates.isEmpty else { return nil }
        let next = current.flatMap(candidates.firstIndex(of:)).map { candidates[($0 + 1) % candidates.count] }
            ?? candidates[0]
        return next == current ? nil : next
    }

    /// Makes `appURL` open http and https links. macOS asks the user to
    /// confirm each scheme it changes; https is set on its own only when it
    /// did not already follow http. Launch Services records the handler by
    /// bundle id, so the copy found at another path still counts.
    @MainActor
    static func makeDefault(_ appURL: URL) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
        let https = NSWorkspace.shared.urlForApplication(toOpen: probe).flatMap { Bundle(url: $0)?.bundleIdentifier }
        if https == nil || https != Bundle(url: appURL)?.bundleIdentifier {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return [error, underlying].contains {
            $0?.domain == NSOSStatusErrorDomain && $0?.code == Int(userCanceledErr)
        }
    }
}
