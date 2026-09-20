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
     "return min(240, max(112, ceil(max(leading + 18 + 8, trailing)) + 32))", "return 112",
     "power and accessory labels fit beside their icon without truncation"),
    ("device alert window ignores its content width", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "guard noticeExpanded else { return geometry.noticeSize(wingWidth: notice.preferredWingWidth) }",
     "guard noticeExpanded else { return geometry.notice }",
     "a device notice widens the actual presentation beyond the compact level indicator"),
    ("Nothing loses its music gate", "notch", "Sources/Vorssaint/Services/Notch/NotchSupport.swift",
     "            && idleContent(in: defaults) != .none\n", "",
     "selecting Nothing retracts already visible music and stops its reader with cached playback still present"),
    ("resting music bypasses automatic opt-out", "notch", "Sources/Vorssaint/Services/Notch/NotchSupport.swift",
     "return choice == .music && !showsMusicActivity(isPlaying: isPlaying, in: defaults) ? .none : choice",
     "return choice == .music && !isPlaying ? .none : choice",
     "disabled automatic music stops the reader even when resting content is Music"),
    ("resting music retains a disabled reader", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "            || (!hiddenUntilHover && NotchSupport.watchesMusicActivity()))",
     "            || (!hiddenUntilHover && (NotchSupport.idleContent() == .music || NotchSupport.watchesMusicActivity())))",
     "disabled automatic music stops the reader even when resting content is Music"),
    ("closing music retains its on-demand reader", "notch", "Sources/Vorssaint/Services/Notch/NotchService.swift",
     "        removeEventMonitors()\n        syncVisibleConsumers()\n    }\n\n    func toggle()",
     "        removeEventMonitors()\n    }\n\n    func toggle()",
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
    ("switcher reveal before resize", "switcher", "Sources/Vorssaint/UI/Switcher/SwitcherView.swift",
     "                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in\n"
     "                            DispatchQueue.main.async {\n"
     "                                revealSelection(in: proxy, animated: false)\n"
     "                            }\n"
     "                        }",
     "                        .onChange(of: switcher.iconRowLayout.previewContentWidth) { _, _ in\n"
     "                            revealSelection(in: proxy, animated: false)\n"
     "                        }",
     "previews search/narrowed without changing selection"),
    ("switcher loses replacement identity", "switcher", "Sources/Vorssaint/UI/Switcher/SwitcherView.swift",
     "                        .onChange(of: appWindows.map(\\.element.id)) { _, _ in",
     "                        .onChange(of: appWindows.count) { _, _ in",
     "previews boundary close/next app at unchanged index"),
    ("switcher follows window count", "switcher-model", "Sources/Vorssaint/Services/Switcher/SwitcherSupport.swift",
     ": min(2, max(windowCount, maximumWindowCount))",
     ": min(2, windowCount)",
     "App Switcher keeps short icon rows stationary when changing apps"),
    ("invalid numeric result", "harness", "Tests/TestSuite.swift",
     "actual.isFinite && expected.isFinite && tol.isFinite && tol >= 0\n                   && abs(actual - expected) <= tol",
     "!(abs(actual - expected) > tol)", "every invalid numeric comparison fails"),
    ("invalid saved zoom", "screenshots", "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
     "guard requested.isFinite else { return 1 }", "guard requested.isFinite else { return requested }",
     "an invalid saved magnifier zoom falls back safely"),
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
    ("overwrite unreadable notes", "storage", "Sources/Vorssaint/Services/QuickTools/ScratchpadStore.swift",
     "        guard canSave else { return false }", "        // guard canSave else { return false }",
     "damaged scratchpad blocks subsequent saves of empty and nonempty documents"),
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
