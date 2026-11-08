// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Intents
import OSLog

enum NotchFocusAuthorization: Equatable {
    case authorized, notDetermined, denied

    static var current: NotchFocusAuthorization {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

struct NotchIdleStatus: Equatable {
    var authorization = NotchFocusAuthorization.current
    var focusActive = false
}

final class NotchIdleStatusService: ObservableObject {
    static let shared = NotchIdleStatusService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                       category: "NotchFocusStatus")

    @Published private(set) var status = NotchIdleStatus()

    private var poll: Timer?
    private var requestInProgress = false

    private init() {}

    func synchronize(for content: NotchIdleContent) {
        synchronize(focusSelected: content == .focus)
    }

    func synchronize(focusSelected: Bool) {
        guard focusSelected else {
            poll?.invalidate()
            poll = nil
            refresh()
            return
        }

        refresh()
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func requestFocusAuthorization() {
        guard !requestInProgress,
              INFocusStatusCenter.default.authorizationStatus == .notDetermined else { return }
        requestInProgress = true
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestInProgress = false
                self.refresh()
                if status == .denied {
                    Self.logger.info("Focus Status access was not granted.")
                }
            }
        }
    }

    func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Focus"),
              NSWorkspace.shared.open(url) else {
            Self.logger.error("Could not open Focus privacy settings.")
            NSSound.beep()
            return
        }
    }

    func refreshPermissionStatus() {
        refresh()
    }

    private func refresh() {
        let focusCenter = INFocusStatusCenter.default
        update(NotchIdleStatus(
            authorization: NotchFocusAuthorization.current,
            focusActive: focusCenter.authorizationStatus == .authorized
                && (focusCenter.focusStatus.isFocused ?? false)
        ))
    }

    private func update(_ next: NotchIdleStatus) {
        guard status != next else { return }
        status = next
    }
}
