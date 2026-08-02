// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Where the pointer went, when it was pressed, and which pointer it was,
/// stored next to the master.
///
/// Packed binary rather than JSON because it is written while a recording is
/// running: ten minutes at 125 Hz is 75 000 samples, which is a megabyte here
/// and several as text. Positions are normalized to the recorded area, so a
/// later crop or a different export size cannot invalidate the track.
struct RecorderPointerTrack: Equatable {

    /// One pointer image the recording actually showed. Kept as PNG so the
    /// whole track is one file, and decoded only when something draws it.
    struct CursorShape: Equatable {
        var png: Data
        /// Where inside the image the pointer points, in the bitmap's own
        /// pixels from the top-left, which is what the window server reports
        /// and what AppKit gets wrong for the I-beam.
        var hotSpot: CGPoint
        /// The bitmap's size, which is also its size in screen points: the
        /// window server draws the base representation one pixel per point.
        var pointSize: CGSize

        var image: CGImage? {
            guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }

    var samples: [RecorderMotion.Sample]
    var clicks: [RecorderMotion.Click]
    var shapes: [CursorShape]
    /// The pointer size the window server was applying, straight from it
    /// rather than from a preference, so a large pointer is neither missed
    /// nor counted twice.
    var systemScale: Double
    /// Pixels per point of the recorded display, so a pointer measured in
    /// points can be drawn at the size it really occupied.
    var displayScale: Double

    init(samples: [RecorderMotion.Sample] = [],
         clicks: [RecorderMotion.Click] = [],
         shapes: [CursorShape] = [],
         systemScale: Double = 1,
         displayScale: Double = 2) {
        self.samples = samples
        self.clicks = clicks
        self.shapes = shapes
        self.systemScale = systemScale
        self.displayScale = displayScale
    }

    var isEmpty: Bool { samples.isEmpty }

    func shape(at index: Int) -> CursorShape? {
        shapes.indices.contains(index) ? shapes[index] : shapes.first
    }

    // MARK: - Encoding

    private static let magic: [UInt8] = [0x56, 0x52, 0x50, 0x54] // "VRPT"
    private static let version: UInt16 = 3
    private static let headerSize = 28
    private static let sampleSize = 16
    private static let clickSize = 8

    func encoded() -> Data {
        var data = Data(capacity: Self.headerSize
                        + samples.count * Self.sampleSize
                        + clicks.count * Self.clickSize)
        data.append(contentsOf: Self.magic)
        data.appendLittleEndian(Self.version)
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(Float(systemScale).bitPattern)
        data.appendLittleEndian(Float(displayScale).bitPattern)
        data.appendLittleEndian(UInt32(samples.count))
        data.appendLittleEndian(UInt32(clicks.count))
        data.appendLittleEndian(UInt32(shapes.count))
        for sample in samples {
            data.appendLittleEndian(Float(sample.time).bitPattern)
            data.appendLittleEndian(Float(sample.point.x).bitPattern)
            data.appendLittleEndian(Float(sample.point.y).bitPattern)
            data.appendLittleEndian(UInt16(clamping: sample.shapeIndex))
            data.appendLittleEndian(UInt16(sample.isPointerVisible ? 1 : 0))
        }
        for click in clicks {
            data.appendLittleEndian(Float(click.time).bitPattern)
            data.appendLittleEndian(UInt32(click.isDown ? 1 : 0))
        }
        for shape in shapes {
            data.appendLittleEndian(Float(shape.hotSpot.x).bitPattern)
            data.appendLittleEndian(Float(shape.hotSpot.y).bitPattern)
            data.appendLittleEndian(Float(shape.pointSize.width).bitPattern)
            data.appendLittleEndian(Float(shape.pointSize.height).bitPattern)
            data.appendLittleEndian(UInt32(shape.png.count))
            data.append(shape.png)
        }
        return data
    }

    /// A track written by a recording that crashed mid-flush is truncated, not
    /// corrupt: whatever whole records are there are kept and the rest is
    /// dropped, so a crash costs the tail and not the effect.
    static func decoded(_ data: Data?) -> RecorderPointerTrack {
        guard let data, data.count >= headerSize,
              Array(data.prefix(4)) == magic,
              let fileVersion = data.readUInt16(at: 4), fileVersion == version
        else { return RecorderPointerTrack() }

        let scale = Float(bitPattern: data.readUInt32(at: 8) ?? 0)
        let display = Float(bitPattern: data.readUInt32(at: 12) ?? 0)
        let declaredSamples = Int(data.readUInt32(at: 16) ?? 0)
        let declaredClicks = Int(data.readUInt32(at: 20) ?? 0)
        let declaredShapes = Int(data.readUInt32(at: 24) ?? 0)

        var samples: [RecorderMotion.Sample] = []
        var offset = headerSize
        let sampleLimit = min(declaredSamples, max(0, (data.count - offset) / sampleSize))
        samples.reserveCapacity(sampleLimit)
        for _ in 0..<sampleLimit {
            guard let t = data.readFloat(at: offset),
                  let x = data.readFloat(at: offset + 4),
                  let y = data.readFloat(at: offset + 8),
                  let shape = data.readUInt16(at: offset + 12),
                  let visible = data.readUInt16(at: offset + 14)
            else { break }
            offset += sampleSize
            guard t.isFinite, x.isFinite, y.isFinite else { continue }
            samples.append(RecorderMotion.Sample(time: Double(t),
                                                 point: CGPoint(x: Double(x), y: Double(y)),
                                                 shapeIndex: Int(shape),
                                                 isPointerVisible: visible != 0))
        }

        var clicks: [RecorderMotion.Click] = []
        let clickLimit = min(declaredClicks, max(0, (data.count - offset) / clickSize))
        clicks.reserveCapacity(clickLimit)
        for _ in 0..<clickLimit {
            guard let t = data.readFloat(at: offset),
                  let down = data.readUInt32(at: offset + 4)
            else { break }
            offset += clickSize
            guard t.isFinite else { continue }
            clicks.append(RecorderMotion.Click(time: Double(t), isDown: down != 0))
        }

        var shapes: [CursorShape] = []
        shapes.reserveCapacity(max(0, declaredShapes))
        for _ in 0..<max(0, declaredShapes) {
            guard let hotX = data.readFloat(at: offset),
                  let hotY = data.readFloat(at: offset + 4),
                  let width = data.readFloat(at: offset + 8),
                  let height = data.readFloat(at: offset + 12),
                  let length = data.readUInt32(at: offset + 16)
            else { break }
            let start = offset + 20
            let end = start + Int(length)
            guard length > 0, end <= data.count else { break }
            let png = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
            offset = end
            guard hotX.isFinite, hotY.isFinite, width > 0, height > 0 else { continue }
            shapes.append(CursorShape(png: png,
                                      hotSpot: CGPoint(x: Double(hotX), y: Double(hotY)),
                                      pointSize: CGSize(width: Double(width),
                                                        height: Double(height))))
        }

        return RecorderPointerTrack(
            samples: samples,
            clicks: clicks,
            shapes: shapes,
            systemScale: scale.isFinite && scale > 0 ? Double(scale) : 1,
            displayScale: display.isFinite && display > 0 ? Double(display) : 2)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }

    func readFloat(at offset: Int) -> Float? {
        guard let bits = readUInt32(at: offset) else { return nil }
        return Float(bitPattern: bits)
    }
}
