// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Foundation

/// A small live picture of what a tool will make. It runs the same code the tool runs, on a
/// reduced copy of the first file, so moving a slider shows the result at once. The real run
/// always starts again from the original file at full size.
@MainActor
final class ConvertPreview: ObservableObject {
    @Published private(set) var image: NSImage?
    /// The file as it is now, for holding down to compare.
    @Published private(set) var original: NSImage?
    @Published private(set) var caption = ""
    @Published private(set) var working = false

    private var task: Task<Void, Never>?
    private var source: Source?
    private var collage: (urls: [URL], images: [CGImage])?
    private var redactions: (key: String, boxes: [CGRect])?

    /// The longest side of the working copy. Big enough to judge a photo, small enough to redraw at once.
    private static let maxEdge = 720

    private struct Source {
        let url: URL
        let image: CGImage
        /// The working copy's width over the file's own.
        let scale: CGFloat
        let originalSize: CGSize
    }

    /// Tools that can show their result before they run.
    static func supports(_ tool: ToolID, category: FormatCategory) -> Bool {
        switch tool {
        case .editImage, .frameImage, .cropImage, .rotateImage, .resizeImage, .redactImage, .createCollage:
            return category == .image
        case .cropVideo, .trimVideo:
            return category == .video
        default:
            return false
        }
    }

    func reset() {
        task?.cancel(); task = nil
        image = nil; original = nil; caption = ""; working = false
        source = nil; collage = nil; redactions = nil
    }

    /// Redraws after a short pause, so dragging a slider draws only the values it rests on.
    func update(_ tool: ToolID, urls: [URL], values: ToolValues) {
        task?.cancel()
        guard !urls.isEmpty else { return }
        working = true
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled else { return }
            await self?.render(tool, urls: urls, values: values)
        }
    }

    private func render(_ tool: ToolID, urls: [URL], values v: ToolValues) async {
        defer { if !Task.isCancelled { working = false } }
        do {
            switch tool {
            case .cropVideo, .trimVideo:
                try await renderVideo(tool, url: urls[0], values: v)
            case .createCollage:
                try await renderCollage(urls: urls, values: v)
            default:
                try await renderImage(tool, url: urls[0], values: v)
            }
        } catch {
            guard !Task.isCancelled else { return }
            image = nil
            caption = (error as? LocalizedError)?.errorDescription ?? "No preview"
        }
    }

    private func publish(_ result: CGImage?, original base: CGImage?, caption text: String) {
        guard !Task.isCancelled else { return }
        image = result.map { ImageOps.nsImage($0) }
        original = base.map { ImageOps.nsImage($0) }
        caption = text
    }

    private func loadSource(_ url: URL) async throws -> Source {
        if let source, source.url == url { return source }
        let edge = Self.maxEdge
        let loaded = try await Task.detached(priority: .userInitiated) { () -> Source in
            let image = try ImageIOBridge.load(url, maxPixelSize: edge)
            var size = CGSize(width: image.width, height: image.height)
            if let file = CGImageSourceCreateWithURL(url as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any],
               let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
               let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 {
                size = CGSize(width: w, height: h)
            }
            return Source(url: url, image: image, scale: CGFloat(image.width) / max(1, size.width), originalSize: size)
        }.value
        source = loaded
        return loaded
    }

    // MARK: Images

    private func renderImage(_ tool: ToolID, url: URL, values v: ToolValues) async throws {
        let src = try await loadSource(url)
        let image = src.image
        var text = ""
        var extra: [CGRect] = []
        if tool == .redactImage {
            let find = v.s["find"] ?? "faces"
            // Keyed by file as well, so one file's boxes are never laid over another's.
            let key = "\(url.path)|\(find)"
            if redactions?.key != key {
                redactions = (key, try await OCR.regions(in: image, faces: find != "text", text: find != "faces"))
            }
            extra = redactions?.boxes ?? []
            if extra.isEmpty { text = "Nothing to cover was found" }
        }
        let boxes = extra
        let scale = src.scale
        let original = src.originalSize
        let result: CGImage? = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            switch tool {
            case .editImage:
                return ImageOps.render(ImageOps.adjusted(ImageOps.ciImage(image), ConvertTools.adjustments(v)))
            case .frameImage:
                return ImageOps.framed(image, options: ConvertTools.frameOptions(v, scale: scale))
            case .cropImage:
                let ratio = CGFloat(Double(v.s["ratio"] ?? "1") ?? 1)
                let w = CGFloat(image.width), h = CGFloat(image.height)
                let size = w / h > ratio ? CGSize(width: h * ratio, height: h) : CGSize(width: w, height: w / ratio)
                return image.cropping(to: CGRect(x: (w - size.width) / 2, y: (h - size.height) / 2,
                                                 width: size.width, height: size.height).integral)
            case .rotateImage:
                return try? ImageOps.rotated(image, quarterTurns: Int(v.s["turn"] ?? "1") ?? 1,
                                             flipHorizontal: v.b["flipH"] ?? false, flipVertical: v.b["flipV"] ?? false)
            case .resizeImage:
                return image
            case .redactImage:
                guard !boxes.isEmpty else { return image }
                let style = RedactionStyle(rawValue: v.s["style"] ?? "blur") ?? .blur
                let w = CGFloat(image.width), h = CGFloat(image.height)
                let list = boxes.map { b -> Redaction in
                    let pad = max(b.width * w, b.height * h) * 0.1
                    return Redaction(rect: CGRect(x: b.minX * w - pad, y: (1 - b.maxY) * h - pad,
                                                  width: b.width * w + pad * 2, height: b.height * h + pad * 2), style: style)
                }
                return ImageOps.render(ImageOps.redact(ImageOps.ciImage(image), redactions: list))
            default:
                return nil
            }
        }.value
        if tool == .resizeImage {
            let edge = Double(Int(v.s["edge"] ?? "1080") ?? 1080)
            let longest = max(original.width, original.height)
            let factor = min(1, edge / max(1, longest))
            text = "\(Int(original.width)) × \(Int(original.height)) → \(Int((original.width * factor).rounded())) × \(Int((original.height * factor).rounded()))"
        } else if tool == .cropImage || tool == .rotateImage || tool == .frameImage, let result, text.isEmpty {
            let w = CGFloat(result.width) / scale, h = CGFloat(result.height) / scale
            text = "\(Int(w.rounded())) × \(Int(h.rounded()))"
        }
        publish(result, original: image, caption: text)
    }

    private func renderCollage(urls: [URL], values v: ToolValues) async throws {
        let pick = Array(urls.prefix(6))
        let images: [CGImage]
        if let collage, collage.urls == pick { images = collage.images }
        else {
            images = try await Task.detached(priority: .userInitiated) { try pick.map { try ImageIOBridge.load($0, maxPixelSize: 600) } }.value
            collage = (pick, images)
        }
        let layout = ImageOps.CollageLayout(rawValue: v.s["layout"] ?? "grid") ?? .grid
        let spacing = CGFloat(v.n["spacing"] ?? 24)
        let result: CGImage? = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            var options = ImageOps.CollageOptions()
            options.layout = layout
            // The real collage is 2400 points square; this one is 720, so everything shrinks by a third.
            options.width = 720; options.height = 720
            options.spacing = spacing * 0.3
            options.cornerRadius = 16 * 0.3
            return ImageOps.collage(images, options: options)
        }.value
        publish(result, original: nil, caption: urls.count > 6 ? "First 6 of \(urls.count)" : "")
    }

    // MARK: Video

    private func renderVideo(_ tool: ToolID, url: URL, values v: ToolValues) async throws {
        let info = await MediaInfo.load(url)
        let start = tool == .trimVideo ? min(max(0, v.n["start"] ?? 0), max(0, info.duration - 0.1)) : info.duration * 0.1
        let edge = Self.maxEdge
        let frame = try await Task.detached(priority: .userInitiated) { () -> CGImage in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: edge, height: edge)
            return try await generator.image(at: CMTime(seconds: start, preferredTimescale: 600)).image
        }.value
        var result = frame
        var text = ""
        if tool == .cropVideo {
            let ratio = CGFloat(Double(v.s["ratio"] ?? "1") ?? 1)
            let w = CGFloat(frame.width), h = CGFloat(frame.height)
            let size = w / h > ratio ? CGSize(width: h * ratio, height: h) : CGSize(width: w, height: w / ratio)
            result = frame.cropping(to: CGRect(x: (w - size.width) / 2, y: (h - size.height) / 2,
                                               width: size.width, height: size.height).integral) ?? frame
        } else {
            let end = (v.n["end"] ?? 0) > 0 ? min(v.n["end"] ?? 0, info.duration) : info.duration
            text = "\(Self.clock(start)) – \(Self.clock(end)) · \(Self.clock(max(0, end - start)))"
        }
        publish(result, original: tool == .cropVideo ? frame : nil, caption: text)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
