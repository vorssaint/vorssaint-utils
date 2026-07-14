// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Runs the safe part of the cleanup on a schedule the user picked: daily or
/// weekly at a chosen time. Only ever cleans what a manual scan would start
/// with already checked (the safe groups), everything still goes to the
/// Trash, and an optional notification reports the outcome. Nothing exists
/// while the schedule is off: no timer, no observers, no cost.
final class CleanerScheduler: ObservableObject {
    static let shared = CleanerScheduler()

    /// When the next automatic pass fires; the interface shows this line so
    /// arming the schedule gives visible confirmation on the spot.
    @Published private(set) var nextFire: Date?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObservers: [NSObjectProtocol] = []
    private var runObserver: AnyCancellable?

    private init() {}

    func syncWithPreferences() {
        let frequency = CleanerSchedule.Frequency.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.cleanerScheduleFrequency) ?? "off")
        guard AppFeature.cleaner.isAvailable, frequency != .off else {
            stop()
            return
        }
        installWakeObserver()
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
        if nextFire != nil { nextFire = nil }
    }

    private func installWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
            // A fire date that passed during sleep never triggers its timer;
            // recomputing catches the miss within a couple of minutes.
            self?.scheduleNext()
        }
        // The chosen time means the user's wall clock: when the time zone
        // or the system clock changes, the armed fire date is stale and the
        // schedule recomputes against the new local time.
        clockObservers = [NSNotification.Name.NSSystemTimeZoneDidChange,
                          NSNotification.Name.NSSystemClockDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil,
                                                   queue: .main) { [weak self] _ in
                self?.scheduleNext()
            }
        }
    }

    private var settings: (frequency: CleanerSchedule.Frequency, hour: Int, minute: Int, weekday: Int) {
        let defaults = UserDefaults.standard
        return (CleanerSchedule.Frequency.sanitized(
                    defaults.string(forKey: DefaultsKey.cleanerScheduleFrequency) ?? "off"),
                defaults.integer(forKey: DefaultsKey.cleanerScheduleHour),
                defaults.integer(forKey: DefaultsKey.cleanerScheduleMinute),
                defaults.integer(forKey: DefaultsKey.cleanerScheduleWeekday))
    }

    private func scheduleNext() {
        let current = settings
        guard current.frequency != .off else { return }

        let defaults = UserDefaults.standard
        let lastRunStamp = defaults.double(forKey: DefaultsKey.cleanerLastAutoRun)
        let lastRun = lastRunStamp > 0 ? Date(timeIntervalSince1970: lastRunStamp) : nil

        let fireDate: Date
        if CleanerSchedule.missedRun(now: Date(), lastRun: lastRun,
                                     frequency: current.frequency,
                                     hour: current.hour, minute: current.minute,
                                     weekday: current.weekday) {
            // Missed while the Mac was off: run soon, not the instant the
            // app comes up, so launch stays snappy.
            fireDate = Date().addingTimeInterval(120)
        } else if let next = CleanerSchedule.nextFireDate(after: Date(),
                                                          frequency: current.frequency,
                                                          hour: current.hour, minute: current.minute,
                                                          weekday: current.weekday) {
            fireDate = next
        } else {
            return
        }
        schedule(at: fireDate)
    }

    private func schedule(at fireDate: Date) {
        timer?.invalidate()
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.runAutomaticCleanup()
        }
        // Tight tolerance: one shot a day costs nothing, and a schedule that
        // fires a minute late reads as broken to anyone testing it.
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if nextFire != fireDate { nextFire = fireDate }
    }

    /// One automatic pass: scan, clean exactly what the scan pre checked
    /// (the safe groups), record the outcome, leave the tool idle again.
    private func runAutomaticCleanup() {
        let cleaner = JunkCleaner.shared
        guard cleaner.phase == .idle, runObserver == nil else {
            // The user is in the middle of a manual session: their review
            // wins. Try again in ten minutes instead of losing the day.
            schedule(at: Date().addingTimeInterval(600))
            return
        }

        // dropFirst: a published property replays its CURRENT value (.idle)
        // to every new subscriber, and that echo must not be read as "the
        // user interrupted the pass" before the pass even started.
        runObserver = cleaner.$phase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .results:
                    // The scan pre checks exactly the safe groups; an
                    // automatic run takes that selection as is.
                    if cleaner.selectedCount > 0 {
                        cleaner.cleanSelected()
                    } else {
                        self.finishRun(freed: 0)
                    }
                case let .done(freed, _):
                    self.finishRun(freed: freed)
                case .idle:
                    // The user (or a reset) interrupted the automatic pass.
                    self.runObserver = nil
                    self.scheduleNext()
                default:
                    break
                }
            }
        cleaner.scan()
    }

    private func finishRun(freed: Int64) {
        runObserver = nil
        JunkCleaner.shared.reset()
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.cleanerLastAutoRun)
        defaults.set(freed, forKey: DefaultsKey.cleanerLastAutoFreed)
        notifyIfWanted(freed: freed)
        scheduleNext()
    }

    /// Reports the outcome when the user asked to be told, through the
    /// app's regular notifier (which drops the note quietly if macOS
    /// notifications are not allowed). Even a run that found nothing posts,
    /// so a fresh schedule gives proof of life on its first pass.
    private func notifyIfWanted(freed: Int64) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.cleanerScheduleNotify) else { return }
        let strings = L10n.shared.s
        let body: String
        if freed > 0 {
            body = String(format: strings.cleanerAutoNotificationFormat,
                          ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))
        } else {
            body = strings.cleanerNothingFound
        }
        Notifier.post(title: strings.cleanerScheduleTitle, body: body)
    }
}
