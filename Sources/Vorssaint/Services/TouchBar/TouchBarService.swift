// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class TouchBarService: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarService()

    private static let groupItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.group")

    private static let keepAwakeItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.keep-awake")
    private static let micMuteItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.mic-mute")
    private static let clipboardItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.clipboard")
    private static let systemMetricsItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.system-metrics")
    private static let quickLauncherItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.quick-launcher")
    private static let killProcessItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.kill-process")

    private(set) var isActive = false
    private(set) var touchBar: NSTouchBar?

    private weak var keepAwakeButton: NSButton?
    private weak var micMuteButton: NSButton?
    private weak var systemMetricsButton: NSButton?
    private weak var memoryCleanupButton: NSButton?
    private var cancellables = Set<AnyCancellable>()

    private var localizedStrings: TouchBarFeatureStrings {
        FeatureStrings.touchBar(L10n.shared.language)
    }

    private override init() {
        super.init()

        KeepAwakeManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateKeepAwakeButton()
            }
            .store(in: &cancellables)

        MicMuteService.shared.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMicMuteButton()
            }
            .store(in: &cancellables)

        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.updateSystemMetricsLabel(snapshot)
            }
            .store(in: &cancellables)
    }

    func syncWithPreferences() {
        let shouldBeActive = AppFeature.touchBar.isAvailable
            && TouchBarHardware.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.touchBarEnabled)

        isActive = shouldBeActive

        let metricsVisible = shouldBeActive
            && TouchBarControl.visibleOrdered.contains(.systemMetrics)
        SystemMonitor.shared.setTouchBarNeeds(
            metricsVisible
                ? SystemMonitorPanelNeeds(cpu: true, memory: true)
                : .none
        )

        if shouldBeActive {
            touchBar = makeTouchBar()
        } else {
            touchBar = nil
        }
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.groupItemIdentifier]
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.groupItemIdentifier:
            return makeGroupItem(identifier: identifier)

        case Self.keepAwakeItemIdentifier:
            return makeKeepAwakeItem(identifier: identifier)

        case Self.micMuteItemIdentifier:
            return makeMicMuteItem(identifier: identifier)

        case Self.clipboardItemIdentifier:
            return makeClipboardItem(identifier: identifier)

        case Self.systemMetricsItemIdentifier:
            return makeSystemMetricsItem(identifier: identifier)

        case Self.quickLauncherItemIdentifier:
            return makeQuickLauncherItem(identifier: identifier)

        case Self.killProcessItemIdentifier:
            return makeKillProcessItem(identifier: identifier)

        default:
            return nil
        }
    }

    private func makeGroupItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)

        let controlViews: [NSView] = TouchBarControl.visibleOrdered.compactMap { control in
            switch control {
            case .keepAwake:
                return makeKeepAwakeItem(
                    identifier: Self.keepAwakeItemIdentifier
                ).view
            case .micMute:
                return makeMicMuteItem(
                    identifier: Self.micMuteItemIdentifier
                ).view
            case .clipboard:
                return makeClipboardItem(
                    identifier: Self.clipboardItemIdentifier
                ).view
            case .systemMetrics:
                return makeSystemMetricsItem(
                    identifier: Self.systemMetricsItemIdentifier
                ).view
            case .quickLauncher:
                return makeQuickLauncherItem(
                    identifier: Self.quickLauncherItemIdentifier
                ).view
            case .killProcess:
                return makeKillProcessItem(
                    identifier: Self.killProcessItemIdentifier
                ).view
            }
        }

        var arrangedViews: [NSView] = []

        for (index, view) in controlViews.enumerated() {
            if index > 0 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.white
                    .withAlphaComponent(0.14)
                    .cgColor

                separator.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    separator.widthAnchor.constraint(equalToConstant: 1),
                    separator.heightAnchor.constraint(equalToConstant: 20)
                ])

                arrangedViews.append(separator)
            }

            arrangedViews.append(view)
        }

        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(
            top: 4,
            left: 9,
            bottom: 4,
            right: 9
        )

        stack.wantsLayer = true
        stack.layer?.cornerRadius = 6
        stack.layer?.backgroundColor = NSColor.white
            .withAlphaComponent(0.16)
            .cgColor

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.heightAnchor.constraint(equalToConstant: 30).isActive = true

        item.view = stack
        return item
    }

    private func makeKillProcessItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            title: "💀",
            target: self,
            action: #selector(showKillProcess(_:))
        )
        button.isBordered = false
        item.view = button
        return item
    }

    private func makeQuickLauncherItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "square.grid.2x2",
                accessibilityDescription: localizedStrings.quickLauncher
            ) ?? NSImage(),
            target: self,
            action: #selector(showQuickLauncher(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        item.view = button
        return item
    }

    private func makeSystemMetricsItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)

        let metrics = NSButton(
            title: "CPU --% · RAM --%",
            target: self,
            action: #selector(showMemoryMetric(_:))
        )
        metrics.isBordered = false
        systemMetricsButton = metrics

        let cleanup = NSButton(
            image: NSImage(
                systemSymbolName: "eraser",
                accessibilityDescription: localizedStrings.freeRAM
            ) ?? NSImage(),
            target: self,
            action: #selector(freeRAM(_:))
        )
        cleanup.imagePosition = .imageOnly
        cleanup.isBordered = false
        memoryCleanupButton = cleanup

        let stack = NSStackView(views: [metrics, cleanup])
        stack.orientation = .horizontal
        stack.spacing = 2

        item.view = stack
        return item
    }

    private func makeClipboardItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: FeatureStrings.clipboard(
                    L10n.shared.language
                ).title
            ) ?? NSImage(),
            target: self,
            action: #selector(toggleClipboard(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        item.view = button
        return item
    }

    private func makeKeepAwakeItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: keepAwakeImage(),
            target: self,
            action: #selector(toggleKeepAwake(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false

        keepAwakeButton = button
        item.view = button
        return item
    }

    private func makeMicMuteItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: micMuteImage(),
            target: self,
            action: #selector(toggleMicMute(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false

        micMuteButton = button
        item.view = button
        return item
    }

    private func keepAwakeImage() -> NSImage {
        let symbol = KeepAwakeManager.shared.isActive
            ? "cup.and.saucer.fill"
            : "cup.and.saucer"

        return NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: localizedStrings.keepAwake
        ) ?? NSImage()
    }

    private func micMuteImage() -> NSImage {
        let symbol = MicMuteService.shared.isMuted
            ? "mic.slash.fill"
            : "mic.fill"

        return NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: localizedStrings.microphoneMute
        ) ?? NSImage()
    }

    private func updateSystemMetricsLabel(_ snapshot: SystemSnapshot) {
        let cpu = snapshot.cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "--%"
        let ram: String
        if let used = snapshot.memoryUsed,
           let total = snapshot.memoryTotal,
           total > 0 {
            ram = "\(Int((Double(used) / Double(total) * 100).rounded()))%"
        } else {
            ram = "--%"
        }

        systemMetricsButton?.title = "CPU \(cpu) · RAM \(ram)"

        let cleanupSymbol: String
        switch snapshot.memoryPressure {
        case .warning, .critical:
            cleanupSymbol = "eraser.fill"
        case .normal, .unknown:
            cleanupSymbol = "eraser"
        }

        memoryCleanupButton?.image = NSImage(
            systemSymbolName: cleanupSymbol,
            accessibilityDescription: localizedStrings.freeRAM
        )
    }

    @objc private func showMemoryMetric(_ sender: NSButton) {
        (NSApp.delegate as? AppDelegate)?.showMemoryMetricPanel()
    }

    private func updateKeepAwakeButton() {
        keepAwakeButton?.image = keepAwakeImage()
    }

    private func updateMicMuteButton() {
        micMuteButton?.image = micMuteImage()
    }

    @objc private func freeRAM(_ sender: NSButton) {
        let result = MemoryCleanupService.freeRAM()

        guard result == KERN_SUCCESS else {
            NSSound.beep()
            return
        }

        sender.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: localizedStrings.ramCleanupCompleted
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak sender] in
            guard let sender else { return }

            let pressure = SystemMonitor.shared.snapshot.memoryPressure
            let symbol = switch pressure {
            case .warning, .critical: "eraser.fill"
            case .normal, .unknown: "eraser"
            }

            sender.image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: self.localizedStrings.freeRAM
            )
        }
    }

    @objc private func showKillProcess(_ sender: NSButton) {
        if AppFeature.killProcess.isAvailable {
            SettingsRouter.shared.request(FeatureSettingsDestination(.killProcess))
        } else {
            SettingsRouter.shared.request(
                FeatureSettingsDestination(.features),
                targetFeature: .killProcess
            )
        }
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    @objc private func showQuickLauncher(_ sender: NSButton) {
        if AppFeature.quickLauncher.isAvailable {
            QuickLauncherService.shared.show()
        } else {
            SettingsRouter.shared.request(
                FeatureSettingsDestination(.features),
                targetFeature: .quickLauncher
            )
            (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        }
    }

    @objc private func toggleClipboard(_ sender: NSButton) {
        ClipboardHistoryService.shared.toggleHistoryWindow()
    }

    @objc private func toggleKeepAwake(_ sender: NSButton) {
        KeepAwakeManager.shared.toggle()
    }

    @objc private func toggleMicMute(_ sender: NSButton) {
        MicMuteService.shared.toggle()
    }
}
