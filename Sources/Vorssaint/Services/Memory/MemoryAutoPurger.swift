// Watches memory pressure and purges automatically when thresholds are hit.

import Combine
import Foundation

@MainActor
final class MemoryAutoPurger: ObservableObject {
    static let shared = MemoryAutoPurger()

    @Published private(set) var lastAutoPurgeAt: Date?
    @Published private(set) var isRunning = false

    private var cancellable: AnyCancellable?
    private let cooldown: TimeInterval = 300

    private init() {}

    func start() {
        guard cancellable == nil else { return }
        SystemMonitor.shared.setMenuBarActive(true)
        cancellable = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.evaluate(snapshot)
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.autoPurgeEnabled) else { return }
        guard !isRunning else { return }
        if let last = lastAutoPurgeAt, Date().timeIntervalSince(last) < cooldown { return }

        let threshold = UserDefaults.standard.string(forKey: DefaultsKey.autoPurgeThreshold) ?? "critical"
        let shouldPurge: Bool
        switch threshold {
        case "warning":
            shouldPurge = snapshot.memoryPressure == .warning || snapshot.memoryPressure == .critical
        default:
            shouldPurge = snapshot.memoryPressure == .critical
        }
        guard shouldPurge else { return }

        isRunning = true
        MemoryPurgeService.purge(mode: .standard) { [weak self] result in
            guard let self else { return }
            self.isRunning = false
            self.lastAutoPurgeAt = Date()
            SystemMonitor.shared.refreshNow()
            if UserDefaults.standard.bool(forKey: DefaultsKey.autoPurgeNotify) {
                Notifier.post(title: "MemoryKill auto-purged",
                              body: result.message)
            }
        }
    }
}