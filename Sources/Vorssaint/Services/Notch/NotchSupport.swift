// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum NotchModule: String, CaseIterable, Identifiable {
    case controls, mixer, music, clipboard, captures, files, system, tools, calendar, notifications, timer, camera, downloads, scratchpad
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .controls: return "slider.horizontal.3"
        // A speaker reads as sound at a glance; faders beside the settings
        // gear looked like a second settings button.
        case .mixer: return "speaker.wave.2"
        case .music: return "music.note"
        case .timer: return "timer"
        case .camera: return "web.camera"
        case .downloads: return "arrow.down.circle"
        case .notifications: return "bell"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .captures: return "camera.viewfinder"
        case .files: return "tray.full"
        case .system: return "gauge.with.dots.needle.50percent"
        case .tools: return "square.grid.2x2"
        case .scratchpad: return "note.text"
        }
    }

    /// Stable across ordering and languages; every destination has a direct key.
    var shortcutKey: String {
        switch self {
        case .controls: return "c"
        case .mixer: return "v"
        case .music: return "m"
        case .clipboard: return "b"
        case .captures: return "s"
        case .files: return "f"
        case .system: return "i"
        case .tools: return "t"
        case .calendar: return "a"
        case .notifications: return "n"
        case .timer: return "r"
        case .camera: return "w"
        case .downloads: return "d"
        case .scratchpad: return "p"
        }
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .controls, .music: return true
        case .timer: return AppFeature.notchTimer.isAvailable(in: defaults)
        case .camera: return AppFeature.cameraPreview.isAvailable(in: defaults)
        case .downloads: return AppFeature.notchDownloads.isAvailable(in: defaults)
        case .notifications: return AppFeature.notchNotifications.isAvailable(in: defaults)
        case .calendar: return AppFeature.notchCalendar.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults)
        case .tools: return AppFeature.quickLauncher.isAvailable(in: defaults)
        case .clipboard: return AppFeature.clipboardHistory.isAvailable(in: defaults)
        case .captures:
            return AppFeature.screenshot.isAvailable(in: defaults)
                || AppFeature.screenRecorder.isAvailable(in: defaults)
                || AppFeature.screenOCR.isAvailable(in: defaults)
                || AppFeature.colorPicker.isAvailable(in: defaults)
        case .files: return AppFeature.shelf.isAvailable(in: defaults)
        case .scratchpad: return AppFeature.scratchpad.isAvailable(in: defaults)
        case .system:
            return [.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork,
                    .monitorDisk, .monitorPower, .fanControl].contains { (feature: AppFeature) in
                feature.isAvailable(in: defaults)
            }
        }
    }
}

enum NotchDisplay: String, CaseIterable {
    case automatic, builtIn, main
}

enum NotchSize: String, CaseIterable {
    case compact, spacious, custom

    static let widthRange = 360.0...600.0
    static let heightRange = 260.0...640.0
    static let defaultWidth = 440.0
    static let defaultHeight = 480.0

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// Shared measurements keep the window's content budget and its SwiftUI
/// layout in agreement, including small screens and custom sizes.
enum NotchLayout {
    static let shoulder: CGFloat = 14
    static let horizontalInset: CGFloat = 28
    static let headerHeight: CGFloat = 36
    static let navigationHeight: CGFloat = 36
    static let spacing: CGFloat = 12
    static let bottomInset: CGFloat = 16
    static var chromeHeight: CGFloat { headerHeight + spacing + bottomInset }
    /// The island stays a wide strip: pages scroll within the preset's budget.
    static let compactContentHeight: CGFloat = 180
    static let spaciousContentHeight: CGFloat = 264
    /// Surfaces that are vertical by nature (the embedded app panel, a metric
    /// detail, a hosted utility) still get a readable page inside a preset.
    static let pageContentHeight: CGFloat = 320
    static let rowSpacing: CGFloat = 10
    static let cardHeight: CGFloat = 96
    static let minimumCardHeight: CGFloat = 68
    static let shortcutHeight: CGFloat = 74
    static let shortcutWidth: CGFloat = 76
    static let shortcutSpacing: CGFloat = 8
    static let systemCardHeight: CGFloat = 72
    static let systemCardWidth: CGFloat = 128
    static let toolHeight: CGFloat = 72
    static let toolWidth: CGFloat = 76
    static let toolSpacing: CGFloat = 6
    /// Three rows fit the gallery's page; two still fill a compact strip.
    static let sectionTileHeight: CGFloat = 86
    static let sectionTileWidth: CGFloat = 92
    static let sectionSpacing: CGFloat = 8
    /// The gallery's row indicator beside the tiles, with its gap.
    static let sectionIndicatorWidth: CGFloat = 12
    static let clipboardSearchHeight: CGFloat = 36
    static let clipboardCardHeight: CGFloat = 104
    static let emptyHeight: CGFloat = 140
    static let musicControlsRowHeight: CGFloat = 32
    static let musicIdleHeight: CGFloat = 84
    static let timerTopRowHeight: CGFloat = 36
    static let timerRowSpacing: CGFloat = 8
    /// The Pomodoro's breaks and sessions as one line of readouts under the ruler.
    static let timerSettingsRowHeight: CGFloat = 28
    static let timerRulerHeight: CGFloat = 82
    static let timerMinimumRulerHeight: CGFloat = 56
    static let timerStartHeight: CGFloat = 36
    /// From this width the start button shares the mode row in every
    /// language; below it the button takes a row of its own.
    static let timerWideWidth: CGFloat = 400
    /// The month grid a short island opens over its week strip: a header
    /// row, the weekday line and six rows sharing what is left.
    static let calendarMonthHeaderHeight: CGFloat = 28
    static let calendarMonthWeekdayHeight: CGFloat = 14
    static let calendarMonthSpacing: CGFloat = 4
    static var calendarMonthMinimumHeight: CGFloat {
        calendarMonthHeaderHeight + calendarMonthWeekdayHeight + calendarMonthSpacing * 2 + 6 * 16
    }
    static func calendarMonthRowHeight(height: CGFloat) -> CGFloat {
        let room = height - calendarMonthHeaderHeight - calendarMonthWeekdayHeight - calendarMonthSpacing * 2
        return min(30, max(16, (room / 6).rounded(.down)))
    }

    /// Fit a 4:3 preview above the stop button, including narrow, tall islands.
    static func cameraPreviewSize(in size: CGSize) -> CGSize {
        let height = max(0, min(size.height - 28 - rowSpacing, size.width * 3 / 4))
        return CGSize(width: height * 4 / 3, height: height)
    }
    /// Breathing room every compact strip keeps from its silhouette.
    static let compactEdgeGap: CGFloat = 5
    /// Corners of a surface of this height. A strip as tall as the camera
    /// keeps the cutout's own corners, so the closed island and the last
    /// frames of a collapse sit inside the notch instead of outlining a
    /// rounder one; the open island reaches the full radius and shoulder.
    static func surfaceRadius(height: CGFloat) -> CGFloat { min(28, height * 0.34) }
    static func shoulder(height: CGFloat) -> CGFloat { min(shoulder, height * 0.19) }
    /// Content clearance under a camera of the usual height.
    static let nominalContentTop: CGFloat = 42

    static func preferredWidth(_ layout: NotchSize, custom: CGFloat) -> CGFloat {
        switch layout {
        case .compact: return 480
        case .spacious: return 560
        case .custom: return custom
        }
    }

    /// The island as a preset presents it on a display whose camera leaves
    /// the usual clearance; custom keeps the chosen height.
    static func nominalHeight(_ layout: NotchSize, custom: CGFloat) -> CGFloat {
        switch layout {
        case .compact: return nominalContentTop + chromeHeight + compactContentHeight
        case .spacious: return nominalContentTop + chromeHeight + spaciousContentHeight
        case .custom: return custom
        }
    }

    /// Balance complete rows across the available width, keeping reading order
    /// left to right and allowing each row to fill its width without empty cells.
    static func systemRowRanges(count: Int, width: CGFloat) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let columns = railCapacity(width: width, itemWidth: systemCardWidth, spacing: rowSpacing)
        let rows = (count + columns - 1) / columns
        let base = count / rows
        let remainder = count % rows
        return (0..<rows).map { row in
            let start = row * base + min(row, remainder)
            return start..<(start + base + (row < remainder ? 1 : 0))
        }
    }

    // MARK: Rails
    // Items fill the rows a height allows and continue sideways. Every page
    // and the geometry that sizes it share these three functions, so the
    // window never reserves a row the page cannot draw.

    static func railCapacity(width: CGFloat, itemWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, itemWidth > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (itemWidth + spacing)).rounded(.down)))
    }

    static func railRows(count: Int, perRow: Int, rowHeight: CGFloat, spacing: CGFloat, height: CGFloat) -> Int {
        let capacity = max(1, perRow)
        let needed = max(1, (max(0, count) + capacity - 1) / capacity)
        guard rowHeight > 0 else { return 1 }
        guard height.isFinite else { return height > 0 ? needed : 1 }
        let fitting = max(1, Int(((height + spacing) / (rowHeight + spacing)).rounded(.down)))
        return min(needed, fitting)
    }

    static func railHeight(rows: Int, rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        CGFloat(max(1, rows)) * rowHeight + CGFloat(max(0, rows - 1)) * spacing
    }

    /// Square artwork, its gap, the three compact transport buttons, and
    /// horizontal padding. Track titles truncate within the remaining space.
    static func musicCardMinimumWidth(height: CGFloat) -> CGFloat {
        max(40, height - 24) + 12 + 120 + 24
    }

    /// The home page: one row of cards (playback and levels) over a rail of
    /// shortcuts. A tight budget shortens the cards before it drops a row.
    static func controls(hasCards: Bool, shortcutCount: Int, width: CGFloat, height: CGFloat) -> NotchControlsLayout {
        guard hasCards || shortcutCount > 0 else { return NotchControlsLayout(cardRow: 0, shortcutRows: 0) }
        var rows = 0
        if shortcutCount > 0 {
            let remaining = hasCards ? height - minimumCardHeight - rowSpacing : height
            rows = railRows(count: shortcutCount,
                            perRow: railCapacity(width: width, itemWidth: shortcutWidth, spacing: shortcutSpacing),
                            rowHeight: shortcutHeight, spacing: shortcutSpacing, height: remaining)
        }
        let rail = rows > 0 ? railHeight(rows: rows, rowHeight: shortcutHeight, spacing: shortcutSpacing) + rowSpacing : 0
        let cardRow = hasCards ? min(cardHeight, max(minimumCardHeight, height - rail)) : 0
        return NotchControlsLayout(cardRow: cardRow, shortcutRows: rows)
    }

    /// Setup is the mode row over the ruler's row, the same for every
    /// mode: the timer and the Pomodoro's focus on the ruler, the stopwatch's
    /// clock alone in it. The Pomodoro adds a line of readouts; a narrow
    /// island gives Start the last row, which those readouts share, and lets
    /// the ruler give up height before anything is cut.
    static func timer(mode: NotchTimerMode, hasSession: Bool, width: CGFloat, height: CGFloat) -> CGFloat {
        if hasSession { return mode == .pomodoro ? 118 : 96 }
        let top = timerTopRowHeight + timerRowSpacing
        return top + timerRulerHeight(mode: mode, width: width, height: height)
            + timerBottomRowHeight(mode: mode, width: width)
    }

    /// The row under the ruler, with its spacing: Start on a narrow island,
    /// the Pomodoro's readouts on a wide one, nothing otherwise.
    static func timerBottomRowHeight(mode: NotchTimerMode, width: CGFloat) -> CGFloat {
        if width < timerWideWidth { return timerRowSpacing + timerStartHeight }
        return mode == .pomodoro ? timerRowSpacing + timerSettingsRowHeight : 0
    }

    static func timerRulerHeight(mode: NotchTimerMode = .timer, width: CGFloat, height: CGFloat) -> CGFloat {
        let below = timerBottomRowHeight(mode: mode, width: width)
        guard below > 0 else { return timerRulerHeight }
        let room = height - timerTopRowHeight - timerRowSpacing - below
        return min(timerRulerHeight, max(timerMinimumRulerHeight, room))
    }

    /// The player row keeps the artwork square; the controls row below holds
    /// volume and the lyrics or queue toggles.
    static func musicPlayerHeight(layout: NotchSize, height: CGFloat) -> CGFloat {
        min(layout == .spacious ? 148 : 120, max(88, height - musicControlsRowHeight - rowSpacing))
    }
}

struct NotchControlsLayout: Equatable {
    let cardRow: CGFloat
    let shortcutRows: Int

    var height: CGFloat {
        let rail = shortcutRows > 0
            ? NotchLayout.railHeight(rows: shortcutRows, rowHeight: NotchLayout.shortcutHeight, spacing: NotchLayout.shortcutSpacing) : 0
        return cardRow + (cardRow > 0 && shortcutRows > 0 ? NotchLayout.rowSpacing : 0) + rail
    }
}

enum NotchIdleContent: String, CaseIterable {
    case none, battery, music
}

/// Resizing can send hover exits and entries without any pointer movement.
struct NotchHoverState {
    private(set) var suppressed = false

    mutating func close(pointerInside: Bool) { suppressed = pointerInside }
    mutating func open() { suppressed = false }
    mutating func update(pointerInside: Bool) {
        if !pointerInside { suppressed = false }
    }
}

enum NotchCompactActivity: Equatable {
    case timer, downloads, music

    var module: NotchModule {
        switch self {
        case .timer: return .timer
        case .downloads: return .downloads
        case .music: return .music
        }
    }
}

enum NotchControlItem: String, CaseIterable, Identifiable {
    case volume, brightness, music, mixer, keepAwake, timer, calendar, microphone, screenshot, recording, speedTest, panel, commandBar, scratchpad
    static let defaultHidden = "microphone,screenshot,recording,speedTest,panel,commandBar,scratchpad"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .keepAwake: return "cup.and.saucer"
        case .microphone: return "mic.fill"
        case .screenshot: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .speedTest: return "speedometer"
        case .panel: return "rectangle.topthird.inset.filled"
        case .mixer: return NotchModule.mixer.symbol
        case .commandBar: return "command"
        case .scratchpad: return "note.text"
        case .music: return NotchModule.music.symbol
        case .timer: return NotchModule.timer.symbol
        case .calendar: return NotchModule.calendar.symbol
        }
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.mixer)
        case .brightness: return AppFeature.brightness.isAvailable(in: defaults)
        case .keepAwake: return AppFeature.keepAwake.isAvailable(in: defaults)
        case .microphone: return AppFeature.micMute.isAvailable(in: defaults)
        case .screenshot: return AppFeature.screenshot.isAvailable(in: defaults)
        case .recording: return AppFeature.screenRecorder.isAvailable(in: defaults)
        case .speedTest: return AppFeature.monitorNetwork.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.system)
        case .commandBar: return AppFeature.commandBar.isAvailable(in: defaults)
        case .scratchpad: return AppFeature.scratchpad.isAvailable(in: defaults)
        case .panel: return true
        case .music: return NotchSupport.modules(in: defaults).contains(.music)
        case .timer: return NotchSupport.modules(in: defaults).contains(.timer)
        case .calendar: return NotchSupport.modules(in: defaults).contains(.calendar)
        }
    }
}

enum NotchQuickAccessSide: String, CaseIterable, Codable {
    case left, right, bottom
}

enum NotchQuickAction: Hashable, Identifiable {
    case explore, settings, pin, module(NotchModule), control(NotchControlItem)

    var id: String {
        switch self {
        case .explore: return "explore"
        case .settings: return "settings"
        case .pin: return "pin"
        case .module(let module): return module.rawValue
        case .control(let item): return "control." + item.rawValue
        }
    }

    init?(id: String) {
        switch id {
        case "explore": self = .explore
        case "settings": self = .settings
        case "pin": self = .pin
        default:
            if id.hasPrefix("control."), let item = NotchControlItem(rawValue: String(id.dropFirst(8))) {
                self = .control(item)
            } else if let module = NotchModule(rawValue: id) { self = .module(module) }
            else { return nil }
        }
    }

    static var optionalActions: [Self] {
        [.explore, .settings, .pin] + NotchModule.allCases.map(Self.module)
            + NotchControlItem.allCases.filter { $0 != .volume && $0 != .brightness }.map(Self.control)
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .module(let module): return NotchSupport.modules(in: defaults).contains(module)
        case .control(let item): return item.isAvailable(in: defaults)
        default: return true
        }
    }
}

struct NotchQuickButton: Codable, Equatable, Identifiable {
    var id: UUID
    var actionID: String
    var side: NotchQuickAccessSide
    var label: String

    init(id: UUID = UUID(), action: NotchQuickAction, side: NotchQuickAccessSide, label: String = "") {
        self.id = id
        actionID = action.id
        self.side = side
        self.label = label
    }

    var action: NotchQuickAction? { NotchQuickAction(id: actionID) }
}

struct NotchQuickAccessConfiguration: Equatable, Codable {
    var buttons: [NotchQuickButton]
    private var version = 1
    static let maximumPerSide = 3
    static let initial = Self(buttons: [
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, action: .explore, side: .left),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, action: .module(.timer), side: .left),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, action: .settings, side: .right),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, action: .module(.mixer), side: .right),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!, action: .module(.music), side: .bottom),
    ])
    var actions: [NotchQuickAction] { buttons.compactMap(\.action) }
    var hasBottom: Bool { buttons.contains { $0.side == .bottom } }

    init(buttons: [NotchQuickButton]) { self.buttons = buttons }

    /// Stable IDs allow the previous single-side preferences to remain live
    /// until the first deliberate edit saves the new layout.
    init(side: NotchQuickAccessSide, actions: [NotchQuickAction]) {
        buttons = actions.enumerated().map { index, action in
            NotchQuickButton(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                             action: action, side: side)
        }
    }

    func sanitized() -> Self {
        var ids = Set<UUID>()
        var counts: [NotchQuickAccessSide: Int] = [:]
        let safe = buttons.prefix(64).compactMap { button -> NotchQuickButton? in
            guard button.action != nil, ids.insert(button.id).inserted,
                  counts[button.side, default: 0] < Self.maximumPerSide else { return nil }
            counts[button.side, default: 0] += 1
            var result = button
            result.label = String(button.label.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            return result
        }
        return Self(buttons: safe)
    }

    var encoded: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(sanitized())) ?? Data()
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        if let data = defaults.data(forKey: DefaultsKey.notchQuickAccessLayout), !data.isEmpty, data.count <= 32_768,
           let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 {
            return value.sanitized()
        }
        // These retired keys have no registration defaults, so even an empty
        // saved value is an explicit legacy choice rather than a fresh install.
        let legacyKeys = [DefaultsKey.notchQuickAccessSide, DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird]
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return .initial }
        let side = NotchQuickAccessSide(rawValue: defaults.string(forKey: DefaultsKey.notchQuickAccessSide) ?? "") ?? .left
        var actions: [NotchQuickAction] = [.explore]
        for key in [DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird] {
            let id = defaults.string(forKey: key) ?? (key == DefaultsKey.notchQuickAccessSecond ? NotchQuickAction.settings.id : "")
            guard let action = NotchQuickAction(id: id),
                  !actions.contains(action) else { continue }
            actions.append(action)
        }
        return Self(side: side, actions: actions)
    }

    static func current(in defaults: UserDefaults = .standard) -> Self {
        var configuration = stored(in: defaults)
        configuration.buttons.removeAll { $0.action?.isAvailable(in: defaults) != true }
        return configuration
    }

    mutating func move(_ id: UUID, to side: NotchQuickAccessSide, before target: UUID? = nil) {
        guard let index = buttons.firstIndex(where: { $0.id == id }),
              buttons[index].side == side || buttons.filter({ $0.side == side }).count < Self.maximumPerSide else { return }
        var item = buttons.remove(at: index)
        item.side = side
        let destination = target.flatMap { target in buttons.firstIndex(where: { $0.id == target && $0.side == side }) }
        buttons.insert(item, at: destination ?? buttons.endIndex)
    }
}

struct NotchQuickAccessPlacement: Equatable, Identifiable {
    let button: NotchQuickButton
    let index: Int
    let edge: CGFloat
    let top: CGFloat
    var id: UUID { button.id }
    var side: NotchQuickAccessSide { button.side }
    func center(progress: CGFloat) -> CGPoint {
        NotchQuickAccessLayout.center(index: index, progress: progress, edge: edge, top: top, side: side)
    }
}

/// All coordinates are in the flipped presentation container, including the
/// transparent space reserved beside the black notch.
enum NotchQuickAccessLayout {
    static let diameter: CGFloat = 44
    static let gap: CGFloat = 12
    static let gutter: CGFloat = 72
    static let rowSpacing: CGFloat = 54
    static let withdrawalDuration = 0.16
    static let hoverMargin: CGFloat = 16
    static let hoverExitDelay = 0.18

    static func center(index: Int, progress: CGFloat, edge: CGFloat, top: CGFloat,
                       side: NotchQuickAccessSide) -> CGPoint {
        let phase = progress.isFinite ? min(1.1, max(0, progress)) : 0
        let offset = -14 + phase * (14 + gap + diameter / 2)
        if side == .bottom { return CGPoint(x: top + CGFloat(index) * rowSpacing, y: edge + offset) }
        return CGPoint(x: edge + (side == .left ? -offset : offset), y: top + CGFloat(index) * rowSpacing)
    }

    /// Hover is a continuous corridor, including the gaps and a forgiving rim.
    /// Clicks still use the exact circles below.
    static func hoverRect(count: Int, edge: CGFloat, top: CGFloat,
                          side: NotchQuickAccessSide) -> CGRect {
        guard count > 0 else { return .null }
        let first = center(index: 0, progress: 1, edge: edge, top: top, side: side)
        let last = center(index: min(3, count) - 1, progress: 1, edge: edge, top: top, side: side)
        let radius = diameter / 2
        if side == .bottom {
            return CGRect(x: first.x - radius, y: edge, width: last.x - first.x + diameter,
                          height: first.y + radius - edge).insetBy(dx: -hoverMargin, dy: -hoverMargin)
        }
        return CGRect(x: min(first.x - radius, edge), y: first.y - radius,
                      width: max(first.x + radius, edge) - min(first.x - radius, edge),
                      height: last.y - first.y + diameter)
            .insetBy(dx: -hoverMargin, dy: -hoverMargin)
    }

    static func placements(_ configuration: NotchQuickAccessConfiguration, body: CGRect, headerTop: CGFloat) -> [NotchQuickAccessPlacement] {
        var indices: [NotchQuickAccessSide: Int] = [:]
        return configuration.buttons.map { button in
            let index = indices[button.side, default: 0]
            indices[button.side] = index + 1
            let count = configuration.buttons.filter { $0.side == button.side }.count
            let edge = button.side == .bottom ? body.maxY : button.side == .left ? body.minX : body.maxX
            let top = button.side == .bottom ? body.midX - CGFloat(count - 1) * rowSpacing / 2 : headerTop
            return NotchQuickAccessPlacement(button: button, index: index, edge: edge, top: top)
        }
    }

    static func hitTest(_ point: CGPoint, count: Int, edge: CGFloat, top: CGFloat,
                        side: NotchQuickAccessSide) -> Bool {
        (0..<max(0, min(3, count))).contains { index in
            let center = center(index: index, progress: 1, edge: edge, top: top, side: side)
            return hypot(point.x - center.x, point.y - center.y) <= diameter / 2
        }
    }
}

enum NotchEvent: String, CaseIterable {
    case volume, brightness, battery, clipboard, capture, systemNotification, keyboardLight, timer, accessory, download

    var preferenceKey: String {
        switch self {
        case .timer: return DefaultsKey.notchTimerEnabled
        case .accessory: return DefaultsKey.notchAccessoriesEnabled
        case .download: return DefaultsKey.notchDownloadsEnabled
        case .systemNotification: return DefaultsKey.notchNotificationsEnabled
        case .keyboardLight: return DefaultsKey.notchKeyboardLight
        case .volume: return DefaultsKey.notchVolume
        case .brightness: return DefaultsKey.notchBrightness
        case .battery: return DefaultsKey.notchBattery
        case .clipboard: return DefaultsKey.notchClipboard
        case .capture: return DefaultsKey.notchCapture
        }
    }

    var priority: Int {
        switch self {
        case .volume, .brightness, .keyboardLight: return 3
        case .capture, .timer: return 2
        case .battery, .systemNotification, .accessory: return 1
        case .clipboard, .download: return 0
        }
    }

    var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardLight: return 1.6
        case .systemNotification: return 3
        case .timer, .download: return 6
        case .battery, .accessory: return 4
        case .clipboard: return 2.5
        case .capture: return 12
        }
    }
}

enum NotchSupport {
    static let toolColumns = 5
    static let defaultHoverDelay = 0.25
    static let hoverDelayRange = 0.10...1.0

    static func sanitizedHoverDelay(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(hoverDelayRange.upperBound, max(hoverDelayRange.lowerBound, value)) : defaultHoverDelay
    }

    static func moduleShortcut(_ characters: String, modules: [NotchModule]) -> NotchModule? {
        modules.first { $0.shortcutKey == characters.lowercased() }
    }

    static func filteredModules(_ modules: [NotchModule], query: String,
                                title: (NotchModule) -> String) -> [NotchModule] {
        let terms = CommandBarSearch.normalized(query).split(separator: " ")
        guard !terms.isEmpty else { return modules }
        return modules.filter { module in
            let name = CommandBarSearch.normalized(title(module))
            return terms.allSatisfy { name.contains($0) }
        }
    }

    static func adjacentModule(to selected: NotchModule?, modules: [NotchModule], backwards: Bool) -> NotchModule? {
        guard !modules.isEmpty else { return nil }
        guard let selected, let index = modules.firstIndex(of: selected) else { return modules.first }
        return modules[(index + (backwards ? modules.count - 1 : 1)) % modules.count]
    }

    static func compactActivity(timer: Bool, downloads: Bool, music: Bool) -> NotchCompactActivity? {
        if timer { return .timer }
        if downloads { return .downloads }
        return music ? .music : nil
    }

    static func gestureIsOverHeader(expanded: Bool, peeking: Bool, fromTop: CGFloat, safeTop: CGFloat) -> Bool {
        (expanded || peeking) && (safeTop...safeTop + NotchLayout.headerHeight).contains(fromTop)
    }

    static func keepsPermissionSurface(requesting: Bool, resolvedAt: TimeInterval?, now: TimeInterval) -> Bool {
        if requesting { return true }
        guard let resolvedAt, now.isFinite, resolvedAt.isFinite else { return false }
        return (0..<1).contains(now - resolvedAt)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notch.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchEnabled)
    }

    static func usesHapticFeedback(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchHapticFeedback)
    }

    static func modules(in defaults: UserDefaults = .standard) -> [NotchModule] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenModules) ?? "")
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchModuleOrder) ?? "")
            .split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
                && ($0 != .timer || defaults.bool(forKey: DefaultsKey.notchTimerEnabled))
                && ($0 != .camera || defaults.bool(forKey: DefaultsKey.notchCameraEnabled))
                && ($0 != .calendar || defaults.bool(forKey: DefaultsKey.notchCalendarEnabled))
                && ($0 != .notifications || defaults.bool(forKey: DefaultsKey.notchNotificationsEnabled))
        }
    }

    static func watchesMusicActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && modules(in: defaults).contains(.music)
            && idleContent(in: defaults) != .none
            && (defaults.object(forKey: DefaultsKey.notchShowPlayingMusic) as? Bool ?? true)
    }

    static func showsMusicActivity(isPlaying: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isPlaying && watchesMusicActivity(in: defaults)
    }

    static func showsInCaptures(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchShowInCaptures) as? Bool ?? true
    }

    /// The closed island may cover the menus instead of giving way to them.
    static func coversMenus(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchCoversMenus)
    }

    static func idleContent(in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = NotchIdleContent(rawValue: defaults.string(forKey: DefaultsKey.notchIdleContent) ?? "") ?? .none
        if choice == .battery, !AppFeature.monitorPower.isAvailable(in: defaults) { return .none }
        if choice == .music, !modules(in: defaults).contains(.music) { return .none }
        return choice
    }

    static func visibleIdleContent(isPlaying: Bool, in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = idleContent(in: defaults)
        return choice == .music && !showsMusicActivity(isPlaying: isPlaying, in: defaults) ? .none : choice
    }

    static func controls(in defaults: UserDefaults = .standard) -> [NotchControlItem] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? NotchControlItem.defaultHidden)
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchControlOrder) ?? "")
            .split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
        }
    }

    /// Power draw has a card of its own beside the battery; fans join once
    /// the monitor reports one.
    static func systemCardCount(hasBattery: Bool, fans: Int = 0, in defaults: UserDefaults = .standard) -> Int {
        [.monitorCPU, .monitorGPU, .monitorMemory, .monitorDisk].filter {
            (feature: AppFeature) in feature.isAvailable(in: defaults)
        }.count + (AppFeature.monitorNetwork.isAvailable(in: defaults) ? 1 : 0)
            + (hasBattery && AppFeature.monitorPower.isAvailable(in: defaults) ? 1 : 0)
            + (AppFeature.monitorPower.isAvailable(in: defaults) ? 1 : 0)
            + (fans > 0 && AppFeature.fanControl.isAvailable(in: defaults) ? 1 : 0)
    }

    /// Direct openings are dismissed explicitly, never by the pointer's
    /// initial position at the menu bar or in the application being used.
    static func closesOnPointerExit(expanded: Bool, peeking: Bool, openedByHover: Bool) -> Bool {
        peeking || (expanded && openedByHover)
    }

    static func routes(_ event: NotchEvent, in defaults: UserDefaults = .standard) -> Bool {
        guard isEnabled(in: defaults), defaults.bool(forKey: event.preferenceKey) else { return false }
        switch event {
        case .timer: return NotchTimerSupport.isEnabled(in: defaults)
        case .accessory: return NotchAccessorySupport.isEnabled(in: defaults)
        case .download: return AppFeature.notchDownloads.isAvailable(in: defaults)
            && modules(in: defaults).contains(.downloads)
        case .systemNotification: return NotchNotificationSupport.isEnabled(in: defaults)
        case .keyboardLight: return AppFeature.brightness.isAvailable(in: defaults)
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .brightness:
            return AppFeature.brightness.isAvailable(in: defaults)
                && defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
        case .battery: return AppFeature.monitorPower.isAvailable(in: defaults)
        case .clipboard:
            return modules(in: defaults).contains(.clipboard)
                && defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
        case .capture:
            return AppFeature.screenshot.isAvailable(in: defaults)
                && modules(in: defaults).contains(.captures)
        }
    }

    static func routesClipboardWindow(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchClipboardWindow)
            && modules(in: defaults).contains(.clipboard)
    }

    static func routesShelf(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchShelf)
            && modules(in: defaults).contains(.files)
    }

    static func revealsShelfDrag(in defaults: UserDefaults = .standard) -> Bool {
        routesShelf(in: defaults) && defaults.bool(forKey: DefaultsKey.notchDragReveal)
    }

    static func routesCaptureControls(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCaptureControls)
            && modules(in: defaults).contains(.captures)
    }

    static func routesQuickPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchQuickPanel)
            && AppFeature.quickLauncher.isAvailable(in: defaults)
            && modules(in: defaults).contains(.tools)
    }

    static func routesAppPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchAppPanel)
    }

    /// A notice the pointer holds open is being read. Only the same kind of
    /// message or something the user just did may take its place.
    static func shouldReplace(_ current: NotchEvent?, with incoming: NotchEvent, held: Bool = false) -> Bool {
        guard let current else { return true }
        if held { return incoming == current || incoming.priority > current.priority }
        return incoming.priority >= current.priority
    }

    static func volumeLevel(current: Double, direction: Int, fine: Bool) -> Double {
        guard current.isFinite else { return 0 }
        return min(1, max(0, current + Double(direction.signum()) / (fine ? 64 : 16)))
    }

    static func screenIndex(preference: NotchDisplay, builtIn: [Bool], notched: [Bool], main: Int) -> Int? {
        guard !builtIn.isEmpty, builtIn.count == notched.count else { return nil }
        let fallback = builtIn.indices.contains(main) ? main : 0
        switch preference {
        case .main: return fallback
        case .builtIn: return builtIn.firstIndex(of: true) ?? fallback
        case .automatic:
            return builtIn.indices.first { builtIn[$0] && notched[$0] }
                ?? notched.firstIndex(of: true) ?? fallback
        }
    }
}

/// A hidden menu bar retains only a measurement from the same display and mode.
/// Until that display has a visible bar, use the native fallback rather than
/// borrowing the application's main-menu height from another display.
struct NotchMenuBarMeasurements {
    private struct Reading {
        let size: CGSize
        let scale: CGFloat
        let height: CGFloat
    }
    private var readings: [UInt32: Reading] = [:]

    mutating func retainDisplays(_ ids: [UInt32]) {
        readings = readings.filter { ids.contains($0.key) }
    }

    mutating func height(displayID: UInt32, frame: CGRect, visibleTop: CGFloat,
                         scale: CGFloat, statusBarThickness: CGFloat) -> CGFloat {
        let range: ClosedRange<CGFloat> = 16...64
        let gap = frame.maxY - visibleTop
        let canRemember = displayID != 0 && scale.isFinite && scale > 0
        if let previous = readings[displayID], previous.size != frame.size || previous.scale != scale {
            readings[displayID] = nil
        }
        if gap.isFinite, range.contains(gap) {
            if canRemember { readings[displayID] = Reading(size: frame.size, scale: scale, height: gap) }
            return gap
        }
        if canRemember, let previous = readings[displayID] { return previous.height }
        return statusBarThickness.isFinite && range.contains(statusBarThickness) ? statusBarThickness : 24
    }
}

/// Screen coordinates stay in points, including displays to the left or above
/// the primary display. No model name or pixel density is assumed.
struct NotchGeometry: Equatable {
    let screen: CGRect
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let isNotched: Bool
    let layout: NotchSize
    let customWidth: CGFloat
    let customHeight: CGFloat
    let menuBarHeight: CGFloat
    var compactSideRoom: CGFloat?
    var quickAccessBottomInset: CGFloat = 0
    private var allowsActivityFooter = true
    private var minimumCompactWidth: CGFloat = 0

    init(screen: CGRect, safeAreaTop: CGFloat, cameraWidth: CGFloat, layout: NotchSize = .compact,
         menuBarHeight: CGFloat = 24, compactSideRoom: CGFloat? = nil,
         customWidth: Double = NotchSize.defaultWidth, customHeight: Double = NotchSize.defaultHeight) {
        self.screen = screen
        self.layout = layout
        self.customWidth = NotchSize.clamped(customWidth, to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
        self.customHeight = NotchSize.clamped(customHeight, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
        let barHeight = menuBarHeight.isFinite ? min(64, max(16, menuBarHeight)) : 24
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && cameraWidth.isFinite && cameraWidth > 0
        self.cameraWidth = min(isNotched ? cameraWidth : 180 * barHeight / 32, screen.width * 0.7)
        cameraHeight = isNotched ? min(safeAreaTop, 64) : barHeight
        self.menuBarHeight = max(cameraHeight, barHeight)
        self.compactSideRoom = compactSideRoom
    }

    func hasSameMenuBar(as other: NotchGeometry) -> Bool {
        screen == other.screen && cameraWidth == other.cameraWidth
            && menuBarHeight == other.menuBarHeight && isNotched == other.isNotched
    }

    var safeContentTop: CGFloat { cameraHeight + 10 }
    /// One row beside the camera. It extends the cutout, whose height a
    /// physical camera sets and a simulated one shares with the bar: a bar
    /// even a point taller would leave a dark line under the notch.
    var stripHeight: CGFloat { cameraHeight }
    func activationArea(in size: CGSize, hasHeader: Bool, compactActivity: Bool) -> CGRect {
        let width = compactActivity ? cameraWidth : size.width
        let height = hasHeader ? min(safeContentTop, size.height)
            : compactActivity && compactActivityUsesFooter ? compactActivityTopPadding : size.height
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
    }

    var restingWingWidth: CGFloat {
        let available = min(44, max(0, compactSideRoom ?? 0)).rounded(.down)
        return available >= 44 ? available : 0
    }
    var collapsed: CGSize {
        CGSize(width: min(screen.width - 24, cameraWidth + restingWingWidth * 2), height: stripHeight)
    }
    func restingSize(showsContent: Bool) -> CGSize {
        showsContent ? collapsed : CGSize(width: cameraWidth, height: cameraHeight)
    }
    /// Music remains one row high, with the physical camera between its wings.
    /// Insufficient menu space hides the wings instead of growing below the camera.
    var compactMusicGeometry: NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        compact.compactSideRoom = room.isFinite && room >= 44 ? min(56, room) : 0
        compact.allowsActivityFooter = false
        return compact
    }
    var musicCameraGap: CGFloat { cameraWidth }
    var compactMusicLabelInset: CGFloat {
        let height = compactActivityContentHeight
        let shoulder = NotchLayout.shoulder(height: height)
        let bottom = NotchLayout.surfaceRadius(height: height)
        // Wings normally provide this room. When menus hide them, the center
        // text must also clear the silhouette's shoulders and bottom corners.
        return max(4, shoulder + bottom + 4 - compactActivityWingWidth)
    }
    func compactTimerGeometry(showsDownloads: Bool) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let wing: CGFloat = showsDownloads ? 80 : 72
        compact.compactSideRoom = room.isFinite && room >= 72 ? min(wing, room) : 0
        // A wider simulated camera must not consume the timer's text budget.
        compact.minimumCompactWidth = cameraWidth + wing * 2
        // Menu changes, including full-screen transitions, must not push the
        // timer below the camera. Its expanded view remains available by click.
        compact.allowsActivityFooter = false
        return compact
    }
    var musicStrip: CGSize {
        let preferred = min(max(layout == .spacious ? 520 : 440, cameraWidth + 88, minimumCompactWidth), screen.width - 24)
        let measuredRoom = compactSideRoom ?? 0
        let room = measuredRoom.isFinite ? max(0, measuredRoom).rounded(.down) : 0
        let wings = min(max(0, preferred - cameraWidth), room * 2)
        return CGSize(width: cameraWidth + (wings >= 88 ? wings : 0), height: stripHeight)
    }
    var musicWingWidth: CGFloat { max(0, (musicStrip.width - musicCameraGap) / 2) }

    /// Only a physical camera may need a footer. A simulated cutout and all
    /// of its compact activity stay within the real menu bar's height.
    var compactActivityUsesFooter: Bool { isNotched && allowsActivityFooter && musicWingWidth < 44 }
    var compactActivityContentHeight: CGFloat { compactActivityUsesFooter ? 32 : stripHeight }
    var compactActivityTopPadding: CGFloat { compactActivityUsesFooter ? stripHeight : 0 }
    var compactActivityHorizontalPadding: CGFloat { compactActivityUsesFooter ? 4 : 0 }
    var compactActivityCameraGap: CGFloat { compactActivityUsesFooter ? 0 : musicCameraGap }
    var compactActivitySize: CGSize {
        compactActivityUsesFooter
            ? CGSize(width: cameraWidth, height: compactActivityTopPadding + compactActivityContentHeight)
            : musicStrip
    }
    var compactActivityWingWidth: CGFloat {
        max(0, (compactActivitySize.width - compactActivityCameraGap - compactActivityHorizontalPadding * 2) / 2)
    }
    /// Where the silhouette's straight edge sits, once its shoulder has flared.
    var compactActivityShoulder: CGFloat {
        NotchLayout.shoulder(height: compactActivitySize.height)
    }
    /// Inset that keeps a vertically centred box of `boxHeight`, itself rounded
    /// by `radius`, an even `gap` away from the strip's silhouette.
    /// A strip is barely taller than its corners, so its lower half is one long
    /// arc: padding measured against the straight edge still leaves artwork and
    /// meters grazing the curve. Push the box in until its own corner keeps the
    /// same distance from the arc that its top keeps from the shoulder.
    func compactActivityEdgeInset(boxHeight: CGFloat, radius: CGFloat,
                                  gap: CGFloat = NotchLayout.compactEdgeGap) -> CGFloat {
        let shoulder = compactActivityShoulder
        let corner = min(NotchLayout.surfaceRadius(height: compactActivitySize.height),
                         (compactActivitySize.width - shoulder * 2) / 2)
        let flat = shoulder + gap - compactActivityHorizontalPadding
        let below = (compactActivityContentHeight - boxHeight) / 2
        // Both corner centres, grown by the gap, decide the horizontal offset.
        let reach = corner - radius - gap
        let drop = corner - radius - below
        guard reach > 0, drop > 0 else { return max(0, flat) }
        let span = reach > drop ? (reach * reach - drop * drop).squareRoot() : 0
        return max(0, flat, shoulder + corner - radius - span - compactActivityHorizontalPadding)
    }
    var notice: CGSize {
        noticeSize(wingWidth: 112)
    }
    var noticeCameraGap: CGFloat { cameraWidth }

    func noticeSize(wingWidth: CGFloat) -> CGSize {
        CGSize(width: min(screen.width - 24, noticeCameraGap + wingWidth * 2), height: stripHeight)
    }

    func noticeWingWidth(preferred: CGFloat) -> CGFloat {
        max(0, (noticeSize(wingWidth: preferred).width - noticeCameraGap) / 2)
    }
    /// A held notification opens as a card about as wide as a native banner,
    /// never wider than the island itself.
    var notificationPreviewWidth: CGFloat { min(max(400, cameraWidth + 200), expandedWidth) }
    var notificationPreviewContentWidth: CGFloat {
        max(0, notificationPreviewWidth - NotchLayout.horizontalInset * 2)
    }
    func notificationPreviewSize(contentHeight: CGFloat) -> CGSize {
        let height = safeContentTop + max(0, contentHeight) + NotchLayout.bottomInset
        return CGSize(width: notificationPreviewWidth, height: min(height, screen.height - 48))
    }
    var peek: CGSize {
        CGSize(width: min(screen.width - 24, max(cameraWidth + 110, 340)), height: safeContentTop + 52)
    }
    var expanded: CGSize { expandedSize(module: .controls) }
    var expandedWidth: CGFloat {
        let preferred = NotchLayout.preferredWidth(layout, custom: customWidth)
        return min(max(preferred, cameraWidth + 36), screen.width - 24 - NotchQuickAccessLayout.gutter * 2)
    }
    var contentWidth: CGFloat { max(0, expandedWidth - NotchLayout.horizontalInset * 2) }
    /// Content height available before a page needs to scroll.
    var contentBudget: CGFloat {
        switch layout {
        case .compact: return NotchLayout.compactContentHeight
        case .spacious: return NotchLayout.spaciousContentHeight
        case .custom: return max(0, customHeight - safeContentTop - NotchLayout.chromeHeight)
        }
    }
    /// Room a vertical surface gets: the budget, or a readable page where a
    /// preset's strip would leave it a few lines.
    var pageBudget: CGFloat { layout == .custom ? contentBudget : max(contentBudget, NotchLayout.pageContentHeight) }
    /// Lyrics and the queue open below the player; custom heights keep them
    /// within the chosen limit and the page swaps the player out instead.
    var musicExtrasHeight: CGFloat { layout == .custom ? min(216, contentBudget) : 216 }

    func systemRows(cards: Int) -> Int {
        NotchLayout.systemRowRanges(count: cards, width: contentWidth).count
    }

    func toolRows(count: Int) -> Int {
        NotchLayout.railRows(count: count,
                             perRow: NotchLayout.railCapacity(width: contentWidth, itemWidth: NotchLayout.toolWidth, spacing: NotchLayout.toolSpacing),
                             rowHeight: NotchLayout.toolHeight, spacing: NotchLayout.toolSpacing, height: contentBudget)
    }

    /// `toolCount` is nil while the launcher edits its grid or hosts a
    /// utility: those need the page, not a rail.
    func expandedSize(module: NotchModule, detail: Bool = false, panel: Bool = false, shortcutCount: Int = 4,
                      sliderCount: Int = 2, controlsHaveMusic: Bool = false, musicHasContent: Bool = true,
                      musicHasControlsRow: Bool = true, musicExtraHeight: CGFloat = 0,
                      fileMediaHeight: CGFloat? = nil, systemCards: Int = 6, toolCount: Int? = 8,
                      capturePreviewHeight: CGFloat? = nil,
                      timerHasSession: Bool = false, timerMode: NotchTimerMode = .timer) -> CGSize {
        let budget = contentBudget
        let showsCapturePreview = module == .captures && !detail && capturePreviewHeight != nil
        let showsFileMedia = module == .files && !detail && fileMediaHeight != nil
        let contentHeight: CGFloat
        if detail || panel {
            contentHeight = pageBudget
        } else if showsFileMedia {
            // Measured surfaces keep their own height; the custom limit and
            // the display bound them below.
            contentHeight = max(0, fileMediaHeight ?? 0)
        } else if showsCapturePreview {
            contentHeight = max(0, capturePreviewHeight ?? 0) + 4
        } else {
            switch module {
            case .controls:
                let sliders = min(2, max(0, sliderCount))
                let home = NotchLayout.controls(hasCards: controlsHaveMusic || sliders > 0, shortcutCount: max(0, shortcutCount),
                                                width: contentWidth, height: budget)
                contentHeight = min(budget, home.height == 0 ? NotchLayout.emptyHeight : home.height)
            case .music:
                let controlsRow = musicHasControlsRow ? NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing : 0
                let player = musicHasContent ? NotchLayout.musicPlayerHeight(layout: layout, height: budget) : NotchLayout.musicIdleHeight
                contentHeight = min(budget, player + controlsRow) + max(0, musicExtraHeight)
            case .system:
                let cards = max(0, systemCards)
                contentHeight = min(budget, cards == 0 ? NotchLayout.emptyHeight
                    : NotchLayout.railHeight(rows: systemRows(cards: cards), rowHeight: NotchLayout.systemCardHeight, spacing: NotchLayout.rowSpacing))
            case .tools:
                guard let toolCount else { contentHeight = pageBudget; break }
                contentHeight = min(budget, toolCount == 0 ? NotchLayout.emptyHeight
                    : NotchLayout.railHeight(rows: toolRows(count: toolCount), rowHeight: NotchLayout.toolHeight, spacing: NotchLayout.toolSpacing))
            case .timer:
                contentHeight = min(budget, NotchLayout.timer(mode: timerMode, hasSession: timerHasSession, width: contentWidth, height: budget))
            // Lists and previews fill the chosen content budget.
            case .mixer, .calendar, .clipboard, .captures, .files, .notifications, .downloads, .camera, .scratchpad:
                contentHeight = budget
            }
        }
        var preferredHeight = safeContentTop + NotchLayout.chromeHeight + contentHeight
        if layout == .custom { preferredHeight = min(preferredHeight, customHeight) }
        return CGSize(width: expandedWidth,
                      height: min(preferredHeight, screen.height - 48 - quickAccessBottomInset))
    }

    /// Leave room for the row indicator without narrowing the tiles below
    /// their readable width. Keyboard navigation uses these same columns.
    var sectionColumns: Int {
        NotchLayout.railCapacity(width: contentWidth - NotchLayout.sectionIndicatorWidth, itemWidth: NotchLayout.sectionTileWidth,
                                 spacing: NotchLayout.sectionSpacing)
    }

    /// Visible rows. The gallery is a page like the app panel, so a preset
    /// shows three rows before any row has to step in; the rest step in whole.
    func sectionRows(count: Int) -> Int {
        NotchLayout.railRows(count: count,
                             perRow: sectionColumns,
                             rowHeight: NotchLayout.sectionTileHeight, spacing: NotchLayout.sectionSpacing, height: pageBudget)
    }

    func sectionPickerSize(count: Int) -> CGSize {
        let content = min(pageBudget, count == 0 ? NotchLayout.emptyHeight
            : NotchLayout.railHeight(rows: sectionRows(count: count), rowHeight: NotchLayout.sectionTileHeight, spacing: NotchLayout.sectionSpacing))
        let desiredHeight = safeContentTop + NotchLayout.chromeHeight + content
        return CGSize(width: expandedWidth, height: min(desiredHeight, screen.height - 48 - quickAccessBottomInset))
    }

    func contentSize(for size: CGSize) -> CGSize {
        CGSize(width: max(0, size.width - NotchLayout.horizontalInset * 2),
               height: max(0, size.height - safeContentTop - NotchLayout.chromeHeight))
    }
    var appPanelSize: CGSize { contentSize(for: expandedSize(module: .tools, panel: true)) }
    func frame(for size: CGSize) -> CGRect {
        CGRect(x: screen.midX - size.width / 2,
               y: screen.maxY - size.height,
               width: size.width, height: size.height)
    }

    func contains(_ point: CGPoint, in size: CGSize) -> Bool {
        let frame = self.frame(for: size)
        // Match the flipped native view: the top edge belongs to the island.
        return CGRect(origin: .zero, size: size).contains(
            CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y))
    }
}

struct NotchSessionState {
    var locked = false
    var sleeping = false
    var displaysSleeping = false
    var onConsole = true
    var canRunTimer: Bool { !locked && !sleeping && onConsole }
    var canPresent: Bool { canRunTimer && !displaysSleeping }
}

/// Reserve enough backing space for both ends. The visible silhouette moves
/// inside it; the native window only shrinks after the transition finishes.
enum NotchMotion {
    static func duration(from: CGSize, to: CGSize) -> TimeInterval {
        let grows = to.height > from.height || (to.height == from.height && to.width > from.width)
        return grows ? 0.34 : 0.26
    }

    static func envelope(from: CGSize, to: CGSize) -> CGSize {
        CGSize(width: max(from.width, to.width), height: max(from.height, to.height))
    }
}

/// Free room on both sides of the camera, in Cocoa screen coordinates.
/// Unknown/occupied camera space is distinct from a known zero-width wing.
enum NotchMenuBarLayout {
    static func sideRoom(screen: CGRect, cameraWidth: CGFloat, barHeight: CGFloat,
                         occupied: [CGRect]) -> CGFloat? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
        let camera = CGRect(x: screen.midX - cameraWidth / 2, y: bar.minY,
                            width: cameraWidth, height: barHeight)
        var left = screen.minX + 8
        var right = screen.maxX - 8
        for rect in occupied where rect.intersects(bar) {
            guard rect.minX.isFinite, rect.maxX.isFinite, rect.width > 0 else { return nil }
            if rect.intersects(camera) { return nil }
            if rect.maxX <= camera.minX { left = max(left, rect.maxX + 8) }
            if rect.minX >= camera.maxX { right = min(right, rect.minX - 8) }
        }
        return max(0, min(camera.minX - left, right - camera.maxX))
    }
}
