// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum NotchSystemReadoutTests {
    typealias Readout = NotchSystemReadout

    static func run(_ suite: TestSuite) {
        let all = Set(Readout.Kind.allCases)
        let gib: UInt64 = 1 << 30
        let laptop = Readout.Input(cpu: 0.14, gpu: 0.06, memoryUsed: 10 * gib, memoryTotal: 16 * gib,
                                   batteryPercent: 82, hasBattery: true, externalPower: false)

        let readings = Readout.readings(laptop, available: all)
        suite.expect(readings.map(\.kind) == [.battery, .cpu, .gpu, .memory],
                     "a laptop shows battery, CPU, GPU and memory in a fixed order")
        suite.expect(readings.map(\.value) == ["82%", "14%", "6%", "63%"],
                     "readings are whole percentages, memory as the share in use")
        suite.expect(readings.allSatisfy { !$0.attention }, "ordinary readings stay quiet")

        var desktop = laptop
        desktop.hasBattery = false
        desktop.batteryPercent = nil
        suite.expect(Readout.readings(desktop, available: all).map(\.kind) == [.cpu, .gpu, .memory],
                     "a Mac without a battery never shows a battery reading")

        suite.expect(Readout.readings(laptop, available: [.cpu, .memory]).map(\.kind) == [.cpu, .memory],
                     "a reading whose monitor feature is unavailable is left out")

        var sampling = laptop
        sampling.gpu = nil
        sampling.memoryTotal = 0
        suite.expect(Readout.readings(sampling, available: all).map(\.kind) == [.battery, .cpu],
                     "a reading not yet sampled, or without a total, is left out instead of shown empty")
        sampling.cpu = .nan
        suite.expect(!Readout.readings(sampling, available: all).contains { $0.kind == .cpu },
                     "a non-finite sample never reaches the header")

        var busy = laptop
        busy.cpu = Readout.busyLevel
        busy.memoryUsed = busy.memoryTotal
        busy.gpu = 1.4
        let busyReadings = Readout.readings(busy, available: all)
        suite.expect(busyReadings.filter(\.attention).map(\.kind) == [.cpu, .gpu, .memory],
                     "CPU, GPU and memory ask for attention from the System cards' busy level")
        suite.expect(busyReadings.first { $0.kind == .gpu }?.value == "100%",
                     "an out-of-range sample is clamped before it is shown")
        var justUnder = laptop
        justUnder.cpu = Readout.busyLevel - 0.01
        suite.expect(Readout.readings(justUnder, available: all).first { $0.kind == .cpu }?.attention == false,
                     "a reading below the busy level stays quiet")

        var low = laptop
        low.batteryPercent = Readout.lowBattery
        suite.expect(Readout.readings(low, available: all).first?.attention == true,
                     "a low battery on battery power asks for attention")
        low.externalPower = true
        let charging = Readout.readings(low, available: all).first
        suite.expect(charging?.attention == false && charging?.symbol == "battery.100percent.bolt",
                     "a low battery that is charging shows the charging symbol and stays quiet")

        suite.expect(Readout.readings(laptop, available: all, limit: 2).map(\.kind) == [.cpu, .memory],
                     "with room for two, CPU and memory stay")
        suite.expect(Readout.readings(laptop, available: all, limit: 3).map(\.kind) == [.cpu, .gpu, .memory],
                     "with room for three, battery gives way first")
        suite.expect(Readout.readings(low, available: all, limit: 0).isEmpty, "no room shows nothing")
        var lowOnBattery = laptop
        lowOnBattery.batteryPercent = 9
        suite.expect(Readout.readings(lowOnBattery, available: all, limit: 2).map(\.kind) == [.battery, .cpu],
                     "a reading that needs attention keeps its place ahead of quiet ones")

        let symbols = [0, 12, 13, 37, 38, 62, 63, 87, 88, 100].map { Readout.batterySymbol(percent: $0, externalPower: false) }
        suite.expect(symbols == ["battery.0percent", "battery.0percent", "battery.25percent", "battery.25percent",
                                 "battery.50percent", "battery.50percent", "battery.75percent", "battery.75percent",
                                 "battery.100percent", "battery.100percent"],
                     "the battery symbol follows the nearest quarter of charge")
    }
}
