// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SQLite3
import UniformTypeIdentifiers

/// One destination in the picker and the rule editor.
struct BrowserPickerChoice: Identifiable, Hashable {
    let target: BrowserPickerTarget
    let title: String
    /// The browser's name under a profile; nil for a browser itself.
    let subtitle: String?
    let appURL: URL

    var id: BrowserPickerTarget { target }
}

/// Finds the installed browsers and their profiles, and hands a link to one.
enum BrowserPickerBrowsers {
    /// How a browser keeps its profiles: Chromium in `Local State` and opens
    /// one with `--profile-directory`, Firefox in `profiles.ini` and its
    /// profile manager's database and opens one with `--profile`.
    enum ProfileKind {
        case chromium, firefox
    }

    /// Browsers whose profiles can be chosen, by bundle ID, with their data
    /// folder in Application Support.
    static let profileBrowsers: [String: (kind: ProfileKind, folder: String)] = [
        "com.google.Chrome": (.chromium, "Google/Chrome"),
        "com.google.Chrome.beta": (.chromium, "Google/Chrome Beta"),
        "com.google.Chrome.canary": (.chromium, "Google/Chrome Canary"),
        "com.microsoft.edgemac": (.chromium, "Microsoft Edge"),
        "com.brave.Browser": (.chromium, "BraveSoftware/Brave-Browser"),
        "com.vivaldi.Vivaldi": (.chromium, "Vivaldi"),
        "org.chromium.Chromium": (.chromium, "Chromium"),
        "org.mozilla.firefox": (.firefox, "Firefox"),
        "org.mozilla.firefoxdeveloperedition": (.firefox, "Firefox"),
        "org.mozilla.nightly": (.firefox, "Firefox"),
        "app.zen-browser.zen": (.firefox, "zen"),
        "io.gitlab.librewolf-community": (.firefox, "librewolf"),
    ]

    static func dataFolder(_ folder: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }

    /// Any build of this app answers web links too, but is never a destination.
    static func isVorssaint(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.vorssaint.utils")
    }

    /// What discovery found: the choices, and the browsers whose profiles
    /// macOS did not let this app read.
    struct Discovery: Equatable {
        var choices: [BrowserPickerChoice] = []
        var withheldProfiles: [String] = []
        /// Profile ids of each browser whose list was read.
        var knownProfiles: [String: Set<String>] = [:]
    }

    /// Browsers by name, each browser with two or more profiles replaced by
    /// its profiles: "Chrome" alone would open whichever profile was used
    /// last, which is the guess the picker is there to avoid.
    ///
    /// A browser's profile list sits with its data, which macOS guards and may
    /// ask about the first time. `readingProfiles` is off until someone has
    /// looked at the feature's settings, so that question never interrupts a
    /// clicked link. Never call this on the main thread with it on: macOS
    /// holds the read until the question is answered.
    static func discover(readingProfiles: Bool) -> Discovery {
        let probe = URL(string: "https://example.com")!
        let htmlViewers = Set(NSWorkspace.shared.urlsForApplications(toOpen: .html).map(\.standardizedFileURL))
        var seen = Set<String>()
        let browsers = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> (String, String, URL)? in
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, !isVorssaint(bundleID),
                  isBrowser(at: url.standardizedFileURL, info: bundle.infoDictionary ?? [:], htmlViewers: htmlViewers),
                  seen.insert(bundleID).inserted else { return nil }
            return (bundleID, displayName(of: url), url)
        }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }

        var discovery = Discovery()
        for (bundleID, name, url) in browsers {
            var profiles: [(id: String, name: String)] = []
            if readingProfiles, profileBrowsers[bundleID] != nil {
                switch self.profiles(bundleID: bundleID) {
                case .success(let found):
                    profiles = found
                    discovery.knownProfiles[bundleID] = Set(found.map(\.id))
                case .failure:
                    discovery.withheldProfiles.append(name)
                }
            }
            guard profiles.count > 1 else {
                discovery.choices.append(BrowserPickerChoice(target: .application(bundleID: bundleID), title: name,
                                                             subtitle: nil, appURL: url))
                continue
            }
            discovery.choices += profiles.map {
                BrowserPickerChoice(target: .profile(bundleID: bundleID, id: $0.id, name: $0.name),
                                    title: $0.name, subtitle: name, appURL: url)
            }
        }
        return discovery
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

    static func displayName(of appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    struct ProfilesWithheld: Error {}

    /// A browser's profiles. Fails only when the list exists but macOS refused
    /// to let it be read; a browser that never made one has no profiles.
    static func profiles(bundleID: String) -> Result<[(id: String, name: String)], ProfilesWithheld> {
        guard let browser = profileBrowsers[bundleID] else { return .success([]) }
        let folder = dataFolder(browser.folder)
        let file = folder.appendingPathComponent(browser.kind == .chromium ? "Local State" : "profiles.ini")
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoPermission {
            return .failure(ProfilesWithheld())
        } catch {
            return .success([])
        }
        switch browser.kind {
        case .chromium:
            return .success(profiles(fromLocalState: data).map { ($0.directory, $0.name) })
        case .firefox:
            let listed = firefoxProfiles(fromIni: String(decoding: data, as: UTF8.self))
            return .success(firefoxProfiles(listed: listed, managed: managedFirefoxProfiles(in: folder), in: folder,
                                            wasUsed: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("prefs.js").path) },
                                            exists: { isDirectory($0) }))
        }
    }

    /// Profiles listed in a Chromium `Local State` file, in the browser's own
    /// order when it keeps one. Only plain folder names are accepted, since the
    /// name ends up in a command-line argument.
    static func profiles(fromLocalState data: Data) -> [(directory: String, name: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        let order = (profile["profiles_order"] as? [String]) ?? []
        let entries = cache.compactMap { directory, value -> (directory: String, name: String)? in
            guard isPlainFolderName(directory),
                  let name = (value as? [String: Any])?["name"] as? String,
                  !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (directory, name)
        }
        return entries.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.directory) ?? .max
            let right = order.firstIndex(of: rhs.directory) ?? .max
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// The `[ProfileN]` sections of a Firefox `profiles.ini`, in file order.
    static func firefoxProfiles(fromIni text: String) -> [(path: String, name: String)] {
        var profiles: [(path: String, name: String)] = []
        var section: [String: String]?
        func close() {
            if let section, let path = section["Path"], !path.isEmpty, let name = section["Name"] {
                profiles.append((path, name))
            }
        }
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                close()
                section = line.hasPrefix("[Profile") ? [:] : nil
            } else if let separator = line.firstIndex(of: "="), section != nil {
                section?[String(line[..<separator])] = String(line[line.index(after: separator)...])
            }
        }
        close()
        return profiles
    }

    /// The profiles Firefox's profile manager keeps, from each profile group's
    /// database, with their paths relative to the data folder.
    static func managedFirefoxProfiles(in folder: URL) -> [(path: String, name: String)] {
        let groups = folder.appendingPathComponent("Profile Groups", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap(profileRows)
    }

    private static func profileRows(_ database: URL) -> [(path: String, name: String)] {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(connection, 200)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, "SELECT path, name FROM Profiles ORDER BY id", -1, &statement, nil)
                == SQLITE_OK else { return [] }
        var rows: [(path: String, name: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1) else { continue }
            rows.append((String(cString: path), String(cString: name)))
        }
        return rows
    }

    /// The Firefox profiles worth offering: those of the profile manager,
    /// under the names given there, then those of `profiles.ini` that have
    /// been used. Firefox creates an extra profile at install that is never
    /// opened; offering it would only add a mystery row.
    static func firefoxProfiles(listed: [(path: String, name: String)], managed: [(path: String, name: String)],
                                in folder: URL, wasUsed: (URL) -> Bool,
                                exists: (URL) -> Bool) -> [(id: String, name: String)] {
        var seen = Set<String>()
        var result: [(id: String, name: String)] = []
        for (path, name, required) in managed.map({ ($0.path, $0.name, false) }) + listed.map({ ($0.path, $0.name, true) }) {
            guard let directory = firefoxProfileDirectory(path, in: folder), exists(directory),
                  !required || wasUsed(directory),
                  !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  seen.insert(directory.path).inserted else { continue }
            result.append((firefoxProfileID(directory, in: folder), name))
        }
        return result
    }

    /// A profile's directory from the path Firefox stores: relative to the
    /// data folder, or absolute (`IsRelative=0`) and then starting with a slash.
    static func firefoxProfileDirectory(_ path: String, in folder: URL) -> URL? {
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
                                      : folder.appendingPathComponent(path, isDirectory: true)
        return url.standardizedFileURL
    }

    /// Profiles inside the data folder are kept relative to it, so a rule
    /// does not carry the home folder's path.
    static func firefoxProfileID(_ directory: URL, in folder: URL) -> String {
        let base = folder.standardizedFileURL.path + "/"
        return directory.path.hasPrefix(base) ? String(directory.path.dropFirst(base.count)) : directory.path
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func isPlainFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.hasPrefix("-")
            && !name.contains("/") && !name.contains("\0")
    }

    /// The arguments that open `url` in one profile, nil when the profile
    /// cannot be named safely. A browser that is already running receives
    /// them from the short-lived second instance.
    static func profileArguments(kind: ProfileKind, id: String, in folder: URL, url: URL) -> [String]? {
        switch kind {
        case .chromium:
            return isPlainFolderName(id) ? ["--profile-directory=\(id)", url.absoluteString] : nil
        case .firefox:
            // The way Firefox's own profile manager opens a link in a profile.
            return firefoxProfileDirectory(id, in: folder).map { ["--profile", $0.path, "-new-tab", url.absoluteString] }
        }
    }

    static func applicationURL(for target: BrowserPickerTarget) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID)
    }

    /// Opens the link and reports whether macOS accepted it, on the main queue.
    static func open(_ url: URL, in target: BrowserPickerTarget, completion: @escaping (Bool) -> Void) {
        guard let appURL = applicationURL(for: target), !isVorssaint(target.bundleID) else {
            completion(false)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let done: (NSRunningApplication?, Error?) -> Void = { _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }
        switch target {
        case .application:
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration,
                                    completionHandler: done)
        case .profile(let bundleID, let id, _):
            guard let browser = profileBrowsers[bundleID],
                  let arguments = profileArguments(kind: browser.kind, id: id, in: dataFolder(browser.folder), url: url)
            else {
                completion(false)
                return
            }
            configuration.createsNewApplicationInstance = true
            configuration.arguments = arguments
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration,
                                               completionHandler: done)
        }
    }
}

