// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation
import ImageIO

extension Notification.Name {
    /// A character's frames finished reading, or failed to.
    static let notchCompanionLoaded = Notification.Name("NotchCompanionLoaded")
}

/// A character pack found on disk, readable or not.
struct NotchCompanionEntry: Identifiable, Equatable {
    let id: String
    let directory: URL
    let pack: NotchCompanionPack?
    /// Why it can't be used, for its author.
    let problem: String?

    var name: String { pack?.name ?? directory.lastPathComponent }
}

/// A character's frames, read and ready to show. Every frame shares one
/// canvas, centred in it, so the face keeps its place from one animation
/// to the next.
final class NotchCompanionSprites {
    let pack: NotchCompanionPack
    let timing: NotchCompanionTiming
    /// The canvas's width over its height.
    let aspect: CGFloat
    private let frames: [NotchCompanionState: [CGImage]]
    private var mirrored: [NotchCompanionCel: CGImage] = [:]

    init(pack: NotchCompanionPack, timing: NotchCompanionTiming, aspect: CGFloat,
         frames: [NotchCompanionState: [CGImage]]) {
        self.pack = pack
        self.timing = timing
        self.aspect = aspect
        self.frames = frames
    }

    func frameCount(_ state: NotchCompanionState) -> Int { frames[state]?.count ?? 0 }

    /// The frame to show for `cel`, turned around for a mirrored one.
    func image(_ cel: NotchCompanionCel) -> CGImage? {
        guard let list = frames[cel.state], !list.isEmpty else { return nil }
        let image = list[min(max(0, cel.frame), list.count - 1)]
        guard cel.mirrored else { return image }
        if let flipped = mirrored[cel] { return flipped }
        guard let context = NotchCompanionLibrary.canvas(width: image.width, height: image.height) else { return image }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let flipped = context.makeImage() ?? image
        mirrored[cel] = flipped
        return flipped
    }

    /// The images of a reel, in order.
    func images(_ reel: NotchCompanionReel) -> [CGImage] { reel.cels.compactMap(image) }
}

/// Finds character packs in the app's Companions folder, reads their frames
/// off the main thread and keeps them for every companion on screen.
final class NotchCompanionLibrary: ObservableObject {
    static let shared = NotchCompanionLibrary()

    @Published private(set) var entries: [NotchCompanionEntry] = []
    private var sprites: [String: NotchCompanionSprites] = [:]
    private var loading: Set<String> = []
    /// Packs whose frames could not be read, and why, for Settings to say.
    @Published private(set) var failures: [String: String] = [:]
    private var scanned = false
    private var generation = 0
    private let queue = DispatchQueue(label: "com.vorssaint.companion-frames", qos: .userInitiated)

    /// The longest side, in pixels, frames are kept at: past twice the
    /// largest the companion shows, on a Retina display and at a pack's
    /// largest scale, so a finely drawn face stays sharp. More would only
    /// take memory.
    static let maxPixels = 192

    /// `~/Library/Application Support/<bundle id>/Companions`.
    static var folderURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("Companions", isDirectory: true)
    }

    // MARK: Packs

    func entry(_ id: String) -> NotchCompanionEntry? {
        if !scanned { rescan() }
        return entries.first { $0.id == id }
    }

    /// Reads every manifest again, and forgets frames read before, so an
    /// edited pack shows as it is now.
    func rescan() {
        scanned = true
        entries = (Self.folderURL.map(Self.scan) ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        // Frames still being read belong to the packs as they were.
        generation += 1
        sprites = [:]
        loading = []
        failures = [:]
        NotificationCenter.default.post(name: .notchCompanionLoaded, object: nil)
    }

    static func scan(_ folder: URL) -> [NotchCompanionEntry] {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return read(directory)
        }
    }

    /// The pack in `directory`, nil when it has no manifest.
    static func read(_ directory: URL) -> NotchCompanionEntry? {
        let id = directory.lastPathComponent
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(NotchCompanionPack.manifestName)) else {
            return nil
        }
        let result = NotchCompanionPack.parse(data, id: id) { path in
            guard let url = resolve(path, in: directory) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return try? FileManager.default.contentsOfDirectory(atPath: url.path)
        }
        switch result {
        case .success(let pack): return NotchCompanionEntry(id: id, directory: directory, pack: pack, problem: nil)
        case .failure(let problem):
            return NotchCompanionEntry(id: id, directory: directory, pack: nil, problem: problem.description)
        }
    }

    /// A path from a manifest inside its pack's folder, nil for one that
    /// leads out of it, by `..` or through a symbolic link.
    static func resolve(_ path: String, in directory: URL) -> URL? {
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else { return nil }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let url = directory.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path == root || url.path.hasPrefix(root + "/") else { return nil }
        return url
    }

    // MARK: Frames

    enum Availability {
        case ready(NotchCompanionSprites)
        /// Its frames are being read; `.notchCompanionLoaded` follows.
        case loading
        /// No such pack, or it can't be read: the drawn companion stands in.
        case unavailable
    }

    /// The character's frames, read in the background the first time they
    /// are asked for.
    func sprites(for id: String) -> Availability {
        if let ready = sprites[id] { return .ready(ready) }
        if loading.contains(id) { return .loading }
        guard failures[id] == nil, let entry = entry(id), let pack = entry.pack else { return .unavailable }
        loading.insert(id)
        let directory = entry.directory
        let generation = generation
        queue.async { [weak self] in
            let result = Result { try Self.load(pack, from: directory) }
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.loading.remove(id)
                switch result {
                case .success(let sprites): self.sprites[id] = sprites
                case .failure(let error): self.failures[id] = "\(error)"
                }
                NotificationCenter.default.post(name: .notchCompanionLoaded, object: nil)
            }
        }
        return .loading
    }

    /// Why a pack's frames could not be read, if they could not.
    func failure(_ id: String) -> String? { failures[id] ?? entry(id)?.problem }

    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    /// Reads every frame of `pack` from `directory`.
    static func load(_ pack: NotchCompanionPack, from directory: URL) throws -> NotchCompanionSprites {
        var raw: [NotchCompanionState: (images: [CGImage], delays: [TimeInterval]?)] = [:]
        for (state, clip) in pack.clips {
            raw[state] = try frames(of: clip, state: state, in: directory)
        }
        guard let first = raw[.idle]?.images.first else { throw LoadError(description: "\"idle\" has no frames.") }
        // Every frame is fit into the first idle frame's shape, at most
        // `maxPixels` on its longer side and never larger than it was drawn.
        let longest = CGFloat(max(first.width, first.height))
        let fit = min(1, CGFloat(maxPixels) / max(1, longest))
        let width = max(1, Int((CGFloat(first.width) * fit).rounded()))
        let height = max(1, Int((CGFloat(first.height) * fit).rounded()))
        var frames: [NotchCompanionState: [CGImage]] = [:]
        var durations: [NotchCompanionState: [TimeInterval]] = [:]
        var loops: [NotchCompanionState: Bool] = [:]
        for (state, clip) in pack.clips {
            guard let read = raw[state] else { continue }
            frames[state] = read.images.compactMap { place($0, width: width, height: height, key: clip.chromaKey) }
            let count = frames[state]?.count ?? 0
            guard count > 0 else { throw LoadError(description: "\"\(state.rawValue)\" has no frames that could be read.") }
            if let given = clip.durations {
                durations[state] = given.count == 1 ? Array(repeating: given[0], count: count)
                    : Array(given.prefix(count)) + Array(repeating: clip.frameDuration, count: max(0, count - given.count))
            } else if clip.ownDelays, let delays = read.delays, delays.count == count {
                durations[state] = delays
            } else {
                durations[state] = Array(repeating: clip.frameDuration, count: count)
            }
            loops[state] = clip.loops
        }
        return NotchCompanionSprites(pack: pack, timing: NotchCompanionTiming(durations: durations, loops: loops),
                                     aspect: CGFloat(width) / CGFloat(height), frames: frames)
    }

    private static func frames(of clip: NotchCompanionClip, state: NotchCompanionState,
                               in directory: URL) throws -> (images: [CGImage], delays: [TimeInterval]?) {
        func source(_ path: String) throws -> CGImageSource {
            guard let url = resolve(path, in: directory) else {
                throw LoadError(description: "\"\(state.rawValue)\": \(path) is outside the pack's folder.")
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
                throw LoadError(description: "\"\(state.rawValue)\": \(path) is missing or not an image.")
            }
            return source
        }
        switch clip.source {
        case .files(let files):
            return (try files.map { path in
                guard let image = thumbnail(try source(path), index: 0) else {
                    throw LoadError(description: "\"\(state.rawValue)\": \(path) can't be read.")
                }
                return image
            }, nil)
        case .sheet(let file, let columns, let rows, let cells):
            guard let sheet = CGImageSourceCreateImageAtIndex(try source(file), 0, nil) else {
                throw LoadError(description: "\"\(state.rawValue)\": \(file) can't be read.")
            }
            let cellWidth = sheet.width / columns, cellHeight = sheet.height / rows
            guard cellWidth > 0, cellHeight > 0 else {
                throw LoadError(description: "\"\(state.rawValue)\": \(file) is smaller than its grid.")
            }
            return (cells.compactMap { cell in
                sheet.cropping(to: CGRect(x: (cell % columns) * cellWidth, y: (cell / columns) * cellHeight,
                                          width: cellWidth, height: cellHeight))
            }, nil)
        case .animated(let file):
            let source = try source(file)
            let count = min(CGImageSourceGetCount(source), NotchCompanionPack.maxFrames)
            var images: [CGImage] = [], delays: [TimeInterval] = []
            for index in 0..<count {
                guard let image = thumbnail(source, index: index) else { continue }
                images.append(image)
                delays.append(delay(source, index: index) ?? clip.frameDuration)
            }
            return (images, delays)
        }
    }

    /// A frame read at most twice `maxPixels`, which `place` brings down
    /// the rest of the way with good filtering.
    private static func thumbnail(_ source: CGImageSource, index: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels * 2,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// An animated image's own delay for a frame, from whichever format it is.
    private static func delay(_ source: CGImageSource, index: Int) -> TimeInterval? {
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

    static func canvas(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// `image` fit into the middle of the canvas, with `key`'s color taken out.
    static func place(_ image: CGImage, width: Int, height: Int, key: NotchCompanionChromaKey?) -> CGImage? {
        guard let context = canvas(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        let fit = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
        context.draw(image, in: CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                                       width: size.width, height: size.height))
        if let key, let data = context.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
            for row in 0..<height {
                for column in 0..<width {
                    let offset = row * context.bytesPerRow + column * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let red = Double(pixels[offset]) / 255 / alpha, green = Double(pixels[offset + 1]) / 255 / alpha
                    let blue = Double(pixels[offset + 2]) / 255 / alpha
                    let keep = key.alpha(red: red, green: green, blue: blue)
                    guard keep < 1 else { continue }
                    for channel in 0..<4 { pixels[offset + channel] = UInt8((Double(pixels[offset + channel]) * keep).rounded()) }
                }
            }
        }
        return context.makeImage()
    }

    // MARK: Adding packs

    enum ImportError: Error, CustomStringConvertible {
        case notAPack, noFolder, copyFailed(String)

        var description: String {
            switch self {
            case .notAPack: return "The folder has no companion.json."
            case .noFolder: return "The Companions folder can't be created."
            case .copyFailed(let reason): return reason
            }
        }
    }

    /// Creates the Companions folder, and returns it.
    @discardableResult
    func ensureFolder() -> URL? {
        guard let folder = Self.folderURL, PrivateFileStore.createDirectory(at: folder) else { return nil }
        return folder
    }

    /// Copies the pack in `source` into the Companions folder, under
    /// `name` or its folder's, made unique, and returns its id.
    func importPack(from source: URL, named name: String? = nil) throws -> String {
        guard Self.read(source) != nil else { throw ImportError.notAPack }
        guard let folder = ensureFolder() else { throw ImportError.noFolder }
        let base = name.flatMap { $0.isEmpty || $0.contains("/") || $0.hasPrefix(".") ? nil : $0 } ?? source.lastPathComponent
        var name = base, number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base)-\(number)"
            number += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name, isDirectory: true))
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        rescan()
        return name
    }
}
