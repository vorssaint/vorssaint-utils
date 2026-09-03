// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ProcessUsageNavigation {
    /// Live rankings should not move the focused process between key presses.
    /// Preserve surviving rows in their displayed order and append new rows;
    /// callers use the fresh ranking again as soon as focus leaves the list.
    static func stabilized<Row>(_ refreshed: [Row], previous: [Row], focusedID: pid_t?,
                                id: (Row) -> pid_t) -> [Row] {
        guard let focusedID, previous.contains(where: { id($0) == focusedID }) else {
            return refreshed
        }
        let byID = Dictionary(uniqueKeysWithValues: refreshed.map { (id($0), $0) })
        let surviving = previous.compactMap { byID[id($0)] }
        let existingIDs = Set(previous.map(id))
        return surviving + refreshed.filter { !existingIDs.contains(id($0)) }
    }
}
