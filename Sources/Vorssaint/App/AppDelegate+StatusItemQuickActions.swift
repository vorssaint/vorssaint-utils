// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Runs the single action a menu bar icon gesture is assigned to.
///
/// Kept beside the gesture layer rather than inside `AppDelegate`: the
/// dispatcher is one switch over a fixed set of features, and every branch
/// reuses the entry point that feature already exposes to the panel, the
/// shortcut or the Command Bar. No gesture owns a second implementation of
/// anything.
extension AppDelegate {
    func performStatusItemAction(_ action: StatusItemQuickAction) {
        guard action != .none else { return }
        let run = { [weak self] in
            guard action.feature.isAvailable else {
                self?.reportStatusItemActionFailure(icon: action.symbolName)
                return
            }
            switch action {
            case .none:
                break
            case .keepAwake:
                KeepAwakeManager.shared.toggle()
            case .micMute:
                MicMuteService.shared.toggle()
            case .soundMute:
                // Read the state now, at the moment of the gesture: a switch
                // captured when a screen was opened would be stale by the time
                // the person clicks the icon.
                guard let muted = AppVolumeMixer.systemOutputIsMuted(),
                      AppVolumeMixer.setSystemOutputMuted(!muted) else {
                    self?.reportStatusItemActionFailure(icon: "speaker.slash")
                    return
                }
            case .screenRecorder:
                ScreenRecorderService.shared.toggle()
            case .screenshot:
                ScreenshotService.shared.capture()
            }
        }
        // A capture must not photograph this app's own panel, so those two
        // wait for it to close. Everything else runs at once: it neither
        // needs the panel gone nor closes it.
        if action.closesPanelBeforeRunning {
            closePopover(animated: false, completion: run)
        } else {
            run()
        }
    }

    /// An assigned action whose feature is not installed, or whose hardware
    /// says no, still speaks: the icon must never look broken.
    private func reportStatusItemActionFailure(icon: String) {
        QuickToolHUD.show(icon: icon,
                          message: FeatureStrings.quickToggles(L10n.shared.language).actionFailed)
    }
}
