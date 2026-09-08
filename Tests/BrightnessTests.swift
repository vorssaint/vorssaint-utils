// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

enum BrightnessTests {
    static func runExtraBrightness(expect: (Bool, String) -> Void) {
        let panel500 = ExtraBrightnessSupport.panelReference(model: "MacBookPro18,1")
        let panel600 = ExtraBrightnessSupport.panelReference(model: "Mac16,7")
        expect(panel500.referenceEDR == 3.2 && panel500.bonus == 0.58,
               "the 2021/2023 500 nit panels take the stronger curve")
        expect(panel600.referenceEDR == 2.66 && panel600.bonus == 0.48,
               "600 nit panels from M3 onwards take the gentler curve")
        expect(ExtraBrightnessSupport.panelReference(model: "Mac99,9").bonus == 0.48
               && ExtraBrightnessSupport.panelReference(model: nil).bonus == 0.48,
               "unknown and future models fall back to the conservative curve")
        expect(ExtraBrightnessSupport.boostFactor(level: 0, maxEDR: 2.66, reference: panel600) == 1.0,
               "zero level applies no brightness boost")
        expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 2.66, reference: panel600) - 1.48) < 0.0001,
               "full level on a 600 nit panel tops out at the sustainable 1.48x")
        expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 16.0, reference: panel600) - 1.48) < 0.0001,
               "huge reported headroom never pushes past what the panel sustains")
        expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 3.2, reference: panel500) - 1.58) < 0.0001,
               "full level on a 500 nit panel tops out at 1.58x")
        expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 1.33, reference: panel600) - 1.24) < 0.0001,
               "a partial headroom grant scales the boost down proportionally")
        expect(abs(ExtraBrightnessSupport.boostFactor(level: 0.5, maxEDR: 2.66, reference: panel600) - 1.24) < 0.0001,
               "half level applies half the panel bonus")
        expect(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 1.0, potentialEDR: 16.0,
                                                   reference: panel600)
               == ExtraBrightnessSupport.engagementFactor,
               "before the panel engages, the overlay shows only the small engagement boost")
        expect(abs(ExtraBrightnessSupport.renderFactor(level: 0.1, currentEDR: 1.0, potentialEDR: 16.0,
                                                       reference: panel600) - 1.048) < 0.0001,
               "the engagement nudge never exceeds the level's own target")
        expect(abs(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 2.66, potentialEDR: 16.0,
                                                       reference: panel600) - 1.48) < 0.0001,
               "with the reference headroom engaged the full level renders the full bonus")
        expect(ExtraBrightnessSupport.renderFactor(level: 0, currentEDR: 2.66, potentialEDR: 16.0,
                                                   reference: panel600) == 1.0,
               "zero level renders no boost even with headroom engaged")
        expect(abs(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 1.2, potentialEDR: 16.0,
                                                       reference: panel600) - 1.2) < 0.0001,
               "the rendered factor never exceeds the headroom macOS is granting right now")
        expect(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 1.0, potentialEDR: 1.0,
                                                   reference: panel600) == 1.0,
               "a mode without any potential headroom gets no boost attempt at all")
        for model in ["MacBookPro18,1", "MacBookPro18,4", "Mac14,5", "Mac14,10",
                      "Mac15,3", "Mac15,11", "Mac16,1", "Mac16,7", "Mac17,2", "Mac17,9"] {
            expect(ExtraBrightnessSupport.isSupportedPanel(model: model,
                                                           localizedName: "Built-in Retina Display",
                                                           potentialEDR: 2.0),
                   "\(model) is a MacBook Pro with an XDR panel, whatever the screen reports")
        }
        for model in ["Mac16,12", "Mac16,13", "Mac15,12", "Mac14,2", "Mac14,7",
                      "Mac17,3", "MacBookPro17,1", "Mac16,2"] {
            expect(!ExtraBrightnessSupport.isSupportedPanel(model: model,
                                                            localizedName: "Built-in Retina Display",
                                                            potentialEDR: 2.0),
                   "\(model) has no XDR panel and its fake 2x headroom does not qualify")
        }
        expect(ExtraBrightnessSupport.isSupportedPanel(model: "Mac99,1",
                                                       localizedName: "Built-in Display",
                                                       potentialEDR: 16.0),
               "future XDR MacBooks qualify by real headroom without a model list update")
        expect(!ExtraBrightnessSupport.isSupportedPanel(model: nil,
                                                        localizedName: "Built-in Retina Display",
                                                        potentialEDR: 1.0),
               "unknown model without headroom or an XDR name stays unsupported")
        expect(ExtraBrightnessSupport.isSupportedPanel(model: nil,
                                                       localizedName: "Liquid Retina XDR Display",
                                                       potentialEDR: 1.0),
               "an explicit XDR product name is accepted even without other signals")
        expect(ExtraBrightnessSupport.isXDRPanelName("Built-in Liquid Retina XDR Display")
               && ExtraBrightnessSupport.isXDRPanelName("Liquid Retina XDR"),
               "the XDR token is recognized wherever a product name exposes it")
        expect(!ExtraBrightnessSupport.isXDRPanelName("Built-in Liquid Retina Display")
               && !ExtraBrightnessSupport.isXDRPanelName("Built-in Retina Display"),
               "generic built-in panel names do not qualify by name")
        expect(abs(ExtraBrightnessSupport.rampedFactor(previous: 1.0, target: 1.48) - 1.03) < 0.0001,
               "the factor climbs one small step per tick")
        expect(ExtraBrightnessSupport.rampedFactor(previous: 1.46, target: 1.48) == 1.48,
               "the last upward step lands exactly on the target")
        expect(abs(ExtraBrightnessSupport.rampedFactor(previous: 1.48, target: 1.10) - 1.385) < 0.0001,
               "downward moves take a share of the gap, never the whole drop at once")
        expect(ExtraBrightnessSupport.rampedFactor(previous: 1.105, target: 1.10) == 1.10,
               "tiny downward gaps snap to the target instead of hovering")
        expect(ExtraBrightnessSupport.rampedFactor(previous: 1.48, target: 1.48) == 1.48,
               "a settled factor stays put")
        expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.48,
                                                   engaged: false, disengagedTicks: 1) == 1.48
               && ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.48,
                                                      engaged: false,
                                                      disengagedTicks: ExtraBrightnessSupport.dropoutGraceTicks) == 1.48,
               "a grant that just vanished keeps the previous factor through the grace window")
        expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.48,
                                                   engaged: false,
                                                   disengagedTicks: ExtraBrightnessSupport.dropoutGraceTicks + 1) == 1.10,
               "a dropout that outlives the grace window is believed")
        expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.40, previous: 1.48,
                                                   engaged: true, disengagedTicks: 0) == 1.40,
               "an engaged reading is always taken at face value")
        expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.0,
                                                   engaged: false, disengagedTicks: 1) == 1.10,
               "grace never lifts a factor that had no boost to protect")
        expect(ExtraBrightnessSupport.canReuseSpaceWindows(
                   sameDisplay: true, overlayOnActiveSpace: true, triggerOnActiveSpace: true),
               "fullscreen handoff keeps the live overlay pair when both windows followed")
        expect(!ExtraBrightnessSupport.canReuseSpaceWindows(
                   sameDisplay: false, overlayOnActiveSpace: true, triggerOnActiveSpace: true)
               && !ExtraBrightnessSupport.canReuseSpaceWindows(
                   sameDisplay: true, overlayOnActiveSpace: false, triggerOnActiveSpace: true)
               && !ExtraBrightnessSupport.canReuseSpaceWindows(
                   sameDisplay: true, overlayOnActiveSpace: true, triggerOnActiveSpace: false),
               "display changes and incomplete Space handoffs still rebuild the overlay pair")
        var ebFactor = 1.48
        var ebLow = 0
        for ebEngaged in [true, false, false, false, true, true] {
            ebLow = ebEngaged ? 0 : ebLow + 1
            let ebTarget = ExtraBrightnessSupport.gracedTarget(instantaneous: ebEngaged ? 1.48 : 1.10,
                                                               previous: ebFactor,
                                                               engaged: ebEngaged, disengagedTicks: ebLow)
            ebFactor = ExtraBrightnessSupport.rampedFactor(previous: ebFactor, target: ebTarget)
            expect(ebFactor == 1.48,
                   "a fullscreen transition blackout leaves the boost visually untouched")
        }
        var ebDrop = 1.48
        var ebDropLow = 0
        var ebBiggestStep = 0.0
        for _ in 0..<12 {
            ebDropLow += 1
            let ebTarget = ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: ebDrop,
                                                               engaged: false, disengagedTicks: ebDropLow)
            let ebNext = ExtraBrightnessSupport.rampedFactor(previous: ebDrop, target: ebTarget)
            ebBiggestStep = max(ebBiggestStep, ebDrop - ebNext)
            ebDrop = ebNext
        }
        expect(ebDrop >= 1.10 && ebDrop < 1.13 && ebBiggestStep < 0.0951,
               "a real revocation ramps the boost down over seconds without one visible slam")
        var ebWobble = 1.48
        var ebWobbleStep = 0.0
        for tick in 0..<20 {
            let ebNext = ExtraBrightnessSupport.rampedFactor(previous: ebWobble,
                                                             target: tick % 4 < 2 ? 1.48 : 1.40)
            ebWobbleStep = max(ebWobbleStep, abs(ebNext - ebWobble))
            ebWobble = ebNext
            expect(ebWobble >= 1.40 && ebWobble <= 1.48,
                   "a wobbling grant keeps the factor inside the grant's own range")
        }
        expect(ebWobbleStep < 0.0301,
               "a wobbling grant moves the factor in imperceptible steps, not flashes")
        var ebGlide = 1.0
        for _ in 0..<16 { ebGlide = ExtraBrightnessSupport.rampedFactor(previous: ebGlide, target: 1.48) }
        expect(ebGlide == 1.48,
               "switching the boost on glides to full strength within about four seconds")
    }

    static func run(expect: (Bool, String) -> Void) {
        // MARK: Display brightness (DDC/CI helpers)

        // Every section of the service below its "Rebuild (work queue)" MARK
        // runs on the private work queue, so a display's user-facing name is
        // read from NSScreen on the main thread and handed to the rebuild.
        // AppKit reached from below the line would be a main thread violation
        // on every hotplug, wake and panel open.
        let brightnessSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Display/BrightnessService.swift",
            encoding: .utf8)) ?? ""
        let brightnessWorkQueueHalf = brightnessSource
            .components(separatedBy: "// MARK: - Rebuild (work queue)").last ?? ""
        // Comments are stripped first: a note naming the symbol it bans is not
        // a call, and a check that cannot tell them apart goes red for prose.
        let brightnessWorkQueueCode = brightnessWorkQueueHalf
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!brightnessWorkQueueHalf.isEmpty && !brightnessWorkQueueCode.contains("NSScreen"),
               "the brightness work queue resolves display names without touching NSScreen")
        // Display numbers are reissued after a reconnection, so the gamma
        // restore before a switch-off must check the monitor like the others.
        expect(brightnessSource.contains("baseline.fingerprint == Self.displayFingerprint(display.id)"),
               "the pre-switch-off gamma restore checks the display fingerprint")

        let ddcWrite = BrightnessSupport.writePacket(code: 0x10, value: 0x1234)
        let expectedDDCWrite: [UInt8] = [0x84, 0x03, 0x10, 0x12, 0x34, 0x8E]
        expect(ddcWrite == expectedDDCWrite,
               "DDC write packet carries the set opcode, big-endian value and checksum")
        let ddcRead = BrightnessSupport.readRequestPacket(code: 0x10)
        let expectedDDCRead: [UInt8] = [0x82, 0x01, 0x10, 0xFD]
        expect(ddcRead == expectedDDCRead,
               "DDC read request omits the sub-address from its checksum seed")
        expect(Array(BrightnessSupport.writePacket(code: 0x10, value: 100)[3...4]) == [0x00, 0x64],
               "DDC values split into high and low bytes")

        var ddcReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32]
        ddcReply.append(ddcReply.reduce(UInt8(0x50)) { $0 ^ $1 })
        expect(BrightnessSupport.parseReply(ddcReply)?.current == 0x32
                && BrightnessSupport.parseReply(ddcReply)?.maximum == 0x64,
               "a valid DDC reply yields the current and maximum values")
        var corrupted = ddcReply
        corrupted[7] ^= 0xFF
        expect(BrightnessSupport.parseReply(corrupted) == nil,
               "a corrupted DDC reply fails its checksum and reads as no reply")
        expect(BrightnessSupport.parseReply([0x6E, 0x88]) == nil,
               "a short DDC reply reads as no reply")

        expect(BrightnessSupport.sanitizedMaximum(0) == 100 && BrightnessSupport.sanitizedMaximum(255) == 255,
               "a display reporting no range falls back to the conventional scale")
        expect(BrightnessSupport.normalized(current: 50, maximum: 100) == 0.5,
               "DDC values normalize to the slider scale")
        expect(BrightnessSupport.normalized(current: 120, maximum: 0) == 1.0,
               "normalization clamps against the fallback range")
        expect(BrightnessSupport.deviceValue(for: 0.5, maximum: 100) == 50
                && BrightnessSupport.deviceValue(for: 1.0, maximum: 255) == 255
                && BrightnessSupport.deviceValue(for: -0.2, maximum: 100) == 0
                && BrightnessSupport.deviceValue(for: 1.7, maximum: 100) == 100,
               "slider values map onto the display's own scale with clamping")
        expect(BrightnessSupport.steppedKeyboardLightLevel(current: 0.5, direction: -1)
                == 0.5 - BrightnessSupport.keyboardLightStep
                && BrightnessSupport.steppedKeyboardLightLevel(current: 0.5, direction: 1)
                == 0.5 + BrightnessSupport.keyboardLightStep,
               "keyboard brightness shortcuts move by one system-sized step")
        expect(BrightnessSupport.steppedKeyboardLightLevel(current: 0, direction: -1) == 0
                && BrightnessSupport.steppedKeyboardLightLevel(current: 1, direction: 1) == 1,
               "keyboard brightness shortcut steps clamp to the supported range")
        expect(BrightnessSupport.steppedKeyboardLightLevel(current: .nan, direction: 1) == 0,
               "an invalid keyboard brightness reading never reaches the private setter")

        // EDID UUID chunks at fixed positions: vendor, product (little endian),
        // manufacture date, image size.
        var serviceIdentity = BrightnessSupport.ServiceIdentity()
        serviceIdentity.edidUUID = "10AC5FA0-0000-0000-1E19-0000003C2200"
        serviceIdentity.ordinal = 1
        var displayIdentity = BrightnessSupport.DisplayIdentity()
        displayIdentity.vendorID = 0x10AC
        displayIdentity.productID = 0xA05F
        displayIdentity.weekOfManufacture = 30
        displayIdentity.yearOfManufacture = 2015
        displayIdentity.horizontalImageSize = 600
        displayIdentity.verticalImageSize = 340
        expect(BrightnessSupport.matchScore(service: serviceIdentity, display: displayIdentity) == 4,
               "every EDID identity chunk scores one point")
        serviceIdentity.ioDisplayLocation = "IOService:/some/path"
        displayIdentity.ioDisplayLocation = "IOService:/some/path"
        expect(BrightnessSupport.matchScore(service: serviceIdentity, display: displayIdentity) == 14,
               "a registry path match is decisive on top of the EDID chunks")
        expect(BrightnessSupport.matchScore(service: BrightnessSupport.ServiceIdentity(),
                                            display: BrightnessSupport.DisplayIdentity()) == 0,
               "empty identities never match")

        let assignment = BrightnessSupport.assignServices(scores: [
            (displayIndex: 0, serviceOrdinal: 1, score: 2),
            (displayIndex: 0, serviceOrdinal: 2, score: 11),
            (displayIndex: 1, serviceOrdinal: 1, score: 3),
            (displayIndex: 1, serviceOrdinal: 2, score: 4),
        ])
        expect(assignment == [0: 2, 1: 1],
               "greedy assignment gives each display its best free service")
        expect(BrightnessSupport.assignServices(scores: [(displayIndex: 0, serviceOrdinal: 1, score: 0)])
                .isEmpty,
               "zero-score pairs never pair up")

        expect(BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: true) == .live,
               "a parsed reply means a live DDC channel")
        expect(BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: false) == .writeOnly,
               "accepted writes without replies keep a blind slider")
        expect(BrightnessSupport.channelOutcome(writeAccepted: false, replyParsed: false) == .dead,
               "rejected writes mean no DDC reaches the display (HDMI conversion)")
        expect(BrightnessSupport.ddcProbeAttempts()
                == BrightnessSupport.retryAttempts + 1
                && BrightnessSupport.ddcProbeWriteCycles(classifyingChannel: true) == 1,
               "channel discovery keeps its reply chances but sends one spaced write each")
        expect(BrightnessSupport.ddcProbeAttempts()
                == BrightnessSupport.retryAttempts + 1
                && BrightnessSupport.ddcProbeWriteCycles(classifyingChannel: false)
                == BrightnessSupport.writeCycles,
               "answering channels retain their field-proven read and write retries")
        let ddcPath = BrightnessSupport.ddcPathKey(
            displayFingerprint: "1507:9218:245",
            ioDisplayLocation: "IOService:/port/1")
        expect(ddcPath == "1507:9218:245|IOService:/port/1",
               "a DDC capability cache key binds the physical display to its connection path")
        expect(BrightnessSupport.ddcPathKey(displayFingerprint: "1507:9218:245",
                                            ioDisplayLocation: "") == nil,
               "a display without a stable connection path is never cached")
        let rememberedPaths = BrightnessSupport.updatedWriteOnlyDDCPaths(
            ["old", "same", "other", "same"], path: "same", isWriteOnly: true, limit: 3)
        expect(rememberedPaths == ["old", "other", "same"],
               "remembering a write-only path deduplicates it and makes it newest")
        expect(BrightnessSupport.updatedWriteOnlyDDCPaths(
            rememberedPaths, path: "other", isWriteOnly: false, limit: 3) == ["old", "same"],
               "a changed DDC result invalidates the remembered path")
        expect(BrightnessSupport.updatedWriteOnlyDDCPaths(
            ["one", "two", "three"], path: "four", isWriteOnly: true, limit: 3)
            == ["two", "three", "four"],
               "the write-only path cache remains bounded")
        expect(!BrightnessSupport.shouldProbeDDC(
            pathKey: ddcPath, writeOnlyPaths: [ddcPath!])
                && BrightnessSupport.shouldProbeDDC(
                    pathKey: "another", writeOnlyPaths: [ddcPath!])
                && BrightnessSupport.shouldProbeDDC(
                    pathKey: nil, writeOnlyPaths: [ddcPath!]),
               "only the same physical display path skips future DDC probes")
        expect(!SettingsBackupSupport.exportKeys().contains(
            DefaultsKey.brightnessDDCWriteOnlyPaths),
               "per-monitor DDC capability never travels in a settings backup")
        let oneDisplay = BrightnessSupport.DisplayTopology(online: [1], active: [1])
        let twoDisplays = BrightnessSupport.DisplayTopology(online: [1, 2], active: [1, 2])
        expect(!BrightnessSupport.shouldQueueRebuild(topology: oneDisplay, pending: oneDisplay),
               "opening Displays does not queue the same monitor scan twice")
        expect(BrightnessSupport.shouldQueueRebuild(topology: twoDisplays, pending: oneDisplay),
               "a connected monitor always queues a fresh display scan")
        expect(BrightnessSupport.shouldQueueRebuild(topology: oneDisplay, pending: oneDisplay,
                                                    force: true),
               "wake recovery can rebuild unchanged display ids")
        expect(BrightnessSupport.brightnessAfterRebuild(probed: 0.3, pending: 0.8) == 0.8,
               "a brightness change made during discovery survives the final probe")
        expect(BrightnessSupport.brightnessAfterRebuild(probed: 0.3, pending: nil) == 0.3,
               "a rebuild keeps the monitor reading when no change is waiting")
        expect(BrightnessSupport.canDisableDisplay(drawableDisplayIDs: [1, 3], target: 3),
               "one display can be disabled while another remains active")
        expect(!BrightnessSupport.canDisableDisplay(drawableDisplayIDs: [1], target: 1),
               "the final active display can never be disabled")
        expect(!BrightnessSupport.canDisableDisplay(drawableDisplayIDs: [1, 3], target: 8),
               "an inactive display cannot enter the disable path")
        expect(BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: [1, 2], activeDisplayIDs: [1, 2, 9], virtualDisplayIDs: [2]) == [1],
               "only online active displays with a visible picture prevent recovery")
        expect(BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: [2], activeDisplayIDs: [2], virtualDisplayIDs: [2]).isEmpty,
               "a virtual-only active display leaves the machine effectively headless")
        let onePhysicalOneVirtual = BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: [1, 2], activeDisplayIDs: [1, 2], virtualDisplayIDs: [2])
        expect(!BrightnessSupport.canDisableDisplay(drawableDisplayIDs: onePhysicalOneVirtual,
                                                    target: 1),
               "a virtual display never makes it safe to disable the last physical display")
        expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [3], managedDisabledIDs: [1], builtInDisabledIDs: [1]).isEmpty,
               "an active external display preserves an intentionally disabled built-in panel")
        expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [], managedDisabledIDs: [1, 4], builtInDisabledIDs: [1]) == [1, 4],
               "losing the last active display tries the built-in panel before other managed displays")
        expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [], managedDisabledIDs: [7, 4], builtInDisabledIDs: []) == [4, 7],
               "a headless desktop Mac can recover one display switched off by this app")
        expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [], managedDisabledIDs: [], builtInDisabledIDs: [1]).isEmpty,
               "a display disabled elsewhere is never changed during headless recovery")
        // CoreGraphics runs a reconfiguration's callbacks inline on the driving
        // thread, and in this process those callbacks are AppKit's, so the
        // transaction belongs to the main thread. Getting it wrong hangs the
        // app rather than returning a wrong answer, and no pure helper can
        // carry that, so it is pinned against the CoreGraphics symbols.
        expect(brightnessSource.components(separatedBy: "CGBeginDisplayConfiguration(").count == 2
               && brightnessSource.components(separatedBy: "CGCompleteDisplayConfiguration(").count == 2,
               "every display power change goes through the one reconfiguration transaction")
        let beforeDisplayConfiguration = brightnessSource
            .components(separatedBy: "CGBeginDisplayConfiguration(").first ?? ""
        expect((beforeDisplayConfiguration.components(separatedBy: "func ").last ?? "")
                .contains("Thread.isMainThread"),
               "the display reconfiguration transaction refuses to start off the main thread")

        // A `UserDefaults` write posts `didChangeNotification`, and the
        // observers registered with `queue: .main` make that post wait for the
        // main thread. Held under `stateLock` it waits on a main thread that
        // can itself be waiting for the same lock inside `canToggleDisplay`,
        // called from a SwiftUI body, and the app hangs with nothing left that
        // can end it (issue #647). Which thread the write happens to run on
        // does not change that, so it is the locked region that is pinned.
        let lockedRegions = brightnessSource.components(separatedBy: "stateLock.lock()")
            .dropFirst()
            .map { $0.components(separatedBy: "stateLock.unlock()").first ?? $0 }
        expect(!lockedRegions.isEmpty
               && lockedRegions.allSatisfy { !$0.contains("SwitchedOff(") },
               "the list of displays switched off is never written while stateLock is held")

        // The same transaction relays its screen change to AppKit inline, and
        // switching off the display the panel is on makes AppKit lay that panel
        // out again right there: the power button's body is evaluated while
        // this app holds the display server busy, so anything it asks the
        // display server is a question the same thread is still answering, and
        // the app freezes with nothing left that can end it (issue #969). The
        // body decides from the published snapshot instead, and the live
        // reading stays where it guards the switch itself. Comments are
        // stripped first: a note naming what it bans is not a call.
        let canToggleCode = ((brightnessSource
            .components(separatedBy: "func canToggleDisplay(").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!canToggleCode.isEmpty
               && canToggleCode.contains("drawableDisplays")
               && !canToggleCode.contains("Self.drawableDisplayIDs(")
               && !canToggleCode.contains("stateLock"),
               "the panel reads whether a display can be switched off without asking the display server")

        expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_000_000,
                                                 lastCommandEndMicroseconds: nil) == 0,
               "the first DDC command to a display waits nothing")
        expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_010_000,
                                                 lastCommandEndMicroseconds: 1_000_000) == 40_000,
               "a command chasing another waits out the standard's interval")
        expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_050_000,
                                                 lastCommandEndMicroseconds: 1_000_000) == 0
                && BrightnessSupport.ddcCommandDelay(nowMicroseconds: 2_000_000,
                                                     lastCommandEndMicroseconds: 1_000_000) == 0,
               "an elapsed interval clears the wait entirely")
        expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_000_000,
                                                 lastCommandEndMicroseconds: 2_000_000) == 0,
               "a clock that moved backwards never blocks the bus")

        expect(BrightnessSupport.reconnectedDimLevel(0.0) == BrightnessSupport.reconnectionDimFloor
                && BrightnessSupport.reconnectedDimLevel(0.1) == BrightnessSupport.reconnectionDimFloor,
               "a near-black dim returns from a connection gap at the visible floor")
        expect(BrightnessSupport.reconnectedDimLevel(0.7) == 0.7
                && BrightnessSupport.reconnectedDimLevel(1.0) == 1.0
                && BrightnessSupport.reconnectedDimLevel(1.4) == 1.0,
               "visible dim levels return from a gap untouched, clamped to the range")

        expect(BrightnessSupport.softwareDimToRestore(remembered: 0.7, appliedByApp: false) == 1.0
                && BrightnessSupport.softwareDimToRestore(remembered: nil, appliedByApp: true) == 1.0,
               "a level read from the monitor is never replayed as a gamma dim")
        expect(BrightnessSupport.softwareDimToRestore(remembered: 0.4, appliedByApp: true) == 0.4,
               "a dim this app applied is restored when the routes are rebuilt")

        expect(BrightnessSupport.softwareDimFactor(for: 1.0) == 1.0
                && BrightnessSupport.softwareDimFactor(for: 0.0) == 0.0,
               "software dimming spans the whole range and zero really is black")
        expect(BrightnessSupport.softwareDimFactor(for: 0.5) == 0.5
                && BrightnessSupport.softwareDimFactor(for: -0.3) == 0.0
                && BrightnessSupport.softwareDimFactor(for: 1.4) == 1.0,
               "software dimming is linear with clamping")
        expect(BrightnessSupport.scaledGammaTable([0.0, 0.5, 1.0], factor: 0.5) == [0.0, 0.25, 0.5],
               "gamma tables scale toward black by the dim factor")
        let untouched: [Float] = [0.0, 0.3, 1.0]
        expect(BrightnessSupport.scaledGammaTable(untouched, factor: 1.0) == untouched,
               "factor one returns the exact original table for bit-exact restores")

        // Brightness keys arrive as system-defined auxiliary control events;
        // data1 packs key code, press state and the repeat bit.
        func brightnessData1(keyCode: Int, state: Int, repeated: Bool = false) -> Int {
            (keyCode << 16) | (state << 8) | (repeated ? 1 : 0)
        }
        expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 2, state: 10))
                == BrightnessSupport.BrightnessKeyEvent(delta: BrightnessSupport.brightnessKeyStep,
                                                        isKeyDown: true, isRepeat: false),
               "brightness up decodes with a positive step")
        expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 3, state: 10, repeated: true))
                == BrightnessSupport.BrightnessKeyEvent(delta: -BrightnessSupport.brightnessKeyStep,
                                                        isKeyDown: true, isRepeat: true),
               "brightness down decodes with a negative step and the repeat bit")
        expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 3, state: 11))?
                .isKeyDown == false,
               "the key release decodes too, so a handled press swallows both halves")
        expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 16, state: 10)) == nil,
               "other media keys never decode as brightness")
        expect(BrightnessSupport.brightnessKeyEvent(subtype: 1, data1: 0) == nil,
               "other system-defined subtypes never decode as brightness")
        expect(BrightnessSupport.keyboardLightOnLevel(lastNonzero: nil) == 0.5
                && BrightnessSupport.keyboardLightOnLevel(lastNonzero: 0) == 0.5
                && BrightnessSupport.keyboardLightOnLevel(lastNonzero: 0.7) == 0.7
                && BrightnessSupport.keyboardLightOnLevel(lastNonzero: 2) == 1,
               "keyboard light restores its last level or starts halfway")
        expect(BrightnessSupport.steppedBrightness(0.97, delta: BrightnessSupport.brightnessKeyStep) == 1.0
                && BrightnessSupport.steppedBrightness(0.03, delta: -BrightnessSupport.brightnessKeyStep) == 0.0,
               "key steps clamp at both ends of the range")

        // Keyboards other than the built-in one send brightness as a plain
        // key press, which is why the pointer never got a say on them
        // (issue #287). Codes measured against the display server.
        func functionKey(_ code: Int,
                         down: Bool = true,
                         modifiers: Bool = false,
                         functionKeys: Bool = true) -> BrightnessSupport.BrightnessKeyEvent? {
            BrightnessSupport.brightnessFunctionKeyEvent(keyCode: code,
                                                         isKeyDown: down,
                                                         isRepeat: false,
                                                         hasModifiers: modifiers,
                                                         functionKeysAdjustBrightness: functionKeys)
        }
        expect(functionKey(144)?.delta == BrightnessSupport.brightnessKeyStep,
               "the dedicated brightness up code steps up by one sixteenth")
        expect(functionKey(145)?.delta == -BrightnessSupport.brightnessKeyStep,
               "the dedicated brightness down code steps down by one sixteenth")
        expect(functionKey(113)?.delta == BrightnessSupport.brightnessKeyStep,
               "F15 steps up while the system still offers it as a brightness key")
        expect(functionKey(107)?.delta == -BrightnessSupport.brightnessKeyStep,
               "F14 steps down while the system still offers it as a brightness key")
        expect(functionKey(113, functionKeys: false) == nil
                && functionKey(107, functionKeys: false) == nil,
               "the function keys are left alone once the system stops using them")
        expect(functionKey(144, functionKeys: false)?.delta == BrightnessSupport.brightnessKeyStep,
               "the dedicated codes mean brightness whatever the function keys do")
        expect(functionKey(144, modifiers: true) == nil,
               "a modified press belongs to the system, not to us")
        expect(functionKey(0) == nil && functionKey(53) == nil,
               "ordinary typing never decodes as brightness")
        expect(functionKey(145, down: false)?.isKeyDown == false,
               "the release decodes too, so a consumed press consumes both halves")
        expect(BrightnessSupport.isBrightnessKeyCode(144)
                && BrightnessSupport.isBrightnessKeyCode(145)
                && BrightnessSupport.isBrightnessKeyCode(107)
                && BrightnessSupport.isBrightnessKeyCode(113),
               "the four brightness codes are recognized on the fast path")
        expect(!BrightnessSupport.isBrightnessKeyCode(0)
                && !BrightnessSupport.isBrightnessKeyCode(36),
               "letters and Return leave the fast path immediately")
        expect(BrightnessSupport.functionKeysAdjustBrightness(symbolicHotKeys: nil),
               "the system ships the function keys as brightness keys")
        expect(BrightnessSupport.functionKeysAdjustBrightness(symbolicHotKeys: [:]),
               "an untouched shortcut list means the defaults are in force")
        expect(!BrightnessSupport.functionKeysAdjustBrightness(
            symbolicHotKeys: ["53": ["enabled": false]]),
               "turning the system shortcut off gives the function key back")
        expect(!BrightnessSupport.functionKeysAdjustBrightness(
            symbolicHotKeys: ["54": ["enabled": NSNumber(value: false)]]),
               "the shortcut flag is read whichever way it was stored")
        expect(BrightnessSupport.functionKeysAdjustBrightness(
            symbolicHotKeys: ["53": ["enabled": true], "54": ["enabled": true]]),
               "shortcuts left switched on keep the function keys as brightness")

        // Pointer routing on system-routed displays (issue #268): the system
        // only ever steps its native target, so any other display the
        // pointer picks must be stepped by the app.
        expect(BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: true,
                                                          displayIsBuiltIn: false,
                                                          overlayReplacesNative: false),
               "pointer on an Apple pipeline external display steps here even without the overlay")
        expect(!BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: true,
                                                           displayIsBuiltIn: true,
                                                           overlayReplacesNative: false),
               "pointer on the built-in panel keeps the system's native handling")
        expect(BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: true,
                                                          displayIsBuiltIn: true,
                                                          overlayReplacesNative: true),
               "the opt-in overlay replaces native handling on the built-in panel")
        expect(!BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: false,
                                                           displayIsBuiltIn: false,
                                                           overlayReplacesNative: false),
               "with pointer routing off and no overlay, the press stays with the system")
        expect(BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: false,
                                                          displayIsBuiltIn: false,
                                                          overlayReplacesNative: true),
               "with the overlay on, the system target is stepped here so only one OSD draws")
        expect(BrightnessSupport.filledBrightnessSegments(0) == 0
                && BrightnessSupport.filledBrightnessSegments(0.01) == 1
                && BrightnessSupport.filledBrightnessSegments(0.5) == 8
                && BrightnessSupport.filledBrightnessSegments(1.2) == 16,
               "brightness overlay segments clamp and preserve non-zero levels")
        expect(BrightnessSupport.wholePercent(-0.2) == 0
                && BrightnessSupport.wholePercent(0.634) == 63
                && BrightnessSupport.wholePercent(0.999) == 100
                && BrightnessSupport.wholePercent(1.2) == 100
                && BrightnessSupport.wholePercent(.infinity) == 0,
               "brightness overlay percentage rounds and clamps safely")
    }

    static func runKeyTiming(expect: (Bool, String) -> Void) {
        // MARK: Brightness key base (issue #370)

        let pressed = Date(timeIntervalSince1970: 1_800_000_000)
        expect(BrightnessSupport.trustsRememberedLevel(lastKnownAt: pressed,
                                                       now: pressed.addingTimeInterval(1),
                                                       window: 3),
               "a level written a moment ago is still the running value")
        expect(!BrightnessSupport.trustsRememberedLevel(lastKnownAt: pressed,
                                                        now: pressed.addingTimeInterval(3),
                                                        window: 3),
               "a level older than the window is asked about again")
        expect(!BrightnessSupport.trustsRememberedLevel(lastKnownAt: nil,
                                                        now: pressed, window: 3),
               "a display never written to is asked about")
        expect(!BrightnessSupport.trustsRememberedLevel(lastKnownAt: pressed.addingTimeInterval(60),
                                                        now: pressed, window: 3),
               "a clock that jumped backwards never makes a stale level look fresh")
        // The step itself is unchanged; what changed is the value it starts
        // from, so the arithmetic stays pinned.
        expect(BrightnessSupport.steppedBrightness(0.8, delta: 1 / 16.0) > 0.8
                && BrightnessSupport.steppedBrightness(0.0, delta: 1 / 16.0) > 0,
               "a step still moves in the direction asked for")
    }
}
