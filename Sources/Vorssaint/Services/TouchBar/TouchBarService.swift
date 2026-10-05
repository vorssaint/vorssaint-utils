// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class TouchBarService: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarService()

    private static let keepAwakeItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.keep-awake")
    private static let micMuteItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.mic-mute")
    private static let clipboardItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.clipboard")
    private static let systemMetricsItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.system-metrics")
    private static let mediaItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.media")
    private static let quickLauncherItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.quick-launcher")
    private static let killProcessItemIdentifier =
        NSTouchBarItem.Identifier("com.vorssaint.touchbar.kill-process")

    private(set) var isActive = false
    private(set) var touchBar: NSTouchBar?

    private weak var keepAwakeButton: NSButton?
    private weak var micMuteButton: NSButton?
    private weak var systemMetricsButton: NSButton?
    private weak var mediaToggleButton: NSButton?
    private var cancellables = Set<AnyCancellable>()

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

        NotchMusicService.shared.$playback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playback in
                self?.updateMediaToggleButton(isPlaying: playback?.isPlaying ?? false)
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

        let mediaVisible = shouldBeActive
            && TouchBarControl.visibleOrdered.contains(.media)
        if mediaVisible {
            NotchMusicService.shared.start(for: .touchBar)
        } else {
            NotchMusicService.shared.stop(for: .touchBar)
        }

        if shouldBeActive {
            touchBar = makeTouchBar()
        } else {
            touchBar = nil
        }
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = TouchBarControl.visibleOrdered.map { control in
            switch control {
            case .keepAwake:
                return Self.keepAwakeItemIdentifier
            case .micMute:
                return Self.micMuteItemIdentifier
            case .clipboard:
                return Self.clipboardItemIdentifier
            case .systemMetrics:
                return Self.systemMetricsItemIdentifier
            case .media:
                return Self.mediaItemIdentifier
            case .quickLauncher:
                return Self.quickLauncherItemIdentifier
            case .killProcess:
                return Self.killProcessItemIdentifier
            }
        }
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.keepAwakeItemIdentifier:
            return makeKeepAwakeItem(identifier: identifier)

        case Self.micMuteItemIdentifier:
            return makeMicMuteItem(identifier: identifier)

        case Self.clipboardItemIdentifier:
            return makeClipboardItem(identifier: identifier)

        case Self.systemMetricsItemIdentifier:
            return makeSystemMetricsItem(identifier: identifier)

        case Self.mediaItemIdentifier:
            return makeMediaItem(identifier: identifier)

        case Self.quickLauncherItemIdentifier:
            return makeQuickLauncherItem(identifier: identifier)

        case Self.killProcessItemIdentifier:
            return makeKillProcessItem(identifier: identifier)

        default:
            return nil
        }
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
                accessibilityDescription: "Quick Launcher"
            ) ?? NSImage(),
            target: self,
            action: #selector(showQuickLauncher(_:))
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        item.view = button
        return item
    }

    private func makeMediaItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)

        let previous = NSButton(
            image: NSImage(
                systemSymbolName: "backward.end.fill",
                accessibilityDescription: "Previous"
            ) ?? NSImage(),
            target: self,
            action: #selector(mediaPrevious(_:))
        )

        let toggle = NSButton(
            image: NSImage(
                systemSymbolName: "play.fill",
                accessibilityDescription: "Play/Pause"
            ) ?? NSImage(),
            target: self,
            action: #selector(mediaToggle(_:))
        )

        mediaToggleButton = toggle

        let next = NSButton(
            image: NSImage(
                systemSymbolName: "forward.end.fill",
                accessibilityDescription: "Next"
            ) ?? NSImage(),
            target: self,
            action: #selector(mediaNext(_:))
        )

        for button in [previous, toggle, next] {
            button.imagePosition = .imageOnly
            button.isBordered = false
        }

        let stack = NSStackView(views: [previous, toggle, next])
        stack.orientation = .horizontal
        stack.spacing = 4

        item.view = stack
        return item
    }

    private func makeSystemMetricsItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            title: "CPU --% · RAM --%",
            target: self,
            action: #selector(showMemoryMetric(_:))
        )
        button.isBordered = false
        systemMetricsButton = button
        item.view = button
        return item
    }

    private func makeClipboardItem(
        identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Clipboard"
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
            accessibilityDescription: "Keep Awake"
        ) ?? NSImage()
    }

    private func micMuteImage() -> NSImage {
        let symbol = MicMuteService.shared.isMuted
            ? "mic.slash.fill"
            : "mic.fill"

        return NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Microphone Mute"
        ) ?? NSImage()
    }

    private func updateMediaToggleButton(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        mediaToggleButton?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Play/Pause"
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
        QuickLauncherService.shared.show()
    }

    @objc private func mediaPrevious(_ sender: NSButton) {
        NotchMusicService.shared.send(.previous)
    }

    @objc private func mediaToggle(_ sender: NSButton) {
        NotchMusicService.shared.send(.toggle)
    }

    @objc private func mediaNext(_ sender: NSButton) {
        NotchMusicService.shared.send(.next)
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
