// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import CoreImage

/// Turns a recording plus an edit into the picture the person sees, for both
/// the editor preview and the export. One function decides what a frame looks
/// like, so what is watched while editing and what lands in the file are the
/// same pixels by construction.
///
/// Everything that does not change frame to frame is rendered once into a
/// plate: the background, the shadow under the recording, the rounded mask.
/// Per frame there is a transform, a mask and a composite, which is what keeps
/// a Retina export running faster than the encoder behind it.
final class RecorderComposer {

    // MARK: - Plan

    /// Everything precomputed for one document and one pointer track. The
    /// per-frame arrays are the offline advantage made concrete: smoothing and
    /// zoom both need to see the whole recording, so they are solved once,
    /// here, and every frame is then an index lookup.
    struct Plan {
        let sourceSize: CGSize
        let canvasSize: CGSize
        let cardRect: CGRect
        let frameRate: Int
        let positions: [CGPoint]
        let zoom: [Double]
        let travel: [CGPoint]
        let pressScale: [Double]
        let ring: [Double]
        let showsPointer: Bool
        /// The real pointer images the recording showed, in the order the
        /// track packed them.
        let pointerShapes: [RecorderPointerTrack.CursorShape]
        /// Which of those is on screen at each frame.
        let pointerShapeIndex: [Int]
        /// Whether a pointer was on screen at all at each frame.
        let pointerVisible: [Bool]
        /// How solid the drawn pointer is, so one parked in a corner fades
        /// out of the way and is back before it moves again.
        let pointerOpacity: [Double]
        /// Points to pixels for the pointer: the display's own scale, times
        /// the accessibility pointer size, times what the person chose.
        let pointerScale: CGFloat
        /// What a pointer of a typical size comes out as, used to size the
        /// click ring so it stays in proportion.
        let pointerPixelSize: CGFloat
        let showsClickRing: Bool
        let plate: CIImage?
        let mask: CIImage?
        /// Lines of text and, for each frame, how solid each one is. Solved
        /// once like everything else, so a frame is a lookup.
        let texts: [RecorderTextOverlay]
        let textOpacity: [[Double]]
    }

    private let plan: Plan
    /// Decoded once. A recording normally shows two or three pointer shapes,
    /// so this is a handful of small images for the whole export.
    private let decodedShapes: [CGImage?]
    private let fallbackArrow: CGImage?

    init(plan: Plan) {
        self.plan = plan
        decodedShapes = plan.showsPointer ? plan.pointerShapes.map { $0.image } : []
        // Only reached when the recording never managed to read a real
        // pointer image, which is the one case where a drawn arrow beats no
        // pointer at all.
        fallbackArrow = (plan.showsPointer && plan.pointerShapes.isEmpty)
            ? RecorderCursorSprite.arrow(pixelSize: plan.pointerPixelSize * 3)
            : nil
    }

    var canvasSize: CGSize { plan.canvasSize }

    // MARK: - Rendering

    func render(_ source: CIImage, at seconds: Double) -> CIImage {
        let index = frameIndex(for: seconds)
        var content = source.cropped(to: CGRect(origin: .zero, size: plan.sourceSize))

        let pointerWasOnScreen = plan.pointerVisible.indices.contains(index)
            ? plan.pointerVisible[index] : true
        let opacity = plan.pointerOpacity.indices.contains(index) ? plan.pointerOpacity[index] : 1
        if plan.showsPointer, pointerWasOnScreen, opacity > 0.01, index < plan.positions.count {
            content = drawPointer(on: content, index: index)
        }
        content = zoomed(content, index: index)
        content = fitted(content)

        if let mask = plan.mask {
            let background = plan.plate ?? CIImage(color: .black)
                .cropped(to: CGRect(origin: .zero, size: plan.canvasSize))
            content = content.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask,
            ])
        } else if let plate = plan.plate {
            content = content.composited(over: plate)
        }
        content = drawTexts(on: content, index: index)
        return content.cropped(to: CGRect(origin: .zero, size: plan.canvasSize))
    }

    /// Text sits on top of everything, including the background and the zoom:
    /// a caption that got magnified along with the picture would leave the
    /// frame the moment the zoom moved.
    private func drawTexts(on content: CIImage, index: Int) -> CIImage {
        guard !plan.texts.isEmpty else { return content }
        var result = content
        for (order, overlay) in plan.texts.enumerated() {
            guard plan.textOpacity.indices.contains(order),
                  plan.textOpacity[order].indices.contains(index) else { continue }
            let opacity = plan.textOpacity[order][index]
            guard opacity > 0.01,
                  let image = RecorderTextRenderer.image(for: overlay,
                                                         canvasHeight: plan.canvasSize.height)
            else { continue }
            let size = CGSize(width: image.width, height: image.height)
            let origin = RecorderTextRenderer.origin(for: overlay,
                                                     textSize: size,
                                                     canvas: plan.canvasSize)
            result = faded(CIImage(cgImage: image), opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: result)
        }
        return result
    }

    private func frameIndex(for seconds: Double) -> Int {
        let raw = Int((max(0, seconds) * Double(plan.frameRate)).rounded())
        return min(max(0, raw), max(0, plan.positions.count - 1))
    }

    /// The pointer is drawn into the content, not over the finished frame, so
    /// the zoom carries it along with everything else it magnifies. The click
    /// ring lives in the same space for the same reason.
    private func faded(_ image: CIImage, opacity: Double) -> CIImage {
        guard opacity < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }

    private func drawPointer(on content: CIImage, index: Int) -> CIImage {
        let uv = plan.positions[index]
        guard uv.x > -0.2, uv.x < 1.2, uv.y > -0.2, uv.y < 1.2 else { return content }
        let press = plan.pressScale.indices.contains(index) ? plan.pressScale[index] : 1
        // Core Image counts up from the bottom; the track counts down from the
        // top, the way the screen does.
        let x = uv.x * plan.sourceSize.width
        let y = (1 - uv.y) * plan.sourceSize.height

        var result = content
        if plan.showsClickRing, plan.ring.indices.contains(index), plan.ring[index] >= 0 {
            result = drawRing(progress: plan.ring[index],
                              at: CGPoint(x: x, y: y),
                              on: result)
        }

        let shapeIndex = plan.pointerShapeIndex.indices.contains(index)
            ? plan.pointerShapeIndex[index] : 0
        if let sprite = decodedShapes.indices.contains(shapeIndex)
            ? decodedShapes[shapeIndex] : decodedShapes.first ?? nil,
           let shape = plan.pointerShapes.indices.contains(shapeIndex)
            ? plan.pointerShapes[shapeIndex] : plan.pointerShapes.first {
            // The image carries its own point size and its own hot spot, so a
            // text beam or a resize arrow lands exactly where the real one did.
            // One bitmap pixel is one point on screen, so the whole
            // conversion is the scale the plan already resolved.
            let drawnWidth = shape.pointSize.width * plan.pointerScale * CGFloat(press)
            let drawnHeight = shape.pointSize.height * plan.pointerScale * CGFloat(press)
            guard drawnWidth > 0, drawnHeight > 0, sprite.width > 0 else { return result }
            let factor = drawnWidth / CGFloat(sprite.width)
            let hotX = shape.hotSpot.x * plan.pointerScale * CGFloat(press)
            let hotY = shape.hotSpot.y * plan.pointerScale * CGFloat(press)
            let opacity = plan.pointerOpacity.indices.contains(index)
                ? plan.pointerOpacity[index] : 1
            return faded(CIImage(cgImage: sprite)
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor)),
                         opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: x - hotX,
                                                   y: y - drawnHeight + hotY))
                .composited(over: result)
        }

        guard let sprite = fallbackArrow, sprite.width > 0 else { return result }
        let drawn = RecorderCursorSprite.fallbackSize.width * plan.pointerScale * CGFloat(press)
        let factor = drawn / CGFloat(sprite.width)
        let height = CGFloat(sprite.height) * factor
        let hot = CGPoint(x: RecorderCursorSprite.fallbackHotSpot.x * plan.pointerScale
                            * CGFloat(press),
                          y: RecorderCursorSprite.fallbackHotSpot.y * plan.pointerScale
                            * CGFloat(press))
        return CIImage(cgImage: sprite)
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            .transformed(by: CGAffineTransform(translationX: x - hot.x, y: y - height + hot.y))
            .composited(over: result)
    }

    private func drawRing(progress: Double, at point: CGPoint, on content: CIImage) -> CIImage {
        let eased = 1 - pow(1 - progress, 3)
        // Tied to the pointer rather than to the frame: the ring belongs to
        // the pointer, so it stays in proportion at any recording size and at
        // whatever pointer size the person chose.
        let unit = plan.pointerPixelSize / 34
        let radius = RecorderMotion.ringRadius * unit * eased
        let width = max(0.6, 2.4 * (1 - progress)) * unit
        let alpha = 0.35 * (1 - progress * progress)
        guard radius > 1, alpha > 0.01,
              let ring = RecorderCursorSprite.ring(radius: radius, lineWidth: width, alpha: alpha)
        else { return content }
        let side = CGFloat(ring.width)
        return CIImage(cgImage: ring)
            .transformed(by: CGAffineTransform(translationX: point.x - side / 2,
                                               y: point.y - side / 2))
            .composited(over: content)
    }

    private func zoomed(_ content: CIImage, index: Int) -> CIImage {
        guard plan.zoom.indices.contains(index) else { return content }
        let z = plan.zoom[index]
        guard z > 1.001, plan.travel.indices.contains(index) else { return content }
        let origin = RecorderMotion.viewportOrigin(travel: plan.travel[index], zoom: z)
        // The viewport is expressed from the top; Core Image measures from the
        // bottom, and the visible height is 1/z of the frame.
        let bottom = 1 - origin.y - 1 / z
        let transform = CGAffineTransform(scaleX: CGFloat(z), y: CGFloat(z))
            .concatenating(CGAffineTransform(
                translationX: -origin.x * plan.sourceSize.width * CGFloat(z),
                y: -bottom * plan.sourceSize.height * CGFloat(z)))
        return content.transformed(by: transform)
            .cropped(to: CGRect(origin: .zero, size: plan.sourceSize))
    }

    private func fitted(_ content: CIImage) -> CIImage {
        guard plan.sourceSize.width > 0, plan.sourceSize.height > 0 else { return content }
        let scaleX = plan.cardRect.width / plan.sourceSize.width
        let scaleY = plan.cardRect.height / plan.sourceSize.height
        return content
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: plan.cardRect.origin.x,
                                               y: plan.cardRect.origin.y))
    }

    // MARK: - Composition

    /// A composition that resamples the recording to a steady frame rate and
    /// renders it through this composer.
    ///
    /// The master is written at a variable rate on purpose, so a still screen
    /// costs nothing while recording; the steady rate is imposed here instead,
    /// in the single decode pass the export already needs.
    static func videoComposition(track: AVAssetTrack,
                                 asset: AVAsset,
                                 duration: CMTime,
                                 frameRate: Int,
                                 composer: RecorderComposer?,
                                 sourceSize: CGSize,
                                 outputSize: CGSize) async -> AVMutableVideoComposition {
        if let composer {
            // The handler may run concurrently; this composer only reads
            // immutable state while rendering each frame.
            nonisolated(unsafe) let threadSafeComposer = composer
            let composition = try? await AVMutableVideoComposition.videoComposition(
                with: asset) { request in
                    let rendered = threadSafeComposer.render(
                        request.sourceImage,
                        at: CMTimeGetSeconds(request.compositionTime))
                    request.finish(with: rendered, context: nil)
                }
            if let composition {
                composition.frameDuration = CMTime(value: 1,
                                                   timescale: CMTimeScale(max(1, frameRate)))
                composition.renderSize = composer.canvasSize
                composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
                return composition
            }
        }
        let naturalSize = (try? await track.load(.naturalSize)) ?? sourceSize
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        return plainComposition(track: track,
                                naturalSize: naturalSize,
                                preferredTransform: preferredTransform,
                                outputSize: outputSize,
                                frameRate: frameRate,
                                duration: duration)
    }

    static func plainComposition(track: AVAssetTrack,
                                 naturalSize: CGSize,
                                 preferredTransform: CGAffineTransform,
                                 outputSize: CGSize,
                                 frameRate: Int,
                                 duration: CMTime) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        composition.renderSize = outputSize
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let geometry = RecorderSupport.videoGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform)
        if geometry.size.width > 0, geometry.size.height > 0 {
            let scale = CGAffineTransform(scaleX: outputSize.width / geometry.size.width,
                                          y: outputSize.height / geometry.size.height)
            layer.setTransform(geometry.transform.concatenating(scale), at: .zero)
        }
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }
}
