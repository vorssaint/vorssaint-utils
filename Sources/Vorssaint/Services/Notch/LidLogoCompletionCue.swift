// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import IOKit
import ObjectiveC

@MainActor
final class LidLogoCompletionCue {
    static let shared = LidLogoCompletionCue(
        driver: { LidLogoFadeClient.available },
        journal: PrivateFileStore.containerURL?.appendingPathComponent("lid-logo-restore"),
        mayControlLogo: {
            // These apps may be running a fade of their own. Leave the logo to them.
            let controllers = ["logolight", "lidlight", "backglow", "codeman"]
            return !NSWorkspace.shared.runningApplications.contains { app in
                let names = [app.localizedName, app.executableURL?.lastPathComponent]
                return names.contains { name in
                    guard let name else { return false }
                    return controllers.contains { name.lowercased().hasPrefix($0) }
                }
            }
        }
    )

    fileprivate nonisolated static let hasLogoDevice: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight"))
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }()

    nonisolated static var isSupported: Bool { LidLogoFadeClient.available != nil }

    struct Timing {
        var dim: Double = 1.1
        var brighten: Double = 1.4
        var settle: Double = 0.55
        var cooldown: Duration = .seconds(8)
        var reminderInterval: Duration = .seconds(25)
        var reminderLifetime: Duration = .seconds(30 * 60)
    }

    private let timing: Timing
    private let driver: () -> (any LidLogoFading)?
    private let journal: URL?
    private let mayControlLogo: () -> Bool
    private let recoveryCenter: NotificationCenter
    private var breath: Task<Void, Never>?
    private var reminders: Task<Void, Never>?
    private enum CueKind { case completion, reminder }

    private var playing: CueKind?
    private var queuedCompletion: CueKind?
    private var queuedStart: Task<Void, Never>?
    private var nextCue = ContinuousClock.now
    private var recoveryObservers: [NSObjectProtocol] = []

    init(driver: @escaping () -> (any LidLogoFading)?, journal: URL?,
         mayControlLogo: @escaping () -> Bool,
         recoveryCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         timing: Timing = Timing()) {
        self.driver = driver
        self.journal = journal
        self.mayControlLogo = mayControlLogo
        self.recoveryCenter = recoveryCenter
        self.timing = timing
    }

    private var restorePending: Bool {
        journal.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func play(repeatReminders: Bool = false, remindersEnabled: @escaping () -> Bool = { true }) {
        _ = startCompletion(.completion)
        guard repeatReminders else { return }
        clearReminderTimer()
        let expires = ContinuousClock.now + timing.reminderLifetime
        let interval = timing.reminderInterval
        reminders = Task { [weak self] in
            defer { if !Task.isCancelled { self?.reminders = nil } }
            var nextReminder = ContinuousClock.now + interval
            while nextReminder < expires {
                do { try await ContinuousClock().sleep(until: nextReminder) } catch { return }
                guard !Task.isCancelled, ContinuousClock.now < expires, remindersEnabled() else { return }
                _ = self?.startCompletion(.reminder)
                nextReminder = ContinuousClock.now + interval
            }
        }
    }

    private func startCompletion(_ kind: CueKind) -> Bool {
        if playing == .completion { return false } // Nearby finishes share the active pair.
        if kind == .reminder && queuedCompletion == .completion { return false }
        if ContinuousClock.now < nextCue {
            if kind == .completion {
                queuedCompletion = kind
                if queuedStart == nil {
                    let deadline = nextCue
                    queuedStart = Task { [weak self] in
                        do { try await ContinuousClock().sleep(until: deadline) } catch { return }
                        self?.queuedStart = nil
                        self?.startQueuedCompletion()
                    }
                }
            }
            return false
        }
        if breath != nil {
            queuedCompletion = kind
            return true
        }
        guard startBreath(kind, timing: timing, pulses: 2) else { return false }
        nextCue = ContinuousClock.now + timing.cooldown
        return true
    }

    private func startQueuedCompletion() {
        guard let queuedCompletion else { return }
        self.queuedCompletion = nil
        _ = startCompletion(queuedCompletion)
    }

    private func clearQueuedCompletion() {
        queuedCompletion = nil
        queuedStart?.cancel()
        queuedStart = nil
    }

    @discardableResult
    private func startBreath(_ kind: CueKind, timing: Timing, pulses: Int) -> Bool {
        guard breath == nil else { return false }
        if restorePending { recover(); return false }
        guard let driver = driver(), driver.canFade, mayControlLogo(), let journal,
              PrivateFileStore.createDirectory(at: journal.deletingLastPathComponent()),
              PrivateFileStore.write(Data(), to: journal)
        else { return false }

        // Record recovery before the first write. Never touch the persisted logo
        // on/off setting or change the screen's brightness.
        observeRecoveryIfNeeded()
        switch driver.fadeOut(duration: timing.dim) {
        case .unavailable:
            clearRecoveryRecord()
            return false
        case .interrupted:
            recover()
            return false
        case .started:
            playing = kind
        }
        breath = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(timing.dim)) } catch { return }
            guard !Task.isCancelled else { return }
            breath = nil
            restore(duration: timing.brighten, timing: timing, remainingPulses: pulses - 1)
        }
        return true
    }

    func stopReminders() {
        clearReminderTimer()
        if queuedCompletion == .reminder { clearQueuedCompletion() }
        if playing == .reminder { stopBreath() }
    }

    func cancelCompletion() {
        stopReminders()
        clearQueuedCompletion()
        if playing == .completion { stopBreath() }
    }

    func cancel() {
        clearReminderTimer()
        clearQueuedCompletion()
        stopBreath()
    }

    private func stopBreath() {
        playing = nil
        breath?.cancel()
        breath = nil
        recover()
    }

    func recover() {
        guard breath == nil else { return }
        restore(duration: 0, timing: timing)
    }

    private func clearReminderTimer() {
        reminders?.cancel()
        reminders = nil
    }

    private func restore(duration: Double, timing: Timing, remainingPulses: Int = 0) {
        guard restorePending, let driver = driver() else { return }
        observeRecoveryIfNeeded()
        guard driver.isAwake, mayControlLogo(), driver.restore(duration: duration) else {
            playing = nil
            clearQueuedCompletion()
            return
        }

        breath = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(duration + timing.settle))
                // A rise from dark can wait for the next display frame. Allow
                // a late return without writing another hardware command.
                for _ in 0..<2 where !driver.isAtBaseline {
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch { return }
            guard !Task.isCancelled else { return }
            breath = nil
            let finished = playing
            playing = nil
            guard driver.isAtBaseline, mayControlLogo(), driver.finishRestore() else {
                clearQueuedCompletion()
                return
            }
            clearRecoveryRecord()
            if let finished, remainingPulses > 0 {
                startBreath(finished, timing: timing, pulses: remainingPulses)
            } else if queuedStart == nil {
                startQueuedCompletion()
            }
        }
    }

    private func clearRecoveryRecord() {
        if let journal { try? FileManager.default.removeItem(at: journal) }
        if !restorePending {
            recoveryObservers.forEach(recoveryCenter.removeObserver)
            recoveryObservers.removeAll()
        }
    }

    private func observeRecoveryIfNeeded() {
        guard recoveryObservers.isEmpty else { return }
        // Retry after the display wakes or a competing controller quits.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            recoveryObservers.append(recoveryCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recover() }
            })
        }
    }
}

enum LidLogoFadeStart {
    /// The hardware was left untouched.
    case unavailable
    /// One or more writes may have taken effect and need recovery.
    case interrupted
    case started
}

protocol LidLogoFading: AnyObject {
    @MainActor var isAwake: Bool { get }
    @MainActor var isAtBaseline: Bool { get }
    @MainActor var canFade: Bool { get }
    @MainActor func fadeOut(duration: Double) -> LidLogoFadeStart
    @MainActor func restore(duration: Double) -> Bool
    @MainActor func finishRestore() -> Bool
}

/// Logo fade and keyboard interaction measured in LogoLight's CoreBrightness
/// notes: https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md
private final class LidLogoFadeClient: LidLogoFading {
    private typealias Read = @convention(c) (NSObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias Write = @convention(c) (NSObject, Selector, NSNumber, NSString) -> Bool
    private typealias WriteKeyboard = @convention(c) (NSObject, Selector, NSNumber, NSString, UInt64) -> Bool
    private typealias CopyIDs = @convention(c) (NSObject, Selector) -> Unmanaged<AnyObject>?

    static let available = LidLogoFadeClient()

    private let client: NSObject
    private let keyboard: NSObject
    private let read: Read
    private let write: Write
    private let writeKeyboard: WriteKeyboard
    private let copyIDs: CopyIDs
    private let readSelector = NSSelectorFromString("copyPropertyForKey:")
    private let writeSelector = NSSelectorFromString("setProperty:forKey:")
    private let keyboardSelector = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

    private init?() {
        guard LidLogoCompletionCue.hasLogoDevice,
              let framework = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              framework.load(),
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              let keyboardType = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
              let get = Self.method(type, readSelector, returns: "@", arguments: ["@"]),
              let set = Self.method(type, writeSelector, returns: "B", arguments: ["@", "@"]),
              let setKeyboard = Self.method(type, keyboardSelector, returns: "B", arguments: ["@", "@", "Q"]),
              let ids = Self.method(keyboardType, idsSelector, returns: "@", arguments: [])
        else { return nil }
        client = type.init()
        keyboard = keyboardType.init()
        read = unsafeBitCast(method_getImplementation(get), to: Read.self)
        write = unsafeBitCast(method_getImplementation(set), to: Write.self)
        writeKeyboard = unsafeBitCast(method_getImplementation(setKeyboard), to: WriteKeyboard.self)
        copyIDs = unsafeBitCast(method_getImplementation(ids), to: CopyIDs.self)
    }

    private static func method(_ type: AnyClass, _ selector: Selector,
                               returns: String, arguments: [String]) -> Method? {
        guard let method = class_getInstanceMethod(type, selector),
              Int(method_getNumberOfArguments(method)) == arguments.count + 2
        else { return nil }
        let copiedReturnType: UnsafeMutablePointer<CChar>? = method_copyReturnType(method)
        guard let returnType = copiedReturnType else { return nil }
        defer { free(returnType) }
        guard String(cString: returnType) == returns else { return nil }

        for (index, expected) in arguments.enumerated() {
            let copiedArgument: UnsafeMutablePointer<CChar>? = method_copyArgumentType(method, UInt32(index + 2))
            guard let argument = copiedArgument else { return nil }
            defer { free(argument) }
            guard String(cString: argument) == expected else { return nil }
        }
        return method
    }

    var isAwake: Bool {
        guard (property("CBClamshellState") as? NSNumber)?.intValue == 0 else { return false }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    var isAtBaseline: Bool {
        isAwake && (fadeFactor ?? 0) >= 0.97
    }

    private var fadeFactor: Double? {
        guard let state = property("LEPWMState") as? NSDictionary,
              let factor = (state["Factor"] as? NSNumber)?.doubleValue, factor.isFinite
        else { return nil }
        return factor
    }

    var canFade: Bool {
        (property("LEBacklightMode") as? NSNumber)?.intValue == 2
            && (property("DisplayLogicalState") as? NSNumber)?.intValue == 2
            && isAtBaseline
            && !keyboardIDs().isEmpty
    }

    func fadeOut(duration: Double) -> LidLogoFadeStart {
        let ids = keyboardIDs()
        guard !ids.isEmpty else { return .unavailable }
        guard set(NSNumber(value: duration), key: "LEPWMFactorFadeDuration"), set(1, key: "DisplayLogicalState")
        else { return .interrupted }
        // A global Blank also reaches the keyboard. Undo it there immediately.
        var keyboardsRestored = true
        for id in ids {
            if !writeKeyboard(client, keyboardSelector, 2, "DisplayLogicalState", id.uint64Value) {
                keyboardsRestored = false
            }
        }
        return keyboardsRestored ? .started : .interrupted
    }

    func restore(duration: Double) -> Bool {
        let durationSet = set(NSNumber(value: duration), key: "LEPWMFactorFadeDuration")
        let unblanked = set(2, key: "DisplayLogicalState")
        return durationSet && unblanked
    }

    func finishRestore() -> Bool {
        // Resetting the duration before the re-light starts can make the
        // return snap on instead of fading, especially on a static display.
        set(0, key: "LEPWMFactorFadeDuration")
    }

    private func keyboardIDs() -> [NSNumber] {
        copyIDs(keyboard, idsSelector)?.takeRetainedValue() as? [NSNumber] ?? []
    }

    private func property(_ key: String) -> AnyObject? {
        read(client, readSelector, key as NSString)?.takeRetainedValue()
    }

    private func set(_ value: NSNumber, key: String) -> Bool {
        write(client, writeSelector, value, key as NSString)
    }
}
