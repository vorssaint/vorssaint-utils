// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Character packs for the companion: the companion.json contract, which
/// face plays for what, and frames read from disk.
enum NotchCompanionTests {
    static func run(_ suite: TestSuite) {
        manifestContracts(suite)
        problemContracts(suite)
        fallbackContracts(suite)
        reelContracts(suite)
        chromaKeyContracts(suite)
        diskContracts(suite)
        preferenceContracts(suite)
        generatorContracts(suite)
    }

    private static func generatorContracts(_ suite: TestSuite) {
        let prompt = NotchCompanionGenerator.prompt(subject: "a sleepy fox", style: .anime)
        suite.expect(prompt.contains("$vorssaint-companion") && prompt.contains("a sleepy fox")
                     && prompt.contains(NotchCompanionGenerator.Style.anime.prompt) && prompt.contains("never pixel art")
                     && prompt.contains("Face only") && prompt.contains("./run")
                     && prompt.contains("Do not run the install step") && prompt.contains("never ask questions"),
                     "Codex is asked for the whole face-only pack, without questions, and leaves installing to the app")
        suite.expect(!prompt.contains("lookLeft") && prompt.contains("idle") && prompt.contains("dance")
                     && NotchCompanionGenerator.states.first == .idle,
                     "every state but the mirrored left look is drawn, idle first")
        suite.expect(Set(NotchCompanionGenerator.Style.allCases.map(\.prompt)).count == NotchCompanionGenerator.Style.allCases.count
                     && NotchCompanionGenerator.Style.allCases.allSatisfy { !$0.prompt.lowercased().contains("pixel") },
                     "each look asks for something of its own, and none for pixel art")
        func event(_ json: String) -> NotchCompanionGenerator.Event? { NotchCompanionGenerator.event(from: Data(json.utf8)) }
        suite.expect(event(#"{"type":"thread.started","thread_id":"01a1-x"}"#) == .thread("01a1-x")
                     && event(#"{"type":"thread.started","thread_id":"../etc"}"#) == nil,
                     "the thread names the folder its images go in, and only a plain name does")
        suite.expect(event(#"{"type":"item.completed","item":{"type":"agent_message","text":"Drawing `idle` now.\nMore."}}"#)
                     == .message("Drawing idle now."), "Codex's first line of news is shown, without code marks")
        suite.expect(event(#"{"type":"turn.failed","error":{"message":"usage limit"}}"#) == .failure("usage limit")
                     && event(#"{"type":"item.completed","item":{"type":"command_execution","command":"ls"}}"#) == nil
                     && event("not json") == nil,
                     "a failed turn says why; commands and noise are not news")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-codex-\(UUID().uuidString)")
        let bundled = home.appendingPathComponent("bundled", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try? FileManager.default.createDirectory(at: bundled.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bundled.appendingPathComponent("SKILL.md").path, contents: Data("v2".utf8))
        FileManager.default.createFile(atPath: bundled.appendingPathComponent("scripts/companion_tool.swift").path,
                                       contents: Data("tool".utf8))
        let codex = home.appendingPathComponent("codex", isDirectory: true)
        let target = try? NotchCompanionGenerator.installSkill(from: bundled, into: codex)
        suite.expect(target.flatMap { try? String(contentsOf: $0.appendingPathComponent("SKILL.md"), encoding: .utf8) } == "v2"
                     && target?.path.hasSuffix("skills/vorssaint-companion") == true,
                     "the skill the app carries is installed among Codex's skills")
        FileManager.default.createFile(atPath: bundled.appendingPathComponent("SKILL.md").path, contents: Data("v3".utf8))
        let updated = try? NotchCompanionGenerator.installSkill(from: bundled, into: codex)
        suite.expect(updated.flatMap { try? String(contentsOf: $0.appendingPathComponent("SKILL.md"), encoding: .utf8) } == "v3",
                     "a newer app replaces an older skill")
    }

    private static func pack(_ json: String, folders: [String: [String]] = [:]) -> Result<NotchCompanionPack, NotchCompanionPack.Problem> {
        NotchCompanionPack.parse(Data(json.utf8), id: "test") { folders[$0] }
    }

    private static func manifestContracts(_ suite: TestSuite) {
        let parsed = pack("""
        {"name": "Bean", "fps": 8, "scale": 1.2, "chromaKey": {"color": "#00FF00"},
         "animations": {
           "idle": {"frames": "idle"},
           "lookRight": {"sheet": "look.png", "columns": 6, "rows": 4, "count": 24, "fps": 12},
           "dance": {"sheet": "all.png", "columns": 8, "rows": 3, "row": 2, "start": 1, "count": 4, "durations": [100]},
           "happy": {"frames": ["happy/b.jpg", "happy/a.jpg"], "durations": [100, 200], "loop": true,
                     "chromaKey": {"color": "FFFFFF", "tolerance": 0.3}},
           "sleep": {"frames": "sleep.gif"},
           "busy": {"frames": "busy.gif", "fps": 20}
         }}
        """, folders: ["idle": ["frame10.png", "frame2.png", "frame1.png", ".DS_Store", "notes.txt"]])
        guard case .success(let bean) = parsed else { suite.expect(false, "a full manifest parses: \(parsed)"); return }
        suite.expect(bean.name == "Bean" && bean.scale == 1.2,
                     "the name and scale are read")
        suite.expect(bean.clips[.idle]?.source == .files(["idle/frame1.png", "idle/frame2.png", "idle/frame10.png"]),
                     "a folder's images play in natural order, without hidden or other files")
        suite.expect(bean.clips[.lookRight]?.source == .sheet(file: "look.png", columns: 6, rows: 4, cells: Array(0..<24))
                     && bean.clips[.lookRight]?.frameDuration == 1.0 / 12,
                     "a sheet is read row by row, at its own frame rate")
        suite.expect(bean.clips[.dance]?.source == .sheet(file: "all.png", columns: 8, rows: 3, cells: [17, 18, 19, 20])
                     && bean.clips[.dance]?.durations == [0.1],
                     "a row of a shared sheet starts at its first column plus start")
        suite.expect(bean.clips[.happy]?.source == .files(["happy/b.jpg", "happy/a.jpg"])
                     && bean.clips[.happy]?.durations == [0.1, 0.2] && bean.clips[.happy]?.loops == true
                     && bean.clips[.happy]?.chromaKey?.tolerance == 0.3,
                     "a list keeps its order, durations are milliseconds, and loop and key can be set per animation")
        suite.expect(bean.clips[.sleep]?.source == .animated(file: "sleep.gif") && bean.clips[.sleep]?.ownDelays == true
                     && bean.clips[.busy]?.source == .animated(file: "busy.gif") && bean.clips[.busy]?.ownDelays == false,
                     "an image file that is not a folder plays as an animated image")
        suite.expect(bean.clips[.idle]?.chromaKey == NotchCompanionChromaKey(hex: "#00ff00")
                     && bean.clips[.idle]?.frameDuration == 1.0 / 8,
                     "the pack's key and frame rate apply where an animation has none")
        suite.expect(bean.clips[.idle]?.loops == true && bean.clips[.lookRight]?.loops == true
                     && NotchCompanionState.happy.loopsByDefault == false && NotchCompanionState.wink.loopsByDefault == false,
                     "rests and looks loop; moments play once unless the pack says otherwise")
        if case .success(let minimal) = pack(#"{"animations": {"idle": {"frames": ["a.png"]}}}"#) {
            suite.expect(minimal.name == "test" && minimal.scale == 1 && minimal.clips.count == 1,
                         "only idle is required, and the folder's name stands for a missing name")
        } else {
            suite.expect(false, "a pack with only idle parses")
        }
    }

    private static func problemContracts(_ suite: TestSuite) {
        func problem(_ json: String) -> NotchCompanionPack.Problem? {
            if case .failure(let problem) = pack(json) { return problem }
            return nil
        }
        suite.expect(problem(#"{"animations": {"lookRight": {"frames": ["a.png"]}}}"#) == .missingIdle,
                     "a pack without idle is refused")
        suite.expect(problem(#"{"animations": {"idle": {"frames": ["a.png"]}, "fly": {"frames": ["b.png"]}}}"#)
                     == .unknownState("fly"), "an unknown animation is named, not silently skipped")
        suite.expect(problem(#"{"animations": {"idle": {"sheet": "s.png"}}}"#).map { "\($0)".contains("columns") } == true,
                     "a sheet needs its columns")
        suite.expect(problem(#"{"animations": {"idle": {"sheet": "s.png", "columns": 9223372036854775807, "rows": 2, "count": 1}}}"#) != nil
                     && problem(#"{"animations": {"idle": {"sheet": "s.png", "columns": 4, "start": -3}}}"#) != nil
                     && problem(#"{"animations": {"idle": {"sheet": "s.png", "columns": 4, "rows": 2, "row": 1, "start": 9}}}"#) != nil
                     && problem(#"{"animations": {"idle": {"sheet": "s.png", "columns": 100, "rows": 100, "count": 5000}}}"#)
                        == .tooManyFrames("idle", 5000),
                     "a grid too big, a start outside it or too many cells is refused before any cell is counted out")
        if case .success(let big) = pack(#"{"animations": {"idle": {"sheet": "s.png", "columns": 256, "rows": 256}}}"#) {
            suite.expect(big.clips[.idle]?.declaredFrameCount == NotchCompanionPack.maxFrames,
                         "a large sheet without a count is read up to the frame limit")
        } else {
            suite.expect(false, "a large sheet without a count parses")
        }
        suite.expect(problem(#"{"animations": {"idle": {"sheet": "s.png", "columns": 4, "count": 5}}}"#) != nil
                     && problem(#"{"animations": {"idle": {"sheet": "s.png", "columns": 4, "rows": 2, "row": 2}}}"#) != nil,
                     "frames past the sheet's end are refused")
        suite.expect(problem(#"{"animations": {"idle": {"frames": ["a.png", "b.png"], "durations": [100, 100, 100]}}}"#)
                     == .badTiming("idle", "give one duration, or one per frame (2)"),
                     "durations come one per frame, or one for all")
        suite.expect(problem(#"{"animations": {"idle": {"frames": ["a.png"], "fps": 0}}}"#) != nil
                     && problem(#"{"animations": {"idle": {"frames": ["a.png"], "durations": [5]}}}"#) != nil,
                     "timings out of range are refused")
        suite.expect(problem(#"{"animations": {"idle": {"frames": ["a.png"], "chromaKey": {"color": "green"}}}}"#)
                     == .badChromaKey("idle"), "a key color must be hex")
        suite.expect(problem(#"{"animations": {"idle": {"frames": "missing"}}}"#) == .noFrames("idle")
                     && problem(#"{"animations": {"idle": {"frames": []}}}"#) == .noFrames("idle"),
                     "an animation with nothing to show is refused")
        suite.expect(problem(#"{"name": "x"}"#).map { "\($0)".contains("animations") } == true
                     && problem("not json") != nil, "a broken manifest says what is wrong")
        let many = (0...NotchCompanionPack.maxFrames).map { "\"\($0).png\"" }.joined(separator: ",")
        suite.expect(problem(#"{"animations": {"idle": {"frames": [\#(many)]}}}"#)
                     == .tooManyFrames("idle", NotchCompanionPack.maxFrames + 1), "frame counts are bounded")
    }

    private static func fallbackContracts(_ suite: TestSuite) {
        guard case .success(let idleOnly) = pack(#"{"animations": {"idle": {"frames": ["a.png"]}}}"#),
              case .success(let looker) = pack(#"{"animations": {"idle": {"frames": ["a.png"]}, "lookRight": {"frames": ["w.png"]}, "happy": {"frames": ["h.png"]}}}"#),
              case .success(let both) = pack(#"{"animations": {"idle": {"frames": ["a.png"]}, "lookRight": {"frames": ["w.png"]}, "lookLeft": {"frames": ["l.png"]}}}"#)
        else { suite.expect(false, "fallback packs parse"); return }
        suite.expect(NotchCompanionState.allCases.allSatisfy { idleOnly.resolve($0) == (.idle, false) },
                     "a pack with only idle shows idle, never mirrored, for everything")
        suite.expect(looker.resolve(.lookLeft) == (.lookRight, true) && looker.resolve(.lookRight) == (.lookRight, false)
                     && both.resolve(.lookLeft) == (.lookLeft, false),
                     "looking left mirrors looking right unless the pack draws it")
        suite.expect(looker.resolve(.dance) == (.happy, false) && looker.resolve(.love) == (.happy, false)
                     && looker.resolve(.sad) == (.idle, false),
                     "moments fall back to happy, then idle")
        var seen = Set<NotchCompanionState>()
        for state in NotchCompanionState.allCases {
            var current: NotchCompanionState? = state
            seen = []
            while let next = current, seen.insert(next).inserted { current = next.fallback }
            suite.expect(current == nil && seen.contains(.idle), "\(state.rawValue) falls back to idle without a cycle")
        }
        suite.expect(NotchMascotMood.allCases.allSatisfy { _ = $0.companionState; return true }
                     && NotchMascotMood.sleepy.companionState == .sleep && NotchMascotMood.thinking.companionState == .think
                     && NotchMascotMood.idle.companionState == .idle,
                     "every face the drawn companion makes has a state")
        suite.expect(NotchMascotReaction.groove.companionState == .dance && NotchMascotReaction.love.companionState == .love
                     && NotchMascotReaction.confused.companionState == .sad && NotchMascotReaction.yawn.companionState == .sleep,
                     "reactions play the animation they read as")
    }

    private static func reelContracts(_ suite: TestSuite) {
        guard case .success(let looker) = pack(#"{"animations": {"idle": {"frames": ["a.png", "b.png"]}, "lookRight": {"frames": ["1.png", "2.png", "3.png"]}, "happy": {"frames": ["h1.png", "h2.png"]}}}"#)
        else { suite.expect(false, "the reel pack parses"); return }
        let timing = NotchCompanionTiming(durations: [.idle: [0.3, 0.2], .lookRight: [0.1, 0.1, 0.1], .happy: [0.1, 0.1]],
                                          loops: [.idle: true, .lookRight: true, .happy: false])
        let idle = NotchCompanionReels.cycle(of: .idle, in: looker, timing: timing)
        suite.expect(idle.cels.map(\.frame) == [0, 1] && idle.starts == [0, 0.3] && abs(idle.duration - 0.5) < 1e-9
                     && idle.keyTimes.count == idle.cels.count + 1 && idle.keyTimes.last == 1,
                     "a cycle is every frame once, with a key time more than frames for a discrete animation")
        let happy = NotchCompanionReels.play(.happy, for: 1, in: looker, timing: timing)
        suite.expect(happy.cels.map(\.frame) == [0, 1] && happy.duration == 1,
                     "a moment that plays once holds its last frame for the rest of its time")
        let dance = NotchCompanionReels.play(.dance, for: 0.45, in: looker, timing: timing)
        suite.expect(dance.cels.allSatisfy { $0.state == .happy } && dance.cels.count == 2,
                     "a missing animation plays its stand-in")
        suite.expect(NotchCompanionReels.still(of: .idle, in: looker, timing: timing).frame == 0
                     && NotchCompanionReels.still(of: .happy, in: looker, timing: timing).frame == 1
                     && NotchCompanionReels.still(of: .lookLeft, in: looker, timing: timing)
                        == NotchCompanionCel(state: .lookRight, frame: 0, mirrored: true),
                     "held still, a loop shows its rest and a moment the expression it ends on")
        let looking = NotchCompanionReels.play(.lookRight, for: 0.45, in: looker, timing: timing)
        suite.expect(looking.cels.map(\.frame) == [0, 1, 2, 0, 1], "a loop goes round for as long as it plays")

        var path = NotchMascotPath()
        path.keyTimes = [0, 0.25, 0.5, 0.5, 0.75, 1]
        path.x = [10, 50, 50, 200, 120, 120]
        path.lift = Array(repeating: 0, count: 6)
        path.duration = 2
        let visit = NotchCompanionReels.visit(path, in: looker, timing: timing)
        func cels(from start: TimeInterval, to end: TimeInterval) -> [NotchCompanionCel] {
            zip(visit.starts, visit.cels).filter { $0.0 >= start - 1e-9 && $0.0 < end - 1e-9 }.map(\.1)
        }
        suite.expect(cels(from: 0, to: 0.5).allSatisfy { $0.state == .lookRight && !$0.mirrored }
                     && cels(from: 0.5, to: 1).allSatisfy { $0.state == .idle }
                     && cels(from: 1, to: 1.5).allSatisfy { $0.state == .lookRight && $0.mirrored }
                     && cels(from: 1.5, to: 2).allSatisfy { $0.state == .idle },
                     "on a visit it looks the way it goes, rests where it stands, and a jump takes no time")
        suite.expect(visit.duration == 2 && zip(visit.starts, visit.starts.dropFirst()).allSatisfy { $0 < $1 }
                     && zip(visit.cels, visit.cels.dropFirst()).allSatisfy { $0 != $1 }
                     && visit.keyTimes.count == visit.cels.count + 1,
                     "a visit's frames run in order, a frame held is one keyframe, and it lasts the visit")
        // A real stroll is sampled sixty times a second: the look still
        // shows each frame for as long as it lasts, the way it goes.
        let track = NotchMascotSupport.track(stripWidth: 268, stripHeight: 32, wing: 44, cameraWidth: 180,
                                             floats: false, bodyHeight: 32)
        for kind in [NotchMascotVisit.Kind.pass, .lap, .cameo(.celebrate)] {
            let stroll = NotchMascotMotion.path(for: kind, on: track)
            let reel = NotchCompanionReels.visit(stroll, in: looker, timing: timing)
            let ends = Array(reel.starts.dropFirst()) + [reel.duration]
            // A frame may be cut short only where it stops or turns.
            let paced = reel.cels.indices.dropLast().allSatisfy { index in
                let cel = reel.cels[index], next = reel.cels[index + 1]
                guard cel.state == .lookRight, next.state == .lookRight, cel.mirrored == next.mirrored else { return true }
                return ends[index] - reel.starts[index] > 0.099
            }
            suite.expect(reel.cels.contains { $0.state == .lookRight } && paced && reel.cels.count < Int(stroll.duration * 20),
                         "a sampled \(kind) looks about at the pack's pace, not one frame per sample")
        }
        let empty = NotchCompanionReels.visit(NotchMascotPath(), in: looker, timing: timing)
        suite.expect(empty.cels.isEmpty, "an empty stroll has no frames")
    }

    private static func chromaKeyContracts(_ suite: TestSuite) {
        guard let green = NotchCompanionChromaKey(hex: "#00FF00", tolerance: 0.2) else {
            suite.expect(false, "a key parses"); return
        }
        suite.expect(green.alpha(red: 0, green: 1, blue: 0) == 0 && green.alpha(red: 0.05, green: 0.95, blue: 0.05) == 0,
                     "the key color and colors close to it go")
        suite.expect(green.alpha(red: 1, green: 0.2, blue: 0.2) == 1 && green.alpha(red: 0, green: 0, blue: 0) == 1,
                     "colors far from it stay")
        let edge = green.alpha(red: 0.25, green: 0.75, blue: 0.25)
        suite.expect(edge > 0 && edge < 1, "an edge between them stays partly, so outlines stay soft")
        suite.expect(NotchCompanionChromaKey(hex: "12345") == nil && NotchCompanionChromaKey(hex: "#GGGGGG") == nil
                     && NotchCompanionChromaKey(hex: "abcdef", tolerance: 4)?.tolerance == 1,
                     "only six hex digits make a key, and its tolerance is bounded")
    }

    /// Writes a frame: a red block in the bottom half's middle, on green.
    private static func writeFrame(_ url: URL, width: Int, height: Int, type: UTType = .png) -> Bool {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 4, y: 0, width: width / 2, height: height / 2))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Writes an animated GIF of `frames` frames, each shown `delay` seconds.
    private static func writeGIF(_ url: URL, frames: Int, delay: Double) -> Bool {
        guard let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)
        else { return false }
        for index in 0..<frames {
            context.setFillColor(CGColor(red: CGFloat(index), green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            guard let image = context.makeImage() else { return false }
            CGImageDestinationAddImage(destination, image,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Draws the image so the pixel at (x, y) from the top left lands on the one-pixel canvas.
        context?.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[3])
    }

    private static func diskContracts(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-companion-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Bean", isDirectory: true)
        let idle = folder.appendingPathComponent("idle", isDirectory: true)
        try? FileManager.default.createDirectory(at: idle, withIntermediateDirectories: true)
        var written = (1...3).allSatisfy { writeFrame(idle.appendingPathComponent("\($0).png"), width: 40, height: 60) }
        written = written && writeFrame(folder.appendingPathComponent("look.jpg"), width: 160, height: 60, type: .jpeg)
        written = written && writeFrame(folder.appendingPathComponent("happy.png"), width: 60, height: 30)
        let manifest = """
        {"name": "Bean", "chromaKey": {"color": "#00FF00", "tolerance": 0.25},
         "animations": {"idle": {"frames": "idle", "fps": 5},
                        "lookRight": {"sheet": "look.jpg", "columns": 4},
                        "happy": {"frames": ["happy.png"]}}}
        """
        written = written && FileManager.default.createFile(atPath: folder.appendingPathComponent("companion.json").path,
                                                           contents: Data(manifest.utf8))
        let stray = root.appendingPathComponent("Stray", isDirectory: true)
        try? FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        let broken = root.appendingPathComponent("Broken", isDirectory: true)
        try? FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        written = written && FileManager.default.createFile(atPath: broken.appendingPathComponent("companion.json").path,
                                                           contents: Data(#"{"animations": {}}"#.utf8))
        suite.expect(written, "the fixture pack is written")

        let found = NotchCompanionLibrary.scan(root)
        suite.expect(found.count == 2 && found.contains { $0.id == "Bean" && $0.pack != nil }
                     && found.contains { $0.id == "Broken" && $0.pack == nil && $0.problem?.contains("idle") == true },
                     "packs are found by their manifest, and one that can't be used says why")
        let outside = root.appendingPathComponent("outside.png")
        written = written && writeFrame(outside, width: 8, height: 8)
        try? FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("escape.png"), withDestinationURL: outside)
        try? FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("inside.png"),
                                                    withDestinationURL: idle.appendingPathComponent("1.png"))
        suite.expect(NotchCompanionLibrary.resolve("escape.png", in: folder) == nil
                     && NotchCompanionLibrary.resolve("inside.png", in: folder) != nil,
                     "a symbolic link out of the pack is refused, and one within it is followed")
        suite.expect(NotchCompanionLibrary.resolve("../secret.png", in: folder) == nil
                     && NotchCompanionLibrary.resolve("/etc/hosts", in: folder) == nil
                     && NotchCompanionLibrary.resolve("idle/1.png", in: folder) != nil,
                     "a manifest can't reach outside its folder")

        guard let pack = found.first(where: { $0.id == "Bean" })?.pack,
              let sprites = try? NotchCompanionLibrary.load(pack, from: folder) else {
            suite.expect(false, "the fixture's frames are read"); return
        }
        suite.expect(sprites.frameCount(.idle) == 3 && sprites.frameCount(.lookRight) == 4
                     && sprites.timing.frames(.idle) == [0.2, 0.2, 0.2],
                     "every frame is read, at the animation's frame rate")
        suite.expect(abs(sprites.aspect - 40.0 / 60.0) < 0.02, "the canvas takes the first idle frame's shape")
        if let frame = sprites.image(NotchCompanionCel(state: .idle, frame: 0)) {
            let corner = pixel(frame, x: 1, y: 1)
            let face = pixel(frame, x: frame.width / 2, y: frame.height - 2)
            suite.expect(corner.alpha == 0 && face.alpha == 255 && face.red > 200,
                         "the green backdrop goes and the character stays")
        } else {
            suite.expect(false, "an idle frame is there")
        }
        if let look = sprites.image(NotchCompanionCel(state: .lookRight, frame: 1)),
           let flipped = sprites.image(NotchCompanionCel(state: .lookRight, frame: 1, mirrored: true)) {
            let chin = pixel(look, x: look.width / 2, y: look.height - 2)
            suite.expect(chin.alpha > 200 && chin.red > 180 && pixel(look, x: look.width / 2, y: 1).alpha == 0,
                         "a JPEG sheet's cells are cut apart and keyed")
            suite.expect(flipped.width == look.width && flipped !== look, "a mirrored frame is its own image")
        } else {
            suite.expect(false, "the look's frames are there")
        }
        if let wide = sprites.image(NotchCompanionCel(state: .happy, frame: 0)) {
            // A 60 by 30 frame fit into the 40 by 60 canvas is 40 by 20, rows 20 to 40.
            suite.expect(wide.width == sprites.image(NotchCompanionCel(state: .idle, frame: 0))?.width
                         && pixel(wide, x: 20, y: 35).alpha == 255 && pixel(wide, x: 20, y: 2).alpha == 0
                         && pixel(wide, x: 20, y: 57).alpha == 0,
                         "a frame of another shape is fit into the canvas's middle, so the face keeps its place")
        } else {
            suite.expect(false, "the wide frame is there")
        }
        // A pack whose links lead to its own files, by absolute path, still
        // reads once copied elsewhere; one leading out of it is left behind.
        try? FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("absolute.png"),
                                                    withDestinationURL: idle.appendingPathComponent("2.png"))
        let copied = root.appendingPathComponent("Copied", isDirectory: true)
        let copiedOK = (try? NotchCompanionLibrary.copy(folder, to: copied)) != nil
        let manager = FileManager.default
        suite.expect(copiedOK && NotchCompanionLibrary.resolve("absolute.png", in: copied) != nil
                     && (try? manager.destinationOfSymbolicLink(atPath: copied.appendingPathComponent("absolute.png").path)) == nil
                     && manager.fileExists(atPath: copied.appendingPathComponent("idle/3.png").path)
                     && !manager.fileExists(atPath: copied.appendingPathComponent("escape.png").path),
                     "a copied pack keeps its own linked frames as files, and drops links out of it")
        // A pack reached through a link, with a linked frames folder whose
        // frames link back into the pack by absolute path, copies whole.
        let real = folder.appendingPathComponent("real", isDirectory: true)
        try? manager.createDirectory(at: real, withIntermediateDirectories: true)
        try? manager.createSymbolicLink(at: real.appendingPathComponent("linked.png"),
                                        withDestinationURL: idle.appendingPathComponent("1.png"))
        try? manager.createSymbolicLink(at: folder.appendingPathComponent("frames"), withDestinationURL: real)
        let alias = root.appendingPathComponent("Alias")
        try? manager.createSymbolicLink(at: alias, withDestinationURL: folder)
        let throughAlias = root.appendingPathComponent("ThroughAlias", isDirectory: true)
        let aliasCopied = (try? NotchCompanionLibrary.copy(alias, to: throughAlias)) != nil
        suite.expect(aliasCopied && manager.fileExists(atPath: throughAlias.appendingPathComponent("companion.json").path)
                     && NotchCompanionLibrary.resolve("frames/linked.png", in: throughAlias) != nil
                     && (try? manager.destinationOfSymbolicLink(atPath: throughAlias.appendingPathComponent("frames/linked.png").path)) == nil
                     && NotchCompanionLibrary.read(throughAlias)?.pack != nil,
                     "a pack reached through a link copies whole, linked folders and the links in them included")
        // Links back up the pack are skipped, not copied over and over.
        let assets = folder.appendingPathComponent("assets", isDirectory: true)
        try? manager.createDirectory(at: assets, withIntermediateDirectories: true)
        try? manager.createSymbolicLink(at: assets.appendingPathComponent("a"), withDestinationURL: assets)
        try? manager.createSymbolicLink(at: assets.appendingPathComponent("b"), withDestinationURL: folder)
        let cyclic = root.appendingPathComponent("Cyclic", isDirectory: true)
        let started = Date()
        let cyclicCopied = (try? NotchCompanionLibrary.copy(folder, to: cyclic)) != nil
        let entries = manager.enumerator(atPath: cyclic.path)?.allObjects.count ?? 0
        suite.expect(cyclicCopied && entries < 60 && Date().timeIntervalSince(started) < 2
                     && NotchCompanionLibrary.read(cyclic)?.pack != nil,
                     "links back up the pack are skipped, so a copy stays the size of the pack")
        if writeGIF(folder.appendingPathComponent("blink.gif"), frames: 2, delay: 0.5) {
            func timing(_ manifest: String) -> [TimeInterval]? {
                guard case .success(let parsed) = NotchCompanionPack.parse(Data(manifest.utf8), id: "gif", listing: { _ in nil }),
                      let read = try? NotchCompanionLibrary.load(parsed, from: folder) else { return nil }
                return read.timing.durations[.idle]
            }
            suite.expect(timing(#"{"animations": {"idle": {"frames": "blink.gif"}}}"#) == [0.5, 0.5]
                         && timing(#"{"fps": 20, "animations": {"idle": {"frames": "blink.gif"}}}"#) == [0.5, 0.5],
                         "an animated image keeps its own delays, whatever the pack's default frame rate")
            suite.expect(timing(#"{"animations": {"idle": {"frames": "blink.gif", "fps": 20}}}"#) == [0.05, 0.05]
                         && timing(#"{"animations": {"idle": {"frames": "blink.gif", "durations": [200]}}}"#) == [0.2, 0.2],
                         "an animation's own frame rate or durations override the image's delays")
        } else {
            suite.expect(false, "the animated fixture is written")
        }
        if case .failure = Result(catching: { try NotchCompanionLibrary.load(
            NotchCompanionPack(id: "x", name: "x", summary: "", scale: 1,
                               clips: [.idle: NotchCompanionClip(source: .files(["missing.png"]), durations: nil,
                                                                 frameDuration: 0.1, loops: true, chromaKey: nil)]),
            from: folder) }) {
            suite.expect(true, "a missing frame fails the pack")
        } else {
            suite.expect(false, "a missing frame fails the pack")
        }
    }

    private static func preferenceContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.companion"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(NotchMascotStyle.character.rawValue, forKey: DefaultsKey.notchMascotStyle)
        defaults.set("bean", forKey: DefaultsKey.notchMascotCharacter)
        let look = NotchMascotSupport.look(in: defaults)
        suite.expect(look.style == .character && look.character == "bean",
                     "the character style and its pack are read as chosen")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchMascotCharacter] != nil
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchMascotCharacter),
                     "the chosen character travels in a settings backup")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchCompanion(language)
            let all = [text.character, text.characterHint, text.empty, text.add, text.openFolder, text.reload,
                       text.unusable, text.addFailed, text.generate, text.generateTitle, text.subject,
                       text.subjectPlaceholder, text.look, text.generateHint, text.start, text.cancel,
                       text.needsCodex, text.needsTools, text.generateFailed] + NotchCompanionGenerator.Style.allCases.map(text.style)
            suite.expect(all.allSatisfy { !$0.isEmpty } && text.characterHint.contains("companion.json")
                         && text.drawing.components(separatedBy: "%@").count == 2
                         && text.generated.components(separatedBy: "%@").count == 2
                         && text.images.components(separatedBy: "%d").count == 3
                         && String(format: text.images, 3, 12).contains("12"),
                         "\(language.rawValue) has every character string, names the manifest, and keeps its placeholders")
        }
    }
}
