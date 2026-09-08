// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO

enum RecorderTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Screen recorder wiring

        expect(Defaults.registeredDefaults[DefaultsKey.recorderShortcutEnabled] as? Bool == false,
               "the screen recorder shortcut ships off like every new feature")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderShortcut] as? String
                == "control+option+command:23",
               "the default recording shortcut sits next to the screenshot's own")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScreenRecorder] as? Bool == true,
               "the screen recorder panel tile ships visible like its siblings")
        let quickLauncherServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/QuickLauncherService.swift",
            encoding: .utf8)) ?? ""
        let quickLauncherViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/QuickLauncher/QuickLauncherView.swift",
            encoding: .utf8)) ?? ""
        expect(quickLauncherServiceSource.contains("case .screenRecorder: return .screenRecorder")
                && quickLauncherServiceSource.contains("ScreenRecorderService.shared.toggle()")
                && quickLauncherViewSource.contains(
                    "case .screenRecorder: return recorder.isRecording ? \"stop.circle\" : \"record.circle\""),
               "the screen recorder keeps its quick-panel tile, action and recording state")
        var windowRetention = WindowActivationRetention()
        let firstWindowNeedsPromotion = windowRetention.retain()
        let secondWindowNeedsPromotion = windowRetention.retain()
        let firstCloseNeedsDemotion = windowRetention.release()
        let lastCloseNeedsDemotion = windowRetention.release()
        let extraCloseNeedsDemotion = windowRetention.release()
        expect(firstWindowNeedsPromotion && !secondWindowNeedsPromotion
                && !firstCloseNeedsDemotion && lastCloseNeedsDemotion
                && !extraCloseNeedsDemotion && windowRetention.count == 0,
               "user-facing windows share one balanced app activation lifetime")
        let appDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift",
            encoding: .utf8)) ?? ""
        expect(appDelegateSource.contains("if !settingsKeepsAppRegular {")
                && appDelegateSource.contains("WindowActivationPolicy.retain()")
                && appDelegateSource.contains("WindowActivationPolicy.release()"),
               "Settings retains Command Tab presence only while its window is visible")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderSystemAudio] as? Bool == true,
               "a recording carries the sound of the Mac unless the person turns it off")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderMicrophone] as? Bool == false,
               "microphone recording is optional and ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderSharingEnabled] as? Bool == true,
               "temporary recording links stay visible but do nothing until explicitly used")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderQuality] as? String == "balanced"
                && Defaults.registeredDefaults[DefaultsKey.recorderFrameRate] as? Int == 60
                && Defaults.registeredDefaults[DefaultsKey.recorderCountdown] as? Int == 3
                && Defaults.registeredDefaults[DefaultsKey.recorderAutomaticZoom] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.recorderOpenEditor] as? Bool == true,
               "the recorder ships balanced, smooth, with automatic zooms, a short countdown and the editor on")
        expect(ScreenshotSupport.countdownRingProgress(elapsed: 0) == 1
                && ScreenshotSupport.countdownRingProgress(elapsed: 0.46) == 0.5
                && ScreenshotSupport.countdownRingProgress(elapsed: 0.92) == 0,
               "the countdown ring drains smoothly across each displayed number")
        expect(ScreenshotSupport.countdownRingProgress(elapsed: -1) == 1
                && ScreenshotSupport.countdownRingProgress(elapsed: 2) == 0,
               "the countdown ring clamps delayed and early frames")
        expect(GlobalShortcutRole.availableRoles(isAvailable: { _ in true })
                .contains(.screenRecorder),
               "the restored recording shortcut is visible in the shortcut editor")
        expect(AppFeature.screenRecorder.group == .tools
                && AppFeature.screenRecorder.enabledKeys.isEmpty
                && AppFeature.screenRecorder.permissions
                    == [.screenRecording, .accessibility, .audioCapture, .microphone],
               "the recorder keeps its optional capture permissions contextual")
        expect(AppFeature.screenRecorder.energyProfile == .idle,
               "the recorder costs nothing between recordings")
        expect(FeatureVisibilitySupport.features(for: .screenshot)
                == [.screenshot, .screenRecorder, .screenOCR, .colorPicker]
                && pageVisible(.screenshot, available: [.screenRecorder])
                && pageVisible(.screenshot, available: [.screenOCR])
                && pageVisible(.screenshot, available: [.colorPicker])
                && !pageVisible(.screenshot, available: []),
               "every installed screen tool keeps the one Screen capture page")
        expect([AppFeature.screenshot, .screenRecorder, .screenOCR, .colorPicker]
                .allSatisfy { $0.settingsDestination.page == .screenshot },
               "every screen tool opens its mode inside the centralized Settings page")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderShortcutEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderShortcut)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenOCRShortcutEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenOCRShortcut)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.colorPickerShortcutEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.colorPickerShortcut)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotShortcutEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderQuality)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderGIFSize)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderMicrophone)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderAutomaticZoom)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderSharingEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderSaveFolder),
               "dedicated capture shortcuts and recorder settings travel in backups")
        expect(RecorderSupport.exceptedOwnWindowIDs(
            ownWindowIDs: [1, 2, 3], protectedWindowIDs: [2, 4]) == [1, 3],
               "recording keeps existing ordinary app windows but never its protected chrome")

        expect(RecordingShareDuration.allCases.map(\.rawValue) == [3_600, 21_600],
               "recording links allow only one or six hours")
        let recordingShareEndpoint = RecordingSharingSupport.endpoint(
            bundleIdentifier: RecordingSharingSupport.developerBundleIdentifier,
            developerOverride: "https://test.example/")
        expect(RecordingSharingSupport.uploadURL(endpoint: recordingShareEndpoint,
                                                 duration: .sixHours)?.absoluteString
                == "https://test.example/v1/recordings?expiresIn=21600",
               "recording sharing uses its fixed endpoint and expiration query")
        let recordingID = String(repeating: "r", count: 32)
        let recordingResponse = RecordingShareResponse(
            id: recordingID,
            viewPath: "/s/\(recordingID)",
            expiresAt: "1970-01-01T06:16:40.000Z",
            deleteToken: String(repeating: "t", count: 43))
        expect(RecordingSharingSupport.record(response: recordingResponse,
                                              endpoint: recordingShareEndpoint,
                                              now: Date(timeIntervalSince1970: 1_000))?.id
                == recordingID,
               "a valid six-hour recording response becomes an owner-held record")
        let recordingPlan = RecordingSharingSupport.encodingPlan(
            duration: 30,
            baseSize: CGSize(width: 3840, height: 2160),
            sourceFrameRate: 60,
            hasAudio: true)
        expect(recordingPlan != nil
                && max(recordingPlan!.size.width, recordingPlan!.size.height) <= 1920
                && recordingPlan!.frameRate == 30
                && recordingPlan!.audioBitRate == 128_000,
               "a large short recording gets a web-sized video and keeps its audio")
        if let recordingPlan {
            let plannedBytes = (recordingPlan.videoBitRate + recordingPlan.audioBitRate)
                * 30 / 8
            expect(plannedBytes < RecordingSharingSupport.targetUploadBytes,
                   "the first compression pass stays inside the upload budget")
        }
        expect(RecordingSharingSupport.encodingPlan(
            duration: 3_600,
            baseSize: CGSize(width: 1920, height: 1080),
            sourceFrameRate: 30,
            hasAudio: true) == nil,
               "sharing refuses a duration that cannot fit without unusable quality")
        expect(RecordingSharingSupport.retryScale(current: 1,
                                                  actualBytes: 100_000_000) ?? 1 < 1,
               "an oversized first pass retries at a lower bitrate")

        // MARK: Screen recorder geometry and policy

        let displayPixels = CGRect(x: 0, y: 0, width: 2940, height: 1912)
        let odd = RecorderSupport.snappedPixelRect(
            CGRect(x: 10.7, y: 20.2, width: 641.4, height: 401.9), in: displayPixels)
        expect(odd.width.truncatingRemainder(dividingBy: 2) == 0
                && odd.height.truncatingRemainder(dividingBy: 2) == 0,
               "a picked area is snapped to even pixels, which is what encoders accept")
        expect(odd.origin.x == 10 && odd.origin.y == 20,
               "snapping moves the origin to whole pixels without shifting the area")
        let overflowing = RecorderSupport.snappedPixelRect(
            CGRect(x: 2900, y: 1900, width: 400, height: 400), in: displayPixels)
        expect(displayPixels.contains(overflowing),
               "an area that runs off the display is brought back inside it")
        expect(overflowing.width >= RecorderSupport.minimumSide
                && overflowing.height >= RecorderSupport.minimumSide,
               "a clamped area never collapses below the smallest recordable size")
        let broken = RecorderSupport.snappedPixelRect(
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), in: displayPixels)
        expect(broken.width > 0 && broken.height > 0,
               "a broken rectangle falls back to the whole display instead of failing")

        expect(RecorderSupport.elapsedLabel(seconds: 0) == "0:00"
                && RecorderSupport.elapsedLabel(seconds: 7) == "0:07"
                && RecorderSupport.elapsedLabel(seconds: 754) == "12:34"
                && RecorderSupport.elapsedLabel(seconds: 3723) == "1:02:03",
               "elapsed time reads like a player position and grows an hour field only when needed")
        expect(RecorderSupport.elapsedLabel(seconds: -5) == "0:00",
               "a clock that never went forward still reads as zero")

        expect(RecorderSupport.trustsSystemAudioTap(previously: false, tapHeardSound: true,
                                                    streamHeardSound: true)
                && RecorderSupport.trustsSystemAudioTap(previously: false, tapHeardSound: true,
                                                        streamHeardSound: false),
               "a tap that heard sound is trusted for the next recording")
        expect(!RecorderSupport.trustsSystemAudioTap(previously: true, tapHeardSound: false,
                                                     streamHeardSound: true),
               "a tap that stayed silent through sound the stream heard loses its trust")
        expect(RecorderSupport.trustsSystemAudioTap(previously: true, tapHeardSound: false,
                                                    streamHeardSound: false)
                && !RecorderSupport.trustsSystemAudioTap(previously: false, tapHeardSound: false,
                                                         streamHeardSound: false),
               "a silent recording proves nothing about the tap")
        expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderSystemAudioTapVerified)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.recorderSystemAudio),
               "the tap grant this Mac gave stays out of the backup while the sound choice travels")
        var pauseTimeline = RecorderPauseTimeline()
        expect(pauseTimeline.pause(at: 3) && !pauseTimeline.pause(at: 4),
               "a recording enters one pause only once")
        expect(pauseTimeline.elapsed(since: 0, at: 7) == 3
                && pauseTimeline.sampleTime(start: 5, duration: 0.01, since: 0) == nil,
               "an open pause freezes elapsed time and discards captured samples")
        expect(pauseTimeline.resume(at: 8) && !pauseTimeline.resume(at: 9),
               "a recording resumes one open pause only once")
        expect(pauseTimeline.sampleTime(start: 2, duration: 0.01, since: 0) == 2
                && pauseTimeline.sampleTime(start: 8, duration: 0.01, since: 0) == 3
                && pauseTimeline.eventTime(10, since: 0) == 5,
               "video, audio and event time close the paused gap exactly")
        expect(pauseTimeline.sampleTime(start: 2.99, duration: 0.02, since: 0) == nil,
               "an audio buffer crossing the pause edge is dropped instead of overlapping")
        expect(pauseTimeline.sampleTime(start: -0.01, duration: 0.01, since: 0) == nil,
               "a late sample from before the recording origin stays out")
        _ = pauseTimeline.pause(at: 12)
        _ = pauseTimeline.resume(at: 14)
        expect(pauseTimeline.eventTime(13, since: 0) == nil
                && pauseTimeline.elapsed(since: 0, at: 16) == 9,
               "several pauses stay excluded from every recording track")

        expect(RecorderSupport.sanitizedFrameRate(60) == 60
                && RecorderSupport.sanitizedFrameRate(30) == 30
                && RecorderSupport.sanitizedFrameRate(144) == 60,
               "an unknown frame rate falls back to the smooth default")
        expect(RecorderSupport.sanitizedQuality("high") == .high
                && RecorderSupport.sanitizedQuality("nonsense") == .balanced
                && RecorderSupport.sanitizedQuality(nil) == .balanced,
               "an unknown quality falls back to balanced")

        let smallSize = RecorderSupport.outputSize(source: CGSize(width: 2940, height: 1912),
                                                   quality: .small)
        expect(smallSize == CGSize(width: 1470, height: 956),
               "the small preset halves the picture and stays on even pixels")
        expect(RecorderSupport.outputSize(source: CGSize(width: 2940, height: 1912), quality: .high)
                == CGSize(width: 2940, height: 1912),
               "the high preset keeps every pixel")
        let highRate = RecorderSupport.averageBitRate(width: 2940, height: 1912, fps: 60,
                                                      quality: .high)
        let smallRate = RecorderSupport.averageBitRate(width: 1470, height: 956, fps: 60,
                                                       quality: .small)
        expect(highRate > smallRate,
               "a bigger picture at a higher preset asks the encoder for more")
        expect(RecorderSupport.averageBitRate(width: 64, height: 64, fps: 30, quality: .small)
                >= 800_000,
               "even a tiny area gets a usable stream")
        expect(highRate <= 60_000_000,
               "no preset asks for more than the media engine sustains")

        let now = Date(timeIntervalSince1970: 1_000_000)
        let beingEdited = UUID()
        let leftBehind = UUID()
        let beingWritten = UUID()
        let deadOnArrival = UUID()
        let takeHistory: [(id: UUID, finishedAt: Date?, createdAt: Date?)] = [
            (id: beingEdited, finishedAt: now.addingTimeInterval(-600),
             createdAt: now.addingTimeInterval(-700)),
            (id: leftBehind, finishedAt: now.addingTimeInterval(-3 * 24 * 3600),
             createdAt: now.addingTimeInterval(-3 * 24 * 3600)),
            (id: beingWritten, finishedAt: nil, createdAt: now.addingTimeInterval(-5)),
            (id: deadOnArrival, finishedAt: nil, createdAt: now.addingTimeInterval(-8 * 3600)),
        ]
        let swept = Set(RecorderSupport.orphanTakeIDs(takeHistory, now: now))
        expect(swept == [leftBehind, deadOnArrival],
               "the sweep only takes what a crash or a quit left behind")
        expect(!swept.contains(beingEdited),
               "a recording whose editor is open is never swept out from under it")
        expect(!swept.contains(beingWritten),
               "a recording being written right now has no file yet and is left alone")

        let directSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-recorder-save-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: directSaveRoot,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directSaveRoot) }

        let savedID = UUID()
        let savedFolder = directSaveRoot.appendingPathComponent(
            RecorderSupport.takeFolderName(id: savedID), isDirectory: true)
        try? FileManager.default.createDirectory(at: savedFolder,
                                                 withIntermediateDirectories: true)
        let savedTake = RecorderTakeStore.Take(id: savedID, folder: savedFolder)
        let masterBytes = Data("finished recording".utf8)
        try? masterBytes.write(to: savedTake.videoURL)
        let savedDestination = directSaveRoot.appendingPathComponent("saved.mov")
        do {
            try RecorderTakeStore.shared.saveDirectly(savedTake, to: savedDestination)
            expect((try? Data(contentsOf: savedDestination)) == masterBytes,
                   "direct save copies the complete recording to its destination")
            expect(!FileManager.default.fileExists(atPath: savedFolder.path),
                   "direct save removes its internal take after the copy succeeds")
        } catch {
            expect(false, "a valid direct save succeeds")
        }

        let recoverableID = UUID()
        let recoverableFolder = directSaveRoot.appendingPathComponent(
            RecorderSupport.takeFolderName(id: recoverableID), isDirectory: true)
        try? FileManager.default.createDirectory(at: recoverableFolder,
                                                 withIntermediateDirectories: true)
        let recoverableTake = RecorderTakeStore.Take(id: recoverableID, folder: recoverableFolder)
        try? masterBytes.write(to: recoverableTake.videoURL)
        let unavailableDestination = directSaveRoot
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("saved.mov")
        var directSaveFailed = false
        do {
            try RecorderTakeStore.shared.saveDirectly(recoverableTake,
                                                      to: unavailableDestination)
        } catch {
            directSaveFailed = true
        }
        expect(directSaveFailed,
               "direct save reports a destination that cannot be written")
        expect(FileManager.default.fileExists(atPath: recoverableTake.videoURL.path),
               "a failed direct save keeps the take available for recovery")

        let importSource = directSaveRoot.appendingPathComponent("source.mp4")
        try? masterBytes.write(to: importSource)
        let importedID = UUID()
        let importedFolder = directSaveRoot.appendingPathComponent(
            RecorderSupport.takeFolderName(id: importedID), isDirectory: true)
        try? FileManager.default.createDirectory(at: importedFolder,
                                                 withIntermediateDirectories: true)
        let importedTake = RecorderTakeStore.Take(id: importedID, folder: importedFolder)
        expect(RecorderTakeStore.shared.importVideo(at: importSource, into: importedTake),
               "an ordinary video is staged as an editor take")
        expect((try? Data(contentsOf: importedTake.videoURL)) == masterBytes,
               "the staged editor take keeps every source byte")
        let changedSourceBytes = Data("changed outside the editor".utf8)
        try? changedSourceBytes.write(to: importSource)
        expect((try? Data(contentsOf: importedTake.videoURL)) == masterBytes,
               "external changes to the original never alter the staged editor master")
        RecorderTakeStore.shared.delete(importedTake)
        expect((try? Data(contentsOf: importSource)) == changedSourceBytes,
               "discarding an imported take never changes the original video")

        // Save as can be pointed at a recording that already exists. What is
        // there survives an export that is cancelled or fails: the new file is
        // written beside it and only takes its place once it is whole.
        let exportDestination = directSaveRoot.appendingPathComponent("export.mp4")
        let alreadySavedBytes = Data("the recording already saved here".utf8)
        try? alreadySavedBytes.write(to: exportDestination)
        let abandonedStaging = RecorderSupport.stagingURL(for: exportDestination)
        expect(abandonedStaging.deletingLastPathComponent().path == directSaveRoot.path
                && abandonedStaging.lastPathComponent.hasPrefix(".")
                && abandonedStaging.pathExtension == exportDestination.pathExtension
                && abandonedStaging != RecorderSupport.stagingURL(for: exportDestination),
               "an export is written beside its destination, out of sight and under its own name")
        try? Data("half an export".utf8).write(to: abandonedStaging)
        try? FileManager.default.removeItem(at: abandonedStaging)
        expect((try? Data(contentsOf: exportDestination)) == alreadySavedBytes,
               "a cancelled or failed export leaves the recording already saved there untouched")
        let exportedBytes = Data("the recording that finished exporting".utf8)
        let finishedStaging = RecorderSupport.stagingURL(for: exportDestination)
        try? exportedBytes.write(to: finishedStaging)
        expect(RecorderSupport.commitExport(from: finishedStaging, to: exportDestination)
                && (try? Data(contentsOf: exportDestination)) == exportedBytes
                && !FileManager.default.fileExists(atPath: finishedStaging.path),
               "a finished export replaces what was there and leaves nothing beside it")
        let freshDestination = directSaveRoot.appendingPathComponent("fresh.mp4")
        let freshStaging = RecorderSupport.stagingURL(for: freshDestination)
        try? exportedBytes.write(to: freshStaging)
        expect(RecorderSupport.commitExport(from: freshStaging, to: freshDestination)
                && (try? Data(contentsOf: freshDestination)) == exportedBytes,
               "an export to a name nothing uses yet lands under that name")
        expect(!RecorderSupport.commitExport(
                    from: RecorderSupport.stagingURL(for: exportDestination),
                    to: exportDestination)
                && (try? Data(contentsOf: exportDestination)) == exportedBytes,
               "an export that wrote no file at all leaves the saved recording as it is")

        // An edit that cannot be composed stops the export. The plain path
        // draws the recording untouched, so answering with it would hand back
        // a file with the areas kept unreadable, and everything else drawn on
        // the picture, missing.
        let recorderComposerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/RecorderComposer.swift",
            encoding: .utf8)) ?? ""
        expect(!recorderComposerSource.isEmpty,
               "the recorder composer source reads back for its shape check")
        expect(recorderComposerSource.contains(
                    "outputSize: CGSize) async -> AVMutableVideoComposition?"),
               "a composition that cannot be built answers with nothing, never with the plain one")
        let recorderExporterSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/RecorderExporter.swift",
            encoding: .utf8)) ?? ""
        expect(!recorderExporterSource.isEmpty,
               "the recorder exporter source reads back for its shape check")
        let compositionsAsked = recorderExporterSource
            .components(separatedBy: "RecorderComposer.videoComposition(").count - 1
        let compositionsGuarded = recorderExporterSource
            .components(separatedBy: "guard let composition = await RecorderComposer.videoComposition(")
            .count - 1
        expect(compositionsAsked > 0 && compositionsAsked == compositionsGuarded,
               "an export stops when the edit cannot be composed, instead of saving the recording bare")

        expect(RecorderSupport.canStart(freeBytes: 10_000_000_000)
                && !RecorderSupport.canStart(freeBytes: 100_000_000),
               "a recording refuses to start when the disk is nearly full")
        expect(RecorderSupport.pendingStartIsAuthorized(requestGeneration: 4,
                                                        currentGeneration: 4,
                                                        featureIsAvailable: true)
                && !RecorderSupport.pendingStartIsAuthorized(requestGeneration: 4,
                                                             currentGeneration: 5,
                                                             featureIsAvailable: true)
                && !RecorderSupport.pendingStartIsAuthorized(requestGeneration: 4,
                                                             currentGeneration: 4,
                                                             featureIsAvailable: false),
               "a late microphone response cannot start a cancelled or uninstalled recorder")
        let recorderStartGate = RecorderStartGate()
        expect(recorderStartGate.begin() && recorderStartGate.isAuthorized,
               "recorder start gate admits one authorized capture start")
        expect(recorderStartGate.cancelAndClaimStop()
                && !recorderStartGate.claimStartFailure(),
               "stop atomically owns writer finalization when it wins the start race")
        let recorderStartFinished = DispatchSemaphore(value: 0)
        Task.detached {
            await recorderStartGate.waitUntilFinished()
            recorderStartFinished.signal()
        }
        expect(recorderStartFinished.wait(timeout: .now() + 0.05) == .timedOut,
               "recorder stop waits while capture start is suspended")
        recorderStartGate.finish()
        expect(recorderStartFinished.wait(timeout: .now() + 0.5) == .success
                && !recorderStartGate.isAuthorized,
               "recorder cancellation resumes stop only after start has unwound")
        let recorderFailureGate = RecorderStartGate()
        expect(recorderFailureGate.begin() && recorderFailureGate.claimStartFailure()
                && !recorderFailureGate.cancelAndClaimStop(),
               "start failure atomically owns writer cancellation when it wins the stop race")
        recorderFailureGate.finish()
        var captureLifecycle = RecorderCaptureLifecycle()
        expect(!captureLifecycle.acceptsSamples && captureLifecycle.beginStart()
                && captureLifecycle.acceptsSamples && !captureLifecycle.isRunning
                && captureLifecycle.didStart() && captureLifecycle.isRunning,
               "recorder capture accepts samples only while its one start is active")
        captureLifecycle.stop()
        expect(!captureLifecycle.acceptsSamples && !captureLifecycle.isRunning
                && !captureLifecycle.beginStart() && !captureLifecycle.didStart(),
               "recorder capture stays terminal after stop so queued samples cannot revive it")
        expect(RecorderSupport.shouldStopForDisk(freeBytes: 100_000_000)
                && !RecorderSupport.shouldStopForDisk(freeBytes: 10_000_000_000),
               "a recording already running stops before it fills the disk")
        expect(RecorderSupport.minimumFreeBytesToContinue < RecorderSupport.minimumFreeBytesToStart,
               "stopping a recording is allowed to get closer to full than starting one")
        expect(!RecorderTakeStore.canImport(fileSize: 600_000_000,
                                            availableBytes: 1_000_000_000)
               && RecorderTakeStore.canImport(fileSize: 600_000_000,
                                              availableBytes: 1_100_000_000),
               "video import reserves enough free disk space before copying the master")

        let wholeClip = RecorderSupport.sanitizedTrim(start: 0, end: 0, duration: 12)
        expect(wholeClip.start == 0 && wholeClip.end == 12,
               "an end of zero means the whole recording, so an untouched edit shows everything")
        let inside = RecorderSupport.sanitizedTrim(start: 2, end: 9, duration: 12)
        expect(inside.start == 2 && inside.end == 9 && inside.duration == 7,
               "a trim inside the recording is kept as it is")
        let collapsed = RecorderSupport.sanitizedTrim(start: 8, end: 8, duration: 12)
        // A hair of tolerance: the floor is added to a start time in binary
        // floating point, so the difference lands a few ulps under it.
        expect(collapsed.duration >= RecorderSupport.minimumTrimSeconds - 1e-9,
               "dragging both handles together still leaves a clip you can play")
        let past = RecorderSupport.sanitizedTrim(start: 20, end: 30, duration: 12)
        expect(past.end <= 12 && past.start >= 0 && past.duration > 0,
               "a trim past the end of the recording is brought back inside it")
        expect(RecorderSupport.sanitizedTrim(start: 0, end: 5, duration: 0).duration == 0,
               "a recording with no duration produces no clip instead of a broken one")

        expect(RecorderSupport.filmstripTimes(duration: 10, count: 4)
                == [1.25, 3.75, 6.25, 8.75],
               "filmstrip frames are sampled at the middle of each slot")
        expect(RecorderSupport.filmstripTimes(duration: 0, count: 4).isEmpty
                && RecorderSupport.filmstripTimes(duration: 10, count: 0).isEmpty,
               "an empty recording asks for no thumbnails")

        expect(RecorderSupport.gifFrameCount(duration: 10, fps: 12) == 120,
               "a GIF holds one frame per tick of its own rate")
        expect(RecorderSupport.gifFitsBudget(duration: 10, fps: 12)
                && !RecorderSupport.gifFitsBudget(duration: 120, fps: 12),
               "a GIF long enough to eat the memory of the machine is refused before it starts")
        expect(Int(RecorderSupport.maximumGIFSeconds(fps: 12)) == 25,
               "the refusal can say exactly how long a GIF may be at that rate")
        expect(RecorderSupport.gifDelay(fps: 10) == 0.1,
               "the frame delay is the reciprocal of the rate")
        let gifSize = RecorderSupport.gifOutputSize(source: CGSize(width: 2940, height: 1912),
                                                    size: .medium)
        expect(max(gifSize.width, gifSize.height) <= RecorderSupport.GIFSize.medium.longEdge
                && gifSize.width.truncatingRemainder(dividingBy: 2) == 0,
               "a GIF is scaled down to its long edge and stays on even pixels")
        expect(RecorderSupport.gifOutputSize(source: CGSize(width: 200, height: 120), size: .large)
                == CGSize(width: 200, height: 120),
               "a recording smaller than the GIF size is never blown up")
        expect(RecorderSupport.sanitizedGIFFrameRate(99) == 12
                && RecorderSupport.sanitizedGIFSize("nonsense") == .medium,
               "unknown GIF settings fall back to the middle choice")
        expect(RecorderSupport.sanitizedAudioGain(-1) == 0
                && RecorderSupport.sanitizedAudioGain(3) == 1
                && RecorderSupport.sanitizedAudioGain(.nan) == 1,
               "audio gain stays inside the editor's safe range")

        var document = RecorderEditDocument()
        expect(!document.isEdited(duration: 12) && !document.zoomsOnTyping,
               "a recording nobody touched is not treated as edited")
        document.trimStart = 3
        expect(document.isEdited(duration: 12),
               "moving a handle marks the recording as edited")
        document.trimStart = 100
        document.trimEnd = -5
        let repaired = document.sanitized(duration: 12)
        expect(repaired.trimStart >= 0 && repaired.trimEnd <= 12
                && repaired.trim(duration: 12).duration > 0,
               "a damaged edit is repaired instead of wedging the editor")
        let documentRoundTrip = RecorderEditDocument.decoded(
            RecorderEditDocument(trimStart: 1, trimEnd: 4, keepsSystemAudio: false,
                                 zoomsOnTyping: true, keepsMicrophone: false,
                                 systemAudioGain: 0.6, microphoneGain: 1.5).encoded())
        expect(documentRoundTrip.trimStart == 1 && documentRoundTrip.trimEnd == 4
                && !documentRoundTrip.keepsSystemAudio && !documentRoundTrip.keepsMicrophone
                && documentRoundTrip.systemAudioGain == 0.6
                && documentRoundTrip.microphoneGain == 1.5
                && documentRoundTrip.zoomsOnTyping,
               "an edit written next to the recording comes back exactly as it was")
        expect(RecorderEditDocument.decoded(Data("not json".utf8)).trimStart == 0,
               "an unreadable edit opens the recording untouched instead of failing")
        let click = RecorderMotion.Click(time: 3, isDown: true)
        let recoveredZooms = RecorderEditDocument(zoomEnabled: true,
                                                  zoomSegments: [],
                                                  zoomsGenerated: true)
            .restoringAutomaticZooms(clicks: [click], duration: 10)
        expect(recoveredZooms.zoomSegments.count == 1
                && recoveredZooms.zoomSegments[0].followsPointer,
               "turning automatic zoom back on recovers a click-based zoom that was deleted")
        let disabledZooms = RecorderEditDocument(zoomEnabled: false)
            .restoringAutomaticZooms(clicks: [click], duration: 10)
        expect(disabledZooms.zoomSegments.isEmpty,
               "a recording with automatic zooms off starts without zooms on its timeline")
        var intentionalZoom = RecorderTimeline.ZoomSegment(start: 2, end: 4, amount: 2.2)
        intentionalZoom.focusX = 0.2
        intentionalZoom.focusY = 0.3
        let preservedZooms = RecorderEditDocument(zoomEnabled: true,
                                                  zoomSegments: [intentionalZoom])
            .restoringAutomaticZooms(clicks: [click], duration: 10)
        expect(preservedZooms.zoomSegments == [intentionalZoom],
               "recovering automatic zoom never replaces a zoom that is still on the timeline")

        let typingTrack = RecorderTypingTrack(times: [1, 1.2])
        expect(RecorderTypingTrack.decoded(typingTrack.encoded()) == typingTrack,
               "typing timing round-trips without storing which keys were pressed")

        var styled = RecorderEditDocument(backdrop: "style", zoomAmount: 2.4,
                                          texts: [RecorderTextOverlay(text: "Keep", start: 0,
                                                                      end: 1)])
        let preset = RecorderEditPreset(name: "Demo", document: styled)
        styled.backdrop = "other"
        styled.texts.append(RecorderTextOverlay(text: "Also keep", start: 1, end: 2))
        let appliedPreset = preset.applying(to: styled)
        expect(appliedPreset.backdrop == "style" && appliedPreset.zoomAmount == 2.4
                && appliedPreset.texts.count == 2,
               "an editor preset changes the look without touching timeline edits")
        RecorderPresetImageStoreTests.run { expect($0, $1) }

        // MARK: Screen recorder motion

        let flatAlpha = RecorderMotion.onePoleAlpha(cutoff: 2, dt: 1.0 / 60)
        expect(abs(flatAlpha - 0.18899) < 0.0001,
               "the one-pole coefficient matches the closed form at 60 fps")
        expect(RecorderMotion.onePoleAlpha(cutoff: 0, dt: 1.0 / 60) == 1,
               "no smoothing at all passes the signal straight through")

        // A step is the hardest case: a causal filter lands late, a forward
        // and backward pass lands on time. That is the whole reason the
        // recording is finished before any of this runs.
        let step = (0..<120).map { $0 < 60 ? 0.0 : 1.0 }
        let filtered = RecorderMotion.filtfilt(step, alpha: 0.28)
        expect(filtered.count == step.count,
               "smoothing returns as many samples as it was given")
        expect(abs(filtered[59] - 0.5) < 0.2,
               "the smoothed step crosses halfway AT the step, not after it")
        expect(filtered[0] < 0.02 && filtered[119] > 0.98,
               "the padded ends are not dragged toward the middle of the clip")
        var monotonic = true
        for index in 1..<filtered.count where filtered[index] < filtered[index - 1] - 1e-9 {
            monotonic = false
        }
        expect(monotonic, "smoothing a step never overshoots or rings")

        let clicks = [RecorderMotion.Click(time: 1.0, isDown: true),
                      RecorderMotion.Click(time: 1.3, isDown: false)]
        expect(RecorderMotion.anchorWeight(at: 1.0, clicks: clicks) == 1,
               "at the moment of the press the pointer is exactly where it really was")
        expect(RecorderMotion.anchorWeight(at: 1.15, clicks: clicks) == 1,
               "through a drag the pointer tracks the truth, or what is dragged comes loose")
        expect(RecorderMotion.anchorWeight(at: 0.5, clicks: clicks) == 0,
               "far from a click the smoothed path is used as it is")
        expect(RecorderMotion.anchorWeight(at: 0.94, clicks: clicks) > 0
                && RecorderMotion.anchorWeight(at: 0.94, clicks: clicks) < 1,
               "the blend back to the truth eases in rather than snapping")

        let openDrag = [RecorderMotion.Click(time: 2.0, isDown: true)]
        expect(RecorderMotion.anchorWeight(at: 5.0, clicks: openDrag) == 1,
               "a recording that ended mid drag keeps tracking to the end")

        expect(RecorderMotion.smoothstep(0) == 0 && RecorderMotion.smoothstep(1) == 1
                && RecorderMotion.smoothstep(0.5) == 0.5,
               "the easing runs from nothing to everything through the middle")
        expect(RecorderMotion.smootherstep(-4) == 0 && RecorderMotion.smootherstep(9) == 1,
               "easing outside its range is clamped instead of exploding")

        // MARK: Screen recorder zoom

        let burst = [RecorderMotion.Click(time: 2.0, isDown: true),
                     RecorderMotion.Click(time: 2.4, isDown: true),
                     RecorderMotion.Click(time: 3.1, isDown: true)]
        let oneZoom = RecorderMotion.zoomSegments(clicks: burst, duration: 20)
        expect(oneZoom.count == 1,
               "a burst of clicks is one zoom that holds, not a flicker")
        expect(oneZoom.first.map { $0.start < 2.0 } == true,
               "the zoom begins BEFORE the click, which is only possible offline")
        let typingZoom = RecorderMotion.zoomSegments(
            clicks: [RecorderMotion.Click(time: 2, isDown: true)],
            typingTimes: [4, 5, 6],
            duration: 20)
        expect(typingZoom.first.map { $0.end >= 7.39 } == true,
               "typing after a click keeps that zoom on the field until writing stops")
        let delayedTypingZoom = RecorderMotion.zoomSegments(
            clicks: [RecorderMotion.Click(time: 2, isDown: true)],
            typingTimes: [9, 10],
            duration: 20)
        expect(delayedTypingZoom.first.map { $0.end >= 11.39 } == true,
               "a pause after focusing a field does not lose its typing zoom")
        expect(RecorderMotion.zoomSegments(clicks: [], typingTimes: [2, 3], duration: 20).isEmpty,
               "typing without a click never invents a place to zoom")
        let farApart = [RecorderMotion.Click(time: 2.0, isDown: true),
                        RecorderMotion.Click(time: 12.0, isDown: true)]
        expect(RecorderMotion.zoomSegments(clicks: farApart, duration: 20).count == 2,
               "clicks far apart get a zoom each")
        expect(RecorderMotion.zoomSegments(
                clicks: [RecorderMotion.Click(time: 9.6, isDown: true)], duration: 10).isEmpty,
               "the click that stopped the recording never causes a zoom")
        expect(RecorderMotion.zoomSegments(clicks: burst, duration: 20)
                .allSatisfy { $0.end <= 20 - RecorderMotion.zoomEndMargin + 0.001 },
               "no clip ends in the middle of a zoom")
        expect(RecorderMotion.zoomSegments(clicks: [], duration: 20).isEmpty,
               "a recording with no clicks has no zoom")

        let segment = RecorderMotion.ZoomSegment(start: 2, end: 6)
        expect(RecorderMotion.zoomProgress(at: 1.5, segments: [segment]) == 0,
               "before the segment the picture is untouched")
        expect(RecorderMotion.zoomProgress(at: 4, segments: [segment]) == 1,
               "in the middle of the segment the zoom is fully in")
        let rampingIn = RecorderMotion.zoomProgress(at: 2.2, segments: [segment])
        expect(rampingIn > 0 && rampingIn < 1, "the zoom eases in rather than cutting")
        let rampingOut = RecorderMotion.zoomProgress(at: 6.3, segments: [segment])
        expect(rampingOut > 0 && rampingOut < 1, "the zoom eases out rather than cutting")

        // The viewport is parameterized in its own travel range, so it cannot
        // leave the frame and never needs clamping afterwards.
        for zoomLevel in [1.2, 1.8, 2.5, 3.0] {
            for travelValue in [-1.0, 0.0, 0.37, 1.0, 2.0] {
                let origin = RecorderMotion.viewportOrigin(
                    travel: CGPoint(x: travelValue, y: travelValue), zoom: zoomLevel)
                let span = 1 / zoomLevel
                expect(origin.x >= -1e-9 && origin.x + span <= 1 + 1e-9
                        && origin.y >= -1e-9 && origin.y + span <= 1 + 1e-9,
                       "the zoomed viewport is inside the frame by construction")
            }
        }
        expect(RecorderMotion.travelParameter(focus: 0.05) == 0
                && RecorderMotion.travelParameter(focus: 0.95) == 1,
               "a pointer near an edge pins the view flush to it, so corners stay reachable")
        expect(abs(RecorderMotion.travelParameter(focus: 0.5) - 0.5) < 1e-9,
               "a pointer in the middle keeps the view centred")

        var spring = RecorderMotion.Spring(value: 0)
        for _ in 0..<400 { spring.step(toward: 1, dt: 1.0 / 240) }
        expect(abs(spring.value - 1) < 0.02,
               "the spring settles on its target instead of orbiting it")
        let springTrace = RecorderMotion.springed(
            [0, 0] + Array(repeating: 1.0, count: 40), frameRate: 60)
        expect(springTrace.first == 0 && springTrace.last ?? 0 > 0.9,
               "a springed timeline starts where it started and settles on the target")
        expect(springTrace.max() ?? 0 <= 1.2,
               "the spring is damped enough not to fly past what it was asked for")

        let cluster = RecorderMotion.focusClusters(
            [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.11, y: 0.1), CGPoint(x: 0.9, y: 0.9)],
            frameRate: 60, zoom: 2)
        expect(cluster.count >= 2,
               "a jump across the screen starts a new place to look at")
        expect(RecorderMotion.focus(at: 0, clusters: cluster) == cluster[0].center,
               "at the start the picture looks where the pointer started")

        expect(RecorderMotion.pressScale(at: 1.0, clicks: clicks) == RecorderMotion.pressPunchScale,
               "the pointer is at its smallest exactly while the button is down")
        expect(RecorderMotion.pressScale(at: 0.5, clicks: clicks) == 1,
               "away from a click the pointer is its normal size")
        expect(RecorderMotion.ringProgress(at: 1.0, clicks: clicks) == 0,
               "the ring is born at the click")
        expect(RecorderMotion.ringProgress(at: 2.0, clicks: clicks) == nil,
               "the ring is gone well before the next second")

        // The composer carries one cursor per lookup across its frame loop
        // instead of rescanning the click list per frame. Every query is
        // compared bit for bit against the scan it replaced, carried and
        // fresh, over a list with bursts, held buttons, presses never
        // released and one at the very end.
        var scanClicks: [RecorderMotion.Click] = []
        var scanSeed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var scanAt: Double = 0.05
        for step in 0..<300 {
            scanSeed = scanSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            scanAt += Double((scanSeed >> 33) % 37) / 100 + 0.01
            scanClicks.append(RecorderMotion.Click(time: scanAt, isDown: true))
            guard step % 7 != 0 else { continue }
            scanAt += Double((scanSeed >> 17) % 29) / 100 + 0.005
            scanClicks.append(RecorderMotion.Click(time: scanAt, isDown: false))
        }
        scanAt += 0.5
        scanClicks.append(RecorderMotion.Click(time: scanAt, isDown: true))
        func scannedPunch(at time: Double) -> Double {
            var weight: Double = 0
            var pressedAt: Double?
            for click in scanClicks {
                if click.isDown {
                    pressedAt = click.time
                    if time >= click.time - RecorderMotion.pressPunchWindow, time <= click.time {
                        weight = max(weight, RecorderMotion.smoothstep(
                            (time - (click.time - RecorderMotion.pressPunchWindow))
                                / RecorderMotion.pressPunchWindow))
                    }
                } else if let down = pressedAt {
                    if time >= down, time <= click.time { weight = 1 }
                    if time > click.time, time <= click.time + RecorderMotion.pressPunchWindow {
                        weight = max(weight, RecorderMotion.smoothstep(
                            1 - (time - click.time) / RecorderMotion.pressPunchWindow))
                    }
                    pressedAt = nil
                }
            }
            if let down = pressedAt, time >= down { weight = 1 }
            return 1 - (1 - RecorderMotion.pressPunchScale) * min(1, weight)
        }
        func scannedRing(at time: Double) -> Double? {
            var best: Double?
            for click in scanClicks where click.isDown {
                let elapsed = time - click.time
                guard elapsed >= 0, elapsed <= RecorderMotion.ringDuration else { continue }
                best = min(best ?? elapsed / RecorderMotion.ringDuration,
                           elapsed / RecorderMotion.ringDuration)
            }
            return best
        }
        func scannedAnchor(at time: Double) -> Double {
            var weight: Double = 0
            var pressedAt: Double?
            for click in scanClicks {
                if click.isDown {
                    pressedAt = click.time
                } else if let down = pressedAt {
                    if time >= down, time <= click.time { return 1 }
                    pressedAt = nil
                }
                let distance = abs(time - click.time)
                guard distance <= RecorderMotion.clickAnchorWindow else { continue }
                weight = max(weight, RecorderMotion.smoothstep(
                    1 - distance / RecorderMotion.clickAnchorWindow))
            }
            if let down = pressedAt, time >= down { return 1 }
            return weight
        }
        func scannedFocus(at time: Double) -> CGPoint {
            var current = cluster.first?.center ?? CGPoint(x: 0.5, y: 0.5)
            for entry in cluster where entry.time <= time { current = entry.center }
            return current
        }
        var punchCursor = 0
        var ringCursor = 0
        var anchorCursor = 0
        var focusCursor = 0
        var cursorMatches = true
        let scanFrames = Int((scanAt + 1) * 60)
        for frame in 0..<scanFrames {
            let time = Double(frame) / 60
            let punch = scannedPunch(at: time)
            let ring = scannedRing(at: time)
            let anchor = scannedAnchor(at: time)
            let focus = scannedFocus(at: time)
            if RecorderMotion.pressScale(at: time, clicks: scanClicks, cursor: &punchCursor)
                    != punch
                || RecorderMotion.ringProgress(at: time, clicks: scanClicks, cursor: &ringCursor)
                    != ring
                || RecorderMotion.anchorWeight(at: time, clicks: scanClicks, cursor: &anchorCursor)
                    != anchor
                || RecorderMotion.focus(at: time, clusters: cluster, cursor: &focusCursor) != focus
                || RecorderMotion.pressScale(at: time, clicks: scanClicks) != punch
                || RecorderMotion.ringProgress(at: time, clicks: scanClicks) != ring
                || RecorderMotion.anchorWeight(at: time, clicks: scanClicks) != anchor
                || RecorderMotion.focus(at: time, clusters: cluster) != focus {
                cursorMatches = false
            }
        }
        expect(scanFrames > 5_000 && scanClicks.count > 500,
               "the cursor comparison covers a long recording and a busy click list")
        expect(cursorMatches,
               "carried or fresh, every cursored lookup answers what the full scan answered")

        // The typing sampler fills an array from an NSEvent monitor callback
        // while the stop path reads it, so the append has to be under the
        // lock: an unsynchronised one races the copy-on-write buffer. The
        // recording's start time is written by `start()` and read from that
        // same callback, so it belongs under the lock too.
        let typingSampler = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/RecorderTypingTrack.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        expect(typingSampler.contains("let lock = NSLock()"),
               "the typing sampler guards its buffer the way the pointer sampler does")
        expect(typingSampler.contains("lock.withLock { startedAt = CACurrentMediaTime() }"),
               "the typing sampler writes the recording's start time under the lock")
        expect(typingSampler.contains(
            "lock.withLock { guard let time = pauseClock.eventTime(now, since: startedAt) "
            + "else { return } times.append(time) }"
        ), "the typing sampler appends a keystroke time only under the lock")
        // `RecorderSession.stop()` is nonisolated and async, so its body runs
        // off the main thread however main-actor the caller was (SE-0338).
        // Both samplers install and remove AppKit event monitors, so they are
        // started and stopped back on the main thread.
        let recorderSessionShape = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/ScreenRecorderService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        expect(recorderSessionShape.contains(
            "await MainActor.run { pointer.start() typing.start() }"
        ), "the recorder installs its event monitors on the main thread")
        expect(recorderSessionShape.contains(
            "await MainActor.run { (pointer.stop(), typing.stop()) }"
        ), "the recorder removes its event monitors on the main thread")

        let uniform = RecorderMotion.resampled(
            [RecorderMotion.Sample(time: 0, point: CGPoint(x: 0, y: 0)),
             RecorderMotion.Sample(time: 1, point: CGPoint(x: 1, y: 1))],
            frameRate: 10, duration: 1)
        expect(uniform.count == 10, "the track is resampled onto the output grid")
        expect(abs(uniform[5].x - 0.5) < 0.01,
               "positions between two samples are interpolated in time")
        expect(RecorderMotion.resampled([], frameRate: 10, duration: 1).count == 10,
               "an empty track still yields a full grid instead of crashing the export")

        // MARK: Screen recorder timeline

        let cutTrim = RecorderSupport.Trim(start: 0, end: 20)
        let oneCut = [RecorderTimeline.Cut(start: 5, end: 8)]
        let kept = RecorderTimeline.keptRanges(trim: cutTrim, cuts: oneCut)
        expect(kept.count == 2 && kept[0] == 0...5 && kept[1] == 8...20,
               "a cut in the middle leaves the two pieces around it")
        expect(abs(RecorderTimeline.outputDuration(trim: cutTrim, cuts: oneCut) - 17) < 0.001,
               "the finished video is shorter by exactly what was cut")
        expect(abs(RecorderTimeline.sourceTime(forOutput: 4, trim: cutTrim, cuts: oneCut) - 4) < 0.001,
               "before the cut the two clocks agree")
        expect(abs(RecorderTimeline.sourceTime(forOutput: 6, trim: cutTrim, cuts: oneCut) - 9) < 0.001,
               "after the cut the recording is ahead of the video by the cut's length")
        expect(RecorderTimeline.outputTime(forSource: 6.5, trim: cutTrim, cuts: oneCut) == nil,
               "a moment that was cut out does not exist in the finished video")
        expect(abs((RecorderTimeline.outputTime(forSource: 12, trim: cutTrim, cuts: oneCut) ?? 0)
                    - 9) < 0.001,
               "a moment after the cut maps back to where it really lands")
        // The two clocks are inverses everywhere the moment survives.
        for step in stride(from: 0.0, through: 17.0, by: 0.37) {
            let source = RecorderTimeline.sourceTime(forOutput: step, trim: cutTrim, cuts: oneCut)
            let back = RecorderTimeline.outputTime(forSource: source, trim: cutTrim, cuts: oneCut)
            expect(abs((back ?? -99) - step) < 0.01,
                   "the recording clock and the video clock are inverses of each other")
        }
        expect(RecorderTimeline.normalized(cuts: [RecorderTimeline.Cut(start: 2, end: 6),
                                                  RecorderTimeline.Cut(start: 5, end: 9)],
                                           duration: 20)
                == [RecorderTimeline.Cut(start: 2, end: 9)],
               "two cuts that touch become one")
        expect(RecorderTimeline.normalized(cuts: [RecorderTimeline.Cut(start: 3, end: 3.02)],
                                           duration: 20).isEmpty,
               "a cut too short to see is not a cut")

        let overlapping = [
            RecorderTimeline.ZoomSegment(start: 1, end: 4, amount: 2),
            RecorderTimeline.ZoomSegment(start: 3, end: 6, amount: 2),
        ]
        let tidy = RecorderTimeline.normalized(segments: overlapping, duration: 20)
        expect(tidy.count == 2 && tidy[0].end <= tidy[1].start + 0.001,
               "two zooms that overlap are pushed apart instead of one being dropped")
        let moved = RecorderTimeline.moved(tidy[1], to: 0, among: tidy, duration: 20)
        expect(moved.start >= tidy[0].end - 0.001,
               "dragging a zoom stops at its neighbour instead of pushing it")
        expect(abs(moved.duration - tidy[1].duration) < 0.001,
               "moving a zoom never changes how long it is")
        let squeezed = RecorderTimeline.resized(tidy[0], edge: .end, to: 1.05,
                                                among: tidy, duration: 20)
        expect(squeezed.duration >= RecorderTimeline.minimumSegment - 1e-9,
               "a zoom cannot be dragged shorter than something you could grab again")
        expect(RecorderTimeline.slotForNewSegment(at: 10, existing: tidy, duration: 20) != nil,
               "there is room for a new zoom in an empty stretch")
        expect(RecorderTimeline.slotForNewSegment(at: 2, existing: tidy, duration: 20)
                .map { $0.start >= tidy[0].end - 0.001 } ?? false,
               "adding a zoom inside another one puts it after that one, never on top")

        let aimed = RecorderTimeline.ZoomSegment(start: 0, end: 3, amount: 2,
                                                 focusX: 0.9, focusY: 0.5)
        let state = RecorderTimeline.zoomState(at: 1.5, segments: [aimed])
        expect(state.progress == 1 && state.amount == 2 && state.focus != nil,
               "in the middle of a zoom it is fully in, at its own strength, aimed where it was put")
        // A hand-aimed spot near the edge must land there, not be pulled in by
        // the calming band the automatic follow uses.
        expect(abs(RecorderMotion.travelParameter(exactFocus: 0.9, zoom: 2) - 1) < 0.001,
               "a spot picked near the edge pins the view to that edge")
        expect(abs(RecorderMotion.travelParameter(exactFocus: 0.5, zoom: 2) - 0.5) < 0.001,
               "a spot picked in the middle keeps the view centred")

        // A pointer parked in a corner fades away, and is back before it
        // moves again. Both halves only work because the whole path is known.
        var parked = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 60 * 8)
        for index in (60 * 6)..<parked.count {
            parked[index] = CGPoint(x: 0.5 + Double(index - 60 * 6) * 0.01, y: 0.5)
        }
        let opacity = RecorderMotion.pointerOpacity(parked, frameRate: 60)
        expect(opacity.count == parked.count, "every frame gets an opacity")
        expect(opacity[10] > 0.95, "a pointer that just stopped is still solid")
        expect(opacity[60 * 5] < 0.05, "a pointer parked for seconds is out of the way")
        expect(opacity[60 * 6] > 0.95, "it is fully back the instant it moves, not after")
        expect(opacity.allSatisfy { $0 >= 0 && $0 <= 1 }, "opacity never leaves its range")
        let alwaysMoving = (0..<120).map { CGPoint(x: Double($0) * 0.01, y: 0.5) }
        expect(RecorderMotion.pointerOpacity(alwaysMoving, frameRate: 60).allSatisfy { $0 > 0.95 },
               "a pointer that keeps moving is never faded")

        // MARK: Screen recorder text

        let caption = RecorderTextOverlay(text: "Hello", start: 2, end: 6)
        expect(caption.opacity(at: 1.9) == 0 && caption.opacity(at: 6.1) == 0,
               "text is not there before it starts or after it ends")
        expect(caption.opacity(at: 4) == 1, "text is solid in the middle of its own time")
        expect(caption.opacity(at: 2.1) > 0 && caption.opacity(at: 2.1) < 1,
               "text eases in instead of appearing on one frame")
        expect(caption.opacity(at: 5.9) > 0 && caption.opacity(at: 5.9) < 1,
               "text eases out the same way")
        let blink = RecorderTextOverlay(text: "Hi", start: 1, end: 1.3)
        expect(blink.opacity(at: 1.15) > 0,
               "a very short caption still gets to be visible at its middle")
        expect(RecorderTextOverlay(text: "x", start: 5, end: 5.05)
                .sanitized(duration: 10) == nil,
               "a caption too short to read is not kept")
        expect(RecorderTextOverlay(text: "x", start: 9, end: 30)
                .sanitized(duration: 10)?.end == 10,
               "a caption that runs past the recording is brought back inside it")
        expect(RecorderTextOverlay(text: "x", start: 1, end: 3, size: 9)
                .sanitized(duration: 10)?.size == RecorderTextOverlay.sizeRange.upperBound,
               "an impossible text size is clamped instead of filling the frame")
        expect(RecorderTextOverlay.Anchor.bottom.unitPoint.y == 1
                && RecorderTextOverlay.Anchor.topLeading.unitPoint == CGPoint(x: 0, y: 0),
               "the nine places mean what they say, counting down from the top")

        // MARK: Screen recorder pictures

        let mark = RecorderImageOverlay(path: "/tmp/logo.png", start: 2, end: 6)
        expect(mark.opacity(at: 1.9) == 0 && mark.opacity(at: 6.1) == 0,
               "a picture is not there before it starts or after it ends")
        expect(mark.opacity(at: 4) == 1,
               "a picture is at full strength in the middle of its own time")
        expect(mark.opacity(at: 2.1) > 0 && mark.opacity(at: 2.1) < 1,
               "a picture eases in like a caption instead of appearing on one frame")
        expectClose(RecorderImageOverlay(path: "/tmp/logo.png", start: 0, end: 10, opacity: 0.5)
                        .opacity(at: 5),
                    0.5,
                    "a picture never goes past the strength it was given")
        expect(RecorderImageOverlay(path: "   ", start: 1, end: 5).sanitized(duration: 10) == nil,
               "a picture with no file behind it is dropped rather than drawn")
        expect(RecorderImageOverlay(path: "/tmp/logo.png", start: 9, end: 30)
                .sanitized(duration: 10)?.end == 10,
               "a picture that runs past the recording is brought back inside it")
        expect(RecorderImageOverlay(path: "/tmp/logo.png", start: 5, end: 5.05)
                .sanitized(duration: 10) == nil,
               "a picture too brief to see is not kept")
        expect(RecorderImageOverlay(path: "/tmp/logo.png", start: 1, end: 5, size: 9)
                .sanitized(duration: 10)?.size == RecorderImageOverlay.sizeRange.upperBound,
               "an impossible picture size is clamped instead of filling the frame")
        expect(RecorderImageOverlay(path: "/tmp/logo.png", start: 1, end: 5, opacity: 0)
                .sanitized(duration: 10)?.opacity == RecorderImageOverlay.opacityRange.lowerBound,
               "a picture turned invisible keeps the least strength that can still be seen")
        expect(RecorderImageOverlay.drawnSize(source: CGSize(width: 200, height: 100),
                                              size: 0.5,
                                              canvas: CGSize(width: 1000, height: 500))
                == CGSize(width: 500, height: 250),
               "a picture is drawn at its share of the frame's width, in its own proportions")
        expect(RecorderImageOverlay.drawnSize(source: CGSize(width: 100, height: 1000),
                                              size: 0.6,
                                              canvas: CGSize(width: 1000, height: 500))
                == CGSize(width: 45, height: 450),
               "a picture taller than the frame is brought down instead of hanging off it")
        for canvas in [CGSize(width: 1000, height: 500), CGSize(width: 500, height: 1000)] {
            for source in [CGSize(width: 100, height: 1000), CGSize(width: 1000, height: 100)] {
                for anchor in RecorderImageOverlay.Anchor.allCases {
                    let drawn = RecorderImageOverlay.drawnSize(source: source, size: 0.6,
                                                                canvas: canvas) ?? .zero
                    let origin = anchor.origin(of: drawn, in: canvas)
                    let margin = min(canvas.width, canvas.height) * 0.05
                    expect(drawn.width > 0 && drawn.height > 0
                            && origin.x >= margin && origin.y >= margin
                            && origin.x + drawn.width <= canvas.width - margin
                            && origin.y + drawn.height <= canvas.height - margin,
                           "the entire picture fits inside its margins at every anchor and aspect")
                }
            }
        }
        expect(RecorderImageOverlay.drawnSize(source: CGSize(width: 10, height: 10),
                                              size: .nan, canvas: CGSize(width: 500, height: 500)) == nil,
               "nonfinite picture geometry cannot reach the renderer")
        expect(RecorderImageOverlay(path: "relative.png", start: 0, end: 2)
                .sanitized(duration: 3) == nil,
               "a damaged picture path never resolves against the app's working directory")
        expect(RecorderImageOverlay(path: "/tmp/picture.png ", start: 0, end: 2)
                .sanitized(duration: 3)?.path == "/tmp/picture.png ",
               "a picked filename keeps its actual whitespace")
        expect(RecorderImageOverlay.drawnSize(source: .zero,
                                              size: 0.2,
                                              canvas: CGSize(width: 1000, height: 500)) == nil,
               "a picture with no size of its own is not drawn")
        expect(RecorderTextOverlay.Anchor.topLeading
                .origin(of: CGSize(width: 100, height: 50),
                        in: CGSize(width: 1000, height: 500)) == CGPoint(x: 25, y: 425),
               "a place keeps its margin off both edges it touches, counting down from the top")
        expect(RecorderTextOverlay.Anchor.bottomTrailing
                .origin(of: CGSize(width: 100, height: 50),
                        in: CGSize(width: 1000, height: 500)) == CGPoint(x: 875, y: 25),
               "the opposite corner keeps the same margin, handed over from the bottom")
        let markedDocument = RecorderEditDocument.decoded(
            RecorderEditDocument(images: [mark]).encoded())
        expect(markedDocument.images == [mark],
               "a picture written next to the recording comes back exactly as it was")
        expect(RecorderEditDocument().affectsPicture(markedDocument)
                && !RecorderEditDocument().affectsTiming(markedDocument)
                && markedDocument.isEdited(duration: 10),
               "adding a picture redraws the preview without rebuilding the timeline, and counts as an edit")
        expect(RecorderEditDocument(images: [RecorderImageOverlay(path: "", start: 1, end: 5)])
                .sanitized(duration: 10).images.isEmpty,
               "a damaged picture is dropped by the same repair that fixes every other field")

        let pictureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-image-test-" + UUID().uuidString, isDirectory: true)
        let pictureTake = RecorderTakeStore.Take(id: UUID(),
                                                  folder: pictureRoot.appendingPathComponent("take"))
        try? FileManager.default.createDirectory(at: pictureTake.folder,
                                                 withIntermediateDirectories: true)
        let pictureSource = pictureRoot.appendingPathComponent("picture.png ")
        let pictureContext = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let picture = pictureContext?.makeImage(),
           let destination = CGImageDestinationCreateWithURL(pictureSource as CFURL,
                                                              "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, picture, nil)
            expect(CGImageDestinationFinalize(destination), "the image import fixture is written")
        } else {
            expect(false, "the image import fixture can be created")
        }
        let originalPictureBytes = try? Data(contentsOf: pictureSource)
        let storedPicture = RecorderTakeStore.shared.importImage(at: pictureSource, into: pictureTake)
        let secondPicture = RecorderTakeStore.shared.importImage(at: pictureSource, into: pictureTake)
        expect(storedPicture != nil && secondPicture != nil && storedPicture != secondPicture,
               "images with the same filename get independent copies inside the recording")
        if let storedPicture {
            expect(MediaSupport.imageThumbnail(at: storedPicture, maxPixel: 2) != nil,
                   "the picked filename is decoded without trimming away meaningful whitespace")
            let attributes = try? FileManager.default.attributesOfItem(atPath: storedPicture.path)
            let permissions = attributes?[.posixPermissions] as? NSNumber
            expect(permissions?.intValue == 0o600,
                   "the private picture copy is readable only by its owner")
            try? Data("replacement".utf8).write(to: pictureSource)
            expect((try? Data(contentsOf: storedPicture)) == originalPictureBytes,
                   "replacing the original leaves the edit's picture unchanged")
            try? FileManager.default.removeItem(at: pictureSource)
            expect((try? Data(contentsOf: storedPicture)) == originalPictureBytes,
                   "removing the original leaves the edit's picture available for export and undo")
        }
        let badPicture = pictureRoot.appendingPathComponent("broken.png")
        try? Data("not an image".utf8).write(to: badPicture)
        let beforeBadImport = try? FileManager.default.contentsOfDirectory(atPath: pictureTake.folder.path)
        expect(RecorderTakeStore.shared.importImage(at: badPicture, into: pictureTake) == nil,
               "an unreadable picture never becomes an invisible timeline block")
        expect((try? FileManager.default.contentsOfDirectory(atPath: pictureTake.folder.path))?
                .sorted() == beforeBadImport?.sorted(),
               "a failed image import leaves no partial file or folder")
        RecorderTakeStore.shared.delete(pictureTake)
        expect(RecorderTakeStore.shared.importImage(at: badPicture, into: pictureTake) == nil
                && !FileManager.default.fileExists(atPath: pictureTake.folder.path),
               "a queued image import cannot recreate a recording after its editor closes")
        expect(FileManager.default.fileExists(atPath: badPicture.path),
               "closing the recording never removes the original picture")
        try? FileManager.default.removeItem(at: pictureRoot)

        // MARK: Screen recorder blur

        let blur = RecorderBlurRegion(start: 2, end: 6,
                                      rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
        expect(blur.covers(2) && blur.covers(4) && blur.covers(6)
                && !blur.covers(1.99) && !blur.covers(6.01),
               "a blur hides its area on every frame of its block and never eases in or out")
        expect(blur.pixelRect(in: CGSize(width: 1000, height: 500))
                == CGRect(x: 100, y: 350, width: 300, height: 50),
               "the area is counted from the top like the screen and handed over from the bottom like Core Image")
        expect(RecorderBlurRegion(start: 1, end: 1.1).sanitized(duration: 10) == nil,
               "a blur too short to matter is not kept")
        expect(RecorderBlurRegion(start: 8, end: 30).sanitized(duration: 10)?.end == 10,
               "a blur that runs past the recording is brought back inside it")
        let spilled = RecorderBlurRegion(start: 1, end: 3,
                                         rect: CGRect(x: -0.2, y: 0.9, width: 0.5, height: 0.5))
            .sanitized(duration: 10)
        expect(spilled.map { abs($0.x) < 1e-9 && abs($0.y - 0.9) < 1e-9
                && abs($0.width - 0.3) < 1e-9 && abs($0.height - 0.1) < 1e-9 } == true,
               "an area drawn past the edge is clamped to the picture instead of reaching outside it")
        expect(RecorderBlurRegion(start: 1, end: 3,
                                  rect: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.2))
                .sanitized(duration: 10) == nil,
               "a line is not an area and is dropped rather than drawn")
        let backwards = RecorderBlurRegion.normalizedRect(from: CGPoint(x: 0.8, y: 0.7),
                                                          to: CGPoint(x: 0.2, y: 0.3))
        expect(backwards.map { abs($0.minX - 0.2) < 1e-9 && abs($0.minY - 0.3) < 1e-9
                && abs($0.width - 0.6) < 1e-9 && abs($0.height - 0.4) < 1e-9 } == true,
               "a drag in any direction produces the same area")
        expect(RecorderBlurRegion.normalizedRect(from: CGPoint(x: 0.5, y: 0.5),
                                                 to: CGPoint(x: 0.502, y: 0.9)) == nil,
               "a drag too thin to be seen leaves the blur where it was")
        expect(RecorderBlurRegion(start: 0, end: 5).rect == RecorderBlurRegion.defaultRect,
               "a new blur lands in the middle until its area is drawn")
        expect(RecorderSupport.blurBlockSize(for: CGSize(width: 300, height: 24)) == 8
                && RecorderSupport.blurBlockSize(for: CGSize(width: 600, height: 90)) == 30
                && RecorderSupport.blurBlockSize(for: CGSize(width: 900, height: 900)) == 48,
               "the mosaic is coarser than one line of text and never turns a big area into four squares")
        let blurredDocument = RecorderEditDocument.decoded(
            RecorderEditDocument(blurs: [blur]).encoded())
        expect(blurredDocument.blurs == [blur],
               "a blur written next to the recording comes back exactly as it was")
        expect(RecorderEditDocument().affectsPicture(blurredDocument)
                && !RecorderEditDocument().affectsTiming(blurredDocument)
                && blurredDocument.isEdited(duration: 10),
               "adding a blur redraws the preview without rebuilding the timeline, and counts as an edit")
        expect(RecorderEditDocument(blurs: [RecorderBlurRegion(start: 4, end: 4.05)])
                .sanitized(duration: 10).blurs.isEmpty,
               "a damaged blur is dropped by the same repair that fixes every other field")

        // The stage letterboxes the picture; a point on it has to come off
        // the empty bands before it means anything in the recording.
        let stagePoint = RecorderSupport.unitPoint(at: CGPoint(x: 300, y: 250),
                                                   in: CGSize(width: 500, height: 500),
                                                   sourceSize: CGSize(width: 1000, height: 500))
        expect(stagePoint.map { abs($0.x - 0.6) < 1e-9 && abs($0.y - 0.5) < 1e-9 } == true,
               "a point on the stage maps through the letterbox into the picture's own space")
        expect(RecorderSupport.unitPoint(at: CGPoint(x: 10, y: 10),
                                         in: CGSize(width: 500, height: 500),
                                         sourceSize: CGSize(width: 1000, height: 500))?.y ?? 0 < 0,
               "a point in the letterbox band comes back outside the picture rather than snapped into it")
        expect(RecorderSupport.unitPoint(at: .zero, in: .zero, sourceSize: .zero) == nil,
               "a stage with no size maps nothing")

        // MARK: Screen recorder pointer track

        let trackRoundTrip = RecorderPointerTrack.decoded(
            RecorderPointerTrack(
                samples: [RecorderMotion.Sample(time: 0.5, point: CGPoint(x: 0.25, y: 0.75))],
                clicks: [RecorderMotion.Click(time: 1.5, isDown: true)],
                systemScale: 2).encoded())
        expect(trackRoundTrip.samples.count == 1 && trackRoundTrip.clicks.count == 1
                && trackRoundTrip.systemScale == 2,
               "a pointer track survives being written and read back")
        expect(abs(trackRoundTrip.samples[0].point.x - 0.25) < 1e-6
                && trackRoundTrip.clicks[0].isDown,
               "the positions and the presses come back as they went in")
        let truncated = RecorderPointerTrack(
            samples: (0..<50).map {
                RecorderMotion.Sample(time: Double($0), point: CGPoint(x: 0.5, y: 0.5))
            }).encoded().prefix(120)
        expect(!RecorderPointerTrack.decoded(Data(truncated)).samples.isEmpty,
               "a track cut short by a crash still gives back everything it did write")
        expect(RecorderPointerTrack.decoded(Data("nonsense".utf8)).isEmpty,
               "an unrelated file is not mistaken for a pointer track")
        expect(RecorderPointerTrack.decoded(nil).isEmpty,
               "a recording with no track at all reads as no track")

        let pointerShape = RecorderPointerTrack.CursorShape(
            png: Data([1, 2, 3]), hotSpot: CGPoint(x: 2, y: 3),
            pointSize: CGSize(width: 16, height: 24))
        let shapedTrack = RecorderPointerTrack(
            samples: trackRoundTrip.samples, clicks: trackRoundTrip.clicks,
            shapes: [pointerShape, pointerShape], systemScale: 2)
        expect(RecorderPointerTrack.decoded(shapedTrack.encoded()) == shapedTrack,
               "bounding shape allocation preserves complete pointer tracks")
        let partialShapes = RecorderPointerTrack.decoded(shapedTrack.encoded().dropLast())
        expect(partialShapes.shapes == [pointerShape]
                && partialShapes.samples == shapedTrack.samples
                && partialShapes.clicks == shapedTrack.clicks,
               "a truncated pointer image preserves earlier complete shapes, samples and clicks")
        var oversizedShapeCount = RecorderPointerTrack().encoded()
        oversizedShapeCount.replaceSubrange(24..<28, with: [0, 0, 1, 0])
        let emptyShapeTrack = RecorderPointerTrack.decoded(oversizedShapeCount)
        expect(emptyShapeTrack.shapes.isEmpty && emptyShapeTrack.shapes.capacity == 0,
               "a header declaring many absent pointer images reserves no shape storage")
        var overstatedShapes = shapedTrack.encoded()
        overstatedShapes.replaceSubrange(24..<28, with: [0, 0, 1, 0])
        let boundedShapeTrack = RecorderPointerTrack.decoded(overstatedShapes)
        expect(boundedShapeTrack == shapedTrack
                && boundedShapeTrack.shapes.capacity <= overstatedShapes.count / 20,
               "an overstated image count keeps complete records without reserving the claimed capacity")

        // MARK: Screen recorder canvas

        let plainCanvas = RecorderSupport.canvasSize(source: CGSize(width: 960, height: 640),
                                                     padding: 0, aspect: .original)
        expect(plainCanvas == CGSize(width: 960, height: 640),
               "with no margin and no shape the canvas is the recording itself")
        let padded = RecorderSupport.canvasSize(source: CGSize(width: 960, height: 640),
                                                padding: 0.1, aspect: .original)
        expect(padded.width > 960 && padded.height > 640,
               "a margin grows the canvas instead of shrinking the recording")
        let wide = RecorderSupport.canvasSize(source: CGSize(width: 640, height: 640),
                                              padding: 0,
                                              aspect: .wide,
                                              cropsToAspect: true)
        expect(abs(wide.width / wide.height - 16.0 / 9.0) < 0.02,
               "a shape preset gives the canvas that shape")
        expect(wide.width <= 640 && wide.height <= 640,
               "a shape without a background crops inside the source instead of adding bars")
        let framedWide = RecorderSupport.canvasSize(source: CGSize(width: 640, height: 640),
                                                    padding: 0,
                                                    aspect: .wide)
        expect(framedWide.width > 640,
               "a shape with a background grows around the source instead of cropping it")
        let huge = RecorderSupport.canvasSize(source: CGSize(width: 6000, height: 4000),
                                              padding: 0.3, aspect: .original)
        expect(max(huge.width, huge.height) <= RecorderSupport.maximumCanvasEdge,
               "no background can ask for a picture bigger than the ceiling")

        let card = RecorderSupport.cardRect(canvas: CGSize(width: 1200, height: 800),
                                            source: CGSize(width: 960, height: 640),
                                            padding: 0.1)
        expect(abs(card.width / card.height - 960.0 / 640.0) < 0.01,
               "the recording keeps its own proportions inside the canvas")
        expect(abs(card.midX - 600) < 1 && abs(card.midY - 400) < 1,
               "the recording is centred in the canvas")
        expect(card.minX >= 0 && card.maxX <= 1200 && card.minY >= 0 && card.maxY <= 800,
               "the recording never hangs off the canvas")
        let squareCrop = RecorderSupport.cardRect(canvas: CGSize(width: 640, height: 640),
                                                  source: CGSize(width: 960, height: 640),
                                                  padding: 0,
                                                  fillsCanvas: true)
        expect(squareCrop.height == 640 && squareCrop.width == 960 && squareCrop.minX == -160,
               "a centred crop covers the chosen shape and clips equal excess from both sides")
        let rotatedGeometry = RecorderSupport.videoGeometry(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2))
        let rotatedRect = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
            .applying(rotatedGeometry.transform)
        expect(rotatedGeometry.size == CGSize(width: 1080, height: 1920),
               "an imported rotated video uses its displayed portrait dimensions")
        expect(abs(rotatedRect.minX) < 0.001 && abs(rotatedRect.minY) < 0.001,
               "an imported video transform is normalized to the output origin")
        expect(RecorderSupport.videoGeometry(naturalSize: .zero,
                                             preferredTransform: .identity).size == .zero,
               "missing video dimensions stay invalid instead of becoming an artificial frame")

        expect(RecorderSupport.sanitizedZoomAmount(99) == RecorderSupport.zoomAmountRange.upperBound
                && RecorderSupport.sanitizedZoomAmount(.nan) == 1.8,
               "a broken zoom amount falls back instead of magnifying to nothing")
        let visibleTrack = RecorderPointerTrack.decoded(
            RecorderPointerTrack(samples: [
                RecorderMotion.Sample(time: 0, point: .zero, isPointerVisible: true),
                RecorderMotion.Sample(time: 1, point: .zero, isPointerVisible: false),
            ]).encoded())
        expect(visibleTrack.samples.count == 2
                && visibleTrack.samples[0].isPointerVisible
                && !visibleTrack.samples[1].isPointerVisible,
               "whether the system was showing a pointer survives the round trip")
        expect(RecorderMotion.resampledVisibility(visibleTrack.samples,
                                                  frameRate: 4, duration: 2)
                == [true, true, true, true, false, false, false, false],
               "a stretch where the system hid the pointer stays hidden in the video")

        let studio = RecorderEditDocument().applying(.studio)
        expect(studio.zoomEnabled && studio.showsPointer && !studio.backdrop.isEmpty,
               "the studio look turns on everything it promises")
        let bare = RecorderEditDocument().applying(.raw)
        expect(!bare.zoomEnabled && !bare.showsClickRing && bare.backdrop.isEmpty,
               "the raw look leaves the recording exactly as it was")
        expect(bare.showsPointer && bare.resolvedSmoothing == .off,
               "raw still draws the pointer, because the capture itself has none, but eases nothing")
        expect(RecorderEditDocument().applying(.clean).zoomEnabled
                && RecorderEditDocument().applying(.clean).backdrop.isEmpty,
               "the clean look smooths and zooms without putting anything behind it")

        let takeID = UUID()
        expect(RecorderSupport.takeID(fromFolderName: RecorderSupport.takeFolderName(id: takeID))
                == takeID,
               "a recording folder name round-trips its id")
        expect(RecorderSupport.takeID(fromFolderName: "Downloads") == nil,
               "an unrelated folder is never mistaken for a recording")
    }
}
