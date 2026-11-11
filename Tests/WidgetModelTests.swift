// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Exercises the snapshot, formatting and activity rules the app and its
/// WidgetKit extension share. No widget is installed and no container is read.
enum WidgetModelTests {
    static func run(_ suite: TestSuite) {
        let preview = WidgetSnapshot.preview
        for kind in VorssaintWidgetKind.readings {
            suite.expect(preview.hasReading(for: kind),
                         "the gallery preview carries a \(kind.rawValue) reading")
        }
        suite.expect(VorssaintWidgetKind.readings.count == 5
                         && !VorssaintWidgetKind.readings.contains(.united),
                     "only the five single-metric kinds need a sampler")

        let empty = WidgetSnapshot(capturedAt: Date())
        suite.expect(!empty.hasReading(for: .united),
                     "a snapshot without readings has no United reading to show")
        let networkOnly = WidgetSnapshot(capturedAt: Date(), network: preview.network)
        suite.expect(networkOnly.hasReading(for: .network) && !networkOnly.hasReading(for: .united),
                     "the United widget combines CPU, GPU, memory and disk, not the network card")

        let placeholder = WidgetSnapshot.placeholder
        for kind in VorssaintWidgetKind.allCases {
            suite.expect(placeholder.hasReading(for: kind),
                         "the placeholder gives the \(kind.rawValue) widget an empty reading")
        }
        suite.expect(placeholder.cpu == .empty && placeholder.gpu == .empty
                         && placeholder.memory == .empty && placeholder.disk == .empty
                         && placeholder.network == .empty,
                     "every placeholder reading is the shared empty value")
        suite.expect(WidgetMemoryReading.empty.usedFraction == 0
                         && WidgetDiskReading.empty.usedFraction == 0
                         && WidgetNetworkReading.empty.downText == "0 B/s",
                     "empty readings render zeroed gauges and values")

        let moment = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let encoded = try? JSONEncoder().encode(WidgetSnapshot(
            capturedAt: moment, cpu: preview.cpu, gpu: preview.gpu,
            memory: preview.memory, disk: preview.disk, network: preview.network))
        let decoded = encoded.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        suite.expect(decoded?.capturedAt == moment && decoded?.cpu == preview.cpu
                         && decoded?.gpu == preview.gpu && decoded?.memory == preview.memory
                         && decoded?.disk == preview.disk && decoded?.network == preview.network,
                     "a snapshot survives the trip from the app to the extension unchanged")

        let memory = WidgetMemoryReading(used: 3_000, total: 10_000, app: 1_000, pressureLevel: 1)
        suite.expectClose(memory.usedFraction, 0.3, "memory fills a third of the donut")
        suite.expect(memory.free == 7_000, "memory reports its free bytes")
        let fullMemory = WidgetMemoryReading(used: 12_000, total: 10_000, app: 0, pressureLevel: 2)
        suite.expect(fullMemory.usedFraction == 1 && fullMemory.free == 0,
                     "a changed total never pushes the memory donut past full or free below zero")
        let noMemory = WidgetMemoryReading(used: 1, total: 0, app: 0, pressureLevel: 0)
        suite.expect(noMemory.usedFraction == 0, "an unknown memory total reads as empty")

        let disk = WidgetDiskReading(used: 250, free: 750, total: 1_000)
        suite.expectClose(disk.usedFraction, 0.25, "disk fills a quarter of the donut")
        suite.expect(WidgetDiskReading(used: 1, free: 0, total: 0).usedFraction == 0,
                     "an unknown disk total reads as empty")

        suite.expect(WidgetFormat.percent(0.345) == "35%", "percent rounds to the nearest whole number")
        suite.expect(WidgetFormat.percent(-1) == "0%" && WidgetFormat.percent(2) == "100%",
                     "percent clamps to the donut's range")
        suite.expect(WidgetFormat.percent(.infinity) == "0%"
                         && WidgetFormat.percent(.nan) == "0%",
                     "a broken reading reads as zero instead of crashing")
        suite.expect(WidgetFormat.bytes(0) == "0 B", "zero bytes keep the byte unit")
        suite.expect(WidgetFormat.bytes(15 * 1024) == "15 KB",
                     "byte sizes step by 1024 like the monitor's readouts")
        suite.expect(WidgetFormat.bytes(15 * 1024 * 1024) == "15 MB",
                     "megabytes follow the same 1024 steps")
        suite.expect(WidgetFormat.rate(0, inBits: false) == "0 B/s"
                         && WidgetFormat.rate(-5, inBits: true) == "0 bps"
                         && WidgetFormat.rate(.nan, inBits: false) == "0 B/s",
                     "a missing transfer reads as zero in its chosen unit")
        suite.expect(WidgetFormat.rate(12 * 1024 * 1024, inBits: false) == "12 MB/s",
                     "byte rates step by 1024 and end in per second")
        suite.expect(WidgetFormat.rate(1_500_000, inBits: true) == "12 Mbps",
                     "bit rates step by 1000 like a link speed")
        let bits = WidgetNetworkReading(downBytesPerSec: 1_500_000, upBytesPerSec: 0,
                                        isConnected: true, usesBits: true,
                                        interfaceName: "Wi-Fi", localAddress: nil)
        suite.expect(bits.downText == "12 Mbps" && bits.upText == "0 bps",
                     "the network card follows the menu bar's bit preference")

        let now: TimeInterval = 1_000_000
        suite.expect(!WidgetSharedData.isRecentlyRequested(0, now: now),
                     "a kind that never asked for a timeline is inactive")
        suite.expect(WidgetSharedData.isRecentlyRequested(now - 89, now: now),
                     "a heartbeat inside the window keeps the monitor sampling")
        suite.expect(!WidgetSharedData.isRecentlyRequested(now - 90, now: now),
                     "a heartbeat exactly at the window's edge no longer counts")
        suite.expect(WidgetSharedData.isRecentlyRequested(now + 5, now: now),
                     "a heartbeat from a clock running slightly ahead stays active")
    }
}
