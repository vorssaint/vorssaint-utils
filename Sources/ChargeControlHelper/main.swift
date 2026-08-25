// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

private final class ChargeControlController {
    private let queue = DispatchQueue(label: "com.vorssaint.charge-control.helper")
    private var hardware = ChargeControlHardware()
    private var mode: ChargeControlMode = .charging
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var owner: UUID?
    private var watchdog: DispatchSourceTimer?

    init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.checkHeartbeat() }
        timer.resume()
        watchdog = timer
        try? hardware?.set(.charging)
    }

    func opened(_ id: UUID) { queue.async { self.owner = id; self.lastHeartbeat = ProcessInfo.processInfo.systemUptime } }
    func closed(_ id: UUID) { queue.async { if self.owner == id { self.restore() } } }

    func reply(_ reply: @escaping (Data) -> Void) {
        queue.async { reply(ChargeControlIPC.encode(self.response())) }
    }

    func apply(_ requested: ChargeControlMode, id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            guard self.owner == id else {
                reply(ChargeControlIPC.encode(.failure(.controlFailed)))
                return
            }
            guard let hardware = self.hardware else {
                reply(ChargeControlIPC.encode(.failure(.unsupportedHardware)))
                return
            }
            do {
                try hardware.set(requested)
                self.mode = requested
                self.lastHeartbeat = ProcessInfo.processInfo.systemUptime
                reply(ChargeControlIPC.encode(self.response()))
            } catch {
                try? hardware.set(.charging)
                self.mode = .charging
                reply(ChargeControlIPC.encode(.failure(.controlFailed, api: hardware.api)))
            }
        }
    }

    func heartbeat(id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            guard self.owner == id else {
                reply(ChargeControlIPC.encode(.failure(.controlFailed)))
                return
            }
            self.lastHeartbeat = ProcessInfo.processInfo.systemUptime
            reply(ChargeControlIPC.encode(self.response()))
        }
    }

    private func response() -> ChargeControlResponse {
        guard let hardware else { return .failure(.unsupportedHardware) }
        return .success(api: hardware.api, mode: mode)
    }

    private func checkHeartbeat() {
        if mode != .charging,
           ProcessInfo.processInfo.systemUptime - lastHeartbeat > 25 { restore() }
    }

    private func restore() {
        try? hardware?.set(.charging)
        mode = .charging
        owner = nil
    }

    func shutdown() { queue.sync { restore() } }
}

private final class ChargeControlConnection: NSObject, ChargeControlXPCProtocol {
    let id = UUID()
    private let controller: ChargeControlController
    init(_ controller: ChargeControlController) { self.controller = controller; super.init(); controller.opened(id) }
    deinit { controller.closed(id) }
    func status(withReply reply: @escaping (Data) -> Void) { controller.reply(reply) }
    func allowCharging(withReply reply: @escaping (Data) -> Void) { controller.apply(.charging, id: id, reply: reply) }
    func pauseCharging(withReply reply: @escaping (Data) -> Void) { controller.apply(.paused, id: id, reply: reply) }
    func startDischarging(withReply reply: @escaping (Data) -> Void) { controller.apply(.discharging, id: id, reply: reply) }
    func heartbeat(withReply reply: @escaping (Data) -> Void) { controller.heartbeat(id: id, reply: reply) }
    func restoreSystemDefault(withReply reply: @escaping (Data) -> Void) { controller.apply(.charging, id: id, reply: reply) }
}

private final class Delegate: NSObject, NSXPCListenerDelegate {
    let controller = ChargeControlController()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = ChargeControlConnection(controller)
        connection.exportedInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak controller] in controller?.closed(session.id) }
        connection.activate()
        return true
    }
}

if CommandLine.arguments.contains("--selftest") { exit(0) }
guard geteuid() == 0 else { exit(EXIT_FAILURE) }
private let delegate = Delegate()
private let listener = NSXPCListener(machServiceName: ChargeControlIdentifiers.helperID)
listener.setConnectionCodeSigningRequirement(ChargeControlIdentifiers.appCodeRequirement)
listener.delegate = delegate
listener.activate()
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { delegate.controller.shutdown(); exit(EXIT_SUCCESS) }
termination.resume()
let interruption = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruption.setEventHandler { delegate.controller.shutdown(); exit(EXIT_SUCCESS) }
interruption.resume()
RunLoop.main.run()
