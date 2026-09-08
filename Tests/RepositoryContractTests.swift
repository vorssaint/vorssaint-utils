// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum RepositoryContractTests {
    static func runResources(expect: (Bool, String) -> Void) {
        let infoPlist = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        let bundleLocalizations = infoPlist?["CFBundleLocalizations"] as? [String] ?? []
        expect(bundleLocalizations.contains("tr"), "Info.plist declares Turkish as a bundle localization")
        expect(bundleLocalizations.contains("ko"), "Info.plist declares Korean as a bundle localization")
        let baseAudioPrompt = infoPlist?["NSAudioCaptureUsageDescription"] as? String ?? ""
        expect(baseAudioPrompt.contains("Vorssaint uses each app's audio"),
               "base audio permission prompt is an English fallback")
        let organizerFolderPromptKeys = [
            "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
            "NSNetworkVolumesUsageDescription", "NSRemovableVolumesUsageDescription",
        ]
        expect(organizerFolderPromptKeys.allSatisfy {
                   !(infoPlist?[$0] as? String ?? "").isEmpty
               },
               "the organizer declares every supported custom destination permission")
        let localizedInfoPlists = (try? FileManager.default.contentsOfDirectory(
            atPath: "Resources"))?.filter { $0.hasSuffix(".lproj") } ?? []
        expect(localizedInfoPlists.allSatisfy { folder in
            let value = (try? String(contentsOfFile: "Resources/\(folder)/InfoPlist.strings",
                                     encoding: .utf8)) ?? ""
            return organizerFolderPromptKeys.allSatisfy(value.contains)
        }, "every localization explains custom organizer folder access")
        // What the bundle says it speaks and what it ships have to be the same
        // list: a language declared without its folder makes the system offer
        // the app in it and then show every permission prompt in English.
        let shippedFolders = Set(localizedInfoPlists.map {
            $0.replacingOccurrences(of: ".lproj", with: "")
        })
        let declared = Set(bundleLocalizations).subtracting(["en"])
        expect(declared == shippedFolders,
               "the bundle ships a folder for every language it claims "
               + "(claimed only: \(declared.subtracting(shippedFolders).sorted()), "
               + "shipped only: \(shippedFolders.subtracting(declared).sorted()))")
        expect(bundleLocalizations.count == AppLanguage.allCases.count,
               "the bundle speaks exactly the languages the app does")
        // A symbol name that does not exist draws an empty box, and nobody
        // notices until someone opens that screen. Every name the app asks
        // for is resolved here instead.
        var missingSymbols: [String] = []
        var symbolNames: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for piece in text.components(separatedBy: "systemName: \"").dropFirst() {
                guard let end = piece.firstIndex(of: "\"") else { continue }
                let name = String(piece[piece.startIndex..<end])
                // Names built at run time are checked where they are built.
                if !name.isEmpty, !name.contains("\\") { symbolNames.insert(name) }
            }
        }
        expect(symbolNames.count > 80, "the symbol names were found (\(symbolNames.count))")
        for name in symbolNames.sorted()
        where NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            missingSymbols.append(name)
        }
        expect(missingSymbols.isEmpty,
               "every symbol the app draws exists (\(missingSymbols.joined(separator: ", ")))")
        // Same blind spot, other half: a file asked for by name is nil at run
        // time if it was renamed or dropped, and nothing says so until the
        // screen that needs it is opened.
        var namedResources: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for marker in ["url(forResource: \"", "path(forResource: \"", "NSImage(named: \""] {
                for piece in text.components(separatedBy: marker).dropFirst() {
                    guard let end = piece.firstIndex(of: "\"") else { continue }
                    let name = String(piece[piece.startIndex..<end])
                    if !name.isEmpty, !name.contains("\\") { namedResources.insert(name) }
                }
            }
        }
        expect(namedResources.count >= 5, "the named resources were found (\(namedResources.count))")
        var shippedNames: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Resources")) ?? [] {
            let file = (path as NSString).lastPathComponent
            shippedNames.insert((file as NSString).deletingPathExtension)
            shippedNames.insert(file)
        }
        // The brand images are drawn during the build and staged from there,
        // so the build script is where their names live.
        let stagingScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        expect(!stagingScript.isEmpty, "the build script reads back for its resource names")
        for word in stagingScript.components(separatedBy: CharacterSet(charactersIn: " \n\t\"'()")) {
            let file = (word as NSString).lastPathComponent
            guard !file.isEmpty else { continue }
            shippedNames.insert((file as NSString).deletingPathExtension)
            shippedNames.insert(file)
        }
        shippedNames.insert("CHANGELOG")
        let absentResources = namedResources.filter { !shippedNames.contains($0) }.sorted()
        expect(absentResources.isEmpty,
               "every file the app asks for by name is in the bundle (\(absentResources.joined(separator: ", ")))")
        // The scripts that drive the Finder are compiled when they run, so an
        // unbalanced block fails in silence exactly where it matters most:
        // these are the ones that delete files and empty the trash. The
        // one-line form, "tell application X to do something", closes itself
        // and is not counted as an opening.
        var unbalancedScripts: [String] = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for chunk in text.components(separatedBy: "\"\"\"").enumerated()
            where chunk.offset % 2 == 1 && chunk.element.contains("tell application") {
                let body = chunk.element.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                func opens(_ word: String, closing: String, inline: (String) -> Bool) -> Bool {
                    let started = body.filter { $0.hasPrefix(word + " ") && !inline($0) }.count
                    let ended = body.filter { $0 == closing }.count
                    return started != ended
                }
                let name = (path as NSString).lastPathComponent
                if opens("tell", closing: "end tell", inline: { $0.contains(" to ") }) {
                    unbalancedScripts.append("\(name):tell")
                }
                if opens("repeat", closing: "end repeat", inline: { _ in false }) {
                    unbalancedScripts.append("\(name):repeat")
                }
            }
        }
        expect(unbalancedScripts.isEmpty,
               "every embedded script closes what it opens (\(unbalancedScripts.joined(separator: ", ")))")
        // The command line tools the app shells out to. If macOS moves or drops
        // one, the feature that calls it fails without a word, so their absence
        // should fail here first. Framework paths are left out on purpose: they
        // are opened with dlopen and live in the shared cache, not on disk.
        var missingTools: [String] = []
        var toolPaths: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for piece in text.components(separatedBy: "\"/").dropFirst() {
                guard let end = piece.firstIndex(of: "\"") else { continue }
                let candidate = "/" + piece[piece.startIndex..<end]
                guard candidate.hasPrefix("/bin/") || candidate.hasPrefix("/usr/bin/")
                        || candidate.hasPrefix("/usr/sbin/") else { continue }
                guard !candidate.contains(" "), !candidate.contains("\\") else { continue }
                toolPaths.insert(candidate)
            }
        }
        expect(toolPaths.count >= 15, "the system tools were found (\(toolPaths.count))")
        for tool in toolPaths.sorted() where !FileManager.default.fileExists(atPath: tool) {
            missingTools.append(tool)
        }
        expect(missingTools.isEmpty,
               "every system tool the app runs is where it expects (\(missingTools.joined(separator: ", ")))")
        // The fan helper's launchd plist ships with the release identifier in
        // three places, and the Developer build rewrites each one so the two
        // apps can run side by side. A fourth mention added without a matching
        // rewrite would leave the Developer build asking launchd for a service
        // that is registered under the other name, and fan control would just
        // never answer.
        let helperTemplate = (try? String(
            contentsOfFile: "Resources/com.vorssaint.utils.fan-control.plist",
            encoding: .utf8)) ?? ""
        expect(!helperTemplate.isEmpty, "the helper template reads back")
        let releaseHelperID = "com.vorssaint.utils.fan-control"
        let mentions = helperTemplate.components(separatedBy: releaseHelperID).count - 1
        expect(mentions == 3,
               "the helper template names the release service exactly where the build rewrites it (\(mentions))")
        let buildText = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        for key in ["Set :Label $FAN_HELPER_ID",
                    "Set :BundleProgram Contents/Library/LaunchServices/$FAN_HELPER_ID",
                    "Delete :MachServices:" + releaseHelperID,
                    "Add :MachServices:$FAN_HELPER_ID"] {
            expect(buildText.contains(key), "the Developer build rewrites \(key)")
        }
        // Every shortcut the app ships with is written to disk as a string and
        // read back on the next launch. One that does not survive the trip
        // would leave that feature with no shortcut at all, on a fresh install,
        // with nothing to show for it.
        let defaultShortcuts: [(String, GlobalShortcut)] = [
            ("cameraPreviewDefault", GlobalShortcut.cameraPreviewDefault),
            ("clipboardDefault", GlobalShortcut.clipboardDefault),
            ("colorPickerDefault", GlobalShortcut.colorPickerDefault),
            ("commandBarDefault", GlobalShortcut.commandBarDefault),
            ("finderRenameDefault", GlobalShortcut.finderRenameDefault),
            ("keepAwakeDefault", GlobalShortcut.keepAwakeDefault),
            ("micMuteDefault", GlobalShortcut.micMuteDefault),
            ("pastePlainDefault", GlobalShortcut.pastePlainDefault),
            ("quickLauncherDefault", GlobalShortcut.quickLauncherDefault),
            ("radialMenuDefault", GlobalShortcut.radialMenuDefault),
            ("scratchpadDefault", GlobalShortcut.scratchpadDefault),
            ("screenOCRDefault", GlobalShortcut.screenOCRDefault),
            ("screenRecorderDefault", GlobalShortcut.screenRecorderDefault),
            ("screenshotClipboardDefault", GlobalShortcut.screenshotClipboardDefault),
            ("screenshotDefault", GlobalShortcut.screenshotDefault),
            ("screenshotFullScreenDefault", GlobalShortcut.screenshotFullScreenDefault),
            ("screenshotLastCaptureDefault", GlobalShortcut.screenshotLastCaptureDefault),
            ("shelfDefault", GlobalShortcut.shelfDefault),
            ("snippetLibraryDefault", GlobalShortcut.snippetLibraryDefault),
            ("soundOutputSwitcherDefault", GlobalShortcut.soundOutputSwitcherDefault),
            ("switcherDefault", GlobalShortcut.switcherDefault),
            ("switcherWindowDefault", GlobalShortcut.switcherWindowDefault),
            ("windowDirectionalDefault", GlobalShortcut.windowDirectionalDefault),
            ("windowLayoutBottomDefault", GlobalShortcut.windowLayoutBottomDefault),
            ("windowLayoutBottomLeftDefault", GlobalShortcut.windowLayoutBottomLeftDefault),
            ("windowLayoutBottomRightDefault", GlobalShortcut.windowLayoutBottomRightDefault),
            ("windowLayoutCenterDefault", GlobalShortcut.windowLayoutCenterDefault),
            ("windowLayoutCenterThirdDefault", GlobalShortcut.windowLayoutCenterThirdDefault),
            ("windowLayoutLeftDefault", GlobalShortcut.windowLayoutLeftDefault),
            ("windowLayoutLeftThirdDefault", GlobalShortcut.windowLayoutLeftThirdDefault),
            ("windowLayoutLeftTwoThirdsDefault", GlobalShortcut.windowLayoutLeftTwoThirdsDefault),
            ("windowLayoutMaximizeDefault", GlobalShortcut.windowLayoutMaximizeDefault),
            ("windowLayoutNextDisplayDefault", GlobalShortcut.windowLayoutNextDisplayDefault),
            ("windowLayoutRestoreDefault", GlobalShortcut.windowLayoutRestoreDefault),
            ("windowLayoutRightDefault", GlobalShortcut.windowLayoutRightDefault),
            ("windowLayoutRightThirdDefault", GlobalShortcut.windowLayoutRightThirdDefault),
            ("windowLayoutRightTwoThirdsDefault", GlobalShortcut.windowLayoutRightTwoThirdsDefault),
            ("windowLayoutTopDefault", GlobalShortcut.windowLayoutTopDefault),
            ("windowLayoutTopLeftDefault", GlobalShortcut.windowLayoutTopLeftDefault),
            ("windowLayoutTopRightDefault", GlobalShortcut.windowLayoutTopRightDefault),
        ]
        expect(defaultShortcuts.count == 40, "every default shortcut is in the round trip")
        var brokenShortcuts: [String] = []
        for (name, shortcut) in defaultShortcuts {
            guard let restored = GlobalShortcut(storageValue: shortcut.storageValue),
                  restored.storageValue == shortcut.storageValue else {
                brokenShortcuts.append(name)
                continue
            }
        }
        expect(brokenShortcuts.isEmpty,
               "a default shortcut survives being written and read back (\(brokenShortcuts.joined(separator: ", ")))")
        // A restored backup is filtered by valueLooksRight, so a setting whose
        // own registered default fails that filter would be dropped on import
        // and come back at its factory value with nothing said. The app's own
        // defaults are the one set guaranteed to be valid, so they are the
        // honest fixture for it.
        var rejectedByOwnFilter: [String] = []
        for key in SettingsBackupSupport.exportKeys().sorted() {
            guard let value = Defaults.registeredDefaults[key] else { continue }
            if !SettingsBackupSupport.valueLooksRight(key, value) {
                rejectedByOwnFilter.append(key)
            }
        }
        expect(rejectedByOwnFilter.isEmpty,
               "a restored backup keeps every setting the app itself ships (\(rejectedByOwnFilter.prefix(6).joined(separator: ", ")))")
        // The two services that hold files for the user delete only what they
        // put there themselves, and they check ownership again at the moment
        // of deletion. An unguarded removeItem added here would be the one bug
        // in this app that costs somebody a file, so it fails the suite first.
        var ungardedDeletes: [String] = []
        let ownershipGuards = ["isShelfOwnedFile", "discardablePaths", "ownedPayloadURLs",
                               "isRegularFile", "tempDir", "legacyDir", "root", "uuidString",
                               "storeRoot", "contentsOfDirectory"]
        for path in ["Sources/Vorssaint/Services/Shelf/ShelfService.swift",
                     "Sources/Vorssaint/Services/QuickTools/RecentCaptureService.swift",
                     "Sources/Vorssaint/Services/QuickTools/RecentCaptureStore.swift"] {
            let lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            expect(!lines.isEmpty, "the store source reads back for its deletion check")
            for (index, line) in lines.enumerated() where line.contains("removeItem(at:") {
                let scope = lines[max(0, index - 10)...index].joined(separator: "\n")
                if !ownershipGuards.contains(where: scope.contains) {
                    ungardedDeletes.append("\((path as NSString).lastPathComponent):\(index + 1)")
                }
            }
        }
        expect(ungardedDeletes.isEmpty,
               "a file is deleted only after the app checks it owns it (\(ungardedDeletes.joined(separator: ", ")))")
        let turkishInfoPlistStrings = (try? String(contentsOfFile: "Resources/tr.lproj/InfoPlist.strings",
                                                   encoding: .utf8)) ?? ""
        expect(turkishInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && turkishInfoPlistStrings.contains("Hiçbir şey kaydedilmez"),
               "Turkish InfoPlist.strings localizes the audio permission prompt")
        let koreanInfoPlistStrings = (try? String(contentsOfFile: "Resources/ko.lproj/InfoPlist.strings",
                                                  encoding: .utf8)) ?? ""
        expect(koreanInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && koreanInfoPlistStrings.contains("Mac 밖으로 나가지"),
               "Korean InfoPlist.strings localizes the audio permission prompt")
    }

    static func runDrawing(expect: (Bool, String) -> Void) {
        // Reading a file is not a drawing step. The watermark logo was being
        // decoded inside the preview's body, so every frame of an opacity
        // drag re-read it from disk; it is loaded once per chosen file now,
        // which is what a task is for.
        var decodingInBody: [String] = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources/Vorssaint/UI")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let full = "Sources/Vorssaint/UI/" + path
            let lines = ((try? String(contentsOfFile: full, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let reads = line.contains("NSImage(contentsOfFile:")
                    || line.contains("Data(contentsOf:")
                guard reads else { continue }
                let around = lines[max(0, index - 6)...min(lines.count - 1, index + 2)]
                if !around.contains(where: { $0.contains(".task(") || $0.contains("func ")
                                             || $0.contains("Task {") }) {
                    decodingInBody.append("\(full):\(index + 1)")
                }
            }
        }
        expect(decodingInBody.isEmpty,
               "a view reads a file once, never while drawing (\(decodingInBody.joined(separator: ", ")))")
        // A word pinned to a fixed column has to be allowed to give: the
        // backdrop sliders were labelled in a 64-point column that the Turkish
        // and Spanish words for blur run past, so they were being cut.
        let widestBackdropLabel = AppLanguage.allCases
            .flatMap { language -> [String] in
                let screenshot = FeatureStrings.screenshot(language)
                return [screenshot.backdropPaddingLabel,
                        screenshot.backdropCornersLabel,
                        screenshot.backdropBlurLabel]
            }
            .map(\.count).max() ?? 0
        expect(widestBackdropLabel >= 10,
               "the backdrop labels are long enough somewhere for the column to matter")
        for path in ["Sources/Vorssaint/UI/Screenshot/ScreenshotBackdropPopover.swift",
                     "Sources/Vorssaint/UI/Recorder/RecorderInspector.swift"] {
            let code = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            expect(!code.isEmpty, "the slider source reads back for its shape check")
            let pinned = code.components(separatedBy: "\n")
                .filter { $0.contains(".frame(width: 64, alignment: .leading)")
                          || $0.contains(".frame(width: 50, alignment: .leading)") }
            expect(!pinned.isEmpty, "the pinned label column is still there in \(path)")
            expect(code.components(separatedBy: "minimumScaleFactor(0.82)").count - 1 == pinned.count,
                   "every label pinned to that column may shrink instead of being cut (\(path))")
        }
    }

    static func runConcurrencyAndAccessibility(expect: (Bool, String) -> Void) {
        // An unpinned borderless Menu claims the free width of its row on
        // macOS 15 and starves whatever shares that row (issue #569), so the
        // rule is checked for every borderless menu in the app rather than for
        // the one this fix touches. Kill Process is the one
        // deliberate exception: its row controls take a shared minimum width
        // so the Kill button and the menu beside it line up down the list.
        let borderlessMenuException = "KillProcess/KillProcessView"
        var unpinnedBorderlessMenus: [String] = []
        let uiFiles = FileManager.default
            .enumerator(atPath: "Sources/Vorssaint/UI")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.contains(" 2") } ?? []
        for file in uiFiles.sorted() {
            let path = "Sources/Vorssaint/UI/\(file)"
            guard !file.contains(borderlessMenuException),
                  let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.contains(".menuStyle(.borderlessButton)") {
                // Read to the end of the menu's own modifier chain: the next
                // line that is neither a modifier nor a comment belongs to
                // something else.
                var pinned = false
                var cursor = index + 1
                while cursor < lines.count {
                    let text = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard text.hasPrefix(".") || text.hasPrefix("//") else { break }
                    if text.hasPrefix(".fixedSize()") { pinned = true; break }
                    cursor += 1
                }
                if !pinned { unpinnedBorderlessMenus.append("\(file):\(index + 1)") }
            }
        }
        // The file count is part of the rule: an enumerator that finds nothing
        // would leave the list empty and pass while checking no menu at all.
        expect(!uiFiles.isEmpty && unpinnedBorderlessMenus.isEmpty,
               "every borderless menu keeps its own size, across \(uiFiles.count) "
               + "scanned files: \(unpinnedBorderlessMenus)")

        // `waitUntilAllOperationsAreFinished` has no deadline, and the window
        // walk that used it runs on the main thread while its operations run on
        // the shared dispatch pool. Once unrelated work had taken every worker
        // in that pool, not one operation started and the wait never returned,
        // taking the whole app with it (issue #971). The call is unusable here
        // for that reason, so the rule is the absence of it rather than the one
        // caller that was found holding it.
        var unboundedOperationWaits: [String] = []
        let appSources = FileManager.default
            .enumerator(atPath: "Sources/Vorssaint")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.contains(" 2") } ?? []
        for file in appSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains("waitUntilAllOperationsAreFinished") {
                unboundedOperationWaits.append("\(file):\(index + 1)")
            }
        }
        expect(!appSources.isEmpty && unboundedOperationWaits.isEmpty,
               "no operation queue is waited on without a deadline: \(unboundedOperationWaits)")

        // Asking an application element for its role switches a Chromium app's
        // renderers into full accessibility mode for the rest of the process's
        // life (issue #953). It was fixed at the liveness probe, then found
        // again in the walk up an element's parents, where the chain above a
        // window is the application element — so the rule is the absence of
        // that read anywhere, rather than one grep per door somebody noticed.
        // This is a text scan, not dataflow: it knows an element is an
        // application element only when the same file names it in a `let x =
        // AXUIElementCreateApplication(...)`, and it reads the role attribute
        // and its element off one line. An application element handed to a
        // helper, stored in a property, or passed inline is still on review to
        // catch; both reads found so far were written the direct way.
        // Both scans below report real line numbers, so neither may filter its
        // array before enumerating: comments drop out in the predicate instead.
        func isCommentLine(_ line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        var applicationRoleReads: [String] = []
        for file in appSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            var applicationElements: Set<String> = []
            for line in lines where line.contains("AXUIElementCreateApplication(") {
                let assigned = (line.components(separatedBy: "=").first ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                guard assigned.count == 2, assigned[0] == "let" || assigned[0] == "var" else { continue }
                applicationElements.insert(assigned[1])
            }
            for (index, line) in lines.enumerated()
            where line.contains("kAXRoleAttribute")
                && !isCommentLine(line)
                && applicationElements.contains(where: { line.contains("(\($0), ") }) {
                applicationRoleReads.append("\(file):\(index + 1)")
            }
        }
        expect(!appSources.isEmpty && applicationRoleReads.isEmpty,
               "no application element is ever asked for its role: \(applicationRoleReads)")
        // The scan above cannot see the other way in: a walk up kAXParent asks
        // `parent` for its role, and the application element is what sits above
        // the last window, so the element it reads is never named after one.
        // Two files carried the same walk, so the rule is that anywhere doing
        // it stops at the application element first, rather than a pin per copy.
        var unguardedParentWalks: [String] = []
        for file in appSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            // Per occurrence and in order: a guard sitting anywhere in the file
            // would let a second walk go unguarded, and one written after the
            // read would let the read happen first, which is the whole failure.
            for (index, line) in lines.enumerated()
            where line.contains("role(of: parent)") && !isCommentLine(line) {
                // The window reads raw lines so the report above stays in real
                // line numbers; a commented-out guard must not count as one.
                let guarded = lines[max(0, index - 3)..<index]
                    .contains { $0.contains("isApplicationElement(parent)") && !isCommentLine($0) }
                if !guarded { unguardedParentWalks.append("\(file):\(index + 1)") }
            }
        }
        expect(!appSources.isEmpty && unguardedParentWalks.isEmpty,
               "a walk up the parent chain stops at the application element: \(unguardedParentWalks)")
    }

    static func runLifecycle(expect: (Bool, String) -> Void) {
        // MARK: Modifying mouse taps are handed back across a session switch
        // The tap owners cannot be reached from this list (they need the event
        // chain), so the wiring is pinned as text: each service follows the
        // session and asks before re-arming a tap the window server disabled.
        // Comments are stripped so prose naming the API cannot answer for it.
        let sessionActivitySource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/SessionActivity.swift",
            encoding: .utf8)) ?? ""
        expect(sessionActivitySource.contains("sessionDidResignActiveNotification")
                && sessionActivitySource.contains("sessionDidBecomeActiveNotification"),
               "the session watcher follows both halves of a fast user switch")
        let mouseAccelerationSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/MouseAcceleration/MouseAccelerationService.swift",
            encoding: .utf8)) ?? ""
        expect(mouseAccelerationSource.contains("SessionActivitySupport.isOnConsole("),
               "mouse acceleration shares the safe initial session-state fallback")
        for tapOwner in ["Sources/Vorssaint/Services/ScrollInverter.swift",
                         "Sources/Vorssaint/Services/SmoothScrollService.swift",
                         "Sources/Vorssaint/Services/MouseNavigation/MouseNavigationService.swift",
                         "Sources/Vorssaint/Services/MouseButtons/MouseButtonShortcutService.swift",
                         "Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift",
                         "Sources/Vorssaint/Services/QuitProtection/QuitProtectionService.swift",
                         "Sources/Vorssaint/Services/RadialMenu/RadialMenuService.swift",
                         "Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift",
                         "Sources/Vorssaint/Services/WindowMaximizer.swift",
                         "Sources/Vorssaint/Services/Finder/FinderCutPaste.swift",
                         "Sources/Vorssaint/Services/Finder/FinderRenameService.swift",
                         "Sources/Vorssaint/Services/KeyboardDebounce/KeyboardDebounceService.swift",
                         "Sources/Vorssaint/Services/SuperKey/SuperKeyService.swift",
                         "Sources/Vorssaint/Services/ShortcutRecordingTap.swift",
                         "Sources/Vorssaint/Services/Switcher/AppSwitcher.swift",
                         "Sources/Vorssaint/Services/Snippets/TextSnippetService.swift",
                         "Sources/Vorssaint/Services/Audio/PreciseVolumeRollerService.swift",
                         "Sources/Vorssaint/Services/DockClick/DockClickService.swift",
                         "Sources/Vorssaint/Services/Display/BrightnessService.swift"] {
            let source = (try? String(contentsOfFile: tapOwner, encoding: .utf8)) ?? ""
            expect(!source.isEmpty, "\(tapOwner) reads back for its session-switch check")
            let code = source.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            expect(code.contains("SessionActivity.shared.onChange"),
                   "\(tapOwner) rebuilds its tap when the session comes back")
            let rearm = code.components(separatedBy: "tapDisabledByTimeout")
                .dropFirst().first?.components(separatedBy: "return").first ?? ""
            expect(rearm.contains("SessionActivity.shared.isActive"),
                   "\(tapOwner) does not re-arm a disabled tap into a switched-away session")
            if tapOwner.contains("MouseNavigation")
                || tapOwner.contains("MouseButtonShortcut")
                || tapOwner.contains("MiddleClick")
                || tapOwner.contains("QuitProtection")
                || tapOwner.contains("RadialMenu")
                || tapOwner.contains("ShortcutRecordingTap") {
                expect(rearm.contains("AXIsProcessTrusted()"),
                       "\(tapOwner) does not keep a modifying tap alive after Accessibility is lost")
            }
            // Switching a tap off leaves the process owning it, which is what
            // the window server waits on; teardown must invalidate the port,
            // either here or through the pointer thread that owns the source.
            expect(code.contains("CFMachPortInvalidate")
                    || code.contains("PointerTapRunLoop.remove("),
                   "\(tapOwner) hands its tap back rather than only disabling it")
        }

        // The taps that filter ordinary clicks and wheel events are served by
        // a thread of their own. On the main run loop each of those events
        // waits for whatever this app is drawing or asking Accessibility,
        // which is felt as click lag in whatever app is in front.
        let pointerTapSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/PointerTapRunLoop.swift",
            encoding: .utf8)) ?? ""
        expect(pointerTapSource.contains("CFMachPortInvalidate"),
               "the pointer thread hands back the port of every tap it gives up")
        expect(pointerTapSource.contains("qualityOfService = .userInteractive"),
               "the pointer thread is scheduled as input work")
        for pointerTapOwner in ["Sources/Vorssaint/Services/ScrollInverter.swift",
                                "Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift"] {
            let source = (try? String(contentsOfFile: pointerTapOwner, encoding: .utf8)) ?? ""
            let code = source.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            expect(code.contains("PointerTapRunLoop.add("),
                   "\(pointerTapOwner) serves its tap on the pointer thread")
            expect(!code.contains("CFRunLoopGetMain()"),
                   "\(pointerTapOwner) keeps its tap off the main run loop")
        }

        // Disabling a tap and dropping the last Swift reference does not hand
        // the port back: CGGetEventTapList still reports the tap against this
        // process, one more per start/stop cycle, for the life of the process.
        // Only CFMachPortInvalidate deregisters it. Counted per tap rather than
        // per file, because BrightnessService and SuperKeyService own two taps
        // each and WindowLayoutService three, and on comment-stripped source,
        // as in the per-service check above, so prose naming the API cannot
        // answer for a missing call. A margin does not cover a tap added later:
        // MouseClickDebounceService's two invalidations are both on its one
        // tap. The owners reached are counted too, because a file with no
        // literal CGEvent.tapCreate is skipped, so moving the call behind a
        // helper would otherwise leave a sweep that passes having read nothing.
        var tapOwnersWithoutInvalidate: [String] = []
        var tapOwners = 0
        let tapOwnerSources = FileManager.default
            .enumerator(atPath: "Sources/Vorssaint")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.contains(" 2") } ?? []
        for file in tapOwnerSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            let code = source.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let taps = code.components(separatedBy: "CGEvent.tapCreate").count - 1
            guard taps > 0 else { continue }
            tapOwners += 1
            // A tap served by the pointer thread is handed back there, which
            // is the same promise: `PointerTapRunLoop.remove` invalidates the
            // port it is given, and the sweep above pins that it does.
            let invalidations = code.components(separatedBy: "CFMachPortInvalidate").count - 1
                + (code.components(separatedBy: "PointerTapRunLoop.remove(").count - 1)
            if invalidations < taps {
                tapOwnersWithoutInvalidate.append("\(file) (\(taps) taps, \(invalidations) invalidated)")
            }
        }
        expect(tapOwners > 0 && tapOwnersWithoutInvalidate.isEmpty,
               "every event tap owner invalidates its port on teardown, across "
               + "\(tapOwners) scanned owners: \(tapOwnersWithoutInvalidate)")

        let mouseTapAppDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift",
            encoding: .utf8)) ?? ""
        expect(mouseTapAppDelegateSource.contains("MouseButtonShortcutService.shared.suspend()"),
               "normal termination releases mouse-button tap state instead of waiting for a future Up")
        let accessibilitySink = mouseTapAppDelegateSource
            .components(separatedBy: "Permissions.shared.$accessibility")
            .dropFirst().first?.components(separatedBy: "Permissions.shared.$screenRecording").first ?? ""
        expect(accessibilitySink.contains(".quitWindowProtection"),
               "granting Accessibility starts quit protection without a relaunch")
        let smoothSchedulerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/SmoothScrollService.swift",
            encoding: .utf8)) ?? ""
        let smoothSchedulerCode = smoothSchedulerSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let steppedLoupeBypass = smoothSchedulerCode
            .components(separatedBy: "if ScreenshotSelectionController.steppedLoupeNeedsRawWheel(")
            .dropFirst().first?.components(separatedBy: "return").first ?? ""
        expect(steppedLoupeBypass.contains("stopGlide()"),
               "entering stepped magnifier zoom cancels the fast glide before passing the raw notch")
        let scrollInverterSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/ScrollInverter.swift",
            encoding: .utf8)) ?? ""
        for (name, source) in [("scroll inverter", scrollInverterSource),
                               ("smooth scroll", smoothSchedulerCode)] {
            expect(source.contains("guard !tapCreationRetryUsed")
                    && source.contains("tapCreationRetryWork?.cancel()"),
                   "\(name) retries tap creation once instead of polling forever")
        }
        expect(smoothSchedulerCode.contains("screen.displayLink(")
                && smoothSchedulerCode.contains("displayLink.add(to: .main, forMode: .common)")
                && smoothSchedulerCode.contains("sender.timestamp")
                && smoothSchedulerCode.contains("sender.duration"),
               "smooth scrolling follows the active display's native cadence and elapsed frame time")
        expect(smoothSchedulerCode.contains("displayLink?.invalidate()")
                && smoothSchedulerCode.contains("frameTimer?.invalidate()")
                && smoothSchedulerCode.contains("removeScreenObserver()")
                && smoothSchedulerCode.contains("removeSleepObserver()"),
               "smooth scrolling releases either scheduler and its lifecycle observers on stop")
        expect(smoothSchedulerCode.contains("NSScreen.withMouse")
                && smoothSchedulerCode.contains("didChangeScreenParametersNotification")
                && smoothSchedulerCode.contains("Timer(timeInterval: SmoothScrollSupport.frameInterval"),
               "smooth scrolling follows display changes and keeps a no-screen timer fallback")
        let smoothTapDisabled = smoothSchedulerCode.components(separatedBy: "tapDisabledByTimeout")
            .dropFirst().first?.components(separatedBy: "return").first ?? ""
        expect(smoothTapDisabled.contains("tapDisabledByUserInput")
                && smoothTapDisabled.contains("stopGlide()")
                && smoothTapDisabled.contains("AppFeature.smoothScroll.isAvailable")
                && smoothTapDisabled.contains("DefaultsKey.smoothScrollEnabled")
                && smoothTapDisabled.contains("AXIsProcessTrusted()")
                && smoothTapDisabled.contains("SessionActivity.shared.isActive"),
               "a disabled smooth-scroll tap drops its tail and re-arms only while fully wanted")
        let smoothSleep = smoothSchedulerCode.components(separatedBy: "willSleepNotification")
            .dropFirst().first?.components(separatedBy: "private func removeSleepObserver").first ?? ""
        expect(smoothSleep.contains("stopGlide()"),
               "smooth scrolling cannot carry a pre-sleep glide into the next wake")
        let cleaningModeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CleaningMode/CleaningModeManager.swift",
            encoding: .utf8)) ?? ""
        expect(cleaningModeSource.contains("SessionActivity.shared.onChange")
                && cleaningModeSource.contains("deactivate(restoreSuspendedFeatures: false)")
                && cleaningModeSource.contains("SessionActivity.shared.isActive")
                && cleaningModeSource.contains("AXIsProcessTrusted()")
                && cleaningModeSource.contains("CFMachPortInvalidate"),
               "Cleaning Mode ends and releases its filter tap when the login session leaves the screen")

        // MARK: Uninstallation paths stay aligned across SelfUninstall and Tools/uninstall.sh
        let selfUninstallSource = (try? String(contentsOfFile: "Sources/Vorssaint/Services/SelfUninstall.swift",
                                              encoding: .utf8)) ?? ""
        let uninstallScriptSource = (try? String(contentsOfFile: "Tools/uninstall.sh",
                                                encoding: .utf8)) ?? ""
        expect(!selfUninstallSource.isEmpty && !uninstallScriptSource.isEmpty,
               "uninstall sources read back for uninstallation alignment check")
        let queryHabitSupportSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarSupport.swift",
            encoding: .utf8)) ?? ""
        expect(selfUninstallSource.contains("CommandBarQueryHabits.removeInstallationKey()")
                && queryHabitSupportSource.contains("installationKeyCache.stopAndRemove {")
                && queryHabitSupportSource.contains("SecItemDelete([")
                && queryHabitSupportSource.contains("kSecClass: kSecClassGenericPassword")
                && queryHabitSupportSource.contains("kSecAttrService: keyService")
                && queryHabitSupportSource.contains("kSecAttrAccount: keyAccount")
                && queryHabitSupportSource.contains("keyService = installationKeyService(")
                && queryHabitSupportSource.contains("keyAccount = \"hmac-key\"")
                && uninstallScriptSource.contains("/usr/bin/security delete-generic-password")
                && uninstallScriptSource.contains("-s \"$BUNDLE.command-bar-query-habits\" -a \"hmac-key\""),
               "both uninstall paths remove only the query-learning Keychain item")
        let requiredSubpaths = ["Library/Application Support", "Library/Caches", "Library/HTTPStorages"]
        for subpath in requiredSubpaths {
            expect(selfUninstallSource.contains(subpath) && uninstallScriptSource.contains(subpath),
                   "both in-app and script uninstall sweep \(subpath)")
        }
        expect(uninstallScriptSource.contains("Library/Preferences/ByHost"),
               "script uninstall sweeps ByHost preferences")
        // Restoring sleep used to be fired and forgotten at both exits. A
        // failure there leaves `pmset disablesleep 1` set system-wide, and
        // removal deletes the flag that launch-time recovery reads before it
        // reads the setting, so nothing repairs it afterwards — a reinstall
        // included.
        let uninstallerSource = (try? String(contentsOfFile: "Sources/Vorssaint/Support/Uninstaller.swift",
                                             encoding: .utf8)) ?? ""
        expect(!uninstallerSource.isEmpty,
               "uninstaller entry point reads back for the sleep restore check")
        expect(!selfUninstallSource.contains("_ = Sudoers.pmsetDisableSleep")
                && !uninstallerSource.contains("_ = Sudoers.pmsetDisableSleep"),
               "neither uninstall path discards the result of restoring sleep")
        expect(selfUninstallSource.contains("guard detachFromSystem() else")
                && selfUninstallSource.contains("restoreSleepBeforeRemoval() -> Bool")
                && selfUninstallSource.contains("guard FanControlService.restoreAndUnregisterForRemoval() else")
                && selfUninstallSource.contains("adminPromptRecover")
                && selfUninstallSource.contains("verification.status == 0"),
               "in-app uninstall aborts unless fans and normal sleep are restored before removal")
        expect(uninstallScriptSource.contains("SleepDisabled"),
               "script uninstall reads the sleep setting back for itself")
    }
}
