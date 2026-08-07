// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Moments when typing happened during one recording. No key or text is kept.
struct RecorderTypingTrack: Codable, Equatable {
    var times: [Double] = []

    var isEmpty: Bool { times.isEmpty }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decoded(_ data: Data?) -> RecorderTypingTrack {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return value
    }
}

/// The monitor exists only while recording and remembers timing, never keys.
final class RecorderTypingSampler {
    private var startedAt: CFTimeInterval = 0
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var times: [Double] = []

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        startedAt = CACurrentMediaTime()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return event
        }
    }

    func stop() -> RecorderTypingTrack {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        return RecorderTypingTrack(times: times)
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        times.append(max(0, CACurrentMediaTime() - startedAt))
    }

    deinit {
        _ = stop()
    }
}
