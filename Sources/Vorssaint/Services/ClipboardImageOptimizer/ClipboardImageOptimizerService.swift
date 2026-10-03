// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Re-encodes a lone copied image into a smaller one of the same kind, and a
/// lone copied video, PDF or HEIC-style image into a smaller file that the
/// clipboard then points at. Polls like the URL cleaner: change count, item
/// count and type names only, and content is read only once those say it
/// qualifies. Whatever is already on the pasteboard when it starts is never
/// touched, and a copied file itself is only ever read.
final class ClipboardImageOptimizerService: ObservableObject {
    static let shared = ClipboardImageOptimizerService()

    @Published private(set) var isRunning = false

    private final class PollToken {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    /// One copied file being turned into a smaller one. Cancelled by any new
    /// copy, a setting that rules it out, sleep, or the feature stopping.
    private final class FileJob {
        let changeCount: Int
        let generation: Int
        let source: ClipboardImageOptimizerSupport.Source
        let directory: URL
        private let lock = NSLock()
        private var cancelled = false
        private var process: Process?
        private(set) var cancelledAt: Date?

        init(changeCount: Int, generation: Int, source: ClipboardImageOptimizerSupport.Source, directory: URL) {
            self.changeCount = changeCount
            self.generation = generation
            self.source = source
            self.directory = directory
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        /// The encoder notices and stops its process itself; `immediately`
        /// is for quitting, when there is no time to wait for that.
        func cancel(immediately: Bool = false) {
            lock.lock()
            if !cancelled {
                cancelled = true
                cancelledAt = Date()
            }
            let process = self.process
            lock.unlock()
            if immediately, let process, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        func attach(_ process: Process) {
            lock.lock()
            self.process = process
            let cancelled = self.cancelled
            lock.unlock()
            if cancelled { process.terminate() }
        }
    }

    private static let pollTimeout: TimeInterval = 2
    /// A cancelled job that has not stopped by then is left to finish alone;
    /// its result is dropped and its folder swept.
    private static let abandonAfter: TimeInterval = 2
    private static let readTimeout: TimeInterval = 4

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var fileJob: FileJob?
    /// The optimized file most recently put on the clipboard; never swept.
    private var lastOutputPath: String?
    /// False until the start-up cleanup has run, so it never kills or removes
    /// a job this session started.
    private var storeReady = false
    private var lastChangeCount = 0
    /// No poll acts until the starting change count is known; otherwise a
    /// timed-out baseline would let the image already copied be rewritten.
    private var hasBaseline = false
    private var lastOwnWrite: Int?
    private var pollInFlight = false
    private var pollToken: PollToken?
    private var encodeInFlight = false

    /// Read from the pasteboard lane and the encode queue, so it sits behind
    /// a lock: a result is written only if nothing turned the feature off or
    /// reconfigured it since the work started.
    private let stateLock = NSLock()
    private var generation = 0
    private var enabled = false

    private let encodeQueue = DispatchQueue(label: "Vorssaint.ClipboardImageOptimizer.encode", qos: .utility)
    private let storeQueue = DispatchQueue(label: "Vorssaint.ClipboardImageOptimizer.store", qos: .utility)

    private init() {}

    func syncWithPreferences() {
        if AppFeature.clipboardImageOptimizer.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.clipboardImageOptimizerEnabled) {
            start()
            if let job = fileJob, !Self.scope().allows(job.source) { job.cancel() }
        } else {
            let wasRunning = isRunning
            stop()
            if wasRunning { clearOptimizedCopies() }
        }
    }

    /// Deletes every optimized copy the clipboard and pinned history no
    /// longer need. Runs when the feature is turned off and from Settings.
    func clearOptimizedCopies(completion: (() -> Void)? = nil) {
        withProtectedPaths { [weak self] protected, _ in
            self?.storeQueue.async {
                let removed = ClipboardOptimizerStore.clear(protected: protected)
                DispatchQueue.main.async {
                    ClipboardHistoryService.shared.restoreOriginals(removed)
                    completion?()
                }
            }
        }
    }

    /// Bytes stored, and how many of them pinned history or the clipboard keep.
    func storedBytes(_ completion: @escaping (_ total: Int64, _ kept: Int64) -> Void) {
        withProtectedPaths { [weak self] protected, _ in
            self?.storeQueue.async {
                let sizes = ClipboardOptimizerStore.totalBytes(protected: protected)
                DispatchQueue.main.async { completion(sizes.all, sizes.protected) }
            }
        }
    }

    private static func scope() -> ClipboardImageOptimizerSupport.Scope {
        .fromDefaults(outputRoot: ClipboardOptimizerStore.rootURL)
    }

    /// Pinned history and whatever file the clipboard points at right now,
    /// which after a relaunch can be a copy this session never made. History
    /// is read on main; the clipboard on the lane.
    private func withProtectedPaths(_ body: @escaping (_ protected: Set<String>, _ recent: Set<String>) -> Void) {
        let history = ClipboardHistoryService.shared.referencedFilePaths
        var protected = history.pinned
        if let lastOutputPath { protected.insert(lastOutputPath) }
        GeneralPasteboardAccess.shared.async(timeout: Self.pollTimeout, { _ -> [String]? in
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                        options: [.urlReadingFileURLsOnly: true]) as? [URL]
            return (urls ?? []).map(\.standardizedFileURL.path)
        }, then: { current in
            // An unreadable clipboard protects everything rather than guess.
            guard let current else { return }
            body(protected.union(current), history.recent)
        })
    }

    private func sweep() {
        withProtectedPaths { [weak self] protected, recent in
            self?.storeQueue.async {
                let removed = ClipboardOptimizerStore.sweep(protected: protected, referenced: recent)
                DispatchQueue.main.async { ClipboardHistoryService.shared.restoreOriginals(removed) }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        fileJob?.cancel(immediately: true)
        fileJob = nil
        cancelPoll()
        updateState(enabled: false)
        encodeInFlight = false
        isRunning = false
    }

    /// Options are read for each new image, so a settings change while
    /// running needs nothing here and never drops the image in flight.
    private func start() {
        guard timer == nil else {
            isRunning = true
            return
        }
        updateState(enabled: true)
        encodeInFlight = false
        hasBaseline = false
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.hasBaseline = false
                self?.baseline()
            }
        // An encode would stall or die across sleep; wake starts from a fresh
        // baseline, so the file is left as it was.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.fileJob?.cancel()
            }
        isRunning = true
        baseline()
        storeReady = false
        storeQueue.async { [weak self] in
            ClipboardOptimizerStore.killOrphanedEncoders()
            ClipboardOptimizerStore.removeIncompleteJobs()
            DispatchQueue.main.async { self?.storeReady = true }
        }
        sweep()
    }

    private func updateState(enabled: Bool) {
        stateLock.lock()
        generation &+= 1
        self.enabled = enabled
        stateLock.unlock()
    }

    private func currentState() -> (generation: Int, enabled: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (generation, enabled)
    }

    /// Whatever sits on the pasteboard now is the user's, never ours to shrink.
    private func baseline() {
        cancelPoll()
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        GeneralPasteboardAccess.shared.async(timeout: Self.pollTimeout, { _ in
            token.isCancelled ? nil : NSPasteboard.general.changeCount
        }, then: { [weak self] changeCount in
            guard let self, self.pollToken === token else { return }
            self.pollToken = nil
            self.pollInFlight = false
            if let changeCount {
                self.lastChangeCount = changeCount
                self.hasBaseline = true
            }
        })
    }

    private func tick() {
        guard isRunning, !pollInFlight, !encodeInFlight, !TransientPaste.shared.isBusy else { return }
        guard hasBaseline else {
            baseline()
            return
        }
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        let since = lastChangeCount
        let includeFiles = Self.scope().readsFiles
        GeneralPasteboardAccess.shared.async(timeout: Self.pollTimeout, { _ in
            token.isCancelled ? nil : Self.readSnapshot(since: since, includeFiles: includeFiles)
        }, then: { [weak self] snapshot in
            guard let self, self.pollToken === token else { return }
            self.pollToken = nil
            self.pollInFlight = false
            guard self.isRunning, let snapshot, snapshot.changeCount != self.lastChangeCount else { return }
            // Anything new on the clipboard ends the file job in flight. The
            // new copy is looked at once that job has stopped, so two
            // encoders never run at once.
            if let job = self.fileJob, job.changeCount != snapshot.changeCount {
                job.cancel()
                if let cancelledAt = job.cancelledAt, Date().timeIntervalSince(cancelledAt) > Self.abandonAfter {
                    self.fileJob = nil
                } else {
                    return
                }
            }
            self.lastChangeCount = snapshot.changeCount
            self.consider(snapshot)
        })
    }

    /// Runs on the pasteboard lane. Reads counts and type names; file URLs
    /// only when files are on and the pasteboard says it carries one.
    private static func readSnapshot(since: Int, includeFiles: Bool) -> PasteboardImageSnapshot? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != since else {
            return PasteboardImageSnapshot(changeCount: changeCount, itemCount: 0, types: [],
                                           fileURLs: [])
        }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        var fileURLs: [URL] = []
        if includeFiles, types.contains(ClipboardImageOptimizerSupport.fileURLType),
           !types.contains(where: ClipboardImageOptimizerSupport.untouchableTypes.contains) {
            fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
        return PasteboardImageSnapshot(changeCount: changeCount,
                                       itemCount: pasteboard.pasteboardItems?.count ?? 0,
                                       types: types, fileURLs: fileURLs)
    }

    private func consider(_ snapshot: PasteboardImageSnapshot) {
        let options = ClipboardImageOptimizerSupport.Options.fromDefaults()
        guard case .eligible(let source) = ClipboardImageOptimizerSupport.eligibility(
            snapshot, lastOwnWrite: lastOwnWrite, scope: Self.scope()) else { return }
        let state = currentState()
        if source.usesOutputFile {
            startFileJob(source, snapshot: snapshot, options: options, generation: state.generation)
            return
        }
        encodeInFlight = true
        switch source {
        case .bitmap(let type):
            GeneralPasteboardAccess.shared.async(timeout: Self.readTimeout, { isExpired -> Data? in
                let pasteboard = NSPasteboard.general
                guard pasteboard.changeCount == snapshot.changeCount, !isExpired() else { return nil }
                return pasteboard.data(forType: NSPasteboard.PasteboardType(type))
            }, then: { [weak self] data in
                guard let self else { return }
                guard let data else {
                    self.finishEncode(generation: state.generation)
                    return
                }
                let sourceType = ClipboardImageOptimizerSupport.pngTypes.contains(type) ? "public.png" : "public.tiff"
                self.encode(data: { data }, sourceType: sourceType, snapshot: snapshot,
                            options: options, generation: state.generation)
            })
        case .file(let url, let uti):
            encode(data: {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                let size = values?.fileSize ?? 0
                guard values?.isRegularFile == true, size > 0, size <= ClipboardImageOptimizerSupport.maxBytes,
                      ClipboardOptimizerFileSupport.isAvailableLocally(url) else { return nil }
                return try? Data(contentsOf: url)
            }, sourceType: uti, snapshot: snapshot, options: options, generation: state.generation)
        case .convertedImage, .video, .pdf:
            break
        }
    }

    // MARK: Copied files that become new files

    private func startFileJob(_ source: ClipboardImageOptimizerSupport.Source,
                              snapshot: PasteboardImageSnapshot,
                              options: ClipboardImageOptimizerSupport.Options,
                              generation: Int) {
        guard storeReady, fileJob == nil, let original = snapshot.fileURLs.first,
              let directory = ClipboardOptimizerStore.makeJobDirectory(source: original) else { return }
        let job = FileJob(changeCount: snapshot.changeCount, generation: generation, source: source,
                          directory: directory)
        fileJob = job
        let video = ClipboardOptimizerFileSupport.VideoOptions.fromDefaults()
        let pdf = ClipboardOptimizerFileSupport.PDFOptions.fromDefaults()
        // A queue per job: one that is abandoned while stuck in a write that
        // cannot be interrupted never holds up the next.
        DispatchQueue(label: "Vorssaint.ClipboardImageOptimizer.file", qos: .utility).async { [weak self] in
            guard let self else { return }
            let isCancelled = { job.isCancelled || self.currentState().generation != generation }
            let outcome: Result<ClipboardFileOptimizer.Result, Error> = Result {
                switch source {
                case .video(let url):
                    return try ClipboardFileOptimizer.optimizeVideo(url, options: video, job: directory,
                                                                    isCancelled: isCancelled,
                                                                    launched: { job.attach($0) })
                case .pdf(let url):
                    return try ClipboardFileOptimizer.optimizePDF(url, options: pdf, job: directory,
                                                                  isCancelled: isCancelled)
                case .convertedImage(let url, _):
                    return try ClipboardFileOptimizer.convertImage(url, options: options, job: directory,
                                                                   isCancelled: isCancelled)
                case .bitmap, .file:
                    throw ClipboardFileOptimizer.Failure.skipped("not a file job")
                }
            }
            if case .failure = outcome { try? FileManager.default.removeItem(at: directory) }
            DispatchQueue.main.async {
                self.finishFileJob(job, outcome: outcome, snapshot: snapshot)
            }
        }
    }

    private func finishFileJob(_ job: FileJob,
                               outcome: Result<ClipboardFileOptimizer.Result, Error>,
                               snapshot: PasteboardImageSnapshot) {
        if fileJob === job { fileJob = nil }
        guard case .success(let result) = outcome else { return }
        let state = currentState()
        guard !job.isCancelled, state.enabled, state.generation == job.generation,
              let original = snapshot.fileURLs.first else {
            try? FileManager.default.removeItem(at: job.directory)
            return
        }
        let source = job.source
        GeneralPasteboardAccess.shared.async({ [weak self] () -> Int? in
            guard let self else { return nil }
            let pasteboard = NSPasteboard.general
            let state = self.currentState()
            guard OptimizationCommit.accepts(generation: job.generation, current: state.generation,
                                             enabled: state.enabled, kindEnabled: Self.scope().allows(source),
                                             pasteboardChangeCount: pasteboard.changeCount,
                                             snapshotChangeCount: snapshot.changeCount) else { return nil }
            pasteboard.clearContents()
            guard pasteboard.writeObjects([result.url as NSURL]) else {
                pasteboard.writeObjects([original as NSURL])
                return nil
            }
            return pasteboard.changeCount
        }, then: { [weak self] newChangeCount in
            guard let self else { return }
            guard let newChangeCount else {
                try? FileManager.default.removeItem(at: job.directory)
                return
            }
            self.lastOwnWrite = newChangeCount
            self.lastChangeCount = max(self.lastChangeCount, newChangeCount)
            self.lastOutputPath = result.url.standardizedFileURL.path
            ClipboardAutoClearService.shared.noteOwnRewrite(from: snapshot.changeCount, to: newChangeCount)
            // History stores standardized paths (/tmp, not /private/tmp).
            ClipboardHistoryService.shared.noteOptimizedRewrite(from: [original.standardizedFileURL.path],
                                                                to: [result.url.standardizedFileURL.path])
            self.sweep()
        })
    }

    private func encode(data load: @escaping () -> Data?,
                        sourceType: String,
                        snapshot: PasteboardImageSnapshot,
                        options: ClipboardImageOptimizerSupport.Options,
                        generation: Int) {
        encodeQueue.async { [weak self] in
            guard let self else { return }
            let isCancelled = { self.currentState().generation != generation }
            let original = isCancelled() ? nil : autoreleasepool { load() }
            let output = original.flatMap {
                ClipboardImageOptimizerEncoding.optimize(data: $0, sourceType: sourceType,
                                                         options: options, isCancelled: isCancelled)
            }
            DispatchQueue.main.async {
                guard original != nil, let output, !isCancelled() else {
                    self.finishEncode(generation: generation)
                    return
                }
                self.commit(output, original: original!, sourceType: sourceType, snapshot: snapshot,
                            generation: generation)
            }
        }
    }

    private func commit(_ output: ClipboardImageOptimizerEncoding.Output,
                        original: Data,
                        sourceType: String,
                        snapshot: PasteboardImageSnapshot,
                        generation: Int) {
        let state = currentState()
        guard state.enabled, state.generation == generation else {
            finishEncode(generation: generation)
            return
        }
        GeneralPasteboardAccess.shared.async({ [weak self] () -> Int? in
            guard let self else { return nil }
            let pasteboard = NSPasteboard.general
            let state = self.currentState()
            guard OptimizationCommit.accepts(generation: generation, current: state.generation,
                                             enabled: state.enabled, kindEnabled: Self.scope().images,
                                             pasteboardChangeCount: pasteboard.changeCount,
                                             snapshotChangeCount: snapshot.changeCount) else { return nil }
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setData(output.data, forType: NSPasteboard.PasteboardType(output.type))
            guard pasteboard.writeObjects([item]) else {
                // Never leave the clipboard empty: put back what was copied.
                if let file = snapshot.fileURLs.first {
                    pasteboard.writeObjects([file as NSURL])
                } else {
                    let restored = NSPasteboardItem()
                    restored.setData(original, forType: NSPasteboard.PasteboardType(sourceType))
                    pasteboard.writeObjects([restored])
                }
                return nil
            }
            return pasteboard.changeCount
        }, then: { [weak self] newChangeCount in
            guard let self else { return }
            self.finishEncode(generation: generation)
            guard let newChangeCount else { return }
            self.lastOwnWrite = newChangeCount
            self.lastChangeCount = max(self.lastChangeCount, newChangeCount)
            // History records the smaller copy as an ordinary change; only
            // auto clear keeps timing from the original copy.
            ClipboardAutoClearService.shared.noteOwnRewrite(from: snapshot.changeCount, to: newChangeCount)
        })
    }

    /// A completion from before a stop/start must not clear the flag of the
    /// encode that the newer generation has in flight.
    private func finishEncode(generation: Int) {
        if currentState().generation == generation { encodeInFlight = false }
    }

    private func cancelPoll() {
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
    }
}
