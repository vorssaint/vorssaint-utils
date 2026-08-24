// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

protocol AlwaysOnTopLevelClient {
    var isAvailable: Bool { get }
    func level(of windowID: CGWindowID) -> Int32?
    func setLevel(_ level: Int32, on windowID: CGWindowID) -> Bool
}

struct AlwaysOnTopPinning {
    static let floatingLevel = Int32(NSWindow.Level.floating.rawValue)
    let client: AlwaysOnTopLevelClient

    func pin(_ windowID: CGWindowID) -> Int32? {
        guard client.isAvailable, let original = client.level(of: windowID) else { return nil }
        guard client.setLevel(Self.floatingLevel, on: windowID) else { return nil }
        return original
    }

    func unpin(_ windowID: CGWindowID, originalLevel: Int32) -> Bool {
        guard client.isAvailable else { return false }
        return client.setLevel(originalLevel, on: windowID)
    }
}

final class AlwaysOnTopStubClient: AlwaysOnTopLevelClient {
    var isAvailable: Bool
    var levels: [CGWindowID: Int32] = [:]
    var setShouldFail: Set<CGWindowID> = []

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func level(of windowID: CGWindowID) -> Int32? {
        guard isAvailable else { return nil }
        return levels[windowID]
    }

    func setLevel(_ level: Int32, on windowID: CGWindowID) -> Bool {
        guard isAvailable, !setShouldFail.contains(windowID) else { return false }
        levels[windowID] = level
        return true
    }
}

enum AlwaysOnTopSkyLightClient {
    static let shared: AlwaysOnTopLevelClient = Live()

    private struct Live: AlwaysOnTopLevelClient {
        private typealias SetLevelFn = @convention(c) (UInt32, UInt32, Int32) -> Int32
        private typealias GetLevelFn = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
        private typealias ConnectionFn = @convention(c) () -> UInt32

        private let connection: UInt32
        private let getLevel: GetLevelFn?
        private let setLevelFn: SetLevelFn?

        var isAvailable: Bool { getLevel != nil && setLevelFn != nil }

        init() {
            func symbol(_ name: String) -> UnsafeMutableRawPointer? {
                dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
            }

            let connectionSymbol = symbol("SLSMainConnectionID") ?? symbol("CGSMainConnectionID")
            if let connectionSymbol {
                connection = unsafeBitCast(connectionSymbol, to: ConnectionFn.self)()
            } else {
                connection = 0
            }

            if let set = symbol("SLSSetWindowLevel") ?? symbol("CGSSetWindowLevel") {
                setLevelFn = unsafeBitCast(set, to: SetLevelFn.self)
            } else {
                setLevelFn = nil
            }

            if let get = symbol("SLSGetWindowLevel") ?? symbol("CGSGetWindowLevel") {
                getLevel = unsafeBitCast(get, to: GetLevelFn.self)
            } else {
                getLevel = nil
            }
        }

        func level(of windowID: CGWindowID) -> Int32? {
            guard let getLevel else { return nil }
            var value: Int32 = 0
            let status = getLevel(connection, windowID, &value)
            return status == 0 ? value : nil
        }

        func setLevel(_ level: Int32, on windowID: CGWindowID) -> Bool {
            guard let setLevelFn else { return false }
            return setLevelFn(connection, windowID, level) == 0
        }
    }
}
