// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

final class AutoClickerService: ObservableObject {

    static let shared = AutoClickerService()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var clickCount: Int = 0

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.vorssaint.autoclicker", qos: .userInteractive)
    private let hotkey = QuickToolHotkey(id: 90)
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private let lock = NSLock()

    private init() {}

    // MARK: - Preferences Sync

    func syncWithPreferences() {
        guard AppFeature.autoClicker.isAvailable else {
            stop()
            hotkey.unregister()
            return
        }

        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoClickerEnabled)
        guard enabled else {
            stop()
            hotkey.unregister()
            return
        }

        hotkey.onPress = { [weak self] in
            self?.toggle()
        }
        hotkey.sync(
            enabled: true,
            shortcut: GlobalShortcutRole.autoClicker.savedShortcut,
            storageKey: DefaultsKey.autoClickerShortcut
        )
    }

    // MARK: - Toggle

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Start / Stop

    func start() {
        if Thread.isMainThread {
            startInternal()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startInternal()
            }
        }
    }

    private func startInternal() {
        guard !isRunning else { return }

        guard Permissions.shared.accessibility else {
            Permissions.shared.requestAccessibility()
            return
        }

        clickCount = 0
        isRunning = true

        let intervalMs = max(
            UserDefaults.standard.integer(forKey: DefaultsKey.autoClickerIntervalMs),
            10
        )
        let interval = intervalMs == 0 ? 100 : intervalMs

        let button = AutoClickerButton(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.autoClickerButton) ?? "left"
        ) ?? .left

        let repeatLimit = UserDefaults.standard.integer(forKey: DefaultsKey.autoClickerRepeatLimit)

        let sourceTimer = DispatchSource.makeTimerSource(queue: queue)
        sourceTimer.schedule(
            deadline: .now(),
            repeating: .milliseconds(interval)
        )
        sourceTimer.setEventHandler { [weak self] in
            guard let self else { return }
            self.performClick(button: button, repeatLimit: repeatLimit)
        }
        sourceTimer.resume()
        timer = sourceTimer

        installEscapeMonitors()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        timer?.cancel()
        timer = nil

        if let monitor = globalEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscapeMonitor = nil
        }
        if let monitor = localEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            localEscapeMonitor = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
    }

    // MARK: - Click Performance

    private func performClick(button: AutoClickerButton, repeatLimit: Int) {
        let point = CGEvent(source: nil)?.location ?? .zero
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: button.cgEventTypeDown,
            mouseCursorPosition: point,
            mouseButton: button.cgMouseButton
        ) else { return }

        guard let up = CGEvent(
            mouseEventSource: source,
            mouseType: button.cgEventTypeUp,
            mouseCursorPosition: point,
            mouseButton: button.cgMouseButton
        ) else { return }

        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        if button == .middle {
            down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }

        down.post(tap: .cghidEventTap)
        usleep(5_000)
        up.post(tap: .cghidEventTap)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.clickCount += 1
            if repeatLimit > 0, self.clickCount >= repeatLimit {
                self.stop()
            }
        }
    }

    // MARK: - Escape Monitors

    private func installEscapeMonitors() {
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.stop()
            }
        }

        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.stop()
            }
            return event
        }
    }
}
