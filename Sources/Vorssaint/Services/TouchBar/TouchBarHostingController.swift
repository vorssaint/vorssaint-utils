// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

final class TouchBarHostingController<Content: View>: NSHostingController<Content> {
    override func makeTouchBar() -> NSTouchBar? {
        return TouchBarService.shared.touchBar
    }
}
