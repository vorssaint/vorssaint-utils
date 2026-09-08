// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum NetworkMetricTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Network speed math

        let slow = NetworkCounters(received: 1000, sent: 500)
        let fast = NetworkCounters(received: 1000 + 2048, sent: 500 + 1024)
        let speed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 2)
        expectClose(speed.down, 1024, "down speed over 2s")
        expectClose(speed.up, 512, "up speed over 2s")

        let zeroElapsed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 0)
        expect(zeroElapsed.down == 0 && zeroElapsed.up == 0, "zero elapsed yields zero")

        // Counter reset (interface went down) must not produce a negative/huge spike.
        let afterReset = MetricFormat.netSpeed(previous: fast, current: slow, elapsed: 2)
        expect(afterReset.down == 0 && afterReset.up == 0, "counter reset yields zero")

        var networkFallback = NetworkCounterFallback()
        let firstFrozenDownload = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 500),
            current: NetworkCounters(received: 1_000, sent: 700)
        )
        expect(firstFrozenDownload.sampleProcesses && !firstFrozenDownload.useProcessDownload,
               "first frozen inbound sample primes the process fallback")
        let secondFrozenDownload = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 700),
            current: NetworkCounters(received: 1_000, sent: 900)
        )
        expect(secondFrozenDownload.sampleProcesses && secondFrozenDownload.useProcessDownload,
               "second frozen inbound sample activates the process fallback")
        let fallbackIdle = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 900),
            current: NetworkCounters(received: 1_000, sent: 900)
        )
        expect(fallbackIdle.sampleProcesses && fallbackIdle.useProcessDownload,
               "active fallback keeps sampling downloads even when upload is idle")
        let inboundRecovered = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 900),
            current: NetworkCounters(received: 1_100, sent: 950)
        )
        expect(!inboundRecovered.sampleProcesses && !inboundRecovered.useProcessDownload,
               "moving inbound counters restore the lightweight interface reader")
        _ = networkFallback.observe(
            previous: NetworkCounters(received: 1_100, sent: 950),
            current: NetworkCounters(received: 1_100, sent: 1_000)
        )
        let counterResetFallback = networkFallback.observe(
            previous: NetworkCounters(received: 1_100, sent: 1_000),
            current: NetworkCounters(received: 10, sent: 20)
        )
        expect(!counterResetFallback.sampleProcesses && !counterResetFallback.useProcessDownload,
               "interface counter resets clear fallback suspicion")

        let fallbackCounters = [
            NetworkCounters(received: 1_000, sent: 500),
            NetworkCounters(received: 1_000, sent: 700),
            NetworkCounters(received: 1_000, sent: 900),
            NetworkCounters(received: 1_200, sent: 1_000),
        ]
        let fallbackProcessSamples = [
            [NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 1_000, bytesOut: 500)],
            [NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 5_000, bytesOut: 700)],
        ]
        var fallbackCounterIndex = 0
        var fallbackProcessIndex = 0
        let fallbackSampler = NetworkSampler(counterReader: {
            defer { fallbackCounterIndex += 1 }
            return fallbackCounters[fallbackCounterIndex]
        }, processReader: {
            defer { fallbackProcessIndex += 1 }
            return fallbackProcessSamples[fallbackProcessIndex]
        })
        let fallbackBaseline = fallbackSampler.sample(now: 0)
        let fallbackProbe = fallbackSampler.sample(now: 2)
        let fallbackReading = fallbackSampler.sample(now: 4)
        let recoveredReading = fallbackSampler.sample(now: 6)
        expect(fallbackBaseline.downBytesPerSec == nil && fallbackBaseline.upBytesPerSec == nil,
               "network sampler first reading remains a baseline")
        expect(fallbackProbe.downBytesPerSec == 0 && fallbackProbe.upBytesPerSec == 100,
               "first frozen inbound sample keeps interface output while priming fallback")
        expectClose(fallbackReading.downBytesPerSec ?? -1, 2_000,
                    "network sampler replaces frozen interface download with process traffic")
        expectClose(fallbackReading.upBytesPerSec ?? -1, 100,
                    "network sampler keeps the lightweight interface upload counter")
        expect(fallbackReading.totalDown == 4_000 && fallbackReading.totalUp == 400,
               "network fallback accumulates process download and interface upload totals")
        expectClose(recoveredReading.downBytesPerSec ?? -1, 100,
                    "network sampler returns to interface download after counter recovery")
        expect(recoveredReading.totalDown == 4_200 && recoveredReading.totalUp == 500,
               "network totals continue across fallback recovery")
        expect(fallbackProcessIndex == 2,
               "network sampler invokes the process reader only for suspect interface samples")

        let intermittentCounters: [NetworkCounters?] = [
            nil,
            NetworkCounters(received: 1_000_000, sent: 500_000),
            NetworkCounters(received: 1_000_200, sent: 500_100),
            nil, nil,
            NetworkCounters(received: 1_000_800, sent: 500_400),
            nil,
            NetworkCounters(received: 2_000_000, sent: 900_000),
            NetworkCounters(received: 2_000_200, sent: 900_100),
            NetworkCounters(),
            NetworkCounters(received: 200, sent: 100),
        ]
        var intermittentCounterIndex = 0
        var unexpectedProcessReads = 0
        let intermittentSampler = NetworkSampler(counterReader: {
            defer { intermittentCounterIndex += 1 }
            return intermittentCounters[intermittentCounterIndex]
        }, processReader: {
            unexpectedProcessReads += 1
            return nil
        })
        let intermittentTimes: [TimeInterval] = [0, 1, 2, 3, 4, 5, 6, 20, 21, 22, 23]
        let expectedDownRates: [Double?] = [nil, nil, 200, nil, nil, 200, nil, nil, 200, 0, 200]
        let expectedDownTotals: [UInt64] = [0, 0, 200, 200, 200, 800, 800, 800, 1_000, 1_000, 1_200]
        for index in intermittentTimes.indices {
            let reading = intermittentSampler.sample(now: intermittentTimes[index])
            expect(reading.downBytesPerSec == expectedDownRates[index]
                    && reading.upBytesPerSec == expectedDownRates[index].map { $0 / 2 },
                   "network reading \(index) distinguishes unavailable counters from zero and averages short gaps")
            expect(reading.totalDown == expectedDownTotals[index]
                    && reading.totalUp == expectedDownTotals[index] / 2,
                   "network reading \(index) preserves totals through failures, long gaps and valid counter resets")
        }
        expect(unexpectedProcessReads == 0,
               "unavailable interface counters never trigger process sampling")

        SpeedTestTests.run { expect($0, $1) }

        let nettopCSV = """
        time,,bytes_in,bytes_out,
        08:31:45.865507,Codex (Service).78844,78288,477660,
        08:31:45.865507,codex.78880,3154372,13193590,
        time,,bytes_in,bytes_out,
        08:31:46.871245,Codex (Service).78844,416,98,
        08:31:46.871246,codex.78880,16245,20641,
        08:31:46.871247,launchd.1,0,0,
        """
        let nettopRows = NetworkProcessSupport.parseNettopCSV(nettopCSV)
        expect(nettopRows.count == 2,
               "nettop parser keeps only active rows from the final delta section")
        expect(nettopRows.first?.name == "Codex (Service)" && nettopRows.first?.pid == 78844,
               "nettop parser extracts process names containing spaces")
        expectClose(nettopRows.last?.bytesIn ?? -1, 16_245, "nettop parser reads numeric bytes in")
        expectClose(nettopRows.last?.bytesOut ?? -1, 20_641, "nettop parser reads numeric bytes out")

        var nettopStream = NetworkProcessDeltaStreamParser()
        let streamLines = [
            "time,,bytes_in,bytes_out,",
            "08:31:45.865507,Codex.78844,78288,477660,",
            "time,,bytes_in,bytes_out,",
            "08:31:46.871245,Codex.78844,416,98,",
            "08:31:46.871247,launchd.1,0,0,",
            "time,,bytes_in,bytes_out,",
        ]
        let streamedSections = streamLines.compactMap { nettopStream.consumeCSVLine($0) }
        expect(streamedSections.count == 1,
               "nettop stream parser skips the initial cumulative section")
        expect(streamedSections.first?.count == 1,
               "nettop stream parser emits only active rows from the first delta section")
        expectClose(streamedSections.first?.first?.bytesIn ?? -1, 416,
                    "nettop stream parser does not publish cumulative bytes")
        expect(NetworkProcessSupport.nettopArguments == ["-P", "-d", "-x", "-J", "bytes_in,bytes_out", "-L", "1", "-s", "1"],
               "nettop per-app sampling asks for one cumulative section and computes deltas in app")
        expect(NetworkProcessSupport.externalNettopArguments == ["-P", "-d", "-x", "-t", "external", "-J", "bytes_in,bytes_out", "-L", "1", "-s", "1"],
               "network fallback samples only external process traffic")
        let cappedProcess = BoundedProcessRunner.run(
            "/bin/sh", ["-c", "/usr/bin/yes x | /usr/bin/head -c 200000"],
            timeout: 2, maxOutputBytes: 1_024)
        expect(cappedProcess.status == 0 && cappedProcess.output.count == 1_024,
               "subprocess output is drained while retained memory stays bounded")
        let orphanStarted = Date()
        let orphanedPipe = BoundedProcessRunner.run(
            "/bin/sh", ["-c", "/bin/sleep 3 & /usr/bin/printf done"],
            timeout: 1, maxOutputBytes: 1_024)
        expect(orphanedPipe.status == 0
                && String(decoding: orphanedPipe.output, as: UTF8.self) == "done"
                && Date().timeIntervalSince(orphanStarted) < 1.5,
               "a child inheriting stdout cannot leave the subprocess reader blocked")
        let timeoutStarted = Date()
        let timedOutProcess = BoundedProcessRunner.run(
            "/bin/sleep", ["3"], timeout: 0.05, maxOutputBytes: 1_024)
        expect(timedOutProcess.timedOut && timedOutProcess.status == -1
                && Date().timeIntervalSince(timeoutStarted) < 1.5,
               "a stalled subprocess is terminated inside its deadline")

        // Reproduces the freeze in issue #971 from the other side: the app's
        // own abandoned waits had filled the shared dispatch pool, so nothing
        // submitted to it ran any more. A runner that waits on a pool thread
        // reports a timeout here for a command that exits instantly, and parks
        // one more worker doing it. Waiting on the child itself is immune, so
        // the pool the runner starved can no longer starve the runner.
        let poolGate = DispatchSemaphore(value: 0)
        // How many threads the pool lets block in synchronous work before it
        // stops serving anything follows the machine rather than a documented
        // number, so the blocks ramp until a probe submitted to the pool times
        // out. A fixed count leaves this check passing without ever reaching
        // the starvation it needs on a Mac whose ceiling is higher.
        var blockedWorkers = 0
        var poolIsStarved = false
        var starvedProbe: DispatchSemaphore?
        while !poolIsStarved && blockedWorkers < 256 {
            for _ in 0..<32 {
                blockedWorkers += 1
                DispatchQueue.global(qos: .utility).async { poolGate.wait() }
            }
            let probe = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async { probe.signal() }
            starvedProbe = probe
            poolIsStarved = probe.wait(timeout: .now() + 0.5) == .timedOut
        }
        let starvedStarted = Date()
        let starvedPoolProcess = BoundedProcessRunner.run(
            "/bin/echo", ["ready"], timeout: 1, maxOutputBytes: 1_024)
        let starvedPoolElapsed = Date().timeIntervalSince(starvedStarted)
        // One signal per block submitted, running or still queued, so the rest
        // of this file never runs against workers parked on the gate.
        for _ in 0..<blockedWorkers { poolGate.signal() }
        _ = starvedProbe?.wait(timeout: .now() + 5)
        expect(poolIsStarved,
               "the dispatch pool starvation this check needs was actually reached")
        expect(!starvedPoolProcess.timedOut && starvedPoolProcess.status == 0
                && String(decoding: starvedPoolProcess.output, as: UTF8.self) == "ready\n"
                && starvedPoolElapsed < 0.5,
               "a subprocess is watched off the dispatch pool, so a starved pool cannot strand it")

        var networkDelta = NetworkProcessDeltaTracker(maxGap: 10)
        let baselineNetwork = [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 1_000, bytesOut: 500),
            NetworkProcessSample(pid: 20, name: "Editor", bytesIn: 200, bytesOut: 300),
        ]
        expect(networkDelta.rates(from: baselineNetwork, now: 100).isEmpty,
               "network process delta primes the first cumulative sample")
        let rateNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 3_048, bytesOut: 1_524),
            NetworkProcessSample(pid: 20, name: "Editor", bytesIn: 200, bytesOut: 300),
        ], now: 102)
        expect(rateNetwork.count == 1 && rateNetwork.first?.pid == 10,
               "network process delta keeps only processes with traffic")
        expectClose(rateNetwork.first?.bytesIn ?? -1, 1_024,
                    "network process delta computes download bytes per second")
        expectClose(rateNetwork.first?.bytesOut ?? -1, 512,
                    "network process delta computes upload bytes per second")
        let resetNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 100, bytesOut: 50),
        ], now: 104)
        expect(resetNetwork.isEmpty,
               "network process delta treats counter resets as a fresh baseline")
        let staleNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 10_000, bytesOut: 10_000),
        ], now: 120)
        expect(staleNetwork.isEmpty,
               "network process delta treats long gaps as a fresh baseline")
        let renewedLease = NetworkProcessSamplingPolicy.renewedLease(now: 50)
        expect(NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: renewedLease, now: 61.9),
               "network monitoring lease remains active before expiry")
        expect(!NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: renewedLease, now: 62.0),
               "network monitoring lease expires exactly at the boundary")
        expectClose(NetworkProcessSamplingPolicy.shortenedLease(currentExpiresAt: 90, now: 50),
                    54,
                    "network monitoring stop shortens the lease instead of depending on balanced disappear events")

        expect(MonitorSamplingPolicy.sampleStride(for: .cpu, intervalSeconds: 2, foreground: false) == 1,
               "monitor CPU stays responsive in menu-bar-only mode")
        expect(MonitorSamplingPolicy.sampleStride(for: .disk, intervalSeconds: 2, foreground: false) == 5,
               "monitor disk sampling slows down in menu-bar-only mode without exceeding DiskSampler.maxGap")
        expect(MonitorSamplingPolicy.sampleStride(for: .peripheralBattery, intervalSeconds: 2, foreground: false) == 30,
               "monitor peripheral battery sampling is heavily throttled in menu-bar-only mode")
        expect(MonitorSamplingPolicy.sampleStride(for: .fanSpeed, intervalSeconds: 2, foreground: false) == 3,
               "fan speed refreshes without waking the monitor every base tick")
        expect(MonitorSamplingPolicy.sampleStride(for: .disk, intervalSeconds: 2, foreground: true) == 1,
               "monitor disk sampling stays live while the panel is open")
        expect(MonitorSamplingPolicy.shouldSample(.disk, tick: 4, intervalSeconds: 2, foreground: false) == false,
               "monitor skips heavy menu-bar-only ticks before the stride")
        expect(MonitorSamplingPolicy.shouldSample(.disk, tick: 5, intervalSeconds: 2, foreground: false),
               "monitor samples heavy menu-bar-only ticks at the stride")

        expect(MonitorSamplingPolicy.wakeTicks(for: [.cpu, .disk], intervalSeconds: 2, foreground: false) == 1,
               "monitor wakes every tick while an every-tick metric is on")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.temperature], intervalSeconds: 2, foreground: false) == 8,
               "monitor with only temperature wakes once per temperature stride")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.fanSpeed], intervalSeconds: 2, foreground: false) == 3,
               "monitor with only fan speed wakes once per fan stride")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.peripheralBattery], intervalSeconds: 2, foreground: false) == 30,
               "monitor with only peripheral battery wakes once per minute")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.disk, .peripheralBattery], intervalSeconds: 2, foreground: false) == 5,
               "monitor wake cadence is the GCD of the needed strides")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.temperature], intervalSeconds: 2, foreground: true) == 1,
               "monitor wakes every tick in the foreground")
        expect(MonitorSamplingPolicy.wakeTicks(for: [], intervalSeconds: 2, foreground: false) == 1,
               "monitor wake cadence defaults to every tick with no needs")
        // Exactness invariant: the cadence always divides every needed stride,
        // so grid-aligned ticks keep hitting each stride exactly on schedule.
        let wakeKinds: [MonitorSamplingKind] = [.disk, .power, .gpuUsage, .temperature,
                                                .fanSpeed, .peripheralBattery]
        let cadence = MonitorSamplingPolicy.wakeTicks(for: wakeKinds, intervalSeconds: 2, foreground: false)
        expect(wakeKinds.allSatisfy {
            MonitorSamplingPolicy.sampleStride(for: $0, intervalSeconds: 2, foreground: false) % cadence == 0
        }, "monitor wake cadence divides every needed stride")
        expect(MonitorSamplingPolicy.alignedTick(16, wakeTicks: 8) == 16,
               "monitor tick already on the wake grid stays put")
        expect(MonitorSamplingPolicy.alignedTick(7, wakeTicks: 8) == 8,
               "monitor tick off the wake grid realigns to the next slot")
        expect(MonitorSamplingPolicy.alignedTick(9, wakeTicks: 1) == 9,
               "monitor tick needs no alignment at every-tick cadence")

        // MARK: Interface filtering

        expect(MetricFormat.includeNetworkInterface("en0"), "en0 included")
        expect(MetricFormat.includeNetworkInterface("en12"), "en12 included")
        expect(!MetricFormat.includeNetworkInterface("lo0"), "lo0 excluded")
        expect(!MetricFormat.includeNetworkInterface("awdl0"), "awdl0 excluded")
        expect(!MetricFormat.includeNetworkInterface("nan0"), "nan0 excluded")
        expect(!MetricFormat.includeNetworkInterface("utun3"), "utun3 (VPN) excluded")
        expect(!MetricFormat.includeNetworkInterface("bridge0"), "bridge0 excluded")
        expect(!MetricFormat.includeNetworkInterface(""), "empty excluded")

        // MARK: History ring buffer

        var history = MetricHistory(capacity: 3)
        history.push(1)
        history.push(2)
        expect(history.values == [1, 2], "history keeps order under capacity")
        history.push(3)
        history.push(4)
        expect(history.values == [2, 3, 4], "history drops oldest at capacity")
        expect(history.values.count == 3, "history never exceeds capacity")
        expect(history.publishedValues(whileVisible: false).isEmpty
                && history.values == [2, 3, 4]
                && history.publishedValues(whileVisible: true) == [2, 3, 4],
               "hidden graphs publish no arrays without discarding their ring")

        var single = MetricHistory(capacity: 1)
        single.push(5)
        single.push(6)
        expect(single.values == [6], "capacity 1 keeps only newest")
    }
}
