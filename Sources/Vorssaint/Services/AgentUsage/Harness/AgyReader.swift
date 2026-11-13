// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Google Antigravity (agy) session transcripts.
/// Each conversation stores its transcript at:
/// brain/<conversation-id>/.system_generated/logs/transcript.jsonl
struct AgyReader: AgentHarnessReader {
    var provider: AgentProvider { .agy }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        AgentLogParser.parseAntigravity(line, state: &state, now: now)
    }
}
