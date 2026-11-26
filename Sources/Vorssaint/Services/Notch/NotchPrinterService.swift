// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

enum PrinterConnection: Equatable {
    case off
    case notConfigured
    case connecting
    case connected
    /// The cloud sign-in was turned down, as when its token expired. Trying
    /// again with the same one would only be turned down again.
    case refused
    case failed(String?)
}

/// The account and printer to follow, from preferences and the keychain.
struct PrinterEndpoint: Equatable {
    let host: String
    let username: String
    let password: String
    let serial: String

    static func current(in defaults: UserDefaults = .standard) -> PrinterEndpoint? {
        let endpoint = PrinterEndpoint(host: BambuCloudAPI.mqttHost,
                                       username: PrinterKeychain.read(.cloudUsername),
                                       password: PrinterKeychain.read(.cloudToken),
                                       serial: NotchPrinterSupport.serial(in: defaults))
        return endpoint.isComplete ? endpoint : nil
    }

    var isComplete: Bool { ![host, username, password, serial].contains { $0.isEmpty } }
}

/// Follows a Bambu Lab printer through Bambu Cloud, with the account signed
/// in under Settings, and keeps the latest print report for the island.
final class NotchPrinterService: ObservableObject {
    static let shared = NotchPrinterService()

    @Published private(set) var connection: PrinterConnection = .off
    @Published private(set) var status = PrinterStatus()
    @Published private(set) var lastReport: Date?

    /// A job is on the printer and the connection is live.
    var isActive: Bool { connection == .connected && status.state.isActive }

    private var client: BambuMQTTClient?
    private var settings: PrinterEndpoint?
    private var sequence = 0
    private var reconnect: DispatchWorkItem?
    private var staleCheck: Timer?

    private init() {}

    func syncWithPreferences() {
        guard NotchPrinterSupport.isEnabled() else { stop(); return }
        guard let wanted = PrinterEndpoint.current() else {
            stop()
            connection = .notConfigured
            return
        }
        if let settings, settings == wanted, client != nil || connection == .refused { return }
        stop()
        settings = wanted
        connect()
    }

    func stop() {
        reconnect?.cancel()
        reconnect = nil
        staleCheck?.invalidate()
        staleCheck = nil
        client?.stop()
        client = nil
        settings = nil
        connection = .off
        status = PrinterStatus()
        lastReport = nil
    }

    /// Settings changed the address, serial or code: start over with them.
    func reconnectNow() {
        stop()
        syncWithPreferences()
    }

    private func connect() {
        guard let settings else { return }
        connection = .connecting
        let client = BambuMQTTClient(host: settings.host, username: settings.username,
                                     password: settings.password) { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        self.client = client
        client.start()
    }

    private func handle(_ event: BambuMQTTClient.Event) {
        guard let settings, client != nil else { return }
        switch event {
        case .connected:
            connection = .connected
            client?.subscribe(NotchPrinterSupport.reportTopic(serial: settings.serial))
            requestFullReport()
            startStaleCheck()
        case .message(let topic, let payload):
            guard topic == NotchPrinterSupport.reportTopic(serial: settings.serial),
                  let print = NotchPrinterSupport.printReport(payload) else { return }
            let before = status
            var next = status
            next.merge(print)
            lastReport = Date()
            if next != status { status = next }
            announce(from: before.state, to: next.state)
        case .refused:
            client = nil
            staleCheck?.invalidate()
            connection = .refused
        case .disconnected(let reason):
            client = nil
            staleCheck?.invalidate()
            connection = .failed(reason)
            scheduleReconnect()
        }
    }

    private func requestFullReport() {
        guard let settings else { return }
        sequence += 1
        client?.publish(NotchPrinterSupport.requestTopic(serial: settings.serial),
                        payload: NotchPrinterSupport.pushAllRequest(sequence: sequence))
    }

    private func scheduleReconnect() {
        reconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.settings != nil, self.client == nil else { return }
            self.connect()
        }
        reconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchPrinterSupport.reconnectDelay, execute: work)
    }

    /// The printer stops sending when its Wi-Fi drops without closing the
    /// connection; a quiet minute and a half starts a fresh one.
    private func startStaleCheck() {
        staleCheck?.invalidate()
        staleCheck = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let lastReport = self.lastReport else { return }
            if Date().timeIntervalSince(lastReport) > NotchPrinterSupport.staleAfter {
                self.client?.stop()
                self.handle(.disconnected(nil))
            }
        }
    }

    /// Says so once when a job ends, fails or pauses, the moments worth
    /// looking up from the desk for.
    private func announce(from old: PrinterJobState, to new: PrinterJobState) {
        guard old != new, old != .unknown else { return }
        let text = FeatureStrings.notchPrinter(L10n.shared.language)
        let title: String
        switch new {
        case .finished where old.isActive: title = text.finishedNotice
        case .failed: title = text.failedNotice
        case .paused where old == .printing: title = text.pausedNotice
        default: return
        }
        let notch = NotchService.shared
        if notch.expanded && notch.selected == .printer { return }
        _ = notch.show(NotchNotice(event: .printer, title: title, detail: status.jobName ?? text.title,
                               symbol: new.symbol))
    }
}
