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
    private let isCancelled: @Sendable () -> Bool
    private var pending: [CIImage] = []
    private var thumbnails: [CGImage] = []
    private var inFlight: Compression?

    init?(writer: RecorderGIFWriter, size: CGSize, sourceSize: CGSize = .zero,
          isCancelled: @escaping @Sendable () -> Bool) {
        guard size.width.isFinite, size.height.isFinite,
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
        // At most ~120 MB of indices per batch. Pending frames also keep
        // their decoded 4:2:0 sources alive, so a large recording exported
        // small batches by ~400 MB of those too. The GPU texture and one
        // compressing batch are additional live allocations.
        let sourceBytes = sourceSize.width.isFinite && sourceSize.height.isFinite
            ? max(1, Int(sourceSize.width * sourceSize.height * 1.5)) : 1
        framesPerBatch = min(16, max(1, min(120_000_000 / (width * height),
                                            400_000_000 / sourceBytes)))
    }

    deinit { inFlight?.wait() }

    func append(_ image: CIImage) throws {
        try checkCancellation()
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
        let palette: Data
        do { palette = try RecorderGIFWriter.palette(for: thumbnails) }
        catch { throw Failure.unavailable }
        guard palette.count >= 6, palette.count <= 768, palette.count % 3 == 0
        else { throw Failure.unavailable }
        let bytes = [UInt8](palette)
        var colors: [SIMD4<Float>] = []
        for index in stride(from: 0, to: bytes.count, by: 3) {
            colors.append(SIMD4(Float(bytes[index]) / 255, Float(bytes[index + 1]) / 255,
                                Float(bytes[index + 2]) / 255, 1))
        }
        guard let colorBuffer = colors.withUnsafeBytes({ data in
            resources.device.makeBuffer(bytes: data.baseAddress!, length: data.count,
                                        options: .storageModeShared)
        }), let lookup = resources.device.makeBuffer(length: 262_144, options: .storageModePrivate),
              let command = resources.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { throw Failure.unavailable }
        encoder.setComputePipelineState(resources.lookup)
        encoder.setBuffer(colorBuffer, offset: 0, index: 0)
        encoder.setBuffer(lookup, offset: 0, index: 1)
        var count = UInt32(min(255, colors.count)) // 255 is reserved for delta transparency.
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.dispatchThreads(MTLSize(width: 262_144, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw Failure.unavailable }

        var indexed: [MTLBuffer] = []
        for image in pending {
            try checkCancellation()
            let buffer = try autoreleasepool { () throws -> MTLBuffer in
                guard let pixels = resources.device.makeBuffer(length: width * height,
                                                               options: .storageModeShared),
                      let alpha = resources.device.makeBuffer(length: 4, options: .storageModeShared),
                      let command = resources.queue.makeCommandBuffer() else { throw Failure.unavailable }
                alpha.contents().storeBytes(of: UInt32(0), as: UInt32.self)
                // Core Image's lower-left origin becomes top-down GIF rows.
                let flipped = image.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                                       tx: 0, ty: CGFloat(height)))
                resources.context.render(flipped, to: texture, commandBuffer: command,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height),
                    colorSpace: CGColorSpaceCreateDeviceRGB())
                guard let encoder = command.makeComputeCommandEncoder() else { throw Failure.unavailable }
                encoder.setComputePipelineState(resources.mapping)
                encoder.setTexture(texture, index: 0)
                encoder.setBuffer(lookup, offset: 0, index: 0)
                encoder.setBuffer(pixels, offset: 0, index: 1)
                encoder.setBuffer(alpha, offset: 0, index: 2)
                encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                guard command.status == .completed,
                      alpha.contents().load(as: UInt32.self) == 0 else { throw Failure.unavailable }
                return pixels
            }
            indexed.append(buffer)
        }
        // This releases the previous batch before starting another compression
        // job. Encoded data is written here, never accumulated for the clip.
        try drain()
        try checkCancellation()
        inFlight = Compression(buffers: indexed, width: width, height: height,
                               palette: palette, isCancelled: isCancelled)
        pending.removeAll(keepingCapacity: true)
        thumbnails.removeAll(keepingCapacity: true)
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
        kernel void make_lookup(device const float4* colors [[buffer(0)]],
            device uchar* lookup [[buffer(1)]], constant uint& count [[buffer(2)]],
            uint i [[thread_position_in_grid]]) {
            if (i >= 262144) return;
            float3 color = float3((i >> 12) & 63, (i >> 6) & 63, i & 63) / 63.0;
            float best = 1e9;
            uint index = 0;
            for (uint j = 0; j < count; ++j) {
                float3 delta = color - colors[j].rgb;
                float error = dot(delta * delta, float3(2, 4, 1));
                if (error < best) { best = error; index = j; }
            }
            lookup[i] = uchar(index);
        }
        kernel void map_pixels(texture2d<float, access::read> source [[texture(0)]],
            device const uchar* lookup [[buffer(0)]], device uchar* output [[buffer(1)]],
            device atomic_uint* has_alpha [[buffer(2)]], uint2 p [[thread_position_in_grid]]) {
            if (p.x >= source.get_width() || p.y >= source.get_height()) return;
            float4 pixel = source.read(p);
            if (pixel.a < 1.0) atomic_store_explicit(has_alpha, 1u, memory_order_relaxed);
            uint3 color = uint3(clamp(pixel.rgb, 0.0, 1.0) * 63.0 + 0.5);
            output[p.y * source.get_width() + p.x] = lookup[(color.r << 12) | (color.g << 6) | color.b];
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

        init(buffers: [MTLBuffer], width: Int, height: Int, palette: Data,
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
                            let previous = index == 0 ? nil
                                : UnsafePointer(buffers[index - 1].contents().assumingMemoryBound(to: UInt8.self))
                            var length = 0
                            let pointer = palette.withUnsafeBytes { colors in
                                RecorderGIFCodecEncode(pixels, previous, width * height,
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
