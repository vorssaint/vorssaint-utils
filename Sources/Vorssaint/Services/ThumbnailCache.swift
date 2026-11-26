// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import ImageIO

/// The one downsample every thumbnail consumer goes through. Before this,
/// the clipboard and the window previews each built their own ImageIO options
/// and each decided its own bitmap cost; now one implementation defines both,
/// so a cache's byte budget counts the same pixels everywhere.
enum Downsampler {
    struct Thumbnail {
        let image: NSImage
        /// The decoded bitmap, for callers that need to re-wrap its size.
        let cgImage: CGImage
        /// Bytes the bitmap actually occupies; what caches account.
        let cost: Int
    }

    struct Bitmap {
        let image: CGImage
        let cost: Int
    }

    /// Decodes a file's first image no larger than `maxPixelSize` on its
    /// longest edge. Synchronous: callers keep it off the main thread.
    static func thumbnail(at url: URL, maxPixelSize: CGFloat) -> Thumbnail? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return thumbnail(source: source, maxPixelSize: maxPixelSize)
    }

    static func thumbnail(from data: Data, maxPixelSize: CGFloat) -> Thumbnail? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return thumbnail(source: source, maxPixelSize: maxPixelSize)
    }

    static func thumbnail(source: CGImageSource, maxPixelSize: CGFloat) -> Thumbnail? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Thumbnail(image: NSImage(cgImage: cgImage, size: .zero),
                         cgImage: cgImage,
                         cost: cost(of: cgImage))
    }

    /// The bitmap's real footprint. Derived from the decoded image rather than
    /// from a point size, so Retina and oversized thumbnails are not guessed.
    static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    /// Redraws an already-captured image into a bitmap this process owns,
    /// downscaling to `maxPixelSize` when the source is larger. Window-server,
    /// ScreenCaptureKit and Core Image captures are surface-backed by the
    /// system; caching one directly would pin that surface (and whatever the
    /// OS charges to it) for as long as the thumbnail lives, so capture caches
    /// only ever hold plain copies.
    static func bitmapCopy(of image: CGImage,
                           maxPixelSize: CGFloat = .greatestFiniteMagnitude) -> Bitmap {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxPixelSize / max(width, height, 1))
        let scaledWidth = max(1, Int(width * scale))
        let scaledHeight = max(1, Int(height * scale))
        guard let context = CGContext(data: nil,
                                      width: scaledWidth,
                                      height: scaledHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Bitmap(image: image, cost: cost(of: image)) }
        context.interpolationQuality = scale < 1 ? .high : .default
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(scaledWidth), height: CGFloat(scaledHeight)))
        guard let copy = context.makeImage() else { return Bitmap(image: image, cost: cost(of: image)) }
        return Bitmap(image: copy, cost: cost(of: copy))
    }

    /// Created with caching off: the downsample is the only thing worth
    /// keeping, and ImageIO's own cache would double the footprint.
    private static let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
}

/// A byte-budgeted thumbnail cache shared by every consumer that keeps
/// thumbnails. The budget is per instance — the clipboard keeps 32 MiB and the
/// window previews 64 MiB — but the accounting, the eviction and the off-main
/// decode lane are the same code.
final class ThumbnailCache<Key: Hashable, Value: AnyObject>: @unchecked Sendable {
    enum Eviction {
        /// The cache keeps itself inside its byte budget and count limit,
        /// dropping the least recently used entries.
        case automatic
        /// The owner knows which entries are still useful (a window parked in
        /// the Stage Manager strip cannot be recaptured), so it chooses the
        /// victims and the cache only tracks what they cost.
        case callerDriven
    }

    private struct Entry {
        let value: Value
        let cost: Int
        var stamp: UInt64
    }

    private let byteBudget: Int
    private let countLimit: Int
    private let eviction: Eviction
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var storedCost = 0
    private var clock: UInt64 = 0
    /// Decodes two at a time at most: a burst of new rows must not hold dozens
    /// of full-size images in memory at once, nor saturate every core.
    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.vorssaint.utils.thumbnail-decodes"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(byteBudget: Int, countLimit: Int = .max, eviction: Eviction = .automatic) {
        self.byteBudget = max(0, byteBudget)
        self.countLimit = max(1, countLimit)
        self.eviction = eviction
    }

    /// Bytes currently accounted. Exposed so the bound can be asserted rather
    /// than assumed.
    var cost: Int { lock.withLock { storedCost } }

    var count: Int { lock.withLock { entries.count } }

    var keys: Set<Key> { lock.withLock { Set(entries.keys) } }

    var costs: [Key: Int] { lock.withLock { entries.mapValues(\.cost) } }

    /// A synchronous lookup that only touches the lock and the dictionary:
    /// a hit never decodes, and a miss never blocks on a decode.
    func value(for key: Key) -> Value? {
        lock.withLock {
            guard var entry = entries[key] else { return nil }
            if eviction == .automatic {
                clock += 1
                entry.stamp = clock
                entries[key] = entry
            }
            return entry.value
        }
    }

    func contains(_ key: Key) -> Bool { lock.withLock { entries[key] != nil } }

    func cost(for key: Key) -> Int? { lock.withLock { entries[key]?.cost } }

    func insert(_ value: Value, cost: Int, for key: Key) {
        let cost = max(0, cost)
        lock.withLock {
            if let previous = entries.removeValue(forKey: key) { storedCost -= previous.cost }
            clock += 1
            entries[key] = Entry(value: value, cost: cost, stamp: clock)
            storedCost += cost
            guard eviction == .automatic else { return }
            evictIfNeeded()
        }
    }

    @discardableResult
    func removeValue(for key: Key) -> Value? {
        lock.withLock {
            guard let removed = entries.removeValue(forKey: key) else { return nil }
            storedCost -= removed.cost
            return removed.value
        }
    }

    func removeAll() {
        lock.withLock {
            entries.removeAll()
            storedCost = 0
        }
    }

    /// A hit answers at once. A miss runs `load` on the shared decode lane; a
    /// caller cancelled before its turn never decodes the image at all. The
    /// load owns its own ImageIO source, so nothing synchronous happens on the
    /// caller's thread.
    func value(for key: Key,
               load: @escaping () -> (value: Value, cost: Int)?) async -> Value? {
        if let cached = value(for: key) { return cached }
        let request = DecodeRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
                decodeQueue.addOperation {
                    guard !request.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    guard let loaded = load() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    self.insert(loaded.value, cost: loaded.cost, for: key)
                    continuation.resume(returning: loaded.value)
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    /// Must be called with `lock` held.
    private func evictIfNeeded() {
        // One entry always stays: an oversized thumbnail is still better than
        // re-decoding it on every draw.
        while entries.count > 1, entries.count > countLimit || storedCost > byteBudget {
            guard let victim = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key,
                  let removed = entries.removeValue(forKey: victim)
            else { break }
            storedCost -= removed.cost
        }
    }

    private final class DecodeRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
}
