// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

struct NetworkProcessSample: Equatable {
    let pid: pid_t
    let name: String
    let bytesIn: Double
    let bytesOut: Double
}

enum NetworkProcessSupport {
    static let nettopArguments = [
        "-P", "-d", "-x",
        "-J", "bytes_in,bytes_out",
        "-L", "1",
        "-s", "1",
    ]
    static let externalNettopArguments = [
        "-P", "-d", "-x",
        "-t", "external",
        "-J", "bytes_in,bytes_out",
        "-L", "1",
        "-s", "1",
    ]

    static func currentActivitySamples(timeout: TimeInterval = 5.5) -> [NetworkProcessSample] {
        currentActivitySamples(arguments: nettopArguments, timeout: timeout) ?? []
    }

    /// Uses socket-flow counters instead of interface counters. This stays idle
    /// unless NetworkSampler detects that macOS stopped reporting inbound bytes.
    static func currentExternalActivitySamples(timeout: TimeInterval = 1) -> [NetworkProcessSample]? {
        currentActivitySamples(arguments: externalNettopArguments, timeout: timeout)
    }

    private static func currentActivitySamples(arguments: [String],
                                               timeout: TimeInterval) -> [NetworkProcessSample]? {
        let result = BoundedProcessRunner.run("/usr/bin/nettop", arguments,
                                              timeout: timeout,
                                              maxOutputBytes: 4 * 1024 * 1024)
        guard !result.timedOut, result.status == 0, !result.output.isEmpty else { return nil }
        let output = String(decoding: result.output, as: UTF8.self)
        return parseNettopCSV(output)
    }

    /// Parses CSV output from nettop logging mode. The last section is returned,
    /// whether the command produced one cumulative section or multiple sections.
    static func parseNettopCSV(_ output: String) -> [NetworkProcessSample] {
        var currentSection: [NetworkProcessSample] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let columns = csvColumns(in: String(rawLine))
            guard !columns.isEmpty else { continue }

            if columns[0] == "time" {
                currentSection = []
                continue
            }

            if let sample = sample(fromCSVColumns: columns) {
                currentSection.append(sample)
            }
        }

        return currentSection
    }

    static func sample(fromCSVLine line: String) -> NetworkProcessSample? {
        sample(fromCSVColumns: csvColumns(in: line))
    }

    static func csvColumns(in line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func sample(fromCSVColumns columns: [String]) -> NetworkProcessSample? {
        guard columns.count >= 4,
              columns[0] != "time",
              let process = processNameAndPID(from: columns[1]) else { return nil }
        let bytesIn = Double(columns[2]) ?? 0
        let bytesOut = Double(columns[3]) ?? 0
        guard bytesIn > 0 || bytesOut > 0 else { return nil }
        return NetworkProcessSample(pid: process.pid,
                                    name: process.name,
                                    bytesIn: bytesIn,
                                    bytesOut: bytesOut)
    }

    private static func processNameAndPID(from raw: String) -> (name: String, pid: pid_t)? {
        guard let dot = raw.lastIndex(of: ".") else { return nil }
        let namePart = raw[..<dot]
        let pidPart = raw[raw.index(after: dot)...]
        guard let pid = pid_t(String(pidPart)) else { return nil }
        let name = String(namePart).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? "pid \(pid)" : name, pid)
    }
}

enum NetworkProcessSamplingPolicy {
    static let leaseDuration: TimeInterval = 12
    static let stopGrace: TimeInterval = 4
    static let sampleInterval: TimeInterval = 5
    static let maxDeltaGap: TimeInterval = 30

    static func renewedLease(now: TimeInterval) -> TimeInterval {
        now + leaseDuration
    }

    static func shortenedLease(currentExpiresAt: TimeInterval,
                               now: TimeInterval) -> TimeInterval {
        min(currentExpiresAt, now + stopGrace)
    }

    static func leaseIsActive(expiresAt: TimeInterval,
                              now: TimeInterval) -> Bool {
        expiresAt > now
    }
}

struct NetworkProcessDeltaTracker {
    private var previousAt: TimeInterval?
    private var previousByPID: [pid_t: NetworkProcessSample] = [:]
    private let maxGap: TimeInterval

    init(maxGap: TimeInterval = NetworkProcessSamplingPolicy.maxDeltaGap) {
        self.maxGap = maxGap
    }

    /// Whether the next `rates(from:now:)` call can produce deltas, or will
    /// only prime the baseline and return nothing.
    func hasBaseline(now: TimeInterval) -> Bool {
        guard let previousAt else { return false }
        return now > previousAt && now - previousAt <= maxGap
    }

    mutating func rates(from samples: [NetworkProcessSample],
                        now: TimeInterval) -> [NetworkProcessSample] {
        defer {
            previousAt = now
            previousByPID = Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
        }

        guard let previousAt,
              now > previousAt,
              now - previousAt <= maxGap
        else { return [] }

        let elapsed = now - previousAt
        return samples.compactMap { sample in
            guard let previous = previousByPID[sample.pid] else { return nil }
            let bytesIn = sample.bytesIn >= previous.bytesIn
                ? (sample.bytesIn - previous.bytesIn) / elapsed
                : 0
            let bytesOut = sample.bytesOut >= previous.bytesOut
                ? (sample.bytesOut - previous.bytesOut) / elapsed
                : 0
            guard bytesIn > 0 || bytesOut > 0 else { return nil }
            return NetworkProcessSample(pid: sample.pid,
                                        name: sample.name,
                                        bytesIn: bytesIn,
                                        bytesOut: bytesOut)
        }
    }

    mutating func reset() {
        previousAt = nil
        previousByPID = [:]
    }
}

struct NetworkProcessDeltaStreamParser {
    private var hasOpenSection = false
    private var didSkipInitialCumulativeSection = false
    private var currentSection: [NetworkProcessSample] = []

    mutating func consumeCSVLine(_ line: String) -> [NetworkProcessSample]? {
        let columns = NetworkProcessSupport.csvColumns(in: line)
        guard !columns.isEmpty else { return nil }

        if columns[0] == "time" {
            return finishSection()
        }

        guard hasOpenSection else { return nil }
        if let sample = NetworkProcessSupport.sample(fromCSVColumns: columns) {
            currentSection.append(sample)
        }
        return nil
    }

    mutating func reset() {
        hasOpenSection = false
        didSkipInitialCumulativeSection = false
        currentSection = []
    }

    private mutating func finishSection() -> [NetworkProcessSample]? {
        defer { currentSection.removeAll() }
        guard hasOpenSection else {
            hasOpenSection = true
            return nil
        }
        guard didSkipInitialCumulativeSection else {
            didSkipInitialCumulativeSection = true
            return nil
        }
        return currentSection
    }
}
