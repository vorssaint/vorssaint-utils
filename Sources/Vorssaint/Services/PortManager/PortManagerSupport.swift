// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PortManagerEntry: Identifiable, Equatable {
    let port: Int
    let protocolName: String
    let address: String
    let pid: Int32
    let processName: String
    let startedAt: UInt64?
    var id: String { "\(protocolName)-\(port)-\(pid)-\(address)" }
}

enum PortManagerSupport {
    static func parseLsof(_ text: String) -> [PortManagerEntry] {
        var name = "", pid: Int32 = 0, address = "", port = 0, proto = "TCP"
        var rows: [PortManagerEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n").map(String.init) {
            guard let type = line.first else { continue }
            let value = String(line.dropFirst())
            switch type {
            case "p":
                pid = Int32(value) ?? 0; port = 0; address = ""
            case "c": name = value
            case "P": proto = value
            case "n":
                address = value
                if let last = value.split(separator: ":").last, let parsed = Int(last) { port = parsed }
                if pid > 0 && port > 0 {
                    let key = "\(proto)|\(port)|\(address)|\(pid)"
                    if seen.insert(key).inserted {
                        rows.append(.init(port: port, protocolName: proto, address: address,
                                          pid: pid, processName: name, startedAt: nil))
                    }
                }
            case "T": continue
            default: continue
            }
        }
        return rows.sorted { $0.port == $1.port ? $0.processName < $1.processName : $0.port < $1.port }
    }
}
