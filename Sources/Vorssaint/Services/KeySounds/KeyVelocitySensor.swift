// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook's built-in accelerometer (Apple SPU, vendor page 0xFF00,
/// usage 3, ~800 Hz, 22-byte reports with Int32 X/Y/Z at 6/10/14 in 1/65536 g)
/// and answers "how big was the jolt around this moment?". Works unprivileged.
final class KeyVelocitySensor {
    enum State: Equatable { case off, running, unavailable }

    private(set) var state: State = .off

    private let lock = NSLock()
    private let capacity = 2048               // ~2.5 s at 800 Hz
    private var times = [UInt64](repeating: 0, count: 2048)
    private var jolts = [Double](repeating: 0, count: 2048)
    private var head = 0
    private var count = 0
    private var last: (Double, Double, Double)?
    private var noiseFloor = 0.0004

    private var device: IOHIDDevice?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    deinit { reportBuffer.deallocate() }

    static var isPresent: Bool {
        guard let service = service(of: "AppleSPUHIDDevice") else { return false }
        IOObjectRelease(service)
        return true
    }

    func start() {
        guard state != .running else { return }
        guard let service = Self.service(of: "AppleSPUHIDDevice"),
              let dev = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
            state = .unavailable
            return
        }
        IOObjectRelease(service)
        if let driver = Self.service(of: "AppleSPUHIDDriver") {
            for (key, value) in [("SensorPropertyReportingState", 1),
                                 ("SensorPropertyPowerState", 1),
                                 ("ReportInterval", 1000)] {
                _ = IORegistryEntrySetCFProperty(driver, key as CFString, value as CFNumber)
            }
            IOObjectRelease(driver)
        }
        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            state = .unavailable
            return
        }
        device = dev
        state = .running
        lock.withLock { count = 0; head = 0; last = nil }

        let thread = Thread { [weak self] in self?.runReports(dev) }
        thread.name = "Vorssaint Key Sounds Accelerometer"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard let dev = device else { state = .off; return }
        let loop: CFRunLoop? = lock.withLock {
            defer { runLoop = nil; device = nil }
            return runLoop
        }
        if let runLoop = loop {
            // Tear down on the report thread so no callback races the close.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        } else {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        thread = nil
        state = .off
    }

    /// Largest jolt above the resting noise in [time - before, time + after].
    func peak(around time: UInt64, beforeMs: Double = 10, afterMs: Double = 25) -> Double? {
        lock.withLock {
            guard state == .running, count > 0 else { return nil }
            let lo = time &- UInt64(beforeMs * 1_000_000)
            let hi = time &+ UInt64(afterMs * 1_000_000)
            var best = 0.0
            var i = head
            for _ in 0..<count {
                i = (i - 1 + capacity) % capacity
                let t = times[i]
                if t < lo { break }
                if t <= hi { best = max(best, jolts[i]) }
            }
            return max(0, best - noiseFloor)
        }
    }

    private func runReports(_ dev: IOHIDDevice) {
        let stillWanted = lock.withLock { () -> Bool in
            guard device === dev else { return false }
            runLoop = CFRunLoopGetCurrent()
            return true
        }
        guard stillWanted else { return }
        IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, 64, { ctx, _, _, _, _, report, length in
            guard let ctx, length >= 18 else { return }
            let me = Unmanaged<KeyVelocitySensor>.fromOpaque(ctx).takeUnretainedValue()
            func axis(_ o: Int) -> Double {
                let raw = UInt32(report[o]) | UInt32(report[o + 1]) << 8
                    | UInt32(report[o + 2]) << 16 | UInt32(report[o + 3]) << 24
                return Double(Int32(bitPattern: raw)) / 65536
            }
            me.record(axis(6), axis(10), axis(14))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRun()
    }

    private func record(_ x: Double, _ y: Double, _ z: Double) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            defer { last = (x, y, z) }
            guard let (px, py, pz) = last else { return }
            let jolt = ((x - px) * (x - px) + (y - py) * (y - py) + (z - pz) * (z - pz)).squareRoot()
            // Slow noise estimate that ignores key hits.
            if jolt < noiseFloor * 3 { noiseFloor += (jolt - noiseFloor) * 0.002 }
            times[head] = now
            jolts[head] = jolt
            head = (head + 1) % capacity
            count = min(count + 1, capacity)
        }
    }

    private static func service(of className: String) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            if intProperty(service, "PrimaryUsagePage") == 0xFF00, intProperty(service, "PrimaryUsage") == 3 {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}
