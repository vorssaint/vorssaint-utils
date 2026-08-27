// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The apps Selection Actions never offers itself in.
struct SelectionActionsExcludedAppsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var excluded = SelectionActionsExcludedApps.shared

    private var text: SelectionActionsStrings { FeatureStrings.selectionActions(l10n.language) }

    var body: some View {
        AppBundleList(title: text.excludedAppsTitle,
                      caption: text.excludedAppsCaption,
                      addTitle: text.excludedAppsAddButton,
                      removeLabel: text.excludedAppsRemoveButton,
                      bundleIDs: excluded.apps,
                      reachesEveryApp: true,
                      onAdd: { excluded.add($0) },
                      onRemove: { excluded.remove($0) })
    }
}
