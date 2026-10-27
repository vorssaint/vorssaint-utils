// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NetworkInterfaceSelectionTests {
    static func run(_ expect: (Bool, String) -> Void) {
        let available: Set<String> = ["en0", "en4", "lo0", "bridge1", "bridge100", "feth98", "feth99", "utun4"]
        expect(MetricFormat.networkInterfacesToCount(available: available, primary: ["bridge1"]) == ["bridge1"],
               "primary internet bridge is counted once without either mirrored fake Ethernet peer")
        expect(MetricFormat.networkInterfacesToCount(available: available, primary: ["en0"]) == ["en0", "en4"],
               "ordinary connections retain physical aggregation and exclude VM bridges and fake Ethernet")
        expect(MetricFormat.networkInterfacesToCount(available: available, primary: ["utun4"]) == ["en0", "en4"],
               "VPN tunnel does not double count physical traffic")
        expect(MetricFormat.networkInterfacesToCount(available: available, primary: ["bridge1", "en4"]) == ["bridge1", "en4"],
               "different IPv4 and IPv6 primary interfaces are each counted once")
        expect(MetricFormat.networkInterfacesToCount(available: available, primary: ["bridge1", "utun4"]) == ["bridge1"],
               "VPN over a primary bridge retains the bridge without its tunnel")
        expect(MetricFormat.networkInterfacesToCount(available: available, primary: []) == ["en0", "en4"],
               "missing primary metadata preserves physical fallback")
        expect(!MetricFormat.includeNetworkInterface("feth98") && !MetricFormat.includeNetworkInterface("feth99"),
               "both mirrored fake Ethernet endpoints are excluded")

        var index = 0
        let counters = [
            NetworkCounters(received: 100, sent: 200, interfaces: ["en0"]),
            NetworkCounters(received: 200, sent: 250, interfaces: ["en0"]),
            NetworkCounters(received: 10_000_000, sent: 20_000_000, interfaces: ["bridge1"]),
            NetworkCounters(received: 10_000_300, sent: 20_000_025, interfaces: ["bridge1"]),
            NetworkCounters(received: 10, sent: 20, interfaces: ["en0"]),
            NetworkCounters(received: 410, sent: 55, interfaces: ["en0"]),
        ]
        let sampler = NetworkSampler(counterReader: {
            defer { index += 1 }
            return counters[index]
        }, processReader: { fatalError("moving counters should not use process fallback") })
        _ = sampler.sample(now: 0)
        let physical = sampler.sample(now: 1)
        expect(physical.downBytesPerSec == 100 && physical.upBytesPerSec == 50,
               "ordinary physical direction rates stay independent")
        let switched = sampler.sample(now: 2)
        expect(switched.downBytesPerSec == nil && switched.upBytesPerSec == nil && switched.totalDown == 100 && switched.totalUp == 50,
               "switching to a bridge establishes a baseline without inflating totals")
        let bridge = sampler.sample(now: 3)
        expect(bridge.downBytesPerSec == 300 && bridge.upBytesPerSec == 25 && bridge.totalDown == 400 && bridge.totalUp == 75,
               "bridge download and upload remain independent and accumulate once")
        let returned = sampler.sample(now: 4)
        expect(returned.downBytesPerSec == nil && returned.upBytesPerSec == nil,
               "switching back to smaller physical counters also resets the baseline")
        let final = sampler.sample(now: 5)
        expect(final.downBytesPerSec == 400 && final.upBytesPerSec == 35 && final.totalDown == 800 && final.totalUp == 110,
               "physical readings and totals resume after leaving the bridge")
    }
}
