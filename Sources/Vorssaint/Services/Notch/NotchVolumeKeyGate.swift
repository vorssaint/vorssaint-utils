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
                         enabled: Bool, hasVolume: Bool, hasMute: Bool,
                         option: Bool, shift: Bool, commandOrControl: Bool) -> Action {
        guard let key = PreciseVolumeMediaKey(rawValue: keyCode), key != .play else { return .passThrough }
        if state == 0x0b { return held.remove(keyCode) != nil ? .consume : .passThrough }
        guard state == 0x0a, enabled, !commandOrControl, !option || shift,
              key == .mute ? hasMute : hasVolume else { return .passThrough }
        held.insert(keyCode)
        if key == .mute { return isRepeat ? .consume : .toggleMute }
        return .step(key == .volumeUp ? 1 : -1)
    }
}
