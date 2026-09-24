// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum AppManagementFeatureTests {
    static func run(_ suite: TestSuite) {
        let registeredDefaults = Defaults.registeredDefaults
        suite.expect(registeredDefaults[DefaultsKey.extraBrightnessEnabled] as? Bool == false,
               "extra brightness is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.extraBrightnessLevel] as? Int == 100,
               "extra brightness starts at full intensity once enabled")
        suite.expect(registeredDefaults[DefaultsKey.bluetoothSleepEnabled] as? Bool == false,
               "switching Bluetooth off on sleep is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.bluetoothSleepRestoreOnWake] as? Bool == true,
               "an enabled Bluetooth sleep feature puts Bluetooth back on wake")
        suite.expect(registeredDefaults[DefaultsKey.bluetoothSleepRestorePending] as? Bool == false,
               "no Bluetooth restore is owed before the first sleep")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.bluetoothSleepRestorePending),
               "a Bluetooth restore owed by one sleeping Mac never travels to another")
        suite.expect(registeredDefaults[DefaultsKey.musicBlockEnabled] as? Bool == false,
               "blocking the music app from launching is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.musicBlockReplacementPath] as? String == "",
               "the music replacement app starts unset")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityCleaner] as? Bool == true,
               "the cleaner row is visible in the panel utilities like its siblings")
        suite.expect(registeredDefaults[DefaultsKey.cleanerScheduleFrequency] as? String == "off",
               "automatic cleanup is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.cleanerScheduleHour] as? Int == 9
               && registeredDefaults[DefaultsKey.cleanerScheduleMinute] as? Int == 0
               && registeredDefaults[DefaultsKey.cleanerScheduleWeekday] as? Int == 2,
               "the schedule defaults to nine in the morning on Mondays")
        suite.expect(registeredDefaults[DefaultsKey.cleanerScheduleNotify] as? Bool == true,
               "the schedule reports its outcome unless the user opts out")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppDownloadsEnabled] as? Bool == false,
               "WhatsApp downloads stay hidden until the user turns them on")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppDownloadsAutomaticEnabled] as? Bool == false,
               "WhatsApp automatic cleanup is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppDownloadsCategories] as? String
               == "image,video,audio",
               "WhatsApp cleanup starts with conservative media categories")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppDownloadsRetentionDays] as? Int == 7,
               "WhatsApp downloads keep a seven day default window")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppDownloadsAccessConfirmed] as? Bool == false,
               "WhatsApp cleanup never probes Downloads in the background before explicit access")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppOrganizerEnabled] as? Bool == false,
               "the experimental WhatsApp organizer is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.whatsAppOrganizerDelayMinutes] as? Int == 5
                && registeredDefaults[DefaultsKey.whatsAppOrganizerLayout] as? String == "flat"
                && registeredDefaults[DefaultsKey.whatsAppOrganizerDuplicateAction] as? String
                    == "trashNew",
               "the organizer starts with a five minute grace period and safe duplicate policy")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func scheduleDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: day,
                                                  hour: hour, minute: minute)) ?? Date()
        }
        suite.expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 8, 0), frequency: .daily,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(9, 9, 0),
               "a daily schedule still due today fires today")
        suite.expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .daily,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(10, 9, 0),
               "a daily schedule already past fires tomorrow")
        suite.expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .weekly,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(13, 9, 0),
               "a weekly Monday schedule queried on Thursday fires next Monday")
        suite.expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .off,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == nil,
               "an off schedule never fires")
        suite.expect(CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0),
                                         lastRun: scheduleDate(8, 9, 30),
                                         frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                         calendar: utcCalendar),
               "a fire that passed while the Mac was off counts as missed")
        suite.expect(!CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0),
                                          lastRun: scheduleDate(9, 9, 30),
                                          frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                          calendar: utcCalendar),
               "a run that already happened today is not missed")
        suite.expect(!CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0), lastRun: nil,
                                          frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                          calendar: utcCalendar),
               "enabling the schedule never triggers a surprise first run")
        suite.expect(CleanerSchedule.hour24(hour12: 12, isPM: false) == 0
               && CleanerSchedule.hour24(hour12: 12, isPM: true) == 12
               && CleanerSchedule.hour24(hour12: 1, isPM: true) == 13
               && CleanerSchedule.hour24(hour12: 11, isPM: false) == 11,
               "twelve hour picks map to the right clock hours, midnight and noon included")
        suite.expect(CleanerSchedule.hour12Components(fromHour24: 0) == (12, false)
               && CleanerSchedule.hour12Components(fromHour24: 12) == (12, true)
               && CleanerSchedule.hour12Components(fromHour24: 18) == (6, true)
               && CleanerSchedule.hour12Components(fromHour24: 9) == (9, false),
               "clock hours split back into the twelve hour pickers")
        suite.expect((0...23).allSatisfy { hour in
                   let parts = CleanerSchedule.hour12Components(fromHour24: hour)
                   return CleanerSchedule.hour24(hour12: parts.hour12, isPM: parts.isPM) == hour
               },
               "every hour of the day round trips through the twelve hour pickers")

        // MARK: WhatsApp downloads

        let whatsAppEnabledSuite = "vorss.tests.whatsapp.enabled"
        if let migrationDefaults = UserDefaults(suiteName: whatsAppEnabledSuite) {
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil,
                   "an untouched setup keeps WhatsApp downloads off by leaving the new switch unset")
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "an existing automatic WhatsApp cleanup keeps its Cleaner surface")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppOrganizerEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "an existing WhatsApp organizer keeps its Cleaner surface")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil,
                   "only opening Downloads does not keep the WhatsApp Cleaner surface")
            migrationDefaults.set(false, forKey: DefaultsKey.whatsAppDownloadsEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            suite.expect(!migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "the WhatsApp downloads migration preserves a newer off choice")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
        } else {
            suite.expect(false, "WhatsApp downloads migration suite can be created")
        }
        suite.expect(WhatsAppDownloadSupport.isWhatsAppAgent("WhatsApp")
                && WhatsAppDownloadSupport.isWhatsAppAgent(" whatsapp ")
                && !WhatsAppDownloadSupport.isWhatsAppAgent("SomeBrowser")
                && !WhatsAppDownloadSupport.isWhatsAppAgent(nil),
               "only an explicit WhatsApp quarantine agent is trusted")
        suite.expect(WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.jpeg",
                                                 extension: "jpeg") == .image
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.mpeg-4",
                                                     extension: "mp4") == .video
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.mp3",
                                                     extension: "mp3") == .audio
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: "com.adobe.pdf",
                                                     extension: "pdf") == .document
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: nil,
                                                     extension: "zip") == .archive,
               "WhatsApp files land in the expected user-facing buckets")
        suite.expect(WhatsAppDownloadSupport.isIncompleteFile(extension: "download")
                && WhatsAppDownloadSupport.isIncompleteFile(extension: "PART")
                && !WhatsAppDownloadSupport.isIncompleteFile(extension: "pdf"),
               "partial downloads can never become cleanup candidates")
        let whatsNow = scheduleDate(20, 12, 0)
        let whatsOld = scheduleDate(10, 12, 0)
        let whatsRecent = scheduleDate(19, 12, 0)
        suite.expect(WhatsAppDownloadSupport.isOldEnough(downloadedAt: whatsOld,
                                                   modifiedAt: whatsOld,
                                                   now: whatsNow, retentionDays: 7,
                                                   calendar: utcCalendar),
               "an untouched old WhatsApp download passes retention")
        suite.expect(!WhatsAppDownloadSupport.isOldEnough(downloadedAt: whatsOld,
                                                    modifiedAt: whatsRecent,
                                                    now: whatsNow, retentionDays: 7,
                                                    calendar: utcCalendar),
               "a recent edit postpones WhatsApp cleanup")
        suite.expect(!WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
                    category: .image, downloadedAt: whatsOld, modifiedAt: whatsOld,
                    now: whatsNow, retentionDays: 7, enabledCategories: [.image],
                    includeExisting: false, automaticStartDate: whatsRecent),
               "future-only automation leaves pre-existing downloads alone")
        suite.expect(WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
                    category: .image, downloadedAt: whatsOld, modifiedAt: whatsOld,
                    now: whatsNow, retentionDays: 7, enabledCategories: [.image],
                    includeExisting: true, automaticStartDate: whatsRecent),
               "explicitly including existing downloads admits old matches")
        let downloadsRoot = URL(fileURLWithPath: "/Users/test/Downloads")
        suite.expect(WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Downloads/file.pdf"), of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Downloads/folder/file.pdf"), of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Documents/file.pdf"), of: downloadsRoot),
               "WhatsApp cleanup accepts only direct children of Downloads")
        let organizedFile = URL(fileURLWithPath: "/Users/test/Downloads/WhatsApp/2026/07/file.pdf")
        suite.expect(WhatsAppDownloadSupport.isDescendant(organizedFile, of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDescendant(downloadsRoot, of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDescendant(
                    URL(fileURLWithPath: "/Users/test/Download/file.pdf"), of: downloadsRoot),
               "organized cleanup accepts descendants without path-prefix confusion")
        let fourMinutesAgo = whatsNow.addingTimeInterval(-4 * 60)
        let sixMinutesAgo = whatsNow.addingTimeInterval(-6 * 60)
        suite.expect(!WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: sixMinutesAgo, modifiedAt: fourMinutesAgo,
                    now: whatsNow, delayMinutes: 5)
                && WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: sixMinutesAgo, modifiedAt: sixMinutesAgo,
                    now: whatsNow, delayMinutes: 5)
                && WhatsAppDownloadSupport.sanitizedOrganizerDelayMinutes(999) == 5,
               "organization waits for both download and modification activity to settle")
        let undoCreatedAt = whatsNow.addingTimeInterval(-6 * 86_400)
        suite.expect(WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: undoCreatedAt, now: whatsNow)
                && !WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: whatsNow.addingTimeInterval(-7 * 86_400), now: whatsNow)
                && !WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: whatsNow.addingTimeInterval(1), now: whatsNow),
               "organizer undo is executable only during its seven day window")
        suite.expect(WhatsAppDownloadSupport.organizerRelativeComponents(
                    layout: .flat, category: .image, date: whatsNow,
                    calendar: utcCalendar).isEmpty
                && WhatsAppDownloadSupport.organizerRelativeComponents(
                    layout: .category, category: .image, date: whatsNow,
                    calendar: utcCalendar) == ["Images"]
                && WhatsAppDownloadSupport.organizerRelativeComponents(
                    layout: .month, category: .image, date: whatsNow,
                    calendar: utcCalendar) == ["2026", "07"],
               "the organizer produces stable flat, type and month folder layouts")
        let volumeA = NSData(bytes: [0x67, 0x45, 0x64, 0x00] as [UInt8], length: 4)
        let volumeB = NSData(bytes: [0x69, 0x98, 0x66, 0x00] as [UInt8], length: 4)
        suite.expect(WhatsAppDownloadSupport.isSameVolume(
                    source: volumeA,
                    destination: NSData(bytes: [0x67, 0x45, 0x64, 0x00] as [UInt8], length: 4)),
               "two equal volume identifiers are one volume even as separate objects")
        suite.expect(!WhatsAppDownloadSupport.isSameVolume(source: volumeA, destination: volumeB),
               "two different volume identifiers never skip the destination check")
        suite.expect(!WhatsAppDownloadSupport.isSameVolume(source: NSNumber(value: 1),
                                                     destination: NSString(string: "1")),
               "unequal identities that print the same string still take the verified path")
        suite.expect(!WhatsAppDownloadSupport.isSameVolume(source: volumeA, destination: nil)
                && !WhatsAppDownloadSupport.isSameVolume(source: nil, destination: volumeB)
                && !WhatsAppDownloadSupport.isSameVolume(source: nil, destination: nil),
               "an unknown volume identity keeps the verified copy rather than an unchecked rename")
        suite.expect(WhatsAppDownloadSupport.nextAutomaticCheck(
                    after: scheduleDate(20, 8, 0), calendar: utcCalendar) == scheduleDate(20, 9, 0)
                && WhatsAppDownloadSupport.nextAutomaticCheck(
                    after: scheduleDate(20, 10, 0), calendar: utcCalendar) == scheduleDate(21, 9, 0),
               "the hidden daily WhatsApp check targets nine in the morning")
        suite.expect(WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 12, 0), lastRun: scheduleDate(19, 9, 0),
                    calendar: utcCalendar)
                && !WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 8, 0), lastRun: scheduleDate(19, 9, 0),
                    calendar: utcCalendar)
                && !WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 12, 0), lastRun: nil, calendar: utcCalendar),
               "missed WhatsApp checks recover after nine without a first-enable surprise")
        let panel500 = ExtraBrightnessSupport.panelReference(model: "MacBookPro18,1")
        let panel600 = ExtraBrightnessSupport.panelReference(model: "Mac16,7")
        suite.expect(panel500.referenceEDR == 3.2 && panel500.bonus == 0.58,
               "the 2021/2023 500 nit panels take the stronger curve")
        suite.expect(panel600.referenceEDR == 2.66 && panel600.bonus == 0.48,
               "600 nit panels from M3 onwards take the gentler curve")
        suite.expect(ExtraBrightnessSupport.panelReference(model: "Mac99,9").bonus == 0.48
               && ExtraBrightnessSupport.panelReference(model: nil).bonus == 0.48,
               "unknown and future models fall back to the conservative curve")
        suite.expect(ExtraBrightnessSupport.boostFactor(level: 0, maxEDR: 2.66, reference: panel600) == 1.0,
               "zero level applies no brightness boost")
        suite.expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 2.66, reference: panel600) - 1.48) < 0.0001,
               "full level on a 600 nit panel tops out at the sustainable 1.48x")
        suite.expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 16.0, reference: panel600) - 1.48) < 0.0001,
               "huge reported headroom never pushes past what the panel sustains")
        suite.expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 3.2, reference: panel500) - 1.58) < 0.0001,
               "full level on a 500 nit panel tops out at 1.58x")
        suite.expect(abs(ExtraBrightnessSupport.boostFactor(level: 1, maxEDR: 1.33, reference: panel600) - 1.24) < 0.0001,
               "a partial headroom grant scales the boost down proportionally")
        suite.expect(abs(ExtraBrightnessSupport.boostFactor(level: 0.5, maxEDR: 2.66, reference: panel600) - 1.24) < 0.0001,
               "half level applies half the panel bonus")
        suite.expect(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 1.0, potentialEDR: 16.0,
                                                   reference: panel600)
               == ExtraBrightnessSupport.engagementFactor,
               "before the panel engages, the overlay shows only the small engagement boost")
        suite.expect(abs(ExtraBrightnessSupport.renderFactor(level: 0.1, currentEDR: 1.0, potentialEDR: 16.0,
                                                       reference: panel600) - 1.048) < 0.0001,
               "the engagement nudge never exceeds the level's own target")
        suite.expect(abs(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 2.66, potentialEDR: 16.0,
                                                       reference: panel600) - 1.48) < 0.0001,
               "with the reference headroom engaged the full level renders the full bonus")
        suite.expect(ExtraBrightnessSupport.renderFactor(level: 0, currentEDR: 2.66, potentialEDR: 16.0,
                                                   reference: panel600) == 1.0,
               "zero level renders no boost even with headroom engaged")
        suite.expect(abs(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 1.2, potentialEDR: 16.0,
                                                       reference: panel600) - 1.2) < 0.0001,
               "the rendered factor never exceeds the headroom macOS is granting right now")
        suite.expect(ExtraBrightnessSupport.renderFactor(level: 1, currentEDR: 1.0, potentialEDR: 1.0,
                                                   reference: panel600) == 1.0,
               "a mode without any potential headroom gets no boost attempt at all")
        for model in ["MacBookPro18,1", "MacBookPro18,4", "Mac14,5", "Mac14,10",
                      "Mac15,3", "Mac15,11", "Mac16,1", "Mac16,7", "Mac17,2", "Mac17,9"] {
            suite.expect(ExtraBrightnessSupport.isSupportedPanel(model: model,
                                                           localizedName: "Built-in Retina Display",
                                                           potentialEDR: 2.0),
                   "\(model) is a MacBook Pro with an XDR panel, whatever the screen reports")
        }
        for model in ["Mac16,12", "Mac16,13", "Mac15,12", "Mac14,2", "Mac14,7",
                      "Mac17,3", "MacBookPro17,1", "Mac16,2"] {
            suite.expect(!ExtraBrightnessSupport.isSupportedPanel(model: model,
                                                            localizedName: "Built-in Retina Display",
                                                            potentialEDR: 2.0),
                   "\(model) has no XDR panel and its fake 2x headroom does not qualify")
        }
        suite.expect(ExtraBrightnessSupport.isSupportedPanel(model: "Mac99,1",
                                                       localizedName: "Built-in Display",
                                                       potentialEDR: 16.0),
               "future XDR MacBooks qualify by real headroom without a model list update")
        suite.expect(!ExtraBrightnessSupport.isSupportedPanel(model: nil,
                                                        localizedName: "Built-in Retina Display",
                                                        potentialEDR: 1.0),
               "unknown model without headroom or an XDR name stays unsupported")
        suite.expect(ExtraBrightnessSupport.isSupportedPanel(model: nil,
                                                       localizedName: "Liquid Retina XDR Display",
                                                       potentialEDR: 1.0),
               "an explicit XDR product name is accepted even without other signals")
        suite.expect(ExtraBrightnessSupport.isXDRPanelName("Built-in Liquid Retina XDR Display")
               && ExtraBrightnessSupport.isXDRPanelName("Liquid Retina XDR"),
               "the XDR token is recognized wherever a product name exposes it")
        suite.expect(!ExtraBrightnessSupport.isXDRPanelName("Built-in Liquid Retina Display")
               && !ExtraBrightnessSupport.isXDRPanelName("Built-in Retina Display"),
               "generic built-in panel names do not qualify by name")
        suite.expect(abs(ExtraBrightnessSupport.rampedFactor(previous: 1.0, target: 1.48) - 1.03) < 0.0001,
               "the factor climbs one small step per tick")
        suite.expect(ExtraBrightnessSupport.rampedFactor(previous: 1.46, target: 1.48) == 1.48,
               "the last upward step lands exactly on the target")
        suite.expect(abs(ExtraBrightnessSupport.rampedFactor(previous: 1.48, target: 1.10) - 1.385) < 0.0001,
               "downward moves take a share of the gap, never the whole drop at once")
        suite.expect(ExtraBrightnessSupport.rampedFactor(previous: 1.105, target: 1.10) == 1.10,
               "tiny downward gaps snap to the target instead of hovering")
        suite.expect(ExtraBrightnessSupport.rampedFactor(previous: 1.48, target: 1.48) == 1.48,
               "a settled factor stays put")
        suite.expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.48,
                                                   engaged: false, disengagedTicks: 1) == 1.48
               && ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.48,
                                                      engaged: false,
                                                      disengagedTicks: ExtraBrightnessSupport.dropoutGraceTicks) == 1.48,
               "a grant that just vanished keeps the previous factor through the grace window")
        suite.expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.48,
                                                   engaged: false,
                                                   disengagedTicks: ExtraBrightnessSupport.dropoutGraceTicks + 1) == 1.10,
               "a dropout that outlives the grace window is believed")
        suite.expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.40, previous: 1.48,
                                                   engaged: true, disengagedTicks: 0) == 1.40,
               "an engaged reading is always taken at face value")
        suite.expect(ExtraBrightnessSupport.gracedTarget(instantaneous: 1.10, previous: 1.0,
                                                   engaged: false, disengagedTicks: 1) == 1.10,
               "grace never lifts a factor that had no boost to protect")
        suite.expect(ExtraBrightnessSupport.canReuseSpaceWindows(
                   sameDisplay: true, overlayOnActiveSpace: true, triggerOnActiveSpace: true),
               "fullscreen handoff keeps the live overlay pair when both windows followed")
        suite.expect(!ExtraBrightnessSupport.canReuseSpaceWindows(
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
            suite.expect(ebFactor == 1.48,
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
        suite.expect(ebDrop >= 1.10 && ebDrop < 1.13 && ebBiggestStep < 0.0951,
               "a real revocation ramps the boost down over seconds without one visible slam")
        var ebWobble = 1.48
        var ebWobbleStep = 0.0
        for tick in 0..<20 {
            let ebNext = ExtraBrightnessSupport.rampedFactor(previous: ebWobble,
                                                             target: tick % 4 < 2 ? 1.48 : 1.40)
            ebWobbleStep = max(ebWobbleStep, abs(ebNext - ebWobble))
            ebWobble = ebNext
            suite.expect(ebWobble >= 1.40 && ebWobble <= 1.48,
                   "a wobbling grant keeps the factor inside the grant's own range")
        }
        suite.expect(ebWobbleStep < 0.0301,
               "a wobbling grant moves the factor in imperceptible steps, not flashes")
        var ebGlide = 1.0
        for _ in 0..<16 { ebGlide = ExtraBrightnessSupport.rampedFactor(previous: ebGlide, target: 1.48) }
        suite.expect(ebGlide == 1.48,
               "switching the boost on glides to full strength within about four seconds")
        suite.expect(CleanerSupport.isProtectedBundleID("com.apple.Music")
               && CleanerSupport.isProtectedBundleID("com.apple")
               && CleanerSupport.isProtectedBundleID("group.com.apple.notes")
               && CleanerSupport.isProtectedBundleID("com.vorssaint.utils"),
               "system domains and this app can never be junk owners")
        suite.expect(!CleanerSupport.isProtectedBundleID("com.vendor.editor"),
               "third party identifiers are eligible for the leftover check")
        suite.expect(UninstallerSupport.verifiedBundleID("com.vendor.editor") == "com.vendor.editor"
               && UninstallerSupport.verifiedBundleID("com.vendor.editor.helper") == "com.vendor.editor.helper"
               && UninstallerSupport.verifiedBundleID("test.editor") == "test.editor"
               && UninstallerSupport.verifiedBundleID("editor.test") == "editor.test",
               "the uninstaller accepts exact third party bundle identifiers, two-component IDs, and embedded helpers")
        suite.expect(UninstallerSupport.verifiedBundleID(nil) == nil
               && UninstallerSupport.verifiedBundleID("") == nil
               && UninstallerSupport.verifiedBundleID("plain-name") == nil
               && UninstallerSupport.verifiedBundleID("com.vendor../escape") == nil
               && UninstallerSupport.verifiedBundleID("com.vorssaint.utils") == nil
               && UninstallerSupport.verifiedBundleID("com.apple.system") == nil,
               "malformed, protected and current app identifiers never enter uninstall paths")
        let uninstallAppURL = URL(fileURLWithPath: "/Applications/Editor.app")
        suite.expect(UninstallerSupport.isNestedBundle(
                   URL(fileURLWithPath: "/Applications/Editor.app/Contents/Library/LoginItems/Background.app"),
                   in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(uninstallAppURL, in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(
                   URL(fileURLWithPath: "/Applications/Editor.app-copy/Contents/Background.app"),
                   in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(nil, in: uninstallAppURL),
               "the uninstaller stops only background apps nested inside the selected bundle")
        suite.expect(!UninstallerSupport.sharedDataIsExclusive(
            selectedURL: URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"),
            bundleID: "com.vendor.editor",
            knownApplications: [
                (URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"), "com.vendor.editor"),
                (URL(fileURLWithPath: "/Applications/Editor.app"), "com.vendor.editor"),
            ])
            && UninstallerSupport.sharedDataIsExclusive(
                selectedURL: URL(fileURLWithPath: "/Applications/Editor.app"),
                bundleID: "com.vendor.editor",
                knownApplications: [
                    (URL(fileURLWithPath: "/Applications/Editor.app"), "com.vendor.editor"),
                    (URL(fileURLWithPath: "/Applications/Other.app"), "com.vendor.other"),
                ]),
               "shared app data is eligible only when no other installed copy owns the bundle identifier")
        suite.expect(UninstallerSupport.sharedDataIsExclusive(
            selectedURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            bundleID: "com.vendor.editor.helper",
            knownApplications: [
                (URL(fileURLWithPath: "/Applications/Editor.app/Contents/Helpers/Helper.app"),
                 "com.vendor.editor.helper"),
            ])
            && UninstallerSupport.applicationIsInTrustedInstallRoot(
                URL(fileURLWithPath: "/Applications/Editor.app"),
                home: URL(fileURLWithPath: "/Users/test"))
            && !UninstallerSupport.applicationIsInTrustedInstallRoot(
                URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"),
                home: URL(fileURLWithPath: "/Users/test")),
               "embedded helpers belong to the selected app while unregistered download copies never own shared data")
        let uninstallCandidateIDs: Set<String> = ["com.vendor.editor", "com.vendor.editor.helper"]
        suite.expect(UninstallerSupport.exclusiveBundleIDs(
                   uninstallCandidateIDs,
                   selectedURL: uninstallAppURL,
                   knownApplications: []) == uninstallCandidateIDs
               && UninstallerSupport.exclusiveBundleIDs(
                   uninstallCandidateIDs,
                   selectedURL: uninstallAppURL,
                   knownApplications: [
                       (URL(fileURLWithPath: "/Applications/Other.app"),
                        "com.vendor.editor.helper"),
                   ]) == ["com.vendor.editor"],
               "package removal preserves helper candidates while excluding an owner installed elsewhere")
        let uninstallIDs: Set<String> = ["com.vendor.editor", "com.vendor.editor.helper"]
        let leftoverIdentity = UninstallerSupport.identity(
            bundleIDs: uninstallIDs, displayNames: ["Editor", "Editor.app"])
        suite.expect(leftoverIdentity.nameTokens.contains("editor")
               && !leftoverIdentity.nameTokens.contains("helper"),
               "display names become match tokens and helper suffixes do not")
        suite.expect(UninstallerSupport.leftoverMatch("Editor", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch("com.vendor.editor.plist", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist",
                   identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("COM.VENDOR.EDITOR.PLIST", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("Editor.prefPane", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "ABCD123456.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "group.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.wrapper.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch("Google", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch("com.vendor.editor2", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.extra", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.helper.plist", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("Editorial", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch("Editor/Nested", identity: leftoverIdentity) == .none,
               "owned identifiers are exact, while prefixes and names stay optional without unsigned wrappers")
        let technicalIdentity = UninstallerSupport.technicalIdentity(leftoverIdentity)
        suite.expect(UninstallerSupport.leftoverMatch("Editor", identity: technicalIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.plist", identity: technicalIdentity) == .exact,
               "sensitive roots accept technical ownership and never a display name")
        suite.expect(UninstallerSupport.leftoverEntryMatches(
                   "Editor_2024-01-01-120000_Mac.plist",
                   identity: leftoverIdentity, crashReporter: true)
               && !UninstallerSupport.leftoverEntryMatches(
                   "Editor_2024-01-01-120000_Mac.plist",
                   identity: leftoverIdentity, crashReporter: false),
               "crash reports may use the app name as a prefix only in that folder")
        suite.expect(UninstallerSupport.ownerBundleID(for: "com.vendor.editor.helper.plist",
                                                identity: leftoverIdentity)
                == "com.vendor.editor.helper"
               && UninstallerSupport.ownerBundleID(for: "Editor", identity: leftoverIdentity)
                == "com.vendor.editor",
               "a helper identifier wins when it is in the name, otherwise the app identifier owns a name match")
        suite.expect(UninstallerSupport.normalizedToken("Example App 2") == "exampleapp2"
               && UninstallerSupport.nameWithoutTrailingVersion("Example App 2") == "Example App"
               && UninstallerSupport.nameWithoutTrailingVersion("Example App Nightly") == "Example App"
               && UninstallerSupport.leftoverMatch(
                   "Example App",
                   identity: UninstallerSupport.identity(bundleIDs: ["com.vendor.exampleapp"],
                                                         displayNames: ["Example App 2"])) == .related
               && UninstallerSupport.leftoverEntryMatches(
                   "ExampleApp2.plist",
                   identity: UninstallerSupport.identity(bundleIDs: ["com.vendor.exampleapp"],
                                                         displayNames: ["Example App 2"])),
               "spaces and trailing version numbers do not hide a leftover named after the app")
        let twoPartIdentity = UninstallerSupport.identity(
            primaryBundleID: "test.editor",
            bundleIDs: ["test.editor"],
            displayNames: ["Editor", "Editor.app"])
        suite.expect(twoPartIdentity.nameTokens.contains("editor")
               && twoPartIdentity.bundleIDs.contains("test.editor"),
               "two-part bundle identifiers yield both display name tokens and exact bundle IDs")
        suite.expect(UninstallerSupport.leftoverMatch("Editor", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("editor", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("test.editor.plist", identity: twoPartIdentity) == .exact
               && UninstallerSupport.leftoverMatch("test.editor", identity: twoPartIdentity) == .exact
               && UninstallerSupport.leftoverMatch("test.editor.helper", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("Unrelated", identity: twoPartIdentity) == .none,
               "two-part bundle identifiers match exact and related leftovers correctly")
        suite.expect(UninstallerSupport.identity(primaryBundleID: "com.vendor.browser",
                                           bundleIDs: ["com.vendor.browser"],
                                           displayNames: ["Vendor Browser"]).nameTokens.contains("browser"),
               "the last identifier component is a token when it names the app")
        let browserIdentity = UninstallerSupport.identity(primaryBundleID: "com.vendor.browser",
                                                          bundleIDs: ["com.vendor.browser"],
                                                          displayNames: ["Vendor Browser"])
        let browserListings = [
            UninstallerSupport.DirListing(name: "Vendor", children: [
                UninstallerSupport.DirListing(name: "Browser", children: []),
                UninstallerSupport.DirListing(name: "Docs", children: []),
            ]),
            UninstallerSupport.DirListing(name: "SuiteApp", children: [
                UninstallerSupport.DirListing(name: "logs", children: []),
            ]),
            UninstallerSupport.DirListing(name: "com.vendor.browser", children: []),
        ]
        suite.expect(UninstallerSupport.leftoverHitRecords(
                   listings: browserListings,
                   identity: browserIdentity,
                   extraChildDepth: 1).map(\.path) == ["Vendor/Browser", "com.vendor.browser"],
               "a leftover nested under a vendor folder is found without taking the whole vendor folder")
        suite.expect(UninstallerSupport.leftoverHitRecords(
                   listings: browserListings,
                   identity: browserIdentity,
                   extraChildDepth: 0).map(\.path) == ["com.vendor.browser"],
               "vendor nesting is not searched when the folder is a leaf location")
        suite.expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(name: "Browser", children: [
                       UninstallerSupport.DirListing(name: "com.vendor.browser", children: [])
                   ])],
                   identity: browserIdentity,
                   extraChildDepth: 1).map(\.path) == ["Browser/com.vendor.browser"],
               "an exact child wins over a broader related parent folder")
        suite.expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(
                       name: "Unrelated.component", children: [],
                       bundleIdentifier: "com.vendor.browser")],
                   identity: browserIdentity,
                   extraChildDepth: 0).first?.confidence == .exact,
               "plugin bundle metadata finds a component whose filename does not identify the app")
        suite.expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(name: "Vendor", children: [
                       UninstallerSupport.DirListing(name: "Mid", children: [
                           UninstallerSupport.DirListing(name: "Editor", children: [])
                       ])
                   ])],
                   identity: leftoverIdentity,
                   extraChildDepth: 2).map(\.path) == ["Vendor/Mid/Editor"],
               "Application Support is searched two levels for vendor/mid/app nesting")
        let teamedIdentity = UninstallerSupport.identity(
            bundleIDs: ["com.vendor.editor"], displayNames: [],
            teamIDs: ["abcd123456"], groupIDs: ["group.com.vendor.editor"])
        suite.expect(UninstallerSupport.leftoverMatch("ABCD123456.com.other", identity: teamedIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "ABCD123456.com.vendor.editor", identity: teamedIdentity) == .exact
               && UninstallerSupport.leftoverMatch(
                   "ZZZZ123456.com.vendor.editor", identity: teamedIdentity) == .none
               && UninstallerSupport.leftoverMatch("group.com.vendor.editor", identity: teamedIdentity) == .exact
               && UninstallerSupport.matchingGroupID(
                   "group.com.vendor.editor", identity: teamedIdentity) == "group.com.vendor.editor"
               && UninstallerSupport.containerMetadataMatches("com.vendor.editor",
                                                              identity: leftoverIdentity) == .exact,
               "team prefixes are related, app groups and container metadata keep the exact owner")
        let leftoverFolders = UninstallerSupport.searchFolders(
            home: URL(fileURLWithPath: "/Users/tester"), darwinCache: nil, darwinTemp: nil)
        suite.expect(leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Group Containers" && $0.kind == .containers
                   && $0.readsContainerMetadata && !$0.allowsNameMatches
                   && $0.requiresSignedGroup
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/PreferencePanes" && $0.kind == .other
               })
               && leftoverFolders.contains(where: {
                   $0.url.path.hasSuffix("CrashReporter") && $0.crashReporter
               })
               && leftoverFolders.contains(where: { $0.url.path == "/private/var/db/receipts" })
               && leftoverFolders.contains(where: { $0.url.path.hasSuffix("/Automator") })
               && leftoverFolders.contains(where: { $0.url.path.hasSuffix("/Frameworks") })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/.config" && !$0.allowsNameMatches
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Preferences/ByHost"
                       && !$0.allowsNameMatches
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Caches/com.apple.nsurlsessiond/Downloads"
                       && !$0.allowsNameMatches
               })
               && !leftoverFolders.contains(where: { $0.url.path.contains("/Desktop") })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Application Support" && $0.extraChildDepth == 2
               }),
               "leftover search covers Library support, plugins and receipts, not the Desktop")
        let spotlightQuery = UninstallerSupport.leftoverSpotlightExpression(identity: leftoverIdentity) ?? ""
        suite.expect(spotlightQuery.contains("com.vendor.editor")
               && spotlightQuery.contains("editor")
               && UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Library/Caches/Editor",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library")])
               && !UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Desktop/Editor",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library")]),
               "Spotlight leftovers stay inside Library-like roots")
        let spotlightGroupIdentity = UninstallerSupport.spotlightIdentity(
            for: "/Users/tester/Library/Group Containers/group.com.vendor.editor",
            identity: teamedIdentity)
        let spotlightLaunchIdentity = UninstallerSupport.spotlightIdentity(
            for: "/Users/tester/Library/LaunchAgents/Editor.plist",
            identity: teamedIdentity)
        suite.expect(spotlightGroupIdentity.bundleIDs.isEmpty
               && spotlightGroupIdentity.groupIDs == ["group.com.vendor.editor"]
               && spotlightLaunchIdentity.nameTokens.isEmpty,
               "Spotlight preserves signed-group and technical-only rules for sensitive roots")
        let safetyFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-uninstaller-\(UUID().uuidString)", isDirectory: true)
        let safetyRoot = safetyFixture.appendingPathComponent("root", isDirectory: true)
        let outsideRoot = safetyFixture.appendingPathComponent("outside", isDirectory: true)
        let safeFile = safetyRoot.appendingPathComponent("safe.plist")
        let replacementFile = safetyRoot.appendingPathComponent("replacement.plist")
        let outsideFile = outsideRoot.appendingPathComponent("foreign.plist")
        let link = safetyRoot.appendingPathComponent("link", isDirectory: true)
        try? FileManager.default.createDirectory(at: safetyRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: safeFile.path, contents: Data("old".utf8))
        _ = FileManager.default.createFile(atPath: replacementFile.path, contents: Data("new".utf8))
        _ = FileManager.default.createFile(atPath: outsideFile.path, contents: Data("foreign".utf8))
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideRoot)
        let originalFileIdentity = UninstallerSupport.fileIdentity(at: safeFile)
        let safePathWasAccepted = UninstallerSupport.removalPathIsSafe(safeFile, within: safetyRoot)
        let linkedPathWasRejected = !UninstallerSupport.removalPathIsSafe(
            link.appendingPathComponent("foreign.plist"), within: safetyRoot)
        try? FileManager.default.removeItem(at: safeFile)
        try? FileManager.default.moveItem(at: replacementFile, to: safeFile)
        suite.expect(safePathWasAccepted && linkedPathWasRejected
               && originalFileIdentity != nil
               && UninstallerSupport.fileIdentity(at: safeFile) != originalFileIdentity,
               "removal stays inside its scan root, rejects symlink escapes and detects path replacement")
        // A failed lookup is not necessarily absence, and links can remain
        // even after their destination has disappeared.
        let absentFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-absent-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: absentFixture, withIntermediateDirectories: true)
        let presentChild = absentFixture.appendingPathComponent("StillHere.app")
        try? "bundle".write(to: presentChild, atomically: true, encoding: .utf8)
        suite.expect(!UninstallerSupport.isConfirmedAbsent(at: presentChild),
               "a path that still exists is not confirmed absent")
        try? FileManager.default.removeItem(at: presentChild)
        suite.expect(UninstallerSupport.isConfirmedAbsent(at: presentChild),
               "a missing child under a readable parent is confirmed absent")
        let danglingLink = absentFixture.appendingPathComponent("Dangling.app")
        let danglingMade = symlink("/tmp/vorssaint-missing-target-\(UUID().uuidString)",
                                   danglingLink.path) == 0
        suite.expect(danglingMade
               && !UninstallerSupport.isConfirmedAbsent(at: danglingLink),
               "a dangling symlink still occupies an entry and is not confirmed absent")
        try? FileManager.default.removeItem(at: danglingLink)
        let nestedParent = absentFixture.appendingPathComponent("NestedParent", isDirectory: true)
        let nestedChild = nestedParent.appendingPathComponent("Gone.app")
        try? FileManager.default.createDirectory(at: nestedParent, withIntermediateDirectories: true)
        try? "x".write(to: nestedChild, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: nestedParent)
        suite.expect(UninstallerSupport.isConfirmedAbsent(at: nestedChild),
               "when the item and its parent folder are both gone, absence is confirmed")
        let inaccessibleParent = absentFixture.appendingPathComponent("Restricted", isDirectory: true)
        let inaccessibleChild = inaccessibleParent.appendingPathComponent("StillHere.app")
        try? FileManager.default.createDirectory(at: inaccessibleParent, withIntermediateDirectories: true)
        let restrictedCreated = FileManager.default.createFile(atPath: inaccessibleChild.path, contents: Data("x".utf8))
        suite.expect(restrictedCreated, "the permission fixture exists before access changes")
        if geteuid() != 0 {
            let accessRestricted = chmod(inaccessibleParent.path, 0) == 0
            suite.expect(accessRestricted && !UninstallerSupport.isConfirmedAbsent(at: inaccessibleChild),
                   "a file that becomes inaccessible after selection remains a failure")
            let missingInRestrictedParent = inaccessibleParent.appendingPathComponent("Absent.app")
            suite.expect(!UninstallerSupport.isConfirmedAbsent(at: missingInRestrictedParent),
                   "absence below an inaccessible parent is not assumed")
            suite.expect(chmod(inaccessibleParent.path, 0o700) == 0,
                   "the permission fixture restores access")
        }
        suite.expect(UninstallerSupport.fileIdentity(at: inaccessibleChild) != nil,
               "the inaccessible file remains present")
        let invalidChild = inaccessibleChild.appendingPathComponent("Child")
        suite.expect(!UninstallerSupport.isConfirmedAbsent(at: invalidChild),
               "a parent replaced by a regular file is not treated as a confirmed removal")
        let loop = absentFixture.appendingPathComponent("Loop")
        let loopCreated = symlink("Loop", loop.path) == 0
        suite.expect(loopCreated && !UninstallerSupport.isConfirmedAbsent(at: loop.appendingPathComponent("Child")),
               "a symbolic link loop is an error, not confirmed absence")
        try? FileManager.default.removeItem(at: inaccessibleChild)
        suite.expect(UninstallerSupport.isConfirmedAbsent(at: inaccessibleChild),
               "the previously inaccessible file is recognized as absent only after removal")
        try? FileManager.default.removeItem(at: absentFixture)
        try? FileManager.default.removeItem(at: safetyFixture)
        func sourceBody(of source: String, from opening: String, to closing: String) -> String {
            guard let start = source.range(of: opening),
                  let end = source.range(of: closing, range: start.upperBound..<source.endIndex)
            else { return "" }
            return String(source[start.upperBound..<end.lowerBound])
        }
        // Building the installed-apps oracle walks the application folders, and
        // the removal guard reads it under `.leftovers` alone — with leftover
        // rows unchecked by default, the common clean must not pay for that
        // walk. JunkCleaner is not part of this test binary, so pin the gate
        // and the premise that makes an empty oracle safe at their source.
        let junkCleanerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Cleaner/JunkCleaner.swift",
            encoding: .utf8)) ?? ""
        let cleanSelectedBody = sourceBody(of: junkCleanerSource, from: "func cleanSelected(",
                                           to: "private static func mayRemove")
        suite.expect(cleanSelectedBody.contains("chosen.contains { $0.category == .leftovers }")
               && cleanSelectedBody.contains("? Self.installedBundleIDs() : []")
               && !cleanSelectedBody.contains("let installed = Self.installedBundleIDs()"),
               "a clean builds the installed-apps oracle only when a leftover row is selected")
        let mayRemoveBody = sourceBody(of: junkCleanerSource, from: "private static func mayRemove",
                                       to: "private static func trashViaFinder")
        let leftoverBranch = mayRemoveBody.range(of: "if item.category == .leftovers")
        suite.expect(mayRemoveBody.components(separatedBy: "installed: installed").count == 2,
               "the removal guard consults the installed-apps oracle exactly once")
        suite.expect(leftoverBranch.map { branch in
                   mayRemoveBody.range(of: "installed: installed",
                                       range: branch.upperBound..<mayRemoveBody.endIndex) != nil
               } == true,
               "the removal guard reads the installed-apps oracle inside its leftovers branch")
        // The known-application roster opens every installed app, and only the
        // shared-data claims read it. AppUninstaller is not part of this test
        // binary either, so pin the gate that keeps a removal that cannot claim
        // shared data from paying for the roster.
        let appUninstallerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Uninstall/AppUninstaller.swift",
            encoding: .utf8)) ?? ""
        let removeSelectedBody = sourceBody(of: appUninstallerSource, from: "func removeSelected()",
                                            to: "func removeSelectedWithHomebrew(")
        suite.expect(removeSelectedBody.contains("let knownApplications = mayClaimSharedData"),
               "a removal builds the known-application roster only when it may claim shared data")
        let finishHomebrewBody = sourceBody(of: appUninstallerSource,
                                            from: "private func finishRemovalAfterHomebrew",
                                            to: "private static func trashViaFinder")
        suite.expect(!finishHomebrewBody.isEmpty,
               "the Homebrew follow-up removal source reads back for its shape check")
        // Package completion must preserve ownership of the remaining choices
        // while counting the app only after its removal is confirmed.
        let markedPackageRemoval = finishHomebrewBody.range(of: "homebrewRemovedApplication = true")
        let firstRemoveSelected = finishHomebrewBody.range(of: "removeSelected()")
        suite.expect(markedPackageRemoval != nil
                && firstRemoveSelected.map { markedPackageRemoval!.upperBound < $0.lowerBound } == true
                && finishHomebrewBody.contains("setInclude(false, for: app.id)")
                && finishHomebrewBody.contains("isConfirmedAbsent")
                && finishHomebrewBody.contains("homebrewRemovalSize = app.size"),
               "after package removal the flag is set before trash, and size is credited only after confirmed absence")
        suite.expect(removeSelectedBody.contains("try fm.trashItem(at: item.url, resultingItemURL: nil)")
                && removeSelectedBody.contains("isConfirmedAbsent")
                && removeSelectedBody.contains("stubborn.append(item)")
                && removeSelectedBody.contains("freed += item.size"),
               "a path is counted freed only when its absence is confirmed, not on a bare fileExists miss")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.prefPane")
                == "com.vendor.editor",
               "preference panes map to their owning bundle identifier")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName: "app-0.0.409") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "0.0.409") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "1.57.0") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.v2.editor")
                == "com.v2.editor",
               "version directories never become deletion ownership evidence")
        let supportRoot = URL(fileURLWithPath: "/Users/tester/Library/Application Support")
        suite.expect(CleanerSupport.isDirectChild(
                   supportRoot.appendingPathComponent("com.vendor.editor"), of: supportRoot)
               && !CleanerSupport.isDirectChild(
                   supportRoot.appendingPathComponent("vendor/app-0.0.409"), of: supportRoot),
               "the general Cleaner accepts only direct children of each leftover root")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.editor.Helper.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist")
                == "com.vendor.editor.Helper"
               && CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.editor") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "ABCD123456.com.vendor.editor")
                == "com.vendor.editor",
               "ByHost UUIDs and team prefixes unwrap to the owning identifier")
        suite.expect(CleanerSupport.hasSharedContainerWrapper("group.com.vendor.editor")
               && CleanerSupport.hasSharedContainerWrapper("ABCD123456.com.vendor.editor")
               && !CleanerSupport.hasSharedContainerWrapper("abcd123456.com.vendor.editor")
               && !CleanerSupport.hasSharedContainerWrapper("com.vendor.editor"),
               "the general Cleaner leaves shared-container wrappers to signed app-specific scans")
        let helperAppIdentity = UninstallerSupport.identity(
            primaryBundleID: "com.vendor.chat",
            bundleIDs: ["com.vendor.chat", "com.vendor.chat.helper.Renderer", "com.vendor.chat.helper.GPU"],
            displayNames: ["Chat App"])
        suite.expect(!helperAppIdentity.nameTokens.contains("renderer")
               && !helperAppIdentity.nameTokens.contains("gpu")
               && helperAppIdentity.nameTokens.contains("chatapp")
               && UninstallerSupport.leftoverMatch("renderer.log", identity: helperAppIdentity) == .none
               && !UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Library/Application Support/OtherApp/logs/sub/renderer.log",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library/Application Support")]),
               "helper subprocess roles and deeply nested foreign logs are never claimed as leftovers")
        suite.expect(CleanerSupport.isProtectedBundleID("systemgroup.com.apple.icloud.searchpartyd.sharedsettings")
               && CleanerSupport.isProtectedBundleID("243LU875E5.groups.com.apple.podcasts")
               && CleanerSupport.isProtectedBundleID("developer.apple.wwdc")
               && CleanerSupport.isProtectedBundleID("is.workflow.my.app")
               && CleanerSupport.isProtectedBundleID("vorss.tests.switcher.shortcut"),
               "system domains stay protected in every wrapping, team prefixes included")
        suite.expect(CleanerSupport.sharedInfrastructurePrefixes.allSatisfy {
                   CleanerSupport.isProtectedBundleID($0)
               },
               "embedded updaters and crash reporters can never be junk owners")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName: "systemgroup.com.apple.icloud.sharedsettings.plist")
               == "com.apple.icloud.sharedsettings",
               "systemgroup wrappers unwrap to the real owner")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.editor") == nil,
               "a UUID in the middle of a name stays unattributable")
        suite.expect(CleanerSupport.containsUUIDComponent("x.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F")
               && !CleanerSupport.containsUUIDComponent("com.vendor.editor"),
               "the UUID detector matches dashed UUIDs and nothing else")
        suite.expect(CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.backgroundtool",
                                                    withInstalled: ["com.vendor.editor"])
               && CleanerSupport.sharesVendorNamespace(candidate: "com.publisher.agent",
                                                       withInstalled: ["com.publisher.browser"]),
               "a vendor's updaters are owned while any app of that vendor is installed")
        suite.expect(!CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.editor",
                                                     withInstalled: ["com.publisher.browser"]),
               "different vendors never own each other")
        suite.expect(!CleanerSupport.sharesVendorNamespace(candidate: "io.github.account.tool",
                                                     withInstalled: ["io.github.other.app"]),
               "code hosting namespaces are shared by unrelated developers and never match")
        suite.expect(CleanerPolicy.precheckCacheEntry("Homebrew")
               && CleanerPolicy.precheckCacheEntry("com.vendor.editor"),
               "download caches and third party app caches start checked")
        suite.expect(!CleanerPolicy.precheckCacheEntry("PlainVendorFolder")
               && !CleanerPolicy.precheckCacheEntry("com.apple.Music")
               && !CleanerPolicy.precheckCacheEntry("com.spotify.client")
               && !CleanerPolicy.precheckCacheEntry("ms-playwright"),
               "system, sensitive and unattributable caches start unchecked")
        suite.expect(CleanerPolicy.isExcludedCacheEntry("com.spotify.client")
               && CleanerPolicy.isExcludedCacheEntry("COM.SPOTIFY.CLIENT")
               && CleanerPolicy.isExcludedCacheEntry("com.spotify.client.helper"),
               "caches holding installed customizations are excluded even when all caches are selected")
        suite.expect(!CleanerPolicy.isExcludedCacheEntry("com.vendor.editor")
               && !CleanerPolicy.isExcludedCacheEntry("ms-playwright"),
               "ordinary and downloadable sensitive caches remain available for review")
        suite.expect(CleanerSupport.Category.deviceBackups.rawValue == 6
               && CleanerSupport.Category.allCases.count == 7,
               "device backups joined the cleaner with a stable category id")
        suite.expect(!CleanerPolicy.precheckDeviceBackups,
               "device backups never start checked, they are the user's safety net")
        // CleanerScheduler and CleanerView are outside this test binary, so
        // pin escalation at the call sites: the unattended pass must never
        // reach Finder's administrator prompt, and no default lets a later
        // automatic caller inherit it.
        let compact = { (path: String) -> String in
            ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isWhitespace).joined()
        }
        let schedulerCode = compact("Sources/Vorssaint/Services/Cleaner/CleanerScheduler.swift")
        let cleanerViewCode = compact("Sources/Vorssaint/UI/Cleaner/CleanerView.swift")
        suite.expect(schedulerCode.components(separatedBy: "cleanSelected(").count == 2
               && schedulerCode.contains("cleanSelected(escalate:false)")
               && schedulerCode.contains("notifyIfWanted(freed:freed,failed:failed)"),
               "the scheduled clean never escalates and reports what it left in place")
        suite.expect(junkCleanerSource.contains("func cleanSelected(escalate: Bool) {")
               && cleanerViewCode.components(separatedBy: "cleanSelected(").count == 2
               && cleanerViewCode.contains("cleanSelected(escalate:true)"),
               "cleanSelected has no default escalation and the manual clean still asks")
        suite.expect(CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/iOS DeviceSupport")
               && CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/watchOS DeviceSupport"),
               "stale DeviceSupport symbol caches count as developer junk")
        suite.expect(CleanerSupport.looksLikeBundleID("com.vendor.editor")
               && CleanerSupport.looksLikeBundleID("com.foo.Bar-Helper_2")
               && CleanerSupport.looksLikeBundleID("test.editor")
               && CleanerSupport.looksLikeBundleID("editor.test")
               && CleanerSupport.looksLikeBundleID("com.foo"),
               "reverse DNS names and two-component bundle identifiers are recognized")
        suite.expect(!CleanerSupport.looksLikeBundleID("VendorFolder")
               && !CleanerSupport.looksLikeBundleID("Editor")
               && !CleanerSupport.looksLikeBundleID("com..foo")
               && !CleanerSupport.looksLikeBundleID(".com.foo")
               && !CleanerSupport.looksLikeBundleID("com.foo.")
               && !CleanerSupport.looksLikeBundleID("com.foo.bár"),
               "plain names, empty parts and odd characters never match by name")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.plist") == "com.vendor.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "test.editor.plist") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.com.foo.bar") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.test.editor") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "ABCD123456.test.editor") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.savedState") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.binarycookies") == "com.foo.bar",
               "entry names map to their owning bundle identifier")
        suite.expect(CleanerSupport.bundleIDCandidate(fromEntryName: "VendorFolder") == nil,
               "folders without a bundle shaped name are never candidates")
        suite.expect(CleanerSupport.isOwned(candidate: "com.vendor.editor.startuphelper",
                                      byInstalled: ["com.vendor.editor"]),
               "embedded helper identifiers are owned by their installed app")
        suite.expect(CleanerSupport.isOwned(candidate: "com.maker",
                                      byInstalled: ["com.maker.app"]),
               "a family prefix of an installed app counts as owned")
        suite.expect(!CleanerSupport.isOwned(candidate: "com.vendor.editor", byInstalled: ["com.publisher.browser"]),
               "identifiers with no installed relative are unowned")
        suite.expect(!CleanerSupport.isOwned(candidate: "com.makerapp.tool", byInstalled: ["com.maker.app"]),
               "prefix ownership requires a dot boundary, not a string prefix")
        suite.expect(CleanerSupport.executablePaths(inLaunchPlist: [
                   "Program": "/Applications/Gone.app/Contents/MacOS/agent",
                   "ProgramArguments": ["/usr/local/bin/gone-tool", "--flag"],
                   "BundleProgram": "Contents/MacOS/relative",
               ]) == ["/Applications/Gone.app/Contents/MacOS/agent", "/usr/local/bin/gone-tool"],
               "launch plists yield their absolute executables and skip relative ones")
        suite.expect(CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                           executables: ["/Applications/Gone.app/x"],
                                                           executableExists: { _ in false }),
               "a plist whose executables are all gone is a removable orphan")
        suite.expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                            executables: ["/bin/ls"],
                                                            executableExists: { _ in true }),
               "a plist with a living executable is never an orphan")
        suite.expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.apple.something",
                                                            executables: ["/gone"],
                                                            executableExists: { _ in false })
               && !CleanerSupport.launchPlistIsRemovableOrphan(label: nil,
                                                               executables: [],
                                                               executableExists: { _ in false }),
               "system agents and undecidable plists are never offered")
        suite.expect(registeredDefaults[DefaultsKey.mediaLastTool] as? String == MediaTool.videoCompressor.rawValue,
               "Media defaults to video compressor")
        suite.expect(registeredDefaults[DefaultsKey.mediaVideoCodec] as? String == MediaVideoCodec.h264.rawValue,
               "Media video codec defaults to H.264")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageFormat] as? String == MediaImageFormat.jpeg.rawValue,
               "Media image format defaults to JPEG")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageResizeKind] as? String == MediaImageResizeKind.maxDimension.rawValue,
               "Media image resize defaults to max side")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageExactResizeMode] as? String == MediaImageExactResizeMode.stretch.rawValue,
               "Media image exact resize defaults to stretch for existing behavior")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageWatermarkKind] as? String == MediaImageWatermarkKind.off.rawValue,
               "Media image watermark starts off")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageBackground] as? String == MediaImageBackground.transparent.rawValue,
               "Media image background starts transparent")
        suite.expect(registeredDefaults[DefaultsKey.mediaImagePreserveModificationDate] as? Bool == false,
               "Media image conversion does not preserve modification dates by default")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageSaveInSubfolder] as? Bool == false,
               "Media image batches keep their current output folder by default")
        suite.expect(registeredDefaults[DefaultsKey.mediaImageProfiles] as? String == "[]",
               "Media image profiles start empty")
        suite.expect((registeredDefaults[DefaultsKey.autoQuitExceptions] as? [String]) == Defaults.mandatoryAutoQuitExceptionBundleIDs,
               "Finder and Phone stay in the default auto-quit exception list")
        suite.expect(Defaults.mandatoryAutoQuitExceptionBundleIDs.contains(Defaults.finderBundleIdentifier)
                && Defaults.mandatoryAutoQuitExceptionBundleIDs.contains(Defaults.phoneBundleIdentifier),
               "Quit on close never terminates Finder or Phone (Continuity calls)")
        suite.expect(Defaults.sanitizedAutoQuitExceptions([Defaults.finderBundleIdentifier])
                .contains(Defaults.phoneBundleIdentifier),
               "existing auto-quit exception lists gain Phone on sanitize")
        suite.expect(AutoQuitSupport.shouldDisplayException(
            bundleID: Defaults.phoneBundleIdentifier, isInstalled: false) == false,
               "Phone stays out of the exceptions UI when the app is not installed")
        suite.expect(AutoQuitSupport.shouldDisplayException(
            bundleID: Defaults.phoneBundleIdentifier, isInstalled: true),
               "Phone appears in the exceptions UI when the app is present")
        suite.expect(AutoQuitSupport.shouldDisplayException(
            bundleID: Defaults.finderBundleIdentifier, isInstalled: true),
               "Finder remains visible in the exceptions UI")
        suite.expect(AutoQuitSupport.visibleExceptions(
            [Defaults.finderBundleIdentifier, Defaults.phoneBundleIdentifier, "com.example.app"],
            isInstalled: { $0 != Defaults.phoneBundleIdentifier }
        ) == [Defaults.finderBundleIdentifier, "com.example.app"],
               "hiding Phone leaves other exceptions, including mandatory Finder, visible")
        suite.expect(Defaults.mandatoryAutoQuitExceptionBundleIDs.contains(Defaults.phoneBundleIdentifier),
               "Phone remains a mandatory quit exception even when hidden from the UI")
        let autoQuitSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/AutoQuitSettings.swift",
            encoding: .utf8)) ?? ""
        suite.expect(autoQuitSettingsSource.contains("AutoQuitSupport.visibleExceptions")
                && autoQuitSettingsSource.contains("InstalledApps.url(for:"),
               "the AutoQuit settings list filters exceptions through installation-aware visibility")
        suite.expect(registeredDefaults[DefaultsKey.panelCollapsedSections] == nil,
               "panel collapsed sections intentionally has no registered default")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityOrder] == nil,
               "panel utility order intentionally has no registered default")
        suite.expect(registeredDefaults[DefaultsKey.panelToggleOrder] == nil,
               "panel toggle order intentionally has no registered default")
        suite.expect(Defaults.sanitizedDefaultDuration(60) == 60, "valid default duration is preserved")
        suite.expect(Defaults.sanitizedDefaultDuration(999) == 0, "invalid default duration falls back to indefinite")
        suite.expect(Defaults.sanitizedBatteryLimit(15) == 15, "valid battery limit is preserved")
        suite.expect(Defaults.sanitizedBatteryLimit(100) == 10, "invalid battery limit falls back to default")
        suite.expect(Defaults.sanitizedClipboardHistoryLimit(1_000) == 1_000,
               "larger clipboard history limits are preserved")
        suite.expect(Defaults.sanitizedClipboardHistoryLimit(999) == 50,
               "unsupported clipboard history limits fall back to default")
        suite.expect(Defaults.sanitizedMonitorInterval(5) == 5, "valid monitor interval is preserved")
        suite.expect(Defaults.sanitizedMonitorInterval(7) == 2, "invalid monitor interval falls back to default")
        suite.expect(Defaults.sanitizedKeyboardDebounceWindow(80) == 80,
               "valid debounce window is preserved")
        suite.expect(Defaults.sanitizedKeyboardDebounceWindow(1) == 1,
               "sub-5 ms keyboard debounce windows are preserved")
        suite.expect(Defaults.sanitizedKeyboardDebounceWindow(3) == 3,
               "magnetic-keyboard debounce windows below 5 ms stay available")
        suite.expect(Defaults.sanitizedKeyboardDebounceWindow(999) == Defaults.defaultKeyboardDebounceWindowMs,
               "invalid debounce window falls back to default")
        suite.expect(Defaults.sanitizedMenuBarLabelStyle("classic") == "classic", "valid label style is preserved")
        suite.expect(Defaults.sanitizedMenuBarLabelStyle("bad") == "compact", "invalid label style falls back to compact")
        suite.expect(Defaults.sanitizedMenuBarMemoryStyle("percent") == "percent", "percent memory style is preserved")
        suite.expect(Defaults.sanitizedMenuBarMemoryStyle("dot") == "dot", "valid memory style is preserved")
        suite.expect(Defaults.sanitizedMenuBarMemoryStyle("both") == "both", "combined memory style is preserved")
        suite.expect(Defaults.sanitizedMenuBarMemoryStyle("bad") == "percent", "invalid memory style falls back to percent")
        suite.expect(Defaults.sanitizedMenuBarMetricOrder("cpu,gpu,memory,network,battery,power")
               == ["cpu", "gpu", "memory", "network", "battery", "power",
                   "cpuTemperature", "gpuTemperature", "batteryTime", "batteryTemperature", "peripheralBattery", "diskUsage", "diskActivity", "connectedDevices", "fanSpeed"],
               "menu bar metric order appends temperature sensors without rewriting existing saved order")
        suite.expect(Defaults.sanitizedMenuBarMetricOrder("temperature,cpu,cpu,bad")
               == ["cpuTemperature", "gpuTemperature", "batteryTemperature",
                   "cpu", "gpu", "memory", "battery", "batteryTime", "peripheralBattery", "network", "diskUsage", "diskActivity", "connectedDevices", "power", "fanSpeed"],
               "menu bar metric order migrates the old generic temperature value")
        suite.expect(Defaults.sanitizedBundleIdentifierList([" com.example.One ", "", "com.example.One", "com.example.Two"])
               == ["com.example.One", "com.example.Two"],
               "bundle id lists are trimmed and deduplicated")
        suite.expect(Defaults.sanitizedAutoQuitExceptions(["com.example.One", Defaults.finderBundleIdentifier])
               == [Defaults.finderBundleIdentifier, Defaults.phoneBundleIdentifier, "com.example.One"],
               "Finder and Phone are mandatory in the auto-quit exception list")
        suite.expect(AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.direct",
                                          bundleURL: nil,
                                          exceptions: ["com.example.direct"]),
               "AutoQuit recognizes a direct bundle identifier exception")
        suite.expect(AutoQuitSupport.isExcepted(
            bundleIdentifier: "com.parallels.winapp.0123456789abcdef.guest",
            bundleURL: nil,
            exceptions: ["com.parallels.desktop.console"]
        ), "AutoQuit extends a guest-window host exception to its generated app helpers")
        suite.expect(!AutoQuitSupport.isExcepted(
            bundleIdentifier: "com.parallels.winapp.0123456789abcdef.guest",
            bundleURL: nil,
            exceptions: ["com.example.unrelated"]
        ), "AutoQuit does not protect a generated guest app without its host exception")
        let outerApp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintAutoQuitTests-\(UUID().uuidString)")
            .appendingPathComponent("Container.app")
        let nestedApp = outerApp.appendingPathComponent("Contents/MacOS/WindowHost.app")
        try? FileManager.default.createDirectory(at: nestedApp.appendingPathComponent("Contents"),
                                                 withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.container"])
            .write(to: outerApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.window-host"])
            .write(to: nestedApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        suite.expect(AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.window-host",
                                          bundleURL: nestedApp,
                                          exceptions: ["com.example.container"]),
               "AutoQuit extends an outer app exception to its bundled window host")
        suite.expect(!AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.window-host",
                                           bundleURL: nestedApp,
                                           exceptions: ["com.example.unrelated"]),
               "AutoQuit does not extend unrelated exceptions to a bundled window host")
        let dependentApp = outerApp.appendingPathComponent("Contents/Hosted.app")
        try? FileManager.default.createDirectory(at: dependentApp.appendingPathComponent("Contents"),
                                                 withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.dependent",
                                  "CrBundleIdentifier": "com.example.host"])
            .write(to: dependentApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        suite.expect(AutoQuitSupport.hasDependentApplication(hostBundleIdentifier: "com.example.host",
                                                       applicationBundleURLs: [dependentApp]),
               "AutoQuit keeps a host running while a declared dependent app is open")
        suite.expect(!AutoQuitSupport.hasDependentApplication(hostBundleIdentifier: "com.example.unrelated",
                                                        applicationBundleURLs: [dependentApp]),
               "AutoQuit does not protect an unrelated host")
        try? FileManager.default.removeItem(at: outerApp.deletingLastPathComponent())
        suite.expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appDeactivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app deactivation as a window close")
        suite.expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appActivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app activation as a window close")
        suite.expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .mainWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat main window changes as a window close")
        suite.expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .focusedWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat focused window changes as a window close")
        suite.expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .windowDestroyed,
                                                         hasRecentCloseRequest: false),
               "AutoQuit checks windows after a destroyed window")
        suite.expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                          hasRecentCloseRequest: false),
               "AutoQuit ignores hidden apps without a recent close request")
        suite.expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                         hasRecentCloseRequest: true),
               "AutoQuit checks hidden apps after a recent close request")
        suite.expect(AutoQuitSupport.isCommandW(keyCode: 13, command: true, control: false),
               "AutoQuit treats Command W as a close request")
        suite.expect(!AutoQuitSupport.isCommandW(keyCode: 18, command: true, control: true),
               "AutoQuit does not treat Control number Space switching as a close request")
        suite.expect(AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                          appIsTerminated: false,
                                                          appIsExcepted: false,
                                                          appIsHidden: false,
                                                          hiddenByCloseRequest: false,
                                                          hasKnownMinimizedWindow: false,
                                                          hasUserFacingWindow: false),
               "AutoQuit can quit when an app that had windows is now windowless")
        suite.expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: false,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit does not quit apps that started windowless")
        suite.expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: true,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps excepted apps running")
        suite.expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: true,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps hidden apps running without explicit close intent")
        suite.expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: true,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps apps running when a minimized window is known")
        suite.expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: true),
               "AutoQuit keeps apps with user-facing windows running")
        suite.expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [4],
                                                            visibleSpaces: [3],
                                                            hasTitle: true),
               "a window parked on another Space keeps its app running")
        suite.expect(!AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [3],
                                                             visibleSpaces: [3],
                                                             hasTitle: true),
               "a window the app hid on the Space in front does not keep it running")
        suite.expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [],
                                                            visibleSpaces: [3],
                                                            hasTitle: true),
               "a window with no Space answer falls back to the title rule")
        suite.expect(!AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [],
                                                             visibleSpaces: nil,
                                                             hasTitle: false),
               "an untitled off-screen window never keeps an app running")
        suite.expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [3],
                                                            visibleSpaces: nil,
                                                            hasTitle: true),
               "without Spaces to compare, the old cautious rule stands")

        suite.expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                     listedWindows: 0,
                                                     foundUserWindow: true,
                                                     hadPriorWindows: false),
               "an app the window server still shows a window for is watched again")
        suite.expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 1,
                                                     listedWindows: 2,
                                                     foundUserWindow: true,
                                                     hadPriorWindows: false),
               "a listed window whose notification failed is watched again")
        suite.expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 2,
                                                       listedWindows: 2,
                                                       foundUserWindow: true,
                                                       hadPriorWindows: false),
               "two registered windows cover the two Accessibility listed windows")
        suite.expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 1,
                                                       listedWindows: 1,
                                                       foundUserWindow: true,
                                                       hadPriorWindows: false),
               "a registered window is the watch, so nothing is retried")
        suite.expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                     listedWindows: 0,
                                                     foundUserWindow: false,
                                                     hadPriorWindows: false),
               "an app with no window on launch is retried during the initial watch window")
        suite.expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                       listedWindows: 0,
                                                       foundUserWindow: false,
                                                       hadPriorWindows: true),
               "an app that had prior windows and now closed its last window needs no watch retry")
        suite.expect(AutoQuitSupport.isWindowNotificationRegistered(.success),
               "a window whose notification was accepted is watched")
        suite.expect(AutoQuitSupport.isWindowNotificationRegistered(.notificationAlreadyRegistered),
               "a window already registered on this observer stays watched across refreshes")
        suite.expect(!AutoQuitSupport.isWindowNotificationRegistered(.cannotComplete),
               "a window whose registration was refused is not watched")
        let autoQuitServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AutoQuit/AutoQuitService.swift",
            encoding: .utf8)) ?? ""
        let autoQuitServiceLines = autoQuitServiceSource.components(separatedBy: "\n")
        func autoQuitServiceCodeLines(containing fragment: String) -> [Int] {
            autoQuitServiceLines.enumerated().compactMap { index, line in
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains(fragment) else { return nil }
                return index + 1
            }
        }
        // The retry has to stop: an app whose windows Accessibility can never
        // describe would otherwise be polled for as long as it runs. The
        // service is not part of this test binary, so pin the load-bearing
        // timing, stale-timer guard, and Space re-arm at their source lines.
        let windowWatchRetryCode = [
            "let serverWindow = windows.isEmpty ? hasWindowServerUserWindow(pid: pid) : nil",
            "let foundUserWindow = !windows.isEmpty || serverWindow == true",
            "private static let windowWatchRetryOffsets: [TimeInterval] = [0.5, 1.5, 4.0]",
            "retry.attemptsScheduled < Self.windowWatchRetryOffsets.count else { return }",
            "deadline: retry.origin + Self.windowWatchRetryOffsets[attempt]",
            "retry.pendingTimerID == timerID",
            "windowWatchRetries.removeAll()",
            "NSWorkspace.activeSpaceDidChangeNotification",
            "rearmWindowWatchRetries()",
            // The count the retry reads must be windows actually watched, not
            // windows Accessibility listed: AXObserverAddNotification can
            // refuse, and a refused registration is exactly the state the
            // retry exists for. Only the destroyed notification decides it.
            "if watch(window: window, observer: observer, refcon: refcon) { watchedWindows += 1 }",
            "needsWindowWatchRetry(registeredWindows: watchedWindows,",
            "listedWindows: windows.count,",
            "if notification == kAXUIElementDestroyedNotification {",
            "watched = AutoQuitSupport.isWindowNotificationRegistered(result)",
        ]
        let missingWindowWatchRetryCode = windowWatchRetryCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        suite.expect(missingWindowWatchRetryCode.isEmpty,
               "the AutoQuit window-watch retry stays bounded, origin-based, re-armed by Space changes, and counts only windows whose destroy notification registered: missing \(missingWindowWatchRetryCode)")
        // Coalescing is only safe while the state it reads is torn down with
        // the app: a refresh left pending for a detached app would run against
        // an observer that is gone.
        let refreshCoalescingCode = [
            "guard pendingRefreshes.insert(pid).inserted else { return }",
            "self.pendingRefreshes.remove(pid) != nil",
            "pendingRefreshes.removeAll()",
        ]
        let missingRefreshCoalescingCode = refreshCoalescingCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        suite.expect(missingRefreshCoalescingCode.isEmpty,
               "AutoQuit collapses a burst of notifications into one refresh and drops it when the app goes: missing \(missingRefreshCoalescingCode)")
        // Two lines drop the pending refresh: the deferred block's own guard
        // and `detach`. Losing the second is the case this counts.
        suite.expect(autoQuitServiceCodeLines(containing: "pendingRefreshes.remove(pid)").count == 2,
               "a pending AutoQuit refresh is dropped both when it runs and when the app is detached")
        let closeCheckOffsetCode = [
            "private static let closeCheckOffsets: [TimeInterval] = [0.35, 1.0, 2.2]",
            "for offset in Self.closeCheckOffsets",
            "DispatchQueue.main.asyncAfter(deadline: origin + offset)",
        ]
        let missingCloseCheckOffsetCode = closeCheckOffsetCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        suite.expect(missingCloseCheckOffsetCode.isEmpty,
               "AutoQuit close checks remain offsets from one origin: missing \(missingCloseCheckOffsetCode)")

        // Attaching to a watched app must never ask its application element for
        // a role. A Chromium app (Electron, and the browsers) answers that by
        // switching its renderers into full accessibility mode, and then pays
        // to rebuild and ship an accessibility tree on every DOM change for the
        // rest of its life — measured on an idle app that this feature only
        // ever needed a window count from (issue #953). Windows are the same
        // liveness signal and leave that mode alone. Comments are stripped
        // first: the note above the probe names the attribute it avoids, and a
        // check that cannot tell prose from a call would go red for it.
        let autoQuitServiceCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AutoQuit/AutoQuitService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(autoQuitServiceCode.contains(
                   "AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .cannotComplete"),
               "AutoQuit probes a watched app for liveness by asking for its windows")
        // The same read reached the application element a second way, up the
        // parent chain of an element that never yields a window. Two files
        // carried that walk, so both the rule and its guard are repo wide
        // further down rather than a grep per copy here.
        suite.expect(Defaults.sanitizedPanelItemOrder("uninstaller,homebrew,homebrew,bad",
                                                defaultOrder: ["homebrew", "media", "uninstaller", "cleanURL", "cleaning"])
               == ["uninstaller", "homebrew", "media", "cleanURL", "cleaning"],
               "panel item order keeps saved valid items first and appends defaults")

        runNonModalAlertChecks(suite)
    }

    /// The disk image installer's alerts used to run modal inside a main-queue
    /// block (the hop after the mount check and the one after the install).
    /// A modal loop started there holds back later main-queue work, such as a
    /// Window Layout shortcut, until the alert closes, and its modal panel
    /// mode stops default-mode timers (issue #1665). The alert is never
    /// ordered on screen here.
    private static func runNonModalAlertChecks(_ suite: TestSuite) {
        func makeAlert() -> NSAlert {
            let alert = NSAlert()
            alert.messageText = "Install?"
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Cancel")
            return alert
        }

        let alert = makeAlert()
        var shownWindows: [NSWindow] = []
        var responses: [NSApplication.ModalResponse] = []
        var queuedWorkRan = false
        DispatchQueue.main.async { queuedWorkRan = true }
        let presentation = NonModalAlert.present(alert, show: { shownWindows.append($0) }) {
            responses.append($0)
        }
        // One pass of the run loop returns after the first source it handles,
        // which on a busy runner need not be the main queue, so keep turning it.
        let queuedWorkDeadline = Date(timeIntervalSinceNow: 2)
        while !queuedWorkRan && Date() < queuedWorkDeadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        suite.expect(queuedWorkRan && responses.isEmpty && presentation.isOpen,
               "main-queue work runs while an installer alert is still waiting for an answer")
        suite.expect(shownWindows.count == 1 && shownWindows.first === alert.window
               && alert.window.level == .modalPanel,
               "the alert shows its own window at the level a modal alert would use")
        suite.expect(!alert.window.hidesOnDeactivate,
               "the alert stays on screen when another app becomes active")
        suite.expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"],
               "Return and Escape still answer the alert")

        alert.buttons[0].performClick(nil)
        alert.buttons[1].performClick(nil)
        suite.expect(responses == [.alertFirstButtonReturn] && !presentation.isOpen,
               "the first button answers once and later clicks are ignored")

        let cancelled = makeAlert()
        var cancelResponses: [NSApplication.ModalResponse] = []
        NonModalAlert.present(cancelled, show: { _ in }) { cancelResponses.append($0) }
        cancelled.buttons[1].performClick(nil)
        suite.expect(cancelResponses == [.alertSecondButtonReturn],
               "the second button answers with the second button's response")

        let result = NSAlert()
        result.messageText = "Installed"
        var resultResponses: [NSApplication.ModalResponse] = []
        let resultPresentation = NonModalAlert.present(result, show: { _ in }) { resultResponses.append($0) }
        result.buttons.first?.performClick(nil)
        suite.expect(result.buttons.count == 1 && result.buttons.first?.keyEquivalent == "\r"
               && resultResponses == [.alertFirstButtonReturn] && !resultPresentation.isOpen,
               "an alert without buttons answers through its OK button, like the installer's result alert")

        weak var weakTarget: NSObject?
        var dismissed: NonModalAlert?
        var dismissResponses: [NSApplication.ModalResponse] = []
        let dismissedAlert = makeAlert()
        autoreleasepool {
            let target = NSObject()
            weakTarget = target
            dismissed = NonModalAlert.present(dismissedAlert, retaining: [target], show: { _ in }) {
                dismissResponses.append($0)
            }
        }
        suite.expect(weakTarget != nil,
               "a checkbox target the alert references weakly stays alive while the alert is open")
        autoreleasepool {
            dismissed?.dismiss(with: .alertSecondButtonReturn)
            dismissedAlert.buttons[0].performClick(nil)
            dismissed = nil
        }
        suite.expect(dismissResponses == [.alertSecondButtonReturn] && weakTarget == nil,
               "dismissing answers once, ignores later clicks and releases what the alert retained")

        let installerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DiskImageInstaller/DiskImageInstallerService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(!installerSource.isEmpty && !installerSource.contains(".runModal()")
               && installerSource.components(separatedBy: "NonModalAlert.present(").count == 3,
               "the install prompt and the result alert both open without a modal session")
    }
}
