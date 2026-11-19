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
    @Published private(set) var currentMacroStepIndex: Int?
    @Published var macros: [AutoClickerMacro] = []
    @Published var selectedMacroId: UUID?

    private var timer: DispatchSourceTimer?
    private var macroStopSemaphore: DispatchSemaphore?
    private var runningFlag = false
    private let queue = DispatchQueue(label: "com.vorssaint.autoclicker", qos: .userInteractive)
    private let hotkey = QuickToolHotkey(id: 90)
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private let lock = NSLock()

    private init() {
        loadMacros()
    }

    // MARK: - Macro Persistence & CRUD

    var selectedMacro: AutoClickerMacro? {
        guard let selectedMacroId else { return macros.first }
        return macros.first(where: { $0.id == selectedMacroId }) ?? macros.first
    }

    private func loadMacros() {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.autoClickerMacros) ?? ""
        macros = AutoClickerMacroStore.decode(raw)

        if let idString = UserDefaults.standard.string(forKey: DefaultsKey.autoClickerSelectedMacroId),
           let uuid = UUID(uuidString: idString),
           macros.contains(where: { $0.id == uuid }) {
            selectedMacroId = uuid
        } else {
            selectedMacroId = macros.first?.id
        }
    }

    private func saveMacros() {
        let encoded = AutoClickerMacroStore.encode(macros)
        UserDefaults.standard.set(encoded, forKey: DefaultsKey.autoClickerMacros)
        UserDefaults.standard.set(selectedMacroId?.uuidString ?? "", forKey: DefaultsKey.autoClickerSelectedMacroId)
    }

    @discardableResult
    func createMacro(name: String) -> AutoClickerMacro {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let macro = AutoClickerMacro(
            name: trimmed.isEmpty ? "Macro \(macros.count + 1)" : trimmed,
            steps: [],
            repeatCount: 1
        )
        macros.append(macro)
        selectedMacroId = macro.id
        saveMacros()
        return macro
    }

    func selectMacro(id: UUID) {
        guard macros.contains(where: { $0.id == id }) else { return }
        selectedMacroId = id
        saveMacros()
    }

    func updateMacro(_ updated: AutoClickerMacro) {
        guard let idx = macros.firstIndex(where: { $0.id == updated.id }) else { return }
        macros[idx] = updated
        saveMacros()
    }

    func deleteMacro(id: UUID) {
        macros.removeAll(where: { $0.id == id })
        if selectedMacroId == id {
            selectedMacroId = macros.first?.id
        }
        saveMacros()
    }

    func appendSteps(_ newSteps: [AutoClickerMacroStep], to macroId: UUID) {
        guard !newSteps.isEmpty,
              let idx = macros.firstIndex(where: { $0.id == macroId }) else { return }
        macros[idx].steps.append(contentsOf: newSteps)
        saveMacros()
    }

    func removeStep(stepId: UUID, from macroId: UUID) {
        guard let idx = macros.firstIndex(where: { $0.id == macroId }) else { return }
        macros[idx].steps.removeAll(where: { $0.id == stepId })
        saveMacros()
    }

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

        let mode = AutoClickerMode(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.autoClickerMode) ?? "single"
        ) ?? .single

        switch mode {
        case .single:
            startSingleClicker()
        case .macro:
            startMacroRunner()
        }
    }

    private func startSingleClicker() {
        lock.lock()
        runningFlag = true
        lock.unlock()

        clickCount = 0
        currentMacroStepIndex = nil
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
        let targetMode = AutoClickerTargetMode(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.autoClickerTargetMode) ?? "cursor"
        ) ?? .cursor
        let fixedPoint = CGPoint(
            x: UserDefaults.standard.double(forKey: DefaultsKey.autoClickerTargetX),
            y: UserDefaults.standard.double(forKey: DefaultsKey.autoClickerTargetY)
        )

        let sourceTimer = DispatchSource.makeTimerSource(queue: queue)
        sourceTimer.schedule(
            deadline: .now(),
            repeating: .milliseconds(interval)
        )
        sourceTimer.setEventHandler { [weak self] in
            guard let self else { return }
            let point = targetMode == .fixedPoint
                ? fixedPoint
                : (CGEvent(source: nil)?.location ?? .zero)
            self.performClick(
                at: point,
                warpCursor: targetMode == .fixedPoint,
                button: button,
                clickCount: 1,
                repeatLimit: repeatLimit
            )
        }
        sourceTimer.resume()
        timer = sourceTimer

        installEscapeMonitors()
    }

    private func startMacroRunner() {
        guard let macro = selectedMacro, !macro.steps.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        runningFlag = true
        macroStopSemaphore = semaphore
        lock.unlock()

        clickCount = 0
        currentMacroStepIndex = 0
        isRunning = true

        installEscapeMonitors()

        let steps = macro.steps
        let repeatLimit = macro.repeatCount

        queue.async { [weak self] in
            guard let self else { return }
            var cycle = 0
            while self.shouldContinueRunning() {
                if repeatLimit > 0 && cycle >= repeatLimit {
                    break
                }

                for (index, step) in steps.enumerated() {
                    guard self.shouldContinueRunning() else { break }

                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isRunning else { return }
                        self.currentMacroStepIndex = index
                    }

                    let point = CGPoint(x: step.x, y: step.y)
                    self.performClick(
                        at: point,
                        warpCursor: true,
                        button: step.button,
                        clickCount: step.clickCount,
                        repeatLimit: 0
                    )

                    let delay = AutoClickerCoordinates.clampedDelayMs(step.delayAfterMs)
                    if semaphore.wait(timeout: .now() + .milliseconds(delay)) == .success {
                        break
                    }
                }

                cycle += 1
            }

            self.stop()
        }
    }

    private func shouldContinueRunning() -> Bool {
        lock.lock()
        let active = runningFlag
        lock.unlock()
        return active
    }

    func stop() {
        lock.lock()
        runningFlag = false
        timer?.cancel()
        timer = nil
        macroStopSemaphore?.signal()
        macroStopSemaphore = nil

        if let monitor = globalEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscapeMonitor = nil
        }
        if let monitor = localEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            localEscapeMonitor = nil
        }
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.currentMacroStepIndex = nil
        }
    }

    // MARK: - Click Performance

    private func performClick(
        at point: CGPoint,
        warpCursor: Bool,
        button: AutoClickerButton,
        clickCount: Int,
        repeatLimit: Int
    ) {
        guard shouldContinueRunning() else { return }

        if warpCursor {
            CGWarpMouseCursorPosition(point)
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let count = max(1, min(clickCount, 2))
        for clickState in 1...count {
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

            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))

            if button == .middle {
                down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }

            down.post(tap: .cghidEventTap)
            usleep(5_000)
            up.post(tap: .cghidEventTap)
            if clickState < count {
                usleep(15_000)
            }
        }

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
