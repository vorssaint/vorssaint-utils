// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Combine

/// Guards only Command-Q and Command-W. The tap deliberately passes every
/// unrelated event without consulting the main app or Accessibility APIs.
final class QuitProtectionService: ObservableObject {
    static let shared = QuitProtectionService()

    @Published private(set) var isRunning = false
    @Published private(set) var revision = 0

    private struct Pending {
        let shortcut: QuitProtectionShortcut
        let event: CGEvent
        let mode: QuitProtectionMode
        let targetProcessIdentifier: pid_t?
    }

    private static let syntheticMarker: Int64 = 0x5652535341494E54
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var holdTimer: Timer?
    private var pendingExpiry: DispatchWorkItem?
    private var pending: Pending?
    private var swallowShortcut: QuitProtectionShortcut?
    private var frontmostBundleIdentifier: String?
    private var frontmostProcessIdentifier: pid_t?
    private let hud = QuitProtectionHUD()

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.quitWindowProtection.isAvailable
            && isEnabledForAnyShortcut
        guard SessionActivitySupport.tapShouldRun(
            featureWanted: enabled,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) else {
            stop()
            return
        }
        start()
    }

    var isEnabledForAnyShortcut: Bool {
        configuration(for: .quit).enabled || configuration(for: .close).enabled
    }

    func exceptions(for shortcut: QuitProtectionShortcut) -> [String] {
        (UserDefaults.standard.array(forKey: exceptionsKey(for: shortcut)) as? [String] ?? [])
            .filter { !$0.isEmpty }
            .sorted()
    }

    func addException(_ bundleIdentifier: String, for shortcut: QuitProtectionShortcut) {
        var values = exceptions(for: shortcut)
        guard !bundleIdentifier.isEmpty, !values.contains(bundleIdentifier) else { return }
        values.append(bundleIdentifier)
        UserDefaults.standard.set(values.sorted(), forKey: exceptionsKey(for: shortcut))
        revision += 1
        syncWithPreferences()
    }

    func removeException(_ bundleIdentifier: String, for shortcut: QuitProtectionShortcut) {
        let values = exceptions(for: shortcut).filter { $0 != bundleIdentifier }
        UserDefaults.standard.set(values, forKey: exceptionsKey(for: shortcut))
        revision += 1
        syncWithPreferences()
    }

    // MARK: Lifecycle

    private func start() {
        guard !isRunning else { return }
        guard installTap() else { return }
        isRunning = true
        let frontmost = NSWorkspace.shared.frontmostApplication
        frontmostBundleIdentifier = frontmost?.bundleIdentifier
        frontmostProcessIdentifier = frontmost?.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            if let pending = self.pending, pending.targetProcessIdentifier != app.processIdentifier {
                self.cancelPending()
            }
            self.frontmostBundleIdentifier = app.bundleIdentifier
            self.frontmostProcessIdentifier = app.processIdentifier
        }
    }

    private func stop() {
        cancelPending()
        swallowShortcut = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<QuitProtectionService>
                    .fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: Event routing

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The key up that ends the swallow may be among the events missed.
            swallowShortcut = nil
            cancelPending()
            let enabled = AppFeature.quitWindowProtection.isAvailable
                && isEnabledForAnyShortcut
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: enabled,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRearm, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard isRunning, !isSynthetic(event) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown: return handleKeyDown(event)
        case .keyUp: return handleKeyUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if keyCode == 53, pending != nil {
            cancelPending()
            return nil
        }

        let shortcut = matchingShortcut(for: event)

        if let swallowShortcut {
            if shortcut == swallowShortcut || isRepeat {
                return nil
            }
        }

        if let currentPending = pending {
            if shortcut != currentPending.shortcut {
                cancelPending()
            }
        }

        guard let shortcut else {
            return Unmanaged.passUnretained(event)
        }

        let configuration = configuration(for: shortcut)
        guard configuration.enabled,
              QuitProtectionSupport.scopeAllows(configuration.scope,
                                                bundleIdentifier: frontmostBundleIdentifier,
                                                exceptions: configuration.exceptions)
        else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let command = flags.contains(.maskCommand)
        if isRepeat, command {
            return nil
        }

        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let character = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
        let commandLabel = GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true)

        switch configuration.mode {
        case .hold:
            guard QuitProtectionSupport.isBaseShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                commandLabel: commandLabel,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut
            ) else {
                return Unmanaged.passUnretained(event)
            }
            beginPending(shortcut: shortcut, mode: .hold, event: event)
            showHUD(for: shortcut, configuration: configuration, extraModifierOnly: false)
            return nil

        case .doublePress:
            guard QuitProtectionSupport.isBaseShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                commandLabel: commandLabel,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut
            ) else {
                return Unmanaged.passUnretained(event)
            }
            if let pending, pending.shortcut == shortcut, pending.mode == .doublePress {
                if QuitProtectionSupport.isWithinDoublePressInterval(
                    firstTimestamp: pending.event.timestamp,
                    secondTimestamp: event.timestamp,
                    intervalMilliseconds: configuration.doublePressIntervalMilliseconds
                ) {
                    let targetPid = pending.targetProcessIdentifier
                    cancelPending()
                    swallowShortcut = shortcut
                    confirm(shortcut: shortcut, event: event, targetProcessIdentifier: targetPid)
                    return nil
                }
            }
            beginPending(shortcut: shortcut, mode: .doublePress, event: event)
            showHUD(for: shortcut, configuration: configuration, extraModifierOnly: false)
            return nil

        case .extraModifier:
            if QuitProtectionSupport.isExtraShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                commandLabel: commandLabel,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut,
                extraModifier: configuration.extraModifier
            ) {
                cancelPending()
                swallowShortcut = shortcut
                confirm(shortcut: shortcut,
                        event: event,
                        targetProcessIdentifier: frontmostProcessIdentifier,
                        removing: configuration.extraModifier)
                return nil
            }
            guard QuitProtectionSupport.isBaseShortcut(
                keyCharacter: character,
                keyCode: keyCode,
                commandLabel: commandLabel,
                command: command,
                control: control,
                option: option,
                shift: shift,
                shortcut: shortcut
            ) else {
                return Unmanaged.passUnretained(event)
            }
            beginPending(shortcut: shortcut, mode: .extraModifier, event: event)
            showHUD(for: shortcut, configuration: configuration, extraModifierOnly: true)
            return nil
        }
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let shortcut = matchingShortcut(for: event)

        if let swallow = swallowShortcut, shortcut == swallow {
            self.swallowShortcut = nil
            return nil
        }

        guard let pending else {
            return Unmanaged.passUnretained(event)
        }

        guard shortcut == pending.shortcut else {
            return Unmanaged.passUnretained(event)
        }

        switch pending.mode {
        case .hold:
            cancelPending()
            return nil

        case .doublePress:
            return nil

        case .extraModifier:
            cancelPending()
            return nil
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard pending != nil else { return }
        let flags = event.flags
        let commandHeld = flags.contains(.maskCommand)
        if !commandHeld {
            cancelPending()
        }
    }

    // MARK: Confirmation state

    private func beginPending(shortcut: QuitProtectionShortcut,
                              mode: QuitProtectionMode,
                              event: CGEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pending = Pending(shortcut: shortcut,
                          event: event,
                          mode: mode,
                          targetProcessIdentifier: frontmostProcessIdentifier)

        let configuration = configuration(for: shortcut)
        switch mode {
        case .hold:
            holdTimer = Timer.scheduledTimer(withTimeInterval:
                QuitProtectionSupport.sanitizedHoldDuration(configuration.holdDurationMilliseconds) / 1_000,
                repeats: false
            ) { [weak self] _ in self?.completeHold() }
        case .doublePress:
            let expiry = DispatchWorkItem { [weak self] in
                guard let self, self.pending?.mode == .doublePress else { return }
                self.cancelPending()
            }
            pendingExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now()
                + (QuitProtectionSupport.sanitizedDoublePressInterval(
                    configuration.doublePressIntervalMilliseconds
                ) + 100) / 1_000,
                                           execute: expiry)
        case .extraModifier:
            let expiry = DispatchWorkItem { [weak self] in
                guard let self, self.pending?.mode == .extraModifier else { return }
                self.cancelPending()
            }
            pendingExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: expiry)
        }
    }

    private func completeHold() {
        guard let pending, pending.mode == .hold else { return }
        let shortcut = pending.shortcut
        let event = pending.event
        let targetPid = pending.targetProcessIdentifier

        swallowShortcut = shortcut
        cancelPending()

        confirm(shortcut: shortcut, event: event, targetProcessIdentifier: targetPid)
    }

    private func cancelPending() {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pending = nil
        hideHUD()
    }

    // MARK: Preferences and presentation

    private func configuration(for shortcut: QuitProtectionShortcut) -> QuitProtectionConfiguration {
        let defaults = UserDefaults.standard
        let enabledKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitEnabled : DefaultsKey.quitProtectionCloseEnabled
        let modeKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitMode : DefaultsKey.quitProtectionCloseMode
        let holdKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitHoldDurationMs : DefaultsKey.quitProtectionCloseHoldDurationMs
        let doubleKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitDoubleIntervalMs : DefaultsKey.quitProtectionCloseDoubleIntervalMs
        let modifierKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitExtraModifier : DefaultsKey.quitProtectionCloseExtraModifier
        let scopeKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitScope : DefaultsKey.quitProtectionCloseScope
        let feedbackKey = shortcut == .quit ? DefaultsKey.quitProtectionQuitShowFeedback : DefaultsKey.quitProtectionCloseShowFeedback
        return QuitProtectionConfiguration(
            enabled: defaults.bool(forKey: enabledKey),
            mode: QuitProtectionSupport.modeFor(defaults.string(forKey: modeKey)),
            holdDurationMilliseconds: QuitProtectionSupport.sanitizedHoldDuration(defaults.double(forKey: holdKey)),
            doublePressIntervalMilliseconds: QuitProtectionSupport.sanitizedDoublePressInterval(defaults.double(forKey: doubleKey)),
            extraModifier: QuitProtectionSupport.extraModifierFor(defaults.string(forKey: modifierKey)),
            scope: QuitProtectionSupport.scopeFor(defaults.string(forKey: scopeKey)),
            exceptions: exceptions(for: shortcut),
            showFeedback: defaults.bool(forKey: feedbackKey)
        )
    }

    private func exceptionsKey(for shortcut: QuitProtectionShortcut) -> String {
        shortcut == .quit ? DefaultsKey.quitProtectionQuitExceptions : DefaultsKey.quitProtectionCloseExceptions
    }

    private func showHUD(for shortcut: QuitProtectionShortcut,
                         configuration: QuitProtectionConfiguration,
                         extraModifierOnly: Bool) {
        guard configuration.showFeedback else { return }
        let strings = FeatureStrings.quitProtection(L10n.shared.language)
        let title: String
        if extraModifierOnly {
            title = String(format: strings.extraHUDFormat,
                           "\(modifierSymbol(configuration.extraModifier))\(shortcut.symbol)")
        } else if configuration.mode == .hold {
            title = String(format: strings.holdHUDFormat, shortcut.symbol)
        } else {
            title = String(format: strings.doubleHUDFormat, shortcut.symbol)
        }
        hud.show(title: title, detail: strings.cancelHint)
    }

    private func hideHUD() { hud.hide() }

    private func modifierSymbol(_ modifier: QuitProtectionExtraModifier) -> String {
        switch modifier {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        }
    }

    // MARK: Event helpers

    private func matchingShortcut(for event: CGEvent) -> QuitProtectionShortcut? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let character = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
        // Read from the keycap cache; this tap runs on the main run loop, so a
        // miss derives from the layout and backfills rather than answering nil.
        let commandLabel = GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true)
        return QuitProtectionShortcut.allCases.first {
            QuitProtectionSupport.matchesKey(keyCharacter: character,
                                             keyCode: keyCode,
                                             commandLabel: commandLabel,
                                             shortcut: $0)
        }
    }

    private func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
    }

    private func confirm(shortcut: QuitProtectionShortcut,
                         event: CGEvent,
                         targetProcessIdentifier: pid_t?,
                         removing modifier: QuitProtectionExtraModifier? = nil) {
        if QuitProtectionSupport.usesNativeQuitRequest(for: shortcut),
           requestQuit(targetProcessIdentifier: targetProcessIdentifier) {
            return
        }
        postSyntheticPress(from: event, removing: modifier)
    }

    @discardableResult
    private func requestQuit(targetProcessIdentifier: pid_t?) -> Bool {
        guard let targetProcessIdentifier,
              let app = NSRunningApplication(processIdentifier: targetProcessIdentifier)
        else { return false }
        return app.terminate()
    }

    private func postSyntheticKeyDown(from event: CGEvent,
                                      removing modifier: QuitProtectionExtraModifier? = nil) {
        let copy = event.copy()!
        if let modifier { copy.flags = flags(for: event, removing: modifier) }
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.post(tap: .cghidEventTap)
    }

    private func postSyntheticKeyUp(from event: CGEvent,
                                    removing modifier: QuitProtectionExtraModifier? = nil) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let copy = CGEvent(keyboardEventSource: nil,
                                 virtualKey: CGKeyCode(keyCode),
                                 keyDown: false) else { return }
        copy.flags = modifier.map { flags(for: event, removing: $0) } ?? event.flags
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.post(tap: .cghidEventTap)
    }

    private func postSyntheticPress(from event: CGEvent,
                                    removing modifier: QuitProtectionExtraModifier? = nil) {
        postSyntheticKeyDown(from: event, removing: modifier)
        postSyntheticKeyUp(from: event, removing: modifier)
    }

    private func flags(for event: CGEvent,
                       removing modifier: QuitProtectionExtraModifier) -> CGEventFlags {
        var flags = event.flags
        switch modifier {
        case .shift: flags.remove(.maskShift)
        case .option: flags.remove(.maskAlternate)
        case .control: flags.remove(.maskControl)
        }
        return flags
    }
}
