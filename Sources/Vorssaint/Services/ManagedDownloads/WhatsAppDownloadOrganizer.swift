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

    struct Record: Codable, Equatable {
        let digest: String
        let destinationPath: String
        let originalName: String
        let size: Int64
        let organizedAt: Date
    }

    private struct UndoTransaction: Codable {
        enum ActionKind: String, Codable { case move, trash }
        struct Action: Codable {
            let kind: ActionKind
            let currentPath: String
            let restorePath: String?
        }

        let id: UUID
        let actions: [Action]
        let recordsBefore: [Record]
        let recordsAfter: [Record]
        let createdAt: Date
    }

    private struct SourceFile {
        let url: URL
        let fingerprint: String
        let size: Int64
        let downloadedAt: Date
        let modifiedAt: Date
        let category: WhatsAppDownloadCategory
    }

    private struct Settings {
        let destination: URL
        let delayMinutes: Int
        let categories: Set<WhatsAppDownloadCategory>
        let layout: WhatsAppOrganizerLayout
        let duplicateAction: WhatsAppDuplicateAction
    }

    private struct RunResult {
        let moved: Int
        let duplicates: Int
        let failed: Int
        let records: [Record]
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
        let destination = configured.isEmpty
            ? root.appendingPathComponent("WhatsApp", isDirectory: true)
            : URL(fileURLWithPath: configured, isDirectory: true)
        let standardized = destination.standardizedFileURL
        guard standardized.path != root.standardizedFileURL.path else {
            return root.appendingPathComponent("WhatsApp", isDirectory: true)
        }
        return standardized
    }

    static func managedDestinationPaths() -> Set<String> {
        Set(loadRecords().map { URL(fileURLWithPath: $0.destinationPath).standardizedFileURL.path })
    }

    func syncWithPreferences() {
        stopMonitoring()
        guard AppFeature.cleaner.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppOrganizerEnabled),
              UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed),
              let root = downloadsURL else {
            phase = .idle
            return
        }
        startMonitoring(root: root)
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
              Self.recordsAllowUndo(transaction, current: Self.loadRecords()) else { return }
        let token = UUID()
        operationToken = token
        phase = .undoing
        queue.async { [weak self] in
            let failed = Self.performUndo(transaction)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationToken == token else { return }
                if failed == 0 {
                    Self.saveRecords(Self.recordsAfterUndo(
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
        guard UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppOrganizerEnabled) else { return }
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
        guard AppFeature.cleaner.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppOrganizerEnabled),
              let root = downloadsURL,
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

    private func settings(root: URL) -> Settings? {
        guard let destination = Self.destinationURL(downloadsURL: root) else { return nil }
        let defaults = UserDefaults.standard
        return Settings(
            destination: destination,
            delayMinutes: WhatsAppDownloadSupport.sanitizedOrganizerDelayMinutes(
                defaults.integer(forKey: DefaultsKey.whatsAppOrganizerDelayMinutes)),
            categories: WhatsAppDownloadSupport.decodedCategories(
                defaults.string(forKey: DefaultsKey.whatsAppOrganizerCategories)),
            layout: WhatsAppOrganizerLayout(
                rawValue: defaults.string(forKey: DefaultsKey.whatsAppOrganizerLayout) ?? "") ?? .flat,
            duplicateAction: WhatsAppDuplicateAction(
                rawValue: defaults.string(
                    forKey: DefaultsKey.whatsAppOrganizerDuplicateAction) ?? "") ?? .trashNew)
    }

    private static func organize(root: URL, settings: Settings) -> RunResult {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: settings.destination,
                                   withIntermediateDirectories: true)
        } catch {
            return RunResult(moved: 0, duplicates: 0, failed: 1,
                             records: loadRecords(), undo: nil, nextEligible: nil)
        }

        let now = Date()
        let files: [SourceFile]
        do {
            files = try sourceFiles(in: root)
        } catch {
            return RunResult(moved: 0, duplicates: 0, failed: 1,
                             records: loadRecords(), undo: nil, nextEligible: nil)
        }

        let recordsBefore = loadRecords()
        var records = recordsBefore.filter {
            fm.fileExists(atPath: $0.destinationPath)
        }
        var undoActions: [UndoTransaction.Action] = []
        var moved = 0
        var duplicates = 0
        var failed = 0
        var nextEligible: Date?

        for source in files where settings.categories.contains(source.category) {
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
                let validDuplicateIndex = try firstValidRecordIndex(
                    digest: digest, records: &records)
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
                        records[duplicateIndex] = Record(
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
                let folder = components.reduce(settings.destination) {
                    $0.appendingPathComponent($1, isDirectory: true)
                }
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = uniqueDestination(
                    in: folder, preferredName: source.url.lastPathComponent)
                let actions = try moveVerified(source: source.url,
                                               destination: destination,
                                               digest: digest)
                undoActions.insert(contentsOf: actions, at: 0)
                records.append(Record(digest: digest,
                                      destinationPath: destination.path,
                                      originalName: source.url.lastPathComponent,
                                      size: source.size, organizedAt: now))
                moved += 1
            } catch {
                failed += 1
            }
        }

        records = Array(records.sorted { $0.organizedAt < $1.organizedAt }.suffix(5_000))
        let undo = undoActions.isEmpty ? nil : UndoTransaction(
            id: UUID(), actions: undoActions, recordsBefore: recordsBefore,
            recordsAfter: records, createdAt: now)
        return RunResult(moved: moved, duplicates: duplicates, failed: failed,
                         records: records, undo: undo, nextEligible: nextEligible)
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
                  WhatsAppDownloadSupport.isWhatsAppAgent(
                    quarantine["LSQuarantineAgentName"] as? String),
                  let downloadedAt = (quarantine["LSQuarantineTimeStamp"] as? Date)
                    ?? values.addedToDirectoryDate ?? values.creationDate,
                  let fingerprint = fingerprint(for: standardized)
            else { return nil }
            let modified = values.contentModificationDate ?? downloadedAt
            let category = WhatsAppDownloadSupport.category(
                contentTypeIdentifier: values.contentType?.identifier,
                extension: standardized.pathExtension)
            return SourceFile(url: standardized, fingerprint: fingerprint,
                              size: Int64(values.fileSize ?? 0),
                              downloadedAt: downloadedAt, modifiedAt: modified,
                              category: category)
        }
    }

    private static func firstValidRecordIndex(digest: String,
                                              records: inout [Record]) throws -> Int? {
        var index = 0
        while index < records.count {
            guard records[index].digest == digest else {
                index += 1
                continue
            }
            let url = URL(fileURLWithPath: records[index].destinationPath)
            guard FileManager.default.fileExists(atPath: url.path),
                  (try? sha256(of: url)) == digest else {
                records.remove(at: index)
                continue
            }
            return index
        }
        return nil
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
        let sourceVolume = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let destinationVolume = try? destination.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier

        if let sourceVolume, let destinationVolume,
           String(describing: sourceVolume) == String(describing: destinationVolume) {
            try fm.moveItem(at: source, to: destination)
            guard (try? sha256(of: destination)) == digest else {
                try? fm.moveItem(at: destination, to: source)
                throw CocoaError(.fileReadCorruptFile)
            }
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

    private static func loadRecords() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.whatsAppOrganizerRecords),
              !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private static func saveRecords(_ records: [Record]) {
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

    private static func recordMap(_ records: [Record]) -> [String: Record] {
        Dictionary(records.map { ($0.destinationPath, $0) },
                   uniquingKeysWith: { _, latest in latest })
    }

    private static func affectedRecordPaths(_ transaction: UndoTransaction) -> Set<String> {
        let before = recordMap(transaction.recordsBefore)
        let after = recordMap(transaction.recordsAfter)
        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
    }

    private static func recordsAllowUndo(_ transaction: UndoTransaction,
                                         current: [Record]) -> Bool {
        let expected = recordMap(transaction.recordsAfter)
        let current = recordMap(current)
        return affectedRecordPaths(transaction).allSatisfy { current[$0] == expected[$0] }
    }

    private static func recordsAfterUndo(_ transaction: UndoTransaction,
                                         current: [Record]) -> [Record] {
        let before = recordMap(transaction.recordsBefore)
        var result = recordMap(current)
        for path in affectedRecordPaths(transaction) {
            result[path] = before[path]
        }
        return result.values.sorted { $0.organizedAt < $1.organizedAt }
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
