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
        "-L", "2",
        "-s", "1",
    ]

    static func currentActivitySamples(timeout: TimeInterval = 5.5) -> [NetworkProcessSample] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = nettopArguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return []
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty,
              let output = String(data: data, encoding: .utf8) else { return [] }
        return parseNettopCSV(output)
    }

    /// Parses `nettop -P -d -x -J bytes_in,bytes_out -L 2`.
    /// Delta mode prints an initial cumulative section and then a delta section;
    /// the last section is the one that represents current activity.
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
