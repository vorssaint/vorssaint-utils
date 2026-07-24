// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The radial menu: a wheel of user-configured actions summoned by a global
/// shortcut. Its configurable activation mode can keep the wheel open after
/// a press, run a pointed action on release, or preserve both gestures.
/// At rest the feature holds only the Carbon hotkey and a pre-warmed, hidden
/// panel (so the wheel appears instantly); every event monitor lives only
/// while a wheel is on screen, and switching the feature off frees it all.
final class RadialMenuService: ObservableObject {
    static let shared = RadialMenuService()

    /// Wheels from root to the currently shown submenu; the last entry is on
    /// screen. Empty means no session.
    @Published private(set) var stack: [[RadialMenuItem]] = []
    /// Names of the submenus that were descended into, for the hub's back hint.
    @Published private(set) var trail: [String] = []
    @Published private(set) var highlightedIndex: Int?
    /// True while a hold-capable session still owns its shortcut or side
    /// button; release behavior is determined by `sessionActivationMode`.
    @Published private(set) var holdPhase = false
    /// True when macOS refused the shortcut (taken by another app).
    @Published private(set) var registrationFailed = false
    /// True while the app is actually able to watch for the chosen mouse
    /// button. Off means the button can never open the wheel, whatever the
    /// setting says, and the settings screen can say so instead of leaving
    /// the user guessing.
    @Published private(set) var isWatchingMouseButton = false
    /// The last extra mouse button that arrived while the settings screen was
    /// asking. Nil means nothing has arrived yet.
    @Published private(set) var lastMouseButtonSeen: Int?
    /// Set only while the settings screen is on screen.
    private var isReportingMouseButtons = false

    /// Starts and stops reporting which extra mouse buttons arrive. Costs
    /// nothing: it only decides whether the tap that already exists writes
    /// down what it sees.
    func setReportingMouseButtons(_ reporting: Bool) {
        isReportingMouseButtons = reporting
        if !reporting, lastMouseButtonSeen != nil { lastMouseButtonSeen = nil }
        // A tap the system disabled behind our back reads exactly like a
        // button that never arrives, so the state is refreshed on the way in.
        if reporting { syncMouseTap() }
    }

    /// Drives the wheel's appear animation: false in the pre-warmed idle
    /// render, true the moment a session fills the stack.
    var visible: Bool { sessionActive }

    private let hotkey = QuickToolHotkey(id: 17)
    private var panel: NSPanel?
    private var wheelCenter: CGPoint = .zero
    private var openPointerLocation: CGPoint = .zero
    private var pointerActivated = false
    private var sessionShortcut: GlobalShortcut?
    private var sessionActivationMode = RadialMenuActivationMode.pressOrHold
    /// Set while a session was summoned by the side button and it is still
    /// down; releasing it runs the pointed slice, mirroring the chord.
    private var holdButton: Int64?
    private var mouseTrigger = RadialMenuMouseTrigger.off
    private var mouseTap: CFMachPort?
    private var mouseTapSource: CFRunLoopSource?
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var promptedForAccessibility = false

    private init() {
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
    }

    var sessionActive: Bool { !stack.isEmpty }

    private var currentItems: [RadialMenuItem] { stack.last ?? [] }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.radialMenu.isAvailable
            && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
        guard enabled else {
            suspend()
            registrationFailed = false
            return
        }
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.radialMenuShortcut,
                                            fallback: .radialMenuDefault)
        registrationFailed = !hotkey.sync(enabled: true, shortcut: shortcut)
        mouseTrigger = RadialMenuMouseTrigger.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuMouseButton))
        syncMouseTap()
        // First render of a hosting view costs real time; pay it now so the
        // wheel appears the instant the shortcut fires.
        ensurePanel().contentView?.layoutSubtreeIfNeeded()
    }

    func suspend() {
        hotkey.unregister()
        // The trigger ivar must die with the tap: the settings page's button
        // test calls syncMouseTap() on appear, and a stale trigger would let
        // it resurrect the tap — and the wheel — with the feature off.
        mouseTrigger = .off
        tearDownMouseTap()
        endSession()
        panel = nil
    }

    // MARK: - Side button trigger (a tap so the click never doubles as
    // back/forward in the app under the pointer; alive only while a button
    // is configured, torn down with the feature)

    private func syncMouseTap() {
        guard mouseTrigger.buttonNumber != nil else {
            tearDownMouseTap()
            return
        }
        // A tap the system disabled (Accessibility revoked and regranted)
        // never revives on its own; rebuild it instead of keeping the corpse.
        if let mouseTap, !CGEvent.tapIsEnabled(tap: mouseTap) {
            tearDownMouseTap()
        }
        guard mouseTap == nil, AXIsProcessTrusted() else { return }
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<RadialMenuService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleMouseTap(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        mouseTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        mouseTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        if !isWatchingMouseButton { isWatchingMouseButton = true }
    }

    private func tearDownMouseTap() {
        if let mouseTap {
            CGEvent.tapEnable(tap: mouseTap, enable: false)
            CFMachPortInvalidate(mouseTap)
        }
        if let mouseTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseTapSource, .commonModes)
        }
        mouseTap = nil
        mouseTapSource = nil
        if isWatchingMouseButton { isWatchingMouseButton = false }
    }

    private func handleMouseTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let pressed = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        // While the mouse button shortcuts capture row is listening, the
        // press belongs to it, even this wheel's own summoner: that capture
        // tap swallows the gesture and tells the user the button is taken.
        if MouseButtonShortcutService.isCaptureActive {
            return Unmanaged.passUnretained(event)
        }
        // While the settings screen is asking, every extra button that
        // arrives is reported, so the user can tell a button this app cannot
        // see from one that is simply set to something else. Nothing new
        // watches for it: the tap that is already required does the telling.
        if isReportingMouseButtons, type == .otherMouseDown {
            lastMouseButtonSeen = pressed
        }
        guard let button = mouseTrigger.buttonNumber, pressed == button
        else { return Unmanaged.passUnretained(event) }

        // The source lives on the main run loop, so this already runs on
        // main; acting synchronously keeps a quick click ordered (the down
        // opens the wheel before its own up arrives). The claimed button is
        // the wheel's alone: both halves of every click are consumed, so the
        // app under the pointer never sees half a gesture (the Settings
        // caption promises exactly that).
        if type == .otherMouseDown {
            if !sessionActive {
                beginSession(hold: false, heldButton: button)
            } else if !holdPhase {
                endSession()
            }
            // A press during a held chord session means nothing and is
            // swallowed with the rest.
        } else if holdPhase, holdButton == button {
            endHoldPhase()
        }
        return nil
    }

    // MARK: - Session

    private func hotkeyPressed() {
        // Carbon hot keys never autorepeat, so a press during a session is
        // always the user asking to close, even with the modifiers still
        // held from the summoning chord.
        if sessionActive {
            endSession()
            return
        }
        beginSession(hold: true)
    }

    /// The Settings page's try-it button: a sticky session with the saved
    /// placement, exactly like a quick press of the shortcut.
    func presentPreview() {
        endSession()
        beginSession(hold: false)
    }

    private func beginSession(hold: Bool, heldButton: Int64? = nil) {
        let defaults = UserDefaults.standard
        let items = availableItems(RadialMenuSupport.decode(defaults.data(forKey: DefaultsKey.radialMenuItems)))
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }

        let shortcut = GlobalShortcut.saved(for: DefaultsKey.radialMenuShortcut,
                                            fallback: .radialMenuDefault)
        let activationMode = RadialMenuActivationMode.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuActivationMode))
        let startsHeld = activationMode.startsHeld(
            requestedHold: hold,
            hasHeldButton: heldButton != nil,
            shortcutHasModifiers: !shortcut.modifiers.isEmpty)
        // Only held sessions need to retain their summoner. Press mode ignores
        // its release and stays up until selection, a second press or an
        // outside click.
        sessionActivationMode = activationMode
        sessionShortcut = startsHeld && heldButton == nil ? shortcut : nil
        holdButton = startsHeld ? heldButton : nil
        holdPhase = startsHeld
        stack = [items]
        trail = []
        highlightedIndex = nil
        pointerActivated = false
        openPointerLocation = NSEvent.mouseLocation

        let atPointer = defaults.bool(forKey: DefaultsKey.radialMenuAtPointer)
        let visibleFrame = NSScreen.pointerVisibleFrame
        let wanted = atPointer ? NSEvent.mouseLocation
                               : CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        wheelCenter = clampedCenter(wanted, in: visibleFrame)

        let panel = ensurePanel()
        let half = RadialMenuLayout.panelSize / 2
        panel.setFrame(NSRect(x: wheelCenter.x - half, y: wheelCenter.y - half,
                              width: RadialMenuLayout.panelSize, height: RadialMenuLayout.panelSize),
                       display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors(for: panel)
        refreshHighlight()
    }

    private func endSession() {
        removeMonitors()
        panel?.orderOut(nil)
        stack = []
        trail = []
        highlightedIndex = nil
        holdPhase = false
        holdButton = nil
        sessionShortcut = nil
        sessionActivationMode = .pressOrHold
        // A try-it session can run with the feature off; nothing may stay
        // resident for it once the wheel closes.
        if !AppFeature.radialMenu.isAvailable
            || !UserDefaults.standard.bool(forKey: DefaultsKey.radialMenuEnabled) {
            panel = nil
        }
    }

    /// Wheels only show what can actually run today: tools whose feature was
    /// uninstalled in the hub disappear instead of leaving a dead slice.
    private func availableItems(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
        items.compactMap { item in
            var item = item
            if let tool = item.tool, !tool.isRunnable() { return nil }
            if item.kind == .windowLayout, !AppFeature.windowLayout.isAvailable { return nil }
            if item.kind == .submenu {
                item.children = availableItems(item.children)
                if item.children.isEmpty { return nil }
            }
            return item
        }
    }

    private func clampedCenter(_ wanted: CGPoint, in frame: NSRect) -> CGPoint {
        let half = RadialMenuLayout.panelSize / 2
        guard frame.width > RadialMenuLayout.panelSize,
              frame.height > RadialMenuLayout.panelSize else { return wanted }
        return CGPoint(x: min(max(wanted.x, frame.minX + half), frame.maxX - half),
                       y: min(max(wanted.y, frame.minY + half), frame.maxY - half))
    }

    // MARK: - Selection

    private func refreshHighlight() {
        let pointer = NSEvent.mouseLocation
        if !pointerActivated {
            let dx = pointer.x - openPointerLocation.x
            let dy = pointer.y - openPointerLocation.y
            // Until the pointer really travels, it owns nothing: a trackpad
            // tremor must not erase a highlight the arrow keys picked.
            guard (dx * dx + dy * dy).squareRoot() >= RadialMenuLayout.moveActivationDistance else {
                return
            }
            pointerActivated = true
        }
        let index = RadialMenuGeometry.highlightedIndex(dx: pointer.x - wheelCenter.x,
                                                        dyUp: pointer.y - wheelCenter.y,
                                                        deadZoneRadius: RadialMenuLayout.deadZoneRadius,
                                                        itemCount: currentItems.count)
        if index != highlightedIndex { highlightedIndex = index }
    }

    /// The wheel view's tap. Where the click lands decides: past the wheel's
    /// edge dismisses, the hub steps back, a highlighted slice runs, and the
    /// rest (a slice direction the pointer has not armed yet) does nothing.
    func activatePointer() {
        guard sessionActive else { return }
        let pointer = NSEvent.mouseLocation
        let dx = pointer.x - wheelCenter.x
        let dyUp = pointer.y - wheelCenter.y
        let distance = (dx * dx + dyUp * dyUp).squareRoot()
        if distance > RadialMenuLayout.wheelDiameter / 2 {
            endSession()
        } else if distance < RadialMenuLayout.deadZoneRadius {
            stepBack()
        } else if let index = highlightedIndex {
            select(index)
        }
    }

    func select(_ index: Int) {
        guard sessionActive, currentItems.indices.contains(index) else { return }
        let item = currentItems[index]
        if item.kind == .submenu {
            stack.append(item.children)
            trail.append(item.name)
            highlightedIndex = nil
            // A hold-release over a submenu lands here; browsing children is
            // a sticky affair by nature. Re-arming the pointer keeps a
            // double-click from running the child that happens to sit in the
            // parent slice's direction.
            enterStickyPhase()
            pointerActivated = false
            openPointerLocation = NSEvent.mouseLocation
            return
        }
        endSession()
        run(item)
    }

    /// Esc or a click on the hub: leave the submenu, then the wheel.
    func stepBack() {
        guard sessionActive else { return }
        if stack.count > 1 {
            stack.removeLast()
            trail.removeLast()
            highlightedIndex = nil
            refreshHighlight()
        } else {
            endSession()
        }
    }

    private func rotateHighlight(by delta: Int) {
        let count = currentItems.count
        guard count > 0 else { return }
        let current = highlightedIndex ?? (delta > 0 ? -1 : 0)
        highlightedIndex = ((current + delta) % count + count) % count
    }

    // MARK: - Monitors (session-scoped, removed the moment the wheel closes)

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            return self.handleKeyDown(event) ? nil : event
        }) { eventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
            return event
        }) { eventMonitors.append(monitor) }

        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.pointerMoved()
        }) { eventMonitors.append(monitor) }

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel, !Self.pointerInside(panel) {
                self.endSession()
            }
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber, !Self.pointerInside(panel) {
                self.endSession()
            }
        }) { eventMonitors.append(monitor) }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self.endSession()
        }
    }

    private func removeMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private static func pointerInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func pointerMoved() {
        guard sessionActive else { return }
        // A chord release can slip past the flags monitor when it lands
        // between the press and the monitor's install; the next pointer move
        // settles it. Button-held sessions end through the tap instead.
        if holdPhase, holdButton == nil { handleFlagsChanged(NSEvent.modifierFlags) }
        refreshHighlight()
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard sessionActive, holdPhase, let shortcut = sessionShortcut else { return }
        guard !shortcut.requiredModifiersHeld(in: flags) else { return }
        endHoldPhase()
    }

    /// Resolve the summoner release according to the mode captured when this
    /// session opened. Reading it once per session prevents a Settings change
    /// mid-gesture from producing a half-old, half-new interaction.
    private func endHoldPhase() {
        guard sessionActive, holdPhase else { return }
        switch sessionActivationMode.releaseAction(hasSelection: highlightedIndex != nil) {
        case .stayOpen:
            enterStickyPhase()
        case .dismiss:
            endSession()
        case .select:
            guard let index = highlightedIndex else { return }
            select(index)
        }
    }

    private func enterStickyPhase() {
        holdPhase = false
        holdButton = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            stepBack()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let index = highlightedIndex { select(index) }
            return true
        case kVK_LeftArrow, kVK_UpArrow:
            // In adaptive mode, reaching for the keyboard switches to sticky
            // browsing. Strict hold deliberately keeps the release-to-run
            // contract even when arrows move the highlight.
            if sessionActivationMode != .hold { enterStickyPhase() }
            rotateHighlight(by: -1)
            return true
        case kVK_RightArrow, kVK_DownArrow:
            if sessionActivationMode != .hold { enterStickyPhase() }
            rotateHighlight(by: 1)
            return true
        default:
            if let character = event.charactersIgnoringModifiers?.first,
               let digit = character.wholeNumberValue, (1...9).contains(digit),
               currentItems.indices.contains(digit - 1) {
                select(digit - 1)
                return true
            }
            return false
        }
    }

    // MARK: - Actions

    private func run(_ item: RadialMenuItem) {
        switch item.kind {
        case .app:
            let url = URL(fileURLWithPath: (item.payload as NSString).expandingTildeInPath)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { DispatchQueue.main.async { NSSound.beep() } }
            }
        case .file:
            let path = (item.payload as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .url:
            if let normalized = RadialMenuSupport.normalizedURL(item.payload),
               let url = URL(string: normalized) {
                NSWorkspace.shared.open(url)
            }
        case .shortcut:
            if let shortcut = GlobalShortcut(storageValue: item.payload) {
                postWhenModifiersReleased(attempt: 0) { Self.postShortcut(shortcut) }
            }
        case .media:
            if let key = item.mediaKey {
                postWhenModifiersReleased(attempt: 0) { Self.postMediaKey(key) }
            }
        case .tool:
            if let tool = item.tool { run(tool) }
        case .windowLayout:
            if let action = item.windowLayoutAction { run(action) }
        case .submenu:
            break
        }
    }

    private func run(_ tool: RadialMenuTool) {
        guard tool.isRunnable() else { return }
        // The same beat the quick panel gives screen-touching tools, so the
        // wheel is really gone before anything captures or presents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch tool {
            case .screenshot: ScreenshotService.shared.capture()
            case .colorPicker: ColorSamplerService.shared.pick()
            case .screenOCR: ScreenTextService.shared.capture()
            case .micMute: MicMuteService.shared.toggle()
            case .clipboardHistory: ClipboardHistoryService.shared.showHistoryWindow()
            case .quickLauncher: QuickLauncherService.shared.show()
            case .cameraPreview: CameraPreviewService.shared.show()
            case .scratchpad: ScratchpadService.shared.show()
            case .shelf: ShelfService.shared.summon()
            case .cleaningMode: CleaningModeManager.shared.activate()
            case .keepAwake: KeepAwakeManager.shared.toggle()
            }
        }
    }

    private func run(_ action: WindowLayoutAction) {
        guard AppFeature.windowLayout.isAvailable, ensureAccessibilityPermission() else { return }
        // Let the non-activating wheel disappear before resolving the window
        // that was active behind it, matching the delay used by visual tools.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if case .failure = WindowLayoutService.shared.apply(action) { NSSound.beep() }
        }
    }

    // MARK: - Accessibility-gated actions (asked once and in context)

    private func ensureAccessibilityPermission() -> Bool {
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return false
        }
        return true
    }

    /// Waits for the summoning chord to leave the keyboard before posting, or
    /// the synthetic key merges with the still-held modifiers (checked every
    /// 15 ms for up to ~1.5 s, with an extra beat once clean).
    private func postWhenModifiersReleased(attempt: Int, then post: @escaping () -> Void) {
        guard ensureAccessibilityPermission() else { return }
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: post)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.postWhenModifiersReleased(attempt: attempt + 1, then: post)
        }
    }

    private static func postShortcut(_ shortcut: GlobalShortcut) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false)
        else { return }
        keyDown.flags = shortcut.modifiers.cgFlags
        keyUp.flags = shortcut.modifiers.cgFlags
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Posts the aux-button pair the physical media keys produce, so whatever
    /// player owns the media keys reacts exactly as if F8 was pressed.
    private static func postMediaKey(_ key: RadialMenuMediaKey) {
        postAuxKey(key.auxKeyType, down: true)
        postAuxKey(key.auxKeyType, down: false)
    }

    private static func postAuxKey(_ type: Int32, down: Bool) {
        let stateFlags: NSEvent.ModifierFlags = down
            ? NSEvent.ModifierFlags(rawValue: 0xA00)
            : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = (Int(type) << 16) | ((down ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: stateFlags,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: 8,
                                             data1: data1,
                                             data2: -1)
        else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default, and the wheel wants it
    /// for Esc, arrows, digits and the hold-release detection.
    private final class KeyableWheelPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = RadialMenuLayout.panelSize
        let panel = KeyableWheelPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered,
                                      defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: RadialMenuView())
        self.panel = panel
        return panel
    }
}
