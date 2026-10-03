// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine

/// Asks for a hold or a second press before Control-Command-Q locks the
/// screen. The shortcut is the Lock Screen item of the Apple menu, not a
/// WindowServer hotkey, so registering it as a hotkey is enough to hold it
/// back: a registered hotkey is answered before the menu sees the key, and it
/// keeps arriving while an app holds secure input, where a key tap is blind.
/// The key registered is the one the current layout types Q with under
/// Command, the same key the menu answers, and it follows layout changes.
final class LockShortcutGuardService: ObservableObject {
    static let shared = LockShortcutGuardService()

    @Published private(set) var isRunning = false

    /// 'VLCK'
    private static let hotKeySignature: OSType = 0x564C_434B
    private static let modifierWatchInterval = 0.05

    private enum Pending {
        case hold
        case doublePress
    }

    private var hotKeyRef: EventHotKeyRef?
    private var registeredKeyCode: Int64?
    private var eventHandler: EventHandlerRef?
    private var layoutObserver: NSObjectProtocol?
    private var holdTimer: Timer?
    private var modifierWatch: Timer?
    private var pendingExpiry: DispatchWorkItem?
    private var pending: Pending?
    private var lastPress: Date?
    private let hud = QuitProtectionHUD()

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    // MARK: Preferences

    var isEnabled: Bool {
        AppFeature.quitWindowProtection.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.lockShortcutGuardEnabled)
    }

    /// Command-Q protection can take Control as its extra key, and then
    /// Control-Command-Q is the press that confirms a quit. That choice wins:
    /// this guard stays off, so the press has one owner whatever order the
    /// two were started in.
    static var quitProtectionOwnsShortcut: Bool {
        let defaults = UserDefaults.standard
        return LockShortcutGuardSupport.quitProtectionOwnsShortcut(
            quitEnabled: defaults.bool(forKey: DefaultsKey.quitProtectionQuitEnabled),
            quitMode: QuitProtectionSupport.modeFor(defaults.string(forKey: DefaultsKey.quitProtectionQuitMode)),
            extraModifier: QuitProtectionSupport.extraModifierFor(
                defaults.string(forKey: DefaultsKey.quitProtectionQuitExtraModifier)))
    }

    private var mode: LockShortcutGuardMode {
        LockShortcutGuardSupport.modeFor(UserDefaults.standard.string(forKey: DefaultsKey.lockShortcutGuardMode))
    }

    private var holdDurationMilliseconds: Double {
        QuitProtectionSupport.sanitizedHoldDuration(
            UserDefaults.standard.double(forKey: DefaultsKey.lockShortcutGuardHoldDurationMs))
    }

    private var doublePressIntervalMilliseconds: Double {
        QuitProtectionSupport.sanitizedDoublePressInterval(
            UserDefaults.standard.double(forKey: DefaultsKey.lockShortcutGuardDoubleIntervalMs))
    }

    private var showsFeedback: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.lockShortcutGuardShowFeedback)
    }

    func syncWithPreferences() {
        guard isEnabled, !Self.quitProtectionOwnsShortcut, SessionActivity.shared.isActive else {
            stop()
            return
        }
        start()
    }

    /// Lets go of the shortcut and any press in flight, for callers outside
    /// this type.
    func suspend() { stop() }

    // MARK: Lifecycle

    private func start() {
        ensureEventHandler()
        if layoutObserver == nil {
            layoutObserver = NotificationCenter.default.addObserver(
                forName: GlobalShortcut.keyboardLayoutDidChange, object: nil, queue: .main) { [weak self] _ in
                    guard let self, self.isRunning else { return }
                    self.register()
                }
        }
        register()
    }

    private func stop() {
        cancelPending()
        unregister()
        if let layoutObserver {
            NotificationCenter.default.removeObserver(layoutObserver)
        }
        layoutObserver = nil
        isRunning = false
    }

    /// Registers the key the layout types Q with under Command, again after
    /// a layout change moves it.
    private func register() {
        let keyCode = LockShortcutGuardSupport.lockKeyCode { code in
            GlobalShortcut.layoutKeyLabel(for: code, usesCommand: true)
        }
        if hotKeyRef != nil, registeredKeyCode == keyCode { return }
        unregister()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | cmdKey),
                                         EventHotKeyID(signature: Self.hotKeySignature, id: 1),
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            isRunning = false
            return
        }
        hotKeyRef = ref
        registeredKeyCode = keyCode
        isRunning = true
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registeredKeyCode = nil
    }

    private func ensureEventHandler() {
        guard eventHandler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == LockShortcutGuardService.hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let service = Unmanaged<LockShortcutGuardService>.fromOpaque(userData).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                pressed ? service.handlePress() : service.handleRelease()
            }
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    // MARK: Presses

    private func handlePress() {
        guard isRunning else { return }
        let now = Date()
        switch mode {
        case .hold:
            begin(.hold)
        case .doublePress:
            if pending == .doublePress, let lastPress,
               LockShortcutGuardSupport.isSecondPress(
                after: now.timeIntervalSince(lastPress) * 1_000,
                intervalMilliseconds: doublePressIntervalMilliseconds) {
                cancelPending()
                ScreenLock.lockNow()
                return
            }
            lastPress = now
            begin(.doublePress)
        }
    }

    /// Only a hold cares about the release: letting go of Q ends it.
    private func handleRelease() {
        if pending == .hold { cancelPending() }
    }

    private func begin(_ kind: Pending) {
        cancelPending()
        pending = kind
        let strings = FeatureStrings.quitProtection(L10n.shared.language)
        switch kind {
        case .hold:
            let duration = holdDurationMilliseconds / 1_000
            holdTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.completeHold()
            }
            // A hotkey reports the release of Q and nothing about Control or
            // Command, so they are read for as long as the hold lasts, and
            // only then: letting go of either ends it at once.
            modifierWatch = Timer.scheduledTimer(withTimeInterval: Self.modifierWatchInterval,
                                                 repeats: true) { [weak self] _ in
                guard let self, !self.modifiersAreDown else { return }
                self.cancelPending()
            }
            if showsFeedback {
                hud.show(title: String(format: strings.holdLockHUDFormat, LockShortcutGuardSupport.symbol),
                         detail: strings.releaseCancelHint,
                         holdDeadline: Date().addingTimeInterval(duration))
            }
        case .doublePress:
            let interval = doublePressIntervalMilliseconds
            let expiry = DispatchWorkItem { [weak self] in self?.cancelPending() }
            pendingExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + (interval + 100) / 1_000, execute: expiry)
            if showsFeedback {
                hud.show(title: String(format: strings.doubleLockHUDFormat, LockShortcutGuardSupport.symbol),
                         detail: "")
            }
        }
    }

    /// Read once more when the time is up, in case the modifiers went up
    /// between two looks of the watch.
    private func completeHold() {
        guard pending == .hold else { return }
        cancelPending()
        guard modifiersAreDown else { return }
        ScreenLock.lockNow()
    }

    private var modifiersAreDown: Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return LockShortcutGuardSupport.holdSurvivesFlagsChange(control: flags.contains(.maskControl),
                                                                command: flags.contains(.maskCommand))
    }

    private func cancelPending() {
        holdTimer?.invalidate()
        holdTimer = nil
        modifierWatch?.invalidate()
        modifierWatch = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pending = nil
        hud.hide()
    }
}
