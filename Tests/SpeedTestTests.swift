// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum SpeedTestTests {
    static func run(_ suite: TestSuite) {
        let cases: [(name: String, requests: [String])] = [
            ("latency-500", ["latency"]),
            ("latency-non-http", ["latency"]),
            ("download-404", Array(repeating: "latency", count: 5) + ["download"]),
            ("download-after-data-503", Array(repeating: "latency", count: 5) + ["download", "download"]),
            ("upload-503", Array(repeating: "latency", count: 5) + ["download", "upload"]),
            ("success-204", Array(repeating: "latency", count: 5) + ["download", "upload"]),
        ]
        for testCase in cases {
            let clock = SpeedTestClock()
            let scheduler = SpeedTestTimeBoxScheduler(clock: clock)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SpeedTestProtocol.self]
            configuration.httpAdditionalHeaders = ["X-Test-Scenario": testCase.name]
            let test = SpeedTest(configuration: configuration, sampleSeconds: 0.1,
                                 clock: clock.now, scheduleTimeBox: scheduler.schedule)
            test.start()
            let deadline = Date().addingTimeInterval(3)
            var completed = false
            var firedDownloadTimeBox = false
            repeat {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                if !firedDownloadTimeBox,
                   testCase.name == "upload-503" || testCase.name == "success-204",
                   SpeedTestProtocol.deliveredDownloadData(for: testCase.name) {
                    firedDownloadTimeBox = scheduler.runNext()
                }
                switch test.phase {
                case .failed, .done: completed = true
                default: break
                }
            } while !completed && Date() < deadline
            suite.expect(completed, "speed test \(testCase.name) reaches a terminal state")

            let succeeded = testCase.name == "success-204"
            if succeeded {
                suite.expect(test.phase == .done && test.latencyMs != nil
                        && (test.downloadMbps ?? 0) > 0 && test.uploadMbps != nil,
                       "successful HTTP responses complete every speed test phase")
            } else {
                if case .failed = test.phase {
                    suite.expect(true, "speed test \(testCase.name) reports a failure")
                } else {
                    suite.expect(false, "speed test \(testCase.name) reports a failure")
                }
                suite.expect(test.uploadMbps == nil,
                       "speed test \(testCase.name) never publishes an upload result after rejection")
                if testCase.name != "upload-503" {
                    suite.expect(test.downloadMbps == nil,
                           "speed test \(testCase.name) never counts an error body as download traffic")
                }
                if testCase.name.hasPrefix("latency-") {
                    suite.expect(test.latencyMs == nil,
                           "speed test \(testCase.name) never measures an invalid latency response")
                }
            }

            let phase = test.phase
            let latencyMs = test.latencyMs
            let downloadMbps = test.downloadMbps
            let uploadMbps = test.uploadMbps
            if testCase.name.hasPrefix("latency-") {
                suite.expect(scheduler.count == 0,
                       "speed test \(testCase.name) fails before scheduling a transfer time box")
            } else {
                suite.expect(scheduler.count > 0 && scheduler.allCancelled,
                       "speed test \(testCase.name) cancels every scheduled transfer time box")
            }
            let callbacksCompleted = scheduler.runEveryCallback()
            drainMainQueue()
            suite.expect(callbacksCompleted && test.phase == phase && test.latencyMs == latencyMs
                          && test.downloadMbps == downloadMbps && test.uploadMbps == uploadMbps,
                   "speed test \(testCase.name) stays terminal after stale time-box callbacks")
            suite.expect(SpeedTestProtocol.requests(for: testCase.name) == testCase.requests,
                   "speed test \(testCase.name) stops requesting data at the failed phase")
            test.cancel()
        }
    }

    private static func drainMainQueue() {
        var drained = false
        DispatchQueue.main.async { drained = true }
        while !drained {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

private final class SpeedTestClock {
    private let lock = NSLock()
    private var value: CFAbsoluteTime = 1_000

    func now() -> CFAbsoluteTime {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value += interval }
    }
}

private final class SpeedTestTimeBoxScheduler {
    private struct Callback {
        let queue: OperationQueue
        let delay: TimeInterval
        let action: () -> Void
        var cancelled = false
        var hasRun = false
    }

    private let lock = NSLock()
    private let clock: SpeedTestClock
    private var callbacks: [Callback] = []

    init(clock: SpeedTestClock) {
        self.clock = clock
    }

    var count: Int {
        lock.withLock { callbacks.count }
    }

    var allCancelled: Bool {
        lock.withLock { callbacks.allSatisfy(\.cancelled) }
    }

    func schedule(on queue: OperationQueue, after delay: TimeInterval,
                  action: @escaping () -> Void) -> () -> Void {
        let index = lock.withLock {
            callbacks.append(Callback(queue: queue, delay: delay, action: action))
            return callbacks.index(before: callbacks.endIndex)
        }
        return { [weak self] in
            self?.lock.withLock { self?.callbacks[index].cancelled = true }
        }
    }

    func runNext() -> Bool {
        let callback: Callback? = lock.withLock {
            guard let index = callbacks.firstIndex(where: { !$0.hasRun }) else { return nil }
            callbacks[index].hasRun = true
            return callbacks[index]
        }
        guard let callback else { return false }
        return run(callback)
    }

    func runEveryCallback() -> Bool {
        let pending = lock.withLock { callbacks }
        var completed = true
        for callback in pending {
            completed = run(callback) && completed
        }
        return completed
    }

    private func run(_ callback: Callback) -> Bool {
        clock.advance(by: callback.delay)
        let completed = DispatchSemaphore(value: 0)
        callback.queue.addOperation {
            callback.action()
            completed.signal()
        }
        return completed.wait(timeout: .now() + 1) == .success
    }
}

private final class SpeedTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recordedRequests: [String: [String]] = [:]
    private static var downloadsWithData: Set<String> = []

    static func requests(for scenario: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests[scenario] ?? []
    }

    static func deliveredDownloadData(for scenario: String) -> Bool {
        lock.withLock { downloadsWithData.contains(scenario) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "X-Test-Scenario") ?? ""
        let url = request.url!
        let phase = url.path == "/__up" ? "upload" : url.query == "bytes=0" ? "latency" : "download"
        Self.lock.lock()
        Self.recordedRequests[scenario, default: []].append(phase)
        let downloadCount = Self.recordedRequests[scenario, default: []].filter { $0 == "download" }.count
        Self.lock.unlock()

        if scenario == "latency-non-http" {
            client?.urlProtocol(self, didReceive: URLResponse(url: url, mimeType: nil,
                                                            expectedContentLength: 0, textEncodingName: nil),
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let rejects = scenario.hasPrefix(phase + "-")
            && (scenario != "download-after-data-503" || downloadCount > 1)
        let status = rejects ? (Int(scenario.split(separator: "-").last!) ?? 500)
            : (phase == "download" ? 200 : 204)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if rejects || phase == "download" {
            client?.urlProtocol(self, didLoad: Data(repeating: 42, count: 1_024))
            if phase == "download" {
                _ = Self.lock.withLock { Self.downloadsWithData.insert(scenario) }
            }
        }
        if rejects || phase != "download" || scenario == "download-after-data-503" {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
