// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Island pages open in the menu panel. A page's service reads for the panel
/// as it does for the island, so either presentation can close, or be turned
/// off, without stopping the other. Main thread.
final class PanelModuleDemand {
    private var holders: [NotchModule: Set<UUID>] = [:]
    /// Tells the owner of a page's service when the panel starts or stops showing it.
    private let changed: (NotchModule) -> Void

    init(changed: @escaping (NotchModule) -> Void) {
        self.changed = changed
    }

    func shows(_ module: NotchModule) -> Bool {
        holders[module]?.isEmpty == false
    }

    /// Several panels may show a page at once; it is released with the last.
    func setVisible(_ visible: Bool, _ module: NotchModule, id: UUID) {
        let before = shows(module)
        if visible { holders[module, default: []].insert(id) } else { holders[module]?.remove(id) }
        if shows(module) != before { changed(module) }
    }
}
