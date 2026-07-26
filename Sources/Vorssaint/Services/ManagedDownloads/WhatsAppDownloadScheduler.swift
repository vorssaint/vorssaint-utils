// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Runs one lightweight pass per day while automatic WhatsApp cleanup is on.
/// Missed passes are recovered after launch/wake, and nothing remains alive
/// when either the feature or the automation is off.
final class WhatsAppDownloadScheduler: ObservableObject {
    static let shared = WhatsAppDownloadScheduler()

    @Published private(set) var nextFire: Date?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObservers: [NSObjectProtocol] = []
    private var runObserver: AnyCancellable?

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        guard AppFeature.cleaner.isAvailable,
              defaults.bool(forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled),
              defaults.bool(forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed) else {
            stop()
            return
        }
        if defaults.double(forKey: DefaultsKey.whatsAppDownloadsAutomaticStartDate) <= 0,
           !defaults.bool(forKey: DefaultsKey.whatsAppDownloadsIncludeExisting) {
            defaults.set(Date().timeIntervalSince1970,
                         forKey: DefaultsKey.whatsAppDownloadsAutomaticStartDate)
        }
        installObservers()
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        for observer in clockObservers { NotificationCenter.default.removeObserver(observer) }
        clockObservers = []
        runObserver = nil
        nextFire = nil
    }

    private func installObservers() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleNext() }
        clockObservers = [NSNotification.Name.NSSystemTimeZoneDidChange,
                          NSNotification.Name.NSSystemClockDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil,
                                                   queue: .main) { [weak self] _ in
                self?.scheduleNext()
            }
        }
    }

    private func scheduleNext() {
        guard AppFeature.cleaner.isAvailable,
              UserDefaults.standard.bool(
                forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled),
              UserDefaults.standard.bool(
                forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed) else { return }
        let now = Date()
        let lastStamp = UserDefaults.standard.double(
            forKey: DefaultsKey.whatsAppDownloadsLastAutoRun)
        let lastRun = lastStamp > 0 ? Date(timeIntervalSince1970: lastStamp) : nil
        let fireDate: Date
        if WhatsAppDownloadSupport.missedAutomaticCheck(now: now, lastRun: lastRun) {
            fireDate = now.addingTimeInterval(120)
        } else {
            guard let next = WhatsAppDownloadSupport.nextAutomaticCheck(after: now) else { return }
            fireDate = next
        }
        schedule(at: fireDate)
    }

    private func schedule(at date: Date) {
        timer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.runAutomaticCleanup()
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        nextFire = date
    }

    private func runAutomaticCleanup() {
        let manager = WhatsAppDownloadManager.shared
        let organizer = WhatsAppDownloadOrganizer.shared
        let userIsReviewing = manager.phase == .results && manager.reviewVisible
        guard runObserver == nil,
              !organizer.isBusy,
              manager.phase != .scanning,
              manager.phase != .cleaning,
              !userIsReviewing else {
            schedule(at: Date().addingTimeInterval(600))
            return
        }

        runObserver = manager.$phase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .results:
                    // The person may have opened the review while the pass's
                    // scan was in flight; automation must never rewrite their
                    // checkboxes or clean under their eyes. Step aside and
                    // try again later.
                    guard !manager.reviewVisible else {
                        self.runObserver = nil
                        self.schedule(at: Date().addingTimeInterval(600))
                        return
                    }
                    manager.selectAutomaticRules()
                    if manager.selectedCount > 0 {
                        manager.cleanSelected(automatic: true)
                    } else {
                        manager.completeAutomaticWithoutCleaning()
                    }
                case let .done(moved, bytes, failed):
                    self.finishRun(moved: moved, bytes: bytes, failed: failed)
                case .failed:
                    self.finishRun(moved: 0, bytes: 0, failed: 1, notify: false)
                default:
                    break
                }
            }
        manager.scan()
    }

    private func finishRun(moved: Int, bytes: Int64, failed: Int, notify: Bool = true) {
        runObserver = nil
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: DefaultsKey.whatsAppDownloadsLastAutoRun)
        if notify, UserDefaults.standard.bool(forKey: DefaultsKey.whatsAppDownloadsNotify) {
            let strings = FeatureStrings.whatsAppDownloads(L10n.shared.language)
            let body = String(format: strings.notificationFormat, moved,
                              ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), failed)
            Notifier.post(title: strings.notificationTitle, body: body)
        }
        scheduleNext()
    }
}
