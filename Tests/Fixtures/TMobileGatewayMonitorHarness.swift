// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

// Only unrelated app wiring is doubled. The coordinator, transport, parsing,
// retirement barrier and demand formatter compile from production sources.
enum DefaultsKey {
    static let monitorNetTMobile = "panel"
    static let tMobileGatewayAddress = "address"
}
enum AppFeature {
    case monitorNetwork
    var availabilityKey: String { "networkAvailable" }
}
struct MenuBarMetric {
    let isTMobileGateway: Bool
    static func enabled(in defaults: UserDefaults) -> [MenuBarMetric] {
        defaults.bool(forKey: "menu") ? [MenuBarMetric(isTMobileGateway: true)] : []
    }
}

@main struct TMobileGatewayMonitorHarness {
    @MainActor static func main() {
        let domain = "com.vorssaint.tests.tmobile-monitor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "networkAvailable")
        defaults.set("http://192.168.12.1", forKey: "address")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MonitorProtocol.self]
        let service = TMobileGatewayService(configuration: configuration)
        let monitor = TMobileGatewayMonitor(service: service, defaults: defaults)
        monitor.syncPreferences()
        settle()
        check(MonitorProtocol.count == 0, "default off performs no gateway request")
        monitor.setPanelVisible(true)
        settle()
        check(MonitorProtocol.count == 0, "visible but disabled panel performs no request")
        defaults.set(true, forKey: "panel")
        monitor.syncPreferences()
        wait { service.phase == .ready }
        check(MonitorProtocol.count == 1, "enabled visible panel shares one successful snapshot")
        monitor.setPanelVisible(false)
        check(service.phase == .idle && service.snapshot == nil, "closing the panel clears live readings")
        monitor.setPanelVisible(true)
        wait { service.phase == .ready }
        check(MonitorProtocol.count == 2, "reopening the panel resumes one shared reader")
        defaults.set(true, forKey: "menu")
        monitor.syncPreferences()
        settle()
        check(MonitorProtocol.count == 2, "adding the menu bar consumer does not start a duplicate request")
        monitor.setPanelVisible(false)
        check(service.phase == .ready, "closing the panel retains demand from the menu bar")
        defaults.set(false, forKey: "menu")
        monitor.syncPreferences()
        check(service.phase == .idle && service.snapshot == nil, "last consumer stopping clears live readings")
        defaults.set(true, forKey: "menu")
        monitor.syncPreferences()
        wait { service.phase == .ready }
        check(MonitorProtocol.count == 3, "re-enabling the pin resumes the same reader")
        defaults.set(false, forKey: "networkAvailable")
        monitor.syncPreferences()
        check(service.phase == .idle && service.snapshot == nil, "removing the network feature cancels all consumers")
        defaults.set(true, forKey: "networkAvailable")
        defaults.set("http://8.8.8.8", forKey: "address")
        monitor.syncPreferences()
        settle()
        check(service.phase == .failed(.invalidAddress) && MonitorProtocol.count == 3,
              "invalid origins do not open another request")
        defaults.set(false, forKey: "menu")
        monitor.syncPreferences()
        print("PASS: 11 T-Mobile shared-reader lifecycle checks; every request intercepted locally")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAIL: \(message)") }
    }
    private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
    private static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline { settle() }
        check(condition(), "asynchronous gateway request completed")
    }
}

private final class MonitorProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var captured = 0
    static var count: Int { lock.withLock { captured } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.captured += 1 }
        let reply = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"signal":{"5g":{"bars":3,"bands":["n41"],"rsrp":-97}}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
