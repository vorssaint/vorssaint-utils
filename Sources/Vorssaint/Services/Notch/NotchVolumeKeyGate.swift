// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchVolumeKeyGate {
    enum Action: Equatable {
        case passThrough, consume, toggleMute
        case step(Int)
    }

    private var held = Set<Int32>()

    mutating func handle(keyCode: Int32, state: Int, isRepeat: Bool,
                         enabled: Bool, acceptsNewPress: Bool, hasVolume: Bool, hasMute: Bool,
                         option: Bool, shift: Bool, commandOrControl: Bool) -> Action {
        guard let key = PreciseVolumeMediaKey(rawValue: keyCode), key != .play else { return .passThrough }
        if state == 0x0b { return held.remove(keyCode) != nil ? .consume : .passThrough }
        guard state == 0x0a else { return .passThrough }
        let ownsPress = held.contains(keyCode)
        // Visibility selects the owner only at key-down. Never take a native
        // repeat, or send half of an intercepted press back to the system.
        guard !isRepeat || ownsPress else { return .passThrough }
        guard enabled, (isRepeat || acceptsNewPress), !commandOrControl, !option || shift,
              key == .mute ? hasMute : hasVolume else { return ownsPress ? .consume : .passThrough }
        held.insert(keyCode)
        if key == .mute { return isRepeat ? .consume : .toggleMute }
        return .step(key == .volumeUp ? 1 : -1)
    }
}
