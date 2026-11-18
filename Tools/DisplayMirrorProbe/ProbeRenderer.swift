// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreVideo
import Metal
import QuartzCore

final class ProbeRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache?

    // UVs use a top-left texture origin; changing x preserves row order.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position [[position]]; float2 uv; };
    vertex Vertex mirrorVertex(uint id [[vertex_id]]) {
        const float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
        Vertex v;
        v.position = float4(p[id], 0, 1);
        v.uv = float2((p[id].x + 1) * 0.5, (1 - p[id].y) * 0.5);
        return v;
    }
    fragment float4 mirrorFragment(Vertex v [[stage_in]],
                                  texture2d<float> source [[texture(0)]],
                                  constant uint &flip [[buffer(0)]]) {
        constexpr sampler sample(filter::linear, address::clamp_to_edge);
        float2 uv = v.uv;
        if (flip != 0) uv.x = 1 - uv.x;
        return float4(source.sample(sample, uv).rgb, 1);
    }
    """

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw ProbeError.message("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mirrorVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mirrorFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw ProbeError.message("Could not create the Metal texture cache")
        }
    }

    /// CoreVideo owns the input surface. Keep its wrapper AND the pixel buffer
    /// alive until GPU completion; no CPU readback occurs in the capture path.
    func texture(for buffer: CVPixelBuffer) throws -> (CVMetalTexture, MTLTexture) {
        guard let cache else { throw ProbeError.message("No texture cache") }
        var wrapper: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &wrapper)
        guard result == kCVReturnSuccess, let wrapper, let texture = CVMetalTextureGetTexture(wrapper) else {
            throw ProbeError.message("Could not map the capture surface to Metal (\(result))")
        }
        return (wrapper, texture)
    }

    func encode(source: MTLTexture, destination: MTLTexture, flipped: Bool) throws -> MTLCommandBuffer {
        guard let command = queue.makeCommandBuffer() else { throw ProbeError.message("No Metal command buffer") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw ProbeError.message("No Metal render encoder")
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        var flip: UInt32 = flipped ? 1 : 0
        encoder.setFragmentBytes(&flip, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return command
    }

    static func selftest() throws {
        let renderer = try ProbeRenderer()
        // Four distinguishable pixels in two rows catch both axis mistakes
        // and a spurious vertical inversion. Exercise the actual GPU shader.
        let pixels: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255,
                               255, 0, 0, 255, 255, 255, 255, 255]
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let output = renderer.device.makeTexture(descriptor: descriptor) else {
            throw ProbeError.message("Could not allocate test textures")
        }
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                           kCVPixelBufferIOSurfacePropertiesKey: [:]]
        guard CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { throw ProbeError.message("Could not allocate a test pixel buffer") }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw ProbeError.message("Test pixel buffer has no storage")
        }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        pixels.withUnsafeBytes { bytes in
            for row in 0..<2 { base.advanced(by: row * stride).copyMemory(from: bytes.baseAddress!.advanced(by: row * 8), byteCount: 8) }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let (wrapper, input) = try renderer.texture(for: pixelBuffer)
        defer { withExtendedLifetime((pixelBuffer, wrapper)) {} }
        for flip in [false, true] {
            let command = try renderer.encode(source: input, destination: output, flipped: flip)
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { throw ProbeError.message("GPU selftest failed") }
            var result = [UInt8](repeating: 0, count: 16)
            result.withUnsafeMutableBytes {
                output.getBytes($0.baseAddress!, bytesPerRow: 8,
                                from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
            }
            let order = flip ? [1, 0, 3, 2] : [0, 1, 2, 3]
            let expected = order.flatMap { Array(pixels[($0 * 4)..<($0 * 4 + 4)]) }
            guard result == expected else { throw ProbeError.message("Incorrect pixels for flip=\(flip): \(result)") }
        }
    }
}
