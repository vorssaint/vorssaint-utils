// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import UniformTypeIdentifiers

/// Turns the standard Back and Forward side buttons into the matching app
/// commands. File managers and browsers expose those commands as Command-[ and
/// Command-], or wherever the current keyboard puts them (see
/// `MouseNavigationKeys`); other apps keep working when they provide the same
/// menu command.
/// Apps that handle the side buttons themselves (some browsers, virtual
/// machines, remote screens) receive the untouched events instead, and an app
/// with neither command gets its click back. Nothing is installed
/// while the opt-in feature is off. Requires Accessibility for the modifying
/// event tap and menu action.
final class MouseNavigationService: ObservableObject {
    static let shared = MouseNavigationService()

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Buttons whose current press started over a pass-through app. The Up
    /// and Drag of a gesture must follow its Down: splitting the pair would
    /// leave the target app with an unmatched mouse event. Only touched from
    /// the tap callback, which runs on the main run loop.
    private var passThroughButtons: Set<Int64> = []
    /// Alive only while the tap is, like every other resource here.
    private var keyboardObserver: NSObjectProtocol?
    /// Registered web handlers that should keep their native side-button events.
    /// Resolved outside the tap callback so its hot path only reads memory.
    private var webURLHandlers: Set<String> = []
    private var webHandlerObservers: [NSObjectProtocol] = []
    private var webHandlerRefreshWork: DispatchWorkItem?
    private var webHandlerRefreshGeneration = 0

    private init() {
        // A filter tap owned by a switched-away login session stalls input in
        // the session on screen. Hand it back on resign and rebuild it from
        // preferences when this session becomes active again.
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.mouseNavigation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.mouseNavigationEnabled)
        if SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    private func start() {
        guard tap == nil else {
            isRunning = true
            return
        }
        webURLHandlers = Self.registeredWebURLHandlers()
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MouseNavigationService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            webURLHandlers.removeAll()
            isRunning = false
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        observeWebHandlerChanges()
        // Which keys carry Back and Forward depends on the keyboard in use.
        // The Go menu answers on every click; without it the answer is asked
        // for now and again on every keyboard change.
        MouseNavigationKeys.refresh()
        keyboardObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in MouseNavigationKeys.refresh() }
        isRunning = true
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        if let keyboardObserver {
            DistributedNotificationCenter.default().removeObserver(keyboardObserver)
        }
        keyboardObserver = nil
        webHandlerRefreshGeneration += 1
        webHandlerRefreshWork?.cancel()
        webHandlerRefreshWork = nil
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in webHandlerObservers { workspaceCenter.removeObserver(observer) }
        webHandlerObservers.removeAll()
        MouseNavigationKeys.reset()
        webURLHandlers.removeAll()
        tap = nil
        runLoopSource = nil
        passThroughButtons.removeAll()
        isRunning = false
    }

    private func observeWebHandlerChanges() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
        ]
        webHandlerObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication)?.processIdentifier
                guard MouseNavigationSupport.shouldRefreshWebHandlers(
                    isApplicationActivation: notification.name
                        == NSWorkspace.didActivateApplicationNotification,
                    activatedPID: activatedPID,
                    ownPID: ProcessInfo.processInfo.processIdentifier
                ) else { return }
                self?.scheduleWebHandlerRefresh()
            }
        }
    }

    private func scheduleWebHandlerRefresh() {
        webHandlerRefreshGeneration += 1
        let generation = webHandlerRefreshGeneration
        webHandlerRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.tap != nil,
                  self.webHandlerRefreshGeneration == generation else { return }
            self.webHandlerRefreshWork = nil
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let handlers = MouseNavigationService.registeredWebURLHandlers()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.tap != nil,
                          self.webHandlerRefreshGeneration == generation else { return }
                    self.webURLHandlers = handlers
                }
            }
        }
        webHandlerRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let wanted = AppFeature.mouseNavigation.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.mouseNavigationEnabled)
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: wanted,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRearm, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                // Invalidating the port from its own callback stack is unsafe;
                // finish this callback fail-open, then release the tap.
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged,
              let direction = MouseNavigationSupport.direction(forButtonNumber: buttonNumber) else {
            return Unmanaged.passUnretained(event)
        }

        // A side button claimed as the radial menu's summoner, or carrying a
        // mouse button shortcut, belongs to that feature. This tap runs at
        // the HID level, before those session taps, so the whole gesture
        // passes through untouched for the owner to take downstream; the
        // other side button keeps navigating. While the shortcut capture row
        // is listening, every press belongs to it, including a button with no
        // mapping yet, or the capture could never see the button it is asked
        // to watch for. Both claims are asked again on every Drag of a held
        // side button, so both have to stay cheap.
        if RadialMenuSupport.claimsMouseButton(buttonNumber)
            || MouseButtonShortcutSupport.claimsButton(buttonNumber)
            || MouseButtonShortcutService.isCaptureActive {
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            // Apps that consume the side buttons themselves keep the raw
            // event; replacing it would drop navigation the user already had,
            // and none of them has a menu command the AX path could press.
            // The same goes for an app the user put on the exception list.
            // Checked only on Down (never per Drag), and both answers come
            // from cached state, so the tap callback stays cheap.
            // Our Settings window handles raw side buttons without Accessibility.
            // Do not replace them with an AX command (or swallow them) here.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
                || MouseNavigationSupport.shouldPassThrough(
                bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                webURLHandlers: webURLHandlers)
                || MouseAppExceptions.shared.excludesActionTarget(.navigation, at: event.location) {
                passThroughButtons.insert(buttonNumber)
                return Unmanaged.passUnretained(event)
            }
            passThroughButtons.remove(buttonNumber)
            let pressedFor = NSWorkspace.shared.frontmostApplication?.processIdentifier
            // The press itself goes to the window under the pointer, which can
            // belong to an app behind the one in front. One window server
            // query reads it here, before another window can take its place;
            // its owner is only looked up if the click goes back.
            let pressedOn = FocusFollowsMouseService.receivingWindow(at: event.location)
            let press = event.copy().map {
                SwallowedPress(down: $0, appPID: pressedFor, windowID: pressedOn)
            }
            // Leave the event-tap callback immediately; AX menu traversal can
            // take a few milliseconds and must never let the tap time out.
            DispatchQueue.main.async { [weak self] in
                self?.perform(direction, press: press)
            }
            return nil
        }

        if passThroughButtons.contains(buttonNumber) {
            if type == .otherMouseUp { passThroughButtons.remove(buttonNumber) }
            return Unmanaged.passUnretained(event)
        }
        // Swallow the full side-button gesture. Letting its Up or Drag through
        // after replacing the Down leaves apps with an unmatched mouse event.
        return nil
    }

    private static func registeredWebURLHandlers() -> Set<String> {
        guard let url = URL(string: "https://example.invalid") else { return [] }
        let urlHandlers = Set(NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap {
            Bundle(url: $0)?.bundleIdentifier
        })
        let documentHandlers = Set(NSWorkspace.shared.urlsForApplications(toOpen: UTType.html).compactMap {
            Bundle(url: $0)?.bundleIdentifier
        })
        return MouseNavigationSupport.nativeWebHandlers(
            urlHandlers: urlHandlers, documentHandlers: documentHandlers)
    }

    private enum MenuPressOutcome {
        case pressed
        case pressFailed(MouseNavigationKeys.Shortcut)
        case missed(MouseNavigationMenuMiss)
    }

    /// A side-button Down this tap swallowed, the app in front when the
    /// button went down, the one the click is for, and the window the press
    /// landed on.
    private struct SwallowedPress {
        let down: CGEvent
        let appPID: pid_t?
        let windowID: CGWindowID?
    }

    /// What one look through the menus has found so far, for every shortcut
    /// the command may sit on, most likely first.
    private struct MenuSearch {
        let shortcuts: [MouseNavigationKeys.Shortcut]
        var visited = 0
        /// Per shortcut, the first item carrying it that read enabled.
        var enabledMatches: [AXUIElement?]
        /// Per shortcut, every item carrying it that read disabled.
        var disabledMatches: [[AXUIElement]]
        /// False once a question timed out or the cap cut the search short.
        var answeredInFull = true

        init(shortcuts: [MouseNavigationKeys.Shortcut]) {
            self.shortcuts = shortcuts
            enabledMatches = Array(repeating: nil, count: shortcuts.count)
            disabledMatches = Array(repeating: [], count: shortcuts.count)
        }

        /// An enabled item under the most likely shortcut cannot be beaten.
        var isSettled: Bool { enabledMatches.isEmpty || enabledMatches[0] != nil }
    }

    private func perform(_ direction: MouseNavigationDirection, press: SwallowedPress?) {
        // Read once, so the menus searched and the app a click goes back to
        // are the same one. Once another app has come forward since the press,
        // the click is dropped rather than sent to it.
        let app = NSWorkspace.shared.frontmostApplication
        if let pressedFor = press?.appPID, app?.processIdentifier != pressedFor { return }
        switch pressMenuItem(shortcuts: MouseNavigationKeys.candidates(for: direction), in: app) {
        case .pressed:
            return
        case .pressFailed(let shortcut):
            postCommand(shortcut)
        case .missed(let miss):
            // No verified Back or Forward in this app. Posting the shortcut
            // blindly is not an option: the same keys deeper in other menus are
            // editing commands (shift code left, rearrange layers) and a stray
            // side click must never touch the document.
            // One reading of the pointer serves both the check and the click, so
            // the click lands where the check looked.
            guard let press, let app, let pointer = CGEvent(source: nil)?.location,
                  MouseNavigationSupport.returnsClick(
                      miss: miss,
                      appStillInFront: NSWorkspace.shared.frontmostApplication?.processIdentifier
                          == app.processIdentifier,
                      pressedOverApp: press.windowID.flatMap(WindowServerSupport.ownerProcessID(ofWindowID:))
                          == app.processIdentifier,
                      pointerOverApp: Self.receivingProcess(at: pointer) == app.processIdentifier)
            else { return }
            handBack(press, at: pointer)
        }
    }

    /// Prefer the app's actual menu item. This preserves app-specific
    /// behavior, and the shortcuts looked for are the ones this keyboard
    /// carries. One look through the menus serves all of them. The synthetic
    /// shortcut below is only a fallback when an item that read enabled
    /// refuses AXPress.
    private func pressMenuItem(shortcuts: [MouseNavigationKeys.Shortcut],
                               in app: NSRunningApplication?) -> MenuPressOutcome {
        guard let app else { return .missed(.unanswered) }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // A busy target must not hold Vorssaint's main thread for AX's
        // multi-second default timeout. Child menu elements get the same
        // bound as they are traversed below.
        AXUIElementSetMessagingTimeout(application, 0.35)
        var search = MenuSearch(shortcuts: shortcuts)
        if let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, from: application, search: &search) {
            findMenuItems(in: menuBar, depth: 0, search: &search)
        }
        guard let target = MouseNavigationSupport.itemToPress(enabled: search.enabledMatches,
                                                              disabled: search.disabledMatches,
                                                              searchedInFull: search.answeredInFull) else {
            return .missed(MouseNavigationSupport.miss(
                sawDisabledItem: search.disabledMatches.contains { !$0.isEmpty },
                answeredInFull: search.answeredInFull))
        }
        guard AXUIElementPerformAction(target.item, kAXPressAction as CFString) == .success else {
            // Only an item that read enabled falls back to its shortcut. One
            // that read disabled may really be off.
            return target.readEnabled ? .pressFailed(shortcuts[target.shortcut]) : .missed(.disabled)
        }
        return .pressed
    }

    private func findMenuItems(in element: AXUIElement, depth: Int, search: inout MenuSearch) {
        // Depth 3 is a direct item of a top level menu (bar, bar item, menu,
        // item). Back and Forward always live there (Go, History); the same
        // key equivalents inside submenus belong to editing commands and are
        // deliberately out of reach. This also keeps the traversal short.
        guard depth <= 3, !search.isSettled else { return }
        guard search.visited < 600 else {
            search.answeredInFull = false
            return
        }
        search.visited += 1
        AXUIElementSetMessagingTimeout(element, 0.35)

        let command: String? = attribute(kAXMenuItemCmdCharAttribute, from: element, search: &search)
        let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, from: element, search: &search)
        let enabled: NSNumber? = attribute(kAXEnabledAttribute, from: element, search: &search)
        for (index, shortcut) in search.shortcuts.enumerated()
        where MouseNavigationSupport.matchesCommand(menuCharacter: command,
                                                    menuModifiers: modifiers?.uint32Value,
                                                    character: shortcut.character,
                                                    modifiers: shortcut.menuModifiers) {
            if enabled?.boolValue != false {
                if search.enabledMatches[index] == nil { search.enabledMatches[index] = element }
            } else {
                search.disabledMatches[index].append(element)
            }
        }

        // Items at the depth cap cannot host a match below them; skipping
        // the children copy saves one AX round trip per menu item.
        guard depth < 3 else { return }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element, search: &search) ?? []
        for child in children {
            findMenuItems(in: child, depth: depth + 1, search: &search)
        }
    }

    private func attribute<T>(_ name: String, from element: AXUIElement, search: inout MenuSearch) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        // Only a value, or a plain statement that there is none, answers the
        // question. A timeout, or an element the app replaced mid-search,
        // leaves it open, and the search no longer speaks for every item.
        switch error {
        case .success, .noValue, .attributeUnsupported: break
        default: search.answeredInFull = false
        }
        guard error == .success else { return nil }
        return value as? T
    }

    /// The process whose window a click at `point` would reach, found the
    /// way AppKit routes clicks, so a panel above the app counts as the panel.
    private static func receivingProcess(at point: CGPoint) -> pid_t? {
        FocusFollowsMouseService.receivingWindow(at: point)
            .flatMap(WindowServerSupport.ownerProcessID(ofWindowID:))
    }

    /// Puts a swallowed side click back for an app with no Back or Forward to
    /// press, so it gets the button it would get with this feature off. It
    /// goes back whole, the release right behind the press, and the real
    /// release that follows is swallowed with the rest of the gesture. A hold
    /// arrives as a plain click: once this tap has swallowed a press, neither
    /// the session's nor the HID system's button state reports the button as
    /// down, so a press still held cannot be told from one already over.
    /// Posted past this tap, at the current time and where the pointer was
    /// just read, so the pointer never jumps back to where the press began.
    private func handBack(_ press: SwallowedPress, at pointer: CGPoint) {
        let down = press.down
        down.location = pointer
        down.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        guard let up = down.copy() else { return }
        up.type = .otherMouseUp
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private func postCommand(_ shortcut: MouseNavigationKeys.Shortcut) {
        // The key that carries the command is the one this keyboard would use,
        // which is not the bracket key on keyboards that cannot type brackets
        // without Option.
        guard let stroke = MouseNavigationKeys.keyStroke(for: shortcut.character) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: stroke.keyCode,
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: stroke.keyCode,
                               keyDown: false) else { return }
        // No keyboardSetUnicodeString: a forced character string on a
        // shortcut event breaks menu key equivalent dispatch in the target
        // app, so the command would arrive and still do nothing. The virtual
        // key plus the modifier flags are all a shortcut needs.
        let flags: CGEventFlags = stroke.needsShift ? [.maskCommand, .maskShift] : .maskCommand
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
