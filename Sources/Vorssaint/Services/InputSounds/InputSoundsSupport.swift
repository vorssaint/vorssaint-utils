// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// What the input sounds do, read once from preferences per change so the
/// event tap never touches UserDefaults.
struct InputSoundsConfig: Equatable {
    var clicksEnabled = true
    var keyboardEnabled = false
    var scrollEnabled = false
    var doubleClickEnabled = false
    var longPressEnabled = false
    var dragEnabled = false
    var stereoEnabled = false
    var modifierKeysEnabled = true
    var typingComboEnabled = false
    var quietDuringMicrophone = true
    var clickPackID = InputSoundLibrary.defaultPackID
    var keyboardPackID = "desk.thock"
    var scrollStyle = InputScrollStyle.tick
    var clickVolume = Defaults.defaultInputSoundsVolume
    var keyboardVolume = Defaults.defaultInputSoundsVolume
    var quietBundleIDs: Set<String> = []

    static func load(from defaults: UserDefaults = .standard) -> InputSoundsConfig {
        InputSoundsConfig(
            clicksEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsClicks),
            keyboardEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsKeyboard),
            scrollEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsScroll),
            doubleClickEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsDoubleClick),
            longPressEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsLongPress),
            dragEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsDrag),
            stereoEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsStereo),
            modifierKeysEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsModifierKeys),
            typingComboEnabled: defaults.bool(forKey: DefaultsKey.inputSoundsTypingCombo),
            quietDuringMicrophone: defaults.bool(forKey: DefaultsKey.inputSoundsQuietDuringMicrophone),
            clickPackID: InputSoundsSupport.sanitizedPackID(
                defaults.string(forKey: DefaultsKey.inputSoundsClickPack),
                fallback: InputSoundLibrary.defaultPackID),
            keyboardPackID: InputSoundsSupport.sanitizedPackID(
                defaults.string(forKey: DefaultsKey.inputSoundsKeyboardPack),
                fallback: "desk.thock"),
            scrollStyle: InputScrollStyle(
                rawValue: defaults.string(forKey: DefaultsKey.inputSoundsScrollStyle) ?? "") ?? .tick,
            clickVolume: Defaults.sanitizedInputSoundsVolume(
                defaults.double(forKey: DefaultsKey.inputSoundsVolume)),
            keyboardVolume: Defaults.sanitizedInputSoundsVolume(
                defaults.double(forKey: DefaultsKey.inputSoundsKeyboardVolume)),
            quietBundleIDs: Set(InputSoundsSupport.decodeBundleIDs(
                defaults.string(forKey: DefaultsKey.inputSoundsQuietApps)))
        )
    }

    /// Whether any sound is wanted at all; nothing wanted means no tap.
    var wantsAnything: Bool {
        clicksEnabled || keyboardEnabled || scrollEnabled
    }

    var wantsKeyboardEvents: Bool {
        keyboardEnabled || typingComboEnabled
    }
}

/// The recordings a user can supply in place of the synthesized sounds.
enum InputSoundCustomSlot: String, CaseIterable, Identifiable {
    case press, release, scroll

    var id: String { rawValue }
}

/// A sound the service should play, decided without any audio running so
/// the rules stay testable.
enum InputSoundCue: Equatable {
    case clickPress(button: Int)
    case clickRelease(button: Int)
    case doubleClick
    case longPress
    case dragStart
    case drop
    case key(InputKeyKind, isRelease: Bool)
    case scrollTick
    case combo(step: Int)
}

enum InputSoundsSupport {
    /// Custom recordings are kept under this pack id.
    static let customPackID = "custom"

    /// Clicks, drags and scrolls always; keys only while a key sound wants
    /// them, so a click-only setup never listens to the keyboard at all.
    static func eventMask(for config: InputSoundsConfig) -> CGEventMask {
        var types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged,
        ]
        if config.scrollEnabled { types.append(.scrollWheel) }
        if config.wantsKeyboardEvents { types += [.keyDown, .keyUp, .flagsChanged] }
        return ListenOnlyEventTap.mask(types)
    }

    static func sanitizedPackID(_ raw: String?, fallback: String) -> String {
        guard let raw else { return fallback }
        if raw == customPackID { return raw }
        return InputSoundLibrary.pack(id: raw) == nil ? fallback : raw
    }

    // MARK: Keys

    /// The kind of a key from its virtual key code. Only the kind is ever
    /// passed on; the code itself is dropped right here.
    static func keyKind(keyCode: Int64) -> InputKeyKind {
        switch keyCode {
        case 49: return .space
        case 36, 76: return .returnKey // Return, keypad Enter
        case 51, 117: return .delete // Delete, forward delete
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: return .modifier
        default: return .regular
        }
    }

    /// Whether a flags-changed event is a modifier going down. The event
    /// carries the key code and the flags after the change, so a key whose
    /// own flag is now set was just pressed.
    static func modifierIsDown(keyCode: Int64, flags: CGEventFlags) -> Bool? {
        switch keyCode {
        case 56, 60: return flags.contains(.maskShift)
        case 59, 62: return flags.contains(.maskControl)
        case 58, 61: return flags.contains(.maskAlternate)
        case 54, 55: return flags.contains(.maskCommand)
        case 57: return flags.contains(.maskAlphaShift)
        case 63: return flags.contains(.maskSecondaryFn)
        default: return nil
        }
    }

    // MARK: Stereo

    /// Left-right placement for a pointer at `x` across `bounds`, kept away
    /// from the hard edges so one ear never carries a sound alone.
    static func pan(pointerX x: CGFloat, across bounds: CGRect) -> Float {
        guard bounds.width > 0 else { return 0 }
        let position = (x - bounds.minX) / bounds.width
        let centered = max(-1, min(1, position * 2 - 1))
        return Float(centered * 0.75)
    }

    // MARK: Quiet apps

    static func decodeBundleIDs(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        var seen = Set<String>()
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encodeBundleIDs(_ ids: [String]) -> String {
        decodeBundleIDs(ids.joined(separator: "\n")).joined(separator: "\n")
    }

    /// Whether sounds should hold back right now.
    static func shouldStayQuiet(config: InputSoundsConfig,
                                frontmostBundleID: String?,
                                microphoneInUse: Bool) -> Bool {
        if config.quietDuringMicrophone, microphoneInUse { return true }
        if let frontmostBundleID, config.quietBundleIDs.contains(frontmostBundleID) { return true }
        return false
    }
}

/// Paces scroll ticks. A wheel notch is one tick; a trackpad or free-spinning
/// wheel sends a stream of small deltas, which are summed so a tick plays per
/// stretch of travel, never faster than the ear can separate.
struct InputScrollTicker {
    static let pixelsPerTick: Double = 48
    static let minimumIntervalNanoseconds: UInt64 = 28_000_000

    private var accumulated: Double = 0
    private var lastTick: UInt64?

    mutating func reset() {
        accumulated = 0
        lastTick = nil
    }

    /// `isContinuous` is the event's own flag for pixel-precise devices.
    /// `momentum` events coast after a swipe and stay silent.
    mutating func shouldTick(delta: Double, isContinuous: Bool, isMomentum: Bool,
                             timestamp: UInt64) -> Bool {
        guard !isMomentum, delta != 0 else { return false }
        if let lastTick, timestamp < lastTick { reset() }
        let ready: Bool
        if isContinuous {
            accumulated += abs(delta)
            ready = accumulated >= Self.pixelsPerTick
        } else {
            ready = true
        }
        guard ready else { return false }
        if let lastTick, timestamp - lastTick < Self.minimumIntervalNanoseconds { return false }
        accumulated = 0
        lastTick = timestamp
        return true
    }
}

/// Typing combos: a fast, steady run of keys earns a chime, one note higher
/// for every stretch the run keeps going. A pause ends the run.
struct InputTypingCombo {
    static let keysPerStep = 24
    static let maximumGapNanoseconds: UInt64 = 450_000_000
    /// The run's average gap must stay under this to count as fast.
    static let fastAverageNanoseconds: UInt64 = 210_000_000
    static let maximumStep = 14

    private var runStart: UInt64?
    private var lastKey: UInt64?
    private var keys = 0
    private(set) var step = 0

    mutating func reset() {
        runStart = nil
        lastKey = nil
        keys = 0
        step = 0
    }

    /// Records a key press and returns the chime step it earned, if any.
    mutating func registerKey(at timestamp: UInt64) -> Int? {
        if let lastKey, timestamp < lastKey || timestamp - lastKey > Self.maximumGapNanoseconds {
            reset()
        }
        if runStart == nil { runStart = timestamp }
        lastKey = timestamp
        keys += 1
        guard keys >= Self.keysPerStep, let runStart else { return nil }
        let average = (timestamp - runStart) / UInt64(max(1, keys - 1))
        // The run restarts counting either way, so a slow stretch must earn
        // its next note again from scratch. This key opens the next stretch.
        keys = 1
        self.runStart = timestamp
        guard average <= Self.fastAverageNanoseconds else {
            step = 0
            return nil
        }
        let earned = step
        step = min(step + 1, Self.maximumStep)
        return earned
    }
}

/// Follows one primary press to tell a click from a long press or a drag.
struct InputPressTracker {
    static let longPressNanoseconds: UInt64 = 550_000_000
    static let dragDistance: CGFloat = 6

    private var downAt: UInt64?
    private var downPoint: CGPoint = .zero
    private(set) var isDragging = false
    private(set) var longPressPlayed = false

    var isPressed: Bool { downAt != nil }

    mutating func reset() {
        downAt = nil
        isDragging = false
        longPressPlayed = false
    }

    mutating func press(at timestamp: UInt64, point: CGPoint) {
        downAt = timestamp
        downPoint = point
        isDragging = false
        longPressPlayed = false
    }

    /// True the moment a held press first moves far enough to be a drag.
    mutating func drag(to point: CGPoint) -> Bool {
        guard downAt != nil, !isDragging else { return false }
        let distance = hypot(point.x - downPoint.x, point.y - downPoint.y)
        guard distance >= Self.dragDistance else { return false }
        isDragging = true
        return true
    }

    /// True once per press when it has been held still long enough.
    mutating func checkLongPress(now: UInt64) -> Bool {
        guard let downAt, !isDragging, !longPressPlayed, now >= downAt,
              now - downAt >= Self.longPressNanoseconds else { return false }
        longPressPlayed = true
        return true
    }

    /// Ends the press and reports whether it was a drag.
    mutating func release() -> Bool {
        let dragged = isDragging
        reset()
        return dragged
    }
}

/// One-tap setups that set the sounds and, when installed, the click
/// highlight. Raw values are persisted.
enum InputFeedbackPreset: String, CaseIterable, Identifiable {
    case standard, recording, quiet, playful, subtle

    var id: String { rawValue }

    var values: [String: Any] {
        switch self {
        case .standard:
            return [
                DefaultsKey.inputSoundsClicks: true,
                DefaultsKey.inputSoundsClickPack: "desk.crisp",
                DefaultsKey.inputSoundsKeyboard: false,
                DefaultsKey.inputSoundsScroll: false,
                DefaultsKey.inputSoundsVolume: Defaults.defaultInputSoundsVolume,
                DefaultsKey.clickHighlightRippleEnabled: false,
                DefaultsKey.clickHighlightSpotlightEnabled: false,
            ]
        case .recording:
            return [
                DefaultsKey.inputSoundsClicks: true,
                DefaultsKey.inputSoundsClickPack: "studio.tap",
                DefaultsKey.inputSoundsKeyboard: true,
                DefaultsKey.inputSoundsKeyboardPack: "desk.creamy",
                DefaultsKey.inputSoundsScroll: false,
                DefaultsKey.inputSoundsVolume: 0.6,
                DefaultsKey.clickHighlightRippleEnabled: true,
                DefaultsKey.clickHighlightStyle: ClickRippleStyle.doubleRing.rawValue,
                DefaultsKey.clickHighlightSpotlightEnabled: true,
                DefaultsKey.clickHighlightSpotlightOnlyWhileRecording: true,
            ]
        case .quiet:
            return [
                DefaultsKey.inputSoundsClicks: true,
                DefaultsKey.inputSoundsClickPack: "studio.felt",
                DefaultsKey.inputSoundsKeyboard: false,
                DefaultsKey.inputSoundsScroll: false,
                DefaultsKey.inputSoundsVolume: 0.25,
                DefaultsKey.clickHighlightRippleEnabled: false,
                DefaultsKey.clickHighlightSpotlightEnabled: false,
            ]
        case .playful:
            return [
                DefaultsKey.inputSoundsClicks: true,
                DefaultsKey.inputSoundsClickPack: "toybox.boop",
                DefaultsKey.inputSoundsKeyboard: true,
                DefaultsKey.inputSoundsKeyboardPack: "toybox.pop",
                DefaultsKey.inputSoundsScroll: true,
                DefaultsKey.inputSoundsScrollStyle: InputScrollStyle.bubble.rawValue,
                DefaultsKey.inputSoundsDoubleClick: true,
                DefaultsKey.inputSoundsDrag: true,
                DefaultsKey.inputSoundsTypingCombo: true,
                DefaultsKey.inputSoundsVolume: 0.6,
                DefaultsKey.clickHighlightRippleEnabled: true,
                DefaultsKey.clickHighlightStyle: ClickRippleStyle.glow.rawValue,
            ]
        case .subtle:
            return [
                DefaultsKey.inputSoundsClicks: true,
                DefaultsKey.inputSoundsClickPack: "studio.soft",
                DefaultsKey.inputSoundsKeyboard: true,
                DefaultsKey.inputSoundsKeyboardPack: "studio.felt",
                DefaultsKey.inputSoundsScroll: false,
                DefaultsKey.inputSoundsVolume: 0.35,
                DefaultsKey.inputSoundsKeyboardVolume: 0.3,
                DefaultsKey.clickHighlightRippleEnabled: true,
                DefaultsKey.clickHighlightStyle: ClickRippleStyle.dot.rawValue,
                DefaultsKey.clickHighlightSpotlightEnabled: false,
            ]
        }
    }

    /// Writes the preset. Highlight values only land where that feature is
    /// installed, so a preset never switches on something uninstalled.
    func apply(to defaults: UserDefaults = .standard, highlightAvailable: Bool) {
        for (key, value) in values {
            if key.hasPrefix("clickHighlight"), !highlightAvailable { continue }
            defaults.set(value, forKey: key)
        }
    }
}
