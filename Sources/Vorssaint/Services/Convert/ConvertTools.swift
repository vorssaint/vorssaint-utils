// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import CoreImage
import Foundation
import PDFKit
import Vision

/// What a tool asks for, drawn by the island's options pane. Values live in
/// `ToolValues` under each field's id.
struct ToolField: Identifiable {
    enum Kind {
        /// One of a few labelled choices; the stored value is the second string.
        case chips([(String, String)], defaultValue: String)
        case slider(ClosedRange<Double>, step: Double, unit: String, defaultValue: Double)
        case number(unit: String, defaultValue: Double)
        case toggle(defaultValue: Bool)
        case text(placeholder: String)
    }
    let id: String
    let title: String
    let kind: Kind
    var showsFor: (ToolID, [FileFormat]) -> Bool = { _, _ in true }
}

struct ToolValues: Equatable {
    var n: [String: Double] = [:]
    var s: [String: String] = [:]
    var b: [String: Bool] = [:]
}

/// The tools, their fields and what each does, over Open Tangerine's operations.
enum ConvertTools {
    /// Tools the island runs. Redacting video or audio and editing PDF text need a
    /// canvas to draw on, so they are not offered here.
    static let unsupported: Set<ToolID> = [.redactVideo, .annotatePDF]

    static func available(for formats: [FileFormat]) -> [ToolID] {
        ToolID.available(for: formats).filter { !unsupported.contains($0) }
    }

    static func fields(for tool: ToolID, formats: [FileFormat]) -> [ToolField] {
        let isImage = formats.first?.category == .image
        switch tool {
        case .compress:
            var list = [ToolField(id: "preset", title: "Strength", kind: .chips([("Balanced", "balanced"), ("Strong", "strong")], defaultValue: "balanced"))]
            if isImage {
                list.append(ToolField(id: "edge", title: "Longest side", kind: .chips([("Original", "0"), ("2048", "2048"), ("1080", "1080"), ("720", "720")], defaultValue: "0")))
            }
            return list
        case .editMetadata:
            return [ToolField(id: "mode", title: "Remove", kind: .chips([("Everything", "all"), ("Location & device", "sensitive")], defaultValue: "all"))]
        case .editImage:
            return [
                ToolField(id: "exposure", title: "Exposure", kind: .slider(-2...2, step: 0.05, unit: "", defaultValue: 0)),
                ToolField(id: "contrast", title: "Contrast", kind: .slider(0.5...1.5, step: 0.01, unit: "", defaultValue: 1)),
                ToolField(id: "saturation", title: "Saturation", kind: .slider(0...2, step: 0.01, unit: "", defaultValue: 1)),
                ToolField(id: "sharpness", title: "Sharpness", kind: .slider(0...2, step: 0.05, unit: "", defaultValue: 0)),
                ToolField(id: "vignette", title: "Vignette", kind: .slider(0...1, step: 0.01, unit: "", defaultValue: 0)),
                ToolField(id: "mono", title: "Black and white", kind: .toggle(defaultValue: false)),
            ]
        case .frameImage:
            return [
                ToolField(id: "aspect", title: "Shape", kind: .chips([("Same", "0"), ("1:1", "1"), ("4:3", "1.3333"), ("16:9", "1.7778"), ("9:16", "0.5625")], defaultValue: "0")),
                ToolField(id: "bg", title: "Background", kind: .chips([("White", "white"), ("Black", "black"), ("Sunset", "sunset"), ("Ocean", "ocean")], defaultValue: "white")),
                ToolField(id: "padding", title: "Space around", kind: .slider(0...0.3, step: 0.01, unit: "", defaultValue: 0.08)),
                ToolField(id: "corner", title: "Rounded corners", kind: .slider(0...80, step: 1, unit: "px", defaultValue: 24)),
            ]
        case .cropImage:
            return [ToolField(id: "ratio", title: "Crop to", kind: .chips([("1:1", "1"), ("4:3", "1.3333"), ("3:2", "1.5"), ("16:9", "1.7778"), ("3:4", "0.75"), ("9:16", "0.5625")], defaultValue: "1"))]
        case .redactImage:
            return [
                ToolField(id: "find", title: "Find", kind: .chips([("Faces", "faces"), ("Text", "text"), ("Both", "both")], defaultValue: "faces")),
                ToolField(id: "style", title: "Cover with", kind: .chips([("Black", "solid"), ("Blur", "blur"), ("Pixels", "pixelate")], defaultValue: "blur")),
            ]
        case .removeBackground:
            return []
        case .upscaleImage:
            return [ToolField(id: "factor", title: "Make it", kind: .chips([("2×", "2"), ("3×", "3"), ("4×", "4")], defaultValue: "2"))]
        case .copyText, .extractArchive:
            return []
        case .resizeImage:
            return [ToolField(id: "edge", title: "Longest side", kind: .chips([("4096", "4096"), ("2048", "2048"), ("1080", "1080"), ("720", "720"), ("512", "512")], defaultValue: "1080"))]
        case .rotateImage:
            return [
                ToolField(id: "turn", title: "Turn", kind: .chips([("90° right", "1"), ("180°", "2"), ("90° left", "3"), ("None", "0")], defaultValue: "1")),
                ToolField(id: "flipH", title: "Flip left to right", kind: .toggle(defaultValue: false)),
                ToolField(id: "flipV", title: "Flip top to bottom", kind: .toggle(defaultValue: false)),
            ]
        case .createPDF, .mergePDF, .joinVideos:
            return []
        case .createCollage:
            return [
                ToolField(id: "layout", title: "Layout", kind: .chips([("Grid", "grid"), ("Row", "row"), ("Column", "column"), ("Featured", "featured")], defaultValue: "grid")),
                ToolField(id: "spacing", title: "Spacing", kind: .slider(0...80, step: 1, unit: "px", defaultValue: 24)),
            ]
        case .trimVideo, .trimAudio:
            return [
                ToolField(id: "start", title: "Start", kind: .number(unit: "s", defaultValue: 0)),
                ToolField(id: "end", title: "End", kind: .number(unit: "s", defaultValue: 0)),
            ]
        case .cropVideo:
            return [ToolField(id: "ratio", title: "Crop to", kind: .chips([("1:1", "1"), ("4:3", "1.3333"), ("16:9", "1.7778"), ("9:16", "0.5625")], defaultValue: "1"))]
        case .changeVideoSpeed:
            return [
                ToolField(id: "factor", title: "Speed", kind: .chips([("½×", "0.5"), ("¾×", "0.75"), ("1.25×", "1.25"), ("1.5×", "1.5"), ("2×", "2"), ("4×", "4")], defaultValue: "2")),
                ToolField(id: "pitch", title: "Keep the pitch", kind: .toggle(defaultValue: true)),
            ]
        case .videoSnapshots:
            return [
                ToolField(id: "interval", title: "Take a picture", kind: .chips([("Every second", "1"), ("Every 5 s", "5"), ("Every 10 s", "10"), ("Every frame", "frame")], defaultValue: "1")),
                ToolField(id: "format", title: "Picture format", kind: .chips([("JPG", "jpg"), ("PNG", "png")], defaultValue: "jpg")),
                ToolField(id: "max", title: "Stop after", kind: .number(unit: "pictures", defaultValue: 100)),
            ]
        case .splitVideo:
            return [ToolField(id: "every", title: "A part every", kind: .chips([("30 s", "30"), ("1 min", "60"), ("5 min", "300"), ("10 min", "600")], defaultValue: "60"))]
        case .normalizeAudio:
            return [ToolField(id: "lufs", title: "Loudness", kind: .chips([("Streaming −14", "-14"), ("Podcast −16", "-16"), ("Broadcast −23", "-23")], defaultValue: "-16"))]
        case .audioChannels:
            return [ToolField(id: "mode", title: "Channels", kind: .chips([("Mono", "mono"), ("Swap", "swap"), ("Left", "leftOnly"), ("Right", "rightOnly")], defaultValue: "mono"))]
        case .redactAudio:
            return [ToolField(id: "ranges", title: "Bleep these times", kind: .text(placeholder: "0:10-0:12, 1:05-1:08"))]
        case .audioToVideo:
            return [
                ToolField(id: "style", title: "Look", kind: .chips([("Waveform", "waveform"), ("Bars", "bars")], defaultValue: "waveform")),
                ToolField(id: "orientation", title: "Shape", kind: .chips([("Wide", "landscape"), ("Tall", "portrait"), ("Square", "square")], defaultValue: "landscape")),
            ]
        case .organizePDF:
            return [
                ToolField(id: "op", title: "Do", kind: .chips([("Turn right", "right"), ("Turn left", "left"), ("Reverse order", "reverse"), ("Remove pages", "remove")], defaultValue: "right")),
                ToolField(id: "pages", title: "Pages to remove", kind: .text(placeholder: "2, 5-7")),
            ]
        case .splitPDF:
            return [
                ToolField(id: "mode", title: "Split", kind: .chips([("Each page", "everyPage"), ("Every N", "everyN"), ("Ranges", "ranges")], defaultValue: "everyPage")),
                ToolField(id: "every", title: "Pages per file", kind: .number(unit: "pages", defaultValue: 2)),
                ToolField(id: "ranges", title: "Ranges", kind: .text(placeholder: "1-3, 4-9")),
            ]
        case .redactVideo, .annotatePDF:
            return []
        }
    }

    static func defaults(for tool: ToolID, formats: [FileFormat]) -> ToolValues {
        var values = ToolValues()
        for field in fields(for: tool, formats: formats) {
            switch field.kind {
            case .chips(_, let d): values.s[field.id] = d
            case .slider(_, _, _, let d), .number(_, let d): values.n[field.id] = d
            case .toggle(let d): values.b[field.id] = d
            case .text: values.s[field.id] = ""
            }
        }
        return values
    }

    /// The photo edit's settings; the preview and the run read them the same way.
    static func adjustments(_ v: ToolValues) -> PhotoAdjustments {
        var a = PhotoAdjustments()
        a.exposure = v.n["exposure"] ?? 0; a.contrast = v.n["contrast"] ?? 1; a.saturation = v.n["saturation"] ?? 1
        a.sharpness = v.n["sharpness"] ?? 0; a.vignette = v.n["vignette"] ?? 0; a.monochrome = v.b["mono"] ?? false
        return a
    }

    /// The background tool's settings. `scale` shrinks the pixel-sized corner for a reduced copy.
    static func frameOptions(_ v: ToolValues, scale: CGFloat = 1) -> ImageOps.FrameOptions {
        var options = ImageOps.FrameOptions()
        let aspect = Double(v.s["aspect"] ?? "0") ?? 0
        options.aspect = aspect > 0 ? CGSize(width: aspect, height: 1) : nil
        options.padding = CGFloat(v.n["padding"] ?? 0.08)
        options.cornerRadius = CGFloat(v.n["corner"] ?? 24) * scale
        options.shadow *= scale
        switch v.s["bg"] {
        case "black": options.background = .color(.black)
        case "sunset": options.background = .gradient(NSColor(red: 1, green: 0.55, blue: 0.3, alpha: 1), NSColor(red: 0.8, green: 0.2, blue: 0.5, alpha: 1), angle: 45)
        case "ocean": options.background = .gradient(NSColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1), NSColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1), angle: 45)
        default: options.background = .color(.white)
        }
        return options
    }

    /// The trim fields start at the whole file.
    static func prepare(_ tool: ToolID, urls: [URL], values: inout ToolValues) async {
        guard tool == .trimVideo || tool == .trimAudio, let url = urls.first else { return }
        let info = await MediaInfo.load(url)
        if info.duration.isFinite, info.duration > 0 { values.n["end"] = (info.duration * 10).rounded() / 10 }
    }
}

// MARK: Running

enum ConvertToolRunner {
    private static func out(_ source: URL, suffix: String, ext: String) -> URL {
        ConversionMatrix.uniqueURL(directory: AppSettings.shared.outputLocation.directory(for: source),
                                   baseName: ConversionMatrix.strippedBaseName(source.lastPathComponent), suffix: suffix, ext: ext)
    }

    private static func folder(_ source: URL, name: String) -> URL {
        ConversionMatrix.uniqueDirectory(directory: AppSettings.shared.outputLocation.directory(for: source), name: name)
    }

    /// An image written back in its own format, or PNG where that cannot be written.
    private static func imageFormat(_ url: URL) -> FileFormat {
        switch FileFormat.detect(url) {
        case .jpg?: return .jpg
        case .tiff?: return .tiff
        case .bmp?: return .bmp
        case .heic?: return .heic
        case .webp?: return .webp
        default: return .png
        }
    }

    private static func writeImage(_ image: CGImage, like source: URL, suffix: String, forcePNG: Bool = false) async throws -> URL {
        let format = forcePNG ? FileFormat.png : imageFormat(source)
        let destination = out(source, suffix: suffix, ext: format.fileExtension)
        try await ImageIOBridge.writeAnyFormat(image, to: destination, format: format, quality: AppSettings.shared.jpegQuality)
        return destination
    }

    private static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    /// Queues the tool's jobs. One per file for tools that act on each file,
    /// one in all for tools that combine them.
    @MainActor
    static func run(_ tool: ToolID, urls: [URL], values v: ToolValues) {
        let runner = JobRunner.shared
        let formats = urls.compactMap(FileFormat.detect)
        func each(_ work: @escaping (URL, @escaping (Double) -> Void) async throws -> [URL]) {
            for url in urls {
                runner.run(title: tool.progressTitle, detail: url.lastPathComponent, symbol: tool.symbol) { progress in try await work(url, progress) }
            }
        }
        func combined(_ detail: String, _ work: @escaping (@escaping (Double) -> Void) async throws -> [URL]) {
            runner.run(title: tool.progressTitle, detail: detail, symbol: tool.symbol, work: work)
        }
        let first = urls[0]
        switch tool {
        case .compress:
            let preset: CompressionPreset = v.s["preset"] == "strong" ? .strong : .balanced
            let edge = Int(v.s["edge"] ?? "0") ?? 0
            each { url, progress in
                let format = Compressor.outputFormat(for: url)
                let destination = out(url, suffix: "compressed", ext: format.fileExtension)
                try await Compressor.compress(url, preset: preset, resizeLongEdge: edge, targetBytes: nil, to: destination, progress: progress)
                return [destination]
            }
        case .editMetadata:
            let sensitive = v.s["mode"] == "sensitive"
            each { url, progress in
                let destination = out(url, suffix: "clean", ext: url.pathExtension)
                try await MetadataOps.write(url, edits: [], removeAll: !sensitive, removeSensitive: sensitive, to: destination, progress: progress)
                return [destination]
            }
        case .editImage:
            let a = ConvertTools.adjustments(v)
            each { url, _ in
                let image = try ImageIOBridge.load(url)
                guard let result = ImageOps.render(ImageOps.adjusted(ImageOps.ciImage(image), a)) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
                return [try await writeImage(result, like: url, suffix: "edited")]
            }
        case .frameImage:
            let options = ConvertTools.frameOptions(v)
            each { url, _ in
                let image = try ImageIOBridge.load(url)
                guard let result = ImageOps.framed(image, options: options) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
                return [try await writeImage(result, like: url, suffix: "framed", forcePNG: true)]
            }
        case .cropImage:
            let ratio = CGFloat(Double(v.s["ratio"] ?? "1") ?? 1)
            each { url, _ in
                let image = try ImageIOBridge.load(url)
                let w = CGFloat(image.width), h = CGFloat(image.height)
                let size = w / h > ratio ? CGSize(width: h * ratio, height: h) : CGSize(width: w, height: w / ratio)
                let rect = CGRect(x: (w - size.width) / 2, y: (h - size.height) / 2, width: size.width, height: size.height).integral
                guard let cropped = image.cropping(to: rect) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
                return [try await writeImage(cropped, like: url, suffix: "cropped")]
            }
        case .redactImage:
            let find = v.s["find"] ?? "faces"
            let style = RedactionStyle(rawValue: v.s["style"] ?? "blur") ?? .blur
            each { url, _ in
                let image = try ImageIOBridge.load(url)
                let boxes = try await OCR.regions(in: image, faces: find != "text", text: find != "faces")
                guard !boxes.isEmpty else { throw OpenTangerineError.invalidInput("Nothing to cover was found in this picture.") }
                let w = CGFloat(image.width), h = CGFloat(image.height)
                let redactions = boxes.map { b -> Redaction in
                    let pad = max(b.width * w, b.height * h) * 0.1
                    let rect = CGRect(x: b.minX * w - pad, y: (1 - b.maxY) * h - pad, width: b.width * w + pad * 2, height: b.height * h + pad * 2)
                    return Redaction(rect: rect, style: style)
                }
                guard let result = ImageOps.render(ImageOps.redact(ImageOps.ciImage(image), redactions: redactions)) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
                return [try await writeImage(result, like: url, suffix: "redacted")]
            }
        case .removeBackground:
            each { url, _ in
                let image = try ImageIOBridge.load(url)
                let result = try await Task.detached(priority: .userInitiated) { () -> CGImage in
                    let request = VNGenerateForegroundInstanceMaskRequest()
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])
                    guard let observation = request.results?.first else { throw OpenTangerineError.invalidInput("No subject was found in this picture.") }
                    let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
                    guard let cut = ImageOps.render(CIImage(cvPixelBuffer: buffer)) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
                    return cut
                }.value
                return [try await writeImage(result, like: url, suffix: "no background", forcePNG: true)]
            }
        case .upscaleImage:
            let factor = CGFloat(Double(v.s["factor"] ?? "2") ?? 2)
            each { url, _ in
                let image = try ImageIOBridge.load(url)
                guard factor * CGFloat(max(image.width, image.height)) <= 16_384 else { throw OpenTangerineError.invalidInput("The result would be larger than 16,384 pixels.") }
                let scaled = ImageOps.ciImage(image).applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: factor, kCIInputAspectRatioKey: 1])
                let sharp = scaled.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.4])
                guard let result = ImageOps.render(sharp) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
                return [try await writeImage(result, like: url, suffix: "\(Int(factor))x")]
            }
        case .copyText:
            combined("\(urls.count) file\(urls.count == 1 ? "" : "s")") { progress in
                var text = ""
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    if FileFormat.detect(url) == .pdf, let document = PDFDocument(url: url) {
                        for page in 0..<document.pageCount {
                            if let content = document.page(at: page)?.string, !content.isEmpty { text += content + "\n" }
                            else if let p = document.page(at: page), let image = PDFRenderer.render(page: p) { text += try await OCR.recognize(image) + "\n" }
                        }
                    } else {
                        text += try await OCR.recognize(try ImageIOBridge.load(url)) + "\n"
                    }
                    progress(Double(index + 1) / Double(urls.count))
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenTangerineError.invalidInput("No text was found.") }
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                return []
            }
        case .extractArchive:
            each { url, progress in
                let staging = try await ArchiveSafety.extractSafely(url)
                defer { try? FileManager.default.removeItem(at: staging) }
                let destination = folder(url, name: ConversionMatrix.strippedBaseName(url.lastPathComponent))
                try FileManager.default.moveItem(at: staging, to: destination)
                progress(1)
                return [destination]
            }
        case .resizeImage:
            let edge = Int(v.s["edge"] ?? "1080") ?? 1080
            each { url, _ in [try await writeImage(try ImageIOBridge.load(url, maxPixelSize: edge), like: url, suffix: "\(edge)px")] }
        case .rotateImage:
            let turns = Int(v.s["turn"] ?? "1") ?? 1
            let flipH = v.b["flipH"] ?? false, flipV = v.b["flipV"] ?? false
            each { url, _ in
                let image = try ImageOps.rotated(try ImageIOBridge.load(url), quarterTurns: turns, flipHorizontal: flipH, flipVertical: flipV)
                return [try await writeImage(image, like: url, suffix: "rotated")]
            }
        case .createPDF:
            combined("\(urls.count) image\(urls.count == 1 ? "" : "s")") { progress in
                let destination = out(first, suffix: urls.count > 1 ? "combined" : "", ext: "pdf")
                try PDFOps.fromImages(urls, to: destination, progress: progress)
                return [destination]
            }
        case .createCollage:
            var options = ImageOps.CollageOptions()
            options.layout = ImageOps.CollageLayout(rawValue: v.s["layout"] ?? "grid") ?? .grid
            options.spacing = CGFloat(v.n["spacing"] ?? 24)
            combined("\(urls.count) pictures") { _ in
                let images = try urls.map { try ImageIOBridge.load($0) }
                guard let result = ImageOps.collage(images, options: options) else { throw OpenTangerineError.encodeFailed("collage") }
                return [try await writeImage(result, like: first, suffix: "collage", forcePNG: true)]
            }
        case .trimVideo:
            let start = v.n["start"] ?? 0, end = v.n["end"] ?? 0
            each { url, progress in
                let destination = out(url, suffix: "trimmed", ext: url.pathExtension)
                try await VideoOps.trim(url, start: start, end: end, to: destination, progress: progress)
                return [destination]
            }
        case .trimAudio:
            let start = v.n["start"] ?? 0, end = v.n["end"] ?? 0
            each { url, progress in
                let format = AudioOps.outputFormat(for: url)
                let destination = out(url, suffix: "trimmed", ext: format.fileExtension)
                try await AudioOps.trim(url, start: start, end: end, to: destination, format: format, progress: progress)
                return [destination]
            }
        case .cropVideo:
            let ratio = CGFloat(Double(v.s["ratio"] ?? "1") ?? 1)
            each { url, progress in
                let info = await MediaInfo.load(url)
                let w = info.naturalSize.width, h = info.naturalSize.height
                guard w > 0, h > 0 else { throw OpenTangerineError.invalidInput("This video's size could not be read.") }
                let size = w / h > ratio ? CGSize(width: h * ratio, height: h) : CGSize(width: w, height: w / ratio)
                let rect = CGRect(x: ((w - size.width) / 2).rounded(), y: ((h - size.height) / 2).rounded(), width: (size.width / 2).rounded() * 2, height: (size.height / 2).rounded() * 2)
                let destination = out(url, suffix: "cropped", ext: "mp4")
                try await VideoOps.crop(url, rect: rect, outputSize: nil, to: destination, progress: progress)
                return [destination]
            }
        case .changeVideoSpeed:
            let factor = Double(v.s["factor"] ?? "2") ?? 2
            let pitch = v.b["pitch"] ?? true
            each { url, progress in
                let destination = out(url, suffix: "\(v.s["factor"] ?? "2")x", ext: "mp4")
                try await VideoOps.changeSpeed(url, factor: factor, preservePitch: pitch, to: destination, progress: progress)
                return [destination]
            }
        case .joinVideos:
            combined("\(urls.count) videos") { progress in
                let destination = out(first, suffix: "joined", ext: "mp4")
                try await VideoOps.join(urls, to: destination, progress: progress)
                return [destination]
            }
        case .videoSnapshots:
            let ext = v.s["format"] ?? "jpg"
            let maxCount = max(1, Int(v.n["max"] ?? 100))
            let intervalSetting = v.s["interval"] ?? "1"
            each { url, progress in
                let info = await MediaInfo.load(url)
                guard info.duration > 0 else { throw OpenTangerineError.invalidInput("This video's length could not be read.") }
                let step = intervalSetting == "frame" ? 1 / max(1, info.frameRate > 0 ? info.frameRate : 25) : Double(intervalSetting) ?? 1
                let directory = folder(url, name: "\(ConversionMatrix.strippedBaseName(url.lastPathComponent)) frames")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var time = 0.0, count = 0
                while time < info.duration, count < maxCount {
                    try Task.checkCancellation()
                    let image = try await VideoOps.snapshot(url, at: time)
                    count += 1
                    try ImageIOBridge.write(image, to: directory.appendingPathComponent(String(format: "frame-%04d.%@", locale: Locale(identifier: "en_US_POSIX"), count, ext)),
                                            format: ext == "png" ? .png : .jpg, quality: 0.9)
                    time += step
                    progress(min(1, Double(count) / Double(min(maxCount, max(1, Int(info.duration / step))))))
                }
                return [directory]
            }
        case .splitVideo:
            let every = Double(v.s["every"] ?? "60") ?? 60
            each { url, progress in
                let info = await MediaInfo.load(url)
                guard info.duration > every else { throw OpenTangerineError.invalidInput("The video is shorter than one part.") }
                let points = stride(from: every, to: info.duration, by: every).map { $0 }
                let directory = folder(url, name: "\(ConversionMatrix.strippedBaseName(url.lastPathComponent)) parts")
                return try await VideoOps.split(url, at: points, duration: info.duration, into: directory, progress: progress)
            }
        case .normalizeAudio:
            let target = Double(v.s["lufs"] ?? "-16") ?? -16
            each { url, progress in
                let format = AudioOps.outputFormat(for: url)
                let destination = out(url, suffix: "normalized", ext: format.fileExtension)
                try await AudioOps.normalize(url, targetLUFS: target, range: 7, truePeak: -1.5, to: destination, format: format, progress: progress)
                return [destination]
            }
        case .audioChannels:
            let mode = AudioOps.ChannelMode(rawValue: v.s["mode"] ?? "mono") ?? .mono
            each { url, progress in
                let format = AudioOps.outputFormat(for: url)
                let destination = out(url, suffix: mode.rawValue, ext: format.fileExtension)
                try await AudioOps.convertChannels(url, mode: mode, leftGain: 1, rightGain: 1, to: destination, format: format, progress: progress)
                return [destination]
            }
        case .redactAudio:
            let ranges = (v.s["ranges"] ?? "").split(separator: ",").compactMap { part -> AudioOps.BleepRange? in
                let ends = part.split(separator: "-").map(String.init)
                guard ends.count == 2, let a = seconds(ends[0]), let b = seconds(ends[1]), b > a else { return nil }
                return AudioOps.BleepRange(start: a, end: b)
            }
            each { url, progress in
                let format = AudioOps.outputFormat(for: url)
                let destination = out(url, suffix: "bleeped", ext: format.fileExtension)
                try await AudioOps.bleep(url, ranges: ranges, frequency: 1000, to: destination, format: format, progress: progress)
                return [destination]
            }
        case .audioToVideo:
            let style = AudioOps.VisualizerStyle(rawValue: v.s["style"] ?? "waveform") ?? .waveform
            let orientation = AudioOps.VisualizerOrientation(rawValue: v.s["orientation"] ?? "landscape") ?? .landscape
            each { url, progress in
                let destination = out(url, suffix: "visualizer", ext: "mp4")
                try await AudioOps.visualize(url, style: style, orientation: orientation, accent: "0xFF9F40", background: "0x101018", image: nil, to: destination, progress: progress)
                return [destination]
            }
        case .mergePDF:
            combined("\(urls.count) PDFs") { _ in
                let destination = out(first, suffix: "merged", ext: "pdf")
                try PDFOps.merge(urls, to: destination)
                return [destination]
            }
        case .organizePDF:
            let op = v.s["op"] ?? "right"
            let pagesText = v.s["pages"] ?? ""
            each { url, _ in
                let document = try PDFOps.document(url)
                var pages = (0..<document.pageCount).map { PDFPageRef(sourceIndex: $0, rotation: 0, sourceURL: url) }
                switch op {
                case "right": pages = pages.map { var p = $0; p.rotation = 90; return p }
                case "left": pages = pages.map { var p = $0; p.rotation = 270; return p }
                case "reverse": pages.reverse()
                default:
                    let drop = Set(PDFOps.parseRanges(pagesText, pageCount: document.pageCount).flatMap { Array($0) })
                    guard !drop.isEmpty, drop.count < pages.count else { throw OpenTangerineError.invalidInput("Choose pages to remove, such as 2, 5-7.") }
                    pages = pages.enumerated().filter { !drop.contains($0.offset + 1) }.map(\.element)
                }
                let destination = out(url, suffix: "organized", ext: "pdf")
                try PDFOps.assemble(pages: pages, to: destination)
                return [destination]
            }
        case .splitPDF:
            let mode = PDFOps.SplitMode(rawValue: v.s["mode"] ?? "everyPage") ?? .everyPage
            let every = Int(v.n["every"] ?? 2), ranges = v.s["ranges"] ?? ""
            each { url, _ in
                let directory = folder(url, name: "\(ConversionMatrix.strippedBaseName(url.lastPathComponent)) pages")
                return try PDFOps.split(url, mode: mode, every: every, ranges: ranges, into: directory)
            }
        case .redactVideo, .annotatePDF:
            runner.run(title: tool.title, detail: first.lastPathComponent) { _ in throw OpenTangerineError.invalidInput("\(tool.title) is not available in the island.") }
        }
        _ = formats
    }
}

// MARK: File actions

enum ConvertAction: String, CaseIterable, Identifiable {
    case reveal, copy, paths, duplicate, hash, zip, moveTo, copyTo, terminal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .reveal: return "Reveal"
        case .copy: return "Copy files"
        case .paths: return "Copy paths"
        case .duplicate: return "Duplicate"
        case .hash: return "SHA-256"
        case .zip: return "Zip"
        case .moveTo: return "Move to…"
        case .copyTo: return "Copy to…"
        case .terminal: return "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .reveal: return "folder"
        case .copy: return "doc.on.doc"
        case .paths: return "link"
        case .duplicate: return "plus.square.on.square"
        case .hash: return "number"
        case .zip: return "archivebox"
        case .moveTo: return "folder.badge.plus"
        case .copyTo: return "doc.on.doc.fill"
        case .terminal: return "terminal"
        }
    }

    /// Runs the action. Most finish at once and return a short note for the island;
    /// zip and duplicate go through the queue and show their progress.
    @MainActor
    func run(_ urls: [URL]) -> String {
        guard let first = urls.first else { return "" }
        switch self {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return "Shown in Finder"
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
            return "Copied \(urls.count) file\(urls.count == 1 ? "" : "s")"
        case .paths:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            return "Paths copied"
        case .duplicate:
            JobRunner.shared.run(title: "Duplicating", detail: "\(urls.count) file\(urls.count == 1 ? "" : "s")", symbol: symbol) { _ in
                try FileAction.duplicateFiles(urls)
            }
            return ""
        case .hash:
            JobRunner.shared.run(title: "Checksum", detail: "SHA-256 of \(urls.count) file\(urls.count == 1 ? "" : "s")", symbol: symbol) { _ in
                let report = try await Task.detached(priority: .userInitiated) { try FileAction.hashReport(urls) }.value
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                return []
            }
            return ""
        case .zip:
            JobRunner.shared.run(title: "Zipping", detail: "\(urls.count) item\(urls.count == 1 ? "" : "s")", symbol: symbol) { progress in
                let destination = ConversionMatrix.uniqueURL(directory: first.deletingLastPathComponent(),
                                                             baseName: urls.count == 1 ? ConversionMatrix.strippedBaseName(first.lastPathComponent) : "Archive", suffix: "", ext: "zip")
                let result = try await ConvertShell.run("/usr/bin/zip", ["-q", "-r", "-j", destination.path] + urls.map(\.path))
                guard result.succeeded else { throw OpenTangerineError.toolFailed("zip", result.stderr) }
                progress(1)
                return [destination]
            }
            return ""
        case .moveTo, .copyTo:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = self == .moveTo ? "Move here" : "Copy here"
            guard panel.runModal() == .OK, let folder = panel.url else { return "" }
            let moving = self == .moveTo
            JobRunner.shared.run(title: moving ? "Moving" : "Copying", detail: "\(urls.count) file\(urls.count == 1 ? "" : "s")", symbol: symbol) { _ in
                try urls.map { url in
                    let destination = ConversionMatrix.uniqueURL(directory: folder, baseName: ConversionMatrix.strippedBaseName(url.lastPathComponent), suffix: "", ext: url.pathExtension)
                    if moving { try FileManager.default.moveItem(at: url, to: destination) } else { try FileManager.default.copyItem(at: url, to: destination) }
                    return destination
                }
            }
            return ""
        case .terminal:
            let folder = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
            NSWorkspace.shared.open([folder], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
            return "Opened Terminal"
        }
    }
}
