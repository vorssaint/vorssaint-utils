// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit
import Darwin
import Foundation

/// Experimental organizer for confirmed WhatsApp downloads. It watches only
/// the top level of Downloads, waits until a file is stable, then moves it to
/// the configured folder. File bytes are read only to calculate a local SHA-256
/// digest used for exact duplicate detection.
///
/// One pass, two retention policies: it routes a confirmed download to the
/// chosen folder, and it files away screenshots of the configured folder that
/// nobody has touched in a chosen number of days. Both stages share this
/// type's single timer, single busy guard and single undo transaction, so
/// one "Undo last organization" puts back both.
final class WhatsAppDownloadOrganizer: ObservableObject {
    static let shared = WhatsAppDownloadOrganizer()

    enum Phase: Equatable {
        case idle, waiting, organizing, undoing
        case done(moved: Int, duplicates: Int, failed: Int)
        case failed

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }
    }

    private struct SourceFile {
        let url: URL
        let agent: String?
        let fingerprint: String
        let size: Int64
        let downloadedAt: Date
        let modifiedAt: Date
        let category: WhatsAppDownloadCategory
    }

    /// The second retention policy's live half: a real screenshot folder, the
    /// `Archive` folder inside it, and the instant that separates "been
    /// sitting here untouched" from "just arrived".
    private struct ArchiveSettings {
        let folder: URL
        let destination: URL
        let boundary: Date
    }

    private struct Settings {
        let destination: URL?
        let sources: [String]
        let extensionWhitelist: Set<String>?
        let delayMinutes: Int
        let categories: Set<WhatsAppDownloadCategory>
        let layout: WhatsAppOrganizerLayout
        let duplicateAction: WhatsAppDuplicateAction
        let archive: ArchiveSettings?
    }

    private struct RunResult {
        let moved: Int
        let duplicates: Int
        let failed: Int
        let records: [OrganizedFileRecord]
        let undo: UndoTransaction?
        let nextEligible: Date?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var nextCheck: Date?

    var isBusy: Bool { phase == .organizing || phase == .undoing }
    var canUndo: Bool {
        Self.validUndoTransactions().last != nil
    }

    private let queue = DispatchQueue(label: "com.vorssaint.whatsapp-organizer",
                                      qos: .utility)
    private var directorySource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var operationToken = UUID()

    private init() {}

    static func destinationURL(defaults: UserDefaults = .standard,
                               downloadsURL: URL? = nil) -> URL? {
        let root = downloadsURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let root else { return nil }
        let configured = defaults.string(forKey: DefaultsKey.whatsAppOrganizerDestinationPath) ?? ""
        // No chosen folder means nothing may move. Inventing one here would
        // put files somewhere the person never named, and the only way to
        // learn a folder was created is to go looking for it later.
        guard !configured.isEmpty else { return nil }
        let standardized = URL(fileURLWithPath: configured, isDirectory: true)
            .standardizedFileURL
        // The Downloads root itself is a refusal, not a redirect: sorting a
        // folder into itself is the shape of a mistake, and answering with a
        // different folder hides it.
        guard standardized.path != root.standardizedFileURL.path else { return nil }
        return standardized
    }

    static func managedDestinationPaths() -> Set<String> {
        Set(loadRecords().map { URL(fileURLWithPath: $0.destinationPath).standardizedFileURL.path })
    }

    /// Whether the routing policy may run: the app it routes for, the routing
    /// switches, and a confirmed Downloads folder to route out of.
    private func routingPolicyIsLive() -> Bool {
        AppFeature.cleaner.isAvailable
            && WhatsAppDownloadSupport.isEnabled
            && UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppOrganizerEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed)
            && downloadsURL != nil
            && Self.destinationURL(downloadsURL: downloadsURL) != nil
    }

    /// Whether any retention policy is live. Both the timer and the pass read
    /// it through this one answer so they cannot drift into disagreeing about
    /// whether there is work to do - and, more importantly, so that either
    /// policy being switched off never switches the other one off.
    private func anyPolicyIsLive() -> Bool {
        routingPolicyIsLive() || Self.archiveSettings() != nil
    }

    /// The archive policy's live half, or nil when it is off. Off means the
    /// day count is zero, no folder has been chosen, the folder no longer
    /// exists, or the screenshot feature is gone. The folder is checked but
    /// never created: this pass files captures away from a place the person
    /// already put them, and inventing one here would create a folder that
    /// quietly collects screenshots nobody asked to put anywhere.
    private static func archiveSettings() -> ArchiveSettings? {
        guard AppFeature.screenshot.isAvailable else { return nil }
        let defaults = UserDefaults.standard
        let plan = ScreenshotArchiveSupport.archivePlan(
            folder: defaults.string(forKey: DefaultsKey.screenshotSaveFolder),
            afterDays: defaults.integer(forKey: ScreenshotArchiveSupport.archiveAfterKey),
            now: Date())
        guard let plan else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: plan.folder.path,
                                              isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return ArchiveSettings(folder: plan.folder, destination: plan.destination,
                               boundary: plan.boundary)
    }

    func syncWithPreferences() {
        stopMonitoring()
        guard anyPolicyIsLive() else {
            phase = .idle
            return
        }
        // The Downloads watcher belongs to routing alone. With routing off,
        // starting it would be a directory source opened on every write to a
        // folder this pass no longer reads, and the archive policy needs no
        // watcher at all: it works from file dates, not from events.
        if routingPolicyIsLive(), let root = downloadsURL {
            startMonitoring(root: root)
        }
        schedule(after: 2)
    }

    func stop() {
        operationToken = UUID()
        stopMonitoring()
        phase = .idle
    }

    @discardableResult
    func setDestination(_ url: URL?) -> Bool {
        guard let root = downloadsURL else { return false }
        if let url {
            let destination = url.standardizedFileURL
            guard destination.path != root.standardizedFileURL.path else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            UserDefaults.standard.set(destination.path,
                                      forKey: DefaultsKey.whatsAppOrganizerDestinationPath)
        } else {
            UserDefaults.standard.set("", forKey: DefaultsKey.whatsAppOrganizerDestinationPath)
        }
        syncWithPreferences()
        return true
    }

    func runNow() {
        run(manual: true)
    }

    func undoLastRun(transactionID: UUID? = nil) {
        guard !isBusy else { return }
        let transactions = Self.validUndoTransactions()
        let transaction = transactionID.flatMap { id in
            transactions.first { $0.id == id }
        } ?? (transactionID == nil ? transactions.last : nil)
        guard let transaction,
              DownloadUndoPolicy.recordsAllowUndo(
                transaction, current: Self.loadRecords()) else { return }
        let token = UUID()
        operationToken = token
        phase = .undoing
        queue.async { [weak self] in
            let failed = Self.performUndo(transaction)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationToken == token else { return }
                if failed == 0 {
                    Self.saveRecords(DownloadUndoPolicy.recordsAfterUndo(
                        transaction, current: Self.loadRecords()))
                    Self.saveUndoTransactions(
                        transactions.filter { $0.id != transaction.id })
                    self.phase = .done(moved: 0, duplicates: 0, failed: 0)
                } else {
                    self.phase = .failed
                }
                WhatsAppDownloadManager.shared.scan()
                self.schedule(after: 2)
            }
        }
    }

    private var downloadsURL: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private func startMonitoring(root: URL) {
        let descriptor = open(root.path, O_EVTONLY)
        guard descriptor >= 0 else {
            schedule(after: 300)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main)
        source.setEventHandler { [weak self] in self?.schedule(after: 2) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        nextCheck = nil
        directorySource?.cancel()
        directorySource = nil
    }

    private func schedule(after delay: TimeInterval) {
        guard anyPolicyIsLive() else { return }
        let date = Date().addingTimeInterval(max(1, delay))
        if let nextCheck, nextCheck <= date { return }
        timer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.run(manual: false)
        }
        timer.tolerance = min(10, max(1, delay / 10))
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        nextCheck = date
        // A fresh .done stays visible as the green just-finished feedback;
        // everything else folds into the quiet waiting state.
        if !isBusy, !phase.isDone { phase = .waiting }
    }

    private func schedule(at date: Date?) {
        guard let date else {
            nextCheck = nil
            phase = .waiting
            return
        }
        schedule(after: max(1, date.timeIntervalSinceNow))
    }

    private func run(manual: Bool) {
        timer?.invalidate()
        timer = nil
        nextCheck = nil
        // A pass already executing keeps its phase untouched: writing .idle
        // here would unmask the busy guard and let a second pass race the
        // first, orphaning the first pass's records and undo transaction.
        guard !isBusy else {
            schedule(after: 60)
            return
        }
        // Read once here: the archive policy may run with no Downloads folder
        // at all, so the pass takes an optional root rather than demanding one.
        let root = downloadsURL
        guard anyPolicyIsLive(),
              let settings = settings(root: root) else {
            phase = .idle
            return
        }
        let manager = WhatsAppDownloadManager.shared
        let managerBusy = manager.phase == .scanning || manager.phase == .cleaning
        guard !managerBusy, manual || !manager.reviewVisible else {
            schedule(after: 300)
            return
        }

        let token = UUID()
        operationToken = token
        phase = .organizing
        queue.async { [weak self] in
            let result = Self.organize(root: root, settings: settings)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationToken == token else { return }
                Self.saveRecords(result.records)
                if let undo = result.undo {
                    var transactions = Self.validUndoTransactions()
                    transactions.append(undo)
                    Self.saveUndoTransactions(Array(transactions.suffix(20)))
                }
                let defaults = UserDefaults.standard
                defaults.set(Date().timeIntervalSince1970,
                             forKey: DefaultsKey.whatsAppOrganizerLastRun)
                defaults.set(result.moved, forKey: DefaultsKey.whatsAppOrganizerLastMoved)
                defaults.set(result.duplicates,
                             forKey: DefaultsKey.whatsAppOrganizerLastDuplicates)
                defaults.set(result.failed, forKey: DefaultsKey.whatsAppOrganizerLastFailed)
                self.phase = .done(moved: result.moved,
                                   duplicates: result.duplicates,
                                   failed: result.failed)
                if result.moved + result.duplicates > 0,
                   defaults.bool(forKey: DefaultsKey.whatsAppDownloadsNotify) {
                    let strings = WhatsAppOrganizerStrings.localized(L10n.shared.language)
                    let body = String(format: strings.notificationFormat,
                                      result.moved, result.duplicates, result.failed)
                    if let undo = result.undo {
                        Notifier.postWhatsAppOrganization(
                            title: strings.notificationTitle, body: body,
                            undoTitle: strings.undo, transactionID: undo.id)
                    } else {
                        Notifier.post(title: strings.notificationTitle, body: body)
                    }
                }
                if manager.reviewVisible { manager.scan() }
                self.schedule(at: result.nextEligible)
            }
        }
    }

    private func settings(root: URL?) -> Settings? {
        let defaults = UserDefaults.standard
        // A stored destination path is not a live routing policy: the switches
        // above it can be off while a path from an earlier session is still
        // remembered, and this pass must not route a single file in that
        // state.
        let destination = routingPolicyIsLive()
            ? Self.destinationURL(downloadsURL: root) : nil
        let archive = Self.archiveSettings()
        // One pass, two policies: it runs when either has work and stops when
        // neither does. Requiring both would make each policy's absence
        // switch the other one off, so turning off routing could never leave
        // archiving running, and turning off archiving could never leave
        // routing running.
        guard destination != nil || archive != nil else { return nil }
        return Settings(
            destination: destination,
            sources: DownloadRouter.decodedSources(
                defaults.string(forKey: DefaultsKey.downloadOrganizerSources)),
            extensionWhitelist: DownloadRouter.decodedExtensionWhitelist(
                defaults.string(forKey: DefaultsKey.downloadOrganizerExtensions)),
            delayMinutes: WhatsAppDownloadSupport.sanitizedOrganizerDelayMinutes(
                defaults.integer(forKey: DefaultsKey.whatsAppOrganizerDelayMinutes)),
            categories: WhatsAppDownloadSupport.decodedCategories(
                defaults.string(forKey: DefaultsKey.whatsAppOrganizerCategories)),
            layout: WhatsAppOrganizerLayout(
                rawValue: defaults.string(forKey: DefaultsKey.whatsAppOrganizerLayout) ?? "") ?? .flat,
            duplicateAction: WhatsAppDuplicateAction(
                rawValue: defaults.string(
                    forKey: DefaultsKey.whatsAppOrganizerDuplicateAction) ?? "") ?? .trashNew,
            archive: archive)
    }

    private static func organize(root: URL?, settings: Settings) -> RunResult {
        // Neither policy configured is not a failure; it is both features
        // being off, and there is nothing this pass could have done.
        guard settings.destination != nil || settings.archive != nil else {
            return RunResult(moved: 0, duplicates: 0, failed: 0,
                             records: loadRecords(), undo: nil, nextEligible: nil)
        }
        let fm = FileManager.default

        let now = Date()
        let recordsBefore = loadRecords()
        var records = recordsBefore
        var undoActions: [UndoTransaction.Action] = []
        var moved = 0
        var duplicates = 0
        var failed = 0
        var nextEligible: Date?

        if let destination = settings.destination, let root {
            records = recordsBefore.filter {
                fm.fileExists(atPath: $0.destinationPath)
            }
            let files: [SourceFile]
            do {
                files = try sourceFiles(in: root)
            } catch {
                return RunResult(moved: 0, duplicates: 0, failed: 1,
                                 records: loadRecords(), undo: nil, nextEligible: nil)
            }

            for source in files {
                guard settings.categories.contains(source.category),
                      let folderBase = DownloadRouter.destination(
                        for: DownloadCandidate(url: source.url, agent: source.agent,
                                               destination: destination),
                        configured: settings.sources,
                        extensionWhitelist: settings.extensionWhitelist) else { continue }
                guard WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: source.downloadedAt, modifiedAt: source.modifiedAt,
                    now: now, delayMinutes: settings.delayMinutes) else {
                    let base = max(source.downloadedAt, source.modifiedAt)
                    let eligible = base.addingTimeInterval(
                        TimeInterval(settings.delayMinutes * 60 + 1))
                    nextEligible = min(nextEligible ?? eligible, eligible)
                    continue
                }

                do {
                    guard fingerprint(for: source.url) == source.fingerprint else {
                        failed += 1
                        continue
                    }
                    let digest = try sha256(of: source.url)
                    let validDuplicateIndex = DownloadUndoPolicy.resolveDuplicate(
                        digest: digest, records: &records) { record in
                        let url = URL(fileURLWithPath: record.destinationPath)
                        return FileManager.default.fileExists(atPath: url.path)
                            && (try? Self.sha256(of: url)) == digest
                    }
                    guard sourceStillMatches(source) else {
                        failed += 1
                        continue
                    }

                    if let duplicateIndex = validDuplicateIndex {
                        let existing = URL(fileURLWithPath: records[duplicateIndex].destinationPath)
                        switch settings.duplicateAction {
                        case .trashNew:
                            let trashed = try trash(source.url)
                            if let trashed {
                                undoActions.insert(.init(kind: .move,
                                                         currentPath: trashed.path,
                                                         restorePath: source.url.path), at: 0)
                            }
                            duplicates += 1
                            continue
                        case .replaceExisting:
                            let actions = try replaceVerified(source: source.url,
                                                              existing: existing,
                                                              digest: digest)
                            records[duplicateIndex] = OrganizedFileRecord(
                                digest: digest, destinationPath: existing.path,
                                originalName: source.url.lastPathComponent,
                                size: source.size, organizedAt: now)
                            undoActions.insert(contentsOf: actions, at: 0)
                            moved += 1
                            duplicates += 1
                            continue
                        case .keepBoth:
                            break
                        }
                    }

                    let components = WhatsAppDownloadSupport.organizerRelativeComponents(
                        layout: settings.layout, category: source.category,
                        date: source.downloadedAt)
                    let folder = components.reduce(folderBase) {
                        $0.appendingPathComponent($1, isDirectory: true)
                    }
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = uniqueDestination(
                        in: folder, preferredName: source.url.lastPathComponent)
                    let actions = try moveVerified(source: source.url,
                                                   destination: destination,
                                                   digest: digest)
                    undoActions.insert(contentsOf: actions, at: 0)
                    records.append(OrganizedFileRecord(digest: digest,
                                          destinationPath: destination.path,
                                          originalName: source.url.lastPathComponent,
                                          size: source.size, organizedAt: now))
                    moved += 1
                } catch {
                    failed += 1
                }
            }
        }

        if let archive = settings.archive {
            // Same pass, same queue block, same undo array: one "Undo last
            // organization" then restores a routed download and a filed-away
            // capture together, because they were one decision to begin with.
            archiveScreenshots(archive, now: now, undoActions: &undoActions,
                               moved: &moved, failed: &failed)
        }

        records = Array(records.sorted { $0.organizedAt < $1.organizedAt }.suffix(5_000))
        let undo = undoActions.isEmpty ? nil : UndoTransaction(
            id: UUID(), actions: undoActions, recordsBefore: recordsBefore,
            recordsAfter: records, createdAt: now)
        return RunResult(moved: moved, duplicates: duplicates, failed: failed,
                         records: records, undo: undo, nextEligible: nextEligible)
    }

    private static let archiveResourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isDirectoryKey,
        .isPackageKey, .isHiddenKey, .addedToDirectoryDateKey,
        .contentModificationDateKey,
    ]

    /// The second policy's stage of the pass: files away screenshots that
    /// macOS itself marked as captures and that have been sitting, untouched
    /// and undisturbed since they arrived, in the top level of the screenshot
    /// folder. Only that top level: a subfolder is a decision about grouping,
    /// and this pass does not reach into one.
    ///
    /// No name rule applies here, deliberately. `JunkCleaner` skips a capture
    /// the person renamed because for DELETION a rename is a decision to keep.
    /// This policy does not delete anything - it moves a file to a subfolder
    /// of the folder it is already in, where it remains visible and keeps its
    /// name - so borrowing the cleaner's rule would make a renamed capture
    /// immortal for a reason that has nothing to do with this decision.
    private static func archiveScreenshots(_ archive: ArchiveSettings, now: Date,
                                           undoActions: inout [UndoTransaction.Action],
                                           moved: inout Int, failed: inout Int) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: archive.folder, includingPropertiesForKeys: Array(archiveResourceKeys),
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { return }

        let candidates = entries.compactMap { url -> ScreenshotCandidate? in
            let standardized = url.standardizedFileURL
            guard WhatsAppDownloadSupport.isDirectChild(standardized, of: archive.folder),
                  !WhatsAppDownloadSupport.isIncompleteFile(
                    extension: standardized.pathExtension),
                  let values = try? standardized.resourceValues(forKeys: archiveResourceKeys),
                  values.isRegularFile == true,
                  values.isDirectory != true,
                  values.isPackage != true,
                  values.isSymbolicLink != true,
                  values.isAliasFile != true,
                  values.isHidden != true,
                  let touched = values.contentModificationDate,
                  captureFlag(of: standardized) else { return nil }
            return ScreenshotCandidate(url: standardized, touched: touched,
                                       added: values.addedToDirectoryDate)
        }

        var archiveFolderExists = false
        for candidate in candidates where ScreenshotArchiveSupport.shouldArchive(
            age: candidate.touched, added: candidate.added, boundary: archive.boundary) {
            do {
                // Reads the bytes once per archived capture, which is the one
                // cost this policy adds: the digest is what lets the existing
                // move primitive verify the copy across volumes, and a
                // capture qualifies only after going untouched for at least
                // seven days and then leaves the folder permanently.
                let digest = try sha256(of: candidate.url)
                // Created at the moment of the first move, never before: a
                // pass that finds nothing to file away must not leave an
                // empty folder behind in the person's screenshot folder.
                if !archiveFolderExists {
                    try fm.createDirectory(at: archive.destination,
                                           withIntermediateDirectories: true)
                    archiveFolderExists = true
                }
                let destination = uniqueDestination(
                    in: archive.destination,
                    preferredName: candidate.url.lastPathComponent)
                let actions = try moveVerified(source: candidate.url,
                                               destination: destination, digest: digest)
                undoActions.insert(contentsOf: actions, at: 0)
                // Deliberately no OrganizedFileRecord. Records are the
                // routing ledger, keyed by digest, and a capture filed away by
                // this policy must never become a duplicate verdict against
                // a file the person is still downloading. Undo restores from
                // transaction.actions, which is independent of records, and
                // its refusal to overwrite anything already sitting at the
                // restore path is what keeps putting a capture back safe.
                //
                // `moved` is reused rather than a new counter: the summary
                // this pass reports is one localized format string, so a new
                // counter would need a new string in fifteen languages to say
                // nothing the person cannot already read there.
                moved += 1
            } catch {
                failed += 1
            }
        }
    }

    /// Whether macOS itself wrote "this is a screenshot" onto the file. The
    /// attribute name and the decoding are the cleaner's; only the `getxattr`
    /// call is repeated here, because the cleaner's copy is private to it.
    /// That duplication is worth collapsing later and not worth forking a
    /// shared policy file over now: the two must stay in step, and both answer
    /// the same question of the same attribute.
    private static func captureFlag(of url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            let length = getxattr(path, CleanerSupport.screenCaptureAttribute, nil, 0, 0,
                                  XATTR_NOFOLLOW)
            guard length > 0, length <= 4096 else { return false }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes {
                getxattr(path, CleanerSupport.screenCaptureAttribute, $0.baseAddress, length, 0,
                         XATTR_NOFOLLOW)
            }
            guard read == length else { return false }
            return CleanerSupport.isScreenCaptureFlag(data)
        }
    }

    private static let sourceResourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isDirectoryKey,
        .isPackageKey, .isHiddenKey, .fileSizeKey, .contentTypeKey,
        .quarantinePropertiesKey, .addedToDirectoryDateKey, .creationDateKey,
        .contentModificationDateKey,
    ]

    private static func sourceFiles(in root: URL) throws -> [SourceFile] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(sourceResourceKeys),
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard WhatsAppDownloadSupport.isDirectChild(standardized, of: root),
                  !WhatsAppDownloadSupport.isIncompleteFile(
                    extension: standardized.pathExtension),
                  let values = try? standardized.resourceValues(forKeys: sourceResourceKeys),
                  values.isRegularFile == true,
                  values.isDirectory != true,
                  values.isPackage != true,
                  values.isSymbolicLink != true,
                  values.isAliasFile != true,
                  values.isHidden != true,
                  let quarantine = values.quarantineProperties,
                  let downloadedAt = (quarantine["LSQuarantineTimeStamp"] as? Date)
                    ?? values.addedToDirectoryDate ?? values.creationDate,
                  let fingerprint = fingerprint(for: standardized)
            else { return nil }
            let modified = values.contentModificationDate ?? downloadedAt
            let category = WhatsAppDownloadSupport.category(
                contentTypeIdentifier: values.contentType?.identifier,
                extension: standardized.pathExtension)
            return SourceFile(url: standardized,
                              agent: quarantine["LSQuarantineAgentName"] as? String,
                              fingerprint: fingerprint,
                              size: Int64(values.fileSize ?? 0),
                              downloadedAt: downloadedAt, modifiedAt: modified,
                              category: category)
        }
    }

    private static func uniqueDestination(in folder: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        let preferred = folder.appendingPathComponent(preferredName)
        guard fm.fileExists(atPath: preferred.path) else { return preferred }
        let source = URL(fileURLWithPath: preferredName)
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private static func moveVerified(source: URL,
                                     destination: URL,
                                     digest: String) throws -> [UndoTransaction.Action] {
        let fm = FileManager.default
        let sourceVolume = (try? source.resourceValues(forKeys: [.volumeIdentifierKey]))?
            .volumeIdentifier as? NSObject
        let destinationVolume = (try? destination.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject

        if WhatsAppDownloadSupport.isSameVolume(source: sourceVolume,
                                                destination: destinationVolume) {
            // Same volume: this is a rename, so no byte ever moves and the
            // digest cannot change. Re-hashing here read a second full copy of
            // every file - on a multi-gigabyte video, longer than the move.
            // The cross-volume branch below copies and must still verify.
            try fm.moveItem(at: source, to: destination)
            return [.init(kind: .move, currentPath: destination.path,
                          restorePath: source.path)]
        }

        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".vorssaint-\(UUID().uuidString).partial")
        do {
            try fm.copyItem(at: source, to: temporary)
            guard try sha256(of: temporary) == digest else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try fm.moveItem(at: temporary, to: destination)
            guard let trashedSource = try trash(source) else {
                _ = try? trash(destination)
                throw CocoaError(.fileWriteUnknown)
            }
            return [
                .init(kind: .trash, currentPath: destination.path, restorePath: nil),
                .init(kind: .move, currentPath: trashedSource.path, restorePath: source.path),
            ]
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    private static func replaceVerified(source: URL,
                                        existing: URL,
                                        digest: String) throws -> [UndoTransaction.Action] {
        let fm = FileManager.default
        let staging = existing.deletingLastPathComponent().appendingPathComponent(
            ".vorssaint-replaced-\(UUID().uuidString).partial")
        try fm.moveItem(at: existing, to: staging)
        do {
            let newActions = try moveVerified(source: source,
                                              destination: existing,
                                              digest: digest)
            guard let trashedExisting = try trash(staging) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return newActions + [
                .init(kind: .move, currentPath: trashedExisting.path,
                      restorePath: existing.path),
            ]
        } catch {
            if !fm.fileExists(atPath: existing.path) {
                try? fm.moveItem(at: staging, to: existing)
            } else {
                _ = try? trash(staging)
            }
            throw error
        }
    }

    private static func trash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fingerprint(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return "\(device):\(inode)"
    }

    private static func sourceStillMatches(_ source: SourceFile) -> Bool {
        guard fingerprint(for: source.url) == source.fingerprint,
              let attributes = try? FileManager.default.attributesOfItem(
                atPath: source.url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date else { return false }
        return size == source.size
            && abs(modified.timeIntervalSince(source.modifiedAt)) < 0.001
    }

    private static func loadRecords() -> [OrganizedFileRecord] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.whatsAppOrganizerRecords),
              !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([OrganizedFileRecord].self, from: data)) ?? []
    }

    private static func saveRecords(_ records: [OrganizedFileRecord]) {
        let data = (try? JSONEncoder().encode(records)) ?? Data()
        UserDefaults.standard.set(data, forKey: DefaultsKey.whatsAppOrganizerRecords)
    }

    private static func loadUndoTransactions() -> [UndoTransaction] {
        guard let data = UserDefaults.standard.data(
            forKey: DefaultsKey.whatsAppOrganizerUndoTransaction),
              !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([UndoTransaction].self, from: data)) ?? []
    }

    private static func validUndoTransactions(now: Date = Date()) -> [UndoTransaction] {
        loadUndoTransactions()
            .filter { WhatsAppDownloadSupport.organizerUndoIsValid(
                createdAt: $0.createdAt, now: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private static func saveUndoTransactions(_ transactions: [UndoTransaction]) {
        let data = (try? JSONEncoder().encode(transactions)) ?? Data()
        UserDefaults.standard.set(data,
                                  forKey: DefaultsKey.whatsAppOrganizerUndoTransaction)
    }

    private static func performUndo(_ transaction: UndoTransaction) -> Int {
        let fm = FileManager.default
        var failed = 0
        for action in transaction.actions {
            let current = URL(fileURLWithPath: action.currentPath)
            guard fm.fileExists(atPath: current.path) else {
                failed += 1
                continue
            }
            do {
                switch action.kind {
                case .move:
                    guard let restorePath = action.restorePath else {
                        failed += 1
                        continue
                    }
                    let restore = URL(fileURLWithPath: restorePath)
                    guard !fm.fileExists(atPath: restore.path) else {
                        failed += 1
                        continue
                    }
                    try fm.createDirectory(at: restore.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try fm.moveItem(at: current, to: restore)
                case .trash:
                    _ = try trash(current)
                }
            } catch {
                failed += 1
            }
        }
        return failed
    }
}
