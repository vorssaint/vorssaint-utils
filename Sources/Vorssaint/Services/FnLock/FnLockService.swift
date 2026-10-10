// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

/// One translation the Fn-Lock performed, for the settings page's key test
/// (issue #1227): which key arrived and what it became. Only the function
/// row ever reaches the translation, so nothing about any other keystroke
/// is ever recorded.
struct FnLockTranslationRecord: Identifiable, Equatable {
    let id = UUID()
    let source: FnLockSupport.KeyRef
    let target: FnLockSupport.KeyRef
    let isKeyDown: Bool
    let at: Date
}

/// Per-app F1-F12 translation (issue #1227). One list of apps; whichever of
/// them is in front gets its function row flipped: real function keys where
/// the system's own checkbox gives the row to the media actions, and the
/// media actions back where that checkbox already hands the row to the
/// function keys.
///
/// The translation runs as the first listener on the shared F-row tap
/// (`FunctionKeyTap`), ahead of the brightness keys, so a listed app's F2
/// reaches the app instead of stepping a display. The decision per event is
/// one dictionary lookup against the frontmost answer `MouseAppExceptions`
/// keeps fresh; nothing here touches AppKit from the tap thread, and the
/// synthetic events carry a marker so they are never translated twice.
final class FnLockService: ObservableObject {
    static let shared = FnLockService()

    /// True while the feature's listener is on the shared tap.
    @Published private(set) var isRunning = false
    /// True while the app in front is on the list, for the settings page
    /// and for the volume features, which stand down while it holds.
    @Published private(set) var engagesFrontmostApp = false
    /// The most recent translations, newest first, for the settings page's
    /// key test. Bounded, so leaving the page open costs nothing.
    @Published private(set) var recentTranslations: [FnLockTranslationRecord] = []
    /// How many translations the key test keeps.
    private static let translationLogLimit = 12

    /// Guards everything the tap thread reads: the engagement, the sampled
    /// system checkbox, the pending releases and the dedup window. Written
    /// on the main thread.
    private let stateLock = NSLock()
    /// The mirror of `engagesFrontmostApp` the tap thread reads; a published
    /// property is not safe to read from the tap thread while the main one
    /// writes it.
    private var engagedSnapshot = false
    private var systemFunctionKeysDefault = false
    /// Function keys whose synthetic press went out and whose release has
    /// not, so a frontmost change mid-press cannot leave one held down.
    private var pendingFunctionKeyUps = Set<Int>()
    /// NX media ids whose synthetic press went out and whose release has not.
    private var pendingMediaUps = Set<Int32>()
    /// Function-row keycodes whose in-place rewrite went out and whose
    /// release has not, mapped to the target keycode the app received, so a
    /// release that arrives after the engagement ended is rewritten to match
    /// the down the app saw, not the original key the hardware sent.
    private var translatedPresses = [Int: Int]()
    private var dedup = FnLockSupport.TranslationDedup()

    private var exceptionObservation: AnyCancellable?
    /// Observes the global keyboard preference so a change in System
    /// Settings is picked up without waiting for the next frontmost switch.
    private var defaultsObservation: AnyCancellable?
    /// Observes the app list so adding the first app or removing the last
    /// one starts or stops the listener without waiting for a full sync.
    private var listObservation: AnyCancellable?

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.fnLock.isAvailable
            && defaults.bool(forKey: DefaultsKey.fnLockEnabled)
            && SessionActivity.shared.isActive
        syncExceptionMonitoring(enabled: enabled && AXIsProcessTrusted())
        syncDefaultsObservation(enabled: enabled)
        syncListObservation(enabled: enabled && AXIsProcessTrusted())
        // An empty list has nothing to translate for anyone, so the listener
        // is not registered at all and the shared tap stays down when no
        // other feature wants it.
        let listWanted = enabled && AXIsProcessTrusted()
            && !MouseAppExceptions.shared.list(.fnLock).isEmpty
            && SessionActivitySupport.tapShouldRun(
                featureWanted: true,
                accessibilityGranted: true,
                sessionIsActive: SessionActivity.shared.isActive)
        if listWanted {
            syncEngagement()
            FunctionKeyTap.shared.addListener(
                named: "fnLock", priority: 0) { [weak self] type, event in
                guard let self else { return Unmanaged.passUnretained(event) }
                return self.route(type: type, event: event)
            }
        } else {
            FunctionKeyTap.shared.removeListener(named: "fnLock")
            // A press that went out under an engagement that just ended gets
            // its release, so no app is left holding a key.
            stateLock.withLock { engagedSnapshot = false }
            flushPendingReleases()
            if engagesFrontmostApp { engagesFrontmostApp = false }
        }
        let running = listWanted
        if isRunning != running { isRunning = running }
    }

    /// Keeps the shared workspace bookkeeping alive for this list and follows
    /// the app in front: the published answer drives the engagement, and the
    /// source ids make a helper shipped inside a listed app match (issue
    /// #1009).
    private func syncExceptionMonitoring(enabled: Bool) {
        let exceptions = MouseAppExceptions.shared
        if enabled {
            if exceptionObservation == nil {
                exceptionObservation = exceptions.$frontmostScopes
                    .map { $0.contains(.fnLock) }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.syncEngagement() }
            }
        } else {
            exceptionObservation = nil
        }
        exceptions.setSourceTracking(enabled, for: .fnLock)
    }

    /// Observes the global F-keys preference so a change in System Settings
    /// refreshes the snapshot without waiting for the next frontmost switch,
    /// including while the same listed app stays in front.
    private func syncDefaultsObservation(enabled: Bool) {
        if enabled {
            if defaultsObservation == nil {
                defaultsObservation = NotificationCenter.default
                    .publisher(for: UserDefaults.didChangeNotification)
                    .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
                    .sink { [weak self] _ in self?.syncEngagement() }
            }
        } else {
            defaultsObservation = nil
        }
    }

    /// Observes the app list so the listener starts the moment the first app
    /// is added and stops the moment the last is removed, without waiting
    /// for another full sync.
    private func syncListObservation(enabled: Bool) {
        if enabled {
            if listObservation == nil {
                listObservation = MouseAppExceptions.shared.$lists
                    .map { !($0[.fnLock]?.isEmpty ?? true) }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.syncWithPreferences() }
            }
        } else {
            listObservation = nil
        }
    }

    /// Reads the engagement from the published answer and samples the
    /// system's own checkbox with it, so a change in System Settings is
    /// picked up on the next frontmost change at the latest. Main thread.
    private func syncEngagement() {
        let engaged = MouseAppExceptions.shared.frontmostScopes.contains(.fnLock)
        let wasEngaged = stateLock.withLock { () -> Bool in
            let was = engagedSnapshot
            engagedSnapshot = engaged
            systemFunctionKeysDefault = FnLockSupport.systemFunctionKeysDefault()
            return was
        }
        if engagesFrontmostApp != engaged { engagesFrontmostApp = engaged }
        if wasEngaged && !engaged { flushPendingReleases() }
    }

    /// Posts the releases of any press that went out under an engagement that
    /// has since ended, so the app in front never holds a key down that no
    /// one will release. Main thread.
    private func flushPendingReleases() {
        let (keyUps, mediaUps, rewritten) = stateLock.withLock { () -> (Set<Int>, Set<Int32>, [Int: Int]) in
            let keyUps = pendingFunctionKeyUps
            let mediaUps = pendingMediaUps
            let rewritten = translatedPresses
            pendingFunctionKeyUps = []
            pendingMediaUps = []
            translatedPresses = [:]
            dedup.reset()
            return (keyUps, mediaUps, rewritten)
        }
        guard !keyUps.isEmpty || !mediaUps.isEmpty || !rewritten.isEmpty else { return }
        for keyCode in keyUps {
            FnLockKeyEvents.functionKeyEvent(keyCode: keyCode, isKeyDown: false,
                                             isRepeat: false, flags: [.maskSecondaryFn])?
                .post(tap: .cgSessionEventTap)
        }
        for nxKey in mediaUps {
            FnLockKeyEvents.mediaEvent(nxKey: nxKey, isKeyDown: false)?
                .post(tap: .cgSessionEventTap)
        }
        // Post the releases of in-place rewrites so the app that received
        // the target keycode also gets its up.
        for (_, target) in rewritten {
            FnLockKeyEvents.functionKeyEvent(keyCode: target, isKeyDown: false,
                                             isRepeat: false, flags: [.maskSecondaryFn])?
                .post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - Key test

    /// Notes one translation for the settings page's key test. Called on the
    /// tap thread; the record is an immutable value, so it crosses to the
    /// main thread and only the published array mutates there.
    private func recordTranslation(source: FnLockSupport.KeyRef,
                                   target: FnLockSupport.KeyRef,
                                   isKeyDown: Bool) {
        let record = FnLockTranslationRecord(source: source, target: target,
                                             isKeyDown: isKeyDown, at: Date())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recentTranslations.insert(record, at: 0)
            if self.recentTranslations.count > Self.translationLogLimit {
                self.recentTranslations.removeLast(self.recentTranslations.count
                                                   - Self.translationLogLimit)
            }
        }
    }

    /// Empties the key test's log.
    func clearTranslationLog() {
        if !recentTranslations.isEmpty { recentTranslations = [] }
    }

    // MARK: - The tap listener

    /// Runs on the shared F-row tap's thread. Reads only the lock-guarded
    /// engagement and the event itself; the synthetic events are posted
    /// from right here, which the window server accepts from a tap
    /// callback, and they carry the marker that brings them back through
    /// untouched.
    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !FnLockKeyEvents.isPosted(event) else { return Unmanaged.passUnretained(event) }
        if type == .keyDown || type == .keyUp {
            return routeKey(type: type, event: event)
        }
        if type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue {
            return routeSystemDefined(event: event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func routeKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isKeyDown = type == .keyDown
        // Complete any release we own before checking engagement: a press
        // we translated while engaged must have its release translated the
        // same way even if the app in front has since changed, so no key is
        // left held in one form and released in another.
        if !isKeyDown {
            if let owned = stateLock.withLock({ translatedPresses.removeValue(forKey: keyCode) }) {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(owned))
                var flags = event.flags
                flags.insert(.maskSecondaryFn)
                event.flags = flags
                recordTranslation(source: .keyCode(keyCode), target: .keyCode(owned), isKeyDown: false)
                return Unmanaged.passUnretained(event)
            }
            if let nxKey = FnLockSupport.functionToNXKey[keyCode],
               stateLock.withLock({ pendingMediaUps.remove(nxKey) }) != nil {
                recordTranslation(source: .keyCode(keyCode), target: .nxKey(nxKey), isKeyDown: false)
                FnLockKeyEvents.mediaEvent(nxKey: nxKey, isKeyDown: false, flags: event.flags)?
                    .post(tap: .cgSessionEventTap)
                return nil
            }
        }
        let (engaged, forward) = stateLock.withLock { (engagedSnapshot, systemFunctionKeysDefault) }
        guard engaged else { return Unmanaged.passUnretained(event) }
        let action = FnLockSupport.keyDownAction(keyCode: keyCode,
                                                 isKeyDown: isKeyDown,
                                                 systemFunctionKeysDefault: forward)
        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .rewrite(let target):
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(target))
            var flags = event.flags
            flags.insert(.maskSecondaryFn)
            event.flags = flags
            recordTranslation(source: .keyCode(keyCode), target: .keyCode(target),
                              isKeyDown: isKeyDown)
            if isKeyDown {
                stateLock.withLock { translatedPresses[keyCode] = target }
            }
            if forward {
                stateLock.withLock {
                    dedup.record(functionKey: keyCode, at: ProcessInfo.processInfo.systemUptime)
                }
            }
            return Unmanaged.passUnretained(event)
        case .postMediaDown(let nxKey):
            stateLock.withLock {
                pendingMediaUps.insert(nxKey)
                dedup.record(functionKey: keyCode, at: ProcessInfo.processInfo.systemUptime)
            }
            recordTranslation(source: .keyCode(keyCode), target: .nxKey(nxKey), isKeyDown: true)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            FnLockKeyEvents.mediaEvent(nxKey: nxKey, isKeyDown: true,
                                       flags: event.flags, isRepeat: isRepeat)?
                .post(tap: .cgSessionEventTap)
            return nil
        case .postMediaUp(let nxKey):
            let owned = stateLock.withLock { pendingMediaUps.remove(nxKey) != nil }
            guard owned else { return Unmanaged.passUnretained(event) }
            recordTranslation(source: .keyCode(keyCode), target: .nxKey(nxKey), isKeyDown: false)
            FnLockKeyEvents.mediaEvent(nxKey: nxKey, isKeyDown: false,
                                       flags: event.flags)?
                .post(tap: .cgSessionEventTap)
            return nil
        case .consume:
            return nil
        }
    }

    private func routeSystemDefined(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let raw = Int32(truncatingIfNeeded: nsEvent.data1)
        let nxKey = Int32((raw >> 16) & 0xFFFF)
        let state = Int((raw >> 8) & 0xFF)
        let isRepeat = raw & 0x1 != 0
        let isKeyDown = state == FnLockSupport.nxKeyDownState
        // Complete any release we own before checking engagement: a
        // synthetic function-key down we posted while engaged must have
        // its up posted too, even if the app in front has since changed.
        if !isKeyDown, let function = FnLockSupport.nxKeyToFunction[nxKey] {
            let owned = stateLock.withLock { pendingFunctionKeyUps.remove(function) != nil }
            if owned {
                recordTranslation(source: .nxKey(nxKey), target: .keyCode(function), isKeyDown: false)
                FnLockKeyEvents.functionKeyEvent(keyCode: function, isKeyDown: false,
                                                 isRepeat: false, flags: [.maskSecondaryFn])?
                    .post(tap: .cgSessionEventTap)
                return nil
            }
        }
        let (engaged, forward) = stateLock.withLock { (engagedSnapshot, systemFunctionKeysDefault) }
        guard engaged else { return Unmanaged.passUnretained(event) }
        let action = FnLockSupport.systemDefinedAction(nxKey: nxKey, state: state,
                                                        systemFunctionKeysDefault: forward)
        guard case .postFunctionKey(let functionKey) = action else {
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        // The same physical press may reach the tap in the plain key form
        // first; that form was already rewritten in place, so this copy is
        // consumed rather than delivered twice. Only the down is deduped:
        // a release within the window is a genuine up that completes the
        // pair, not an echo, so it always goes through.
        let blocked = isKeyDown && stateLock.withLock { dedup.blocks(functionKey: functionKey, at: now) }
        if blocked { return nil }
        if isKeyDown { stateLock.withLock { dedup.record(functionKey: functionKey, at: now) } }
        if isKeyDown { _ = stateLock.withLock { pendingFunctionKeyUps.insert(functionKey) } }
        else { _ = stateLock.withLock { pendingFunctionKeyUps.remove(functionKey) } }
        recordTranslation(source: .nxKey(nxKey), target: .keyCode(functionKey), isKeyDown: isKeyDown)
        FnLockKeyEvents.functionKeyEvent(keyCode: functionKey, isKeyDown: isKeyDown,
                                         isRepeat: isRepeat, flags: event.flags)?
            .post(tap: .cgSessionEventTap)
        return nil
    }
}
