// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NetworkAddressTests {
    static func run(expect: (Bool, String) -> Void) {
        let running = UInt32(IFF_UP | IFF_RUNNING)
        expect(NetworkAddressService.includesLocalAddress(name: "en0", flags: running, family: AF_INET),
               "an up and running IPv4 interface is included")
        expect(!NetworkAddressService.includesLocalAddress(name: "lo0", flags: running, family: AF_INET),
               "the loopback interface is excluded")
        expect(!NetworkAddressService.includesLocalAddress(name: "utun3", flags: running, family: AF_INET),
               "a VPN tunnel is excluded, as on the rest of the network card")
        expect(!NetworkAddressService.includesLocalAddress(name: "bridge0", flags: running, family: AF_INET),
               "a bridge is excluded, as on the rest of the network card")
        expect(!NetworkAddressService.includesLocalAddress(name: "en0", flags: UInt32(IFF_UP), family: AF_INET),
               "an interface that is not running is excluded")
        expect(!NetworkAddressService.includesLocalAddress(name: "en0", flags: running, family: AF_INET6),
               "IPv6 interfaces are excluded from the local list")

        let trace = "fl=234f18\nh=speed.cloudflare.com\nip=203.0.113.7\nts=1792664858.000\n"
        expect(NetworkAddressService.publicAddress(fromTrace: trace) == "203.0.113.7",
               "the public address is the trace's ip line")
        expect(NetworkAddressService.publicAddress(fromTrace: "ip=2001:db8::1") == "2001:db8::1",
               "an IPv6 public address is kept whole")
        expect(NetworkAddressService.publicAddress(fromTrace: "h=x\nip=\n") == nil
                   && NetworkAddressService.publicAddress(fromTrace: "<html>") == nil,
               "a trace without an address shows none")
        expect(NetworkAddressService.formattedPhysicalAddress([0x84, 0x2f, 0x57, 0x2e, 0xd6, 0x1d])
                   == "84:2f:57:2e:d6:1d",
               "a hardware address reads as six lowercase hex pairs")
        expect(NetworkAddressService.formattedPhysicalAddress([0, 0, 0, 0, 0, 0]) == nil
                   && NetworkAddressService.formattedPhysicalAddress([]) == nil,
               "an interface without a hardware address shows none")
    }
}
