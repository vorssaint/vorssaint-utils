// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import SwiftUI

/// The OpenBot window in Vorssaint's frame. OpenBot is an Electron app whose
/// renderer only lives inside its own process, so the window shows the real
/// OpenBot page through Chrome's DevTools protocol: the page is screencast
/// frame by frame into this surface, and the mouse, wheel and keys Vorssaint
/// receives are dispatched straight back into the page.
///
/// OpenBot's own window never stands alone on the screen. Each time the
/// service brings the app up it writes the app's window-state file first,
/// parking the window one pixel behind the card — enough of it stays
/// uncovered that macOS never marks it occluded, so it keeps painting,
/// while the card covers the rest. The page itself is rendered at the
/// card's size through a metrics override, and while the card is closed
/// the app is simply hidden: a hidden renderer freezes, and unhiding it
/// when the card opens again picks the stream straight back up.
final class OpenBotMirrorService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = OpenBotMirrorService()

    enum Phase: Equatable {
        case idle
        case launching
        case connecting
        case streaming
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isPinned = false

    /// The surface that is on screen, so frames skip SwiftUI publishing.
    weak var surface: OpenBotMirrorSurface?

    private static let debugPort = 9_222
    private static let appBundleID = "app.openbot.desktop"
    private static let targetURLPrefix = "openbot-app://app/index.html"

    private var panel: NSPanel?
    private var socket: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [Int: (Result<[String: Any], Error>) -> Void] = [:]
    /// The page area of the card, in points; the mirrored page is forced
    /// to render at exactly this size.
    private var overrideWidth: Double = 980
    private var overrideHeight: Double = 620
    private var viewportSyncPending: DispatchWorkItem?
    private var reconnectAttempts = 0
    private var outsideClickMonitor: Any?
    private let queue = DispatchQueue(label: "com.vorssaint.openbot.mirror")
    private let hotkey = QuickToolHotkey(id: 19)

    private override init() {
        super.init()
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    // MARK: - Preferences

    func syncWithPreferences() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.openBotShortcut,
                                            fallback: .openBotDefault)
        _ = hotkey.sync(enabled: true, shortcut: shortcut,
                        storageKey: DefaultsKey.openBotShortcut)
    }

    func suspend() {
        hotkey.unregister()
        hide()
        disconnect()
    }

    // MARK: - Window

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if isVisible {
            panel?.makeKey()
            return
        }
        let panel = ensurePanel()
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        // Every opening starts as a card that steps aside on a click outside,
        // the way the rest of Vorssaint's pads behave; one click on the pin
        // keeps it floating instead.
        isPinned = false
        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
        begin(initial: true)
    }

    func hide() {
        guard panel != nil else { return }
        removeMonitors()
        panel?.orderOut(nil)
        isPinned = false
        // Nothing mirrors while the card is closed, and the app's own
        // window must never appear on the desktop. The hidden renderer
        // freezes; unhiding on the next opening resumes it.
        send("Page.stopScreencast")
        hideOpenBotApp()
    }

    func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = OpenBotMirrorPanel(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                                       styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                       backing: .buffered,
                                       defer: false)
        panel.title = "OpenBot"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 480, height: 380)
        panel.delegate = self
        let host = NSHostingController(rootView: OpenBotMirrorView())
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 980, height: 660))
        center(panel)
        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.5
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, min(y, screen.maxY - size.height - 16)),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Window delegate

    func windowWillClose(_ notification: Notification) {
        hide()
    }

    // MARK: - OpenBot's own window

    /// The running OpenBot, whatever context asks for it.
    private var openBotApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.appBundleID).first
    }

    /// OpenBot's own window is never part of the show: the app is tucked
    /// away whenever the card is not streaming it. No accessibility grant,
    /// no automation prompt — hiding an app needs neither.
    private func hideOpenBotApp() {
        guard let app = openBotApp, !app.isHidden else { return }
        app.hide()
    }

    /// The card's frame in the coordinate system OpenBot's window-state
    /// file uses: points from the top-left of the display, with one pixel
    /// of width to spare so the parked window is never fully covered.
    private func parkedFrame() -> CGRect? {
        guard let panel else { return nil }
        let frame = panel.frame
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }) ?? NSScreen.main else { return nil }
        return CGRect(x: frame.minX,
                      y: screen.frame.maxY - frame.maxY,
                      width: frame.width + 1,
                      height: frame.height)
    }

    /// OpenBot reads its window bounds back from a state file whenever it
    /// launches and clamps them to the work area, so writing that file
    /// while nothing runs parks the app's window behind the card — no
    /// accessibility, no automation, nothing but a file the app owns.
    private func parkOpenBotWindow(at frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let state: [String: Any] = ["version": 1,
                                    "x": Int(frame.minX),
                                    "y": Int(frame.minY),
                                    "width": Int(frame.width),
                                    "height": Int(frame.height)]
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        let file = support.appendingPathComponent("OpenBot/openbot-main-window-state-v1.json")
        try? data.write(to: file)
    }

    // MARK: - Connection

    /// The card's own opening may bring OpenBot up with the debugger port;
    /// an automatic reconnect after a dropped socket never relaunches the
    /// app, it only re-attaches while the port stays open.
    private func begin(initial: Bool) {
        queue.async { [self] in
            portIsOpen { open in
                DispatchQueue.main.async { [self] in
                    if open {
                        connect()
                    } else if initial {
                        launchWithDebugger()
                    } else {
                        phase = .failed("OpenBot kjører ikke")
                    }
                }
            }
        }
    }

    private func portIsOpen(_ completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.debugPort)/json/version")!)
        request.timeoutInterval = 1
        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode == 200)
        }.resume()
    }

    /// OpenBot only opens the debugger endpoint when launched with the
    /// switch, so an app that is already running without it has to be
    /// relaunched; its state lives on disk, so nothing is lost.
    private func launchWithDebugger() {
        phase = .launching
        // Park the app's window where the card is about to stream it from.
        let park = parkedFrame()
        let openBotRunning = NSRunningApplication.runningApplications(withBundleIdentifier: Self.appBundleID).first != nil
        if let app = openBotApp {
            app.terminate()
        }
        queue.async { [self] in
            if openBotRunning {
                wait(for: { NSRunningApplication.runningApplications(withBundleIdentifier: Self.appBundleID).isEmpty },
                     timeout: 12)
            }
            // The old instance flushes its live bounds on quit, so the park
            // only lands once nothing is left to overwrite it.
            if let park {
                parkOpenBotWindow(at: park)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            // The backgrounding switches are the heart of the mirror: without
            // them a hidden Electron window stops compositing, and with them
            // the renderer keeps painting frames no desktop ever sees.
            process.arguments = ["-a", "OpenBot", "--args",
                                 "--remote-debugging-port=\(Self.debugPort)",
                                 "--disable-backgrounding-occluded-windows",
                                 "--disable-renderer-backgrounding",
                                 "--disable-background-timer-throttling"]
            try? process.run()
            DispatchQueue.main.async { [self] in
                waitForPort()
            }
        }
    }

    private func waitForPort(tries: Int = 0) {
        portIsOpen { [self] open in
            DispatchQueue.main.async { [self] in
                if open {
                    connect()
                } else if tries < 30 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                        waitForPort(tries: tries + 1)
                    }
                } else {
                    phase = .failed("OpenBot åpnet ikke feilsøkingsporten")
                }
            }
        }
    }

    private func connect(reopenTries: Int = 0) {
        phase = .connecting
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.debugPort)/json/list")!)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { [self] data, _, error in
            let webSocketURL = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
                .flatMap { targets in
                    targets.first { ($0["url"] as? String)?.hasPrefix(Self.targetURLPrefix) == true }
                }
                .flatMap { $0["webSocketDebuggerUrl"] as? String }
                .flatMap(URL.init(string:))
            DispatchQueue.main.async { [self] in
                guard let webSocketURL else {
                    // The port is open but the page is not: OpenBot runs
                    // without a window, and a plain reopen brings it back
                    // in the background — hidden, never on the desktop.
                    guard reopenTries < 2 else {
                        phase = .failed("Fant ikke OpenBot-siden")
                        return
                    }
                    let reopen = Process()
                    reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    reopen.arguments = ["-g", "-a", "OpenBot"]
                    try? reopen.run()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
                        if panel?.isVisible == true {
                            connect(reopenTries: reopenTries + 1)
                        }
                    }
                    return
                }
                attach(to: webSocketURL)
            }
        }.resume()
    }

    private func attach(to url: URL) {
        reconnectAttempts = 0
        // A card that closed and opened again leaves the old stream socket
        // behind; cancel it or the page paints into two connections.
        socket?.cancel(with: .goingAway, reason: nil)
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive()
        // A window the card previously tucked away has to come back for
        // the stream: a hidden renderer freezes, and unhiding resumes it.
        if let app = openBotApp, app.isHidden {
            app.unhide()
        }
        send("Page.enable") { [weak self] _ in
            self?.suppressOpenBotIsland()
            // The page renders at the card's size, whatever window it lives
            // in; the first frames may arrive one override late.
            self?.syncViewport()
            self?.startScreencast()
        }
    }

    private func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pending.forEach { $0.value(.failure(URLError(.cancelled))) }
        pending = [:]
        phase = .idle
    }

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handle(text)
                    }
                @unknown default:
                    break
                }
                self.receive()
            case .failure:
                DispatchQueue.main.async {
                    if self.phase != .idle, self.panel?.isVisible == true {
                        self.reconnectAttempts += 1
                        if self.reconnectAttempts > 3 {
                            self.phase = .failed("Koblingen til OpenBot falt")
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if self.panel?.isVisible == true { self.begin(initial: false) }
                        }
                    }
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        if let id = message["id"] as? Int, let completion = pending.removeValue(forKey: id) {
            if let error = message["error"] as? [String: Any],
               let description = error["message"] as? String {
                completion(.failure(OpenBotError(description)))
            } else {
                completion(.success(message["result"] as? [String: Any] ?? [:]))
            }
            return
        }
        guard let method = message["method"] as? String else { return }
        switch method {
        case "Page.screencastFrame":
            guard let params = message["params"] as? [String: Any],
                  let base64 = params["data"] as? String,
                  let metadata = params["metadata"] as? [String: Any],
                  let sessionID = params["sessionId"] as? Int else { return }
            send("Page.screencastFrameAck", params: ["sessionId": sessionID])
            let width = metadata["deviceWidth"] as? Double ?? 0
            let height = metadata["deviceHeight"] as? Double ?? 0
            queue.async { [self] in
                guard let data = Data(base64Encoded: base64),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
                DispatchQueue.main.async { [self] in
                    surface?.displayFrame(image,
                                          viewportWidth: overrideWidth,
                                          viewportHeight: overrideHeight)
                    if phase != .streaming { phase = .streaming }
                }
            }
        default:
            break
        }
    }

    private func send(_ method: String,
                      params: [String: Any] = [:],
                      completion: ((Result<[String: Any], Error>) -> Void)? = nil) {
        guard let socket else {
            completion?(.failure(OpenBotError("Ingen tilkobling")))
            return
        }
        let id = nextID
        nextID += 1
        if let completion {
            pending[id] = completion
        }
        var message: [String: Any] = ["id": id, "method": method]
        if !params.isEmpty {
            message["params"] = params
        }
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    // MARK: - Page setup

    /// The card's live page area, reported by the surface whenever it lays
    /// out; the mirrored page is forced to this size, so the stream always
    /// fits the card, whatever the real window's size is.
    func setViewport(width: Double, height: Double) {
        guard width > 0, height > 0,
              width != overrideWidth || height != overrideHeight else { return }
        overrideWidth = width
        overrideHeight = height
        viewportSyncPending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncViewport() }
        viewportSyncPending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func syncViewport() {
        send("Emulation.setDeviceMetricsOverride",
             params: ["width": Int(overrideWidth),
                      "height": Int(overrideHeight),
                      "deviceScaleFactor": Double(panel?.backingScaleFactor ?? 2),
                      "mobile": false])
    }

    /// OpenBot draws its own dynamic island at the notch, exactly where
    /// Vorssaint's island lives; turn the app's off so the two never stack.
    private func suppressOpenBotIsland() {
        let script = """
        (async () => {
          try {
            const current = await window.openbot.dynamicIsland.getPreference();
            if (current && current.enabled !== false) {
              await window.openbot.dynamicIsland.setPreference({...current, enabled: false});
            }
          } catch (e) { /* en fremtidig OpenBot uten øy overlates til seg selv */ }
          return true;
        })()
        """
        send("Runtime.evaluate",
             params: ["expression": script, "awaitPromise": true, "returnByValue": true]) { _ in }
    }

    private func startScreencast() {
        send("Page.startScreencast",
             params: ["format": "png", "maxWidth": 2600, "maxHeight": 1800, "everyNthFrame": 1])
    }

    // MARK: - Input

    private static func cdpModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var value = 0
        if flags.contains(.option) { value |= 1 }
        if flags.contains(.control) { value |= 2 }
        if flags.contains(.command) { value |= 4 }
        if flags.contains(.shift) { value |= 8 }
        return value
    }

    func sendMouseEvent(_ type: String, x: Double, y: Double,
                        button: String = "left", clickCount: Int = 0,
                        deltaX: Double = 0, deltaY: Double = 0) {
        var params: [String: Any] = ["type": type, "x": x, "y": y,
                                     "button": button, "pointerType": "mouse"]
        if clickCount > 0 { params["clickCount"] = clickCount }
        if type == "mouseWheel" {
            params["deltaX"] = deltaX
            params["deltaY"] = deltaY
        }
        params["modifiers"] = Self.cdpModifiers(NSEvent.modifierFlags)
        send("Input.dispatchMouseEvent", params: params)
    }

    func sendKeyEvent(_ type: String, key: String, code: String, keyCode: Int, text: String? = nil) {
        var params: [String: Any] = ["type": type, "key": key, "code": code,
                                     "windowsVirtualKeyCode": keyCode,
                                     "nativeVirtualKeyCode": keyCode]
        if let text { params["text"] = text }
        params["modifiers"] = Self.cdpModifiers(NSEvent.modifierFlags)
        send("Input.dispatchKeyEvent", params: params)
    }

    func insertText(_ text: String) {
        send("Input.insertText", params: ["text": text])
    }

    // MARK: - Outside clicks

    /// The card steps aside on a click anywhere outside it, unless the pin
    /// holds it up — the pad behaviour every other Vorssaint card follows.
    private func installMonitors(for panel: NSPanel) {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible, !self.isPinned else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    // MARK: - Helpers

    private func wait(for condition: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private struct OpenBotError: LocalizedError {
        let description: String
        init(_ description: String) { self.description = description }
        var errorDescription: String? { description }
    }
}

/// A borderless panel that still takes the keyboard, like the scratchpad's.
final class OpenBotMirrorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
