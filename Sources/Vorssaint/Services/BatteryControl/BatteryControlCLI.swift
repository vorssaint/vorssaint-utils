// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement

/// Shortcuts can invoke this signed executable with Run Shell Script. It uses
/// exactly the same validated helper actions as the UI; no sudo or shell interpolation.
enum BatteryControlCLI {
    static func runIfRequestedAndExit() {
        guard let index = CommandLine.arguments.firstIndex(of: "--battery-care") else { return }
        let args = Array(CommandLine.arguments.dropFirst(index + 1))
        guard let command = args.first, command == "status" || command == "setLED" || BatteryAction(rawValue: command) != nil,
              args.count <= 2,
              command == "setLED" ? (args.count == 2 && BatteryLED(rawValue: args[1]) != nil)
                : (args.count < 2 || Int(args[1]).map({ (20...100).contains($0) }) == true) else {
            fputs("Usage: --battery-care status|setLimit|topUp|discharge|pause|resume|calibrate|cancel|lowPowerOn|lowPowerOff [20...100] or --battery-care setLED automatic|green|orange|blinking|off\n", stderr)
            exit(2)
        }
        guard AppFeature.batteryCare.isAvailable,
              SMAppService.daemon(plistName: FanControlIdentifiers.plistName).status == .enabled else {
            fputs("Enable Battery Care and authorize its helper in Settings first.\n", stderr); exit(1)
        }
        let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
        connection.activate()
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Data?
        let reply: (Data) -> Void = { data in lock.withLock { result = data }; semaphore.signal() }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in semaphore.signal() }) as? FanControlXPCProtocol else { exit(1) }
        if command == "status" { proxy.batteryStatus(withReply: reply) }
        else {
            let request = command == "setLED" ? BatteryRequest(led: BatteryLED(rawValue: args[1])) : BatteryRequest(action: BatteryAction(rawValue: command), value: args.count == 2 ? Int(args[1])! : BatteryControlService.shared.configuration.limit)
            guard let data = try? JSONEncoder().encode(request) else { exit(1) }
            proxy.batteryRequest(data, withReply: reply)
        }
        _ = semaphore.wait(timeout: .now() + 20)
        connection.invalidate()
        guard let data = lock.withLock({ result }), let response = try? JSONDecoder().decode(BatteryResponse.self, from: data) else {
            fputs("Battery helper did not respond.\n", stderr); exit(1)
        }
        FileHandle.standardOutput.write(data); print("")
        exit(response.error == nil ? 0 : 1)
    }
}
