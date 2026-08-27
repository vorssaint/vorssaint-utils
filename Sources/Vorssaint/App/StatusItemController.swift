// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Owns the menu bar presence: the black hole glyph, the optional countdown
/// title and the tooltip. Click handling is delegated back to the AppDelegate.
final class StatusItemController {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMetricClick: ((MenuBarMetric, NSStatusBarButton) -> Void)?

    private(set) var statusItem: NSStatusItem!
    private var metricStatusItems: [String: NSStatusItem] = [:]
    private var metricStatusItemFocus: [String: MenuBarMetric] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var titleTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    /// Last combination applied by updateIconAppearance, so refresh ticks
    /// don't re-render an unchanged icon every 2 seconds.
    private var lastIconStateKey = ""
    private var heldMicBadgeActive: Bool?
    /// A settings reply already waiting for the next turn of the run loop.
    private var settingsSyncScheduled = false
    /// How many readings in a row each metric has failed to render, so an
    /// item is kept through a hiccup but not forever.
    private var metricEmptyRenders: [String: Int] = [:]
    /// How many metric items are actually showing a reading. An item kept
    /// through a hiccup shows nothing, so it must not be what makes the main
    /// item step aside: that would leave the menu bar with nothing to click.
    private var renderedMetricItemCount = 0
    /// True while a refresh is running. Anything the menu bar announces back
    /// to us in the middle of one is a consequence of that same work, so it
    /// is answered once afterwards rather than on top of it.
    private var isRefreshing = false
    private var refreshRequestedWhileRunning = false
    private static let mainAutosaveName = "VorssaintMenuBarItem"
    private static let metricAutosavePrefix = "VorssaintMetric"
    private static let maxPlacementGeneration = 10_000
    private static let emptyStatusImage = NSImage()

    private struct MetricStatusGroup {
        let id: String
        let metrics: [MenuBarMetric]
        let focusMetric: MenuBarMetric
        let title: String
    }

    /// Cached so the countdown tooltip doesn't allocate a DateFormatter (expensive)
    /// on every refresh while a keep-awake session is active.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var button: NSStatusBarButton? { statusItem.button }

    func containsStatusItem(at screenPoint: NSPoint) -> Bool {
        let buttons = ([statusItem?.button] + metricStatusItems.values.map(\.button)).compactMap { $0 }
        // Bound once for the whole scan: a default argument is evaluated per
        // call, so leaving it to the default would rebuild this per button.
        let screenFrames = NSScreen.screens.map(\.frame)
        return buttons.contains { button in
            guard let frame = button.window?.frame,
                  StatusItemAnchorSupport.isTrustworthyStatusFrame(frame, screenFrames: screenFrames)
            else { return false }
            return frame.insetBy(dx: -4, dy: -8).contains(screenPoint)
        }
    }

    init() {
        installStatusItem()
        bind()
    }

    /// Creates the status item and configures its button. The menu bar item is the
    /// app's only entry point, so an empty behavior set keeps it from being dragged
    /// off the bar (reordering still works), and forcing isVisible undoes any hidden
    /// state macOS may have persisted. If it ever goes missing, re-opening the app
    /// recovers access (see applicationShouldHandleReopen) and the "Show menu bar
    /// icon" button in Settings rebuilds it.
    private func installStatusItem() {
        StatusItemPlacementSupport.sanitizeStalePlacement(in: .standard)
        // A fresh NSStatusItem starts blank; the memoized icon state belongs
        // to the previous instance and must not suppress the first apply.
        lastIconStateKey = ""
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable identity so macOS remembers the item's position across launches
        // and across rebuilds, instead of re-placing it at the crowded default spot.
        statusItem.autosaveName = StatusItemPlacementSupport.mainAutosaveName(in: .standard)
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

    /// Tears the status item down and builds a fresh one. When recovery is explicit,
    /// reset the saved placement too; otherwise macOS can restore the new item to
    /// the same hidden/crowded position that made it unreachable.
    func recreateStatusItem(resetPlacement: Bool = false) {
        if resetPlacement {
            StatusItemPlacementSupport.bumpPlacementGeneration(in: .standard)
        }
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

        MicMuteService.shared.$isMuted
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
            // Showing a status item writes its own remembered position into
            // this same domain and announces it right there on the stack, so
            // reacting immediately would call back into the work that is
            // still running. The reply waits for the next turn of the run
            // loop, and a burst of writes collapses into one.
            self?.scheduleSettingsSync()
        }
    }

    private func scheduleSettingsSync() {
        guard !settingsSyncScheduled else { return }
        settingsSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsSyncScheduled = false
            self.syncMonitorMode()
            self.updateIconAppearance()
            self.refresh()
        }
    }

    deinit {
        // The controller lives for the whole process today, but tear down cleanly
        // so a future "recreate the status item" path can't leak a firing timer or
        // a block observer that outlives this instance.
        titleTimer?.invalidate()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        for item in metricStatusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    /// Keeps the background sampler in step with the menu bar settings: it runs
    /// continuously only while at least one metric is pinned to the menu bar.
    private func syncMonitorMode() {
        let defaults = UserDefaults.standard
        let interval = Defaults.sanitizedMonitorInterval(defaults.integer(forKey: DefaultsKey.monitorInterval))
        SystemMonitor.shared.setInterval(seconds: interval)
        SystemMonitor.shared.setMenuBarActive(MenuBarMetric.anyEnabled(in: defaults))
    }

    private func syncTitleTimer(keepAwakeActive: Bool,
                                showsCountdown: Bool,
                                endDate: Date?) {
        let shouldRun = MenuBarSpacingSupport.needsTitleRefreshTimer(
            keepAwakeActive: keepAwakeActive,
            showsCountdown: showsCountdown,
            hasEndDate: endDate != nil)
        guard shouldRun else {
            titleTimer?.invalidate()
            titleTimer = nil
            return
        }
        guard titleTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    private var currentMicBadgeActive: Bool {
        MicMuteService.shared.isMuted
            && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteMenuBarIndicator)
    }

    private var renderedMicBadgeActive: Bool {
        heldMicBadgeActive ?? currentMicBadgeActive
    }

    /// Keeps the variable-width mic badge unchanged while any status item is
    /// anchoring an open panel. The current state is rendered after it closes.
    func setMicBadgeHeld(_ held: Bool) {
        if held {
            guard heldMicBadgeActive == nil else { return }
            heldMicBadgeActive = currentMicBadgeActive
            return
        }
        guard heldMicBadgeActive != nil else { return }
        heldMicBadgeActive = nil
        updateIconAppearance()
    }

    /// Reflects keep-awake state and an available update in the icon. Updates
    /// keep the blue attention glyph; an active session uses the chosen icon.
    /// With the mute indicator option on, a red slashed mic joins the glyph
    /// while the microphone is muted, whatever the underlying state. The
    /// glyph can also hide entirely while metrics render in the title (user
    /// option); the decision reads the button's actual title, so it must run
    /// AFTER refresh() writes it — refresh() calls this at its end.
    private func updateIconAppearance() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let updateAvailable: Bool
        if case .available = UpdateService.shared.state {
            updateAvailable = true
        } else {
            updateAvailable = false
        }
        let micBadgeActive = renderedMicBadgeActive
        let optionEnabled = defaults.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics)
        let separateMetrics = defaults.bool(forKey: DefaultsKey.menuBarSeparateMetrics)
        let signal = updateAvailable || micBadgeActive
        let hidden = MenuBarSpacingSupport.shouldHideStatusIcon(
            optionEnabled: optionEnabled,
            separateMetrics: separateMetrics,
            metricsEnabled: MenuBarMetric.anyEnabled(in: defaults),
            renderedTitleLength: button.attributedTitle.length,
            mustShowForSignal: signal)
        // In the separate-items mode the metrics are their own clickable
        // items, so hiding means the whole main item steps aside instead of
        // just its image (which is all that item has).
        let mainItemHidden = MenuBarSpacingSupport.shouldHideMainStatusItem(
            optionEnabled: optionEnabled,
            separateMetrics: separateMetrics,
            metricItemsShown: renderedMetricItemCount,
            renderedTitleLength: button.attributedTitle.length,
            mustShowForSignal: signal)
        let keepAwakeActive = KeepAwakeManager.shared.isActive

        // refresh() runs on every monitor tick and lands here; re-rendering
        // the same image every 2 seconds would be wasted composition, so the
        // image is only touched when some ingredient actually changed.
        let stateKey = [String(hidden), String(mainItemHidden), String(updateAvailable),
                        String(keepAwakeActive), KeepAwakeIconTint.current.rawValue,
                        KeepAwakeActiveIcon.current.rawValue,
                        String(micBadgeActive)].joined(separator: "|")
        guard stateKey != lastIconStateKey else { return }
        lastIconStateKey = stateKey

        statusItem.isVisible = !mainItemHidden

        guard !hidden else {
            // A non-nil image lets macOS apply the inactive-display appearance
            // to the title while keeping the glyph visually absent.
            button.image = Self.emptyStatusImage
            return
        }
        let stateImage: NSImage?
        if updateAvailable {
            stateImage = BlackHoleGlyph.attentionImage()
        } else {
            stateImage = BlackHoleGlyph.image(active: keepAwakeActive)
        }
        if micBadgeActive {
            button.image = BlackHoleGlyph.micMutedImage(over: stateImage) ?? stateImage
        } else {
            button.image = stateImage
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
        guard !isRefreshing else {
            refreshRequestedWhileRunning = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshRequestedWhileRunning {
                refreshRequestedWhileRunning = false
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        }
        performRefresh()
    }

    private func performRefresh() {
        guard let button = statusItem?.button else { return }
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let defaults = UserDefaults.standard
        let snapshot = SystemMonitor.shared.snapshot
        let metrics = MenuBarMetric.enabled(in: defaults)
        let separateMetrics = defaults.bool(forKey: DefaultsKey.menuBarSeparateMetrics)

        syncTitleTimer(keepAwakeActive: manager.isActive,
                       showsCountdown: defaults.bool(forKey: DefaultsKey.showCountdown),
                       endDate: manager.endDate)

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
        if separateMetrics {
            refreshMetricStatusItems(metrics: metrics, snapshot: snapshot, strings: strings)
        } else {
            removeMetricStatusItems(except: Set<String>())
            renderedMetricItemCount = 0
        }
        if !separateMetrics, !metrics.isEmpty {
            let metricsTitle = MenuBarRenderer.attributed(for: snapshot,
                                                          metrics: metrics,
                                                          allowStacked: !includesCountdown,
                                                          linePrefix: " ")
            if metricsTitle.length > 0 {
                if title.length > 0 { title.append(NSAttributedString(string: "  ")) }
                title.append(metricsTitle)
            }
        }

        // Every write below invalidates the button's layout and redraws the
        // status window even when the value is identical — and this runs on
        // every monitor tick and defaults change. Rounded metric strings
        // repeat most ticks, so skipping no-op writes skips that churn.
        if statusItem.length != NSStatusItem.variableLength {
            statusItem.length = NSStatusItem.variableLength
        }

        if title.length == 0 {
            if button.attributedTitle.length != 0 {
                button.attributedTitle = NSAttributedString(string: "")
            }
            if button.imagePosition != .imageOnly {
                button.imagePosition = .imageOnly
            }
        } else {
            // The leading space separates the glyph from the text; with the
            // glyph hidden by the metrics-only option it would be pure dead
            // padding on the item's left edge. Same decision inputs as
            // updateIconAppearance, with a sentinel length: the title is
            // known non-empty on this branch.
            let updateAvailable: Bool
            if case .available = UpdateService.shared.state {
                updateAvailable = true
            } else {
                updateAvailable = false
            }
            let micBadgeActive = renderedMicBadgeActive
            let glyphHidden = MenuBarSpacingSupport.shouldHideStatusIcon(
                optionEnabled: defaults.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics),
                separateMetrics: separateMetrics,
                metricsEnabled: !metrics.isEmpty,
                renderedTitleLength: 1,
                mustShowForSignal: updateAvailable || micBadgeActive)
            let full = NSMutableAttributedString(string: glyphHidden ? "" : " ")
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
            if !full.isEqual(to: button.attributedTitle) {
                button.font = font
                button.attributedTitle = full
            }
            if button.imagePosition != .imageLeading {
                button.imagePosition = .imageLeading
            }
        }

        let toolTip: String
        if manager.isActive {
            if manager.sessionTrigger == .automation {
                toolTip = FeatureStrings.keepAwakeAutomation(L10n.shared.language)
                    .activeStatus(for: manager.activeAutomationConditions)
            } else if let end = manager.endDate {
                toolTip = "\(strings.statusActiveUntil) \(Self.timeFormatter.string(from: end))"
            } else {
                toolTip = strings.statusActiveIndefinite
            }
        } else {
            toolTip = strings.statusIdleTooltip
        }
        if button.toolTip != toolTip {
            button.toolTip = toolTip
        }

        // The icon decision depends on the title just written (the glyph may
        // hide only while metrics actually render), so it re-runs here — the
        // one place where title and icon can never get out of step.
        updateIconAppearance()
    }

    private func refreshMetricStatusItems(metrics: [MenuBarMetric],
                                          snapshot: SystemSnapshot,
                                          strings: Strings) {
        let groups = metricStatusGroups(for: metrics, strings: strings)
        let wanted = Set(groups.map(\.id))
        removeMetricStatusItems(except: wanted)
        var rendered = 0
        defer { renderedMetricItemCount = rendered }

        for group in groups {
            let title = MenuBarRenderer.attributed(for: snapshot,
                                                   metrics: group.metrics,
                                                   allowStacked: false)
            let empties = title.length > 0 ? 0 : (metricEmptyRenders[group.id] ?? 0) + 1
            metricEmptyRenders[group.id] = empties
            guard MenuBarSpacingSupport.keepsMetricStatusItem(
                hasRenderedTitle: title.length > 0,
                itemExists: metricStatusItems[group.id] != nil,
                consecutiveEmptyRenders: empties) else {
                // The reading has been gone long enough to call it gone.
                removeMetricStatusItem(for: group.id)
                continue
            }
            if title.length > 0 { rendered += 1 }

            metricStatusItemFocus[group.id] = group.focusMetric
            let item = metricStatusItems[group.id] ?? installMetricStatusItem(for: group)
            if item.length != NSStatusItem.variableLength {
                item.length = NSStatusItem.variableLength
            }
            guard let button = item.button else { continue }

            let full = NSMutableAttributedString(attributedString: title)
            let font = MenuBarRenderer.statusFont(stacked: false)
            full.addAttribute(.font,
                              value: font,
                              range: NSRange(location: 0, length: full.length))
            if button.font?.isEqual(font) != true {
                button.font = font
            }
            if !full.isEqual(to: button.attributedTitle) {
                button.attributedTitle = full
            }
            if button.image !== Self.emptyStatusImage {
                button.image = Self.emptyStatusImage
            }
            if button.imagePosition != .noImage {
                button.imagePosition = .noImage
            }
            if button.toolTip != group.title {
                button.toolTip = group.title
            }
        }
    }

    private func metricStatusGroups(for metrics: [MenuBarMetric], strings: Strings) -> [MetricStatusGroup] {
        guard MenuBarMetricAppearance.current.allowsCombinedTemperatures,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarCombineTemperatures) else {
            return metrics.map {
                MetricStatusGroup(id: $0.rawValue, metrics: [$0], focusMetric: $0, title: $0.title(strings))
            }
        }

        let enabled = Set(metrics)
        var emittedIDs = Set<String>()
        var groups: [MetricStatusGroup] = []

        func appendComponentGroup(id: String,
                                  primary: MenuBarMetric,
                                  temperature: MenuBarMetric,
                                  primaryTitle: String) {
            guard emittedIDs.insert(id).inserted else { return }
            var groupedMetrics: [MenuBarMetric] = []
            if enabled.contains(primary) { groupedMetrics.append(primary) }
            if enabled.contains(temperature) { groupedMetrics.append(temperature) }
            guard let focusMetric = groupedMetrics.first else { return }
            let title = groupedMetrics.count > 1 ? primaryTitle : focusMetric.title(strings)
            groups.append(MetricStatusGroup(id: id,
                                            metrics: groupedMetrics,
                                            focusMetric: focusMetric,
                                            title: title))
        }

        for metric in metrics {
            switch metric {
            case .cpu, .cpuTemperature:
                appendComponentGroup(id: "cpu",
                                     primary: .cpu,
                                     temperature: .cpuTemperature,
                                     primaryTitle: strings.monitorShowCPU)
            case .gpu, .gpuTemperature:
                appendComponentGroup(id: "gpu",
                                     primary: .gpu,
                                     temperature: .gpuTemperature,
                                     primaryTitle: strings.monitorShowGPU)
            case .battery, .batteryTemperature:
                appendComponentGroup(id: "battery",
                                     primary: .battery,
                                     temperature: .batteryTemperature,
                                     primaryTitle: strings.batteryLabel)
            case .memory, .network, .diskUsage, .diskActivity, .batteryTime, .peripheralBattery, .power,
                 .fanSpeed:
                let id = metric.rawValue
                guard emittedIDs.insert(id).inserted else { continue }
                groups.append(MetricStatusGroup(id: id,
                                                metrics: [metric],
                                                focusMetric: metric,
                                                title: metric.title(strings)))
            }
        }

        return groups
    }

    private func installMetricStatusItem(for group: MetricStatusGroup) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "\(Self.metricAutosavePrefix).\(group.id)"
        item.behavior = []
        // Registered before it is shown: showing it writes its remembered
        // position and announces that write while this call is still on the
        // stack, and an unregistered item would be built all over again by
        // whoever answers that announcement.
        metricStatusItems[group.id] = item
        metricStatusItemFocus[group.id] = group.focusMetric
        item.isVisible = true
        if let button = item.button {
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = true
            button.target = self
            button.action = #selector(metricClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier("\(Self.metricAutosavePrefix).\(group.id)")
        }
        return item
    }

    @objc private func metricClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
            return
        }
        guard let metric = focusMetric(from: sender) else {
            onLeftClick?()
            return
        }
        onMetricClick?(metric, sender)
    }

    private func focusMetric(from button: NSStatusBarButton) -> MenuBarMetric? {
        let prefix = "\(Self.metricAutosavePrefix)."
        guard let identifier = button.identifier?.rawValue,
              identifier.hasPrefix(prefix) else { return nil }
        return metricStatusItemFocus[String(identifier.dropFirst(prefix.count))]
    }

    private func removeMetricStatusItems(except wanted: Set<String>) {
        let staleMetrics = metricStatusItems.keys.filter { !wanted.contains($0) }
        for id in staleMetrics {
            removeMetricStatusItem(for: id)
        }
    }

    private func removeMetricStatusItem(for id: String) {
        metricStatusItemFocus.removeValue(forKey: id)
        metricEmptyRenders.removeValue(forKey: id)
        guard let item = metricStatusItems.removeValue(forKey: id) else { return }
        NSStatusBar.system.removeStatusItem(item)
    }
}

/// The official mark, bundled as a template image so the idle state adapts to
/// light and dark menu bars. Active states can use real colors for attention.
enum BlackHoleGlyph {
    /// Logical size of the glyph in the menu bar, in points. Wide because the
    /// mark is ~1.97:1 and sized from its height. Tools/MakeIcon.swift writes
    /// the bundled PNGs at this size; `--selftest` checks the two still agree.
    static let pointSize = NSSize(width: 26, height: 20)

    /// Requested ink height for the active states' system symbols. A compact
    /// symbol has to stand taller than the wide mark to read as the same size,
    /// matching the menu bar's other compact icons at ~15 pt. Antialiasing
    /// costs about a point of what is asked for here.
    private static let symbolHeight: CGFloat = 16

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
        let tint = KeepAwakeIconTint.current
        guard active else { return base ?? fallback(active: false) }
        return activeImage(style: .current, tint: tint)
    }

    static func activeImage(style: KeepAwakeActiveIcon,
                            tint: KeepAwakeIconTint = .orange) -> NSImage? {
        let source: NSImage?
        if let symbolName = style.systemSymbolName {
            source = fixedSizeSymbol(named: symbolName, drop: style.menuBarDrop)
        } else {
            source = base
        }
        guard let source else { return fallback(active: tint != .none) }
        guard let color = color(for: tint) else {
            source.isTemplate = true
            return source
        }
        return tintedImage(source, color: color) ?? fallback(active: true)
    }

    /// System symbols have different natural widths. Center them inside the
    /// same canvas as the app glyph so activation never shifts nearby items.
    ///
    /// Sized by the symbol's ink rather than its bounding box: SF Symbols pad
    /// their box by different amounts, so fitting the box leaves each style a
    /// different, smaller size than asked for.
    private static func fixedSizeSymbol(named name: String, drop: CGFloat = 0) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)),
              symbol.size.width > 0,
              symbol.size.height > 0,
              let ink = inkBounds(of: symbol),
              ink.width > 0, ink.height > 0 else { return nil }
        let scale = min(symbolHeight / ink.height, (pointSize.width - 2) / ink.width)
        let drawSize = NSSize(width: symbol.size.width * scale,
                              height: symbol.size.height * scale)
        // Offsets used to center the ink rather than the padded box.
        let inkOrigin = NSPoint(x: ink.minX * scale, y: ink.minY * scale)
        let inkSize = NSSize(width: ink.width * scale, height: ink.height * scale)
        let image = NSImage(size: pointSize, flipped: false) { rect in
            let target = NSRect(x: rect.midX - inkOrigin.x - inkSize.width / 2,
                                y: rect.midY - inkOrigin.y - inkSize.height / 2 - drop,
                                width: drawSize.width,
                                height: drawSize.height)
            symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Bounding box of an image's visible pixels, in its own (bottom-up) point
    /// space. Only runs when the menu bar icon changes, so rasterizing is cheap.
    private static func inkBounds(of image: NSImage) -> NSRect? {
        let sampling = 2
        let wide = Int(ceil(image.size.width)) * sampling
        let high = Int(ceil(image.size.height)) * sampling
        guard wide > 0, high > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The context comes from the rep's pixel dimensions, so it draws in
        // pixels; fill the whole bitmap and scale the bounds back down. A
        // point-sized rect here would only cover a corner of it.
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(wide), height: CGFloat(high)))
        NSGraphicsContext.restoreGraphicsState()

        var minX = wide, minY = high, maxX = -1, maxY = -1
        for y in 0..<high {
            for x in 0..<wide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // colorAt() reads top-down; NSImage coordinates run bottom-up.
        let unit = CGFloat(sampling)
        return NSRect(x: CGFloat(minX) / unit,
                      y: CGFloat(high - 1 - maxY) / unit,
                      width: CGFloat(maxX - minX + 1) / unit,
                      height: CGFloat(maxY - minY + 1) / unit)
    }

    /// A blue, full-strength glyph used to flag an available update. Non-template
    /// (a real color), drawn by masking blue into the glyph's shape.
    static func attentionImage() -> NSImage? {
        guard let base else { return fallback(active: true) }
        return tintedImage(base, color: .systemBlue) ?? fallback(active: true)
    }

    /// The given state image with a red slashed microphone beside it, shown
    /// while the mute indicator option is on and the mic is muted. The badge
    /// is a real color, so the composite can't stay a template image; the
    /// drawing handler runs against the destination appearance, which keeps a
    /// template underlying glyph legible on both light and dark menu bars.
    static func micMutedImage(over underlying: NSImage?) -> NSImage? {
        guard let underlying else { return nil }
        guard let badge = NSImage(systemSymbolName: "mic.slash.fill",
                                  accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) else { return nil }
        let gap: CGFloat = 2
        let badgeSize = badge.size
        let height = max(underlying.size.height, badgeSize.height)
        let size = NSSize(width: underlying.size.width + gap + badgeSize.width, height: height)
        let composed = NSImage(size: size, flipped: false) { _ in
            let glyphRect = NSRect(x: 0, y: (height - underlying.size.height) / 2,
                                   width: underlying.size.width, height: underlying.size.height)
            underlying.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
            if underlying.isTemplate {
                // Template pixels carry no usable color of their own.
                NSColor.labelColor.setFill()
                glyphRect.fill(using: .sourceAtop)
            }
            let badgeRect = NSRect(x: underlying.size.width + gap,
                                   y: (height - badgeSize.height) / 2,
                                   width: badgeSize.width, height: badgeSize.height)
            badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.systemRed.setFill()
            badgeRect.fill(using: .sourceAtop)
            return true
        }
        composed.isTemplate = false
        return composed
    }

    private static func tintedImage(_ source: NSImage, color: NSColor) -> NSImage? {
        let tinted = NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private static func color(for tint: KeepAwakeIconTint) -> NSColor? {
        switch tint {
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .none: return nil
        }
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
