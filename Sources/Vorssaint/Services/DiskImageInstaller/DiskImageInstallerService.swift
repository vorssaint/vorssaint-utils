// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

final class DiskImageInstallerService {
    static let shared = DiskImageInstallerService()

    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct Candidate {
        let mountURL: URL
        let appURL: URL
        let imageURL: URL
        let imageIdentity: FileIdentity
        let destinationURL: URL
        let displayName: String
    }

    private enum InstallFailure {
        case alreadyInstalled
        case verification
        case copy
    }

    private enum InstallOutcome {
        case installed
        case installedKeepingMount
        case installedKeepingDownload
        case failed(InstallFailure)
    }

    private struct CommandResult {
        let status: Int32
        let output: Data
    }

    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.disk-image-installer",
                                          qos: .utility)
    private var mountObserver: NSObjectProtocol?
    private var pending: [Candidate] = []
    private var processingMounts = Set<String>()
    private var promptActive = false

    private init() {}

    func syncWithPreferences() {
        precondition(Thread.isMainThread)
        AppFeature.diskImageInstaller.isAvailable ? start() : stop()
    }

    private func start() {
        guard mountObserver == nil else { return }
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mountURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
                return
            }
            self?.inspect(mountURL: mountURL)
        }
    }

    private func stop() {
        if let mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(mountObserver)
        }
        mountObserver = nil
        pending.removeAll()
        processingMounts.removeAll()
    }

    private func inspect(mountURL: URL) {
        guard mountObserver != nil else { return }
        let path = mountURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard processingMounts.insert(path).inserted else { return }

        workQueue.async { [weak self] in
            let candidate = self?.candidate(mountedAt: mountURL)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.processingMounts.remove(path)
                guard self.mountObserver != nil, let candidate else { return }
                self.pending.append(candidate)
                self.presentNextCandidate()
            }
        }
    }

    private func candidate(mountedAt mountURL: URL) -> Candidate? {
        let fm = FileManager.default
        let info = Self.run("/usr/bin/hdiutil", arguments: ["info", "-plist"])
        guard info.status == 0,
              let imageURL = DiskImageInstallerSupport.imageURL(mountedAt: mountURL,
                                                                 hdiutilInfo: info.output),
              let imageIdentity = Self.fileIdentity(at: imageURL),
              let entries = try? fm.contentsOfDirectory(at: mountURL,
                                                        includingPropertiesForKeys: [
                                                            .isDirectoryKey,
                                                            .isSymbolicLinkKey,
                                                        ],
                                                        options: [.skipsHiddenFiles])
        else { return nil }

        let apps = entries.filter { url in
            guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey,
                                                                  .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { return false }
            return Self.validBundle(at: url)
        }
        guard apps.count == 1, let appURL = apps.first,
              let destinationURL = DiskImageInstallerSupport.destinationURL(
                for: appURL,
                applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true)),
              !fm.fileExists(atPath: destinationURL.path)
        else { return nil }

        let preferredName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return Candidate(mountURL: mountURL,
                         appURL: appURL,
                         imageURL: imageURL,
                         imageIdentity: imageIdentity,
                         destinationURL: destinationURL,
                         displayName: DiskImageInstallerSupport.displayName(preferred: preferredName,
                                                                            appURL: appURL))
    }

    private func presentNextCandidate() {
        guard !promptActive, mountObserver != nil, let candidate = pending.first else { return }
        pending.removeFirst()
        promptActive = true

        let strings = FeatureStrings.diskImageInstaller(L10n.shared.language)
        let alert = NSAlert()
        alert.messageText = strings.promptTitle
        alert.informativeText = String(format: strings.promptBodyFormat, candidate.displayName)
        alert.icon = NSWorkspace.shared.icon(forFile: candidate.appURL.path)
        alert.addButton(withTitle: strings.installButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            finishCurrentCandidate()
            return
        }

        workQueue.async { [weak self] in
            let outcome = self?.install(candidate) ?? .failed(.copy)
            DispatchQueue.main.async { [weak self] in
                self?.present(outcome: outcome, candidate: candidate)
                self?.finishCurrentCandidate()
            }
        }
    }

    private func finishCurrentCandidate() {
        promptActive = false
        presentNextCandidate()
    }

    private func install(_ candidate: Candidate) -> InstallOutcome {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: candidate.destinationURL.path) else {
            return .failed(.alreadyInstalled)
        }

        let stagingDirectory: URL
        do {
            stagingDirectory = try fm.url(for: .itemReplacementDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: candidate.destinationURL.deletingLastPathComponent(),
                                          create: true)
        } catch {
            return .failed(.copy)
        }
        defer { try? fm.removeItem(at: stagingDirectory) }

        let stagedApp = stagingDirectory.appendingPathComponent(candidate.appURL.lastPathComponent,
                                                                 isDirectory: true)
        let copy = Self.run("/usr/bin/ditto", arguments: [
            "--rsrc", "--extattr", "--acl", "--qtn",
            candidate.appURL.path, stagedApp.path,
        ])
        guard copy.status == 0, Self.validBundle(at: stagedApp) else {
            return .failed(.copy)
        }
        guard Self.gatekeeperAccepts(stagedApp) else {
            return .failed(.verification)
        }

        do {
            guard !fm.fileExists(atPath: candidate.destinationURL.path) else {
                return .failed(.alreadyInstalled)
            }
            try fm.moveItem(at: stagedApp, to: candidate.destinationURL)
        } catch {
            return .failed(.copy)
        }

        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: candidate.mountURL)
        } catch {
            return .installedKeepingMount
        }

        guard Self.fileIdentity(at: candidate.imageURL) == candidate.imageIdentity else {
            return .installedKeepingDownload
        }
        do {
            try fm.trashItem(at: candidate.imageURL, resultingItemURL: nil)
            return .installed
        } catch {
            return .installedKeepingDownload
        }
    }

    private func present(outcome: InstallOutcome, candidate: Candidate) {
        let strings = FeatureStrings.diskImageInstaller(L10n.shared.language)
        let alert = NSAlert()
        alert.icon = NSWorkspace.shared.icon(forFile: candidate.destinationURL.path)
        switch outcome {
        case .installed:
            alert.messageText = strings.installedTitle
            alert.informativeText = String(format: strings.installedBodyFormat, candidate.displayName)
        case .installedKeepingMount:
            alert.alertStyle = .warning
            alert.messageText = strings.installedTitle
            alert.informativeText = String(format: strings.installedKeepingMountBodyFormat,
                                           candidate.displayName)
        case .installedKeepingDownload:
            alert.alertStyle = .warning
            alert.messageText = strings.installedTitle
            alert.informativeText = String(format: strings.installedKeepingDownloadBodyFormat,
                                           candidate.displayName)
        case let .failed(failure):
            alert.alertStyle = .warning
            alert.messageText = strings.failedTitle
            switch failure {
            case .alreadyInstalled:
                alert.informativeText = String(format: strings.alreadyInstalledBodyFormat,
                                               candidate.displayName)
            case .verification:
                alert.informativeText = strings.verificationFailedBody
            case .copy:
                alert.informativeText = strings.failedBody
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func validBundle(at appURL: URL) -> Bool {
        guard let bundle = Bundle(url: appURL),
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else { return false }
        let root = appURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let executable = executableURL.standardizedFileURL.resolvingSymlinksInPath().path
        return executable.hasPrefix(root)
    }

    private static func gatekeeperAccepts(_ appURL: URL) -> Bool {
        let signature = run("/usr/bin/codesign",
                            arguments: ["--verify", "--deep", "--strict", appURL.path])
        guard signature.status == 0 else { return false }
        let status = run("/usr/sbin/spctl", arguments: ["--status"])
        if String(data: status.output, encoding: .utf8)?.localizedCaseInsensitiveContains("disabled") == true {
            return true
        }
        return run("/usr/sbin/spctl", arguments: ["-a", "-t", "exec", appURL.path]).status == 0
    }

    private static func fileIdentity(at url: URL) -> FileIdentity? {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0,
              (info.st_mode & S_IFMT) == S_IFREG
        else { return nil }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func run(_ executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: Data())
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: data)
    }
}
