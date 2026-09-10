// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

enum MouseButtonAction: String, CaseIterable, Hashable {
    case shortcut
    case volumeUp
    case volumeDown
    case volumeMute
    case mediaPlayPause
    case mediaPrevious
    case mediaNext
    case mediaFastForward
    case mediaRewind
    case displayBrightnessUp
    case displayBrightnessDown
    case keyboardBrightnessUp
    case keyboardBrightnessDown
    case missionControl
    case appExpose
    case launchpad
    case showDesktop
    case spaceLeft
    case spaceRight
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight

    var repeatsWhileHeld: Bool {
        switch self {
        case .volumeUp, .volumeDown, .displayBrightnessUp, .displayBrightnessDown,
             .keyboardBrightnessUp, .keyboardBrightnessDown: return true
        default: return false
        }
    }

    func title(in strings: MouseButtonFeatureStrings) -> String {
        switch self {
        case .shortcut: return strings.actionShortcut
        case .volumeUp: return strings.actionVolumeUp
        case .volumeDown: return strings.actionVolumeDown
        case .volumeMute: return strings.actionVolumeMute
        case .mediaPlayPause: return strings.actionMediaPlayPause
        case .mediaPrevious: return strings.actionMediaPrevious
        case .mediaNext: return strings.actionMediaNext
        case .mediaFastForward: return strings.actionMediaFastForward
        case .mediaRewind: return strings.actionMediaRewind
        case .displayBrightnessUp: return strings.actionDisplayBrightnessUp
        case .displayBrightnessDown: return strings.actionDisplayBrightnessDown
        case .keyboardBrightnessUp: return strings.actionKeyboardBrightnessUp
        case .keyboardBrightnessDown: return strings.actionKeyboardBrightnessDown
        case .missionControl: return strings.actionMissionControl
        case .appExpose: return strings.actionAppExpose
        case .launchpad: return strings.actionLaunchpad
        case .showDesktop: return strings.actionShowDesktop
        case .spaceLeft: return strings.actionSpaceLeft
        case .spaceRight: return strings.actionSpaceRight
        case .scrollUp: return strings.actionScrollUp
        case .scrollDown: return strings.actionScrollDown
        case .scrollLeft: return strings.actionScrollLeft
        case .scrollRight: return strings.actionScrollRight
        }
    }
}

/// The system-defined media-key values macOS uses for the controls exposed in
/// this picker. They match the documented NX_KEYTYPE ordering used by macOS.
enum MouseButtonSystemKey: Int32 {
    case volumeUp = 0
    case volumeDown = 1
    case displayBrightnessUp = 2
    case displayBrightnessDown = 3
    case mute = 7
    case playPause = 16
    case next = 17
    case previous = 18
    case fastForward = 19
    case rewind = 20
    case keyboardBrightnessUp = 21
    case keyboardBrightnessDown = 22
}

/// Desktop navigation belongs to the Dock and WindowServer rather than to a
/// fixed set of function keys. Sending F3/F4 or Control+Arrow directly is
/// fragile: the user may have changed the bindings, and a synthetic key event
/// without matching modifier transitions is not always recognised as a system
/// hot key. Resolve the system entry points at runtime so these actions retain
/// the same behaviour as their native macOS counterparts.
enum MouseButtonDesktopAction {
    case missionControl
    case appExpose
    case launchpad
    case showDesktop
    case spaceLeft
    case spaceRight

    private typealias DockNotification = @convention(c) (CFString, Int32) -> Int32

    private static let applicationServicesHandle = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)

    private static let sendDockNotification: DockNotification? = symbol("CoreDockSendNotification")

    static func perform(_ action: MouseButtonDesktopAction) {
        switch action {
        case .missionControl:
            _ = sendDockNotification?("com.apple.expose.awake" as CFString, 0)
        case .appExpose:
            _ = sendDockNotification?("com.apple.expose.front.awake" as CFString, 0)
        case .launchpad:
            _ = sendDockNotification?("com.apple.launchpad.toggle" as CFString, 0)
        case .showDesktop:
            _ = sendDockNotification?("com.apple.showdesktop.awake" as CFString, 0)
        case .spaceLeft:
            pressSpaceShortcut(.left)
        case .spaceRight:
            pressSpaceShortcut(.right)
        }
    }

    /// Reuse the project's WindowServer wrapper so custom Spaces shortcuts
    /// and a deliberately disabled system shortcut keep their existing
    /// semantics.
    private static func pressSpaceShortcut(_ direction: SpaceWindowBridge.SpaceDirection) {
        guard let shortcut = SpaceWindowBridge.spaceShortcut(direction) else { return }
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let applicationServicesHandle,
              let pointer = dlsym(applicationServicesHandle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

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
    /// Existing shortcut mappings remain in their original preference. The
    /// second dictionary only records direct actions, so older versions still
    /// understand every shortcut they created.
    static func decode(shortcuts rawShortcuts: [String: String]?,
                       actions rawActions: [String: String]?) -> [Int64: MouseButtonAction] {
        var mappings: [Int64: MouseButtonAction] = [:]
        for (key, value) in rawShortcuts ?? [:] {
            guard let button = Int64(key), canMap(button),
                  GlobalShortcut(storageValue: value) != nil else { continue }
            mappings[button] = .shortcut
        }
        for (key, value) in rawActions ?? [:] {
            guard let button = Int64(key), canMap(button),
                  let action = MouseButtonAction(rawValue: value), action != .shortcut else { continue }
            mappings[button] = action
        }
        return mappings
    }

    static func shortcut(for button: Int64, in raw: [String: String]?) -> GlobalShortcut? {
        guard let stored = raw?[String(button)] else { return nil }
        return GlobalShortcut(storageValue: stored)
    }

    static func encodeActions(_ mappings: [Int64: MouseButtonAction]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: mappings.compactMap { button, action in
            guard canMap(button), action != .shortcut else { return nil }
            return (String(button), action.rawValue)
        })
    }

    static func decodeRepeatingActions(_ raw: [String: Bool]?,
                                       mappings: [Int64: MouseButtonAction]) -> Set<Int64> {
        Set((raw ?? [:]).compactMap { button, repeats in
            guard repeats, let input = Int64(button),
                  mappings[input]?.repeatsWhileHeld == true else { return nil }
            return input
        })
    }

    static func encodeRepeatingActions(_ buttons: Set<Int64>,
                                       mappings: [Int64: MouseButtonAction]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: buttons.compactMap { button in
            guard mappings[button]?.repeatsWhileHeld == true else { return nil }
            return (String(button), true)
        })
    }

    // Kept for callers and tests of the original shortcut-only persistence.
    static func decode(_ raw: [String: String]?) -> [Int64: GlobalShortcut] {
        Dictionary(uniqueKeysWithValues: (raw ?? [:]).compactMap { key, value in
            guard let button = Int64(key), canMap(button),
                  let shortcut = GlobalShortcut(storageValue: value) else { return nil }
            return (button, shortcut)
        })
    }

    static func encode(_ mappings: [Int64: GlobalShortcut]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: mappings.compactMap { button, shortcut in
            guard canMap(button) else { return nil }
            return (String(button), shortcut.storageValue)
        })
    }

    /// Whether a button fires its shortcut right now, given plain readers so
    /// the rule is testable without touching real defaults. The radial menu
    /// keeps its summoner: a wheel button never doubles as a shortcut.
    static func action(for button: Int64,
                       isAvailable: Bool,
                       isEnabled: Bool,
                       mappings: [Int64: MouseButtonAction],
                       claimedByWheel: (Int64) -> Bool) -> MouseButtonAction? {
        guard isAvailable, isEnabled, !claimedByWheel(button) else { return nil }
        return mappings[button]
    }

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
        return hasActiveAction(button, defaults) || spacesGestureButton(defaults) == button
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
            hasShortcut: { hasActiveAction($0, defaults) },
            claimedByWheel: RadialMenuSupport.claimsMouseButton)
    }

    /// A stored action that would really fire. A mapping left behind while
    /// the switch is off is inert, so it holds no claim on a button.
    private static func hasActiveAction(_ button: Int64, _ defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled) else { return false }
        let shortcuts = defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String]
        let actions = defaults.dictionary(forKey: DefaultsKey.mouseButtonActions) as? [String: String]
        return decode(shortcuts: shortcuts, actions: actions)[button] != nil
    }

    /// The rows in Settings sort by button number so the list never reorders
    /// itself between visits.
    static func sortedButtons<Value>(_ mappings: [Int64: Value]) -> [Int64] {
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
