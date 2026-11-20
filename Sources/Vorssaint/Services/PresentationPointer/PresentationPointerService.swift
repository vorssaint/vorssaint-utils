// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Combine

/// A large pointer for screen shares and recordings: a hand, magic wand,
/// pencil, banana or ring drawn over every display that follows the mouse and
/// taps wherever it clicks, harder the faster the clicks come. Optionally the
/// clicks stop at the pointer instead of reaching the app being presented.
///
/// It needs no permission. Mouse-only global monitors are ungated, the
/// shortcuts are Carbon hot keys, the drawing is a click-through window and
/// blocked clicks land on a window of its own. Nothing runs while the feature
/// is uninstalled, and nothing but two hot keys and a few notification
/// observers while the pointer is off: the monitors, windows and sound players
/// exist only while it shows. It starts off at every launch, so a forgotten
/// switch never leaves a Mac with a hidden system pointer after a restart.
final class PresentationPointerService: ObservableObject {
    static let shared = PresentationPointerService()

    @Published private(set) var mode = PresentationPointerMode() {
        didSet { if mode != oldValue { revision &+= 1 } }
    }
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var blockClicksShortcutRegistrationFailed = false

    private let pointerHotkey = QuickToolHotkey(id: 82)
    private let blockClicksHotkey = QuickToolHotkey(id: 83)
    private let systemPointer = SystemPointerHider()
    private let sound = PresentationPointerSoundPlayer()

    private var style = PresentationPointerSupport.defaultStyle
    private var color = NSColor.systemYellow
    private var pointerSize = CGFloat(PresentationPointerSupport.defaultSize)
    private var energy = PresentationPointerSupport.defaultEnergy
    private var burstsEnabled = true
    /// Drawn once per backing scale and setting change.
    private var artworkByScale: [CGFloat: PresentationPointerArtwork] = [:]

    private var overlays: [CGDirectDisplayID: PresentationPointerOverlay] = [:]
    private var shields: [CGDirectDisplayID: PresentationPointerClickShield] = [:]
    private var activeDisplayID: CGDirectDisplayID?
    /// Set when the pointer is turned on: the first display it lands on
    /// starts the arrival fade, and one it crosses to while that fade runs
    /// carries it on from `arrivalTime`.
    private var awaitingArrival = false
    private var arrivalTime: TimeInterval?
    private var restoreGeneration = 0
    /// The displays and their frames in the system's order, read once per
    /// layout so a mouse move allocates nothing.
    private var displayIDs: [CGDirectDisplayID] = []
    private var displayFrames: [CGRect] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Whether the overlays, monitors and observers are up.
    private var isPresenting = false
    private var presentationObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// Observers kept while the feature is installed, for the moments the
    /// pointer has to step aside.
    private var lifecycleObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var preview: NSSound?
    private var series = PresentationPointerTapSeries()
    /// Buttons seen going down since the pointer appeared, so a release only
    /// lifts the tap of a press it saw.
    private var buttonsDown: Set<Int> = []
    /// The tap being held, carried to another display if the pointer moves
    /// there mid-press.
    private var heldExpression: PresentationPointerTapExpression?

    /// The newest mouse position not drawn yet, applied once per screen
    /// refresh by the frame clock, which stops itself once the mouse rests.
    private var pendingMove: (location: CGPoint, time: TimeInterval)?
    private var frameClock: CADisplayLink?
    private var frameClockDisplay: CGDirectDisplayID?
    private var restingFrames = 0

    private var lastMove: (x: CGFloat, time: TimeInterval)?
    /// Where the pointer was last drawn, to notice a move nothing reported.
    private var drawnLocation: CGPoint?
    private var horizontalSpeed: Double = 0
    private var leanAngle: CGFloat = 0
    private var settleScheduled = false

    /// Reasons to step aside that come and go on their own; the switches stay
    /// as the person left them and the pointer returns when these clear.
    private var screenIsLocked = false
    private var screenSaverIsRunning = false
    private var captureHoldsPointer = false

    /// Whether this process ever made the service, so quitting gives the
    /// system pointer back whatever the feature's availability reads by then
    /// (a backup import can change it on the way out).
    private(set) static var isLoaded = false

    /// Posted when the pointer's overlay windows change, with their window
    /// numbers under `windowNumbersKey`, so a recording can take them in.
    static let overlayWindowsDidChange = Notification.Name("PresentationPointerService.overlayWindowsDidChange")
    static let windowNumbersKey = "windowNumbers"
    /// The overlay windows showing now, read on the main thread by a
    /// recording that starts while the pointer is already on.
    private(set) static var overlayWindowNumbers: [Int] = []

    /// Counts every change of the two switches, whatever made it, so a
    /// change scheduled for later can tell whether something else got there
    /// first.
    private(set) var revision = 0

    private init() {
        Self.isLoaded = true
        pointerHotkey.onPress = { [weak self] in self?.toggle() }
        blockClicksHotkey.onPress = { [weak self] in self?.toggleBlockingClicks() }
        SessionActivity.shared.onChange { [weak self] isActive in
            guard let self, AppFeature.presentationPointer.isAvailable else { return }
            // Clicks never stay blocked across a switch of user: whoever
            // comes back should find a mouse that works.
            if !isActive { self.allowClicksIfBlocked() }
            self.refreshPresentation()
        }
    }

    var isShowing: Bool { mode.isShowing }
    var blocksClicks: Bool { mode.blocksClicks }

    // MARK: - Preferences

    func syncWithPreferences() {
        let available = AppFeature.presentationPointer.isAvailable
        let defaults = UserDefaults.standard
        shortcutRegistrationFailed = !pointerHotkey.sync(
            enabled: available && defaults.bool(forKey: DefaultsKey.presentationPointerShortcutEnabled),
            shortcut: GlobalShortcutRole.presentationPointer.savedShortcut,
            storageKey: DefaultsKey.presentationPointerShortcut)
        blockClicksShortcutRegistrationFailed = !blockClicksHotkey.sync(
            enabled: available
                && defaults.bool(forKey: DefaultsKey.presentationPointerBlockClicksShortcutEnabled),
            shortcut: GlobalShortcutRole.presentationPointerBlockClicks.savedShortcut,
            storageKey: DefaultsKey.presentationPointerBlockClicksShortcut)
        if available {
            observeLifecycle()
        } else {
            mode.reset()
            stopObservingLifecycle()
        }
        if !available || Self.soundSource(from: defaults) == nil { stopPreview() }
        readAppearance(from: defaults)
        refreshPresentation()
    }

    func suspend() {
        pointerHotkey.unregister()
        blockClicksHotkey.unregister()
        mode.reset()
        stopObservingLifecycle()
        stopPreview()
        refreshPresentation()
    }

    // MARK: - Switches

    func toggle() {
        guard canPresent else { return }
        clearStaleStepAsideReasons()
        let wasBlocking = mode.blocksClicks
        mode.toggleShowing()
        if wasBlocking, !mode.blocksClicks { announceClicks() }
        refreshPresentation()
    }

    func toggleBlockingClicks() {
        guard canPresent else { return }
        clearStaleStepAsideReasons()
        // A screenshot or recording selection on screen needs the mouse;
        // blocking can be lifted then but not started.
        guard mode.blocksClicks || !captureHoldsPointer else { return }
        mode.toggleBlockingClicks()
        announceClicks()
        refreshPresentation()
    }

    /// Plays the chosen tap once, for the settings page.
    func previewSound() {
        stopPreview()
        guard let source = Self.soundSource(from: .standard),
              let sound = source.makeSound(level: 1) ?? PresentationPointerSoundSource.builtIn(.drum).makeSound(level: 1)
        else { return }
        sound.volume = Self.soundVolume(from: .standard)
        sound.play()
        preview = sound
        // A long file of the person's own is a tap, not a song: the preview
        // stops where a tap would.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak sound] in
            guard let self, let sound, self.preview === sound else { return }
            self.stopPreview()
        }
    }

    func stopPreview() {
        preview?.stop()
        preview = nil
    }

    private var canPresent: Bool {
        AppFeature.presentationPointer.isAvailable && SessionActivity.shared.isActive
    }

    /// A shortcut or a click on a switch means someone is at an unlocked
    /// screen, whatever a missed notification left behind.
    private func clearStaleStepAsideReasons() {
        screenIsLocked = false
        screenSaverIsRunning = false
        captureHoldsPointer = BackgroundCursor.owners.contains(.screenCapture)
    }

    private func allowClicksIfBlocked() {
        guard mode.blocksClicks else { return }
        mode.toggleBlockingClicks()
    }

    private func announceClicks() {
        let strings = FeatureStrings.presentationPointer(L10n.shared.language)
        guard mode.blocksClicks else {
            QuickToolHUD.show(icon: "cursorarrow.click", message: strings.clicksAllowedHUD)
            return
        }
        let message: String
        if UserDefaults.standard.bool(forKey: DefaultsKey.presentationPointerBlockClicksShortcutEnabled),
           !blockClicksShortcutRegistrationFailed {
            message = String(format: strings.clicksBlockedHUDWithShortcut,
                             GlobalShortcutRole.presentationPointerBlockClicks.savedShortcut.displayString)
        } else {
            // The menu bar stays clickable above the shield, and the panel
            // offers the way back while clicks are blocked.
            message = strings.clicksBlockedHUD
        }
        QuickToolHUD.show(icon: "hand.raised", message: message)
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let watched: [(String, (PresentationPointerService) -> Void)] = [
            ("com.apple.screenIsLocked", { $0.screenIsLocked = true; $0.allowClicksIfBlocked() }),
            ("com.apple.screenIsUnlocked", { $0.screenIsLocked = false }),
            ("com.apple.screensaver.didstart", { $0.screenSaverIsRunning = true }),
            ("com.apple.screensaver.didstop", { $0.screenSaverIsRunning = false }),
        ]
        for (name, update) in watched {
            lifecycleObservers.append((distributed, distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    guard let self else { return }
                    update(self)
                    self.refreshPresentation()
                }))
        }
        // A screenshot or recording selection shows its own crosshair, which
        // a hidden system pointer would hide too. Starting one also ends
        // click blocking: the capture has to scroll and find windows, and the
        // person has just shown they want the mouse back.
        let app = NotificationCenter.default
        lifecycleObservers.append((app, app.addObserver(
            forName: BackgroundCursor.ownersDidChange, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let holds = BackgroundCursor.owners.contains(.screenCapture)
                guard holds != self.captureHoldsPointer else { return }
                self.captureHoldsPointer = holds
                if holds { self.allowClicksIfBlocked() }
                self.refreshPresentation()
            }))
    }

    private func stopObservingLifecycle() {
        lifecycleObservers.forEach { $0.center.removeObserver($0.token) }
        lifecycleObservers = []
        screenIsLocked = false
        screenSaverIsRunning = false
        captureHoldsPointer = false
    }

    // MARK: - Presentation

    private var shouldPresent: Bool {
        mode.isShowing && canPresent && !screenIsLocked && !screenSaverIsRunning && !captureHoldsPointer
    }

    private func refreshPresentation() {
        if shouldPresent {
            present()
        } else {
            dismiss()
        }
        PresentationPointerClickBlock.set(isPresenting && mode.blocksClicks)
    }

    private func present() {
        let arriving = !isPresenting
        if arriving {
            installMonitors()
            // Without its monitor the drawn pointer could not follow the
            // mouse over other apps, and must not replace the real one.
            guard globalMonitor != nil else {
                removeMonitors()
                return
            }
            isPresenting = true
            sound.configure(source: Self.soundSource(from: .standard), volume: Self.soundVolume(from: .standard))
            let app = NotificationCenter.default
            presentationObservers = [
                (app, app.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                      object: nil, queue: .main) { [weak self] _ in self?.layoutDisplays() }),
                // A warp to another display sends no mouse event of its own.
                (app, app.addObserver(forName: PointerDisplayService.didWarpPointer,
                                      object: nil, queue: .main) { [weak self] _ in
                    self?.pendingMove = nil
                    self?.movePointer(to: NSEvent.mouseLocation)
                }),
            ]
            // Waking, moving between Spaces and another app coming forward are
            // when macOS is most likely to show its pointer again or to put a
            // window in front of the overlays.
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification,
                         NSWorkspace.didActivateApplicationNotification] {
                presentationObservers.append((workspace, workspace.addObserver(
                    forName: name, object: nil, queue: .main) { [weak self] _ in self?.reassertPointer() }))
            }
        }
        // The first display the pointer lands on fades it in (movePointer).
        if arriving {
            awaitingArrival = true
            arrivalTime = nil
        }
        layoutDisplays()
        if arriving { schedulePresentationCheck(after: 0.5) }
    }

    private func dismiss() {
        guard isPresenting else { return }
        isPresenting = false
        removeMonitors()
        stopFrameClock()
        presentationObservers.forEach { $0.center.removeObserver($0.token) }
        presentationObservers = []
        overlays.values.forEach { $0.close() }
        overlays = [:]
        Self.overlayWindowNumbers = []
        shields.values.forEach { $0.close() }
        shields = [:]
        activeDisplayID = nil
        displayIDs = []
        displayFrames = []
        awaitingArrival = false
        arrivalTime = nil
        drawnLocation = nil
        cancelPresentationCheck()
        systemPointerShowing = false
        series.reset()
        buttonsDown = []
        heldExpression = nil
        lastMove = nil
        horizontalSpeed = 0
        leanAngle = 0
        restoreSystemPointer()
        sound.configure(source: nil, volume: 0)
    }

    /// One overlay per display, and one click shield per display while clicks
    /// are blocked, matched to the screens as they are now.
    private func layoutDisplays() {
        let windowsBefore = Set(overlays.values.map(\.windowNumber))
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.displayID))
        for id in overlays.keys where !ids.contains(id) {
            overlays.removeValue(forKey: id)?.close()
        }
        for id in shields.keys where !ids.contains(id) || !mode.blocksClicks {
            shields.removeValue(forKey: id)?.close()
        }
        for screen in screens {
            let id = screen.displayID
            let overlay = overlays[id] ?? PresentationPointerOverlay(screen: screen)
            overlay.update(frame: screen.frame)
            if let artwork = artwork(scale: screen.backingScaleFactor) {
                overlay.apply(artwork)
            }
            if overlays[id] == nil {
                overlays[id] = overlay
                overlay.show()
            }
            if mode.blocksClicks {
                let shield = shields[id] ?? PresentationPointerClickShield(screen: screen)
                shield.update(frame: screen.frame)
                if shields[id] == nil {
                    shields[id] = shield
                    shield.show()
                }
            }
        }
        let windowsNow = overlays.values.map(\.windowNumber)
        Self.overlayWindowNumbers = windowsNow
        if Set(windowsNow) != windowsBefore {
            NotificationCenter.default.post(name: Self.overlayWindowsDidChange, object: nil,
                                            userInfo: [Self.windowNumbersKey: windowsNow])
        }
        displayIDs = screens.map(\.displayID).filter { overlays[$0] != nil }
        displayFrames = displayIDs.compactMap { overlays[$0]?.frame }
        // A display that went away took its pointer and its frame clock with
        // it; any other one keeps its pointer until the mouse leaves it.
        if let activeDisplayID, overlays[activeDisplayID] == nil { self.activeDisplayID = nil }
        if let frameClockDisplay, overlays[frameClockDisplay] == nil { stopFrameClock() }
        pendingMove = nil
        movePointer(to: NSEvent.mouseLocation)
        reconcileSystemPointer()
    }

    /// Hidden only while a picture stands in for it on the display the mouse
    /// is on: a picture that could not be read, or no display to draw on,
    /// leaves the system pointer where it is.
    private func reconcileSystemPointer() {
        if isPresenting, style.replacesSystemPointer, let id = activeDisplayID, overlays[id]?.hasArtwork == true {
            restoreGeneration &+= 1
            systemPointer.hide()
            // Some surfaces keep the system pointer however it is hidden;
            // find out in a moment, once the hide has landed, rather than at
            // the next mouse move.
            schedulePresentationCheck(after: 0.05)
        } else {
            // Only a pointer hidden until now needs giving back; a pass while
            // a refused show is being retried leaves that retry and its
            // spacing alone.
            if systemPointer.isHiding { restoreSystemPointer() }
            systemPointerShowing = false
            // The ring circles the system pointer, so it never steps aside.
            overlays.values.forEach { $0.setSuppressed(false) }
        }
    }

    // MARK: - Mouse

    private static let moveEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]
    private static let pressEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    private static let releaseEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]

    /// Events for other apps reach the global monitor and events for this
    /// app's own windows (Settings, the menu, the click shield) the local one,
    /// so between them every click is seen once.
    private func installMonitors() {
        let mask = Self.moveEvents.union(Self.pressEvents).union(Self.releaseEvents)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let location = Self.screenLocation(of: event)
        let type = NSEvent.EventTypeMask(type: event.type)
        if Self.pressEvents.contains(type) || Self.releaseEvents.contains(type) {
            // A click is drawn at once, where it landed.
            pendingMove = nil
            movePointer(to: location)
            if Self.pressEvents.contains(type) {
                press(event.buttonNumber, at: location, time: event.timestamp)
            } else {
                release(event.buttonNumber)
            }
        } else {
            // A mouse can report many times per refresh; only the newest
            // position is drawn, on the next frame.
            pendingMove = (location, event.timestamp)
            runFrameClock()
            releaseButtonsNoLongerHeld()
        }
        checkSystemPointer(now: event.timestamp)
        // A click can open a menu, where macOS may show its own pointer a
        // moment later with no move to tell us.
        if !Self.moveEvents.contains(type) { schedulePresentationCheck(after: 0.12) }
    }

    // MARK: - One pointer at a time

    /// Whether macOS showed its pointer at the last check, which the picture
    /// on whichever display the mouse is on follows.
    private var systemPointerShowing = false
    private var systemPointerCheckDue: TimeInterval?
    private var systemPointerCheckGeneration = 0

    /// Hides the system pointer again if macOS showed it, and where macOS
    /// insists on it (menus, the Dock, some system surfaces), steps the
    /// picture aside so the two never show at once.
    private func checkSystemPointer(now: TimeInterval, force: Bool = false) {
        guard isPresenting, style.replacesSystemPointer, let id = activeDisplayID else { return }
        guard let showing = systemPointer.reassertIfNeeded(now: now, force: force) else { return }
        systemPointerShowing = showing
        overlays[id]?.setSuppressed(showing)
        // While it shows, look often, so the picture comes back as soon as
        // the system pointer goes.
        if showing { schedulePresentationCheck(after: 0.15) }
    }

    /// Twice a second while the pointer shows, and soon after anything that
    /// can change it, a look at what sends no mouse event to follow: macOS
    /// showing its own pointer again (a menu opening late, an app resetting
    /// the cursor), an app moving the pointer itself, a button let go inside
    /// another app's own tracking loop.
    private func presentationCheck() {
        guard isPresenting else { return }
        followUnreportedPointer()
        releaseButtonsNoLongerHeld()
        checkSystemPointer(now: ProcessInfo.processInfo.systemUptime, force: true)
        schedulePresentationCheck(after: 0.5)
    }

    /// One pending check at a time; an earlier one replaces a later one.
    private func schedulePresentationCheck(after delay: TimeInterval) {
        let due = ProcessInfo.processInfo.systemUptime + delay
        if let systemPointerCheckDue, systemPointerCheckDue <= due { return }
        systemPointerCheckDue = due
        systemPointerCheckGeneration &+= 1
        let generation = systemPointerCheckGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.systemPointerCheckGeneration else { return }
            self.systemPointerCheckDue = nil
            self.presentationCheck()
        }
    }

    private func cancelPresentationCheck() {
        systemPointerCheckDue = nil
        systemPointerCheckGeneration &+= 1
    }

    /// A pointer moved by an app (a warp) sends no event; follow it.
    private func followUnreportedPointer() {
        guard pendingMove == nil else { return }
        let location = NSEvent.mouseLocation
        if let drawnLocation, hypot(location.x - drawnLocation.x, location.y - drawnLocation.y) < 0.5 { return }
        movePointer(to: location)
    }

    /// A release that happened inside another app's tracking loop never
    /// reaches the monitors; the mouse itself says the button is up.
    private func releaseButtonsNoLongerHeld() {
        guard !buttonsDown.isEmpty else { return }
        let held = NSEvent.pressedMouseButtons
        for button in buttonsDown where (0..<Int.bitWidth).contains(button) && held & (1 << button) == 0 {
            release(button)
        }
    }

    /// Gives the system pointer back. The window server can refuse, which
    /// would leave the Mac without a pointer, so a refused show is tried
    /// again, further apart each time up to every few seconds, until it
    /// takes or a picture stands in for the pointer again. One chain of
    /// retries runs at a time.
    private func restoreSystemPointer() {
        restoreGeneration &+= 1
        guard !systemPointer.show() else { return }
        retryRestore(generation: restoreGeneration, after: 0.25)
    }

    private func retryRestore(generation: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.restoreGeneration, !self.systemPointer.isHiding,
                  !self.systemPointer.show() else { return }
            self.retryRestore(generation: generation, after: min(delay * 2, 4))
        }
    }

    // MARK: - Frame clock

    /// Frames the clock keeps ticking after the last move before it stops.
    private static let framesBeforeRest = 30

    private func runFrameClock() {
        restingFrames = 0
        if let id = activeDisplayID, id != frameClockDisplay { stopFrameClock() }
        if let frameClock {
            frameClock.isPaused = false
            return
        }
        guard let id = activeDisplayID, let overlay = overlays[id] else { return }
        let clock = overlay.makeDisplayLink(target: self, selector: #selector(frameDidTick(_:)))
        clock.add(to: .main, forMode: .common)
        frameClock = clock
        frameClockDisplay = id
    }

    private func stopFrameClock() {
        frameClock?.invalidate()
        frameClock = nil
        frameClockDisplay = nil
    }

    @objc private func frameDidTick(_ clock: CADisplayLink) {
        guard let move = pendingMove else {
            restingFrames += 1
            if restingFrames >= Self.framesBeforeRest { clock.isPaused = true }
            return
        }
        pendingMove = nil
        restingFrames = 0
        movePointer(to: move.location)
        lean(toward: move.location.x, time: move.time)
        // Crossed onto another display: this clock belongs to the old one,
        // and the next move starts one there.
        if activeDisplayID != frameClockDisplay { stopFrameClock() }
    }

    /// Where the event happened, in AppKit's screen space. The mouse may have
    /// moved on by the time a monitor runs, so the click is drawn where it
    /// landed rather than where the mouse is now. Global coordinates run down
    /// from the top of the display with the menu bar.
    private static func screenLocation(of event: NSEvent) -> CGPoint {
        guard let location = event.cgEvent?.location, let primary = NSScreen.screens.first else {
            return NSEvent.mouseLocation
        }
        return CGPoint(x: location.x, y: primary.frame.maxY - location.y)
    }

    private func movePointer(to location: CGPoint) {
        guard let index = PresentationPointerSupport.screenIndex(containing: location, in: displayFrames)
        else { return }
        drawnLocation = location
        let id = displayIDs[index]
        if id != activeDisplayID {
            if let previous = activeDisplayID { overlays[previous]?.hidePointer() }
            activeDisplayID = id
            leanAngle = 0
            // The picture here picks up where the last one was: aside while
            // macOS shows its pointer, and still fading if it just arrived.
            overlays[id]?.setSuppressed(style.replacesSystemPointer && systemPointerShowing)
            overlays[id]?.movePointer(to: location)
            let now = ProcessInfo.processInfo.systemUptime
            if awaitingArrival {
                awaitingArrival = false
                arrivalTime = now
            }
            if let arrivalTime {
                overlays[id]?.fadeIn(elapsed: now - arrivalTime,
                                     reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
            reconcileSystemPointer()
            // A press held across the edge stays pressed on the new display.
            if let heldExpression {
                overlays[id]?.press(heldExpression,
                                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
            return
        }
        overlays[id]?.movePointer(to: location)
    }

    private func press(_ button: Int, at location: CGPoint, time: TimeInterval) {
        guard let id = activeDisplayID, let overlay = overlays[id] else { return }
        buttonsDown.insert(button)
        let level = series.registerPress(at: time)
        let expression = PresentationPointerTapExpression.make(level: level, energy: energy)
        heldExpression = expression
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Sound first: it is the part a person notices late soonest.
        sound.play(level: level, gain: expression.soundGain)
        overlay.press(expression, reduceMotion: reduceMotion)
        if burstsEnabled {
            overlay.burst(at: location, expression, reduceMotion: reduceMotion)
        }
    }

    private func release(_ button: Int) {
        guard buttonsDown.remove(button) != nil, buttonsDown.isEmpty else { return }
        heldExpression = nil
        if let id = activeDisplayID {
            overlays[id]?.release(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
    }

    /// Leans the pointer into sideways movement and lets it straighten once
    /// the movement stops. A turn too small to see is skipped, and one timer
    /// at a time waits for the stop, so a fast mouse costs little.
    private func lean(toward x: CGFloat, time: TimeInterval) {
        guard style.replacesSystemPointer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let id = activeDisplayID, let overlay = overlays[id] else { return }
        if let lastMove, time > lastMove.time {
            let speed = Double(x - lastMove.x) / (time - lastMove.time)
            if speed.isFinite { horizontalSpeed = horizontalSpeed * 0.6 + speed * 0.4 }
        }
        lastMove = (x, time)
        let angle = CGFloat(PresentationPointerSupport.tiltRadians(horizontalSpeed: horizontalSpeed))
        if abs(angle - leanAngle) >= Self.visibleLean {
            leanAngle = angle
            overlay.setTilt(angle, animated: true)
        }
        scheduleSettle(after: Self.settleDelay)
    }

    private static let visibleLean = CGFloat(0.4 * Double.pi / 180)
    private static let settleDelay: TimeInterval = 0.12

    private func scheduleSettle(after delay: TimeInterval) {
        guard !settleScheduled else { return }
        settleScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.settleScheduled = false
            guard self.isPresenting, let lastMove = self.lastMove else { return }
            let still = ProcessInfo.processInfo.systemUptime - lastMove.time
            guard still >= Self.settleDelay else {
                self.scheduleSettle(after: Self.settleDelay - still)
                return
            }
            self.horizontalSpeed = 0
            self.lastMove = nil
            self.leanAngle = 0
            if let id = self.activeDisplayID { self.overlays[id]?.setTilt(0, animated: true) }
        }
    }

    private func reassertPointer() {
        guard isPresenting else { return }
        checkSystemPointer(now: ProcessInfo.processInfo.systemUptime, force: true)
        overlays.values.forEach { $0.show() }
        shields.values.forEach { $0.show() }
    }

    // MARK: - Appearance

    private func readAppearance(from defaults: UserDefaults) {
        let style = PresentationPointerSupport.style(stored: defaults.string(forKey: DefaultsKey.presentationPointerStyle))
        let rgb = MenuBarUsageBarSupport.rgb(for: defaults.string(forKey: DefaultsKey.presentationPointerColor),
                                             fallback: PresentationPointerSupport.defaultColor)
        let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let size = CGFloat(PresentationPointerSupport.sanitizedSize(
            defaults.double(forKey: DefaultsKey.presentationPointerSize)))
        energy = PresentationPointerSupport.clampedFraction(defaults.double(forKey: DefaultsKey.presentationPointerEnergy))
        burstsEnabled = defaults.bool(forKey: DefaultsKey.presentationPointerBursts)
        if style != self.style || color != self.color || size != pointerSize {
            self.style = style
            self.color = color
            pointerSize = size
            artworkByScale = [:]
        }
        if isPresenting {
            sound.configure(source: Self.soundSource(from: defaults), volume: Self.soundVolume(from: defaults))
        }
    }

    private func artwork(scale: CGFloat) -> PresentationPointerArtwork? {
        if let cached = artworkByScale[scale] { return cached }
        let made = PresentationPointerArtwork.make(style: style, color: color, pointerSize: pointerSize,
                                                   scale: scale)
        artworkByScale[scale] = made
        return made
    }

    // MARK: - Sound

    /// What a tap plays, or nil for silence. A custom file that has gone
    /// missing falls back to the default sound rather than going quiet while
    /// the switch still reads on.
    static func soundSource(from defaults: UserDefaults) -> PresentationPointerSoundSource? {
        guard defaults.bool(forKey: DefaultsKey.presentationPointerSoundEnabled) else { return nil }
        switch PresentationPointerSoundChoice.resolve(
            stored: defaults.string(forKey: DefaultsKey.presentationPointerSoundName),
            systemNames: TextSnippetSupport.alertSoundNames) {
        case .builtIn(let sound):
            return .builtIn(sound)
        case .system(let name):
            return .file(TextSnippetSupport.soundFileURL(for: name))
        case .custom:
            guard let path = defaults.string(forKey: DefaultsKey.presentationPointerCustomSoundPath),
                  !path.isEmpty, FileManager.default.isReadableFile(atPath: path)
            else { return .builtIn(.drum) }
            return .file(URL(fileURLWithPath: path))
        }
    }

    static func soundVolume(from defaults: UserDefaults) -> Float {
        Float(PresentationPointerSupport.clampedFraction(
            defaults.double(forKey: DefaultsKey.presentationPointerSoundVolume)))
    }
}

// MARK: - System pointer

/// Hides the system pointer from the background while a drawn pointer stands
/// in for it, and gives it back exactly once. macOS can show it again on its
/// own (after waking, on a Space change, when another app comes forward), so
/// it is checked again at those moments, up to twenty times a second while the
/// mouse moves, and twice a second while it rests. Only calls the window server
/// accepted are counted.
private final class SystemPointerHider {
    private typealias VisibleFunction = @convention(c) () -> Int32

    private(set) var isHiding = false
    private var hides = 0
    private var lastCheck: TimeInterval = 0
    private var lastHideAttempt: TimeInterval = 0

    private let isVisible: VisibleFunction? = {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, "CGCursorIsVisible")
            .map { unsafeBitCast($0, to: VisibleFunction.self) }
    }()

    func hide() {
        guard !isHiding else { return }
        isHiding = true
        BackgroundCursor.setAllowed(true, by: .presentationPointer)
        if CGDisplayHideCursor(CGMainDisplayID()) == .success { hides += 1 }
    }

    /// Returns whether every hide has been given back.
    @discardableResult
    func show() -> Bool {
        guard isHiding || hides > 0 else { return true }
        isHiding = false
        while hides > 0, CGDisplayShowCursor(CGMainDisplayID()) == .success {
            hides -= 1
        }
        // A show the window server refused leaves the hide owed, and the
        // background permission with it; the next attempt pays it rather
        // than dropping it.
        if hides == 0 { BackgroundCursor.setAllowed(false, by: .presentationPointer) }
        return hides == 0
    }

    /// Hides the system pointer again if macOS showed it. Returns whether it
    /// is on screen after trying, or nil when it was not checked this time.
    /// Checks are cheap and run up to twenty times a second; where a hide
    /// does not take (macOS keeps its pointer over menus), it is tried again
    /// only every few tenths of a second.
    func reassertIfNeeded(now: TimeInterval, force: Bool = false) -> Bool? {
        guard isHiding, force || now - lastCheck >= 0.05 else { return nil }
        lastCheck = now
        guard let isVisible else { return nil }
        guard isVisible() != 0 else { return false }
        guard now - lastHideAttempt >= 0.3 else { return true }
        lastHideAttempt = now
        guard CGDisplayHideCursor(CGMainDisplayID()) == .success else { return true }
        hides += 1
        // A hide that changed nothing is handed straight back, so the count
        // owed on the way out stays small; one the window server refuses to
        // take back stays counted and is paid on the way out.
        if isVisible() != 0 {
            if CGDisplayShowCursor(CGMainDisplayID()) == .success { hides -= 1 }
            return true
        }
        return false
    }
}

// MARK: - Sound

/// Where a tap's sound comes from.
enum PresentationPointerSoundSource: Equatable {
    case builtIn(PresentationPointerTapSound)
    case file(URL)

    /// One player for a tap at `level`. The pointer's own sounds have a voice
    /// per level; a file sounds the same at every level.
    func makeSound(level: Int) -> NSSound? {
        switch self {
        case .builtIn(let sound):
            return NSSound(data: PresentationPointerTapSound.wavData(sound.samples(level: level)))
        case .file(let url):
            return NSSound(contentsOf: url, byReference: true)
        }
    }
}

/// The tap sounds on a small audio engine of their own, the way games play
/// effects: each sound sits ready in memory and a few players take turns, so a
/// tap is heard within a few milliseconds of the click and quick taps overlap
/// instead of cutting each other off. The engine runs only while the pointer
/// shows with sound on, and rests after a while without taps.
private final class PresentationPointerSoundPlayer {
    /// Made the first time a sound is configured, so a pointer that never
    /// plays one never builds an engine.
    private lazy var engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    /// One buffer per level for the pointer's own sounds; a file has one,
    /// under level 0.
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var source: PresentationPointerSoundSource?
    private var volume: Float = 0
    private var next = 0
    private var restWork: DispatchWorkItem?

    /// Long enough for any tap; a long file is cut here rather than held whole.
    private static let longestSound: TimeInterval = 2
    private static let restAfter: TimeInterval = 30

    func configure(source: PresentationPointerSoundSource?, volume: Float) {
        self.volume = volume
        guard source != self.source else { return }
        self.source = source
        tearDown()
        // A file that cannot be read as audio taps with the default sound,
        // as a missing one does, rather than going quiet with the switch on.
        guard let source, let format = load(source) ?? load(.builtIn(.drum)) else { return }
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.prepare()
        try? engine.start()
        scheduleRest()
    }

    func play(level: Int, gain: Float) {
        guard volume > 0, !players.isEmpty, let buffer = buffers[level] ?? buffers[0] else { return }
        // The output device may have changed, or the engine rested.
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.volume = min(1, volume * gain)
        // Interrupting replaces whatever this player still had queued
        // without stopping it: a stop waits for the audio thread, about
        // 13 ms on the main thread per tap (measured on macOS 27), where this
        // takes microseconds.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        scheduleRest()
    }

    private func scheduleRest() {
        restWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.engine.pause() }
        restWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restAfter, execute: work)
    }

    private func load(_ source: PresentationPointerSoundSource) -> AVAudioFormat? {
        switch source {
        case .builtIn(let sound):
            let rate = Double(PresentationPointerTapSound.sampleRate)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return nil }
            for level in 1...PresentationPointerTapSeries.maximumLevel {
                let samples = sound.samples(level: level)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                      let channel = buffer.floatChannelData?[0] else { continue }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
                buffers[level] = buffer
            }
            return buffers.isEmpty ? nil : format
        case .file(let url):
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let format = file.processingFormat
            let frames = AVAudioFrameCount(min(Double(file.length), format.sampleRate * Self.longestSound))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  (try? file.read(into: buffer, frameCount: frames)) != nil else { return nil }
            buffers[0] = buffer
            return format
        }
    }

    private func tearDown() {
        restWork?.cancel()
        restWork = nil
        guard !players.isEmpty || !buffers.isEmpty else { return }
        engine.stop()
        players.forEach {
            $0.stop()
            engine.detach($0)
        }
        players = []
        buffers = [:]
        next = 0
    }
}
