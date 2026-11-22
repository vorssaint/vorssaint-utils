// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine's DragMonitor, (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AppKit

/// Watches for a file drag that starts with the Convert key held, or gets it
/// pressed part way. The island opens on the formats while it lasts and closes
/// if the drag ends elsewhere. Mouse events are observed globally, which needs
/// no permission; only the modifier keys' state is polled.
final class ConvertDragMonitor {
    static let shared = ConvertDragMonitor()

    /// The drag began with the key down, or it was pressed during the drag.
    var onKeyDown: (([URL], ConvertService.Mode) -> Void)?
    /// A different key was pressed during the drag.
    var onModeChange: ((ConvertService.Mode) -> Void)?
    /// The key was let go while the drag went on.
    var onKeyUp: (() -> Void)?
    /// The mouse button came up.
    var onEnd: (() -> Void)?

    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var activity: NSObjectProtocol?
    private var pressChangeCount = 0
    private var lastReadChange = 0
    private var activeURLs: [URL] = []
    private var dragInFlight = false
    private var presenting = false
    private var mouseDown = false
    private var pressOrigin = NSPoint.zero
    private var pressTime = Date.distantPast
    private var pressInFinder = false

    private static let idleInterval = 1.0 / 20.0
    private static let dragInterval = 1.0 / 60.0
    private static let fallbackDragDistance: CGFloat = 24
    private static let fallbackDelay: TimeInterval = 0.3

    private init() {}

    /// Starts or stops with the settings. Safe to call again.
    func sync() {
        let defaults = UserDefaults.standard
        let anyKey = defaults.bool(forKey: DefaultsKey.convertKeyConvert) || defaults.bool(forKey: DefaultsKey.convertKeyTools)
            || defaults.bool(forKey: DefaultsKey.convertKeyActions)
        let wanted = defaults.bool(forKey: DefaultsKey.convertEnabled) && anyKey
            && AppFeature.shelf.isAvailable && AppFeature.notch.isAvailable
        wanted ? start() : stop()
    }

    private func start() {
        guard monitors.isEmpty else { return }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.beginPressIfNeeded()
            self?.poll()
        }
        let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.beginPressIfNeeded() }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in self?.finishPress() }
        monitors = [dragged, down, up].compactMap { $0 }
        schedulePoll(interval: Self.idleInterval)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        if presenting { presenting = false; presentedMode = nil; onEnd?() }
        mouseDown = false
        endActivity()
    }

    private func schedulePoll(interval: TimeInterval) {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private var buttonPressed: Bool { NSEvent.pressedMouseButtons & 1 == 1 }
    /// Control: file actions. Command, or Option with Shift: tools. Shift alone: convert.
    /// A key the person switched off in settings does not count.
    private var heldMode: ConvertService.Mode? {
        let flags = NSEvent.modifierFlags
        let defaults = UserDefaults.standard
        if flags.contains(.control), defaults.bool(forKey: DefaultsKey.convertKeyActions) { return .actions }
        if flags.contains(.command) || (flags.contains(.option) && flags.contains(.shift)),
           defaults.bool(forKey: DefaultsKey.convertKeyTools) { return .tools }
        if flags.contains(.shift), defaults.bool(forKey: DefaultsKey.convertKeyConvert) { return .convert }
        return nil
    }
    private var presentedMode: ConvertService.Mode?
    private var keyHeld: Bool { heldMode != nil }

    private func beginPressIfNeeded() {
        guard !mouseDown else { return }
        mouseDown = true
        dragInFlight = false
        activeURLs = []
        pressOrigin = NSEvent.mouseLocation
        pressTime = Date()
        pressInFinder = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        pressChangeCount = NSPasteboard(name: .drag).changeCount
        lastReadChange = pressChangeCount
        DiagnosticLog.log("convert-drag: press in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?") changeCount=\(pressChangeCount)")
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                         reason: "Tracking a file drag")
        schedulePoll(interval: Self.dragInterval)
    }

    private func poll() {
        guard buttonPressed else {
            if mouseDown { finishPress() }
            return
        }
        beginPressIfNeeded()
        refreshDragPasteboard()
        // Finder can start a drag before it fills the drag pasteboard, so movement stands in for it.
        if !dragInFlight, pressInFinder, keyHeld, Date().timeIntervalSince(pressTime) >= Self.fallbackDelay,
           hypot(NSEvent.mouseLocation.x - pressOrigin.x, NSEvent.mouseLocation.y - pressOrigin.y) >= Self.fallbackDragDistance {
            dragInFlight = true
        }
        guard dragInFlight else { return }
        let mode = heldMode
        if mode != nil || presenting { DiagnosticLog.log("convert-drag: mode=\(String(describing: mode)) presenting=\(presenting) urls=\(activeURLs.count)") }
        if let mode, !presenting, !activeURLs.isEmpty {
            presenting = true
            presentedMode = mode
            onKeyDown?(activeURLs, mode)
        } else if let mode, presenting, mode != presentedMode {
            presentedMode = mode
            onModeChange?(mode)
        } else if mode == nil, presenting {
            presenting = false
            presentedMode = nil
            onKeyUp?()
        }
    }

    private func refreshDragPasteboard() {
        let pasteboard = NSPasteboard(name: .drag)
        let change = pasteboard.changeCount
        guard change != lastReadChange else { return }
        lastReadChange = change
        guard change > pressChangeCount else { return }
        activeURLs = Self.fileURLs(on: pasteboard)
        dragInFlight = !activeURLs.isEmpty || (pasteboard.types ?? []).contains(.fileURL)
        DiagnosticLog.log("convert-drag: pasteboard change=\(change) urls=\(activeURLs.count) inFlight=\(dragInFlight)")
    }

    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty {
            urls = (pasteboard.pasteboardItems ?? []).compactMap { item in item.string(forType: .fileURL).flatMap { URL(string: $0) } }
        }
        return urls.compactMap { url -> URL? in
            let resolved = (url as NSURL).filePathURL ?? url
            guard resolved.isFileURL else { return nil }
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            return isDirectory.boolValue ? nil : resolved.standardizedFileURL
        }
    }

    private func finishPress() {
        guard mouseDown else { return }
        mouseDown = false
        dragInFlight = false
        activeURLs = []
        endActivity()
        schedulePoll(interval: Self.idleInterval)
        if presenting {
            presenting = false
            onEnd?()
        }
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
