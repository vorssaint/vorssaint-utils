// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Both entry points use the same feature and permission gates in AppToolLauncher.
enum FinderToolsSystemTool {
    static func tool(for action: FinderToolsAction) -> RadialMenuTool? {
        switch action {
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .colorPicker: return .colorPicker
        case .cleaningMode: return .cleaningMode
        case .keepAwake: return .keepAwake
        case .micMute: return .micMute
        case .clipboardHistory: return .clipboardHistory
        default: return nil
        }
    }
}
