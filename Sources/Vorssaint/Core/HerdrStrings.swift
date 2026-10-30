// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the herdr status feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file. Non-English tables carry the English
/// interim text until native review (// TODO(translate)).
struct HerdrFeatureStrings {
    let title: String
    let empty: String
    let loading: String
    let noServer: String
    let startHint: String
    let notInstalled: String
    let installHint: String
    let updateRequired: String
    let stale: String
    let refresh: String
    let statusIdle: String
    let statusWorking: String
    let statusBlocked: String
    let statusDone: String
    let statusUnknown: String
    let needsAttention: String
    let hubDescription: String
    let lastUpdatedFormat: String

    func statusLabel(_ status: HerdrAgent.Status) -> String {
        switch status {
        case .idle: return statusIdle
        case .working: return statusWorking
        case .blocked: return statusBlocked
        case .done: return statusDone
        case .unknown: return statusUnknown
        }
    }
}

extension FeatureStrings {
    static func herdr(_ language: AppLanguage) -> HerdrFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension HerdrFeatureStrings {
    // TODO(translate): interim English text until native review.
    static let enUS = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let ptBR = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let tr = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let ru = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let es = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let sk = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let de = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let fr = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let it = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let ja = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let ko = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let uk = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let zhHans = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let zhTW = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )

    // TODO(translate): interim English text until native review.
    static let zhHK = HerdrFeatureStrings(
        title: "Herdr Agents", empty: "No supervised agents right now",
        loading: "Reading herdr status…", noServer: "Herdr server is not running",
        startHint: "Run herdr once to start its server, then refresh.",
        notInstalled: "Herdr is not installed",
        installHint: "Install herdr with Homebrew, then open this panel again.",
        updateRequired: "This herdr version is too old. Update herdr and refresh.",
        stale: "Showing the last update",
        refresh: "Refresh", statusIdle: "Idle", statusWorking: "Working",
        statusBlocked: "Blocked", statusDone: "Done", statusUnknown: "Unknown",
        needsAttention: "Needs attention",
        hubDescription: "Watch agents supervised by herdr: live status in the menu panel and the island.",
        lastUpdatedFormat: "Updated %@"
    )
}
