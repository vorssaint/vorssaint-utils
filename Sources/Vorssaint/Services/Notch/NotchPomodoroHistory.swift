// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchPomodoroHistory {
    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let completedAt: Date
        let phase: NotchTimerPhase
        let durationSeconds: Int

        init?(session: NotchTimerSession, completedAt: Date) {
            guard session.mode == .pomodoro, session.completed else { return nil }
            id = UUID()
            self.completedAt = completedAt
            phase = session.phase
            durationSeconds = Int(session.duration)
        }
    }

    struct Day: Identifiable {
        let date: Date
        var entries: [Entry]
        var id: Date { date }

        var focusSeconds: Int {
            entries.reduce(0) { $0 + ($1.phase == .focus ? $1.durationSeconds : 0) }
        }

        var breakSeconds: Int {
            entries.reduce(0) { $0 + ($1.phase == .focus ? 0 : $1.durationSeconds) }
        }
    }

    struct Snapshot {
        let calendar: Calendar
        let readFailed: Bool
        private(set) var days: [Day]
        private(set) var months: [Date]
        var writeFailed = false

        var storageUnavailable: Bool { readFailed || writeFailed }

        init(calendar: Calendar, readFailed: Bool, days: [Day]) {
            self.calendar = calendar
            self.readFailed = readFailed
            self.days = days
            months = Self.months(for: days, calendar: calendar)
        }

        mutating func insert(_ entry: Entry) {
            let date = calendar.startOfDay(for: entry.completedAt)
            let index = days.firstIndex { $0.date <= date } ?? days.endIndex
            guard index < days.endIndex, days[index].date == date else {
                days.insert(Day(date: date, entries: [entry]), at: index)
                months = Self.months(for: days, calendar: calendar)
                return
            }
            let row = days[index].entries.firstIndex { $0.completedAt < entry.completedAt }
                ?? days[index].entries.endIndex
            days[index].entries.insert(entry, at: row)
        }

        func recentDays(through now: Date) -> [Day] {
            let today = calendar.startOfDay(for: now)
            return (-6...0).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
                return day(containing: date)
            }
        }

        func day(containing date: Date) -> Day {
            let start = calendar.startOfDay(for: date)
            return days.first { $0.date == start } ?? Day(date: start, entries: [])
        }

        func days(inMonth date: Date) -> ArraySlice<Day> {
            guard let interval = calendar.dateInterval(of: .month, for: date),
                  let first = days.firstIndex(where: { $0.date < interval.end }) else { return [] }
            return days[first...].prefix { $0.date >= interval.start }
        }

        private static func months(for days: [Day], calendar: Calendar) -> [Date] {
            days.reduce(into: [Date]()) { months, day in
                guard let start = calendar.dateInterval(of: .month, for: day.date)?.start,
                      start != months.last else { return }
                months.append(start)
            }
        }
    }

    static func days(_ entries: [Entry], calendar: Calendar) -> [Day] {
        let newestFirst = entries.sorted { $0.completedAt > $1.completedAt }
        let grouped = Dictionary(grouping: newestFirst) { calendar.startOfDay(for: $0.completedAt) }
        return grouped.map { Day(date: $0.key, entries: $0.value) }.sorted { $0.date > $1.date }
    }

    static func csv(_ entries: [Entry]) -> String {
        let timestamp = ISO8601DateFormatter()
        let rows = entries.sorted { $0.completedAt < $1.completedAt }.map { entry in
            "\(timestamp.string(from: entry.completedAt)),\(entry.phase.rawValue),\(entry.durationSeconds)"
        }
        return (["completed_at,phase,duration_seconds"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    // One immutable file per interval in the private container. A failed or
    // concurrent write cannot replace another interval or the legacy history.
    struct Store {
        let containerURL: URL

        var recordsURL: URL { containerURL.appendingPathComponent("pomodoro-history", isDirectory: true) }
        var legacyURL: URL { containerURL.appendingPathComponent("pomodoro-history.json") }

        func write(_ entry: Entry) -> Bool {
            guard let data = try? JSONEncoder().encode(entry),
                  PrivateFileStore.createDirectory(at: recordsURL, container: containerURL) else { return false }
            return PrivateFileStore.write(data, to: recordsURL.appendingPathComponent(entry.id.uuidString + ".json"))
        }

        func read() -> (entries: [Entry], failed: Bool) {
            let decoder = JSONDecoder()
            var entries: [UUID: Entry] = [:]
            var failed = false

            func add(_ entry: Entry) {
                guard [.focus, .shortBreak, .longBreak].contains(entry.phase),
                      (1...(NotchPomodoroConfiguration.focusRange.upperBound * 60)).contains(entry.durationSeconds),
                      (Date.distantPast...Date.distantFuture).contains(entry.completedAt) else {
                    failed = true
                    return
                }
                entries[entry.id] = entry
            }

            do {
                let data = try Data(contentsOf: legacyURL)
                if let legacy = try? decoder.decode([Entry].self, from: data) {
                    legacy.forEach(add)
                } else {
                    failed = true
                    // Older builds wrote one array. Recover its valid rows
                    // when possible and leave the original file in place.
                    if let rows = try JSONSerialization.jsonObject(with: data) as? [Any] {
                        for row in rows {
                            guard let data = try? JSONSerialization.data(withJSONObject: row, options: .fragmentsAllowed),
                                  let entry = try? decoder.decode(Entry.self, from: data) else { continue }
                            add(entry)
                        }
                    }
                }
            } catch CocoaError.fileReadNoSuchFile {
                // The legacy file is absent on new installs.
            } catch {
                failed = true
            }

            do {
                let files = try FileManager.default.contentsOfDirectory(at: recordsURL,
                    includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                for file in files where file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file),
                          let entry = try? decoder.decode(Entry.self, from: data),
                          UUID(uuidString: file.deletingPathExtension().lastPathComponent) == entry.id else {
                        failed = true
                        continue
                    }
                    add(entry)
                }
            } catch CocoaError.fileReadNoSuchFile {
                // No intervals have been saved by this build yet.
            } catch {
                failed = true
            }
            return (Array(entries.values), failed)
        }
    }

    final class Persistence {
        private let store: Store?
        private let queue = DispatchQueue(label: "com.vorssaint.pomodoro-history", qos: .utility)
        private var pending: [Entry] = []
        private var snapshot: Snapshot?
        private var observer: ((Snapshot) -> Void)?
        private var retryScheduled = false
        private var retryDelay: TimeInterval
        private let initialRetryDelay: TimeInterval

        init(store: Store?, retryDelay: TimeInterval = 5) {
            self.store = store
            self.initialRetryDelay = retryDelay
            self.retryDelay = retryDelay
        }

        func load(calendar: Calendar = .current, onUpdate: @escaping (Snapshot) -> Void) {
            queue.async {
                self.observer = onUpdate
                self.refreshSnapshot(calendar: calendar)
                self.publish()
            }
        }

        func record(_ entry: Entry) {
            queue.async {
                self.pending.append(entry)
                self.snapshot?.insert(entry)
                self.savePending()
                self.publish()
                self.scheduleRetry()
            }
        }

        func flush() {
            queue.sync { savePending() }
        }

        func export(_ snapshot: Snapshot, to destination: URL, onFailure: @escaping () -> Void) {
            queue.async {
                do {
                    let csv = NotchPomodoroHistory.csv(snapshot.days.flatMap(\.entries))
                    try Data(csv.utf8).write(to: destination, options: .atomic)
                } catch {
                    DispatchQueue.main.async { onFailure() }
                }
            }
        }

        private func refreshSnapshot(calendar: Calendar) {
            let result = store?.read() ?? (entries: [], failed: true)
            let saved = Set(result.entries.map(\.id))
            let entries = result.entries + pending.filter { !saved.contains($0.id) }
            snapshot = Snapshot(calendar: calendar, readFailed: result.failed,
                                days: NotchPomodoroHistory.days(entries, calendar: calendar))
        }

        private func savePending() {
            guard let store else { return }
            pending.removeAll { store.write($0) }
            if pending.isEmpty { retryDelay = initialRetryDelay }
        }

        private func publish() {
            guard var snapshot, let observer else { return }
            snapshot.writeFailed = !pending.isEmpty
            let update = snapshot
            DispatchQueue.main.async { observer(update) }
        }

        private func scheduleRetry() {
            guard store != nil, !pending.isEmpty, !retryScheduled else { return }
            retryScheduled = true
            queue.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                guard let self else { return }
                self.retryScheduled = false
                self.savePending()
                if self.pending.isEmpty, let snapshot = self.snapshot, snapshot.readFailed {
                    self.refreshSnapshot(calendar: snapshot.calendar)
                }
                self.publish()
                self.scheduleRetry()
            }
            retryDelay = min(retryDelay * 2, 60)
        }
    }
}
