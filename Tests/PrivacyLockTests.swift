// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Privacy Lock's rules and its encryption, against real temporary files: a
/// file and a folder lock and unlock, a wrong password and a tampered
/// container are refused, and nothing that must stay lockable-proof is lockable.
enum PrivacyLockTests {
    static func run(_ suite: TestSuite) {
        // MARK: Passwords

        suite.expect(PrivacyLockSupport.passwordProblem("short", confirmation: nil) == .tooShort,
                     "a password under the minimum length is refused")
        suite.expect(PrivacyLockSupport.passwordProblem("long enough", confirmation: "long enougH") == .mismatch,
                     "two different entries are refused")
        suite.expect(PrivacyLockSupport.passwordProblem("long enough", confirmation: "long enough") == nil,
                     "a long enough password that matches is accepted")

        let record = PrivacyLockSupport.makePasswordRecord("correct horse", iterations: 1_000)
        suite.expect(record.map { PrivacyLockSupport.verify("correct horse", against: $0) } == true,
                     "the stored hash accepts the right password")
        suite.expect(record.map { PrivacyLockSupport.verify("correct horsf", against: $0) } == false,
                     "the stored hash refuses a near miss")
        suite.expect(!PrivacyLockSupport.verify("anything", against: Data([1, 2, 3])),
                     "a damaged hash record verifies nothing")
        let again = PrivacyLockSupport.makePasswordRecord("correct horse", iterations: 1_000)
        suite.expect(record != again, "each hash gets a fresh salt")

        suite.expect(PrivacyLockSupport.lockoutSeconds(afterFailures: 4) == 0
                     && PrivacyLockSupport.lockoutSeconds(afterFailures: 5) == 30
                     && PrivacyLockSupport.lockoutSeconds(afterFailures: 6) == 60
                     && PrivacyLockSupport.lockoutSeconds(afterFailures: 99) == 3600,
                     "wrong passwords are met with a growing wait that stops at an hour")

        // MARK: What may be locked

        let home = URL(fileURLWithPath: "/Users/someone")
        suite.expect(!PrivacyLockSupport.isLockable(URL(fileURLWithPath: "/System/Library"), home: home)
                     && !PrivacyLockSupport.isLockable(home, home: home)
                     && !PrivacyLockSupport.isLockable(home.appendingPathComponent("Library"), home: home)
                     && !PrivacyLockSupport.isLockable(URL(fileURLWithPath: "/Applications/Safari.app"), home: home),
                     "the system, the home folder and its Library are never locked")
        suite.expect(PrivacyLockSupport.isLockable(home.appendingPathComponent("Documents/taxes.pdf"), home: home),
                     "an ordinary document is lockable")

        suite.expect(!PrivacyLockSupport.canLock(bundleID: "com.apple.finder", ownBundleID: "com.vorssaint.utils")
                     && !PrivacyLockSupport.canLock(bundleID: "com.vorssaint.utils", ownBundleID: "com.vorssaint.utils")
                     && PrivacyLockSupport.canLock(bundleID: "com.apple.Notes", ownBundleID: "com.vorssaint.utils"),
                     "Finder and Vorssaint itself can never be shielded")
        suite.expect(PrivacyLockSupport.lockedBundleIDs(from: "com.apple.Notes\ncom.apple.finder\ncom.apple.Notes\n",
                                                        ownBundleID: nil) == ["com.apple.Notes"],
                     "a restored list drops protected and repeated apps")
        suite.expect(PrivacyLockSupport.safeComponent("../../etc/passwd") == "passwd"
                     && PrivacyLockSupport.safeComponent("..") == nil,
                     "a name read from a container cannot point outside its folder")
        suite.expect(PrivacyLockSupport.uniqueName("a.txt", exists: { $0 == "a.txt" || $0 == "a 2.txt" }) == "a 3.txt",
                     "a taken name gets the next free number before its extension")

        // MARK: Quick Action links

        let tricky = ["/Users/a/My Docs/\u{e9}t\u{e9} & \"quotes\" + plus.txt", "/tmp/a/b"]
        let link = PrivacyLockLink.url(action: .lockItems, paths: tricky)
        let parsed = link.flatMap(PrivacyLockLink.parse)
        suite.expect(parsed?.action == .lockItems && parsed?.paths.map(\.path) == tricky,
                     "file names with spaces, accents and symbols survive the trip through a link")
        suite.expect(PrivacyLockLink.parse(URL(string: "vorssaint://privacy-lock/lock?p=bm90YXBhdGg")!) == nil,
                     "a path that is not absolute is refused")
        suite.expect(PrivacyLockLink.parse(URL(string: "vorssaint://other/lock?p=L3RtcA")!) == nil
                     && PrivacyLockLink.parse(URL(string: "vorssaint://privacy-lock/explode?p=L3RtcA")!) == nil,
                     "a link for another place or an unknown action is ignored")
        suite.expect(PrivacyLockQuickActions.script(for: .toggleApps).contains("privacy-lock/toggle-app?"),
                     "each Quick Action opens the link of its own action")

        // MARK: Encryption on disk

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("PrivacyLockTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("note.txt")
            var payload = Data()
            for index in 0..<300_000 { payload.append(UInt8(index % 251)) }
            try payload.write(to: file)
            let id = try LockedItemVault.randomItemID()
            let container = try LockedItemVault.createContainer(from: file, password: "swordfish-1", itemID: id)
            suite.expect(container.lastPathComponent == "note.txt.vslock" && fm.fileExists(atPath: file.path),
                         "locking writes the container beside the original and leaves the original alone")
            let raw = try Data(contentsOf: container)
            suite.expect(raw.range(of: Data("note.txt".utf8)) == nil && raw.range(of: payload.prefix(64)) == nil,
                         "neither the name nor the content is readable in the container")
            suite.expect((try? LockedItemVault.readHeader(of: container))?.itemID == id,
                         "the header carries the item id used for a remembered password")

            do {
                _ = try LockedItemVault.unlock(container: container, password: "swordfish-2")
                suite.expect(false, "a wrong password must not open the container")
            } catch LockedItemError.wrongPassword {
                suite.expect(true, "a wrong password is reported as such")
            }
            try fm.removeItem(at: file)
            let restored = try LockedItemVault.unlock(container: container, password: "swordfish-1")
            let restoredData = try Data(contentsOf: restored.url)
            suite.expect(restored.name == "note.txt" && restoredData == payload
                         && !fm.fileExists(atPath: container.path),
                         "the right password restores the exact file and removes the container")

            // Tampering is caught.
            let second = try LockedItemVault.createContainer(from: restored.url, password: "swordfish-1", itemID: id)
            var bytes = try Data(contentsOf: second)
            bytes[bytes.count - 20] ^= 0xFF
            try bytes.write(to: second)
            do {
                _ = try LockedItemVault.unlock(container: second, password: "swordfish-1")
                suite.expect(false, "a tampered container must not open")
            } catch {
                suite.expect(true, "a changed byte is detected and nothing is restored")
            }

            // Folders.
            let folder = root.appendingPathComponent("Taxes", isDirectory: true)
            try fm.createDirectory(at: folder.appendingPathComponent("2025"), withIntermediateDirectories: true)
            try Data("one".utf8).write(to: folder.appendingPathComponent("a.txt"))
            try Data("two".utf8).write(to: folder.appendingPathComponent("2025/b.txt"))
            let folderContainer = try LockedItemVault.createContainer(from: folder, password: "folder-pass-9", itemID: id)
            try fm.removeItem(at: folder)
            let opened = try LockedItemVault.unlock(container: folderContainer, password: "folder-pass-9")
            suite.expect(opened.name == "Taxes"
                         && (try? String(contentsOf: opened.url.appendingPathComponent("2025/b.txt"), encoding: .utf8)) == "two"
                         && (try? String(contentsOf: opened.url.appendingPathComponent("a.txt"), encoding: .utf8)) == "one",
                         "a locked folder comes back whole, subfolders included")
            suite.expect(((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).allSatisfy { !$0.hasPrefix(".vss-") },
                         "no working folder is left behind")
        } catch {
            suite.expect(false, "the vault round trip ran without an error: \(error)")
        }

        // MARK: Catalog and words

        suite.expect(AppFeature.privacyLock.installedByDefault == false
                     && Defaults.registeredDefaults[DefaultsKey.privacyLockEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.appLockEnabled] as? Bool == false,
                     "Privacy Lock is never installed or switched on by an update")
        for lang in AppLanguage.allCases {
            let strings = FeatureStrings.privacyLock(lang)
            suite.expect(!strings.title.isEmpty && !strings.hubDescription.isEmpty && !strings.lockMenuName.isEmpty,
                         "Privacy Lock has its title, description and menu names in \(lang)")
            suite.expect(!strings.tabApps.isEmpty && !strings.quickActionsHint.isEmpty
                         && strings.appsCountFormat.contains("%d") && strings.itemsCountFormat.contains("%d"),
                         "the tabs, the Finder card and the counts have their words in \(lang)")
            suite.expect(!FeatureStrings.authenticationGroupTitle(lang).isEmpty,
                         "the Authentication group is named in \(lang)")
            suite.expect(strings.shieldTitleFormat.contains("%@") && strings.lockPromptTitleFormat.contains("%@")
                         && strings.shortPasswordFormat.contains("%d") && strings.shieldWaitFormat.contains("%d"),
                         "every format string keeps its placeholder in \(lang)")
        }
    }
}
