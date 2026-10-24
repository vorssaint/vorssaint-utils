// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where iCloud sync of the clipboard history stands.
enum ClipboardHistorySyncStatus: Equatable {
    case off
    case checking
    case noAccount
    case unavailable
    case storageFull
    case synced(at: Date, otherMacs: Int)
}

/// What the history window shows about sync: a symbol, one short line that
/// follows the status, and a tooltip saying when it syncs.
struct ClipboardSyncStatusDisplay: Equatable {
    enum Tone: Equatable {
        case normal
        case busy
        case warning
    }

    let symbol: String
    let text: String
    let help: String
    let tone: Tone

    /// Nothing is shown while sync is off.
    static func isShown(_ status: ClipboardHistorySyncStatus) -> Bool {
        status != .off
    }

    /// `now` is the moment shown: the window passes the time of each redraw,
    /// so "2 min ago" keeps counting while it stays open. A sync less than a
    /// minute old, or one a changed clock puts ahead, reads as just now.
    init(status: ClipboardHistorySyncStatus, syncing: Bool, now: Date, language: AppLanguage) {
        let strings = FeatureStrings.clipboardSync(language)
        let help = strings.statusHelp
        if syncing {
            self.init(symbol: "arrow.clockwise.icloud", text: strings.statusSyncing, help: help, tone: .busy)
            return
        }
        switch status {
        case .off, .checking:
            self.init(symbol: "icloud", text: strings.statusChecking, help: help, tone: .busy)
        case .noAccount:
            self.init(symbol: "icloud.slash", text: strings.statusNoAccount,
                      help: strings.noAccount + "\n" + help, tone: .warning)
        case .unavailable:
            self.init(symbol: "exclamationmark.icloud", text: strings.statusUnavailable,
                      help: strings.unavailable + "\n" + help, tone: .warning)
        case .storageFull:
            self.init(symbol: "exclamationmark.icloud", text: strings.statusStorageFull,
                      help: strings.storageFull + "\n" + help, tone: .warning)
        case let .synced(at, otherMacs):
            let elapsed = now.timeIntervalSince(at)
            let when: String
            if elapsed < 60 {
                when = strings.statusJustNow
            } else {
                let formatter = RelativeDateTimeFormatter()
                formatter.locale = language.formattingLocale()
                formatter.unitsStyle = .short
                formatter.dateTimeStyle = .numeric
                when = String(format: strings.statusSyncedFormat, formatter.localizedString(for: at, relativeTo: now))
            }
            self.init(symbol: "checkmark.icloud",
                      text: when + " · " + String(format: strings.otherMacsFormat, otherMacs),
                      help: help, tone: .normal)
        }
    }

    private init(symbol: String, text: String, help: String, tone: Tone) {
        self.symbol = symbol
        self.text = text
        self.help = help
        self.tone = tone
    }
}
