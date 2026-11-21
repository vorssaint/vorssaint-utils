// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SwiftUI

/// The bar that turns a request about the Finder selection into one shell
/// command. Nothing runs in the background: no polling, no cached window and
/// no connection exist until the shortcut is pressed, and the window and its
/// view tree are released when the bar closes.
final class AIBarService: ObservableObject {
    static let shared = AIBarService()

    enum Phase: Equatable {
        case idle
        case generating
        case ready(command: String)
        case running
        case finished(output: String, status: Int32, timedOut: Bool)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [AIBarItem] = []
    @Published private(set) var folder: URL?
    @Published private(set) var prediction: AIBarPrediction?
    @Published private(set) var pressesLeft = 0
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var detectedModels: [String] = []
    @Published private(set) var isDetectingModels = false
    @Published var request = ""

    private let hotkey = QuickToolHotkey(id: 90)
    private var panel: NSPanel?
    private var generation: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?

    private static let outputLimit = 64 * 1024
    private static let runTimeout: TimeInterval = 120

    private init() {}

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: Lifecycle

    func syncWithPreferences() {
        let available = AppFeature.aiBar.isAvailable
        let enabled = available && UserDefaults.standard.bool(forKey: DefaultsKey.aiBarShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.aiBarShortcut, fallback: .aiBarDefault)
        hotkey.onPress = { [weak self] in self?.toggle() }
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.aiBarShortcut)
        if !available { hide() }
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard AppFeature.aiBar.isAvailable else { return }
        reset()
        let panel = ensurePanel()
        position(panel, dockedBelow: nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        // The Finder is asked off the main thread: a busy Finder must not
        // hold the keystroke that opened the bar.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = FinderBridge.selectionURLs()
            let folder = FinderBridge.insertionLocationPath().map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? urls.first?.deletingLastPathComponent()
            let bounds = Self.frontFinderWindowFrame()
            let items = urls.map {
                AIBarItem(url: $0, isDirectory: (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
            }
            DispatchQueue.main.async {
                guard let self, self.isVisible else { return }
                self.items = items
                self.folder = folder
                if let bounds, let panel = self.panel { self.position(panel, dockedBelow: bounds) }
            }
        }
    }

    func hide() {
        generation?.cancel()
        generation = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        // Released with the window: a closed bar holds no view tree.
        panel?.contentViewController = nil
        panel = nil
        reset()
    }

    private func reset() {
        phase = .idle
        prediction = nil
        pressesLeft = 0
        items = []
        folder = nil
        request = ""
    }

    // MARK: Generating

    func submit() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase != .generating, phase != .running else { return }
        let defaults = UserDefaults.standard
        let endpoint = defaults.string(forKey: DefaultsKey.aiBarEndpoint) ?? ""
        let model = defaults.string(forKey: DefaultsKey.aiBarModel) ?? ""
        let local = AIBarContextLevel(rawValue: defaults.string(forKey: DefaultsKey.aiBarLocalContext) ?? "") ?? .fullPaths
        let remote = AIBarContextLevel(rawValue: defaults.string(forKey: DefaultsKey.aiBarRemoteContext) ?? "") ?? .namesOnly
        let level = AIBarPrompt.level(baseURL: endpoint, local: local, remote: remote)
        let lines = AIBarPrompt.contextLines(items: items, folder: folder, level: level)
        let message = AIBarPrompt.userMessage(request: text, contextLines: lines, level: level)
        let key = AIBarKeychain.read()
        let strings = FeatureStrings.aiBar(L10n.shared.language)

        prediction = nil
        phase = .generating
        generation?.cancel()
        generation = Task { @MainActor [weak self] in
            do {
                let reply = try await AIBarClient.complete(endpoint: endpoint, model: model, key: key,
                                                           system: AIBarPrompt.systemPrompt, user: message)
                guard !Task.isCancelled else { return }
                self?.accept(reply: reply, strings: strings)
            } catch {
                guard !Task.isCancelled else { return }
                let text: String
                switch error as? AIBarClient.Failure {
                case .notConfigured: text = strings.notConfigured
                case .insecureEndpoint: text = strings.insecureEndpoint
                case .status(let code): text = String(format: strings.unreachableFormat, "HTTP \(code)")
                case .network(let detail): text = String(format: strings.unreachableFormat, detail)
                default: text = strings.cannot
                }
                self?.phase = .failed(text)
            }
        }
    }

    private func accept(reply: String, strings: AIBarFeatureStrings) {
        guard phase == .generating else { return }
        guard let command = AIBarPrompt.extractCommand(from: reply) else {
            phase = .failed(strings.cannot)
            return
        }
        let predicted = AIBarSafety.predict(command)
        prediction = predicted
        pressesLeft = AIBarSafety.pressesToRun(predicted)
        phase = .ready(command: command)
    }

    /// Lets the person correct a command before it runs; the prediction is
    /// taken again so an edit cannot keep an earlier, milder verdict.
    func edit(command: String) {
        guard case .ready = phase else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let predicted = AIBarSafety.predict(trimmed)
        prediction = predicted
        pressesLeft = AIBarSafety.pressesToRun(predicted)
        phase = .ready(command: trimmed)
    }

    // MARK: Running

    /// The command starts on the last required press. A dangerous one needs two.
    func confirmOrRun() {
        guard case .ready(let command) = phase else { return }
        pressesLeft -= 1
        if pressesLeft > 0 { return }
        run(command)
    }

    private func run(_ command: String) {
        phase = .running
        let directory = (folder ?? FileManager.default.homeDirectoryForCurrentUser).path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BoundedProcessRunner.runInNewSession(
                "/bin/zsh", ["-f", "-c", "cd -- \"$AIBAR_DIR\" || exit 1; eval \"$AIBAR_CMD\""],
                timeout: Self.runTimeout, maxOutputBytes: Self.outputLimit,
                environment: Self.environment(directory: directory, command: command))
            let output = String(decoding: result.output, as: UTF8.self)
            DispatchQueue.main.async {
                guard let self, self.panel != nil else { return }
                self.phase = .finished(output: output, status: result.status, timedOut: result.timedOut)
            }
        }
    }

    static func environment(directory: String, command: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
        environment["PATH"] = extra + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        environment["AIBAR_DIR"] = directory
        environment["AIBAR_CMD"] = command
        return environment
    }

    func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    /// Back to the field with the request kept, to ask again or refine.
    func backToRequest() {
        generation?.cancel()
        phase = .idle
        prediction = nil
        pressesLeft = 0
    }

    // MARK: Models

    func detectModels(endpoint: String) {
        guard !isDetectingModels else { return }
        isDetectingModels = true
        let key = AIBarKeychain.read()
        Task { @MainActor [weak self] in
            let names = (try? await AIBarClient.listModels(endpoint: endpoint, key: key)) ?? []
            self?.detectedModels = names
            self?.isDetectingModels = false
        }
    }

    // MARK: Panel

    private final class KeyablePanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 120),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: AIBarView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            // Clicking away closes the bar, except while a command is running.
            guard let self, self.phase != .running else { return }
            self.hide()
        }
        self.panel = panel
        return panel
    }

    /// Under the front Finder window when there is one, otherwise a little
    /// above the middle of the screen the pointer is on.
    private func position(_ panel: NSPanel, dockedBelow window: NSRect?) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 580, height: 120)
        let screen = NSScreen.pointerVisibleFrame
        var origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY + screen.height * 0.12 - size.height)
        if let window {
            origin = NSPoint(x: window.midX - size.width / 2, y: window.minY - size.height - 8)
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// The front Finder window in AppKit coordinates. Finder reports it from
    /// the top left of the primary display, so it is flipped here.
    private static func frontFinderWindowFrame() -> NSRect? {
        let result = AppleScriptRunner.run("tell application \"Finder\" to get bounds of front Finder window")
        guard result.ok else { return nil }
        let numbers = result.output.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard numbers.count == 4, let primary = NSScreen.screens.first?.frame.height else { return nil }
        let (left, top, right, bottom) = (numbers[0], numbers[1], numbers[2], numbers[3])
        guard right > left, bottom > top else { return nil }
        return NSRect(x: left, y: primary - bottom, width: right - left, height: bottom - top)
    }
}
