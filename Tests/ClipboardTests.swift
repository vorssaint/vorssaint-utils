// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum ClipboardTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            expect(actual == expected, "\(label): got \"\(actual)\", expected \"\(expected)\"")
        }
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            let actual = formatSpecifiers(in: format)
            expect(actual == expected, "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Clipboard history search

        let clipboardCandidates = [
            ClipboardHistorySearchCandidate(index: 0, text: "Deploy checklist final", isPinned: false),
            ClipboardHistorySearchCandidate(index: 1, text: "Token cleanup note", isPinned: true),
            ClipboardHistorySearchCandidate(index: 2, text: "Final database deploy plan", isPinned: false),
            ClipboardHistorySearchCandidate(index: 3, text: "Reunião com João", isPinned: false),
        ]
        expect(ClipboardHistorySearch.matches("Reunião com João", query: "reuniao joao"),
               "clipboard search ignores case and accents")
        expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "deploy final") == [0, 2],
               "clipboard search matches multiple words in any order and ranks prefix matches first")
        expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "cleanup token") == [1],
               "clipboard search matches pinned entries with reordered query terms")
        expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "missing") == [],
               "clipboard search returns no results for unmatched terms")

        // MARK: Clipboard auto clear preferences

        expect(Defaults.sanitizedClipboardAutoClearDelay(20) == 20,
               "auto clear delay in range passes through")
        expect(Defaults.sanitizedClipboardAutoClearDelay(4) == 5,
               "auto clear delay below the floor clamps up, so a typed 4 does not jump to the default")
        expect(Defaults.sanitizedClipboardAutoClearDelay(0) == 5,
               "auto clear delay of zero clamps up instead of clearing instantly")
        expect(Defaults.sanitizedClipboardAutoClearDelay(99_999) == 3_600,
               "auto clear delay above the ceiling clamps down")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnDelay] as? Bool == false,
               "auto clear is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnSleep] as? Bool == false,
               "clear on computer sleep is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnDisplaySleep] as? Bool == false,
               "clear on display sleep is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnScreenLock] as? Bool == false,
               "clear on screen lock is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearDelay] as? Int == 20,
               "auto clear starts at twenty seconds")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardHistoryQuickPreview] as? Bool == false,
               "clipboard history quick preview is closed by default")

        // MARK: Clipboard auto clear timing

        let autoClearCopiedAt = Date(timeIntervalSince1970: 1_000_000)
        expect(ClipboardAutoClearSupport.decide(changeCount: 8,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(600),
                                                delay: 20) == .noteChange,
               "a new change count restarts the clock however long the old content sat there")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(19),
                                                delay: 20) == .wait,
               "unchanged content waits until the delay is up")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(20),
                                                delay: 20) == .clear,
               "unchanged content clears once the delay is exactly up")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(8 * 3_600),
                                                delay: 20) == .clear,
               "waking after hours of sleep clears at once instead of waiting out another delay")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 7,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(600),
                                                delay: 20) == .wait,
               "the count our own clear produced never clears again, so clearing cannot loop")
        expect(ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                           currentGeneration: 3,
                                                           featureIsAvailable: true,
                                                           triggerIsEnabled: true)
               && !ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                                currentGeneration: 4,
                                                                featureIsAvailable: true,
                                                                triggerIsEnabled: true)
               && !ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                                currentGeneration: 3,
                                                                featureIsAvailable: true,
                                                                triggerIsEnabled: false),
               "a queued clear is invalidated when its setting changes before pasteboard access")

        expect(FeatureStrings.clipboard(.ptBR).shortcutHint.contains("colar no app anterior"),
               "clipboard shortcut hint exposes row click paste in Portuguese")
        expect(FeatureStrings.clipboard(.ptBR).shortcutHint.contains("⌘+clique seleciona"),
               "clipboard shortcut hint exposes command click multi-select in Portuguese")
        expect(FeatureStrings.clipboard(.ptBR).clickRowShortcut == "Clique na linha",
               "clipboard visual shortcut exposes row click in Portuguese")
        expect(FeatureStrings.clipboard(.enUS).shortcutHint.contains("paste it into the previous app"),
               "clipboard shortcut hint exposes row click paste in English")
        expect(FeatureStrings.clipboard(.enUS).shortcutHint.contains("⌘-click selects"),
               "clipboard shortcut hint exposes command click multi-select in English")
        expect(FeatureStrings.clipboard(.enUS).commandClickShortcut == "⌘ Click",
               "clipboard visual shortcut exposes command click in English")
        expect(FeatureStrings.clipboard(.tr).shortcutHint.contains("yapıştırın"),
               "clipboard shortcut hint exposes row click paste in Turkish")
        expect(FeatureStrings.clipboard(.tr).shortcutHint.contains("birden çok öğe seçer"),
               "clipboard shortcut hint exposes command click multi-select in Turkish")
        expect(FeatureStrings.clipboard(.tr).clickRowShortcut == "Satıra tıkla",
               "clipboard visual shortcut exposes row click in Turkish")
        let featureTitles: [(AppLanguage, String, String, String, String)] = [
            (.enUS, "Clipboard", "Window layout", "Utilities", "Alerts"),
            (.ptBR, "Clipboard", "Layout de janelas", "Utilitários", "Alertas"),
            (.tr, "Pano", "Pencere yerleşimi", "Araçlar", "Uyarılar"),
            (.es, "Portapapeles", "Diseño de ventanas", "Utilidades", "Alertas"),
            (.de, "Zwischenablage", "Fensterlayout", "Dienstprogramme", "Warnungen"),
            (.fr, "Presse-papiers", "Disposition des fenêtres", "Utilitaires", "Alertes"),
            (.it, "Appunti", "Layout finestre", "Utilità", "Avvisi"),
            (.ja, "クリップボード", "ウインドウ配置", "ユーティリティ", "アラート"),
            (.ko, "클립보드", "윈도우 정렬", "유틸리티", "알림"),
            (.ru, "Буфер обмена", "Раскладка окон", "Утилиты", "Оповещения"),
            (.zhHans, "剪贴板", "窗口布局", "实用工具", "提醒"),
            (.zhTW, "剪貼簿", "視窗排列", "工具程式", "提醒"),
            (.zhHK, "剪貼簿", "視窗排列", "工具", "提示"),
        ]
        for (language, clipboardTitle, windowTitle, utilitiesTitle, alertsTitle) in featureTitles {
            expect(FeatureStrings.clipboard(language).title == clipboardTitle,
                   "\(language.rawValue) clipboard title is localized")
            expect(FeatureStrings.windowLayout(language).title == windowTitle,
                   "\(language.rawValue) window layout title is localized")
            expect(FeatureStrings.settingsCategories(language).utilities == utilitiesTitle,
                   "\(language.rawValue) settings category title is localized")
            expect(FeatureStrings.monitorAlerts(language).section == alertsTitle,
                   "\(language.rawValue) monitor alert section is localized")
        }
        for language in AppLanguage.allCases {
            let clipboardStrings = FeatureStrings.clipboard(language)
            expectFormat(clipboardStrings.pasteSelectedFormat, ["d"],
                         "\(language.rawValue) paste-selected button format")
            expectFormat(clipboardStrings.copySelectedFormat, ["d"],
                         "\(language.rawValue) copy-selected button format")
            expect(!clipboardStrings.autoClearEnable.isEmpty
                   && !clipboardStrings.autoClearSecondsSuffix.isEmpty
                   && !clipboardStrings.autoClearOnSleep.isEmpty
                   && !clipboardStrings.autoClearOnDisplaySleep.isEmpty
                   && !clipboardStrings.autoClearOnScreenLock.isEmpty
                   && !clipboardStrings.autoClearCaption.isEmpty,
                   "\(language.rawValue) clipboard auto clear labels are localized")
            let layoutStrings = FeatureStrings.windowLayout(language)
            expect(!layoutStrings.sixths.isEmpty
                   && !layoutStrings.topLeftSixth.isEmpty
                   && !layoutStrings.topCenterSixth.isEmpty
                   && !layoutStrings.topRightSixth.isEmpty
                   && !layoutStrings.bottomLeftSixth.isEmpty
                   && !layoutStrings.bottomCenterSixth.isEmpty
                   && !layoutStrings.bottomRightSixth.isEmpty,
                   "\(language.rawValue) window sixth layout labels are localized")
            expect(!layoutStrings.gestureSection.isEmpty
                   && !layoutStrings.gestureEnable.isEmpty
                   && !layoutStrings.gestureCaption.isEmpty
                   && !layoutStrings.gestureModifiers.isEmpty
                   && !layoutStrings.gestureMove.isEmpty
                   && !layoutStrings.gestureResize.isEmpty
                   && !layoutStrings.gestureResizeHint.isEmpty
                   && !layoutStrings.gestureRaiseWindow.isEmpty,
                   "\(language.rawValue) window gesture controls are localized")
            expect(!layoutStrings.edgeSnapEnable.isEmpty
                   && !layoutStrings.edgeSnapCaption.isEmpty
                   && !layoutStrings.edgeSnapSystemConflict.isEmpty
                   && !layoutStrings.edgeSnapOpenSystemSettings.isEmpty
                   && !layoutStrings.edgeSnapWaitingForSystem.isEmpty
                   && !layoutStrings.edgeSnapEnable.contains("—")
                   && !layoutStrings.edgeSnapCaption.contains("—")
                   && !layoutStrings.edgeSnapSystemConflict.contains("—")
                   && !layoutStrings.edgeSnapOpenSystemSettings.contains("—")
                   && !layoutStrings.edgeSnapWaitingForSystem.contains("—"),
                   "\(language.rawValue) window edge snap controls are localized")
            let alertStrings = FeatureStrings.monitorAlerts(language)
            expect(alertStrings.caption.contains("12"),
                   "\(language.rawValue) monitor alert caption explains the sustained alert window")
            expectFormat(alertStrings.cpuBodyFormat, ["d"], "\(language.rawValue) CPU alert format")
            expectFormat(alertStrings.cpuTemperatureBodyFormat, ["d"],
                         "\(language.rawValue) CPU temperature alert format")
            expectFormat(alertStrings.diskBodyFormat, ["@", "d"], "\(language.rawValue) disk alert format")
            expectFormat(alertStrings.batteryBodyFormat, ["d"], "\(language.rawValue) battery alert format")
            expectFormat(alertStrings.batteryTemperatureBodyFormat, ["d"],
                         "\(language.rawValue) battery temperature alert format")
        }
        expect(FeatureStrings.monitorAlerts(.enUS).cooldown == "Repeat the same alert after",
               "English monitor repeat control is explicit")
        expect(FeatureStrings.monitorAlerts(.ptBR).cooldown == "Repetir o mesmo alerta depois de",
               "Portuguese monitor repeat control is explicit")
        expect(ClipboardHistorySelection.initialIndex(totalCount: 3) == 0,
               "clipboard quick window starts keyboard navigation on the first item")
        expect(ClipboardHistorySelection.initialIndex(totalCount: 0) == 0,
               "clipboard quick window keeps an empty selection index safe")

        // MARK: Settings search navigation

        expect(SettingsSearchSupport.moveSelection(index: 0, delta: -1, count: 3) == 2,
               "Settings search Up wraps from first to last")
        expect(SettingsSearchSupport.moveSelection(index: 2, delta: 1, count: 3) == 0,
               "Settings search Down wraps from last to first")
        expect(SettingsSearchSupport.moveSelection(index: nil, delta: 1, count: 3) == 0,
               "Settings search Down starts a nil selection at the first result")
        expect(SettingsSearchSupport.moveSelection(index: nil, delta: -1, count: 3) == 2,
               "Settings search Up starts a nil selection at the last result")
        expect(SettingsSearchSupport.moveSelection(index: 0, delta: 1, count: 0) == nil,
               "Settings search navigation leaves an empty result set unselected")
        expect(SettingsSearchSupport.moveSelection(index: 0, delta: 10, count: 3) == 1,
               "Settings search navigation wraps large positive deltas")
        expect(SettingsSearchSupport.moveSelection(index: 0, delta: -10, count: 3) == 2,
               "Settings search navigation wraps large negative deltas")
        expect(SettingsSearchSupport.clampedSelection(index: 4, count: 2) == 1,
               "Settings search selection clamps after results shrink")
        expect(SettingsSearchSupport.reconciledSelection(index: 2,
                                                         previousIDs: ["a", "b", "c"],
                                                         resultIDs: ["a", "b"]) == 1,
               "Settings search reconciliation clamps after results shrink")
        expect(SettingsSearchSupport.reconciledSelection(index: nil,
                                                         previousIDs: [String](),
                                                         resultIDs: ["new"]) == 0,
               "Settings search selects the first newly available result")
        expect(SettingsSearchSupport.clampedSelection(index: 0, count: 0) == nil,
               "Settings search clamping clears an empty result set")
        expect(SettingsSearchSupport.reconciledSelection(index: 1,
                                                         previousIDs: ["a", "b", "c"],
                                                         resultIDs: ["b", "a"]) == 0,
               "Settings search selection follows the same result after reranking")

        expect(!ClipboardHistoryPreview.handlesSpace(selectionIsVisible: false, hasModifiers: false),
               "clipboard preview leaves spaces typed into search alone")
        expect(ClipboardHistoryPreview.handlesSpace(selectionIsVisible: true, hasModifiers: false),
               "clipboard preview uses Space after keyboard navigation")
        expect(!ClipboardHistoryPreview.handlesSpace(selectionIsVisible: true, hasModifiers: true),
               "clipboard preview never steals modified Space shortcuts")
        expect(ClipboardHistoryEscape.action(batchCount: 0) == .hideWindow,
               "Esc closes the panel when nothing is selected")
        expect(ClipboardHistoryEscape.action(batchCount: 2) == .clearBatchSelection,
               "Esc clears a batch selection before it closes the panel")
        expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: true,
                                                      isFieldEditor: true,
                                                      isEditable: true),
               "a composing search field keeps Return, the arrows and Esc")
        expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                       isFieldEditor: true,
                                                       isEditable: true),
               "the list keeps its shortcuts over a search field that is not composing")
        expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                      isFieldEditor: false,
                                                      isEditable: true),
               "the multiline editor owns its editing keys")
        expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                       isFieldEditor: false,
                                                       isEditable: false),
               "the read-only preview leaves the list's shortcuts intact")
        expect(ClipboardHistoryEditing.canSave(original: "First draft", draft: "Second draft"),
               "clipboard text can save a real edit")
        expect(!ClipboardHistoryEditing.canSave(original: "Same", draft: "Same"),
               "clipboard text does not save an unchanged draft")
        expect(ClipboardHistoryEditing.storableText("  keep spacing  ") == "  keep spacing  ",
               "clipboard editing preserves intentional outer spacing")
        expect(ClipboardHistoryEditing.storableText(" \n\t ") == nil,
               "clipboard editing rejects an empty text item")
        let largeClipboardText = String(repeating: "long copied text ", count: 10_000)
        expect(ClipboardHistoryEditing.storableText(largeClipboardText) == largeClipboardText,
               "clipboard history keeps copied documents larger than the old short-text bound")
        expect(ClipboardHistoryEditing.storableText(
            String(repeating: "a", count: ClipboardHistoryEditing.maxCharacters + 1)) == nil,
               "clipboard editing keeps the history text size bound")
        let budgetPinned = ClipboardHistoryEntry(text: "123456", pinnedAt: Date())
        let budgetRecentA = ClipboardHistoryEntry(text: "abcd")
        let budgetRecentB = ClipboardHistoryEntry(text: "efgh")
        let budgetedHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetPinned, budgetRecentA, budgetRecentB],
            recentLimit: 10,
            textByteLimit: 10)
        expect(budgetedHistory.map(\.id) == [budgetPinned.id, budgetRecentA.id],
               "clipboard history keeps pinned and newest entries inside one aggregate text budget")
        let protectedPinned = ClipboardHistoryEntry(text: "1234", pinnedAt: Date())
        var enlargedPinned = budgetPinned
        enlargedPinned.text = "12345678"
        let trimmedPinned = ClipboardHistoryEditing.retainedEntries(
            [enlargedPinned, protectedPinned],
            recentLimit: 10,
            textByteLimit: 10)
        expect(!ClipboardHistoryEditing.preservesPinnedEntries(
            from: [budgetPinned, protectedPinned],
            in: trimmedPinned),
               "an edit that would evict another pinned clipboard item is rejected")
        expect(ClipboardHistoryEditing.canLoadEncodedHistory(
            byteCount: ClipboardHistoryEditing.maxEncodedHistoryBytes)
                && !ClipboardHistoryEditing.canLoadEncodedHistory(
                    byteCount: ClipboardHistoryEditing.maxEncodedHistoryBytes + 1)
                && !ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: nil),
               "clipboard history size is checked before its store file is loaded")
        let escapingHistory = (0..<8).map { index in
            ClipboardHistoryEntry(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                text: String(repeating: "\\", count: 1_000),
                copiedAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let encodedHistoryLimit = 5_000
        if let encodedHistory = ClipboardHistoryEditing.encodedHistory(
            escapingHistory, byteLimit: encodedHistoryLimit) {
            expect(encodedHistory.data.count <= encodedHistoryLimit
                    && (try? JSONDecoder().decode([ClipboardHistoryEntry].self,
                                                 from: encodedHistory.data)) == encodedHistory.entries
                    && encodedHistory.entries.count < escapingHistory.count,
                   "clipboard persistence trims against actual escaped JSON before writing")
        } else {
            expect(false, "clipboard persistence encodes a bounded escaped history")
        }
        let largeClipboardPreview = ClipboardHistoryEntry(text: largeClipboardText).preview
        expect(largeClipboardPreview.hasSuffix("…")
                && largeClipboardPreview.count <= ClipboardHistoryEditing.previewCharacters + 1,
               "clipboard rows keep very large text previews bounded")
        expect(Defaults.allowedClipboardHistoryLimits == [20, 50, 100, 250, 500, 1_000, 10_000, 0],
               "clipboard history limits include 10k and unlimited options")
        expect(Defaults.sanitizedClipboardHistoryLimit(10_000) == 10_000
                && Defaults.sanitizedClipboardHistoryLimit(0) == 0
                && Defaults.sanitizedClipboardHistoryLimit(50) == 50
                && Defaults.sanitizedClipboardHistoryLimit(-99) == 50,
               "sanitized clipboard history limits accept 10k and 0 (unlimited)")
        let unlimitedHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetRecentA, budgetRecentB],
            recentLimit: 0,
            textByteLimit: 1_000)
        expect(unlimitedHistory.count == 2,
               "clipboard history retainedEntries preserves all entries when recentLimit is 0 (unlimited)")
        let tenThousandHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetRecentA, budgetRecentB],
            recentLimit: 10_000,
            textByteLimit: 1_000)
        expect(tenThousandHistory.count == 2,
               "clipboard history retainedEntries preserves entries with 10_000 limit")
        let previewID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let nextPreviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let updatedPreview = ClipboardHistoryEntry(id: previewID, text: "updated")
        let nextPreview = ClipboardHistoryEntry(id: nextPreviewID, text: "next")
        expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [updatedPreview, nextPreview],
                                                      selectedEntry: nextPreview)?.text == "updated",
               "clipboard preview resolves the current payload for its UUID")
        expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [nextPreview],
                                                      selectedEntry: nextPreview)?.id == nextPreviewID,
               "clipboard search falls back to the selected visible entry")
        expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [],
                                                      selectedEntry: nil) == nil,
               "clipboard preview clears after removing the final visible entry")
        expectEqual(ClipboardHistoryBatch.combinedText(["First", "Second", "Third"]),
                    "First\nSecond\nThird",
                    "clipboard batch joins selected entries as a single paste")
        expect(ClipboardHistoryBatch.orderedSelectedIndexes(allIDs: ["a", "b", "c", "d"],
                                                           selectedIDs: Set(["d", "b"])) == [1, 3],
               "clipboard batch preserves the visible history order")
        expect(ClipboardHistoryBatch.rangeSelectionIDs(allIDs: ["a", "b", "c", "d"],
                                                       anchor: 3, target: 1) == ["b", "c", "d"],
               "shift-click selects the whole range in either direction")
        expect(ClipboardHistoryBatch.rangeSelectionIDs(allIDs: ["a"], anchor: 9, target: -2) == ["a"],
               "shift-click range clamps out-of-bounds anchors")
        let batchTextA = ClipboardHistoryEntry(text: "alpha")
        let batchTextB = ClipboardHistoryEntry(text: "beta")
        let batchFiles = ClipboardHistoryEntry(text: "", kind: .files,
                                               filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        let batchImage = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "x.png")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchFiles, batchFiles])
                   == .files(["/tmp/a.txt", "/tmp/b.txt", "/tmp/a.txt", "/tmp/b.txt"]),
               "an all-files selection pastes as the files themselves")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchTextB])
                   == .text("alpha\nbeta"),
               "an all-text selection combines as lines")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchFiles])
                   == .text("alpha\n/tmp/a.txt\n/tmp/b.txt"),
               "a mixed selection combines as text with file paths inlined")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchImage])
                   == .rich([.text("alpha"), .image("x.png")]),
               "a selection with an image pastes as rich text with the image embedded")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchImage, batchFiles])
                   == .rich([.image("x.png"), .text("/tmp/a.txt\n/tmp/b.txt")]),
               "files in a rich selection contribute their paths as text")
        expect(ClipboardHistoryBatch.richPlainText([.text("alpha"), .image("x.png"), .text("beta")])
                   == "alpha\nbeta",
               "the plain-text fallback of a rich batch keeps only the text parts")

        let legacyClipboardJSON = Data("""
        [{"text":"hello","copiedAt":700000000}]
        """.utf8)
        if let legacy = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: legacyClipboardJSON) {
            expect(legacy.count == 1 && legacy[0].kind == .text && legacy[0].text == "hello",
                   "clipboard histories saved before images and files decode as text")
        } else {
            expect(false, "clipboard legacy history decodes")
        }
        var editedTextEntry = ClipboardHistoryEntry(text: "before", pinnedAt: Date(timeIntervalSince1970: 42))
        editedTextEntry.text = ClipboardHistoryEditing.storableText("after") ?? editedTextEntry.text
        if let encoded = try? JSONEncoder().encode([editedTextEntry]),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded) {
            expect(decoded.first?.id == editedTextEntry.id
                   && decoded.first?.text == "after"
                   && decoded.first?.pinnedAt == editedTextEntry.pinnedAt,
                   "clipboard text edits persist without losing item identity or pinning")
        } else {
            expect(false, "clipboard text edit round-trips")
        }
        let imageEntry = ClipboardHistoryEntry(text: "",
                                               kind: .image,
                                               imageFile: "a.png",
                                               imageHash: "h1",
                                               imageWidth: 1470,
                                               imageHeight: 956)
        if let encoded = try? JSONEncoder().encode([imageEntry]),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded) {
            expect(decoded.first?.kind == .image
                       && decoded.first?.imageFile == "a.png"
                       && decoded.first?.imageWidth == 1470,
                   "clipboard image entries round-trip through storage")
        } else {
            expect(false, "clipboard image entry round-trips")
        }
        expectEqual(imageEntry.preview, "1470×956",
                    "clipboard image preview shows the dimensions")
        expect(imageEntry.searchableText(imageLabel: "Imagem").contains("Imagem"),
               "clipboard image entries match the localized image word in search")
        expect(imageEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                   kind: .image,
                                                                   imageFile: "b.png",
                                                                   imageHash: "h1")),
               "clipboard image dedupe matches by content hash, not by file")
        expect(!imageEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                    kind: .image,
                                                                    imageFile: "c.png",
                                                                    imageHash: "h2")),
               "clipboard image dedupe rejects different content")
        expect(!ClipboardHistoryEntry(text: "", kind: .image).matchesContent(
                   of: ClipboardHistoryEntry(text: "", kind: .image)),
               "clipboard image dedupe never matches entries without a hash")
        let filesEntry = ClipboardHistoryEntry(text: "",
                                               kind: .files,
                                               filePaths: ["/Users/a/Documents/Report.pdf",
                                                           "/Users/a/Pictures/Photo.png"])
        expectEqual(filesEntry.preview, "Report.pdf, Photo.png",
                    "clipboard files preview lists the file names")
        expect(filesEntry.searchableText(imageLabel: "Image").contains("Report.pdf"),
               "clipboard files entries are searchable by file name")
        expect(filesEntry.searchableText(imageLabel: "Image").contains("Image"),
               "clipboard files with images include the localized image label in search")
        expect(ClipboardHistoryImageSupport.isImageFileName("screenshot.PNG"),
               "clipboard image file support recognizes png case-insensitively")
        expect(ClipboardHistoryImageSupport.isImageFileName("photo.jpeg")
               && ClipboardHistoryImageSupport.isImageFileName("picture.heic")
               && ClipboardHistoryImageSupport.isImageFileName("art.webp"),
               "clipboard image file support recognizes standard image extensions")
        expect(!ClipboardHistoryImageSupport.isImageFileName("document.pdf")
               && !ClipboardHistoryImageSupport.isImageFileName("archive.zip"),
               "clipboard image file support rejects non-image extensions")
        expect(filesEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                   kind: .files,
                                                                   filePaths: filesEntry.filePaths)),
               "clipboard files dedupe matches the same path set")
        expect(!filesEntry.matchesContent(of: ClipboardHistoryEntry(text: "Report.pdf, Photo.png",
                                                                    kind: .text)),
               "clipboard dedupe never crosses kinds")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "http://localhost:3000/page",
                                                                 plainText: "//localhost:3000/page") ?? "",
                    "http://localhost:3000/page",
                    "clipboard history preserves the scheme for scheme-relative browser URLs")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://example.com/docs",
                                                                 plainText: "example.com/docs") ?? "",
                    "https://example.com/docs",
                    "clipboard history restores the scheme for scheme-stripped browser URLs")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://example.com/docs",
                                                                 plainText: "Open docs") ?? "",
                    "Open docs",
                    "clipboard history keeps ordinary link text when it is not a URL")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "file:///tmp/example.txt",
                                                                 plainText: "/tmp/example.txt") ?? "",
                    "/tmp/example.txt",
                    "clipboard history ignores non-web URL pasteboard types")
        expect(!ClipboardHistorySensitiveText.looksSensitive("http://localhost:3000/page"),
               "clipboard history does not treat normal web URLs as secrets")
        expect(ClipboardHistorySensitiveText.looksSensitive("https://example.com/callback?token=abc"),
               "clipboard history still skips URLs with obvious secret words")
        expect(ClipboardHistorySensitiveText.looksSensitive("abc1234567890-xyz-abc"),
               "clipboard history still skips compact secret-looking text")
        // Issue #423: an identifier code is ordinary content to copy around,
        // and losing it is what stopped people from leaving the skip on.
        expect(!ClipboardHistorySensitiveText.looksSensitive("3f2504e0-4f89-11d3-9a0c-0305e82c3301"),
               "clipboard history keeps a plain identifier code")
        expect(!ClipboardHistorySensitiveText.looksSensitive("3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
               "clipboard history keeps an identifier code written in capitals")
        expect(!ClipboardHistorySensitiveText.looksSensitive("{3f2504e0-4f89-11d3-9a0c-0305e82c3301}"),
               "clipboard history keeps an identifier code wrapped in braces")
        expect(ClipboardHistorySensitiveText.looksSensitive("3f2504e0-4f89-11d3-9a0c-0305e82c33x1"),
               "a string that only resembles an identifier code is still treated as a secret")
        expect(ClipboardHistorySensitiveText.looksSensitive("3f2504e04f8911d39a0c0305e82c3301!x"),
               "dropping the dashes does not turn a secret into an identifier code")
        // The mark an app puts on the pasteboard when it hands over a secret.
        // It travels with every item, so one read of the pasteboard types
        // answers for a mark written on its own item too (measured).
        expect(ClipboardHistorySensitiveText.isConcealed(["public.utf8-plain-text",
                                                          ClipboardHistorySensitiveText
                                                              .concealedPasteboardType]),
               "clipboard history leaves out content an app marked as a secret")
        expect(!ClipboardHistorySensitiveText.isConcealed(["public.utf8-plain-text",
                                                            "NSStringPboardType"]),
               "ordinary copied text carries no secret mark")
        expectEqual(ClipboardHistorySensitiveText.concealedPasteboardType,
                    "org.nspasteboard.ConcealedType",
                    "the secret mark keeps the exact name the apps that write it use")

        let pasteboardAccess = GeneralPasteboardAccess(label: "Vorssaint.Tests.PasteboardAccess")
        let pasteboardGroup = DispatchGroup()
        let pasteboardStateLock = NSLock()
        var activePasteboardOperations = 0
        var maximumPasteboardOperations = 0
        for _ in 0..<16 {
            pasteboardGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pasteboardAccess.async {
                    pasteboardStateLock.lock()
                    activePasteboardOperations += 1
                    maximumPasteboardOperations = max(maximumPasteboardOperations,
                                                       activePasteboardOperations)
                    pasteboardStateLock.unlock()
                    usleep(1_000)
                    pasteboardStateLock.lock()
                    activePasteboardOperations -= 1
                    pasteboardStateLock.unlock()
                    pasteboardGroup.leave()
                }
            }
        }
        expect(pasteboardGroup.wait(timeout: .now() + 5) == .success,
               "pasteboard access operations finish without deadlock")
        expect(maximumPasteboardOperations == 1,
               "pasteboard access serializes concurrent service work")

        // The freeze this lane exists to prevent (issue #887): a read stuck
        // behind an app that promised pasteboard content and stopped answering
        // holds the lane, and any caller that waited for it would be frozen
        // with it. Wedge the lane, then ask for work from the main thread: the
        // ask must return at once and the answer must arrive later, on main.
        let wedgeReleased = DispatchSemaphore(value: 0)
        pasteboardAccess.async { wedgeReleased.wait() }
        // Released on its own, so a caller that waited for the lane comes out
        // measurably late instead of hanging the whole test run.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            wedgeReleased.signal()
        }
        var laneAnswer: Int?
        var laneAnsweredOnMain = false
        let askedAt = Date()
        pasteboardAccess.async({ 887 }, then: { value in
            laneAnswer = value
            laneAnsweredOnMain = Thread.isMainThread
        })
        let askDuration = Date().timeIntervalSince(askedAt)
        expect(askDuration < 0.1,
               "asking the wedged pasteboard lane for work returns without waiting "
                   + "(took \(askDuration)s)")
        expect(laneAnswer == nil, "the wedged lane has not answered yet")
        let laneDeadline = Date().addingTimeInterval(5)
        while laneAnswer == nil, Date() < laneDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        expect(laneAnswer == 887, "the queued work runs once the lane comes free")
        expect(laneAnsweredOnMain, "the pasteboard lane answers on the main queue")
        let pastePlainSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/PastePlainService.swift",
            encoding: .utf8)) ?? ""
        expect(pastePlainSource.contains("GeneralPasteboardAccess.shared.async"),
               "paste as plain text reads the clipboard on the lane, not on the main thread")
    }
}
