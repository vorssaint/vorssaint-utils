// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreImage
import Foundation
@preconcurrency import Metal
import RecorderGIFCodec

/// Palette mapping stays on the GPU. Only indexed pixels cross to the CPU,
/// where independent frames compress in parallel and stream out in order.
/// One batch can compress while the producer prepares the next batch.
final class RecorderFastGIFWriter {
    enum Failure: Error { case unavailable, cancelled }

    private let resources: Resources
    private let writer: RecorderGIFWriter
    private let texture: MTLTexture
    private let width: Int
    private let height: Int
    let framesPerBatch: Int
    private let sourceByteLimit: Int
    private let isCancelled: @Sendable () -> Bool
    private var pending: [CIImage] = []
    private var pendingSourceBytes = 0
    private var thumbnails: [CGImage] = []
    private var inFlight: Compression?
    private var lastIndexed: (colors: [UInt32], pixels: MTLBuffer)?

    init?(writer: RecorderGIFWriter, size: CGSize, sourceByteLimit: Int = 400_000_000,
          isCancelled: @escaping @Sendable () -> Bool) {
        guard sourceByteLimit > 0, size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1,
              size.width <= 8192, size.height <= 8192,
              let resources = Resources.shared else { return nil }
        let width = Int(size.width), height = Int(size.height)
        guard CGFloat(width) == size.width, CGFloat(height) == size.height,
              width * height <= 67_108_864 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = resources.device.makeTexture(descriptor: descriptor) else { return nil }
        self.resources = resources
        self.writer = writer
        self.texture = texture
        self.width = width
        self.height = height
        self.isCancelled = isCancelled
        self.sourceByteLimit = sourceByteLimit
        framesPerBatch = min(16, max(1, 120_000_000 / (width * height)))
    }

    deinit { inFlight?.wait() }

    func append(_ image: CIImage, sourceBytes: Int) throws {
        try checkCancellation()
        // A lazy CIImage retains its pixel buffer, including plane padding.
        // Flush before retaining a frame that would exceed the source budget.
        guard sourceBytes >= 0, sourceBytes <= sourceByteLimit else { throw Failure.unavailable }
        if pendingSourceBytes > sourceByteLimit - sourceBytes { try flush() }
        let scale = min(1, 128 / CGFloat(max(width, height)))
        let bounds = CGRect(x: 0, y: 0, width: max(1, Int(CGFloat(width) * scale)),
                            height: max(1, Int(CGFloat(height) * scale)))
        let picture = autoreleasepool {
            resources.context.createCGImage(
                image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), from: bounds)
        }
        guard let picture
        else { throw Failure.unavailable }
        pending.append(image)
        pendingSourceBytes += sourceBytes
        thumbnails.append(picture)
        if pending.count >= framesPerBatch { try flush() }
    }

    func finish() throws {
        try flush()
        try drain()
        try checkCancellation()
        try writer.finish()
    }

    private func checkCancellation() throws {
        if isCancelled() { throw Failure.cancelled }
    }

    private func drain() throws {
        guard let job = inFlight else { return }
        defer { inFlight = nil }
        let frames = try job.frames()
        try checkCancellation()
        try writer.appendEncodedFrames(frames)
    }

    private func flush() throws {
        guard !pending.isEmpty else { return }
        try autoreleasepool { try flushBatch() }
    }

    private func flushBatch() throws {
        try checkCancellation()
        let sampled: Data
        do { sampled = try RecorderGIFWriter.palette(for: thumbnails) }
        catch { throw Failure.unavailable }
        guard sampled.count >= 6, sampled.count <= 768, sampled.count % 3 == 0 else { throw Failure.unavailable }
        let bytes = [UInt8](sampled)
        var palette: [UInt32] = []
        for i in stride(from: 0, to: bytes.count, by: 3) {
            let rgb = UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2])
            if palette.count < 255, !palette.contains(rgb) { palette.append(rgb) }
        }
        if let previous = lastIndexed?.colors, palette.allSatisfy(previous.contains) {
            palette = previous
        }
        var lookup = try makeLookup(palette)
        var indexed: [MTLBuffer] = []
        for image in pending {
            try checkCancellation()
            let pixels = try autoreleasepool { try indices(for: image, palette: &palette, lookup: &lookup) }
            indexed.append(pixels)
        }
        pending.removeAll(keepingCapacity: true)
        pendingSourceBytes = 0
        thumbnails.removeAll(keepingCapacity: true)
        // The C encoder needs at least two entries. Opaque pixels never use 255.
        if palette.count == 1 { palette.append(palette[0]) }
        let table = Data(palette.flatMap { rgb in
            [UInt8(rgb >> 16), UInt8(truncatingIfNeeded: rgb >> 8), UInt8(truncatingIfNeeded: rgb)]
        })
        try drain()
        try checkCancellation()
        let previous = lastIndexed.flatMap { palette.starts(with: $0.colors) ? $0.pixels : nil }
        inFlight = Compression(buffers: indexed, previous: previous, width: width, height: height,
                               palette: table, isCancelled: isCancelled)
        if let last = indexed.last { lastIndexed = (palette, last) }
    }

    private func makeLookup(_ palette: [UInt32]) throws -> MTLBuffer {
        guard let colors = palette.withUnsafeBytes({ data in
            resources.device.makeBuffer(bytes: data.baseAddress!, length: data.count, options: .storageModeShared)
        }), let lookup = resources.device.makeBuffer(length: 262_144 * MemoryLayout<UInt32>.stride,
                                                      options: .storageModePrivate),
              let command = resources.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { throw Failure.unavailable }
        encoder.setComputePipelineState(resources.lookup)
        encoder.setBuffer(colors, offset: 0, index: 0)
        encoder.setBuffer(lookup, offset: 0, index: 1)
        var count = UInt32(palette.count)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.dispatchThreads(MTLSize(width: 262_144, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw Failure.unavailable }
        return lookup
    }

    private func indices(for image: CIImage, palette: inout [UInt32], lookup: inout MTLBuffer) throws -> MTLBuffer {
        // The first word flags transparency. The remaining 8×8×8 bins collect
        // actual colors that the thumbnail palette could not represent.
        let wordCount = 1 + 8 * 8 * 8
        guard let pixels = resources.device.makeBuffer(length: width * height, options: .storageModeShared),
              let misses = resources.device.makeBuffer(length: wordCount * MemoryLayout<UInt32>.stride,
                                                       options: .storageModeShared) else { throw Failure.unavailable }
        let words = misses.contents().bindMemory(to: UInt32.self, capacity: wordCount)
        for pass in 0...1 {
            try checkCancellation()
            memset(misses.contents(), 0, misses.length)
            guard let command = resources.queue.makeCommandBuffer() else { throw Failure.unavailable }
            if pass == 0 {
                let flipped = image.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                                       tx: 0, ty: CGFloat(height)))
                resources.context.render(flipped, to: texture, commandBuffer: command,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height),
                    colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            guard let encoder = command.makeComputeCommandEncoder() else { throw Failure.unavailable }
            encoder.setComputePipelineState(resources.mapping)
            encoder.setTexture(texture, index: 0)
            encoder.setBuffer(lookup, offset: 0, index: 0)
            encoder.setBuffer(pixels, offset: 0, index: 1)
            encoder.setBuffer(misses, offset: 0, index: 2)
            // A sparse palette can afford to recover subtler screen details.
            var tolerance: UInt32 = pass == 0 && palette.count <= 16 ? 4 : 31
            encoder.setBytes(&tolerance, length: MemoryLayout<UInt32>.size, index: 3)
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                   threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed, words[0] == 0 else { throw Failure.unavailable }
            let count = palette.count
            for i in 1..<wordCount where words[i] != 0 {
                let rgb = words[i] - 1
                guard pass == 0, palette.count < 255, !palette.contains(rgb) else { throw Failure.unavailable }
                palette.append(rgb)
            }
            if palette.count == count { return pixels }
            // Only append colors: indices already mapped with this batch's
            // palette remain valid. Recheck every pixel before accepting it.
            lookup = try makeLookup(palette)
        }
        throw Failure.unavailable
    }

    /// Immutable Metal/Core Image resources are safe to share between exports.
    private final class Resources: @unchecked Sendable {
        static let shared = Resources()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let context: CIContext
        let lookup: MTLComputePipelineState
        let mapping: MTLComputePipelineState

        private init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                  let library = try? device.makeLibrary(source: Self.source, options: nil),
                  let lookup = library.makeFunction(name: "make_lookup"),
                  let mapping = library.makeFunction(name: "map_pixels"),
                  let lookupPipeline = try? device.makeComputePipelineState(function: lookup),
                  let mappingPipeline = try? device.makeComputePipelineState(function: mapping)
            else { return nil }
            self.device = device
            self.queue = queue
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
            self.lookup = lookupPipeline
            self.mapping = mappingPipeline
        }

        private static let source = """
        #include <metal_stdlib>
        using namespace metal;
        uint3 channels(uint rgb) {
            return uint3((rgb >> 16) & 255u, (rgb >> 8) & 255u, rgb & 255u);
        }
        kernel void make_lookup(device const uint* colors [[buffer(0)]],
            device uint* lookup [[buffer(1)]], constant uint& count [[buffer(2)]],
            uint i [[thread_position_in_grid]]) {
            if (i >= 262144) return;
            float3 color = float3((i >> 12) & 63, (i >> 6) & 63, i & 63) / 63.0;
            float best = 1e9;
            uint index = 0;
            for (uint j = 0; j < count; ++j) {
                float3 delta = color - float3(channels(colors[j])) / 255.0;
                float error = dot(delta * delta, float3(2, 4, 1));
                if (error < best) { best = error; index = j; }
            }
            lookup[i] = (index << 24) | colors[index];
        }
        kernel void map_pixels(texture2d<float, access::read> source [[texture(0)]],
            device const uint* lookup [[buffer(0)]], device uchar* output [[buffer(1)]],
            device atomic_uint* misses [[buffer(2)]], constant uint& tolerance [[buffer(3)]],
            uint2 p [[thread_position_in_grid]]) {
            if (p.x >= source.get_width() || p.y >= source.get_height()) return;
            float4 pixel = source.read(p);
            if (pixel.a < 1.0) atomic_store_explicit(&misses[0], 1u, memory_order_relaxed);
            uint3 color = uint3(clamp(pixel.rgb, 0.0, 1.0) * 63.0 + 0.5);
            uint match = lookup[(color.r << 12) | (color.g << 6) | color.b];
            output[p.y * source.get_width() + p.x] = uchar(match >> 24);
            uint3 rgb = uint3(pixel.rgb * 255.0 + 0.5);
            // At most 31 of 255 levels per channel. A rare screen detail
            // outside that range must enter the palette or go through ImageIO.
            uint3 chosen = channels(match);
            if (any(max(rgb, chosen) - min(rgb, chosen) > uint3(tolerance))) {
                uint bin = ((rgb.r >> 5) << 6) | ((rgb.g >> 5) << 3) | (rgb.b >> 5);
                uint packed = (rgb.r << 16) | (rgb.g << 8) | rgb.b;
                atomic_fetch_max_explicit(&misses[1 + bin], packed + 1u, memory_order_relaxed);
            }
        }
        """
    }

    /// The worker owns its buffers. A DispatchGroup wait establishes visibility
    /// of its result before the serial producer reads it or releases the batch.
    private final class Compression: @unchecked Sendable {
        // One CPU batch at a time across exports; each batch itself uses up to
        // eight workers. A dedicated queue also keeps this work independent
        // of the cooperative task threads waiting for an ordered result.
        private static let queue = DispatchQueue(label: "recorder.gif.compression", qos: .userInitiated)
        private let group = DispatchGroup()
        private var result: Result<[RecorderGIFWriter.Chunk], Error>?

        init(buffers: [MTLBuffer], previous: MTLBuffer?, width: Int, height: Int, palette: Data,
             isCancelled: @escaping @Sendable () -> Bool) {
            group.enter()
            Self.queue.async { [self] in
                defer { group.leave() }
                let results = FrameResults(count: buffers.count)
                let workers = min(8, buffers.count)
                DispatchQueue.concurrentPerform(iterations: workers) { worker in
                    for index in stride(from: worker, to: buffers.count, by: workers) {
                        let frame = autoreleasepool { Result { () throws -> RecorderGIFWriter.Chunk in
                            if isCancelled() { throw Failure.cancelled }
                            let pixels = buffers[index].contents().assumingMemoryBound(to: UInt8.self)
                            let prior = index == 0 ? previous : buffers[index - 1]
                            let old = prior.map { UnsafePointer($0.contents().assumingMemoryBound(to: UInt8.self)) }
                            var length = 0
                            let pointer = palette.withUnsafeBytes { colors in
                                RecorderGIFCodecEncode(pixels, old, width * height,
                                    UInt32(width), UInt32(height),
                                    colors.baseAddress?.assumingMemoryBound(to: UInt8.self), colors.count, &length)
                            }
                            guard let pointer, length > 0 else { throw Failure.unavailable }
                            let data = Data(bytesNoCopy: pointer, count: length, deallocator: .free)
                            do { return try RecorderGIFWriter.chunk(from: data) }
                            catch { throw Failure.unavailable }
                        } }
                        results.set(frame, at: index)
                    }
                }
                result = Result { try results.ordered() }
            }
        }

        func wait() { group.wait() }
        func frames() throws -> [RecorderGIFWriter.Chunk] {
            wait()
            guard let result else { throw Failure.unavailable }
            return try result.get()
        }
    }

    private final class FrameResults: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [Result<RecorderGIFWriter.Chunk, Error>?]
        init(count: Int) { frames = Array(repeating: nil, count: count) }
        func set(_ frame: Result<RecorderGIFWriter.Chunk, Error>, at index: Int) {
            lock.lock()
            defer { lock.unlock() }
            frames[index] = frame
        }
        func ordered() throws -> [RecorderGIFWriter.Chunk] {
            // All workers have joined before the consumer calls this method.
            try frames.map { frame in
                guard let frame else { throw Failure.unavailable }
                return try frame.get()
            }
        }
    }
}
