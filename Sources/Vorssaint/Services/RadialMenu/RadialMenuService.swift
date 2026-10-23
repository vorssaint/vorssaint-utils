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
    /// The profile active in the current session.
    @Published private(set) var activeProfile: RadialMenuProfile?
    /// Names of the submenus that were descended into, for the hub's back hint.
    @Published private(set) var trail: [String] = []
    @Published private(set) var highlightedIndex: Int? {
        didSet { if highlightedIndex != oldValue { highlightDidChange() } }
    }
    @Published private(set) var nowPlayingState = RadialNowPlayingState.nothingPlaying
    /// True while a hold-capable session still owns its shortcut or mouse
    /// button; release behavior is determined by `sessionActivationMode`.
    @Published private(set) var holdPhase = false
    /// True when macOS refused a shortcut (taken by another app).
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

    /// Drives the wheel's arrival and departure: false while the panel is
    /// being placed, true once it is on screen, and false again the moment a
    /// session starts closing, which is what lets the wheel shrink away
    /// instead of blinking out.
    @Published private(set) var visible = false

    private var hotkeys: [UUID: QuickToolHotkey] = [:]
    private var panel: NSPanel?
    private var wheelCenter: CGPoint = .zero
    private var openPointerLocation: CGPoint = .zero
    private var pointerActivated = false
    private var sessionShortcut: GlobalShortcut?
    private var sessionActivationMode = RadialMenuActivationMode.pressOrHold
    private var sessionUsesSuperKey = false
    private var sessionID = 0
    /// Set while a session was summoned by a mouse button and it is still
    /// down; releasing it runs the pointed slice, mirroring the chord.
    private var holdButton: Int64?
    private var mouseTap: CFMachPort?
    private var mouseTapSource: CFRunLoopSource?
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var promptedForAccessibility = false
    private let dismissal = PanelDismissal()
    /// The list a slice opens beside the wheel while the pointer rests on it.
    private let peek = RadialMenuPeekController()
    private var peekDwell: DispatchWorkItem?

    private init() {
        peek.onOpenFile = { [weak self] url in self?.openFromPeek(url) }
        // A drag outlives the summoner: letting go of the shortcut mid-drag
        // must not close the wheel under the files being carried.
        peek.onDragStarted = { [weak self] in self?.enterStickyPhase() }
        peek.onDragEnded = { [weak self] dropped in
            // Dropped somewhere, the job is done; a cancelled drag returns
            // to the list it came from.
            guard dropped, let self, self.sessionActive else { return }
            self.endSession()
        }
        // A filter tap owned by a switched-away login session keeps its place
        // in the chain, so the account on screen waits out this tap's timeout
        // on every extra-button click it makes (issue #1075). Hand the tap
        // back on resign and build it again from preferences on the way in.
        // The open wheel goes with it: this tap is the only thing that sees a
        // held summoner released, so a wheel still up when the tap is handed
        // back would come back stuck in hold phase with no release coming.
        SessionActivity.shared.onChange { [weak self] active in
            if !active { self?.endSession() }
            self?.syncMouseTap()
        }
    }

    var sessionActive: Bool { !stack.isEmpty && !dismissal.isActive }

    private var currentItems: [RadialMenuItem] { stack.last ?? [] }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        // The trackpad tap is recognized by the middle click's contact reader.
        defer { MiddleClickService.shared.syncWithPreferences() }
        let defaults = UserDefaults.standard
        let enabled = AppFeature.radialMenu.isAvailable
            && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
        guard enabled else {
            suspend()
            registrationFailed = false
            return
        }

        let profiles = RadialMenuSupport.decodeProfiles(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        )

        for hotkey in hotkeys.values { hotkey.unregister() }
        hotkeys.removeAll()

        var anyFailed = false
        for (index, profile) in profiles.enumerated() {
            guard !profile.shortcut.isEmpty,
                  let shortcut = GlobalShortcut(storageValue: profile.shortcut) else { continue }
            let hotkey = QuickToolHotkey(id: 1700 + UInt32(index))
            hotkey.onPress = { [weak self] in self?.hotkeyPressed(for: profile) }
            // Wheels keep their combinations inside the profile list, so a
            // claim is named by the profile it belongs to.
            let registered = hotkey.sync(
                enabled: true, shortcut: shortcut,
                storageKey: "\(DefaultsKey.radialMenuProfiles).\(profile.id.uuidString)")
            if !registered { anyFailed = true }
            hotkeys[profile.id] = hotkey
        }
        registrationFailed = anyFailed

        syncMouseTap(profiles: profiles)
        // First render of a hosting view costs real time; pay it now so the
        // wheel appears the instant the shortcut fires.
        ensurePanel().contentView?.layoutSubtreeIfNeeded()
    }

    func suspend() {
        for hotkey in hotkeys.values { hotkey.unregister() }
        hotkeys.removeAll()
        tearDownMouseTap()
        endSession()
        panel = nil
        peek.releasePanel()
    }

    // MARK: - Mouse button trigger (a tap so the click never also reaches the
    // app under the pointer; alive only while a button is configured, torn
    // down with the feature)

    /// Whether the button tap has a job right now. The feature check is here
    /// rather than only in `syncWithPreferences`, because the resign handler
    /// and the capture row call the sync directly and so never pass that
    /// guard. The capture row wants the tap even with the feature switched
    /// off, so it can tell a button this app cannot see from one that is
    /// simply set to something else.
    private func mouseTapWanted(profiles: [RadialMenuProfile]?) -> Bool {
        let defaults = UserDefaults.standard
        // Asked of the stored buttons alone when the caller has no profiles in
        // hand: this only needs to know whether any wheel is bound to a button,
        // and the full decode pays for every item and icon to answer it.
        let hasAnyButton = profiles.map { list in
            list.contains { RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber != nil }
        } ?? !RadialMenuSupport.claimedMouseButtons(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        ).isEmpty
        let enabled = AppFeature.radialMenu.isAvailable
            && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
        return (hasAnyButton && enabled) || isReportingMouseButtons
    }

    private func syncMouseTap(profiles: [RadialMenuProfile]? = nil) {
        // Accessibility is asked of the system and not of `Permissions.shared`,
        // whose answer is a poll up to `PermissionPollingSupport.interval` old.
        // The re-arm hands a tap it declines to put back to this sync to be
        // stopped, and a stale grant here would install it straight back.
        guard SessionActivitySupport.tapShouldRun(
            featureWanted: mouseTapWanted(profiles: profiles),
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) else {
            tearDownMouseTap()
            return
        }
        // A tap the system disabled (Accessibility revoked and regranted)
        // never revives on its own; rebuild it instead of keeping the corpse.
        if let mouseTap, !CGEvent.tapIsEnabled(tap: mouseTap) {
            tearDownMouseTap()
        }
        guard mouseTap == nil else { return }
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
            // This tap's callback runs on the main run loop, so the session
            // flag is read where it is written. A tap put straight back is a
            // tap put back into whatever session is on screen now, which is
            // the stall the gate exists to end (issue #1075). Accessibility is
            // asked for the same reason as the sync: this tap swallows the
            // click, so a revoked grant has to end it rather than put it back.
            if SessionActivitySupport.tapShouldRun(
                featureWanted: mouseTapWanted(profiles: nil),
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            ), let mouseTap {
                CGEvent.tapEnable(tap: mouseTap, enable: true)
            } else {
                // Invalidating the port from its own callback stack is unsafe;
                // finish this callback fail-open, then release the tap.
                DispatchQueue.main.async { [weak self] in self?.syncMouseTap() }
            }
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
        let defaults = UserDefaults.standard
        let button = Int64(pressed)
        // Every press and release of every extra button lands here, so the
        // cheap question comes first: the wheels themselves are decoded only
        // once a press turns out to be a summoner, and only to open one.
        guard RadialMenuSupport.claimedMouseButtons(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        ).contains(button) else {
            return Unmanaged.passUnretained(event)
        }

        // The source lives on the main run loop, so this already runs on
        // main; acting synchronously keeps a quick click ordered (the down
        // opens the wheel before its own up arrives). The claimed button is
        // the wheel's alone: both halves of every click are consumed, so the
        // app under the pointer never sees half a gesture (the Settings
        // caption promises exactly that).
        if type == .otherMouseDown {
            if !sessionActive {
                let profiles = RadialMenuSupport.decodeProfiles(
                    defaults.data(forKey: DefaultsKey.radialMenuProfiles),
                    defaults: defaults
                )
                // The guard above already claimed the click, and the release
                // will be swallowed to match it. A profile the full decode
                // drops but the cheap read keeps (a corrupt blob) therefore
                // opens no wheel and still costs the app under the pointer
                // nothing: never one half of a click.
                if let matchingProfile = profiles.first(where: {
                    RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber == button
                }) {
                    beginSession(for: matchingProfile, hold: false, heldButton: button)
                }
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

    private func hotkeyPressed(for profile: RadialMenuProfile) {
        // Carbon hot keys never autorepeat, so a press during a session is
        // always the user asking to close, even with the modifiers still
        // held from the summoning chord.
        if sessionActive {
            if activeProfile?.id == profile.id {
                endSession()
                return
            }
            endSession()
        }
        beginSession(for: profile, hold: true)
    }

    /// A four-finger tap: opens the wheel that claims it as a sticky session,
    /// or closes it, like a second press of its shortcut.
    func toggleFromTrackpad() {
        let defaults = UserDefaults.standard
        guard AppFeature.radialMenu.isAvailable,
              defaults.bool(forKey: DefaultsKey.radialMenuEnabled),
              let profile = RadialMenuSupport.decodeProfiles(
                  defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults
              ).first(where: \.trackpadTap) else { return }
        if sessionActive {
            let sameWheel = activeProfile?.id == profile.id
            endSession()
            if sameWheel { return }
        }
        beginSession(for: profile, hold: false)
    }

    /// The Settings page's try-it button: a sticky session with the saved
    /// placement, exactly like a quick press of the shortcut.
    func presentPreview(for profile: RadialMenuProfile? = nil) {
        endSession()
        let defaults = UserDefaults.standard
        let profiles = RadialMenuSupport.decodeProfiles(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        )
        let targetProfile = profile ?? profiles.first ?? RadialMenuProfilePreset.general.createProfile()
        beginSession(for: targetProfile, hold: false)
    }

    private func beginSession(for profile: RadialMenuProfile, hold: Bool, heldButton: Int64? = nil) {
        let defaults = UserDefaults.standard
        let items = availableItems(profile.items)
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        // Summoned again mid-close, the wheel is taken back rather than left
        // to be emptied by the closing it was already in the middle of.
        dismissal.cancel { forgetSession() }
        // Small and clear until the panel is placed, so the wheel has somewhere
        // to grow from.
        visible = false
        activeProfile = profile
        if RadialMenuSupport.containsNowPlaying(items) {
            let nowPlaying = RadialNowPlayingService.shared
            nowPlaying.dismissDetails()
            nowPlaying.refresh { [weak self] state in self?.nowPlayingState = state }
        } else {
            nowPlayingState = .nothingPlaying
        }

        let shortcut = GlobalShortcut(storageValue: profile.shortcut) ?? .radialMenuDefault
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
        sessionUsesSuperKey = startsHeld && heldButton == nil
            && SuperKeyService.isEngaged && SuperKeyService.shared.isHeld
        holdButton = startsHeld ? heldButton : nil
        holdPhase = startsHeld
        sessionID &+= 1
        let activeSessionID = sessionID
        if sessionUsesSuperKey {
            SuperKeyService.shared.onHoldEnded = { [weak self] released in
                guard let self,
                      self.sessionUsesSuperKey,
                      self.sessionID == activeSessionID else { return }
                // No pointer event may mistake a queued cancellation for a
                // physical release before the deferred resolution runs.
                self.sessionShortcut = nil
                DispatchQueue.main.async {
                    guard self.sessionUsesSuperKey,
                          self.sessionID == activeSessionID else { return }
                    if released {
                        self.endHoldPhase()
                    } else {
                        self.endSession()
                    }
                }
            }
        }
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
        WheelMotion.present(panel)
        installMonitors(for: panel)
        refreshHighlight()
        // On the next turn, so the wheel has been drawn small once and has a
        // state to grow out of.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionActive, self.sessionID == activeSessionID else { return }
            self.visible = true
        }
    }

    private func endSession() {
        // A closing already under way finishes on its own.
        if dismissal.isActive { return }
        removeMonitors()
        stopTrackingSuperKeyHold()
        // The peek is a list to pick from, not part of the wheel's picture:
        // it leaves at once instead of fading out with it.
        closePeek()
        guard let panel, panel.isVisible, !stack.isEmpty else {
            forgetSession()
            return
        }
        // The wheel keeps its slices while it shrinks: emptying the stack now
        // would leave a bare disc fading out where a menu used to be.
        visible = false
        dismissal.begin(panel) { [weak self] in self?.forgetSession() }
    }

    /// Everything a session leaves behind, dropped once the wheel is gone.
    private func forgetSession() {
        // Every way a session ends passes here, so nothing that belongs to
        // the wheel outlives it, whichever path closed it.
        closePeek()
        visible = false
        panel?.orderOut(nil)
        stack = []
        activeProfile = nil
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
            peek.releasePanel()
        }
    }

    /// Wheels only show what can actually run today: tools whose feature was
    /// uninstalled in the hub disappear instead of leaving a dead slice.
    private func availableItems(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
        items.compactMap { item in
            var item = item
            if let tool = item.tool, !tool.isRunnable() { return nil }
            if item.kind == .quickToggle, !AppFeature.quickToggles.isAvailable { return nil }
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
        // Files on their way out: the pointer is carrying them over other
        // apps, not choosing a slice, and the list must stay where it is.
        if peek.isDragging { return }
        let dx = pointer.x - wheelCenter.x
        let dyUp = pointer.y - wheelCenter.y
        if peek.isOpen {
            peek.trackPointer(pointer)
            if peek.contains(pointer)
                || RadialMenuPeekLayout.holdsHighlight(pointerDistance: (dx * dx + dyUp * dyUp).squareRoot()) {
                return
            }
        }
        let index = RadialMenuGeometry.highlightedIndex(dx: dx,
                                                        dyUp: dyUp,
                                                        deadZoneRadius: RadialMenuLayout.deadZoneRadius,
                                                        itemCount: currentItems.count)
        if index != highlightedIndex { highlightedIndex = index }
    }

    /// A new slice under the pointer closes the last one's peek and starts
    /// the rest that opens its own. Keyboard highlights rest the same way.
    private func highlightDidChange() {
        closePeek()
        guard let index = highlightedIndex, sessionActive,
              currentItems.indices.contains(index),
              let kind = currentItems[index].peek,
              UserDefaults.standard.bool(forKey: DefaultsKey.radialMenuPeekEnabled) else { return }
        let session = sessionID
        let level = stack.count
        let dwell = DispatchWorkItem { [weak self] in
            guard let self, self.sessionActive, self.sessionID == session,
                  self.stack.count == level, self.highlightedIndex == index,
                  self.panel?.isVisible == true else { return }
            self.peekDwell = nil
            self.peek.open(kind, slice: index, color: self.activeProfile?.color ?? .accent,
                           wheelCenter: self.wheelCenter,
                           direction: RadialMenuGeometry.unitPosition(index: index,
                                                                      itemCount: self.currentItems.count))
        }
        peekDwell = dwell
        DispatchQueue.main.asyncAfter(deadline: .now() + RadialMenuPeekLayout.dwell, execute: dwell)
    }

    private func closePeek() {
        peekDwell?.cancel()
        peekDwell = nil
        peek.close()
    }

    /// Pastes the peek row the pointer or the arrows are on into the app in
    /// front, once the summoning chord has left the keyboard, or the paste
    /// would merge with it. False when no row is picked.
    @discardableResult
    private func choosePeekEntry() -> Bool {
        guard sessionActive, let entry = peek.highlightedEntry else { return false }
        endSession()
        afterModifiersReleased(attempt: 0) { ClipboardHistoryService.shared.paste(entry) }
        return true
    }

    /// A file opened from the folder list, the way a file slice opens one.
    private func openFromPeek(_ url: URL) {
        guard sessionActive else { return }
        endSession()
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
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

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: RadialMenuSupport.sessionMoveMask,
                                                          handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: RadialMenuSupport.sessionMoveMask,
                                                           handler: { [weak self] _ in
            self?.pointerMoved()
        }) { eventMonitors.append(monitor) }

        // Scrolling reaches the window under the pointer, key or not, so the
        // peek scrolls without ever taking the keyboard from the wheel.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, let peekWindow = self.peek.window, event.window === peekWindow else { return event }
            self.peek.scroll(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                             pointer: NSEvent.mouseLocation)
            return nil
        }) { eventMonitors.append(monitor) }

        // The rest of a press on the folder list: moving far enough makes it
        // a drag, coming back up where it began makes it a click. Watched
        // only while such a press is pending; every other press passes.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp],
                                                          handler: { [weak self] event in
            guard let self, self.peek.hasPendingPress else { return event }
            let point = NSEvent.mouseLocation
            if event.type == .leftMouseUp {
                self.peek.folderMouseUp(event, at: point)
                return nil
            }
            return self.peek.folderMouseDragged(event, at: point) ? nil : event
        }) { eventMonitors.append(monitor) }

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            // The peek never takes the keyboard, so its rows are not buttons:
            // a click there runs the row under the pointer, and nothing else.
            if let peekWindow = self.peek.window, event.window === peekWindow {
                if event.type == .leftMouseDown {
                    if self.peek.isFolder {
                        // A click or the start of a drag: the button's way
                        // back up, or the pointer's travel, decides which.
                        self.peek.folderMouseDown(at: NSEvent.mouseLocation)
                    } else {
                        self.peek.trackPointer(NSEvent.mouseLocation)
                        self.choosePeekEntry()
                    }
                }
                return nil
            }
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
        guard !RadialMenuSupport.shortcutIsStillHeld(
            modifiersHeld: shortcut.requiredModifiersHeld(in: flags),
            superKeyHeld: sessionUsesSuperKey && SuperKeyService.isEngaged
                && SuperKeyService.shared.isHeld
        ) else { return }
        endHoldPhase()
    }

    /// Resolve the summoner release according to the mode captured when this
    /// session opened. Reading it once per session prevents a Settings change
    /// mid-gesture from producing a half-old, half-new interaction.
    private func endHoldPhase() {
        guard sessionActive, holdPhase else { return }
        // Picking from a folder is the pointer's work: letting go of the
        // summoner over its list keeps the wheel up instead of opening
        // whatever file happens to sit under the pointer.
        if peek.isFolder, peek.contains(NSEvent.mouseLocation) {
            enterStickyPhase()
            return
        }
        switch sessionActivationMode.releaseAction(hasSelection: highlightedIndex != nil) {
        case .stayOpen:
            enterStickyPhase()
        case .dismiss:
            endSession()
        case .select:
            // Released over a peek row, the gesture was for that row.
            if choosePeekEntry() { return }
            guard let index = highlightedIndex else { return }
            select(index)
        }
    }

    private func enterStickyPhase() {
        holdPhase = false
        holdButton = nil
        stopTrackingSuperKeyHold()
    }

    private func stopTrackingSuperKeyHold() {
        guard sessionUsesSuperKey else { return }
        sessionUsesSuperKey = false
        SuperKeyService.shared.onHoldEnded = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if peek.isOpen, handlePeekKeyDown(event) { return true }
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

    /// While a peek is open, up and down walk its rows and Return pastes the
    /// one they are on; a digit pastes the entry with that number. Left and
    /// right still turn the wheel, which closes it. Esc closes the peek
    /// alone, and a second Esc steps back as usual.
    private func handlePeekKeyDown(_ event: NSEvent) -> Bool {
        if peek.isFolder { return handleFolderKeyDown(event) }
        let keyCode = Int(event.keyCode)
        if let digit = event.charactersIgnoringModifiers?.first?.wholeNumberValue, (1...9).contains(digit) {
            // Swallowed even past the last entry: with the list open, a digit
            // is a number in it, never a slice of the wheel behind.
            if peek.highlight(row: digit - 1) { choosePeekEntry() }
            return true
        }
        switch keyCode {
        case kVK_Escape:
            closePeek()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return choosePeekEntry()
        case kVK_UpArrow, kVK_DownArrow:
            if sessionActivationMode != .hold { enterStickyPhase() }
            peek.moveHighlight(by: keyCode == kVK_DownArrow ? 1 : -1)
            return true
        default:
            return false
        }
    }

    /// The folder list's keys: up and down walk the rows, Return or a digit
    /// opens a file or goes into a folder, → goes in and ← comes back up,
    /// Space picks a file and ⌘C copies the picked files. At the folder on
    /// the wheel, ← turns the wheel as it always does, and Return with no
    /// row opens the slice itself.
    private func handleFolderKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        let characters = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command), characters == "c" {
            if peek.copyFiles() { endSession() } else { NSSound.beep() }
            return true
        }
        if let digit = characters?.first?.wholeNumberValue, (1...9).contains(digit) {
            if peek.highlight(row: digit - 1) { _ = peek.activateHighlighted() }
            return true
        }
        switch keyCode {
        case kVK_Escape:
            closePeek()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return peek.activateHighlighted()
        case kVK_UpArrow, kVK_DownArrow:
            if sessionActivationMode != .hold { enterStickyPhase() }
            peek.moveHighlight(by: keyCode == kVK_DownArrow ? 1 : -1)
            return true
        case kVK_RightArrow:
            return peek.enterHighlightedFolder()
        case kVK_LeftArrow:
            return peek.goUp()
        case kVK_Space:
            return peek.togglePickHighlighted()
        default:
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
                if key == .nowPlaying {
                    RadialNowPlayingService.shared.presentDetails(at: wheelCenter)
                } else {
                    postWhenModifiersReleased(attempt: 0) { Self.postMediaKey(key) }
                }
            }
        case .tool:
            if let tool = item.tool { run(tool) }
        case .quickToggle:
            if let action = item.quickToggle { run(action) }
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
            case .screenRecorder: ScreenRecorderService.shared.toggle()
            case .colorPicker: ColorSamplerService.shared.pick()
            case .screenOCR: ScreenTextService.shared.capture()
            case .micMute: MicMuteService.shared.toggle()
            case .clipboardHistory: ClipboardHistoryService.shared.showHistoryWindow()
            case .quickLauncher: QuickLauncherService.shared.show()
            case .cameraPreview: CameraPreviewService.shared.show()
            case .scratchpad: ScratchpadService.shared.show()
            case .shelf: ShelfService.shared.summon()
            case .cleaner: Self.openSettings(at: .cleaner)
            case .uninstaller: Self.openSettings(at: .uninstaller)
            case .appUpdates:
                AppUpdatesService.shared.check()
                Self.openSettings(at: .appUpdates)
            case .cleaningMode: CleaningModeManager.shared.activate()
            case .keepAwake: KeepAwakeManager.shared.toggle()
            }
        }
    }

    private static func openSettings(at page: SettingsPage) {
        SettingsRouter.shared.page = page
        appDelegate()?.openSettingsWindow()
    }

    private func run(_ action: RadialMenuQuickToggle) {
        guard AppFeature.quickToggles.isAvailable else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let toggles = QuickTogglesService.shared
            switch action {
            case .darkMode: toggles.toggleDarkMode()
            case .emptyTrash: toggles.emptyTrash()
            case .ejectDisks: toggles.ejectAllDisks()
            case .hiddenFiles: toggles.toggleHiddenFiles()
            case .desktopIcons: toggles.toggleDesktopIcons()
            case .lockScreen: toggles.lockScreen()
            case .displayOff: toggles.turnDisplayOff()
            case .screenSaver: toggles.startScreenSaver()
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

    private func postWhenModifiersReleased(attempt: Int, then post: @escaping () -> Void) {
        guard ensureAccessibilityPermission() else { return }
        afterModifiersReleased(attempt: attempt, then: post)
    }

    /// Waits for the summoning chord to leave the keyboard before posting, or
    /// the synthetic key merges with the still-held modifiers (checked every
    /// 15 ms for up to ~1.5 s, with an extra beat once clean). Asks nothing
    /// of Accessibility itself: a peek's paste still copies without it.
    private func afterModifiersReleased(attempt: Int, then action: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.afterModifiersReleased(attempt: attempt + 1, then: action)
        }
    }

    private static func postShortcut(_ shortcut: GlobalShortcut) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false)
        else { return }
        // The flags a real press carries, so a shortcut on an arrow or an F
        // key is recognised beyond the app in front as well (issue #401).
        keyDown.flags = shortcut.syntheticEventFlags
        keyUp.flags = shortcut.syntheticEventFlags
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Posts the aux-button pair the physical media keys produce, so whatever
    /// player owns the media keys reacts exactly as if F8 was pressed.
    private static func postMediaKey(_ key: RadialMenuMediaKey) {
        guard let auxKeyType = key.auxKeyType else { return }
        postAuxKey(auxKeyType, down: true)
        postAuxKey(auxKeyType, down: false)
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
    private final class KeyableWheelPanel: OverlayPanel {
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

/// The wheel's own arrival and departure. Reduce Motion is the only switch
/// over it: this is how the menu opens now, not a preference.
private enum WheelMotion {
    static var isEnabled: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Ordered while still transparent, so the wheel is never seen at full
    /// strength for a frame before the fade starts.
    static func present(_ panel: NSPanel) {
        panel.ignoresMouseEvents = false
        guard isEnabled else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Fades out, then hands back so the caller can order the panel away:
    /// only the caller knows whether a new session claimed it meanwhile.
    ///
    /// The keyboard is given back on the first frame, not the last. This panel
    /// takes key status without activating the app, and closing it is usually
    /// the prelude to typing into whatever is underneath; a window that is
    /// only fading out must not eat that. Ordering out and straight back in is
    /// what drops key status, and the pair lands in a single commit, so
    /// nothing blinks.
    static func dismiss(_ panel: NSPanel, completion: @escaping () -> Void) {
        guard isEnabled, panel.isVisible else {
            completion()
            return
        }
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { completion() }
    }
}

/// The bookkeeping a fading wheel needs: only one closing at a time, and a
/// closing that a new summon overtook must never order the panel away
/// underneath it.
final class PanelDismissal {
    /// True while the panel is only a picture: its monitors and its keyboard
    /// are already gone, so the wheel counts as closed from here.
    private(set) var isActive = false
    private var token = 0

    /// Fades the panel away and orders it out, then runs `finish` once, unless
    /// a new session claimed the panel first.
    func begin(_ panel: NSPanel, finish: @escaping () -> Void) {
        isActive = true
        token &+= 1
        let started = token
        WheelMotion.dismiss(panel) { [weak self] in
            guard let self, self.isActive, self.token == started else { return }
            self.isActive = false
            panel.orderOut(nil)
            finish()
        }
    }

    /// A new summon takes the panel back, so the closing it interrupted
    /// finishes here and now instead of landing on the new one.
    func cancel(finish: () -> Void) {
        guard isActive else { return }
        isActive = false
        token &+= 1
        finish()
    }
}
