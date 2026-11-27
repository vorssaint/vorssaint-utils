// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderNewFileTests {
    static func run(_ suite: TestSuite) {
        let extensionID = "com.vorssaint.utils.dev.finder-new-file"
        func ignored(_ output: String) -> Bool {
            FinderNewFileExtensionElection.isIgnored(output, identifier: extensionID)
        }
        suite.expect(ignored("-    \(extensionID)(1.0)\tUUID\t/path\n (1 plug-in)"),
                     "the exact extension has an ignore election")
        suite.expect(!ignored("+    \(extensionID)(1.0)\n (1 plug-in)")
                     && !ignored("?    \(extensionID)(1.0)\n (1 plug-in)")
                     && !ignored("     \(extensionID)(1.0)\n (1 plug-in)"),
                     "enabled, unknown and unmarked elections cannot confirm a reset")
        suite.expect(ignored("-    \(extensionID)(1.0)\n=    \(extensionID)(0.9)\n (2 plug-ins)")
                     && !ignored("-    \(extensionID)(1.0)\n+    \(extensionID)(0.9)\n (2 plug-ins)"),
                     "superseded copies are harmless but enabled copies are not")
        suite.expect(ignored(" (0 plug-ins)") && ignored("")
                     && !ignored("unexpected response")
                     && !ignored("-    com.vorssaint.utils.finder-new-file(1.0)\n (1 plug-in)"),
                     "only a successful empty or exact-identifier query confirms no active extension")

        suite.expect(FinderNewFileKind.selection(nil) == FinderNewFileKind.defaultKinds,
                     "new file defaults include Office formats")
        suite.expect(FinderNewFileKind.selection("xlsx,unknown,txt,txt") == [.text, .excel],
                     "file choices are sanitized and stable")
        suite.expect(FinderNewFileKind.selection("").isEmpty, "no selected file types stays empty")
        suite.expect(FinderNewFileStrings.supportedCodes == Set(AppLanguage.allCases.map(\.rawValue)),
                     "Finder new file supports every app language")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.finderNewFile(language)
            suite.expect(strings.title == FinderNewFileStrings.localized(language.rawValue).title,
                         "host and extension share the same Finder menu title: \(language)")
            suite.expect(!strings.title.isEmpty && !strings.description.isEmpty
                         && !strings.enable.isEmpty && !strings.page.isEmpty && !strings.text.isEmpty
                         && !strings.cancel.isEmpty && !strings.manage.isEmpty && !strings.error.isEmpty
                         && !strings.extensionName.isEmpty && !strings.extensionEnabled.isEmpty
                         && !strings.extensionDisabled.isEmpty && !strings.extensionHelp.isEmpty
                         && strings.extensionEnabled != strings.extensionDisabled
                         && !strings.customTitle.isEmpty && !strings.addItem.isEmpty
                         && !strings.menuName.isEmpty && !strings.fileName.isEmpty && !strings.suffixLabel.isEmpty
                         && !strings.templateLabel.isEmpty && !strings.emptyTemplate.isEmpty
                         && !strings.templateHelp.isEmpty && !strings.invalidItem.isEmpty && !strings.defaultContent.isEmpty,
                         "localized Finder labels are complete: \(language)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-new-file-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = try FinderNewFileCreator.create(.text, in: directory, templates: nil)
            try Data("keep".utf8).write(to: first)
            let second = try FinderNewFileCreator.create(.text, in: directory, templates: nil)
            suite.expect(first.lastPathComponent == "Untitled.txt"
                         && second.lastPathComponent == "Untitled 2.txt",
                         "repeated creation gets a unique filename")
            suite.expect(try Data(contentsOf: first) == Data("keep".utf8), "existing content is preserved")
            suite.expect(try Data(contentsOf: second).isEmpty, "new text is empty")
            let json = try FinderNewFileCreator.create(.json, in: directory, templates: nil)
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: json))
            suite.expect((value as? [String: Any])?.isEmpty == true, "JSON starts as a valid empty object")

            let templates = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/FinderNewFileTemplates", isDirectory: true)
            for kind in FinderNewFileKind.allCases where kind.usesTemplate {
                let file = try FinderNewFileCreator.create(kind, in: directory, templates: templates)
                let source = try Data(contentsOf: templates.appendingPathComponent("Blank.\(kind.rawValue)"))
                let actual = try Data(contentsOf: file)
                suite.expect(!source.isEmpty && actual == source, "template copied without alteration: \(kind)")
            }
            do {
                _ = try FinderNewFileCreator.create(.excel, in: directory, templates: nil)
                suite.expect(false, "missing document template must not create an empty Office file")
            } catch {
                suite.expect(true, "missing document template rejected")
            }
            var custom = FinderNewFileItem(title: "Python", filename: "main", suffix: ".py")
            guard let normalized = custom.normalized else {
                suite.expect(false, "valid custom item"); return
            }
            custom = normalized
            let customFirst = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: nil)
            let customSecond = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: nil)
            suite.expect(customFirst.lastPathComponent == "main.py" && customSecond.lastPathComponent == "main 2.py",
                         "custom filename and suffix use exclusive numbered creation")
            suite.expect(try Data(contentsOf: customFirst).isEmpty, "custom blank file is empty")
            var noSuffix = custom
            noSuffix.filename = ".env"
            noSuffix.suffix = ""
            let hidden = try FinderNewFileCreator.create(noSuffix, in: directory, templateDirectory: nil)
            suite.expect(hidden.lastPathComponent == ".env", "extensionless hidden filename supported")
            var compound = custom
            compound.filename = "config"
            compound.suffix = "local.json"
            let compoundFile = try FinderNewFileCreator.create(compound, in: directory, templateDirectory: nil)
            suite.expect(compoundFile.lastPathComponent == "config.local.json", "compound suffix supported")
            let migrated = FinderNewFileItem.items("", legacySelection: "txt",
                legacyCustom: FinderNewFileItem.encode([custom]))
            suite.expect(migrated.count == FinderNewFileKind.allCases.count + 1
                         && migrated.filter(\.isEnabled).map(\.id) == [FinderNewFileKind.text.itemID, custom.id],
                         "legacy configuration migrates built-ins and custom entries")
            var edited = migrated.first { $0.builtIn == .word }!
            edited.filename = "Report"
            edited.enabled = true
            let ordered = [custom, edited] + migrated.filter { $0.id != custom.id && $0.id != edited.id }
            let movedDown = FinderNewFileItem.reordered(ordered, moving: custom.id, to: edited.id)
            suite.expect(movedDown.map(\.id) == [edited.id, custom.id] + ordered.dropFirst(2).map(\.id),
                         "dragging a custom entry down across a built-in preserves identities")
            let movedUp = FinderNewFileItem.reordered(movedDown, moving: custom.id, to: edited.id)
            suite.expect(movedUp == ordered, "dragging upward restores the original mixed order")
            suite.expect(FinderNewFileItem.reordered(ordered, moving: custom.id, to: custom.id) == ordered,
                         "dropping onto itself does not change order")
            suite.expect(FinderNewFileItem.reordered(ordered, moving: UUID(), to: edited.id) == ordered,
                         "unknown drag source is ignored")
            let restored = FinderNewFileItem.items(FinderNewFileItem.encode(ordered))
            suite.expect(restored.map(\.id) == ordered.map(\.id), "mixed order survives persistence")
            suite.expect(restored[1].filename == "Report" && !restored[1].canDelete,
                         "built-in edits preserve identity")
            suite.expect(FinderNewFileItem.items(FinderNewFileItem.encode([custom])).count == migrated.count,
                         "missing built-in entries restored")
            let strings = FinderNewFileStrings.localized("en-US")
            let snapshot = FinderNewFileSnapshot(enabled: true, language: "en-US",
                entries: restored.filter(\.isEnabled).map { $0.menuItem(strings) })
            let snapshotData = try JSONEncoder().encode(snapshot)
            suite.expect(!String(decoding: snapshotData, as: UTF8.self).contains("filename"),
                         "extension snapshot contains presentation fields only")
            suite.expect(snapshot.entries.first?.id == custom.id, "Finder receives the same mixed order")
            let report = try FinderNewFileCreator.create(edited, in: directory, templateDirectory: nil,
                                                        bundledTemplates: templates)
            let reportContents = try Data(contentsOf: report)
            let originalContents = try Data(contentsOf: templates.appendingPathComponent("Blank.docx"))
            suite.expect(report.lastPathComponent == "Report.docx" && reportContents == originalContents,
                         "renaming a built-in retains its bundled template")
            var disabled = restored[0]
            disabled.enabled = false
            let switched = FinderNewFileItem.items(FinderNewFileItem.encode([disabled] + Array(restored.dropFirst())))
            suite.expect(!switched[0].isEnabled && switched.map(\.id) == restored.map(\.id),
                         "disabling a custom entry preserves its position")
            var emptyBuiltIn = edited
            emptyBuiltIn.useBuiltInContent = false
            emptyBuiltIn.filename = "Empty"
            let empty = try FinderNewFileCreator.create(emptyBuiltIn, in: directory, templateDirectory: nil)
            suite.expect(try Data(contentsOf: empty).isEmpty, "built-in content can be explicitly replaced with empty content")
            var invalid = custom
            invalid.filename = "../outside"
            suite.expect(invalid.normalized == nil, "reject path traversal in custom filename")
            invalid = custom
            invalid.suffix = "/txt"
            suite.expect(invalid.normalized == nil, "reject path separators in custom suffix")
            suite.expect(FinderNewFileItem.items(FinderNewFileItem.encode([custom, custom, invalid])).filter(\.canDelete) == [custom],
                         "custom settings round trip and reject duplicate/invalid entries")
            let customRequest = FinderNewFileRequest(customID: custom.id, directory: directory)
            suite.expect(customRequest.url.flatMap { FinderNewFileRequest.decode($0) } == customRequest,
                         "custom request carries a registered item ID")
            let store = directory.appendingPathComponent("templates")
            let source = directory.appendingPathComponent("source.txt")
            let contents = Data("template contents".utf8)
            try contents.write(to: source)
            custom.template = try FinderNewFileTemplateStore.importFile(source, into: store, container: directory)
            try FileManager.default.removeItem(at: source)
            let copy = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: store)
            suite.expect(copy.lastPathComponent == "main 3.py",
                         "imported template uses configured name and suffix, not source.txt")
            suite.expect(try Data(contentsOf: copy) == contents, "imported template survives source removal")

            var defaultNamed = custom
            defaultNamed.filename = "Untitled"
            defaultNamed.suffix = "log"
            let defaultCopy = try FinderNewFileCreator.create(defaultNamed, in: directory, templateDirectory: store)
            suite.expect(defaultCopy.lastPathComponent == "Untitled.log",
                         "Untitled is a valid explicit filename with imported content")
            var extensionless = custom
            extensionless.filename = "Makefile"
            extensionless.suffix = ""
            let extensionlessCopy = try FinderNewFileCreator.create(extensionless, in: directory, templateDirectory: store)
            suite.expect(extensionlessCopy.lastPathComponent == "Makefile",
                         "template extension is not inherited by extensionless output")
            var builtInWithTemplate = edited
            builtInWithTemplate.filename = "Custom Report"
            builtInWithTemplate.template = custom.template
            let builtInCopy = try FinderNewFileCreator.create(builtInWithTemplate, in: directory,
                                                             templateDirectory: store, bundledTemplates: templates)
            suite.expect(builtInCopy.lastPathComponent == "Custom Report.docx",
                         "built-in entries also use configured names with imported templates")
            suite.expect(try Data(contentsOf: builtInCopy) == contents,
                         "imported content takes precedence over bundled content")
            FinderNewFileTemplateStore.remove(custom.template!, from: store)
            do {
                _ = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: store)
                suite.expect(false, "missing custom template must not silently create an empty file")
            } catch {
                suite.expect(true, "missing custom template rejected")
            }
            let request = FinderNewFileRequest(kind: .excel, directory: directory)
            if let url = request.url {
                suite.expect(FinderNewFileRequest.decode(url) == request, "creation request round trips")
                var oldRoute = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                oldRoute.host = "confirm"
                suite.expect(FinderNewFileRequest.decode(oldRoute.url!) == nil, "old confirmation route rejected")
                oldRoute.host = "queued"
                suite.expect(FinderNewFileRequest.decode(oldRoute.url!) == nil, "old queue route rejected")
                var invalid = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                invalid.queryItems?.append(URLQueryItem(name: "extra", value: "1"))
                suite.expect(FinderNewFileRequest.decode(invalid.url!) == nil, "unexpected URL fields rejected")
            } else {
                suite.expect(false, "creation URL encodes")
            }
            var replay = FinderNewFileReplayGuard()
            suite.expect(replay.accept(request), "fresh request accepted")
            suite.expect(!replay.accept(request), "duplicate request rejected")
            suite.expect(!replay.accept(FinderNewFileRequest(kind: .text, directory: directory,
                                                            createdAt: Date(timeIntervalSinceNow: -120))),
                         "expired requests rejected by replay guard")
            suite.expect(!FinderNewFileRequest(kind: .text, directory: directory,
                                                createdAt: Date(timeIntervalSinceNow: -120)).isValid(),
                         "expired request rejected")
            suite.expect(!FinderNewFileRequest.isLocalDirectoryURL(URL(string: "https://example.com")!),
                         "remote URL rejected")
        } catch {
            suite.expect(false, "new file fixture failed: \(error)")
        }
    }
}
