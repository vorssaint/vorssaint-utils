// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
@preconcurrency import CoreGraphics
import Foundation
import os

/// Snapshot of display transaction parameters prior to applying a display configuration mutation.
public struct DisplayTransactionSnapshot: @unchecked Sendable {
    public let targetDisplayID: CGDirectDisplayID
    public let previousMode: CGDisplayMode?
    public let previousCGSModeNumber: Int32?
    public let previousMirrorMasterID: CGDirectDisplayID?
    public let virtualDisplayCreated: Bool
    public let timestamp: Date

    public init(
        targetDisplayID: CGDirectDisplayID,
        previousMode: CGDisplayMode? = nil,
        previousCGSModeNumber: Int32? = nil,
        previousMirrorMasterID: CGDirectDisplayID? = nil,
        virtualDisplayCreated: Bool = false,
        timestamp: Date = Date()
    ) {
        self.targetDisplayID = targetDisplayID
        self.previousMode = previousMode
        self.previousCGSModeNumber = previousCGSModeNumber
        self.previousMirrorMasterID = previousMirrorMasterID
        self.virtualDisplayCreated = virtualDisplayCreated
        self.timestamp = timestamp
    }
}

/// Coordinates display mutation safety with a 15-second watchdog timer and automatic rollback.
public final class DisplayRecoveryManager: ObservableObject, @unchecked Sendable {
    public static let shared = DisplayRecoveryManager()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
        category: "display-recovery"
    )

    @Published public private(set) var awaitingConfirmation: Bool = false
    @Published public private(set) var remainingSeconds: Int = 15
    @Published public private(set) var currentSnapshot: DisplayTransactionSnapshot?

    private var timer: DispatchSourceTimer?

    private init() {}

    deinit {
        cancelTimer()
    }

    /// Begins a monitored display mutation action with a countdown watchdog.
    public func beginAction(
        targetDisplayID: CGDirectDisplayID,
        previousMode: CGDisplayMode? = nil,
        previousCGSModeNumber: Int32? = nil,
        previousMirrorMasterID: CGDirectDisplayID? = nil,
        virtualDisplayCreated: Bool = false,
        confirmationSeconds: Int = 15
    ) {
        if Thread.isMainThread {
            _beginAction(
                targetDisplayID: targetDisplayID,
                previousMode: previousMode,
                previousCGSModeNumber: previousCGSModeNumber,
                previousMirrorMasterID: previousMirrorMasterID,
                virtualDisplayCreated: virtualDisplayCreated,
                confirmationSeconds: confirmationSeconds
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._beginAction(
                    targetDisplayID: targetDisplayID,
                    previousMode: previousMode,
                    previousCGSModeNumber: previousCGSModeNumber,
                    previousMirrorMasterID: previousMirrorMasterID,
                    virtualDisplayCreated: virtualDisplayCreated,
                    confirmationSeconds: confirmationSeconds
                )
            }
        }
    }

    private func _beginAction(
        targetDisplayID: CGDirectDisplayID,
        previousMode: CGDisplayMode?,
        previousCGSModeNumber: Int32?,
        previousMirrorMasterID: CGDirectDisplayID?,
        virtualDisplayCreated: Bool,
        confirmationSeconds: Int
    ) {
        cancelTimer()
        let snapshot = DisplayTransactionSnapshot(
            targetDisplayID: targetDisplayID,
            previousMode: previousMode,
            previousCGSModeNumber: previousCGSModeNumber,
            previousMirrorMasterID: previousMirrorMasterID,
            virtualDisplayCreated: virtualDisplayCreated,
            timestamp: Date()
        )
        self.currentSnapshot = snapshot
        let seconds = max(1, confirmationSeconds)
        self.remainingSeconds = seconds
        self.awaitingConfirmation = true
        Self.log.info("Display mutation started for display \(targetDisplayID, privacy: .public). Watchdog started with \(seconds)s countdown.")
        startTimer()
    }

    /// Confirms the current display configuration and cancels the watchdog timer.
    public func confirm() {
        if Thread.isMainThread {
            _confirm()
        } else {
            DispatchQueue.main.sync {
                self._confirm()
            }
        }
    }

    private func _confirm() {
        cancelTimer()
        remainingSeconds = 0
        awaitingConfirmation = false
        currentSnapshot = nil
        Self.log.info("Display configuration change confirmed by user.")
    }

    /// Rolls back display configuration to the state recorded in the active snapshot.
    public func rollback() {
        if Thread.isMainThread {
            _rollback()
        } else {
            DispatchQueue.main.sync {
                self._rollback()
            }
        }
    }

    private func _rollback() {
        cancelTimer()
        guard let snapshot = currentSnapshot else {
            remainingSeconds = 0
            awaitingConfirmation = false
            return
        }

        Self.log.warning("Rolling back display configuration for display \(snapshot.targetDisplayID, privacy: .public)...")

        // 1. If virtual display was created, teardown the virtual mirror
        if snapshot.virtualDisplayCreated {
            do {
                try VirtualDisplayService.shared.disableVirtualMirror(for: snapshot.targetDisplayID)
                Self.log.info("Disabled virtual mirror for display \(snapshot.targetDisplayID, privacy: .public).")
            } catch {
                Self.log.error("Failed to disable virtual mirror for display \(snapshot.targetDisplayID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2. Restore mirror or mode if needed
        let needsMirrorRestore = snapshot.previousMirrorMasterID != nil && (!snapshot.virtualDisplayCreated || snapshot.previousMirrorMasterID != kCGNullDirectDisplay)
        let needsModeRestore = snapshot.previousCGSModeNumber != nil || snapshot.previousMode != nil

        if needsMirrorRestore || needsModeRestore {
            var config: CGDisplayConfigRef?
            let beginErr = CGBeginDisplayConfiguration(&config)
            if beginErr == .success, let cfg = config {
                var hasChanges = false

                if let masterID = snapshot.previousMirrorMasterID,
                   (!snapshot.virtualDisplayCreated || masterID != kCGNullDirectDisplay) {
                    let mirrorErr = CGConfigureDisplayMirrorOfDisplay(cfg, snapshot.targetDisplayID, masterID)
                    if mirrorErr == .success {
                        hasChanges = true
                        Self.log.info("Configured mirror master \(masterID, privacy: .public) for display \(snapshot.targetDisplayID, privacy: .public).")
                    } else {
                        Self.log.error("Failed to restore mirror configuration for display \(snapshot.targetDisplayID, privacy: .public) to master \(masterID, privacy: .public): \(mirrorErr.rawValue, privacy: .public)")
                    }
                }

                if let cgsModeNumber = snapshot.previousCGSModeNumber {
                    let modeErr = SkyLightBridge.configureDisplayMode(config: cfg, displayID: snapshot.targetDisplayID, modeNumber: cgsModeNumber)
                    if modeErr == .success {
                        hasChanges = true
                        Self.log.info("Configured CGS mode number \(cgsModeNumber, privacy: .public) for display \(snapshot.targetDisplayID, privacy: .public).")
                    } else {
                        Self.log.error("Failed to restore CGS mode \(cgsModeNumber, privacy: .public) for display \(snapshot.targetDisplayID, privacy: .public): \(modeErr.rawValue, privacy: .public). Attempting CGDisplayMode fallback...")
                        if let previousMode = snapshot.previousMode {
                            let fallbackErr = CGConfigureDisplayWithDisplayMode(cfg, snapshot.targetDisplayID, previousMode, nil)
                            if fallbackErr == .success {
                                hasChanges = true
                                Self.log.info("Configured CGDisplayMode fallback for display \(snapshot.targetDisplayID, privacy: .public).")
                            } else {
                                Self.log.error("Fallback CGConfigureDisplayWithDisplayMode also failed: \(fallbackErr.rawValue, privacy: .public)")
                            }
                        }
                    }
                } else if let previousMode = snapshot.previousMode {
                    let modeErr = CGConfigureDisplayWithDisplayMode(cfg, snapshot.targetDisplayID, previousMode, nil)
                    if modeErr == .success {
                        hasChanges = true
                        Self.log.info("Configured CGDisplayMode for display \(snapshot.targetDisplayID, privacy: .public).")
                    } else {
                        Self.log.error("Failed to restore CGDisplayMode for display \(snapshot.targetDisplayID, privacy: .public): \(modeErr.rawValue, privacy: .public)")
                    }
                }

                if hasChanges {
                    let completeErr = CGCompleteDisplayConfiguration(cfg, .forSession)
                    if completeErr != .success {
                        Self.log.error("Failed to complete display configuration rollback: \(completeErr.rawValue, privacy: .public)")
                        CGCancelDisplayConfiguration(cfg)
                    } else {
                        Self.log.info("Successfully completed display configuration rollback transaction.")
                    }
                } else {
                    CGCancelDisplayConfiguration(cfg)
                }
            } else {
                Self.log.error("CGBeginDisplayConfiguration failed during rollback: \(beginErr.rawValue, privacy: .public)")
            }
        }

        remainingSeconds = 0
        awaitingConfirmation = false
        currentSnapshot = nil
        Self.log.info("Display configuration rollback finished.")
    }

    /// Performs cleanup on application termination: rolls back unconfirmed changes and destroys virtual displays.
    public func cleanupOnExit() {
        if Thread.isMainThread {
            _cleanupOnExit()
        } else {
            DispatchQueue.main.sync {
                self._cleanupOnExit()
            }
        }
    }

    private func _cleanupOnExit() {
        Self.log.info("DisplayRecoveryManager executing cleanup on exit.")
        if awaitingConfirmation {
            Self.log.warning("Display configuration transaction was still pending at exit. Performing rollback.")
            _rollback()
        }
        VirtualDisplayService.shared.destroyAll()
    }

    private func startTimer() {
        cancelTimer()
        let timerSource = DispatchSource.makeTimerSource(queue: .main)
        timerSource.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timerSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.tick()
        }
        self.timer = timerSource
        timerSource.resume()
    }

    private func cancelTimer() {
        if let existing = timer {
            existing.cancel()
            timer = nil
        }
    }

    private func tick() {
        guard awaitingConfirmation else {
            cancelTimer()
            return
        }
        if remainingSeconds > 1 {
            remainingSeconds -= 1
        } else {
            remainingSeconds = 0
            Self.log.warning("Display confirmation timeout expired. Triggering watchdog rollback.")
            _rollback()
        }
    }
}
