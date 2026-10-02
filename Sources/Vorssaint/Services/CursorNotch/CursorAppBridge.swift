// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Opens folders and prompt links in the Cursor app installed on this Mac.
enum CursorAppBridge {
    static let stableBundleID = CursorSessionReducer.cursorBundleID

    static func applicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: stableBundleID)
    }

    static func openFolder(_ path: String) -> Bool {
        guard let app = applicationURL(), !path.isEmpty else { return false }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: configuration)
        return true
    }

    static func openPrompt(text: String) -> Bool {
        guard applicationURL() != nil, let url = CursorPromptLink.url(text: text) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Opens the folder, then the prompt link once Cursor is in front, or after three seconds.
    static func openFolderThenPrompt(path: String, text: String) {
        guard openFolder(path) else { return }
        waitUntilCursorIsFront(attempts: 15) {
            _ = openPrompt(text: text)
        }
    }

    private static func waitUntilCursorIsFront(attempts: Int, then: @escaping () -> Void) {
        let front = NSWorkspace.shared.frontmostApplication
        let ready = attempts <= 0 || CursorSessionReducer.isCursorApp(bundleIdentifier: front?.bundleIdentifier,
                                                                        name: front?.localizedName)
        guard !ready else { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            waitUntilCursorIsFront(attempts: attempts - 1, then: then)
        }
    }

    static func focus(workspace: String) -> Bool {
        openFolder(workspace)
    }

    static func open(file: String) -> Bool {
        guard let app = applicationURL(), !file.isEmpty else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: file)], withApplicationAt: app, configuration: configuration)
        return true
    }
}
