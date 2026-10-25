// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The charge limit's decisions run against doubles: nothing here touches
/// the SMC, the power sources or a privileged helper. The hardware contract
/// itself is only exercised by the helper's own selftest on a real Mac.
enum BatteryControlTests {
    static func run(_ suite: TestSuite) {
        limitsValidate()
        hysteresisDecisions(suite)
        dischargeCycle(suite)
        capabilitySelection(suite)
        snapshotRoundTrip(suite)
        localization(suite)
    }

    // MARK: Limits

    private static func limitsValidate() {
        typealias S = BatteryLimitState
        func expect(_ condition: Bool, _ name: String) {
            guard condition else {
                fatalError("BatteryControlTests expected \(name)")
            }
        }
        expect(S.valid(S(enabled: true, upper: 80, lowerDelta: 2)), "a normal band is valid")
        expect(S.valid(S(enabled: true, upper: 100, lowerDelta: 0)),
               "100 % with no delta is the inert edge")
        expect(S.valid(S(enabled: true, upper: 50, lowerDelta: 20)), "the extreme band is valid")
        expect(S.valid(S(enabled: true, upper: 100, lowerDelta: 90)), "the deepest band is valid")
        expect(!S.valid(S(enabled: true, upper: 49, lowerDelta: 0)), "the band stops at 50 %")
        expect(!S.valid(S(enabled: true, upper: 101, lowerDelta: 0)), "the band stops at 100 %")
        expect(!S.valid(S(enabled: true, upper: 80, lowerDelta: 91)), "the delta stops at 90")
        expect(S(enabled: true, upper: 80, lowerDelta: 65).lower == 15,
               "a deep resume level is honoured")
        expect(S(enabled: true, upper: 80, lowerDelta: 80).lower == 10,
               "the lower edge clamps to the 10 % floor")
    }

    private static func hysteresisDecisions(_ suite: TestSuite) {
        let limits = BatteryLimitState(enabled: true, upper: 80, lowerDelta: 2)
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: 85) == .inhibit,
                     "above the upper limit the charge stops")
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: 80) == .inhibit,
                     "at the upper limit the charge stops")
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: 78) == .enable,
                     "at the lower limit the charge resumes")
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: 79) == nil,
                     "inside the band the current state stands")
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: 100) == .inhibit,
                     "a full pack is inhibited")
        // A disabled state answers nil: macOS holds charging, we stay out.
        let disabled = BatteryLimitState(enabled: false, upper: 80, lowerDelta: 2)
        suite.expect(BatteryLimitState.charging(enabled: disabled, percentage: 30) == nil,
                     "the disabled state never decides")
        // Invalid state answers nil: nonsense data cannot steer hardware.
        let nonsense = BatteryLimitState(enabled: true, upper: 10, lowerDelta: 0)
        suite.expect(BatteryLimitState.charging(enabled: nonsense, percentage: 5) == nil,
                     "an invalid band never decides")
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: -1) == nil,
                     "an impossible reading never decides")
        suite.expect(BatteryLimitState.charging(enabled: limits, percentage: 101) == nil,
                     "an impossible reading never decides")
    }

    // MARK: Capability selection

    private static func dischargeCycle(_ suite: TestSuite) {
        typealias S = BatteryLimitState
        let cycling = S(enabled: true, upper: 80, lowerDelta: 10, discharge: true)
        suite.expect(S.adapter(for: cycling, percentage: 80) == .disconnect,
                     "cycle mode cuts wall power at the upper limit")
        suite.expect(S.adapter(for: cycling, percentage: 100) == .disconnect,
                     "a full pack drains on cycle mode")
        suite.expect(S.adapter(for: cycling, percentage: 75) == .hold,
                     "mid-discharge the cut stands")
        suite.expect(S.adapter(for: cycling, percentage: 70) == .connect,
                     "wall power returns at the lower edge")
        suite.expect(S.adapter(for: cycling, percentage: 40) == .connect,
                     "a low pack is always connected")
        var plain = cycling
        plain.discharge = false
        suite.expect(S.adapter(for: plain, percentage: 95) == .connect,
                     "without cycle mode the adapter is handed back")
        var off = cycling
        off.enabled = false
        suite.expect(S.adapter(for: off, percentage: 95) == .connect,
                     "a disabled limit never holds wall power back")
        let invalid = S(enabled: true, upper: 10, lowerDelta: 0, discharge: true)
        suite.expect(S.adapter(for: invalid, percentage: 95) == .connect,
                     "an invalid band never cuts wall power")
        // The floor: the lower edge never drops under 10 %, so a cycle can
        // never drain a Mac below it, however deep the band is set.
        let deep = S(enabled: true, upper: 80, lowerDelta: 90, discharge: true)
        suite.expect(S.adapter(for: deep, percentage: 10) == .connect,
                     "the drain stops at the 10 % floor")
        suite.expect(S.adapter(for: deep, percentage: 11) == .hold,
                     "above the floor the drain carries on")
        suite.expect(S.adapter(for: S(enabled: true, upper: 80, lowerDelta: 65, discharge: true),
                               percentage: 15) == .connect,
                     "a 15 % resume level brings wall power back")

        suite.expect(BatteryControlIPC.decodeLimits(BatteryControlIPC.encode(cycling)) == cycling,
                     "cycle mode travels over XPC JSON")
    }

    private static func capabilitySelection(_ suite: TestSuite) {
        func probe(_ presented: [String: Int]) -> Probe {
            var probe = Probe()
            probe.keySizes = presented
            return probe
        }

        suite.expect(probe(["bfF0": 1, "bfD0": 4, "bfE0": 4]).backend == .unsupported,
                     "firmware-managed limits are left to macOS")
        suite.expect(probe(["CH0B": 1, "CH0C": 1]).backend == .legacy,
                     "the direct pairing selects the legacy backend")
        suite.expect(probe(["CH0B": 1]).backend == .unsupported,
                     "one direct key alone selects nothing")
        suite.expect(probe(["CHTE": 4]).backend == .legacy,
                     "the Tahoe-family key selects the legacy backend")
        suite.expect(probe(["CHIE": 1]).backend == .unsupported,
                     "adapter keys alone control nothing")

        suite.expect(probe(["CH0I": 1]).adapterKeyName == "CH0I", "the first adapter key wins")
        suite.expect(probe(["CH0J": 1]).adapterKeyName == "CH0J", "the second adapter key wins")
        suite.expect(probe(["CH0I": 1, "CH0J": 1, "CHIE": 1]).adapterKeyName == "CH0I",
                     "the first adapter key wins when all exist")
        suite.expect(probe([:]).adapterKeyName == nil, "no adapter key is reported as none")
    }

    // MARK: IPC snapshot

    private static func snapshotRoundTrip(_ suite: TestSuite) {
        var snapshot = BatteryControlSnapshot.empty
        snapshot.backend = .legacy
        snapshot.adapterKeyPresent = true
        snapshot.limits = BatteryLimitState(enabled: true, upper: 80, lowerDelta: 2)
        snapshot.percentage = 97
        snapshot.isCharging = false
        snapshot.lastFault = "none"
        let data = BatteryControlIPC.encode(snapshot)
        let restored = BatteryControlIPC.decodeSnapshot(data)
        suite.expect(restored == snapshot, "the snapshot round-trips over XPC JSON")

        suite.expect(BatteryControlIPC.decodeSnapshot(Data("broken".utf8)) == nil,
                     "a broken reply never wedges a caller")
        let inert = BatteryLimitState(enabled: false,
                                      upper: BatteryControlCore.defaultUpper,
                                      lowerDelta: BatteryControlCore.defaultLowerDelta)
        suite.expect(BatteryControlIPC.decodeLimits(BatteryControlIPC.encode(inert)) == inert,
                     "limits travel over XPC JSON")
    }

    // MARK: Localization coverage

    private static func localization(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = BatteryControlFeatureStrings.batteryControl(language)
            suite.expect(!strings.dischargeLabel.isEmpty && !strings.dischargeNote.isEmpty
                            && !strings.dischargeUnavailable.isEmpty,
                         "\(language.rawValue) holds its cycle mode strings")
            suite.expect(!strings.title.isEmpty && !strings.engage.isEmpty,
                         "\(language.rawValue) holds its core strings")
        }
    }
}
