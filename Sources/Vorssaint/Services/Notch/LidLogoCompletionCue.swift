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

    nonisolated static let hasLogoDevice: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight"))
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }()

    static var isSupported: Bool { LidLogoFadeClient.available != nil }

    private let driver: () -> (any LidLogoFading)?
    private let journal: URL?
    private let mayControlLogo: () -> Bool
    private var task: Task<Void, Never>?
    private var nextCue = ContinuousClock.now
    private var wakeObservers: [NSObjectProtocol] = []

    init(driver: @escaping () -> (any LidLogoFading)?, journal: URL?,
         mayControlLogo: @escaping () -> Bool) {
        self.driver = driver
        self.journal = journal
        self.mayControlLogo = mayControlLogo
    }

    private var restorePending: Bool {
        journal.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func play() {
        guard task == nil, ContinuousClock.now >= nextCue else { return }
        if restorePending { recover(); return }
        guard let driver = driver(), driver.canFade, mayControlLogo(), let journal,
              PrivateFileStore.createDirectory(at: journal.deletingLastPathComponent()),
              PrivateFileStore.write(Data(), to: journal)
        else { return }

        // Record recovery before the first write. Never touch the persisted logo
        // on/off setting or change the screen's brightness.
        nextCue = ContinuousClock.now + .seconds(8)
        guard driver.fadeOut() else { recover(); return }
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            guard let self else { return }
            task = nil
            restore(duration: 0.85)
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

    private func restore(duration: Double) {
        guard let journal, restorePending else { return }
        observeWakeIfNeeded()
        guard let driver = driver(), driver.isAwake, mayControlLogo(),
              driver.restore(duration: duration)
        else { return }

        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            guard let self else { return }
            task = nil
            guard driver.isAtBaseline else { return }
            try? FileManager.default.removeItem(at: journal)
            if !restorePending {
                let center = NSWorkspace.shared.notificationCenter
                wakeObservers.forEach(center.removeObserver)
                wakeObservers.removeAll()
            }
        }
    }

    private func observeWakeIfNeeded() {
        guard wakeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recover() }
            })
        }
    }
}

@MainActor
protocol LidLogoFading: AnyObject {
    var isAwake: Bool { get }
    var isAtBaseline: Bool { get }
    var canFade: Bool { get }
    func fadeOut() -> Bool
    func restore(duration: Double) -> Bool
}

/// Logo fade and keyboard interaction measured in LogoLight's CoreBrightness
/// notes: https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md
@MainActor
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
              let get = class_getInstanceMethod(type, readSelector),
              let set = class_getInstanceMethod(type, writeSelector),
              let setKeyboard = class_getInstanceMethod(type, keyboardSelector),
              let ids = class_getInstanceMethod(keyboardType, idsSelector)
        else { return nil }
        client = type.init()
        keyboard = keyboardType.init()
        read = unsafeBitCast(method_getImplementation(get), to: Read.self)
        write = unsafeBitCast(method_getImplementation(set), to: Write.self)
        writeKeyboard = unsafeBitCast(method_getImplementation(setKeyboard), to: WriteKeyboard.self)
        copyIDs = unsafeBitCast(method_getImplementation(ids), to: CopyIDs.self)
        guard property("LEPWMState") is NSDictionary, property("LEBacklightMode") is NSNumber else { return nil }
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
        let state = property("LEPWMState") as? [String: NSNumber]
        return isAwake && (state?["Factor"]?.doubleValue ?? 0) >= 0.97
    }

    var canFade: Bool {
        (property("LEBacklightMode") as? NSNumber)?.intValue == 2
            && (property("DisplayLogicalState") as? NSNumber)?.intValue == 2
            && isAtBaseline
    }

    func fadeOut() -> Bool {
        guard let ids = copyIDs(keyboard, idsSelector)?.takeRetainedValue() as? [NSNumber], !ids.isEmpty,
              set(0.9, key: "LEPWMFactorFadeDuration"), set(1, key: "DisplayLogicalState")
        else { return false }
        // A global Blank also reaches the keyboard. Undo it there immediately.
        var keyboardsRestored = true
        for id in ids {
            if !writeKeyboard(client, keyboardSelector, 2, "DisplayLogicalState", id.uint64Value) {
                keyboardsRestored = false
            }
        }
        return keyboardsRestored
    }

    func restore(duration: Double) -> Bool {
        let durationSet = set(NSNumber(value: duration), key: "LEPWMFactorFadeDuration")
        let unblanked = set(2, key: "DisplayLogicalState")
        let automatic = set(0, key: "LEPWMFactorFadeDuration")
        return durationSet && unblanked && automatic
    }

    private func property(_ key: String) -> AnyObject? {
        read(client, readSelector, key as NSString)?.takeRetainedValue()
    }

    private func set(_ value: NSNumber, key: String) -> Bool {
        write(client, writeSelector, value, key as NSString)
    }
}
