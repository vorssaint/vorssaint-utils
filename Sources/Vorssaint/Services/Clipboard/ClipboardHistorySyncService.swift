// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CloudKit
import Foundation
import IOKit
import Security

/// Opt-in sync of the clipboard history between the user's Macs, through the
/// private CloudKit database of their own Apple Account (issue #3142).
///
/// CloudKit only works in a build signed with an iCloud container entitlement,
/// which a Developer ID app can carry only with a Developer ID provisioning
/// profile of the team that owns the container (see build.sh). The container
/// is read from this build's own signature, so the release and a build signed
/// by another team each use their own; a build without one, such as a local
/// or ad hoc build, hides the feature. Each Mac writes only its own records
/// and merges the others' into its history; see ClipboardHistorySync for the
/// rules and ClipboardHistoryCloudRecords for the records.
///
/// Main-thread state. CloudKit calls run one round at a time.
final class ClipboardHistorySyncService: ObservableObject {
    static let shared = ClipboardHistorySyncService()

    typealias Status = ClipboardHistorySyncStatus

    @Published private(set) var status: Status = .off
    /// True while a round talks to CloudKit.
    @Published private(set) var isSyncing = false

    /// The CloudKit container this build is entitled to, or nil. Asking
    /// CloudKit for a container the signature does not name ends the process,
    /// so nothing touches CloudKit without it.
    static let containerIdentifier: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(
                  task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              services.contains("CloudKit"),
              let containers = SecTaskCopyValueForEntitlement(
                  task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        else { return nil }
        return containers.first { !$0.isEmpty }
    }()

    static var isAvailable: Bool { containerIdentifier != nil }

    /// What this Mac remembers between launches: its deletions and pin
    /// changes, plus those adopted from the other Macs, and whether turning
    /// sync off still has to take this Mac's records out of iCloud.
    private struct State: Codable, Equatable {
        var deleted: [String: Date] = [:]
        var pinChanges: [String: Date] = [:]
        var removalPending = false
    }

    /// What decides which remote entries fit here; a change merges again.
    private struct Signature: Equatable {
        let policy: ClipboardHistorySyncPolicy
        let limit: Int
        let retentionDays: Int
    }

    private let queue = DispatchQueue(label: "com.vorssaint.utils.clipboard-sync", qos: .utility)
    private static let stateQueue = DispatchQueue(label: "com.vorssaint.utils.clipboard-sync-state",
                                                  qos: .utility)
    private lazy var container: CKContainer? = Self.containerIdentifier.map { CKContainer(identifier: $0) }
    private var running = false
    private var device: String?
    private var state = State()
    private var stateLoaded = false
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private var signature: Signature?
    private var syncScheduled = false
    private var busy = false {
        didSet { if isSyncing != busy { isSyncing = busy } }
    }
    private var syncAgain = false
    private var publishPending = true
    /// Merge even when nothing changed in iCloud: the local limits or filters
    /// moved, or a picture was still missing at the last look.
    private var forceMerge = true
    private var retryAfter: Date?
    private var accountChecked = false
    private var zoneReady = false

    /// This Mac's mirror of the zone, kept current from the change feed.
    private var changeToken: CKServerChangeToken?
    private var entryRecords: [String: (device: String, record: ClipboardHistorySyncRecord)] = [:]
    private var deviceStates: [String: ClipboardHistoryCloudRecords.DeviceState] = [:]
    private var publishedState: ClipboardHistoryCloudRecords.DeviceState?

    private init() {}

    private var wanted: Bool {
        let defaults = UserDefaults.standard
        return Self.isAvailable
            && AppFeature.clipboardHistory.isAvailable
            && defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
            && defaults.bool(forKey: DefaultsKey.clipboardHistorySyncEnabled)
    }

    func syncWithPreferences() {
        if wanted {
            start()
            return
        }
        stop()
        // Turning sync off promised to take this Mac's copy out of iCloud; a
        // removal that could not finish then is finished now.
        guard Self.isAvailable, !UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistorySyncEnabled)
        else { return }
        loadState()
        if state.removalPending { Task { @MainActor in await self.removeThisMac() } }
    }

    /// Reads the other Macs' changes and publishes this Mac's at once, instead
    /// of at the next round. Nothing to do while one is under way.
    func syncNow() {
        guard running, !busy else { return }
        forceMerge = true
        publishPending = true
        scheduleSync(after: 0)
    }

    /// The settings switch. Turning it off also takes this Mac's records out
    /// of iCloud; the other Macs keep what they already received.
    func setEnabled(_ enabled: Bool) {
        guard Self.isAvailable else { return }
        if enabled {
            syncWithPreferences()
            return
        }
        stop()
        loadState()
        state = State(removalPending: true)
        saveState()
        Task { @MainActor in await self.removeThisMac() }
    }

    // MARK: - Hooks from the history

    /// Any saved change: a new copy, a re-copy, a move, an edit, a trim.
    func historyDidChange() {
        guard running else { return }
        publishPending = true
        scheduleSync(after: 2)
    }

    /// Entries the user deleted or cleared, as opposed to ones the local
    /// limits dropped: only these are deleted on the other Macs too.
    func historyDidRemove(_ removed: [ClipboardHistoryEntry]) {
        guard running, !removed.isEmpty else { return }
        let now = Date()
        for key in ClipboardHistorySync.deletedKeys(for: removed, policy: Self.currentPolicy()) {
            state.deleted[key] = now
        }
        saveState()
        historyDidChange()
    }

    func historyDidChangePin(_ entry: ClipboardHistoryEntry) {
        guard running, ClipboardHistorySync.allows(entry, policy: Self.currentPolicy()),
              let key = ClipboardHistorySync.key(for: entry) else { return }
        state.pinChanges[key] = Date()
        saveState()
        historyDidChange()
    }

    /// Quit must not lose a deletion made just before it: the next launch
    /// would otherwise take the entry back from another Mac.
    func flushBeforeTermination() {
        Self.stateQueue.sync {}
    }

    // MARK: - Running

    private func start() {
        guard !running else { return }
        running = true
        status = .checking
        loadState()
        if state.removalPending {
            state.removalPending = false
            saveState()
        }
        device = device ?? Self.deviceIdentifier()
        forceMerge = true
        publishPending = true
        signature = currentSignature()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.scheduleSync(after: 0) }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.preferencesMayHaveChanged()
        }
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.accountChanged()
        }
        scheduleSync(after: 0)
    }

    private func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        for observer in [defaultsObserver, accountObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        defaultsObserver = nil
        accountObserver = nil
        status = .off
    }

    /// Another account, or the same one signed in again, starts from a clean
    /// mirror: nothing known about the old one applies.
    private func accountChanged() {
        accountChecked = false
        zoneReady = false
        resetMirror()
        forceMerge = true
        publishPending = true
        scheduleSync(after: 0)
    }

    private func resetMirror() {
        changeToken = nil
        entryRecords = [:]
        deviceStates = [:]
        publishedState = nil
    }

    private func preferencesMayHaveChanged() {
        guard running else { return }
        let current = currentSignature()
        guard current != signature else { return }
        signature = current
        forceMerge = true
        publishPending = true
        scheduleSync(after: 2)
    }

    private func currentSignature() -> Signature {
        let defaults = UserDefaults.standard
        return Signature(
            policy: Self.currentPolicy(),
            limit: Defaults.sanitizedClipboardHistoryLimit(defaults.integer(forKey: DefaultsKey.clipboardHistoryLimit)),
            retentionDays: Defaults.sanitizedClipboardHistoryRetentionDays(
                defaults.integer(forKey: DefaultsKey.clipboardHistoryRetentionDays)))
    }

    /// The same filters the history applies while it records, read now: an
    /// app added to the ignore list or the sensitive filter turned on also
    /// keeps entries saved before from leaving this Mac.
    static func currentPolicy() -> ClipboardHistorySyncPolicy {
        let defaults = UserDefaults.standard
        return ClipboardHistorySyncPolicy(
            includesImages: defaults.bool(forKey: DefaultsKey.clipboardHistorySyncImages)
                && defaults.bool(forKey: DefaultsKey.clipboardHistoryIncludeImagesFiles),
            skipsSensitiveText: defaults.bool(forKey: DefaultsKey.clipboardHistoryFilterSensitiveText),
            ignoredApps: Set(ClipboardIgnoredApps.shared.apps))
    }

    private func scheduleSync(after delay: TimeInterval) {
        guard running, !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.syncScheduled = false
            Task { @MainActor in await self.sync() }
        }
    }

    // MARK: - One round

    /// Checks the account and the zone, reads what changed, merges it, and
    /// publishes what changed here.
    @MainActor
    private func sync() async {
        guard running, let container, let device else { return }
        guard !busy else {
            syncAgain = true
            return
        }
        if let retryAfter, retryAfter > Date() { return }
        busy = true
        let database = container.privateCloudDatabase
        do {
            if !accountChecked {
                switch try await container.accountStatus() {
                case .available:
                    accountChecked = true
                case .noAccount, .restricted:
                    status = .noAccount
                    busy = false
                    return
                default:
                    status = .unavailable
                    busy = false
                    return
                }
            }
            if !zoneReady {
                let zone = CKRecordZone(zoneID: ClipboardHistoryCloudRecords.zoneID)
                let result = try await database.modifyRecordZones(saving: [zone], deleting: [])
                if case .failure(let error)? = result.saveResults[zone.zoneID] { throw error }
                zoneReady = true
            }
            if try await fetchChanges(database) { forceMerge = true }
            if running, forceMerge { try await merge(database, device: device) }
            if running, publishPending { try await publish(database, device: device) }
            retryAfter = nil
            if running {
                status = .synced(at: Date(), otherMacs: ClipboardHistoryCloudRecords.devices(
                    entries: entryRecords, states: deviceStates, excluding: device).count)
            }
        } catch {
            handle(error)
        }
        busy = false
        if syncAgain {
            syncAgain = false
            scheduleSync(after: 1)
        }
    }

    @MainActor
    private func handle(_ error: Error) {
        guard running else { return }
        guard let error = error as? CKError else {
            status = .unavailable
            return
        }
        let codes = [error.code] + (error.partialErrorsByItemID?.values.compactMap { ($0 as? CKError)?.code } ?? [])
        if let seconds = error.retryAfterSeconds { retryAfter = Date().addingTimeInterval(seconds) }
        if codes.contains(.userDeletedZone) {
            // The user deleted this data in iCloud's storage settings: that is
            // taken as stopping sync, not as a zone to bring back.
            UserDefaults.standard.set(false, forKey: DefaultsKey.clipboardHistorySyncEnabled)
            stop()
            resetMirror()
        } else if codes.contains(.notAuthenticated) {
            accountChecked = false
            status = .noAccount
        } else if codes.contains(.quotaExceeded) {
            status = .storageFull
        } else if codes.contains(.zoneNotFound) || codes.contains(.changeTokenExpired) {
            // A reset keychain makes the encrypted zone unreadable and reports
            // it missing; start over from a fresh zone and a full read.
            zoneReady = false
            resetMirror()
            forceMerge = true
            publishPending = true
            syncAgain = true
        } else {
            status = .unavailable
        }
    }

    /// Reads what changed in the zone since the last look. True when another
    /// Mac changed anything: this Mac's own writes come back here too, and
    /// those need no merge.
    @MainActor
    private func fetchChanges(_ database: CKDatabase) async throws -> Bool {
        var changed = false
        var moreComing = true
        while moreComing {
            let result = try await database.recordZoneChanges(inZoneWith: ClipboardHistoryCloudRecords.zoneID,
                                                              since: changeToken,
                                                              desiredKeys: ClipboardHistoryCloudRecords.mergeFields)
            for (_, modification) in result.modificationResultsByID {
                guard case .success(let modification) = modification else { continue }
                if absorb(modification.record) { changed = true }
            }
            for deletion in result.deletions where forget(deletion.recordID.recordName) {
                changed = true
            }
            changeToken = result.changeToken
            moreComing = result.moreComing
        }
        return changed
    }

    /// Takes a record into the mirror; true when another Mac wrote it.
    @discardableResult
    private func absorb(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        if let entry = ClipboardHistoryCloudRecords.syncRecord(from: record) {
            entryRecords[name] = entry
            return entry.device != device
        }
        if let state = ClipboardHistoryCloudRecords.deviceState(from: record) {
            deviceStates[state.device] = state.state
            if state.device == device { publishedState = state.state }
            return state.device != device
        }
        return entryRecords.removeValue(forKey: name).map { $0.device != device } ?? false
    }

    /// Drops a deleted record from the mirror; true when another Mac's went.
    @discardableResult
    private func forget(_ recordName: String) -> Bool {
        if let entry = entryRecords.removeValue(forKey: recordName) { return entry.device != device }
        guard let owner = ClipboardHistoryCloudRecords.device(ofDeviceRecordName: recordName) else { return false }
        deviceStates[owner] = nil
        if owner == device { publishedState = nil }
        return owner != device
    }

    // MARK: - Merging

    @MainActor
    private func merge(_ database: CKDatabase, device: String) async throws {
        forceMerge = false
        let history = ClipboardHistoryService.shared
        let snapshot = history.entries
        let protectedIDs = Set([history.editingEntryID].compactMap { $0 })
        let signature = currentSignature()
        let remotes = ClipboardHistoryCloudRecords.devices(entries: entryRecords, states: deviceStates,
                                                           excluding: device)
        let deleted = state.deleted
        let pinChanges = state.pinChanges
        let (merge, trimmed): (ClipboardHistorySync.Merge, [ClipboardHistoryEntry]) =
            await withCheckedContinuation { continuation in
                queue.async {
                    let merge = ClipboardHistorySync.merge(local: snapshot, remotes: remotes, tombstones: deleted,
                                                           pinChanges: pinChanges, policy: signature.policy,
                                                           protectedIDs: protectedIDs) { _ in
                        ClipboardHistorySync.pendingImageFile
                    }
                    // The local limits apply before any picture is fetched, so
                    // a long history elsewhere never downloads what this Mac
                    // would drop.
                    let trimmed = ClipboardHistoryEditing.retainedEntries(merge.entries,
                                                                          recentLimit: signature.limit,
                                                                          retentionDays: signature.retentionDays,
                                                                          ageExemptIDs: protectedIDs)
                    continuation.resume(returning: (merge, trimmed))
                }
            }
        state.deleted = ClipboardHistorySync.latest(state.deleted, merge.tombstones)
        state.pinChanges = ClipboardHistorySync.latest(state.pinChanges, merge.pinChanges)
        saveState()

        let pending = ClipboardHistorySync.pendingImageHashes(trimmed)
        let batch = Array(pending.prefix(Self.imageBatch))
        let images = batch.isEmpty ? [:] : try await fetchImages(batch, database)
        guard running else { return }
        guard history.entries == snapshot else {
            // The history moved while CloudKit answered; merge again.
            forceMerge = true
            syncAgain = true
            return
        }
        // Stored here on the main thread, in the same turn the entries land:
        // the history's own sweep runs here too and would otherwise take a
        // picture whose entry is not in the list yet.
        var stored: [String: String] = [:]
        for (hash, data) in images {
            stored[hash] = ClipboardImageStore.store(data)
        }
        // Trimmed again once the pictures that did not arrive are out, so they
        // never push a local entry past the limit.
        let resolved = ClipboardHistoryEditing.retainedEntries(
            ClipboardHistorySync.resolvingImages(merge.entries, stored: stored),
            recentLimit: signature.limit, retentionDays: signature.retentionDays, ageExemptIDs: protectedIDs)
        if resolved != snapshot { history.applySyncedEntries(resolved) }
        if images.count < pending.count {
            forceMerge = true
            if pending.count > batch.count { syncAgain = true }
        }
    }

    /// Pictures are fetched a few at a time, so the first sync of a Mac does
    /// not hold all of them in memory at once.
    private static let imageBatch = 20

    @MainActor
    private func fetchImages(_ hashes: [String], _ database: CKDatabase) async throws -> [String: Data] {
        var ids: [CKRecord.ID: String] = [:]
        for hash in hashes {
            let key = "i:" + hash
            guard let name = entryRecords.first(where: { $0.value.record.key == key })?.key else { continue }
            ids[CKRecord.ID(recordName: name, zoneID: ClipboardHistoryCloudRecords.zoneID)] = hash
        }
        guard !ids.isEmpty else { return [:] }
        let results = try await database.records(for: Array(ids.keys),
                                                 desiredKeys: [ClipboardHistoryCloudRecords.imageField])
        var files: [String: URL] = [:]
        for (id, result) in results {
            guard let hash = ids[id], case .success(let record) = result,
                  let url = (record[ClipboardHistoryCloudRecords.imageField] as? CKAsset)?.fileURL else { continue }
            files[hash] = url
        }
        // Read and checked off the main thread: a picture is only taken when
        // its bytes hash to the entry they belong to. The records stay alive
        // until then, since an asset's file may go with its record.
        return await withCheckedContinuation { continuation in
            queue.async {
                var images: [String: Data] = [:]
                withExtendedLifetime(results) {
                    for (hash, url) in files {
                        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                              size <= ClipboardHistorySync.maxImageBytes,
                              let data = try? Data(contentsOf: url),
                              ClipboardHistorySync.sha256Hex(data) == hash else { continue }
                        images[hash] = data
                    }
                }
                continuation.resume(returning: images)
            }
        }
    }

    // MARK: - Publishing

    @MainActor
    private func publish(_ database: CKDatabase, device: String) async throws {
        publishPending = false
        let entries = ClipboardHistoryService.shared.entries
        let policy = Self.currentPolicy()
        let keys = Set(entries.compactMap { ClipboardHistorySync.key(for: $0) })
        state.deleted = ClipboardHistorySync.prunedTombstones(state.deleted)
        state.pinChanges = ClipboardHistorySync.prunedPinChanges(state.pinChanges, keeping: keys)
        let pinChanges = state.pinChanges
        let imageDirectory = ClipboardImageStore.directory
        let desired: [ClipboardHistorySyncRecord] = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: ClipboardHistorySync.records(for: entries, policy: policy,
                                                                            pinChanges: pinChanges) { entry in
                    guard let name = entry.imageFile, let imageDirectory else { return nil }
                    return (try? imageDirectory.appendingPathComponent(name)
                        .resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                })
            }
        }
        let published = entryRecords.filter { $0.value.device == device }
            .map { (recordName: $0.key, record: $0.value.record) }
        let plan = ClipboardHistoryCloudRecords.plan(desired: desired, published: published) {
            ClipboardHistoryCloudRecords.newEntryRecordName(device: device)
        }

        var saving: [(record: CKRecord, cost: ClipboardHistoryCloudRecords.WriteCost)] = []
        // The Mac's own record goes first, so no other Mac reads an entry of
        // a Mac it does not know yet.
        let deviceState = ClipboardHistoryCloudRecords.DeviceState(deleted: state.deleted, seenAt: Date())
        if publishedState.map({ $0.deleted != deviceState.deleted
            || deviceState.seenAt.timeIntervalSince($0.seenAt) > ClipboardHistoryCloudRecords.seenInterval }) ?? true,
           let record = ClipboardHistoryCloudRecords.deviceRecord(device: device, state: deviceState) {
            saving.append((record, .init(bytes: ClipboardHistorySync.maxDeletedBytes, asset: false)))
        }
        let imageNames = Dictionary(entries.compactMap { entry in
            entry.imageHash.flatMap { hash in entry.imageFile.map { (hash, $0) } }
        }, uniquingKeysWith: { first, _ in first })
        for item in plan.save {
            let image = ClipboardHistorySync.imageHash(fromKey: item.record.key)
                .flatMap { imageNames[$0] }
                .flatMap { imageDirectory?.appendingPathComponent($0) }
            if item.record.kind == .image, image == nil { continue }
            saving.append((ClipboardHistoryCloudRecords.entryRecord(item.record, recordName: item.recordName,
                                                                    image: image),
                           .init(bytes: item.record.text.utf8.count, asset: image != nil)))
        }
        var deleting = plan.delete.map { CKRecord.ID(recordName: $0, zoneID: ClipboardHistoryCloudRecords.zoneID) }

        var firstError: Error?
        while !saving.isEmpty || !deleting.isEmpty {
            let saveCount = ClipboardHistoryCloudRecords.batchCount(saving.map(\.cost))
            let saveBatch = saving.prefix(saveCount).map(\.record)
            saving.removeFirst(saveCount)
            let deleteBatch = Array(deleting.prefix(ClipboardHistoryCloudRecords.maxBatchRecords - saveCount))
            deleting.removeFirst(deleteBatch.count)
            // Each record has one writer, this Mac, so its copy always wins.
            let result = try await database.modifyRecords(saving: saveBatch, deleting: deleteBatch,
                                                          savePolicy: .allKeys, atomically: false)
            for (_, saved) in result.saveResults {
                switch saved {
                case .success(let record): absorb(record)
                case .failure(let error): firstError = firstError ?? error
                }
            }
            for (id, deleted) in result.deleteResults {
                switch deleted {
                case .success: forget(id.recordName)
                case .failure(let error): firstError = firstError ?? error
                }
            }
        }
        if let firstError {
            publishPending = true
            throw firstError
        }
    }

    // MARK: - Leaving

    /// Deletes every record this Mac wrote. The zone stays: another Mac may
    /// still be using it.
    @MainActor
    private func removeThisMac() async {
        guard let container, let device = device ?? Self.deviceIdentifier(), !running else { return }
        guard !busy else {
            // A round still in flight finishes first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Task { @MainActor in await self.removeThisMac() }
            }
            return
        }
        busy = true
        let database = container.privateCloudDatabase
        do {
            guard try await container.accountStatus() == .available else {
                busy = false
                return
            }
            resetMirror()
            _ = try await fetchChanges(database)
            var deleting = entryRecords.filter { $0.value.device == device }
                .map { CKRecord.ID(recordName: $0.key, zoneID: ClipboardHistoryCloudRecords.zoneID) }
            if deviceStates[device] != nil { deleting.append(ClipboardHistoryCloudRecords.deviceRecordID(device)) }
            while !deleting.isEmpty {
                let batch = Array(deleting.prefix(ClipboardHistoryCloudRecords.maxBatchRecords))
                deleting.removeFirst(batch.count)
                let result = try await database.modifyRecords(saving: [], deleting: batch)
                for case .failure(let error) in result.deleteResults.values { throw error }
            }
            state.removalPending = false
            saveState()
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Nothing of this Mac's is left in iCloud.
            state.removalPending = false
            saveState()
        } catch {
            // Tried again at the next launch.
        }
        resetMirror()
        zoneReady = false
        busy = false
    }

    // MARK: - Local state

    private static var stateURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("ClipboardHistorySync.json")
    }

    private func loadState() {
        guard !stateLoaded else { return }
        stateLoaded = true
        let decoder = JSONDecoder()
        guard let url = Self.stateURL,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= 4 * ClipboardHistorySync.maxDeletedBytes,
              let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(State.self, from: data)
        else { return }
        state = State(deleted: ClipboardHistorySync.prunedTombstones(decoded.deleted),
                      pinChanges: decoded.pinChanges.filter { ClipboardHistorySync.isValidKey($0.key) },
                      removalPending: decoded.removalPending)
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let url = Self.stateURL else { return }
        let data = state == State() ? nil : try? encoder.encode(state)
        Self.stateQueue.async {
            guard let data else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            PrivateFileStore.createDirectory(at: url.deletingLastPathComponent())
            PrivateFileStore.write(data, to: url)
        }
    }

    // MARK: - This Mac

    /// A hash of the Mac's hardware identifier, the account and the bundle,
    /// so a restored backup or a migrated account on a new Mac never writes
    /// the same records as the Mac it came from.
    static func deviceIdentifier() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let hardware = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                                                             kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String, !hardware.isEmpty
        else { return nil }
        return ClipboardHistorySync.deviceIdentifier(hardware: hardware, user: NSUserName(),
                                                     bundle: Bundle.main.bundleIdentifier ?? "")
    }
}
