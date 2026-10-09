// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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

    /// A place on Home's row of shortcuts.
    enum Slot: Hashable, Identifiable {
        case control(NotchControlItem)
        /// The tool last opened from Tools, by its raw value.
        case tool(String)
        /// The page last opened from Explore.
        case page(NotchModule)
        /// The Tools page itself, when nothing was opened lately.
        case tools

        var id: String {
            switch self {
            case .control(let item): return "control." + item.rawValue
            case .tool(let raw): return "tool." + raw
            case .page(let module): return "page." + module.rawValue
            case .tools: return "tools"
            }
        }
    }

    /// What was last opened from Tools or Explore.
    enum Launch: Equatable {
        case tool(String)
        case page(NotchModule)

        var stored: String {
            switch self {
            case .tool(let raw): return "tool:" + raw
            case .page(let module): return "page:" + module.rawValue
            }
        }

        init?(stored: String) {
            let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            switch parts[0] {
            case "tool": self = .tool(parts[1])
            case "page":
                guard let module = NotchModule(rawValue: parts[1]) else { return nil }
                self = .page(module)
            default: return nil
            }
        }
    }

    /// How long the last launch keeps its place before Tools returns.
    static let launchLifetime: TimeInterval = 3 * 60

    /// Tools and pages the row already reaches through a shortcut of its own.
    static let toolShortcuts: [String: NotchControlItem] = [
        "keepAwake": .keepAwake, "micMute": .microphone, "screenshot": .screenshot,
        "screenRecorder": .recording, "scratchpad": .scratchpad,
    ]
    static let pageShortcuts: [NotchModule: NotchControlItem] = [
        .mixer: .mixer, .calendar: .calendar, .scratchpad: .scratchpad,
    ]

    /// The last launch while it is recent, unless the row already reaches it
    /// or it is no longer available. Home, Controls and Tools never take the
    /// place: they are where the row already leads.
    static func recentSlot(_ launch: Launch?, at date: Date?, now: Date, shortcuts: [NotchControlItem],
                           available: (Launch) -> Bool) -> Slot? {
        guard let launch, let date else { return nil }
        let age = now.timeIntervalSince(date)
        guard age >= 0, age < launchLifetime, available(launch) else { return nil }
        switch launch {
        case .tool(let raw):
            if let shortcut = toolShortcuts[raw], shortcuts.contains(shortcut) { return nil }
            return .tool(raw)
        case .page(let module):
            if [.home, .controls, .tools].contains(module) { return nil }
            if let shortcut = pageShortcuts[module], shortcuts.contains(shortcut) { return nil }
            return .page(module)
        }
    }

    /// Controls' shortcuts, with the timer's place given to what was last
    /// opened from Tools or Explore, or to Tools itself when nothing was
    /// lately; the timer stays a page away.
    static func rail(controls: [NotchControlItem], recent: Slot?, toolsPage: Bool) -> [Slot] {
        let shortcuts = controls.filter { !$0.isLevel && $0 != .music }
        var slots = shortcuts.filter { $0 != .timer }.map(Slot.control)
        guard let slot = recent ?? (toolsPage ? .tools : nil) else { return slots }
        let index = shortcuts.firstIndex(of: .timer).map { min($0, slots.count) } ?? slots.count
        slots.insert(slot, at: index)
        return slots
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
