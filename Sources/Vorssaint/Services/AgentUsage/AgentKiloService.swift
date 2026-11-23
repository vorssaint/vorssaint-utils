// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Kilo Code's totals for the AI page's Kilo card. Read while the card shows,
/// again only when Kilo's database changed, the period changed or a minute passed.
final class AgentKiloService: ObservableObject {
    static let shared = AgentKiloService()

    @Published private(set) var summary: AgentKiloSummary?

    /// A reading this recent stands while the database has not changed.
    static let freshness: TimeInterval = 60

    private let queue = DispatchQueue(label: "com.vorssaint.kilo-usage", qos: .utility)
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var reading = false
    private var last: (period: AgentPeriod, day: Date, modified: Date?, at: Date)?

    private init() {}

    func refreshIfStale(period: AgentPeriod, now: Date = Date()) {
        guard !reading else { return }
        let modified = AgentKiloReader.modified(home: home)
        let day = Calendar.current.startOfDay(for: now)
        if let last, last.period == period, last.day == day, last.modified == modified,
           now.timeIntervalSince(last.at) < Self.freshness { return }
        reading = true
        let home = home
        let since = AgentKiloReader.start(of: period, now: now)
        queue.async { [weak self] in
            let summary = AgentKiloReader.read(home: home, since: since)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                self.last = (period, day, modified, now)
                if self.summary != summary { self.summary = summary }
            }
        }
    }
}
