// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum DockEnhancementTests {
    static func run(_ suite: TestSuite) {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let below = CGRect(x: 200, y: 800, width: 400, height: 500)
        let frames = [primary, right, below]
        suite.expect(DockLockSupport.exposed(primary, screens: frames, orientation: .bottom) == [0...200, 600...1000], "partially covered bottom edges preserve both exposed intervals")
        suite.expect(DockLockSupport.exposed(primary, screens: frames, orientation: .right).isEmpty, "a shared edge remains traversable")
        suite.expect(DockLockSupport.zones(screens: frames, locked: 0, orientation: .bottom).allSatisfy { !$0.rect.intersects(primary) && $0.dy < 0 }, "lock nudges only non-target exposed edges inward")
        suite.expect(DockLockSupport.zones(screens: frames, locked: -1, orientation: .bottom).isEmpty && DockLockSupport.zones(screens: [primary], locked: 0, orientation: .bottom).isEmpty, "invalid or single-display locks do nothing")
        suite.expect(DockLockSupport.zones(screens: [primary, right], locked: 0, orientation: .right).isEmpty, "fully covered target edges do not strand the Dock")
        let path = DockLockSupport.relocationPath(frame: primary, screens: frames, orientation: .bottom)
        suite.expect(path?.1.y == 799 && (path?.1.x ?? 0) > 600, "relocation approaches the largest exposed interval rather than a covered edge")
        let negative = CGRect(x: -1000, y: -200, width: 1000, height: 800)
        suite.expect(DockLockSupport.zones(screens: [primary, negative], locked: 0, orientation: .left).first?.rect.minX == -1000, "lock supports displays left of the primary coordinate origin")

        suite.expect(DockEnhancementSupport.isCompact(count: 1, forced: false, threshold: 0, canCapture: false), "no capture permission still exposes usable titles")
        suite.expect(!DockEnhancementSupport.isCompact(count: 1, forced: false, threshold: 0, canCapture: true), "zero threshold preserves thumbnail mode")
        suite.expect(DockEnhancementSupport.isCompact(count: 4, forced: false, threshold: 4, canCapture: true), "compact threshold includes its boundary")
        suite.expect(DockEnhancementSupport.titleIsExcluded("Private – résumé", filters: "  \n RESUME \n"), "title filters ignore empty terms, case and accents")
        suite.expect(!DockEnhancementSupport.titleIsExcluded("Public window", filters: "Private\nSecret"), "title filters do not remove unrelated windows")
        suite.expect(DockEnhancementSupport.fuzzyMatches("safri resume", in: "Safari Résumé", tolerance: 1), "bounded fuzzy search matches every token with an optional typo")
        suite.expect(!DockEnhancementSupport.fuzzyMatches("safri", in: "Safari", tolerance: 0), "exact search stays exact by default")
        suite.expect(!DockEnhancementSupport.fuzzyMatches(String(repeating: "x", count: 1000), in: "Safari", tolerance: 3), "long fuzzy queries are bounded")
        suite.expect(DockOption.trigger.sanitizedString("unsupported") == "hover" && DockOption.windowTitleFilters.sanitizedString("Private") == "Private", "unknown option values fall back safely while free-form filters are preserved")
        suite.expect(DockEnhancementSupport.usableLanes(requested: 4, count: 12, available: 900, cardSize: 240, spacing: 8, padding: 16, header: 0) == 3, "grid lanes fit the available cross-axis dimension")
        suite.expect(DockEnhancementSupport.usableLanes(requested: 4, count: 12, available: 200, cardSize: 240, spacing: 8, padding: 16, header: 0) == 1, "small displays preserve a single scrollable lane")
        suite.expect(DockEnhancementSupport.hexRGB(" #ff00AC ") == 0xFF00AC && DockEnhancementSupport.hexRGB("bad-color") == 0x4C8DFF, "hex colors support an optional hash and reject malformed values")
        suite.expect(DockProcessIdentity.matches("__CFBundleIdentifier=app.launcher\0HOME=/unrelated\0", launcher: "app.launcher", storage: nil), "Parall instances match exact launch identities")
        suite.expect(!DockProcessIdentity.matches("__CFBundleIdentifier=app.launcher.other\0--path=/storage-extra\0", launcher: "app.launcher", storage: "/storage"), "similar launch IDs and path prefixes do not cross-wire app instances")
        suite.expect(DockProcessIdentity.matches("--user-data-dir=/storage/Profile\0", launcher: nil, storage: "/storage"), "Parall instances can match a bounded storage path argument")
        let icon = CGRect(x: 50, y: 0, width: 40, height: 40)
        let line = DockEnhancementSupport.indicatorFrame(icon: icon, orientation: .bottom, thickness: .nan, length: 200, offset: .infinity)
        suite.expect(line.width == 40 && line.height == 3 && line.minY == 3, "indicator geometry bounds lengths and rejects nonfinite preferences")
        let leftLine = DockEnhancementSupport.indicatorFrame(icon: icon, orientation: .left, thickness: 2, length: 20, offset: 4)
        suite.expect(leftLine.width == 2 && leftLine.height == 20 && leftLine.minX == 54, "side Dock indicator rotates along the icon edge")

        for value: Any in [true, false, 0, -1, 3.5, Double.nan, Double.infinity, Double(UInt32.max) + 1, "42"] {
            suite.expect(DockScriptSupport.identifier(value) == nil, "script IDs reject booleans, fractions, nonfinite, out of range and string coercions")
        }
        suite.expect(DockScriptSupport.identifier(42) == 42 && DockScriptSupport.identifier(UInt32.max) == UInt32.max, "script IDs preserve the complete nonzero CGWindowID range")
        suite.expect((try? DockScriptSupport.arguments("[]")) == nil && (try? DockScriptSupport.arguments(String(repeating: " ", count: 20_000))) == nil, "script parsing rejects arrays and oversized input")
        suite.expect((try? DockScriptSupport.arguments("{\"id\":42}"))?["id"] as? Int == 42, "script parsing preserves JSON number identity")
        suite.expect(DockScriptSupport.frame(["x": 0, "y": 0, "width": 600, "height": 400])?.size == CGSize(width: 600, height: 400), "valid script geometry is preserved")
        suite.expect(DockScriptSupport.frame(["x": true, "y": 0, "width": 600, "height": 400]) == nil && DockScriptSupport.frame(["x": 0, "y": 0, "width": -1, "height": 400]) == nil, "script frames refuse bool coercions and negative sizes")

        let root = URL(fileURLWithPath: "/fixture")
        let entries = [DockFolderEntry(url: root.appendingPathComponent("file2"), name: "file2", directory: false, modified: .distantPast, size: 2),
            DockFolderEntry(url: root.appendingPathComponent("file10"), name: "file10", directory: false, modified: .distantFuture, size: 10),
            DockFolderEntry(url: root.appendingPathComponent("dir"), name: "dir", directory: true, modified: .distantPast, size: 0)]
        suite.expect(DockFolderSupport.sorted(entries, by: "name", descending: false).map(\.name) == ["dir", "file2", "file10"], "folder browser uses natural filename sorting with directories first")
        suite.expect(DockFolderSupport.sorted(entries, by: "size", descending: true).map(\.name) == ["dir", "file10", "file2"], "folder sorting honors descending metadata without moving directories last")

        var consumers = NotchMusicConsumers()
        consumers.acquire(.dock); consumers.acquire(.island); consumers.acquire(.dock)
        suite.expect(consumers.owners.count == 2 && !consumers.release(.island), "repeated syncs are idempotent and island teardown preserves Dock music")
        consumers.acquire(.lockScreen)
        suite.expect(!consumers.release(.dock) && consumers.release(.lockScreen), "the adapter stops only after the last surface releases it")

        var shake = PreviewShakeDetector()
        suite.expect(!shake.sample(.zero, at: 1) && !shake.sample(CGPoint(x: 30, y: 0), at: 1.1), "ordinary dragging is not a shake")
        suite.expect(!shake.sample(.zero, at: 1.2) && !shake.sample(CGPoint(x: 30, y: 0), at: 1.3) && shake.sample(.zero, at: 1.4), "three deliberate reversals recognize a shake")
        var slow = PreviewShakeDetector()
        for (index, x) in [0, 30, 0, 30, 0].enumerated() { suite.expect(!slow.sample(CGPoint(x: x, y: 0), at: Double(index)), "slow drag reversals do not minimize other windows") }

        var detector = TrackpadSwipeDetector()
        func touches(_ x: CGFloat, count: Int = 3) -> [SwipeTouch] { (0..<count).map { SwipeTouch(id: $0, position: CGPoint(x: 0.2 + x, y: 0.5)) } }
        suite.expect(detector.handle(touches(0), fingers: 3, horizontal: true) == nil, "trackpad samples establish identity before opening")
        suite.expect(detector.handle(touches(0.05), fingers: 3, horizontal: true) == .open, "three fingers open after coherent travel")
        suite.expect(detector.handle(touches(0.21), fingers: 3, horizontal: true) == .cycleForward, "travel after opening advances the selection")
        suite.expect(detector.handle(touches(0.14), fingers: 3, horizontal: true) == .cycleBackward, "reversing direction cycles backward")
        suite.expect(detector.handle([], fingers: 3, horizontal: true) == .release, "lifting fingers commits the external session")
        var extra = TrackpadSwipeDetector()
        suite.expect(extra.handle(touches(0, count: 4), fingers: 3, horizontal: true) == nil && extra.handle(touches(0.2), fingers: 3, horizontal: true) == nil, "an extra finger invalidates a three-finger gesture until lift")
        _ = extra.handle([], fingers: 3, horizontal: true)
        _ = extra.handle(touches(0, count: 4), fingers: 4, horizontal: true)
        suite.expect(extra.handle(touches(0.05, count: 4), fingers: 4, horizontal: true) == .open, "four-finger mode is independently selectable")

        for language in AppLanguage.allCases {
            for term in DockEnhancementStrings.Term.allCases {
                suite.expect(!DockEnhancementStrings.text(term, language: language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "every Dock option has text in every supported language")
            }
        }
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DockOption.folderSortChoices.key) && !SettingsBackupSupport.exportKeys().contains(DockOption.lockDisplay.key), "machine-specific folder paths and display IDs never enter portable backups")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DockOption.indicatorColor.key) && SettingsBackupSupport.exportKeys().contains(DockOption.trackpadFingers.key), "portable visual and input preferences are backed up")
        suite.expect(AppFeature.dockIndicator.permissions == [.accessibility] && AppFeature.dockLock.permissions == [.accessibility], "indicator and lock never require screen capture")
        suite.expect(!AppFeature.dockIndicator.installedByDefault && !AppFeature.dockLock.installedByDefault, "new standalone features do not run on existing installations without opt-in")
    }
}
