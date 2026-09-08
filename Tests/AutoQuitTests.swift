// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

enum AutoQuitTests {
    static func run(expect: (Bool, String) -> Void) {
        expect(AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.direct",
                                          bundleURL: nil,
                                          exceptions: ["com.example.direct"]),
               "AutoQuit recognizes a direct bundle identifier exception")
        expect(AutoQuitSupport.isExcepted(
            bundleIdentifier: "com.parallels.winapp.0123456789abcdef.guest",
            bundleURL: nil,
            exceptions: ["com.parallels.desktop.console"]
        ), "AutoQuit extends a guest-window host exception to its generated app helpers")
        expect(!AutoQuitSupport.isExcepted(
            bundleIdentifier: "com.parallels.winapp.0123456789abcdef.guest",
            bundleURL: nil,
            exceptions: ["com.example.unrelated"]
        ), "AutoQuit does not protect a generated guest app without its host exception")
        let outerApp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintAutoQuitTests-\(UUID().uuidString)")
            .appendingPathComponent("Container.app")
        let nestedApp = outerApp.appendingPathComponent("Contents/MacOS/WindowHost.app")
        try? FileManager.default.createDirectory(at: nestedApp.appendingPathComponent("Contents"),
                                                 withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.container"])
            .write(to: outerApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.window-host"])
            .write(to: nestedApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        expect(AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.window-host",
                                          bundleURL: nestedApp,
                                          exceptions: ["com.example.container"]),
               "AutoQuit extends an outer app exception to its bundled window host")
        expect(!AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.window-host",
                                           bundleURL: nestedApp,
                                           exceptions: ["com.example.unrelated"]),
               "AutoQuit does not extend unrelated exceptions to a bundled window host")
        let dependentApp = outerApp.appendingPathComponent("Contents/Hosted.app")
        try? FileManager.default.createDirectory(at: dependentApp.appendingPathComponent("Contents"),
                                                 withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.dependent",
                                  "CrBundleIdentifier": "com.example.host"])
            .write(to: dependentApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        expect(AutoQuitSupport.hasDependentApplication(hostBundleIdentifier: "com.example.host",
                                                       applicationBundleURLs: [dependentApp]),
               "AutoQuit keeps a host running while a declared dependent app is open")
        expect(!AutoQuitSupport.hasDependentApplication(hostBundleIdentifier: "com.example.unrelated",
                                                        applicationBundleURLs: [dependentApp]),
               "AutoQuit does not protect an unrelated host")
        try? FileManager.default.removeItem(at: outerApp.deletingLastPathComponent())
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appDeactivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app deactivation as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appActivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app activation as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .mainWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat main window changes as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .focusedWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat focused window changes as a window close")
        expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .windowDestroyed,
                                                         hasRecentCloseRequest: false),
               "AutoQuit checks windows after a destroyed window")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                          hasRecentCloseRequest: false),
               "AutoQuit ignores hidden apps without a recent close request")
        expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                         hasRecentCloseRequest: true),
               "AutoQuit checks hidden apps after a recent close request")
        expect(AutoQuitSupport.isCommandW(keyCode: 13, command: true, control: false),
               "AutoQuit treats Command W as a close request")
        expect(!AutoQuitSupport.isCommandW(keyCode: 18, command: true, control: true),
               "AutoQuit does not treat Control number Space switching as a close request")
        expect(AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                          appIsTerminated: false,
                                                          appIsExcepted: false,
                                                          appIsHidden: false,
                                                          hiddenByCloseRequest: false,
                                                          hasKnownMinimizedWindow: false,
                                                          hasUserFacingWindow: false),
               "AutoQuit can quit when an app that had windows is now windowless")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: false,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit does not quit apps that started windowless")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: true,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps excepted apps running")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: true,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps hidden apps running without explicit close intent")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: true,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps apps running when a minimized window is known")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: true),
               "AutoQuit keeps apps with user-facing windows running")
        expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [4],
                                                            visibleSpaces: [3],
                                                            hasTitle: true),
               "a window parked on another Space keeps its app running")
        expect(!AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [3],
                                                             visibleSpaces: [3],
                                                             hasTitle: true),
               "a window the app hid on the Space in front does not keep it running")
        expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [],
                                                            visibleSpaces: [3],
                                                            hasTitle: true),
               "a window with no Space answer falls back to the title rule")
        expect(!AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [],
                                                             visibleSpaces: nil,
                                                             hasTitle: false),
               "an untitled off-screen window never keeps an app running")
        expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [3],
                                                            visibleSpaces: nil,
                                                            hasTitle: true),
               "without Spaces to compare, the old cautious rule stands")

        expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                     listedWindows: 0,
                                                     foundUserWindow: true,
                                                     hadPriorWindows: false),
               "an app the window server still shows a window for is watched again")
        expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 1,
                                                     listedWindows: 2,
                                                     foundUserWindow: true,
                                                     hadPriorWindows: false),
               "a listed window whose notification failed is watched again")
        expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 2,
                                                       listedWindows: 2,
                                                       foundUserWindow: true,
                                                       hadPriorWindows: false),
               "two registered windows cover the two Accessibility listed windows")
        expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 1,
                                                       listedWindows: 1,
                                                       foundUserWindow: true,
                                                       hadPriorWindows: false),
               "a registered window is the watch, so nothing is retried")
        expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                     listedWindows: 0,
                                                     foundUserWindow: false,
                                                     hadPriorWindows: false),
               "an app with no window on launch is retried during the initial watch window")
        expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                       listedWindows: 0,
                                                       foundUserWindow: false,
                                                       hadPriorWindows: true),
               "an app that had prior windows and now closed its last window needs no watch retry")
        expect(AutoQuitSupport.isWindowNotificationRegistered(.success),
               "a window whose notification was accepted is watched")
        expect(AutoQuitSupport.isWindowNotificationRegistered(.notificationAlreadyRegistered),
               "a window already registered on this observer stays watched across refreshes")
        expect(!AutoQuitSupport.isWindowNotificationRegistered(.cannotComplete),
               "a window whose registration was refused is not watched")
        let autoQuitServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AutoQuit/AutoQuitService.swift",
            encoding: .utf8)) ?? ""
        let autoQuitServiceLines = autoQuitServiceSource.components(separatedBy: "\n")
        func autoQuitServiceCodeLines(containing fragment: String) -> [Int] {
            autoQuitServiceLines.enumerated().compactMap { index, line in
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains(fragment) else { return nil }
                return index + 1
            }
        }
        // The retry has to stop: an app whose windows Accessibility can never
        // describe would otherwise be polled for as long as it runs. The
        // service is not part of this test binary, so pin the load-bearing
        // timing, stale-timer guard, and Space re-arm at their source lines.
        let windowWatchRetryCode = [
            "let serverWindow = windows.isEmpty ? hasWindowServerUserWindow(pid: pid) : nil",
            "let foundUserWindow = !windows.isEmpty || serverWindow == true",
            "private static let windowWatchRetryOffsets: [TimeInterval] = [0.5, 1.5, 4.0]",
            "retry.attemptsScheduled < Self.windowWatchRetryOffsets.count else { return }",
            "deadline: retry.origin + Self.windowWatchRetryOffsets[attempt]",
            "retry.pendingTimerID == timerID",
            "windowWatchRetries.removeAll()",
            "NSWorkspace.activeSpaceDidChangeNotification",
            "rearmWindowWatchRetries()",
            // The count the retry reads must be windows actually watched, not
            // windows Accessibility listed: AXObserverAddNotification can
            // refuse, and a refused registration is exactly the state the
            // retry exists for. Only the destroyed notification decides it.
            "if watch(window: window, observer: observer, refcon: refcon) { watchedWindows += 1 }",
            "needsWindowWatchRetry(registeredWindows: watchedWindows,",
            "listedWindows: windows.count,",
            "if notification == kAXUIElementDestroyedNotification {",
            "watched = AutoQuitSupport.isWindowNotificationRegistered(result)",
        ]
        let missingWindowWatchRetryCode = windowWatchRetryCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        expect(missingWindowWatchRetryCode.isEmpty,
               "the AutoQuit window-watch retry stays bounded, origin-based, re-armed by Space changes, and counts only windows whose destroy notification registered: missing \(missingWindowWatchRetryCode)")
        // Coalescing is only safe while the state it reads is torn down with
        // the app: a refresh left pending for a detached app would run against
        // an observer that is gone.
        let refreshCoalescingCode = [
            "guard pendingRefreshes.insert(pid).inserted else { return }",
            "self.pendingRefreshes.remove(pid) != nil",
            "pendingRefreshes.removeAll()",
        ]
        let missingRefreshCoalescingCode = refreshCoalescingCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        expect(missingRefreshCoalescingCode.isEmpty,
               "AutoQuit collapses a burst of notifications into one refresh and drops it when the app goes: missing \(missingRefreshCoalescingCode)")
        // Two lines drop the pending refresh: the deferred block's own guard
        // and `detach`. Losing the second is the case this counts.
        expect(autoQuitServiceCodeLines(containing: "pendingRefreshes.remove(pid)").count == 2,
               "a pending AutoQuit refresh is dropped both when it runs and when the app is detached")
        let closeCheckOffsetCode = [
            "private static let closeCheckOffsets: [TimeInterval] = [0.35, 1.0, 2.2]",
            "for offset in Self.closeCheckOffsets",
            "DispatchQueue.main.asyncAfter(deadline: origin + offset)",
        ]
        let missingCloseCheckOffsetCode = closeCheckOffsetCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        expect(missingCloseCheckOffsetCode.isEmpty,
               "AutoQuit close checks remain offsets from one origin: missing \(missingCloseCheckOffsetCode)")

        // Attaching to a watched app must never ask its application element for
        // a role. A Chromium app (Electron, and the browsers) answers that by
        // switching its renderers into full accessibility mode, and then pays
        // to rebuild and ship an accessibility tree on every DOM change for the
        // rest of its life — measured on an idle app that this feature only
        // ever needed a window count from (issue #953). Windows are the same
        // liveness signal and leave that mode alone. Comments are stripped
        // first: the note above the probe names the attribute it avoids, and a
        // check that cannot tell prose from a call would go red for it.
        let autoQuitServiceCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AutoQuit/AutoQuitService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(autoQuitServiceCode.contains(
                   "AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .cannotComplete"),
               "AutoQuit probes a watched app for liveness by asking for its windows")
        // The same read reached the application element a second way, up the
        // parent chain of an element that never yields a window. Two files
        // carried that walk, so both the rule and its guard are repo wide
        // further down rather than a grep per copy here.
        expect(Defaults.sanitizedPanelItemOrder("uninstaller,homebrew,homebrew,bad",
                                                defaultOrder: ["homebrew", "media", "uninstaller", "cleanURL", "cleaning"])
               == ["uninstaller", "homebrew", "media", "cleanURL", "cleaning"],
               "panel item order keeps saved valid items first and appends defaults")
    }
}
