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

    private let driver: () -> (any LidLogoFading)?
    private let journal: URL?
    private let mayControlLogo: () -> Bool
    private let recoveryCenter: NotificationCenter
    private var task: Task<Void, Never>?
    private var nextCue = ContinuousClock.now
    private var recoveryObservers: [NSObjectProtocol] = []

    init(driver: @escaping () -> (any LidLogoFading)?, journal: URL?,
         mayControlLogo: @escaping () -> Bool,
         recoveryCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.driver = driver
        self.journal = journal
        self.mayControlLogo = mayControlLogo
        self.recoveryCenter = recoveryCenter
    }

    private var restorePending: Bool {
        journal.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func play(_ pattern: LidLogoCuePattern) {
        guard task == nil, ContinuousClock.now >= nextCue else { return }
        if restorePending { recover(); return }
        guard let driver = driver(), driver.canFade, mayControlLogo(), let journal,
              PrivateFileStore.createDirectory(at: journal.deletingLastPathComponent()),
              PrivateFileStore.write(Data(), to: journal)
        else { return }

        // Record recovery before the first write. Never touch the persisted logo
        // on/off setting or change the screen's brightness.
        nextCue = ContinuousClock.now + .seconds(8)
        startDip(using: driver, remainingDips: pattern.pulseCount)
    }

    private func startDip(using driver: any LidLogoFading, remainingDips: Int) {
        switch driver.fadeOut() {
        case .unavailable:
            clearRecoveryRecord()
            return
        case .interrupted:
            recover()
            return
        case .started:
            break
        }
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            task = nil
            restore(duration: 0.85, followingDips: remainingDips - 1)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        recover()
    }

    func recover() {
        guard task == nil else { return }
        restore(duration: 0)
    }

    private func restore(duration: Double, followingDips: Int = 0) {
        guard restorePending, let driver = driver() else { return }
        observeRecoveryIfNeeded()
        guard driver.isAwake, mayControlLogo(),
              driver.restore(duration: duration)
        else { return }

        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            task = nil
            guard driver.isAtBaseline else { return }
            if followingDips > 0, restorePending, driver.isAwake, driver.canFade, mayControlLogo() {
                startDip(using: driver, remainingDips: followingDips)
                return
            }
            clearRecoveryRecord()
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
    @MainActor func fadeOut() -> LidLogoFadeStart
    @MainActor func restore(duration: Double) -> Bool
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
        guard fadeFactor != nil,
              property("LEBacklightMode") is NSNumber,
              property("DisplayLogicalState") is NSNumber,
              property("CBClamshellState") is NSNumber
        else { return nil }
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

    func fadeOut() -> LidLogoFadeStart {
        let ids = keyboardIDs()
        guard !ids.isEmpty else { return .unavailable }
        guard set(0.9, key: "LEPWMFactorFadeDuration"), set(1, key: "DisplayLogicalState")
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
        let automatic = set(0, key: "LEPWMFactorFadeDuration")
        return durationSet && unblanked && automatic
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
