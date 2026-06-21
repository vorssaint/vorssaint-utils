// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Owns the menu bar presence: the black hole glyph, the optional countdown
/// title and the tooltip. Click handling is delegated back to the AppDelegate.
final class StatusItemController {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private(set) var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var titleTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    /// Cached so the countdown tooltip doesn't allocate a DateFormatter (expensive)
    /// on every refresh while a keep-awake session is active.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var button: NSStatusBarButton? { statusItem.button }

    init() {
        installStatusItem()
        bind()

        titleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        titleTimer?.tolerance = 5
    }

    /// Creates the status item and configures its button. The menu bar item is the
    /// app's only entry point, so an empty behavior set keeps it from being dragged
    /// off the bar (reordering still works), and forcing isVisible undoes any hidden
    /// state macOS may have persisted. If it ever goes missing, re-opening the app
    /// recovers access (see applicationShouldHandleReopen) and the "Show menu bar
    /// icon" button in Settings rebuilds it.
    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable identity so macOS remembers the item's position across launches
        // and across rebuilds, instead of re-placing it at the crowded default spot.
        statusItem.autosaveName = "VorssaintMenuBarItem"
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = BlackHoleGlyph.image(active: false)
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = false
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
        syncMonitorMode()
        updateIconAppearance()
    }

    /// Tears the status item down and builds a fresh one. macOS sometimes drops an
    /// item from a crowded or notched menu bar and won't re-place it; a brand new
    /// item forces it to re-register, which usually brings the icon back. Backs the
    /// "Show menu bar icon" button in Settings.
    func recreateStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        installStatusItem()
    }

    private func bind() {
        KeepAwakeManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIconAppearance()
                self?.refresh()
            }
            .store(in: &cancellables)

        UpdateService.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIconAppearance() }
            .store(in: &cancellables)

        KeepAwakeManager.shared.$endDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        L10n.shared.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard MenuBarMetric.anyEnabled(in: .standard) else { return }
                self?.refresh()
            }
            .store(in: &cancellables)

        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            self?.syncMonitorMode()
            self?.refresh()
        }
    }

    deinit {
        // The controller lives for the whole process today, but tear down cleanly
        // so a future "recreate the status item" path can't leak a firing timer or
        // a block observer that outlives this instance.
        titleTimer?.invalidate()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    /// Keeps the background sampler in step with the menu bar settings: it runs
    /// continuously only while at least one metric is pinned to the menu bar.
    private func syncMonitorMode() {
        let defaults = UserDefaults.standard
        let interval = Defaults.sanitizedMonitorInterval(defaults.integer(forKey: DefaultsKey.monitorInterval))
        SystemMonitor.shared.setInterval(seconds: interval)
        SystemMonitor.shared.setMenuBarActive(MenuBarMetric.anyEnabled(in: defaults))
    }

    /// Reflects keep-awake state and an available update in the icon. Updates
    /// keep the blue attention color; an active keep-awake session turns amber.
    private func updateIconAppearance() {
        guard let button = statusItem?.button else { return }
        if case .available = UpdateService.shared.state {
            button.image = BlackHoleGlyph.attentionImage()
        } else {
            button.image = BlackHoleGlyph.image(active: KeepAwakeManager.shared.isActive)
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    /// Updates the countdown title and tooltip from the current session state.
    func refresh() {
        guard let button = statusItem?.button else { return }
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let defaults = UserDefaults.standard

        // Compose the title from the keep-awake countdown (when shown) followed by
        // the pinned live metrics. Built attributed so the memory pressure dot can
        // carry its green/yellow/red color; all other runs stay adaptive.
        let title = NSMutableAttributedString()
        var includesCountdown = false
        if manager.isActive, defaults.bool(forKey: DefaultsKey.showCountdown) {
            let countdown: String
            if let end = manager.endDate {
                let remaining = max(0, Int(end.timeIntervalSinceNow))
                let hours = remaining / 3600
                let minutes = (remaining % 3600) / 60
                countdown = hours > 0 ? String(format: "%d:%02d", hours, minutes) : "\(max(minutes, 1)) min"
            } else {
                countdown = "∞"
            }
            title.append(NSAttributedString(string: countdown))
            includesCountdown = true
        }
        let metrics = MenuBarMetric.enabled(in: defaults)
        if !metrics.isEmpty {
            let metricsTitle = MenuBarRenderer.attributed(for: SystemMonitor.shared.snapshot,
                                                          metrics: metrics,
                                                          allowStacked: !includesCountdown,
                                                          linePrefix: " ")
            if metricsTitle.length > 0 {
                if title.length > 0 { title.append(NSAttributedString(string: "  ")) }
                title.append(metricsTitle)
            }
        }

        statusItem.length = NSStatusItem.variableLength

        if title.length == 0 {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        } else {
            let full = NSMutableAttributedString(string: " ")
            full.append(title)
            let stacked = full.string.contains("\n")
            let font = MenuBarRenderer.statusFont(stacked: stacked)
            full.addAttribute(.font, value: font, range: NSRange(location: 0, length: full.length))
            if stacked {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .left
                paragraph.lineBreakMode = .byClipping
                paragraph.minimumLineHeight = MenuBarRenderer.statusLineHeight(stacked: true)
                paragraph.maximumLineHeight = MenuBarRenderer.statusLineHeight(stacked: true)
                full.addAttribute(.paragraphStyle,
                                  value: paragraph,
                                  range: NSRange(location: 0, length: full.length))
                full.addAttribute(.baselineOffset,
                                  value: -0.4,
                                  range: NSRange(location: 0, length: full.length))
            }
            button.font = font
            button.attributedTitle = full
            button.imagePosition = .imageLeading
        }

        if manager.isActive {
            if let end = manager.endDate {
                button.toolTip = "\(strings.statusActiveUntil) \(Self.timeFormatter.string(from: end))"
            } else {
                button.toolTip = strings.statusActiveIndefinite
            }
        } else {
            button.toolTip = strings.statusIdleTooltip
        }
    }
}

/// The official mark, bundled as a template image so the idle state adapts to
/// light and dark menu bars. Active states use real colors for attention.
enum BlackHoleGlyph {
    /// Logical size of the glyph in the menu bar, in points.
    private static let pointSize = NSSize(width: 20, height: 14)

    /// Both scale representations go into one NSImage — loading the 1x file
    /// alone would render blurry on Retina menu bars.
    private static let base: NSImage? = {
        let image = NSImage(size: pointSize)
        for resource in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data)
            else { continue }
            rep.size = pointSize
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }()

    static func image(active: Bool) -> NSImage? {
        guard let base else { return fallback(active: active) }
        return active ? awakeImage() ?? base : base
    }

    /// Amber marks an active keep-awake session so it is easier to notice at a
    /// glance than the normal adaptive menu bar icon.
    static func awakeImage() -> NSImage? {
        tintedImage(color: .systemOrange) ?? fallback(active: true)
    }

    /// A blue, full-strength glyph used to flag an available update. Non-template
    /// (a real color), drawn by masking blue into the glyph's shape.
    static func attentionImage() -> NSImage? {
        tintedImage(color: .systemBlue) ?? fallback(active: true)
    }

    private static func tintedImage(color: NSColor) -> NSImage? {
        guard let base else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    /// Keeps a recognizable presence if the bundled asset is ever missing
    /// (e.g. running the bare binary from build/).
    private static func fallback(active: Bool) -> NSImage? {
        if let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: active ? .bold : .regular)) {
            symbol.isTemplate = true
            return symbol
        }
        // Guaranteed last resort: draw a filled circle so the button always has a
        // visible, clickable image and can never become a zero-width, invisible item.
        let drawn = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        drawn.isTemplate = true
        return drawn
    }
}
