// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Public reset announcements only; never receives quota or account data.
final class AgentCodexResetForecastSource: ObservableObject {
    typealias Loader = (@escaping (Data?) -> Void) -> (() -> Void)
    static let shared = AgentCodexResetForecastSource()
    @Published private(set) var forecast: AgentCodexResetForecast?
    private let loader: Loader
    private let clock: () -> Date
    private var attempted = Date.distantPast
    private var request: UUID?
    private var cancellation: (() -> Void)?

    init(loader: @escaping Loader = AgentCodexResetForecastSource.download,
         clock: @escaping () -> Date = Date.init) {
        self.loader = loader
        self.clock = clock
    }

    /// Called only for a visible Codex weekly card. UI ticks may check the
    /// cadence, but success and failure both wait six hours before retrying.
    func synchronize(enabled: Bool) {
        guard enabled else { cancel(); return }
        guard request == nil, clock().timeIntervalSince(attempted) >= 6 * 3600 else { return }
        attempted = clock()
        let id = UUID()
        request = id
        cancellation = loader { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.request == id else { return }
                self.request = nil
                self.cancellation = nil
                if let data, let value = AgentCodexResetForecast.decode(data, fetchedAt: self.clock()) {
                    self.forecast = value
                }
            }
        }
    }

    func cancel() {
        guard request != nil else { return }
        request = nil
        cancellation?()
        cancellation = nil
        attempted = .distantPast
    }

    private static func download(_ completion: @escaping (Data?) -> Void) -> (() -> Void) {
        let task = AgentDownload.start(AgentCodexResetForecast.endpoint,
                                       limit: AgentCodexResetForecast.maximumSize,
                                       userAgent: "Vorssaint/\(AppInfo.version) (+https://github.com/vorssaint/vorssaint-utils)",
                                       completion: completion)
        return { task.cancel() }
    }
}
