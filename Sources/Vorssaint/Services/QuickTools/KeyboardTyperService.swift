// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A floating pad whose text goes out as key presses instead of a paste, for
/// remote desktops and other places that block the clipboard. The pad never
/// activates the app, so the window behind it keeps its place: Send hides the
/// pad and types into that window. The text lives in memory only, since it is
/// often a password.
final class KeyboardTyperService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = KeyboardTyperService()

    @Published var text = ""
    @Published private(set) var isTyping = false
    /// Read from disk the first time the side panel is shown.
    @Published private(set) var snippets: [KeyboardTyperSnippet] = []
    private var snippetsLoaded = false
    /// False after a read that failed: writing then would replace a file
    /// that may still hold every snippet with the few in memory.
    private var snippetsCanSave = false
    static let snippetsWidth: CGFloat = 190
    /// Wide enough for the footer's row in every language, with both send
    /// buttons whole.
    static let baseMinimumWidth: CGFloat = 380

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var textView: NSTextView?
    private var run: TypingRun?
    /// The destination layout of the run under way, nil for the system's own.
    private var runLayoutID: String?
    /// The Mac's own input source while a run types with the destination's,
    /// put back when the run ends.
    private var inputSourceToRestore: String?
    private var stopMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.vorssaint.keyboard-typer", qos: .userInitiated)

    private var strings: KeyboardTyperFeatureStrings { FeatureStrings.keyboardTyper(L10n.shared.language) }

    /// Read from TIS once, the first time Settings or the pad needs a name.
    private(set) lazy var layouts = KeyboardTyperSupport.installedLayouts()

    func layoutName(_ id: String) -> String {
        layouts.first { $0.id == id }?.name ?? id
    }

    func syncWithPreferences() {
        guard !AppFeature.keyboardTyper.isAvailable else { return }
        run?.cancel()
        hide()
        // Uninstalled in the hub: nothing stays resident.
        panel = nil
        text = ""
        snippets = []
        snippetsLoaded = false
    }

    func show() {
        guard AppFeature.keyboardTyper.isAvailable, !isTyping else { return }
        // With the island's page on, the typer opens there instead.
        if NotchService.shared.showKeyboardTyper() {
            hide()
            return
        }
        let panel = ensurePanel()
        installKeyMonitor(for: panel)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, let textView = self.textView, textView.window === panel else { return }
            panel.makeFirstResponder(textView)
        }
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
    }

    func registerTextView(_ view: NSTextView) {
        textView = view
    }

    // MARK: - Typing

    /// `afterCountdown` waits the seconds set in Settings before typing, then
    /// types into whatever app is in front by then: some apps lose focus when
    /// the typer goes away, and the wait leaves time to click back into them.
    func send(afterCountdown: Bool = false) {
        guard !isTyping, !text.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            QuickToolHUD.show(icon: "lock", message: strings.needsAccessibility)
            Permissions.shared.requestAccessibility()
            return
        }
        let target = Self.currentTarget()
        guard afterCountdown || target != nil else {
            NSSound.beep()
            return
        }
        // The keys are found on the destination's layout, since the remote
        // side reads each key through its own. Built at Send, so a layout
        // switched while the pad was open is the one typed with.
        let defaults = UserDefaults.standard
        let destination = KeyboardTyperSupport.destinationLayoutID(
            selected: defaults.string(forKey: DefaultsKey.keyboardTyperLayout),
            favorites: KeyboardTyperSupport.favorites(
                from: defaults.string(forKey: DefaultsKey.keyboardTyperFavoriteLayouts)))
        let map = (destination.flatMap(KeyboardTyperSupport.layoutData(id:)) ?? Self.currentLayoutData()).map {
            KeyboardTyperSupport.keyMap(layoutData: $0, keyboardType: UInt32(LMGetKbdType()))
        } ?? [:]
        let method = KeyboardTyperMethod.sanitized(defaults.string(forKey: DefaultsKey.keyboardTyperMethod))
        let strokes = KeyboardTyperSupport.strokes(for: text, map: map, method: method)
        let missing = KeyboardTyperSupport.missingCharacters(in: strokes)
        guard method == .keyPositions || missing.isEmpty else {
            QuickToolHUD.show(icon: "exclamationmark.triangle",
                              message: String(format: strings.missingCharactersFormat, missing))
            return
        }
        let delay = KeyboardTyperSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.keyboardTyperDelayMs))

        hide()
        // From the island's page: folding it hands the keyboard back to the app behind.
        if NotchService.shared.expanded, NotchService.shared.selected == .keyboardTyper {
            NotchService.shared.collapse()
        }
        let run = TypingRun()
        self.run = run
        // Only a destination that reads characters needs the Mac on its layout.
        runLayoutID = method == .characters ? destination : nil
        isTyping = true
        installEscapeMonitor(run: run)
        if afterCountdown {
            let seconds = KeyboardTyperSupport.sanitizedCountdown(
                defaults.integer(forKey: DefaultsKey.keyboardTyperCountdownSeconds))
            countDown(from: seconds, run: run, strokes: strokes, delay: delay)
            return
        }
        guard let target else { return }
        if !target.isActive { target.activate() }
        type(strokes, delay: delay, into: target, run: run, after: KeyboardTyperSupport.startDelay)
    }

    /// The app the keys go to: the one in front, or, while the menu bar panel
    /// or Settings leave this app in front, the one whose window sits right
    /// behind ours. Nil when there is none, since the keys would then land in
    /// this app.
    private static func currentTarget() -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        let target = front?.processIdentifier == ownPID
            ? KeyboardTyperSupport.appBehind(windows: WindowServerSupport.onScreenWindowInfo(), ownPID: ownPID)
                .flatMap(NSRunningApplication.init(processIdentifier:))
            : front
        return target?.isTerminated == false ? target : nil
    }

    /// One HUD tick a second. Clicks are how the person picks the window
    /// meanwhile, so only Esc stops the wait.
    private func countDown(from seconds: Int, run: TypingRun, strokes: [KeyboardTyperStroke], delay: Int) {
        guard !run.isCancelled else { return finish(run) }
        guard seconds > 0 else {
            guard let target = Self.currentTarget() else {
                run.cancel()
                return finish(run)
            }
            // Not yet in front only when this app still is: it hands over first.
            guard target.isActive else {
                target.activate()
                return type(strokes, delay: delay, into: target, run: run, after: KeyboardTyperSupport.startDelay)
            }
            return type(strokes, delay: delay, into: target, run: run, after: 0)
        }
        QuickToolHUD.showCountdown(seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.countDown(from: seconds - 1, run: run, strokes: strokes, delay: delay)
        }
    }

    private func type(_ strokes: [KeyboardTyperStroke], delay: Int, into target: NSRunningApplication,
                      run: TypingRun, after wait: TimeInterval) {
        installTargetMonitors(run: run, targetPID: target.processIdentifier)
        // Browsers and some remote clients read each key through the Mac's own
        // layout (a web console sends the character, not the key), so the Mac
        // types with the destination's for the length of the run. Switched
        // here rather than at Send: a click into a window during the
        // countdown can bring that window's own input source back.
        let switched = runLayoutID.map(switchInputSource(to:)) ?? false
        queue.asyncAfter(deadline: .now() + max(wait, switched ? 0.2 : 0)) { [weak self] in
            let source = CGEventSource(stateID: .hidSystemState)
            for stroke in strokes {
                guard !run.isCancelled else { break }
                Self.post(stroke, source: source)
                if delay > 0 { usleep(useconds_t(delay * 1000)) }
            }
            DispatchQueue.main.async { self?.finish(run) }
        }
    }

    /// Quitting mid-run: `finish` would never come, so the run stops and the
    /// Mac gets its own layout back now.
    func stopBeforeTermination() {
        run?.cancel()
        if let inputSourceToRestore {
            _ = InputSourceSelection.select(sourceID: inputSourceToRestore)
            self.inputSourceToRestore = nil
        }
    }

    private func finish(_ finished: TypingRun) {
        guard run === finished else { return }
        run = nil
        runLayoutID = nil
        isTyping = false
        if let inputSourceToRestore {
            _ = InputSourceSelection.select(sourceID: inputSourceToRestore)
            self.inputSourceToRestore = nil
        }
        stopMonitors.forEach(NSEvent.removeMonitor)
        stopMonitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if finished.isCancelled {
            QuickToolHUD.show(icon: "stop.circle", message: strings.stopped)
        }
    }

    /// Esc, a click, or another app coming forward stops the run, so keys
    /// never land somewhere the user did not aim them. Only installed for the
    /// length of a run, and the run never posts Esc or clicks itself.
    /// Esc reaches this app instead while it stays in front, as after the
    /// menu bar panel, so both sides listen.
    private func installEscapeMonitor(run: TypingRun) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == UInt16(kVK_Escape) { run.cancel() }
        }) {
            stopMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            run.cancel()
            return nil
        }) {
            stopMonitors.append(monitor)
        }
    }

    private func installTargetMonitors(run: TypingRun, targetPID: pid_t) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                           handler: { _ in run.cancel() }) {
            stopMonitors.append(monitor)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != targetPID { run.cancel() }
        }
    }

    /// Modifiers go down and up as keys of their own: remote desktop clients
    /// read Shift and Option from those, not from the flags on the letter.
    private static func post(_ stroke: KeyboardTyperStroke, source: CGEventSource?) {
        func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        switch stroke {
        case .key(let key):
            var modifiers: [(CGKeyCode, CGEventFlags)] = []
            if key.shift { modifiers.append((CGKeyCode(kVK_Shift), .maskShift)) }
            if key.option { modifiers.append((CGKeyCode(kVK_Option), .maskAlternate)) }
            var held: CGEventFlags = []
            for (code, flag) in modifiers {
                held.insert(flag)
                postKey(code, down: true, flags: held)
            }
            postKey(key.code, down: true, flags: held)
            postKey(key.code, down: false, flags: held)
            for (code, flag) in modifiers.reversed() {
                held.remove(flag)
                postKey(code, down: false, flags: held)
            }
        // Right Option is AltGr to a web console and to Windows over remote
        // desktop; the left one is plain Alt there. The event names the
        // character, so the host never has to guess it from a Mac Option layer.
        case .altGraph(let code, let units):
            // 0x40 is NX_DEVICERALTKEYMASK: the Option held is the right one.
            let rightAlt = CGEventFlags.maskAlternate.union(CGEventFlags(rawValue: 0x40))
            postKey(CGKeyCode(kVK_RightOption), down: true, flags: rightAlt)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
                event.flags = rightAlt
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
            postKey(CGKeyCode(kVK_RightOption), down: false, flags: [])
        case .unicode(let units):
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Selects the layout, turning it on in the Input menu first if needed
    /// (it stays listed there afterwards), and remembers the one to restore.
    /// False when the Mac already types with it or refuses the switch.
    private func switchInputSource(to id: String) -> Bool {
        let current = InputSourceSelection.currentSourceID()
        guard current != id else { return false }
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
        else { return false }
        if !InputSourceSelection.inputSourceBool(source, property: kTISPropertyInputSourceIsEnabled) {
            TISEnableInputSource(source)
        }
        guard TISSelectInputSource(source) == noErr else { return false }
        inputSourceToRestore = current
        return true
    }

    /// Same source as `GlobalShortcut`'s key labels: under an input method,
    /// the ASCII capable layout beneath it is the keyboard the keys belong to.
    private static func currentLayoutData() -> Data? {
        let inputMethodIsActive: Bool = {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
            else { return false }
            return Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() as String
                != (kTISTypeKeyboardLayout as String)
        }()
        let source = inputMethodIsActive
            ? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
            : TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let source,
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the pad needs it for typing.
    private final class KeyableTyperPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableTyperPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                                      styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                      backing: .buffered,
                                      defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: Self.minimumWidth, height: 220)
        panel.minSize = NSSize(width: Self.baseMinimumWidth, height: 220)
        panel.delegate = self
        let host = NSHostingController(rootView: KeyboardTyperView())
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 40 + Self.minimumWidth, height: 260))
        center(panel)
        self.panel = panel
        return panel
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(Self.minimumWidth, frameSize.width), height: max(220, frameSize.height))
    }

    private static var minimumWidth: CGFloat {
        baseMinimumWidth + (UserDefaults.standard.bool(forKey: DefaultsKey.keyboardTyperSnippetsShown) ? snippetsWidth : 0)
    }

    // MARK: - Snippets

    private static var snippetsURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("KeyboardTyperSnippets.json")
    }

    func loadSnippetsIfNeeded() {
        guard !snippetsLoaded else { return }
        snippetsLoaded = true
        guard let url = Self.snippetsURL else { return }
        do {
            snippets = try JSONDecoder().decode([KeyboardTyperSnippet].self, from: Data(contentsOf: url))
            snippetsCanSave = true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            snippetsCanSave = true
        } catch {
            // The file stays as it is; saving reports the failure instead.
        }
    }

    func saveSnippet(name: String) {
        guard !text.isEmpty else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        write(snippets + [KeyboardTyperSnippet(name: name, text: text)])
    }

    func deleteSnippet(_ id: UUID) {
        write(snippets.filter { $0.id != id })
    }

    func useSnippet(_ snippet: KeyboardTyperSnippet) {
        text = snippet.text
    }

    /// Owner-only and atomic, as every file in the app's container.
    private func write(_ next: [KeyboardTyperSnippet]) {
        guard snippetsCanSave, let url = Self.snippetsURL,
              let data = try? JSONEncoder().encode(next),
              PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()),
              PrivateFileStore.write(data, to: url) else {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.snippetsSaveFailed)
            return
        }
        snippets = next
    }

    /// The floating pad grows to the right for the panel and gives the room
    /// back when it closes, so the text keeps its width.
    func toggleSnippets() {
        let shown = !UserDefaults.standard.bool(forKey: DefaultsKey.keyboardTyperSnippetsShown)
        UserDefaults.standard.set(shown, forKey: DefaultsKey.keyboardTyperSnippetsShown)
        if shown { loadSnippetsIfNeeded() }
        guard let panel else { return }
        panel.contentMinSize.width = Self.minimumWidth
        var frame = panel.frame
        frame.size.width = max(Self.minimumWidth, frame.width + (shown ? Self.snippetsWidth : -Self.snippetsWidth))
        panel.setFrame(frame, display: true, animate: false)
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2,
                                     y: screen.minY + (screen.height - size.height) * 0.58))
    }

    private func installKeyMonitor(for panel: NSPanel) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel,
                  event.keyCode == UInt16(kVK_Escape) else { return event }
            // Mid-composition Esc belongs to the input method, not the pad.
            if let textView = self.textView, textView.hasMarkedText() { return event }
            self.hide()
            return nil
        }
    }
}

/// One run's stop switch, flipped on the main thread and read by the typing queue.
private final class TypingRun {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
