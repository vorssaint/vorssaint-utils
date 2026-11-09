// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// The press interpreter below is ported from NythralHome/globe (MIT License,
// Copyright (c) 2026 Globe contributors) and relicensed as GPL-3.0-or-later
// as part of this project.

import Foundation

/// A gesture the Globe key recognizes. Presses are counted, so one press and
/// two presses are different actions by design: the switch lands on the
/// layout the gesture names, never on whatever comes next in the list.
enum GlobeGesture: String, CaseIterable, Identifiable {
    case singlePress, doublePress, triplePress, longPress

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> GlobeGesture {
        raw.flatMap(GlobeGesture.init(rawValue:)) ?? .singlePress
    }
}

/// What one gesture does. A stored input source id is only validated when the
/// gesture fires: `InputSourceSelection.select` answers false for a source
/// that is no longer enabled, and a removed layout must not disable the rest.
enum GlobeKeyAction: Hashable {
    case none
    case inputSource(id: String)
    case openKeyboardSettings

    static func sanitized(_ raw: String?) -> GlobeKeyAction {
        guard let raw else { return .none }
        if raw == Self.openKeyboardSettingsToken { return .openKeyboardSettings }
        if raw.hasPrefix(Self.inputSourceToken) {
            let id = String(raw.dropFirst(Self.inputSourceToken.count))
            if !id.isEmpty { return .inputSource(id: id) }
        }
        return .none
    }

    var storageValue: String {
        switch self {
        case .none: ""
        case .openKeyboardSettings: Self.openKeyboardSettingsToken
        case .inputSource(let id): Self.inputSourceToken + id
        }
    }

    private static let inputSourceToken = "inputSource:"
    private static let openKeyboardSettingsToken = "openKeyboardSettings"
}

/// The gesture-to-action table. Defaults mirror NythralHome/globe: gestures
/// start inert and a long press opens the keyboard settings, which is also
/// where the "Press Globe key to" prerequisite lives.
struct GlobeGestureMapping: Equatable {
    var singlePress: GlobeKeyAction
    var doublePress: GlobeKeyAction
    var triplePress: GlobeKeyAction
    var longPress: GlobeKeyAction

    static let fallback = GlobeGestureMapping(
        singlePress: .none,
        doublePress: .none,
        triplePress: .none,
        longPress: .openKeyboardSettings
    )

    func action(for gesture: GlobeGesture) -> GlobeKeyAction {
        switch gesture {
        case .singlePress: singlePress
        case .doublePress: doublePress
        case .triplePress: triplePress
        case .longPress: longPress
        }
    }

    /// The gestures whose action is a fixed input source, in display order,
    /// so the service can check early whether the feature has anything to do.
    var configuredSourceIDs: [String] {
        [singlePress, doublePress, triplePress, longPress].compactMap {
            if case .inputSource(let id) = $0 { return id }
            return nil
        }
    }
}

/// Gesture timing, in nanoseconds of uptime so it shares the clock the event
/// timestamps live on. The values are NythralHome/globe's defaults.
struct GlobePressTiming: Equatable {
    /// How long the interpreter waits after a release to see whether another
    /// press joins it. This is also the latency of a single press.
    var multiPressTimeout: UInt64
    /// How long the key must stay down to become a long press.
    var longPressDuration: UInt64

    static let `default` = GlobePressTiming(
        multiPressTimeout: 300_000_000,
        longPressDuration: 700_000_000
    )
}

/// The pure press-count interpreter: key down, key up and timer ticks go in,
/// recognized gestures come out. Timestamps are nanoseconds of uptime, the
/// clock `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` and Quartz event
/// timestamps share.
///
/// Ported from NythralHome/globe with the timestamp type swapped from Date to
/// uptime nanoseconds; the behavior is theirs, including the parts the tests
/// pin: a press whose release carries the count past three fires at once, a
/// long press fires on release or on its own deadline, and a press that sits
/// past its timeout finalizes on the next key down instead of merging into
/// the press that follows it.
struct GlobePressInterpreter: Equatable {
    enum Input: Equatable {
        case keyDown(UInt64)
        case keyUp(UInt64)
        case timer(UInt64)
    }

    enum Action: Equatable {
        case singlePress, doublePress, triplePress, longPress
    }

    private(set) var keyDownTimestamp: UInt64?
    private(set) var pressCount = 0
    private(set) var deadline: UInt64?
    private let timing: GlobePressTiming

    init(timing: GlobePressTiming = .default) {
        self.timing = timing
    }

    /// The next moment a timer tick can change anything, or nil when nothing
    /// is in flight. The service schedules exactly one timer for it.
    var pendingDeadline: UInt64? {
        keyDownTimestamp.map { $0 &+ timing.longPressDuration } ?? deadline
    }

    /// True while a press is down or a finished press waits for company.
    var isPending: Bool { keyDownTimestamp != nil || deadline != nil }

    mutating func handle(_ input: Input) -> [Action] {
        switch input {
        case .keyDown(let timestamp):
            return handleKeyDown(at: timestamp)
        case .keyUp(let timestamp):
            return handleKeyUp(at: timestamp)
        case .timer(let timestamp):
            return handleTimer(at: timestamp)
        }
    }

    mutating func reset() {
        keyDownTimestamp = nil
        pressCount = 0
        deadline = nil
    }

    private mutating func handleKeyDown(at timestamp: UInt64) -> [Action] {
        guard keyDownTimestamp == nil else {
            return []
        }
        if let deadline, timestamp > deadline {
            let actions = finalizePendingPresses()
            keyDownTimestamp = timestamp
            return actions
        }
        keyDownTimestamp = timestamp
        return []
    }

    private mutating func handleKeyUp(at timestamp: UInt64) -> [Action] {
        guard let downTimestamp = keyDownTimestamp else {
            return []
        }
        keyDownTimestamp = nil
        if Self.duration(from: downTimestamp, to: timestamp) >= timing.longPressDuration {
            reset()
            return [.longPress]
        }
        pressCount += 1
        deadline = timestamp &+ timing.multiPressTimeout
        if pressCount >= 3 {
            reset()
            return [.triplePress]
        }
        return []
    }

    private mutating func handleTimer(at timestamp: UInt64) -> [Action] {
        if let downTimestamp = keyDownTimestamp,
           Self.duration(from: downTimestamp, to: timestamp) >= timing.longPressDuration {
            reset()
            return [.longPress]
        }
        guard let deadline, timestamp >= deadline else {
            return []
        }
        return finalizePendingPresses()
    }

    private mutating func finalizePendingPresses() -> [Action] {
        let count = pressCount
        reset()
        switch count {
        case 1:
            return [.singlePress]
        case 2:
            return [.doublePress]
        case 3...:
            return [.triplePress]
        default:
            return []
        }
    }

    /// Uptime nanoseconds never go backwards inside one tap's events, but a
    /// hand-built test or a clock source hiccup must subtract safely anyway.
    static func duration(from start: UInt64, to end: UInt64) -> UInt64 {
        end >= start ? end - start : 0
    }
}

/// What the tap saw, reduced to the distinctions the tracker needs. The key
/// code never crosses this boundary: the Globe key is recognized by its
/// `maskSecondaryFn` flag transitions, which is how the system reports the
/// key both MacBooks and external keyboards share.
enum GlobeKeyEvent: Equatable {
    /// The Globe key went down. `hasPrimaryModifiers` says whether a real
    /// modifier (Control, Option, Shift or Command) was already held.
    case fnDown(hasPrimaryModifiers: Bool, timestamp: UInt64)
    /// The Globe key came back up.
    case fnUp(timestamp: UInt64)
    /// Anything else the tap watches: another key going down or up, another
    /// modifier changing, or a system-defined event such as a media key.
    case otherEvent
}

/// The pure half of the feature around the interpreter: which Globe key
/// events deserve to reach it, and when the whole gesture must be forgotten.
///
/// This is where the port deliberately diverges from NythralHome/globe.
/// Their monitor feeds the interpreter every fn flag transition, so a chord
/// like Globe+arrow (Home) or Globe+media key adjusts the volume AND lands as
/// a single press. Here any other key, modifier or system-defined event while
/// the Globe key is down cancels the press, and typing during the wait
/// between presses cancels the pending count instead of switching the layout
/// under the next character.
struct GlobeKeyMachine: Equatable {
    private(set) var interpreter = GlobePressInterpreter()
    private(set) var fnIsDown = false
    /// The press in progress started as a chord (or became one), so its
    /// release must not reach the interpreter as a key up.
    private(set) var chordedPress = false

    var pendingDeadline: UInt64? { interpreter.pendingDeadline }
    var isPending: Bool { interpreter.isPending }

    /// Feeds one tap event in and answers the interpreter actions it produced.
    mutating func handle(_ event: GlobeKeyEvent) -> [GlobePressInterpreter.Action] {
        switch event {
        case .fnDown(let hasPrimaryModifiers, let timestamp):
            guard !fnIsDown else { return [] }
            fnIsDown = true
            if hasPrimaryModifiers {
                return cancelPending(chorded: true)
            }
            chordedPress = false
            return interpreter.handle(.keyDown(timestamp))
        case .fnUp(let timestamp):
            guard fnIsDown else { return [] }
            fnIsDown = false
            if chordedPress {
                chordedPress = false
                return cancelPending(chorded: false)
            }
            return interpreter.handle(.keyUp(timestamp))
        case .otherEvent:
            if fnIsDown {
                chordedPress = true
                return cancelPending(chorded: false)
            }
            if interpreter.isPending {
                return cancelPending(chorded: false)
            }
            return []
        }
    }

    /// A timer tick for the deadline `pendingDeadline` published. Ticks are
    /// not tap events: they arrive from the service's scheduled timer, and a
    /// tick after a chord or a reset finds nothing pending and stays silent.
    mutating func tick(at timestamp: UInt64) -> [GlobePressInterpreter.Action] {
        interpreter.handle(.timer(timestamp))
    }

    /// Forgets everything: the tap went away, the session ended, or the
    /// feature turned off while the key was held.
    mutating func reset() {
        fnIsDown = false
        chordedPress = false
        interpreter.reset()
    }

    private mutating func cancelPending(chorded: Bool) -> [GlobePressInterpreter.Action] {
        if chorded || interpreter.isPending {
            interpreter.reset()
        }
        return []
    }
}
