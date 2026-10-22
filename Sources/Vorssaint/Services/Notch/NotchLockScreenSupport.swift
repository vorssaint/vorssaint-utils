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

    /// The AI rail right of the stage, with the AI section on.
    static func showsAgents(in defaults: UserDefaults = .standard) -> Bool {
        NotchAgentSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockScreenAgents)
    }

    /// This Mac: the rail left of the stage and the calendar on it. It needs
    /// no section of the island: its readings come from the system monitor,
    /// power and calendar.
    static func showsMac(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchLockScreenMac)
    }

    /// The moon wallpaper moves only over the lock screen it belongs to.
    static func showsWallpaper(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockWallpaper)
    }

    /// Events read Busy instead of their titles, with no locations.
    static func hidesEventTitles(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchLockScreenMacHideEvents)
    }

    /// What the widget keeps from anyone at the Mac who has not unlocked it.
    static func agentPrivacy(in defaults: UserDefaults = .standard) -> NotchAgentPrivacy {
        NotchAgentPrivacy(hidesProjects: defaults.bool(forKey: DefaultsKey.notchLockScreenAgentsHideProjects),
                          hidesAmounts: defaults.bool(forKey: DefaultsKey.notchLockScreenAgentsHideAmounts))
    }

    /// The line's agent readout: the time worked in place of a cost the
    /// person chose to hide.
    static func lineReadout(_ readout: NotchAgentReadout, privacy: NotchAgentPrivacy) -> NotchAgentReadout {
        readout == .cost && privacy.hidesAmounts ? .elapsed : readout
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

/// How a reading stands: green, yellow or red on the lock screen's rings.
enum NotchLockScreenLevel: Equatable {
    case good, warning, critical
}

extension NotchLockScreenSupport {
    /// CPU, GPU and memory in use: green under half, yellow to 80%, red above.
    static func loadLevel(_ fraction: Double) -> NotchLockScreenLevel {
        fraction >= 0.8 ? .critical : fraction >= 0.5 ? .warning : .good
    }

    /// A chip's temperature in Celsius: green under 70, yellow to 85, red above.
    static func temperatureLevel(_ celsius: Double) -> NotchLockScreenLevel {
        celsius >= 85 ? .critical : celsius >= 70 ? .warning : .good
    }

    /// Charge left, whether or not it is charging: green from half, yellow
    /// from a fifth, red under it.
    static func chargeLevel(_ percent: Int) -> NotchLockScreenLevel {
        percent >= 50 ? .good : percent >= 20 ? .warning : .critical
    }

    /// How much of a ring a reading fills: in use is capped at the whole,
    /// and a temperature fills it at 100 °C while its number reads on.
    static func ringFill(_ fraction: Double) -> Double {
        fraction.isFinite ? min(1, max(0, fraction)) : 0
    }

    static func temperatureFill(_ celsius: Double) -> Double { ringFill(celsius / 100) }

    /// Which of today's `count` events a calendar of `fits` rows shows: the
    /// last one past above the one at `upcoming`, then what follows. Near
    /// the day's end it reaches further back rather than leave rows empty.
    static func dayWindow(count: Int, upcoming: Int, fits: Int) -> Range<Int> {
        guard count > 0, fits > 0 else { return 0..<0 }
        let shown = min(fits, count)
        let start = min(max(0, upcoming - 1), count - shown)
        return start..<(start + shown)
    }

    /// Days in a row with any use, ending today, or yesterday while today
    /// has none yet; and the longest such run the days hold. `active` is
    /// oldest first, ending with today.
    static func streak(_ active: [Bool]) -> (current: Int, best: Int) {
        var current = 0
        for (index, used) in active.enumerated().reversed() {
            if used { current += 1 } else if current > 0 || index != active.count - 1 { break }
        }
        var best = 0, run = 0
        for used in active {
            run = used ? run + 1 : 0
            best = max(best, run)
        }
        return (current, best)
    }
}

/// How tall the player stands on the stage: its compact fit, or its
/// shortest where the stage is short.
enum NotchLockScreenPlayerFit: Equatable {
    case regular, short

    var height: CGFloat {
        switch self {
        case .regular: return NotchLockScreenLayout.playerHeight
        case .short: return NotchLockScreenLayout.shortPlayerHeight
        }
    }
}

/// Where everything goes on one display. A part with no room is nil.
struct NotchLockScreenScene: Equatable {
    /// The line of activities under the clock.
    var row: CGRect?
    var calendar: CGRect?
    var player: CGRect?
    var playerFit: NotchLockScreenPlayerFit?
    /// This Mac's rail left of the stage, and the height of its four gauges.
    var mac: CGRect?
    var gauge: CGFloat = 0
    /// The AI rail right of the stage: Claude with Codex and Lifetime under
    /// it, Agents at work, and Streak. Only the last two take the pointer.
    var aiCards: CGRect?
    var agents: CGRect?
    var streak: CGRect?
}

/// macOS draws the lock screen's date, clock and login controls in one window
/// over the whole display, so their room is kept by measure. On macOS 26 and
/// 27 the date and clock end 236 points from the top of a 956-point display,
/// and the name, picture, password field and hint take the lowest 218.
/// Activities read as a line under the clock. The stage under it holds the
/// calendar over Now Playing, and a rail stands in each free column beside
/// it: This Mac on the left, AI on the right, both ending level with the
/// player.
enum NotchLockScreenLayout {
    /// A taller display draws a larger clock.
    static func clockBottom(screenHeight: CGFloat) -> CGFloat { max(236, screenHeight * 0.247) }
    static let rowGap: CGFloat = 18
    static let rowHeight: CGFloat = 30
    /// From the bottom of the display to the stage and the rails.
    static let loginClearance: CGFloat = 250

    // MARK: Stage

    static let stageWidth: CGFloat = 460
    /// From the line to the stage, and between the calendar and the player.
    static let stageGap: CGFloat = 10
    /// The player's compact fit: the cover beside the title and buttons,
    /// then the timeline. Its shortest drops the cover to a thumbnail.
    static let playerHeight: CGFloat = 190
    static let shortPlayerHeight: CGFloat = 150
    /// The calendar takes the stage over the player: a header and a few
    /// events at least, and no more than a day's worth on a tall display.
    static let calendarMinimum: CGFloat = 200
    static let calendarMaximum: CGFloat = 360
    /// Room left around the player's pane for its cover's glow; the clear
    /// edge lets clicks through.
    static let playerGlow: CGFloat = 16

    // MARK: Rails

    static let railWidth: CGFloat = 440
    /// The least room kept clear on each side of a rail in its column.
    static let railMargin: CGFloat = 24
    static let railTop: CGFloat = 72
    static let cardGap: CGFloat = 16
    /// A card half a rail wide.
    static var halfCard: CGFloat { (railWidth - cardGap) / 2 }
    /// This Mac: four gauges in two rows, then Accessories and Battery. The
    /// gauges take the rail's spare height and give it back first.
    static let gaugeMinimum: CGFloat = 150
    static let gaugeMaximum: CGFloat = 260
    static let accessoriesHeight: CGFloat = 126
    static let batteryHeight: CGFloat = 126
    /// AI: Claude, then Codex beside Lifetime, Agents at work and Streak.
    /// Agents at work takes the spare height and gives it back first.
    static let claudeHeight: CGFloat = 130
    static let pairHeight: CGFloat = 130
    static let agentsMinimum: CGFloat = 150
    static let agentsMaximum: CGFloat = 360
    static let streakHeight: CGFloat = 150

    private static func readable(_ screen: CGRect) -> Bool {
        [screen.minX, screen.minY, screen.width, screen.height].allSatisfy(\.isFinite)
            && screen.width >= stageWidth + 32 && screen.height > 0
    }

    /// Everything on `screen`, with This Mac (the calendar and the left
    /// rail) and the AI rail where they are on.
    static func scene(in screen: CGRect, calendar: Bool, mac: Bool, ai: Bool) -> NotchLockScreenScene {
        var scene = NotchLockScreenScene()
        guard readable(screen) else { return scene }
        let rails = railColumns(in: screen)
        if mac, let rails, let gauge = gaugeHeight(railHeight: rails.left.height) {
            let height = gauge * 2 + fixedMacHeight
            scene.mac = CGRect(x: rails.left.minX, y: rails.left.minY, width: railWidth, height: height)
            scene.gauge = gauge
        }
        if ai, let rails, let agents = agentsHeight(railHeight: rails.right.height) {
            let bottom = rails.right.minY
            scene.streak = CGRect(x: rails.right.minX, y: bottom, width: railWidth, height: streakHeight)
            scene.agents = CGRect(x: rails.right.minX, y: bottom + streakHeight + cardGap, width: railWidth, height: agents)
            let top = bottom + streakHeight + cardGap + agents + cardGap
            scene.aiCards = CGRect(x: rails.right.minX, y: top, width: railWidth,
                                   height: claudeHeight + cardGap + pairHeight)
        }
        scene.row = rowFrame(in: screen, besideRails: scene.mac != nil || scene.aiCards != nil)
        guard let row = scene.row else { return scene }
        let bottom = screen.minY + loginClearance
        let stage = row.minY - stageGap - bottom
        let x = (screen.midX - stageWidth / 2).rounded()
        let fit: NotchLockScreenPlayerFit?
        if stage >= calendarMinimum + stageGap + playerHeight {
            fit = .regular
        } else if stage >= calendarMinimum + stageGap + shortPlayerHeight {
            fit = .short
        } else {
            fit = nil
        }
        if let fit {
            scene.player = CGRect(x: x, y: bottom, width: stageWidth, height: fit.height)
            scene.playerFit = fit
        }
        if calendar && mac {
            let above = fit.map { bottom + $0.height + stageGap } ?? bottom
            let height = min(calendarMaximum, (row.minY - stageGap - above).rounded(.down))
            if height >= calendarMinimum {
                // A tall stage keeps the calendar on the player, the room
                // above it left to the wallpaper.
                scene.calendar = CGRect(x: x, y: above, width: stageWidth, height: height)
            }
        }
        return scene
    }

    /// Accessories and Battery under the gauges, with the gaps between all.
    private static var fixedMacHeight: CGFloat { accessoriesHeight + batteryHeight + cardGap * 3 }
    private static var fixedAIHeight: CGFloat { claudeHeight + pairHeight + streakHeight + cardGap * 3 }

    /// The left and right rails' room: centred in the columns beside the
    /// stage, from `railTop` down to the player's foot. Nil where a column
    /// is too narrow, as with a larger text setting.
    static func railColumns(in screen: CGRect) -> (left: CGRect, right: CGRect)? {
        guard readable(screen) else { return nil }
        let column = (screen.width - stageWidth) / 2
        guard column >= railWidth + railMargin * 2 else { return nil }
        let inset = ((column - railWidth) / 2).rounded()
        let bottom = screen.minY + loginClearance
        let height = screen.maxY - railTop - bottom
        guard height > 0 else { return nil }
        return (CGRect(x: screen.minX + inset, y: bottom, width: railWidth, height: height),
                CGRect(x: screen.maxX - inset - railWidth, y: bottom, width: railWidth, height: height))
    }

    /// Each gauge's height in a rail of `railHeight`, or nil where even the
    /// shortest gauges leave no room for the rest.
    static func gaugeHeight(railHeight: CGFloat) -> CGFloat? {
        let gauge = (railHeight - fixedMacHeight) / 2
        return gauge >= gaugeMinimum ? min(gaugeMaximum, gauge) : nil
    }

    static func agentsHeight(railHeight: CGFloat) -> CGFloat? {
        let agents = railHeight - fixedAIHeight
        return agents >= agentsMinimum ? min(agentsMaximum, agents) : nil
    }

    /// The line of activities under the clock. Beside a rail it keeps to
    /// the room between the two columns' rails.
    static func rowFrame(in screen: CGRect, besideRails: Bool = false) -> CGRect? {
        guard readable(screen) else { return nil }
        var width = min(screen.width - 64, 1000)
        if besideRails, let rails = railColumns(in: screen) {
            width = min(width, (rails.right.minX - rails.left.maxX - railMargin * 2).rounded(.down))
        }
        let top = screen.maxY - clockBottom(screenHeight: screen.height) - rowGap
        guard top - rowHeight >= screen.minY + loginClearance else { return nil }
        return CGRect(x: (screen.midX - width / 2).rounded(), y: top - rowHeight, width: width, height: rowHeight)
    }

    /// The locked island hung from the top of `screen`, around its camera,
    /// with a `wing` on each side: the padlock in the first, as wide as the
    /// music strip's wings so the island keeps its size as the Mac locks. It
    /// is the camera's exact fitted height, as the closed strips keep it: a
    /// half point more would show as a dark line under the housing.
    static func islandSurface(in screen: CGRect, cameraWidth: CGFloat, cameraHeight: CGFloat, wing: CGFloat) -> CGRect? {
        guard [screen.width, screen.height, cameraWidth, cameraHeight, wing].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let width = min(screen.width - 24, cameraWidth + wing * 2)
        guard width > cameraWidth else { return nil }
        // Centred on the camera to the half point: a notch only comes on Retina displays.
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - cameraHeight, width: width, height: cameraHeight)
    }

    /// The island's window. The lock screen's windows land on whole points,
    /// so it grows out to them around the island, which keeps its own size
    /// at the top of the window and leaves the extra room clear.
    static func islandFrame(around surface: CGRect) -> CGRect { surface.integral }
}
