// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Multi-finger trackpad gestures: recognizes taps, swipes and pinches from
/// the contacts `TrackpadTouchService` reads and hands each one to its owner.
/// The middle click's tap and the radial menu's four-finger tap stay reserved
/// for them; every other gesture runs the action the user mapped to it.
///
/// One recognizer owns every multi-finger tap, so two features never judge
/// the same touch. MultitouchSupport only observes: a gesture macOS also uses
/// still does what macOS does, which is why Settings shows those gestures as
/// taken instead of trying to block them. Requires Accessibility, like the
/// actions it runs.
final class TrackpadGestureService: ObservableObject {
    static let shared = TrackpadGestureService()

    @Published private(set) var isRunning = false
    /// Gestures macOS acts on as well, and where each can be freed.
    @Published private(set) var systemClaims: [TrackpadGesture: TrackpadSystemClaim] = [:]
    /// Taps another feature owns, by finger count.
    @Published private(set) var reservations: [Int: TrackpadTapOwner] = [:]

    /// Guards the recognizer, fed on the multitouch thread.
    private let stateLock = NSLock()
    private var recognizer = TrackpadGestureRecognizer()

    // Main thread only from here on.
    private var gesturesOn = false
    private var mappings: [TrackpadGesture: TriggerAction] = [:]
    private var systemSettings = TrackpadSystemGestureSettings()
    private var systemSettingsReadAt: TimeInterval = -10
    private var promptedForAccessibility = false

    private init() {
        // Contact callbacks belong only to the login session on screen.
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    /// Re-reads every input: the gestures' own switch and mappings, the
    /// middle-click and radial-menu taps they must leave alone, and the
    /// system gestures. The middle click calls this after each of its own
    /// syncs, and the radial menu through it.
    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let middleClickOn = AppFeature.middleClick.isAvailable
            && defaults.bool(forKey: DefaultsKey.middleClickEnabled)
        let middleClickTap = middleClickOn ? Defaults.sanitizedMiddleClickTapFingers(
            defaults.integer(forKey: DefaultsKey.middleClickTapFingers)) : 0
        let radialMenuTap = MiddleClickSupport.radialMenuTapFingers(
            radialMenuWantsTap: AppFeature.radialMenu.isAvailable
                && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
                && RadialMenuSupport.decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles),
                                                    defaults: defaults).contains(where: \.trackpadTap),
            middleClickTapFingers: middleClickTap)
        let owners = TrackpadGestureSupport.tapReservations(middleClickTapFingers: middleClickTap,
                                                            radialMenuTapFingers: radialMenuTap)
        if reservations != owners { reservations = owners }
        gesturesOn = AppFeature.trackpadGestures.isAvailable
            && defaults.bool(forKey: DefaultsKey.trackpadGesturesEnabled)
        mappings = gesturesOn
            ? TrackpadGestureMappingSupport.decode(defaults.data(forKey: DefaultsKey.trackpadGestureMappings))
            : [:]
        refreshSystemClaims()
        if SessionActivitySupport.tapShouldRun(
            featureWanted: gesturesOn || !owners.isEmpty,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    /// Re-reads which gestures macOS uses. Settings calls this when it
    /// appears, so a gesture freed in System Settings shows as free.
    func refreshSystemClaims() {
        systemSettings = Self.readSystemSettings()
        systemSettingsReadAt = ProcessInfo.processInfo.systemUptime
        let claims = TrackpadGestureSupport.systemClaims(systemSettings)
        if systemClaims != claims { systemClaims = claims }
    }

    /// Force-stops recognition regardless of preferences. Used by Cleaning
    /// Mode (wiping the trackpad is nothing but stray contacts), on quit and
    /// before the app resets its own permissions.
    func suspend() { stop() }

    // MARK: - Lifecycle

    private func start() {
        guard !isRunning else { return }
        stateLock.withLock { recognizer = TrackpadGestureRecognizer() }
        TrackpadTouchService.shared.subscribe(.gestures, wantsGeometry: true) { [weak self] frame in
            self?.contactFrame(frame)
        }
        isRunning = true
    }

    private func stop() {
        guard isRunning else { return }
        TrackpadTouchService.shared.unsubscribe(.gestures)
        stateLock.withLock { recognizer = TrackpadGestureRecognizer() }
        isRunning = false
    }

    // MARK: - Contact frames (multitouch callback thread)

    private func contactFrame(_ frame: TrackpadTouchFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        let finished = stateLock.withLock {
            recognizer.feed(count: frame.count, geometry: frame.geometry, now: now)
        }
        guard var contact = finished else { return }
        // Typing and clicking are read from the system's own event record
        // once the fingers lift, so no event tap is needed to notice them.
        // That record also counts the shortcut the previous gesture's action
        // posted, which is told apart from typing by when we posted it.
        contact.secondsSinceLastKeyDown = TrackpadGestureSupport.secondsSinceTyping(
            sinceLastKeyDown: CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                                      eventType: .keyDown),
            sinceOwnKeyPost: OwnKeyEvent.secondsSinceLastPost)
        let sinceClick = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
        contact.buttonPressed = sinceClick <= contact.contactDuration
        guard let gesture = TrackpadGestureSupport.judge(contact) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handle(gesture)
        }
    }

    // MARK: - Dispatch (main thread)

    private func handle(_ gesture: TrackpadGesture) {
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - systemSettingsReadAt > 2 { refreshSystemClaims() }
        switch TrackpadGestureSupport.route(gesture,
                                            reservations: reservations,
                                            systemDragGestureEnabled: systemSettings.threeFingerDrag ?? false) {
        case .middleClick:
            MiddleClickService.shared.postMiddleTap()
        case .radialMenu:
            RadialMenuService.shared.toggleFromTrackpad()
        case .dropped:
            return
        case .mapping:
            // An action that cannot run stays quiet; Settings says why.
            guard gesturesOn, let action = mappings[gesture],
                  TriggerActionRunner.unavailability(action) == nil else { return }
            let pointer = CGEvent(source: nil)?.location ?? .zero
            // An app on the exception list keeps the gesture to itself.
            guard !MouseAppExceptions.shared.excludesActionTarget(.trackpadGestures, at: pointer) else { return }
            TriggerActionRunner.run(action, context: TriggerActionRunner.Context(
                anchor: NSEvent.mouseLocation,
                ensureAccessibility: { [weak self] in self?.ensureAccessibilityPermission() ?? false },
                waitsForModifierRelease: false))
        }
    }

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

    // MARK: - System gestures

    private static let trackpadDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    private static func readSystemSettings() -> TrackpadSystemGestureSettings {
        TrackpadSystemGestureSettings(
            trackpad: { key in
                TrackpadSystemGestureSettings.merged(trackpadDomains.map { domain in
                    (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber)?.intValue
                })
            },
            dock: { key in
                (CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? NSNumber)?.boolValue
            })
    }
}
