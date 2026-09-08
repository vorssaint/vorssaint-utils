// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CleanerScheduleTests {
    static func run(expect: (Bool, String) -> Void) {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func scheduleDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: day,
                                                  hour: hour, minute: minute)) ?? Date()
        }
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 8, 0), frequency: .daily,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(9, 9, 0),
               "a daily schedule still due today fires today")
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .daily,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(10, 9, 0),
               "a daily schedule already past fires tomorrow")
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .weekly,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(13, 9, 0),
               "a weekly Monday schedule queried on Thursday fires next Monday")
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .off,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == nil,
               "an off schedule never fires")
        expect(CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0),
                                         lastRun: scheduleDate(8, 9, 30),
                                         frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                         calendar: utcCalendar),
               "a fire that passed while the Mac was off counts as missed")
        expect(!CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0),
                                          lastRun: scheduleDate(9, 9, 30),
                                          frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                          calendar: utcCalendar),
               "a run that already happened today is not missed")
        expect(!CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0), lastRun: nil,
                                          frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                          calendar: utcCalendar),
               "enabling the schedule never triggers a surprise first run")
        expect(CleanerSchedule.hour24(hour12: 12, isPM: false) == 0
               && CleanerSchedule.hour24(hour12: 12, isPM: true) == 12
               && CleanerSchedule.hour24(hour12: 1, isPM: true) == 13
               && CleanerSchedule.hour24(hour12: 11, isPM: false) == 11,
               "twelve hour picks map to the right clock hours, midnight and noon included")
        expect(CleanerSchedule.hour12Components(fromHour24: 0) == (12, false)
               && CleanerSchedule.hour12Components(fromHour24: 12) == (12, true)
               && CleanerSchedule.hour12Components(fromHour24: 18) == (6, true)
               && CleanerSchedule.hour12Components(fromHour24: 9) == (9, false),
               "clock hours split back into the twelve hour pickers")
        expect((0...23).allSatisfy { hour in
                   let parts = CleanerSchedule.hour12Components(fromHour24: hour)
                   return CleanerSchedule.hour24(hour12: parts.hour12, isPM: parts.isPM) == hour
               },
               "every hour of the day round trips through the twelve hour pickers")

        // MARK: WhatsApp downloads

        let whatsAppEnabledSuite = "vorss.tests.whatsapp.enabled"
        if let migrationDefaults = UserDefaults(suiteName: whatsAppEnabledSuite) {
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil,
                   "an untouched setup keeps WhatsApp downloads off by leaving the new switch unset")
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "an existing automatic WhatsApp cleanup keeps its Cleaner surface")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppOrganizerEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "an existing WhatsApp organizer keeps its Cleaner surface")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil,
                   "only opening Downloads does not keep the WhatsApp Cleaner surface")
            migrationDefaults.set(false, forKey: DefaultsKey.whatsAppDownloadsEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(!migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "the WhatsApp downloads migration preserves a newer off choice")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
        } else {
            expect(false, "WhatsApp downloads migration suite can be created")
        }
        expect(WhatsAppDownloadSupport.isWhatsAppAgent("WhatsApp")
                && WhatsAppDownloadSupport.isWhatsAppAgent(" whatsapp ")
                && !WhatsAppDownloadSupport.isWhatsAppAgent("SomeBrowser")
                && !WhatsAppDownloadSupport.isWhatsAppAgent(nil),
               "only an explicit WhatsApp quarantine agent is trusted")
        expect(WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.jpeg",
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
        expect(WhatsAppDownloadSupport.isIncompleteFile(extension: "download")
                && WhatsAppDownloadSupport.isIncompleteFile(extension: "PART")
                && !WhatsAppDownloadSupport.isIncompleteFile(extension: "pdf"),
               "partial downloads can never become cleanup candidates")
        let whatsNow = scheduleDate(20, 12, 0)
        let whatsOld = scheduleDate(10, 12, 0)
        let whatsRecent = scheduleDate(19, 12, 0)
        expect(WhatsAppDownloadSupport.isOldEnough(downloadedAt: whatsOld,
                                                   modifiedAt: whatsOld,
                                                   now: whatsNow, retentionDays: 7,
                                                   calendar: utcCalendar),
               "an untouched old WhatsApp download passes retention")
        expect(!WhatsAppDownloadSupport.isOldEnough(downloadedAt: whatsOld,
                                                    modifiedAt: whatsRecent,
                                                    now: whatsNow, retentionDays: 7,
                                                    calendar: utcCalendar),
               "a recent edit postpones WhatsApp cleanup")
        expect(!WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
                    category: .image, downloadedAt: whatsOld, modifiedAt: whatsOld,
                    now: whatsNow, retentionDays: 7, enabledCategories: [.image],
                    includeExisting: false, automaticStartDate: whatsRecent),
               "future-only automation leaves pre-existing downloads alone")
        expect(WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
                    category: .image, downloadedAt: whatsOld, modifiedAt: whatsOld,
                    now: whatsNow, retentionDays: 7, enabledCategories: [.image],
                    includeExisting: true, automaticStartDate: whatsRecent),
               "explicitly including existing downloads admits old matches")
        let downloadsRoot = URL(fileURLWithPath: "/Users/test/Downloads")
        expect(WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Downloads/file.pdf"), of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Downloads/folder/file.pdf"), of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Documents/file.pdf"), of: downloadsRoot),
               "WhatsApp cleanup accepts only direct children of Downloads")
        let organizedFile = URL(fileURLWithPath: "/Users/test/Downloads/WhatsApp/2026/07/file.pdf")
        expect(WhatsAppDownloadSupport.isDescendant(organizedFile, of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDescendant(downloadsRoot, of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDescendant(
                    URL(fileURLWithPath: "/Users/test/Download/file.pdf"), of: downloadsRoot),
               "organized cleanup accepts descendants without path-prefix confusion")
        let fourMinutesAgo = whatsNow.addingTimeInterval(-4 * 60)
        let sixMinutesAgo = whatsNow.addingTimeInterval(-6 * 60)
        expect(!WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: sixMinutesAgo, modifiedAt: fourMinutesAgo,
                    now: whatsNow, delayMinutes: 5)
                && WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: sixMinutesAgo, modifiedAt: sixMinutesAgo,
                    now: whatsNow, delayMinutes: 5)
                && WhatsAppDownloadSupport.sanitizedOrganizerDelayMinutes(999) == 5,
               "organization waits for both download and modification activity to settle")
        let undoCreatedAt = whatsNow.addingTimeInterval(-6 * 86_400)
        expect(WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: undoCreatedAt, now: whatsNow)
                && !WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: whatsNow.addingTimeInterval(-7 * 86_400), now: whatsNow)
                && !WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: whatsNow.addingTimeInterval(1), now: whatsNow),
               "organizer undo is executable only during its seven day window")
        expect(WhatsAppDownloadSupport.organizerRelativeComponents(
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
        expect(WhatsAppDownloadSupport.isSameVolume(
                    source: volumeA,
                    destination: NSData(bytes: [0x67, 0x45, 0x64, 0x00] as [UInt8], length: 4)),
               "two equal volume identifiers are one volume even as separate objects")
        expect(!WhatsAppDownloadSupport.isSameVolume(source: volumeA, destination: volumeB),
               "two different volume identifiers never skip the destination check")
        expect(!WhatsAppDownloadSupport.isSameVolume(source: NSNumber(value: 1),
                                                     destination: NSString(string: "1")),
               "unequal identities that print the same string still take the verified path")
        expect(!WhatsAppDownloadSupport.isSameVolume(source: volumeA, destination: nil)
                && !WhatsAppDownloadSupport.isSameVolume(source: nil, destination: volumeB)
                && !WhatsAppDownloadSupport.isSameVolume(source: nil, destination: nil),
               "an unknown volume identity keeps the verified copy rather than an unchecked rename")
        expect(WhatsAppDownloadSupport.nextAutomaticCheck(
                    after: scheduleDate(20, 8, 0), calendar: utcCalendar) == scheduleDate(20, 9, 0)
                && WhatsAppDownloadSupport.nextAutomaticCheck(
                    after: scheduleDate(20, 10, 0), calendar: utcCalendar) == scheduleDate(21, 9, 0),
               "the hidden daily WhatsApp check targets nine in the morning")
        expect(WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 12, 0), lastRun: scheduleDate(19, 9, 0),
                    calendar: utcCalendar)
                && !WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 8, 0), lastRun: scheduleDate(19, 9, 0),
                    calendar: utcCalendar)
                && !WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 12, 0), lastRun: nil, calendar: utcCalendar),
               "missed WhatsApp checks recover after nine without a first-enable surprise")
    }
}
