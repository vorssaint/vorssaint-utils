// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The production catalog rebuild, grouping and VoiceOver label, with only
/// the microphone row and a controllable publisher behind the open bar.
enum CommandBarMicMuteTests {
    enum AppFeature {
        case micMute
        var isAvailable: Bool { true }
    }

    final class MicMuteService {
        struct Warning { let message: String }
        static let shared = MicMuteService()
        @Published var isMuted = false
        @Published var warning: Warning?
        var controlSymbol: String { warning != nil ? "exclamationmark.triangle" : "mic" }
        func toggle() {}
    }

    enum CommandBarCatalog {
        typealias AppFeature = CommandBarMicMuteTests.AppFeature
        typealias MicMuteService = CommandBarMicMuteTests.MicMuteService
        static func area(_ feature: AppFeature) -> String { "Microphone tools" }
        static func roleShortcut(_ role: AppFeature) -> GlobalShortcut? { nil }
        static func emojiEntries(bar: CommandBarFeatureStrings) -> [CommandBarEntry] { [] }
    }

    final class Bar {
        typealias CommandBarCatalog = CommandBarMicMuteTests.CommandBarCatalog
        typealias AppFeature = CommandBarMicMuteTests.AppFeature
        typealias MicMuteService = CommandBarMicMuteTests.MicMuteService
        struct L10n {
            static let shared = Self()
            let language = AppLanguage.enUS
        }
        struct Permissions {
            static let shared = Self()
            let accessibility = true
        }
        struct EmojiInputs: Equatable {
            let language: AppLanguage
            let skinTone: String
            let accessibility: Bool
        }
        let finderAutomationDenied = false
        var catalog: [CommandBarEntry] = []
        var builtEmojiInputs: EmojiInputs?
        var builtLanguage: AppLanguage?
        var emojiEntries: [CommandBarEntry] = []
        var micMuteChanges: AnyCancellable?
        var presentationLifecycle = CommandBarPresentationLifecycle()
        let presentationID = UUID()
        var pendingAnswerRefresh: UUID?
        var isVisible = true
        let text = FeatureStrings.commandBar(.enUS)
        var service: Bar { self }
        var refreshes = 0
        func refreshResults() { refreshes += 1 }
        func indexEntries() {}
        func rowShortcut(for entry: CommandBarEntry) -> GlobalShortcut? { nil }
        func isPinned(_ entry: CommandBarEntry) -> Bool { false }
    }

    static func run(_ suite: TestSuite) {
        let mic = MicMuteService.shared
        mic.isMuted = false
        mic.warning = nil
        let bar = Bar()
        bar.presentationLifecycle.beginHome(bar.presentationID)
        bar.presentationLifecycle.completeHomeHydration(bar.presentationID, isVisible: true)
        bar.rebuildCatalog()
        func waitForRefresh(after previous: Int) {
            let deadline = Date().addingTimeInterval(1)
            while bar.refreshes == previous && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        mic.isMuted = true
        waitForRefresh(after: 0)
        suite.expect(bar.catalog.first?.title == Strings.enUS.micUnmuteName,
                     "an open command bar reflects a microphone toggle elsewhere")
        let active = bar.refreshes
        mic.warning = .init(message: Strings.enUS.micMutePartialHUD)
        waitForRefresh(after: active)
        suite.expect(bar.refreshes > active && bar.catalog.first.map(bar.accessibilityLabel)?.contains(Strings.enUS.micMutePartialHUD) == true,
                     "losing coverage without toggling refreshes the visible microphone row")
        bar.rebuildCatalog()
        guard let row = bar.catalog.first else { return suite.expect(false, "missing microphone action") }
        suite.expect(bar.browseGroup(for: row, bar: bar.text) == "Microphone tools" && !row.needsPrompt,
                     "a partial mute stays runnable under the microphone group")
        let browseLabel = bar.accessibilityLabel(row.withSubtitle(""))
        suite.expect(browseLabel.contains(Strings.enUS.micMutePartialHUD) && browseLabel.contains(bar.text.stateOn),
                     "the browsed action announces both the active feature and the unconfirmed microphone")
        let partial = bar.refreshes
        mic.warning = nil
        waitForRefresh(after: partial)
        suite.expect(bar.refreshes > partial && bar.catalog.first.map(bar.accessibilityLabel)?.contains(Strings.enUS.micMutePartialHUD) == false,
                     "the open bar clears a stale warning when all inputs are confirmed")
        let confirmed = bar.refreshes
        mic.isMuted = false
        mic.warning = .init(message: Strings.enUS.micManualRestore)
        waitForRefresh(after: confirmed)
        suite.expect(bar.catalog.first?.isActive == false
                     && bar.catalog.first.map(bar.accessibilityLabel)?.contains(Strings.enUS.micManualRestore) == true,
                     "the open bar announces manual recovery while the Mic Mute action is off")
        bar.isVisible = false
        let count = bar.refreshes
        mic.warning = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.07))
        suite.expect(bar.refreshes == count, "a closed bar does not refresh its rows for a microphone change")
    }
}
