// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Draws a new character with Codex. The vorssaint-companion skill, which
/// the app carries and installs into Codex, runs headless under
/// `codex exec`: Codex's image generation draws the face and each
/// expression, and the skill's tool cuts them into a pack. The app then adds
/// the pack and picks it. Nothing runs until the user asks for a character.
final class NotchCompanionGenerator: ObservableObject {
    static let shared = NotchCompanionGenerator()

    enum Phase: Equatable {
        case idle
        case running(Progress)
        case finished(id: String, name: String)
        case failed(String)
    }

    struct Progress: Equatable {
        var subject: String
        /// What Codex last said it is doing.
        var status: String
        var images: Int
        var expectedImages: Int
    }

    /// How the face is drawn. Never pixel art.
    enum Style: String, CaseIterable, Identifiable {
        case illustration, anime, render, painterly

        var id: String { rawValue }

        var prompt: String {
            switch self {
            case .illustration: return "polished 2D digital illustration, soft cel shading, gentle highlights"
            case .anime: return "high-quality anime illustration in the style of a modern TV anime key visual, clean line art, soft cel shading, glossy eyes"
            case .render: return "soft 3D render like a modern animated feature film, smooth materials, gentle studio lighting"
            case .painterly: return "painterly digital painting with soft visible brushwork and warm lighting"
            }
        }
    }

    @Published private(set) var phase = Phase.idle
    /// The Codex command line, once found; nil while looking or without one.
    @Published private(set) var codex: URL?
    @Published private(set) var lookedForCodex = false
    /// Whether Apple's Command Line Tools are there: the skill builds its
    /// helper with Swift, which macOS has only with them.
    @Published private(set) var hasSwift = false

    private var process: Process?
    private var run: URL?
    private var pending = Data()
    private var errorTail = Data()
    private var cancelled = false
    /// Counts runs, so the check of one that was stopped can't add its pack
    /// in the middle of the next.
    private var runNumber = 0
    private var terminationObserver: NSObjectProtocol?
    /// Codex saves each image it draws in a folder named for the run's
    /// thread, and says nothing of them in its events. Redrawn sheets land
    /// there too, so progress counts the base face once something is drawn,
    /// and each state once its frames are cut into the pack.
    private var imagesFolder: URL?
    private var imageCount: Timer?

    static let skillName = "vorssaint-companion"
    /// The states drawn for a new character: every one but `lookLeft`,
    /// which mirrors `lookRight`.
    static let states = NotchCompanionState.allCases.filter { $0 != .lookLeft }
    static let framesPerState = 8

    init() {
        // A run left going would go on drawing after the app quits.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: Codex

    static var codexHome: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    /// The login shell's PATH, once Codex had to be looked for along it.
    private var searchPath: String?

    /// Looks for Codex off the main thread, as the AI Agents page does:
    /// inside the desktop app, where its installers put it, and along the
    /// login shell's PATH, since an app opened from the Finder has none.
    func locateCodex() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AgentCodexServer.appIdentifiers.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
            let home = FileManager.default.homeDirectoryForCurrentUser
            var path: String?
            var found = AgentCodexServer.executable(apps: apps, home: home)
            if found == nil {
                path = Self.run("/bin/zsh", ["-lc", "printf '%s' \"$PATH\""])
                found = AgentCodexServer.executable(apps: apps, home: home, searchPath: path)
            }
            let swift = Self.swiftAvailable()
            DispatchQueue.main.async {
                self.codex = found
                self.searchPath = path
                self.hasSwift = swift
                self.lookedForCodex = true
            }
        }
    }

    /// Asks `xcode-select` where the developer tools are, which never offers
    /// to install them as `swift` or `xcrun` would, and looks for the
    /// compiler there.
    static func swiftAvailable() -> Bool {
        guard let folder = run("/usr/bin/xcode-select", ["-p"]), folder.hasPrefix("/") else { return false }
        return ["\(folder)/usr/bin/swiftc", "\(folder)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The first line `tool` prints, nil when it fails or takes too long.
    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Copies the skill the app carries into Codex's skills, replacing an
    /// older copy, so Codex draws to the contract this version reads.
    @discardableResult
    static func installSkill(from bundled: URL, into home: URL = codexHome) throws -> URL {
        let target = home.appendingPathComponent("skills/\(skillName)", isDirectory: true)
        let manager = FileManager.default
        let current = try? Data(contentsOf: target.appendingPathComponent("SKILL.md"))
        let tool = "scripts/companion_tool.swift"
        if current == (try? Data(contentsOf: bundled.appendingPathComponent("SKILL.md"))),
           (try? Data(contentsOf: target.appendingPathComponent(tool))) == (try? Data(contentsOf: bundled.appendingPathComponent(tool))) {
            return target
        }
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
        try manager.copyItem(at: bundled, to: target)
        return target
    }

    // MARK: Prompt and events

    /// What Codex is asked to do: the whole skill, without questions, up to
    /// a checked pack in `./run/pack`, which the app installs itself.
    static func prompt(subject: String, style: Style, states: [NotchCompanionState] = states,
                       frames: Int = framesPerState) -> String {
        """
        Use the $\(skillName) skill to create a Vorssaint companion character.

        Character: \(subject)
        Look: \(style.prompt). High quality, never pixel art. Face only.
        States: \(states.map(\.rawValue).joined(separator: ",")). Frames per state: \(frames).
        Run folder: the current working directory. Prepare the run with --out ./run.

        Work non-interactively: never ask questions, infer anything missing, and do not use subagents.
        If the character is an existing fictional character, draw a fan-art portrait of them in the requested look.
        Do every step up to and including validate and preview. Do not run the install step: the app installs the pack itself from ./run/pack.
        Finish with one line: PACK <absolute path of the pack folder>
        """
    }

    enum Event: Equatable {
        /// The run's thread began; its images go in a folder of that name.
        case thread(String)
        /// Codex said what it is doing.
        case message(String)
        case failure(String)
    }

    /// One line of `codex exec --json`.
    static func event(from line: Data) -> Event? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        if type == "thread.started", let id = json["thread_id"] as? String, !id.isEmpty, !id.contains("/") {
            return .thread(id)
        }
        if type == "turn.failed" || type == "error" {
            let error = json["error"] as? [String: Any]
            return .failure(error?["message"] as? String ?? json["message"] as? String ?? "Codex stopped.")
        }
        guard type == "item.completed", let item = json["item"] as? [String: Any],
              let kind = item["type"] as? String else { return nil }
        if kind == "agent_message", let text = item["text"] as? String {
            let line = text.split(separator: "\n").first.map(String.init) ?? text
            return .message(line.replacingOccurrences(of: "`", with: ""))
        }
        return nil
    }

    /// The states asked for that a generated pack lacks, or has too few
    /// frames of to move.
    static func missing(in sprites: NotchCompanionSprites, states: [NotchCompanionState] = states) -> [NotchCompanionState] {
        states.filter { sprites.pack.clips[$0] == nil || sprites.frameCount($0) < 2 }
    }

    // MARK: Running

    func start(subject: String, style: Style) {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !isRunning, hasSwift, let codex else { return }
        guard let skill = Bundle.main.resourceURL?.appendingPathComponent("CompanionSkill", isDirectory: true),
              FileManager.default.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path) else {
            phase = .failed("This build has no companion skill to give Codex.")
            return
        }
        guard let runs = PrivateFileStore.containerURL?.appendingPathComponent("CompanionRuns", isDirectory: true) else {
            phase = .failed("The app's folder can't be found.")
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let run = runs.appendingPathComponent(stamp, isDirectory: true)
        do {
            try Self.installSkill(from: skill)
            guard PrivateFileStore.createDirectory(at: run) else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        let process = Process()
        process.executableURL = codex
        process.arguments = ["exec", "--json", "--skip-git-repo-check", "--sandbox", "workspace-write",
                             "--cd", run.path, "--output-last-message", run.appendingPathComponent("last-message.txt").path, "-"]
        process.currentDirectoryURL = run
        process.environment = AgentCodexServer.environment(for: codex, searchPath: searchPath)
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Codex quitting as it starts fails the prompt's write rather than
        // ending the app with SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            phase = .failed("Codex can't be started.")
            return
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.read(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self else { return }
                self.errorTail.append(data)
                if self.errorTail.count > 4096 { self.errorTail = self.errorTail.suffix(4096) }
            }
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            let rest = output.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                self?.read(rest)
                self?.finish(status: finished.terminationStatus)
            }
        }
        pending = Data()
        errorTail = Data()
        cancelled = false
        runNumber += 1
        self.run = run
        phase = .running(Progress(subject: subject, status: "", images: 0, expectedImages: Self.states.count + 1))
        do {
            try process.run()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        self.process = process
        imagesFolder = nil
        imageCount = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.countImages() }
        // A failed write ends the run, which reports what Codex said.
        try? input.fileHandleForWriting.write(contentsOf: Data(Self.prompt(subject: subject, style: style).utf8))
        try? input.fileHandleForWriting.close()
    }

    /// Stops a run: Codex while it draws, or the pack it left while its
    /// frames are still being checked, which is then not added.
    func cancel() {
        guard isRunning else { return }
        cancelled = true
        if let process, process.isRunning { process.terminate() } else { phase = .idle }
    }

    /// Back to choosing, once a result has been seen.
    func dismiss() {
        guard !isRunning else { return }
        phase = .idle
    }

    private func read(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            guard case .running(var progress) = phase, let event = Self.event(from: Data(line)) else { continue }
            switch event {
            case .thread(let id):
                imagesFolder = Self.codexHome.appendingPathComponent("generated_images/\(id)", isDirectory: true)
            case .message(let text): progress.status = text
            case .failure(let text) where text.lowercased().contains("under-development"): continue
            case .failure(let text): progress.status = text
            }
            phase = .running(progress)
        }
    }

    private func countImages() {
        guard case .running(var progress) = phase, let imagesFolder, let run else { return }
        let manager = FileManager.default
        let drawn = ((try? manager.contentsOfDirectory(atPath: imagesFolder.path)) ?? []).contains { $0.hasSuffix(".png") }
        let pack = run.appendingPathComponent("run/pack", isDirectory: true)
        let states = ((try? manager.contentsOfDirectory(atPath: pack.path)) ?? []).filter { name in
            NotchCompanionState(rawValue: name) != nil
                && ((try? manager.contentsOfDirectory(atPath: pack.appendingPathComponent(name).path)) ?? []).contains { $0.hasSuffix(".png") }
        }
        let count = (drawn ? 1 : 0) + states.count
        guard count != progress.images else { return }
        progress.images = count
        phase = .running(progress)
    }

    private func finish(status: Int32) {
        process = nil
        imageCount?.invalidate()
        imageCount = nil
        guard let run else { return }
        defer { self.run = nil }
        if cancelled {
            try? FileManager.default.removeItem(at: run)
            phase = .idle
            return
        }
        let pack = run.appendingPathComponent("run/pack", isDirectory: true)
        guard status == 0, let entry = NotchCompanionLibrary.read(pack), let made = entry.pack else {
            let said = (try? String(contentsOf: run.appendingPathComponent("last-message.txt"), encoding: .utf8)) ?? ""
            let stderr = String(decoding: errorTail, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? ""
            let reason = NotchCompanionLibrary.read(pack)?.problem ?? (said.isEmpty ? stderr : said)
            phase = .failed(reason.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        let slug = (try? Data(contentsOf: run.appendingPathComponent("run/run.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["slug"] as? String
        // Every frame is read before the pack is added: a manifest Codex
        // left over missing or broken images is a failed run, not a character.
        let number = runNumber
        DispatchQueue.global(qos: .userInitiated).async {
            let frames = Result { try NotchCompanionLibrary.load(made, from: pack) }
            DispatchQueue.main.async {
                guard !self.cancelled, number == self.runNumber else {
                    try? FileManager.default.removeItem(at: run)
                    return
                }
                switch frames {
                case .failure(let error):
                    self.phase = .failed("\(error)")
                    return
                case .success(let sprites):
                    // A pack added by hand may be as small as its author
                    // likes; one asked of Codex has every face it was asked for.
                    let missing = Self.missing(in: sprites)
                    guard missing.isEmpty else {
                        self.phase = .failed("Codex finished without these expressions: "
                                             + missing.map(\.rawValue).joined(separator: ", ") + ".")
                        return
                    }
                }
                do {
                    let id = try NotchCompanionLibrary.shared.importPack(from: pack, named: slug)
                    UserDefaults.standard.set(NotchMascotStyle.character.rawValue, forKey: DefaultsKey.notchMascotStyle)
                    UserDefaults.standard.set(id, forKey: DefaultsKey.notchMascotCharacter)
                    self.phase = .finished(id: id, name: made.name)
                } catch {
                    self.phase = .failed("\(error)")
                }
            }
        }
    }
}
