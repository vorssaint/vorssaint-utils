// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "apps to leave alone" block that lives INSIDE a mouse feature's own
/// section in Settings (issue #358), right under the switch it holds back, so
/// the list is where the user is already looking. Scrolling presents one shared
/// list; unrelated mouse behaviors use the same view with independent scopes.
struct MouseExceptionsList: View {
    let scope: MouseExceptionScope

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var exceptions = MouseAppExceptions.shared

    private var text: MouseExceptionStrings { FeatureStrings.mouseExceptions(l10n.language) }

    var body: some View {
        AppBundleList(title: text.listTitle,
                      caption: text.caption(for: scope),
                      addTitle: text.addButton,
                      removeLabel: text.removeButton,
                      bundleIDs: exceptions.list(scope),
                      reachesEveryApp: true,
                      acceptsExecutables: true,
                      onAdd: { exceptions.add($0, to: scope) },
                      onRemove: { exceptions.remove($0, from: scope) })
    }
}
