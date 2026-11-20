// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

/// Monitors Caps Lock, held Shift keys, and paste triggers for Dynamic Island notices.
final class NotchInputFeedbackService: ObservableObject {
    static let shared = NotchInputFeedbackService()
    static let pasteTriggeredNotification = Notification.Name("VorssaintDidPaste")

    @Published private(set) var modifierIndicator: NotchModifierIndicator? = nil

    let pasteTriggered = PassthroughSubject<Void, Never>()

    private var running = false
    private var screensAsleep = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pasteNotificationObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var shiftHoldWork: DispatchWorkItem?

    private var modifierTracker = NotchModifierHoldTracker()
    private var pasteDetector = NotchPasteDetector()

    private init() {}

    func syncWithPreferences() {
        if NotchSupport.isEnabled() {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        screensAsleep = false

        pollModifierFlags(at: ProcessInfo.processInfo.systemUptime)

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        pasteNotificationObserver = NotificationCenter.default.addObserver(
            forName: Self.pasteTriggeredNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.triggerPaste()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
            }
        ]

        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, self.running, !self.screensAsleep else { return }
            self.pollModifierFlags(at: ProcessInfo.processInfo.systemUptime)
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        guard running else { return }
        running = false
        pollTimer?.invalidate()
        pollTimer = nil
        shiftHoldWork?.cancel()
        shiftHoldWork = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let pasteNotificationObserver { NotificationCenter.default.removeObserver(pasteNotificationObserver) }
        pasteNotificationObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers = []
        screensAsleep = false
        modifierTracker = NotchModifierHoldTracker()
        pasteDetector = NotchPasteDetector()
        if modifierIndicator != nil { modifierIndicator = nil }
    }

    private func handle(_ event: NSEvent) {
        guard running else { return }
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags
            let capsLock = flags.contains(.capsLock)
                || CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            let shiftDown = flags.contains(.shift)
            let otherDown = !flags.intersection([.command, .control, .option]).isEmpty
            applyModifierFlags(capsLock: capsLock, shiftDown: shiftDown, otherModifiersDown: otherDown,
                               at: ProcessInfo.processInfo.systemUptime)
        case .keyDown:
            if !event.isARepeat,
               NotchPasteDetector.isPasteKey(
                   keyCode: event.keyCode,
                   charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                   command: event.modifierFlags.contains(.command),
                   control: event.modifierFlags.contains(.control)
               ) {
                triggerPaste()
            }
        default:
            break
        }
    }

    private func pollModifierFlags(at now: TimeInterval) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let capsLock = flags.contains(.maskAlphaShift)
        let shiftDown = flags.contains(.maskShift)
        let otherDown = !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
        applyModifierFlags(capsLock: capsLock, shiftDown: shiftDown, otherModifiersDown: otherDown, at: now)
    }

    private func applyModifierFlags(capsLock: Bool, shiftDown: Bool, otherModifiersDown: Bool, at now: TimeInterval) {
        let next = modifierTracker.update(capsLock: capsLock, shiftDown: shiftDown, otherModifiersDown: otherModifiersDown, at: now)
        if next != modifierIndicator {
            modifierIndicator = next
        }
        if shiftDown, !otherModifiersDown, next != .shift, next != .both {
            if shiftHoldWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.running else { return }
                    self.shiftHoldWork = nil
                    self.pollModifierFlags(at: ProcessInfo.processInfo.systemUptime)
                }
                shiftHoldWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchModifierHoldTracker.shiftHoldDelay + 0.01, execute: work)
            }
        } else {
            shiftHoldWork?.cancel()
            shiftHoldWork = nil
        }
    }

    private func triggerPaste() {
        guard running, pasteDetector.recordPaste(at: ProcessInfo.processInfo.systemUptime) else { return }
        let send = { [weak self] in
            guard let self, self.running else { return }
            self.pasteTriggered.send()
        }
        if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
    }
}
