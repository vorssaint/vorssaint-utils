// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Collects the real pointer images while a recording runs.
///
/// The recording is captured with the system pointer switched off so the
/// editor can smooth it, which means the pointer in the video has to be drawn,
/// and it has to be the pointer the person actually saw: the arrow, but also
/// the I-beam over text, the hand over a link and the resize arrows at a
/// window edge.
///
/// Three measured facts shape all of this. Asking the window server which
/// pointer is current costs about 2 nanoseconds, so that is the gate. Asking
/// it for the pixels costs about 22 microseconds, so that happens only when
/// the gate says the shape changed. And the identity it hands out is NOT
/// stable: setting the same arrow again produces a different number every
/// time, so shapes are keyed by what they look like, never by that number.
final class RecorderCursorCatalog {

    struct Shape {
        let image: CGImage
        /// Size in the pointer bitmap's own pixels, which is also its size in
        /// screen POINTS: the window server vends the base representation and
        /// draws it one bitmap pixel per point.
        let size: CGSize
        /// Where inside it the pointer points, in the same units.
        let hotSpot: CGPoint
    }

    private let lock = NSLock()
    private var shapes: [UInt64: Shape] = [:]
    private var order: [UInt64] = []
    private var upgraded: Set<UInt64> = []

    /// The pointer size the window server itself is applying. Read once, and
    /// used instead of the accessibility preference: whichever way the system
    /// implements a large pointer, this number is already correct, and
    /// multiplying the two would double count.
    private(set) var systemScale: Double = 1

    let isAvailable: Bool

    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias SeedFunction = @convention(c) () -> Int32
    private typealias VisibleFunction = @convention(c) () -> Bool
    private typealias ScaleFunction = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SizeFunction = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias DataFunction = @convention(c) (
        Int32, UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>,
        UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<Int32>,
        UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    private let seedFunction: SeedFunction?
    private let visibleFunction: VisibleFunction?
    private let sizeFunction: SizeFunction?
    private let dataFunction: DataFunction?
    private let connection: Int32

    init() {
        // dlsym rather than a link: none of this is published, so a macOS that
        // stops vending it has to degrade quietly instead of failing to launch.
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                            RTLD_LAZY)
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            guard let handle else { return nil }
            return dlsym(handle, name)
        }
        seedFunction = symbol("CGSCurrentCursorSeed").map {
            unsafeBitCast($0, to: SeedFunction.self)
        }
        visibleFunction = symbol("CGCursorIsVisible").map {
            unsafeBitCast($0, to: VisibleFunction.self)
        }
        sizeFunction = symbol("CGSGetGlobalCursorDataSize").map {
            unsafeBitCast($0, to: SizeFunction.self)
        }
        dataFunction = symbol("CGSGetGlobalCursorData").map {
            unsafeBitCast($0, to: DataFunction.self)
        }
        connection = symbol("CGSMainConnectionID").map {
            unsafeBitCast($0, to: ConnectionFunction.self)()
        } ?? 0
        isAvailable = seedFunction != nil && sizeFunction != nil
            && dataFunction != nil && connection != 0

        if let scaleSymbol = symbol("CGSGetCursorScale") {
            var value: Float = 1
            let function = unsafeBitCast(scaleSymbol, to: ScaleFunction.self)
            if function(connection, &value) == 0, value.isFinite, value > 0 {
                systemScale = min(4, max(1, Double(value)))
            }
        }
    }

    // MARK: - Per sample

    /// Changes whenever the pointer image changes. Two nanoseconds, which is
    /// why it can ride every sample.
    func currentSeed() -> Int32 {
        seedFunction?() ?? 0
    }

    /// Whether the pointer is on screen at all. Hiding it does NOT change the
    /// seed, so this is a separate question, and without it a recording of
    /// somebody typing gets a pointer painted over text that had none.
    func isPointerVisible() -> Bool {
        visibleFunction?() ?? true
    }

    /// Reads the pixels of whatever pointer is current and returns its
    /// identity. About 22 microseconds, called only when the seed moved.
    /// Safe on the sampler thread: nothing here touches AppKit.
    @discardableResult
    func captureCurrentShape() -> UInt64 {
        guard isAvailable,
              let sizeFunction, let dataFunction else { return 0 }
        var byteCount: Int32 = 0
        guard sizeFunction(connection, &byteCount) == 0, byteCount > 0, byteCount < 16_000_000
        else { return 0 }

        var buffer = [UInt8](repeating: 0, count: Int(byteCount))
        var capacity = byteCount
        var bytesPerRow: Int32 = 0
        var rect = CGRect.zero
        var hotSpot = CGPoint.zero
        var bitsPerPixel: Int32 = 0
        var components: Int32 = 0
        var bitsPerComponent: Int32 = 0
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return dataFunction(connection, base, &capacity, &bytesPerRow, &rect, &hotSpot,
                                &bitsPerPixel, &components, &bitsPerComponent)
        }
        guard status == 0, bitsPerPixel == 32, components == 4, bitsPerComponent == 8,
              rect.width >= 1, rect.height >= 1, bytesPerRow > 0
        else { return 0 }

        let identity = Self.hash(buffer, rect: rect, hotSpot: hotSpot)
        lock.lock()
        let known = shapes[identity] != nil
        lock.unlock()
        if known { return identity }

        guard let shape = Self.makeShape(buffer,
                                         bytesPerRow: Int(bytesPerRow),
                                         rect: rect,
                                         hotSpot: hotSpot)
        else { return 0 }
        lock.lock()
        if shapes[identity] == nil {
            shapes[identity] = shape
            order.append(identity)
        }
        lock.unlock()
        // The window server always vends the base representation, so on a
        // Retina recording this bitmap is half the pixels it will be drawn at.
        // AppKit keeps the sharper ones, and it lives on the main thread.
        requestSharperImage(for: identity, rect: rect)
        return identity
    }

    // MARK: - Building

    private static func makeShape(_ buffer: [UInt8],
                                  bytesPerRow: Int,
                                  rect: CGRect,
                                  hotSpot: CGPoint) -> Shape? {
        let width = Int(rect.width)
        var height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }

        // An animated pointer arrives as a vertical strip of frames: the wait
        // spinner comes back as one column of thirty. Taking the whole strip
        // would paint a smear down the video, so only the first frame is kept.
        if height >= width * 2, height % width == 0 {
            height = width
        }

        let needed = bytesPerRow * height
        guard needed <= buffer.count else { return nil }
        guard let provider = CGDataProvider(data: Data(buffer.prefix(needed)) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // Premultiplied BGRA, top row first, exactly as the window server
        // hands it over.
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: space,
                                  bitmapInfo: info,
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { return nil }
        return Shape(image: image,
                     size: CGSize(width: width, height: height),
                     hotSpot: CGPoint(x: min(hotSpot.x, CGFloat(width)),
                                      y: min(hotSpot.y, CGFloat(height))))
    }

    /// A sharper copy of the same shape, when AppKit happens to have one.
    /// Accepted only when its proportions match what the window server
    /// reported, which is what keeps a pointer that changed mid-read from
    /// replacing the one that was actually captured.
    private func requestSharperImage(for identity: UInt64, rect: CGRect) {
        lock.lock()
        let alreadyTried = upgraded.contains(identity)
        if !alreadyTried { upgraded.insert(identity) }
        lock.unlock()
        guard !alreadyTried, rect.width > 0, rect.height > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let cursor = NSCursor.currentSystem
            else { return }
            let wanted = Int((rect.width * 2 * RecorderSupport.zoomAmountRange.upperBound)
                .rounded(.up))
            let reps = cursor.image.representations.compactMap { $0 as? NSBitmapImageRep }
            guard let rep = reps.filter({ $0.pixelsWide >= wanted })
                    .min(by: { $0.pixelsWide < $1.pixelsWide })
                    ?? reps.max(by: { $0.pixelsWide < $1.pixelsWide }),
                  rep.pixelsWide > Int(rect.width),
                  let image = rep.cgImage
            else { return }
            // Same shape, or the pointer moved on between the two reads.
            let repAspect = Double(rep.pixelsWide) / Double(max(1, rep.pixelsHigh))
            let cgsAspect = Double(rect.width) / Double(max(1, rect.height))
            guard abs(repAspect - cgsAspect) < 0.02 else { return }

            self.lock.lock()
            if let existing = self.shapes[identity] {
                self.shapes[identity] = Shape(image: image,
                                              size: existing.size,
                                              hotSpot: existing.hotSpot)
            }
            self.lock.unlock()
        }
    }

    /// Content identity: the same pointer must be one entry no matter how many
    /// times it is set, because the window server's own number changes on
    /// every set.
    private static func hash(_ buffer: [UInt8], rect: CGRect, hotSpot: CGPoint) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ byte: UInt8) {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        // Every byte of a small bitmap is cheap, and sampling would collide
        // between pointers that differ only in a corner.
        for byte in buffer { mix(byte) }
        for component in [rect.width, rect.height, hotSpot.x, hotSpot.y] {
            withUnsafeBytes(of: Float(component).bitPattern) { $0.forEach(mix) }
        }
        return value
    }

    /// Every shape the recording showed, in the order they first appeared, so
    /// the first one is whatever was on screen when recording started.
    func collected() -> [(id: UInt64, shape: Shape)] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { identity in
            shapes[identity].map { (id: identity, shape: $0) }
        }
    }
}

extension RecorderPointerTrack {
    /// Turns the shapes a catalog collected into the packed table, and remaps
    /// each sample's shape identity onto its index in that table. Index zero
    /// is the first shape the recording showed, so a sample whose shape was
    /// never captured falls back to something sensible rather than to
    /// whatever happened to sort first.
    static func packing(samples: [RecorderMotion.Sample],
                        identities: [UInt64],
                        clicks: [RecorderMotion.Click],
                        catalog: [(id: UInt64, shape: RecorderCursorCatalog.Shape)],
                        systemScale: Double,
                        displayScale: Double) -> RecorderPointerTrack {
        var indexByIdentity: [UInt64: Int] = [:]
        var packed: [CursorShape] = []
        for entry in catalog {
            guard let png = pngData(entry.shape.image) else { continue }
            indexByIdentity[entry.id] = packed.count
            packed.append(CursorShape(png: png,
                                      hotSpot: entry.shape.hotSpot,
                                      pointSize: entry.shape.size))
        }
        let remapped = samples.enumerated().map { offset, sample -> RecorderMotion.Sample in
            var copy = sample
            let identity = identities.indices.contains(offset) ? identities[offset] : 0
            copy.shapeIndex = indexByIdentity[identity] ?? 0
            return copy
        }
        return RecorderPointerTrack(samples: remapped,
                                    clicks: clicks,
                                    shapes: packed,
                                    systemScale: systemScale,
                                    displayScale: displayScale)
    }
}
