// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// The expanded header's readout at rest: a few system readings in the room
/// its hidden actions keep, so a glance needs no trip to the System page.
enum NotchSystemReadout {
    enum Kind: String, CaseIterable {
        case battery, cpu, gpu, memory

        var symbol: String {
            switch self {
            case .battery: return "battery.100percent"
            case .cpu: return "cpu"
            case .gpu: return "rectangle.connected.to.line.below"
            case .memory: return "memorychip"
            }
        }
    }

    struct Reading: Equatable, Identifiable {
        let kind: Kind
        let symbol: String
        let value: String
        /// Set when the reading itself is the news, as on the System cards.
        let attention: Bool
        var id: String { kind.rawValue }
    }

    struct Input: Equatable {
        var cpu: Double?
        var gpu: Double?
        var memoryUsed: UInt64?
        var memoryTotal: UInt64?
        var batteryPercent: Int?
        var hasBattery = false
        var externalPower = false
    }

    /// The System cards' threshold, so both pages agree on what is busy.
    static let busyLevel = 0.85
    static let lowBattery = 20
    /// With less room, the readings that change most during work stay longest.
    static let priority: [Kind] = [.cpu, .memory, .gpu, .battery]

    /// At most `limit` readings, in their fixed order. A reading that needs
    /// attention keeps its place ahead of a quiet one when room runs out; a
    /// reading not yet sampled is left out rather than shown empty.
    static func readings(_ input: Input, available: Set<Kind>, limit: Int = Kind.allCases.count) -> [Reading] {
        let all = Kind.allCases.compactMap { kind in available.contains(kind) ? reading(kind, input) : nil }
        guard limit < all.count else { return all }
        guard limit > 0 else { return [] }
        let kept = all.sorted { lhs, rhs in
            if lhs.attention != rhs.attention { return lhs.attention }
            return rank(lhs.kind) < rank(rhs.kind)
        }.prefix(limit).map(\.kind)
        return all.filter { kept.contains($0.kind) }
    }

    static func batterySymbol(percent: Int, externalPower: Bool) -> String {
        if externalPower { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private static func rank(_ kind: Kind) -> Int {
        priority.firstIndex(of: kind) ?? priority.count
    }

    private static func reading(_ kind: Kind, _ input: Input) -> Reading? {
        switch kind {
        case .battery:
            guard input.hasBattery, let percent = input.batteryPercent else { return nil }
            let clamped = min(100, max(0, percent))
            return Reading(kind: kind, symbol: batterySymbol(percent: clamped, externalPower: input.externalPower),
                           value: "\(clamped)%", attention: !input.externalPower && clamped <= lowBattery)
        case .cpu:
            return level(kind, input.cpu)
        case .gpu:
            return level(kind, input.gpu)
        case .memory:
            guard let used = input.memoryUsed, let total = input.memoryTotal, total > 0 else { return nil }
            return level(kind, Double(used) / Double(total))
        }
    }

    private static func level(_ kind: Kind, _ value: Double?) -> Reading? {
        guard let value, value.isFinite else { return nil }
        let clamped = min(1, max(0, value))
        return Reading(kind: kind, symbol: kind.symbol, value: "\(Int((clamped * 100).rounded()))%",
                       attention: clamped >= busyLevel)
    }
}
