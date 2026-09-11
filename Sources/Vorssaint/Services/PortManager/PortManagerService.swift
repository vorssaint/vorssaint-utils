// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class PortManagerService: ObservableObject {
    static let shared = PortManagerService()
    @Published private(set) var entries: [PortManagerEntry] = []
    @Published var query = ""
    @Published private(set) var isRefreshing = false

    var filteredEntries: [PortManagerEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { "\($0.port) \($0.processName) \($0.pid) \($0.address)".lowercased().contains(q) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.snapshot()
            DispatchQueue.main.async {
                if let result { self.entries = result } 
                self.isRefreshing = false
            }
        }
    }

    func terminate(_ entry: PortManagerEntry, force: Bool) {
        guard let startedAt = entry.startedAt else { return }
        KillProcessService.shared.kill(pid: entry.pid,
                                       name: entry.processName,
                                       startedAt: startedAt,
                                       force: force) { [weak self] in
            self?.refresh()
        }
    }

    private static func snapshot() -> [PortManagerEntry]? {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"])
        // Negative status means Shell.run hit its own timeout — always bail.
        guard result.status >= 0 else { return nil }
        let parsed = PortManagerSupport.parseLsof(result.output).map { entry in
            PortManagerEntry(port: entry.port,
                             protocolName: entry.protocolName,
                             address: entry.address,
                             pid: entry.pid,
                             processName: entry.processName,
                             startedAt: KillProcessService.startTime(for: entry.pid))
        }
        // lsof exits 1 when it prints a warning but still outputs good rows above
        // it; treat that as a valid snapshot. Only return nil when non-zero AND
        // the parse came up empty — that's a genuine failure we should not use to
        // replace good data already on screen.
        if result.status != 0 && parsed.isEmpty { return nil }
        return parsed
    }

}
