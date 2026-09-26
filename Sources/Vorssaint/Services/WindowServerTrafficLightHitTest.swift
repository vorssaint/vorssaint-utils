// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Cheap front-to-back WindowServer lookup used before asking another app
/// about its Accessibility tree. This keeps ordinary mouse clicks away from
/// cross-process waits while still pinning a later drag to the same window.
enum WindowServerWindowHitTest {
    static func candidate(at point: CGPoint,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> WindowServerWindowCandidate? {
        WindowServerSupport.windowCandidate(in: WindowServerSupport.onScreenWindowInfo(),
                                            at: point,
                                            ownProcessID: getpid(),
                                            pidIsEligible: pidIsEligible)
    }
}

enum WindowServerTrafficLightHitTest {
    // Cheap WindowServer gate before AX hit-testing. Some apps can stall when
    // queried through Accessibility in the middle of ordinary mouse clicks.
    static func candidate(at point: CGPoint,
                          button: TrafficLightButton,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> TrafficLightCandidate? {
        WindowServerSupport.trafficLightCandidate(in: WindowServerSupport.onScreenWindowInfo(),
                                                  at: point,
                                                  button: button,
                                                  ownProcessID: getpid(),
                                                  pidIsEligible: pidIsEligible)
    }
}
