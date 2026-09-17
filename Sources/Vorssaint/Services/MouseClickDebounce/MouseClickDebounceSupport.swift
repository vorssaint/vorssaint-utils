// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct MouseClickDebounceConfig {
    let enabled: Bool
    let windowMilliseconds: Int
}

enum MouseClickDebounceEvent: Equatable {
    case down
    case dragged
    case up
}

struct MouseClickDebounceInput: Equatable {
    let button: Int64
    let event: MouseClickDebounceEvent

    /// Primary, secondary and middle clicks only. Extra buttons keep their
    /// existing navigation, shortcut and gesture ownership untouched.
    static func resolve(type: CGEventType, buttonNumber: Int64) -> MouseClickDebounceInput? {
        switch type {
        case .leftMouseDown: return MouseClickDebounceInput(button: 0, event: .down)
        case .leftMouseDragged: return MouseClickDebounceInput(button: 0, event: .dragged)
        case .leftMouseUp: return MouseClickDebounceInput(button: 0, event: .up)
        case .rightMouseDown: return MouseClickDebounceInput(button: 1, event: .down)
        case .rightMouseDragged: return MouseClickDebounceInput(button: 1, event: .dragged)
        case .rightMouseUp: return MouseClickDebounceInput(button: 1, event: .up)
        case .otherMouseDown where buttonNumber == 2:
            return MouseClickDebounceInput(button: 2, event: .down)
        case .otherMouseDragged where buttonNumber == 2:
            return MouseClickDebounceInput(button: 2, event: .dragged)
        case .otherMouseUp where buttonNumber == 2:
            return MouseClickDebounceInput(button: 2, event: .up)
        default: return nil
        }
    }
}

/// Conservative switch-bounce filtering with exact Down/Up ownership.
///
/// A healthy click passes through immediately. After its accepted Up, a new
/// Down inside the short filter window is suppressed together with its own Up.
/// The Up of an accepted Down is never suppressed, so resetting the state or
/// stopping the tap cannot leave a button held in the target app.
struct MouseClickDebounceState {
    private struct ButtonState {
        var acceptedDown = false
        var suppressedDown = false
        var lastAcceptedUp: UInt64?
        var lastEventTimestamp: UInt64?
    }

    private var stateByButton: [Int64: ButtonState] = [:]

    mutating func reset() {
        stateByButton.removeAll()
    }

    mutating func shouldSuppress(button: Int64,
                                 event: MouseClickDebounceEvent,
                                 timestampNanoseconds: UInt64,
                                 config: MouseClickDebounceConfig) -> Bool {
        guard config.enabled, (0...2).contains(button) else {
            stateByButton.removeValue(forKey: button)
            return false
        }

        var buttonState = sanitizedState(for: button, timestamp: timestampNanoseconds)
        defer {
            buttonState.lastEventTimestamp = timestampNanoseconds
            stateByButton[button] = buttonState
        }

        switch event {
        case .down:
            // Repeated Down while the accepted press is still held is noise,
            // but its eventual Up still belongs to that accepted press.
            if buttonState.acceptedDown {
                return true
            }
            // More Down packets can arrive before the Up paired with a click
            // already identified as bounce. They share the same suppressed Up.
            if buttonState.suppressedDown {
                return true
            }

            let window = UInt64(max(0, config.windowMilliseconds)) * 1_000_000
            if let release = buttonState.lastAcceptedUp,
               timestampNanoseconds >= release,
               timestampNanoseconds - release < window {
                buttonState.suppressedDown = true
                return true
            }

            buttonState.acceptedDown = true
            return false

        case .dragged:
            // A suppressed Down must also own its drag packets; otherwise the
            // target app would receive a drag with no matching press.
            return buttonState.suppressedDown

        case .up:
            if buttonState.suppressedDown {
                buttonState.suppressedDown = false
                return true
            }
            guard buttonState.acceptedDown else {
                // An unmatched Up may be recovery from a disabled tap. Passing
                // it through is the only fail-open choice and cannot stick.
                return false
            }
            buttonState.acceptedDown = false
            buttonState.lastAcceptedUp = timestampNanoseconds
            return false
        }
    }

    private func sanitizedState(for button: Int64,
                                timestamp: UInt64) -> ButtonState {
        var state = stateByButton[button] ?? ButtonState()
        guard let previous = state.lastEventTimestamp else { return state }
        if timestamp < previous {
            state = ButtonState()
        }
        return state
    }
}
