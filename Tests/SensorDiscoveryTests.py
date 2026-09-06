# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Replay the production sensor discovery methods with a fake IOKit transport.

The monitor methods are taken unchanged from the source, as in the preference
cleanup harness. This isolates them from the app's global services and UI. The
SMC client, wire structs, decoding and temperature selection compile unchanged.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
sdk = sys.argv[1] if len(sys.argv) > 1 else subprocess.check_output(
    ["xcrun", "--show-sdk-path"], text=True).strip()
source = (root / "Sources/Vorssaint/Services/SystemMonitor/SystemMonitor.swift").read_text()


def method(name):
    start = source.index("    private func " + name + "(")
    end = source.index("\n    }", start) + len("\n    }")
    return source[start:end]


methods = "\n".join(method(name) for name in (
    "prepareIfNeeded", "cpuTemperature", "temperatureReadings", "maxTemperature"))

transport = r'''
#include <IOKit/IOKitLib.h>
#include <string.h>
static int scenario, opens, scans;
void set_scenario(int n) { scenario = n; }
void reset_counts(void) { opens = 0; scans = 0; }
int open_count(void) { return opens; }
int scan_count(void) { return scans; }
io_service_t IOServiceGetMatchingService(mach_port_t p, CFDictionaryRef d) { CFRelease(d); return 42; }
kern_return_t IOServiceOpen(io_service_t s, task_port_t t, uint32_t type, io_connect_t *c) {
    opens++;
    if (scenario == 1) return kIOReturnError;
    *c = 42; return KERN_SUCCESS;
}
kern_return_t IOServiceClose(io_connect_t c) { return KERN_SUCCESS; }
kern_return_t IOObjectRelease(io_object_t o) { return KERN_SUCCESS; }
static uint32_t code(const char *s) {
    return (uint32_t)s[0]<<24 | (uint32_t)s[1]<<16 | (uint32_t)s[2]<<8 | (uint32_t)s[3];
}
kern_return_t IOConnectCallStructMethod(mach_port_t c, uint32_t selector, const void *in,
                                      size_t insize, void *out, size_t *outsize) {
    if (insize != 80 || *outsize < 80 || selector != 2) return kIOReturnBadArgument;
    const unsigned char *i = in; unsigned char *o = out;
    uint32_t key, index;
    memcpy(&key, i, 4); memcpy(&index, i+44, 4);
    memset(o, 0, 80); *outsize = 80;
    if (i[42] == 5 && key == code("#KEY")) {
        scans++;
        if (scenario == 2) return kIOReturnError;
        o[51] = 5; return KERN_SUCCESS;
    }
    if (i[42] == 8 && index < 5) {
        if (scenario == 3 && index < 4) return kIOReturnError;
        // Every supported CPU map has at least one of these keys.
        const char *names[] = {"Tp01", "Tp00", "Te05", "Tg00", "TB0T"};
        key = code(scenario == 7 ? "ZZ00" : names[index]);
        memcpy(o, &key, 4); return KERN_SUCCESS;
    }
    if (i[42] == 9) {
        if ((scenario == 4 && key != code("TB0T"))
            || (scenario == 5 && key == code("Tg00"))
            || (scenario == 6 && key != code("Tg00"))) {
            o[40] = 132; return KERN_SUCCESS;
        }
        uint32_t size = 4, type = code("flt ");
        memcpy(o+28, &size, 4); memcpy(o+32, &type, 4); return KERN_SUCCESS;
    }
    if (i[42] == 5) {
        float value = key == code("Tg00") ? 46 : key == code("TB0T") ? 25 : 45;
        memcpy(o+48, &value, 4); return KERN_SUCCESS;
    }
    return kIOReturnBadArgument;
}
'''

harness = r'''
import Foundation
@_silgen_name("set_scenario") func setScenario(_ value: Int32)
@_silgen_name("reset_counts") func resetCounts()
@_silgen_name("open_count") func openCount() -> Int32
@_silgen_name("scan_count") func scanCount() -> Int32

struct PowerSampler { init(smc: SMCClient?) {} }
final class ReplayMonitor {
    private var smc: SMCClient?
    private var smcDiscoveryRetry = SensorDiscoveryRetry()
    private var temperatureDiscoveryRetry = SensorDiscoveryRetry()
    private var cpuKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var fanKeys: [SMCClient.Key] = []
    private var tempKeysPrepared = false
    private var fanKeysPrepared = false
    private var cpuTemperaturePlatform: CPUTemperaturePlatform = .generic
    private var powerSampler: PowerSampler?
    static let fanTelemetryCount = 0

    func prepare(now: TimeInterval, needed: Bool = true) {
        prepareIfNeeded(needSMC: needed, needTemperature: needed, needFanSpeed: false, now: now)
    }
    var values: [Double?] {
        [cpuTemperature(), maxTemperature(of: gpuKeys), maxTemperature(of: batteryKeys)]
    }
    // PRODUCTION_METHODS
}

@main struct SensorDiscoveryTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ label: String) {
        checks += 1
        guard condition else { fatalError(label) }
    }
    static func main() {
        setScenario(0)
        guard let client = SMCClient() else { fatalError("fake SMC did not open") }
        let healthy = client.discoverKeys { $0.hasPrefix("T") }
        expect(healthy.isComplete && healthy.keys.count == 5, "complete discovery finds every sensor")
        expect(healthy.keys.compactMap { client.readValue($0) } == [45, 45, 45, 46, 25],
               "the real SMC codec decodes CPU, GPU and battery wire values")
        for failure: Int32 in [2, 3, 4] {
            setScenario(failure)
            expect(!client.discoverKeys { $0.hasPrefix("T") }.isComplete,
                   "count, index and metadata errors remain distinguishable from missing hardware")
        }
        setScenario(0)
        let absent = client.discoverKeys { $0.hasPrefix("unrelated") }
        expect(absent.isComplete && absent.keys.isEmpty, "a complete scan can legitimately find no matching sensors")

        let wanted: [Double?] = [45, 46, 25]
        for failure: Int32 in 1...4 {
            resetCounts()
            setScenario(failure)
            let monitor = ReplayMonitor()
            monitor.prepare(now: 100, needed: false)
            expect(openCount() == 0 && scanCount() == 0, "disabled monitoring does no discovery")
            monitor.prepare(now: 100)
            expect(monitor.values[0] == nil && monitor.values[1] == nil,
                   "startup failure leaves CPU and GPU unavailable")
            if failure >= 3 {
                expect(monitor.values[2] == 25, "a partial scan preserves the battery reading")
            }
            let attempts = (openCount(), scanCount())
            setScenario(0)
            monitor.prepare(now: 104.9)
            expect(openCount() == attempts.0 && scanCount() == attempts.1,
                   "ordinary ticks cannot spin on a startup failure")
            monitor.prepare(now: 105)
            expect(monitor.values == wanted, "both chip temperatures return after the transport recovers")
            let completed = (openCount(), scanCount())
            monitor.prepare(now: 110)
            monitor.prepare(now: 10_000)
            expect(openCount() == completed.0 && scanCount() == completed.1,
                   "successful discovery is cached without further scans")
        }

        resetCounts()
        setScenario(5)
        let partial = ReplayMonitor()
        partial.prepare(now: 100)
        expect(partial.values == [45, nil, 25], "initial partial scan retains CPU and battery")
        setScenario(6)
        partial.prepare(now: 105)
        expect(partial.values == wanted, "a second partial scan adds GPU without losing earlier healthy sensors")
        setScenario(0)
        partial.prepare(now: 110)
        partial.prepare(now: 10_000)
        expect(partial.values == wanted && scanCount() == 3, "a complete third scan finishes discovery")

        for failure: Int32 in [1, 2, 4] {
            resetCounts()
            setScenario(failure)
            let unavailable = ReplayMonitor()
            for time in [100.0, 105.0, 110.0, 115.0, 10_000.0] { unavailable.prepare(now: time) }
            expect(failure == 1 ? openCount() == 3 : scanCount() == 3,
                   "permanent failures consume only three discovery attempts")
        }
        resetCounts()
        setScenario(7)
        let unsupported = ReplayMonitor()
        unsupported.prepare(now: 100)
        unsupported.prepare(now: 105)
        unsupported.prepare(now: 10_000)
        expect(unsupported.values == [nil, nil, nil] && scanCount() == 1,
               "absent sensors do not cause retries or fabricated temperatures")
        print("SENSOR DISCOVERY TESTS OK (\(checks) checks)")
    }
}
'''.replace("    // PRODUCTION_METHODS", methods)

with tempfile.TemporaryDirectory(prefix="vorssaint-sensor-tests-") as directory:
    temp = Path(directory)
    (temp / "transport.c").write_text(transport)
    (temp / "SensorDiscoveryTests.swift").write_text(harness)
    subprocess.run(["clang", "-isysroot", sdk, "-c", str(temp / "transport.c"),
                    "-o", str(temp / "transport.o")], check=True)
    subprocess.run([
        "swiftc", "-O", "-sdk", sdk,
        str(root / "Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift"),
        str(root / "Sources/Vorssaint/Services/FanControl/FanControlSupport.swift"),
        str(root / "Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift"),
        str(temp / "SensorDiscoveryTests.swift"), str(temp / "transport.o"),
        "-o", str(temp / "sensor-tests"),
    ], check=True)
    subprocess.run([str(temp / "sensor-tests")], check=True)
