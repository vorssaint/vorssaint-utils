// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// While a shortcut field is listening, every key press belongs to the field.
/// This active tap swallows key events ahead of the system, other apps'
/// global shortcuts and this app's own menu, and hands them to the field.
/// Without it, typing a combination something answers to performs that action
/// instead of landing in the field: recording Command Q would quit an app,
/// and combinations the system consumes could never be recorded at all.
///
/// The tap lives only while a field records, plus the tail of a key still
/// held when recording ends, so its release and autorepeats cannot reach the
/// app as a fresh press of the recorded combination. Only one field ever
/// records at a time (the ShortcutCapture invariant), so one static tap is
/// enough. Main thread only. Without Accessibility, begin fails and the
/// field falls back to plain view events, which is how it always worked.
enum ShortcutRecordingTap {
    private static var tap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?
    private static var handler: ((Int64, GlobalShortcutModifiers, CGEventFlags) -> Void)?
    /// True while the field is paused at a take-over offer. Safe navigation
    /// keys pass through to its buttons; bare Escape goes to the recording
    /// handler so the tap can swallow the complete pair. The tap stays alive
    /// and `ShortcutCapture` keeps the app's own global shortcuts quiet.
    private static var isPaused = false
    /// Identifies the offer that owns forwarded navigation-key repeats. A
    /// replacement offer must not inherit a key still held from the old one.
    private static var pausedOfferID: UUID?
    /// Routes safe button-navigation events as matched keyDown/keyUp pairs.
    /// It also swallows autorepeats if a button action ends the pause while
    /// its activating key is still held.
    private static var pausedKeyRouter = CommandBarRowShortcuts.PausedKeyRouter()
    /// The key most recently pressed while recording and possibly still down.
    private static var heldKeyCode: Int64?
    /// Set when recording ends with a key still down: its autorepeats and
    /// release keep being swallowed until the release arrives.
    private static var drainingKeyCode: Int64?
    private static var drainWatchdog: DispatchWorkItem?
    /// This tap is created after the super key's and therefore sits ahead of
    /// it, so the trigger key arrives here bare. Reading it the same way the
    /// super key does lets a field record the combination the way it will be
    /// pressed later, instead of asking for the chosen modifiers by hand.
    private static var superState = SuperKeySupport.State()
    private static var observingSession = false

    /// Starts swallowing key events and delivering each fresh press to the
    /// handler. Returns false when the tap cannot exist (no Accessibility),
    /// in which case the caller keeps its ordinary event path.
    @discardableResult
    static func begin(_ newHandler: @escaping (Int64, GlobalShortcutModifiers, CGEventFlags) -> Void) -> Bool {
        drainWatchdog?.cancel()
        drainWatchdog = nil
        drainingKeyCode = nil
        heldKeyCode = nil
        isPaused = false
        pausedOfferID = nil
        // The router keeps its promise across a re-begin: a key the pause
        // let through before its release still owes that release, even
        // when a new capture starts first.
        superState.reset()
        // Registered before the Accessibility check: ShortcutCapture.begin() has
        // already switched the global shortcuts off, and the resign must give them back.
        if !observingSession {
            observingSession = true
            SessionActivity.shared.onChange { if !$0 { tearDown(); ShortcutCapture.end() } }
        }
        drainGeneration += 1  // a re-begin owns the drain's next generation
        // A tap the system disabled behind our back reads as dead; rebuild.
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            tearDown()
        }
        if tap == nil {
            guard AXIsProcessTrusted() else { return false }
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            guard let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    ShortcutRecordingTap.handle(type: type, event: event)
                },
                userInfo: nil
            ) else { return false }
            tap = created
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
        }
        handler = newHandler
        return true
    }

    /// Safe to call twice and when begin failed. When the recorded key is
    /// still down, the tap lingers just long enough to swallow its release.
    static func end() {
        isPaused = false
        pausedOfferID = nil
        handler = nil
        guard tap != nil else { return }
        // Keys the pause already let reach the app owe their releases, even
        // though their press never reached the recording handler: accepting
        // an offer while a navigation key is held ends recording with those
        // still down. Their autorepeats stay suppressed and the release
        // forwards on its own, so the tap stays up until the last of them
        // lifts (or until the watchdog decides they will not).
        if let heldKeyCode { drainingKeyCode = heldKeyCode }
        drainGeneration += 1
        if !drainIsSettled {
            armDrainWatchdog()
        } else {
            tearDown()
        }
    }

    /// Hands the keys to the app while the recording holds still — an offer
    /// is being answered, and its buttons must take keyboard focus and
    /// activation. The tap itself stays alive (a rebuild would churn the
    /// system keyboard path, issue #275) and `ShortcutCapture` keeps the
    /// app's own global shortcuts quiet.
    static func setPaused(_ paused: Bool, offerID: UUID? = nil) {
        let nextOfferID = paused ? offerID : nil
        guard isPaused != paused || pausedOfferID != nextOfferID else { return }
        isPaused = paused
        pausedOfferID = nextOfferID
        if paused {
            // Any key still down belongs to the app from here on: its
            // release reaches the app, not this tap, so holding the record
            // would drain a key that already ended.
            heldKeyCode = nil
        } else {
            // Presses already handed to the app keep their release: it passes
            // through even with the pause gone, until the tap ends.
            superState.reset()
        }
    }

    /// Whether a paused recording hands this key to the app. The policy is
    /// the row take-over's own (`CommandBarRowShortcuts.passesWhilePaused`),
    /// so the tap and the panel's monitor can never drift apart.
    static func passesWhilePaused(keyCode: Int64, modifiers: GlobalShortcutModifiers) -> Bool {
        CommandBarRowShortcuts.passesWhilePaused(keyCode: keyCode, modifiers: modifiers)
    }

    /// True once every drain is over: no recorded key still draining and no
    /// key the pause passed or swallowed still owing its release. The one rule
    /// both release paths and the watchdog ask, so neither can stand the tap
    /// down while the other still holds a key.
    private static var drainIsSettled: Bool {
        drainingKeyCode == nil && pausedKeyRouter.isEmpty
    }

    /// The drain must outlive the key, not the clock: each swallowed
    /// autorepeat pushes the deadline back, so the tap dies after a second of
    /// silence instead of mid-hold, where the key's remaining repeats would
    /// reach the frontmost app as fresh presses of the recorded combination.
    /// A given battery keyboard's autorepeat pauses for up to that second
    /// when momentum restarts, so the deadline itself re-asks first: it
    /// stands the tap down only when nothing is still held, keeping the one
    /// true failure mode covered — a release or repeat lost to a switched
    /// session — without dropping a held key mid-hold.
    private static func armDrainWatchdog() {
        drainWatchdog?.cancel()
        let watchdog = DispatchWorkItem { watchdogPass() }
        drainWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: watchdog)
    }

    /// A lost release must not leave a held key held forever, and a long
    /// pause between autorepeats must not drop a held key mid-hold: the
    /// deadline asks the keyboard itself. A key the router still owes but
    /// the hardware no longer holds is a lost keyUp, not a still-held key,
    /// and its debt clears alone; a key still down keeps the tap up.
    /// `keyState` waits on a lock the main run loop itself has to service,
    /// so the read hops off main — a main-thread call here would deadlock
    /// the app, the same trap `SuperKeyService` documents — and its answer
    /// comes back to `applyKeyboardSnapshot` under the generation it was
    /// asked under.
    private static func watchdogPass() {
        guard tap != nil else { return }
        guard !drainIsSettled else { return tearDown() }
        var codes = pausedKeyRouter.owedKeyCodes
        var draining: Int64?
        if let drainingKeyCode {
            draining = drainingKeyCode
            codes.insert(drainingKeyCode)
        }
        guard !codes.isEmpty else { return }
        let generation = drainGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let keyIsDown = codes.reduce(into: [:]) { result, code in
                result[code] = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code))
            }
            DispatchQueue.main.async {
                ShortcutRecordingTap.applyKeyboardSnapshot(
                    keyIsDown: keyIsDown, draining: draining, generation: generation)
            }
        }
    }

    /// Generations name a snapshot: a read that took longer than the events
    /// it was asked about re-checks against the drain it returns to, so a
    /// late answer never drops a debt the drain has since changed. Every
    /// routed key event bumps the generation; an answer that lands stale
    /// re-arms the check instead of applying.
    private static var drainGeneration = 0

    /// Applies the keyboard's answer. Runs on main: the key codes it drops
    /// were checked against this exact generation of the drain, and events
    /// that arrived while the background read ran get to change the answer.
    private static func applyKeyboardSnapshot(keyIsDown: [Int64: Bool],
                                              draining: Int64?,
                                              generation: Int) {
        guard tap != nil else { return }
        guard generation == drainGeneration else {
            // The answer names a drain that has since changed. The events
            // that changed it re-arm the watchdog themselves, but an answer
            // can also arrive stale across a re-begin; while anything is
            // still owed, the re-check must keep coming.
            if !drainIsSettled { armDrainWatchdog() }
            return
        }
        for (keyCode, isDown) in keyIsDown where !isDown {
            if keyCode == drainingKeyCode {
                drainingKeyCode = nil
            } else {
                pausedKeyRouter.settleOwedRelease(keyCode)
            }
        }
        if drainIsSettled {
            tearDown()
        } else {
            armDrainWatchdog()
        }
    }

    private static func tearDown() {
        drainWatchdog?.cancel()
        drainWatchdog = nil
        isPaused = false
        pausedOfferID = nil
        drainingKeyCode = nil
        heldKeyCode = nil
        pausedKeyRouter.reset()
        handler = nil
        superState.reset()
        drainGeneration += 1
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { tearDown(); ShortcutCapture.end() }
            }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // The pause sits ahead of everything below. A press the policy allows
        // reaches the app and is remembered, so its release follows it; the
        // press itself is never the handler's — and after the pause ends the
        // remembered release still passes through first, so a button key
        // never lands in the recording as a fresh combination. Anything else,
        // above all the combination the question names, keeps being
        // swallowed while the offer waits.
        // The drain keeps this route alive past the recording's end: keys
        // the pause handed the app finish as pairs there (their repeats
        // suppressed, their releases forwarded) even after `end` cleared
        // the handler, so they cannot reach the bar as fresh presses.
        // That debt survives `end` on its own: the drain lives while any
        // key the pause handed over still owes its release, whether or not
        // a recorded key was left draining.
        if isPaused || handler != nil || drainingKeyCode != nil || !pausedKeyRouter.isEmpty {
            let route = pausedKeyRouter.route(
                type == .keyDown ? .down : .up,
                keyCode: keyCode,
                modifiers: GlobalShortcutModifiers(cgFlags: event.flags),
                offerID: isPaused ? pausedOfferID : nil)
            switch route {
            case .pass:
                // A fresh event invalidates a keyboard snapshot already in
                // flight. A release settles its pair; the tap stands down
                // only once every drain is over.
                drainGeneration += 1
                if handler == nil {
                    if type == .keyUp && drainIsSettled {
                        tearDown()
                    } else {
                        armDrainWatchdog()
                    }
                }
                return Unmanaged.passUnretained(event)
            case .swallow:
                // Any event may re-earn or settle a debt while a stale
                // snapshot is running, including during a newly begun capture.
                drainGeneration += 1
                if handler == nil {
                    if type == .keyDown {
                        // A repeat re-earns a debt; keep checking until release.
                        armDrainWatchdog()
                    } else {
                        // A swallowed release settles its pair; keep the tap
                        // only while another key still owes its release.
                        if drainIsSettled { tearDown() } else { armDrainWatchdog() }
                    }
                }
                return nil
            case .record: break
            }
        }
        if let handler {
            // Holding the super key while recording means the modifiers it
            // stands for, and the key holding them is never the shortcut.
            var heldModifiers: GlobalShortcutModifiers = []
            if SuperKeyService.isEngaged {
                let superEvent: SuperKeySupport.Event
                if keyCode == SuperKeySupport.triggerKeyCode {
                    let timestamp = UInt64(event.timestamp)
                    superEvent = type == .keyDown
                        ? .triggerDown(
                            isRepeat: isRepeat,
                            hasPrimaryModifiers: !GlobalShortcutModifiers(cgFlags: event.flags).isEmpty,
                            timestamp: timestamp
                        )
                        : .triggerUp(timestamp: timestamp)
                } else {
                    superEvent = .otherKey
                }
                switch superState.decide(superEvent) {
                case .swallow, .soloTap(repeated: _), .soloHold(repeated: _): return nil
                case .addModifiers: heldModifiers = SuperKeyService.shared.modifiers
                case .pass, .interceptAndRemap: break
                }
            }
            if type == .keyDown {
                heldKeyCode = keyCode
                // Autorepeats of a held key are swallowed but never re-fed:
                // the field wants the press, not a stream of it.
                if !isRepeat {
                    handler(keyCode, GlobalShortcutModifiers(cgFlags: event.flags).union(heldModifiers),
                            event.flags)
                }
            } else if keyCode == heldKeyCode {
                heldKeyCode = nil
            }
            return nil
        }
        if let drainingKeyCode, keyCode == drainingKeyCode {
            if type == .keyUp {
                // The release clears this key's drain; the tap stands down
                // only once no other key still owes its release.
                self.drainingKeyCode = nil
                drainGeneration += 1
                if drainIsSettled { tearDown() } else { armDrainWatchdog() }
            } else {
                // A re-press of the draining key re-earns its debt: a
                // snapshot already reading the keyboard as "up" must not
                // stand the drain down mid-hold.
                drainGeneration += 1
                armDrainWatchdog()
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
