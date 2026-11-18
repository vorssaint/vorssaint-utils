// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryAction: String, Codable, CaseIterable {
    case resume, pause, topUp, discharge, calibrate, cancel, setLimit, lowPowerOn, lowPowerOff
}
enum BatteryMode: String, Codable { case automatic, paused, topUp, discharge, calibration }
enum BatteryPhase: String, Codable { case firstCharge, drain, finalCharge, returnToLimit }
enum BatteryState: String, Codable {
    case disabled, charging, holding, sailing, discharging, topUp, calibration, heatProtection, sleeping, onBattery, unavailable
}
enum BatteryLED: String, Codable, CaseIterable { case automatic, green, orange, blinking, off }
enum BatteryRepeat: String, Codable, CaseIterable { case once, daily, weekdays, weekly, fortnightly, monthly, yearly }

struct BatterySchedule: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var date = Date()
    var repetition: BatteryRepeat = .daily
    var action: BatteryAction = .topUp
    var value = 80

    /// Advance from the intended date, never replay every missed occurrence after sleep.
    func next(after now: Date, calendar: Calendar = .current) -> Date? {
        guard repetition != .once else { return nil }
        let component: Calendar.Component
        let amount: Int
        switch repetition {
        case .once: return nil
        case .daily, .weekdays: component = .day; amount = 1
        case .weekly: component = .day; amount = 7
        case .fortnightly: component = .day; amount = 14
        case .monthly: component = .month; amount = 1
        case .yearly: component = .year; amount = 1
        }
        let elapsed = calendar.dateComponents([component], from: date, to: now).value(for: component) ?? 0
        let first = max(1, elapsed / amount)
        for step in first..<(first + 8) {
            guard let candidate = calendar.date(byAdding: component, value: step * amount, to: date) else { return nil }
            if candidate > now && (repetition != .weekdays || !calendar.isDateInWeekend(candidate)) { return candidate }
        }
        return nil
    }
}

struct BatteryConfiguration: Codable, Equatable {
    var enabled = false
    var limit = 80
    var sailing = 5
    var heatProtection = true
    var maximumTemperature = 35
    var automaticDischarge = false
    var dischargeInClamshell = false
    var stopOnSleep = true
    var continueWhenClosed = false
    var pauseWhenClosed = false
    var preventSleep = false
    var led: BatteryLED = .automatic
    var schedules: [BatterySchedule] = []

    var valid: Bool {
        (20...100).contains(limit) && (0...20).contains(sailing) && limit - sailing >= 10
            && (25...45).contains(maximumTemperature) && schedules.count <= 32
            && Set(schedules.map(\.id)).count == schedules.count
            && schedules.allSatisfy { (20...100).contains($0.value) && $0.date.timeIntervalSince1970.isFinite }
    }
}

struct BatteryTelemetry: Codable, Equatable {
    var percent: Int
    var temperature: Double?
    var adapterConnected: Bool
    var charging: Bool
    var full: Bool
    var clamshell: Bool
    var watts: Double?
    var voltage: Double?
    var cycles: Int?
    var health: Double?
    var hardwarePercent: Double?
    var adapterWatts: Double?
    var minutesToFull: Int?
    var valid: Bool { (0...100).contains(percent) }
}

struct BatteryDecision: Equatable {
    var state: BatteryState
    var limit: Int
    var disconnectAdapter = false
}

/// Pure policy shared with tests. Hardware writes happen only in the signed helper.
struct BatteryPolicy {
    var mode: BatteryMode = .automatic
    var phase: BatteryPhase = .firstCharge
    var dischargeTarget = 80
    var isHolding = false
    var isHot = false
    var startedAt: Date?

    mutating func perform(_ action: BatteryAction, value: Int, configuration: inout BatteryConfiguration,
                          reading: BatteryTelemetry?, now: Date) -> Bool {
        guard (20...100).contains(value) else { return false }
        switch action {
        case .setLimit:
            configuration.limit = value
            configuration.sailing = min(configuration.sailing, value - 10)
            mode = .automatic
        case .resume, .cancel: mode = .automatic
        case .pause: mode = .paused
        case .topUp: mode = .topUp
        case .discharge:
            guard let reading, reading.adapterConnected, reading.percent > value else { return false }
            mode = .discharge; dischargeTarget = value
        case .calibrate:
            guard reading?.adapterConnected == true else { return false }
            mode = .calibration; phase = .firstCharge
        case .lowPowerOn, .lowPowerOff: break
        }
        startedAt = now
        isHolding = false
        return true
    }

    mutating func evaluate(_ c: BatteryConfiguration, reading r: BatteryTelemetry?,
                           sleeping: Bool = false, now: Date = Date()) -> BatteryDecision {
        guard c.enabled, c.valid else { return .init(state: .disabled, limit: 100) }
        guard let r, r.valid else { return .init(state: .unavailable, limit: 100) }
        // All temporary operations expire, including after wall-clock changes or long sleep.
        if let startedAt, now.timeIntervalSince(startedAt) > 48 * 3600 || now < startedAt {
            mode = .automatic; self.startedAt = nil
        }
        if !r.adapterConnected {
            if mode == .discharge || mode == .calibration { mode = .automatic; startedAt = nil }
            return .init(state: .onBattery, limit: c.limit)
        }
        if sleeping {
            return .init(state: .sleeping, limit: c.stopOnSleep ? max(20, min(c.limit, r.percent)) : c.limit)
        }
        if c.heatProtection {
            guard let temperature = r.temperature, temperature.isFinite, (-10...80).contains(temperature) else {
                return .init(state: .unavailable, limit: max(20, min(c.limit, r.percent)))
            }
            if temperature >= Double(c.maximumTemperature) { isHot = true }
            if temperature <= Double(c.maximumTemperature - 2) { isHot = false }
            if isHot { return .init(state: .heatProtection, limit: max(20, min(c.limit, r.percent))) }
        } else { isHot = false }
        let canDrain = !r.clamshell || c.dischargeInClamshell
        switch mode {
        case .paused: return .init(state: .holding, limit: max(20, min(c.limit, r.percent)))
        case .topUp:
            if !r.full { return .init(state: .topUp, limit: 100) }
            mode = .automatic; startedAt = nil; isHolding = true
        case .discharge:
            if r.percent > dischargeTarget && r.percent > 10 {
                return .init(state: canDrain ? .discharging : .holding, limit: dischargeTarget, disconnectAdapter: canDrain)
            }
            mode = .automatic; startedAt = nil
        case .calibration:
            switch phase {
            case .firstCharge:
                if !r.full { return .init(state: .calibration, limit: 100) }
                phase = .drain
            case .drain:
                if r.percent <= 10 { phase = .finalCharge }
            case .finalCharge:
                if !r.full { return .init(state: .calibration, limit: 100) }
                phase = .returnToLimit
            case .returnToLimit: break
            }
            if phase == .finalCharge { return .init(state: .calibration, limit: 100) }
            let target = phase == .drain ? 10 : c.limit
            if r.percent > target {
                return .init(state: canDrain ? .calibration : .holding, limit: max(20, target), disconnectAdapter: canDrain)
            }
            if phase == .returnToLimit { mode = .automatic; startedAt = nil; isHolding = true }
        case .automatic: break
        }
        if r.percent >= c.limit { isHolding = true }
        if r.percent <= c.limit - max(1, c.sailing) { isHolding = false }
        if c.automaticDischarge && r.percent > c.limit && canDrain {
            return .init(state: .discharging, limit: c.limit, disconnectAdapter: true)
        }
        if isHolding {
            return .init(state: r.percent < c.limit ? .sailing : .holding,
                         limit: max(20, min(r.percent, c.limit)))
        }
        return .init(state: .charging, limit: c.limit)
    }
}

struct BatteryRequest: Codable {
    var led: BatteryLED?
    var configuration: BatteryConfiguration?
    var action: BatteryAction?
    var value: Int = 80
}
struct BatteryResponse: Codable {
    var configuration: BatteryConfiguration
    var telemetry: BatteryTelemetry?
    var state: BatteryState
    var mode: BatteryMode
    var phase: BatteryPhase
    var supportsLimit: Bool
    var supportsDischarge: Bool
    var supportsLED: Bool
    var error: String?
    var errorDetail: String? = nil
}
