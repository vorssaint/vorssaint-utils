// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MissionControlAction: String, CaseIterable, Identifiable {
    case none
    case closeWindow
    case minimizeWindow
    case terminateApp
    case hideApp

    var id: String { rawValue }

    static func sanitized(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .none
    }
}

struct MissionControlActionSettings: Equatable {
    let rightClick: MissionControlAction
    let middleClick: MissionControlAction
    let keyboardShortcutsEnabled: Bool
}

enum MissionControlInput: Equatable {
    case rightClick
    case middleClick
    case commandW
    case commandQ
    case commandH
    case commandM
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case enter
    case other
}

struct MissionControlTileSnapshot: Equatable {
    let frame: CGRect
    let role: String
    let windowID: CGWindowID
}

struct MissionControlWindowSnapshot: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerIsWindowManager: Bool
    let layer: Int
    let bounds: CGRect
    let onScreen: Bool
    let alpha: Double
}

struct MissionControlDetectionSnapshot: Equatable {
    let windowManagerBundleIdentifier: String?
    let displayIdentifier: String?
    let displayFrame: CGRect?
    let displayChildrenCount: Int
    let tiles: [MissionControlTileSnapshot]
    let windows: [MissionControlWindowSnapshot]
    let screenFrames: [CGRect]
    let axTreeComplete: Bool
    let stageManagerEnabled: Bool
    let ownPID: pid_t
}

struct MissionControlTarget: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let tileFrame: CGRect
}

struct MissionControlProcessIdentity: Equatable {
    let processIdentifier: pid_t
    let launchTime: TimeInterval
}

struct MissionControlValidatedTarget: Equatable {
    let target: MissionControlTarget
    let processIdentity: MissionControlProcessIdentity
    let windowResolved: Bool
}

struct MissionControlPendingAction: Equatable {
    let target: MissionControlValidatedTarget
    let action: MissionControlAction
}

struct MissionControlSnapshotTiming: Equatable {
    static let maximumCaptureDuration: TimeInterval = 0.25
    static let maximumAge: TimeInterval = 0.45

    let startedAt: TimeInterval
    let finishedAt: TimeInterval

    func isUsable(now: TimeInterval) -> Bool {
        finishedAt >= startedAt
            && finishedAt - startedAt <= Self.maximumCaptureDuration
            && now >= startedAt
            && now - startedAt <= Self.maximumAge
    }
}

struct MissionControlRuntimeDecision: Equatable {
    let monitor: Bool
    let captureAX: Bool
    let holdEventTap: Bool
}

struct MissionControlRuntimeConditions: Equatable {
    let featureWanted: Bool
    let accessibilityGranted: Bool
    let sessionIsActive: Bool
    let stageManagerEnabled: Bool
    let cgWindowSignaturePresent: Bool
    let axGatePositive: Bool
    let snapshotFresh: Bool

    var decision: MissionControlRuntimeDecision {
        let monitor = featureWanted && accessibilityGranted && sessionIsActive
            && !stageManagerEnabled
        let captureAX = monitor && cgWindowSignaturePresent
        return MissionControlRuntimeDecision(
            monitor: monitor,
            captureAX: captureAX,
            holdEventTap: captureAX && axGatePositive && snapshotFresh
        )
    }

    func replacing(featureWanted: Bool? = nil,
                   accessibilityGranted: Bool? = nil,
                   sessionIsActive: Bool? = nil,
                   stageManagerEnabled: Bool? = nil,
                   cgWindowSignaturePresent: Bool? = nil,
                   axGatePositive: Bool? = nil,
                   snapshotFresh: Bool? = nil) -> Self {
        Self(featureWanted: featureWanted ?? self.featureWanted,
             accessibilityGranted: accessibilityGranted ?? self.accessibilityGranted,
             sessionIsActive: sessionIsActive ?? self.sessionIsActive,
             stageManagerEnabled: stageManagerEnabled ?? self.stageManagerEnabled,
             cgWindowSignaturePresent: cgWindowSignaturePresent ?? self.cgWindowSignaturePresent,
             axGatePositive: axGatePositive ?? self.axGatePositive,
             snapshotFresh: snapshotFresh ?? self.snapshotFresh)
    }
}

enum MissionControlRevalidationDecision: Equatable {
    case perform
    case replayEvents
}

enum MissionControlRevalidationSupport {
    static func decision(original: MissionControlPendingAction,
                         freshTarget: MissionControlValidatedTarget?,
                         ownPID: pid_t) -> MissionControlRevalidationDecision {
        guard let freshTarget,
              freshTarget.windowResolved,
              freshTarget.target.windowID == original.target.target.windowID,
              freshTarget.target.ownerPID == original.target.target.ownerPID,
              freshTarget.target.ownerPID != ownPID,
              freshTarget.processIdentity == original.target.processIdentity,
              freshTarget.processIdentity.processIdentifier == freshTarget.target.ownerPID
        else { return .replayEvents }
        return .perform
    }
}

enum MissionControlActionsSupport {
    static let windowManagerBundleIdentifier = "com.apple.WindowManager"
    static let displayIdentifier = "mc.display"
    static let dragSlop: CGFloat = 6

    static func cgWindowSignaturePresent(in windows: [MissionControlWindowSnapshot]) -> Bool {
        let visible = windows.filter { $0.ownerIsWindowManager && $0.onScreen && $0.alpha > 0 }
        return visible.contains { $0.layer == 0 }
            && visible.contains { $0.layer == 2 }
            && visible.contains { $0.layer == 19 }
    }

    static func action(for input: MissionControlInput,
                       settings: MissionControlActionSettings) -> MissionControlAction? {
        switch input {
        case .rightClick:
            return settings.rightClick
        case .middleClick:
            return settings.middleClick
        case .commandW:
            return settings.keyboardShortcutsEnabled ? .closeWindow : nil
        case .commandQ:
            return settings.keyboardShortcutsEnabled ? .terminateApp : nil
        case .commandH:
            return settings.keyboardShortcutsEnabled ? .hideApp : nil
        case .commandM:
            return settings.keyboardShortcutsEnabled ? .minimizeWindow : nil
        case .leftArrow, .rightArrow, .upArrow, .downArrow, .enter, .other:
            return nil
        }
    }

    /// A positive result deliberately needs the complete signature measured
    /// on macOS 27. Every missing, duplicated or contradictory value is
    /// uncertainty and therefore a native pass-through.
    static func target(at point: CGPoint,
                       in snapshot: MissionControlDetectionSnapshot) -> MissionControlTarget? {
        guard snapshot.windowManagerBundleIdentifier == windowManagerBundleIdentifier,
              snapshot.axTreeComplete,
              !snapshot.stageManagerEnabled,
              snapshot.displayIdentifier == displayIdentifier,
              snapshot.displayChildrenCount >= 2,
              let displayFrame = snapshot.displayFrame,
              snapshot.screenFrames.contains(where: { approximatelyEqual($0, displayFrame) })
        else { return nil }

        let buttons = snapshot.tiles.filter { $0.role == "AXButton" }
        guard buttons.count >= 2,
              Set(buttons.map(\.windowID)).count == buttons.count else { return nil }

        let realWindowsByID = Dictionary(grouping: snapshot.windows.filter {
            !$0.ownerIsWindowManager && $0.ownerPID > 0 && $0.ownerPID != snapshot.ownPID
                && $0.onScreen && $0.alpha > 0
        }, by: \.windowID)
        guard buttons.allSatisfy({ realWindowsByID[$0.windowID]?.count == 1 }) else { return nil }
        let ownerPIDs = Set(buttons.compactMap { realWindowsByID[$0.windowID]?.first?.ownerPID })
        // App Expose shows one app. Requiring two owners is intentionally
        // conservative: Mission Control with only one app stays native.
        guard ownerPIDs.count >= 2 else { return nil }

        let hits = buttons.filter { $0.frame.contains(point) }
        guard hits.count == 1, let tile = hits.first,
              let matches = realWindowsByID[tile.windowID], matches.count == 1,
              let realWindow = matches.first,
              !snapshot.screenFrames.contains(where: {
                  approximatelyEqual($0, realWindow.bounds, tolerance: 2)
              }) else { return nil }

        let hoverWindows = snapshot.windows.filter {
            $0.ownerIsWindowManager && $0.layer == 0 && $0.onScreen && $0.alpha > 0
                && closelyEncloses($0.bounds, tile.frame)
        }
        guard hoverWindows.count == 1,
              snapshot.windows.contains(where: {
                  $0.ownerIsWindowManager && $0.layer == 2 && $0.onScreen && $0.alpha > 0
                      && displayFrame.intersects($0.bounds)
              }),
              snapshot.windows.contains(where: {
                  $0.ownerIsWindowManager && $0.layer == 19 && $0.onScreen && $0.alpha > 0
                      && approximatelyEqual($0.bounds, displayFrame, tolerance: 2)
              }) else { return nil }

        return MissionControlTarget(windowID: tile.windowID,
                                    ownerPID: realWindow.ownerPID,
                                    tileFrame: tile.frame)
    }

    private static func closelyEncloses(_ outer: CGRect, _ inner: CGRect) -> Bool {
        guard outer.width >= inner.width, outer.height >= inner.height,
              outer.width - inner.width <= 48, outer.height - inner.height <= 48 else {
            return false
        }
        return abs(outer.minX - inner.minX) <= 24
            && abs(outer.minY - inner.minY) <= 24
            && abs(outer.maxX - inner.maxX) <= 24
            && abs(outer.maxY - inner.maxY) <= 24
    }

    private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect,
                                           tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

enum MissionControlPointerButton: Equatable {
    case right
    case middle
}

enum MissionControlPointerDecision: Equatable {
    case passThrough
    case suppress
    case replayDownAndPass
    case revalidate(MissionControlPendingAction)
    case replayPairNoAction
}

enum MissionControlPendingResolution: Equatable {
    case none
    case replayIfStillHeld
}

struct MissionControlPointerGesture {
    static let maximumHoldDuration: TimeInterval = 1.5

    private struct Pending: Equatable {
        let button: MissionControlPointerButton
        let origin: CGPoint
        let target: MissionControlValidatedTarget
        let action: MissionControlAction
        let startedAt: TimeInterval
    }

    private var pending: Pending?

    mutating func resolveBeforeNewDown() -> MissionControlPendingResolution {
        guard pending != nil else { return .none }
        pending = nil
        return .replayIfStillHeld
    }

    mutating func beginDown(button: MissionControlPointerButton,
                            point: CGPoint,
                            target: MissionControlValidatedTarget?,
                            action: MissionControlAction,
                            now: TimeInterval) -> MissionControlPointerDecision {
        pending = nil
        guard let target, action != .none else { return .passThrough }
        pending = Pending(button: button, origin: point, target: target,
                          action: action, startedAt: now)
        return .suppress
    }

    mutating func drag(button: MissionControlPointerButton,
                       point: CGPoint) -> MissionControlPointerDecision {
        guard let candidate = pending, candidate.button == button else { return .passThrough }
        let dx = point.x - candidate.origin.x
        let dy = point.y - candidate.origin.y
        if (dx * dx + dy * dy).squareRoot() > MissionControlActionsSupport.dragSlop {
            pending = nil
            return .replayDownAndPass
        }
        return .suppress
    }

    mutating func endUp(button: MissionControlPointerButton,
                        point _: CGPoint,
                        now: TimeInterval) -> MissionControlPointerDecision {
        guard let candidate = pending, candidate.button == button else { return .passThrough }
        pending = nil
        guard now >= candidate.startedAt,
              now - candidate.startedAt <= Self.maximumHoldDuration else {
            return .replayPairNoAction
        }
        return .revalidate(MissionControlPendingAction(
            target: candidate.target, action: candidate.action
        ))
    }

    mutating func expire(now: TimeInterval) -> MissionControlPendingResolution {
        guard let candidate = pending,
              now < candidate.startedAt
                || now - candidate.startedAt > Self.maximumHoldDuration else { return .none }
        pending = nil
        return .replayIfStillHeld
    }

    mutating func reset() -> MissionControlPendingResolution {
        guard pending != nil else { return .none }
        pending = nil
        return .replayIfStillHeld
    }
}
