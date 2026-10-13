// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum NotchWatchTests {
    static func run(_ suite: TestSuite) {
        NotchWatchChoiceTests.run(suite)
        readingContracts(suite)
        numberContracts(suite)
        changeContracts(suite)
        settleContracts(suite)
        matchContracts(suite)
        geometryContracts(suite)
        fingerprintContracts(suite)
        gateContracts(suite)
        readingLoopContracts(suite)
        companionContracts(suite)
    }

    private static func companionContracts(_ suite: TestSuite) {
        suite.expect(NotchWatchOutcome.changed.mascotReaction == .perk
                     && [NotchWatchOutcome.settled, .shows("Done"), .reached("100%")]
                        .allSatisfy { $0.mascotReaction == .celebrate }
                     && NotchWatchOutcome.closed.mascotReaction == .confused,
                     "the companion is wide-eyed at a change, glad when the wait is over, puzzled when the window goes")
    }

    private static func readingContracts(_ suite: TestSuite) {
        suite.expect(NotchWatchSupport.headline(from: "Exporting video\n73 % complete") == "73%",
                     "a percentage anywhere in the area is its reading")
        suite.expect(NotchWatchSupport.headline(from: "All cores\n1250% CPU") == "1250%"
                        && NotchWatchSupport.headline(from: "Change today\n\u{2212}5 %") == "\u{2212}5%",
                     "a percentage keeps all its digits and a typeset minus sign")
        suite.expect(NotchWatchSupport.headline(from: "  Build Succeeded \n") == "Build Succeeded",
                     "a short first line is shown as it is")
        suite.expect(NotchWatchSupport.headline(from: "Your order will arrive at the door at 14:30 today") == "14:30",
                     "a long line gives way to the clock in it")
        suite.expect(NotchWatchSupport.headline(from: "Uploading the whole project folder, 3.2 GB left") == "3.2 GB",
                     "or to the first amount with its unit")
        let long = NotchWatchSupport.headline(from: "Waiting for the other participants to join the call")
        suite.expect(long.count == NotchWatchSupport.headlineLength && long.hasSuffix("…"),
                     "text without numbers is cut to the strip's length")
        suite.expect(NotchWatchSupport.headline(from: " \n ").isEmpty, "an area without text has no reading")
        let area = "Project Alpha\nUploading 3 files\n12 MB of 40 MB"
        suite.expect(NotchWatchSupport.lines(in: area) == ["Project Alpha", "Uploading 3 files", "12 MB of 40 MB"]
                        && NotchWatchSupport.headline(from: area, line: 2) == "12 MB of 40 MB",
                     "a chosen line is what the island shows")
        suite.expect(NotchWatchSupport.headline(from: area, line: nil) == "Project Alpha"
                        && NotchWatchSupport.headline(from: "Done", line: 2) == "Done",
                     "without a choice, or once that line is gone, the reading is automatic again")
        suite.expect(NotchWatchSupport.normalized("  Concluído\n  AGORA ") == "concluido agora",
                     "comparisons ignore case, accents and spacing")
    }

    private static func numberContracts(_ suite: TestSuite) {
        let cases: [(String, Double?)] = [
            ("45%", 45), ("Progress 12,5 %", 12.5), ("1,234 of 5,000 files", 1234),
            ("1.234,5 MB", 1234.5), ("1,234.5 MB", 1234.5), ("Score -3", -3),
            ("3 of 10, then 80% done", 80), ("No numbers here", nil), ("1.234.567", 1234567),
            ("1250%", 1250), ("Zoom 1,250%", 1250), ("CPU 1250.5 %", 1250.5),
            ("\u{2212}5%", -5), ("Change \u{2212}12,5 %", -12.5), ("-5%", -5),
        ]
        for (text, expected) in cases {
            suite.expect(NotchWatchSupport.number(in: text) == expected,
                         "\(text) reads as \(String(describing: expected))")
        }
        for space in [" ", "\u{00A0}", "\u{202F}"] {
            for (sign, multiplier) in [("", 1.0), ("+", 1.0), ("-", -1.0), ("−", -1.0)] {
                let reading = "Change \(sign)1\(space)250,5\(space)%"
                suite.expect(NotchWatchSupport.number(in: reading, decimalSeparator: ",", groupsWithSpace: true)
                                == multiplier * 1250.5
                                && NotchWatchSupport.headline(from: reading, groupsWithSpace: true) == "\(sign)1250,5%",
                             "spaced percentages retain every digit and their sign: \(reading)")
            }
        }
        for (reading, percent) in [("Step 2 100%", 100.0), ("1 of 3 100%", 100), ("Elapsed 02:13 100%", 100),
                                   ("CPU 2 150%", 150)] {
            suite.expect(NotchWatchSupport.number(in: reading) == percent
                            && NotchWatchSupport.headline(from: reading, groupsWithSpace: false) == "\(Int(percent))%",
                         "a number before a percentage is not joined to it where thousands are not spaced: \(reading)")
        }
        suite.expect(NotchWatchSupport.number(in: "Progress 45\n% done") == 45
                        && NotchWatchSupport.headline(from: "Progress 45\n% done", groupsWithSpace: true) == "Progress 45",
                     "a percent sign on the next line is not read into the number")
        suite.expect(NotchWatchSupport.number(in: "Step 2 50%") == 50
                        && NotchWatchSupport.number(in: "Step 2\n250%", groupsWithSpace: true) == 250
                        && NotchWatchSupport.headline(from: "Step 2\n250%") == "250%",
                     "percentage grouping does not join separate numbers or lines")
        suite.expect(NotchWatchSupport.number(in: "1.000", decimalSeparator: ",") == 1000
                        && NotchWatchSupport.number(in: "12.500", decimalSeparator: ",") == 12500
                        && NotchWatchSupport.number(in: "12,500", decimalSeparator: ",") == 12.5
                        && NotchWatchSupport.number(in: "1.000", decimalSeparator: ".") == 1
                        && NotchWatchSupport.number(in: "12,500", decimalSeparator: ".") == 12500,
                     "a lone mark before three digits follows the region's decimal mark")
        suite.expect(NotchWatchSupport.number(in: "0,125") == 0.125 && NotchWatchSupport.number(in: "0.125",
                                                                                         decimalSeparator: ",") == 0.125,
                     "a number that starts at zero has decimals, never thousands")
        for identifier in ["pt_BR", "de_DE", "en_US", "fr_FR", "ja_JP"] {
            let locale = Locale(identifier: identifier)
            for value in [1000.0, 25_000, 1_234_567, 12.5, 0.25] {
                let shown = NotchWatchSupport.formatted(value, locale: locale)
                suite.expect(NotchWatchSupport.typedNumber(shown, locale: locale) == value,
                             "a target shown as \(shown) in \(identifier) reads back as \(value)")
            }
        }
        suite.expect(NotchWatchSupport.typedNumber("1.000", locale: Locale(identifier: "pt_BR")) == 1000
                        && NotchWatchSupport.typedNumber("1,5", locale: Locale(identifier: "pt_BR")) == 1.5
                        && NotchWatchSupport.typedNumber("10\u{202F}000", locale: Locale(identifier: "fr_FR")) == 10000
                        && NotchWatchSupport.typedNumber("1,000", locale: Locale(identifier: "en_US")) == 1000,
                     "a typed target is read as the page's region writes it")
        let brazil = Locale(identifier: "pt_BR")
        var climbing = NotchWatchTracker(condition: .reaches, text: "", target: 1000, locale: brazil)
        suite.expect(climbing.observe(signature: "a", reading: "850 de 1.200", at: Date()) == nil
                        && climbing.observe(signature: "b", reading: "1.000 de 1.200", at: Date()) == .reached("1.000 de 1.200"),
                     "a window's numbers are read as the Mac's region writes them")
        let france = Locale(identifier: "fr_FR")
        var percentage = NotchWatchTracker(condition: .reaches, text: "", target: 1000, locale: france)
        suite.expect(percentage.observe(signature: "a", reading: "900%", at: Date()) == nil
                        && percentage.observe(signature: "b", reading: "1\u{202F}250%", at: Date())
                            == .reached("1250%"),
                     "a percentage crossing one thousand triggers the watch in a space-grouping region")
        var falling = NotchWatchTracker(condition: .reaches, text: "", target: 10, locale: france)
        suite.expect(falling.observe(signature: "a", reading: "Reste 10\u{202F}000 fichiers", at: Date()) == nil
                        && falling.observe(signature: "b", reading: "Reste 999 fichiers", at: Date()) == nil
                        && falling.observe(signature: "c", reading: "Reste 3 fichiers", at: Date()) == .reached("Reste 3 fichiers"),
                     "a region that groups thousands with a space reads them as one number")
        suite.expect(NotchWatchSupport.number(in: "3 of 10 000", decimalSeparator: ",", groupsWithSpace: true) == 3
                        && NotchWatchSupport.number(in: "10 000,5 Mo", decimalSeparator: ",", groupsWithSpace: true) == 10000.5
                        && NotchWatchSupport.groupsWithSpace(france) && !NotchWatchSupport.groupsWithSpace(brazil),
                     "the first number still comes first, and only space regions join groups")
    }

    private static func changeContracts(_ suite: TestSuite) {
        let start = Date()
        let hold = NotchWatchTracker.changeConfirmation
        func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
        var tracker = NotchWatchTracker(condition: .changes)
        suite.expect(tracker.observe(signature: "uploading", reading: "Uploading", at: at(0)) == nil,
                     "the first reading is the starting point")
        suite.expect(tracker.observe(signature: nil, reading: "Uploading", at: at(2)) == nil
                        && tracker.observe(signature: "uploading", reading: "Uploading", at: at(4)) == nil,
                     "an unchanged area is not a change")
        suite.expect(tracker.observe(signature: "uploadin", reading: "Uploadin", at: at(6)) == nil
                        && tracker.observe(signature: "uploading", reading: "Uploading", at: at(6 + hold)) == nil,
                     "a reading that flips back is noise, not a change")
        suite.expect(tracker.observe(signature: "done", reading: "Done", at: at(20)) == nil
                        && tracker.observe(signature: "done", reading: "Done", at: at(21)) == nil,
                     "a new reading waits a few seconds before it counts")
        suite.expect(tracker.observe(signature: "done", reading: "Done", at: at(20 + hold)) == .changed,
                     "a change that holds for a few seconds ends the watch")

        // A still area is not read again: it comes back with its last signature.
        var still = NotchWatchTracker(condition: .changes)
        _ = still.observe(signature: "uploading", reading: "Uploading", at: at(0))
        suite.expect(still.observe(signature: "done", reading: "Done", at: at(2)) == nil
                        && still.observe(signature: "done", reading: "Done", at: at(4)) == nil
                        && still.observe(signature: "done", reading: "Done", at: at(6)) == .changed,
                     "a change that then holds still ends the watch at the background pace")
        var moving = NotchWatchTracker(condition: .changes)
        _ = moving.observe(signature: "12%", reading: "12%", at: at(0))
        suite.expect(moving.observe(signature: "13%", reading: "13%", at: at(1)) == nil
                        && moving.observe(signature: "14%", reading: "14%", at: at(2)) == nil
                        && moving.observe(signature: "15%", reading: "15%", at: at(1 + hold)) == .changed,
                     "a reading that keeps moving ends the watch too")
        func picture(_ level: UInt8, nudged: Int = 0) -> String? {
            var cells = [UInt8](repeating: level, count: 256)
            for index in 0..<nudged { cells[index] = level + 1 }
            return NotchWatchSupport.signature(text: "", fingerprint: cells)
        }
        var bar = NotchWatchTracker(condition: .changes)
        _ = bar.observe(signature: picture(4), reading: "", at: at(0))
        suite.expect(bar.observe(signature: picture(4, nudged: 3), reading: "", at: at(2)) == nil
                        && bar.observe(signature: picture(4, nudged: 2), reading: "", at: at(2 + hold)) == nil,
                     "a picture that only shimmers is not a change")
        suite.expect(bar.observe(signature: picture(9), reading: "", at: at(10)) == nil
                        && bar.observe(signature: picture(9), reading: "", at: at(10 + hold)) == .changed,
                     "an area without text ends the watch once its picture moves and holds")
    }

    private static func settleContracts(_ suite: TestSuite) {
        let start = Date()
        var tracker = NotchWatchTracker(condition: .settles)
        _ = tracker.observe(signature: "line 1", reading: "line 1", at: start)
        suite.expect(tracker.observe(signature: nil, reading: "line 1",
                                     at: start.addingTimeInterval(120)) == nil,
                     "an area that never moved has not stopped anything")
        _ = tracker.observe(signature: "line 2", reading: "line 2", at: start.addingTimeInterval(121))
        suite.expect(tracker.observe(signature: nil, reading: "line 2",
                                     at: start.addingTimeInterval(140)) == nil,
                     "a short pause is not the end")
        suite.expect(tracker.observe(signature: "line 2", reading: "line 2",
                                     at: start.addingTimeInterval(121 + NotchWatchTracker.settleInterval)) == .settled,
                     "after a change, the settle interval of stillness ends the watch")
        suite.expect(NotchWatchSupport.sameSignature("done", "done") && !NotchWatchSupport.sameSignature("done", nil)
                        && !NotchWatchSupport.sameSignature("done", "image:1.2"),
                     "texts compare exactly, and a text never matches a picture")
    }

    private static func matchContracts(_ suite: TestSuite) {
        let now = Date()
        var words = NotchWatchTracker(condition: .contains, text: "concluida")
        suite.expect(words.observe(signature: "x", reading: "Exportando…", at: now) == nil
                        && words.observe(signature: "y", reading: "Exportação CONCLUÍDA", at: now) == .shows("concluida"),
                     "the typed words are found whatever their case and accents")
        var empty = NotchWatchTracker(condition: .contains, text: "  ")
        suite.expect(!empty.isReady && empty.observe(signature: "x", reading: "anything", at: now) == nil,
                     "without words to find, nothing can match")
        var up = NotchWatchTracker(condition: .reaches, target: 100)
        suite.expect(up.observe(signature: "a", reading: "Copying 40%", at: now) == nil
                        && up.observe(signature: "b", reading: "Copying 99%", at: now) == nil
                        && up.observe(signature: "c", reading: "Copying 100%", at: now) == .reached("100%"),
                     "a number counting up reaches its target")
        var down = NotchWatchTracker(condition: .reaches, target: 0)
        suite.expect(down.observe(signature: "a", reading: "5 left", at: now) == nil
                        && down.observe(signature: "b", reading: "0 left", at: now) == .reached("0 left"),
                     "a number counting down reaches its target too")
        var already = NotchWatchTracker(condition: .reaches, target: 3)
        suite.expect(already.observe(signature: "a", reading: "3", at: now) == .reached("3"),
                     "a target already shown is met at once")
        var unread = NotchWatchTracker(condition: .reaches, target: 10)
        suite.expect(unread.observe(signature: "a", reading: "no digits", at: now) == nil && unread.start == nil,
                     "a reading without a number does not set the direction")
    }

    private static func geometryContracts(_ suite: TestSuite) {
        let windows: [(id: CGWindowID, bounds: CGRect)] = [
            (id: 7, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            (id: 3, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)),
        ]
        let front = NotchWatchSupport.windowCrop(for: CGRect(x: 150, y: 120, width: 100, height: 40), windows: windows)
        suite.expect(front?.id == 7 && front?.crop == CGRect(x: 50, y: 20, width: 100, height: 40),
                     "the front window under the area keeps it, in its own coordinates")
        let overhanging = NotchWatchSupport.windowCrop(for: CGRect(x: 420, y: 360, width: 100, height: 60), windows: windows)
        suite.expect(overhanging?.id == 7 && overhanging?.crop == CGRect(x: 320, y: 260, width: 80, height: 40),
                     "an area running past the window's edge is kept inside it")
        suite.expect(NotchWatchSupport.windowCrop(for: CGRect(x: 1200, y: 10, width: 50, height: 50), windows: windows) == nil,
                     "an area over no window has no window to follow")
        suite.expect(NotchWatchSupport.pixelCrop(CGRect(x: 50, y: 20, width: 100, height: 40),
                                                 windowSize: CGSize(width: 400, height: 300),
                                                 imageSize: CGSize(width: 800, height: 600))
                        == CGRect(x: 100, y: 40, width: 200, height: 80),
                     "points become the window image's pixels")
        suite.expect(NotchWatchSupport.pixelCrop(CGRect(x: 350, y: 250, width: 100, height: 100),
                                                 windowSize: CGSize(width: 400, height: 300),
                                                 imageSize: CGSize(width: 400, height: 300))
                        == CGRect(x: 350, y: 250, width: 50, height: 50),
                     "a window that shrank keeps what is left of the area")
        suite.expect(NotchWatchSupport.pixelCrop(CGRect(x: 500, y: 500, width: 10, height: 10),
                                                 windowSize: CGSize(width: 400, height: 300),
                                                 imageSize: CGSize(width: 400, height: 300)) == nil,
                     "an area the window no longer covers reads nothing")
    }

    private static func fingerprintContracts(_ suite: TestSuite) {
        func image(_ fill: (CGContext) -> Void) -> CGImage? {
            guard let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            fill(context)
            return context.makeImage()
        }
        let empty = image { $0.setFillColor(gray: 0.1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 32)) }
        let half = image {
            $0.setFillColor(gray: 0.1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            $0.setFillColor(gray: 0.9, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let a = empty.flatMap(NotchWatchSupport.fingerprint)
        let b = empty.flatMap(NotchWatchSupport.fingerprint)
        let c = half.flatMap(NotchWatchSupport.fingerprint)
        suite.expect(a != nil && NotchWatchSupport.sameFingerprint(a, b), "the same picture reads the same")
        suite.expect(!NotchWatchSupport.sameFingerprint(a, c), "a progress bar that moved reads as a change")
        suite.expect(NotchWatchSupport.signature(text: "  Done ", fingerprint: c) == "done"
                        && NotchWatchSupport.signature(text: "", fingerprint: c)?.hasPrefix("image:") == true,
                     "text decides when there is any, the picture otherwise")
    }

    private static func gateContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-watch"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults), "Watch needs the island")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchWatchSupport.isEnabled(in: defaults) && NotchSupport.routes(.watch, in: defaults)
                        && NotchSupport.modules(in: defaults).contains(.watch),
                     "with the island on, the page and its alerts are there by default")
        suite.expect(NotchWatchCondition.saved(in: defaults) == .changes, "a first watch speaks up on any change")
        defaults.set("settles", forKey: DefaultsKey.notchWatchCondition)
        suite.expect(NotchWatchCondition.saved(in: defaults) == .settles, "the last rule chosen is kept")
        defaults.set("watch", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults) && !NotchSupport.routes(.watch, in: defaults),
                     "a hidden page stops watching")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: DefaultsKey.notchWatchEnabled)
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults) && !NotchSupport.modules(in: defaults).contains(.watch),
                     "its own switch removes the page")
        defaults.set(true, forKey: DefaultsKey.notchWatchEnabled)
        defaults.set(false, forKey: AppFeature.notchWatch.availabilityKey)
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults), "uninstalling the feature turns it off")
        suite.expect(NotchSupport.compactActivities(timer: true, watch: true, downloads: true, agents: false,
                                                    calendar: false, music: true) == [.timer, .watch, .downloads, .music],
                     "a watch follows the timer in the closed island's automatic order")
        suite.expect(AppFeature.notchWatch.permissions == [.screenRecording, .notifications],
                     "Watch reads the area, and notifies where the island cannot show itself")
    }

    /// The service is not part of this test binary, so the reading loop's
    /// load-bearing lines are pinned at their source.
    private static func readingLoopContracts(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchWatchService.swift",
                                  encoding: .utf8)) ?? ""
        func line(_ fragment: String) -> Int? {
            source.components(separatedBy: "\n").enumerated().first { _, line in
                let code = line.trimmingCharacters(in: .whitespaces)
                return !code.hasPrefix("//") && code.contains(fragment)
            }.map { $0.offset + 1 }
        }
        suite.expect(line("tracker.observe(signature: signature, reading: text, at: Date())") != nil
                        && line("tracker.observe(signature: nil") == nil,
                     "a still area comes back with its last signature, so a change that holds is confirmed")
        if let recognized = line("fallbackLanguages: languages"), let kept = line("fingerprint = picture") {
            suite.expect(kept > recognized, "an area is marked as read only once its reading is kept")
        } else {
            suite.expect(false, "the reading loop still reads text and keeps the area's picture")
        }
        if let permission = line("guard CGPreflightScreenCaptureAccess() else"),
           let capture = line("await WindowPreviewProvider.captureViaWindowServer(windowID)"),
           let region = line("await regionCapture?.image()") {
            suite.expect(permission < capture && permission < region,
                         "without Screen Recording nothing is captured, so the system is not asked again")
        } else {
            suite.expect(false, "the reading loop still checks Screen Recording before capturing")
        }
    }
}
