// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The pure half of the mouse button shortcuts feature: which buttons can
/// carry a shortcut, how the mappings persist and who owns a button when two
/// features could answer the same click.
enum MouseButtonShortcutSupport {
    /// Buttons a shortcut can live on. CoreGraphics numbers left, right and
    /// middle as 0, 1 and 2; everything from 3 up is an extra button (3 and 4
    /// are the standard Back and Forward side buttons). Left and right never
    /// arrive as extra-button events, and the middle button stays with its
    /// own feature, so mappings start at 3.
    static let buttonRange: ClosedRange<Int64> = 3...31

    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4
    /// Negative values cannot collide with CoreGraphics mouse button numbers.
    /// They let the existing persisted dictionary represent the two directions
    /// of a side wheel without adding another preference or storage format.
    static let sideWheelLeftInput: Int64 = -2
    static let sideWheelRightInput: Int64 = -1

    /// A wheel driver can emit several horizontal packets for one physical
    /// move. Keep the first packet for each direction in that burst and let a
    /// quiet gap begin a new move, without a timer or work between events.
    struct SideWheelGestureGate {
        static let quietNanoseconds: UInt64 = 250_000_000

        private var lastTimestamp: UInt64?
        private var firedDirections: UInt8 = 0

        mutating func shouldFire(_ input: Int64, at timestamp: UInt64) -> Bool {
            let bit: UInt8
            switch input {
            case MouseButtonShortcutSupport.sideWheelLeftInput: bit = 1
            case MouseButtonShortcutSupport.sideWheelRightInput: bit = 2
            default: return false
            }

            if let lastTimestamp,
               timestamp >= lastTimestamp,
               timestamp - lastTimestamp <= Self.quietNanoseconds {
                self.lastTimestamp = timestamp
            } else {
                lastTimestamp = timestamp
                firedDirections = 0
            }

            guard firedDirections & bit == 0 else { return false }
            firedDirections |= bit
            return true
        }

        mutating func reset() {
            lastTimestamp = nil
            firedDirections = 0
        }
    }

    static func canMap(_ input: Int64) -> Bool {
        input == sideWheelLeftInput
            || input == sideWheelRightInput
            || buttonRange.contains(input)
    }

    /// Whether an extra mouse button is physically down right now. This is
    /// used only to recover state after the system disabled an event tap: an
    /// Up may have bypassed the tap while it was off, so stale consumed state
    /// must survive only for buttons that are still held.
    static func isPressed(_ button: Int64, pressedButtons: Int) -> Bool {
        guard button >= 0, button < Int64(Int.bitWidth) else { return false }
        return pressedButtons & (1 << Int(button)) != 0
    }

    /// Resolves only horizontal mouse-wheel movement. Vertical scrolling stays
    /// ordinary scrolling, and the caller first excludes touch gestures.
    static func sideWheelInput(isContinuous: Bool,
                               vertical: (line: Double, fixedPoint: Double, point: Double),
                               horizontal: (line: Double, fixedPoint: Double, point: Double)) -> Int64? {
        guard vertical.line.isFinite,
              vertical.fixedPoint.isFinite,
              vertical.point.isFinite,
              horizontal.line.isFinite,
              horizontal.fixedPoint.isFinite,
              horizontal.point.isFinite else { return nil }
        let verticalDelta: Double
        let horizontalDelta: Double
        if isContinuous {
            verticalDelta = vertical.point != 0
                ? vertical.point : (vertical.fixedPoint != 0 ? vertical.fixedPoint : vertical.line)
            horizontalDelta = horizontal.point != 0
                ? horizontal.point : (horizontal.fixedPoint != 0 ? horizontal.fixedPoint : horizontal.line)
        } else {
            verticalDelta = vertical.fixedPoint != 0
                ? vertical.fixedPoint : (vertical.line != 0 ? vertical.line : vertical.point)
            horizontalDelta = horizontal.fixedPoint != 0
                ? horizontal.fixedPoint : (horizontal.line != 0 ? horizontal.line : horizontal.point)
        }
        guard horizontalDelta != 0, abs(horizontalDelta) > abs(verticalDelta) else { return nil }
        // AppKit defines a positive horizontal delta as movement to the left.
        return horizontalDelta > 0 ? sideWheelLeftInput : sideWheelRightInput
    }

    /// Mappings persist as a plain dictionary of button number to the same
    /// storage form every other shortcut in the app uses. Anything that does
    /// not parse (a hand-edited plist, an imported backup from a newer
    /// version) is dropped rather than trusted.
    static func decode(_ raw: [String: String]?) -> [Int64: GlobalShortcut] {
        guard let raw else { return [:] }
        var mappings: [Int64: GlobalShortcut] = [:]
        for (key, value) in raw {
            guard let button = Int64(key), canMap(button),
                  let shortcut = GlobalShortcut(storageValue: value) else { continue }
            mappings[button] = shortcut
        }
        return mappings
    }

    static func encode(_ mappings: [Int64: GlobalShortcut]) -> [String: String] {
        var raw: [String: String] = [:]
        for (button, shortcut) in mappings where canMap(button) {
            raw[String(button)] = shortcut.storageValue
        }
        return raw
    }

    /// Whether a button fires its shortcut right now, given plain readers so
    /// the rule is testable without touching real defaults. The radial menu
    /// keeps its summoner: a wheel button never doubles as a shortcut.
    static func firesShortcut(for button: Int64,
                              isAvailable: Bool,
                              isEnabled: Bool,
                              mappings: [Int64: GlobalShortcut],
                              claimedByWheel: (Int64) -> Bool) -> GlobalShortcut? {
        guard isAvailable, isEnabled, !claimedByWheel(button) else { return nil }
        return mappings[button]
    }

    /// Whether this feature currently owns the button, for either of the two
    /// jobs it can give one: pressing a shortcut, or driving the Spaces and
    /// Mission Control drag. Mouse navigation asks this from its own tap and
    /// lets an owned button through, the same contract it already keeps with
    /// the radial menu; pure defaults reads, so asking never wakes the
    /// service.
    static func claimsButton(_ button: Int64) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
              !RadialMenuSupport.claimsMouseButton(button) else { return false }
        // Runs inside a HID tap callback during side-button drags: look up
        // just this button's entry instead of decoding the whole dictionary.
        guard canMap(button) else { return false }
        return hasActiveShortcut(button, defaults) || spacesGestureButton(defaults) == button
    }

    /// The button the Spaces and Mission Control drag is bound to right now,
    /// or nil when the gesture is off, unbound, or the button already belongs
    /// to a shortcut or to the radial menu. Defaults reads only, so both taps
    /// can ask on the hot path.
    static func spacesGestureButton(_ defaults: UserDefaults = .standard) -> Int64? {
        MouseSpacesGestureSupport.boundButton(
            isAvailable: defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
            isEnabled: defaults.bool(forKey: DefaultsKey.mouseSpacesGestureEnabled),
            button: Int64(defaults.integer(forKey: DefaultsKey.mouseSpacesGestureButton)),
            hasShortcut: { hasActiveShortcut($0, defaults) },
            claimedByWheel: RadialMenuSupport.claimsMouseButton)
    }

    /// A stored shortcut that would really fire. A mapping left behind while
    /// the shortcut switch is off is inert, so it holds no claim on a button.
    private static func hasActiveShortcut(_ button: Int64, _ defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled) else { return false }
        let raw = defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String]
        guard let stored = raw?[String(button)] else { return false }
        return GlobalShortcut(storageValue: stored) != nil
    }

    /// The rows in Settings sort by button number so the list never reorders
    /// itself between visits.
    static func sortedButtons(_ mappings: [Int64: GlobalShortcut]) -> [Int64] {
        mappings.keys.sorted()
    }

    /// What a button is called across the feature: the two standard side
    /// buttons by their job, anything above by the count printed on mouse
    /// software (button number 5 is the sixth button of the mouse).
    static func buttonName(for button: Int64, strings: MouseButtonFeatureStrings) -> String {
        switch button {
        case sideWheelLeftInput: return strings.sideWheelLeftName
        case sideWheelRightInput: return strings.sideWheelRightName
        case backButtonNumber: return strings.backButtonName
        case forwardButtonNumber: return strings.forwardButtonName
        default: return String(format: strings.otherButtonFormat, Int(button) + 1)
        }
    }
}
