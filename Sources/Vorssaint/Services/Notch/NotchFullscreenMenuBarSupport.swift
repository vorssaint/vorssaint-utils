// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Decisions for keeping the menu bar in full-screen apps on the notched
/// built-in display, and letting it hide while full-screen video plays.
/// Everything here is pure; `NotchFullscreenMenuBarService` reads the system.
enum NotchFullscreenMenuBarSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchFullscreenMenuBar.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchFullscreenMenuBarEnabled)
    }

    /// macOS keeps the bar in full screen (*Never* or *On Desktop Only*), so
    /// releasing the override cannot hide it for video. The global domain
    /// stores the four choices as two booleans.
    static func systemShowsBarInFullscreen(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "AppleMenuBarVisibleInFullscreen")
    }

    struct Inputs: Equatable {
        /// The app owning the notched display's current full-screen Space.
        var fullscreenApp: pid_t?
        /// That app, or a helper it is responsible for, keeps the display awake.
        var playsVideo: Bool
        /// Any input device is running: a call keeps the display awake too.
        var microphoneInUse: Bool
        /// The app shows a toolbar, tab strip or sidebar of its own on the
        /// display. nil without Accessibility.
        var appShowsOwnUI: Bool?
        /// *Automatically hide and show the menu bar* is *Always*.
        var systemHidesBarOnDesktop = false
    }

    enum Decision: Equatable {
        /// Hold the override: the window server shows the bar on the display.
        case show
        /// Release it: macOS shows or hides the bar by its own setting.
        case release
    }

    /// The override is held outside full screen too, where the bar shows
    /// anyway: applied only once a full-screen Space appears, macOS hides the
    /// bar first and it flashes away. With *Always* the desktop would gain a
    /// bar it is set to hide, so there the override follows full screen.
    static func decide(_ inputs: Inputs) -> Decision {
        guard inputs.fullscreenApp != nil else { return inputs.systemHidesBarOnDesktop ? .release : .show }
        guard inputs.playsVideo, !inputs.microphoneInUse, inputs.appShowsOwnUI != true else { return .show }
        return .release
    }

    /// Video has the display to itself: the bar is let go in a full-screen
    /// app and macOS hides it there. The island steps out of the strip
    /// with it, so no artwork or level meter stays beside the notch.
    static func videoHidesBar(_ inputs: Inputs, systemShowsBarInFullscreen: Bool) -> Bool {
        inputs.fullscreenApp != nil && !systemShowsBarInFullscreen && decide(inputs) == .release
    }

    // MARK: - The app's own UI

    /// Is `element` app UI along an edge of the window on this display: a
    /// toolbar or tab strip across the top, or a tab strip or sidebar down one
    /// side? Rects are in top-left (window server and Accessibility)
    /// coordinates. A part off the display counts for nothing: browsers park a
    /// hidden toolbar above the screen. A toolbar revealed under the menu bar
    /// sits a little below the window's top. Bottom bars are left out: a
    /// player's controls belong to the video.
    static func isEdgeBar(_ element: CGRect, window: CGRect, display: CGRect) -> Bool {
        // Not clipped to the window: a browser's toolbar can sit above it.
        let visible = element.intersection(display)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1, window.width > 0, window.height > 0
        else { return false }
        let thinnest: CGFloat = 36
        let slack: CGFloat = 2
        let nearTop = visible.minY <= max(window.minY, display.minY) + 64
        let top = nearTop && visible.width >= window.width * 0.5
            && visible.height >= thinnest && visible.height <= window.height * 0.35
        let side = (abs(visible.minX - window.minX) <= slack || abs(visible.maxX - window.maxX) <= slack)
            && visible.height >= window.height * 0.6
            && visible.width >= thinnest && visible.width <= window.width * 0.35
        return top || side
    }

    static func edgeBarsVisible(_ elements: [CGRect], window: CGRect, display: CGRect) -> Bool {
        elements.contains { isEdgeBar($0, window: window, display: display) }
    }

    /// Roles that can hold a toolbar, tab strip or sidebar, or wrap content.
    static let containerRoles: Set<String> = ["AXGroup", "AXToolbar", "AXTabGroup", "AXSplitGroup", "AXList",
                                              "AXOutline"]
    /// Chrome nests four containers the window's size before its bars;
    /// its web view sits two levels below them.
    static let maximumWalkDepth = 5
    static let maximumContainersRead = 40

    /// From a window down through containers the same size as their parent,
    /// collecting the frames of the elements beside them: bars and the
    /// content area. Only those wrappers are opened, never content, and never
    /// past `maximumWalkDepth`, so a browser's web accessibility tree is not
    /// asked for.
    static func edgeCandidates<Element>(of window: Element, frame windowFrame: CGRect,
                                        children: (Element) -> [Element], role: (Element) -> String?,
                                        frame: (Element) -> CGRect?, shouldContinue: () -> Bool = { true })
        -> [CGRect] {
        var queue: [(element: Element, frame: CGRect, depth: Int)] = [(window, windowFrame, 0)]
        var found: [CGRect] = []
        var read = 0
        while !queue.isEmpty, read < maximumContainersRead, shouldContinue() {
            let (element, elementFrame, depth) = queue.removeFirst()
            read += 1
            for child in children(element).prefix(16) {
                guard let childRole = role(child), containerRoles.contains(childRole),
                      let childFrame = frame(child) else { continue }
                if depth + 1 < maximumWalkDepth, sameRect(childFrame, elementFrame) {
                    queue.append((child, childFrame, depth + 1))
                } else {
                    found.append(childFrame)
                }
            }
        }
        return found
    }

    static func sameRect(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.maxX - b.maxX) <= 2 && abs(a.maxY - b.maxY) <= 2
    }

    // MARK: - Video

    /// Assertion types that keep the display on. Browsers, players and call
    /// apps take one while video or a call is on screen.
    static let displayAwakeTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    /// Apps keeping the display awake, from `IOPMCopyAssertionsByProcess`
    /// keyed by pid. A helper process (a browser's GPU or media process)
    /// counts for the app responsible for it.
    static func displayAwakeOwners(_ assertionsByPID: [pid_t: [[String: Any]]],
                                   owner: (pid_t) -> pid_t) -> Set<pid_t> {
        var owners = Set<pid_t>()
        for (pid, assertions) in assertionsByPID {
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String, displayAwakeTypes.contains(type),
                      (assertion["AssertLevel"] as? Int ?? 255) != 0 else { continue }
                owners.insert(owner(pid))
                if let onBehalf = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value, onBehalf > 0 {
                    owners.insert(owner(onBehalf))
                }
            }
        }
        return owners
    }
}
