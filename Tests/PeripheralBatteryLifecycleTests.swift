// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PeripheralBatteryLifecycleTests {
    private final class Reader: PeripheralBluetoothReading {
        let cancellation: BoundedProcessCancellation
        let completion: ([BluetoothBatteryReading]) -> Void
        var starts = 0
        var cancels = 0
        init(cancellation: BoundedProcessCancellation, completion: @escaping ([BluetoothBatteryReading]) -> Void) {
            self.cancellation = cancellation
            self.completion = completion
        }
        func start() { starts += 1 }
        func cancel() { cancels += 1 }
        // Deliberately misbehave after cancellation to exercise the real sampler's guard.
        func emit(_ percent: Int) {
            completion([BluetoothBatteryReading(id: "fixture", name: "Keyboard", percent: percent)])
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        freshness(expect: expect)
        cachedSources(expect: expect)
        cancellation(expect: expect)
        cancelledProfiler(expect: expect)
        cancelledFastRead(expect: expect)
        processCancellation(expect: expect)
    }

    private static func device(_ percent: Int, id: String = "HID:fixture") -> PeripheralBatteryDevice {
        PeripheralBatteryDevice(id: id, name: "Keyboard", percent: percent, kind: .keyboard)
    }

    private static func sample(_ percent: Int, at observedAt: TimeInterval, id: String = "HID:fixture") -> PeripheralBatterySample {
        PeripheralBatterySample(devices: [device(percent, id: id)], observedAt: [id: observedAt])
    }

    private static func freshness(expect: (Bool, String) -> Void) {
        var state = NotchAccessoryBatteryState()
        expect(state.consume(sample(35, at: 1), observedAfter: 10).isEmpty,
               "a previously high snapshot cannot establish the new accessory baseline")
        expect(state.consume(sample(35, at: 1), observedAfter: 10).isEmpty,
               "republishing a cache cannot turn it into a new reading")
        expect(state.consume(sample(19, at: 11), observedAfter: 10).isEmpty,
               "cache 35 then first actual 19 starts a silent low episode")
        expect(state.consume(sample(35, at: 1), observedAfter: 10).isEmpty
               && state.consume(sample(18, at: 12), observedAfter: 10).isEmpty,
               "an older high value cannot rearm an established low episode")
        expect(state.consume(sample(25, at: 13), observedAfter: 10).isEmpty,
               "a fresh recovery rearms without warning")
        expect(state.consume(sample(20, at: 14), observedAfter: 10).count == 1,
               "a later observed fall after the fresh baseline warns exactly once")
        expect(state.consume(sample(20, at: 14), observedAfter: 10).isEmpty,
               "a repeated fresh snapshot does not replay its alert")
        expect(state.consume(sample(35, at: 19), observedAfter: 20).isEmpty
               && state.consume(sample(15, at: 21, id: "Bluetooth:fixture"), observedAfter: 20).isEmpty,
               "suspension keeps the low episode while ignoring caches from before resumption")
        _ = state.consume(sample(30, at: 22), observedAfter: 20)
        expect(state.consume(sample(20, at: 23), observedAfter: 20).count == 1,
               "a measured recharge after resumption allows the next real fall")
        var freshHigh = NotchAccessoryBatteryState()
        _ = freshHigh.consume(sample(35, at: 10), observedAfter: 10)
        expect(freshHigh.consume(sample(19, at: 20), observedAfter: 19).count == 1,
               "sleep preserves a genuinely established high baseline too")
    }

    private static func cachedSources(expect: (Bool, String) -> Void) {
        let queue = DispatchQueue(label: "com.vorssaint.tests.battery-cache")
        var clock: TimeInterval = 1
        var fast: [PeripheralBatteryDevice] = []
        var readers: [Reader] = [] // Access only while the serial queue is drained or inside it.
        let sampler = PeripheralBatterySampler(bluetoothQueue: queue, readFast: { fast },
            readProfiler: { _ in Data() }, makeBluetoothRead: { _, cancellation, completion in
                let reader = Reader(cancellation: cancellation, completion: completion)
                readers.append(reader)
                return reader
            }, currentTime: { clock })
        defer { sampler.setEnabled(false); queue.sync {} }
        sampler.setEnabled(true)
        _ = sampler.sample(now: clock)
        queue.sync { readers[0].emit(35) }
        let cached = sampler.sample(now: clock)
        expect(cached.devices.first?.percent == 35
               && cached.observedAt["BluetoothGATT:fixture"] == 1,
               "the sampler attaches the Bluetooth observation time")
        clock = 20
        fast = [PeripheralBatteryDevice(id: "HID:mouse", name: "Mouse", percent: 60, kind: .mouse)]
        let mixed = sampler.sample(now: clock)
        expect(mixed.observedAt["HID:mouse"] == 20
               && mixed.observedAt["BluetoothGATT:fixture"] == 1,
               "a new HID read cannot refresh the age of cached Bluetooth data")
        var state = NotchAccessoryBatteryState()
        _ = state.consume(mixed, observedAfter: 10)
        clock = 302
        _ = sampler.sample(now: clock)
        queue.sync { readers[1].emit(19) }
        let actual = sampler.sample(now: clock)
        expect(state.consume(actual, observedAfter: 10).isEmpty,
               "the production sampler's old Bluetooth 35 then actual 19 is silent on first observation")
        expect(actual.observedAt["BluetoothGATT:fixture"] == 302,
               "the completed refresh supplies its own observation time")
        clock = 303
        expect(sampler.sample(now: clock).observedAt == actual.observedAt,
               "the fast cache preserves source timestamps exactly")
    }

    private static func cancellation(expect: (Bool, String) -> Void) {
        let queue = DispatchQueue(label: "com.vorssaint.tests.battery-cancel")
        var readers: [Reader] = []
        let sampler = PeripheralBatterySampler(bluetoothQueue: queue, readFast: { [] },
            readProfiler: { _ in Data() }, makeBluetoothRead: { _, cancellation, completion in
                let reader = Reader(cancellation: cancellation, completion: completion)
                readers.append(reader)
                return reader
            }, currentTime: { 1 })
        sampler.setEnabled(true)
        _ = sampler.sample(now: 0)
        queue.sync {}
        expect(readers.count == 1 && readers[0].starts == 1, "one active consumer starts one Bluetooth reader")
        sampler.setEnabled(true)
        _ = sampler.sample(now: 1)
        queue.sync {}
        expect(readers[0].cancels == 0 && !readers[0].cancellation.isCancelled && readers.count == 1,
               "remaining shared demand preserves the existing reader without starting a second one")
        sampler.setEnabled(false)
        queue.sync {}
        expect(readers[0].cancels == 1 && readers[0].cancellation.isCancelled,
               "losing the last consumer cancels the owned reader and its request")
        queue.sync { readers[0].emit(10) }
        expect(sampler.sample(now: 2).devices.isEmpty, "a late callback cannot publish while observation is off")
        sampler.setEnabled(true)
        _ = sampler.sample(now: 3)
        queue.sync { readers[0].emit(99) }
        expect(readers.count == 2 && sampler.sample(now: 3).devices.isEmpty,
               "a cancelled generation cannot contaminate a newly enabled reader")
        sampler.setEnabled(false)
        sampler.setEnabled(true)
        _ = sampler.sample(now: 4)
        queue.sync { readers[1].emit(99); readers[2].emit(19) }
        expect(readers.count == 3 && readers[1].cancels == 1
               && readers[2].starts == 1 && readers[2].cancels == 0,
               "rapidly disabling and reenabling cannot apply old cleanup to the new reader")
        expect(sampler.sample(now: 4).devices.first?.percent == 19,
               "only the replacement generation can supply the final battery value")
        sampler.setEnabled(false)
        queue.sync {}
    }

    private static func cancelledProfiler(expect: (Bool, String) -> Void) {
        let queue = DispatchQueue(label: "com.vorssaint.tests.battery-profiler")
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        var readers = 0
        var capturedRequest: BoundedProcessCancellation?
        let sampler = PeripheralBatterySampler(bluetoothQueue: queue, readFast: { [] },
            readProfiler: { request in
                capturedRequest = request
                entered.signal()
                _ = release.wait(timeout: .now() + 3)
                return Data()
            }, makeBluetoothRead: { _, cancellation, completion in
                readers += 1
                return Reader(cancellation: cancellation, completion: completion)
            })
        sampler.setEnabled(true)
        _ = sampler.sample(now: 0)
        let didEnter = entered.wait(timeout: .now() + 2) == .success
        sampler.setEnabled(false)
        release.signal()
        queue.sync {}
        expect(didEnter && capturedRequest?.isCancelled == true,
               "disabling during the profiler phase cancels that pending request")
        expect(readers == 0, "a profiler result arriving after disable cannot create Bluetooth connections")
    }

    private static func cancelledFastRead(expect: (Bool, String) -> Void) {
        let queue = DispatchQueue(label: "com.vorssaint.tests.battery-fast-read")
        var sampler: PeripheralBatterySampler!
        sampler = PeripheralBatterySampler(bluetoothQueue: queue, readFast: {
            sampler.setEnabled(false)
            return [device(19)]
        }, readProfiler: { _ in Data() }, makeBluetoothRead: { _, cancellation, completion in
            Reader(cancellation: cancellation, completion: completion)
        })
        sampler.setEnabled(true)
        expect(sampler.sample(now: 0).devices.isEmpty, "a fast read finishing after disable cannot repopulate the cache")
        queue.sync {}
        sampler = nil
    }

    private static func processCancellation(expect: (Bool, String) -> Void) {
        let cancelled = BoundedProcessCancellation()
        cancelled.cancel()
        let skipped = BoundedProcessRunner.run("/usr/bin/printf", ["unexpected"], timeout: 1,
                                               maxOutputBytes: 32, cancellation: cancelled)
        expect(skipped.status == -1 && skipped.output.isEmpty, "a cancelled queued process is never launched")
        let running = BoundedProcessCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { running.cancel() }
        let stopped = BoundedProcessRunner.run("/bin/sleep", ["30"], timeout: 5,
                                               maxOutputBytes: 0, cancellation: running)
        expect(running.isCancelled && !stopped.timedOut && stopped.status != 0,
               "cancellation terminates an active process without waiting for its normal timeout")
    }
}
