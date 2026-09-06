// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum SpeedTestTests {
    static func run(expect: (Bool, String) -> Void) {
        let cases: [(name: String, requests: [String])] = [
            ("latency-500", ["latency"]),
            ("latency-non-http", ["latency"]),
            ("download-404", Array(repeating: "latency", count: 5) + ["download"]),
            ("download-after-data-503", Array(repeating: "latency", count: 5) + ["download", "download"]),
            ("upload-503", Array(repeating: "latency", count: 5) + ["download", "upload"]),
            ("success-204", Array(repeating: "latency", count: 5) + ["download", "upload"]),
        ]
        for testCase in cases {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SpeedTestProtocol.self]
            configuration.httpAdditionalHeaders = ["X-Test-Scenario": testCase.name]
            let test = SpeedTest(configuration: configuration, sampleSeconds: 0.1)
            test.start()
            let deadline = Date().addingTimeInterval(3)
            var completed = false
            repeat {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                switch test.phase {
                case .failed, .done: completed = true
                default: break
                }
            } while !completed && Date() < deadline
            expect(completed, "speed test \(testCase.name) reaches a terminal state")

            let succeeded = testCase.name == "success-204"
            if succeeded {
                expect(test.phase == .done && test.latencyMs != nil
                        && (test.downloadMbps ?? 0) > 0 && test.uploadMbps != nil,
                       "successful HTTP responses complete every speed test phase")
            } else {
                if case .failed = test.phase {
                    expect(true, "speed test \(testCase.name) reports a failure")
                } else {
                    expect(false, "speed test \(testCase.name) reports a failure")
                }
                expect(test.uploadMbps == nil,
                       "speed test \(testCase.name) never publishes an upload result after rejection")
                if testCase.name != "upload-503" {
                    expect(test.downloadMbps == nil,
                           "speed test \(testCase.name) never counts an error body as download traffic")
                }
                if testCase.name.hasPrefix("latency-") {
                    expect(test.latencyMs == nil,
                           "speed test \(testCase.name) never measures an invalid latency response")
                }
            }

            // Let the cancelled time box expire: an error must stay terminal.
            let phase = test.phase
            let settled = Date().addingTimeInterval(0.15)
            while Date() < settled {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            expect(test.phase == phase, "speed test \(testCase.name) stays terminal after its time box")
            expect(SpeedTestProtocol.requests(for: testCase.name) == testCase.requests,
                   "speed test \(testCase.name) stops requesting data at the failed phase")
            test.cancel()
        }
    }
}

private final class SpeedTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recordedRequests: [String: [String]] = [:]

    static func requests(for scenario: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests[scenario] ?? []
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
        }
        if rejects || phase != "download" || scenario == "download-after-data-503" {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
