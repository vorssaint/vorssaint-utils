// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum NotchSliderEditingTests {
    static func run(expect: (Bool, String) -> Void) {
        var editing = NotchSliderEditing()
        var position = 32.0
        var callbacks: [Bool] = []
        var commits: [Double] = []
        let changed: (Bool) -> Void = { isEditing in
            callbacks.append(isEditing)
            if !isEditing { commits.append(position) }
        }
        editing.valueChanged({ position = 75 }, onEditingChanged: changed)
        expect(position == 75 && commits == [75] && callbacks == [true, false],
               "an accessibility value action commits the new playback position without requiring mouse tracking")
        editing.valueChanged({ position = 76 }, onEditingChanged: changed)
        editing.valueChanged({ position = 77 }, onEditingChanged: changed)
        expect(commits == [75, 76, 77] && callbacks == [true, false, true, false, true, false],
               "consecutive keyboard changes each complete their own edit after updating the bound value")

        callbacks = []; commits = []
        editing.trackingChanged(true, onEditingChanged: changed)
        for value in 0...100 {
            editing.valueChanged({ position = Double(value) }, onEditingChanged: changed)
        }
        expect(position == 100 && callbacks == [true] && commits.isEmpty,
               "continuous mouse movement updates the thumb without submitting a seek for every sample")
        editing.trackingChanged(false, onEditingChanged: changed)
        expect(callbacks == [true, false] && commits == [100],
               "finishing a drag commits its final bound position exactly once")
        editing.trackingChanged(false, onEditingChanged: changed)
        expect(commits == [100], "a repeated native tracking-end callback cannot submit the drag again")
        editing.valueChanged({ position = 110 }, onEditingChanged: changed)
        expect(commits == [100, 110] && callbacks.suffix(2) == [true, false],
               "keyboard or accessibility input after a drag still receives a complete edit cycle")

        var levels: [Double] = []
        editing.valueChanged({ levels.append(0.25) }, onEditingChanged: nil)
        editing.trackingChanged(true, onEditingChanged: nil)
        editing.valueChanged({ levels.append(0.5) }, onEditingChanged: nil)
        editing.trackingChanged(false, onEditingChanged: nil)
        editing.valueChanged({ levels.append(0.75) }, onEditingChanged: nil)
        expect(levels == [0.25, 0.5, 0.75],
               "volume and brightness controls without an editing callback retain exactly one value write per action")
    }
}
