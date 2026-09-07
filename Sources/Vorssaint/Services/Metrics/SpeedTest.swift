// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// A user-triggered internet speed test: latency, then download, then upload,
/// using Cloudflare's public speed endpoints (the same backend speed.cloudflare.com
/// uses). Time-boxed so it stays bounded on any connection. No third-party
/// framework; no user data ever leaves the machine (the upload body is zeros).
///
/// All mutable state is touched only on the session's serial delegate queue;
/// published values are pushed to the main thread.
final class SpeedTest: NSObject, ObservableObject {
    static let shared = SpeedTest()

    enum Phase: Equatable {
        case idle, latency, download, upload, done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latencyMs: Double?
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?

    var isRunning: Bool {
        switch phase { case .latency, .download, .upload: return true; default: return false }
    }

    private enum Kind { case none, download, upload }

    private let host = "https://speed.cloudflare.com"
    private let sampleSeconds: TimeInterval
    // Cloudflare's __down caps the size just under 100 MB (100 MB+ returns ~nothing),
    // so request under that and loop chunks back-to-back until the time box — that
    // keeps a fast link's pipe full for a full measurement window.
    private let downloadBytes = 90_000_000
    private let uploadBytes = 100_000_000

    private let queue = OperationQueue()
    private var session: URLSession!
    private var task: URLSessionTask?
    private var kind: Kind = .none           // touched only on `queue`
    private var transferred: Int64 = 0       // touched only on `queue`
    private var startedAt: CFAbsoluteTime = 0
    private var finished = false
    private var generation = 0
    private var stopWork: DispatchWorkItem?

    init(configuration: URLSessionConfiguration = .ephemeral, sampleSeconds: TimeInterval = 5) {
        self.sampleSeconds = sampleSeconds
        super.init()
        queue.maxConcurrentOperationCount = 1
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func start() {
        guard !isRunning else { return }
        latencyMs = nil; downloadMbps = nil; uploadMbps = nil
        setPhase(.latency)
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.measureLatency(remaining: 5, best: .greatestFiniteMagnitude)
        }
    }

    func cancel() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.stopWork?.cancel(); self.stopWork = nil
            self.task?.cancel(); self.task = nil
            self.kind = .none
            self.finished = true
            self.setPhase(.idle)   // inside the op, so it orders after any pending transition
        }
    }

    private func setPhase(_ phase: Phase) {
        DispatchQueue.main.async { self.phase = phase }
    }

    // MARK: - Latency (completion-handler tasks bypass the byte-counting delegate)

    private func measureLatency(remaining: Int, best: Double) {
        guard remaining > 0 else {
            let value = best == .greatestFiniteMagnitude ? nil : best
            DispatchQueue.main.async { self.latencyMs = value }
            startTransfer(.download)
            return
        }
        let url = URL(string: "\(host)/__down?bytes=0")!
        let started = CFAbsoluteTimeGetCurrent()
        let generation = self.generation
        task = session.dataTask(with: url) { [weak self] _, response, error in
            guard let self else { return }
            let rtt = (CFAbsoluteTimeGetCurrent() - started) * 1000
            // Continue on the delegate queue so the transfer phase's `kind` is set
            // there too — otherwise the byte-counting delegate could miss it.
            self.queue.addOperation {
                guard self.generation == generation else { return }
                guard error == nil, Self.isSuccessful(response) else {
                    self.fail(error ?? URLError(.badServerResponse))
                    return
                }
                self.measureLatency(remaining: remaining - 1, best: min(best, rtt))
            }
        }
        task?.resume()
    }

    // MARK: - Download / upload (delegate tasks), time-boxed

    private func startTransfer(_ transfer: Kind) {
        generation += 1
        kind = transfer
        transferred = 0
        finished = false
        setPhase(transfer == .download ? .download : .upload)
        startedAt = CFAbsoluteTimeGetCurrent()

        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            self?.queue.addOperation {
                guard let self, self.generation == generation else { return }
                self.finishTransfer(timedOut: true)
            }
        }
        stopWork?.cancel()   // defensive: never leave a previous time box armed
        stopWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + sampleSeconds, execute: work)
        beginChunk()
    }

    /// Starts one transfer. Download loops these (each capped under Cloudflare's
    /// limit) until the time box; upload is a single body.
    private func beginChunk() {
        guard !finished else { return }
        let task: URLSessionTask
        if kind == .download {
            task = session.dataTask(with: URL(string: "\(host)/__down?bytes=\(downloadBytes)")!)
        } else {
            var request = URLRequest(url: URL(string: "\(host)/__up")!)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            task = session.uploadTask(with: request, from: Data(count: uploadBytes))
        }
        self.task = task
        task.resume()
    }

    private func finishTransfer(timedOut: Bool) {
        guard !finished else { return }
        finished = true
        stopWork?.cancel(); stopWork = nil

        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        let bytes = transferred
        if timedOut { task?.cancel() }
        task = nil
        let finishedKind = kind
        kind = .none

        let mbps = elapsed > 0 ? max(0, Double(bytes) * 8 / elapsed / 1_000_000) : 0
        DispatchQueue.main.async {
            if finishedKind == .download { self.downloadMbps = mbps } else { self.uploadMbps = mbps }
        }

        if finishedKind == .download {
            startTransfer(.upload)
        } else {
            setPhase(.done)
        }
    }

    private static func isSuccessful(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse else { return false }
        return (200...299).contains(response.statusCode)
    }

    private func fail(_ error: Error) {
        generation += 1
        finished = true
        stopWork?.cancel(); stopWork = nil
        task?.cancel(); task = nil
        kind = .none
        setPhase(.failed(error.localizedDescription))
    }
}

extension SpeedTest: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === task, kind != .none, !finished else {
            completionHandler(.cancel)
            return
        }
        guard Self.isSuccessful(response) else {
            fail(URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if dataTask === task, kind == .download { transferred += Int64(data.count) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        if task === self.task, kind == .upload { transferred = totalBytesSent }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Ignore a stale completion from a task we already moved past (e.g. the
        // download chunk the time box just cancelled, arriving after upload began).
        guard task === self.task, kind != .none else { return }
        if let error = error as NSError?, error.code != NSURLErrorCancelled, transferred == 0 {
            fail(error)
            return
        }
        if kind == .download, !finished {
            beginChunk()   // keep the pipe full until the time box
        } else {
            finishTransfer(timedOut: false)
        }
    }
}
