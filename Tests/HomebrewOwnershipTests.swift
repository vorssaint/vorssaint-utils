// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production lookup methods with controlled process replies. No brew command,
/// installed application or package receipt is changed by these checks.
enum HomebrewOwnershipTests {
    typealias Lookup = Result<HomebrewPackage?, HomebrewOwnershipError>

    enum Queue {
        static var main: Queue.Type { Self.self }
        static func async(execute: () -> Void) { execute() }
    }

    final class Manager {
        typealias DispatchQueue = Queue
        var brewPath: String? = "/opt/homebrew/bin/brew"
        var ownershipLoads: [String: [(Lookup) -> Void]] = [:]
        var commands: [HomebrewCommand] = []
        var replies: [(Int32, String) -> Void] = []

        func detectBrewPath() -> String? { brewPath }
        func run(_ command: HomebrewCommand, completion: @escaping (Int32, String) -> Void) {
            commands.append(command)
            replies.append(completion)
        }
        func reply(_ status: Int32, _ output: String) {
            replies.removeFirst()(status, output)
        }
    }

    private static func isUnmanaged(_ result: Lookup?) -> Bool {
        if case .success(nil)? = result { return true }
        return false
    }

    private static func isUnavailable(_ result: Lookup?) -> Bool {
        if case .failure? = result { return true }
        return false
    }

    private static func packageName(_ result: Lookup?) -> String? {
        if case let .success(package)? = result { return package?.name }
        return nil
    }

    static func run(_ suite: TestSuite) {
        let app = URL(fileURLWithPath: "/Applications/Editor.app")
        let inventory = #"{"formulae":[],"casks":[{"token":"editor","name":["Editor"],"installed":"1","artifacts":[{"app":["Source.app",{"target":"Editor.app"}],"target":"/Applications/Editor.app"}]}]}"#
        let empty = #"{"formulae":[],"casks":[]}"#
        let manager = Manager()
        var answer: Lookup?
        manager.packageManagingApplication(at: app) { answer = $0 }
        suite.expect(answer == nil && manager.commands.first?.arguments == ["info", "--json=v2", "--installed"],
                     "ownership waits for an installed inventory before deciding")
        var concurrent: Lookup?
        manager.packageManagingApplication(at: app) { concurrent = $0 }
        suite.expect(manager.commands.count == 1, "concurrent lookups share their pending read")
        manager.reply(0, "Warning: catalog notice\n" + inventory)
        suite.expect(packageName(answer) == "editor" && packageName(concurrent) == "editor"
                     && manager.ownershipLoads.isEmpty,
                     "a successful inventory reaches every pending caller and permits another read")

        for (status, output) in [(Int32(1), inventory), (-1, "timed out"),
                                 (0, "not JSON"), (0, "{}"),
                                 (0, #"{"casks":[{"token":"--invalid","installed":"1","artifacts":[]}]}"#),
                                 (0, #"{"casks":[{"token":"editor","installed":"1"}]}"#)] {
            answer = nil
            manager.packageManagingApplication(at: app) { answer = $0 }
            manager.reply(status, output)
            suite.expect(isUnavailable(answer),
                         "failed or malformed inventory is not an unmanaged app (status \(status), \(output))")
        }

        manager.packageManagingApplication(at: app) { answer = $0 }
        manager.reply(0, empty)
        suite.expect(isUnmanaged(answer), "a verified empty inventory permits ordinary removal")
        let readsBeforeInstall = manager.commands.count
        manager.packageManagingApplication(at: app) { answer = $0 }
        suite.expect(manager.commands.count == readsBeforeInstall + 1,
                     "a new selection does not reuse the inventory from before an external install")
        manager.reply(0, inventory)
        suite.expect(packageName(answer) == "editor", "retry recovers a cask installed since the last lookup")

        let absent = Manager()
        absent.brewPath = nil
        absent.packageManagingApplication(at: app) { answer = $0 }
        suite.expect(isUnmanaged(answer) && absent.commands.isEmpty,
                     "a Mac without Homebrew still supports ordinary removal")

        guard let records = try? HomebrewParser.parseInstalledCaskRecords(inventory) else {
            suite.expect(false, "valid installed metadata parses")
            return
        }
        suite.expect(isUnmanaged(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Desktop/Editor.app", installed: records)),
                     "a same-named copy outside the exact installed path stays independent")
        suite.expect(isUnavailable(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: app.path, installed: records + records)),
                     "ambiguous ownership blocks both package and ordinary removal")
        let relative = HomebrewCaskRecord(token: "editor", displayName: "Editor", installedVersion: "1",
                                          appFileNames: ["Editor.app"])
        suite.expect(isUnavailable(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: app.path, installed: [relative])),
                     "an installed app without its target path needs verification, not a guessed owner")
        let custom = HomebrewCaskRecord(token: "editor", displayName: "Editor", installedVersion: "1",
                                        appFileNames: ["Renamed.app"],
                                        appPaths: ["/Users/test/Applications/Renamed.app"])
        suite.expect(packageName(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Applications/Renamed.app", installed: [custom])) == "editor",
                     "exact ownership supports a renamed app in a custom app directory")

        if let package = try? HomebrewOwnershipSupport.packageManagingApplication(atPath: app.path, installed: records).get() {
            suite.expect(HomebrewCommandBuilder.uninstall(brewPath: "/opt/homebrew/bin/brew", package: package).arguments
                         == ["uninstall", "--cask", "editor"],
                         "verified casks keep normal uninstall without automatic zap or force")
        } else {
            suite.expect(false, "the exact app resolves before building its uninstall command")
        }
    }
}
