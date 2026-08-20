// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

enum AudioRecoveryResult: Equatable {
    case succeeded
    case failed
}

/// Restarts macOS' Core Audio daemon on demand when the audio stack is stuck.
/// The existing AdminShell owns the password prompt and serializes privileged
/// requests, so this feature never stores credentials or shells through sudo.
final class AudioRecoveryService: ObservableObject {
    static let shared = AudioRecoveryService()

    @Published private(set) var isResetting = false
    @Published private(set) var lastResult: AudioRecoveryResult?

    private init() {}

    func resetAudio() {
        guard !isResetting else { return }
        isResetting = true
        lastResult = nil

        let prompt = L10n.shared.s.audioRecoveryAdminPrompt
        AdminShell.run(AudioRecoverySupport.resetCommand, prompt: prompt) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResetting = false
                self.lastResult = succeeded ? .succeeded : .failed
            }
        }
    }
}
