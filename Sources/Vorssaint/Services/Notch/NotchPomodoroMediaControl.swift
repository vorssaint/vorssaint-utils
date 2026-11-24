// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One explicit request per timer action, addressed to the system media session.
/// No polling or toggle fallback: manual playback changes between phases are
/// left alone, and a repeated pause can never start a paused player.
final class NotchPomodoroMediaControl {
    enum Command: String { case play, pause }
    typealias Runner = (Command, BoundedProcessCancellation) -> Bool
    private let queue = DispatchQueue(label: "com.vorssaint.pomodoro-media", qos: .userInitiated)
    private let run: Runner
    private var pending: BoundedProcessCancellation?

    init(run: @escaping Runner = NotchPomodoroMediaControl.run) { self.run = run }

    func send(_ command: Command, completion: @escaping (Bool) -> Void) {
        cancel()
        let request = BoundedProcessCancellation()
        pending = request
        let run = self.run
        queue.async { [weak self] in
            guard !request.isCancelled else { return }
            let accepted = run(command, request)
            DispatchQueue.main.async {
                guard let self, self.pending === request, !request.isCancelled else { return }
                self.pending = nil
                completion(accepted)
            }
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    private static func run(_ command: Command, cancellation: BoundedProcessCancellation) -> Bool {
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libVorssaintNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path) else { return false }
        let result = BoundedProcessRunner.run("/usr/bin/perl", [script.path, library.path, command.rawValue],
                                              timeout: 2, maxOutputBytes: 1024, cancellation: cancellation)
        guard !result.timedOut, result.status == 0,
              let reply = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any]
        else { return false }
        // Acceptance is not proof that a third-party player obeyed the command.
        return reply["sent"] as? Bool == true
    }

    deinit { pending?.cancel() }
}
