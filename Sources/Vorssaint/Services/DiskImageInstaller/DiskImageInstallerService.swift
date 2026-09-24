// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation
import SwiftUI

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
        let displayName: String
    }

    private enum InstallFailure {
        case alreadyInstalled
        case verification
        case copy
    }

    private enum InstallOutcome {
        case installed(downloadTrashed: Bool)
        case installedKeepingMount
        case installedKeepingDownload
        case failed(InstallFailure)

        var isInstalled: Bool {
            if case .failed = self { return false }
            return true
        }
    }

    private struct InstallResult {
        let outcome: InstallOutcome
        let destinationURL: URL?
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
    private var installPrompt: NonModalAlert?
    private var progressPanel: NSPanel?

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
        installPrompt?.dismiss(with: .alertSecondButtonReturn)
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
        let useUserApplications = UserDefaults.standard.bool(
            forKey: DefaultsKey.diskImageInstallerUseUserApplications)
        guard apps.count == 1, let appURL = apps.first,
              let collisionURLs = DiskImageInstallerSupport.collisionURLs(for: appURL,
                useUserApplications: useUserApplications,
                fileManager: fm),
              collisionURLs.allSatisfy({ !fm.fileExists(atPath: $0.path) })
        else { return nil }

        let preferredName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return Candidate(mountURL: mountURL,
                         appURL: appURL,
                         imageURL: imageURL,
                         imageIdentity: imageIdentity,
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
        alert.icon = NSWorkspace.shared.icon(forFile: candidate.appURL.path)
        alert.addButton(withTitle: strings.installButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)

        let defaults = UserDefaults.standard
        let trashDownload = NSButton(checkboxWithTitle: strings.trashDownloadOption, target: nil, action: nil)
        trashDownload.state = defaults.bool(forKey: DefaultsKey.diskImageInstallerTrashesDownload) ? .on : .off
        let revealApp = NSButton(checkboxWithTitle: strings.revealAppOption, target: nil, action: nil)
        revealApp.state = defaults.bool(forKey: DefaultsKey.diskImageInstallerRevealsApp) ? .on : .off
        let destinationPrompt = DiskImageInstallDestinationPrompt(alert: alert, strings: strings,
                                                                  displayName: candidate.displayName)
        let userApplications = NSButton(checkboxWithTitle: strings.useUserApplications,
                                        target: destinationPrompt,
                                        action: #selector(DiskImageInstallDestinationPrompt.updateDestination(_:)))
        userApplications.state = defaults.bool(forKey: DefaultsKey.diskImageInstallerUseUserApplications) ? .on : .off
        destinationPrompt.updateDestination(userApplications)
        let options = NSStackView(views: [trashDownload, revealApp, userApplications])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 6
        options.frame = NSRect(origin: .zero, size: options.fittingSize)
        alert.accessoryView = options

        // Not runModal: this runs inside a main-queue block (the hop after the
        // mount check), and a modal loop started there holds back later
        // main-queue work, such as shortcut actions, until the alert closes.
        // Its modal panel mode also stops default-mode timers (issue #1665).
        NSApp.activate(ignoringOtherApps: true)
        installPrompt = NonModalAlert.present(alert, retaining: [destinationPrompt]) { [weak self] response in
            guard let self else { return }
            self.installPrompt = nil
            guard response == .alertFirstButtonReturn else {
                self.finishCurrentCandidate()
                return
            }
            let trashesDownload = trashDownload.state == .on
            let revealsApp = revealApp.state == .on
            let usesUserApplications = userApplications.state == .on
            defaults.set(trashesDownload, forKey: DefaultsKey.diskImageInstallerTrashesDownload)
            defaults.set(revealsApp, forKey: DefaultsKey.diskImageInstallerRevealsApp)
            defaults.set(usesUserApplications, forKey: DefaultsKey.diskImageInstallerUseUserApplications)
            self.beginInstall(candidate, strings: strings, trashingDownload: trashesDownload,
                              revealingApp: revealsApp, useUserApplications: usesUserApplications)
        }
    }

    private func beginInstall(_ candidate: Candidate, strings: DiskImageInstallerStrings,
                              trashingDownload trashesDownload: Bool, revealingApp revealsApp: Bool,
                              useUserApplications usesUserApplications: Bool) {
        showProgress(for: candidate, strings: strings)

        workQueue.async { [weak self] in
            let result = self?.install(candidate, trashingDownload: trashesDownload,
                                       useUserApplications: usesUserApplications)
                ?? InstallResult(outcome: .failed(.copy), destinationURL: nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hideProgress()
                self.present(result: result, candidate: candidate) { [weak self] in
                    if revealsApp, result.outcome.isInstalled, let destinationURL = result.destinationURL {
                        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    }
                    self?.finishCurrentCandidate()
                }
            }
        }
    }

    /// Copying and verifying take a few seconds with nothing else on screen,
    /// which reads as a failure. A quiet floating card keeps the wait honest.
    private func showProgress(for candidate: Candidate, strings: DiskImageInstallerStrings) {
        let host = NSHostingController(rootView: DiskImageInstallProgressView(
            icon: NSWorkspace.shared.icon(forFile: candidate.appURL.path),
            message: String(format: strings.installingFormat, candidate.displayName)))
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = progressPanel ?? Self.makeProgressPanel()
        progressPanel = panel
        panel.contentViewController = host
        let screen = NSScreen.pointerVisibleFrame
        panel.setFrame(NSRect(x: (screen.midX - size.width / 2).rounded(),
                              y: (screen.maxY - size.height - 24).rounded(),
                              width: size.width,
                              height: size.height),
                       display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hideProgress() {
        progressPanel?.orderOut(nil)
        progressPanel?.contentViewController = nil
    }

    private static func makeProgressPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }

    private func finishCurrentCandidate() {
        promptActive = false
        presentNextCandidate()
    }

    private func install(_ candidate: Candidate, trashingDownload: Bool,
                         useUserApplications: Bool) -> InstallResult {
        let fm = FileManager.default
        let applicationsDomain = DiskImageInstallerSupport.applicationsDomain(
            useUserApplications: useUserApplications)
        guard let applicationsURL = try? fm.url(for: .applicationDirectory,
                                                in: applicationsDomain,
                                                appropriateFor: nil,
                                                create: true),
              let destinationURL = DiskImageInstallerSupport.destinationURL(
                for: candidate.appURL,
                applicationsURL: applicationsURL),
              let collisionURLs = DiskImageInstallerSupport.collisionURLs(for: candidate.appURL,
                useUserApplications: useUserApplications,
                fileManager: fm),
              collisionURLs.contains(destinationURL)
        else {
            return InstallResult(outcome: .failed(.copy), destinationURL: nil)
        }
        guard collisionURLs.allSatisfy({ !fm.fileExists(atPath: $0.path) }) else {
            return InstallResult(outcome: .failed(.alreadyInstalled),
                                 destinationURL: destinationURL)
        }

        let stagingDirectory: URL
        do {
            stagingDirectory = try fm.url(for: .itemReplacementDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: destinationURL.deletingLastPathComponent(),
                                          create: true)
        } catch {
            return InstallResult(outcome: .failed(.copy), destinationURL: destinationURL)
        }
        defer { try? fm.removeItem(at: stagingDirectory) }

        let stagedApp = stagingDirectory.appendingPathComponent(candidate.appURL.lastPathComponent,
                                                                 isDirectory: true)
        // Carrying the mounted image's quarantine over leaves the installed app eligible for
        // path randomization, so macOS runs it from a read-only random location instead of
        // Applications. The checks below are the same assessment that flag defers to.
        let copy = Self.run("/usr/bin/ditto", arguments: [
            "--rsrc", "--extattr", "--acl", "--noqtn",
            candidate.appURL.path, stagedApp.path,
        ])
        guard copy.status == 0, Self.validBundle(at: stagedApp) else {
            return InstallResult(outcome: .failed(.copy), destinationURL: destinationURL)
        }
        guard Self.gatekeeperAccepts(stagedApp) else {
            return InstallResult(outcome: .failed(.verification), destinationURL: destinationURL)
        }

        do {
            guard let finalCollisionURLs = DiskImageInstallerSupport.collisionURLs(
                for: candidate.appURL,
                useUserApplications: useUserApplications,
                fileManager: fm),
                finalCollisionURLs.contains(destinationURL)
            else {
                return InstallResult(outcome: .failed(.copy), destinationURL: destinationURL)
            }
            guard finalCollisionURLs.allSatisfy({ !fm.fileExists(atPath: $0.path) }) else {
                return InstallResult(outcome: .failed(.alreadyInstalled),
                                     destinationURL: destinationURL)
            }
            try fm.moveItem(at: stagedApp, to: destinationURL)
        } catch {
            return InstallResult(outcome: .failed(.copy), destinationURL: destinationURL)
        }

        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: candidate.mountURL)
        } catch {
            return InstallResult(outcome: .installedKeepingMount, destinationURL: destinationURL)
        }

        guard trashingDownload else {
            return InstallResult(outcome: .installed(downloadTrashed: false),
                                 destinationURL: destinationURL)
        }
        guard Self.fileIdentity(at: candidate.imageURL) == candidate.imageIdentity else {
            return InstallResult(outcome: .installedKeepingDownload,
                                 destinationURL: destinationURL)
        }
        do {
            try fm.trashItem(at: candidate.imageURL, resultingItemURL: nil)
            return InstallResult(outcome: .installed(downloadTrashed: true),
                                 destinationURL: destinationURL)
        } catch {
            return InstallResult(outcome: .installedKeepingDownload,
                                 destinationURL: destinationURL)
        }
    }

    private func present(result: InstallResult, candidate: Candidate,
                         completion: @escaping () -> Void) {
        let strings = FeatureStrings.diskImageInstaller(L10n.shared.language)
        let alert = NSAlert()
        let folder = result.destinationURL?.deletingLastPathComponent().path == "/Applications"
            ? strings.applicationsFolder : strings.userApplicationsFolder
        alert.icon = NSWorkspace.shared.icon(forFile: result.destinationURL?.path
                                              ?? candidate.appURL.path)
        switch result.outcome {
        case let .installed(downloadTrashed):
            alert.messageText = strings.installedTitle
            alert.informativeText = String(format: downloadTrashed
                                               ? strings.installedBodyFormat
                                               : strings.installedKeptDownloadBodyFormat,
                                           candidate.displayName, folder)
        case .installedKeepingMount:
            alert.alertStyle = .warning
            alert.messageText = strings.installedTitle
            alert.informativeText = String(format: strings.installedKeepingMountBodyFormat,
                                           candidate.displayName, folder)
        case .installedKeepingDownload:
            alert.alertStyle = .warning
            alert.messageText = strings.installedTitle
            alert.informativeText = String(format: strings.installedKeepingDownloadBodyFormat,
                                           candidate.displayName, folder)
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
        // Not runModal either: this runs inside the hop after the install.
        NSApp.activate(ignoringOtherApps: true)
        NonModalAlert.present(alert) { _ in completion() }
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

private struct DiskImageInstallProgressView: View {
    let icon: NSImage
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            .frame(width: 220, alignment: .leading)
        }
        .padding(14)
        .background(HUDBackdrop(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}

private final class DiskImageInstallDestinationPrompt: NSObject {
    let alert: NSAlert
    let strings: DiskImageInstallerStrings
    let displayName: String

    init(alert: NSAlert, strings: DiskImageInstallerStrings, displayName: String) {
        self.alert = alert
        self.strings = strings
        self.displayName = displayName
    }

    @objc func updateDestination(_ sender: NSButton) {
        let folder = sender.state == .on ? strings.userApplicationsFolder : strings.applicationsFolder
        alert.informativeText = String(format: strings.promptBodyFormat, displayName, folder)
        // The alert keeps the height it was laid out with, and the home-folder
        // wording can need one more line than the default one, which would cut
        // its last line off. Lay the alert out again for the longer wording,
        // keeping the bottom edge in place so the options stay under the
        // pointer; the shorter wording simply leaves that line blank.
        guard sender.state == .on, alert.window.isVisible else { return }
        let window = alert.window
        let bottom = window.frame.minY
        alert.layout()
        var frame = window.frame
        frame.origin.y = bottom
        window.setFrame(frame, display: true)
    }
}
