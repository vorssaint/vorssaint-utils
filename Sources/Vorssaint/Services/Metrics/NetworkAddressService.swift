// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import SystemConfiguration

/// View-owned. Every reading but the public address comes from the local
/// interface list, so no request leaves the machine. The public address is
/// opt-in and asks Cloudflare, the speed test's provider, so the app still
/// talks to only one.
final class NetworkAddressService: ObservableObject {
    @Published private(set) var localAddresses: [String] = []
    /// The interface the default route uses, as "Wi-Fi (en0)".
    @Published private(set) var primaryInterface: String?
    @Published private(set) var physicalAddress: String?
    @Published private(set) var publicAddress: String?

    private static let traceURL = URL(string: "\(SpeedTest.host)/cdn-cgi/trace")!
    private let store = SCDynamicStoreCreate(nil, "Vorssaint" as CFString, nil, nil)
    private let session = URLSession(configuration: .ephemeral)
    private var publicTask: URLSessionDataTask?
    private var publicSerial = 0

    func refreshLocalAddresses() {
        let names = Self.connectionNames()
        let bsdName = primaryInterfaceName()
        let interface = bsdName.map { name in names[name].map { "\($0) (\(name))" } ?? name }
        if interface != primaryInterface { primaryInterface = interface }
        let hardware = bsdName.flatMap(Self.physicalAddress(of:))
        if hardware != physicalAddress { physicalAddress = hardware }

        let addresses = Self.readLocalAddresses(names: names)
        guard addresses != localAddresses else { return }
        localAddresses = addresses
        // A new local address means a new network, and likely a new way out.
        refreshPublicAddress()
    }

    /// Looks the public address up again, or forgets it when the setting is
    /// off or nothing is connected.
    func refreshPublicAddress() {
        publicSerial &+= 1
        publicTask?.cancel()
        publicTask = nil
        guard UserDefaults.standard.bool(forKey: DefaultsKey.networkPublicIP), !localAddresses.isEmpty else {
            publicAddress = nil
            return
        }
        let serial = publicSerial
        publicTask = session.dataTask(with: Self.traceURL) { [weak self] data, _, _ in
            let address = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Self.publicAddress(fromTrace:))
            DispatchQueue.main.async {
                guard let self, self.publicSerial == serial else { return }
                self.publicTask = nil
                self.publicAddress = address
            }
        }
        publicTask?.resume()
    }

    func cancel() {
        publicSerial &+= 1
        publicTask?.cancel()
        publicTask = nil
        localAddresses = []
        primaryInterface = nil
        physicalAddress = nil
        publicAddress = nil
    }

    static func includesLocalAddress(name: String, flags: UInt32, family: Int32) -> Bool {
        family == AF_INET && flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING)
            && MetricFormat.includeNetworkInterface(name)
    }

    /// The `ip=` line of Cloudflare's trace, which is plain `key=value` lines.
    static func publicAddress(fromTrace text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("ip=") }
        guard let address = line?.dropFirst(3), !address.isEmpty else { return nil }
        return String(address)
    }

    /// Six bytes as "84:2f:57:2e:d6:1d"; an empty or all-zero address is none.
    static func formattedPhysicalAddress(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    static func readLocalAddresses(names: [String: String]) -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses = Set<String>()
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            guard includesLocalAddress(name: name, flags: entry.ifa_flags,
                                       family: Int32(address.pointee.sa_family)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            // The system knows en0 as "Wi-Fi"; the BSD name means nothing on screen.
            addresses.insert(names[name].map { "\(ip) (\($0))" } ?? ip)
        }
        return addresses.sorted()
    }

    /// The BSD name of the interface carrying the default IPv4 route, as the
    /// system publishes it for its own network settings.
    private func primaryInterfaceName() -> String? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    /// The link-layer address of one interface. A `sockaddr_dl` stores the
    /// interface name first and the address right after it.
    private static func physicalAddress(of name: String) -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  String(cString: entry.ifa_name) == name else { continue }
            let raw = UnsafeRawPointer(address)
            let link = raw.load(as: sockaddr_dl.self)
            let start = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data)! + Int(link.sdl_nlen)
            guard start + Int(link.sdl_alen) <= Int(link.sdl_len) else { return nil }
            return formattedPhysicalAddress((0..<Int(link.sdl_alen)).map {
                raw.load(fromByteOffset: start + $0, as: UInt8.self)
            })
        }
        return nil
    }

    /// The system's own name per interface ("Wi-Fi", "Ethernet"), keyed by BSD
    /// name. An interface the system has no name for keeps no tag.
    private static func connectionNames() -> [String: String] {
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            names[bsd] = display
        }
        return names
    }
}
