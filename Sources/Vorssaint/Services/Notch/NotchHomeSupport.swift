// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Home is Controls with smart cards: the player and the levels each hold a
/// second face a swipe away, and the face that matters now comes first.
enum NotchHomeSupport {
    enum Face: Equatable {
        case music, agents, levels, calendar, files
    }

    /// The player, then the agents. A turn in progress with nothing playing
    /// puts the agents first.
    static func leftFaces(agents: Bool, musicPlaying: Bool, agentsWorking: Bool) -> [Face] {
        guard agents else { return [.music] }
        return agentsWorking && !musicPlaying ? [.agents, .music] : [.music, .agents]
    }

    /// The levels, then the calendar. Files sent to the island lead, since
    /// they are what the island was just given, unless an event is about to
    /// start or under way, which leads before anything else.
    static func rightFaces(calendar: Bool, eventSoon: Bool, files: Bool = false) -> [Face] {
        var faces: [Face] = [.levels]
        if calendar { faces.append(.calendar) }
        if files { faces.insert(.files, at: 0) }
        if calendar, eventSoon {
            faces.removeAll { $0 == .calendar }
            faces.insert(.calendar, at: 0)
        }
        return faces
    }

    /// Home and Controls stand in for each other: a link to the one hidden
    /// opens the other rather than nothing.
    static func page(_ module: NotchModule, in modules: [NotchModule]) -> NotchModule? {
        if modules.contains(module) { return module }
        switch module {
        case .home where modules.contains(.controls): return .controls
        case .controls where modules.contains(.home): return .home
        default: return nil
        }
    }
}
