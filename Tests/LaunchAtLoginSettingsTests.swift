// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production view methods run with controlled queues and an inert system
/// service. No login item or user preference is changed by these tests.
enum LaunchAtLoginSettingsTests {
    @propertyWrapper struct State<Value> {
        final class Storage {
            var value: Value
            init(_ value: Value) { self.value = value }
        }
        private let storage: Storage
        init(wrappedValue: Value) { storage = Storage(wrappedValue) }
        var wrappedValue: Value {
            get { storage.value }
            nonmutating set { storage.value = newValue }
        }
    }

    final class Queue {
        enum QoS { case userInitiated }
        static let main = Queue()
        static let worker = Queue()
        var jobs: [() -> Void] = []
        static func global(qos: QoS) -> Queue { worker }
        func async(execute action: @escaping () -> Void) { jobs.append(action) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }

    enum Failure: LocalizedError {
        case approval, unavailable
        var errorDescription: String? { "test service failure" }
    }

    enum Service {
        static var registration: LaunchAtLoginSupport.Registration = .off
        static var result: LaunchAtLoginSupport.Registration = .off
        static var failure: Failure?
        static var writes: [Bool] = []
        static func setEnabled(_ enabled: Bool) throws {
            writes.append(enabled)
            registration = result
            if let failure { throw failure }
        }
    }

    struct View {
        typealias DispatchQueue = Queue
        typealias LaunchAtLogin = Service
        @State var loginRegistration: LaunchAtLoginSupport.Registration = .off
        @State var loginError: String?
        @State var loginRefreshID = UUID()
    }

    static func run(_ suite: TestSuite) {
        defer {
            Queue.main.jobs = []; Queue.worker.jobs = []
            Service.registration = .off; Service.result = .off
            Service.failure = nil; Service.writes = []
        }
        let view = View()
        func refresh(to registration: LaunchAtLoginSupport.Registration) {
            Service.registration = registration
            view.refreshLaunchAtLogin()
            Queue.worker.drain()
            Queue.main.drain()
        }

        refresh(to: .needsApproval)
        suite.expect(view.loginRegistration == .needsApproval,
                     "opening settings preserves pending approval instead of flattening it to off")
        view.loginError = "previous approval warning"
        refresh(to: .enabled)
        suite.expect(view.loginRegistration == .enabled && view.loginError == nil,
                     "refresh after system approval enables the toggle and clears the old warning")
        refresh(to: .needsApproval)
        refresh(to: .off)
        suite.expect(view.loginRegistration == .off && view.loginError == nil,
                     "removing the login item clears approval guidance without claiming it is enabled")
        suite.expect(Service.writes.isEmpty, "refresh never registers or unregisters a login item")

        Service.result = .needsApproval
        Service.failure = .approval
        view.setLaunchAtLogin(true)
        suite.expect(view.loginRegistration == .needsApproval && view.loginError == nil,
                     "pending approval is shown from current status without a duplicate operation error")
        Service.failure = nil
        view.setLaunchAtLogin(true)
        suite.expect(view.loginRegistration == .needsApproval,
                     "a successful register call does not imply that macOS allowed the item")
        Service.result = .off
        Service.failure = .unavailable
        view.setLaunchAtLogin(true)
        suite.expect(view.loginRegistration == .off && view.loginError == Failure.unavailable.localizedDescription,
                     "an unrelated registration failure still has an actionable error")

        Service.registration = .enabled
        view.refreshLaunchAtLogin()
        Queue.worker.drain() // The old enabled snapshot is waiting for publication.
        Service.result = .off
        Service.failure = nil
        view.setLaunchAtLogin(false)
        Queue.main.drain()
        suite.expect(view.loginRegistration == .off && view.loginError == nil,
                     "a stale refresh cannot undo a later user disable")

        Service.registration = .needsApproval
        view.refreshLaunchAtLogin()
        Queue.worker.drain()
        Service.registration = .enabled
        view.refreshLaunchAtLogin()
        Queue.worker.drain()
        let newest = Queue.main.jobs.removeLast()
        newest()
        Queue.main.drain()
        suite.expect(view.loginRegistration == .enabled,
                     "an older approval snapshot cannot overwrite a newer refresh")
        suite.expect(Service.writes == [true, true, true, false],
                     "only explicit toggle actions write to the system service")
    }
}
