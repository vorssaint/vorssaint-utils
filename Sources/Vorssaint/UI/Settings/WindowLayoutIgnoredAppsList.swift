// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowLayoutIgnoredAppsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var ignored = WindowLayoutIgnoredApps.shared

    private var text: WindowLayoutIgnoredAppsStrings {
        FeatureStrings.windowLayoutIgnoredApps(l10n.language)
    }

    var body: some View {
        AppBundleList(title: text.listTitle,
                      caption: text.caption,
                      addTitle: text.addButton,
                      removeLabel: text.removeButton,
                      bundleIDs: ignored.apps,
                      onAdd: { ignored.add($0) },
                      onRemove: { ignored.remove($0) })
    }
}
