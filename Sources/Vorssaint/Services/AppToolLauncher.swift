// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shared launch surface for the radial menu and Finder workspace.
enum AppToolLauncher {
    static func run(_ tool: RadialMenuTool) {
        guard tool.isRunnable() else { return }
        switch tool {
        case .screenshot: ScreenshotService.shared.capture()
        case .screenRecorder: ScreenRecorderService.shared.toggle()
        case .colorPicker: ColorSamplerService.shared.pick()
        case .screenOCR: ScreenTextService.shared.capture()
        case .micMute: MicMuteService.shared.toggle()
        case .clipboardHistory: ClipboardHistoryService.shared.showHistoryWindow()
        case .quickLauncher: QuickLauncherService.shared.show()
        case .cameraPreview: CameraPreviewService.shared.show()
        case .scratchpad: ScratchpadService.shared.show()
        case .shelf: ShelfService.shared.summon()
        case .cleaner: openSettings(at: .cleaner)
        case .uninstaller: openSettings(at: .uninstaller)
        case .appUpdates:
            AppUpdatesService.shared.check()
            openSettings(at: .appUpdates)
        case .cleaningMode: CleaningModeManager.shared.activate()
        case .keepAwake: KeepAwakeManager.shared.toggle()
        case .finderTools: FinderToolsService.shared.openFromFinder()
        }
    }

    private static func openSettings(at page: SettingsPage) {
        SettingsRouter.shared.page = page
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}
