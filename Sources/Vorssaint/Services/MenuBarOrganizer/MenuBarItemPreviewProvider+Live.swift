// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension MenuBarItemPreviewProvider {
    static let shared = MenuBarItemPreviewProvider(
        permitted: { MenuBarOrganizerPolicy.supportsAdvancedBackend && CGPreflightScreenCaptureAccess() },
        validate: { item in
            guard MenuBarWindowServerBridge.menuBarWindowIDs()?.contains(item.windowID) == true,
                  let frame = MenuBarWindowServerBridge.frame(of: item.windowID),
                  MenuBarOrganizerPolicy.validFrame(frame),
                  let records = CGWindowListCopyWindowInfo(.optionIncludingWindow, item.windowID) as? [[String: Any]],
                  records.count == 1, let record = records.first,
                  let owner = record[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == item.ownerPID else { return false }
            return true
        },
        capture: { await WindowPreviewProvider.captureViaWindowServer($0, waitingForOtherCaptures: false) })
}
