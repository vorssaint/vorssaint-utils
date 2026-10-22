// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The identity of a quick tool's global hotkey.
///
/// `QuickToolHotkey` routes a press by looking its owner up in one
/// process-wide dictionary keyed by the id it was built with, so two tools
/// sharing an id do not both work: the second registration replaces the
/// first, and the first tool's unregister takes the second's entry with it.
/// `QuickToolHotkey.sync` refuses an id another tool already holds, so a
/// repeat is turned away at registration rather than silently splitting a
/// key between two tools.
///
/// This suite reads the hand-written ids out of the tree and keeps them
/// unique there, which catches the mistake before it reaches a Mac.
enum QuickToolHotkeyIdentityTests {
    static func run(_ suite: TestSuite) {
        let sources = ((try? FileManager.default.contentsOfDirectory(atPath: "Sources")) ?? [])
        suite.expect(!sources.isEmpty, "the quick tool hotkey guard finds the source tree")

        var ids: [UInt32: [String]] = [:]
        for path in swiftFiles(under: "Sources") {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            for (id, owner) in registeredIDs(in: source, path: path) {
                ids[id, default: []].append(owner)
            }
        }

        suite.expect(!ids.isEmpty, "the quick tool hotkey guard discovers registered hotkey ids")

        let shared = ids.filter { $0.value.count > 1 }
        suite.expect(shared.isEmpty,
                     "every quick tool hotkey id is used by one owner only: "
                     + shared.map { "\($0.key) in \($0.value.joined(separator: ", "))" }
                        .sorted().joined(separator: "; "))
    }

    /// Every Swift file under a folder, in a stable order.
    private static func swiftFiles(under folder: String) -> [String] {
        let entries = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
        var found: [String] = []
        for entry in entries.sorted() {
            let path = folder + "/" + entry
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                found.append(contentsOf: swiftFiles(under: path))
            } else if entry.hasSuffix(".swift") {
                found.append(path)
            }
        }
        return found
    }

    /// The ids a file registers, with the file that registers them.
    ///
    /// Only a literal id is read. A tool that hands the initializer a
    /// computed id — a running count, an offset from a base — is not seen
    /// here, because the value it will take is not in the source. Those
    /// are covered at the point they matter instead: `QuickToolHotkey.sync`
    /// refuses an id another tool already holds, so a computed id that
    /// reaches a taken one is turned away at registration.
    private static func registeredIDs(in source: String, path: String) -> [(UInt32, String)] {
        var found: [(UInt32, String)] = []
        var remainder = Substring(source)
        while let call = remainder.range(of: "QuickToolHotkey(id: ") {
            let tail = remainder[call.upperBound...]
            let digits = tail.prefix { $0.isNumber }
            guard !digits.isEmpty, let id = UInt32(digits) else {
                remainder = remainder[call.upperBound...]
                continue
            }
            found.append((id, path))
            remainder = remainder[call.upperBound...]
        }
        return found
    }
}
