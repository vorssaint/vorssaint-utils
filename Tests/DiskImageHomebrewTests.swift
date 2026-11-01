// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production mount inspection and candidate selection with a controlled
/// hdiutil response and temporary directories. No disk image is mounted and
/// no app is installed or opened.
enum DiskImageHomebrewTests {
    final class Queue {
        var work: [() -> Void] = []
        func async(_ block: @escaping () -> Void) { work.append(block) }
        func drain() {
            let pending = work
            work = []
            pending.forEach { $0() }
        }
    }
    enum DispatchQueue { static let main = Queue() }
    final class Files: Foundation.FileManager, @unchecked Sendable {
        var root: URL!
        override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
            [root.appendingPathComponent(directory == .libraryDirectory ? "Library" : "Applications",
                                          isDirectory: true)]
        }
    }
    enum FileManager { static let `default` = Files() }
    struct UserDefaults {
        static let standard = Self()
        func bool(forKey key: String) -> Bool { false }
    }
    enum DefaultsKey { static let diskImageInstallerUseUserApplications = "fixture" }
    class Fixture {
        static var info = Data()
        // An active cask operation must not suppress another app's image.
        static var isHomebrewInstallingApp = true
        static func run(_ executable: String, arguments: [String]) -> CommandResult {
            CommandResult(status: 0, output: info)
        }
        let workQueue = Queue()
        var mountObserver: Bool? = true
        var processingMounts = Set<String>()
        var pending: [Candidate] = []
        var prompts = 0
        func presentNextCandidate() { prompts += 1 }
    }

    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = Foundation.FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-dmg-homebrew-\(UUID())", isDirectory: true)
        fm.root = root
        defer {
            try? fm.removeItem(at: root)
            fm.root = nil
            Fixture.info = Data()
            DispatchQueue.main.work = []
        }
        do {
            let mount = root.appendingPathComponent("Mount", isDirectory: true)
            let app = mount.appendingPathComponent("Fixture-\(UUID()).app", isDirectory: true)
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            let bin = contents.appendingPathComponent("MacOS", isDirectory: true)
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            let executable = bin.appendingPathComponent("fixture")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let plist: [String: String] = ["CFBundleExecutable": "fixture", "CFBundleIdentifier": "test.fixture",
                                           "CFBundlePackageType": "APPL", "CFBundleName": "Fixture"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            let library = root.appendingPathComponent("Library", isDirectory: true)
            let cache = library.appendingPathComponent("Caches/Homebrew", isDirectory: true)
            let cached = cache.appendingPathComponent("downloads/example.dmg")
            let manual = root.appendingPathComponent("Downloads/manual.dmg")
            let sibling = library.appendingPathComponent("Caches/Homebrew-backup/example.dmg")
            for url in [cached, manual, sibling] {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([0]).write(to: url)
            }
            let linked = root.appendingPathComponent("cache-link", isDirectory: true)
            try fm.createSymbolicLink(at: linked, withDestinationURL: cache)
            suite.expect(Service.isHomebrewImage(cached)
                         && Service.isHomebrewImage(linked.appendingPathComponent("downloads/example.dmg")),
                         "cached Homebrew images and symlinks into that cache are excluded")
            suite.expect(!Service.isHomebrewImage(manual) && !Service.isHomebrewImage(sibling),
                         "manual downloads and similarly named sibling folders are retained")
            func info(_ image: URL) throws {
                Fixture.info = try PropertyListSerialization.data(fromPropertyList: [
                    "images": [["image-path": image.path, "system-entities": [["mount-point": mount.path]]]],
                ], format: .xml, options: 0)
            }
            let service = Service()
            try info(cached)
            suite.expect(service.candidate(mountedAt: mount) == nil,
                         "production candidate selection rejects a Homebrew cache mount")
            try info(manual)
            suite.expect(service.candidate(mountedAt: mount)?.imageURL == manual,
                         "production candidate selection retains a manual app image")
            service.inspect(mountURL: mount)
            service.inspect(mountURL: mount)
            suite.expect(service.workQueue.work.count == 1,
                         "one manual mount is inspected even during a cask install, without duplicate work")
            service.workQueue.drain()
            DispatchQueue.main.drain()
            suite.expect(service.prompts == 1 && service.pending.first?.imageURL == manual
                         && service.processingMounts.isEmpty,
                         "a manual mount still reaches its prompt while Homebrew is active")

            let disabled = Service()
            disabled.inspect(mountURL: mount)
            disabled.workQueue.drain()
            disabled.mountObserver = nil
            DispatchQueue.main.drain()
            suite.expect(disabled.prompts == 0 && disabled.pending.isEmpty,
                         "stopping the installer still rejects a late inspection result")
            let stopped = Service()
            stopped.mountObserver = nil
            stopped.inspect(mountURL: mount)
            suite.expect(stopped.workQueue.work.isEmpty,
                         "a disabled installer does not inspect new mounts")
        } catch {
            suite.expect(false, "disk image fixture failed: \(error)")
        }
    }
}
