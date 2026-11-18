// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PiReader: AgentHarnessReader {
    var provider: AgentProvider = .pi

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        AgentLogParser.parsePi(line, state: &state, now: now, provider: provider)
    }
}
