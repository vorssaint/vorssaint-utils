// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// In Finder, Space on a folder-only selection opens Get Info; Space on files
/// still reaches Quick Look. The tap claims Space synchronously from focus and
/// modifier state, then classifies the selection off the tap thread so Finder
/// Automation never stalls key delivery (issue #1424).
final class FinderFolderInfoService {
    static let shared = FinderFolderInfoService()

    private static let finderBundleID = "com.apple.finder"
    /// Marks Space events we re-inject for Quick Look so this tap ignores them.
    private static let syntheticSpaceMarker: Int64 = 0x46494E46 // "FINF"

    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false

    private let workQueue = DispatchQueue(label: "Vorssaint.FinderFolderInfo", qos: .userInitiated)
    private let generationLock = NSLock()
    private var inspectionGeneration = 0

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.finderCutPaste.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderFolderSpaceGetInfo)
        if SessionActivitySupport.tapShouldRun(featureWanted: enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            installTap()
        } else {
            removeTap()
        }
    }

    func suspend() {
        removeTap()
    }

    private func installTap() {
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingStartAfterStop = true }
                return nil
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint Finder Folder Info"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func removeTap() {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            guard !shouldStop else {
                if clearEventTapThread() { installTap() }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<FinderFolderInfoService>
                        .fromOpaque(userInfo).takeUnretainedValue()
                    return service.route(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() { installTap() }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticSpaceMarker
        else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Int64(kVK_Space) else { return Unmanaged.passUnretained(event) }

        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        let hasModifiers = !flags.isEmpty
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              FinderFolderInfoSupport.shouldClaimSpace(
                  isFinderFrontmost: front.bundleIdentifier == Self.finderBundleID,
                  hasModifiers: hasModifiers,
                  acceptsFocusedRole: FinderRenameSupport.acceptsFocusedRole(
                      focusedRole(for: front.processIdentifier)))
        else { return Unmanaged.passUnretained(event) }

        // Swallow the matching keyUp so Finder never sees a lone Space release
        // after we claimed keyDown.
        if type == .keyUp { return nil }

        let generation = generationLock.withLock { () -> Int in
            inspectionGeneration += 1
            return inspectionGeneration
        }
        workQueue.async { [weak self] in
            self?.inspectSelection(generation: generation)
        }
        return nil
    }

    private func inspectSelection(generation: Int) {
        let urls = selectionURLs()
        let flags = urls.map(Self.isDirectory)
        let action = FinderFolderInfoSupport.action(directoryFlags: flags)
        let current = generationLock.withLock { inspectionGeneration }
        guard generation == current else { return }
        switch action {
        case .openGetInfo:
            openGetInfo(for: urls)
        case .forwardQuickLook:
            postSyntheticSpace()
        }
    }

    private func openGetInfo(for urls: [URL]) {
        guard !urls.isEmpty,
              AppleScriptRunner.consentToAutomate(bundleID: Self.finderBundleID)
        else { return }
        let lines = urls.map { url in
            "open information window of (POSIX file \(AppleScriptRunner.literal(url.path)) as alias)"
        }.joined(separator: "\n")
        let script = """
        tell application "Finder"
            \(lines)
        end tell
        """
        _ = AppleScriptRunner.run(script)
    }

    private func postSyntheticSpace() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space),
                               keyDown: false)
        else { return }
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticSpaceMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticSpaceMarker)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private func focusedRole(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString,
                                            &role) == .success,
              let role, CFGetTypeID(role) == CFStringGetTypeID()
        else { return nil }
        return role as? String
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue
    }

    private func selectionURLs() -> [URL] {
        guard AppleScriptRunner.consentToAutomate(bundleID: Self.finderBundleID) else { return [] }
        let script = """
        tell application "Finder"
            set out to ""
            repeat with f in (get selection)
                set out to out & (POSIX path of (f as alias)) & linefeed
            end repeat
            return out
        end tell
        """
        let result = AppleScriptRunner.run(script)
        guard result.ok else { return [] }
        return result.output.split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
    }
}
