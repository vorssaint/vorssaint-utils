// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import MediaPlayer

/// Coordinates the opt-in play/pause gesture without taking ownership of a
/// player. A resume is issued only when the same session paused media and the
/// system still reports it as paused.
@MainActor
final class DictationMediaController {
    static let shared = DictationMediaController()

    private var shouldResume = false
    private var resumeTask: Task<Void, Never>?

    private init() {}

    func begin() {
        resumeTask?.cancel()
        resumeTask = nil
        let decision = DictationMediaPolicy.begin(enabled: enabled,
                                                  playback: playbackState)
        shouldResume = decision.shouldResume
        if decision.action == .pause { Self.postPlayPause() }
    }

    func end() {
        guard shouldResume else { return }
        resumeTask?.cancel()
        resumeTask = nil
        let shouldResumeNow = shouldResume
        shouldResume = false
        guard shouldResumeNow, enabled else { return }
        let delay = DictationMediaPolicy.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.dictationMediaResumeDelay))
        resumeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            guard DictationMediaPolicy.end(enabled: self.enabled,
                                           shouldResume: true,
                                           playback: self.playbackState) == .resume else { return }
            Self.postPlayPause()
            self.resumeTask = nil
        }
    }

    func cancel() {
        resumeTask?.cancel()
        resumeTask = nil
        shouldResume = false
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.dictationPauseMedia)
    }

    private var playbackState: DictationMediaPlayback {
        switch MPNowPlayingInfoCenter.default().playbackState {
        case .playing: return .playing
        case .paused: return .paused
        case .stopped: return .stopped
        default: return .unknown
        }
    }

    /// Simulates the hardware Play/Pause key accepted by Music, Safari and
    /// other players without requiring an app-specific Automation grant.
    private static func postPlayPause() {
        func post(down: Bool) {
            let flags: NSEvent.ModifierFlags = NSEvent.ModifierFlags(
                rawValue: down ? 0xA00 : 0xB00)
            let data1 = (16 << 16) | ((down ? 0xA : 0xB) << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined,
                                                 location: .zero,
                                                 modifierFlags: flags,
                                                 timestamp: 0,
                                                 windowNumber: 0,
                                                 context: nil,
                                                 subtype: 8,
                                                 data1: data1,
                                                 data2: -1) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}
