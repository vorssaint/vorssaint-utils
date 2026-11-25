// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The apps whose copies keep their formatting instead of being stripped
/// (the paste-plain equivalent of the history's ignored-apps list). It sits
/// with the other choices of the section and stays a single quiet row until
/// there is an app in it, so the page reads the same for everyone who never
/// needs one.
struct PastePlainExcludedAppsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var excluded = PastePlainExcludedApps.shared

    private var text: PastePlainStrings {
        FeatureStrings.pastePlain(l10n.language)
    }

    var body: some View {
        AppBundleList(title: text.excludedListTitle,
                      caption: text.excludedCaption,
                      addTitle: text.excludedAddButton,
                      removeLabel: text.excludedRemoveButton,
                      bundleIDs: excluded.apps,
                      onAdd: { excluded.add($0) },
                      onRemove: { excluded.remove($0) })
    }
}
