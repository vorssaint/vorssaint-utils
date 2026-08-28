// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Checks GitHub Releases for a newer version and, when asked, downloads the
/// release DMG and installs it over the running app. Self-update for an app
/// distributed outside the App Store, with no third-party framework.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        /// nil while the total size is still unknown (indeterminate spinner).
        case downloading(progress: Double?)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?
    /// Markdown release notes for the available update, shown in the pre-install
    /// preview. Set alongside `.available`; cleared otherwise.
    @Published private(set) var availableNotes: String?

    private let repository = "vorssaintapp/vorssaint-utils"
    private var downloadURL: URL?
    /// Size the release advertises for the asset, used to bound the download.
    private var downloadExpectedBytes: Int64?
    private var refreshTimer: Timer?
    private var notifiedVersion: String?   // last release we posted a notification for
    private var downloadSession: URLSession?

    private init() {}

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.autoCheckUpdates) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoCheckUpdates)
            configureAutomaticChecks()
        }
    }

    var includeBetaUpdates: Bool {
        get {
            if let explicit = UserDefaults.standard.object(forKey: DefaultsKey.includeBetaUpdates) as? Bool {
                return explicit
            }
            return AppInfo.isBeta
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.includeBetaUpdates)
        }
    }

    // MARK: - Scheduling

    /// Called at launch: checks shortly after start and then daily, if enabled.
    func startAutomaticChecks() {
        consumeInstallResult()
        if AppInfo.isBeta && UserDefaults.standard.object(forKey: DefaultsKey.includeBetaUpdates) == nil {
            UserDefaults.standard.set(true, forKey: DefaultsKey.includeBetaUpdates)
        }
        // The local dev build never auto-updates, but can simulate the
        // "update available" UI via the `simulateUpdate` default, for testing.
        if AppInfo.isDeveloperBuild {
            if UserDefaults.standard.bool(forKey: DefaultsKey.simulateUpdate) {
                let simulatedVersion = AppInfo.isBeta ? "9.9.9-beta.1" : "9.9.9"
                state = .available(version: simulatedVersion)
                availableNotes = ReleaseNotes.rawNotes(for: AppInfo.version)
            }
            return
        }
        configureAutomaticChecks()
        if autoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.check(manual: false)
            }
        }
    }

    private func configureAutomaticChecks() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard autoCheckEnabled else { return }
        // Hourly (was daily). Combined with the activate / panel-open checks, a new
        // release surfaces within the hour instead of up to a day later.
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
        timer.tolerance = 60 * 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Check

    func check(manual: Bool) {
        if AppInfo.isDeveloperBuild {
            // No real update target; reflect the simulation default so the
            // notification UI can be exercised locally.
            if UserDefaults.standard.bool(forKey: DefaultsKey.simulateUpdate) {
                state = .available(version: "9.9.9")
                availableNotes = ReleaseNotes.rawNotes(for: AppInfo.version)
            } else {
                state = .upToDate
                availableNotes = nil
            }
            lastChecked = Date()
            return
        }
        if case .checking = state { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking

        let endpoint = includeBetaUpdates
            ? "https://api.github.com/repos/\(repository)/releases?per_page=10"
            : "https://api.github.com/repos/\(repository)/releases/latest"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.lastChecked = Date()
                guard let data, error == nil else {
                    self.availableNotes = nil
                    self.state = .failed(error?.localizedDescription ?? "-")
                    return
                }

                let releases: [GitHubRelease]
                if self.includeBetaUpdates {
                    releases = (try? JSONDecoder().decode([GitHubRelease].self, from: data)) ?? []
                } else if let single = try? JSONDecoder().decode(GitHubRelease.self, from: data) {
                    releases = [single]
                } else {
                    releases = []
                }

                guard !releases.isEmpty else {
                    self.availableNotes = nil
                    self.state = .failed(error?.localizedDescription ?? "-")
                    return
                }

                let candidates = releases.map { rel -> UpdateServiceSupport.ReleaseCandidate in
                    let asset = rel.assets.first { $0.name.hasSuffix(".dmg") }
                    return UpdateServiceSupport.ReleaseCandidate(
                        tagName: rel.tagName,
                        isPrerelease: rel.prerelease ?? false,
                        isDraft: rel.draft ?? false,
                        dmgURL: asset?.browserDownloadURL,
                        dmgExpectedBytes: asset?.size,
                        body: rel.body
                    )
                }

                if let chosen = UpdateServiceSupport.selectUpdate(
                    from: candidates,
                    currentVersion: AppInfo.version,
                    includeBetas: self.includeBetaUpdates
                ) {
                    let versionClean = chosen.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                    self.downloadURL = chosen.dmgURL
                    self.downloadExpectedBytes = chosen.dmgExpectedBytes
                    self.availableNotes = ReleaseNotes.inAppUpdateNotes(from: chosen.body)
                    self.state = .available(version: versionClean)
                    // Notify once per distinct release, not on every hourly re-check.
                    if !manual, versionClean != self.notifiedVersion {
                        self.notifiedVersion = versionClean
                        let s = L10n.shared.s
                        Notifier.post(title: s.updateNotifyTitle,
                                      body: "\(s.updateAvailablePrefix) \(versionClean)")
                    }
                } else {
                    self.availableNotes = nil
                    self.state = .upToDate
                }
            }
        }.resume()
    }

    /// Re-checks only if the last check is stale — called when the app reactivates
    /// or the panel opens, so a new release surfaces promptly without hammering the
    /// API. The hourly timer is the floor; this makes it feel immediate.
    func checkIfStale(maxAge: TimeInterval = 15 * 60) {
        if AppInfo.isDeveloperBuild { return }
        guard autoCheckEnabled else { return }
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        if let last = lastChecked, Date().timeIntervalSince(last) < maxAge { return }
        check(manual: false)
    }

    // MARK: - Download & install

    func downloadAndInstall() {
        if AppInfo.isDeveloperBuild { return }  // never replace the local dev build over itself
        guard let downloadURL else { return }
        // Pre-flight BEFORE spending the download: a translocated app or one
        // running from a read-only volume (the mounted DMG) can never be
        // replaced in place, so say so now instead of after the download.
        if UpdateInstallerSupport.runsFromImmutableLocation(appPath: Bundle.main.bundlePath,
                                                            volumeIsReadOnly: Self.volumeIsReadOnly) {
            let s = L10n.shared.s
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = s.updateNeedsApplicationsTitle
            alert.informativeText = s.updateNeedsApplicationsBody
            alert.runModal()
            return
        }
        // Remember the offer so a failed download restores it (the user can retry)
        // instead of dropping to a dead .failed state that hides the update and
        // blocks checkIfStale for 15 min.
        let offered: String?
        if case let .available(version) = state { offered = version } else { offered = nil }
        state = .downloading(progress: nil)

        let expectedBytes = downloadExpectedBytes
        let byteLimit = UpdateInstallerSupport.downloadByteLimit(expectedBytes: expectedBytes)
        let delegate: BoundedUpdateDownloadDelegate
        do {
            delegate = try BoundedUpdateDownloadDelegate(
                byteLimit: byteLimit,
                progress: { [weak self] receivedBytes, responseExpectedBytes in
                    let totalBytes = expectedBytes ?? responseExpectedBytes
                    guard let totalBytes, totalBytes > 0 else { return }
                    let fraction = min(Double(receivedBytes) / Double(totalBytes), 1)
                    DispatchQueue.main.async {
                        guard let self, case let .downloading(current) = self.state else { return }
                        if UpdateInstallerSupport.progressStepAdvanced(from: current, to: fraction) {
                            self.state = .downloading(progress: fraction)
                        }
                    }
                },
                completion: { [weak self] tempURL, response, error in
                    guard let self else { return }
                    self.downloadSession?.finishTasksAndInvalidate()
                    DispatchQueue.main.async {
                        self.downloadSession = nil
                    }
                    guard let tempURL, error == nil else {
                        DispatchQueue.main.async {
                            self.state = offered.map { State.available(version: $0) }
                                ?? .failed(error?.localizedDescription ?? "-")
                        }
                        return
                    }
                    // A response that cannot be the asset is dropped here, before it is
                    // moved out of the scratch space and mounted. The installer still
                    // verifies the signature; this only keeps a wrong body from getting
                    // that far.
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let received = (try? FileManager.default.attributesOfItem(atPath: tempURL.path))
                        .flatMap { $0[.size] as? NSNumber }?.int64Value ?? 0
                    guard UpdateInstallerSupport.downloadIsUsable(status: status,
                                                                  receivedBytes: received,
                                                                  expectedBytes: expectedBytes) else {
                        try? FileManager.default.removeItem(at: tempURL)
                        DispatchQueue.main.async {
                            self.state = offered.map { State.available(version: $0) }
                                ?? .failed("HTTP \(status)")
                        }
                        return
                    }
                    // Move out of the session's scratch space before handing off.
                    let dmgURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Vorssaint-update.dmg")
                    try? FileManager.default.removeItem(at: dmgURL)
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: dmgURL)
                    } catch {
                        DispatchQueue.main.async {
                            self.state = offered.map { State.available(version: $0) }
                                ?? .failed(error.localizedDescription)
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.state = .installing
                        self.launchInstaller(dmgPath: dmgURL.path, offered: offered)
                    }
                })
        } catch {
            DispatchQueue.main.async {
                self.state = offered.map { State.available(version: $0) }
                    ?? .failed(error.localizedDescription)
            }
            return
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadSession = session
        let task = session.dataTask(with: downloadURL)
        task.resume()
    }

    /// Hands the swap to a detached shell script: it waits for this process to
    /// quit, verifies and mounts the DMG, replaces the bundle, clears
    /// quarantine and relaunches. Running it outside the app means the bundle
    /// can be replaced safely while we exit. When the app's folder is not
    /// writable by this user (standard account with the app in /Applications),
    /// the script runs through an admin prompt instead of failing silently.
    private func launchInstaller(dmgPath: String, offered: String?) {
        let appPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let fm = FileManager.default

        guard let resultURL = Self.installResultURL, let expectedVersion = offered else {
            abortInstall(dmgPath: dmgPath, offered: offered)
            return
        }
        try? fm.createDirectory(at: resultURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? fm.removeItem(at: resultURL)
        try? fm.removeItem(at: resultURL.appendingPathExtension("progress"))

        let appDirectory = (appPath as NSString).deletingLastPathComponent
        let lastFailure = UserDefaults.standard.string(forKey: DefaultsKey.updateLastInstallFailure)
        if fm.isWritableFile(atPath: appDirectory),
           !UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: lastFailure) {
            launchUserInstaller(appPath: appPath, dmgPath: dmgPath, pid: pid,
                                resultPath: resultURL.path, expectedVersion: expectedVersion)
        } else {
            // Either the folder is not writable, or the last attempt died at
            // the copy/swap step: retry with admin rights instead of failing
            // the same way twice.
            launchAdminInstaller(appPath: appPath, dmgPath: dmgPath, pid: pid,
                                 resultPath: resultURL.path, expectedVersion: expectedVersion)
        }
    }

    private func launchUserInstaller(appPath: String, dmgPath: String, pid: Int32,
                                     resultPath: String, expectedVersion: String) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-update-\(pid)-\(UUID().uuidString).sh")
        do {
            try UpdateInstallerSupport.installerScript()
                .write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            failInstall(dmgPath: dmgPath, message: error.localizedDescription)
            return
        }

        do {
            // Its own session: a plain child would be swept away with this
            // app's session and launchd job, before the swap it is here for.
            try DetachedProcess.spawn("/bin/sh",
                                      [scriptURL.path, appPath, dmgPath, "\(pid)", resultPath,
                                       "\(getuid())", expectedVersion])
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            failInstall(dmgPath: dmgPath, message: error.localizedDescription)
            return
        }
        // Quit so the installer can replace the bundle; it relaunches us.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    /// Same installer, behind the system admin prompt via AdminShell, which
    /// serializes prompts and brings this menu bar app forward so the dialog
    /// cannot open behind another window. The script goes inline inside the
    /// elevated command (never a user-writable file run as root), started in
    /// its own session so the prompt returns while the installer waits for our
    /// exit — and so it survives that exit.
    private func launchAdminInstaller(appPath: String, dmgPath: String, pid: Int32,
                                      resultPath: String, expectedVersion: String) {
        let command = UpdateInstallerSupport.elevatedInstallCommand(appPath: appPath,
                                                                    dmgPath: dmgPath,
                                                                    pid: pid,
                                                                    resultPath: resultPath,
                                                                    uid: getuid(),
                                                                    expectedVersion: expectedVersion)
        AdminShell.runInProcess(command, prompt: L10n.shared.s.adminPromptUpdate) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    NSApp.terminate(nil)
                } else {
                    // The user dismissed the admin prompt: keep the offer so
                    // the button simply works again.
                    self.abortInstall(dmgPath: dmgPath, offered: expectedVersion)
                }
            }
        }
    }

    /// Puts the world back as if the install had not been attempted: the
    /// downloaded DMG is discarded and the offer (or idle state) returns.
    private func abortInstall(dmgPath: String, offered: String?) {
        try? FileManager.default.removeItem(atPath: dmgPath)
        if let offered {
            state = .available(version: offered)
        } else {
            state = .idle
        }
    }

    private func failInstall(dmgPath: String, message: String) {
        try? FileManager.default.removeItem(atPath: dmgPath)
        state = .failed(message)
    }

    /// Whether the volume holding `path` is mounted read-only (the DMG). An
    /// unanswerable query counts as read-only: refusing with a clear message
    /// beats quitting for an install that cannot happen.
    private static func volumeIsReadOnly(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly ?? true
    }

    // MARK: - Install result

    /// Marker the installer script writes; read on the next launch so a swap
    /// that failed after the app quit is reported instead of looking like the
    /// update was simply ignored.
    private static var installResultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("update-install-result", isDirectory: false)
    }

    private func consumeInstallResult() {
        guard let url = Self.installResultURL else { return }
        // A leftover progress file means an installer died mid-run (or is
        // still running right now); it is never a finished verdict.
        try? FileManager.default.removeItem(at: url.appendingPathExtension("progress"))
        guard let marker = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)
        guard let code = UpdateInstallerSupport.installFailureCode(fromMarker: marker) else {
            // The swap finished: this launch IS the new version, so any
            // remembered failure no longer applies.
            UserDefaults.standard.removeObject(forKey: DefaultsKey.updateLastInstallFailure)
            return
        }
        // Remember the failing step so the next attempt can route around it
        // (copy/swap failures retry through the admin prompt), and check
        // again soon so the update offer comes right back instead of
        // looking silently dropped.
        UserDefaults.standard.set(code, forKey: DefaultsKey.updateLastInstallFailure)
        let s = L10n.shared.s
        Notifier.post(title: s.updateNotifyTitle,
                      body: "\(s.updateInstallFailedBody) (\(code))")
        if !AppInfo.isDeveloperBuild {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.check(manual: false)
            }
        }
    }

    // MARK: - Version compare

    /// True when `latest` is a higher semantic version than `current`.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        UpdateServiceSupport.isNewer(latest, than: current)
    }
}

private final class BoundedUpdateDownloadDelegate: NSObject, URLSessionDataDelegate {
    private let byteLimit: Int64
    private let progress: (Int64, Int64?) -> Void
    private let completion: (URL?, URLResponse?, Error?) -> Void
    private let fileURL: URL
    private let fileHandle: FileHandle
    private var response: URLResponse?
    private var responseExpectedBytes: Int64?
    private var receivedBytes: Int64 = 0
    private var completed = false
    private var exceededLimit = false
    private var writeError: Error?

    init(byteLimit: Int64,
         progress: @escaping (Int64, Int64?) -> Void,
         completion: @escaping (URL?, URLResponse?, Error?) -> Void) throws {
        self.byteLimit = byteLimit
        self.progress = progress
        self.completion = completion
        let temporaryFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vorssaint-update-\(UUID().uuidString).download")
        fileURL = temporaryFileURL
        guard FileManager.default.createFile(atPath: temporaryFileURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            fileHandle = try FileHandle(forWritingTo: temporaryFileURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryFileURL)
            throw error
        }
    }

    deinit {
        try? fileHandle.close()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        responseExpectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard writeError == nil, !exceededLimit else { return }
        let chunkBytes = Int64(data.count)
        guard chunkBytes <= byteLimit - receivedBytes else {
            exceededLimit = true
            dataTask.cancel()
            return
        }
        do {
            try fileHandle.write(contentsOf: data)
            receivedBytes += chunkBytes
            progress(receivedBytes, responseExpectedBytes)
        } catch {
            writeError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let closeError: Error?
        do {
            try fileHandle.close()
            closeError = nil
        } catch {
            closeError = error
        }
        if let writeError {
            complete(location: nil, response: response, error: writeError)
        } else if exceededLimit {
            complete(location: nil, response: response, error: POSIXError(.EFBIG))
        } else if let error {
            complete(location: nil, response: response, error: error)
        } else if let closeError {
            complete(location: nil, response: response, error: closeError)
        } else {
            complete(location: fileURL, response: response, error: nil)
        }
    }

    private func complete(location: URL?, response: URLResponse?, error: Error?) {
        guard !completed else { return }
        completed = true
        if location == nil {
            try? FileManager.default.removeItem(at: fileURL)
        }
        completion(location, response, error)
    }
}

// MARK: - GitHub API shapes

private struct GitHubRelease: Decodable {
    let tagName: String
    let prerelease: Bool?
    let draft: Bool?
    let assets: [Asset]
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
        case draft
        case assets
        case body
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}
