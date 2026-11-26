// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// The shared thumbnail pipeline: a cache hit must never decode again, the
/// byte budget must actually bound what is retained, and the off-main load
/// must count a decode exactly once per miss.
enum ThumbnailCacheTests {
    private final class Box {}

    static func run(_ suite: TestSuite) {
        hitsDoNotDecode(suite)
        byteBudgetEvictsLeastRecentlyUsed(suite)
        callerDrivenEvictionLeavesTheChoiceToTheOwner(suite)
        asyncMissDecodesOnceAndThenHits(suite)
        benchmark(suite)
    }

    private static func hitsDoNotDecode(_ suite: TestSuite) {
        let cache = ThumbnailCache<String, Box>(byteBudget: 1024 * 1024)
        var decodes = 0
        func decode() -> Box {
            decodes += 1
            return Box()
        }
        let first = decode()
        cache.insert(first, cost: 100, for: "key")
        for _ in 0..<10 {
            suite.expect(cache.value(for: "key") === first, "a hit returns the cached instance")
        }
        suite.expect(decodes == 1, "one decode built the image; ten lookups reused it")
        suite.expect(cache.cost == 100, "lookups do not change the accounted cost")
    }

    private static func byteBudgetEvictsLeastRecentlyUsed(_ suite: TestSuite) {
        let cache = ThumbnailCache<String, Box>(byteBudget: 300)
        let a = Box(), b = Box(), c = Box()
        cache.insert(a, cost: 100, for: "a")
        cache.insert(b, cost: 100, for: "b")
        cache.insert(c, cost: 100, for: "c")
        suite.expect(cache.cost == 300, "the cache may hold exactly its budget")
        _ = cache.value(for: "a") // touch: "b" becomes the least recent
        let d = Box()
        cache.insert(d, cost: 100, for: "d")
        suite.expect(cache.cost <= 300, "the budget is enforced after an insert")
        suite.expect(cache.value(for: "b") == nil, "the least recently used entry was evicted")
        suite.expect(cache.value(for: "a") === a && cache.value(for: "c") === c,
                     "recently used entries survive")
        suite.expect(cache.value(for: "d") === d, "the newest entry is retained")
        cache.removeAll()
        suite.expect(cache.cost == 0 && cache.count == 0, "removeAll clears the accounting")
    }

    private static func callerDrivenEvictionLeavesTheChoiceToTheOwner(_ suite: TestSuite) {
        let cache = ThumbnailCache<String, Box>(byteBudget: 100, eviction: .callerDriven)
        cache.insert(Box(), cost: 80, for: "a")
        cache.insert(Box(), cost: 80, for: "b")
        suite.expect(cache.count == 2 && cache.cost == 160,
                     "a caller-driven cache reports over-budget cost instead of choosing victims")
        suite.expect(cache.costs == ["a": 80, "b": 80], "costs are exposed for the owner's policy")
        cache.removeValue(for: "a")
        suite.expect(cache.cost == 80, "removing an entry releases its bytes")
    }

    private static func asyncMissDecodesOnceAndThenHits(_ suite: TestSuite) {
        let cache = ThumbnailCache<String, Box>(byteBudget: 1024 * 1024)
        let decodes = LockedCounter()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let miss = await cache.value(for: "key") {
                decodes.increment()
                let box = Box()
                return (value: box, cost: 64)
            }
            let hit = await cache.value(for: "key") {
                decodes.increment()
                return (value: Box(), cost: 64)
            }
            suite.expect(miss != nil && hit === miss,
                         "the async path returns the cached instance on a hit")
            semaphore.signal()
        }
        suite.expect(semaphore.wait(timeout: .now() + 5) == .success, "the async load completes")
        suite.expect(decodes.value == 1, "a miss decodes once and the hit decodes nothing")
        suite.expect(cache.cost == 64, "the async miss accounts the loader's cost once")
    }

    private static func benchmark(_ suite: TestSuite) {
        guard let directory = makeImages(count: 100, width: 800, height: 600) else {
            suite.expect(false, "the benchmark fixture writes its images")
            return
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = (0..<100).map { directory.appendingPathComponent("image-\($0).png") }
        let budget = 32 * 1024 * 1024
        let cache = ThumbnailCache<String, NSImage>(byteBudget: budget)
        var decodes = 0

        let coldStart = ProcessInfo.processInfo.systemUptime
        for url in urls {
            let key = url.lastPathComponent
            guard let thumbnail = Downsampler.thumbnail(at: url, maxPixelSize: 480) else { continue }
            decodes += 1
            cache.insert(thumbnail.image, cost: thumbnail.cost, for: key)
        }
        let cold = ProcessInfo.processInfo.systemUptime - coldStart

        let warmStart = ProcessInfo.processInfo.systemUptime
        var hits = 0
        for url in urls where cache.value(for: url.lastPathComponent) != nil {
            hits += 1
        }
        let warm = ProcessInfo.processInfo.systemUptime - warmStart

        suite.expect(decodes == 100, "a cold pass decodes each image once")
        suite.expect(hits == cache.count, "every retained entry answers from the cache")
        suite.expect(hits > 0, "the cold pass retained thumbnails to hit")
        suite.expect(warm < cold, "cache hits are faster than decoding")
        suite.expect(cache.cost <= budget, "the retained bytes stay inside the budget")
        print(String(format: "thumbnail benchmark: cold %.3fs (%d decodes), warm %.4fs (%d hits), "
                        + "%d bytes accounted, %d entries",
                     cold, decodes, warm, hits, cache.cost, cache.count))
    }

    private static func makeImages(count: Int, width: Int, height: Int) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true))
        != nil else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        for index in 0..<count {
            context.setFillColor(CGColor(red: CGFloat(index % 7) / 7,
                                         green: CGFloat(index % 5) / 5,
                                         blue: CGFloat(index % 3) / 3,
                                         alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            for step in 0..<20 {
                context.fill(CGRect(x: step * 37, y: step * 23, width: 120, height: 80))
            }
            guard let image = context.makeImage() else { return nil }
            let url = directory.appendingPathComponent("image-\(index).png")
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
        }
        return directory
    }

    private final class LockedCounter {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }
}
