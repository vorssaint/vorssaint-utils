// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The menu panel's utility list as a direct island destination. Shares the
/// tools, visibility choices and order without opening the full app panel.
struct NotchUtilitiesView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var tracksNavigation = true
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        OverlayScrollView(measuredHeight: $measuredHeight) {
            UtilitiesSection(collapsible: false, startCleaning: {
                service.perform { CleaningModeManager.shared.activate() }
            }, hostedLayerChanged: { close in
                guard tracksNavigation else { return }
                service.setPageLayer(.utilities, close: close)
            })
            .frame(width: size.width)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.notchPresentation, true)
    }
}
