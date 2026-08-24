// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Finds which of the installed apps have a newer version waiting, in one
/// list, and updates the ones the person picks.
///
/// Two sources, because those are the two that can answer honestly for an app
/// somebody else wrote: the package manager (which can also install the
/// update on the spot) and the App Store (which can only be opened). Apps
/// that ship their own updater are left alone, since they already do this by
/// themselves.
///
/// Nothing runs at rest. The scan happens when the person opens the list or
/// asks for it, and the background check only exists while its schedule is on.
final class AppUpdatesService: ObservableObject {
    static let shared = AppUpdatesService()

    @Published private(set) var items: [AppUpdatesSupport.Item] = []
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var nextCheck: Date?
    /// Rows the person ticked. New findings arrive ticked, so the common
    /// case is one click.
    @Published var selection: Set<String> = []
    /// The package manager is missing, so only the store half can answer.
    @Published private(set) var packageManagerAvailable = false
    /// A check finished in THIS process. The time of the last check survives
    /// relaunches, but its findings do not, so nothing may claim the Mac is
    /// up to date until a scan has actually run here.
    @Published private(set) var hasCheckedThisSession = false
    @Published private(set) var lastError: String?

    private let workQueue = DispatchQueue(label: "com.vorssaint.appupdates", qos: .utility)
    private lazy var lookupSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var scanGeneration = 0
    private var sourceRefreshPending = false
    private var automaticCheckPending = false
    private var knownIDs = Set<String>()
    /// The person was sent to the store to finish an update, so the list is
    /// about to be wrong until it is read again.
    private(set) var storeHandoffPending = false
    /// Alive only while an upgrade this service started is running, so the
    /// list refreshes itself even when no window is on screen to notice.
    private var upgradeObserver: AnyCancellable?

    private init() {
        let stamp = UserDefaults.standard.double(forKey: DefaultsKey.appUpdatesLastCheck)
        lastCheck = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    // MARK: - Lifecycle

    var frequency: AppUpdatesSupport.CheckFrequency {
        AppUpdatesSupport.CheckFrequency.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.appUpdatesCheckFrequency))
    }

    func syncWithPreferences() {
        guard AppFeature.appUpdates.isAvailable, frequency != .off else {
            stop()
            return
        }
        installWakeObserver()
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        if nextCheck != nil { nextCheck = nil }
    }

    private func installWakeObserver() {
        guard wakeObserver == nil else { return }
        // A check that came due during sleep never fires its timer; waking up
        // recomputes and catches the miss.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.scheduleNext()
        }
    }

    private func scheduleNext() {
        guard let fireDate = AppUpdatesSupport.nextCheckDate(lastCheck: lastCheck,
                                                             frequency: frequency,
                                                             now: Date()) else { return }
        timer?.invalidate()
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.check(automatic: true)
        }
        // One shot a day: a loose tolerance costs nothing and lets the system
        // group the wake-up with other work.
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if nextCheck != fireDate { nextCheck = fireDate }
    }

    // MARK: - Checking

    /// A source switch changes the answer. Let an in-flight scan finish its
    /// read, discard that answer and immediately run once with the new choice.
    func sourceSelectionDidChange() {
        if isChecking {
            sourceRefreshPending = true
        } else {
            check()
        }
    }

    /// Scans both sources. `automatic` marks the background pass, which is
    /// the only one that can post a notification and re-arm the schedule.
    func check(automatic: Bool = false) {
        guard AppFeature.appUpdates.isAvailable else { return }
        if isChecking {
            automaticCheckPending = automaticCheckPending || automatic
            return
        }
        isChecking = true
        lastError = nil
        scanGeneration += 1
        let generation = scanGeneration
        let includeHomebrewApps = UserDefaults.standard.bool(
            forKey: DefaultsKey.appUpdatesIncludeHomebrewApps)
        let includeAppStore = UserDefaults.standard.bool(forKey: DefaultsKey.appUpdatesIncludeAppStore)
        let country = Locale.current.region?.identifier

        workQueue.async { [weak self] in
            guard let self else { return }
            let apps = Self.scanInstalledApps()
            let packageResult = includeHomebrewApps
                ? self.packageManagerFindings(apps: apps)
                : PackageResult(items: [], available: true)
            let coveredPaths = Set(packageResult.items.compactMap(\.bundlePath))
            let storeCandidates = includeAppStore
                ? AppUpdatesSupport.appStoreCandidates(
                    apps: apps, coveredPaths: coveredPaths)
                : []

            self.storeFindings(for: storeCandidates, country: country) { storeItems in
                DispatchQueue.main.async {
                    guard generation == self.scanGeneration else { return }
                    self.finishCheck(items: AppUpdatesSupport.merged(packageResult.items, storeItems),
                                     packageManagerAvailable: packageResult.available,
                                     automatic: automatic)
                }
            }
        }
    }

    private func finishCheck(items newItems: [AppUpdatesSupport.Item],
                             packageManagerAvailable available: Bool,
                             automatic: Bool) {
        // The feature can be switched off in the hub while a scan is in
        // flight; its findings belong to a surface that no longer exists.
        guard AppFeature.appUpdates.isAvailable else {
            isChecking = false
            sourceRefreshPending = false
            automaticCheckPending = false
            return
        }
        let shouldFinishAutomatically = automatic || automaticCheckPending
        automaticCheckPending = false
        if sourceRefreshPending {
            sourceRefreshPending = false
            isChecking = false
            check(automatic: shouldFinishAutomatically)
            return
        }
        // What was already announced survives relaunches, unlike knownIDs:
        // otherwise the first background check of every launch would speak up
        // about the same pending update again. Findings that are gone drop out,
        // so an app updating again later is announced again.
        var announced = Self.announcedIDs().intersection(newItems.map(\.id))
        let fresh = newItems.filter { !announced.contains($0.id) }
        selection = AppUpdatesSupport.reconciledSelection(previous: selection,
                                                          knownIDs: knownIDs,
                                                          items: newItems)
        knownIDs = Set(newItems.map(\.id))
        items = newItems
        packageManagerAvailable = available
        hasCheckedThisSession = true
        isChecking = false
        let now = Date()
        lastCheck = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: DefaultsKey.appUpdatesLastCheck)
        UserDefaults.standard.set(newItems.count, forKey: DefaultsKey.appUpdatesLastCount)
        if shouldFinishAutomatically {
            if notifyIfWanted(freshCount: fresh.count, total: newItems.count) {
                announced = Set(newItems.map(\.id))
            }
            scheduleNext()
        }
        Self.saveAnnouncedIDs(announced)
    }

    /// Only the background pass speaks up, and only about apps the person has
    /// not been told about yet, so a Mac with one stubborn pending update
    /// stays quiet after the first notice. True when a notice went out.
    private func notifyIfWanted(freshCount: Int, total: Int) -> Bool {
        guard freshCount > 0,
              UserDefaults.standard.bool(forKey: DefaultsKey.appUpdatesNotify) else { return false }
        let strings = FeatureStrings.appUpdates(L10n.shared.language)
        let body = total == 1
            ? strings.notificationBodyOne
            : String(format: strings.notificationBodyFormat, "\(total)")
        Notifier.post(title: strings.pageTitle, body: body)
        return true
    }

    private static func announcedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.appUpdatesNotifiedIDs) ?? [])
    }

    private static func saveAnnouncedIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(ids.sorted(), forKey: DefaultsKey.appUpdatesNotifiedIDs)
    }

    // MARK: - Package manager source

    private struct PackageResult {
        let items: [AppUpdatesSupport.Item]
        let available: Bool
    }

    private func packageManagerFindings(apps: [AppUpdatesSupport.InstalledApp]) -> PackageResult {
        guard let brewPath = HomebrewCommandBuilder.candidatePaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return PackageResult(items: [], available: false)
        }
        let installedOutput = Self.runCommand(HomebrewCommandBuilder.installed(brewPath: brewPath))
        let outdatedOutput = Self.runCommand(
            HomebrewCommandBuilder.outdatedCasksIncludingSelfUpdating(brewPath: brewPath))
        guard installedOutput.status == 0, outdatedOutput.status == 0 else {
            let failure = [outdatedOutput, installedOutput].first { $0.status != 0 }
            let message = failure.map { HomebrewProgressParser.visibleError(from: $0.output) } ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.lastError = message.isEmpty ? nil : message
            }
            return PackageResult(items: [], available: true)
        }
        let records = HomebrewParser.parseInstalledCaskRecords(installedOutput.output)
        let updates = (try? HomebrewParser.parseOutdatedCommandOutput(outdatedOutput.output)) ?? [:]
        let items = AppUpdatesSupport.packageUpdates(
            outdated: Array(updates.values),
            installed: records,
            ignoredTokens: Self.ownPackageTokens,
            apps: apps.filter { !$0.version.isEmpty })
        return PackageResult(items: items, available: true)
    }

    // MARK: - App Store source

    private func storeFindings(for candidates: [AppUpdatesSupport.InstalledApp],
                               country: String?,
                               completion: @escaping ([AppUpdatesSupport.Item]) -> Void) {
        guard !candidates.isEmpty else {
            completion([])
            return
        }
        let batches = stride(from: 0, to: candidates.count, by: AppUpdatesSupport.storeLookupBatchSize)
            .map { Array(candidates[$0..<min($0 + AppUpdatesSupport.storeLookupBatchSize, candidates.count)]) }
        var merged: [String: AppUpdatesSupport.StoreEntry] = [:]
        let group = DispatchGroup()
        let lock = NSLock()

        for batch in batches {
            guard let url = AppUpdatesSupport.storeLookupURL(bundleIDs: batch.map(\.bundleID),
                                                             country: country) else { continue }
            group.enter()
            lookupSession.dataTask(with: url) { data, _, _ in
                defer { group.leave() }
                guard let data else { return }
                let entries = AppUpdatesSupport.parseStoreLookup(data)
                lock.lock()
                merged.merge(entries) { _, new in new }
                lock.unlock()
            }.resume()
        }

        group.notify(queue: workQueue) {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            completion(AppUpdatesSupport.appStoreUpdates(apps: candidates,
                                                         storeVersions: merged,
                                                         operatingSystemVersion: version))
        }
    }

    // MARK: - Acting on the list

    var selectedCount: Int { selection.count }

    func selectAll() {
        selection = Set(items.map(\.id))
    }

    func selectNone() {
        selection = []
    }

    func toggle(_ item: AppUpdatesSupport.Item) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    /// Updates what the person ticked: the package manager installs its share
    /// in one command, and the store apps hand off to the App Store, which is
    /// as far as any app can go there.
    func updateSelected() {
        let tokens = AppUpdatesSupport.tokens(in: items, selection: selection)
        if !tokens.isEmpty {
            startUpgrade(tokens)
        }
        if let page = AppUpdatesSupport.singleStorePage(in: items, selection: selection),
           let url = URL(string: page) {
            handOffToStore(url)
        } else if AppUpdatesSupport.hasStoreSelection(in: items, selection: selection) {
            openAppStoreUpdates()
        }
    }

    func update(_ item: AppUpdatesSupport.Item) {
        if let token = item.token {
            startUpgrade([token])
        } else if let page = item.storePage, let url = URL(string: page) {
            handOffToStore(url)
        } else {
            openAppStoreUpdates()
        }
    }

    func openAppStoreUpdates() {
        guard let url = URL(string: "macappstore://showUpdatesPage") else { return }
        handOffToStore(url)
    }

    /// The store installs its own updates and macOS offers no way to do it
    /// from here, so the honest move is to open it and then tell the truth
    /// again the moment the person is back.
    private func handOffToStore(_ url: URL) {
        storeHandoffPending = true
        NSWorkspace.shared.open(url)
    }

    /// Watches the upgrade to its end and re-reads the list, so a row leaves
    /// on its own instead of waiting for someone to press Check now. The
    /// observer lives only for that one operation.
    private func startUpgrade(_ tokens: [String]) {
        upgradeObserver = HomebrewManager.shared.$operationStatus
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let status, status.result != .running else { return }
                self?.upgradeObserver = nil
                guard status.result == .succeeded else { return }
                self?.check()
            }
        HomebrewManager.shared.upgradeCasks(tokens)
    }

    func reveal(_ item: AppUpdatesSupport.Item) {
        guard let path = item.bundlePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// After a package upgrade finishes the list is stale, so it re-checks
    /// without touching the schedule.
    func refreshAfterUpgrade() {
        check()
    }

    /// What a surface calls when it appears. It scans again when the answer
    /// could have changed behind the app's back: nothing read yet in this
    /// process, an update just finished in the store, or the last answer is
    /// simply old. Otherwise reopening the panel costs nothing.
    func checkIfNeeded() {
        guard AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: hasCheckedThisSession,
                                              handoffPending: storeHandoffPending,
                                              lastCheck: lastCheck,
                                              now: Date()) else { return }
        check()
    }

    /// Called when the app comes back to the front. Returning from the store
    /// is the moment the list is most likely to be stale, and the window the
    /// person left behind is buried because this app has no Dock icon.
    func applicationBecameActive() {
        guard storeHandoffPending else { return }
        checkIfNeeded()
    }

    /// True while the app should reopen the window the store hand-off left
    /// behind. Reading it clears the flag, so the window is restored once.
    func consumeStoreHandoffReturn() -> Bool {
        guard storeHandoffPending else { return false }
        storeHandoffPending = false
        return true
    }

    // MARK: - Scanning the Applications folders

    /// Reads the normal Applications folders plus shallow app results from
    /// Spotlight in the user's home, all off the main thread.
    private static func scanInstalledApps() -> [AppUpdatesSupport.InstalledApp] {
        InstalledApps.applicationScanPaths(
            folderPaths: folderApplicationPaths(),
            spotlightPaths: spotlightApplicationPaths(),
            homeDirectory: NSHomeDirectory()
        ).compactMap { scannedApp(at: URL(fileURLWithPath: $0)) }
    }

    private static func folderApplicationPaths() -> [String] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications",
                                                                          isDirectory: true),
        ]
        var paths: [String] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(at: root,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                paths.append(url.path)
            }
        }
        return paths
    }

    private static func spotlightApplicationPaths() -> [String] {
        let command = HomebrewCommand(
            executable: "/usr/bin/mdfind",
            arguments: ["-onlyin", NSHomeDirectory(),
                        "kMDItemContentType == 'com.apple.application-bundle'"])
        let result = runCommand(command)
        guard result.status == 0 else { return [] }
        return result.output.split(separator: "\n").map(String.init)
    }

    private static func scannedApp(at url: URL) -> AppUpdatesSupport.InstalledApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return nil }
        guard let bundleID = plist["CFBundleIdentifier"] as? String,
              !isOwnBundle(bundleID) else { return nil }
        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String) ?? ""
        var name = url.deletingPathExtension().lastPathComponent
        if let display = plist["CFBundleDisplayName"] as? String, !display.isEmpty {
            name = display
        }
        // A store purchase always carries its receipt inside the bundle; it
        // is the only reliable marker macOS gives.
        let hasReceipt = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        return AppUpdatesSupport.InstalledApp(name: name,
                                              bundleID: bundleID,
                                              path: url.standardizedFileURL.path,
                                              version: version,
                                              isFromAppStore: hasReceipt)
    }

    /// This app never lists itself: it has its own updater, and letting the
    /// package manager replace a running bundle is exactly what that updater
    /// exists to do safely.
    private static func isOwnBundle(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier || bundleID.hasPrefix("com.vorssaint")
    }

    private static let ownPackageTokens: Set<String> = ["vorssaint", "vorssaint@beta", "vorssaint-beta"]

    /// The package manager refreshes its own catalog on the way, which can sit
    /// on a slow network. A ceiling keeps a stalled command from leaving the
    /// check spinning for the rest of the session; the next check simply tries
    /// again.
    private static let commandTimeout: TimeInterval = 120
    private static let commandOutputLimit = 32 * 1_024 * 1_024

    private static func runCommand(_ command: HomebrewCommand) -> (status: Int32, output: String) {
        let result = BoundedProcessRunner.run(command.executable, command.arguments,
                                              timeout: commandTimeout,
                                              maxOutputBytes: commandOutputLimit)
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }
}
