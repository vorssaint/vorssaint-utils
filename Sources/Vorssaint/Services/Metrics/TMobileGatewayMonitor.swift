// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// One LAN reader shared by the visible panel and the pinned menu bar
/// indicator. Settings previews are never consumers.
@MainActor
final class TMobileGatewayMonitor {
    static let shared = TMobileGatewayMonitor(service: TMobileGatewayService(), defaults: .standard)

    let service: TMobileGatewayService
    private let defaults: UserDefaults
    private var panelVisible = false
    private var isPolling = false
    private var cancellables = Set<AnyCancellable>()

    init(service: TMobileGatewayService, defaults: UserDefaults) {
        self.service = service
        self.defaults = defaults
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncPreferences() }
            .store(in: &cancellables)
        syncPreferences()
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        syncPreferences()
    }

    func syncPreferences() {
        let menuBarEnabled = MenuBarMetric.enabled(in: defaults).contains { $0.isTMobileGateway }
        let shouldPoll = TMobileGatewayMenuBarSupport.needsPolling(
            networkAvailable: defaults.bool(forKey: AppFeature.monitorNetwork.availabilityKey),
            panelVisible: panelVisible, panelEnabled: defaults.bool(forKey: DefaultsKey.monitorNetTMobile),
            menuBarEnabled: menuBarEnabled)
        if shouldPoll {
            // start() is idempotent for the current validated address and
            // retires the previous request before starting a changed origin.
            service.start(baseURL: defaults.string(forKey: DefaultsKey.tMobileGatewayAddress)
                          ?? TMobileGatewayService.defaultBaseURL)
        } else if isPolling {
            service.cancel()
        }
        isPolling = shouldPoll
    }
}
