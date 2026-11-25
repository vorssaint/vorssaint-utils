// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The generator compiles the real helper request, service save and settings
/// callbacks against these doubles. No hardware or app preferences are touched.
enum BatterySettingsApplyTests {
    struct Queue { func async(_ work: () -> Void) { work() } }
    struct Hardware { var supportsLED = true }
    class ControllerState {
        let queue = Queue()
        var configuration = BatteryConfiguration()
        var baseline: BatteryControlHardware.Baseline?
        var owner: UUID?
        var error: String?
        var hardware: Hardware? = Hardware()
        var starts = 0
        var restores = 0
        var saves = 0
        func start() { starts += 1 }
        func restore() -> Bool { restores += 1; baseline = nil; return true }
        @discardableResult func persist() -> Bool { saves += 1; return true }
        func tick() {}
        func execute(_ action: BatteryAction, value: Int) {}
        func response() -> Data { try! JSONEncoder().encode(reply(configuration, error: error)) }
    }
    enum AppFeature {
        case batteryCare
        var isAvailable: Bool { true }
    }
    enum PowerSampler { static let hasInternalBattery = true }
    enum UserDefaults {
        static let standard = Defaults()
        final class Defaults { func set(_ value: Bool, forKey: String) {} }
    }
    class ServiceState {
        var authorized = true
        var error: String?
        var configuration = BatteryConfiguration()
        var request: BatteryRequest?
        var callback: ((BatteryResponse) -> Void)?
        func send(_ request: BatteryRequest?, completion: ((BatteryResponse) -> Void)? = nil) {
            self.request = request; callback = completion
        }
        func store(_ value: BatteryConfiguration) { configuration = value }
        func updateTimer() {}
        func deliver(_ response: BatteryResponse) { let reply = callback; callback = nil; reply?(response) }
    }
    class SettingsState {
        let service = Service()
        var draft = BatteryConfiguration()
        var dirty = false
    }
    static func reply(_ configuration: BatteryConfiguration, error: String? = nil) -> BatteryResponse {
        .init(configuration: configuration, state: configuration.enabled ? .charging : .disabled,
              mode: .automatic, phase: .firstCharge, supportsLimit: true,
              supportsDischarge: false, supportsLED: false, error: error)
    }
    static func run(_ t: TestSuite) {
        let controller = Controller()
        let session = UUID()
        for limit in [20, 50, 70, 73, 90, 100] {
            var requested = BatteryConfiguration(); requested.limit = limit
            let data = try! JSONEncoder().encode(BatteryRequest(configuration: requested))
            var received: BatteryResponse?
            controller.request(data, session: session) { received = try? JSONDecoder().decode(BatteryResponse.self, from: $0) }
            t.expect(received?.configuration == requested, "saving a disabled limit retains \(limit)% instead of the helper's previous value")
            t.expect(controller.starts == 0, "saving disabled preferences never starts hardware control")
        }
        controller.configuration.enabled = true
        controller.baseline = .init()
        var disabled = BatteryConfiguration(); disabled.limit = 90; disabled.sailing = 8
        controller.request(try! JSONEncoder().encode(BatteryRequest(configuration: disabled)), session: session) { _ in }
        t.expect(controller.configuration == disabled && controller.saves == 1 && controller.baseline == nil,
                 "disabling active control retains the selected policy while restoring hardware")
        var invalid = disabled; invalid.limit = 101
        controller.request(try! JSONEncoder().encode(BatteryRequest(configuration: invalid)), session: session) { _ in }
        t.expect(controller.configuration == disabled && controller.error == "invalidConfiguration", "invalid limits cannot replace saved settings")

        let settings = Settings()
        settings.draft.limit = 90; settings.dirty = true
        settings.apply()
        t.expect(settings.service.request?.configuration?.limit == 90 && settings.dirty, "Apply submits the selected limit and waits for acknowledgment")
        settings.receive(reply(BatteryConfiguration()))
        t.expect(settings.draft.limit == 90 && settings.dirty, "an old 80% status cannot erase an in-flight selection")
        settings.service.deliver(reply(settings.draft))
        t.expect(!settings.dirty && settings.service.configuration.limit == 90, "matching acknowledgment commits the selection")
        settings.receive(reply(BatteryConfiguration()))
        t.expect(settings.draft.limit == 90, "restarted idle helper defaults cannot erase a saved disabled limit")

        settings.draft.limit = 73; settings.dirty = true
        settings.apply()
        settings.service.deliver(reply(settings.service.configuration, error: "failed"))
        settings.receive(reply(settings.service.configuration))
        t.expect(settings.draft.limit == 73 && settings.dirty, "failed saves retain the selection for retry instead of resetting the slider")
        settings.apply()
        settings.service.deliver(reply(settings.service.configuration))
        t.expect(settings.draft.limit == 73 && settings.dirty, "a successful reply with the wrong configuration is not an acknowledgment")

        settings.apply()
        let submitted = settings.draft
        settings.draft.limit = 95
        settings.service.deliver(reply(submitted))
        t.expect(settings.draft.limit == 95 && settings.dirty, "edits made while Apply is running remain unsaved")
        settings.apply()
        settings.service.deliver(reply(settings.draft))
        var active = settings.draft; active.enabled = true; active.limit = 70
        settings.receive(reply(active))
        t.expect(settings.draft == active, "clean settings still follow active helper changes such as scheduled limits")
    }
}
