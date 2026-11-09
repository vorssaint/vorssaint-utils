// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import Combine

enum ContinuityFailure: Error, Equatable {
    case permission, unavailable, connection, quit, brightness
}

/// Ordering and cancellation are independent of the macOS adapters, so a
/// delayed network response can never dim a session that has already ended.
@MainActor final class ContinuityWorkflow: ObservableObject {
    enum Phase: Equatable {
        case idle, connecting, quitting, countdown(Int), active, failed(ContinuityFailure)
    }
    struct Hooks {
        var isAvailable: () -> Bool
        var connect: (String) async throws -> Void
        var quitApps: ([String]) async throws -> Bool
        var wait: (UInt64) async throws -> Void
        var dim: () -> Bool
        var restore: () -> Void
        var prepareSession: () -> Void = { }
    }
    @Published private(set) var phase: Phase = .idle
    private let hooks: Hooks
    private var generation = 0
    init(hooks: Hooks) { self.hooks = hooks }

    var busy: Bool {
        switch phase {
        case .connecting, .quitting, .countdown: return true
        default: return false
        }
    }

    func cancel() {
        generation += 1
        if phase == .active || phase == .failed(.brightness) { hooks.restore() }
        phase = .idle
    }

    func run(hotspot: String, apps: [String]) async {
        guard !busy, phase != .active, !Task.isCancelled else { return }
        hooks.prepareSession()
        guard hooks.isAvailable() else { return }
        generation += 1
        let operation = generation
        func check() throws {
            guard operation == generation, hooks.isAvailable(), !Task.isCancelled else {
                throw CancellationError()
            }
        }
        do {
            phase = .connecting
            try await hooks.connect(hotspot)
            try check()
            phase = .quitting
            guard try await hooks.quitApps(apps) else { throw ContinuityFailure.quit }
            try check()
            for remaining in stride(from: 5, through: 1, by: -1) {
                phase = .countdown(remaining)
                try await hooks.wait(1)
                try check()
            }
            guard hooks.dim() else { throw ContinuityFailure.brightness }
            phase = .active
        } catch is CancellationError {
            if operation == generation { cancel() }
        } catch {
            guard operation == generation else { return }
            phase = .failed((error as? ContinuityFailure) ?? .connection)
        }
    }
}
