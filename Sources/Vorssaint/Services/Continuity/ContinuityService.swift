// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import Combine

@MainActor final class ContinuityService: ObservableObject {
    static let shared = ContinuityService()
    let workflow: ContinuityWorkflow
    @Published private(set) var hotspots: [String] = []
    @Published private(set) var discovering = false
    @Published private(set) var discoveryFailure: ContinuityFailure?
    private var discoveryTask: Task<Void, Never>?
    private var operationID = UUID()
    private var task: Task<Void, Never>?
    private var sessionObservation: AnyCancellable?
    private var lockObserver: NSObjectProtocol?
    private var preferencesObservation: AnyCancellable?

    private init() {
        workflow = ContinuityWorkflow(hooks: .init(
            isAvailable: { AppFeature.keepAwake.isAvailable && KeepAwakeManager.shared.isActive },
            connect: { name in
                do { try await ContinuityHotspotConnector().connect(named: name) }
                catch let error as ContinuityHotspotError {
                    switch error {
                    case .permission: throw ContinuityFailure.permission
                    case .unavailable: throw ContinuityFailure.unavailable
                    case .connectionFailed: throw ContinuityFailure.connection
                    }
                }
            },
            quitApps: { ids in
                let selected = Set(Defaults.sanitizedBundleIdentifierList(ids))
                let apps = NSWorkspace.shared.runningApplications.filter {
                    guard let id = $0.bundleIdentifier else { return false }
                    return selected.contains(id) && Self.canQuit(id)
                        && $0.activationPolicy == .regular
                }
                for app in apps {
                    try Task.checkCancellation()
                    if !app.isTerminated && !app.terminate() { return false }
                }
                // A save sheet is a refusal to finish, never a reason to force quit.
                for _ in 0..<100 {
                    try Task.checkCancellation()
                    if apps.allSatisfy(\.isTerminated) { return true }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                return apps.allSatisfy(\.isTerminated)
            },
            wait: { try await Task.sleep(nanoseconds: $0 * 1_000_000_000) },
            dim: { KeepAwakeManager.shared.dimForContinuity() },
            restore: { KeepAwakeManager.shared.restoreContinuityBrightness() },
            prepareSession: {
                let minutes = UserDefaults.standard.integer(forKey: DefaultsKey.continuityDuration)
                KeepAwakeManager.shared.activate(minutes: Defaults.sanitizedDefaultDuration(minutes))
            }
        ))
        sessionObservation = KeepAwakeManager.shared.$isActive.sink { [weak self] active in
            if !active { self?.cancel() }
        }
        preferencesObservation = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                if !AppFeature.keepAwake.isAvailable { self?.cancel() }
            }
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }

    static func canQuit(_ id: String) -> Bool {
        ![Bundle.main.bundleIdentifier ?? "", "com.apple.finder", "com.apple.systempreferences",
          "com.apple.loginwindow"].contains(id)
    }

    func discover() {
        guard AppFeature.keepAwake.isAvailable, !discovering, !workflow.busy else { return }
        discovering = true
        discoveryFailure = nil
        discoveryTask = Task {
            defer { discovering = false }
            do {
                hotspots = try await ContinuityHotspotConnector().discover()
                try Task.checkCancellation()
                if hotspots.isEmpty { discoveryFailure = .unavailable }
                let defaults = UserDefaults.standard
                if (defaults.string(forKey: DefaultsKey.continuityHotspot) ?? "").isEmpty,
                   hotspots.count == 1 {
                    defaults.set(hotspots[0], forKey: DefaultsKey.continuityHotspot)
                }
            } catch is CancellationError { }
            catch let error as ContinuityHotspotError {
                discoveryFailure = error == .permission ? .permission : .unavailable
            } catch { discoveryFailure = .unavailable }
        }
    }

    func start() {
        guard AppFeature.keepAwake.isAvailable,
              task == nil, !discovering, !workflow.busy else { return }
        let defaults = UserDefaults.standard
        let name = (defaults.string(forKey: DefaultsKey.continuityHotspot) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if workflow.phase == .active { workflow.cancel() }
        let apps = defaults.stringArray(forKey: DefaultsKey.continuityQuitApps) ?? []
        let id = UUID()
        operationID = id
        task = Task {
            defer { if operationID == id { task = nil } }
            await workflow.run(hotspot: name, apps: apps)
        }
    }

    func cancel() {
        discoveryTask?.cancel()
        operationID = UUID()
        task?.cancel()
        task = nil
        workflow.cancel()
    }
}
