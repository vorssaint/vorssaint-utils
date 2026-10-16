#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Verify that selected real regressions fail their existing tests.

Each mutation runs in a temporary copy and must fail an assertion with the
expected diagnostic. Compiler errors, timeouts and unrelated failures do not
count as detection. The working checkout and its build cache stay untouched.
"""
from pathlib import Path
import os
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

MUTATIONS = [
    ("screenshot OCR reuses a request generation", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenTextService.swift",
     "        recognitionGeneration += 1\n        let generation",
     "        let generation",
     "only the latest OCR request copies, with newestFirst=false"),
    ("screenshot OCR ignores the line-break preference", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenTextService.swift",
     "UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRRemoveLineBreaks)", "true",
     "OCR respects QR=false, joinLines=false, preview=true"),
    ("screenshot OCR ignores the unified QR preference", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenTextService.swift",
     "UserDefaults.standard.bool(\n                    forKey: DefaultsKey.screenOCRDetectQRCodes)", "true",
     "OCR respects QR=false, joinLines=false, preview=false"),
    ("screenshot OCR button is always visible", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "if featureRuntime.isAvailable(.screenOCR) {", "if true {",
     "OCR button is absent when disabled"),
    ("screenshot OCR button is always hidden", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "if featureRuntime.isAvailable(.screenOCR) {", "if false {",
     "enabling OCR reveals exactly one localized button"),
    ("screenshot OCR button loses its action", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "Button(action: copyText)", "Button(action: {})",
     "pressing the rendered OCR button calls its action once"),
    ("screenshot OCR button stops observing availability", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "@ObservedObject private var featureRuntime = FeatureRuntime.shared",
     "private let featureRuntime = FeatureRuntime.shared",
     "enabling OCR reveals exactly one localized button"),
    ("island screenshot OCR button is always hidden", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "if embedded, featureRuntime.isAvailable(.screenOCR) {", "if false {",
     "embedded=true: enabling OCR reveals exactly one localized button"),
    ("floating screenshot OCR button widens the full action row", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "if embedded, featureRuntime.isAvailable(.screenOCR) {", "if featureRuntime.isAvailable(.screenOCR) {",
     "embedded=false: only the island toolbar makes room for the OCR button"),
    ("screenshot OCR hands Vision an oversized capture whole", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenTextService.swift",
     "ScreenTextService.outcome(for: ScreenTextService.recognitionImage(image),",
     "ScreenTextService.outcome(for: image,",
     "an oversized capture is scaled to the recognition bound before Vision reads it"),
    ("preview Copy text races the after-capture copy", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "        ScreenshotService.shared.afterAutoCopy {\n"
     "            ScreenTextService.shared.copyText(from: image)\n        }\n",
     "        ScreenTextService.shared.copyText(from: image)\n",
     "Copy text closes at once and waits for a pending after-capture copy"),
    ("Copy text stops waiting for the after-capture copy", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift",
     "            await pending.value\n", "",
     "Copy text waits while the after-capture copy is still being prepared"),
    ("compact rail eagerly builds history", "notch", "Sources/Vorssaint/UI/Notch/NotchComponents.swift",
     "                    LazyHStack(alignment: .top, spacing: spacing) {",
     "                    HStack(alignment: .top, spacing: spacing) {",
     "a thousand history entries create only the visible rail neighborhood"),
    ("preview recreates the scratchpad editor", "notch", "Sources/Vorssaint/UI/Notch/NotchScratchpadView.swift",
     "                        .opacity(pad.isPreviewing ? 0 : 1)",
     "                        .id(pad.isPreviewing)\n                        .opacity(pad.isPreviewing ? 0 : 1)",
     "preview preserves the same editor and undo history"),
    ("floating scratchpad takes another host's focus", "notch", "Sources/Vorssaint/Services/QuickTools/ScratchpadService.swift",
     "guard let panel, panel.isVisible, !requiresKeyWindow || panel.isKeyWindow else { return }",
     "guard let panel, panel.isVisible else { return }",
     "document actions preserve island focus with the floating host visible or hidden"),
    ("scratchpad toggle trusts only the hand-cleared key flag", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "let panel, panel.isKeyWindow || NSApp.keyWindow === panel {",
     "let panel, panel.isKeyWindow {",
     "the shortcut closes a reopened Scratchpad AppKit still keeps as its key window"),
    ("scratchpad toggle takes a missing panel for the key window", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "let panel, panel.isKeyWindow || NSApp.keyWindow === panel {",
     "panel?.isKeyWindow == true || NSApp.keyWindow === panel {",
     "an island without a panel is never taken for the key window"),
    ("closing the island keeps the keyboard AppKit still gives it", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "        else { return }\n        next.makeKey()\n",
     "        else { return }\n        _ = next\n",
     "closing the island hands the keyboard back to Settings while Vorssaint stays active"),
    ("closing the island takes the keyboard from the app in front", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "              NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,\n",
     "",
     "closing the island leaves the keyboard alone while another app takes over"),
    ("closing the island hands the keyboard to any window", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "$0 !== panel && $0.isVisible && $0.isOnActiveSpace && $0.canBecomeMain",
     "$0 !== panel",
     "closing the island hands the keyboard only to a visible regular window"),
    ("closing the island hands the keyboard to the backmost window", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "let next = NSApp.orderedWindows.first(where: {",
     "let next = NSApp.orderedWindows.last(where: {",
     "closing the island hands the keyboard to the frontmost regular window on this Space"),
    ("closing the island hands the keyboard to another Space", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "$0.isVisible && $0.isOnActiveSpace && $0.canBecomeMain",
     "$0.isVisible && $0.canBecomeMain",
     "closing the island hands the keyboard to the frontmost regular window on this Space"),
    ("emoji family offers unsupported tones", "emoji", "Sources/Vorssaint/Services/CommandBar/CommandBarEmoji.swift",
     "scalar.value != 0x1F46A && scalar.properties.isEmojiModifierBase", "scalar.properties.isEmojiModifierBase",
     "family stays unchanged instead of offering unsupported skin tones"),
    ("one-off emoji skips usage learning", "emoji", "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift",
     "                self.recordUsage(of: entry)\n", "",
     "a one-off tone records exactly one use under the original emoji"),
    ("one-off emoji learns the action field instead of its search", "emoji", "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift",
     "        case .argument, .actions:\n", "        case .argument:\n",
     "a one-off tone learns the search saved before opening actions"),
    ("output switches reuse another device's volume baseline", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "                self.volumeBaseline = nil\n                self.muteBaseline = nil\n", "",
     "switching output never replaces its connection notice with stored volume or mute"),
    ("volume observation reads partially published controls", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     ".receive(on: DispatchQueue.main)\n            .sink { [weak self, weak mixer] _ in",
     ".sink { [weak self, weak mixer] _ in",
     "switching output never replaces its connection notice with stored volume or mute"),
    ("device alerts return to the fixed level width", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "func fitted(_ content: CGFloat) -> CGFloat { min(maximum, max(Self.minimumWing, ceil(content) + 16 + cameraGap)) }",
     "func fitted(_ content: CGFloat) -> CGFloat { 112 }",
     "power labels and connection status fit beside their icon"),
    ("levels return to a fixed wing with empty black at the end", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "let wing = ceil(Self.levelInset + 18 + 8 + leading)",
     "let wing: CGFloat = 80",
     "a level's wings fit its mark and reading, with no empty black at the end"),
    ("a banner's short side takes its longer side's width", "notch", "Sources/Vorssaint/Services/Notch/NotchNotificationSupport.swift",
     "return NotchNoticeWings(leading: fitted(title), trailing: fitted(detail))",
     "return NotchNoticeWings(leading: fitted(max(title, detail)), trailing: fitted(max(title, detail)))",
     "a one-word message leaves no band of empty black beside it"),
    ("device alert window ignores its content width", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "guard noticeExpanded else { return geometry.noticeSize(wings: notice.wings(in: geometry)) }",
     "guard noticeExpanded else { return geometry.notice }",
     "a device notice widens the actual presentation toward its longer name"),
    ("a lopsided notice stays centred on the camera", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "        if let notice { return noticeExpanded ? 0 : geometry.noticeShift(notice.wings(in: geometry)) }",
     "        if let notice { return 0 }",
     "a device notice widens the actual presentation toward its longer name"),
    ("Nothing loses its music gate", "notch", "Sources/Vorssaint/Services/Notch/NotchSupport.swift",
     "            && (choice != .none || companionOccupiesRest)\n", "",
     "selecting Nothing retracts already visible music and stops its reader with cached playback still present"),
    ("resting music bypasses automatic opt-out", "notch", "Sources/Vorssaint/Services/Notch/NotchSupport.swift",
     "if showsMusicActivity(isPlaying: isPlaying, in: defaults),",
     "if isPlaying,",
     "disabled automatic music stops the reader even when resting content is Music"),
    ("resting music retains a disabled reader", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "            || (!hiddenUntilHover && (NotchSupport.watchesMusicActivity() || NotchSupport.routes(.track))))",
     "            || (!hiddenUntilHover && (NotchSupport.idleContent() == .music || NotchSupport.watchesMusicActivity()"
     " || NotchSupport.routes(.track))))",
     "disabled automatic music stops the reader even when resting content is Music"),
    ("closing music retains its on-demand reader", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "        removeEventMonitors()\n        syncVisibleConsumers()\n        closeCapture?()\n    }\n\n    func toggle()",
     "        removeEventMonitors()\n        closeCapture?()\n    }\n\n    func toggle()",
     "closing manually opened controls stops the reader and never leaves a music strip behind"),
    ("the software route keeps the picture dimmed when it is turned off", "software-dimming",
     "Sources/Vorssaint/Services/Display/BrightnessService.swift",
     "        guard !preferred else {\n"
     "            refresh(force: true)\n"
     "            return\n"
     "        }\n"
     "        // Handing the display back to DDC has to hand the picture back with\n"
     "        // it. The scaled curve belongs to this app, and the level behind it\n"
     "        // describes the gamma route, not the monitor: left in place they show\n"
     "        // a dark screen the monitor's own controls cannot explain, and the\n"
     "        // first write to the panel then dims what is already dimmed. The\n"
     "        // curve goes back before the rebuild, so the probe reads a display\n"
     "        // showing its own picture.\n"
     "        stateLock.lock()\n"
     "        lastApplied[id] = nil\n"
     "        levelKnownAt[id] = nil\n"
     "        stateLock.unlock()\n"
     "        workQueue.async { [weak self] in\n"
     "            guard let self else { return }\n"
     "            self.applySoftwareDim(id, value: 1)\n"
     "            DispatchQueue.main.async { [weak self] in self?.refresh(force: true) }\n"
     "        }\n",
     "        refresh(force: true)\n",
     "the picture goes back to its own curve when the choice goes off"),
    ("a timed session hands over on one condition", "keep-awake", "Sources/Vorssaint/Services/KeepAwakeManager.swift",
     "        guard KeepAwakeAutomationSupport.conditionsSatisfied(\n"
     "                matching: matches,\n"
     "                enabled: currentEnabledAutomationConditions(),\n"
     "                requireAll: automationRequiresAllConditions()) else { return false }\n",
     "        guard !matches.isEmpty else { return false }\n",
     "a timer running out on battery hands nothing over to an All automation"),
    ("lid sleep ignores a display connection in progress", "keep-awake", "Sources/Vorssaint/Services/KeepAwakeAutomationSupport.swift",
     'return appliesToLid && assertion["AssertLevel"] as? Int != 0', 'return false',
     "a live monitor transition overrides a stale allowed lid policy"),
    ("lid sleep forgets to retry a refusal", "keep-awake", "Sources/Vorssaint/Services/KeepAwakeManager.swift",
     "guard result != kIOReturnSuccess, attemptsLeft > 1 else { return }",
     "guard false else { return }",
     "a refused lid sleep retries until the system accepts it"),
    ("match mode labels grow back into sentences", "preferences", "Sources/Vorssaint/Core/KeepAwakeStrings.swift",
     "        matchAny: \"L\u2019une\",\n        matchAll: \"Toutes\",\n",
     "        matchAny: \"N\u2019importe quelle condition\",\n        matchAll: \"Toutes les conditions\",\n",
     "fr: the match mode labels fit the panel card"),
    ("recording metadata rebases after startup", "recording", "Sources/Vorssaint/Services/Recorder/RecorderSupport.swift",
     "return timeline.eventTime(time, since: origin)",
     "return timeline.eventTime(time, since: origin + 0.3)",
     "stored pointer, click and typing markers align with decoded video after delayed startup and pauses"),
    ("microphone returns to its changing native format", "recording", "Sources/Vorssaint/Services/Recorder/RecorderWriter.swift",
     "let interleaved = Self.interleavedAudioSample(sampleBuffer, converter: &microphoneConverter)",
     "let interleaved = Optional(sampleBuffer)",
     "writer dropped required microphone fixture sample"),
    ("system audio returns to its changing native format", "recording", "Sources/Vorssaint/Services/Recorder/RecorderWriter.swift",
     "let interleaved = Self.interleavedAudioSample(sampleBuffer, converter: &systemAudioConverter)",
     "let interleaved = Optional(sampleBuffer)",
     "writer dropped required systemAudio fixture sample"),
    ("GIF chunk lets the previous frame show through", "recorder",
     "Sources/Vorssaint/Services/Recorder/RecorderGIFWriter.swift",
     "                    || Self.hasTransparency(pending[0]) {",
     "                    || false {",
     "chunk boundaries never let an earlier frame show through"),
    ("window recording hears the whole Mac", "recorder",
     "Sources/Vorssaint/Services/Recorder/ScreenRecorderService.swift",
     "RecorderSystemAudioTap.make(hearing: Self.windowOwner(of: region))",
     "RecorderSystemAudioTap.make(hearing: nil)",
     "a window recording hears the app that owns the window, found by its window number"),
    ("app tap gives up before the app plays", "recorder",
     "Sources/Vorssaint/Services/Recorder/RecorderSystemAudioTap.swift",
     "continuation.resume(returning: aggregateID != 0 || awaitingApp)",
     "continuation.resume(returning: aggregateID != 0)",
     "an app's tap waits for the app's first audio process and never holds this app's own"),
    ("waiting tap is built on every process change", "recorder",
     "Sources/Vorssaint/Services/Recorder/RecorderSystemAudioTap.swift",
     "            awaitingApp = false\n",
     "",
     "a waiting tap is built once, by the first change that brings its app's processes"),
    ("rebuilt app tap keeps the ID it gave back", "recorder",
     "Sources/Vorssaint/Services/Recorder/RecorderSystemAudioTap.swift",
     "        // The HAL may hand this ID to another tap from here on.\n        tapID = 0\n",
     "        // The HAL may hand this ID to another tap from here on.\n",
     "a rebuilt app tap forgets the ID it gave back"),
    ("missing feed loses fallback requirement", "app-updates", "Sources/Vorssaint/Services/AppUpdates/AppUpdateFeedSupport.swift",
     "return Findings(catalogFallbackPaths: Set(apps.map(\\.path)))", "return Findings()",
     "manifest 404 missing: only usable catalog coverage clears a missing-feed warning"),
    ("current catalog app loses coverage", "app-updates", "Sources/Vorssaint/Services/AppUpdates/AppUpdatesSupport.swift",
     "if !isUncomparable(app.version) { checkedPaths.insert(app.path) }",
     "if isNewer(versionCore(entry.version), than: app.version) { checkedPaths.insert(app.path) }",
     "manifest 404 current: only usable catalog coverage clears a missing-feed warning"),
    ("ambiguous catalog claims coverage", "app-updates", "Sources/Vorssaint/Services/AppUpdates/AppUpdatesSupport.swift",
     "guard matches.count == 1, let entry = matches.first else { return nil }",
     "guard !matches.isEmpty, let entry = matches.first else { return nil }",
     "manifest 404 ambiguous: only usable catalog coverage clears a missing-feed warning"),
    ("switcher ignores resized viewport", "switcher", "Sources/Vorssaint/UI/Switcher/SwitcherView.swift",
     "                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in\n"
     "                            DispatchQueue.main.async {\n"
     "                                revealSelection(in: proxy, animated: false)\n"
     "                            }\n"
     "                        }",
     "",
     "previews search/narrowed without changing selection"),
    ("paused silence writes off the resumed play", "notch", "Sources/Vorssaint/Services/Notch/NotchAudioLevelService.swift",
     "        if stopWork == nil { silence.giveUp(on: identity) }",
     "        silence.giveUp(on: identity)",
     "silence heard during the pause grace does not write the next play off"),
    ("resumed play keeps a reader still reporting paused silence", "notch", "Sources/Vorssaint/Services/Notch/NotchAudioLevelService.swift",
     "        guard readerPID != pid || resumeBeforeSound else { return }",
     "        guard readerPID != pid else { return }",
     "a delayed silence report from the pause cannot write off the resumed play"),
    ("switcher loses replacement identity", "switcher", "Sources/Vorssaint/UI/Switcher/SwitcherView.swift",
     "                        .onChange(of: appWindows.map(\\.element.id)) { _, _ in",
     "                        .onChange(of: appWindows.count) { _, _ in",
     "previews boundary close/next app at unchanged index"),
    ("switcher follows window count", "switcher-model", "Sources/Vorssaint/Services/Switcher/SwitcherSupport.swift",
     ": min(2, max(windowCount, maximumWindowCount))",
     ": min(2, windowCount)",
     "App Switcher keeps short icon rows stationary when changing apps"),
    ("one entry per app hops to a fullscreen desktop", "switcher-model",
     "Sources/Vorssaint/Services/Switcher/WindowEnumerator.swift",
     "                return isOnHiddenSpace(windowID)\n            })",
     "                return false\n            })",
     "one entry per app keeps the window here over a later fullscreen window on another desktop"),
    ("icon row hops to a fullscreen desktop", "switcher-model",
     "Sources/Vorssaint/Services/Switcher/SwitcherSupport.swift",
     "$0.pid == item.pid && !$0.isOnHiddenSpace",
     "$0.pid == item.pid",
     "current-desktop icon row picks the app's window here over its fullscreen window on another desktop"),
    ("icon row steps ignore the current desktop", "switcher-model",
     "Sources/Vorssaint/Services/Switcher/AppSwitcher.swift",
     "                                                              wrapping: wrapping,\n"
     "                                                              currentSpaceOnly: currentSpaceOnly)",
     "                                                              wrapping: wrapping)",
     "the icon row's first selection, app steps, icon clicks and edge hover share the current-desktop entry"),
    ("invalid numeric result", "harness", "Tests/TestSuite.swift",
     "actual.isFinite && expected.isFinite && tol.isFinite && tol >= 0\n                   && abs(actual - expected) <= tol",
     "!(abs(actual - expected) > tol)", "every invalid numeric comparison fails"),
    ("invalid saved zoom", "screenshots", "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "guard requested.isFinite else { return 1 }", "guard requested.isFinite else { return requested }",
     "an invalid saved magnifier zoom falls back safely"),
    ("a posted Command-C closes the editor under a stroke", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "            && now - lastPointerActivity < editorPostedCopyGrace",
     "            && now - lastPointerActivity < 0",
     "a Command-C another app posts as a canvas drag ends does not copy and close the editor"),
    ("missing recording action", "launcher", "Sources/Vorssaint/Services/QuickTools/QuickLauncherService.swift",
     "                ScreenRecorderService.shared.toggle()", "                // ScreenRecorderService.shared.toggle()",
     "screenRecorder executes the intended action exactly once"),
    ("incorrect recording icon", "launcher", "Sources/Vorssaint/UI/QuickLauncher/QuickLauncherView.swift",
     'case .screenRecorder: return recorder.isRecording ? "stop.circle" : "record.circle"',
     'case .screenRecorder: return "record.circle"', "an active recording tile offers stopping"),
    ("missing translation", "localization", "Sources/Vorssaint/Core/FeatureStrings.swift",
     'shortcutHint: "Clique numa linha para colar no app anterior. ⌘+clique seleciona várias; ⌘C copia sem colar."',
     'shortcutHint: ""', "clipboard/pt-BR: missing text in shortcutHint"),
    ("unsafe argument comparison", "harness", "Tests/LocalizationTests.swift",
     "actual?.arguments == expected?.arguments",
     "actual?.arguments.values.sorted() == expected?.arguments.values.sorted()",
     "localization validation detects missing text and unsafe argument swaps"),
    ("unreachable window visibility preference", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotCapturePolicy.swift",
     "        honoursVisibilityPreference\n            ? workflowWindowIDs\n            : workflowWindowIDs.union(contentWindowIDs)",
     "        workflowWindowIDs.union(contentWindowIDs)",
     "a screenshot protects only the surfaces taking it"),
    ("island preference overrides a caller that keeps it out", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotCapturePolicy.swift",
     "        return excluded.subtracting(islandWindowIDs.subtracting(protectedWindowIDs))",
     "        return excluded.subtracting(islandWindowIDs)",
     "a caller that protects the island keeps it out even when it shows in captures"),
    ("capture controls photographed in the island", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotCapturePolicy.swift",
     "        guard showsCaptureTool, let mainWindowID else { return islandWindowIDs }",
     "        guard let mainWindowID else { return islandWindowIDs }",
     "the island at rest, or open on a page, is in the picture when it shows in captures"),
    ("tool switch keeps a stale picture of own windows", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "                && hideVorssaintWindows == other.hideVorssaintWindows\n                && keepsContentWindowsOut == other.keepsContentWindowsOut",
     "                && hideVorssaintWindows == other.hideVorssaintWindows",
     "switching between recording and screenshot, text or color refreshes the picture and pickable windows both ways"),
    ("capture accepts a refreshing source", "capture",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "        sourceRefreshPending = true", "        sourceRefreshPending = false",
     "pending refresh rejects region, window, full-screen, repeat and color confirmations"),
    ("capture reuses a failed display", "capture",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "guard !freeze || panels.allSatisfy({ frozenImages[$0.displayID] != nil }) else",
     "guard true else",
     "missing refreshed display closes selection safely"),
    ("old loupe overwrites the selected tool", "capture",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "guard let self, !self.finished, self.sourceGeneration == generation else",
     "guard let self, !self.finished else",
     "a previous tool's delayed live loupe cannot replace the current source"),
    ("full-screen action loses its first click", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "        acceptsFirstClick = true", "        acceptsFirstClick = false",
     "the interactive full-screen host receives its first click while Dynamic Island owns key focus"),
    ("full-screen hover highlights the window underneath", "capture",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "                && !pointerIsOverFullScreenControl(point)",
     "                && true",
     "hovering the full-screen action suppresses the window capture highlight"),
    ("island collapse moves a hovered full-screen action", "capture",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "        if fullScreenControlHovered {", "        if false {",
     "an island collapse cannot move the full-screen action while it is hovered"),
    ("hidden full-screen action keeps stale hover", "capture",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
     "        if hidden { resetFullScreenControlHover() }",
     "        if false { resetFullScreenControlHover() }",
     "hiding a hovered full-screen action clears hover and applies deferred island geometry"),
    ("lowered capsule overlaps the full-screen action", "notch",
     "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "            geometry.screen, geometry.floatingDrop + size.height)",
     "            geometry.screen, size.height)",
     "a lowered capsule publishes its drop plus height so it cannot cover the full-screen action"),
    ("full-screen action appears on every display", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "        isAvailable && pointerOnDisplay && !selectionInProgress && !capturePending",
     "        isAvailable && !selectionInProgress && !capturePending",
     "the full-screen action stays on the pointer display and disappears as soon as selection or capture starts"),
    ("overwrite unreadable notes", "storage", "Sources/Vorssaint/Services/QuickTools/ScratchpadStore.swift",
     "        guard canSave else { return false }", "        // guard canSave else { return false }",
     "damaged scratchpad blocks subsequent saves of empty and nonempty documents"),
    ("island forgets a preview stays until dismissed", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "        captureClosesOnCollapse = closeOnCollapse\n", "",
     "capture controls detach a persistent preview before closing it after island takeover"),
    ("companion hides from under the pointer", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "        if !now, mascotRestsInView, windowHost?.containsHover(NSEvent.mouseLocation) == true {\n",
     "        if false {\n",
     "it never hides while the pointer is on it, looking at it or petting it"),
    ("confirmation switch stops hiding previews", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "confirmationEnabled: defaults.bool(forKey: DefaultsKey.screenshotPreviewEnabled))",
     "confirmationEnabled: true)",
     "with confirmations off a successful action shows nothing"),
    ("upload shortcut publishes an edited capture's original", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift",
     "        withholdLatestCapture()\n        let editor = ScreenshotEditorController(capture: capture)",
     "        let editor = ScreenshotEditorController(capture: capture)",
     "a capture that went through an editor is not published"),
    ("island link click publishes at once", "screenshots",
     "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "            shareMenuChrome(Menu { shareDurations } label: { shareMenuLabel },\n",
     "            shareMenuChrome(Menu { shareDurations } label: { shareMenuLabel } primaryAction: { share(.saved()) },\n",
     "the island's link button opens the durations on a click"),
    ("clipboard highlight searches the whole preview", "clipboard",
     "Sources/Vorssaint/Services/Clipboard/ClipboardHistorySupport.swift",
     "        let visible = excerpt(string)\n",
     "        let visible = string\n",
     "a long preview is searched and styled only as far as a row can show"),
    ("clipboard highlight restyles the whole row", "clipboard",
     "Sources/Vorssaint/Services/Clipboard/ClipboardHistorySupport.swift",
     "        var attributed = AttributedString(visible)\n",
     "        var attributed = AttributedString(visible)\n        attributed.foregroundColor = .primary\n",
     "a highlighted row styles only its matches and leaves the rest to its text's modifiers"),
    ("agent log written again in place goes unnoticed", "agents",
     "Sources/Vorssaint/Services/AgentUsage/AgentUsageStore.swift",
     "        if identity != cursor.identity || size < cursor.offset\n"
     "            || (size > cursor.offset && !cursor.holdsWhatWasRead) {\n",
     "        if identity != cursor.identity || size < cursor.offset {\n",
     "a log written again in place while the app runs is read again at once"),
    ("agent progress keeps a log that started over", "agents",
     "Sources/Vorssaint/Services/AgentUsage/AgentUsageService.swift",
     "let kept = cursors.values.filter { !$0.restarted && $0.provider != .opencode }",
     "let kept = cursors.values.filter { $0.provider != .opencode }",
     "a log replaced or written again while the app ran is left out of saved progress"),
    ("Codex conversation starts its plugins", "agents",
     "Sources/Vorssaint/Services/AgentUsage/AgentCodexServer.swift",
     "process.arguments = [\"-c\", \"features.plugins=false\", \"app-server\"]",
     "process.arguments = [\"app-server\"]",
     "a conversation starts Codex's server with its plugins off"),
    ("an engine plays the slider without the loudness curve", "mixer",
     "Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift",
     "engine.gain = MixerRoutingSupport.gain(forVolume: latestApp.volume)",
     "engine.gain = Float(latestApp.volume)",
     "every engine plays an app's slider through the same loudness curve"),
    ("saved app volumes are not moved onto the new curve", "mixer",
     "Sources/Vorssaint/Core/Defaults.swift",
     "positions[id] = MixerRoutingSupport.volume(forGain: sanitizedAppVolume(gain))",
     "positions[id] = sanitizedAppVolume(gain)",
     "an app saved below 100% plays exactly as loud after the update, converted once"),
    ("a microphone's non-finite gain is published", "mixer",
     "Sources/Vorssaint/Services/Audio/AudioInputDeviceManager.swift",
     "return volume.isFinite ? min(max(volume, 0), 1) : nil",
     "return volume",
     "positive infinity main gain is hidden"),
]


def run(directory, arguments):
    process = subprocess.Popen(["./build.sh", *arguments], cwd=directory,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate()
        raise RuntimeError("Mutation run timed out; this is not a detected regression")
    return process.returncode, output


def main():
    with tempfile.TemporaryDirectory(prefix="vorss-mutation-") as temporary:
        directory = Path(temporary)
        # APFS clones keep the snapshot cheap and preserve timestamps so the
        # compiler can reuse unaffected objects after the baseline build.
        tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
        entries = sorted({path.split("/")[0] for path in tracked if path})
        for name in entries:
            subprocess.run(["/bin/cp", "-cRp", str(ROOT / name), str(directory / name)], check=True)
        for name in ["objects/tests", "generated-tests", "metrics-tests"]:
            source = ROOT / "build" / name
            if source.exists():
                target = directory / "build" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["/bin/cp", "-cRp", str(source), str(target)], check=True)

        print("Checking the unmodified baseline…", flush=True)
        status, output = run(directory, ["--test"])
        if status != 0 or "TESTS OK" not in output:
            raise RuntimeError("Baseline failed:\n" + output[-12000:])
        for name, group, relative, before, after, diagnostic in MUTATIONS:
            path = directory / relative
            original = path.read_text()
            if original.count(before) != 1:
                raise RuntimeError(f"Mutation fixture needs updating: {name}")
            print(f"Checking: {name}…", flush=True)
            try:
                path.write_text(original.replace(before, after))
                status, output = run(directory, ["--test-suite=" + group])
                if status != 1 or "TESTS FAILED" not in output or diagnostic not in output:
                    raise RuntimeError(f"Mutation was not caught by its intended assertion: {name}\n{output[-12000:]}")
                print(f"DETECTED: {name}", flush=True)
            finally:
                path.write_text(original)
        print(f"MUTATION CHECKS OK ({len(MUTATIONS)} regressions detected)", flush=True)


if __name__ == "__main__":
    main()
