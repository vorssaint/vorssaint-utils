// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TouchBarFeatureStrings {
    let title: String
    let hubDescription: String
    let unavailable: String
}

extension TouchBarFeatureStrings {
    static let enUS = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Customize controls and information shown on the Touch Bar",
        unavailable: "This Mac does not have a Touch Bar."
    )
}
