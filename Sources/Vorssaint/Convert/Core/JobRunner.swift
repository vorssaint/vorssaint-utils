// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AppKit
import Combine

final class Job: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    @Published var progress: Double = 0
    @Published var status: Status = .waiting
    var outputs: [URL] = []
    var task: Task<Void, Never>?
    /// About how long the work should take, for the estimate shown between real readings.
    var expectedSeconds: TimeInterval = 4
    fileprivate var startedAt: TimeInterval?
    fileprivate var lastReadingAt: TimeInterval?

    enum Status: Equatable {
        case waiting, running, done, cancelled
        case failed(String)

        var isFinished: Bool {
            switch self {
            case .done, .cancelled, .failed: return true
            case .waiting, .running: return false
            }
        }
    }

    init(title: String, detail: String, symbol: String = "arrow.triangle.2.circlepath") {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

/// The conversion queue. Jobs run one at a time; the island shows them. The
/// window, pill and card the original drew are gone: Vorssaint's island is the
/// only surface.
@MainActor
final class JobRunner: ObservableObject {
    static let shared = JobRunner()

    @Published private(set) var jobs: [Job] = []
    private let semaphore = AsyncSemaphore(limit: 1)
    private var jobSubscriptions: [UUID: AnyCancellable] = [:]
    private var reservedDestinations: [UUID: URL] = [:]
    /// Set when a batch has finished, so the island can show its results.
    let finishedBatch = PassthroughSubject<[Job], Never>()

    private var estimateTimer: Timer?

    private init() {}

    var hasWork: Bool { jobs.contains { !$0.status.isFinished } }

    func convert(_ urls: [URL], to target: FileFormat, options: ConvertOptions = ConvertOptions()) {
        DiagnosticLog.log("convert \(urls.map(\.lastPathComponent)) -> \(target.displayName)")
        for url in urls {
            let job = Job(title: "Converting to \(target.displayName)", detail: url.lastPathComponent, symbol: target.category.symbol)
            job.expectedSeconds = JobProgressEstimate.expectedSeconds(
                bytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Double.init) ?? 0,
                category: FileFormat.detect(url)?.category ?? target.category)
            guard let source = FileFormat.detect(url) else {
                enqueue(job) { _ in
                    throw OpenTangerineError.invalidInput("Unsupported file type: \(url.lastPathComponent)")
                }
                continue
            }
            let directory = AppSettings.shared.outputLocation.directory(for: url)
            let reserved = Set(reservedDestinations.values.filter {
                $0.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
            }.map(\.lastPathComponent))
            let destination = ConversionMatrix.outputURL(for: url, target: target, in: directory, existing: reserved)
            reservedDestinations[job.id] = destination
            enqueue(job) { progress in
                let request = ConversionRequest(source: url, sourceFormat: source, target: target, destination: destination, progress: progress, options: options)
                try await Engines.convert(request)
                return [destination]
            }
        }
    }

    func run(title: String, detail: String, symbol: String = "arrow.triangle.2.circlepath",
             work: @escaping (@escaping (Double) -> Void) async throws -> [URL]) {
        enqueue(Job(title: title, detail: detail, symbol: symbol), work: work)
    }

    func enqueue(_ job: Job, work: @escaping (@escaping (Double) -> Void) async throws -> [URL]) {
        // Completed results belong to the previous interaction, not the next batch.
        for old in jobs where old.status.isFinished { jobSubscriptions[old.id] = nil }
        jobs.removeAll { $0.status.isFinished }
        jobs.append(job)
        jobSubscriptions[job.id] = job.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        job.task = Task {
            defer { reservedDestinations[job.id] = nil }
            await semaphore.wait()
            guard !Task.isCancelled else {
                job.status = .cancelled
                await semaphore.signal()
                finishBatchIfDone()
                return
            }
            job.status = .running
            job.startedAt = ProcessInfo.processInfo.systemUptime
            startEstimates()
            let progress: (Double) -> Void = { value in
                Task { @MainActor in
                    guard !job.status.isFinished, value.isFinite else { return }
                    job.lastReadingAt = ProcessInfo.processInfo.systemUptime
                    // A reading never takes the bar back past what was already shown.
                    let reading = min(max(value, 0), 1)
                    if reading > job.progress { job.progress = reading }
                }
            }
            do {
                let outputs = try await work(progress)
                try Task.checkCancellation()
                job.outputs = outputs
                job.progress = 1
                job.status = .done
                if AppSettings.shared.revealInFinder, !outputs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
            } catch is CancellationError {
                job.status = .cancelled
            } catch OpenTangerineError.cancelled {
                job.status = .cancelled
            } catch {
                DiagnosticLog.log("job failed: \(job.detail): \(error)")
                job.status = .failed(error.localizedDescription)
            }
            await semaphore.signal()
            finishBatchIfDone()
        }
    }

    /// Between real readings, and for work that reports none, the bar eases
    /// forward on an estimate from the file's size and kind, so it is never
    /// left sitting at zero. A real reading always wins, and the estimate stops
    /// short of the end, which only the finished work reaches.
    private func startEstimates() {
        guard estimateTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceEstimates() }
        }
        RunLoop.main.add(timer, forMode: .common)
        estimateTimer = timer
    }

    private func advanceEstimates() {
        let now = ProcessInfo.processInfo.systemUptime
        let running = jobs.filter { $0.status == .running }
        guard !running.isEmpty else {
            estimateTimer?.invalidate()
            estimateTimer = nil
            return
        }
        for job in running {
            guard let started = job.startedAt else { continue }
            let quiet = job.lastReadingAt.map { now - $0 } ?? .infinity
            guard quiet > JobProgressEstimate.readingGrace else { continue }
            let estimate = JobProgressEstimate.estimate(elapsed: now - started, expected: job.expectedSeconds)
            if estimate > job.progress + 0.002 { job.progress = estimate }
        }
    }

    private func finishBatchIfDone() {
        guard !jobs.isEmpty, jobs.allSatisfy({ $0.status.isFinished }) else { return }
        ConvertRecents.add(jobs.flatMap(\.outputs))
        finishedBatch.send(jobs)
    }

    func cancel(_ job: Job) {
        job.task?.cancel()
        job.status = .cancelled
        finishBatchIfDone()
    }

    func cancelAll() {
        for job in jobs where !job.status.isFinished { job.task?.cancel() }
        dismissAll()
    }

    func dismiss(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        jobSubscriptions[job.id] = nil
    }

    func dismissAll() {
        jobs.removeAll()
        jobSubscriptions.removeAll()
    }
}

actor AsyncSemaphore {
    private let limit: Int
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func wait() async {
        if count < limit {
            count += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            count = max(0, count - 1)
        }
    }
}

extension JobProgressEstimate {
    /// Bytes per second each kind of work gets through, roughly, on Apple silicon.
    static func expectedSeconds(bytes: Double, category: FormatCategory) -> TimeInterval {
        let rate: Double
        switch category {
        case .image: rate = 25_000_000
        case .audio: rate = 12_000_000
        case .video: rate = 6_000_000
        case .document: rate = 4_000_000
        case .subtitle: rate = 50_000_000
        case .archive: rate = 60_000_000
        }
        return expectedSeconds(bytes: bytes, bytesPerSecond: rate)
    }
}
