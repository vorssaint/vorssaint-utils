// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The apps the clipboard history never saves from (issue #423). It sits with
/// the other choices about what gets saved, and stays a single quiet row until
/// there is an app in it, so the page reads the same for everyone who never
/// needs one.
struct ClipboardIgnoredAppsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var ignored = ClipboardIgnoredApps.shared

    private var text: ClipboardIgnoredAppsStrings {
        FeatureStrings.clipboardIgnoredApps(l10n.language)
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
