// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentAgyConversationReaderTests {
    static func run(_ suite: TestSuite) {
        testVarintDecoding(suite)
        testProtobufFieldExtraction(suite)
        testModelNameMapping(suite)
        testMalformedProtobuf(suite)
        testProjectInference(suite)
        testApprovalTransitions(suite)
        testAgyTurnSync(suite)
    }

    private static func testVarintDecoding(_ suite: TestSuite) {
        // Single byte varints
        var idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0x00], at: &idx) == 0 && idx == 1,
                     "varint 0 decodes correctly")

        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0x01], at: &idx) == 1 && idx == 1,
                     "varint 1 decodes correctly")

        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0x7F], at: &idx) == 127 && idx == 1,
                     "varint 127 decodes correctly")

        // Two byte varints: 128 -> [0x80, 0x01], 300 -> [0xAC, 0x02], 1318 -> [0xA6, 0x0A]
        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0x80, 0x01], at: &idx) == 128 && idx == 2,
                     "varint 128 decodes correctly")

        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0xAC, 0x02], at: &idx) == 300 && idx == 2,
                     "varint 300 decodes correctly")

        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0xA6, 0x0A], at: &idx) == 1318 && idx == 2,
                     "varint 1318 decodes correctly")

        // Three byte varint: 23630 -> [0xCE, 0xB8, 0x01]
        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0xCE, 0xB8, 0x01], at: &idx) == 23630 && idx == 3,
                     "varint 23630 decodes correctly")

        // Truncated varint
        idx = 0
        suite.expect(AgentAgyConversationReader.decodeVarint([0x80], at: &idx) == nil,
                     "truncated varint returns nil")
    }

    private static func testProtobufFieldExtraction(_ suite: TestSuite) {
        // Calibrated synthetic protobuf payload:
        // message {
        //   1: message {
        //     3: 1318 (model)
        //     4: message {
        //       2: 100 (fresh input)
        //       3: 50 (output)
        //       5: 200 (cached read)
        //       9: 30 (thinking)
        //     }
        //   }
        // }
        let payload: [UInt8] = [10, 14, 24, 166, 10, 34, 9, 16, 100, 24, 50, 40, 200, 1, 72, 30]

        var fields: [String: UInt64] = [:]
        let success = AgentAgyConversationReader.parseFields(payload, out: &fields)
        suite.expect(success, "parsing valid protobuf returns true")
        suite.expect(fields[".1.3"] == 1318, "model code 1318 at .1.3")
        suite.expect(fields[".1.4.2"] == 100, "fresh input 100 at .1.4.2")
        suite.expect(fields[".1.4.3"] == 50, "output tokens 50 at .1.4.3")
        suite.expect(fields[".1.4.5"] == 200, "cache-read tokens 200 at .1.4.5")
        suite.expect(fields[".1.4.9"] == 30, "thinking tokens 30 at .1.4.9")
    }

    private static func testModelNameMapping(_ suite: TestSuite) {
        suite.expect(AgentAgyConversationReader.modelName(for: 326) == "gemini-3.8-flash",
                     "code 326 maps to gemini-3.8-flash")
        suite.expect(AgentAgyConversationReader.modelName(for: 1298) == "gemini-3.7-flash-high",
                     "code 1298 maps to gemini-3.7-flash-high")
        suite.expect(AgentAgyConversationReader.modelName(for: 1318) == "gemini-3.8-flash-high",
                     "code 1318 maps to gemini-3.8-flash-high")
        suite.expect(AgentAgyConversationReader.modelName(for: 1319) == "gemini-3.8-flash-medium",
                     "code 1319 maps to gemini-3.8-flash-medium")
        suite.expect(AgentAgyConversationReader.modelName(for: 1320) == "gemini-3.8-flash-low",
                     "code 1320 maps to gemini-3.8-flash-low")
        suite.expect(AgentAgyConversationReader.modelName(for: 1322) == "gemini-3.8-flash",
                     "code 1322 maps to gemini-3.8-flash")
        suite.expect(AgentAgyConversationReader.modelName(for: 1404) == "claude-sonnet-5-5",
                     "code 1404 maps to claude-sonnet-5-5")
        suite.expect(AgentAgyConversationReader.modelName(for: 1417) == "gemini-4-argon-high",
                     "code 1417 maps to gemini-4-argon-high")
        suite.expect(AgentAgyConversationReader.modelName(for: 1419) == "gemini-4-argon-low",
                     "code 1419 maps to gemini-4-argon-low")
        suite.expect(AgentAgyConversationReader.modelName(for: 9999) == "gemini-unknown-9999",
                     "unknown code 9999 maps to gemini-unknown-9999")
    }

    private static func testMalformedProtobuf(_ suite: TestSuite) {
        // Truncated length-delimited field
        var fields: [String: UInt64] = [:]
        let truncated: [UInt8] = [10, 14, 24]
        suite.expect(!AgentAgyConversationReader.parseFields(truncated, out: &fields),
                     "truncated protobuf fails gracefully without crashing")

        // Invalid field number 0
        fields = [:]
        let invalidField: [UInt8] = [0x00, 0x01]
        suite.expect(!AgentAgyConversationReader.parseFields(invalidField, out: &fields),
                     "field number 0 fails gracefully")

        // Unsupported wire type (7)
        fields = [:]
        let invalidWireType: [UInt8] = [0x0F, 0x01]
        suite.expect(!AgentAgyConversationReader.parseFields(invalidWireType, out: &fields),
                     "invalid wire type fails gracefully")

        // Empty bytes
        fields = [:]
        suite.expect(AgentAgyConversationReader.parseFields([], out: &fields),
                     "empty bytes parses to empty map")
        suite.expect(fields.isEmpty, "empty bytes has no fields")
    }

    private static func testProjectInference(_ suite: TestSuite) {
        // Global/system config paths should be ignored
        suite.expect(AgentLogParser.inferProject(fromPath: "~/.ai/directives/planner-seat-directive.md") == nil,
                     "~/.ai/directives is ignored")
        suite.expect(AgentLogParser.inferProject(fromPath: "/Users/alice/.ai/directives/rule.md") == nil,
                     "/Users/alice/.ai/directives is ignored")
        suite.expect(AgentLogParser.inferProject(fromPath: "~/.gemini/antigravity/brain/session/transcript.jsonl") == nil,
                     "~/.gemini/... is ignored")
        suite.expect(AgentLogParser.inferProject(fromPath: "/tmp/scratch.py") == nil,
                     "/tmp/... is ignored")
        suite.expect(AgentLogParser.inferProject(fromPath: "/private/tmp/run.sh") == nil,
                     "/private/tmp/... is ignored")
        suite.expect(AgentLogParser.inferProject(fromPath: "~/.claude/settings.json") == nil,
                     "~/.claude/... is ignored")
        suite.expect(AgentLogParser.inferProject(fromPath: "/Library/Application Support/app/config.json") == nil,
                     "/Library/... is ignored")

        // Arbitrary paths without .git / Package.swift / _ai / root folder should not be inferred
        suite.expect(AgentLogParser.inferProject(fromPath: "/some/arbitrary/nested/path/file.txt") == nil,
                     "arbitrary parent path is not inferred as a project")

        // Recognized root folders
        suite.expect(AgentLogParser.inferProject(fromPath: "/Users/alice/Developer/Repositories/vorssaint-utils/Sources/main.swift") == "vorssaint-utils",
                     "recognized Repositories root folder infers project")
        suite.expect(AgentLogParser.inferProject(fromPath: "/Users/alice/Projects/my-app/Package.swift") == "my-app",
                     "recognized Projects root folder infers project")
    }

    private static func testApprovalTransitions(_ suite: TestSuite) {
        let store = AgentUsageStore()
        store.reportsTransitions = false
        let pastDate = Date().addingTimeInterval(-3600)
        let events = store.apply([.turnNeedsApproval(pastDate)], file: "/path/to/log.jsonl",
                                 provider: .agy, tracksTurns: true, modified: pastDate)
        suite.expect(events.isEmpty,
                     "turnNeedsApproval produces no events when reportsTransitions is false")

        store.reportsTransitions = true
        let liveEvents = store.apply([.turnNeedsApproval(Date())], file: "/path/to/live.jsonl",
                                     provider: .agy, tracksTurns: true, modified: Date())
        suite.expect(liveEvents.count == 1,
                     "turnNeedsApproval produces event when reportsTransitions is true")
        if case .needsApproval(let provider, _) = liveEvents.first {
            suite.expect(provider == .agy, "event provider matches")
        } else {
            suite.expect(false, "expected needsApproval event")
        }
    }

    private static func testAgyTurnSync(_ suite: TestSuite) {
        let store = AgentUsageStore()
        let session = "test-session-123"
        let logPath = "/Users/alice/.gemini/antigravity/brain/\(session)/transcript.jsonl"
        let now = Date()

        // Turn begins with a speculative project name "directives"
        store.apply([.turnBegan(now), .turnContext(model: "gemini-3.8-flash", project: "directives")],
                    file: logPath, provider: .agy, tracksTurns: true, modified: now)
        suite.expect(store.live.first?.project == "directives",
                     "turn initialized with speculative project")

        // Authoritative project arrives from database metadata
        store.noteAgySession(session, project: "vorssaint-utils")
        suite.expect(store.live.first?.project == "vorssaint-utils",
                     "authoritative project overwrites speculative inferred project")
    }
}
