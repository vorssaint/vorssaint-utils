// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// The stable helper Cursor launches. `hooks.json` points here, so moving the
/// app does not break a connection. Connect creates the copy; each launch
/// replaces it when the bundled helper has changed.
enum CursorHookInstall {
    static func bundledHelperURL(bundle: Bundle = .main) -> URL? {
        guard bundle.bundleURL.pathExtension == "app" else { return nil }
        let url = bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(CursorHookProtocol.helperName)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func liveInstalledHelperURL() -> URL? {
        guard let container = PrivateFileStore.containerURL else { return nil }
        return installedHelperURL(container: container)
    }

    @discardableResult
    static func installLiveCopy() -> Bool {
        guard let bundled = bundledHelperURL(), let installed = liveInstalledHelperURL() else { return false }
        return install(bundled: bundled, installed: installed)
    }

    static func installedHelperURL(container: URL) -> URL {
        container
            .appendingPathComponent(CursorHookProtocol.directoryName, isDirectory: true)
            .appendingPathComponent(CursorHookProtocol.helperName)
    }

    static func refreshInstalledCopyIfPresent() {
        guard let bundled = bundledHelperURL(),
              let container = PrivateFileStore.containerURL else { return }
        let installed = installedHelperURL(container: container)
        guard FileManager.default.fileExists(atPath: installed.path) else { return }
        _ = refresh(bundled: bundled, installed: installed)
    }

    /// Replaces an existing copy when its bytes differ. Does not create one.
    @discardableResult
    static func refresh(bundled: URL, installed: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: installed.path) else { return false }
        guard signatureIsValid(bundled), let bundledHash = hash(of: bundled) else { return false }
        if hash(of: installed) == bundledHash {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
            return signatureIsValid(installed)
        }
        return write(bundled: bundled, to: installed)
    }

    /// Creates or replaces the stable copy. Used when the person connects.
    @discardableResult
    static func install(bundled: URL, installed: URL) -> Bool {
        guard signatureIsValid(bundled) else { return false }
        return write(bundled: bundled, to: installed)
    }

    private static func write(bundled: URL, to installed: URL) -> Bool {
        let directory = installed.deletingLastPathComponent()
        let container = directory.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: container.path) {
            guard CursorHookProtocol.createOwnerOnlyDirectory(container.path) else { return false }
        }
        guard CursorHookProtocol.createOwnerOnlyDirectory(directory.path) else { return false }
        let incoming = installed.appendingPathExtension("incoming")
        let manager = FileManager.default
        try? manager.removeItem(at: incoming)
        guard run("/usr/bin/ditto", [bundled.path, incoming.path]) else { return false }
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: incoming.path)
        _ = run("/usr/bin/xattr", ["-c", incoming.path])
        guard signatureIsValid(incoming) else {
            try? manager.removeItem(at: incoming)
            return false
        }
        do {
            if manager.fileExists(atPath: installed.path) {
                _ = try manager.replaceItemAt(installed, withItemAt: incoming)
            } else {
                try manager.moveItem(at: incoming, to: installed)
            }
        } catch {
            try? manager.removeItem(at: incoming)
            return false
        }
        _ = run("/usr/bin/xattr", ["-c", installed.path])
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
        return signatureIsValid(installed)
    }

    private static func signatureIsValid(_ url: URL) -> Bool {
        run("/usr/bin/codesign", ["--verify", "--strict", url.path])
    }

    static func hash(of url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Data(SHA256.hash(data: data))
    }

    @discardableResult
    private static func run(_ program: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
