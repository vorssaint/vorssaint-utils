// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum InstantSpacesSupport {
    enum Action: Equatable {
        case step(Int)
        case desktop(Int)
        case cycle
    }

    static let shortcutIDs: Set<Int32> = Set([79, 81] + Array(118...127))

    static func action(keyCode: Int64, flags: CGEventFlags,
                       shortcuts: [LiveSystemShortcut]) -> Action? {
        let modifiers = GlobalShortcutModifiers(cgFlags: flags)
        guard let entry = shortcuts.first(where: {
            $0.enabled && $0.shortcut.matches(keyCode: keyCode, modifiers: modifiers)
                && (!$0.requiresFunctionKey || flags.contains(.maskSecondaryFn))
                && ($0.id < 118 || !$0.shortcut.modifiers.isEmpty)
        }) else { return nil }
        switch entry.id {
        case 79: return .step(-1)
        case 81: return .step(1)
        case 118...127: return .desktop(Int(entry.id - 118))
        default: return nil
        }
    }

    static func destination(in spaces: [UInt64], current: UInt64,
                            direction: Int) -> UInt64? {
        guard direction == -1 || direction == 1, let index = spaces.firstIndex(of: current),
              spaces.indices.contains(index + direction) else { return nil }
        return spaces[index + direction]
    }

    static func cycleDestination(in spaces: [UInt64], current: UInt64) -> UInt64? {
        guard spaces.count > 1, let index = spaces.firstIndex(of: current) else { return nil }
        return spaces[(index + 1) % spaces.count]
    }

    /// A bare Fn tap is committed on release. A chord or repeated flags event
    /// must never turn Fn-arrow navigation into a Space switch.
    struct FnPress {
        private(set) var isDown = false
        private var chorded = false

        mutating func begin(flags: CGEventFlags) {
            guard !isDown else { return }
            isDown = true
            chorded = !GlobalShortcutModifiers(cgFlags: flags).isEmpty
        }

        mutating func markChorded() {
            if isDown { chorded = true }
        }

        mutating func finish() -> Bool {
            let bare = isDown && !chorded
            self = FnPress()
            return bare
        }
    }

    /// One intent per direction, with enough return travel to distinguish a
    /// deliberate reversal from fingers settling at the end of a swipe.
    struct Swipe {
        private(set) var direction = 0
        private var extreme = 0.0

        mutating func update(progress: Double) -> Int? {
            guard progress.isFinite else { return nil }
            if direction == 0 {
                guard abs(progress) >= 0.05 else { return nil }
                direction = progress > 0 ? 1 : -1
            } else {
                extreme = direction > 0 ? max(extreme, progress) : min(extreme, progress)
                guard (progress - extreme) * Double(direction) <= -0.2 else { return nil }
                direction = -direction
            }
            extreme = progress
            return direction
        }

        func finish(velocity: Double) -> Int? {
            guard direction == 0, velocity.isFinite, velocity != 0 else { return nil }
            return velocity > 0 ? 1 : -1
        }
    }
}
