// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// One decision per physical scroll sequence. No timer is needed for wheel
/// devices without phases: the next event itself expires an old sequence.
struct NotchGestureSupport {
    enum Action: Equatable { case open, close, nextTrack, previousTrack }
    private enum Axis { case horizontal, vertical }
    private struct Origin {
        let vertical: Bool
        let horizontal: Bool
        let expanded: Bool
    }
    private var origin: Origin?
    private var axis: Axis?
    private var distance = 0.0
    private var fired = false
    private var lastTimestamp: TimeInterval?

    static func nativeInteraction(at view: NSView?) -> (control: Bool, scroll: Bool) {
        var control = false
        var scroll = false
        var view = view
        while let current = view {
            // The transparent opening button is the gesture surface itself.
            if (current is NSControl && !(current is NotchActivationButton)) || current is NSTextView {
                control = true
            }
            if current is NSScrollView { scroll = true }
            view = current.superview
        }
        return (control, scroll)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchGestures.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchGesturesEnabled)
    }

    static func movement(_ delta: Double, precise: Bool, inverted: Bool) -> Double {
        guard delta.isFinite else { return 0 }
        return delta * (inverted ? 1 : -1) * (precise ? 1 : 24)
    }

    mutating func handle(x: Double, y: Double, timestamp: TimeInterval,
                         began: Bool, ended: Bool, momentum: Bool, precise: Bool, hasPhase: Bool,
                         allowVertical: Bool, allowHorizontal: Bool, expanded: Bool) -> Action? {
        guard timestamp.isFinite, x.isFinite, y.isFinite else { self = Self(); return nil }
        if ended || momentum { self = Self(); return nil }
        if hasPhase {
            if began {
                self = Self()
                origin = Origin(vertical: allowVertical, horizontal: allowHorizontal, expanded: expanded)
            }
            // AppKit keeps a phased scroll attached to its original view.
            // A blocked beginning stays blocked, and an interrupted sequence
            // cannot restart from a later changed event under another view.
            guard origin != nil else { return nil }
            if lastTimestamp.map({ timestamp < $0 }) == true { self = Self(); return nil }
        } else if origin != nil || began
                    || lastTimestamp.map({ timestamp < $0 || timestamp - $0 > 0.35 }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        guard !fired else { return nil }
        let allowVertical = origin?.vertical ?? allowVertical
        let allowHorizontal = origin?.horizontal ?? allowHorizontal
        let expanded = origin?.expanded ?? expanded
        if axis == nil {
            if precise, allowHorizontal, abs(x) > 0.2, abs(x) >= abs(y) * 1.5 { axis = .horizontal }
            else if allowVertical, abs(y) > 0.2, abs(y) >= abs(x) * 1.5 { axis = .vertical }
            else { return nil }
        }
        switch axis {
        case .horizontal where allowHorizontal:
            distance += x
            guard abs(distance) >= 40 else { return nil }
            fired = true
            return distance < 0 ? .nextTrack : .previousTrack
        case .vertical where allowVertical:
            distance += y
            guard abs(distance) >= 24 else { return nil }
            fired = true
            if distance > 0, !expanded { return .open }
            if distance < 0, expanded { return .close }
            return nil
        default:
            return nil
        }
    }
}
