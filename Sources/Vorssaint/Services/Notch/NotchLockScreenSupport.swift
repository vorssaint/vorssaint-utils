// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

/// What the lock screen reads out under the clock, in the order the line
/// gives them up when it runs short.
enum NotchLockScreenActivity: String, CaseIterable, Identifiable {
    case timer, calendar, agents, downloads

    var id: String { rawValue }
}

enum NotchLockScreenSupport {
    /// The Space level macOS gives the notifications it shows over the lock
    /// screen, one step above the lock screen's own 300. A window in a Space
    /// at this level is drawn over the lock screen; the same window without
    /// it, even at the shielding window level, stays behind it.
    static let spaceLevel: Int32 = 400

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockScreen)
    }

    static func playsSounds(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockSounds)
    }

    /// Music follows the island's Music section, not its resting choice: an
    /// island that rests empty still has music to show when locked.
    static func showsMusic(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.modules(in: defaults).contains(.music)
    }

    /// A paused song stays while the Mac is locked once it has played there,
    /// so it can be resumed; one paused long before never takes the screen.
    static func showsMusic(isPlaying: Bool, playedWhileLocked: Bool) -> Bool {
        isPlaying || playedWhileLocked
    }

    /// The timer is suspended while locked, so a countdown that reaches its
    /// end there is read as finished rather than stuck at zero.
    static func timerFinished(_ session: NotchTimerSession, at now: TimeInterval) -> Bool {
        session.completed || session.deadline.map { now >= $0 } == true
    }

    static func activities(timer: Bool, calendar: Bool, agents: Bool, downloads: Bool) -> [NotchLockScreenActivity] {
        NotchLockScreenActivity.allCases.filter {
            switch $0 {
            case .timer: return timer
            case .calendar: return calendar
            case .agents: return agents
            case .downloads: return downloads
            }
        }
    }

    /// A song's position, as the island's player shows it.
    static func timestamp(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? Int(min(604_800, max(0, interval))) : 0
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// The padlock sounds macOS plays in its own settings. A release that
    /// moves them falls back to alert sounds rather than going quiet.
    static func soundURL(locking: Bool, fileManager: FileManager = .default) -> URL? {
        if let padlock = Bundle(path: "/System/Library/Frameworks/SecurityInterface.framework")?
            .url(forResource: locking ? "lock" : "unlock", withExtension: "aif") {
            return padlock
        }
        let alert = URL(fileURLWithPath: "/System/Library/Sounds/\(locking ? "Tink" : "Pop").aiff")
        return fileManager.fileExists(atPath: alert.path) ? alert : nil
    }
}

/// macOS draws the lock screen's date, clock and login controls in one window
/// over the whole display, so their room is kept by measure. On macOS 26 and
/// 27 the date and clock end 236 points from the top of a 956-point display,
/// and the name, picture, password field and hint take the lowest 218.
/// Activities read as a line under the clock, where a phone keeps its lock
/// screen widgets; music plays on its pane between that line and the login
/// controls.
enum NotchLockScreenLayout {
    /// A taller display draws a larger clock.
    static func clockBottom(screenHeight: CGFloat) -> CGFloat { max(236, screenHeight * 0.247) }
    static let rowGap: CGFloat = 18
    static let rowHeight: CGFloat = 30
    /// From the bottom of the display to the player.
    static let loginClearance: CGFloat = 250
    /// The player's room, with space around its pane for the cover's glow.
    static let playerWidth: CGFloat = 460
    static let paneWidth: CGFloat = 404
    /// A title, the timeline and the buttons, the least the player shows.
    static let minimumPlayerHeight: CGFloat = 190

    private static func readable(_ screen: CGRect) -> Bool {
        [screen.minX, screen.minY, screen.width, screen.height].allSatisfy(\.isFinite)
            && screen.width >= playerWidth + 32 && screen.height > 0
    }

    /// The line of activities under the clock.
    static func rowFrame(in screen: CGRect) -> CGRect? {
        guard readable(screen) else { return nil }
        let width = min(screen.width - 64, 1000)
        let top = screen.maxY - clockBottom(screenHeight: screen.height) - rowGap
        guard top - rowHeight >= screen.minY + loginClearance else { return nil }
        return CGRect(x: (screen.midX - width / 2).rounded(), y: top - rowHeight, width: width, height: rowHeight)
    }

    /// The player's room: under the line of activities, over the login controls.
    static func playerFrame(in screen: CGRect) -> CGRect? {
        guard let row = rowFrame(in: screen) else { return nil }
        let bottom = screen.minY + loginClearance
        let height = row.minY - 10 - bottom
        guard height >= minimumPlayerHeight else { return nil }
        return CGRect(x: (screen.midX - playerWidth / 2).rounded(), y: bottom, width: playerWidth, height: height)
    }

    /// The island as it rests with something beside the camera: one wing on
    /// each side, the padlock in the first.
    static let islandWing: CGFloat = 44

    /// The locked island hung from the top of `screen`, around its camera.
    static func islandFrame(in screen: CGRect, cameraWidth: CGFloat, cameraHeight: CGFloat) -> CGRect? {
        guard [screen.width, screen.height, cameraWidth, cameraHeight].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let width = min(screen.width - 24, cameraWidth + islandWing * 2)
        guard width > cameraWidth else { return nil }
        // Centred on the camera to the half point: a notch only comes on Retina displays.
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - cameraHeight, width: width, height: cameraHeight)
    }
}
