// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Deterministic helper for the vorssaint-companion skill: plans a run, cuts
// generated sprite sheets into stabilised square face frames, writes and
// checks companion.json, renders previews and installs the pack. It never
// draws a face itself; every face pixel comes from an image generator.
//
//   swift companion_tool.swift <command> [options]
//
// Commands: prepare, slice, manifest, validate, preview, install. Run a
// command with --help for its options.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - States

struct StateInfo {
    let name: String
    let loops: Bool
    let fps: Int
    let beats: String
}

let states: [StateInfo] = [
    StateInfo(name: "idle", loops: true, fps: 10, beats: """
        A calm resting loop. Neutral, relaxed expression; very subtle breathing (tiny rise and fall of the head). \
        One natural blink around the middle: eyes half-closed, closed, half-open over consecutive frames, then open. \
        A small glance to one side and back is welcome. The last frame must lead smoothly back into the first.
        """),
    StateInfo(name: "lookRight", loops: true, fps: 10, beats: """
        Travelling to the right of the image: the head is turned about 30 degrees toward the image's right side, \
        eyes looking that way, with a gentle bobbing up and down as if moving along. Keep the turn constant; loop smoothly.
        """),
    StateInfo(name: "lookLeft", loops: true, fps: 10, beats: """
        Travelling to the left of the image: the head is turned about 30 degrees toward the image's left side, \
        eyes looking that way, with a gentle bobbing up and down as if moving along. Keep the turn constant; loop smoothly.
        """),
    StateInfo(name: "sleep", loops: true, fps: 6, beats: """
        Dozing: eyes fully closed, peaceful face, slow breathing with a slight droop of the head and a soft nod. \
        Mouth relaxed, maybe slightly open. Loop smoothly.
        """),
    StateInfo(name: "wink", loops: false, fps: 12, beats: """
        A friendly hello: starts neutral, then one eye closes in a wink with a warm smile, holds the wink for a few \
        frames, and the last frames show a happy smile with both eyes open.
        """),
    StateInfo(name: "happy", loops: false, fps: 12, beats: """
        Delight: starts neutral, eyebrows lift, breaks into a big open smile with happy squinting eyes, a small upward \
        bounce of the head, and holds the joyful expression in the last frames.
        """),
    StateInfo(name: "love", loops: false, fps: 12, beats: """
        Adoration: eyes soften and half-close contentedly, cheeks blush, a loving closed-mouth smile, head tilts \
        slightly; holds the affectionate look at the end. Blush is painted on the cheeks, never floating hearts.
        """),
    StateInfo(name: "surprised", loops: false, fps: 14, beats: """
        Startled: from neutral, eyes widen sharply, eyebrows shoot up, mouth opens into an "o", head pulls back a \
        little; the last frames settle into a curious, still-surprised look.
        """),
    StateInfo(name: "sad", loops: false, fps: 10, beats: """
        Disappointed: eyebrows tilt up in the middle, eyes look down, a small frown forms, the head lowers slightly; \
        the last frames hold the sad look, optionally with a single tear on the cheek touching the face.
        """),
    StateInfo(name: "think", loops: true, fps: 8, beats: """
        Pondering: eyes look up and to one side, a slight head tilt, mouth pursed or to one side, an eyebrow raised; \
        small shifts of the gaze while thinking. Loop smoothly.
        """),
    StateInfo(name: "busy", loops: true, fps: 10, beats: """
        Focused at work: determined eyes looking slightly down as if at a screen, a small frown of concentration, \
        a tiny nod now and then. Loop smoothly.
        """),
    StateInfo(name: "dance", loops: true, fps: 12, beats: """
        Enjoying music: the head bobs on the beat and sways left and right, a big happy smile, eyes closed with joy \
        on some beats. Loop smoothly so the sway is continuous.
        """),
]

let defaultStates = ["idle", "lookRight", "sleep", "wink", "happy", "love", "surprised", "sad", "think", "busy", "dance"]
let canvasSide = 512
let faceFill: CGFloat = 0.86

// MARK: - Arguments

struct Arguments {
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ list: ArraySlice<String>) {
        var index = list.startIndex
        while index < list.endIndex {
            let item = list[index]
            guard item.hasPrefix("--") else { index += 1; continue }
            let key = String(item.dropFirst(2))
            let next = list.index(after: index)
            if next < list.endIndex, !list[next].hasPrefix("--") {
                values[key] = list[next]
                index = list.index(after: next)
            } else {
                flags.insert(key)
                index = next
            }
        }
    }

    func require(_ key: String) -> String {
        guard let value = values[key], !value.isEmpty else { fail("missing --\(key)") }
        return value
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func expand(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

func slug(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics
    let parts = name.lowercased().unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        .split(separator: "-").filter { !$0.isEmpty }
    return parts.isEmpty ? "companion" : parts.joined(separator: "-")
}

// MARK: - Images

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ width: Int, _ height: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot create a \(width)x\(height) canvas")
    }
    context.interpolationQuality = .high
    return context
}

func loadImages(_ url: URL) -> [(image: CGImage, delay: Double?)] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
    return (0..<CGImageSourceGetCount(source)).compactMap { index in
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        return (image, delay(source, index: index))
    }
}

/// An animated image's own delay for a frame, from whichever format it is,
/// as the app reads it.
func delay(_ source: CGImageSource, index: Int) -> Double? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return nil }
    let formats: [(CFString, CFString, CFString)] = [
        (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
        (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
    ]
    for (dictionary, unclamped, clamped) in formats {
        guard let values = properties[dictionary] as? [CFString: Any] else { continue }
        let seconds = (values[unclamped] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? (values[clamped] as? Double)
        if let seconds, seconds > 0 { return max(0.02, seconds) }
    }
    return nil
}

func loadImage(_ url: URL) -> CGImage {
    guard let image = loadImages(url).first?.image else { fail("cannot read image \(url.path)") }
    return image
}

func writePNG(_ image: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

func writeGIF(_ frames: [CGImage], delays: [Double], _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                            frames.count, nil) else { fail("cannot write \(url.path)") }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (frame, delay) in zip(frames, delays) {
        CGImageDestinationAddImage(destination, frame,
                                   [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

/// Straight (not premultiplied) RGBA pixels, top row first.
struct Pixels {
    var width: Int
    var height: Int
    var data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        let canvas = context(width, height)
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let raw = canvas.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        data = Array(UnsafeBufferPointer(start: raw, count: width * height * 4))
        for offset in stride(from: 0, to: data.count, by: 4) where data[offset + 3] > 0 && data[offset + 3] < 255 {
            let alpha = Double(data[offset + 3]) / 255
            for channel in 0..<3 { data[offset + channel] = UInt8(min(255, (Double(data[offset + channel]) / alpha).rounded())) }
        }
    }

    var image: CGImage {
        var premultiplied = data
        for offset in stride(from: 0, to: premultiplied.count, by: 4) where premultiplied[offset + 3] < 255 {
            let alpha = Double(premultiplied[offset + 3]) / 255
            for channel in 0..<3 { premultiplied[offset + channel] = UInt8((Double(premultiplied[offset + channel]) * alpha).rounded()) }
        }
        let canvas = context(width, height)
        premultiplied.withUnsafeBytes { canvas.data!.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        return canvas.makeImage()!
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }

    /// The box around pixels more than a tenth opaque, nil when there are none.
    var bounds: CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) > 25 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The average of the four corners, for a flat backdrop to key out.
    var cornerColor: (Double, Double, Double) {
        let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        let sums = corners.reduce((0.0, 0.0, 0.0)) { sum, corner in
            let offset = (corner.1 * width + corner.0) * 4
            return (sum.0 + Double(data[offset]), sum.1 + Double(data[offset + 1]), sum.2 + Double(data[offset + 2]))
        }
        return (sums.0 / 4 / 255, sums.1 / 4 / 255, sums.2 / 4 / 255)
    }

    var cornersTransparent: Bool {
        [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)].allSatisfy { alpha($0.0, $0.1) < 16 }
    }
}

struct Key {
    var red: Double, green: Double, blue: Double
    var tolerance: Double

    init(red: Double, green: Double, blue: Double, tolerance: Double) {
        self.red = red; self.green = green; self.blue = blue; self.tolerance = tolerance
    }

    init?(_ hex: String, tolerance: Double = 0.16) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
        self.tolerance = tolerance
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    /// Makes the key color transparent, with a soft edge, and pulls its tint
    /// out of the edge pixels so no colored fringe is left.
    func apply(to pixels: inout Pixels) {
        let keyChannels = [red, green, blue].map { $0 > 0.5 }
        for offset in stride(from: 0, to: pixels.data.count, by: 4) {
            let r = Double(pixels.data[offset]) / 255, g = Double(pixels.data[offset + 1]) / 255
            let b = Double(pixels.data[offset + 2]) / 255
            let distance = ((r - red) * (r - red) + (g - green) * (g - green) + (b - blue) * (b - blue)).squareRoot() / 3.0.squareRoot()
            let keep = distance <= tolerance ? 0 : min(1, (distance - tolerance) / (tolerance * 0.5))
            pixels.data[offset + 3] = UInt8((Double(pixels.data[offset + 3]) * keep).rounded())
            guard keep > 0, distance < tolerance * 3 else { continue }
            // Despill: a key channel may not outshine the face's own channels.
            let channels = [r, g, b]
            let others = channels.enumerated().filter { !keyChannels[$0.offset] }.map(\.element)
            guard let ceiling = others.max() else { continue }
            for channel in 0..<3 where keyChannels[channel] && channels[channel] > ceiling {
                pixels.data[offset + channel] = UInt8((ceiling * 255).rounded())
            }
        }
    }
}

// MARK: - Run file

struct Plan: Codable {
    struct Sheet: Codable {
        var state: String
        var frames: Int
        var columns: Int
        var rows: Int
        var width: Int
        var height: Int
        var fps: Int
    }

    var name: String
    var slug: String
    var concept: String
    var style: String
    /// A #RRGGBB chroma key, or "transparent".
    var background: String
    var sheets: [Sheet]
}

func grid(for frames: Int) -> (columns: Int, rows: Int, width: Int, height: Int) {
    switch frames {
    case ...4: return (2, 2, 1024, 1024)
    case 5...6: return (3, 2, 1536, 1024)
    case 7...8: return (4, 2, 1536, 1024)
    case 9...12: return (4, 3, 1536, 1024)
    case 13...16: return (4, 4, 1024, 1024)
    default: return (6, 4, 1536, 1024)
    }
}

func readPlan(_ run: URL) -> Plan {
    guard let data = try? Data(contentsOf: run.appendingPathComponent("run.json")),
          let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
        fail("no readable run.json in \(run.path); run prepare first")
    }
    return plan
}

// MARK: - prepare

func backgroundRule(_ plan: Plan) -> String {
    plan.background == "transparent"
        ? "Background: fully transparent (alpha), with nothing behind the face: no color, gradient, shadow, floor or vignette."
        : "Background: one perfectly flat, solid \(plan.background) color filling everything outside the face, with no gradient, texture, shadow, floor, vignette or lighting falloff. Do not use \(plan.background) or anything close to it anywhere in the face."
}

func basePrompt(_ plan: Plan) -> String {
    """
    Create the reference portrait for an animated character face that lives in a Mac's menu bar.

    Character: \(plan.concept)

    Composition: a single face, head only. No neck, shoulders, body, hands or props below the chin. Front view, \
    looking at the viewer, relaxed neutral expression, eyes open. The face is centered and fills about 80% of a \
    square image, with even margins and nothing cropped (ears, hair and horns fully inside the frame).

    Style: \(plan.style). High quality, smooth and detailed with clean anti-aliased edges, appealing and expressive. \
    Not pixel art, not low resolution, no visible pixels or dithering. Bold, readable features: large clear eyes and \
    a clear mouth that still read when the face is only 20 pixels tall.

    \(backgroundRule(plan))

    Do not include text, logos, watermarks, borders, frames, shadows cast on the background, glow or halo.
    """
}

func sheetPrompt(_ plan: Plan, _ sheet: Plan.Sheet, _ info: StateInfo) -> String {
    """
    Draw a sprite sheet of the character in the attached reference image: \(sheet.columns) columns by \(sheet.rows) \
    rows, exactly \(sheet.frames) frames, read left to right, top to bottom, on a \(sheet.width)x\(sheet.height) image. \
    The cells are equal, with no gaps, borders, grid lines, labels or numbers.

    Animation "\(sheet.state)" (\(info.loops ? "a seamless loop" : "plays once, then holds its last frame")):
    \(info.beats)

    Identity lock: it is exactly the same character as the reference, with the same face shape, colors, markings, \
    hair, accessories, art style, line quality, lighting and rendering. Only the expression and small head motion \
    change from frame to frame.

    Framing: in every cell the face is the same size, centered in its cell, filling about 75% of the cell's \
    shorter side, never touching or crossing the cell's edges. Head only: no neck, body or hands. Consecutive \
    frames change a little, so the sequence plays as smooth animation.

    \(backgroundRule(plan))

    No detached effects: no floating hearts, stars, sparkles, "Z"s, sweat drops, motion lines, speech bubbles or \
    text. Anything extra (a blush, a tear) must be painted on the face itself.

    The attached layout guide only shows where the cells and faces go. Do not draw the guide, its lines or its colors.
    Not pixel art: high quality, smooth, detailed illustration as in the reference.
    """
}

/// A layout-only guide: the cells, and the circle each face should fill.
func guide(_ sheet: Plan.Sheet) -> CGImage {
    let canvas = context(sheet.width, sheet.height)
    canvas.setFillColor(CGColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
    let cellWidth = CGFloat(sheet.width) / CGFloat(sheet.columns), cellHeight = CGFloat(sheet.height) / CGFloat(sheet.rows)
    canvas.setLineWidth(2)
    for index in 0..<(sheet.columns * sheet.rows) {
        let column = index % sheet.columns, row = index / sheet.columns
        let cell = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(sheet.height) - CGFloat(row + 1) * cellHeight,
                          width: cellWidth, height: cellHeight)
        let used = index < sheet.frames
        canvas.setStrokeColor(CGColor(srgbRed: 0.55, green: 0.55, blue: 0.6, alpha: 1))
        canvas.stroke(cell.insetBy(dx: 1, dy: 1))
        guard used else { continue }
        let side = min(cellWidth, cellHeight) * 0.75
        canvas.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.45, blue: 0.9, alpha: 1))
        canvas.strokeEllipse(in: CGRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side))
    }
    return canvas.makeImage()!
}

func prepare(_ args: Arguments) {
    let name = args.require("name")
    let out = expand(args.require("out"))
    let background = args.values["background"] ?? "transparent"
    if background != "transparent", Key(background) == nil { fail("--background must be #RRGGBB or transparent") }
    let defaultFrames = Int(args.values["frames"] ?? "8") ?? 8
    var perState: [String: Int] = [:]
    for item in (args.values["state-frames"] ?? "").split(separator: ",") {
        let parts = item.split(separator: "=")
        if parts.count == 2, let count = Int(parts[1]) { perState[String(parts[0])] = count }
    }
    let wanted = (args.values["states"].map { $0.split(separator: ",").map(String.init) } ?? defaultStates)
    for state in wanted where !states.contains(where: { $0.name == state }) { fail("unknown state \(state)") }
    guard wanted.contains("idle") else { fail("idle is required") }
    let sheets = wanted.map { state -> Plan.Sheet in
        let info = states.first { $0.name == state }!
        let frames = max(2, min(24, perState[state] ?? defaultFrames))
        let layout = grid(for: frames)
        return Plan.Sheet(state: state, frames: frames, columns: layout.columns, rows: layout.rows,
                          width: layout.width, height: layout.height, fps: info.fps)
    }
    let plan = Plan(name: name, slug: args.values["slug"] ?? slug(name),
                    concept: args.values["concept"] ?? name,
                    style: args.values["style"] ?? "polished 2D digital illustration, soft cel shading, gentle highlights",
                    background: background, sheets: sheets)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? FileManager.default.createDirectory(at: out.appendingPathComponent("prompts"), withIntermediateDirectories: true)
    try? encoder.encode(plan).write(to: out.appendingPathComponent("run.json"))
    try? basePrompt(plan).write(to: out.appendingPathComponent("prompts/base.txt"), atomically: true, encoding: .utf8)
    for sheet in sheets {
        let info = states.first { $0.name == sheet.state }!
        try? sheetPrompt(plan, sheet, info).write(to: out.appendingPathComponent("prompts/\(sheet.state).txt"),
                                                  atomically: true, encoding: .utf8)
        writePNG(guide(sheet), out.appendingPathComponent("guides/\(sheet.state).png"))
    }
    print("run: \(out.path)")
    print("pack id: \(plan.slug)")
    for sheet in sheets {
        print("  \(sheet.state): \(sheet.frames) frames, \(sheet.columns)x\(sheet.rows) on \(sheet.width)x\(sheet.height)")
    }
    print("next: generate prompts/base.txt, then each prompts/<state>.txt with the base and guides/<state>.png attached")
}

// MARK: - slice

func median(_ values: [CGFloat]) -> CGFloat {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
}

func slice(_ args: Arguments) {
    let run = expand(args.require("run"))
    let plan = readPlan(run)
    let state = args.require("state")
    guard let sheet = plan.sheets.first(where: { $0.state == state }) else { fail("\(state) is not in run.json") }
    let columns = Int(args.values["columns"] ?? "") ?? sheet.columns
    let rows = Int(args.values["rows"] ?? "") ?? sheet.rows
    let count = Int(args.values["count"] ?? "") ?? sheet.frames
    let source = loadImage(expand(args.require("sheet")))
    let keyText = args.values["key"] ?? plan.background
    let key = keyText == "transparent" ? nil : Key(keyText, tolerance: Double(args.values["tolerance"] ?? "") ?? 0.16)
    let cellWidth = source.width / columns, cellHeight = source.height / rows
    var cells: [(pixels: Pixels, bounds: CGRect)] = []
    var warnings: [String] = []
    for index in 0..<count {
        let rect = CGRect(x: (index % columns) * cellWidth, y: (index / columns) * cellHeight, width: cellWidth, height: cellHeight)
        guard let crop = source.cropping(to: rect) else { fail("cell \(index + 1) is outside the sheet") }
        var pixels = Pixels(crop)
        if let key {
            key.apply(to: &pixels)
        } else if !pixels.cornersTransparent {
            // Asked for transparency, the generator painted a backdrop
            // anyway: key out the flat color in its corners.
            let color = pixels.cornerColor
            Key(red: color.0, green: color.1, blue: color.2, tolerance: 0.12).apply(to: &pixels)
            if index == 0 {
                warnings.append(String(format: "the sheet has no transparency; keyed out its corner color #%02X%02X%02X — check edges in the preview",
                                       Int(color.0 * 255), Int(color.1 * 255), Int(color.2 * 255)))
            }
        }
        guard let bounds = pixels.bounds else { warnings.append("frame \(index + 1) is empty"); continue }
        if bounds.minX <= 1 || bounds.minY <= 1 || bounds.maxX >= CGFloat(pixels.width - 1) || bounds.maxY >= CGFloat(pixels.height - 1) {
            warnings.append("frame \(index + 1) touches its cell's edge: the face may be cropped, or the background is not clean")
        }
        cells.append((pixels, bounds))
    }
    guard !cells.isEmpty else { fail("no frames found in the sheet") }
    // One transform for the whole sheet: the median face size fills the
    // canvas and the median center goes to the middle, so the face is
    // steady from frame to frame and state to state, while the motion drawn
    // inside the sheet stays.
    let side = median(cells.map { max($0.bounds.width, $0.bounds.height) })
    let center = CGPoint(x: median(cells.map { $0.bounds.midX }), y: median(cells.map { $0.bounds.midY }))
    let scale = CGFloat(canvasSide) * faceFill / max(1, side)
    for (index, cell) in cells.enumerated() {
        let offset = hypot(cell.bounds.midX - center.x, cell.bounds.midY - center.y) / side
        if offset > 0.12 { warnings.append(String(format: "frame %d sits %.0f%% of a face away from the others", index + 1, offset * 100)) }
        let sizeChange = abs(max(cell.bounds.width, cell.bounds.height) - side) / side
        if sizeChange > 0.15 { warnings.append(String(format: "frame %d is %.0f%% bigger or smaller than the others", index + 1, sizeChange * 100)) }
    }
    let folder = run.appendingPathComponent("pack/\(state)", isDirectory: true)
    if !args.flags.contains("append") { try? FileManager.default.removeItem(at: folder) }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let existing = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") }.count
    for (index, cell) in cells.enumerated() {
        let canvas = context(canvasSide, canvasSide)
        let width = CGFloat(cell.pixels.width) * scale, height = CGFloat(cell.pixels.height) * scale
        // Pixels count down from the top; Core Graphics counts up.
        let x = CGFloat(canvasSide) / 2 - center.x * scale
        let y = CGFloat(canvasSide) / 2 - (CGFloat(cell.pixels.height) - center.y) * scale
        canvas.draw(cell.pixels.image, in: CGRect(x: x, y: y, width: width, height: height))
        writePNG(canvas.makeImage()!, folder.appendingPathComponent(String(format: "%04d.png", existing + index + 1)))
    }
    print("\(state): wrote \(cells.count) frames to \(folder.path)")
    warnings.forEach { print("warning: \($0)") }
}

// MARK: - manifest

func manifest(_ args: Arguments) {
    let run = expand(args.require("run"))
    let plan = readPlan(run)
    let pack = run.appendingPathComponent("pack", isDirectory: true)
    var animations: [String: Any] = [:]
    for sheet in plan.sheets {
        let folder = pack.appendingPathComponent(sheet.state)
        let frames = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") }
        guard !frames.isEmpty else { print("skipped \(sheet.state): no frames yet"); continue }
        animations[sheet.state] = ["frames": sheet.state, "fps": sheet.fps]
    }
    guard animations["idle"] != nil else { fail("idle has no frames yet") }
    let json: [String: Any] = ["format": 1, "name": plan.name, "description": plan.concept, "animations": animations]
    let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: pack.appendingPathComponent("companion.json"))
    print("wrote \(pack.appendingPathComponent("companion.json").path) with \(animations.keys.sorted().joined(separator: ", "))")
}

// MARK: - validate

struct Animation {
    var name: String
    var frames: [CGImage]
    var delays: [Double]
}

/// Reads a pack as the app does, collecting problems instead of stopping.
func readPack(_ pack: URL, errors: inout [String], warnings: inout [String]) -> (name: String, animations: [Animation]) {
    guard let data = try? Data(contentsOf: pack.appendingPathComponent("companion.json")) else {
        errors.append("no companion.json in \(pack.path)")
        return ("", [])
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        errors.append("companion.json is not a JSON object")
        return ("", [])
    }
    let known = Set(states.map(\.name))
    let packKeys: Set<String> = ["format", "name", "description", "fps", "scale", "chromaKey", "animations"]
    for key in json.keys where !packKeys.contains(key) { warnings.append("unknown top-level key \"\(key)\" is ignored") }
    if let scale = json["scale"] as? Double, !(0.5...2).contains(scale) { warnings.append("scale is clamped to 0.5...2") }
    let packFPS = json["fps"] as? Double ?? 10
    if !(1...60).contains(packFPS) { errors.append("fps must be 1...60") }
    guard let animations = json["animations"] as? [String: Any] else {
        errors.append("\"animations\" is missing")
        return (json["name"] as? String ?? pack.lastPathComponent, [])
    }
    if animations["idle"] == nil { errors.append("there is no \"idle\" animation") }
    // As the app reads it: inside the pack, symbolic links resolved.
    let root = pack.resolvingSymlinksInPath().standardizedFileURL.path
    func url(_ path: String) -> URL? {
        let resolved = pack.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), resolved.path.hasPrefix(root + "/") else {
            errors.append("\(path) is outside the pack's folder")
            return nil
        }
        return resolved
    }
    var result: [Animation] = []
    for name in animations.keys.sorted() {
        guard known.contains(name) else { errors.append("\"\(name)\" is not a state (known: \(states.map(\.name).joined(separator: ", ")))"); continue }
        guard let spec = animations[name] as? [String: Any] else { errors.append("\"\(name)\" is not an object"); continue }
        var frames: [CGImage] = [], fileDelays: [Double]? = nil
        if let sheet = spec["sheet"] as? String {
            // The app's bounds, checked before any arithmetic.
            guard let columns = spec["columns"] as? Int, (1...256).contains(columns) else {
                errors.append("\"\(name)\" sheet needs columns, 1...256"); continue
            }
            let rows = spec["rows"] as? Int ?? 1
            guard (1...256).contains(rows) else { errors.append("\"\(name)\" rows must be 1...256"); continue }
            let start = spec["start"] as? Int ?? 0
            let first: Int, available: Int
            if let row = spec["row"] as? Int {
                guard (0..<rows).contains(row), (0..<columns).contains(start) else {
                    errors.append("\"\(name)\": row or start is outside the sheet"); continue
                }
                first = row * columns + start
                available = columns - start
            } else {
                guard (0..<(columns * rows)).contains(start) else { errors.append("\"\(name)\": start is outside the sheet"); continue }
                first = start
                available = columns * rows - start
            }
            let count = spec["count"] as? Int ?? min(available, 120)
            guard count > 0, count <= available else { errors.append("\"\(name)\": count does not fit the sheet"); continue }
            guard let file = url(sheet), FileManager.default.fileExists(atPath: file.path) else {
                errors.append("\"\(name)\": \(sheet) is missing"); continue
            }
            let image = loadImage(file)
            let cellWidth = image.width / columns, cellHeight = image.height / rows
            guard cellWidth > 0, cellHeight > 0 else { errors.append("\"\(name)\": \(sheet) is smaller than its grid"); continue }
            frames = (first..<(first + count)).compactMap {
                image.cropping(to: CGRect(x: ($0 % columns) * cellWidth, y: ($0 / columns) * cellHeight, width: cellWidth, height: cellHeight))
            }
        } else if let list = spec["frames"] as? [String] {
            for path in list {
                guard let file = url(path), let image = loadImages(file).first?.image else { errors.append("\"\(name)\": \(path) can't be read"); continue }
                frames.append(image)
            }
        } else if let path = spec["frames"] as? String, let target = url(path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
                errors.append("\"\(name)\": \(path) is missing"); continue
            }
            if isDirectory.boolValue {
                let extensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "tif", "tiff", "bmp", "gif"]
                let files = ((try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? [])
                    .filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                // Each frame is checked as the app checks it, links included.
                frames = files.compactMap { file in url((path as NSString).appendingPathComponent(file)).flatMap { loadImages($0).first?.image } }
                if frames.count != files.count { errors.append("\"\(name)\": some frames in \(path) can't be read") }
            } else {
                let read = loadImages(target)
                frames = read.map(\.image)
                fileDelays = read.map { $0.delay ?? 0.1 }
            }
        } else {
            errors.append("\"\(name)\" has neither frames nor sheet"); continue
        }
        guard !frames.isEmpty else { errors.append("\"\(name)\" has no frames"); continue }
        if frames.count > 120 { errors.append("\"\(name)\" has \(frames.count) frames; at most 120 are read") }
        let fps = spec["fps"] as? Double ?? packFPS
        if !(1...60).contains(fps) { errors.append("\"\(name)\" fps must be 1...60") }
        // An animated image keeps its own delays unless this animation sets its timing.
        let ownDelays = spec["fps"] == nil && spec["durations"] == nil
        var delays = (ownDelays ? fileDelays : nil) ?? Array(repeating: 1 / fps, count: frames.count)
        if let durations = spec["durations"] as? [Double] {
            if durations.count != 1, durations.count != frames.count {
                errors.append("\"\(name)\": give one duration, or one per frame (\(frames.count))")
            } else if durations.contains(where: { $0 < 10 || $0 > 10_000 }) {
                errors.append("\"\(name)\": durations are milliseconds, 10...10000")
            } else {
                delays = durations.count == 1 ? Array(repeating: durations[0] / 1000, count: frames.count) : durations.map { $0 / 1000 }
            }
        }
        // Keyed as the app keys them, so previews show what the island will.
        let keySpec = (spec["chromaKey"] ?? json["chromaKey"]) as? [String: Any]
        if let keySpec {
            if let color = keySpec["color"] as? String, let key = Key(color, tolerance: keySpec["tolerance"] as? Double ?? 0.16) {
                frames = frames.map { frame in
                    var pixels = Pixels(frame)
                    key.apply(to: &pixels)
                    return pixels.image
                }
            } else {
                errors.append("\"\(name)\" chromaKey is not a #RRGGBB color")
            }
        }
        result.append(Animation(name: name, frames: frames, delays: delays))
    }
    // Quality checks against the contract.
    if let idle = result.first(where: { $0.name == "idle" })?.frames.first {
        if idle.width != idle.height { warnings.append("idle frames are \(idle.width)x\(idle.height); square frames centre best") }
        if max(idle.width, idle.height) < 256 { warnings.append("frames are \(idle.width)x\(idle.height); use 512 or more for a sharp face") }
        for animation in result {
            if let first = animation.frames.first, first.width * idle.height != first.height * idle.width {
                warnings.append("\"\(animation.name)\" frames have another shape than idle's and are fit into it")
            }
            if let first = animation.frames.first, !Pixels(first).cornersTransparent {
                warnings.append("\"\(animation.name)\" frames keep an opaque background; it shows as a box unless it is black, so make it transparent or set chromaKey")
            }
        }
    }
    return (json["name"] as? String ?? pack.lastPathComponent, result)
}

func validate(_ args: Arguments) {
    let pack = expand(args.require("pack"))
    var errors: [String] = [], warnings: [String] = []
    let read = readPack(pack, errors: &errors, warnings: &warnings)
    for animation in read.animations {
        let total = animation.delays.reduce(0, +)
        print(String(format: "  %@: %d frames, %.2fs", animation.name, animation.frames.count, total))
    }
    let missing = states.map(\.name).filter { name in !read.animations.contains { $0.name == name } }
    if !missing.isEmpty { print("  falls back for: \(missing.joined(separator: ", "))") }
    warnings.forEach { print("warning: \($0)") }
    errors.forEach { print("error: \($0)") }
    print(errors.isEmpty ? "VALID: \(read.name)" : "INVALID: \(errors.count) error(s)")
    exit(errors.isEmpty ? 0 : 1)
}

// MARK: - preview

func fit(_ image: CGImage, side: Int, background: CGColor) -> CGImage {
    let canvas = context(side, side)
    canvas.setFillColor(background)
    canvas.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let scale = CGFloat(side) / CGFloat(max(image.width, image.height))
    let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
    canvas.draw(image, in: CGRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2, width: width, height: height))
    return canvas.makeImage()!
}

func label(_ text: String, in canvas: CGContext, at point: CGPoint) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 22, nil)
    let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                     NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.9, alpha: 1)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    canvas.textPosition = point
    CTLineDraw(line, canvas)
}

func preview(_ args: Arguments) {
    let pack = expand(args.require("pack"))
    let out = expand(args.values["out"] ?? pack.deletingLastPathComponent().appendingPathComponent("qa").path)
    var errors: [String] = [], warnings: [String] = []
    let read = readPack(pack, errors: &errors, warnings: &warnings)
    guard !read.animations.isEmpty else { errors.forEach { print("error: \($0)") }; fail("nothing to preview") }
    let black = CGColor(gray: 0, alpha: 1), grey = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    // A contact sheet: one row per state, every frame, on the island's black.
    let tile = 112, labelWidth = 170
    let columns = read.animations.map(\.frames.count).max() ?? 1
    let sheet = context(labelWidth + columns * tile, read.animations.count * tile)
    sheet.setFillColor(grey)
    sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
    for (row, animation) in read.animations.enumerated() {
        let y = sheet.height - (row + 1) * tile
        label(animation.name, in: sheet, at: CGPoint(x: 12, y: y + tile / 2 - 8))
        for (column, frame) in animation.frames.enumerated() {
            sheet.draw(fit(frame, side: tile - 6, background: black),
                       in: CGRect(x: labelWidth + column * tile + 3, y: y + 3, width: tile - 6, height: tile - 6))
        }
        writeGIF(animation.frames.map { fit($0, side: 192, background: black) }, delays: animation.delays,
                 out.appendingPathComponent("\(animation.name).gif"))
    }
    writePNG(sheet.makeImage()!, out.appendingPathComponent("contact-sheet.png"))
    // How it reads at the sizes the island draws it, at 2x: 20, 18 and 13 points.
    if let idle = read.animations.first(where: { $0.name == "idle" })?.frames.first {
        let sizes = [40, 36, 26]
        let strip = context(sizes.reduce(0, +) + 24 * (sizes.count + 1), 64)
        strip.setFillColor(black)
        strip.fill(CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
        var x = 24
        for size in sizes {
            strip.draw(fit(idle, side: size, background: black), in: CGRect(x: x, y: (64 - size) / 2, width: size, height: size))
            x += size + 24
        }
        writePNG(strip.makeImage()!, out.appendingPathComponent("island-sizes.png"))
    }
    warnings.forEach { print("warning: \($0)") }
    errors.forEach { print("error: \($0)") }
    print("previews in \(out.path): contact-sheet.png, island-sizes.png, <state>.gif")
}

// MARK: - install

/// Copies a pack as the app adds one: links inside it become the files
/// and folders they lead to, links out of it and back up it are skipped,
/// so the installed copy reads on its own.
func copyResolvingLinks(_ folder: URL, to destination: URL, root: String, ancestry: Set<String>, budget: inout Int) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: destination, withIntermediateDirectories: true)
    for item in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
        budget -= 1
        guard budget >= 0 else { fail("the pack holds more than 5000 files") }
        var real = item.standardizedFileURL
        if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            real = item.resolvingSymlinksInPath().standardizedFileURL
            guard real.path.hasPrefix(root + "/") else { continue }
        }
        let target = destination.appendingPathComponent(item.lastPathComponent)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: real.path, isDirectory: &isDirectory) else { continue }
        if isDirectory.boolValue {
            guard !ancestry.contains(real.path) else { continue }
            try copyResolvingLinks(real, to: target, root: root, ancestry: ancestry.union([real.path]), budget: &budget)
        } else {
            try manager.copyItem(at: real, to: target)
        }
    }
}

func install(_ args: Arguments) {
    let pack = expand(args.require("pack"))
    var errors: [String] = [], warnings: [String] = []
    _ = readPack(pack, errors: &errors, warnings: &warnings)
    guard errors.isEmpty else { errors.forEach { print("error: \($0)") }; fail("fix the pack before installing") }
    let bundle = args.flags.contains("dev") ? "com.vorssaint.utils.dev" : "com.vorssaint.utils"
    // A run's pack takes the id prepare planned; any other folder its own name.
    let planned = (try? Data(contentsOf: pack.deletingLastPathComponent().appendingPathComponent("run.json")))
        .flatMap { try? JSONDecoder().decode(Plan.self, from: $0) }?.slug
    let name = args.values["id"] ?? planned ?? pack.lastPathComponent
    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/\(bundle)/Companions", isDirectory: true)
    let destination = folder.appendingPathComponent(slug(name), isDirectory: true)
    if FileManager.default.fileExists(atPath: destination.path) {
        guard destination.resolvingSymlinksInPath().standardizedFileURL.path
                != pack.resolvingSymlinksInPath().standardizedFileURL.path else {
            fail("\(pack.path) is already the installed pack; nothing to do")
        }
        guard args.flags.contains("replace") else { fail("\(destination.path) exists; pass --replace to overwrite it") }
        try? FileManager.default.removeItem(at: destination)
    }
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var budget = 5000
        let root = pack.resolvingSymlinksInPath().standardizedFileURL
        try copyResolvingLinks(root, to: destination, root: root.path, ancestry: [root.path], budget: &budget)
    } catch {
        fail("cannot install: \(error.localizedDescription)")
    }
    print("installed \(destination.path)")
    print("in Vorssaint: Settings → Dynamic Island → Companion → Style → Character, then Reload and pick it")
}

// MARK: - main

let usage = """
usage: swift companion_tool.swift <command> [options]

  prepare  --name NAME --out RUN [--concept TEXT] [--style TEXT] [--background transparent|#00FF00]
           [--states idle,happy,...] [--frames 8] [--state-frames idle=12,dance=24] [--slug ID]
  slice    --run RUN --state STATE --sheet IMAGE [--key #RRGGBB|transparent] [--tolerance 0.16]
           [--columns C --rows R --count N] [--append]
  manifest --run RUN
  validate --pack PACK
  preview  --pack PACK [--out DIR]
  install  --pack PACK [--id ID] [--dev] [--replace]
"""

let arguments = CommandLine.arguments
guard arguments.count > 1, !arguments.contains("--help") else { print(usage); exit(arguments.count > 1 ? 0 : 1) }
let options = Arguments(arguments.dropFirst(2))
switch arguments[1] {
case "prepare": prepare(options)
case "slice": slice(options)
case "manifest": manifest(options)
case "validate": validate(options)
case "preview": preview(options)
case "install": install(options)
default: print(usage); exit(1)
}
