// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderToolsPreferencesTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder tools configuration") {
            var configuration = FinderToolsConfiguration()
            configuration.menu.order = ["unknown-future-action", "sha256", "sha256", "newFile"]
            configuration.menu.titles["sha256"] = "Checksum"
            configuration.menu.titles["newFile"] = "\n"
            suite.expect(configuration.menu.orderedActions.first == .sha256
                         && configuration.menu.orderedActions.count == FinderToolsAction.allCases.count,
                         "menu order preserves known actions exactly once and appends new actions")
            suite.expect(configuration.menu.title(for: .sha256, language: "pt-BR") == "Checksum"
                         && configuration.menu.title(for: .newFile, language: "pt-BR") == "Novo arquivo",
                         "custom labels are honored and blank labels fall back to the app language")
            suite.expect(!configuration.menu.visibleActions.contains(.permanentDelete),
                         "permanent deletion starts hidden in the native menu")
            configuration.menu.shortcuts = ["sha256": "k", "newFile": "k", "copyPath": ";"]
            configuration.menu.icons = ["sha256": "number", "newFile": "../invalid"]
            suite.expect(configuration.menu.shortcut(for: .sha256) == "k"
                         && configuration.menu.shortcut(for: .newFile).isEmpty
                         && configuration.menu.shortcut(for: .copyPath).isEmpty,
                         "duplicate and invalid shortcuts cannot shadow the first visible action")
            suite.expect(configuration.menu.icon(for: .sha256) == "number" && configuration.menu.icon(for: .newFile) == nil,
                         "menu icon names accept symbols and reject path-like input")
            configuration.savedActions = [.init(title: "Docs", kind: .website, location: URL(string: "https://example.com")!)]
            suite.expect(FinderToolsConfiguration.decode(configuration.encoded) == configuration,
                         "menu and saved actions round-trip through the backup-compatible representation")
            configuration.savedActions[0].group = "Documentation"
            suite.expect(FinderToolsConfiguration.decode(configuration.encoded).savedActions[0].group == "Documentation",
                         "saved action grouping survives settings backup")
            suite.expect(!FinderToolsSavedAction(title: "Private", kind: .website,
                location: URL(string: "https://user:password@example.com")!).isValid,
                         "saved sites cannot embed credentials")
            configuration.savedActions.append(.init(title: "Untrusted", kind: .script,
                                                      location: URL(string: "https://example.com/script.sh")!))
            suite.expect(FinderToolsConfiguration.decode(configuration.encoded).savedActions.count == 1,
                         "import does not turn a remote URL into a runnable script")
            suite.expect(FinderToolsConfiguration.decode("invalid") == FinderToolsConfiguration(),
                         "corrupt preferences restore the default menu")
        }
        suite.run("Finder script arguments") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("script 'fixture-" + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let script = try FinderFileActions.createFile(in: root, named: "arguments.sh",
                    contents: Data("printf '%s\\n' \"$@\"\n".utf8))
                let marker = root.appendingPathComponent("must-not-exist")
                let unusual = root.appendingPathComponent("$(touch injected); quoted ' name.txt")
                let output = try FinderScriptOperation.run(script, selection: [unusual], directory: root,
                                                           cancellation: FinderToolsCancellation())
                suite.expect(output == unusual.path + "\n", "selected filenames reach the script as literal arguments")
                suite.expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path),
                             "shell metacharacters in filenames are never evaluated")
                let cancellation = FinderToolsCancellation()
                cancellation.cancel()
                let markerScript = try FinderFileActions.createFile(in: root, named: "marker.sh",
                    contents: Data("touch must-not-exist\n".utf8))
                do {
                    _ = try FinderScriptOperation.run(markerScript, selection: [], directory: root, cancellation: cancellation)
                    suite.expect(false, "cancelled script should not launch")
                } catch is CancellationError {
                    suite.expect(!FileManager.default.fileExists(atPath: marker.path), "cancelled script makes no changes")
                }
            } catch { suite.expect(false, "script fixture failed: \(error)") }
        }
    }
}
