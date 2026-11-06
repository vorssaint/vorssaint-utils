// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One entry of a display's preset menu (System Settings > Displays >
/// Preset), as XDR panels, the Pro Display XDR and the Studio Display list
/// them: Apple's own modes, the reference modes and any custom ones.
struct DisplayPreset: Identifiable, Equatable {
    let index: Int
    let name: String
    let group: Int
    var id: Int { index }
}

struct DisplayPresetList: Equatable {
    let presets: [DisplayPreset]
    let activeIndex: Int?

    /// Consecutive runs of the same group, so the menu separates Apple,
    /// reference and custom presets the way System Settings does.
    var groups: [[DisplayPreset]] {
        presets.reduce(into: [[DisplayPreset]]()) { groups, preset in
            if let last = groups.last?.last, last.group == preset.group {
                groups[groups.count - 1].append(preset)
            } else {
                groups.append([preset])
            }
        }
    }
}

/// Pure selection rules for the preset menu, kept free of the private
/// framework so the tests can pin them.
enum DisplayPresetSupport {
    struct Candidate {
        let index: Int
        let name: String?
        let group: Int
        let valid: Bool
    }

    /// The presets a person can pick. The framework also reports the empty
    /// slots for custom presets ("Preset #11" and on), which are invalid
    /// until one is created there; those stay hidden. A display with fewer
    /// than two presets offers no choice and gets no menu.
    static func list(_ candidates: [Candidate], activeIndex: Int?) -> DisplayPresetList? {
        let presets = candidates.compactMap { candidate -> DisplayPreset? in
            guard candidate.valid,
                  let name = candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return DisplayPreset(index: candidate.index, name: name, group: candidate.group)
        }
        guard presets.count > 1 else { return nil }
        let active = presets.contains { $0.index == activeIndex } ? activeIndex : nil
        return DisplayPresetList(presets: presets, activeIndex: active)
    }
}
