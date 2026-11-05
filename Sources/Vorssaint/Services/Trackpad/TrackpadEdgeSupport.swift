// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum TrackpadEdge: String, CaseIterable, Identifiable {
    case left, right, top, bottom

    var id: String { rawValue }

    var isVertical: Bool { self == .left || self == .right }

    var defaultsKey: String {
        switch self {
        case .left: return DefaultsKey.trackpadEdgeLeftAction
        case .right: return DefaultsKey.trackpadEdgeRightAction
        case .top: return DefaultsKey.trackpadEdgeTopAction
        case .bottom: return DefaultsKey.trackpadEdgeBottomAction
        }
    }

    var defaultAction: TrackpadSlideAction {
        switch self {
        case .left: return .brightness
        case .right: return .volume
        case .top: return .keyboardBrightness
        case .bottom: return .tracks
        }
    }
}

enum TrackpadSlideAction: String, CaseIterable, Identifiable {
    case off, volume, brightness, keyboardBrightness, microphoneVolume, tracks

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .off: return "minus"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .keyboardBrightness: return "light.max"
        case .microphoneVolume: return "mic.fill"
        case .tracks: return "forward.end.alt.fill"
        }
    }

    var requiredFeature: AppFeature? {
        self == .microphoneVolume ? .mixer : nil
    }

    var isStepped: Bool { self != .off && self != .tracks }

    static func sanitized(_ raw: String?, fallback: TrackpadSlideAction) -> TrackpadSlideAction {
        raw.flatMap(TrackpadSlideAction.init(rawValue:)) ?? fallback
    }
}

enum TrackpadCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }

    var defaultsKey: String {
        switch self {
        case .topLeft: return DefaultsKey.trackpadCornerTopLeftAction
        case .topRight: return DefaultsKey.trackpadCornerTopRightAction
        case .bottomLeft: return DefaultsKey.trackpadCornerBottomLeftAction
        case .bottomRight: return DefaultsKey.trackpadCornerBottomRightAction
        }
    }

    var defaultAction: TrackpadCornerAction {
        switch self {
        case .topLeft: return .microphoneMute
        case .topRight: return .outputMute
        case .bottomLeft, .bottomRight: return .off
        }
    }
}

enum TrackpadCornerAction: String, CaseIterable, Identifiable {
    case off, microphoneMute, outputMute, playPause, nextTrack, previousTrack,
         missionControl, appExpose, nextSoundOutput, lockScreen

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .off: return "minus"
        case .microphoneMute: return "mic.slash.fill"
        case .outputMute: return "speaker.slash.fill"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "rectangle.stack"
        case .nextSoundOutput: return "hifispeaker"
        case .lockScreen: return "lock.fill"
        }
    }

    var requiredFeature: AppFeature? {
        switch self {
        case .microphoneMute: return .micMute
        case .nextSoundOutput: return .soundOutputSwitcher
        case .lockScreen: return .quickToggles
        default: return nil
        }
    }

    var isMute: Bool { self == .microphoneMute || self == .outputMute }

    static func sanitized(_ raw: String?, fallback: TrackpadCornerAction) -> TrackpadCornerAction {
        raw.flatMap(TrackpadCornerAction.init(rawValue:)) ?? fallback
    }
}

enum TrackpadTapTarget: Hashable {
    case corner(TrackpadCorner)
    case mediaStrip
}

enum TrackpadActiveArea: String, CaseIterable, Identifiable {
    case full, threeQuarters, half, quarter

    var id: String { rawValue }

    var fraction: Float {
        switch self {
        case .full: return 1
        case .threeQuarters: return 0.75
        case .half: return 0.5
        case .quarter: return 0.25
        }
    }

    static func sanitized(_ raw: String?) -> TrackpadActiveArea {
        raw.flatMap(TrackpadActiveArea.init(rawValue:)) ?? .full
    }
}

enum TrackpadSlideSensitivity: String, CaseIterable, Identifiable {
    case gentle, normal, fast

    var id: String { rawValue }

    var fullRangeTravel: Float {
        switch self {
        case .gentle: return 0.95
        case .normal: return 0.7
        case .fast: return 0.45
        }
    }

    static func sanitized(_ raw: String?) -> TrackpadSlideSensitivity {
        raw.flatMap(TrackpadSlideSensitivity.init(rawValue:)) ?? .normal
    }
}

enum TrackpadEdgeModifier: String, CaseIterable, Identifiable {
    case none, fn, option

    var id: String { rawValue }

    func isSatisfied(by flags: CGEventFlags) -> Bool {
        switch self {
        case .none: return true
        case .fn: return flags.contains(.maskSecondaryFn)
        case .option: return flags.contains(.maskAlternate)
        }
    }

    static func sanitized(_ raw: String?) -> TrackpadEdgeModifier {
        raw.flatMap(TrackpadEdgeModifier.init(rawValue:)) ?? .none
    }
}

struct TrackpadEdgeConfiguration: Equatable {
    static let edgeWidthRange: ClosedRange<Double> = 0.03...0.15
    static let defaultEdgeWidth = 0.06
    static let fullRangeSteps = 16
    static let preciseRangeSteps = 64

    var slideActions: [TrackpadEdge: TrackpadSlideAction]
    var cornerActions: [TrackpadCorner: TrackpadCornerAction]
    var mediaStripTap: Bool
    var edgeWidth: Float
    var activeArea: TrackpadActiveArea
    var sensitivity: TrackpadSlideSensitivity
    var precise: Bool
    var tapToSlide = false

    static let standard = TrackpadEdgeConfiguration(
        slideActions: Dictionary(uniqueKeysWithValues: TrackpadEdge.allCases.map { ($0, $0.defaultAction) }),
        cornerActions: Dictionary(uniqueKeysWithValues: TrackpadCorner.allCases.map { ($0, $0.defaultAction) }),
        mediaStripTap: true,
        edgeWidth: Float(defaultEdgeWidth),
        activeArea: .full,
        sensitivity: .normal,
        precise: false)

    func slideAction(_ edge: TrackpadEdge) -> TrackpadSlideAction {
        slideActions[edge] ?? .off
    }

    func cornerAction(_ corner: TrackpadCorner) -> TrackpadCornerAction {
        cornerActions[corner] ?? .off
    }

    var hasAnyGesture: Bool {
        slideActions.values.contains { $0 != .off }
            || cornerActions.values.contains { $0 != .off }
    }

    var horizontalBand: Float { min(edgeWidth * 1.5, 0.25) }
    var cornerWidth: Float { max(edgeWidth * 2, 0.1) }
    var cornerHeight: Float { max(horizontalBand * 2, 0.16) }

    var rangeSteps: Int { precise ? Self.preciseRangeSteps : Self.fullRangeSteps }

    var stepSize: Double { 1 / Double(rangeSteps) }

    var stepDistance: Float {
        let full = sensitivity.fullRangeTravel / Float(Self.fullRangeSteps)
        return precise ? full / 2 : full
    }

    var mediaStripArmed: Bool { mediaStripTap && slideAction(.bottom) == .tracks }

    static func sanitizedEdgeWidth(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultEdgeWidth }
        return min(max(value, edgeWidthRange.lowerBound), edgeWidthRange.upperBound)
    }

    static func load(from defaults: UserDefaults,
                     isAvailable: (AppFeature) -> Bool = { $0.isAvailable }) -> TrackpadEdgeConfiguration {
        var slides: [TrackpadEdge: TrackpadSlideAction] = [:]
        for edge in TrackpadEdge.allCases {
            let action = TrackpadSlideAction.sanitized(defaults.string(forKey: edge.defaultsKey),
                                                       fallback: edge.defaultAction)
            slides[edge] = action.requiredFeature.map(isAvailable) == false ? .off : action
        }
        var corners: [TrackpadCorner: TrackpadCornerAction] = [:]
        for corner in TrackpadCorner.allCases {
            let action = TrackpadCornerAction.sanitized(defaults.string(forKey: corner.defaultsKey),
                                                        fallback: corner.defaultAction)
            corners[corner] = action.requiredFeature.map(isAvailable) == false ? .off : action
        }
        let width = defaults.object(forKey: DefaultsKey.trackpadEdgeWidth) == nil
            ? defaultEdgeWidth
            : defaults.double(forKey: DefaultsKey.trackpadEdgeWidth)
        return TrackpadEdgeConfiguration(
            slideActions: slides,
            cornerActions: corners,
            mediaStripTap: defaults.object(forKey: DefaultsKey.trackpadEdgeMediaStripTap) == nil
                || defaults.bool(forKey: DefaultsKey.trackpadEdgeMediaStripTap),
            edgeWidth: Float(sanitizedEdgeWidth(width)),
            activeArea: TrackpadActiveArea.sanitized(defaults.string(forKey: DefaultsKey.trackpadEdgeActiveArea)),
            sensitivity: TrackpadSlideSensitivity.sanitized(
                defaults.string(forKey: DefaultsKey.trackpadEdgeSensitivity)),
            precise: defaults.bool(forKey: DefaultsKey.trackpadEdgePrecise),
            tapToSlide: defaults.bool(forKey: DefaultsKey.trackpadEdgeTapToSlide))
    }
}

struct TrackpadContact: Equatable {
    let id: Int32
    let x: Float
    let y: Float
}

enum TrackpadEdgeEvent: Equatable {
    case slideBegan(TrackpadEdge, TrackpadSlideAction)
    case step(TrackpadSlideAction, direction: Int)
    case slideEnded(TrackpadEdge)
    case trackSkip(direction: Int)
    case firstTap(TrackpadTapTarget?, generation: Int)
    case doubleTap(TrackpadTapTarget, generation: Int)

    var beginsSlide: Bool {
        if case .slideBegan = self { return true }
        return false
    }
}

enum TrackpadTapClickRole: Equatable {
    case none
    case firstTap(generation: Int)
    case secondTap
}

struct TrackpadEdgeZones: Equatable {
    var vertical: TrackpadEdge?
    var horizontal: TrackpadEdge?
    var tap: TrackpadTapTarget?

    var isEmpty: Bool { vertical == nil && horizontal == nil && tap == nil }
}

struct TrackpadEdgeRecognizer {
    static let engageDistance: Float = 0.025
    static let abandonDistance: Float = 0.06
    static let axisDominance: Float = 1.4
    static let tapMaxDuration: TimeInterval = 0.28
    static let tapMaxMovement: Float = 0.02
    static let doubleTapGap: TimeInterval = 0.35
    static let tapClickWindow: TimeInterval = 0.3
    static let trackSwipeDistance: Float = 0.12
    static let maxStepsPerFrame = 8

    struct Candidate: Equatable {
        var id: Int32
        var startX: Float
        var startY: Float
        var startedAt: TimeInterval
        var vertical: TrackpadEdge?
        var horizontal: TrackpadEdge?
        var tapTarget: TrackpadTapTarget?
        var arms: Set<TrackpadEdge> = []
    }

    struct Slide: Equatable {
        var id: Int32
        var edge: TrackpadEdge
        var action: TrackpadSlideAction
        var origin: Float
        var lastAxis: Float
        var accumulated: Float
    }

    struct PendingTap: Equatable {
        var target: TrackpadTapTarget?
        var armedEdges: Set<TrackpadEdge> = []
        var liftedAt: TimeInterval
        var generation: Int
    }

    enum Phase: Equatable {
        case idle
        case ignored
        case candidate(Candidate)
        case sliding(Slide)
        case swiped(TrackpadEdge)
    }

    var configuration: TrackpadEdgeConfiguration
    private(set) var phase: Phase = .idle
    private(set) var pendingTap: PendingTap?
    private(set) var lastTapLiftAt: TimeInterval?
    private(set) var lastTapWasDouble = false
    private var tapGeneration = 0

    init(configuration: TrackpadEdgeConfiguration) {
        self.configuration = configuration
    }

    var isSliding: Bool {
        switch phase {
        case .sliding, .swiped: return true
        default: return false
        }
    }

    var activeEdge: TrackpadEdge? {
        switch phase {
        case .sliding(let slide): return slide.edge
        case .swiped(let edge): return edge
        default: return nil
        }
    }

    var hasCandidate: Bool {
        if case .candidate = phase { return true }
        return false
    }

    var candidateTapTarget: TrackpadTapTarget? {
        if case .candidate(let candidate) = phase { return candidate.tapTarget }
        return nil
    }

    mutating func reset() {
        phase = .idle
        pendingTap = nil
        lastTapLiftAt = nil
        lastTapWasDouble = false
    }

    func zones(x: Float, y: Float) -> TrackpadEdgeZones {
        let config = configuration
        var zones = TrackpadEdgeZones()
        let width = config.edgeWidth
        let band = config.horizontalBand
        if y <= config.activeArea.fraction {
            if x <= width, config.slideAction(.left) != .off {
                zones.vertical = .left
            } else if x >= 1 - width, config.slideAction(.right) != .off {
                zones.vertical = .right
            }
        }
        if y <= band, config.slideAction(.bottom) != .off {
            zones.horizontal = .bottom
        } else if y >= 1 - band, config.slideAction(.top) != .off {
            zones.horizontal = .top
        }
        let nearLeft = x <= config.cornerWidth
        let nearRight = x >= 1 - config.cornerWidth
        let nearTop = y >= 1 - config.cornerHeight
        let nearBottom = y <= config.cornerHeight
        var corner: TrackpadCorner?
        if nearTop && nearLeft { corner = .topLeft }
        if nearTop && nearRight { corner = .topRight }
        if nearBottom && nearLeft { corner = .bottomLeft }
        if nearBottom && nearRight { corner = .bottomRight }
        if let corner, config.cornerAction(corner) != .off {
            zones.tap = .corner(corner)
        } else if y <= band, config.mediaStripArmed {
            zones.tap = .mediaStrip
        }
        return zones
    }

    func tapClickRole(at time: TimeInterval) -> TrackpadTapClickRole {
        if case .candidate(let candidate) = phase, let target = candidate.tapTarget,
           let pendingTap, pendingTap.target == target {
            return .secondTap
        }
        guard phase == .idle, let lastTapLiftAt, time - lastTapLiftAt <= Self.tapClickWindow else {
            return .none
        }
        if lastTapWasDouble { return .secondTap }
        if let pendingTap { return .firstTap(generation: pendingTap.generation) }
        return .none
    }

    func isAwaitingSecondTap(generation: Int) -> Bool {
        guard let pendingTap, pendingTap.generation == generation,
              case .candidate(let candidate) = phase else { return false }
        if let target = candidate.tapTarget, target == pendingTap.target { return true }
        return !pendingTap.armedEdges.isDisjoint(with: [candidate.vertical, candidate.horizontal].compactMap { $0 })
    }

    mutating func process(_ contacts: [TrackpadContact],
                          at time: TimeInterval,
                          startAllowed: () -> Bool) -> [TrackpadEdgeEvent] {
        guard !contacts.isEmpty else { return finishTouch(at: time) }
        switch phase {
        case .idle:
            begin(contacts, at: time, startAllowed: startAllowed)
            return []
        case .ignored, .swiped:
            return []
        case .candidate(let candidate):
            return advance(candidate, contacts: contacts, at: time)
        case .sliding(let slide):
            return advance(slide, contacts: contacts)
        }
    }

    private mutating func begin(_ contacts: [TrackpadContact], at time: TimeInterval,
                                startAllowed: () -> Bool) {
        if let pendingTap, time - pendingTap.liftedAt > Self.doubleTapGap {
            self.pendingTap = nil
        }
        guard contacts.count == 1, let contact = contacts.first else {
            ignore()
            return
        }
        let zones = zones(x: contact.x, y: contact.y)
        guard !zones.isEmpty, startAllowed() else {
            ignore()
            return
        }
        let zoneEdges = Set([zones.vertical, zones.horizontal].compactMap { $0 })
        let armedEdges = pendingTap?.armedEdges.intersection(zoneEdges) ?? []
        let sameTarget = zones.tap != nil && pendingTap?.target == zones.tap
        if pendingTap != nil, !sameTarget, armedEdges.isEmpty {
            self.pendingTap = nil
        }
        let slidable = configuration.tapToSlide ? armedEdges : zoneEdges
        let candidate = Candidate(id: contact.id, startX: contact.x, startY: contact.y, startedAt: time,
                                  vertical: zones.vertical.flatMap { slidable.contains($0) ? $0 : nil },
                                  horizontal: zones.horizontal.flatMap { slidable.contains($0) ? $0 : nil },
                                  tapTarget: zones.tap,
                                  arms: configuration.tapToSlide ? zoneEdges : [])
        phase = .candidate(candidate)
    }

    private mutating func ignore() {
        phase = .ignored
        pendingTap = nil
    }

    private mutating func advance(_ candidate: Candidate, contacts: [TrackpadContact],
                                  at time: TimeInterval) -> [TrackpadEdgeEvent] {
        guard contacts.count == 1, let contact = contacts.first, contact.id == candidate.id else {
            ignore()
            return []
        }
        var candidate = candidate
        let dx = contact.x - candidate.startX
        let dy = contact.y - candidate.startY
        let distance = (dx * dx + dy * dy).squareRoot()
        if time - candidate.startedAt > Self.tapMaxDuration || distance > Self.tapMaxMovement {
            candidate.tapTarget = nil
            candidate.arms = []
        }
        if let edge = candidate.vertical, abs(dy) >= Self.engageDistance,
           abs(dy) >= Self.axisDominance * abs(dx) {
            return engage(edge, id: contact.id, origin: candidate.startY, current: contact.y)
        }
        if let edge = candidate.horizontal, abs(dx) >= Self.engageDistance,
           abs(dx) >= Self.axisDominance * abs(dy) {
            return engage(edge, id: contact.id, origin: candidate.startX, current: contact.x)
        }
        let hasEdge = candidate.vertical != nil || candidate.horizontal != nil
        if distance >= Self.abandonDistance || (!hasEdge && candidate.tapTarget == nil && candidate.arms.isEmpty) {
            ignore()
            return []
        }
        phase = .candidate(candidate)
        return []
    }

    private mutating func engage(_ edge: TrackpadEdge, id: Int32, origin: Float,
                                 current: Float) -> [TrackpadEdgeEvent] {
        pendingTap = nil
        let action = configuration.slideAction(edge)
        var slide = Slide(id: id, edge: edge, action: action, origin: origin,
                          lastAxis: current, accumulated: current - origin)
        var events: [TrackpadEdgeEvent] = [.slideBegan(edge, action)]
        if action == .tracks {
            phase = .sliding(slide)
            return events
        }
        events += drainSteps(&slide)
        phase = .sliding(slide)
        return events
    }

    private mutating func advance(_ slide: Slide, contacts: [TrackpadContact]) -> [TrackpadEdgeEvent] {
        var slide = slide
        let contact: TrackpadContact
        if let same = contacts.first(where: { $0.id == slide.id }) {
            contact = same
        } else if contacts.count == 1, let replacement = contacts.first {
            slide.id = replacement.id
            slide.lastAxis = slide.edge.isVertical ? replacement.y : replacement.x
            if slide.action == .tracks { slide.origin = slide.lastAxis }
            phase = .sliding(slide)
            return []
        } else {
            return []
        }
        let axis = slide.edge.isVertical ? contact.y : contact.x
        if slide.action == .tracks {
            let travel = axis - slide.origin
            guard abs(travel) >= Self.trackSwipeDistance else {
                slide.lastAxis = axis
                phase = .sliding(slide)
                return []
            }
            phase = .swiped(slide.edge)
            return [.trackSkip(direction: travel > 0 ? 1 : -1)]
        }
        slide.accumulated += axis - slide.lastAxis
        slide.lastAxis = axis
        let events = drainSteps(&slide)
        phase = .sliding(slide)
        return events
    }

    private func drainSteps(_ slide: inout Slide) -> [TrackpadEdgeEvent] {
        let distance = configuration.stepDistance
        guard distance > 0 else { return [] }
        var events: [TrackpadEdgeEvent] = []
        while slide.accumulated >= distance, events.count < Self.maxStepsPerFrame {
            slide.accumulated -= distance
            events.append(.step(slide.action, direction: 1))
        }
        while slide.accumulated <= -distance, events.count < Self.maxStepsPerFrame {
            slide.accumulated += distance
            events.append(.step(slide.action, direction: -1))
        }
        if events.count == Self.maxStepsPerFrame {
            slide.accumulated = 0
        }
        return events
    }

    private mutating func finishTouch(at time: TimeInterval) -> [TrackpadEdgeEvent] {
        let finished = phase
        phase = .idle
        switch finished {
        case .sliding(let slide):
            return [.slideEnded(slide.edge)]
        case .swiped(let edge):
            return [.slideEnded(edge)]
        case .candidate(let candidate):
            let target = candidate.tapTarget
            guard target != nil || !candidate.arms.isEmpty,
                  time - candidate.startedAt <= Self.tapMaxDuration else { return [] }
            lastTapLiftAt = time
            if let target, let pendingTap, pendingTap.target == target,
               candidate.startedAt - pendingTap.liftedAt <= Self.doubleTapGap {
                self.pendingTap = nil
                lastTapWasDouble = true
                return [.doubleTap(target, generation: pendingTap.generation)]
            }
            tapGeneration += 1
            pendingTap = PendingTap(target: target, armedEdges: candidate.arms,
                                    liftedAt: time, generation: tapGeneration)
            lastTapWasDouble = false
            return [.firstTap(target, generation: tapGeneration)]
        case .idle, .ignored:
            return []
        }
    }
}

enum TrackpadEdgeLevel {
    static func stepped(_ level: Double, direction: Int, stepSize: Double) -> Double {
        guard level.isFinite, stepSize > 0 else { return level }
        return min(1, max(0, level + Double(direction.signum()) * stepSize))
    }
}

enum TrackpadMediaKey: Int32 {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case playPause = 16
    case nextTrack = 19
    case previousTrack = 20
    case illuminationUp = 21
    case illuminationDown = 22

    static let fineFlags: UInt = 0x80000 | 0x20000

    func halves(fine: Bool) -> [(data1: Int, flags: UInt)] {
        [0x0A, 0x0B].map { state in
            let data1 = Int(rawValue << 16) | (state << 8)
            return (data1, UInt(state << 8) | (fine ? Self.fineFlags : 0))
        }
    }

    func events(fine: Bool, marker: Int64? = nil) -> [CGEvent] {
        halves(fine: fine).compactMap { half -> CGEvent? in
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: half.flags),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: half.data1, data2: -1)?.cgEvent
            else { return nil }
            if let marker { event.setIntegerValueField(.eventSourceUserData, value: marker) }
            return event
        }
    }
}
