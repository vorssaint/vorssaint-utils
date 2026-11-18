// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the lock screen can show, each in its place: This Mac's rail left of
/// the stage, the stage itself, and the AI rail right of it. Each place
/// shows its own widgets top to bottom in the order listed here until the
/// person reorders them.
enum NotchLockScreenWidget: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, accessories, battery
    case calendar, nowPlaying
    case claude, codex, lifetime, agents, streak

    enum Place: String, CaseIterable, Identifiable {
        case mac, stage, ai

        var id: String { rawValue }

        var widgets: [NotchLockScreenWidget] { NotchLockScreenWidget.allCases.filter { $0.place == self } }
    }

    var id: String { rawValue }

    var place: Place {
        switch self {
        case .cpu, .gpu, .memory, .network, .accessories, .battery: return .mac
        case .calendar, .nowPlaying: return .stage
        case .claude, .codex, .lifetime, .agents, .streak: return .ai
        }
    }

    /// Half a rail wide: two in a row share it, and one left on its own
    /// widens to the whole rail, so a hidden or moved partner leaves no hole.
    var isHalf: Bool {
        switch self {
        case .cpu, .gpu, .memory, .network, .codex, .lifetime: return true
        default: return false
        }
    }

    /// Agents at work scrolls and Streak answers the pointer; the player
    /// has its own window on the stage. Every other widget lets clicks
    /// through to the lock screen.
    var takesPointer: Bool { self == .agents || self == .streak }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.connected.to.line.below"
        case .memory: return "memorychip"
        case .network: return "network"
        case .accessories: return "dot.radiowaves.left.and.right"
        case .battery: return "battery.75percent"
        case .calendar: return "calendar"
        case .nowPlaying: return "play.circle"
        case .claude: return "gauge.with.dots.needle.33percent"
        case .codex: return "gauge.with.dots.needle.67percent"
        case .lifetime: return "dollarsign.circle"
        case .agents: return "sparkle"
        case .streak: return "flame"
        }
    }
}

/// Which widgets the lock screen shows and in what order: one saved order
/// for all of them, each place reading its own widgets from it, and the set
/// the person hid. Unknown or repeated entries drop out; a widget added in a
/// later version joins the end of its place, shown.
struct NotchLockScreenWidgets: Equatable {
    private(set) var order: [NotchLockScreenWidget]
    var hidden: Set<NotchLockScreenWidget>

    /// Everything shown, in the order the lock screen first had.
    static let initial = Self(order: NotchLockScreenWidget.allCases, hidden: [])

    init(order: [NotchLockScreenWidget], hidden: Set<NotchLockScreenWidget>) {
        var seen = Set<NotchLockScreenWidget>()
        self.order = (order + NotchLockScreenWidget.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
    }

    init(order: String, hidden: String) {
        self.init(order: Self.decode(order), hidden: Set(Self.decode(hidden)))
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        Self(order: defaults.string(forKey: DefaultsKey.notchLockScreenWidgetOrder) ?? "",
             hidden: defaults.string(forKey: DefaultsKey.notchLockScreenHiddenWidgets) ?? "")
    }

    private static func decode(_ saved: String) -> [NotchLockScreenWidget] {
        saved.split(separator: ",").compactMap { NotchLockScreenWidget(rawValue: String($0)) }
    }

    var encodedOrder: String { order.map(\.rawValue).joined(separator: ",") }
    /// In display order, so the saved value reads the same however it was built.
    var encodedHidden: String { order.filter(hidden.contains).map(\.rawValue).joined(separator: ",") }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(encodedOrder, forKey: DefaultsKey.notchLockScreenWidgetOrder)
        defaults.set(encodedHidden, forKey: DefaultsKey.notchLockScreenHiddenWidgets)
    }

    /// A place's widgets top to bottom, hidden ones included.
    func order(in place: NotchLockScreenWidget.Place) -> [NotchLockScreenWidget] {
        order.filter { $0.place == place }
    }

    /// What a place shows, top to bottom.
    func shown(in place: NotchLockScreenWidget.Place) -> [NotchLockScreenWidget] {
        order.filter { $0.place == place && !hidden.contains($0) }
    }

    /// The place `arranged` belongs to, in that order; the other places keep
    /// theirs. An arrangement that is not exactly one place's widgets
    /// changes nothing.
    func arranging(_ arranged: [NotchLockScreenWidget]) -> Self {
        guard let place = arranged.first?.place, arranged.count == Set(arranged).count,
              Set(arranged) == Set(order(in: place)) else { return self }
        var next = arranged.makeIterator()
        return Self(order: order.map { $0.place == place ? next.next() ?? $0 : $0 }, hidden: hidden)
    }

    /// `widget` moved `offset` places within its own place, for VoiceOver,
    /// which cannot drag. A move past either end changes nothing.
    func moving(_ widget: NotchLockScreenWidget, by offset: Int) -> Self {
        var arranged = order(in: widget.place)
        guard let index = arranged.firstIndex(of: widget), arranged.indices.contains(index + offset) else { return self }
        arranged.swapAt(index, index + offset)
        return arranging(arranged)
    }

    func showing(_ widget: NotchLockScreenWidget, _ shown: Bool) -> Self {
        var next = self
        if shown { next.hidden.remove(widget) } else { next.hidden.insert(widget) }
        return next
    }
}
