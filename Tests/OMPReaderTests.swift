// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The OMP reader, pinned by behaviour: a reply that carries usage becomes
/// one record, a line that carries none becomes nothing, and a line of a
/// kind the reader does not know is ignored rather than treated as a
/// failure. The log lines are built here, so the tests need no OMP install.
enum OMPReaderTests {
    static func run(_ suite: TestSuite) {
        runUsage(suite)
        runWithoutUsage(suite)
        runUnknownKind(suite)
        runZeroCost(suite)
    }

    /// A log line as OMP writes it: a `message` object with a usage block
    /// beside the model that answered.
    private static func line(id: String = "m1",
                             model: String = "muse-spark-1.3",
                             role: String = "assistant",
                             usage: String? = nil,
                             type: String = "message") -> Data {
        let block = usage ?? """
        {"input":120,"output":45,"cacheRead":30,"cacheWrite":10,"totalTokens":205,\
        "cost":{"input":0.01,"output":0.02,"cacheRead":0.001,"cacheWrite":0.002,"total":0.033}}
        """
        return """
        {"type":"\(type)","id":"\(id)","timestamp":"2026-09-12T14:14:56.937Z",\
        "sessionId":"s-1","cwd":"/tmp/project",\
        "message":{"role":"\(role)","model":"\(model)","timestamp":"2026-09-12T14:14:56.937Z",\
        "usage":\(block)}}
        """.data(using: .utf8)!
    }

    private static func records(_ entries: [AgentLogEntry]) -> [AgentUsageRecord] {
        entries.compactMap { entry in
            if case .usage(_, let record, _) = entry { return record }
            return nil
        }
    }

    private static func runUsage(_ suite: TestSuite) {
        var state = AgentLogState()
        let entries = OMPReader().parse(line(), state: &state, now: Date())
        let records = records(entries)
        suite.expect(records.count == 1,
                     "a reply that carries usage becomes exactly one record")
        guard let record = records.first else { return }
        suite.expect(record.provider == .omp,
                     "the record belongs to OMP")
        suite.expect(record.tokens.input == 120 && record.tokens.output == 45
                     && record.tokens.cacheRead == 30 && record.tokens.cacheWrite == 10,
                     "the tokens come out as OMP counted them, cache reads and writes included")
        suite.expect(record.tokens.total == 205,
                     "the total is the sum of the four counts OMP reported")
        suite.expect(record.model == "muse-spark-1.3",
                     "the model is the one that answered")
        suite.expect(record.session == "s-1",
                     "the session is the one the line names")
        suite.expect(record.project == "project",
                     "the project comes from the working directory the session was started in")
        suite.expect(record.cost != nil,
                     "a reply that OMP charged for has a cost")
    }

    private static func runWithoutUsage(_ suite: TestSuite) {
        var state = AgentLogState()
        let entries = OMPReader().parse(line(usage: "null"), state: &state, now: Date())
        suite.expect(entries.isEmpty,
                     "a reply that carries no usage becomes no record")
    }

    private static func runUnknownKind(_ suite: TestSuite) {
        var state = AgentLogState()
        let entries = OMPReader().parse(line(type: "thinking_level_change"), state: &state, now: Date())
        suite.expect(entries.isEmpty,
                     "a line of a kind the reader does not know is ignored rather than failing")
    }

    /// A free model records a cost of zero. The reply still happened, so it
    /// is still a record, and the zero stays an estimate rather than a
    /// reported cost.
    private static func runZeroCost(_ suite: TestSuite) {
        var state = AgentLogState()
        let free = """
        {"input":10,"output":5,"cacheRead":0,"cacheWrite":0,"totalTokens":15,\
        "cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}
        """
        let entries = OMPReader().parse(line(usage: free), state: &state, now: Date())
        let records = records(entries)
        suite.expect(records.count == 1,
                     "a reply from a free model is still a record")
        guard let record = records.first else { return }
        suite.expect(record.tokens.total == 15,
                     "the tokens of a free reply are still counted")
        suite.expect(record.reportedCost == false,
                     "a recorded zero stays an estimate, so a price learned later still applies")
    }
}
