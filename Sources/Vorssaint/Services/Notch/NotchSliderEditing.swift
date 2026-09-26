// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Keyboard and accessibility actions have no mouse-tracking callbacks. They
/// form a complete edit around the value write; dragging keeps its one shared
/// edit open until the native cell finishes tracking.
struct NotchSliderEditing {
    private var tracking = false

    mutating func trackingChanged(_ value: Bool, onEditingChanged: ((Bool) -> Void)?) {
        guard tracking != value else { return }
        tracking = value
        onEditingChanged?(value)
    }

    func valueChanged(_ update: () -> Void, onEditingChanged: ((Bool) -> Void)?) {
        let callback = tracking ? nil : onEditingChanged
        callback?(true)
        update()
        callback?(false)
    }
}
