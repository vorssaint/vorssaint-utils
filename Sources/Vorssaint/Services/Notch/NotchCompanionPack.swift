// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

// A character for the companion, drawn frame by frame rather than with
// shapes: a face, finely drawn, in a folder with a `companion.json` naming
// its animations, each a folder of numbered frames, a sprite sheet or an
// animated image. docs/COMPANIONS.md is the contract for pack authors; this
// file is its model, kept free of AppKit so the tests can read packs.

/// The faces a character can make. Only `idle` is required: anything
/// missing stands in with the nearest one it has, down to `idle`.
enum NotchCompanionState: String, CaseIterable, Identifiable {
    /// At rest, breathing and blinking. Required.
    case idle
    /// Looking to the right as it travels that way on a visit; `lookLeft`
    /// the other way, or `lookRight` seen in a mirror.
    case lookRight, lookLeft
    /// Dozing where it rests.
    case sleep
    /// Saying hello as it passes by.
    case wink
    /// Glad: results turned up, a focus session ended, the battery is full.
    case happy
    /// Petted, or the charger went in.
    case love
    /// A timer rang, a screenshot was taken.
    case surprised
    /// Nothing matched, a download failed.
    case sad
    /// Searching or thinking in the Command Bar.
    case think
    /// At work: an agent started, Keep Awake holds the Mac up.
    case busy
    /// Music is playing.
    case dance

    var id: String { rawValue }

    /// Whether it plays round and round unless the manifest says otherwise.
    /// The others play once and hold their last frame.
    var loopsByDefault: Bool {
        switch self {
        case .idle, .lookRight, .lookLeft, .sleep, .think, .busy, .dance: return true
        case .wink, .happy, .love, .surprised, .sad: return false
        }
    }

    /// The state that stands in for this one when a pack has none. A missing
    /// `lookLeft` is `lookRight` mirrored, which `NotchCompanionPack.resolve` handles.
    var fallback: NotchCompanionState? {
        switch self {
        case .idle: return nil
        case .lookRight, .sleep, .happy, .sad, .think, .busy, .surprised: return .idle
        case .lookLeft: return .lookRight
        case .wink, .love, .dance: return .happy
        }
    }
}

extension NotchMascotMood {
    /// What a character shows for the face the drawn companion would make.
    var companionState: NotchCompanionState {
        switch self {
        case .idle: return .idle
        case .happy: return .happy
        case .wink: return .wink
        case .love: return .love
        case .sleepy: return .sleep
        case .determined, .alert: return .busy
        case .surprised: return .surprised
        case .searching, .thinking: return .think
        case .confused: return .sad
        }
    }
}

extension NotchMascotReaction {
    /// What a character acts out for a reaction, for as long as the reaction lasts.
    var companionState: NotchCompanionState {
        switch self {
        case .celebrate, .wakeUp, .bounce: return .happy
        case .love: return .love
        case .surprised, .flash, .perk: return .surprised
        case .confused: return .sad
        case .yawn, .hush: return .sleep
        case .ready: return .busy
        case .groove: return .dance
        }
    }
}

/// A color made see-through in every frame, for frames drawn on a flat
/// backdrop such as a JPEG or a generated sprite strip on green.
struct NotchCompanionChromaKey: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    /// How far from the color, 0...1, a pixel still counts as the backdrop.
    var tolerance: Double = 0.16

    /// `#RRGGBB` or `RRGGBB`.
    init?(hex: String, tolerance: Double? = nil) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
        if let tolerance { self.tolerance = min(1, max(0, tolerance)) }
    }

    /// How opaque a pixel of this color stays: none within the tolerance,
    /// fully past half as much again, and partly in between so edges stay soft.
    func alpha(red r: Double, green g: Double, blue b: Double) -> Double {
        let distance = ((r - red) * (r - red) + (g - green) * (g - green) + (b - blue) * (b - blue)).squareRoot() / 3.0.squareRoot()
        guard tolerance > 0 else { return distance == 0 ? 0 : 1 }
        if distance <= tolerance { return 0 }
        let feather = tolerance * 0.5
        return min(1, (distance - tolerance) / feather)
    }
}

/// Where an animation's frames come from, relative to its pack's folder.
enum NotchCompanionFrameSource: Equatable {
    /// One image per frame, in order.
    case files([String])
    /// Cells of a sprite sheet `columns` wide and `rows` high, by index
    /// counted row by row from the top left.
    case sheet(file: String, columns: Int, rows: Int, cells: [Int])
    /// Every frame of an animated GIF, PNG, WebP or HEIC.
    case animated(file: String)
}

/// One animation of a pack.
struct NotchCompanionClip: Equatable {
    var source: NotchCompanionFrameSource
    /// Seconds per frame, nil to take an animated image's own delays, or
    /// one duration for every frame.
    var durations: [TimeInterval]?
    var frameDuration: TimeInterval
    var loops: Bool
    var chromaKey: NotchCompanionChromaKey?
    /// An animated image plays with the delays stored in it.
    var ownDelays = true

    /// The frame count before the files are read, nil for an animated image.
    var declaredFrameCount: Int? {
        switch source {
        case .files(let files): return files.count
        case .sheet(_, _, _, let cells): return cells.count
        case .animated: return nil
        }
    }
}

/// A character as its manifest describes it.
struct NotchCompanionPack: Equatable {
    /// Unique among packs: its folder's name.
    var id: String
    var name: String
    var summary: String
    /// How big the face shows next to the drawn companion's square, so one
    /// with room around it in its frames can fill as much.
    var scale: CGFloat
    var clips: [NotchCompanionState: NotchCompanionClip]

    static let manifestName = "companion.json"
    static let frameExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "tif", "tiff", "bmp", "gif"]
    static let defaultFPS: Double = 10
    static let fpsRange: ClosedRange<Double> = 1...60
    static let scaleRange: ClosedRange<CGFloat> = 0.5...2
    static let maxFrames = 120
    /// The most columns or rows a sheet may have.
    static let maxGrid = 256

    /// The state that plays for `state`, and whether to mirror it.
    func resolve(_ state: NotchCompanionState) -> (state: NotchCompanionState, mirrored: Bool) {
        if clips[state] != nil { return (state, false) }
        if state == .lookLeft {
            let right = resolve(.lookRight)
            // Standing in for looking aside, idle is not turned around.
            return right.state == .lookRight ? (.lookRight, !right.mirrored) : right
        }
        guard let fallback = state.fallback else { return (.idle, false) }
        return resolve(fallback)
    }

    enum Problem: Error, Equatable, CustomStringConvertible {
        case unreadable(String)
        case missingIdle
        case unknownState(String)
        case noFrames(String)
        case badSheet(String, String)
        case badTiming(String, String)
        case badChromaKey(String)
        case tooManyFrames(String, Int)

        var description: String {
            switch self {
            case .unreadable(let reason): return "The manifest can't be read: \(reason)"
            case .missingIdle: return "There is no \"idle\" animation, and every character needs one."
            case .unknownState(let name):
                return "\"\(name)\" is not an animation the companion plays. Known: "
                    + NotchCompanionState.allCases.map(\.rawValue).joined(separator: ", ") + "."
            case .noFrames(let name): return "\"\(name)\" has no frames."
            case .badSheet(let name, let reason): return "\"\(name)\" sheet: \(reason)"
            case .badTiming(let name, let reason): return "\"\(name)\" timing: \(reason)"
            case .badChromaKey(let name): return "\"\(name)\" chromaKey is not a #RRGGBB color."
            case .tooManyFrames(let name, let count):
                return "\"\(name)\" has \(count) frames; at most \(NotchCompanionPack.maxFrames) are read."
            }
        }
    }

    // MARK: companion.json

    private struct Manifest: Decodable {
        var format: Int?
        var name: String?
        var description: String?
        var fps: Double?
        var scale: Double?
        var chromaKey: Key?
        var animations: [String: Animation]

        struct Key: Decodable {
            var color: String
            var tolerance: Double?
        }

        struct Animation: Decodable {
            var frames: Frames?
            var sheet: String?
            var columns: Int?
            var rows: Int?
            var row: Int?
            var start: Int?
            var count: Int?
            var fps: Double?
            var durations: [Double]?
            var loop: Bool?
            var chromaKey: Key?
        }

        enum Frames: Decodable {
            case path(String)
            case list([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let list = try? container.decode([String].self) { self = .list(list) }
                else { self = .path(try container.decode(String.self)) }
            }
        }
    }

    /// Reads a `companion.json`. `listing` gives the files in a folder of the
    /// pack, nil when there is no such folder, so the tests need no disk.
    static func parse(_ data: Data, id: String, listing: (String) -> [String]?) -> Result<NotchCompanionPack, Problem> {
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) } catch {
            return .failure(.unreadable(Self.describe(error)))
        }
        func key(_ key: Manifest.Key?, _ name: String) -> Result<NotchCompanionChromaKey?, Problem> {
            guard let key else { return .success(nil) }
            guard let parsed = NotchCompanionChromaKey(hex: key.color, tolerance: key.tolerance) else {
                return .failure(.badChromaKey(name))
            }
            return .success(parsed)
        }
        let packKey: NotchCompanionChromaKey?
        switch key(manifest.chromaKey, "pack") {
        case .success(let parsed): packKey = parsed
        case .failure(let problem): return .failure(problem)
        }
        let packFPS = manifest.fps ?? defaultFPS
        guard fpsRange.contains(packFPS) else { return .failure(.badTiming("pack", "fps must be 1...60")) }
        var clips: [NotchCompanionState: NotchCompanionClip] = [:]
        for (name, animation) in manifest.animations.sorted(by: { $0.key < $1.key }) {
            guard let state = NotchCompanionState(rawValue: name) else { return .failure(.unknownState(name)) }
            let source: NotchCompanionFrameSource
            if let sheet = animation.sheet {
                // Bounded before any arithmetic, so no grid a manifest names
                // can overflow or ask for more cells than are ever read.
                guard let columns = animation.columns, (1...maxGrid).contains(columns) else {
                    return .failure(.badSheet(name, "\"columns\" is required, 1...\(maxGrid)"))
                }
                let rows = animation.rows ?? 1
                guard (1...maxGrid).contains(rows) else { return .failure(.badSheet(name, "\"rows\" must be 1...\(maxGrid)")) }
                let start = animation.start ?? 0
                let first: Int, available: Int
                if let row = animation.row {
                    guard (0..<rows).contains(row) else { return .failure(.badSheet(name, "\"row\" is outside the sheet")) }
                    guard (0..<columns).contains(start) else {
                        return .failure(.badSheet(name, "\"start\" is outside the row"))
                    }
                    first = row * columns + start
                    available = columns - start
                } else {
                    guard (0..<(columns * rows)).contains(start) else {
                        return .failure(.badSheet(name, "\"start\" is outside the sheet"))
                    }
                    first = start
                    available = columns * rows - start
                }
                let count = animation.count ?? min(available, maxFrames)
                guard count > 0, count <= available else {
                    return .failure(.badSheet(name, "\"count\" and \"start\" must fit in the sheet"))
                }
                guard count <= maxFrames else { return .failure(.tooManyFrames(name, count)) }
                source = .sheet(file: sheet, columns: columns, rows: rows, cells: Array(first..<(first + count)))
            } else {
                switch animation.frames {
                case .list(let files):
                    source = .files(files)
                case .path(let path):
                    let ext = (path as NSString).pathExtension.lowercased()
                    if let listed = listing(path) {
                        let frames = listed
                            .filter { frameExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
                            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                            .map { (path as NSString).appendingPathComponent($0) }
                        source = .files(frames)
                    } else if frameExtensions.contains(ext) {
                        source = .animated(file: path)
                    } else {
                        return .failure(.noFrames(name))
                    }
                case nil:
                    return .failure(.noFrames(name))
                }
            }
            if case .files(let files) = source, files.isEmpty { return .failure(.noFrames(name)) }
            let clipKey: NotchCompanionChromaKey?
            switch key(animation.chromaKey, name) {
            case .success(let parsed): clipKey = parsed ?? packKey
            case .failure(let problem): return .failure(problem)
            }
            let fps = animation.fps ?? packFPS
            guard fpsRange.contains(fps) else { return .failure(.badTiming(name, "fps must be 1...60")) }
            var durations: [TimeInterval]?
            if let given = animation.durations {
                guard !given.isEmpty, given.allSatisfy({ $0 >= 10 && $0 <= 10_000 }) else {
                    return .failure(.badTiming(name, "durations are milliseconds, 10...10000"))
                }
                if let count = (NotchCompanionClip(source: source, durations: nil, frameDuration: 0, loops: false)
                                    .declaredFrameCount), given.count != 1, given.count != count {
                    return .failure(.badTiming(name, "give one duration, or one per frame (\(count))"))
                }
                durations = given.map { $0 / 1000 }
            }
            // An animated image keeps its own delays unless this animation
            // sets its timing; the pack's frame rate is only a default.
            let clip = NotchCompanionClip(source: source, durations: durations, frameDuration: 1 / fps,
                                          loops: animation.loop ?? state.loopsByDefault, chromaKey: clipKey,
                                          ownDelays: animation.fps == nil && durations == nil)
            if let count = clip.declaredFrameCount, count > maxFrames { return .failure(.tooManyFrames(name, count)) }
            clips[state] = clip
        }
        guard clips[.idle] != nil else { return .failure(.missingIdle) }
        let scale = CGFloat(manifest.scale ?? 1)
        return .success(NotchCompanionPack(
            id: id, name: manifest.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? id,
            summary: manifest.description ?? "",
            scale: min(scaleRange.upperBound, max(scaleRange.lowerBound, scale)), clips: clips))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): return "\"\(key.stringValue)\" is missing"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        default: return error.localizedDescription
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: Reels

/// One frame of one state, perhaps seen in a mirror.
struct NotchCompanionCel: Hashable {
    var state: NotchCompanionState
    var frame: Int
    var mirrored = false
}

/// Frames in a row and when each starts, in seconds from the reel's start:
/// one discrete keyframe animation of a layer's contents.
struct NotchCompanionReel: Equatable {
    var cels: [NotchCompanionCel] = []
    var starts: [TimeInterval] = []
    var duration: TimeInterval = 0

    /// Key times for a discrete animation, which takes one more than its values.
    var keyTimes: [Double] {
        guard duration > 0 else { return [] }
        return starts.map { $0 / duration } + [1]
    }

    fileprivate mutating func append(_ cel: NotchCompanionCel, at time: TimeInterval) {
        if cels.last == cel { return }
        cels.append(cel)
        starts.append(time)
    }
}

/// How long each frame of each state shows, once the frames are read.
struct NotchCompanionTiming: Equatable {
    var durations: [NotchCompanionState: [TimeInterval]]
    var loops: [NotchCompanionState: Bool]

    func frames(_ state: NotchCompanionState) -> [TimeInterval] {
        let frames = durations[state] ?? []
        return frames.isEmpty ? [0.1] : frames
    }

    func cycle(_ state: NotchCompanionState) -> TimeInterval { frames(state).reduce(0, +) }
}

enum NotchCompanionReels {
    /// One pass through `state`'s frames.
    static func cycle(of state: NotchCompanionState, in pack: NotchCompanionPack,
                      timing: NotchCompanionTiming) -> NotchCompanionReel {
        let resolved = pack.resolve(state)
        var reel = NotchCompanionReel()
        var time: TimeInterval = 0
        for (index, length) in timing.frames(resolved.state).enumerated() {
            reel.cels.append(NotchCompanionCel(state: resolved.state, frame: index, mirrored: resolved.mirrored))
            reel.starts.append(time)
            time += length
        }
        reel.duration = time
        return reel
    }

    /// The one frame that stands for `state` when it can't play, with Reduce
    /// Motion or out of sight: a loop's first, which is its rest, and a
    /// moment's last, which holds the expression it builds to.
    static func still(of state: NotchCompanionState, in pack: NotchCompanionPack,
                      timing: NotchCompanionTiming) -> NotchCompanionCel {
        let resolved = pack.resolve(state)
        let loops = timing.loops[resolved.state] ?? resolved.state.loopsByDefault
        return NotchCompanionCel(state: resolved.state, frame: loops ? 0 : timing.frames(resolved.state).count - 1,
                                 mirrored: resolved.mirrored)
    }

    /// `state` played for `duration`: round and round when it loops, or once
    /// and held on its last frame.
    static func play(_ state: NotchCompanionState, for duration: TimeInterval, in pack: NotchCompanionPack,
                     timing: NotchCompanionTiming) -> NotchCompanionReel {
        var reel = NotchCompanionReel()
        guard duration > 0 else { return reel }
        fill(&reel, state: state, from: 0, to: duration, phase: 0, in: pack, timing: timing)
        reel.duration = duration
        return reel
    }

    /// Moving slower than this, in points a second, it rests rather than
    /// looks the way it goes.
    static let travelSpeed: CGFloat = 3

    /// A visit: looking the way it travels where it moves, and at rest
    /// where it stands. Its greeting and reactions play over this.
    static func visit(_ path: NotchMascotPath, in pack: NotchCompanionPack,
                      timing: NotchCompanionTiming) -> NotchCompanionReel {
        var reel = NotchCompanionReel()
        guard path.duration > 0, path.keyTimes.count == path.x.count, path.x.count > 1 else { return reel }
        // A path is sampled many times a second, so its samples join into
        // runs of travelling one way or resting before any frame is laid:
        // each frame then shows as long as the pack says.
        var runs: [(state: NotchCompanionState, start: TimeInterval, end: TimeInterval)] = []
        for index in 0..<(path.x.count - 1) {
            let start = path.keyTimes[index] * path.duration, end = path.keyTimes[index + 1] * path.duration
            // A jump off stage takes no time, and no frame.
            guard end - start > 0.0001 else { continue }
            let distance = path.x[index + 1] - path.x[index]
            let state: NotchCompanionState = abs(distance) / CGFloat(end - start) < travelSpeed ? .idle
                : distance < 0 ? .lookLeft : .lookRight
            if let last = runs.last, last.state == state, abs(last.end - start) < 0.0001 {
                runs[runs.count - 1].end = end
            } else {
                runs.append((state, start, end))
            }
        }
        // A look carries on from one run to the next, so a stroll broken
        // by a hop does not start it again.
        var stride = 0
        for run in runs {
            let next = fill(&reel, state: run.state, from: run.start, to: run.end,
                            phase: run.state == .idle ? 0 : stride, in: pack, timing: timing)
            if run.state != .idle { stride = next }
        }
        if reel.cels.isEmpty { fill(&reel, state: .idle, from: 0, to: path.duration, phase: 0, in: pack, timing: timing) }
        reel.duration = path.duration
        return reel
    }

    /// Lays `state` from `start` to `end`, from frame `phase`, and returns
    /// the frame it would show next.
    @discardableResult
    private static func fill(_ reel: inout NotchCompanionReel, state: NotchCompanionState, from start: TimeInterval,
                             to end: TimeInterval, phase: Int, in pack: NotchCompanionPack,
                             timing: NotchCompanionTiming) -> Int {
        let resolved = pack.resolve(state)
        let frames = timing.frames(resolved.state)
        let loops = timing.loops[resolved.state] ?? resolved.state.loopsByDefault
        var index = phase % frames.count
        var time = start
        while time < end - 0.0005 {
            reel.append(NotchCompanionCel(state: resolved.state, frame: index, mirrored: resolved.mirrored), at: time)
            time += frames[index]
            if index + 1 < frames.count { index += 1 } else if loops { index = 0 } else { break }
        }
        return index
    }
}
