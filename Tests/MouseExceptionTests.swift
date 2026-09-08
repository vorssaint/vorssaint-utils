// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MouseExceptionTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Mouse app exceptions (issue #358)

        expect(MouseExceptionScope.allCases.allSatisfy {
                    (Defaults.registeredDefaults[$0.defaultsKey] as? [String])?.isEmpty == true
               },
               "every feature's exception list registers empty, so they all start out working everywhere")
        expect(Set(MouseExceptionScope.allCases.map(\.defaultsKey)).count == MouseExceptionScope.allCases.count,
               "each feature keeps its own list, never a key shared with another")
        expect(MouseExceptionScope.smoothScroll.feature == .smoothScroll
                && MouseExceptionScope.scrollDirection.feature == .scrollInverter
                && MouseExceptionScope.focusFollowsMouse.feature == .focusFollowsMouse
                && MouseExceptionScope.navigation.feature == .mouseNavigation
                && MouseExceptionScope.buttonShortcuts.feature == .mouseButtonShortcuts
                && MouseExceptionScope.middleClick.feature == .middleClick
                && MouseExceptionScope.superKey.feature == .superKey,
               "each list knows the feature that owns it, so it hides with that feature")
        expect(MouseExceptionScope.allCases.allSatisfy { $0.feature.group == .mouseKeyboard },
               "every exception list belongs to a mouse-and-keyboard feature")
        expect(Defaults.sanitizedBundleIdentifierList(["  com.example.a  ", "", "com.example.a", "com.example.b"])
                == ["com.example.a", "com.example.b"],
               "the exception list drops blanks, spaces and repeats")

        let exceptionSet: Set<String> = ["com.example.modeler"]
        expect(MouseAppExceptionSupport.isExcepted("com.example.modeler", exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted("com.example.other", exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted(nil, exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted("com.example.modeler", exceptions: []),
               "an app is excepted only when its identifier is on a list that has entries")
        expect(MouseAppExceptionSupport.isExcepted(["com.example.modeler"],
                                                    exceptions: exceptionSet)
                && MouseAppExceptionSupport.isExcepted(
                    ["com.example.helper", "com.example.modeler"],
                    exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted(["com.example.other"],
                                                         exceptions: exceptionSet),
               "a source app or one of its bundled helpers can carry an exception")
        // A program started from a launcher — the Java process behind a game
        // is the reported one — has no bundle identifier at all, so the file
        // being run stands in as its identity (issue #1009). An app that has
        // an identifier keeps answering only to that, so nothing already
        // listed changes meaning.
        expect(MouseAppExceptionSupport.identity(bundleID: "com.example.modeler",
                                                 executablePath: "/Applications/Modeler.app/Contents/MacOS/Modeler")
                == "com.example.modeler",
               "an app with a bundle identifier answers to it and not to its executable")
        expect(MouseAppExceptionSupport.identity(bundleID: nil,
                                                 executablePath: "/opt/game/runtime/bin/java")
                == "/opt/game/runtime/bin/java",
               "a program with no bundle identifier answers to the file being run")
        expect(MouseAppExceptionSupport.identity(bundleID: nil, executablePath: nil) == nil
                && MouseAppExceptionSupport.identity(bundleID: nil, executablePath: "java") == nil,
               "a program with nothing to be named by is never excepted by accident")
        expect(MouseAppExceptionSupport.isExecutablePathIdentity("/opt/game/runtime/bin/java")
                && !MouseAppExceptionSupport.isExecutablePathIdentity("com.example.modeler"),
               "a stored path is told from a bundle identifier by its leading slash")
        expect(MouseAppExceptionSupport.isExcepted(
                   MouseAppExceptionSupport.identity(bundleID: nil,
                                                     executablePath: "/opt/game/runtime/bin/java"),
                   exceptions: ["/opt/game/runtime/bin/java"])
                && !MouseAppExceptionSupport.isExcepted(
                    MouseAppExceptionSupport.identity(bundleID: nil,
                                                      executablePath: "/opt/other/bin/java"),
                    exceptions: ["/opt/game/runtime/bin/java"]),
               "a listed program path excepts that program and no other")
        expect(InstalledApps.name(for: "/opt/game/runtime/bin/java") == "java",
               "a listed program path is shown by its file name, not the whole path")

        // The stored path is the one the file sheet handed back and the
        // matched one is the file the running program reports, and the same
        // file arrives at the two ends under different names as soon as
        // anything on the way is a link — measured on this Mac, the sheet
        // answers /private/tmp/… for a file the running program answers
        // /tmp/… for. Both ends resolve, so they meet.
        let identityRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-identity-\(getpid())", isDirectory: true)
        let runtimeBinary = identityRoot.appendingPathComponent("runtime/bin/launcher")
        try? FileManager.default.createDirectory(at: runtimeBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runtimeBinary.path, contents: Data())
        let linkedBinary = identityRoot.appendingPathComponent("launcher")
        try? FileManager.default.createSymbolicLink(at: linkedBinary, withDestinationURL: runtimeBinary)
        let pickedThroughLink = MouseAppExceptionSupport.executablePathIdentity(linkedBinary.path)
        let reportedByTheSystem = MouseAppExceptionSupport.identity(bundleID: nil,
                                                                    executablePath: runtimeBinary.path)
        expect(pickedThroughLink != nil
                && pickedThroughLink != linkedBinary.path
                && pickedThroughLink == reportedByTheSystem,
               "a program picked through a link stores the file it links to")
        expect(MouseAppExceptionSupport.isExcepted(reportedByTheSystem,
                                                   exceptions: Set([pickedThroughLink].compactMap { $0 })),
               "the program the system reports matches the entry the picker stored")

        // A file sheet that takes programs can be walked into a bundle, and
        // what is stored has to be what the system will report once the file
        // runs. Measured on this Mac: a bundle's own executable run straight
        // from disk is reported as com.example.withid, while a runtime shipped
        // deeper in that same bundle — the shape issue #1009 is about — is
        // reported with no identifier and stays a path. Filing that runtime
        // under the app above it would break the case this all exists for.
        func makeTestBundle(_ name: String, identifier: String?) -> URL {
            let bundle = identityRoot.appendingPathComponent("\(name).app")
            for file in ["Contents/MacOS/\(name)", "Contents/runtime/bin/java"] {
                let url = bundle.appendingPathComponent(file)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            var info: [String: Any] = ["CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
            if let identifier { info["CFBundleIdentifier"] = identifier }
            if let plist = try? PropertyListSerialization.data(fromPropertyList: info,
                                                               format: .xml,
                                                               options: 0) {
                try? plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            }
            return bundle
        }
        let namedBundle = makeTestBundle("Modeler", identifier: "com.example.modeler")
        let namelessBundle = makeTestBundle("Bare", identifier: nil)
        expect(MouseAppExceptionSupport.pickedIdentity(for: namedBundle) == "com.example.modeler"
                && MouseAppExceptionSupport.pickedIdentity(
                    for: namedBundle.appendingPathComponent("Contents/MacOS/Modeler"))
                    == "com.example.modeler",
               "an app is stored by its identifier whether its bundle or the binary inside it was picked")
        let bundledRuntime = namedBundle.appendingPathComponent("Contents/runtime/bin/java")
        expect(MouseAppExceptionSupport.pickedIdentity(for: bundledRuntime)
                == MouseAppExceptionSupport.executablePathIdentity(bundledRuntime.path),
               "a runtime shipped inside an app keeps its own path, never the identifier of the app above it")
        expect(MouseAppExceptionSupport.pickedIdentity(for: namelessBundle)
                == MouseAppExceptionSupport.executablePathIdentity(
                    namelessBundle.appendingPathComponent("Contents/MacOS/Bare").path),
               "an app whose Info.plist names no identifier is stored by the binary it runs")
        expect(MouseAppExceptionSupport.pickedIdentity(for: runtimeBinary)
                == MouseAppExceptionSupport.executablePathIdentity(runtimeBinary.path),
               "a program that is not packaged as an app is stored by its own file")
        try? FileManager.default.removeItem(at: identityRoot)

        // The list sanitizer runs over stored entries, and a file name may
        // legally end in a space: trimming a path would look for a spelling
        // the running program never reports, so only an identifier is trimmed.
        expect(Defaults.sanitizedBundleIdentifierList(["/opt/game/bin/java ", " com.example.a "])
                == ["/opt/game/bin/java ", "com.example.a"],
               "a stored path keeps its exact file name while an identifier is trimmed")

        expect(InstalledApps.location(for: "com.example.modeler") == nil,
               "a bundle identifier names its app on its own and carries no location")
        expect(InstalledApps.location(for: NSHomeDirectory() + "/runtimes/zulu-8.jre/bin/java")
                == "~/runtimes/zulu-8.jre/bin",
               "a path identity is located by its directory, spelled from home")
        expect(InstalledApps.location(for: "/opt/game/bin/java") == "/opt/game/bin",
               "a path outside home keeps its absolute directory")

        // Running programs that are not packaged as apps (issue #865): a bare
        // executable run under .regular activation policy (e.g. a game
        // launcher's runtime process) answers to its resolved file path when it
        // has no bundle identifier, while an ordinary .app bundle keeps its
        // bundle row and background/accessory processes stay excluded.
        let runningTestRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-running-\(getpid())", isDirectory: true)
        let runningTargetBinary = runningTestRoot.appendingPathComponent("bin/java")
        let runningSymlinkBinary = runningTestRoot.appendingPathComponent("bin/java_link")
        try? FileManager.default.createDirectory(at: runningTargetBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runningTargetBinary.path, contents: Data())
        try? FileManager.default.createSymbolicLink(at: runningSymlinkBinary, withDestinationURL: runningTargetBinary)
        let resolvedRunningPath = MouseAppExceptionSupport.executablePathIdentity(runningTargetBinary.path)

        let regularBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: runningSymlinkBinary,
            executableURL: runningSymlinkBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        if let regularBareApp, let resolvedRunningPath {
            expect(regularBareApp.identity == resolvedRunningPath
                    && regularBareApp.bundleID == nil
                    && regularBareApp.name == "java"
                    && regularBareApp.url.path == resolvedRunningPath,
                   "a running regular bare executable produces a path row with its resolved path identity")
        } else {
            expect(false, "a running regular bare executable resolves its path row setup")
        }

        let runningWrapper = runningTestRoot.appendingPathComponent("zulu-8.jre", isDirectory: true)
        let runningWrapperBinary = runningWrapper.appendingPathComponent("bin/java")
        try? FileManager.default.createDirectory(at: runningWrapperBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runningWrapperBinary.path, contents: Data())
        let wrapperBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: runningWrapper,
            executableURL: runningWrapperBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        let resolvedWrapperPath = MouseAppExceptionSupport.executablePathIdentity(runningWrapperBinary.path)
        if let wrapperBareApp, let resolvedWrapperPath {
            expect(wrapperBareApp.identity == resolvedWrapperPath
                    && wrapperBareApp.bundleID == nil
                    && wrapperBareApp.url.path == resolvedWrapperPath,
                   "a running executable inside a non-app wrapper produces a path row")
        } else {
            expect(false, "a non-app wrapper executable resolves its path row setup")
        }

        let appBundleURL = URL(fileURLWithPath: "/Applications/TextEdit.app")
        let regularBundleApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: "com.apple.TextEdit",
            bundleURL: appBundleURL,
            executableURL: appBundleURL.appendingPathComponent("Contents/MacOS/TextEdit"),
            localizedName: "TextEdit",
            acceptsExecutables: true
        )
        expect(regularBundleApp != nil
                && regularBundleApp?.identity == "com.apple.TextEdit"
                && regularBundleApp?.bundleID == "com.apple.TextEdit"
                && regularBundleApp?.url == appBundleURL
                && regularBundleApp?.name == "TextEdit",
               "a running regular app bundle produces an unchanged bundle row")

        let accessoryBareApp = InstalledApps.runningApplication(
            activationPolicy: .accessory,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        let prohibitedBareApp = InstalledApps.runningApplication(
            activationPolicy: .prohibited,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        expect(accessoryBareApp == nil && prohibitedBareApp == nil,
               "an accessory or prohibited bare executable is ignored")

        let embeddedBundleBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: "com.example.embedded",
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "embedded_tool",
            acceptsExecutables: true
        )
        expect(embeddedBundleBareApp != nil
                && embeddedBundleBareApp?.identity == "com.example.embedded"
                && embeddedBundleBareApp?.bundleID == "com.example.embedded"
                && embeddedBundleBareApp?.identity != runningTargetBinary.path,
               "a bare executable that reports a bundle identifier uses that identifier and not its path")

        let duplicateProcessApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        if let regularBareApp, let duplicateProcessApp, let resolvedRunningPath {
            let deduplicated = InstalledApps.deduplicatedAndFiltered(
                [regularBareApp, duplicateProcessApp],
                excluding: []
            )
            expect(deduplicated.count == 1
                    && deduplicated.first?.identity == resolvedRunningPath,
                   "duplicate processes with the same path identity collapse to one entry")

            let excludedPathApps = InstalledApps.deduplicatedAndFiltered(
                [regularBareApp],
                excluding: [resolvedRunningPath]
            )
            let unexcludedPathApps = InstalledApps.deduplicatedAndFiltered(
                [regularBareApp],
                excluding: ["/other/path/java"]
            )
            expect(excludedPathApps.isEmpty && unexcludedPathApps.count == 1,
                   "an exclusion set containing a path identity drops that program")
        } else {
            expect(false, "running path identities resolve before they are deduplicated or excluded")
        }

        let reverseJavaApps = InstalledApps.deduplicatedAndFiltered([
            InstalledApps.InstalledApp(id: "/runtimes/zulu/bin/java",
                                       name: "java",
                                       bundleID: nil,
                                       url: URL(fileURLWithPath: "/runtimes/zulu/bin/java"),
                                       isSystem: false,
                                       explicitIdentity: "/runtimes/zulu/bin/java"),
            InstalledApps.InstalledApp(id: "/runtimes/temurin/bin/java",
                                       name: "java",
                                       bundleID: nil,
                                       url: URL(fileURLWithPath: "/runtimes/temurin/bin/java"),
                                       isSystem: false,
                                       explicitIdentity: "/runtimes/temurin/bin/java")
        ], excluding: [])
        expect(reverseJavaApps.compactMap(\.identity) == ["/runtimes/temurin/bin/java", "/runtimes/zulu/bin/java"],
               "same-named executable rows sort by identity")

        let unacceptedBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: false
        )
        expect(unacceptedBareApp == nil,
               "a bare executable is omitted when the caller does not accept executables")

        let emptyIdentifierBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: "",
            bundleURL: runningSymlinkBinary,
            executableURL: runningSymlinkBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        expect(emptyIdentifierBareApp == nil,
               "an empty bundle identifier is dropped, as the taps would never match it")

        try? FileManager.default.removeItem(at: runningTestRoot)

        // Both ends of that agreement live outside this binary: the picker
        // stores from AppBundleList and the taps match from MouseAppExceptions.
        // An identity resolved at one end and taken raw at the other silently
        // matches nothing (issue #1009), so what each side may hand on is
        // pinned rather than the spelling it happens to use today — a second
        // way into the list, dropping a file onto it among them, has to go
        // through the same resolver as the sheet does.
        let pickerLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/AppBundleList.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        var resolvedAddSites: [String] = []
        var rawAddSites: [String] = []
        for (index, line) in pickerLines.enumerated()
        where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") && line.contains("onAdd(") {
            let added = (line.components(separatedBy: "onAdd(").last?
                .components(separatedBy: ")").first ?? "").trimmingCharacters(in: .whitespaces)
            let nearbyLines = pickerLines[..<index].suffix(4)
            if nearbyLines.contains(where: {
                $0.contains("let \(added) =") && $0.contains("MouseAppExceptionSupport.")
            }) {
                resolvedAddSites.append("AppBundleList.swift:\(index + 1)")
            } else {
                rawAddSites.append("AppBundleList.swift:\(index + 1) adds \(added)")
            }
        }
        expect(!resolvedAddSites.isEmpty && rawAddSites.isEmpty,
               "every value the picker adds is one the support enum resolved: \(rawAddSites)")

        // A list row's location caption is what tells path identities apart —
        // every bundled runtime displays as "java" (issue #1009) — and sibling
        // runtimes differ only after a long shared directory prefix, so the
        // caption must truncate from the HEAD: cutting the middle or tail
        // would hide the one component that differs. Neither picker is
        // compiled into this binary, so their shapes are pinned here.
        let appPickerLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Uninstall/AppPickerView.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let captionPickerLines = ["AppBundleList.swift": pickerLines,
                                  "AppPickerView.swift": appPickerLines]
        var captionFiles: [String] = []
        for (file, lines) in captionPickerLines {
            let sourceLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            if sourceLines.contains(where: { $0.contains("InstalledApps.location(for:") })
                && sourceLines.contains(where: { $0.contains(".truncationMode(") && $0.contains(".head") }) {
                captionFiles.append(file)
            }
        }
        expect(captionFiles.count == captionPickerLines.count,
               "each path identity picker shows where its file sits and truncates from the head: "
                   + "\(captionFiles)")

        var resolvedMatchSites: [String] = []
        var rawMatchSites: [String] = []
        let matcherLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/MouseExceptions/MouseAppExceptions.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        for (index, line) in matcherLines.enumerated()
        where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && line.contains("executableURL") && line.contains(".path") {
            if line.contains("MouseAppExceptionSupport.identity(")
                || (index > 0 && matcherLines[index - 1].contains("MouseAppExceptionSupport.identity(")) {
                resolvedMatchSites.append("MouseAppExceptions.swift:\(index + 1)")
            } else {
                rawMatchSites.append("MouseAppExceptions.swift:\(index + 1)")
            }
        }
        expect(resolvedMatchSites.count == 1 && rawMatchSites.isEmpty,
               "the taps read an executable path only through the support enum: "
                   + "\(resolvedMatchSites) \(rawMatchSites)")
        let matcherBody = matcherLines
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!matcherBody.isEmpty && !matcherBody.contains("trimmingCharacters"),
               "the exception list is sanitized through the one sanitizer, never beside it")

        // The leading-slash test IS the rule that tells a stored path from a
        // bundle identifier. A second spelling of it drifts the day the rule
        // learns a new shape — a ~ path, a file URL — so every file that
        // handles an identity asks isExecutablePathIdentity instead of
        // re-testing the prefix.
        var slashRuleSites: [String] = []
        for file in ["Services/MouseExceptions/MouseAppExceptionSupport.swift",
                     "Services/InstalledApps.swift",
                     "Core/Defaults.swift"] {
            let ruleLines = ((try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                          encoding: .utf8)) ?? "").components(separatedBy: "\n")
            if ruleLines.count <= 1 { slashRuleSites.append("\(file) unreadable") }
            for (index, line) in ruleLines.enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                    && line.contains("hasPrefix(\"/\")") {
                slashRuleSites.append("\(file):\(index + 1)")
            }
        }
        expect(slashRuleSites.count == 1
                && slashRuleSites[0].hasPrefix("Services/MouseExceptions/MouseAppExceptionSupport.swift:"),
               "the leading-slash rule is spelled once, inside isExecutablePathIdentity: \(slashRuleSites)")
        expect(MouseAppExceptionSupport.sourceProcessID(42) == 42
                && MouseAppExceptionSupport.sourceProcessID(0) == nil
                && MouseAppExceptionSupport.sourceProcessID(-1) == nil
                && MouseAppExceptionSupport.sourceProcessID(Int64(Int32.max) + 1) == nil,
               "only positive process ids supported by the workspace enter source tracking")

        let pointer = CGPoint(x: 100, y: 100)
        let ownWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, processID: 9)
        let systemWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 25, processID: 3)
        let hiddenWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, alpha: 0, processID: 4)
        let frontWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 50, y: 50, width: 300, height: 300), layer: 0, processID: 5)
        let panelWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 60, y: 60, width: 100, height: 100), layer: 3, processID: 6)
        let behindWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, processID: 7)
        let underlayWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: -2_147_483_601, processID: 8)
        expect(MouseAppExceptionSupport.pointerWindow(
                in: [ownWindow, systemWindow, hiddenWindow, frontWindow, behindWindow],
                at: pointer, ownProcessID: 9) == frontWindow,
               "the pointer's window is the frontmost real window under it")
        expect(MouseAppExceptionSupport.pointerWindow(
                in: [underlayWindow], at: pointer, ownProcessID: 9) == nil,
               "a window living below every real one never answers for the pointer")
        expect(MouseAppExceptionSupport.pointerWindow(
                in: [panelWindow, frontWindow], at: pointer, ownProcessID: 9) == panelWindow,
               "an app's floating panel answers for its app")
        expect(MouseAppExceptionSupport.pointerWindow(
                in: [frontWindow], at: CGPoint(x: 380, y: 380), ownProcessID: 9) == nil,
               "a pointer outside every window resolves to nothing")

        expect(MouseAppExceptionSupport.cacheHolds(region: frontWindow.frame, resolvedPoint: pointer,
                                                   resolvedAt: 10, point: CGPoint(x: 120, y: 120), now: 10.2),
               "a fresh answer keeps serving while the pointer stays inside its window")
        expect(!MouseAppExceptionSupport.cacheHolds(region: frontWindow.frame, resolvedPoint: pointer,
                                                    resolvedAt: 10, point: CGPoint(x: 380, y: 380), now: 10.2),
               "the pointer leaving the window asks the window server again")
        expect(!MouseAppExceptionSupport.cacheHolds(region: frontWindow.frame, resolvedPoint: pointer,
                                                    resolvedAt: 10, point: pointer,
                                                    now: 10 + MouseAppExceptionSupport.resolveLifetime),
               "an answer expires, so a window that opened under a resting pointer is noticed")
        expect(MouseAppExceptionSupport.cacheHolds(region: nil, resolvedPoint: pointer,
                                                   resolvedAt: 10, point: pointer, now: 10.2)
                && !MouseAppExceptionSupport.cacheHolds(region: nil, resolvedPoint: pointer,
                                                        resolvedAt: 10,
                                                        point: CGPoint(x: 101, y: 100), now: 10.2),
               "an answer of nothing only covers the exact spot it was resolved at")
        expect(MouseAppExceptionSupport.cacheNamesWindow(region: frontWindow.frame, point: pointer)
                && !MouseAppExceptionSupport.cacheNamesWindow(region: frontWindow.frame,
                                                              point: CGPoint(x: 380, y: 380))
                && !MouseAppExceptionSupport.cacheNamesWindow(region: nil, point: pointer),
               "an expired answer still names its own window, and no other")

        // Hold the main queue while a real pointer lookup runs elsewhere. A
        // synchronous hop would miss the deadline even with a cold cache.
        // Volatile preferences keep this fixture out of the user's settings.
        do {
            let defaults = UserDefaults.standard
            let savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            var arguments = savedArguments
            for scope in MouseExceptionScope.allCases {
                arguments[scope.defaultsKey] = ["com.example.mouse-exception-test"]
            }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let exceptions = MouseAppExceptions.shared
            exceptions.reload()
            defer {
                defaults.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
            }

            func queryWithoutMain(_ label: String) {
                let finished = DispatchGroup()
                finished.enter()
                Thread {
                    for index in 0..<100 {
                        let point = CGPoint(x: -10_000 - index, y: -10_000)
                        for scope in [MouseExceptionScope.middleClick, .scrollDirection] {
                            _ = exceptions.excludesPointerTarget(scope, at: point)
                        }
                    }
                    finished.leave()
                }.start()
                expect(finished.wait(timeout: .now() + 0.5) == .success,
                       "\(label) pointer lookups return while the main queue is held")
                // Drain both the refresh and a failed synchronous lookup so
                // a regression fails an assertion rather than wedging tests.
                var drained = false
                DispatchQueue.main.async { drained = true }
                let deadline = Date().addingTimeInterval(5)
                while (!drained || finished.wait(timeout: .now()) != .success),
                      Date() < deadline {
                    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                expect(drained && finished.wait(timeout: .now()) == .success,
                       "pointer lookups and the queued refresh finish once main is available")
            }

            /// The verdict a tap gets while the app under the pointer has not
            /// been resolved yet.
            func verdictWithoutMain(_ point: CGPoint) -> Bool {
                var verdict = false
                let answered = DispatchGroup()
                answered.enter()
                Thread {
                    verdict = exceptions.excludesPointerTarget(.middleClick, at: point)
                    answered.leave()
                }.start()
                let deadline = Date().addingTimeInterval(5)
                while answered.wait(timeout: .now()) != .success, Date() < deadline {
                    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                return verdict
            }

            queryWithoutMain("cold-cache")
            queryWithoutMain("changed-window")
            Thread.sleep(forTimeInterval: MouseAppExceptionSupport.resolveLifetime)
            queryWithoutMain("expired-cache")
            expect(verdictWithoutMain(CGPoint(x: -20_000, y: -20_000)),
                   "an app that cannot be told apart from a listed one keeps the feature's hands off")
            for scope in MouseExceptionScope.allCases { arguments[scope.defaultsKey] = [String]() }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            exceptions.reload()
            queryWithoutMain("empty-list")
            expect(!verdictWithoutMain(CGPoint(x: -20_010, y: -20_010)),
                   "an empty list stands nothing down")
        }

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.mouseExceptions(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty },
                   "every mouse exception string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible mouse exception strings (\(language.rawValue))")
            expect(Set(MouseExceptionScope.allCases.map { strings.caption(for: $0) }).count
                    == MouseExceptionScope.allCases.count,
                   "each list explains its own feature, never the same line twice (\(language.rawValue))")
        }

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.clipboardIgnoredApps(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 4 && values.allSatisfy { !$0.isEmpty },
                   "every clipboard skip list string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible clipboard skip list strings (\(language.rawValue))")
        }

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.switcherAppRules(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 8 && values.allSatisfy { !$0.isEmpty },
                   "every per-app switcher rule string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in per-app switcher rule strings (\(language.rawValue))")
            expect(Set([strings.showWithoutWindows, strings.windowsOnly, strings.hidden]).count == 3,
                   "each per-app switcher choice is distinct for \(language.rawValue)")
        }

        expect(FinderRenameSupport.acceptsFocusedRole("AXOutline")
                && !FinderRenameSupport.acceptsFocusedRole("AXTextField")
                && !FinderRenameSupport.acceptsFocusedRole("AXTextArea")
                && !FinderRenameSupport.acceptsFocusedRole(nil),
               "Finder rename only acts outside editable fields with a known focus")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.windowPreviewExclusions(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 5 && values.allSatisfy { !$0.isEmpty },
                   "every window preview exclusion string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible window preview exclusion strings (\(language.rawValue))")
        }

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.diskExclusions(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 6 && values.allSatisfy { !$0.isEmpty },
                   "every disk exclusion string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible disk exclusion strings (\(language.rawValue))")
        }

        for language in AppLanguage.allCases {
            let strings = WindowDirectionalStrings.localized(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 2 && values.allSatisfy { !$0.isEmpty },
                   "every directional layout string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in directional layout strings (\(language.rawValue))")
        }
    }
}
