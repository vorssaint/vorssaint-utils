// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct AlwaysOnTopPin: Equatable {
    let windowID: CGWindowID
    let originalLevel: Int32
    let pid: pid_t
}

struct AlwaysOnTopPinMap {
    private(set) var pins: [CGWindowID: AlwaysOnTopPin] = [:]

    var isEmpty: Bool { pins.isEmpty }

    func contains(_ windowID: CGWindowID) -> Bool {
        pins[windowID] != nil
    }

    mutating func pin(_ pin: AlwaysOnTopPin) {
        pins[pin.windowID] = pin
    }

    @discardableResult
    mutating func unpin(_ windowID: CGWindowID) -> AlwaysOnTopPin? {
        pins.removeValue(forKey: windowID)
    }

    mutating func unpinAll() -> [AlwaysOnTopPin] {
        let all = Array(pins.values)
        pins.removeAll()
        return all
    }

    mutating func remove(pid: pid_t) -> [AlwaysOnTopPin] {
        let gone = pins.values.filter { $0.pid == pid }
        for pin in gone { pins.removeValue(forKey: pin.windowID) }
        return gone
    }

    func pins(for pid: pid_t) -> [AlwaysOnTopPin] {
        pins.values.filter { $0.pid == pid }
    }
}

enum AlwaysOnTopSupport {
    static func isExcluded(bundleIdentifier: String?, exceptions: [String]) -> Bool {
        AutoQuitSupport.isExcepted(bundleIdentifier: bundleIdentifier,
                                   bundleURL: nil,
                                   exceptions: exceptions)
    }

    static func windowIDsToUnpinAfterExclude(
        pins: [AlwaysOnTopPin],
        exceptions: [String],
        bundleIDForPID: (pid_t) -> String?
    ) -> [CGWindowID] {
        pins.compactMap { pin in
            isExcluded(bundleIdentifier: bundleIDForPID(pin.pid), exceptions: exceptions)
                ? pin.windowID : nil
        }
    }

    static func preferredWindowID(focused: CGWindowID?,
                                  main: CGWindowID?,
                                  first: CGWindowID?) -> CGWindowID? {
        focused ?? main ?? first
    }
}
