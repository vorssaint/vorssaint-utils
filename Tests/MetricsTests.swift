// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Carbon.HIToolbox
import Darwin
import Foundation

// Standalone unit tests for pure helpers. Compiled without IOKit or UI by
// `./build.sh --test`, so they run fast and deterministically on any machine.
//
// A tiny @main harness instead of XCTest: the Command Line Tools cannot run
// `swift test`, and these checks need nothing more than equality assertions.
@main
struct MetricsTests {
    static func main() {
        var failures: [String] = []
        var checks = 0

        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            if !condition { failures.append(message()) }
        }
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            checks += 1
            if actual != expected { failures.append("\(label): got \"\(actual)\", expected \"\(expected)\"") }
        }
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            checks += 1
            if abs(actual - expected) > tol { failures.append("\(label): got \(actual), expected \(expected)") }
        }
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            checks += 1
            let actual = formatSpecifiers(in: format)
            if actual != expected { failures.append("\(label): got \(actual), expected \(expected)") }
        }

        // MARK: Byte / rate formatting

        expectEqual(MetricFormat.bytes(0), "0 B", "bytes zero")
        expectEqual(MetricFormat.bytes(512), "512 B", "bytes < 1K")
        expectEqual(MetricFormat.bytes(1024), "1.0 KB", "bytes 1K")
        expectEqual(MetricFormat.bytes(1536), "1.5 KB", "bytes 1.5K")
        expectEqual(MetricFormat.bytes(10 * 1024), "10 KB", "bytes 10K drops decimal")
        expectEqual(MetricFormat.bytes(1024 * 1024), "1.0 MB", "bytes 1M")
        expectEqual(MetricFormat.bytes(3 * 1024 * 1024 * 1024), "3.0 GB", "bytes 3G")
        expectEqual(MetricFormat.diskBytes(245_107_195_904), "245 GB", "disk bytes use decimal storage units")
        expectEqual(MetricFormat.diskBytes(1_000_204_845_056), "1.0 TB", "disk bytes show decimal terabytes")
        expectEqual(MetricFormat.diskBytes(123_456_789_000), "123 GB", "disk bytes match Finder-style GB")
        expectEqual(MetricFormat.diskBytesPrecise(14_878_047_232_000), "14.88 TB",
                    "precise disk bytes keep SMART totals readable")

        expectEqual(MetricFormat.bytesPerSec(0), "0 B/s", "rate zero")
        expectEqual(MetricFormat.bytesPerSec(2 * 1024 * 1024), "2.0 MB/s", "rate 2M")
        expectEqual(MetricFormat.bytesPerSec(1500 * 1024), "1.5 MB/s", "rate 1.5M")

        expectEqual(MetricFormat.bytesPerSecCompact(0), "0B", "compact zero")
        expectEqual(MetricFormat.bytesPerSecCompact(320 * 1024), "320K", "compact 320K")
        expectEqual(MetricFormat.bytesPerSecCompact(1.2 * 1024 * 1024), "1.2M", "compact 1.2M")
        expectEqual(MetricFormat.bytesPerSecCompact(1022), "1022B", "compact 1022B remains stable")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.4), "1023B", "compact keeps sub-kilobyte values")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.6), "1.0K", "compact promotes rounded kilobyte edge")
        expectEqual(MetricFormat.bytesPerSecCompact(9.96 * 1024), "10K", "compact drops redundant decimal at 10K")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.6 * 1024), "1.0M", "compact promotes rounded megabyte edge")
        expectEqual(MetricFormat.bytesPerSecCompact(9.96 * 1024 * 1024), "10M", "compact drops redundant decimal at 10M")

        // MARK: Disk helpers

        expect(DiskSupport.nvmeBytes(low: 2, high: nil) == 1_024_000,
               "NVMe data units convert to 512,000 byte units")
        expect(DiskSupport.nvmeBytes(low: 1, high: 1) == 2_199_023_256_064_000,
               "NVMe high data unit word is included")
        expectClose(DiskSupport.celsius(fromSMARTTemperature: 302) ?? -1, 28.85,
                    "SMART Kelvin temperature converts to Celsius")
        expectClose(DiskSupport.celsius(fromSMARTTemperature: 33) ?? -1, 33,
                    "SMART Celsius temperature is preserved")
        expect(DiskSupport.celsius(fromSMARTTemperature: 999) == nil,
               "SMART invalid temperature is ignored")
        expect(DiskSupport.healthPercent(fromPercentageUsed: 1) == 99,
               "SMART health subtracts percentage used")
        expect(DiskSupport.healthPercent(fromPercentageUsed: 150) == 0,
               "SMART health clamps exhausted drives")
        expect(DiskSupport.fileSystemLabel(type: "apfs") == "APFS",
               "file system label maps apfs")
        expect(DiskSupport.fileSystemLabel(type: " APFS \n") == "APFS",
               "file system label trims and ignores case")
        expect(DiskSupport.fileSystemLabel(type: "hfs", name: "Journaled HFS+") == "HFS+",
               "file system label maps journaled hfs")
        expect(DiskSupport.fileSystemLabel(type: "exfat") == "exFAT",
               "file system label keeps exFAT capitalization")
        expect(DiskSupport.fileSystemLabel(type: "ntfs") == "NTFS",
               "file system label maps ntfs")
        expect(DiskSupport.fileSystemLabel(type: "msdos", name: "Legacy FAT32") == "FAT32",
               "file system label reads FAT width from the name")
        expect(DiskSupport.fileSystemLabel(type: "msdos", name: "Legacy FAT16") == "FAT16",
               "file system label reads FAT16 from the name")
        expect(DiskSupport.fileSystemLabel(type: "msdos") == "FAT",
               "file system label falls back to plain FAT")
        expect(DiskSupport.fileSystemLabel(type: "cd9660") == "ISO 9660",
               "file system label maps optical media")
        expect(DiskSupport.fileSystemLabel(type: "udf") == "UDF",
               "file system label uppercases short unknown tokens")
        expect(DiskSupport.fileSystemLabel(type: "lifs") == "LIFS",
               "file system label keeps acronym-sized tokens")
        expect(DiskSupport.fileSystemLabel(type: "someverylongdriver") == nil,
               "file system label drops long driver tokens")
        expect(DiskSupport.fileSystemLabel(type: "a") == nil,
               "file system label drops single letters")
        expect(DiskSupport.fileSystemLabel(type: "123456") == nil,
               "file system label needs at least one letter")
        expect(DiskSupport.fileSystemLabel(type: "") == nil,
               "file system label ignores empty type")
        expect(DiskSupport.fileSystemLabel(type: nil) == nil,
               "file system label ignores missing type")
        let diskRate = MetricFormat.diskSpeed(
            previous: DiskIOCounters(read: 1_000, written: 500),
            current: DiskIOCounters(read: 3_048, written: 1_524),
            elapsed: 2
        )
        expectClose(diskRate.read, 1_024, "disk read speed uses elapsed time")
        expectClose(diskRate.write, 512, "disk write speed uses elapsed time")
        let resetDiskRate = MetricFormat.diskSpeed(
            previous: DiskIOCounters(read: 3_048, written: 1_524),
            current: DiskIOCounters(read: 2_000, written: 800),
            elapsed: 2
        )
        expectClose(resetDiskRate.read, 0, "disk read counter reset does not spike")
        expectClose(resetDiskRate.write, 0, "disk write counter reset does not spike")
        let smart = DiskSupport.smartReading(
            status: "Verified",
            vendorKeys: [
                "DATA_UNITS_READ_0": 2,
                "DATA_UNITS_WRITTEN_0": 4,
                "TEMPERATURE": 302,
                "PERCENTAGE_USED": 7,
                "POWER_CYCLES_0": 11,
                "POWER_ON_HOURS_0": 12,
                "UNSAFE_SHUTDOWNS_0": 13,
                "MEDIA_ERRORS_0": 14,
            ]
        )
        expect(smart?.status == "Verified", "SMART status is preserved")
        expect(smart?.totalReadBytes == 1_024_000, "SMART total read uses NVMe units")
        expect(smart?.totalWrittenBytes == 2_048_000, "SMART total written uses NVMe units")
        expectClose(smart?.temperatureCelsius ?? -1, 28.85, "SMART reading includes temperature")
        expect(smart?.healthPercent == 93, "SMART reading includes estimated health")
        expect(smart?.powerCycles == 11, "SMART reading includes power cycles")
        expect(smart?.powerOnHours == 12, "SMART reading includes power-on hours")
        expect(smart?.unsafeShutdowns == 13, "SMART reading includes unsafe shutdowns")
        expect(smart?.mediaErrors == 14, "SMART reading includes media errors")

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
            let alertStrings = FeatureStrings.monitorAlerts(language)
            expect(alertStrings.caption.contains("12"),
                   "\(language.rawValue) monitor alert caption explains the CPU spike window")
            expectFormat(alertStrings.cpuBodyFormat, ["d"], "\(language.rawValue) CPU alert format")
            expectFormat(alertStrings.cpuTemperatureBodyFormat, ["d"],
                         "\(language.rawValue) CPU temperature alert format")
            expectFormat(alertStrings.diskBodyFormat, ["@", "d"], "\(language.rawValue) disk alert format")
            expectFormat(alertStrings.batteryBodyFormat, ["d"], "\(language.rawValue) battery alert format")
        }
        expect(FeatureStrings.monitorAlerts(.enUS).cooldown == "Repeat the same alert after",
               "English monitor repeat control is explicit")
        expect(FeatureStrings.monitorAlerts(.ptBR).cooldown == "Repetir o mesmo alerta depois de",
               "Portuguese monitor repeat control is explicit")
        expect(ClipboardHistorySelection.initialIndex(totalCount: 3) == 0,
               "clipboard quick window starts keyboard navigation on the first item")
        expect(ClipboardHistorySelection.initialIndex(totalCount: 0) == 0,
               "clipboard quick window keeps an empty selection index safe")
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

        let pasteboardAccess = GeneralPasteboardAccess(label: "Vorssaint.Tests.PasteboardAccess")
        let pasteboardGroup = DispatchGroup()
        let pasteboardStateLock = NSLock()
        var activePasteboardOperations = 0
        var maximumPasteboardOperations = 0
        for _ in 0..<16 {
            pasteboardGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pasteboardAccess.sync {
                    pasteboardStateLock.lock()
                    activePasteboardOperations += 1
                    maximumPasteboardOperations = max(maximumPasteboardOperations,
                                                       activePasteboardOperations)
                    pasteboardStateLock.unlock()
                    usleep(1_000)
                    pasteboardStateLock.lock()
                    activePasteboardOperations -= 1
                    pasteboardStateLock.unlock()
                }
                pasteboardGroup.leave()
            }
        }
        expect(pasteboardGroup.wait(timeout: .now() + 2) == .success,
               "pasteboard access operations finish without deadlock")
        expect(maximumPasteboardOperations == 1,
               "pasteboard access serializes concurrent service work")
        let nestedPasteboardValue = pasteboardAccess.sync {
            pasteboardAccess.sync { 230 }
        }
        expect(nestedPasteboardValue == 230,
               "pasteboard access permits nested work without deadlock")

        let maxCapacityStringJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"93%"}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityStringJSON) == 93,
               "battery maximum capacity parses percentage strings")
        let maxCapacityNumberJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":93}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNumberJSON) == 93,
               "battery maximum capacity parses numeric JSON")
        let maxCapacityNestedJSON = Data(#"{"SPPowerDataType":[{"_items":[{"_items":[{"Maximum Capacity":"93%"}]}]}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNestedJSON) == 93,
               "battery maximum capacity parses nested System Report keys")
        let maxCapacityUnavailableJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"EM_DASH"}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityUnavailableJSON) == nil,
               "battery maximum capacity ignores placeholder values")

        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: false) == 13_320,
               "battery time converts the public time-to-empty minutes")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: -1,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time preserves the system calculating state")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: true,
                                                   isCharging: false) == nil,
               "battery time stays hidden on external power")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: true) == nil,
               "battery time stays hidden while charging")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 65_535,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time ignores the public unavailable sentinel")
        expect(BatteryTimeSupport.formatted(seconds: 13_320) == "3h 42m",
               "battery time formats hours and minutes")
        expect(BatteryTimeSupport.formatted(seconds: 30) == "0h 1m",
               "battery time keeps a positive final minute visible")

        // MARK: Peripheral battery helpers

        expect(PeripheralBatterySupport.percent(from: "87%") == 87,
               "peripheral battery parses percentage strings")
        expect(PeripheralBatterySupport.percent(from: NSNumber(value: 62.4)) == 62,
               "peripheral battery rounds numeric values")
        expect(PeripheralBatterySupport.percent(from: 140) == nil,
               "peripheral battery ignores invalid percentages")
        let usageMouse = [["DeviceUsagePage": 1, "DeviceUsage": 2]]
        expect(PeripheralBatterySupport.kind(product: "Wireless Device",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: usageMouse) == .mouse,
               "peripheral battery infers mouse from HID usage")
        expect(PeripheralBatterySupport.kind(product: "soundcore Space Q45",
                                             minorType: "Headset",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: []) == .audio,
               "peripheral battery infers Bluetooth headsets as audio devices")
        let bluetoothJSON = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"soundcore Space Q45":{"device_address":"F4:9D:8A:A2:4C:12","device_batteryLevelMain":"100%","device_minorType":"Headset"}},
          {"AirPods Pro":{"device_address":"E5:04:BE:68:C2:93","device_batteryLevelCase":"88%","device_batteryLevelLeft":"92%","device_batteryLevelRight":"90%"}}
        ],"device_not_connected":[
          {"Old Mouse":{"device_address":"00:00:00:00:00:00","device_batteryLevelMain":"12%","device_minorType":"Mouse"}}
        ]}]}
        """.utf8)
        let bluetoothDevices = PeripheralBatterySupport.bluetoothDevices(fromSystemProfilerJSON: bluetoothJSON)
        expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:F4:9D:8A:A2:4C:12",
                                                                 name: "soundcore Space Q45",
                                                                 percent: 100,
                                                                 kind: .audio)),
               "peripheral battery parses connected Bluetooth headset battery")
        expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:E5:04:BE:68:C2:93",
                                                                 name: "AirPods Pro",
                                                                 percent: 88,
                                                                 kind: .audio)),
               "peripheral battery uses the lowest connected AirPods component")
        expect(!bluetoothDevices.contains { $0.name == "Old Mouse" },
               "peripheral battery ignores disconnected Bluetooth devices")
        let keyboard = PeripheralBatteryDevice(id: "keyboard",
                                               name: "Magic Keyboard",
                                               percent: 78,
                                               kind: .keyboard)
        let mouse = PeripheralBatteryDevice(id: "mouse",
                                            name: "Magic Mouse",
                                            percent: 24,
                                            kind: .mouse)
        expect(PeripheralBatterySupport.sorted([keyboard, mouse]).map(\.id) == ["mouse", "keyboard"],
               "peripheral battery devices sort by lowest charge first")
        let menuMetric = PeripheralBatterySupport.menuBarMetric(for: [keyboard, mouse])
        expect(menuMetric?.label == "MOU" && menuMetric?.value == "24%+1",
               "peripheral battery menu metric shows the lowest device and extra count")
        expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 300,
            lastStartedAt: -.greatestFiniteMagnitude,
            lastFinishedAt: -.greatestFiniteMagnitude,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh starts when no cache exists")
        expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 400,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: true,
            interval: 300
        ), "peripheral Bluetooth refresh is single-flight")
        expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 500,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh respects its cache interval")
        expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 606,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh runs again only after the interval")

        // MARK: Keyboard debounce

        var debounceState = KeyboardDebounceState()
        let debounceConfig = KeyboardDebounceConfig(enabled: true,
                                                    globalWindowMs: 50,
                                                    keyWindows: [:])
        func debounceDown(_ keyCode: Int64,
                          at time: TimeInterval,
                          repeat isAutoRepeat: Bool = false,
                          config: KeyboardDebounceConfig) -> Bool {
            debounceState.shouldSuppress(keyCode: keyCode,
                                         isAutoRepeat: isAutoRepeat,
                                         event: .keyDown,
                                         time: time,
                                         config: config)
        }
        func debounceUp(_ keyCode: Int64,
                        at time: TimeInterval,
                        config: KeyboardDebounceConfig) -> Bool {
            debounceState.shouldSuppress(keyCode: keyCode,
                                         isAutoRepeat: false,
                                         event: .keyUp,
                                         time: time,
                                         config: config)
        }
        expect(!debounceDown(37, at: 10.00, config: debounceConfig),
               "debounce accepts the first key press")
        expect(!debounceUp(37, at: 10.01, config: debounceConfig),
               "debounce accepts key release")
        expect(debounceDown(37, at: 10.03, config: debounceConfig),
               "debounce suppresses same-key bounce after release")
        expect(!debounceDown(37, at: 10.06, config: debounceConfig),
               "debounce accepts same-key press after the release window")
        expect(!debounceDown(37, at: 10.07, repeat: true, config: debounceConfig),
               "debounce leaves key auto-repeat alone")
        let fastConfig = KeyboardDebounceConfig(enabled: true,
                                                globalWindowMs: 10,
                                                keyWindows: [:])
        debounceState.reset()
        expect(!debounceDown(0, at: 40.000, config: fastConfig),
               "debounce 10 ms accepts the first fast key press")
        _ = debounceUp(0, at: 40.004, config: fastConfig)
        expect(debounceDown(0, at: 40.009, config: fastConfig),
               "debounce 10 ms suppresses same-key bounce inside the release window")
        expect(!debounceDown(0, at: 40.014, config: fastConfig),
               "debounce 10 ms accepts the same key at the release boundary")
        let defaultDebounceConfig = KeyboardDebounceConfig(enabled: true,
                                                           globalWindowMs: Defaults.defaultKeyboardDebounceWindowMs,
                                                           keyWindows: [:])
        debounceState.reset()
        expect(!debounceDown(0, at: 45.000, config: defaultDebounceConfig),
               "debounce 5 ms default accepts the first fast key press")
        _ = debounceUp(0, at: 45.001, config: defaultDebounceConfig)
        expect(debounceDown(0, at: 45.005, config: defaultDebounceConfig),
               "debounce 5 ms default suppresses same-key bounce inside the release window")
        expect(!debounceDown(0, at: 45.006, config: defaultDebounceConfig),
               "debounce 5 ms default accepts the same key at the release boundary")
        debounceState.reset()
        expect(!debounceDown(37, at: 50.000, config: fastConfig),
               "debounce accepts normal phrase first letter")
        _ = debounceUp(37, at: 50.020, config: fastConfig)
        expect(!debounceDown(14, at: 50.025, config: fastConfig),
               "debounce accepts normal phrase next letter")
        _ = debounceUp(14, at: 50.045, config: fastConfig)
        expect(!debounceDown(17, at: 50.050, config: fastConfig),
               "debounce accepts normal phrase repeated-letter first press")
        _ = debounceUp(17, at: 50.070, config: fastConfig)
        expect(!debounceDown(17, at: 50.110, config: fastConfig),
               "debounce accepts normal phrase repeated-letter second press")
        debounceState.reset()
        expect(!debounceDown(0, at: 60.000, config: fastConfig),
               "debounce accepts the first key in an alternating pattern")
        _ = debounceUp(0, at: 60.004, config: fastConfig)
        expect(!debounceDown(11, at: 60.006, config: fastConfig),
               "debounce accepts a different key inside another key's window")
        _ = debounceUp(11, at: 60.009, config: fastConfig)
        expect(!debounceDown(0, at: 60.011, config: fastConfig),
               "debounce accepts a same-key press after another key was accepted")
        debounceState.reset()
        expect(!debounceDown(0, at: 70.000, config: fastConfig),
               "debounce accepts the first key before duplicate down")
        expect(debounceDown(0, at: 70.004, config: fastConfig),
               "debounce suppresses non-repeat duplicate down while the key is still down")
        expect(!debounceUp(0, at: 70.020, config: fastConfig),
               "debounce still passes the release after a duplicate down")
        debounceState.reset()
        expect(!debounceDown(0, at: 75.000, config: fastConfig),
               "debounce accepts a key before a missing release")
        expect(!debounceDown(0, at: 75.020, config: fastConfig),
               "debounce accepts a same-key press after the window even if release was missed")
        debounceState.reset()
        expect(!debounceDown(0, at: 80.000, config: fastConfig),
               "debounce accepts the first key before an out-of-order event")
        _ = debounceUp(0, at: 80.010, config: fastConfig)
        expect(!debounceDown(0, at: 79.990, config: fastConfig),
               "debounce resets same-key state when event timestamps move backward")
        let perKeyConfig = KeyboardDebounceConfig(enabled: true,
                                                  globalWindowMs: 20,
                                                  keyWindows: [37: 100, 40: 0])
        debounceState.reset()
        _ = debounceDown(37, at: 20.00, config: perKeyConfig)
        _ = debounceUp(37, at: 20.01, config: perKeyConfig)
        expect(debounceDown(37, at: 20.06, config: perKeyConfig),
               "debounce per-key window overrides the global window")
        _ = debounceDown(40, at: 30.00, config: perKeyConfig)
        _ = debounceUp(40, at: 30.005, config: perKeyConfig)
        expect(!debounceDown(40, at: 30.006, config: perKeyConfig),
               "debounce per-key zero disables filtering for that key")
        let encodedKeyWindows = KeyboardDebounceConfig.encodeKeyWindows([37: 100, 40: 0])
        expect(encodedKeyWindows == "37:100,40:0",
               "debounce key windows encode in stable key order")
        expect(KeyboardDebounceConfig.decodeKeyWindows("37:100,bad,40:0,99:999")
               == [37: 100, 40: 0, 99: Defaults.defaultKeyboardDebounceWindowMs],
               "debounce key windows decode and sanitize stored values")

        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: false, momentumPhase: 0, scrollPhase: 0, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "classic mouse wheel ticks classify as a wheel")
        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "phase-less continuous wheel events classify as a wheel")
        expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 2, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "touch scrolling phases classify as touch")
        expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 3, scrollPhase: 0, scrollCount: 1),
            secondsSinceLastGesturePhase: 0.1
        ), "momentum scrolling classifies as touch")
        expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: 0.05
        ), "touch transition events (phaseless, counted, right after a phased event) classify as touch")
        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: 5.0
        ), "counted wheel events long after any gesture classify as a wheel")
        expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: nil
        ), "counted wheel events classify as a wheel when no gesture was ever seen")

        expect(MouseNavigationSupport.direction(
            forButtonNumber: MouseNavigationSupport.backButtonNumber) == .back,
               "the first standard mouse side button maps to Back")
        expect(MouseNavigationSupport.direction(
            forButtonNumber: MouseNavigationSupport.forwardButtonNumber) == .forward,
               "the second standard mouse side button maps to Forward")
        expect(MouseNavigationSupport.direction(forButtonNumber: 2) == nil,
               "the middle mouse button is never consumed as navigation")
        expect(MouseNavigationSupport.direction(forButtonNumber: 9) == nil,
               "unrelated extra mouse buttons pass through")
        expect(MouseNavigationSupport.commandCharacter(for: .back) == "[",
               "Back uses the standard Command left bracket menu command")
        expect(MouseNavigationSupport.commandCharacter(for: .forward) == "]",
               "Forward uses the standard Command right bracket menu command")
        expect(MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "org.mozilla.firefox"),
               "the pass-through browser family keeps the raw side button events")
        expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "org.mozilla.firefoxdeveloperedition"),
               "every channel of the browser family passes through via the prefix rule")
        expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.parallels.desktop.console"),
               "virtual machines keep the raw side buttons for the guest system")
        expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "com.apple.finder"),
               "Finder stays on the menu-command navigation path")
        expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "org.mozillafoundation.x"),
               "prefix matching stops at the org.mozilla. namespace boundary")
        expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: nil),
               "an unknown frontmost app keeps the navigation behavior")

        // MARK: Smooth scrolling

        expect(SmoothScrollSupport.ticks(line: 1, fixedPoint: 1.0) == 1.0,
               "a classic wheel tick reads the same from either delta field")
        expect(SmoothScrollSupport.ticks(line: 0, fixedPoint: 0.25) == 0.25,
               "high-resolution wheels keep their fractional ticks when the integer field truncates to zero")
        expect(SmoothScrollSupport.ticks(line: -2, fixedPoint: 0) == -2,
               "a zero fixed-point field falls back to the integer line delta")
        expect(SmoothScrollSupport.remaining(afterTicks: 1, step: 40, current: 0) == 40,
               "one wheel tick queues one step of glide")
        expect(SmoothScrollSupport.remaining(afterTicks: 2, step: 40, current: 30) == 110,
               "same-direction ticks add to what is left")
        expect(SmoothScrollSupport.remaining(afterTicks: -1, step: 40, current: 100) == -40,
               "reversing direction abandons the leftover instead of fighting it")
        expect(SmoothScrollSupport.remaining(afterTicks: 0, step: 40, current: 25) == 25,
               "a tickless event leaves the glide untouched")
        // Measured against a scroll view: a one-line tick with Shift moves the
        // content the same way a horizontal delta of the SAME sign does, so
        // the redirect must not flip the tick.
        expect(SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 0, horizontal: 2),
               "Shift routes a vertical wheel tick sideways keeping its sign")
        expect(SmoothScrollSupport.axes(vertical: -2, horizontal: 0, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 0, horizontal: -2),
               "the Shift redirect keeps the sign in the other direction too")
        expect(SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: false)
               == SmoothScrollSupport.Axes(vertical: 2, horizontal: 0),
               "a wheel tick without Shift keeps its vertical axis")
        expect(SmoothScrollSupport.axes(vertical: 2, horizontal: -1, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 2, horizontal: -1),
               "Shift preserves a wheel event that already carries horizontal movement")
        expect(SmoothScrollSupport.frameDelta(remaining: 100) == 18,
               "a frame emits its fraction of the remaining distance")
        expect(SmoothScrollSupport.frameDelta(remaining: -100) == -18,
               "negative glides emit negative frames")
        expect(SmoothScrollSupport.frameDelta(remaining: 0.8) == 0.8,
               "small leftovers flush in one final frame")
        expect(SmoothScrollSupport.frameDelta(remaining: 3) == 1,
               "the glide never stalls below one pixel per frame")
        expect(SmoothScrollSupport.frameDelta(remaining: 0) == 0,
               "no remaining distance emits nothing")
        expect(SmoothScrollSupport.sanitizedStep(0) == 40,
               "an unset step falls back to the default")
        expect(SmoothScrollSupport.sanitizedStep(500) == 100,
               "the step clamps to its range")
        expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollEnabled] as? Bool == false,
               "smooth scrolling ships off by default")
        expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollStep] as? Int == 40,
               "smooth scrolling step registers its default")

        // A wheel that reports continuously already measures in points, and
        // that field is the one to trust; the line field only fills in for a
        // movement too small to register as a whole point.
        expect(ScrollWheelSupport.pointsPerLine == 10,
               "one scroll line spans ten points")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 40) == 40,
               "the default step travels the same distance the event asked for")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 12, step: 40) == 12,
               "the point field wins, so no assumption about points per line is made")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 20) == 20,
               "a shorter step halves the distance of a continuous wheel")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 100) == 100,
               "a longer step stretches the distance of a continuous wheel")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: -0.5, pointDelta: -5, step: 40) == -5,
               "direction survives the conversion")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0.35, pointDelta: 0, step: 40) == 3.5,
               "a movement below one whole point still glides")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0, pointDelta: 12, step: 40) == 12,
               "a driver that fills in only whole points still glides")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0, pointDelta: 0, step: 40) == 0,
               "an empty event asks for no distance")
        expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: .nan, pointDelta: 0, step: 40) == 0,
               "a nonsense delta asks for no distance")

        // The continuous path scales by the step itself and then hands the
        // budget a step of one. Scaling in both places would square the
        // setting, so pin that the budget equals the distance.
        for continuousStep in [20.0, 40.0, 100.0] {
            let distance = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: 4.0, pointDelta: 40, step: continuousStep)
            expect(SmoothScrollSupport.remaining(afterTicks: distance, step: 1, current: 0) == distance,
                   "the step scales a continuous wheel exactly once")
        }

        // Fractions are carried instead of rounded away, so the glide
        // delivers the whole distance it was given.
        var carriedTotal: Double = 0
        var carry: Double = 0
        for _ in 0..<10 {
            let frame = SmoothScrollSupport.wholePixels(0.6, carry: carry)
            carriedTotal += frame.pixels
            carry = frame.carry
        }
        expect(abs(carriedTotal + carry - 6) < 0.000001,
               "ten six-tenths of a pixel are all still there, posted or waiting")
        expect(carriedTotal >= 5,
               "never more than one pixel is left waiting")
        expect(SmoothScrollSupport.wholePixels(0.4, carry: 0).pixels == 0,
               "a fraction alone posts nothing yet")
        expect(SmoothScrollSupport.wholePixels(0.4, carry: 0).carry == 0.4,
               "the fraction is kept for the next frame")
        expect(SmoothScrollSupport.wholePixels(-1.5, carry: 0).pixels == -1,
               "negative frames keep their whole pixels")
        expect(SmoothScrollSupport.wholePixels(-1.5, carry: 0).carry == -0.5,
               "negative frames carry their fraction")
        expect(SmoothScrollSupport.wholePixels(.infinity, carry: 0).pixels == 0,
               "an impossible frame posts nothing")
        expect(SmoothScrollSupport.finalPixels(0.4, carry: 0.3) == 1,
               "the landing frame spends the leftover instead of dropping it")
        expect(SmoothScrollSupport.finalPixels(-0.4, carry: -0.3) == -1,
               "the landing frame spends it in either direction")
        expect(SmoothScrollSupport.finalPixels(0.2, carry: 0) == 0,
               "a landing frame with almost nothing left posts nothing")
        expect(SmoothScrollSupport.finalPixels(.infinity, carry: 0) == 0,
               "an impossible landing frame posts nothing")
        expect(SmoothScrollSupport.carry(0.6, continuing: 5) == 0.6,
               "leftovers survive while the direction holds")
        expect(SmoothScrollSupport.carry(0.6, continuing: -5) == 0,
               "reversing direction drops the leftovers")
        expect(SmoothScrollSupport.carry(0.6, continuing: 0) == 0.6,
               "an empty event leaves the leftovers alone")

        // MARK: Watts & percent

        expectEqual(MetricFormat.watts(8.5), "8.5 W", "watts under 10")
        expectEqual(MetricFormat.watts(23.4), "23 W", "watts over 10 rounds")
        expectEqual(MetricFormat.wattsCompact(8.6), "9W", "watts compact rounds")
        expectEqual(MetricFormat.percent(0), "0%", "percent 0")
        expectEqual(MetricFormat.percent(0.125), "13%", "percent rounds")
        expectEqual(MetricFormat.percent(1), "100%", "percent full")
        expectEqual(MetricFormat.percent(1.4), "100%", "percent clamps high")
        expectEqual(MetricFormat.percent(-0.2), "0%", "percent clamps low")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: 100), "79%",
                    "menu bar memory shows the current RAM percentage")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: nil, total: 100), "--%",
                    "menu bar memory keeps a placeholder when used RAM is unavailable")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: nil), "--%",
                    "menu bar memory keeps a placeholder when total RAM is unavailable")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: 0), "--%",
                    "menu bar memory keeps a placeholder when total RAM is invalid")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.03, current: 0.80), 0.23,
                    "GPU usage readout caps one-tick upward spikes")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.23, current: 0.80), 0.43,
                    "GPU usage readout still climbs during sustained load")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.60, current: 0.10), 0.275,
                    "GPU usage readout falls quickly after transient load")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: nil, current: 1.4), 1.0,
                    "GPU usage readout clamps first sample")
        expectEqual(MetricFormat.temperature(0, unit: .celsius), "0 °C", "celsius freezing")
        expectEqual(MetricFormat.temperature(0, unit: .fahrenheit), "32 °F", "fahrenheit freezing")
        expectEqual(MetricFormat.temperature(41, unit: .fahrenheit), "106 °F", "fahrenheit rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .celsius), "50°", "compact celsius rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .fahrenheit), "121°", "compact fahrenheit rounds")
        expectEqual(MetricFormat.temperatureUnitSuffix(.celsius), "°C", "celsius suffix is explicit")
        expectEqual(MetricFormat.temperatureUnitSuffix(.fahrenheit), "°F", "fahrenheit suffix is explicit")

        // MARK: Temperature sensor selection

        expect(TemperatureSensorSelector.platform(brandString: "Apple M1") == .appleM1Family,
               "Apple M1 uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M2 Pro") == .appleM2Family,
               "Apple M2 Pro uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M3 Max") == .appleM3Family,
               "Apple M3 Max uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M4 Ultra") == .appleM4Family,
               "Apple M4 Ultra uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M5") == .appleM5Family,
               "Apple M5 uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M10") == .generic,
               "future unmapped Apple Silicon generations keep the generic CPU sensor path")
        let m1CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp09", 43.0), ("Tp01", 49.0), ("Tp02", 70.0)],
            platform: .appleM1Family
        )
        expectClose(m1CPU ?? -1, 49.0, "M1 family uses hottest mapped CPU core")
        let m2CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp1h", 42.0), ("Tp0j", 52.0), ("Tp0k", 75.0)],
            platform: .appleM2Family
        )
        expectClose(m2CPU ?? -1, 52.0, "M2 family uses hottest mapped CPU core")
        let m3CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Te05", 44.0), ("Tf4E", 53.0), ("Tf4F", 76.0)],
            platform: .appleM3Family
        )
        expectClose(m3CPU ?? -1, 53.0, "M3 family uses hottest mapped CPU core")
        let m4CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6), ("Tp0W", 67.0), ("Te04", 43.2)],
            platform: .appleM4Family
        )
        expectClose(m4CPU ?? -1, 51.6, "M4 family uses hottest mapped CPU core instead of auxiliary hotspots")
        let m5CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 45.0), ("Tp0y", 54.0), ("Tp0z", 80.0)],
            platform: .appleM5Family
        )
        expectClose(m5CPU ?? -1, 54.0, "M5 family uses hottest mapped CPU core")
        let m4InvalidCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp01", 0.5), ("Tp05", 130.0), ("Tp09", 49.25), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        expectClose(m4InvalidCPU ?? -1, 49.25, "mapped CPU core selection ignores invalid temperatures")
        let m4FallbackCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        expectClose(m4FallbackCPU ?? -1, 67.0, "mapped CPU core selection falls back when no mapped sensor is available")
        let genericCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6)],
            platform: .generic
        )
        expectClose(genericCPU ?? -1, 51.6, "generic CPU sensor selection preserves previous hottest behavior")

        // MARK: Uptime formatting

        expectEqual(MetricFormat.uptime(0), "0min", "uptime zero")
        expectEqual(MetricFormat.uptime(59), "0min", "uptime under one minute")
        expectEqual(MetricFormat.uptime(60), "1min", "uptime one minute")
        expectEqual(MetricFormat.uptime(3_600), "1h 0min", "uptime one hour")
        expectEqual(MetricFormat.uptime(93_600), "1d 2h", "uptime days and hours")
        expectEqual(MetricFormat.uptime(8 * 86_400 + 21 * 3_600 + 8 * 60), "8d 21h",
                    "uptime keeps days compact")

        // MARK: Memory used

        let used = MetricFormat.memoryUsed(totalBytes: 16 * 1024,
                                           pageSize: 1024,
                                           freePages: 1,
                                           speculativePages: 2,
                                           fileBackedPages: 3)
        expect(used == 10 * 1024, "memory used excludes free, speculative and file-backed pages")
        expect(MetricFormat.memoryUsed(totalBytes: 16, pageSize: 1,
                                       freePages: 20, speculativePages: 0, fileBackedPages: 0) == 0,
               "memory used clamps impossible available memory")

        // MARK: Registered defaults

        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.keepAwakeAutoStart] as? Bool == false,
               "Keep Awake launch restore is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeExternalDisplay] as? Bool == false,
               "external-display Keep Awake is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeConnectedToPower] as? Bool == false,
               "power-connected Keep Awake is opt-in")
        expect(registeredDefaults[DefaultsKey.hotkeyEnabled] as? Bool == true,
               "global hotkey is on for clean installs")
        expect(registeredDefaults[DefaultsKey.keepAwakeShortcut] as? String == "control+option+command:40",
               "keep awake shortcut defaults to Ctrl+Opt+Cmd+K")
        expect(registeredDefaults[DefaultsKey.keepAwakeIconTint] as? String == KeepAwakeIconTint.orange.rawValue,
               "keep-awake active icon tint defaults to orange")
        expect(registeredDefaults[DefaultsKey.keepAwakeActiveIcon] as? String == KeepAwakeActiveIcon.vorssaint.rawValue,
               "keep-awake active icon defaults to the Vorssaint glyph")
        expect(registeredDefaults[DefaultsKey.keepAwakeMouseJiggleEnabled] as? Bool == false,
               "Keep Awake mouse movement is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeMouseJiggleInterval] as? Int == 5,
               "Keep Awake mouse movement defaults to five minutes")
        expect(Defaults.sanitizedKeepAwakeMouseJiggleInterval(10) == 10,
               "valid Keep Awake mouse movement interval is preserved")
        expect(Defaults.sanitizedKeepAwakeMouseJiggleInterval(3) == 5,
               "invalid Keep Awake mouse movement interval falls back to five minutes")
        expect(Defaults.sanitizedKeepAwakeIconTint("pink") == .pink,
               "valid keep-awake active icon tint is preserved")
        expect(Defaults.sanitizedKeepAwakeIconTint("bad") == .orange,
               "invalid keep-awake active icon tint falls back to orange")
        expect(Defaults.sanitizedKeepAwakeActiveIcon("coffee") == .coffee,
               "valid keep-awake active icon is preserved")
        expect(Defaults.sanitizedKeepAwakeActiveIcon("bad") == .vorssaint,
               "invalid keep-awake active icon falls back to the Vorssaint glyph")
        expect(KeepAwakeActiveIcon.eye.systemSymbolName == "eye.fill",
               "keep-awake eye option maps to its menu bar symbol")
        expect(!KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: []),
               "no online display does not count as an external display")
        expect(!KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: [true]),
               "the built-in screen does not count as an external display")
        expect(KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: [true, false]),
               "an online non-built-in screen counts as an external display")
        let combinedKeepAwakeConditions = KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: true,
            externalDisplayConnected: true,
            powerEnabled: true,
            connectedToPower: true
        )
        expect(combinedKeepAwakeConditions == [.externalDisplay, .power],
               "enabled Keep Awake conditions combine with OR behavior")
        expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [.externalDisplay],
            sessionActive: false,
            automaticSessionActive: false
        ) == .activate, "an external display starts the automatic session")
        expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [],
            sessionActive: true,
            automaticSessionActive: true
        ) == .deactivate, "clearing every matching condition ends the automatic session")
        expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [],
            sessionActive: true,
            automaticSessionActive: false
        ) == .none, "clearing automatic conditions does not end a manual session")
        let sleepDisabledReport = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
        """
        let sleepEnabledReport = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         standby              1
        """
        expect(SudoersSupport.sleepDisabled(inPmsetOutput: sleepDisabledReport),
               "a pmset report with SleepDisabled 1 reads as lid sleep disabled")
        expect(!SudoersSupport.sleepDisabled(inPmsetOutput: sleepEnabledReport),
               "a pmset report with SleepDisabled 0 reads as lid sleep enabled")
        expect(!SudoersSupport.sleepDisabled(inPmsetOutput: ""),
               "an empty pmset report reads as lid sleep enabled")
        expect(registeredDefaults[DefaultsKey.switcherEnabled] as? Bool == true,
               "window switcher is on for clean installs")
        expect(registeredDefaults[DefaultsKey.switcherShortcut] as? String == "command:48",
               "switcher shortcut defaults to Cmd+Tab")
        expect(registeredDefaults[DefaultsKey.switcherWindowShortcut] as? String
               == GlobalShortcut.switcherWindowDefault.storageValue,
               "switcher window shortcut defaults to Cmd+Grave")
        let shortcutSuite = "vorss.tests.switcher.shortcut"
        if let migrationDefaults = UserDefaults(suiteName: shortcutSuite) {
            migrationDefaults.removePersistentDomain(forName: shortcutSuite)
            migrationDefaults.set("control+option+command:50", forKey: DefaultsKey.switcherWindowShortcut)
            Defaults.migrateLegacySwitcherWindowShortcut(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowShortcut)
                   == GlobalShortcut.switcherWindowDefault.storageValue,
                   "switcher window shortcut migrates the accidental Ctrl+Option+Cmd+Grave default back to Cmd+Grave")
            migrationDefaults.set("option:50", forKey: DefaultsKey.switcherWindowShortcut)
            Defaults.migrateLegacySwitcherWindowShortcut(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowShortcut) == "option:50",
                   "switcher window shortcut migration preserves real custom shortcuts")
            migrationDefaults.set(30, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(false, forKey: DefaultsKey.keyboardDebounceEnabled)
            migrationDefaults.set("", forKey: DefaultsKey.keyboardDebounceKeyWindows)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
                   == Defaults.defaultKeyboardDebounceWindowMs,
                   "keyboard debounce migration updates the old disabled Developer default")
            migrationDefaults.set(10, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(false, forKey: DefaultsKey.keyboardDebounceEnabled)
            migrationDefaults.set("", forKey: DefaultsKey.keyboardDebounceKeyWindows)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
                   == Defaults.defaultKeyboardDebounceWindowMs,
                   "keyboard debounce migration updates the old disabled 10 ms default")
            migrationDefaults.set(30, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(true, forKey: DefaultsKey.keyboardDebounceEnabled)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs) == 30,
                   "keyboard debounce migration preserves active user choices")
            migrationDefaults.set(10, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(true, forKey: DefaultsKey.keyboardDebounceEnabled)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs) == 10,
                   "keyboard debounce migration preserves active 10 ms user choices")
            migrationDefaults.removeObject(forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.panelUtilityOrder) == nil,
                   "utility migration leaves a clean default order unpersisted")
            migrationDefaults.set("quickLauncher,cleaner,homebrew",
                                  forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.panelUtilityOrder)
                   == "screenshot,quickLauncher,cleaner,homebrew",
                   "utility migration puts the newly added screenshot first")
            migrationDefaults.set("homebrew,screenshot,cleaner",
                                  forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.panelUtilityOrder)
                   == "homebrew,screenshot,cleaner",
                   "utility migration preserves a screenshot position already chosen")
            migrationDefaults.removePersistentDomain(forName: shortcutSuite)
        } else {
            expect(false, "test suite defaults are available")
        }
        expect(registeredDefaults[DefaultsKey.switcherIconRowMode] as? Bool == false,
               "App Switcher icon-row mode is optional")
        expect(registeredDefaults[DefaultsKey.switcherSimpleMode] as? Bool == false,
               "App Switcher simple mode preserves previews until requested")
        expect(SwitcherSupport.usesIconRowLayout(iconRowMode: false, simpleMode: true),
               "App Switcher simple mode always uses the app icon row")
        expect(!SwitcherSupport.capturesPreviews(simpleMode: true),
               "App Switcher simple mode never captures window previews")
        expect(!SwitcherSupport.needsScreenRecording(switcherEnabled: true,
                                                      simpleMode: true,
                                                      dockPreviewEnabled: false),
               "App Switcher simple mode alone does not request Screen Recording")
        expect(SwitcherSupport.needsScreenRecording(switcherEnabled: true,
                                                    simpleMode: false,
                                                    dockPreviewEnabled: false)
               && SwitcherSupport.needsScreenRecording(switcherEnabled: false,
                                                        simpleMode: true,
                                                        dockPreviewEnabled: true),
               "window previews still request Screen Recording where needed")
        let regularBundlePaths: [pid_t: String] = [101: "/Applications/Primary.app"]
        expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Primary.app/Contents/Frameworks/Window Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == 101,
               "App Switcher associates an embedded window helper with its regular host app")
        expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Primary Tools.app/Contents/Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == nil,
               "App Switcher does not associate apps whose paths only share a prefix")
        expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Independent Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == nil,
               "App Switcher leaves unrelated accessory apps independent")
        let embeddedWindow = SwitcherItem.window(id: 77,
                                                 title: "Project",
                                                 appName: "Primary",
                                                 pid: 101,
                                                 windowOwnerPID: 202,
                                                 isOnScreen: true,
                                                 frame: CGRect(x: 20, y: 20, width: 900, height: 600))
        expect(embeddedWindow.pid == 101
               && embeddedWindow.windowOwnerPID == 202
               && embeddedWindow.previewWindowID == 77,
               "App Switcher keeps regular app identity separate from the window owner")
        expect(embeddedWindow.withMinimized(true).windowOwnerPID == 202,
               "App Switcher preserves the real window owner across state updates")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher can start when the foreground app is represented")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 202,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher can start when an embedded helper owns the foreground window")
        let offscreenWindow = SwitcherItem.window(id: 78,
                                                  title: "Archive",
                                                  appName: "Primary",
                                                  pid: 101,
                                                  isOnScreen: false,
                                                  frame: CGRect(x: 20, y: 20, width: 900, height: 600))
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [offscreenWindow]) == nil,
               "App Switcher does not treat an old off-screen window as the foreground surface")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: 78,
                                                 items: [offscreenWindow])?.id == offscreenWindow.id,
               "App Switcher accepts an Accessibility-focused window from outside the CG list")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [offscreenWindow, embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher chooses the on-screen source over an older window from the same app")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: 78,
                                                 items: [offscreenWindow, embeddedWindow])?.id == offscreenWindow.id,
               "App Switcher gives the exact focused source priority over CG ordering")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 404,
                                                 focusedWindowID: nil,
                                                 items: [.appOnly(appName: "Desktop", pid: 404)])?.id == "a:404",
               "App Switcher accepts its intentional app-only desktop entry")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 303,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow]) == nil,
               "App Switcher leaves the system shortcut alone when the foreground app is missing")
        expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/usr/local/bin/wine64-preloader",
            localizedName: "wine64-preloader"),
               "App Switcher recognizes a bare compatibility-layer loader process")
        expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/Users/u/Library/Bottles/games/winetemp-8f3a21/Launcher",
            localizedName: "Launcher"),
               "App Switcher recognizes a bottle loader renamed after its hosted program")
        expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: "com.example.native",
            executablePath: "/Applications/Native.app/Contents/MacOS/wine64-preloader",
            localizedName: "wine64-preloader"),
               "App Switcher never relaxes window rules for bundled apps")
        expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/usr/bin/python3",
            localizedName: "python3"),
               "App Switcher leaves ordinary unbundled processes alone")
        expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: nil,
            localizedName: "wine-preloader"),
               "App Switcher falls back to the process name when the executable is unknown")
        expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: nil,
            localizedName: nil),
               "App Switcher requires a positive signal before relaxing window rules")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: nil,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow]) == nil,
               "App Switcher leaves the system shortcut alone without a foreground app")
        expect(registeredDefaults[DefaultsKey.switcherShowWindowlessFinder] as? Bool == true,
               "Finder without windows stays visible in the switcher by default")
        expect(registeredDefaults[DefaultsKey.dockPreviewEnabled] as? Bool == false,
               "Dock Preview is opt-in for clean installs")
        expect(registeredDefaults[DefaultsKey.autoCheckUpdates] as? Bool == true,
               "update checks are on for clean installs")
        expect(registeredDefaults[DefaultsKey.updateShowcaseIntroVersion] as? String == "",
               "update showcase intro starts unseen")
        expect(registeredDefaults[DefaultsKey.updateShowcaseMediaOverride] as? String == "",
               "update showcase media override is empty by default")
        expect(SupportUpdateIntroInfo.releaseVersion == "3.1.13",
               "support prompt is deliberately pinned to 3.1.13")
        expect(SupportUpdateIntroInfo.shouldShow(appVersion: "3.1.13", lastSeenVersion: "3.1.12"),
               "support prompt shows once after updating to its pinned release")
        expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.1.13", lastSeenVersion: "3.1.13"),
               "support prompt stays hidden after it is seen")
        expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.1.12", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.1.14", lastSeenVersion: nil),
               "support prompt never leaks into another release")
        expect(SupportUpdateIntroInfo.installCommand == "brew install --cask vorssaint",
               "official Homebrew install command stays unqualified")
        expect(SupportUpdateIntroInfo.migrationCommand == "brew untap --force vorssaint/tap",
               "old tap migration removes only the tap")
        expect(SupportUpdateIntroStep.homebrew.next == .community
               && SupportUpdateIntroStep.community.next == .support
               && SupportUpdateIntroStep.support.next == nil,
               "update intro keeps Homebrew before community and support")
        expect(SupportUpdateIntroStep.homebrew.previous == nil
               && SupportUpdateIntroStep.community.previous == .homebrew
               && SupportUpdateIntroStep.support.previous == .community,
               "update intro navigates back without closing")
        // AppInfo.version falls back to "dev" in this bare harness, so read
        // the plist the shipped app will actually carry. The pin is a
        // per-release decision: this check fails on every version bump so the
        // decision above is made consciously, never by omission.
        let plistVersion = (NSDictionary(contentsOfFile: "Resources/Info.plist")?["CFBundleShortVersionString"] as? String) ?? ""
        expect(plistVersion == "3.1.15",
               "bumping the app version requires re-deciding the support prompt pin above")
        // 3.1.15 ships as a fix-only release with no new features to tour, so
        // the highlights pin stays on the last feature release (3.1.14) and the
        // tour does not re-appear. A feature release re-curates the rows and
        // moves this pin to the shipping version.
        expect(UpdateHighlightsInfo.releaseVersion == "3.1.14",
               "re-decide the highlights tour on a feature release: re-curate its rows and move the pin to the shipping version")
        expect(UpdateHighlightsInfo.shouldShow(appVersion: "3.1.14", lastSeenVersion: "3.1.13")
               && UpdateHighlightsInfo.shouldShow(appVersion: "3.1.14", lastSeenVersion: nil),
               "highlights tour shows once after updating to its pinned release")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.1.14", lastSeenVersion: "3.1.14"),
               "highlights tour stays hidden after it is seen")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.1.15", lastSeenVersion: nil),
               "highlights tour never leaks into another release")
        expect(registeredDefaults[DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect] as? Bool == false,
               "headphone disconnect volume lowering is opt-in")
        expect(registeredDefaults[DefaultsKey.mixerHeadphonesDisconnectVolumePercent] as? Int == 0,
               "headphone disconnect volume keeps the existing mute behavior by default")
        expect(registeredDefaults[DefaultsKey.mixerShowFinder] as? Bool == true,
               "Finder returns to the mixer by default")
        expect(registeredDefaults[DefaultsKey.soundOutputSwitcherEnabled] as? Bool == false,
               "sound output switcher is opt-in")
        expect(registeredDefaults[DefaultsKey.soundOutputSwitcherShortcut] as? String
               == GlobalShortcut.soundOutputSwitcherDefault.storageValue,
               "sound output switcher shortcut has a registered default")
        expect(registeredDefaults[DefaultsKey.shelfShortcutEnabled] as? Bool == true,
               "shelf shortcut is on by default once shelf is enabled")
        expect(registeredDefaults[DefaultsKey.shelfShortcut] as? String == "control+option+command:2",
               "shelf shortcut defaults to Ctrl+Opt+Cmd+D")
        expect(registeredDefaults[DefaultsKey.shelfShakeToOpen] as? Bool == true,
               "shelf shake opens by default once shelf is enabled")
        expect(registeredDefaults[DefaultsKey.shelfCloseAfterDrop] as? Bool == false,
               "closing after a drop is new behavior and must arrive off in an update")
        expect(registeredDefaults[DefaultsKey.shelfRemoveAfterDrop] as? Bool == true,
               "shelf removes accepted items after a drop by default")
        expect((registeredDefaults[DefaultsKey.shelfAutomaticExclusions] as? [String])?.isEmpty == true,
               "shelf automatic exclusions start empty")
        expect(registeredDefaults[DefaultsKey.mouseNavigationEnabled] as? Bool == false,
               "mouse side-button navigation is opt-in")
        expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcutEnabled] as? Bool == true,
               "clipboard history shortcut is ready when clipboard history is enabled")
        expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcut] as? String
               == GlobalShortcut.clipboardDefault.storageValue,
               "clipboard history shortcut defaults to Ctrl+Opt+Cmd+V")
        expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.command])
                   .isStandardPasteCommand,
               "Cmd+V is recognized when plain-text paste must release its own hotkey")
        expect(!GlobalShortcut.pastePlainDefault.isStandardPasteCommand,
               "the default plain-text paste shortcut does not intercept synthesized Cmd+V")
        expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_C), modifiers: [.command])
                   .isStandardPasteCommand,
               "other Command shortcuts never release the plain-text paste hotkey")
        expect(registeredDefaults[DefaultsKey.urlCleanerEnabled] as? Bool == false,
               "URL cleaner clipboard watching is opt-in")
        expect(registeredDefaults[DefaultsKey.windowMaximizeEnabled] as? Bool == false,
               "green button maximize override is opt-in")
        expect(registeredDefaults[DefaultsKey.keyboardDebounceEnabled] as? Bool == false,
               "keyboard debounce is opt-in")
        expect(registeredDefaults[DefaultsKey.keyboardDebounceWindowMs] as? Int == 5,
               "keyboard debounce default window starts low")
        expect(registeredDefaults[DefaultsKey.keyboardDebounceKeyWindows] as? String == "",
               "keyboard debounce per-key windows start empty")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaning] as? Bool == true,
               "panel cleaning utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityURLCleaner] as? Bool == true,
               "panel URL cleaner utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityUninstaller] as? Bool == true,
               "panel uninstaller utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityHomebrew] as? Bool == true,
               "panel Homebrew utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityMedia] as? Bool == true,
               "panel Media utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlMouseScroll] as? Bool == true,
               "panel mouse scroll control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlMouseNavigation] as? Bool == true,
               "panel mouse navigation control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlSwitcher] as? Bool == true,
               "panel switcher control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlDockPreview] as? Bool == true,
               "panel Dock Preview control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlCutPaste] as? Bool == true,
               "panel cut and paste control is visible by default")
        expect(registeredDefaults[DefaultsKey.colorPickerBareHex] as? Bool == false,
               "color picker keeps the # prefix by default")
        expect(registeredDefaults[DefaultsKey.screenOCRDetectQRCodes] as? Bool == true,
               "copy text from screen reads QR codes by default")
        expect(registeredDefaults[DefaultsKey.micMuteMenuBarIndicator] as? Bool == true,
               "mic mute menu bar indicator ships on by default (badge only shows while muted)")
        expect(registeredDefaults[DefaultsKey.menuBarMetricSpacing] as? String == "compact",
               "menu bar metric spacing defaults to the compact look")
        expect(registeredDefaults[DefaultsKey.menuBarMetricAppearance] as? String == "values",
               "menu bar usage metrics keep numeric values by default")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarNormalColor] as? String == "#64D2FF",
               "menu bar bars use a bright normal color by default")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarElevatedColor] as? String == "#FFD60A"
               && registeredDefaults[DefaultsKey.menuBarUsageBarCriticalColor] as? String == "#FF453A",
               "menu bar bars keep visible elevated and critical defaults")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarMediumThreshold] as? Int == 70
               && registeredDefaults[DefaultsKey.menuBarUsageBarHighThreshold] as? Int == 90,
               "menu bar bar thresholds default to seventy and ninety percent")
        expect(Defaults.sanitizedMonitorAlertCooldown(2) == 2,
               "the two minute alert cooldown is a valid stored choice")
        expect(Defaults.sanitizedMonitorAlertCooldown(7) == 15,
               "unknown alert cooldowns fall back to fifteen minutes")
        expect(Defaults.sanitizedMenuBarMetricSpacing("standard") == "standard",
               "standard menu bar spacing is a valid stored choice")
        expect(Defaults.sanitizedMenuBarMetricSpacing("banana") == "compact",
               "unknown menu bar spacing values fall back to the compact default")
        expect(Defaults.sanitizedMenuBarMetricAppearance("bars") == "bars",
               "bar appearance is a valid stored choice")
        expect(Defaults.sanitizedMenuBarMetricAppearance("banana") == "values",
               "unknown menu bar appearances fall back to numeric values")
        expect(MenuBarMetricAppearance.values.allowsCombinedTemperatures,
               "numeric menu bar values may combine usage and temperature")
        expect(!MenuBarMetricAppearance.bars.allowsCombinedTemperatures,
               "menu bar bars keep usage and temperature separate")
        expectClose(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 4) ?? -1, 0.75,
                    "menu bar memory bars use the current used fraction")
        expect(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 0) == nil,
               "menu bar memory bars keep missing totals unavailable")
        expectClose(MenuBarUsageBarSupport.clampedFraction(-0.2), 0,
                    "menu bar bars clamp negative readings")
        expectClose(MenuBarUsageBarSupport.clampedFraction(1.4), 1,
                    "menu bar bars clamp readings above full")
        expect(MenuBarUsageBarSupport.fillLevel(for: 0.5, steps: 16) == 8,
               "menu bar bars quantize fractions to visible fill steps")
        expect(MenuBarUsageBarSupport.level(for: 0.69) == .normal,
               "menu bar usage stays blue below seventy percent")
        expect(MenuBarUsageBarSupport.level(for: 0.70) == .elevated,
               "menu bar usage turns yellow at seventy percent")
        expect(MenuBarUsageBarSupport.level(for: 0.89) == .elevated,
               "menu bar usage stays yellow below ninety percent")
        expect(MenuBarUsageBarSupport.level(for: 0.90) == .critical,
               "menu bar usage turns red at ninety percent")
        expect(MenuBarUsageBarSupport.level(for: 0.50,
                                            mediumPercent: 40,
                                            highPercent: 80) == .elevated,
               "custom menu bar medium thresholds change the bar level")
        expect(MenuBarUsageBarSupport.level(for: 0.80,
                                            mediumPercent: 40,
                                            highPercent: 80) == .critical,
               "custom menu bar high thresholds change the bar level")
        let repairedBarThresholds = MenuBarUsageBarSupport.thresholds(medium: 100, high: 20)
        expect(repairedBarThresholds.medium == 99 && repairedBarThresholds.high == 100,
               "invalid menu bar thresholds keep medium below high")
        expect(MenuBarUsageBarSupport.sanitizedColorHex(" 64d2ff ", fallback: "#000000") == "#64D2FF",
               "menu bar colors normalize stored hex values")
        expect(MenuBarUsageBarSupport.sanitizedColorHex("bad", fallback: "#FFD60A") == "#FFD60A",
               "invalid menu bar colors use their visible fallback")
        let customBarRGB = MenuBarUsageBarSupport.rgb(for: "#804020", fallback: "#000000")
        expectClose(customBarRGB.red, 128.0 / 255.0, "menu bar color parses red")
        expectClose(customBarRGB.green, 64.0 / 255.0, "menu bar color parses green")
        expectClose(customBarRGB.blue, 32.0 / 255.0, "menu bar color parses blue")
        expect(MenuBarUsageBarSupport.hex(red: 1, green: 0.5, blue: 0) == "#FF8000",
               "menu bar color picker writes stable hex values")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%") == "88%",
               "compact spacing reserves the current digit count for percentages")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "999°") == "888°",
               "compact spacing reserves the current digit count for temperatures")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "1.5M") == "8.8M",
               "compact spacing keeps units and separators while widening digits")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "") == "",
               "compact spacing reserve of an empty value stays empty")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "4%", minimumDigits: 2) == "88%",
               "compact spacing pads single digits up to the stability floor")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%", minimumDigits: 2) == "88%",
               "a one and a two digit value reserve the same width, so 4% to 10% never moves the bar")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "100%", minimumDigits: 2) == "888%",
               "values above the floor keep their own digit count")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 1, highWater: nil) == 2,
               "the compact floor starts at two digits")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 3, highWater: 2) == 3,
               "a three digit value raises the floor")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 2, highWater: 3) == 3,
               "the session high-water mark keeps a block from shrinking back and wobbling")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .standard) == " ",
               "standard dense spacing keeps the full space between blocks")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .compact) == "\u{200A}",
               "compact dense spacing joins blocks with a hair space")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: true, spacing: .compact) == " ",
               "compact readable spacing tightens the double space to a single one")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1135, reportedMidX: 1452, buttonWidth: 38) == -317,
               "a click far left of the status item's reported frame re-anchors the panel at the click")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1452, reportedMidX: 1135, buttonWidth: 38) == 317,
               "a click far right of the status item's reported frame re-anchors the panel at the click")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1150, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a click inside the status button never counts as drift")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1186, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a sloppy click just past the button edge stays within the drift slack")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1188, reportedMidX: 1144, buttonWidth: 38) == 44,
               "a click beyond the slack re-anchors by the full offset")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1240, reportedMidX: 1144, buttonWidth: 197) == nil,
               "clicks near the edge of a wide metrics item stay anchored to the item")

        // The built-in display and a taller one placed to its left.
        let builtInScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let secondScreen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let attachedScreens = [builtInScreen, secondScreen]
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 932, width: 0, height: 0),
                                                                 screenFrames: attachedScreens),
               "a status item frame with no size is never an anchor")
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 950, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a status item parked above the top edge is not an anchor")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "a status item sitting in the menu bar band is a trustworthy anchor")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: -1000, y: 1143, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "the menu bar band follows each screen's own top edge")
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 0, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a frame down at the bottom of a screen is not a menu bar item")

        // The panel keeps its top edge and its center while its content resizes.
        let panelArea = CGRect(x: 0, y: 0, width: 1470, height: 932)
        let shortPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                  anchorMidX: 1283, anchorTop: 932,
                                                                  visibleFrame: panelArea)
        let tallPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                                 anchorMidX: 1283, anchorTop: 932,
                                                                 visibleFrame: panelArea)
        let shrunkPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                   anchorMidX: 1283, anchorTop: 932,
                                                                   visibleFrame: panelArea)
        expect(shortPanel.midX == 1283 && tallPanel.midX == 1283 && shrunkPanel.midX == 1283,
               "the pinned panel stays centered on its anchor through a content resize")
        expect(shortPanel.maxY == 932 && tallPanel.maxY == 932 && shrunkPanel.maxY == 932,
               "a taller panel grows downward instead of moving its top edge")
        expect(shortPanel == shrunkPanel,
               "going back to the first tab lands the panel exactly where it started")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 20, anchorTop: 932,
                                                        visibleFrame: panelArea).minX == 8,
               "a panel anchored past the left edge stops at the margin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 1465, anchorTop: 932,
                                                        visibleFrame: panelArea).maxX == 1462,
               "a panel anchored past the right edge stops at the margin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: -1910, anchorTop: 1155,
                                                        visibleFrame: CGRect(x: -1920, y: 100,
                                                                             width: 1920, height: 1055))
                == CGRect(x: -1912, y: 780, width: 332, height: 375),
               "a display left of the built-in one clamps against its own negative origin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                        anchorMidX: 700, anchorTop: 300,
                                                        visibleFrame: CGRect(x: 0, y: 0,
                                                                             width: 1470, height: 300)).maxY == 300,
               "a screen too short for the panel still shows its top")
        expect(registeredDefaults[DefaultsKey.menuBarHideIconWithMetrics] as? Bool == false,
               "the menu bar icon stays visible by default")
        expect(MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                          metricsEnabled: true, renderedTitleLength: 12,
                                                          mustShowForSignal: false),
               "the glyph hides when metrics render in the title and the option is on")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: false, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: false),
               "the glyph never hides while the option is off")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 0,
                                                           mustShowForSignal: false),
               "an empty rendered title keeps the glyph, so the item can never turn invisible")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: false, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "a countdown-only title keeps the glyph when no metric is enabled")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: true,
                                                           metricsEnabled: true, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "separate metric items keep the glyph in the otherwise empty main item")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: true),
               "an available update or muted mic brings the glyph back to carry the signal")
        expect(MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                              metricItemsShown: 2, renderedTitleLength: 0,
                                                              mustShowForSignal: false),
               "with separate metric items installed the whole main item may step aside")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 0, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "no installed metric items keep the main item, so the app never vanishes")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 5,
                                                               mustShowForSignal: false),
               "an active countdown renders in the main item and keeps it visible")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: false,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "the whole-item hiding only applies to the separate-items mode")

        // A pinned metric that momentarily has nothing to show keeps its item
        // instead of being taken away and put back every tick.
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: false),
               "a metric with something to show gets its own item")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: true,
                                                           consecutiveEmptyRenders: 1),
               "a reading that goes missing for a tick blanks its item instead of removing it")
        expect(!MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: false, itemExists: true,
            consecutiveEmptyRenders: MenuBarSpacingSupport.emptyMetricRendersBeforeRemoval),
               "a reading that stops for good takes its item away instead of leaving a gap")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: true, itemExists: true,
            consecutiveEmptyRenders: 99),
               "a reading that comes back keeps its item whatever came before")
        expect(!MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: false),
               "a metric with nothing to show yet gets no item at all")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: true),
               "an item already showing a reading stays")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: true),
               "a signal brings the main item back even in the separate-items mode")
        expect(registeredDefaults[DefaultsKey.panelControlAutoQuit] as? Bool == true,
               "panel auto quit control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlShelf] as? Bool == true,
               "panel shelf control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlWindowMaximize] as? Bool == true,
               "panel window maximize control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlKeyDebounce] as? Bool == true,
               "panel keyboard debounce control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlTextSnippets] as? Bool == true,
               "panel text snippets control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelShowKeepAwake] as? Bool == true,
               "Keep Awake panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowBrightness] as? Bool == true,
               "brightness panel section is shown by default once the feature is on")
        expect(registeredDefaults[DefaultsKey.brightnessControlEnabled] as? Bool == false,
               "brightness control arrives switched off")
        expect(registeredDefaults[DefaultsKey.brightnessKeysEnabled] as? Bool == false,
               "pointer-following brightness keys arrive switched off")
        expect(registeredDefaults[DefaultsKey.brightnessOSDEnabled] as? Bool == false,
               "brightness adjustment overlay arrives switched off")
        expect(registeredDefaults[DefaultsKey.screenshotOpenEditorDirectly] as? Bool == false,
               "capture keeps showing the preview unless the user opts into the editor")
        expect(registeredDefaults[DefaultsKey.panelShowUtilities] as? Bool == true,
               "Utilities panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowControls] as? Bool == true,
               "Quick Controls panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowToggles] as? Bool == true,
               "Quick toggles panel section is shown by default")
        expect([DefaultsKey.panelToggleDarkMode, DefaultsKey.panelToggleEmptyTrash,
                DefaultsKey.panelToggleEjectDisks, DefaultsKey.panelToggleHiddenFiles,
                DefaultsKey.panelToggleDesktopIcons, DefaultsKey.panelToggleLockScreen,
                DefaultsKey.panelToggleDisplayOff, DefaultsKey.panelToggleScreenSaver]
                .allSatisfy { registeredDefaults[$0] as? Bool == true },
               "every quick toggle row is visible by default")
        expect(registeredDefaults[DefaultsKey.monitorInterval] as? Int == 2,
               "monitor default interval stays at 2 seconds")
        expect(registeredDefaults[DefaultsKey.monitorShowDisk] as? Bool == true,
               "disk monitor panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorSysAlerts] as? Bool == true,
               "system alert controls are shown by default")
        expect(registeredDefaults[DefaultsKey.monitorGraphDisk] as? Bool == true,
               "disk monitor graph is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorNetApps] as? Bool == true,
               "network app usage block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskUsage] as? Bool == true,
               "disk usage block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskActivity] as? Bool == true,
               "disk activity block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskSMART] as? Bool == true,
               "disk SMART block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskProtection] as? Bool == true,
               "disk protection block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskTools] as? Bool == true,
               "disk tools block is shown by default")
        expect(registeredDefaults[DefaultsKey.temperatureUnit] as? String == TemperatureUnit.celsius.rawValue,
               "temperature defaults to Celsius")
        expect(registeredDefaults[DefaultsKey.menuBarCPUTemperature] as? Bool == false,
               "menu bar CPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarGPUTemperature] as? Bool == false,
               "menu bar GPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTemperature] as? Bool == false,
               "menu bar battery temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTime] as? Bool == false,
               "menu bar battery time is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarDiskUsage] as? Bool == false,
               "menu bar disk usage is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarDiskActivity] as? Bool == false,
               "menu bar disk activity is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarPeripheralBattery] as? Bool == false,
               "menu bar peripheral battery is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarMetricOrder] as? String
               == "cpu,cpuTemperature,gpu,gpuTemperature,memory,battery,batteryTime,batteryTemperature,peripheralBattery,network,diskUsage,diskActivity,power",
               "menu bar metric order keeps temperature sensors next to their components and disk near live I/O")
        expect(registeredDefaults[DefaultsKey.menuBarCombineTemperatures] as? Bool == true,
               "menu bar combines usage and temperature by default")
        expect(registeredDefaults[DefaultsKey.menuBarSeparateMetrics] as? Bool == false,
               "separate menu bar metric items are opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarNetworkUploadFirst] as? Bool == false,
               "network menu bar upload-first layout is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarLabelStyle] as? String == "compact",
               "menu bar label style defaults to compact")
        expect(registeredDefaults[DefaultsKey.menuBarMemoryStyle] as? String == "percent",
               "memory menu bar style defaults to percent")
        expect(registeredDefaults[DefaultsKey.monitorPwrTimeRemaining] as? Bool == true,
               "battery time is shown in the Power panel by default")
        expect(registeredDefaults[DefaultsKey.windowLayoutShortcutsEnabled] as? Bool == false,
               "window layout shortcuts stay off until enabled")
        expect(registeredDefaults[DefaultsKey.windowGestureEnabled] as? Bool == false,
               "window move and resize gestures are opt-in")
        expect(registeredDefaults[DefaultsKey.windowGestureModifiers] as? String == "control+command",
               "window gestures start with the deliberate control-command chord")
        expect(registeredDefaults[DefaultsKey.windowGestureRaiseWindow] as? Bool == false,
               "window gestures do not change app focus unless requested")
        let assignedLayoutShortcutKeys = [
            DefaultsKey.windowLayoutShortcutLeft,
            DefaultsKey.windowLayoutShortcutRight,
            DefaultsKey.windowLayoutShortcutTop,
            DefaultsKey.windowLayoutShortcutBottom,
            DefaultsKey.windowLayoutShortcutTopLeft,
            DefaultsKey.windowLayoutShortcutTopRight,
            DefaultsKey.windowLayoutShortcutBottomLeft,
            DefaultsKey.windowLayoutShortcutBottomRight,
            DefaultsKey.windowLayoutShortcutMaximize,
            DefaultsKey.windowLayoutShortcutCenter,
            DefaultsKey.windowLayoutShortcutRestore,
            DefaultsKey.windowLayoutShortcutLeftThird,
            DefaultsKey.windowLayoutShortcutCenterThird,
            DefaultsKey.windowLayoutShortcutRightThird,
            DefaultsKey.windowLayoutShortcutLeftTwoThirds,
            DefaultsKey.windowLayoutShortcutRightTwoThirds,
            DefaultsKey.windowLayoutShortcutNextDisplay,
        ]
        let assignedLayoutShortcutValues = assignedLayoutShortcutKeys.compactMap {
            registeredDefaults[$0] as? String
        }
        expect(assignedLayoutShortcutValues.count == assignedLayoutShortcutKeys.count,
               "every established window layout action has a registered shortcut")
        let unassignedSixthShortcutKeys = [
            DefaultsKey.windowLayoutShortcutTopLeftSixth,
            DefaultsKey.windowLayoutShortcutTopCenterSixth,
            DefaultsKey.windowLayoutShortcutTopRightSixth,
            DefaultsKey.windowLayoutShortcutBottomLeftSixth,
            DefaultsKey.windowLayoutShortcutBottomCenterSixth,
            DefaultsKey.windowLayoutShortcutBottomRightSixth,
        ]
        expect(unassignedSixthShortcutKeys.allSatisfy {
                   registeredDefaults[$0] as? String == WindowLayoutAction.clearedShortcutStorageValue
               },
               "sixth layout shortcuts start unassigned")
        expect(Set(assignedLayoutShortcutValues).count == assignedLayoutShortcutValues.count,
               "window layout shortcuts do not conflict with each other by default")
        let globalShortcutValues = GlobalShortcutRole.allCases
            .compactMap { registeredDefaults[$0.storageKey] as? String }
        expect(Set(assignedLayoutShortcutValues).intersection(globalShortcutValues).isEmpty,
               "window layout shortcuts do not conflict with other global shortcuts by default")
        expect(GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                              modifiers: [.control, .option, .command]).isValid,
               "the extra ISO key (paragraph/caret above Tab) is recordable as a shortcut")
        expect(registeredDefaults[DefaultsKey.extraBrightnessEnabled] as? Bool == false,
               "extra brightness is opt-in")
        expect(registeredDefaults[DefaultsKey.extraBrightnessLevel] as? Int == 100,
               "extra brightness starts at full intensity once enabled")
        expect(registeredDefaults[DefaultsKey.musicBlockEnabled] as? Bool == false,
               "blocking the music app from launching is opt-in")
        expect(registeredDefaults[DefaultsKey.musicBlockReplacementPath] as? String == "",
               "the music replacement app starts unset")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaner] as? Bool == true,
               "the cleaner row is visible in the panel utilities like its siblings")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleFrequency] as? String == "off",
               "automatic cleanup is opt-in")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleHour] as? Int == 9
               && registeredDefaults[DefaultsKey.cleanerScheduleMinute] as? Int == 0
               && registeredDefaults[DefaultsKey.cleanerScheduleWeekday] as? Int == 2,
               "the schedule defaults to nine in the morning on Mondays")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleNotify] as? Bool == true,
               "the schedule reports its outcome unless the user opts out")
        expect(registeredDefaults[DefaultsKey.cleanerBadgeSeen] as? Bool == false,
               "the red dot guiding to the cleaner shows until the cleaner opens once")
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
        expect(CleanerSupport.isProtectedBundleID("com.apple.Music")
               && CleanerSupport.isProtectedBundleID("com.apple")
               && CleanerSupport.isProtectedBundleID("group.com.apple.notes")
               && CleanerSupport.isProtectedBundleID("com.vorssaint.utils"),
               "system domains and this app can never be junk owners")
        expect(!CleanerSupport.isProtectedBundleID("com.vendor.editor"),
               "third party identifiers are eligible for the leftover check")
        expect(CleanerSupport.isProtectedBundleID("systemgroup.com.apple.icloud.searchpartyd.sharedsettings")
               && CleanerSupport.isProtectedBundleID("243LU875E5.groups.com.apple.podcasts")
               && CleanerSupport.isProtectedBundleID("developer.apple.wwdc")
               && CleanerSupport.isProtectedBundleID("is.workflow.my.app")
               && CleanerSupport.isProtectedBundleID("vorss.tests.switcher.shortcut"),
               "system domains stay protected in every wrapping, team prefixes included")
        expect(CleanerSupport.sharedInfrastructurePrefixes.allSatisfy {
                   CleanerSupport.isProtectedBundleID($0)
               },
               "embedded updaters and crash reporters can never be junk owners")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "systemgroup.com.apple.icloud.sharedsettings.plist")
               == "com.apple.icloud.sharedsettings",
               "systemgroup wrappers unwrap to the real owner")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.editor.Helper.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist") == nil,
               "names carrying a UUID are unattributable and never candidates")
        expect(CleanerSupport.containsUUIDComponent("x.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F")
               && !CleanerSupport.containsUUIDComponent("com.vendor.editor"),
               "the UUID detector matches dashed UUIDs and nothing else")
        expect(CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.backgroundtool",
                                                    withInstalled: ["com.vendor.editor"])
               && CleanerSupport.sharesVendorNamespace(candidate: "com.publisher.agent",
                                                       withInstalled: ["com.publisher.browser"]),
               "a vendor's updaters are owned while any app of that vendor is installed")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.editor",
                                                     withInstalled: ["com.publisher.browser"]),
               "different vendors never own each other")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "io.github.account.tool",
                                                     withInstalled: ["io.github.other.app"]),
               "code hosting namespaces are shared by unrelated developers and never match")
        expect(CleanerPolicy.precheckCacheEntry("Homebrew")
               && CleanerPolicy.precheckCacheEntry("com.vendor.editor"),
               "download caches and third party app caches start checked")
        expect(!CleanerPolicy.precheckCacheEntry("PlainVendorFolder")
               && !CleanerPolicy.precheckCacheEntry("com.apple.Music")
               && !CleanerPolicy.precheckCacheEntry("com.spotify.client")
               && !CleanerPolicy.precheckCacheEntry("ms-playwright"),
               "system, sensitive and unattributable caches start unchecked")
        expect(CleanerSupport.Category.deviceBackups.rawValue == 6
               && CleanerSupport.Category.allCases.count == 7,
               "device backups joined the cleaner with a stable category id")
        expect(!CleanerPolicy.precheckDeviceBackups,
               "device backups never start checked, they are the user's safety net")
        expect(CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/iOS DeviceSupport")
               && CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/watchOS DeviceSupport"),
               "stale DeviceSupport symbol caches count as developer junk")
        expect(CleanerSupport.looksLikeBundleID("com.vendor.editor")
               && CleanerSupport.looksLikeBundleID("com.foo.Bar-Helper_2"),
               "reverse DNS names are recognized")
        expect(!CleanerSupport.looksLikeBundleID("VendorFolder")
               && !CleanerSupport.looksLikeBundleID("com.foo")
               && !CleanerSupport.looksLikeBundleID("com..foo")
               && !CleanerSupport.looksLikeBundleID("com.foo.bár"),
               "plain names, short names and odd characters never match by name")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.plist") == "com.vendor.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.com.foo.bar") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.savedState") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.binarycookies") == "com.foo.bar",
               "entry names map to their owning bundle identifier")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "VendorFolder") == nil,
               "folders without a bundle shaped name are never candidates")
        expect(CleanerSupport.isOwned(candidate: "com.vendor.editor.startuphelper",
                                      byInstalled: ["com.vendor.editor"]),
               "embedded helper identifiers are owned by their installed app")
        expect(CleanerSupport.isOwned(candidate: "com.maker",
                                      byInstalled: ["com.maker.app"]),
               "a family prefix of an installed app counts as owned")
        expect(!CleanerSupport.isOwned(candidate: "com.vendor.editor", byInstalled: ["com.publisher.browser"]),
               "identifiers with no installed relative are unowned")
        expect(!CleanerSupport.isOwned(candidate: "com.makerapp.tool", byInstalled: ["com.maker.app"]),
               "prefix ownership requires a dot boundary, not a string prefix")
        expect(CleanerSupport.executablePaths(inLaunchPlist: [
                   "Program": "/Applications/Gone.app/Contents/MacOS/agent",
                   "ProgramArguments": ["/usr/local/bin/gone-tool", "--flag"],
                   "BundleProgram": "Contents/MacOS/relative",
               ]) == ["/Applications/Gone.app/Contents/MacOS/agent", "/usr/local/bin/gone-tool"],
               "launch plists yield their absolute executables and skip relative ones")
        expect(CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                           executables: ["/Applications/Gone.app/x"],
                                                           executableExists: { _ in false }),
               "a plist whose executables are all gone is a removable orphan")
        expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                            executables: ["/bin/ls"],
                                                            executableExists: { _ in true }),
               "a plist with a living executable is never an orphan")
        expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.apple.something",
                                                            executables: ["/gone"],
                                                            executableExists: { _ in false })
               && !CleanerSupport.launchPlistIsRemovableOrphan(label: nil,
                                                               executables: [],
                                                               executableExists: { _ in false }),
               "system agents and undecidable plists are never offered")
        expect(registeredDefaults[DefaultsKey.mediaLastTool] as? String == MediaTool.videoCompressor.rawValue,
               "Media defaults to video compressor")
        expect(registeredDefaults[DefaultsKey.mediaVideoCodec] as? String == MediaVideoCodec.h264.rawValue,
               "Media video codec defaults to H.264")
        expect(registeredDefaults[DefaultsKey.mediaImageFormat] as? String == MediaImageFormat.jpeg.rawValue,
               "Media image format defaults to JPEG")
        expect((registeredDefaults[DefaultsKey.autoQuitExceptions] as? [String]) == Defaults.mandatoryAutoQuitExceptionBundleIDs,
               "Finder stays in the default auto-quit exception list")
        expect(registeredDefaults[DefaultsKey.panelCollapsedSections] == nil,
               "panel collapsed sections intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelUtilityOrder] == nil,
               "panel utility order intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelToggleOrder] == nil,
               "panel toggle order intentionally has no registered default")
        expect(Defaults.sanitizedDefaultDuration(60) == 60, "valid default duration is preserved")
        expect(Defaults.sanitizedDefaultDuration(999) == 0, "invalid default duration falls back to indefinite")
        expect(Defaults.sanitizedBatteryLimit(15) == 15, "valid battery limit is preserved")
        expect(Defaults.sanitizedBatteryLimit(100) == 10, "invalid battery limit falls back to default")
        expect(Defaults.sanitizedClipboardHistoryLimit(1_000) == 1_000,
               "larger clipboard history limits are preserved")
        expect(Defaults.sanitizedClipboardHistoryLimit(999) == 50,
               "unsupported clipboard history limits fall back to default")
        expect(Defaults.sanitizedMonitorInterval(5) == 5, "valid monitor interval is preserved")
        expect(Defaults.sanitizedMonitorInterval(7) == 2, "invalid monitor interval falls back to default")
        expect(Defaults.sanitizedKeyboardDebounceWindow(80) == 80,
               "valid debounce window is preserved")
        expect(Defaults.sanitizedKeyboardDebounceWindow(999) == Defaults.defaultKeyboardDebounceWindowMs,
               "invalid debounce window falls back to default")
        expect(Defaults.sanitizedMenuBarLabelStyle("classic") == "classic", "valid label style is preserved")
        expect(Defaults.sanitizedMenuBarLabelStyle("bad") == "compact", "invalid label style falls back to compact")
        expect(Defaults.sanitizedMenuBarMemoryStyle("percent") == "percent", "percent memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("dot") == "dot", "valid memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("both") == "both", "combined memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("bad") == "percent", "invalid memory style falls back to percent")
        expect(Defaults.sanitizedMenuBarMetricOrder("cpu,gpu,memory,network,battery,power")
               == ["cpu", "gpu", "memory", "network", "battery", "power",
                   "cpuTemperature", "gpuTemperature", "batteryTime", "batteryTemperature", "peripheralBattery", "diskUsage", "diskActivity"],
               "menu bar metric order appends temperature sensors without rewriting existing saved order")
        expect(Defaults.sanitizedMenuBarMetricOrder("temperature,cpu,cpu,bad")
               == ["cpuTemperature", "gpuTemperature", "batteryTemperature",
                   "cpu", "gpu", "memory", "battery", "batteryTime", "peripheralBattery", "network", "diskUsage", "diskActivity", "power"],
               "menu bar metric order migrates the old generic temperature value")
        expect(Defaults.sanitizedBundleIdentifierList([" com.example.One ", "", "com.example.One", "com.example.Two"])
               == ["com.example.One", "com.example.Two"],
               "bundle id lists are trimmed and deduplicated")
        expect(Defaults.sanitizedAutoQuitExceptions(["com.example.One", Defaults.finderBundleIdentifier])
               == [Defaults.finderBundleIdentifier, "com.example.One"],
               "Finder is mandatory in the auto-quit exception list")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appDeactivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app deactivation as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .mainWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat main window changes as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .focusedWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat focused window changes as a window close")
        expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .windowDestroyed,
                                                         hasRecentCloseRequest: false),
               "AutoQuit checks windows after a destroyed window")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                          hasRecentCloseRequest: false),
               "AutoQuit ignores hidden apps without a recent close request")
        expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                         hasRecentCloseRequest: true),
               "AutoQuit checks hidden apps after a recent close request")
        expect(AutoQuitSupport.isCommandW(keyCode: 13, command: true, control: false),
               "AutoQuit treats Command W as a close request")
        expect(!AutoQuitSupport.isCommandW(keyCode: 18, command: true, control: true),
               "AutoQuit does not treat Control number Space switching as a close request")
        expect(AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                          appIsTerminated: false,
                                                          appIsExcepted: false,
                                                          appIsHidden: false,
                                                          hiddenByCloseRequest: false,
                                                          hasKnownMinimizedWindow: false,
                                                          hasUserFacingWindow: false),
               "AutoQuit can quit when an app that had windows is now windowless")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: false,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit does not quit apps that started windowless")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: true,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps excepted apps running")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: true,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps hidden apps running without explicit close intent")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: true,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps apps running when a minimized window is known")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: true),
               "AutoQuit keeps apps with user-facing windows running")
        expect(Defaults.sanitizedPanelItemOrder("uninstaller,homebrew,homebrew,bad",
                                                defaultOrder: ["homebrew", "media", "uninstaller", "cleanURL", "cleaning"])
               == ["uninstaller", "homebrew", "media", "cleanURL", "cleaning"],
               "panel item order keeps saved valid items first and appends defaults")

        // MARK: Window layout shortcut resolution (issue #169)

        expect(WindowLayoutAction.resolvedShortcut(storedValue: nil,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "window layout falls back to the default shortcut when nothing was saved")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: WindowLayoutAction.clearedShortcutStorageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault) == nil,
               "a cleared window layout shortcut resolves to no shortcut at all")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value",
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "a corrupt stored shortcut falls back to the default, never to cleared")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: GlobalShortcut.windowLayoutRightDefault.storageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutRightDefault,
               "a saved window layout shortcut wins over the default")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: nil, defaultShortcut: nil) == nil,
               "a window layout action without a default shortcut stays unassigned")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value", defaultShortcut: nil) == nil,
               "a corrupt shortcut cannot assign an action that has no default")

        // MARK: Window layout geometry

        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let currentWindow = CGRect(x: 200, y: 200, width: 800, height: 500)
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 860),
               "window layout left half targets the full left side")
        expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 860),
               "window layout right half targets the full right side")
        expect(WindowLayoutGeometry.rect(for: .topHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 1440, height: 430),
               "window layout top half targets the upper visible frame")
        expect(WindowLayoutGeometry.rect(for: .bottomHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1440, height: 430),
               "window layout bottom half targets the lower visible frame")
        expect(WindowLayoutGeometry.rect(for: .leftThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 480, height: 860),
               "window layout left third targets the first third")
        expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 480, height: 860),
               "window layout center third targets the middle third")
        expect(WindowLayoutGeometry.rect(for: .rightThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 960, y: 40, width: 480, height: 860),
               "window layout right third targets the final third")
        expect(WindowLayoutGeometry.rect(for: .leftTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 960, height: 860),
               "window layout left two thirds targets the first two thirds")
        expect(WindowLayoutGeometry.rect(for: .rightTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 960, height: 860),
               "window layout right two thirds targets the final two thirds")
        let sixthLayouts: [(WindowLayoutAction, CGRect, CGRect)] = [
            (.topLeftSixth,
             CGRect(x: 0, y: 470, width: 480, height: 430),
             CGRect(x: 0, y: 400, width: 600, height: 500)),
            (.topCenterSixth,
             CGRect(x: 480, y: 470, width: 480, height: 430),
             CGRect(x: 420, y: 400, width: 600, height: 500)),
            (.topRightSixth,
             CGRect(x: 960, y: 470, width: 480, height: 430),
             CGRect(x: 840, y: 400, width: 600, height: 500)),
            (.bottomLeftSixth,
             CGRect(x: 0, y: 40, width: 480, height: 430),
             CGRect(x: 0, y: 40, width: 600, height: 500)),
            (.bottomCenterSixth,
             CGRect(x: 480, y: 40, width: 480, height: 430),
             CGRect(x: 420, y: 40, width: 600, height: 500)),
            (.bottomRightSixth,
             CGRect(x: 960, y: 40, width: 480, height: 430),
             CGRect(x: 840, y: 40, width: 600, height: 500)),
        ]
        for (action, target, anchored) in sixthLayouts {
            expect(WindowLayoutGeometry.rect(for: action,
                                             current: currentWindow,
                                             visibleFrame: visibleFrame) == target,
                   "\(action.rawValue) targets its cell in the 3 by 2 grid")
            expect(WindowLayoutGeometry.anchoredRect(for: action,
                                                     targetRect: target,
                                                     actualSize: CGSize(width: 600, height: 500),
                                                     visibleFrame: visibleFrame) == anchored,
                   "\(action.rawValue) preserves its requested horizontal and vertical anchors")
            expect(WindowLayoutGeometry.accepts(actualRect: anchored,
                                                targetRect: target,
                                                action: action,
                                                anchorTolerance: 36),
                   "\(action.rawValue) accepts a larger minimum-sized window on the same anchors")
        }
        let nextDisplayFrame = CGRect(x: 1440, y: 80, width: 1920, height: 1000)
        let rightHalfWindow = CGRect(x: 720, y: 40, width: 720, height: 860)
        expect(WindowLayoutGeometry.rectForNextDisplay(current: rightHalfWindow,
                                                       sourceVisibleFrame: visibleFrame,
                                                       destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 2400, y: 80, width: 960, height: 1000),
               "window layout next display preserves relative placement and size")
        let oversizedWindow = CGRect(x: -40, y: 0, width: 2000, height: 1200)
        expect(WindowLayoutGeometry.rectForNextDisplay(current: oversizedWindow,
                                                       sourceVisibleFrame: visibleFrame,
                                                       destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "window layout next display clamps oversized windows to the destination visible frame")
        expect(WindowLayoutAction.shortcutActions.count == WindowLayoutAction.allCases.count,
               "every window layout action can register a global shortcut")
        expect(WindowLayoutAction.shortcutActions.contains(.nextDisplay),
               "next display registers a global shortcut")
        expect(Set(WindowLayoutAction.shortcutActions.map(\.shortcutKey)).count
               == WindowLayoutAction.shortcutActions.count,
               "every window layout shortcut has its own defaults key")
        expect(WindowLayoutAction.shortcutActions.contains(.leftHalf),
               "existing half actions keep global shortcuts")
        expect([WindowLayoutAction.topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
               .allSatisfy { $0.supportsShortcut && $0.defaultShortcut == nil },
               "sixth actions support optional shortcuts without claiming defaults")
        expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 720, height: 430),
               "window layout top left targets the upper-left quadrant")
        expect(WindowLayoutGeometry.rect(for: .topRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 470, width: 720, height: 430),
               "window layout top right targets the upper-right quadrant")
        expect(WindowLayoutGeometry.rect(for: .bottomLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 430),
               "window layout bottom left targets the lower-left quadrant")
        expect(WindowLayoutGeometry.rect(for: .bottomRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 430),
               "window layout bottom right targets the lower-right quadrant")
        expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame)
               == visibleFrame,
               "window layout maximize uses the full visible frame")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 320, y: 220, width: 800, height: 500),
               "window layout center preserves current size and centers inside the visible frame")
        expect(WindowLayoutGeometry.rect(for: .restore, current: currentWindow, visibleFrame: visibleFrame)
               == currentWindow,
               "window layout restore keeps the saved frame")
        let topWindow = CGRect(x: 0, y: 470, width: 1440, height: 430)
        let bottomWindow = CGRect(x: 0, y: 40, width: 1440, height: 430)
        let leftWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        let topLeftWindow = CGRect(x: 0, y: 470, width: 720, height: 430)
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays direct when the previous layout action was not top")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .maximize,
               "window layout top half promotes only when top is used twice in a row")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays top when the window is elsewhere")
        expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom does not promote while at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .leftHalf,
               "window layout left does not become a corner after top")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the bottom")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the bottom")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct from the upper-left corner")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct from the upper-left corner")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct when the window is already on the left")
        expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom stays direct when the window is already on the left")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .bottomHalf) == .rightHalf,
               "window layout right does not become a corner after bottom")
        let leftTarget = WindowLayoutGeometry.rect(for: .leftHalf,
                                                   current: currentWindow,
                                                   visibleFrame: visibleFrame)
        let rightTarget = WindowLayoutGeometry.rect(for: .rightHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 0, y: 40, width: 720, height: 430),
                                            targetRect: leftTarget,
                                            action: .leftHalf,
                                            anchorTolerance: 36) == false,
               "window layout left half does not accept a lower-left corner as the full side")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 720, y: 40, width: 720, height: 430),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36) == false,
               "window layout right half does not accept a lower-right corner as the full side")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 540, y: 40, width: 900, height: 860),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36),
               "window layout right half accepts a larger app minimum size when it spans the full height")
        expect(WindowLayoutGeometry.anchoredRect(for: .rightHalf,
                                                 targetRect: rightTarget,
                                                 actualSize: CGSize(width: 900, height: 700),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 700),
               "window layout right anchors the accepted app size to the right edge")
        let bottomTarget = WindowLayoutGeometry.rect(for: .bottomHalf,
                                                     current: currentWindow,
                                                     visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.anchoredRect(for: .bottomHalf,
                                                 targetRect: bottomTarget,
                                                 actualSize: CGSize(width: 1000, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1000, height: 620),
               "window layout bottom anchors the accepted app size to the bottom edge")
        let bottomRightTarget = WindowLayoutGeometry.rect(for: .bottomRight,
                                                          current: currentWindow,
                                                          visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.anchoredRect(for: .bottomRight,
                                                 targetRect: bottomRightTarget,
                                                 actualSize: CGSize(width: 900, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 620),
               "window layout bottom right anchors the accepted app size to both requested edges")

        // MARK: Window move and resize gestures

        expect(WindowGestureSupport.modifiers(from: nil) == [.control, .command],
               "window gestures fall back to control-command")
        expect(WindowGestureSupport.modifiers(from: "option+shift") == [.option],
               "shift stays reserved for trackpad resizing")
        expect(WindowGestureSupport.modifiers(from: "shift") == [.control, .command],
               "shift alone never takes over ordinary system dragging")
        expect(WindowGestureSupport.modifiers(from: "invalid") == [.control, .command],
               "corrupt window gesture modifiers fall back safely")
        expect(WindowGestureSupport.storageValue(for: [.command, .control]) == "control+command",
               "window gesture modifiers serialize in stable order")
        expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand],
                                                   expected: [.control, .command]),
               "window gestures match their exact modifier chord")
        expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                    expected: [.control, .command]),
               "the resize chord does not trigger window movement")
        let resizeModifiers = WindowGestureSupport.resizeModifiers(from: [.control, .command])
        expect(resizeModifiers == [.control, .shift, .command],
               "trackpad resizing adds shift to the chosen move chord")
        expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                   expected: resizeModifiers),
               "trackpad resizing matches its exact primary-drag chord")
        expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift, .maskAlternate],
                                                    expected: resizeModifiers),
               "unexpected extra modifiers do not trigger trackpad resizing")
        expect(WindowGestureSupport.movedOrigin(from: CGPoint(x: 100, y: 80),
                                                pointerStart: CGPoint(x: 300, y: 200),
                                                pointerNow: CGPoint(x: 345, y: 175))
               == CGPoint(x: 145, y: 55),
               "window movement follows the full pointer delta")
        let gestureFrame = CGRect(x: 100, y: 80, width: 600, height: 420)
        expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 110, y: 90), in: gestureFrame)
               == [.left, .top],
               "a top-left press resizes from both matching edges")
        expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 90), in: gestureFrame)
               == [.top],
               "a top-center press resizes only the top edge")
        expect(!WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 290), in: gestureFrame).isEmpty,
               "the center region always chooses a usable nearest edge")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 110, y: 90),
                                                 pointerNow: CGPoint(x: 160, y: 120),
                                                 edges: [.left, .top])
               == CGRect(x: 150, y: 110, width: 550, height: 390),
               "top-left resizing keeps the opposite corner anchored")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 690, y: 490),
                                                 pointerNow: CGPoint(x: 760, y: 540),
                                                 edges: [.right, .bottom])
               == CGRect(x: 100, y: 80, width: 670, height: 470),
               "bottom-right resizing grows in both axes")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 100, y: 80),
                                                 pointerNow: CGPoint(x: 900, y: 700),
                                                 edges: [.left, .top])
               == CGRect(x: 580, y: 420, width: 120, height: 80),
               "gesture minimum size keeps the far corner fixed")
        expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: CGPoint(x: 580, y: 420),
                                                   acceptedSize: CGSize(width: 260, height: 180),
                                                   edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "an app-specific minimum size keeps the opposite corner anchored")
        expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: gestureFrame.origin,
                                                   acceptedSize: CGSize(width: 760, height: 540),
                                                   edges: [.right, .bottom])
               == gestureFrame.origin,
               "right and bottom resizing keep the original window origin")
        expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: gestureFrame.origin,
                                                           acceptedSize: CGSize(width: 760, height: 540),
                                                           edges: [.right, .bottom]) == nil,
               "right and bottom resizing never adds a redundant position mutation")
        expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: CGPoint(x: 580, y: 420),
                                                           acceptedSize: CGSize(width: 260, height: 180),
                                                           edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "left and top resizing reanchors only after the accepted size is known")

        expect(MediaImageFormat.sanitized("pdf") == .pdf,
               "Image converter accepts the PDF format")
        expect(MediaImageFormat.pdf.fileExtension == "pdf",
               "PDF output uses the pdf file extension")
        expect(MediaImageFormat.sanitized("bmp") == .jpeg,
               "Unknown image format falls back to JPEG")

        let trim = MediaSupport.sanitizedTrim(start: -5, end: 3, assetDuration: 10)
        expect(trim == MediaTrimRange(start: 0, end: 3),
               "Media trim clamps negative start")
        let fullTrim = MediaSupport.sanitizedTrim(start: 2, end: 0, assetDuration: 10)
        expect(fullTrim == MediaTrimRange(start: 2, end: 10),
               "Media trim treats zero end as the source duration")
        expectClose(MediaSupport.sanitizedQuality(.infinity), 0.7,
                    "Media invalid quality falls back")
        expectClose(MediaSupport.sanitizedQuality(0.02), 0.1,
                    "Media quality clamps low")
        expectClose(MediaSupport.sanitizedQuality(2), 1,
                    "Media quality clamps high")
        expectClose(MediaSupport.sanitizedFPS(90), 60,
                    "Media FPS clamps high")
        expectClose(MediaSupport.sanitizedFPS(-1), 12,
                    "Media FPS falls back when invalid")
        expect(MediaSupport.sanitizedPixelDimension(641, fallback: 1280) == 640,
               "Media pixel dimensions stay even")
        expect(MediaSupport.scaledEvenSize(source: CGSize(width: 1920, height: 1080), maxDimension: 1000)
               == CGSize(width: 1000, height: 562),
               "Media scaling keeps aspect ratio with even dimensions")
        expect(MediaSupport.scaledVideoSize(source: CGSize(width: 320, height: 180), maxDimension: 180)
               == CGSize(width: 176, height: 96),
               "Media video scaling uses encoder-friendly dimensions")
        let mediaInput = URL(fileURLWithPath: "/tmp/Clip.mov")
        expect(MediaSupport.outputURL(for: mediaInput, suffix: "-compressed", fileExtension: "mp4").path
               == "/tmp/Clip-compressed.mp4",
               "Media output names keep clear suffixes")
        let hiddenMediaInput = URL(fileURLWithPath: "/tmp/.Clip.mov")
        expect(MediaSupport.outputURL(for: hiddenMediaInput, suffix: "", fileExtension: "gif").path
               == "/tmp/Clip.gif",
               "Media GIF output strips a leading dot from the source name")
        let extensionOnlyMediaInput = URL(fileURLWithPath: "/tmp/.mov")
        expect(MediaSupport.outputURL(for: extensionOnlyMediaInput, suffix: "", fileExtension: "gif").path
               == "/tmp/mov.gif",
               "Media GIF output stays visible for extension-looking source names")
        let emptyBaseMediaInput = URL(fileURLWithPath: "/tmp/...")
        expect(MediaSupport.outputURL(for: emptyBaseMediaInput, suffix: "", fileExtension: "gif").path
               == "/tmp/Output.gif",
               "Media GIF output falls back when the visible source name is empty")
        let mediaVisibilityDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-media-visibility-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaVisibilityDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mediaVisibilityDir) }
        let visibleMediaOutput = mediaVisibilityDir.appendingPathComponent("Visible.gif")
        FileManager.default.createFile(atPath: visibleMediaOutput.path,
                                       contents: Data([0x47, 0x49, 0x46, 0x38]),
                                       attributes: nil)
        visibleMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, UInt32(UF_HIDDEN))
        }
        var hiddenMediaOutputStat = stat()
        visibleMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = lstat(path, &hiddenMediaOutputStat)
        }
        expect((UInt32(hiddenMediaOutputStat.st_flags) & UInt32(UF_HIDDEN)) != 0,
               "Media visibility test marks the fixture hidden")
        MediaSupport.makeVisibleIfNeeded(visibleMediaOutput)
        var visibleMediaOutputStat = stat()
        visibleMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = lstat(path, &visibleMediaOutputStat)
        }
        expect((UInt32(visibleMediaOutputStat.st_flags) & UInt32(UF_HIDDEN)) == 0,
               "Media visible outputs clear the Finder hidden flag")
        let intentionallyHiddenMediaOutput = mediaVisibilityDir.appendingPathComponent(".Manual.gif")
        FileManager.default.createFile(atPath: intentionallyHiddenMediaOutput.path,
                                       contents: Data([0x47, 0x49, 0x46, 0x38]),
                                       attributes: nil)
        intentionallyHiddenMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, UInt32(UF_HIDDEN))
        }
        MediaSupport.makeVisibleIfNeeded(intentionallyHiddenMediaOutput)
        var intentionallyHiddenMediaOutputStat = stat()
        intentionallyHiddenMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = lstat(path, &intentionallyHiddenMediaOutputStat)
        }
        expect((UInt32(intentionallyHiddenMediaOutputStat.st_flags) & UInt32(UF_HIDDEN)) != 0,
               "Media output visibility respects dot-prefixed manual filenames")
        expect(MediaSupport.recognitionLanguages(for: "pt-BR") == ["pt-BR", "en-US"],
               "Media OCR language defaults include the app language and English")
        expect(MediaSupport.recognitionLanguages(for: "tr") == ["tr-TR", "en-US"],
               "Media OCR language defaults include Turkish and English")
        expect(MediaSupport.recognitionLanguages(for: "ko") == ["ko-KR", "en-US"],
               "Media OCR language defaults include Korean and English")
        expectClose(Defaults.sanitizedAppVolume(1.5), 1.5, "valid app volume is preserved")
        expectClose(Defaults.sanitizedAppVolume(3), 2, "high app volume clamps to boost maximum")
        expectClose(Defaults.sanitizedAppVolume(-1), 0, "negative app volume clamps to mute")
        expectClose(Defaults.sanitizedAppVolume(.infinity), 1, "non-finite app volume falls back to unity")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(35) == 35,
               "headphone disconnect volume preserves valid percentages")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(-5) == 0,
               "headphone disconnect volume clamps low values")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(105) == 100,
               "headphone disconnect volume clamps high values")
        expect(Defaults.sanitizedAppOutputDeviceUID(" BuiltInSpeakerDevice ") == "BuiltInSpeakerDevice",
               "audio output device UIDs are trimmed")
        expect(Defaults.sanitizedAppOutputDeviceUID("") == nil,
               "empty audio output device UIDs are ignored")
        expect(Defaults.sanitizedAppOutputDeviceUID("bad\nuid") == nil,
               "control characters are rejected from audio output device UIDs")
        expect(Defaults.sanitizedPreferredInputDeviceUID(" BuiltInMicrophoneDevice ") == "BuiltInMicrophoneDevice",
               "audio input device UIDs are trimmed")
        expect(Defaults.sanitizedPreferredInputDeviceUID("") == nil,
               "empty audio input device UIDs are ignored")
        let savedRoutes = Defaults.sanitizedAppOutputDevices([
            "com.apple.Safari": "BuiltInSpeakerDevice",
            "bad\napp": "ExternalDisplay",
            "com.example.Empty": "",
        ])
        expect(savedRoutes == ["com.apple.Safari": "BuiltInSpeakerDevice"],
               "app output device routes keep only valid app and device ids")
        expect(Defaults.sanitizedSoundOutputSwitcherDeviceUIDs([
            " BuiltInSpeakerDevice ",
            "bad\nuid",
            "BuiltInSpeakerDevice",
            "ExternalDisplay",
            7,
        ]) == ["BuiltInSpeakerDevice", "ExternalDisplay"],
               "sound output switcher keeps valid unique device ids in order")
        let savedMixerVolumes = ["com.apple.Safari": 0.35, "com.apple.Music": 1.4]
        let successfulUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: true)
        expect(successfulUniversalOutput.outputDeviceUIDs.isEmpty,
               "universal output clears per-app routes after a successful switch")
        expect(successfulUniversalOutput.volumes == savedMixerVolumes,
               "universal output preserves saved app volumes")
        let failedUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: false)
        expect(failedUniversalOutput.outputDeviceUIDs == savedRoutes,
               "failed universal output keeps per-app routes")
        expect(failedUniversalOutput.volumes == savedMixerVolumes,
               "failed universal output keeps saved app volumes")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher moves from the current selected output to the next")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "ExternalDisplay",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher wraps selected outputs")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "USBHeadphones",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher starts at the first selected output when current is outside the cycle")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "MissingDisplay", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher skips unavailable selected outputs")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice"],
            availableUIDs: ["BuiltInSpeakerDevice"]) == nil,
               "sound output switcher does nothing when the only selected output is already current")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "AirPods Pro",
                                                             uid: "",
                                                             dataSourceName: nil),
               "AirPods are treated as headphones")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Built-in Output",
                                                             uid: "",
                                                             dataSourceName: "Headphones"),
               "wired headphone data source is treated as headphones")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Sony WH-1000XM5",
                                                             uid: "",
                                                             dataSourceName: nil),
               "common Bluetooth headphone names are treated as headphones")
        expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "MacBook Pro Speakers",
                                                              uid: "BuiltInSpeakerDevice",
                                                              dataSourceName: nil),
               "built-in speakers are not treated as headphones")
        expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "JBL Flip",
                                                              uid: "",
                                                              dataSourceName: nil),
               "Bluetooth speakers are not treated as headphones")
        // Issue #256: some browsers' audio helpers answer for themselves, so
        // the mixer walks the parent chain to the nearest regular app.
        let helperParents: [pid_t: pid_t] = [500: 100, 100: 1, 700: 1,
                                             900: 901, 901: 902, 902: 903, 903: 904,
                                             904: 905, 905: 906, 906: 907, 907: 100]
        func owningApp(of responsible: pid_t, regularApps: Set<pid_t> = [100]) -> pid_t? {
            MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: responsible,
                isRegularApp: { regularApps.contains($0) },
                parentPid: { helperParents[$0] ?? 0 })
        }
        expect(owningApp(of: 100) == 100,
               "a responsible regular app is billed directly")
        expect(owningApp(of: 500) == 100,
               "a helper answering for itself is billed to the app that spawned it")
        expect(owningApp(of: 700) == nil,
               "daemons whose parent chain ends at launchd stay unlisted")
        expect(owningApp(of: 42) == nil,
               "a failed parent lookup stops the walk")
        expect(owningApp(of: 900) == nil,
               "the parent walk gives up beyond the depth cap")
        expect(owningApp(of: 902) == 100,
               "a regular app within the depth cap is still found")
        expect(owningApp(of: 0) == nil,
               "a missing responsible pid maps to no app")
        expect(!MixerRoutingSupport.requiresEngine(volume: 1,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output at 100 percent stays passthrough")
        expect(MixerRoutingSupport.requiresEngine(volume: 0.5,
                                                  selectedOutputDeviceUID: nil,
                                                  targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output with changed volume uses an engine")
        expect(MixerRoutingSupport.requiresEngine(volume: 1,
                                                  selectedOutputDeviceUID: "ExternalDisplay",
                                                  targetOutputDeviceUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "specific non-default output at 100 percent uses an engine")
        expect(!MixerRoutingSupport.requiresEngine(hasAudioObjects: false,
                                                   volume: 0.5,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a persistent mixer row waits for an audio connection before building a tap")
        expect(!MixerRoutingSupport.isHiddenFromMixer(bundleIdentifier: "com.apple.finder",
                                                      showFinder: true),
               "Finder shows in the mixer when enabled")
        expect(MixerRoutingSupport.isHiddenFromMixer(bundleIdentifier: "com.apple.finder",
                                                     showFinder: false),
               "Finder can be hidden from the mixer")
        expect(!MixerRoutingSupport.isHiddenFromMixer(bundleIdentifier: "com.example.Player",
                                                      showFinder: false),
               "hiding Finder leaves every other app visible")
        expect(!MixerRoutingSupport.isHiddenFromMixer(bundleIdentifier: nil, showFinder: false),
               "apps without a bundle id still show in the mixer")
        expect(MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                            hasFinderRow: false),
               "Finder gets a persistent row before Quick Look opens")
        expect(!MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                             hasFinderRow: true)
                && !MixerRoutingSupport.needsPersistentFinderRow(showFinder: false,
                                                                 hasFinderRow: false),
               "Finder is never duplicated and stays absent when hidden")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.xos", name: "zoom.us"),
               "Zoom is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.ZoomAutoUpdater", name: "Zoom"),
               "Zoom helper bundle ids are kept out of process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.Safari", name: "Safari"),
               "regular apps remain eligible for process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: nil, name: "Zoomable Notes"),
               "unrelated app names are not treated as Zoom")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.logic10", name: "Logic Pro"),
               "Logic Pro is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.ableton.live", name: "Live"),
               "Ableton Live is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.steinberg.cubase13", name: "Cubase"),
               "Cubase is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.presonus.studioone6", name: "Studio One"),
               "Studio One is kept out of process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.spotify.client", name: "Spotify"),
               "music players remain eligible for process-tap audio routing")
        expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: "ExternalDisplay",
                                                      availableUIDs: ["BuiltInSpeakerDevice"],
                                                      defaultUID: "BuiltInSpeakerDevice") == "BuiltInSpeakerDevice",
               "missing saved output falls back to default")
        expect(MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: "ExternalDisplay",
                                                             availableUIDs: ["BuiltInSpeakerDevice"]),
               "missing saved output is marked unavailable without deleting the preference")
        let defaultInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: nil,
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(defaultInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                         selectedUnavailable: false,
                                                         shouldApplyPreferred: false),
               "no preferred input follows the current system input")
        let connectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(connectedPreferredInput == MixerInputRouteResolution(effectiveUID: "StudioMic",
                                                                    selectedUnavailable: false,
                                                                    shouldApplyPreferred: true),
               "connected preferred input is applied when different from current")
        let alreadyCurrentInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "StudioMic")
        expect(!alreadyCurrentInput.shouldApplyPreferred,
               "preferred input is not reapplied when already current")
        let disconnectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(disconnectedPreferredInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                                       selectedUnavailable: true,
                                                                       shouldApplyPreferred: false),
               "missing preferred input falls back visually without deleting preference")
        expect(MixerRoutingSupport.displayOrderedBefore(name: "Music", id: "com.apple.Music",
                                                        otherName: "Safari", otherID: "com.apple.Safari"),
               "mixer rows order by display name")
        expect(MixerRoutingSupport.displayOrderedBefore(name: "safari", id: "a",
                                                        otherName: "Safari", otherID: "b")
                   && !MixerRoutingSupport.displayOrderedBefore(name: "Safari", id: "b",
                                                                otherName: "safari", otherID: "a"),
               "mixer rows with equal names order deterministically by id")
        expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: true, name: "Zeta", uid: "z",
                                                              otherIsDefault: false, otherName: "Alpha",
                                                              otherUID: "a"),
               "the default device orders before any other device")
        expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro", uid: "aa",
                                                              otherIsDefault: false, otherName: "AirPods Pro",
                                                              otherUID: "bb")
                   && !MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro",
                                                                      uid: "bb",
                                                                      otherIsDefault: false,
                                                                      otherName: "AirPods Pro",
                                                                      otherUID: "aa"),
               "identically named devices order deterministically by uid")

        // MARK: Shelf persistence

        expect(ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: "com.example.Editor",
            excludedBundleIdentifiers: ["com.example.Browser"]),
               "shelf automatic opening allows apps outside the exclusion list")
        expect(!ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: "com.example.Browser",
            excludedBundleIdentifiers: ["com.example.Browser"]),
               "shelf automatic opening stays off for an excluded source app")
        expect(ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: nil,
            excludedBundleIdentifiers: ["com.example.Browser"]),
               "shelf automatic opening does not false-block an unknown drag source")
        expect(ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: true, draggedItemCount: 2, closeAfterDrop: true, pinned: false),
               "shelf closes after a real accepted external drag")
        expect(!ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: false, draggedItemCount: 2, closeAfterDrop: true, pinned: false),
               "shelf stays open after a cancelled drag")
        expect(!ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: true, draggedItemCount: 0, closeAfterDrop: true, pinned: false),
               "shelf internal merges do not dismiss the panel")
        expect(!ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: true, draggedItemCount: 2, closeAfterDrop: true, pinned: true),
               "shelf pin overrides close after drop")
        expect(ShelfInteractionSupport.shouldRemoveAfterDrag(
            dropAccepted: true, draggedItemCount: 1, removeAfterDrop: true),
               "shelf removes an accepted item when automatic removal is on")
        expect(!ShelfInteractionSupport.shouldRemoveAfterDrag(
            dropAccepted: true, draggedItemCount: 1, removeAfterDrop: false),
               "shelf retains an accepted item when automatic removal is off")

        expect(!ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 5, beganInDock: false,
            hasDroppableContent: { true }),
               "moving a window past retained pasteboard content is not a content drag")
        expect(!ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 6, beganInDock: false,
            hasDroppableContent: { false }),
               "a pasteboard bump without droppable content is not a content drag")
        expect(ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 6, beganInDock: false,
            hasDroppableContent: { true }),
               "content published during the gesture is a content drag")
        expect(ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 5, beganInDock: true,
            hasDroppableContent: { true }),
               "dock stacks may publish the drag contents before the mouse-down")
        expect(!ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 5, beganInDock: false,
            hasDroppableContent: { fatalError("droppable check must stay lazy") }),
               "an unchanged pasteboard outside the Dock skips the content inspection")

        let shelfFile = ShelfPersistedItem(id: UUID(), kind: .file, title: "notes.pdf",
                                           path: "/tmp/notes.pdf")
        let shelfText = ShelfPersistedItem(id: UUID(), kind: .text, title: "Hello", text: "Hello world")
        let shelfLink = ShelfPersistedItem(id: UUID(), kind: .link, title: "example.com",
                                           url: "https://example.com/page")
        let shelfRoundTrip = [shelfFile, shelfText, shelfLink,
                              ShelfPersistedItem(id: UUID(), kind: .batch, title: "batch",
                                                 children: [shelfFile, shelfText])]
        if let encoded = try? JSONEncoder().encode(shelfRoundTrip),
           let decoded = try? JSONDecoder().decode([ShelfPersistedItem].self, from: encoded) {
            expect(decoded == shelfRoundTrip, "shelf items survive an encode and decode round trip")
        } else {
            expect(false, "shelf items must encode and decode")
        }

        expect(ShelfPersistenceSupport.sanitized([shelfFile, shelfText, shelfLink]) { _ in true }
                   == [shelfFile, shelfText, shelfLink],
               "healthy shelf items pass sanitizing untouched")
        expect(ShelfPersistenceSupport.sanitized([shelfFile, shelfText]) { _ in false } == [shelfText],
               "shelf files that no longer exist are dropped at load")
        expect(ShelfPersistenceSupport.unmountedVolumeRoot(of: "/Volumes/NAS/docs/a.txt") == "/Volumes/NAS",
               "files under /Volumes report their volume root")
        expect(ShelfPersistenceSupport.unmountedVolumeRoot(of: "/Users/me/a.txt") == nil,
               "boot volume files have no volume root to wait for")
        expect(ShelfPersistenceSupport.sanitized(
                   [ShelfPersistedItem(id: UUID(), kind: .text, title: "", text: "  \n ")]) { _ in true }
                   .isEmpty,
               "whitespace-only shelf text is dropped at load")
        expect(ShelfPersistenceSupport.sanitized(
                   [ShelfPersistedItem(id: UUID(), kind: .link, title: "x", url: "not a url##"),
                    ShelfPersistedItem(id: UUID(), kind: .link, title: "x", url: "file:///etc/hosts"),
                    ShelfPersistedItem(id: UUID(), kind: .link, title: "x", url: "relative/path")]) { _ in true }
                   .isEmpty,
               "invalid, file and schemeless shelf links are dropped at load")
        let shelfBatch = ShelfPersistedItem(id: UUID(), kind: .batch, title: "batch",
                                            children: [shelfFile, shelfText])
        expect(ShelfPersistenceSupport.sanitized([shelfBatch]) { _ in false } == [shelfText],
               "a shelf batch left with one child collapses to that child")
        expect(ShelfPersistenceSupport.sanitized(
                   [ShelfPersistedItem(id: UUID(), kind: .batch, title: "batch",
                                       children: [shelfFile])]) { _ in false }
                   .isEmpty,
               "a shelf batch left empty is dropped")
        let oversizedShelf = (0..<(ShelfPersistenceSupport.maxLeaves + 20)).map { index in
            ShelfPersistedItem(id: UUID(), kind: .text, title: "t\(index)", text: "t\(index)")
        }
        expect(ShelfPersistenceSupport.sanitized(oversizedShelf) { _ in true }.count
                   == ShelfPersistenceSupport.maxLeaves,
               "shelf restore caps the number of items")

        expect(ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: 2)
                   && !ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: 0),
               "the list only claims command-C over an explicit selection")
        expect(ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 0, queryIsEmpty: true)
                   && !ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 0, queryIsEmpty: false)
                   && ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 1, queryIsEmpty: false),
               "the list claims command-A over a selection or an empty search field")

        // MARK: Middle click tap (issue #161)

        expect(Defaults.sanitizedMiddleClickTapFingers(3) == 3
                   && Defaults.sanitizedMiddleClickTapFingers(4) == 4,
               "tap to middle click accepts three or four fingers")
        expect(Defaults.sanitizedMiddleClickTapFingers(0) == 0
                   && Defaults.sanitizedMiddleClickTapFingers(2) == 0
                   && Defaults.sanitizedMiddleClickTapFingers(-1) == 0,
               "any other tap finger count means off")
        expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: false,
                                                tapFingers: 3),
               "a quick still three-finger tap fires")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.2, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "a swipe never fires the tap")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.8, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "resting fingers never fire the tap")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: true,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "a physical click during the touch belongs to the press path")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: true, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "extra fingers cancel the tap")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: true, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "unreadable touch positions stand the tap down")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: true,
                                                 tapFingers: 3),
               "three-finger tap stands down while the system drag gesture owns it")
        expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: true,
                                                tapFingers: 4),
               "four-finger tap stays available alongside the system drag gesture")
        expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.2,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 4),
               "a pinch or spread never fires the tap even with a still centroid")

        // MARK: Cut and paste move progress (issue #168)

        expect(!CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                      destination: NSNumber(value: 1)),
               "a move inside one volume never shows progress")
        expect(CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                     destination: NSNumber(value: 2)),
               "a move between volumes is recognized as a real copy")
        expect(!CutPasteProgressSupport.isCrossVolume(source: nil,
                                                      destination: NSNumber(value: 2)),
               "unknown volume identities fall back to the silent same-volume path")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 0, currentBytes: 0, totalBytes: 0) == nil,
               "an unknown byte total yields an indeterminate bar, not a broken fraction")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 50, currentBytes: 25, totalBytes: 150) == 0.5,
               "progress combines finished files with the growing destination")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 100, currentBytes: 200, totalBytes: 150) == 1.0,
               "progress clamps at full when the destination briefly over-reports")
        expect(CutPasteProgressSupport.fraction(finishedBytes: -5, currentBytes: -5, totalBytes: 100) == 0.0,
               "negative byte readings clamp to an empty bar")
        expect(CutPasteProgressSupport.displayPosition(completed: 1, total: 5) == 2,
               "the counter shows the item currently moving, one past the finished count")
        expect(CutPasteProgressSupport.displayPosition(completed: 5, total: 5) == 5,
               "the counter never runs past the batch size")

        // MARK: Update installer helpers

        expect(GlobalShortcutRole.activeRoles(isOn: { _ in false }).isEmpty,
               "no enabled gates means no active shortcuts")
        expect(GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.hotkeyEnabled })
                   == [.keepAwake],
               "keep awake activates on its own gate alone")
        expect(!GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.clipboardHistoryShortcutEnabled })
                   .contains(.clipboard),
               "the clipboard shortcut needs the feature on too")
        expect(GlobalShortcutRole.activeRoles(isOn: {
                   $0 == DefaultsKey.clipboardHistoryEnabled
                       || $0 == DefaultsKey.clipboardHistoryShortcutEnabled
               }).contains(.clipboard),
               "the clipboard shortcut activates with both gates on")

        expect(UpdateInstallerSupport.progressStepAdvanced(from: nil, to: 0.004),
               "the first known download fraction always publishes")
        expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.011, to: 0.019),
               "fractions inside the same percent stay quiet")
        expect(UpdateInstallerSupport.progressStepAdvanced(from: 0.019, to: 0.021),
               "crossing into the next percent publishes")
        expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.5, to: 0.5),
               "an unchanged fraction stays quiet")

        expect(SettingsSearchSupport.matches(query: "", title: "Monitor"),
               "a blank settings search matches everything")
        expect(SettingsSearchSupport.matches(query: "moni", title: "Monitor"),
               "settings search is case-insensitive prefix-friendly")
        expect(SettingsSearchSupport.matches(query: "musica", title: "Música"),
               "settings search ignores accents")
        expect(!SettingsSearchSupport.matches(query: "shelf", title: "Monitor"),
               "settings search filters out non-matches")
        expect(SettingsSearchSupport.matches(query: "  switcher ", title: "Switcher"),
               "settings search trims surrounding whitespace")
        expect(SettingsSearchSupport.filteredIndices(query: "mo",
                                                     sections: [["Monitor", "Shelf"], ["Mouse"]])
                   == [[0], [0]],
               "settings search keeps matching rows per section")
        expect(SettingsSearchSupport.matches(query: "lid", title: "Energy",
                                             keywords: ["Keep going with the lid closed"]),
               "settings search finds a page by an option living inside it")
        expect(!SettingsSearchSupport.matches(query: "lid", title: "Energy", keywords: []),
               "without keywords the same query stays a miss")

        let freshSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                 availableHeight: 1200)
        expect(freshSize.width == 772 && freshSize.height == 838,
               "settings window opens at the tall default when nothing is saved")
        let clampedSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                   availableHeight: 700)
        expect(clampedSize.height == 700,
               "the tall default shrinks to what the screen fits")
        let tinyScreen = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                  availableHeight: 400)
        expect(tinyScreen.height == 528,
               "the default never goes below the design height")
        let savedSize = SettingsWindowSupport.initialContentSize(savedWidth: 900, savedHeight: 950,
                                                                 availableHeight: 700)
        expect(savedSize.width == 900 && savedSize.height == 950,
               "a user-chosen size is restored as is")
        let bogusSaved = SettingsWindowSupport.initialContentSize(savedWidth: 300, savedHeight: 200,
                                                                  availableHeight: 1200)
        expect(bogusSaved.width == 772 && bogusSaved.height == 838,
               "a saved size below the minimum falls back to the default")

        expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-copy"),
               "a copy failure retries through the admin prompt")
        expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-swap"),
               "a swap failure retries through the admin prompt")
        expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-verify"),
               "a verification failure is not a permission problem")
        expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: nil),
               "no remembered failure means the normal path")

        let hiddenLayout = WindowLayoutAction.hiddenActions(from: "leftHalf, restore,bogus")
        expect(hiddenLayout == [.leftHalf, .restore],
               "hidden layout actions parse names and drop unknown ones")
        expect(WindowLayoutAction.hiddenActionsStorageValue([.restore, .leftHalf])
                   == "leftHalf,restore",
               "hidden layout actions serialize sorted for stable storage")
        expect(WindowLayoutAction.hiddenActions(from: "").isEmpty,
               "an empty stored value hides nothing")

        expect(MediaSupport.inputMatchesTool(contentType: .jpeg, inputTypes: [.image]),
               "a JPEG drop fits the image tool")
        expect(!MediaSupport.inputMatchesTool(contentType: .pdf, inputTypes: [.image]),
               "a PDF drop does not fit the image tool")
        expect(!MediaSupport.inputMatchesTool(contentType: nil, inputTypes: [.image]),
               "an unreadable content type is rejected")
        expect(MediaSupport.inputMatchesTool(contentType: .quickTimeMovie,
                                             inputTypes: [.movie, .video]),
               "a movie drop fits the video tools")

        expect(MediaSupport.outputGrew(originalBytes: 9_000, outputBytes: 12_000),
               "a larger output earns the grew caption")
        expect(!MediaSupport.outputGrew(originalBytes: 12_000, outputBytes: 9_000),
               "a smaller output does not")
        expect(!MediaSupport.outputGrew(originalBytes: 0, outputBytes: 12_000),
               "an unknown original size never triggers the grew caption")

        expect(UpdateInstallerSupport.shellSingleQuoted("/Applications/My App.app")
                   == "'/Applications/My App.app'",
               "shell quoting wraps paths with spaces")
        expect(UpdateInstallerSupport.shellSingleQuoted("it's") == "'it'\\''s'",
               "shell quoting survives embedded single quotes")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: "ok\n") == nil,
               "an ok marker is not a failure")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: " fail-verify\n") == "fail-verify",
               "a fail marker surfaces its step code")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: "") == nil,
               "an empty marker is not a failure")
        expect(UpdateInstallerSupport.runsFromImmutableLocation(
                   appPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1F2/d/Vorssaint.app",
                   volumeIsReadOnly: { _ in false }),
               "translocated apps are flagged as not updatable in place")
        expect(UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/Vorssaint/Vorssaint.app",
                                                                volumeIsReadOnly: { _ in true }),
               "apps on a read-only volume (the DMG) are flagged as not updatable in place")
        expect(!UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/ExternalSSD/Vorssaint.app",
                                                                 volumeIsReadOnly: { _ in false }),
               "apps on a writable external volume stay updatable in place")
        let installerScript = UpdateInstallerSupport.installerScript()
        for step in ["fail-tempdir", "fail-mount", "fail-no-app-in-dmg",
                     "fail-copy", "fail-verify", "fail-swap", "note ok"] {
            expect(installerScript.contains(step),
                   "installer script reports the \(step) step")
        }
        expect(installerScript.contains("spctl --status"),
               "installer script skips Gatekeeper assessment when the user disabled it")
        expect(installerScript.contains("chown -R"),
               "an elevated install hands the bundle back to the user")
        expect(installerScript.contains("update-old.$PID"),
               "the swap backup name is unique per run so a stale root-owned one never blocks it")
        expect(installerScript.contains("launchctl asuser"),
               "installer script relaunches as the user when running as root")
        expect(installerScript.contains("$RESULT.progress") && installerScript.contains("finalize"),
               "installer markers stay in a progress file until the run finishes")
        let elevated = UpdateInstallerSupport.elevatedInstallCommand(
            appPath: "/Applications/Vorssaint.app",
            dmgPath: "/tmp/Vorssaint-update.dmg",
            pid: 123,
            resultPath: "/tmp/result",
            uid: 501)
        expect(elevated.contains("nohup") && elevated.hasSuffix("&"),
               "elevated installer detaches so the app can quit")
        expect(elevated.contains("'/Applications/Vorssaint.app'"),
               "elevated installer passes the app path quoted for the shell")

        // MARK: Launch at login reconciliation

        expect(LaunchAtLoginSupport.startupAction(wanted: true, systemEnabled: false,
                                                  locationIsUnstable: false) == .register,
               "a lost registration the user wants is redone at startup")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, systemEnabled: false,
                                                  locationIsUnstable: true) == .none,
               "no registration is redone from an unstable location")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, systemEnabled: true,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: true, systemEnabled: true,
                                                      locationIsUnstable: true) == .none,
               "a healthy registration is left alone")
        expect(LaunchAtLoginSupport.startupAction(wanted: false, systemEnabled: true,
                                                  locationIsUnstable: false) == .adoptEnabled
                && LaunchAtLoginSupport.startupAction(wanted: false, systemEnabled: true,
                                                      locationIsUnstable: true) == .adoptEnabled,
               "an enable made outside the app becomes the stored choice")
        expect(LaunchAtLoginSupport.startupAction(wanted: false, systemEnabled: false,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, systemEnabled: false,
                                                      locationIsUnstable: true) == .none,
               "startup never turns launch at login on for a user who never asked")

        // MARK: Dock Preview helpers

        let dockPrefs = DockPreviewPreferences.sanitized(orientation: "left",
                                                         autohide: true,
                                                         tileSize: 81,
                                                         magnification: false,
                                                         magnifiedTileSize: 100)
        expect(dockPrefs == DockPreviewPreferences(orientation: .left,
                                                   autohide: true,
                                                   tileSize: 81,
                                                   magnification: false,
                                                   magnifiedTileSize: 100),
               "Dock Preview preferences preserve valid Dock values")
        let fallbackDockPrefs = DockPreviewPreferences.sanitized(orientation: "bad",
                                                                 autohide: nil,
                                                                 tileSize: 999,
                                                                 magnification: nil,
                                                                 magnifiedTileSize: nil)
        expect(fallbackDockPrefs == DockPreviewPreferences(orientation: .bottom,
                                                           autohide: false,
                                                           tileSize: 256,
                                                           magnification: false,
                                                           magnifiedTileSize: 128),
               "Dock Preview preferences sanitize missing and out-of-range values")
        expect(DockPreviewSupport.availability(enabled: false,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs)
               == DockPreviewAvailability(canRun: false, blockedReason: nil),
               "disabled Dock Preview does not report an error")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: false,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).blockedReason == .missingAccessibility,
               "Dock Preview requires Accessibility")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: false,
                                               preferences: dockPrefs).blockedReason == .missingScreenRecording,
               "Dock Preview requires Screen Recording")
        let magnifiedPrefs = DockPreviewPreferences(orientation: .bottom,
                                                    autohide: false,
                                                    tileSize: 64,
                                                    magnification: true,
                                                    magnifiedTileSize: 128)
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: magnifiedPrefs).canRun,
               "Dock Preview runs with Dock magnification enabled")
        expect(magnifiedPrefs.hoverTileSize == 128,
               "hover tile size follows the magnified size while magnification is on")
        expect(dockPrefs.hoverTileSize == 81,
               "hover tile size stays at the resting size while magnification is off")
        expect(DockPreviewSupport.dockProximityBand(tileSize: magnifiedPrefs.hoverTileSize)
               > magnifiedPrefs.magnifiedTileSize,
               "Dock proximity band covers a fully magnified icon")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).canRun,
               "Dock Preview can run when enabled and permitted")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let iconBottom = CGRect(x: 660, y: 0, width: 80, height: 80)
        let panelSize = CGSize(width: 400, height: 160)
        let bottomFrame = DockPreviewSupport.panelFrame(anchor: iconBottom,
                                                        panelSize: panelSize,
                                                        screenVisibleFrame: screen,
                                                        orientation: .bottom)
        expectClose(Double(bottomFrame.midX), Double(iconBottom.midX), "Dock Preview bottom panel centers on icon")
        expect(bottomFrame.minY > iconBottom.maxY,
               "Dock Preview bottom panel sits above the Dock icon")
        let leftFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 0, y: 380, width: 80, height: 80),
                                                      panelSize: panelSize,
                                                      screenVisibleFrame: screen,
                                                      orientation: .left)
        expect(leftFrame.minX > 80,
               "Dock Preview left panel sits to the right of the Dock")
        let rightFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 1360, y: 380, width: 80, height: 80),
                                                       panelSize: panelSize,
                                                       screenVisibleFrame: screen,
                                                       orientation: .right)
        expect(rightFrame.maxX < 1360,
               "Dock Preview right panel sits to the left of the Dock")
        let corridor = DockPreviewSupport.hoverCorridor(iconFrame: iconBottom,
                                                        panelFrame: bottomFrame,
                                                        orientation: .bottom)
        expect(corridor.contains(CGPoint(x: iconBottom.midX, y: (iconBottom.maxY + bottomFrame.minY) / 2)),
               "Dock Preview corridor keeps the path from Dock icon to panel alive")
        // A neighbouring Dock icon, one tile to the side, must fall OUTSIDE the
        // corridor; otherwise returning to the Dock can never hand the session to
        // another app and the panel stays stuck on the previous one.
        let neighborIcon = CGRect(x: iconBottom.maxX + 8, y: 0, width: 80, height: 80)
        expect(!corridor.contains(CGPoint(x: neighborIcon.midX, y: neighborIcon.midY)),
               "Dock Preview corridor excludes the neighbouring Dock icon so app switching works")
        expect(DockPreviewSupport.shouldRestoreOnEnd(committed: false),
               "Dock Preview restores the previous window when cancelled")
        expect(!DockPreviewSupport.shouldRestoreOnEnd(committed: true),
               "Dock Preview does not restore after a confirmed click")
        expect(DockPreviewSupport.dockProximityBand(tileSize: 64) >= 160,
               "Dock proximity band covers a default-size Dock")
        expect(DockPreviewSupport.dockProximityBand(tileSize: 200)
               > DockPreviewSupport.dockProximityBand(tileSize: 64),
               "Dock proximity band grows with the Dock tile size")
        let onePreviewSize = DockPreviewSupport.panelSize(itemCount: 1, screenVisibleFrame: screen)
        let twoPreviewSize = DockPreviewSupport.panelSize(itemCount: 2, screenVisibleFrame: screen)
        expect(twoPreviewSize.width > onePreviewSize.width,
               "Dock Preview panel size shrinks when a card is removed")
        expect(onePreviewSize.height == DockPreviewSupport.cardHeight
               + DockPreviewSupport.panelPadding * 2
               + DockPreviewSupport.panelHeaderHeight,
               "Dock Preview panel reserves room for the pinned header")
        expect(DockPreviewSupport.windowPositionText(selectedWindowID: nil, windowIDs: [11]) == nil,
               "Dock Preview hides the window counter for a single window")
        expect(DockPreviewSupport.windowPositionText(selectedWindowID: nil, windowIDs: [11, 22, 33]) == "3",
               "Dock Preview header shows the window count before a card is selected")
        expect(DockPreviewSupport.windowPositionText(selectedWindowID: 22, windowIDs: [11, 22, 33]) == "2/3",
               "Dock Preview header shows selected window position")
        let iconRowLayout = SwitcherIconRowLayout.compute(count: 6, screenVisibleFrame: screen)
        expect(iconRowLayout.visibleIconCount == 6,
               "App Switcher icon-row mode can show all icons when they fit")
        expect(iconRowLayout.panelSize.width <= screen.width * 0.96 + SwitcherIconRowLayout.padding * 2,
               "App Switcher icon-row mode stays within the visible screen")
        expect(iconRowLayout.panelSize.height
               == SwitcherIconRowLayout.previewHeight
               + SwitcherIconRowLayout.previewGap
               + SwitcherIconRowLayout.rowHeight
               + SwitcherIconRowLayout.hintGap
               + SwitcherIconRowLayout.hintHeight
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher icon-row mode reserves preview, icon row and shortcut hint height")
        expect(iconRowLayout.simplePanelSize.height
               == SwitcherIconRowLayout.simpleTitleHeight
               + SwitcherIconRowLayout.simpleTitleGap
               + SwitcherIconRowLayout.rowHeight
               + SwitcherIconRowLayout.hintGap
               + SwitcherIconRowLayout.hintHeight
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher simple mode replaces previews with a compact title rail")
        expect(iconRowLayout.simplePanelSize.width
               == max(iconRowLayout.appRowSurfaceWidth, SwitcherIconRowLayout.hintBarWidth)
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher simple mode fits the app row and shortcut hints")
        expect(SwitcherSupport.gridSelectionIndex(after: 1,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 6,
               "App Switcher down navigation keeps the same column when it exists")
        expect(SwitcherSupport.gridSelectionIndex(after: 4,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 7,
               "App Switcher down navigation lands on the last item of a shorter row")
        expect(SwitcherSupport.gridSelectionIndex(after: 7,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 7,
               "App Switcher down navigation stays put on the final row")
        expect(SwitcherSupport.gridSelectionIndex(after: 6,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: false) == 1,
               "App Switcher up navigation keeps its existing column behavior")
        let previousPreviewSize = UserDefaults.standard.object(forKey: DefaultsKey.previewSize)
        UserDefaults.standard.set("xlarge", forKey: DefaultsKey.previewSize)
        let xlargeIconRowLayout = SwitcherIconRowLayout.compute(appCount: 6,
                                                                 selectedWindowCount: 1,
                                                                 screenVisibleFrame: screen)
        expect(SwitcherIconRowLayout.scale <= 1.15,
               "App Switcher icon-row mode caps Extra High preview scaling")
        expect(xlargeIconRowLayout.panelSize.height < 540,
               "App Switcher icon-row mode stays compact with Extra High previews")
        expect(xlargeIconRowLayout.panelSize.width < 950,
               "App Switcher icon-row mode avoids a giant empty backdrop with six apps")
        let xlargeSingleWindowLayout = SwitcherIconRowLayout.compute(appCount: 1,
                                                                     selectedWindowCount: 1,
                                                                     screenVisibleFrame: screen)
        expectClose(Double(xlargeSingleWindowLayout.previewContentWidth),
                    Double(SwitcherIconRowLayout.previewCardWidth),
                    "App Switcher icon-row mode keeps a one-window preview card compact")
        expectClose(Double(xlargeSingleWindowLayout.previewSurfaceWidth),
                    Double(SwitcherIconRowLayout.previewCardWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                    "App Switcher icon-row mode keeps padding around a one-window preview card")
        expect(xlargeSingleWindowLayout.panelSize.width < 430,
               "App Switcher icon-row mode avoids a giant horizontal panel for one app with one window")
        if let previousPreviewSize {
            UserDefaults.standard.set(previousPreviewSize, forKey: DefaultsKey.previewSize)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.previewSize)
        }
        let defaultSwitcherHints = SwitcherSupport.shortcutHints(for: .switcherDefault,
                                                                 windowShortcut: .switcherWindowDefault)
        expect(defaultSwitcherHints.apps == "⌘Tab" && defaultSwitcherHints.windows == "⌘ `",
               "App Switcher icon-row hints describe default app and window shortcuts")
        let customSwitcherHints = SwitcherSupport.shortcutHints(
            for: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.option]),
            windowShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.command])
        )
        expect(customSwitcherHints.apps == "⌥Tab" && customSwitcherHints.windows == "⌘J",
               "App Switcher icon-row hints show custom app and window shortcuts independently")
        expect(SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                  wasShiftHeld: false,
                                                                  isShiftHeld: true),
               "App Switcher shift-only back navigation fires when Shift is pressed")
        expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                   wasShiftHeld: true,
                                                                   isShiftHeld: true),
               "App Switcher shift-only back navigation does not repeat while Shift is held")
        expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                   wasShiftHeld: true,
                                                                   isShiftHeld: false),
               "App Switcher shift-only back navigation does not fire on Shift release")
        expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: false,
                                                                   wasShiftHeld: false,
                                                                   isShiftHeld: true),
               "App Switcher shift-only back navigation stays off when Shift belongs to the shortcut")

        func syntheticCapture(_ draw: (CGContext, CGSize) -> Void) -> CGImage? {
            let size = CGSize(width: 320, height: 200)
            guard let context = CGContext(data: nil,
                                          width: Int(size.width),
                                          height: Int(size.height),
                                          bitsPerComponent: 8,
                                          bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            draw(context, size)
            return context.makeImage()
        }
        let opaqueCapture = syntheticCapture { context, size in
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        let roundedCapture = syntheticCapture { context, size in
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                              cornerWidth: 12, cornerHeight: 12, transform: nil)
            context.addPath(path)
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fillPath()
        }
        let shearedCapture = syntheticCapture { context, size in
            context.translateBy(x: size.width * 0.35, y: size.height * 0.3)
            context.concatenate(CGAffineTransform(a: 0.35, b: 0.12, c: -0.18, d: 0.35, tx: 0, ty: 0))
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        // A sheared capture whose bounding box hugs the artwork: only the two
        // corners outside the parallelogram stay transparent.
        let tightShearCapture = syntheticCapture { context, size in
            context.move(to: CGPoint(x: size.width * 0.25, y: 0))
            context.addLine(to: CGPoint(x: size.width, y: 0))
            context.addLine(to: CGPoint(x: size.width * 0.75, y: size.height))
            context.addLine(to: CGPoint(x: 0, y: size.height))
            context.closePath()
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fillPath()
        }
        if let opaqueCapture, let grid = SwitcherSupport.alphaGrid(of: opaqueCapture) {
            expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher keeps captures of fully opaque windows")
        } else {
            expect(false, "switcher alpha grid renders an opaque synthetic capture")
        }
        if let roundedCapture, let grid = SwitcherSupport.alphaGrid(of: roundedCapture) {
            expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher keeps captures of windows with rounded corners")
        } else {
            expect(false, "switcher alpha grid renders a rounded synthetic capture")
        }
        if let shearedCapture, let grid = SwitcherSupport.alphaGrid(of: shearedCapture) {
            expect(SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher rejects the small sheared snapshot Stage Manager renders for parked windows")
        } else {
            expect(false, "switcher alpha grid renders a sheared synthetic capture")
        }
        if let tightShearCapture, let grid = SwitcherSupport.alphaGrid(of: tightShearCapture) {
            expect(SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher rejects sheared captures even when the bounding box hugs the artwork")
        } else {
            expect(false, "switcher alpha grid renders a tight sheared synthetic capture")
        }
        expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: [], gridSize: 8),
               "switcher capture classifier tolerates a malformed alpha grid")

        expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3], active: [], lastTouched: [:], limit: 3).isEmpty,
               "switcher preview cache keeps everything under the limit")
        expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3, 4],
                                                 active: [1],
                                                 lastTouched: [2: 10, 3: 5, 4: 20],
                                                 limit: 3) == [3],
               "switcher preview cache evicts the least recently used entry beyond the limit")
        expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3, 4],
                                                 active: [3],
                                                 lastTouched: [1: 1, 2: 2, 4: 4],
                                                 limit: 2) == [1, 2],
               "switcher preview cache never evicts entries being refreshed right now")
        expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 30, 2: 30],
                                                      active: [],
                                                      lastTouched: [1: 1, 2: 2],
                                                      budget: 100).isEmpty,
               "preview byte budget keeps everything while under budget")
        expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 60, 2: 60, 3: 60],
                                                      active: [],
                                                      lastTouched: [1: 1, 2: 2, 3: 3],
                                                      budget: 100) == [1, 2],
               "preview byte budget evicts least recently used entries until the bytes fit")
        expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 60, 2: 60, 3: 60],
                                                      active: [1],
                                                      lastTouched: [1: 1, 2: 2, 3: 3],
                                                      budget: 100) == [2, 3],
               "preview byte budget never evicts entries being refreshed right now")

        // Sheared alpha mask (rows shift right going down): corner detection
        // must find the parallelogram's extremes so rectification can undo it.
        let quadWidth = 120, quadHeight = 100
        var shearAlpha = [UInt8](repeating: 0, count: quadWidth * quadHeight)
        for y in 0..<quadHeight {
            let shift = y * 20 / quadHeight
            for x in shift..<(80 + shift) {
                shearAlpha[y * quadWidth + x] = 255
            }
        }
        if let corners = SwitcherSupport.opaqueQuadCorners(alpha: shearAlpha,
                                                           width: quadWidth,
                                                           height: quadHeight) {
            expect(corners.topLeft == CGPoint(x: 0, y: 0)
                   && corners.topRight == CGPoint(x: 79, y: 0)
                   && corners.bottomRight == CGPoint(x: 98, y: 99)
                   && corners.bottomLeft == CGPoint(x: 19, y: 99),
                   "switcher quad corners land on the sheared mask extremes")
        } else {
            expect(false, "switcher quad corners resolve for a sheared mask")
        }
        expect(SwitcherSupport.opaqueQuadCorners(alpha: [UInt8](repeating: 0, count: quadWidth * quadHeight),
                                                 width: quadWidth,
                                                 height: quadHeight) == nil,
               "switcher quad corners reject an empty capture")

        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .minimize,
               "dock click minimizes the frontmost app with visible windows")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .passThrough,
               "dock click lets the Dock activate apps that are not frontmost")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .restore,
               "dock click restores when every window is minimized")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .restore,
               "dock click restores minimized windows of background apps too")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .passThrough,
               "dock click passes through for windowless apps")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false) == .passThrough,
               "dock click stays hands-off while the app has a fullscreen window")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: true) == .passThrough,
               "dock click keeps the Dock's native modifier shortcuts")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       unminimizedWindowCount: 3) == .cycleWindows,
               "dock click cycles instead of minimizing when both are on and there are windows to cycle")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       unminimizedWindowCount: 1) == .minimize,
               "dock click still minimizes a single-window app with cycling on")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       unminimizedWindowCount: 1) == .passThrough,
               "cycling alone never minimizes a single-window app")
        expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       unminimizedWindowCount: 0) == .passThrough,
               "cycling alone never restores minimized windows")
        expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       unminimizedWindowCount: 3) == .passThrough,
               "cycling lets the Dock activate apps that are not frontmost")
        expect(DockClickSupport.repeatDecision(lastAction: .cycleWindows, elapsed: 0.5) == .deriveFromState,
               "a repeated click after a cycle keeps cycling from live state")

        expect(DockClickSupport.repeatDecision(lastAction: nil, elapsed: nil) == .deriveFromState,
               "dock click derives the first click from window state")
        expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 0.1) == .swallow,
               "dock click swallows accidental double-clicks")
        expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 0.5) == .toggle(.restore),
               "dock click right after a minimize toggles straight back to restore")
        expect(DockClickSupport.repeatDecision(lastAction: .restore, elapsed: 0.5) == .toggle(.minimize),
               "dock click right after a restore toggles back to minimize")
        expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 2.0) == .deriveFromState,
               "dock click trusts settled window state once the intent window passes")

        expect(DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                       modifiers: 2,
                                                       identifier: "miniaturizeAll:"),
               "dock click recognizes the standard Minimize All menu action")
        expect(!DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                        modifiers: 2,
                                                        identifier: "toggleCompactWindow:"),
               "dock click rejects an unrelated action that shares the Minimize All shortcut")
        expect(!DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                        modifiers: 2,
                                                        identifier: nil),
               "dock click never guesses when an Option-Command-M action has no identifier")

        // Bottom Dock reserving ~70 pt: only the reserved strip counts, so a
        // click on a preview panel floating just above the Dock passes through.
        let dockScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bottomDockVisible = CGRect(x: 0, y: 24, width: 1512, height: 888)
        expect(DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: bottomDockVisible),
               "dock strip accepts clicks inside the reserved bottom strip")
        expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 880),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: bottomDockVisible),
               "dock strip rejects clicks hovering above the Dock, like a preview panel")
        expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 20),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: bottomDockVisible),
               "dock strip ignores the top edge where the Dock never lives")
        let leftDockVisible = CGRect(x: 70, y: 24, width: 1442, height: 958)
        expect(DockClickSupport.dockStripContains(CGPoint(x: 40, y: 500),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: leftDockVisible),
               "dock strip accepts clicks inside a left Dock's reserved strip")
        expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: leftDockVisible),
               "dock strip rejects bottom clicks when the Dock lives on the left")
        expect(DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: CGRect(x: 0, y: 24, width: 1512, height: 958)),
               "dock strip falls back to an edge band when auto-hide reserves nothing")

        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .transform,
               "middle click transforms a settled three-finger press")
        expect(MiddleClickSupport.actionForClick(fingerCount: 2, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click leaves two-finger clicks alone")
        expect(MiddleClickSupport.actionForClick(fingerCount: 4, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click leaves four-finger clicks alone")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 1.0, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click ignores stale contact frames (fingers already lifted)")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.01,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click rejects a click arriving with the third finger's touchdown")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: 0.1,
                                                 systemDragGestureEnabled: false) == .swallow,
               "middle click drops the tap-to-click bounce right after a transform")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: 0.5,
                                                 systemDragGestureEnabled: false) == .transform,
               "middle click accepts a deliberate second press after the guard window")
        expect(MiddleClickSupport.actionForClick(fingerCount: 1, frameAge: 0.05, settledFor: 0,
                                                 sinceLastTransformEnd: 0.1,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click never swallows ordinary one-finger clicks")
        expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: true) == .passThrough,
               "middle click stands down while the system three-finger drag owns the gesture")

        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hex), "#FF0000",
                    "color picker formats pure red as hex")
        expectEqual(QuickToolsSupport.colorString(red: 0.2, green: 0.4, blue: 0.6, format: .rgb),
                    "rgb(51, 102, 153)",
                    "color picker formats components as CSS rgb")
        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hsl),
                    "hsl(0, 100%, 50%)",
                    "color picker formats pure red as hsl")
        expectEqual(QuickToolsSupport.colorString(red: 0, green: 0.5, blue: 0, format: .hsl),
                    "hsl(120, 100%, 25%)",
                    "color picker formats dark green as hsl")
        expectEqual(QuickToolsSupport.colorString(red: 0.25, green: 0.5, blue: 0.75, format: .swiftui),
                    "Color(red: 0.250, green: 0.500, blue: 0.750)",
                    "color picker formats components as SwiftUI code")
        expectEqual(QuickToolsSupport.colorString(red: 1.4, green: -0.2, blue: 0.5, format: .hex), "#FF0080",
                    "color picker clamps extended-gamut components")
        expect(ColorCopyFormat.sanitized("banana") == .hex,
               "color picker falls back to hex for unknown stored formats")
        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hex, bareHex: true),
                    "FF0000",
                    "color picker drops the leading # when the bare hex option is on")
        expectEqual(QuickToolsSupport.colorString(red: 0.2, green: 0.4, blue: 0.6, format: .rgb, bareHex: true),
                    "rgb(51, 102, 153)",
                    "bare hex option leaves the other copy formats untouched")

        let ocrLines = [
            QuickToolsSupport.RecognizedLine(text: "world", x: 0.5, y: 0.8),
            QuickToolsSupport.RecognizedLine(text: "hello", x: 0.1, y: 0.81),
            QuickToolsSupport.RecognizedLine(text: "below", x: 0.1, y: 0.4),
            QuickToolsSupport.RecognizedLine(text: "   ", x: 0.2, y: 0.6),
        ]
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines), "hello\nworld\nbelow",
                    "screen OCR joins lines top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedRecognizedText([]), "",
                    "screen OCR joins an empty result to an empty string")

        // QR codes: several join top to bottom, left to right, blanks dropped.
        let qrCodes = [
            QuickToolsSupport.DecodedBarcode(payload: "second", x: 0.6, y: 0.8),
            QuickToolsSupport.DecodedBarcode(payload: "first", x: 0.1, y: 0.81),
            QuickToolsSupport.DecodedBarcode(payload: "bottom", x: 0.1, y: 0.3),
            QuickToolsSupport.DecodedBarcode(payload: "  ", x: 0.2, y: 0.5),
        ]
        expectEqual(QuickToolsSupport.joinedBarcodePayloads(qrCodes), "first\nsecond\nbottom",
                    "QR codes join top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedBarcodePayloads([]), "",
                    "no QR codes joins to an empty string")

        // Open link is limited to http and https so a scanned code can never
        // launch another scheme.
        expect(QuickToolsSupport.openableURL(from: "https://example.com/menu")?.absoluteString
                    == "https://example.com/menu",
               "an https payload is offered as an open link")
        expect(QuickToolsSupport.openableURL(from: " http://example.com ")?.host == "example.com",
               "surrounding whitespace does not stop a plain web link")
        expect(QuickToolsSupport.openableURL(from: "WIFI:S:Net;T:WPA;P:secret;;") == nil,
               "a Wi-Fi payload is copied, never opened")
        expect(QuickToolsSupport.openableURL(from: "mailto:a@b.com") == nil,
               "a mailto payload is not treated as an open link")
        expect(QuickToolsSupport.openableURL(from: "just some text") == nil,
               "plain text is never an open link")
        expect(QuickToolsSupport.openableURL(from: "example.com") == nil,
               "a bare host with no scheme is not opened")

        // Launcher grid: 8 items in 3 columns (rows of 3, 3, 2).
        expect(QuickToolsSupport.gridIndex(after: 0, count: 8, columns: 3, direction: .right) == 1,
               "launcher grid moves right within a row")
        expect(QuickToolsSupport.gridIndex(after: 2, count: 8, columns: 3, direction: .right) == 2,
               "launcher grid does not wrap at the row's right edge")
        expect(QuickToolsSupport.gridIndex(after: 3, count: 8, columns: 3, direction: .left) == 3,
               "launcher grid does not wrap at the row's left edge")
        expect(QuickToolsSupport.gridIndex(after: 1, count: 8, columns: 3, direction: .down) == 4,
               "launcher grid moves down one row")
        expect(QuickToolsSupport.gridIndex(after: 7, count: 8, columns: 3, direction: .down) == 7,
               "launcher grid stays put when there is no row below")
        expect(QuickToolsSupport.gridIndex(after: 4, count: 8, columns: 3, direction: .up) == 1,
               "launcher grid moves up one row")
        expect(QuickToolsSupport.gridIndex(after: 6, count: 8, columns: 3, direction: .right) == 7,
               "launcher grid moves right in the last partial row")
        expect(QuickToolsSupport.gridIndex(after: 99, count: 8, columns: 3, direction: .left) == 6,
               "launcher grid clamps an out-of-range index")
        expect(QuickToolsSupport.gridIndex(after: 0, count: 0, columns: 3, direction: .down) == 0,
               "launcher grid survives an empty item list")

        expect(QuickToolsSupport.hiddenIDs(from: "a,b,,c") == Set(["a", "b", "c"]),
               "launcher hidden set parses and drops empties")
        expectEqual(QuickToolsSupport.serializeHiddenIDs(Set(["b", "a"])), "a,b",
                    "launcher hidden set serializes deterministically")
        expect(QuickToolsSupport.hiddenIDs(from: QuickToolsSupport.serializeHiddenIDs(Set(["x", "y"])))
                   == Set(["x", "y"]),
               "launcher hidden set round-trips")
        let groupedSwitcherItems = [
            SwitcherItem.window(id: 1, title: "One", appName: "Alpha", pid: 101,
                                isOnScreen: true, frame: .zero),
            SwitcherItem.window(id: 2, title: "Two", appName: "Alpha", pid: 101,
                                isOnScreen: true, frame: .zero),
            SwitcherItem.window(id: 3, title: "Main", appName: "Beta", pid: 202,
                                isOnScreen: true, frame: .zero),
        ]
        let appGroups = SwitcherSupport.appGroups(items: groupedSwitcherItems)
        expect(appGroups.count == 2
               && appGroups[0].representativeIndex == 0
               && appGroups[0].windowCount == 2
               && appGroups[1].representativeIndex == 2,
               "App Switcher icon-row mode keeps one row entry per app")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: 1) == 2,
               "App Switcher icon-row app navigation skips duplicate windows from the same app")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 2,
                                                     delta: -1) == 0,
               "App Switcher icon-row app navigation wraps backward by app")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 2,
                                                     delta: 1,
                                                     wrapping: false) == 2,
               "held key stops at the last app instead of wrapping, like the system switcher")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: -1,
                                                     wrapping: false) == 0,
               "held key stops at the first app when navigating backward")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: 1,
                                                     wrapping: false) == 2,
               "non-wrapping navigation still advances while not at the edge")
        expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 0,
                                                                 delta: 1) == 1,
               "App Switcher icon-row window navigation moves within the selected app")
        expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 1,
                                                                 delta: 1) == 0,
               "App Switcher icon-row window navigation wraps within the selected app")
        expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 2,
                                                                 delta: 1) == 2,
               "App Switcher icon-row window navigation stays put when the app has one window")
        let afterFirstSwitch = SwitcherSupport.updatedMRU(afterActivating: "window-b",
                                                          previousID: "window-a",
                                                          existing: [])
        expect(afterFirstSwitch == ["window-b", "window-a"],
               "App Switcher MRU records the previous window immediately after a switch")
        let afterSecondSwitch = SwitcherSupport.updatedMRU(afterActivating: "window-a",
                                                           previousID: "window-b",
                                                           existing: afterFirstSwitch)
        expect(afterSecondSwitch == ["window-a", "window-b"],
               "App Switcher MRU toggles back after two consecutive switcher uses")
        let groupedIconLayout = SwitcherIconRowLayout.compute(appCount: appGroups.count,
                                                              selectedWindowCount: appGroups[0].windowCount,
                                                              screenVisibleFrame: screen)
        expect(groupedIconLayout.appRowContentWidth
               >= CGFloat(appGroups.count) * SwitcherIconRowLayout.appTileWidth,
               "App Switcher icon-row layout uses full app tile width")
        expect(groupedIconLayout.previewContentWidth
               >= CGFloat(appGroups[0].windowCount) * SwitcherIconRowLayout.previewCardWidth,
               "App Switcher icon-row layout reserves room for selected app previews")
        expectClose(Double(groupedIconLayout.appRowSurfaceWidth),
                    Double(groupedIconLayout.appRowContentWidth + SwitcherIconRowLayout.rowHorizontalPadding * 2),
                    "App Switcher icon-row layout keeps horizontal padding inside the app row surface")
        expectClose(Double(groupedIconLayout.previewSurfaceWidth),
                    Double(groupedIconLayout.previewContentWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                    "App Switcher icon-row layout keeps preview cards away from the surface border")
        let issue128Layout = SwitcherIconRowLayout.compute(appCount: 7,
                                                           selectedWindowCount: 2,
                                                           screenVisibleFrame: screen)
        let issue128LeftPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 7,
            selectedAppIndex: 1,
            selectedWindowIndex: 0,
            selectedWindowCount: 2,
            visibleIconCount: issue128Layout.visibleIconCount,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        let leftAppCenter = SwitcherIconRowLayout.appTileWidth / 2
            + SwitcherIconRowLayout.appTileWidth
            + SwitcherIconRowLayout.spacing
        func expectedPreviewLeading(selectedCenterInRow: CGFloat,
                                    layout: SwitcherIconRowLayout) -> CGFloat {
            let contentWidth = max(layout.appRowSurfaceWidth, layout.previewSurfaceWidth)
            let rawLeading = selectedCenterInRow - layout.previewSurfaceWidth / 2
            return min(max(0, rawLeading), contentWidth - layout.previewSurfaceWidth)
        }
        let issue128ContentWidth = max(issue128Layout.appRowSurfaceWidth, issue128Layout.previewSurfaceWidth)
        let issue128RowLeading = max(0, (issue128ContentWidth - issue128Layout.appRowSurfaceWidth) / 2)
            + SwitcherIconRowLayout.rowHorizontalPadding
        let leftPreviewLeading = expectedPreviewLeading(selectedCenterInRow: issue128RowLeading + leftAppCenter,
                                                        layout: issue128Layout)
        expectClose(Double(issue128LeftPlacement.leading),
                    Double(leftPreviewLeading),
                    "App Switcher icon-row preview anchors to a left-side selected app")
        let issue128SecondWindowPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 7,
            selectedAppIndex: 1,
            selectedWindowIndex: 1,
            selectedWindowCount: 2,
            visibleIconCount: issue128Layout.visibleIconCount,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        expectClose(Double(issue128SecondWindowPlacement.leading),
                    Double(issue128LeftPlacement.leading),
                    "App Switcher icon-row preview does not move when switching windows inside one app")
        let issue128CenterPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 7,
            selectedAppIndex: 3,
            selectedWindowIndex: 0,
            selectedWindowCount: 2,
            visibleIconCount: issue128Layout.visibleIconCount,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        let centerAppCenter = SwitcherIconRowLayout.appTileWidth / 2
            + 3 * (SwitcherIconRowLayout.appTileWidth + SwitcherIconRowLayout.spacing)
        let centerPreviewLeading = expectedPreviewLeading(selectedCenterInRow: issue128RowLeading + centerAppCenter,
                                                          layout: issue128Layout)
        expectClose(Double(issue128CenterPlacement.leading),
                    Double(centerPreviewLeading),
                    "App Switcher icon-row preview anchors to a centered selected app")
        let scrollingPreviewPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 20,
            selectedAppIndex: 1,
            selectedWindowIndex: 0,
            selectedWindowCount: 2,
            visibleIconCount: 6,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        let scrollingPreviewLeading = expectedPreviewLeading(
            selectedCenterInRow: issue128RowLeading + issue128Layout.appRowContentWidth / 2,
            layout: issue128Layout
        )
        expectClose(Double(scrollingPreviewPlacement.leading),
                    Double(scrollingPreviewLeading),
                    "App Switcher icon-row preview anchors to the visible app row when the app row scrolls")
        let manyWindowLayout = SwitcherIconRowLayout.compute(appCount: 20,
                                                             selectedWindowCount: 12,
                                                             screenVisibleFrame: screen)
        let scrollingWindowPreviewPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 20,
            selectedAppIndex: 1,
            selectedWindowIndex: 6,
            selectedWindowCount: 12,
            visibleIconCount: manyWindowLayout.visibleIconCount,
            appRowContentWidth: manyWindowLayout.appRowContentWidth,
            appRowSurfaceWidth: manyWindowLayout.appRowSurfaceWidth,
            previewContentWidth: manyWindowLayout.previewContentWidth,
            previewSurfaceWidth: manyWindowLayout.previewSurfaceWidth
        )
        let centeredPreviewLeading = (scrollingWindowPreviewPlacement.contentWidth - manyWindowLayout.previewSurfaceWidth) / 2
        expectClose(Double(scrollingWindowPreviewPlacement.leading), Double(centeredPreviewLeading),
                    "App Switcher icon-row preview stays centered when the window preview row scrolls")
        let singleWindowAppLayout = SwitcherIconRowLayout.compute(appCount: appGroups.count,
                                                                  selectedWindowCount: appGroups[1].windowCount,
                                                                  screenVisibleFrame: screen)
        expect(singleWindowAppLayout.previewContentWidth == SwitcherIconRowLayout.previewCardWidth,
               "App Switcher icon-row layout does not reserve empty preview slots for a one-window app")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: 22,
                                                   windowIDs: [11, 22, 33],
                                                   offset: 1) == 33,
               "Dock Preview next button selects the next window")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: 11,
                                                   windowIDs: [11, 22, 33],
                                                   offset: -1) == 33,
               "Dock Preview previous button wraps from the first window to the last")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [11, 22, 33],
                                                   offset: 1) == 11,
               "Dock Preview next button starts from the first window when none is selected")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [11, 22, 33],
                                                   offset: -1) == 33,
               "Dock Preview previous button starts from the last window when none is selected")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [],
                                                   offset: 1) == nil,
               "Dock Preview navigation handles an empty window list")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: true,
                                                    isInsidePanel: false,
                                                    clickedDock: false)
               == DockPreviewMouseDownDecision(shouldEndSession: false, restoreOrigin: false),
               "Dock Preview pinned panel ignores outside clicks")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: true,
                                                    clickedDock: false)
               == DockPreviewMouseDownDecision(shouldEndSession: false, restoreOrigin: false),
               "Dock Preview panel clicks are handled by the panel")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: false,
                                                    clickedDock: true)
               == DockPreviewMouseDownDecision(shouldEndSession: true, restoreOrigin: false),
               "Dock Preview Dock clicks close without restoring the previous window")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: false,
                                                    clickedDock: false)
               == DockPreviewMouseDownDecision(shouldEndSession: true, restoreOrigin: true),
               "Dock Preview outside clicks close and restore the previous window")
        expect(!DockPreviewSupport.shouldRestoreOriginAfterMinimize(originPID: 10,
                                                                    originWindowID: 44,
                                                                    targetPID: 10,
                                                                    targetWindowID: 44),
               "Dock Preview does not restore the same window after minimizing it")
        expect(DockPreviewSupport.shouldRestoreOriginAfterMinimize(originPID: 10,
                                                                   originWindowID: 44,
                                                                   targetPID: 10,
                                                                   targetWindowID: 45),
               "Dock Preview can restore a different source window after minimizing a preview")
        expect(DockPreviewSupport.shouldRestoreOriginAfterMinimize(originPID: 10,
                                                                   originWindowID: 44,
                                                                   targetPID: 20,
                                                                   targetWindowID: 45),
               "Dock Preview can restore a different source app after minimizing a preview")
        let closeMiddle = DockPreviewSupport.closeState(afterRemoving: 22,
                                                        windowIDs: [11, 22, 33],
                                                        selectedWindowID: 22,
                                                        activePeekWindowID: 22,
                                                        desiredWindowID: 22)
        expect(closeMiddle.remainingWindowIDs == [11, 33],
               "Dock Preview close removes only the closed window")
        expect(closeMiddle.selectedWindowID == nil
               && closeMiddle.activePeekWindowID == nil
               && closeMiddle.desiredWindowID == nil,
               "Dock Preview close clears selection and peek for the closed window")
        expect(!closeMiddle.shouldEndSession,
               "Dock Preview close keeps the panel open when other windows remain")
        let closeUnselected = DockPreviewSupport.closeState(afterRemoving: 22,
                                                            windowIDs: [11, 22, 33],
                                                            selectedWindowID: 11,
                                                            activePeekWindowID: 33,
                                                            desiredWindowID: 33)
        expect(closeUnselected.selectedWindowID == 11
               && closeUnselected.activePeekWindowID == 33
               && closeUnselected.desiredWindowID == 33,
               "Dock Preview close preserves selection and peek for other windows")
        let closeLast = DockPreviewSupport.closeState(afterRemoving: 44,
                                                      windowIDs: [44],
                                                      selectedWindowID: 44,
                                                      activePeekWindowID: nil,
                                                      desiredWindowID: nil)
        expect(closeLast.shouldEndSession && closeLast.remainingWindowIDs.isEmpty,
               "Dock Preview close ends the panel when the last window is removed")
        let dockPreviewWindow = SwitcherItem.window(id: 77,
                                                    title: "Preview",
                                                    appName: "Demo",
                                                    pid: 123,
                                                    isOnScreen: true,
                                                    frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        let minimizedDockPreviewWindow = dockPreviewWindow.withMinimized(true)
        expect(minimizedDockPreviewWindow.id == dockPreviewWindow.id
               && minimizedDockPreviewWindow.windowID == dockPreviewWindow.windowID
               && minimizedDockPreviewWindow.isMinimized
               && !minimizedDockPreviewWindow.isOnScreen,
               "Dock Preview minimize state keeps the same window identity")
        let restoredDockPreviewWindow = minimizedDockPreviewWindow.withMinimized(false)
        expect(restoredDockPreviewWindow.id == dockPreviewWindow.id
               && !restoredDockPreviewWindow.isMinimized
               && restoredDockPreviewWindow.isOnScreen,
               "Dock Preview restore clears the minimized state without changing identity")
        expect(SwitcherSupport.activationPlan(targetsSpecificWindow: true)
               == SwitcherActivationPlan(activateAllWindows: false,
                                         makeAppFrontmostAfterActivation: false,
                                         restoreSourceWhenTargetMinimizes: true),
               "App Switcher keeps specific-window activation scoped to one window")
        expect(SwitcherSupport.activationPlan(targetsSpecificWindow: false)
               == SwitcherActivationPlan(activateAllWindows: true,
                                         makeAppFrontmostAfterActivation: true,
                                         restoreSourceWhenTargetMinimizes: false),
               "App Switcher can activate the full app for app-only entries")
        expect(!SwitcherSupport.shouldActivateAllWindows(targetsSpecificWindow: true),
               "App Switcher activates only the selected window when a window target exists")
        expect(SwitcherSupport.shouldActivateAllWindows(targetsSpecificWindow: false),
               "App Switcher can activate the full app for app-only entries")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 10,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99),
               "App Switcher restores the previous app when a specific target window is minimized")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 10,
                                                                       frontmostPID: 10,
                                                                       targetIsMinimized: true,
                                                                       ownPID: 99),
               "App Switcher does not restore when the source is another window from the same app")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 20,
                                                                       frontmostPID: 30,
                                                                       targetIsMinimized: true,
                                                                       ownPID: 99),
               "App Switcher does not steal focus if the user already moved to another app")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 30,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99,
                                                                      frontmostMatchesTargetBundle: true),
               "App Switcher restores the previous app if a sibling app instance is promoted after minimize")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 30,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99,
                                                                      frontmostCanBeSystemPromotion: true),
               "App Switcher restores the previous app if the system promotes another window during minimize")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 20,
                                                                       frontmostPID: 10,
                                                                       targetIsMinimized: false,
                                                                       ownPID: 99),
               "App Switcher restores the previous app only after the target window is minimized")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 10,
                                                                            focusedWindowID: 44,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99),
               "App Switcher restores the source after a minimize-button intent once the target is minimized")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 10,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: false,
                                                                            ownPID: 99),
               "App Switcher restores the source if the target app focuses another window after minimize intent")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 20,
                                                                             frontmostPID: 10,
                                                                             focusedWindowID: 44,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: false,
                                                                             ownPID: 99),
               "App Switcher waits when minimize intent is observed but the target remains focused and unminimized")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 20,
                                                                             frontmostPID: 30,
                                                                             focusedWindowID: 55,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: false,
                                                                             ownPID: 99),
               "App Switcher does not restore source after minimize intent if a third app is already active")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 30,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99,
                                                                            frontmostMatchesTargetBundle: true),
               "App Switcher restores after minimize intent if a sibling app instance is promoted")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 30,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99,
                                                                            frontmostCanBeSystemPromotion: true),
               "App Switcher restores after minimize intent if the system promotes another app")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 10,
                                                                             frontmostPID: 10,
                                                                             focusedWindowID: 55,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: true,
                                                                             ownPID: 99),
               "App Switcher does not restore source after minimize intent within the same app")
        expect(SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                             sourcePID: 20,
                                                             sourceWindowID: 44),
               "App Switcher can keep the source window directly behind a selected target window")
        expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 10,
                                                              sourceWindowID: 44),
               "App Switcher does not stage a source window from the same app")
        expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 20,
                                                              sourceWindowID: nil),
               "App Switcher does not stage without a concrete source window")
        expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 10,
                                                        targetIsMinimized: false,
                                                        ownPID: 99),
               "App Switcher focus retries can continue while the selected target app is still active")
        expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 20,
                                                        targetIsMinimized: false,
                                                        ownPID: 99),
               "App Switcher focus retries can continue during the source-target handoff")
        expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 20,
                                                         targetIsMinimized: true,
                                                         ownPID: 99),
               "App Switcher focus retries stop once the selected target window was minimized")
        expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: false,
                                                         ownPID: 99),
               "App Switcher focus retries do not steal focus after the user moves to another app")
        expect(SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                sourcePID: 20,
                                                                frontmostPID: 20,
                                                                targetWasObservedFrontmost: false,
                                                                ownPID: 99),
               "App Switcher can retry an app-only target during a fullscreen handoff")
        expect(SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                sourcePID: 20,
                                                                frontmostPID: 10,
                                                                targetWasObservedFrontmost: true,
                                                                ownPID: 99),
               "App Switcher can settle repeated activation on the app-only target")
        expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 frontmostPID: 20,
                                                                 targetWasObservedFrontmost: true,
                                                                 ownPID: 99),
               "App Switcher cancels app-only retries when the user returns to the fullscreen source")
        expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 frontmostPID: 30,
                                                                 targetWasObservedFrontmost: false,
                                                                 ownPID: 99),
               "App Switcher app-only retries do not steal focus from another app")
        expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: nil,
                                                                 frontmostPID: 30,
                                                                 targetWasObservedFrontmost: false,
                                                                 ownPID: 99),
               "App Switcher app-only retries fail closed without a known source app")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 10,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer when the target app remains active")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 20,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer when the source app is staged behind the target")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 99,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer through its own activation handoff")
        expect(!SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                  sourcePID: 20,
                                                                  activatedPID: 30,
                                                                  ownPID: 99),
               "App Switcher cancels the minimize observer when the user moves to a third app")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 30,
                                                                 ownPID: 99,
                                                                 activatedMatchesTargetBundle: true),
               "App Switcher keeps the minimize observer when a sibling app instance activates")
        let switcherCloseSelected = SwitcherSupport.closeState(afterRemoving: "b",
                                                               itemIDs: ["a", "b", "c"],
                                                               selectedIndex: 1)
        expect(switcherCloseSelected.remainingItemIDs == ["a", "c"]
               && switcherCloseSelected.selectedIndex == 1
               && !switcherCloseSelected.shouldEndSession,
               "App Switcher close selects the next window after closing the selected one")
        let switcherCloseBeforeSelection = SwitcherSupport.closeState(afterRemoving: "a",
                                                                      itemIDs: ["a", "b", "c"],
                                                                      selectedIndex: 2)
        expect(switcherCloseBeforeSelection.remainingItemIDs == ["b", "c"]
               && switcherCloseBeforeSelection.selectedIndex == 1,
               "App Switcher close preserves the same logical selection after removing an earlier window")
        let switcherCloseLast = SwitcherSupport.closeState(afterRemoving: "only",
                                                           itemIDs: ["only"],
                                                           selectedIndex: 0)
        expect(switcherCloseLast.didRemove
               && switcherCloseLast.shouldEndSession
               && switcherCloseLast.remainingItemIDs.isEmpty,
               "App Switcher close ends the session after the last item is removed")
        let switcherCloseMissing = SwitcherSupport.closeState(afterRemoving: "missing",
                                                              itemIDs: ["a", "b"],
                                                              selectedIndex: 1)
        expect(!switcherCloseMissing.didRemove
               && switcherCloseMissing.remainingItemIDs == ["a", "b"]
               && switcherCloseMissing.selectedIndex == 1,
               "App Switcher close leaves selection intact when the item is not present")
        let searchRecords = [
            SwitcherSearchRecord(id: "alpha", title: "Inbox", appName: "Alpha"),
            SwitcherSearchRecord(id: "beta", title: "Vorssaint Roadmap", appName: "Beta"),
            SwitcherSearchRecord(id: "gamma", title: "Café notes", appName: "Gamma"),
        ]
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "") == ["alpha", "beta", "gamma"],
               "App Switcher search keeps all windows for an empty query")
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "beta roadmap") == ["beta"],
               "App Switcher search matches multiple tokens across app name and window title")
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "cafe") == ["gamma"],
               "App Switcher search ignores accents")
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "missing").isEmpty,
               "App Switcher search can return no matches")
        expect(SwitcherSupport.searchSelectionIndex(itemIDs: ["alpha", "beta"],
                                                    preferredID: "beta",
                                                    previousIndex: 0) == 1,
               "App Switcher search preserves the selected item when it remains visible")
        expect(SwitcherSupport.searchSelectionIndex(itemIDs: ["alpha"],
                                                    preferredID: "beta",
                                                    previousIndex: 2) == 0,
               "App Switcher search falls back to a valid selection")
        // MARK: Release notes parsing

        let changelog = """
        # Changelog

        ## [2.17.2] - 2026-06-17

        ### Summary
        This update keeps **Shelf** clear
        and the update window centered.

        ### Fixed
        - **Shelf** no longer shows an extra outline.
        - The update window opens centered
          on the visible screen.

        ### Added
        - Coffee shortcut in the menu panel.
        ![Menu bar temperature metrics](Resources/Images/menu-bar-temperature-metrics.png)

        ### Website
        - Official site: [vorssaint.com](https://vorssaint.com).

        ## [2.17.1] - 2026-06-17

        ### Fixed
        - Older release note.
        """
        let notes = ReleaseNotes.notes(for: "2.17.2", changelog: changelog)
        expect(notes.version == "2.17.2", "release notes version is parsed")
        expect(notes.date == "2026-06-17", "release notes date is parsed")
        expect(notes.sections.count == 3, "release notes keep sections for the requested version")
        expect(notes.sections.first?.title == "Summary", "release notes first section title is parsed")
        expect(notes.sections.first?.paragraphItems.first == "This update keeps Shelf clear and the update window centered.",
               "release notes parse summary paragraphs")
        expect(notes.sections.dropFirst().first?.title == "Fixed", "release notes fixed section title is parsed")
        expect(notes.sections.dropFirst().first?.bulletItems.first == "Shelf no longer shows an extra outline.",
               "release notes strip simple markdown emphasis")
        expect(notes.sections.dropFirst().first?.bulletItems.dropFirst().first == "The update window opens centered on the visible screen.",
               "release notes join continuation lines")
        expect(notes.sections.last?.bulletItems == ["Coffee shortcut in the menu panel."],
               "release notes stop before the next version")
        expect(notes.sections.last?.items.last == .image(ReleaseNoteImage(alt: "Menu bar temperature metrics",
                                                                          path: "Resources/Images/menu-bar-temperature-metrics.png")),
               "release notes parse changelog images")
        expect(!notes.sections.contains(where: { $0.title == "Website" }),
               "release notes hide website sections from the feature list")
        let previewBodyWithoutSummaryHeading = """
        ## [2.17.3]

        A short release summary from the GitHub release body.

        ### Fixed
        - Preview bullet.
        """
        let previewNotes = ReleaseNotes.notes(for: "2.17.3", changelog: previewBodyWithoutSummaryHeading)
        expect(previewNotes.sections.first?.title == "Summary",
               "release notes preserve an unheaded release-body summary paragraph")
        expect(previewNotes.sections.first?.paragraphItems.first == "A short release summary from the GitHub release body.",
               "release notes keep summary text before the first subsection")
        let githubReleaseBodyWithFooter = """
        ### Fixed
        - Update preview stays focused on changes.

        Signed with an Apple Developer ID and notarized by Apple, so it downloads and opens normally. Requires macOS 14 or later. Open the .dmg below and drag Vorssaint to Applications.
        """
        let inAppUpdateBody = ReleaseNotes.inAppUpdateNotes(from: githubReleaseBodyWithFooter) ?? ""
        expect(!inAppUpdateBody.contains("Signed with an Apple Developer ID"),
               "in-app update notes remove the GitHub installation footer")
        let githubPreviewNotes = ReleaseNotes.notes(for: "2.17.4",
                                                    changelog: "## [2.17.4]\n\n" + inAppUpdateBody)
        expect(githubPreviewNotes.sections.first?.bulletItems == ["Update preview stays focused on changes."],
               "in-app update notes keep release changes after removing the footer")

        // MARK: URL cleaning

        expectEqual(URLCleaning.cleanedString(from: "https://example.com/path?utm_source=news&id=42&fbclid=abc") ?? "",
                    "https://example.com/path?id=42",
                    "URL cleaner removes tracking and preserves useful query")
        expectEqual(URLCleaning.cleanedString(from: " https://example.com/?GCLID=one&utm_campaign=x#section ") ?? "",
                    "https://example.com/#section",
                    "URL cleaner is case-insensitive and preserves fragments")
        expectEqual(URLCleaning.cleanedString(from: "https://example.com/?id=42") ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner leaves clean URLs alone")
        expect(URLCleaning.cleanedString(from: "not a url") == nil,
               "URL cleaner rejects plain text")

        // MARK: Homebrew command building and parsing

        expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "Error: Refusing to load formula foo from untrusted tap someone/sometap.\nRun `brew trust someone/sometap` to trust it.")
            == "someone/sometap",
               "untrusted tap name is extracted from Homebrew's refusal")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput: "Error: no such formula") == nil,
               "other Homebrew errors extract no tap")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "from untrusted tap ../evil") == nil,
               "a tap name that fails token validation is rejected")
        let trustCommand = HomebrewCommandBuilder.trustTap(brewPath: "/opt/homebrew/bin/brew", tap: "someone/sometap")
        expect(trustCommand.arguments == ["trust", "--tap", "someone/sometap"],
               "trust command targets the tap explicitly")
        expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "sample-tool",
                                   displayName: "Sample Tool", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        expect(HomebrewCommandBuilder.outdated(brewPath: brewPath).arguments
               == ["outdated", "--json=v2"],
               "Homebrew outdated command uses read-only JSON v2 output")
        expect(HomebrewCommandBuilder.update(brewPath: brewPath).arguments
               == ["update"],
               "Homebrew update command refreshes Homebrew metadata")
        expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "sample-tool"],
               "cask install command uses --cask")
        expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "sample-tool"],
               "cask uninstall command uses --cask")
        expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: cask).arguments
               == ["upgrade", "--cask", "sample-tool"],
               "cask upgrade command uses --cask")
        let formula = HomebrewPackage(kind: .formula, name: "jq",
                                      displayName: "jq", desc: nil,
                                      installedVersion: "1.8.1", stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: formula).arguments
               == ["upgrade", "jq"],
               "formula upgrade command uses separated arguments")
        expect(HomebrewCommandBuilder.upgradeAll(brewPath: brewPath).arguments
               == ["upgrade"],
               "Homebrew update all command upgrades all outdated packages")
        expect(HomebrewOperation.Action.install.runningSystemImage == "arrow.down.circle.fill",
               "Homebrew install status uses a download icon")
        expect(HomebrewOperation.Action.uninstall.runningSystemImage == "trash.circle.fill",
               "Homebrew uninstall status uses a trash icon")
        expect(HomebrewOperation.Action.upgrade.runningSystemImage == "arrow.up.circle.fill",
               "Homebrew package update status uses an update icon")
        expect(HomebrewOperation.Action.updateHomebrew.runningSystemImage == "arrow.triangle.2.circlepath",
               "Homebrew metadata refresh status uses a refresh icon")
        expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
               "Homebrew installer command matches the official install script entrypoint")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/zsh"),
                    "/Users/test/.zprofile",
                    "Homebrew shell setup uses zprofile for zsh")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/bash"),
                    "/Users/test/.bash_profile",
                    "Homebrew shell setup uses bash_profile for bash")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath),
                    #"eval "$(/opt/homebrew/bin/brew shellenv)""#,
                    "Homebrew shell setup line uses brew shellenv")
        expectEqual(HomebrewAnalytics.url(kind: .formula).absoluteString,
                    "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json",
                    "Homebrew formula popularity uses install-on-request analytics")
        expectEqual(HomebrewAnalytics.url(kind: .cask).absoluteString,
                    "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json",
                    "Homebrew cask popularity uses cask install analytics")
        expectEqual(HomebrewAnalytics.compactCount(999), "999", "Homebrew popularity under 1K stays plain")
        expectEqual(HomebrewAnalytics.compactCount(1_250), "1.2K", "Homebrew popularity compacts thousands")
        expectEqual(HomebrewAnalytics.compactCount(1_200_000), "1.2M", "Homebrew popularity compacts millions")
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        expect(shellSetupCommand.contains("PROFILE=/Users/test/.zprofile"),
               "Homebrew shell setup command targets the detected profile")
        expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        expect(HomebrewProgressParser.phase(in: "==> Installing Cask sample-tool",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask sample-tool",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        expect(HomebrewProgressParser.phase(in: "==> Upgrading sample-formula",
                                            action: .upgrade) == .upgrading,
               "Homebrew progress parser detects upgrades")
        expect(HomebrewProgressParser.phase(in: "Already up-to-date.",
                                            action: .updateHomebrew) == .refreshing,
               "Homebrew progress parser detects metadata refresh")
        expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Sample.app'\u{001B}[0m")
               == "Moving App 'Sample.app'",
               "Homebrew progress parser cleans activity lines")
        expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
               == "Error: Cask failed",
               "Homebrew progress parser hides command lines from visible errors")

        let homebrewJSON = """
        {
          "formulae": [
            {
              "name": "sample-formula",
              "full_name": "sample-formula",
              "desc": "Sample formula",
              "homepage": "https://example.com/sample-formula",
              "versions": { "stable": "1.8.1" },
              "installed": [{ "version": "1.8.1" }]
            }
          ],
          "casks": [
            {
              "token": "sample-tool",
              "name": ["Sample Tool"],
              "desc": "Sample cask",
              "homepage": "https://example.com/sample-tool",
              "version": "1.108.1",
              "installed": "1.107.0"
            }
          ]
        }
        """
        let homebrewPackages = (try? HomebrewParser.parseInfoJSON(Data(homebrewJSON.utf8))) ?? []
        expect(homebrewPackages.count == 2, "Homebrew JSON parser keeps formulae and casks")
        expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        expect(homebrewPackages.first(where: { $0.name == "sample-formula" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        expect(homebrewPackages.first(where: { $0.name == "sample-tool" })?.displayName == "Sample Tool",
               "Homebrew parser reads cask display name")
        let cleanCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(homebrewJSON)) ?? []
        expect(cleanCommandPackages.count == 2,
               "Homebrew command output parser keeps clean JSON")
        let noisyHomebrewOutput = """
        Warning: Skipping some beta metadata
        {"notice": "not package data"}
        \(homebrewJSON)
        Warning: A newer Homebrew beta changed an optional field
        """
        let noisyCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(noisyHomebrewOutput)) ?? []
        expect(noisyCommandPackages.count == 2,
               "Homebrew command output parser accepts warnings around JSON")
        expect(noisyCommandPackages.first(where: { $0.name == "sample-tool" })?.installedVersion == "1.107.0",
               "Homebrew command output parser keeps package data from noisy output")
        expect((try? HomebrewParser.parseInfoCommandOutput("Warning: no JSON here")) == nil,
               "Homebrew command output parser rejects output without valid JSON")
        let outdatedJSON = """
        {
          "formulae": [
            {
              "name": "fmt",
              "installed_versions": ["12.1.0"],
              "current_version": "12.2.0",
              "pinned": false
            }
          ],
          "casks": [
            {
              "name": "sample-tool",
              "installed_versions": ["1.107.0"],
              "current_version": "1.108.1",
              "pinned": true
            }
          ]
        }
        """
        let outdatedPackages = (try? HomebrewParser.parseOutdatedJSON(Data(outdatedJSON.utf8))) ?? [:]
        expect(outdatedPackages.count == 2,
               "Homebrew outdated parser keeps formulae and casks")
        expect(outdatedPackages["formula:fmt"]?.versionSummary == "12.1.0 -> 12.2.0",
               "Homebrew outdated parser renders installed to current version")
        expect(outdatedPackages["cask:sample-tool"]?.isPinned == true,
               "Homebrew outdated parser reads pinned status")
        let noisyOutdatedOutput = """
        Warning: Homebrew updated metadata
        {"notice": "not outdated data"}
        \(outdatedJSON)
        """
        let noisyOutdatedPackages = (try? HomebrewParser.parseOutdatedCommandOutput(noisyOutdatedOutput)) ?? [:]
        expect(noisyOutdatedPackages["formula:fmt"]?.currentVersion == "12.2.0",
               "Homebrew outdated command output parser accepts warnings around JSON")
        let orderingPackages = [
            HomebrewPackage(kind: .cask, name: "alpha-tool", displayName: "Alpha Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil),
            HomebrewPackage(kind: .cask, name: "beta-tool", displayName: "Beta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .cask, name: "beta-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "gamma-tool", displayName: "Gamma Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .formula, name: "gamma-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "delta-tool", displayName: "Delta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil)
        ]
        expect(HomebrewPackageOrdering.updatesFirst(orderingPackages).map(\.name)
               == ["beta-tool", "gamma-tool", "alpha-tool", "delta-tool"],
               "Homebrew installed packages keep all pending updates first without reordering either group")
        let searchPackages = HomebrewParser.parseSearchOutput("sample-formula\nbad token\nsample-filter\nsample-tool\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        expect(searchPackages.map(\.name) == ["sample-formula", "sample-filter", "sample-tool"],
               "Homebrew search parser keeps valid one-token results")
        let analyticsJSON = """
        {
          "category": "formula_install_on_request",
          "formulae": {
            "sample-formula": [
              { "formula": "sample-formula", "count": "21,557" },
              { "formula": "sample-formula --HEAD", "count": "30" }
            ],
            "sample-filter": [
              { "formula": "sample-filter", "count": "42,001" }
            ]
          }
        }
        """
        let popularity = (try? HomebrewAnalytics.parse(Data(analyticsJSON.utf8), kind: .formula)) ?? [:]
        expect(popularity["sample-formula"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        expect(popularity["sample-filter"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        expect(rankedPackages.map(\.name) == ["sample-filter", "sample-formula", "sample-tool"],
               "Homebrew search results sort by popularity first")
        expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")

        // MARK: Localization format contracts

        let localizedStrings: [(AppLanguage, Strings)] = [
            (.enUS, .enUS),
            (.ptBR, .ptBR),
            (.tr, .tr),
            (.ru, .ru),
            (.es, .es),
            (.de, .de),
            (.fr, .fr),
            (.it, .it),
            (.ja, .ja),
            (.ko, .ko),
            (.zhHans, .zhHans),
            (.zhTW, .zhTW),
            (.zhHK, .zhHK)
        ]
        expect(localizedStrings.count == AppLanguage.allCases.count, "all app languages are covered by tests")
        for (language, strings) in localizedStrings {
            let prefix = "localization \(language.rawValue)"
            expectFormat(strings.cutMovedPluralFormat, ["d"], "\(prefix) cut plural format")
            expectFormat(strings.uninstallerSelectedFormat, ["d", "d"], "\(prefix) uninstaller selected format")
            expectFormat(strings.uninstallerFreedFormat, ["@"], "\(prefix) uninstaller freed format")
            expectFormat(strings.shelfSelectedFormat, ["d"], "\(prefix) shelf selection format")
            expectFormat(strings.powerAdapterMaxFormat, ["@"], "\(prefix) adapter max format")
            expectFormat(strings.mixerInputErrorFormat, ["@"], "\(prefix) mixer input error format")
            expectFormat(strings.homebrewConfirmInstallBodyFormat, ["@"], "\(prefix) Homebrew install format")
            expectFormat(strings.homebrewConfirmUninstallBodyFormat, ["@"], "\(prefix) Homebrew uninstall format")
            expectFormat(strings.homebrewConfirmUpgradeBodyFormat, ["@"], "\(prefix) Homebrew upgrade format")
            expect(!strings.homebrewUpgradeAll.isEmpty, "\(prefix) Homebrew update all title is present")
            expect(!strings.homebrewUpdateHomebrew.isEmpty, "\(prefix) Homebrew update Homebrew title is present")
            expect(!strings.switcherIconRowMode.isEmpty, "\(prefix) App Switcher icon-row title is present")
            expect(!strings.switcherIconRowModeCaption.isEmpty, "\(prefix) App Switcher icon-row caption is present")
            expect(!strings.switcherSimpleMode.isEmpty, "\(prefix) App Switcher simple-mode title is present")
            expect(!strings.switcherSimpleModeCaption.isEmpty, "\(prefix) App Switcher simple-mode caption is present")
            expect(!strings.switcherShortcutHintApps.isEmpty, "\(prefix) App Switcher app shortcut hint is present")
            expect(!strings.switcherShortcutHintWindows.isEmpty, "\(prefix) App Switcher window shortcut hint is present")
            expect(!strings.networkApps.isEmpty, "\(prefix) network app usage title is present")
            expect(!strings.networkAppsIdle.isEmpty, "\(prefix) network app idle text is present")
            expect(!strings.launchAtLoginNeedsApplications.isEmpty
                   && !strings.launchAtLoginNeedsApplications.contains("—"),
                   "\(prefix) launch at login location note is present without em dash")
            let ocrQRStrings = [strings.ocrQRToggle, strings.ocrQRCaption, strings.ocrQRCopied,
                                strings.qrResultTitle, strings.qrResultCopy, strings.qrResultOpen]
            expect(ocrQRStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) screen QR strings are present without em dash")
            let highlightsStrings = [strings.highlightsTitle, strings.highlightsCaptionDockPreview,
                                     strings.highlightsCaptionScreenshot, strings.highlightsConfigure,
                                     strings.highlightsTry, strings.highlightsSeeAll]
            expect(highlightsStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) update highlights strings are present without em dash")
            let officialHomebrewIntroStrings = [
                strings.homebrewOfficialIntroTitle,
                strings.homebrewOfficialIntroMessage,
                strings.homebrewOfficialIntroInstallLabel,
                strings.homebrewOfficialIntroMigrationTitle,
                strings.homebrewOfficialIntroMigrationMessage,
                strings.homebrewOfficialIntroCopyButton,
                strings.supportIntroDoneButton,
            ]
            expect(officialHomebrewIntroStrings.allSatisfy { !$0.isEmpty },
                   "\(prefix) official Homebrew intro is complete")
            expect(officialHomebrewIntroStrings.allSatisfy { !$0.contains("—") },
                   "\(prefix) official Homebrew intro has no em dash")
            expect(!strings.communityIntroMessage.isEmpty
                   && strings.communityIntroMessage.contains("X"),
                   "\(prefix) community intro invites users to follow previews on X")
            let retiredWeeklyPhrases = [
                "uma vez por semana", "once a week", "haftada bir", "раз в неделю",
                "una vez por semana", "einmal pro Woche", "une fois par semaine",
                "una volta a settimana", "週1回", "매주 한 번", "每周更新一次", "每週更新一次",
            ]
            expect(retiredWeeklyPhrases.allSatisfy {
                !strings.communityIntroMessage.localizedCaseInsensitiveContains($0)
            }, "\(prefix) community intro no longer promises weekly updates")
            expect(!strings.communityIntroMessage.contains("—")
                   && strings.communityIntroMessage.count <= 320,
                   "\(prefix) community intro stays concise and has no em dash")
            expect(!strings.updateShowcaseTitle.isEmpty, "\(prefix) update showcase title is present")
            expect(!strings.updateShowcaseMessage.isEmpty, "\(prefix) update showcase message is present")
            expect(!strings.updateShowcaseUnavailable.isEmpty, "\(prefix) update showcase fallback is present")
            expect(!strings.updateShowcaseRestart.isEmpty, "\(prefix) update showcase restart control is present")
            expect(!strings.homebrewConfirmUpgradeAllTitle.isEmpty, "\(prefix) Homebrew update all confirmation title is present")
            expect(!strings.homebrewConfirmUpgradeAllBody.isEmpty, "\(prefix) Homebrew update all confirmation body is present")
            expect(!strings.homebrewConfirmUpdateHomebrewTitle.isEmpty, "\(prefix) Homebrew update Homebrew confirmation title is present")
            expect(!strings.homebrewConfirmUpdateHomebrewBody.isEmpty, "\(prefix) Homebrew update Homebrew confirmation body is present")
            expectFormat(strings.homebrewPopularityFormat, ["@", "@"], "\(prefix) Homebrew popularity format")
            expectFormat(strings.homebrewOperationInstallFormat, ["@"], "\(prefix) Homebrew operation install format")
            expectFormat(strings.homebrewOperationUninstallFormat, ["@"], "\(prefix) Homebrew operation uninstall format")
            expectFormat(strings.homebrewOperationUpgradeFormat, ["@"], "\(prefix) Homebrew operation upgrade format")
            expect(!strings.homebrewOperationUpgradeAll.isEmpty, "\(prefix) Homebrew operation update all is present")
            expect(!strings.homebrewOperationUpdateHomebrew.isEmpty, "\(prefix) Homebrew operation update Homebrew is present")
            expectFormat(strings.homebrewOperationInstalledFormat, ["@"], "\(prefix) Homebrew operation installed format")
            expectFormat(strings.homebrewOperationUninstalledFormat, ["@"], "\(prefix) Homebrew operation uninstalled format")
            expectFormat(strings.homebrewOperationUpgradedFormat, ["@"], "\(prefix) Homebrew operation upgraded format")
            expect(!strings.homebrewOperationUpgradedAll.isEmpty, "\(prefix) Homebrew operation updated all is present")
            expect(!strings.homebrewOperationUpdatedHomebrew.isEmpty, "\(prefix) Homebrew operation updated Homebrew is present")
            expectFormat(strings.homebrewOperationFailedFormat, ["@"], "\(prefix) Homebrew operation failed format")
            expectFormat(strings.homebrewOperationElapsedFormat, ["@"], "\(prefix) Homebrew operation elapsed format")

            let rendered = [
                String(format: strings.cutMovedPluralFormat, 2),
                String(format: strings.uninstallerSelectedFormat, 1, 3),
                String(format: strings.uninstallerFreedFormat, "1 MB"),
                String(format: strings.shelfSelectedFormat, 2),
                String(format: strings.powerAdapterMaxFormat, "30 W"),
                String(format: strings.mixerInputErrorFormat, "OSStatus -1"),
                String(format: strings.homebrewConfirmInstallBodyFormat, "jq"),
                String(format: strings.homebrewConfirmUninstallBodyFormat, "jq"),
                String(format: strings.homebrewPopularityFormat, "1,234", "30"),
                String(format: strings.homebrewOperationInstallFormat, "jq"),
                String(format: strings.homebrewOperationUninstallFormat, "jq"),
                String(format: strings.homebrewOperationInstalledFormat, "jq"),
                String(format: strings.homebrewOperationUninstalledFormat, "jq"),
                String(format: strings.homebrewOperationFailedFormat, "jq"),
                String(format: strings.homebrewOperationElapsedFormat, "10s"),
            ]
            for value in rendered {
                expect(!value.isEmpty && !value.contains("%"), "\(prefix) renders format strings")
            }
        }
        let infoPlist = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        let bundleLocalizations = infoPlist?["CFBundleLocalizations"] as? [String] ?? []
        expect(bundleLocalizations.contains("tr"), "Info.plist declares Turkish as a bundle localization")
        expect(bundleLocalizations.contains("ko"), "Info.plist declares Korean as a bundle localization")
        let baseAudioPrompt = infoPlist?["NSAudioCaptureUsageDescription"] as? String ?? ""
        expect(baseAudioPrompt.contains("Vorssaint taps individual app audio"),
               "base audio permission prompt is an English fallback")
        let turkishInfoPlistStrings = (try? String(contentsOfFile: "Resources/tr.lproj/InfoPlist.strings",
                                                   encoding: .utf8)) ?? ""
        expect(turkishInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && turkishInfoPlistStrings.contains("Hiçbir şey kaydedilmez"),
               "Turkish InfoPlist.strings localizes the audio permission prompt")
        let koreanInfoPlistStrings = (try? String(contentsOfFile: "Resources/ko.lproj/InfoPlist.strings",
                                                  encoding: .utf8)) ?? ""
        expect(koreanInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && koreanInfoPlistStrings.contains("어떤 오디오도 녹음되거나"),
               "Korean InfoPlist.strings localizes the audio permission prompt")

        // MARK: Network speed math

        let slow = NetworkCounters(received: 1000, sent: 500)
        let fast = NetworkCounters(received: 1000 + 2048, sent: 500 + 1024)
        let speed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 2)
        expectClose(speed.down, 1024, "down speed over 2s")
        expectClose(speed.up, 512, "up speed over 2s")

        let zeroElapsed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 0)
        expect(zeroElapsed.down == 0 && zeroElapsed.up == 0, "zero elapsed yields zero")

        // Counter reset (interface went down) must not produce a negative/huge spike.
        let afterReset = MetricFormat.netSpeed(previous: fast, current: slow, elapsed: 2)
        expect(afterReset.down == 0 && afterReset.up == 0, "counter reset yields zero")

        let nettopCSV = """
        time,,bytes_in,bytes_out,
        08:31:45.865507,Codex (Service).78844,78288,477660,
        08:31:45.865507,codex.78880,3154372,13193590,
        time,,bytes_in,bytes_out,
        08:31:46.871245,Codex (Service).78844,416,98,
        08:31:46.871246,codex.78880,16245,20641,
        08:31:46.871247,launchd.1,0,0,
        """
        let nettopRows = NetworkProcessSupport.parseNettopCSV(nettopCSV)
        expect(nettopRows.count == 2,
               "nettop parser keeps only active rows from the final delta section")
        expect(nettopRows.first?.name == "Codex (Service)" && nettopRows.first?.pid == 78844,
               "nettop parser extracts process names containing spaces")
        expectClose(nettopRows.last?.bytesIn ?? -1, 16_245, "nettop parser reads numeric bytes in")
        expectClose(nettopRows.last?.bytesOut ?? -1, 20_641, "nettop parser reads numeric bytes out")

        var nettopStream = NetworkProcessDeltaStreamParser()
        let streamLines = [
            "time,,bytes_in,bytes_out,",
            "08:31:45.865507,Codex.78844,78288,477660,",
            "time,,bytes_in,bytes_out,",
            "08:31:46.871245,Codex.78844,416,98,",
            "08:31:46.871247,launchd.1,0,0,",
            "time,,bytes_in,bytes_out,",
        ]
        let streamedSections = streamLines.compactMap { nettopStream.consumeCSVLine($0) }
        expect(streamedSections.count == 1,
               "nettop stream parser skips the initial cumulative section")
        expect(streamedSections.first?.count == 1,
               "nettop stream parser emits only active rows from the first delta section")
        expectClose(streamedSections.first?.first?.bytesIn ?? -1, 416,
                    "nettop stream parser does not publish cumulative bytes")
        expect(NetworkProcessSupport.nettopArguments == ["-P", "-d", "-x", "-J", "bytes_in,bytes_out", "-L", "1", "-s", "1"],
               "nettop per-app sampling asks for one cumulative section and computes deltas in app")

        var networkDelta = NetworkProcessDeltaTracker(maxGap: 10)
        let baselineNetwork = [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 1_000, bytesOut: 500),
            NetworkProcessSample(pid: 20, name: "Editor", bytesIn: 200, bytesOut: 300),
        ]
        expect(networkDelta.rates(from: baselineNetwork, now: 100).isEmpty,
               "network process delta primes the first cumulative sample")
        let rateNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 3_048, bytesOut: 1_524),
            NetworkProcessSample(pid: 20, name: "Editor", bytesIn: 200, bytesOut: 300),
        ], now: 102)
        expect(rateNetwork.count == 1 && rateNetwork.first?.pid == 10,
               "network process delta keeps only processes with traffic")
        expectClose(rateNetwork.first?.bytesIn ?? -1, 1_024,
                    "network process delta computes download bytes per second")
        expectClose(rateNetwork.first?.bytesOut ?? -1, 512,
                    "network process delta computes upload bytes per second")
        let resetNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 100, bytesOut: 50),
        ], now: 104)
        expect(resetNetwork.isEmpty,
               "network process delta treats counter resets as a fresh baseline")
        let staleNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 10_000, bytesOut: 10_000),
        ], now: 120)
        expect(staleNetwork.isEmpty,
               "network process delta treats long gaps as a fresh baseline")
        let renewedLease = NetworkProcessSamplingPolicy.renewedLease(now: 50)
        expect(NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: renewedLease, now: 61.9),
               "network monitoring lease remains active before expiry")
        expect(!NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: renewedLease, now: 62.0),
               "network monitoring lease expires exactly at the boundary")
        expectClose(NetworkProcessSamplingPolicy.shortenedLease(currentExpiresAt: 90, now: 50),
                    54,
                    "network monitoring stop shortens the lease instead of depending on balanced disappear events")

        expect(MonitorSamplingPolicy.sampleStride(for: .cpu, intervalSeconds: 2, foreground: false) == 1,
               "monitor CPU stays responsive in menu-bar-only mode")
        expect(MonitorSamplingPolicy.sampleStride(for: .disk, intervalSeconds: 2, foreground: false) == 5,
               "monitor disk sampling slows down in menu-bar-only mode without exceeding DiskSampler.maxGap")
        expect(MonitorSamplingPolicy.sampleStride(for: .peripheralBattery, intervalSeconds: 2, foreground: false) == 30,
               "monitor peripheral battery sampling is heavily throttled in menu-bar-only mode")
        expect(MonitorSamplingPolicy.sampleStride(for: .disk, intervalSeconds: 2, foreground: true) == 1,
               "monitor disk sampling stays live while the panel is open")
        expect(MonitorSamplingPolicy.shouldSample(.disk, tick: 4, intervalSeconds: 2, foreground: false) == false,
               "monitor skips heavy menu-bar-only ticks before the stride")
        expect(MonitorSamplingPolicy.shouldSample(.disk, tick: 5, intervalSeconds: 2, foreground: false),
               "monitor samples heavy menu-bar-only ticks at the stride")

        expect(MonitorSamplingPolicy.wakeTicks(for: [.cpu, .disk], intervalSeconds: 2, foreground: false) == 1,
               "monitor wakes every tick while an every-tick metric is on")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.temperature], intervalSeconds: 2, foreground: false) == 8,
               "monitor with only temperature wakes once per temperature stride")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.peripheralBattery], intervalSeconds: 2, foreground: false) == 30,
               "monitor with only peripheral battery wakes once per minute")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.disk, .peripheralBattery], intervalSeconds: 2, foreground: false) == 5,
               "monitor wake cadence is the GCD of the needed strides")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.temperature], intervalSeconds: 2, foreground: true) == 1,
               "monitor wakes every tick in the foreground")
        expect(MonitorSamplingPolicy.wakeTicks(for: [], intervalSeconds: 2, foreground: false) == 1,
               "monitor wake cadence defaults to every tick with no needs")
        // Exactness invariant: the cadence always divides every needed stride,
        // so grid-aligned ticks keep hitting each stride exactly on schedule.
        let wakeKinds: [MonitorSamplingKind] = [.disk, .power, .gpuUsage, .temperature, .peripheralBattery]
        let cadence = MonitorSamplingPolicy.wakeTicks(for: wakeKinds, intervalSeconds: 2, foreground: false)
        expect(wakeKinds.allSatisfy {
            MonitorSamplingPolicy.sampleStride(for: $0, intervalSeconds: 2, foreground: false) % cadence == 0
        }, "monitor wake cadence divides every needed stride")
        expect(MonitorSamplingPolicy.alignedTick(16, wakeTicks: 8) == 16,
               "monitor tick already on the wake grid stays put")
        expect(MonitorSamplingPolicy.alignedTick(7, wakeTicks: 8) == 8,
               "monitor tick off the wake grid realigns to the next slot")
        expect(MonitorSamplingPolicy.alignedTick(9, wakeTicks: 1) == 9,
               "monitor tick needs no alignment at every-tick cadence")

        // MARK: Interface filtering

        expect(MetricFormat.includeNetworkInterface("en0"), "en0 included")
        expect(MetricFormat.includeNetworkInterface("en12"), "en12 included")
        expect(!MetricFormat.includeNetworkInterface("lo0"), "lo0 excluded")
        expect(!MetricFormat.includeNetworkInterface("awdl0"), "awdl0 excluded")
        expect(!MetricFormat.includeNetworkInterface("nan0"), "nan0 excluded")
        expect(!MetricFormat.includeNetworkInterface("utun3"), "utun3 (VPN) excluded")
        expect(!MetricFormat.includeNetworkInterface("bridge0"), "bridge0 excluded")
        expect(!MetricFormat.includeNetworkInterface(""), "empty excluded")

        // MARK: History ring buffer

        var history = MetricHistory(capacity: 3)
        history.push(1)
        history.push(2)
        expect(history.values == [1, 2], "history keeps order under capacity")
        history.push(3)
        history.push(4)
        expect(history.values == [2, 3, 4], "history drops oldest at capacity")
        expect(history.values.count == 3, "history never exceeds capacity")

        var single = MetricHistory(capacity: 1)
        single.push(5)
        single.push(6)
        expect(single.values == [6], "capacity 1 keeps only newest")

        // MARK: Cleaning-mode unlock gesture

        // Five deliberate taps of the same key unlock, on the fifth.
        var taps = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        var tapUnlock = false
        for (i, t) in [0.0, 0.3, 0.6, 0.9, 1.2].enumerated() {
            tapUnlock = taps.registerKeyDown(code: 0, time: t, isRepeat: false)
            if i < 4 { expect(!tapUnlock, "no unlock before the fifth tap (\(i + 1))") }
        }
        expect(tapUnlock, "five same-key taps unlock")
        expect(taps.progress == 5, "progress reaches the threshold")

        // Wiping the keyboard hits many different keys: it must never unlock.
        var wipe = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        var wipeUnlock = false
        for (i, code) in [Int64(10), 11, 12, 13, 14, 15, 16, 17].enumerated() {
            if wipe.registerKeyDown(code: code, time: Double(i) * 0.1, isRepeat: false) { wipeUnlock = true }
        }
        expect(!wipeUnlock, "wiping different keys never unlocks")
        expect(wipe.progress == 1, "different keys keep progress at 1")

        // A different key mid-streak resets the count.
        var streak = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        _ = streak.registerKeyDown(code: 9, time: 0.0, isRepeat: false)
        _ = streak.registerKeyDown(code: 9, time: 0.2, isRepeat: false)
        _ = streak.registerKeyDown(code: 9, time: 0.4, isRepeat: false)
        _ = streak.registerKeyDown(code: 8, time: 0.6, isRepeat: false)
        expect(streak.progress == 1, "a different key mid-streak resets to 1")

        // Auto-repeat (holding a key) is ignored, so resting on a key can't unlock.
        var held = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        var heldUnlock = false
        for i in 0..<10 {
            if held.registerKeyDown(code: 7, time: Double(i) * 0.1, isRepeat: true) { heldUnlock = true }
        }
        expect(!heldUnlock, "auto-repeat never unlocks")
        expect(held.progress == 0, "auto-repeat does not advance progress")

        // A pause longer than the window restarts the count.
        var paused = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        _ = paused.registerKeyDown(code: 3, time: 0.0, isRepeat: false)
        _ = paused.registerKeyDown(code: 3, time: 0.5, isRepeat: false)
        expect(paused.progress == 2, "presses within the window accumulate")
        _ = paused.registerKeyDown(code: 3, time: 10.0, isRepeat: false)
        expect(paused.progress == 1, "a pause beyond the window restarts the count")

        // reset() clears everything.
        var cleared = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        _ = cleared.registerKeyDown(code: 1, time: 0.0, isRepeat: false)
        _ = cleared.registerKeyDown(code: 1, time: 0.2, isRepeat: false)
        expect(cleared.progress == 2, "progress accumulates before reset")
        cleared.reset()
        expect(cleared.progress == 0, "reset clears progress")
        let afterReset2 = cleared.registerKeyDown(code: 1, time: 0.4, isRepeat: false)
        expect(!afterReset2 && cleared.progress == 1, "after reset the same key starts fresh at 1")

        func systemKeyData(keyCode: Int, state: Int, repeatFlag: Bool = false) -> Int {
            Int((UInt32(keyCode) << 16) | (UInt32(state) << 8) | (repeatFlag ? 1 : 0))
        }

        let brightnessDown = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 3, state: CleaningSystemKeyEvent.keyDownState)
        )
        expect(brightnessDown?.isKeyDown == true && brightnessDown?.isRepeat == false,
               "brightness key down is decoded from system-defined events")

        let volumeUpRepeat = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 0, state: CleaningSystemKeyEvent.keyDownState, repeatFlag: true)
        )
        expect(volumeUpRepeat?.isKeyDown == true && volumeUpRepeat?.isRepeat == true,
               "system-defined auto-repeat is preserved")

        let mediaNextUp = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 17, state: CleaningSystemKeyEvent.keyUpState)
        )
        expect(mediaNextUp?.isKeyDown == false,
               "system-defined key up is decoded without advancing unlock")

        let powerKey = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.powerKeySubtype,
            data1: 0
        )
        expect(powerKey?.isKeyDown == true && powerKey?.isRepeat == false,
               "power and lock key system events are recognized")

        let unrelatedSystemEvent = CleaningSystemKeyEvent.decode(subtype: 99, data1: 0)
        expect(unrelatedSystemEvent == nil, "unrelated system-defined events do not count as unlock keys")

        // MARK: Features hub catalog

        expect(AppFeature.allCases.count == 43, "feature catalog has 43 features")
        expect(Set(AppFeature.allCases.map(\.rawValue)).count == AppFeature.allCases.count,
               "feature ids are unique")
        expect(AppFeature.allCases.map(\.rawValue) == [
            "switcher", "dockPreview", "dockClick", "windowMaximizer", "windowLayout", "autoQuit",
            "scrollInverter", "smoothScroll", "mouseNavigation", "middleClick", "keyboardDebounce",
            "textSnippets",
            "clipboardHistory", "pastePlain", "finderCutPaste", "shelf", "urlCleaner",
            "mixer", "soundOutputSwitcher", "micMute", "musicBlock",
            "keepAwake", "brightness", "extraBrightness",
            "quickLauncher", "quickToggles", "colorPicker", "screenOCR", "cleaningMode", "mediaTools",
            "cleaner", "uninstaller", "homebrew", "screenshot", "cameraPreview", "radialMenu",
            "scratchpad",
            "monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk", "monitorPower",
        ], "feature ids are stable (they persist inside availability keys)")
        expect(AppFeature.switcher.availabilityKey == "featureAvailable.switcher",
               "availability key derives from the raw value")
        expect(AppFeature.availabilityDefaults.count == AppFeature.allCases.count
                && AppFeature.availabilityDefaults.values.allSatisfy { ($0 as? Bool) == true },
               "every feature registers as available by default")
        expect(FeatureGroup.allCases.map { AppFeature.features(in: $0).count }.reduce(0, +)
                == AppFeature.allCases.count,
               "every feature belongs to exactly one group")
        expect(!FeatureGroup.allCases.contains { AppFeature.features(in: $0).isEmpty },
               "no hub group is empty")

        func activeSet(_ permission: AppPermission,
                       available: Set<AppFeature> = Set(AppFeature.allCases),
                       on: Set<String> = [],
                       strings: [String: String] = [:]) -> Set<AppFeature> {
            Set(AppFeature.activeFeatures(using: permission,
                                          isAvailable: { available.contains($0) },
                                          boolFor: { on.contains($0) },
                                          stringFor: { strings[$0] }))
        }

        expect(activeSet(.accessibility) == [.windowLayout, .cleaningMode],
               "with nothing enabled only on-demand features use accessibility")
        expect(activeSet(.accessibility, on: [DefaultsKey.scrollInverterEnabled]).contains(.scrollInverter),
               "an enabled feature counts as using its permission")
        expect(!activeSet(.accessibility, available: [], on: [DefaultsKey.scrollInverterEnabled])
                .contains(.scrollInverter),
               "an unavailable feature never uses a permission")
        expect(activeSet(.accessibility, on: [DefaultsKey.keepAwakeMouseJiggleEnabled]).contains(.keepAwake),
               "keep awake uses accessibility only with the mouse jiggle on")
        expect(!activeSet(.accessibility).contains(.keepAwake),
               "keep awake without jiggle does not use accessibility")
        expect(activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled,
                                              DefaultsKey.brightnessKeysEnabled]).contains(.brightness),
               "brightness uses accessibility only for the key option")
        expect(activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled,
                                              DefaultsKey.brightnessOSDEnabled]).contains(.brightness),
               "brightness uses accessibility for the adjustment overlay")
        expect(!activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled])
                .contains(.brightness),
               "brightness sliders alone never use accessibility")

        expect(activeSet(.screenRecording, on: [DefaultsKey.switcherEnabled])
                == [.switcher, .screenOCR, .screenshot],
               "switcher with previews uses screen recording; OCR and screenshots are on demand")
        expect(activeSet(.screenRecording,
                         on: [DefaultsKey.switcherEnabled, DefaultsKey.switcherSimpleMode])
                == [.screenOCR, .screenshot],
               "simple-mode switcher stops using screen recording")
        expect(activeSet(.screenRecording,
                         on: [DefaultsKey.switcherSimpleMode, DefaultsKey.dockPreviewEnabled])
                .contains(.dockPreview),
               "dock preview keeps screen recording in use regardless of switcher mode")

        expect(activeSet(.notifications) == [],
               "no alerts and no schedule means notifications are unused")
        expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertCPUTemperature]) == [.monitorCPU],
               "a CPU temperature alert marks the CPU monitor as notifying")
        expect(activeSet(.notifications,
                         available: Set(AppFeature.allCases).subtracting([.monitorCPU]),
                         on: [DefaultsKey.monitorAlertCPU]) == [],
               "an alert whose metric is unavailable does not notify")
        expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "weekly"]) == [.cleaner],
               "a scheduled cleaner with notice enabled uses notifications")
        expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "off"]) == [],
               "an unscheduled cleaner does not use notifications")

        expect(activeSet(.fullDiskAccess) == [.cleaner, .uninstaller],
               "cleaner and uninstaller are on-demand full disk users")
        expect(activeSet(.automationFinder, on: [DefaultsKey.finderCutPasteEnabled])
                == [.finderCutPaste, .uninstaller, .quickToggles],
               "finder automation is used by cut and paste, the uninstaller and the quick toggles")
        expect(AppFeature.quickToggles.permissions == [.automationFinder],
               "the quick toggles need no permission beyond the Trash's Finder ask")
        expect(activeSet(.automationTerminal) == [.homebrew], "homebrew drives the Terminal")
        expect(activeSet(.audioCapture) == [.mixer], "the mixer is the only audio capture user")
        expect(activeSet(.audioCapture, available: Set(AppFeature.allCases).subtracting([.mixer])) == [],
               "audio capture reads as unused once the mixer is off in the hub")
        expect(activeSet(.camera) == [.cameraPreview],
               "the camera preview is the only on-demand camera user")
        expect(activeSet(.camera, available: Set(AppFeature.allCases).subtracting([.cameraPreview])) == [],
               "the camera reads as unused once the preview is off in the hub")
        expect(AppFeature.cameraPreview.permissions == [.camera]
                && AppFeature.cameraPreview.enabledKeys.isEmpty,
               "the camera preview works on demand and only ever asks for the camera")

        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true }, boolFor: { _ in false }),
               "no alert keys means no monitor alerts")
        expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "one alert on an available metric arms the alert service")
        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorDisk },
                                                  boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "an alert with its metric off in the hub stays disarmed")

        expect(GlobalShortcutRole.activeRoles(isOn: { _ in true }).count == GlobalShortcutRole.allCases.count,
               "the availability-free overload keeps every enabled role")
        expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                               isAvailable: { $0 != .shelf }).contains(.shelf),
               "a role leaves the shortcuts page when its feature is off in the hub")
        expect(GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                              isAvailable: { $0 != .switcher })
                .allSatisfy { $0 != .switcher && $0 != .switcherWindow },
               "both switcher roles follow the switcher feature")

        // MARK: Features hub strings

        for language in AppLanguage.allCases {
            let hub = FeatureStrings.hub(language)
            let values = Mirror(reflecting: hub).children.compactMap { $0.value as? String }
            expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty },
                   "every hub string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible hub strings (\(language.rawValue))")
            expect(hub.activeCountFormat.contains("%1$d") && hub.activeCountFormat.contains("%2$d"),
                   "count format keeps positional specifiers (\(language.rawValue))")
        }
        expect(FeatureStrings.hub(.ptBR).pageTitle == "Recursos"
                && FeatureStrings.hub(.enUS).pageTitle == "Features",
               "hub page title reads naturally in the owner languages")
        for language in AppLanguage.allCases {
            let snippetValues = Mirror(reflecting: FeatureStrings.snippets(language)).children
                .compactMap { $0.value as? String }
            expect(!snippetValues.isEmpty && snippetValues.allSatisfy { !$0.isEmpty },
                   "every snippet string is set for \(language.rawValue)")
            expect(snippetValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible snippet strings (\(language.rawValue))")
            let backupValues = Mirror(reflecting: FeatureStrings.backup(language)).children
                .compactMap { $0.value as? String }
            expect(!backupValues.isEmpty && backupValues.allSatisfy { !$0.isEmpty },
                   "every backup string is set for \(language.rawValue)")
            expect(backupValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible backup strings (\(language.rawValue))")
            let guideValues = Mirror(reflecting: FeatureStrings.permissionGuide(language)).children
                .compactMap { $0.value as? String }
            expect(!guideValues.isEmpty && guideValues.allSatisfy { !$0.isEmpty },
                   "every permission guide string is set for \(language.rawValue)")
            expect(guideValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in permission guide strings (\(language.rawValue))")
            let brightnessValues = Mirror(reflecting: FeatureStrings.brightness(language)).children
                .compactMap { $0.value as? String }
            expect(!brightnessValues.isEmpty && brightnessValues.allSatisfy { !$0.isEmpty },
                   "every brightness string is set for \(language.rawValue)")
            expect(brightnessValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible brightness strings (\(language.rawValue))")
            let quickToggleValues = Mirror(reflecting: FeatureStrings.quickToggles(language)).children
                .compactMap { $0.value as? String }
            expect(!quickToggleValues.isEmpty && quickToggleValues.allSatisfy { !$0.isEmpty },
                   "every quick toggle string is set for \(language.rawValue)")
            expect(quickToggleValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible quick toggle strings (\(language.rawValue))")
            let keepAwakeAutomationValues = Mirror(
                reflecting: FeatureStrings.keepAwakeAutomation(language)
            ).children.compactMap { $0.value as? String }
            expect(!keepAwakeAutomationValues.isEmpty
                    && keepAwakeAutomationValues.allSatisfy { !$0.isEmpty },
                   "every Keep Awake automation string is set for \(language.rawValue)")
            expect(keepAwakeAutomationValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in Keep Awake automation strings (\(language.rawValue))")
            let batteryTimeValues = Mirror(reflecting: FeatureStrings.batteryTime(language)).children
                .compactMap { $0.value as? String }
            expect(!batteryTimeValues.isEmpty && batteryTimeValues.allSatisfy { !$0.isEmpty },
                   "every battery time string is set for \(language.rawValue)")
            expect(batteryTimeValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible battery time strings (\(language.rawValue))")
            let menuBarAppearanceValues = Mirror(reflecting: FeatureStrings.menuBarAppearance(language)).children
                .compactMap { $0.value as? String }
            expect(!menuBarAppearanceValues.isEmpty && menuBarAppearanceValues.allSatisfy { !$0.isEmpty },
                   "every menu bar appearance string is set for \(language.rawValue)")
            expect(menuBarAppearanceValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible menu bar appearance strings (\(language.rawValue))")
            let screenshotValues = Mirror(reflecting: FeatureStrings.screenshot(language)).children
                .compactMap { $0.value as? String }
            expect(!screenshotValues.isEmpty && screenshotValues.allSatisfy { !$0.isEmpty },
                   "every screenshot string is set for \(language.rawValue)")
            expect(screenshotValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible screenshot strings (\(language.rawValue))")
            let cameraPreviewValues = Mirror(reflecting: FeatureStrings.cameraPreview(language)).children
                .compactMap { $0.value as? String }
            expect(!cameraPreviewValues.isEmpty && cameraPreviewValues.allSatisfy { !$0.isEmpty },
                   "every camera preview string is set for \(language.rawValue)")
            expect(cameraPreviewValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible camera preview strings (\(language.rawValue))")
            let radialMenuValues = Mirror(reflecting: FeatureStrings.radialMenu(language)).children
                .compactMap { $0.value as? String }
            expect(radialMenuValues.count == 44 && radialMenuValues.allSatisfy { !$0.isEmpty },
                   "every radial menu string is set for \(language.rawValue)")
            expect(radialMenuValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible radial menu strings (\(language.rawValue))")
            let scratchpadValues = Mirror(reflecting: FeatureStrings.scratchpad(language)).children
                .compactMap { $0.value as? String }
            expect(scratchpadValues.count == 15 && scratchpadValues.allSatisfy { !$0.isEmpty },
                   "every scratchpad string is set for \(language.rawValue)")
            expect(scratchpadValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible scratchpad strings (\(language.rawValue))")
            expect(FeatureStrings.screenshot(language).delaySecondsFormat.contains("%d"),
                   "screenshot delay format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.screenshot(language).savedHUDFormat.contains("%@"),
                   "screenshot saved format keeps its specifier (\(language.rawValue))")
            let strings: Strings = {
                switch language {
                case .enUS: return .enUS
                case .ptBR: return .ptBR
                case .tr: return .tr
                case .ru: return .ru
                case .es: return .es
                case .de: return .de
                case .fr: return .fr
                case .it: return .it
                case .ja: return .ja
                case .ko: return .ko
                case .zhHans: return .zhHans
                case .zhTW: return .zhTW
                case .zhHK: return .zhHK
                }
            }()
            expect(!strings.obPurposeTitle.isEmpty && !strings.obPurposeBody.isEmpty
                    && !strings.obPurposeSkip.isEmpty,
                   "the purpose step speaks \(language.rawValue)")
        }

        // MARK: Hub presets and energy badges

        expect(FeaturePreset.allCases.count == 3,
               "three starting points, not another wall of decisions")
        expect(FeaturePreset.allCases.allSatisfy { !$0.features.isEmpty },
               "every preset installs something")
        expect(FeaturePreset.essential.features.contains(.mixer)
                && FeaturePreset.essential.features.contains(.keepAwake)
                && FeaturePreset.essential.features.contains(.monitorPower),
               "the essential preset covers mixer, monitor and keep awake")
        expect(FeaturePreset.windows.features.allSatisfy { $0.group == .windowsDock },
               "the windows preset stays inside the windows and Dock group")
        expect(FeaturePreset.battery.features.allSatisfy {
                   $0.energyProfile != .mouse && $0.energyProfile != .pointer
                       && $0.energyProfile != .keyboard
                       && $0.energyProfile != .inputs
               },
               "battery and quiet installs nothing that listens to input")
        expect(FeaturePreset.battery.features.allSatisfy {
                   !$0.permissions.contains(.accessibility)
               },
               "battery and quiet needs no accessibility permission at all")
        for preset in FeaturePreset.allCases {
            expect(preset.enableKeys.allSatisfy { key in
                       preset.features.contains { $0.enabledKeys.contains(key) }
                   },
                   "preset enable keys belong to its own features (\(preset.rawValue))")
        }
        expect(AppFeature.monitorCPU.energyProfile == .periodic
                && AppFeature.clipboardHistory.energyProfile == .periodic
                && AppFeature.textSnippets.energyProfile == .inputs
                && AppFeature.dockPreview.energyProfile == .mouse
                && AppFeature.switcher.energyProfile == .keyboard
                && AppFeature.colorPicker.energyProfile == .idle
                && AppFeature.keepAwake.energyProfile == .idle
                && AppFeature.brightness.energyProfile == .idle
                && AppFeature.scratchpad.energyProfile == .idle,
               "energy badges tell the honest mechanism per feature")
        let previousWindowGestureEnergy = UserDefaults.standard.object(
            forKey: DefaultsKey.windowGestureEnabled
        )
        UserDefaults.standard.set(true, forKey: DefaultsKey.windowGestureEnabled)
        expect(AppFeature.windowLayout.energyProfile == .pointer,
               "window dragging reports trackpad and mouse pointer input")
        if let previousWindowGestureEnergy {
            UserDefaults.standard.set(previousWindowGestureEnergy,
                                      forKey: DefaultsKey.windowGestureEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowGestureEnabled)
        }

        // MARK: Settings page visibility

        func pageVisible(_ page: SettingsPage, available: Set<AppFeature>) -> Bool {
            FeatureVisibilitySupport.isPageVisible(page) { available.contains($0) }
        }
        let allFeatures = Set(AppFeature.allCases)
        expect(pageVisible(.mouse, available: allFeatures), "mouse page shows with everything available")
        expect(pageVisible(.mouse, available: [.middleClick]),
               "one remaining mouse feature keeps the mouse page")
        expect(!pageVisible(.mouse, available: []),
               "the mouse page hides only with all four mouse features off")
        expect(!pageVisible(.energy, available: allFeatures.subtracting([.keepAwake, .brightness,
                                                                         .extraBrightness])),
               "energy hides when all three display features are off")
        expect(pageVisible(.energy, available: [.extraBrightness]), "XDR alone keeps the energy page")
        expect(pageVisible(.energy, available: [.brightness]),
               "brightness control alone keeps the energy page")
        expect(!pageVisible(.monitor, available: allFeatures.subtracting(Set(FeatureVisibilitySupport.monitorFeatures))),
               "monitor page hides with every metric off")
        expect(pageVisible(.monitor, available: [.monitorNetwork]), "one metric keeps the monitor page")
        expect(pageVisible(.general, available: []) && pageVisible(.about, available: [])
                && pageVisible(.shortcuts, available: []),
               "app pages never hide")
        expect(!pageVisible(.shelf, available: allFeatures.subtracting([.shelf])),
               "single-feature pages follow their feature")
        expect(pageVisible(.quickTools, available: [.quickToggles]),
               "the quick toggles alone keep the quick tools page")

        // MARK: Display brightness (DDC/CI helpers)

        let ddcWrite = BrightnessSupport.writePacket(code: 0x10, value: 0x1234)
        expect(ddcWrite == [0x84, 0x03, 0x10, 0x12, 0x34,
                            0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x12 ^ 0x34],
               "DDC write packet carries the set opcode, big-endian value and checksum")
        let ddcRead = BrightnessSupport.readRequestPacket(code: 0x10)
        expect(ddcRead == [0x82, 0x01, 0x10, 0x6E ^ 0x82 ^ 0x01 ^ 0x10],
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
        expect(BrightnessSupport.canDisableDisplay(activeDisplayIDs: [1, 3], target: 3),
               "one display can be disabled while another remains active")
        expect(!BrightnessSupport.canDisableDisplay(activeDisplayIDs: [1], target: 1),
               "the final active display can never be disabled")
        expect(!BrightnessSupport.canDisableDisplay(activeDisplayIDs: [1, 3], target: 8),
               "an inactive display cannot enter the disable path")

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
        expect(BrightnessSupport.steppedBrightness(0.97, delta: BrightnessSupport.brightnessKeyStep) == 1.0
                && BrightnessSupport.steppedBrightness(0.03, delta: -BrightnessSupport.brightnessKeyStep) == 0.0,
               "key steps clamp at both ends of the range")

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

        // MARK: Text snippets engine (issue #201)

        expect(TextSnippetSupport.sanitizedTrigger("  ;e mail\n") == ";email", "triggers lose whitespace")
        expect(TextSnippetSupport.bufferAppending(String(repeating: "a", count: 64), typed: "b").count
                == TextSnippetSupport.bufferLimit,
               "the buffer stays capped")
        expect(TextSnippetSupport.bufferAppending("abc", typed: "d") == "abcd", "the buffer appends typing")

        let email = TextSnippet(name: "Email", trigger: ";email", replacement: "me@x.com",
                                expansion: .afterDelimiter, enabled: true)
        let email2 = TextSnippet(name: "Email 2", trigger: ";email2", replacement: "us@x.com",
                                 expansion: .afterDelimiter, enabled: true)
        let dateSnippet = TextSnippet(name: "Now", trigger: ";;dt", replacement: "{{datetime}}",
                                      expansion: .immediate, enabled: true)
        let disabledSnippet = TextSnippet(name: "Off", trigger: ";off", replacement: "x",
                                          expansion: .afterDelimiter, enabled: false)

        expect(TextSnippetSupport.match(buffer: "hello ;email", expansion: .afterDelimiter,
                                        snippets: [email, email2, disabledSnippet]) == email,
               "a completed trigger matches at the buffer's end")
        expect(TextSnippetSupport.match(buffer: "x ;email2", expansion: .afterDelimiter,
                                        snippets: [email, email2]) == email2,
               "the longest trigger wins")
        expect(TextSnippetSupport.match(buffer: ";emai", expansion: .afterDelimiter,
                                        snippets: [email]) == nil,
               "a half-typed trigger stays quiet")
        expect(TextSnippetSupport.match(buffer: "abc ;off", expansion: .afterDelimiter,
                                        snippets: [disabledSnippet]) == nil,
               "disabled snippets never fire")
        expect(TextSnippetSupport.match(buffer: "a;;dt", expansion: .afterDelimiter,
                                        snippets: [dateSnippet]) == nil,
               "modes do not cross: immediate snippets ignore the delimiter path")
        expect(TextSnippetSupport.match(buffer: "a;;dt", expansion: .immediate,
                                        snippets: [dateSnippet]) == dateSnippet,
               "immediate snippets fire the moment the trigger completes")

        let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)
        let expandedText = TextSnippetSupport.expand("Report on {{date}} at {{time}}.",
                                                     date: fixedDate, clipboard: nil,
                                                     locale: Locale(identifier: "en_US"))
        expect(expandedText.contains("2025") && !expandedText.contains("{{date}}")
                && !expandedText.contains("{{time}}"),
               "date and time variables expand")
        expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate, clipboard: "X")
                == "clip: X",
               "the clipboard variable expands to the copied text")
        expect(TextSnippetSupport.expand("clip: {{clipboard}}", date: fixedDate, clipboard: nil)
                == "clip: ",
               "a missing clipboard expands to nothing")
        expect(TextSnippetSupport.expand("keep {{unknown}}", date: fixedDate, clipboard: nil)
                == "keep {{unknown}}",
               "unknown variables stay visible")
        expect(TextSnippetSupport.expand("plain", date: fixedDate, clipboard: nil) == "plain",
               "text without variables passes through untouched")

        let storedSnippets = [email, dateSnippet]
        expect(TextSnippetSupport.decode(TextSnippetSupport.encode(storedSnippets)) == storedSnippets,
               "snippets round-trip through persistence")
        expect(TextSnippetSupport.decode(nil).isEmpty, "no stored data means no snippets")

        // MARK: Radial menu (issue #220)

        expect(RadialMenuGeometry.angle(dx: 0, dyUp: 1) == 0
                && abs(RadialMenuGeometry.angle(dx: 1, dyUp: 0) - .pi / 2) < 0.0001
                && abs(RadialMenuGeometry.angle(dx: 0, dyUp: -1) - .pi) < 0.0001
                && abs(RadialMenuGeometry.angle(dx: -1, dyUp: 0) - 3 * .pi / 2) < 0.0001,
               "wheel angles run clockwise from 12 o'clock")
        expect(RadialMenuGeometry.index(forAngle: 0, itemCount: 4) == 0
                && RadialMenuGeometry.index(forAngle: .pi / 2, itemCount: 4) == 1
                && RadialMenuGeometry.index(forAngle: .pi, itemCount: 4) == 2
                && RadialMenuGeometry.index(forAngle: 3 * .pi / 2, itemCount: 4) == 3,
               "each slice claims the arc around its own center")
        expect(RadialMenuGeometry.index(forAngle: 2 * .pi - 0.01, itemCount: 12) == 0
                && RadialMenuGeometry.index(forAngle: 2 * .pi - 0.3, itemCount: 12) == 11,
               "the top slice claims both sides of 12 o'clock and its left neighbor starts past it")
        expect(RadialMenuGeometry.index(forAngle: 1, itemCount: 0) == nil,
               "an empty wheel highlights nothing")
        expect(RadialMenuGeometry.highlightedIndex(dx: 10, dyUp: 0, deadZoneRadius: 40, itemCount: 4) == nil
                && RadialMenuGeometry.highlightedIndex(dx: 50, dyUp: 0, deadZoneRadius: 40, itemCount: 4) == 1,
               "the hub dead zone highlights nothing and past it the pointer picks a slice")
        let topUnit = RadialMenuGeometry.unitPosition(index: 0, itemCount: 6)
        let rightUnit = RadialMenuGeometry.unitPosition(index: 1, itemCount: 4)
        expect(abs(topUnit.dx) < 0.0001 && abs(topUnit.dyUp - 1) < 0.0001
                && abs(rightUnit.dx - 1) < 0.0001 && abs(rightUnit.dyUp) < 0.0001,
               "slice centers land on the unit circle from the top clockwise")

        let starter = RadialMenuSupport.starterItems
        expect(starter.count == 6 && RadialMenuSupport.sanitized(starter) == starter,
               "the starter wheel is already clean")
        expect(starter.allSatisfy { !$0.effectiveSymbolName.isEmpty },
               "every starter slice has a symbol to draw")
        expect(RadialMenuSupport.decode(nil) == starter,
               "a fresh install decodes to the starter wheel")
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode([])) == [],
               "an emptied wheel stays empty instead of reseeding")

        let sampleWheel = [
            RadialMenuItem(kind: .app, name: "  Editor  ", payload: "/Applications/Editor.app"),
            RadialMenuItem(kind: .url, payload: "example.com/page"),
            RadialMenuItem(kind: .shortcut, payload: "control+option+command:49"),
            RadialMenuItem(kind: .submenu, name: "More", children: [
                RadialMenuItem(kind: .media, payload: "playPause"),
                RadialMenuItem(kind: .submenu, children: [RadialMenuItem(kind: .media, payload: "nextTrack")]),
            ]),
        ]
        let cleaned = RadialMenuSupport.sanitized(sampleWheel)
        expect(cleaned.count == 4 && cleaned[0].name == "Editor"
                && cleaned[1].payload == "https://example.com/page",
               "sanitizing trims names and completes bare links")
        expect(cleaned[3].children.count == 1 && cleaned[3].children[0].kind == .media,
               "submenus keep their actions but never nest another submenu")
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode(cleaned)) == cleaned,
               "radial menu items round-trip through persistence")
        let fullSubmenu = [RadialMenuItem(kind: .submenu, name: "Pack", children: (0 ..< 5).map {
            RadialMenuItem(kind: .url, payload: "example.com/\($0)")
        })]
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode(fullSubmenu)).first?.children.count == 5,
               "a submenu keeps every action through persistence, not just two")
        expect(RadialMenuSupport.sanitized([
            RadialMenuItem(kind: .app, payload: ""),
            RadialMenuItem(kind: .url, payload: "not a link"),
            RadialMenuItem(kind: .shortcut, payload: "garbage"),
            RadialMenuItem(kind: .tool, payload: "unknownTool"),
            RadialMenuItem(kind: .media, payload: "unknownKey"),
        ]).isEmpty,
               "slices that cannot run are dropped instead of rendering dead")
        expect(RadialMenuSupport.sanitized((0 ..< 20).map {
            RadialMenuItem(kind: .url, payload: "example.com/\($0)")
        }).count == RadialMenuSupport.maxItemsPerWheel,
               "a wheel never holds more than 12 slices")
        let lossyJSON = """
        [{"kind":"media","payload":"playPause"},{"kind":"teleport","payload":"x"}]
        """
        expect(RadialMenuSupport.decode(Data(lossyJSON.utf8)).count == 1,
               "unknown kinds from newer versions drop just that slice")

        expect(RadialMenuSupport.normalizedURL("https://a.example/x") == "https://a.example/x"
                && RadialMenuSupport.normalizedURL("mailto:someone@example.com") == "mailto:someone@example.com"
                && RadialMenuSupport.normalizedURL("   ") == nil
                && RadialMenuSupport.normalizedURL("two words") == nil,
               "link normalization keeps schemes and rejects non-links")
        expect(RadialMenuSupport.normalizedURL("tel:5551234") == "tel:5551234"
                && RadialMenuSupport.normalizedURL("example.com:8080/x") == "https://example.com:8080/x"
                && RadialMenuSupport.normalizedURL("localhost:3000") == "https://localhost:3000",
               "digit-after-colon means a port only when the prefix looks like a host")
        expect(RadialMenuSupport.needsAccessibility([starter[3]]) == false
                && RadialMenuSupport.needsAccessibility(starter)
                && RadialMenuSupport.needsAccessibility([
                    RadialMenuItem(kind: .submenu, children: [RadialMenuItem(kind: .shortcut, payload: "command:8")]),
                ]),
               "only wheels that press keys need Accessibility, submenus included")
        expect(RadialMenuMediaKey.playPause.auxKeyType == 16
                && RadialMenuMediaKey.previousTrack.auxKeyType == 20
                && RadialMenuMediaKey.nextTrack.auxKeyType == 19,
               "media slices post the aux codes of the physical keys")
        expect(RadialMenuTool.allCases.allSatisfy { !$0.symbolName.isEmpty }
                && RadialMenuTool.screenshot.feature == .screenshot
                && RadialMenuTool.clipboardHistory.feature == .clipboardHistory
                && RadialMenuTool.scratchpad.feature == .scratchpad,
               "every wheel tool maps to a real feature and symbol")

        // MARK: Dock click with AX-blind apps (issue #200)

        expect(DockClickSupport.effectiveHasUnminimized(unminimizedCount: 2,
                                                        minimizedCount: 0,
                                                        windowServerSeesWindows: false),
               "AX-visible windows count as always")
        expect(DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                        minimizedCount: 0,
                                                        windowServerSeesWindows: true),
               "an AX-blind app with on-screen windows still minimizes")
        expect(!DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                         minimizedCount: 3,
                                                         windowServerSeesWindows: true),
               "minimized-only apps keep the restore path")
        expect(!DockClickSupport.effectiveHasUnminimized(unminimizedCount: 0,
                                                         minimizedCount: 0,
                                                         windowServerSeesWindows: false),
               "a truly windowless app passes the click through")
        expect(!DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 103, y: 103)),
               "click jitter stays a click")
        expect(!DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 106, y: 100)),
               "movement at the slop boundary still counts as a click")
        expect(DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                               to: CGPoint(x: 105, y: 105)),
               "a real drag crosses the slop and hands the press to the Dock")
        expect(DockClickSupport.isDragMovement(from: CGPoint(x: 100, y: 100),
                                               to: CGPoint(x: 100, y: 93)),
               "vertical pulls count as drags too")

        // MARK: Quick toggles

        expect(QuickTogglesSupport.emptyTrashSource == "tell application \"Finder\" to empty trash",
               "the Trash script asks the Finder and nothing else")
        expect(QuickTogglesSupport.isPermissionError(-1743)
                && QuickTogglesSupport.isPermissionError(-1744),
               "both Apple Event consent errors read as a permission problem")
        expect(!QuickTogglesSupport.isPermissionError(-1728)
                && !QuickTogglesSupport.isPermissionError(nil),
               "other script errors and success never read as a permission problem")
        expect(QuickTogglesSupport.finderFlag(true, default: false)
                && !QuickTogglesSupport.finderFlag(false, default: true),
               "real booleans win over the default")
        expect(QuickTogglesSupport.finderFlag("YES", default: false)
                && QuickTogglesSupport.finderFlag("true", default: false)
                && QuickTogglesSupport.finderFlag("1", default: false),
               "legacy YES, true and 1 strings read as on")
        expect(!QuickTogglesSupport.finderFlag("NO", default: true)
                && !QuickTogglesSupport.finderFlag("false", default: true)
                && !QuickTogglesSupport.finderFlag("0", default: true),
               "legacy NO, false and 0 strings read as off")
        expect(QuickTogglesSupport.finderFlag(NSNumber(value: 1), default: false)
                && !QuickTogglesSupport.finderFlag(NSNumber(value: 0), default: true),
               "numeric preference values read by their truthiness")
        expect(QuickTogglesSupport.finderFlag(nil, default: true)
                && !QuickTogglesSupport.finderFlag(nil, default: false)
                && QuickTogglesSupport.finderFlag("maybe", default: true),
               "absent or unreadable values fall back to the given default")
        expect(QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                    isEjectable: false, isLocal: true)
                && QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                        isEjectable: true, isLocal: true),
               "external removable or ejectable local volumes are offered")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: true, isRemovable: true,
                                                     isEjectable: true, isLocal: true),
               "internal volumes are never ejected")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: false),
               "network volumes are never ejected")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                     isEjectable: false, isLocal: true),
               "a fixed external volume without eject support is left alone")

        // MARK: Screenshot tool

        expect(ScreenshotSupport.sanitizedDelay(5) == 5
                && ScreenshotSupport.sanitizedDelay(7) == 0
                && ScreenshotSupport.sanitizedDelay(-3) == 0,
               "capture delay only accepts the offered steps")

        let dragRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 100, y: 80),
                                                       to: CGPoint(x: 40, y: 200))
        expect(dragRect == CGRect(x: 40, y: 80, width: 60, height: 120),
               "a drag in any direction normalizes to a positive rect")
        let squareRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 10, y: 10),
                                                         to: CGPoint(x: 40, y: 90),
                                                         square: true)
        expect(squareRect.width == squareRect.height && squareRect.width == 80,
               "shift constrains the selection to a square")
        let centered = ScreenshotSupport.selectionRect(from: CGPoint(x: 50, y: 50),
                                                       to: CGPoint(x: 70, y: 60),
                                                       fromCenter: true)
        expect(centered == CGRect(x: 30, y: 40, width: 40, height: 20),
               "option grows the selection from the center")
        expect(ScreenshotSupport.isClick(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 8))
                && !ScreenshotSupport.isClick(from: .zero, to: CGPoint(x: 12, y: 0)),
               "a tiny drag is a click, a real drag is not")

        let cocoa = ScreenshotSupport.cocoaRect(fromWindowServer: CGRect(x: 10, y: 30, width: 200, height: 100),
                                                mainScreenHeight: 900)
        expect(cocoa == CGRect(x: 10, y: 770, width: 200, height: 100),
               "window server rects convert to Cocoa coordinates")
        let viewRect = ScreenshotSupport.flippedViewRect(fromCocoa: cocoa,
                                                         screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        expect(viewRect == CGRect(x: 10, y: 30, width: 200, height: 100),
               "the round trip back to a flipped view restores the window server rect")
        expect(ScreenshotSupport.cocoaRect(fromFlippedView: viewRect,
                                           screenFrame: CGRect(x: 0, y: 0,
                                                               width: 1600, height: 900)) == cocoa,
               "a flipped overlay rect maps back to its Cocoa screen position")
        let pixels = ScreenshotSupport.imagePixelRect(fromView: CGRect(x: 10, y: 20, width: 30, height: 40),
                                                      viewSize: CGSize(width: 100, height: 100),
                                                      imageSize: CGSize(width: 200, height: 200))
        expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 80),
               "view points scale to image pixels")
        expect(ScreenshotSupport.imagePixelRect(fromView: CGRect(x: -20, y: -20, width: 500, height: 500),
                                                viewSize: CGSize(width: 100, height: 100),
                                                imageSize: CGSize(width: 200, height: 200))
                == CGRect(x: 0, y: 0, width: 200, height: 200),
               "pixel rects clamp to the image")
        expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: 50, y: 25),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 100, y: 50),
               "the capture loupe maps its pointer to the matching source pixel")
        expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: -10, y: 90),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 0, y: 100),
               "the capture loupe clamps source points at display edges")
        let editorMinimum = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 1470, height: 956))
        expect(editorMinimum == CGSize(width: 980, height: 680),
               "the screenshot editor opens on a comfortable canvas")
        let editorSmallDisplay = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 700, height: 500))
        expect(editorSmallDisplay == CGSize(width: 700, height: 500),
               "the editor minimum never exceeds a compact display")
        let smallCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 180, height: 100),
            visibleSize: CGSize(width: 1470, height: 956))
        expect(smallCaptureWindow == editorMinimum,
               "a small screenshot still receives the full editing canvas")
        let largeCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 2200, height: 1400),
            visibleSize: CGSize(width: 1470, height: 956))
        expect(largeCaptureWindow.width <= 1470 * 0.90
                && largeCaptureWindow.height <= 956 * 0.88,
               "a large screenshot editor stays inside the visible display")
        let previewFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 286, height: 210),
            anchor: CGRect(x: 1100, y: 100, width: 300, height: 300),
            pointer: CGPoint(x: 1300, y: 220),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        expect(CGRect(x: 10, y: 10, width: 1450, height: 936).contains(previewFrame),
               "the quick capture preview stays fully inside the visible display")

        let pickable = [ScreenshotSupport.PickableWindow(windowID: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 50)),
                        ScreenshotSupport.PickableWindow(windowID: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 400))]
        expect(ScreenshotSupport.window(at: CGPoint(x: 10, y: 10), in: pickable)?.windowID == 1,
               "the frontmost window wins a click")
        expect(ScreenshotSupport.window(at: CGPoint(x: 300, y: 300), in: pickable)?.windowID == 2
                && ScreenshotSupport.window(at: CGPoint(x: 900, y: 900), in: pickable) == nil,
               "clicks outside every window pick nothing")

        let fileDate = Date(timeIntervalSince1970: 1_752_486_065) // 2025-07-14 09:41:05 UTC
        let fileName = ScreenshotSupport.fileName(prefix: "Screenshot", date: fileDate)
        expect(fileName.hasPrefix("Screenshot 20") && fileName.hasSuffix(".png")
                && !fileName.contains(":") && fileName.contains(" at "),
               "file names are dated, colon free and png")
        expect(ScreenshotSupport.uniqueFileName("a.png", exists: { _ in false }) == "a.png",
               "a free name stays untouched")
        expect(ScreenshotSupport.uniqueFileName("a.png", exists: { $0 == "a.png" }) == "a 2.png",
               "a taken name gets the next numbered variant")
        expect(ScreenshotSupport.uniqueFileName("a.png",
                                                exists: { $0 == "a.png" || $0 == "a 2.png" }) == "a 3.png",
               "numbering keeps walking until a free name")

        var counterList = [
            ScreenshotSupport.Annotation(tool: .counter, number: 1),
            ScreenshotSupport.Annotation(tool: .arrow),
            ScreenshotSupport.Annotation(tool: .counter, number: 2),
            ScreenshotSupport.Annotation(tool: .counter, number: 3),
        ]
        counterList.remove(at: 0)
        let renumbered = ScreenshotSupport.renumberingCounters(counterList)
        expect(renumbered.filter { $0.tool == .counter }.map(\.number) == [1, 2],
               "deleting a counter renumbers the rest without holes")
        expect(renumbered[0].tool == .arrow || renumbered.count == 3,
               "renumbering never drops annotations")

        let resized = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .bottomRight,
                                                    to: CGPoint(x: 50, y: 60))
        expect(resized == CGRect(x: 10, y: 10, width: 40, height: 50),
               "dragging a handle resizes the rect")
        let crossed = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .right,
                                                    to: CGPoint(x: 0, y: 0))
        expect(crossed.width == 10 && crossed.minX == 0,
               "dragging a handle across the opposite edge flips instead of going negative")
        let movedCrop = ScreenshotSupport.movedRect(
            CGRect(x: 20, y: 30, width: 80, height: 60),
            by: CGPoint(x: 50, y: -100),
            within: CGRect(x: 0, y: 0, width: 120, height: 100))
        expect(movedCrop == CGRect(x: 40, y: 0, width: 80, height: 60),
               "dragging inside a crop moves it without resizing past the image edges")
        expect(ScreenshotSupport.handle(at: CGPoint(x: 10, y: 10),
                                        rect: CGRect(x: 10, y: 10, width: 100, height: 100),
                                        tolerance: 6) == .topLeft,
               "handle hit testing finds the corner")

        let head = ScreenshotSupport.arrowHead(from: CGPoint(x: 0, y: 0),
                                               to: CGPoint(x: 100, y: 0),
                                               strokeWidth: 4)
        expect(head.left.x < 100 && head.right.x < 100 && head.left.y != head.right.y,
               "arrow heads open behind the tip")
        let shortHead = ScreenshotSupport.arrowHead(from: .zero,
                                                    to: CGPoint(x: 10, y: 0),
                                                    strokeWidth: 14)
        expect(shortHead.left.x >= 0 && shortHead.right.x >= 0,
               "a short arrow head never extends behind its tail")
        let arrowPath = ScreenshotSupport.arrowSilhouette(from: CGPoint(x: 100, y: 20),
                                                          to: CGPoint(x: 100, y: 300),
                                                          strokeWidth: 40)
        expect(arrowPath.contains(CGPoint(x: 100, y: 30),
                                  using: .winding,
                                  transform: .identity),
               "the arrow tail stays filled where its cap meets the shaft")
        expect(arrowPath.contains(CGPoint(x: 100, y: 190),
                                  using: .winding,
                                  transform: .identity),
               "the arrow stays filled where its shaft meets the head")
        expect(abs(ScreenshotSupport.distance(from: CGPoint(x: 50, y: 10),
                                              toSegment: CGPoint(x: 0, y: 0),
                                              CGPoint(x: 100, y: 0)) - 10) < 0.001,
               "segment distance measures perpendicular offset")
        expect(ScreenshotSupport.distance(from: CGPoint(x: -30, y: 0),
                                          toSegment: CGPoint(x: 0, y: 0),
                                          CGPoint(x: 100, y: 0)) == 30,
               "segment distance clamps to the endpoints")

        expect(ScreenshotSupport.pixelBlockSize(for: CGSize(width: 5500, height: 3600)) == 65
                && ScreenshotSupport.pixelBlockSize(for: CGSize(width: 200, height: 120)) == 10,
               "pixelation blocks scale with the capture and never get too fine")
        expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 2)
                == CGSize(width: 400, height: 300),
               "the 1x option halves a Retina capture")
        expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 1)
                == CGSize(width: 800, height: 600),
               "a 1x capture never downscales")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 100, height: 100), factor: 0.5) == 24,
               "backdrop padding keeps a floor for tiny captures")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 1)
                == (4000 * 0.175).rounded(),
               "the margin slider grows the backdrop padding")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 0)
                == 140,
               "margin zero still keeps a small frame")
        expect(ScreenshotSupport.BackdropID.allCases.filter { $0 != .none }
                .allSatisfy { $0.stops.count == 2 },
               "every backdrop gradient has its two stops")
        expect(ScreenshotSupport.ColorID.sanitized("bogus") == .red
                && ScreenshotSupport.StrokeID.sanitized(nil) == .medium,
               "style choices sanitize to safe defaults")
        expect(ScreenshotSupport.StickerID.sanitized("bogus") == .check
                && ScreenshotSupport.StickerID.allCases.count == 12,
               "stickers keep a safe default and a compact built-in set")
        let stickerRect = ScreenshotSupport.stickerRect(
            centeredAt: CGPoint(x: 5, y: 5),
            side: 40,
            within: CGRect(x: 0, y: 0, width: 100, height: 80))
        expect(stickerRect == CGRect(x: 0, y: 0, width: 40, height: 40),
               "a sticker placed at an edge stays fully inside the image")

        expect(ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 0) == 0
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 1) == 180
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 2) == 180,
               "card corner radius clamps and scales with the short side")

        let solidStyle = ScreenshotSupport.BackdropStyle(kind: .solid, colors: [[0.2, 0.4, 0.9]],
                                                         padding: 0.3, cornerRadius: 0.2)
        let solidRoundTrip = ScreenshotSupport.BackdropStyle.decoded(solidStyle.encoded())
        expect(solidRoundTrip == solidStyle, "a backdrop style round-trips through JSON")
        expect(ScreenshotSupport.BackdropStyle.decoded(nil).kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("").kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("not json").kind == .none,
               "a missing or broken backdrop style falls back to none")
        expect(ScreenshotSupport.BackdropStyle().cornerRadius == 0,
               "the default backdrop leaves capture corners unchanged")
        let brokenSolid = ScreenshotSupport.BackdropStyle(kind: .solid, colors: nil)
        expect(brokenSolid.sanitized().kind == .none,
               "a solid style without colors demotes to none")
        let wildSliders = ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "ocean",
                                                          padding: 9, cornerRadius: -3)
        expect(wildSliders.sanitized().padding == 1 && wildSliders.sanitized().cornerRadius == 0,
               "backdrop sliders clamp to their range")
        expect(ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "bogus").sanitized().kind == .none
                && ScreenshotSupport.BackdropStyle(kind: .image, imagePath: nil).sanitized().kind == .none,
               "unknown presets and missing image paths demote to none")
        expect(ScreenshotSupport.BackdropStyle(kind: .gradient,
                                               colors: [[0, 2, -1], [0.5, 0.5, 0.5]])
                .sanitized().colors?.first == [0, 1, 0],
               "gradient colors clamp component by component")

        let presetList = [solidStyle,
                          ScreenshotSupport.BackdropStyle(kind: .gradient,
                                                          colors: [[1, 0, 0], [0, 0, 1]])]
        let decodedPresets = ScreenshotSupport.decodedBackdropPresets(
            ScreenshotSupport.encodedBackdropPresets(presetList))
        expect(decodedPresets == presetList, "saved backdrops round-trip through JSON")
        expect(ScreenshotSupport.decodedBackdropPresets("junk").isEmpty
                && ScreenshotSupport.decodedBackdropPresets(nil).isEmpty,
               "broken preset lists decode to empty")
        let overflow = Array(repeating: solidStyle, count: 40)
        expect(ScreenshotSupport.decodedBackdropPresets(
                ScreenshotSupport.encodedBackdropPresets(overflow)).count
                == ScreenshotSupport.backdropPresetLimit,
               "saved backdrops cap at the presets limit")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotBackdropStyle] as? String == ""
                && Defaults.registeredDefaults[DefaultsKey.screenshotBackdropPresets] as? String == "[]",
               "backdrop style and presets register empty")

        let wordBoxes = [CGRect(x: 0, y: 0, width: 40, height: 10),
                         CGRect(x: 50, y: 0, width: 40, height: 10),
                         CGRect(x: 0, y: 20, width: 40, height: 10)]
        expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 60, y: 5),
                                               boxes: wordBoxes) == [0, 1],
               "a drag across a line selects the words it crosses")
        expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 10, y: 25),
                                               boxes: wordBoxes) == [0, 2],
               "a drag across lines selects into the next line")
        let recognizedWords = [
            ScreenshotSupport.RecognizedWord(text: "ola", rect: wordBoxes[0], line: 0),
            ScreenshotSupport.RecognizedWord(text: "mundo", rect: wordBoxes[1], line: 0),
            ScreenshotSupport.RecognizedWord(text: "linha", rect: wordBoxes[2], line: 1),
        ]
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [1, 0]) == "ola mundo",
               "selected words join in reading order with spaces")
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [2, 0]) == "ola\nlinha",
               "line changes become newlines")
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [9]).isEmpty
                && ScreenshotSupport.joinedWords(recognizedWords, selected: []).isEmpty,
               "out of range or empty selections copy nothing")
        let defaultScreenshotTools = ScreenshotSupport.Tool.allCases
        expect(defaultScreenshotTools.count == 13
                && Array(defaultScreenshotTools.prefix(9))
                    == [.select, .arrow, .pixelate, .crop, .text, .sticker,
                        .rect, .highlight, .freehand],
               "the screenshot rail leads with the nine most useful numbered tools")
        let customScreenshotTools = ScreenshotSupport.Tool.ordered(
            from: "crop,arrow,arrow,invalid")
        expect(Array(customScreenshotTools.prefix(2)) == [.crop, .arrow]
                && customScreenshotTools.count == 13
                && Set(customScreenshotTools).count == 13,
               "a saved screenshot tool order drops invalid duplicates and appends missing tools")
        expect(ScreenshotSupport.Tool.shortcutTool(number: 1,
                                                   orderRaw: nil,
                                                   enabled: true) == .select
                && ScreenshotSupport.Tool.shortcutTool(number: 3,
                                                       orderRaw: nil,
                                                       enabled: true) == .pixelate
                && ScreenshotSupport.Tool.shortcutTool(number: 9,
                                                       orderRaw: nil,
                                                       enabled: true) == .freehand
                && ScreenshotSupport.Tool.shortcutTool(number: 1,
                                                       orderRaw: nil,
                                                       enabled: false) == nil
                && ScreenshotSupport.Tool.shortcutTool(number: 10,
                                                       orderRaw: nil,
                                                       enabled: true) == nil,
               "number keys 1 through 9 follow tool order and can be disabled together")
        expect(ScreenshotSupport.Tool.shortcutNumber(for: .crop,
                                                     orderRaw: "arrow,crop",
                                                     enabled: true) == 2
                && ScreenshotSupport.Tool.shortcutNumber(for: .redact,
                                                         orderRaw: nil,
                                                         enabled: true) == nil,
               "the rail exposes only the first nine configured shortcut numbers")
        let cropAssignedFirst = ScreenshotSupport.Tool.assigningShortcut(
            1, to: .crop, orderRaw: nil)
        let selectWithoutShortcut = ScreenshotSupport.Tool.assigningShortcut(
            nil, to: .select, orderRaw: nil)
        expect(cropAssignedFirst.first == .crop
                && ScreenshotSupport.Tool.shortcutNumber(
                    for: .crop,
                    orderRaw: cropAssignedFirst.map(\.rawValue).joined(separator: ","),
                    enabled: true) == 1
                && selectWithoutShortcut.firstIndex(of: .select) == 9
                && ScreenshotSupport.Tool.shortcutNumber(
                    for: .select,
                    orderRaw: selectWithoutShortcut.map(\.rawValue).joined(separator: ","),
                    enabled: true) == nil,
               "the visible shortcut menu assigns a numbered slot or removes a tool from 1 through 9")

        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 50, y: 40),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 43, y: 33, width: 14, height: 14),
               "the crop loupe centers its source pixels around an inner grip")
        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 80),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 86, y: 66, width: 14, height: 14),
               "the crop loupe keeps a full sample at the bottom right edge")
        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: .zero,
            imageSize: CGSize(width: 8, height: 5))
            == CGRect(x: 0, y: 0, width: 8, height: 5),
               "the crop loupe safely shrinks only for images smaller than its sample")
        expectClose(ScreenshotSupport.captureLoupeZoom(1, adjustedBy: 1), 1.15,
                    "scrolling up zooms the capture loupe in")
        expectClose(ScreenshotSupport.captureLoupeZoom(0.5, adjustedBy: -1), 0.5,
                    "capture loupe zoom stays above its minimum")
        expectClose(ScreenshotSupport.captureLoupeZoom(4, adjustedBy: 1), 4,
                    "capture loupe zoom stays below its maximum")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 2), 6,
                    "higher capture loupe zoom samples fewer source pixels")

        expect(Defaults.registeredDefaults[DefaultsKey.screenshotFreeze] as? Bool == true,
               "the screen freezes during selection by default")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotShortcutEnabled] as? Bool == false,
               "the screenshot shortcut ships off like the other quick tools")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotAnnotationShadows] as? Bool == false,
               "screenshot annotation shadows ship off")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolShortcutsEnabled] as? Bool == true,
               "screenshot number shortcuts ship enabled")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolOrder] as? String
                == ScreenshotSupport.Tool.defaultOrderStorage,
               "the screenshot rail ships in its useful numbered order")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastSticker] as? String == "check",
               "the sticker tool starts with a safe built-in choice")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotShortcut] as? String
                == "control+option+command:21",
               "the default screenshot shortcut is control option command 4")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScreenshot] as? Bool == true,
               "the panel row ships visible like its siblings")
        expect(GlobalShortcutRole.screenshot.requiredEnableKeys == [DefaultsKey.screenshotShortcutEnabled]
                && GlobalShortcutRole.screenshot.feature == .screenshot,
               "the screenshot shortcut role gates on its toggle and feature")

        expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcutEnabled] as? Bool == false,
               "the camera preview shortcut ships off like the other quick tools")
        expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcut] as? String
                == "control+option+command:13",
               "the default camera preview shortcut is control option command W")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityCameraPreview] as? Bool == true,
               "the camera preview panel row ships visible like its siblings")
        expect(GlobalShortcutRole.cameraPreview.requiredEnableKeys == [DefaultsKey.cameraPreviewShortcutEnabled]
                && GlobalShortcutRole.cameraPreview.feature == .cameraPreview,
               "the camera preview shortcut role gates on its toggle and feature")

        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcutEnabled] as? Bool == false,
               "the scratchpad shortcut ships off like the other quick tools")
        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcut] as? String
                == "control+option+command:45",
               "the default scratchpad shortcut is control option command N")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScratchpad] as? Bool == true,
               "the scratchpad panel row ships visible like its siblings")
        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadRetention] as? String == "never",
               "the scratchpad keeps text until cleared by default")
        expect(GlobalShortcutRole.scratchpad.requiredEnableKeys == [DefaultsKey.scratchpadShortcutEnabled]
                && GlobalShortcutRole.scratchpad.feature == .scratchpad,
               "the scratchpad shortcut role gates on its toggle and feature")
        expect(ScratchpadRetention.sanitized("day") == .day
                && ScratchpadRetention.sanitized("week") == .week
                && ScratchpadRetention.sanitized("month") == .month
                && ScratchpadRetention.sanitized(nil) == .never
                && ScratchpadRetention.sanitized("yesterday") == .never,
               "scratchpad retention sanitizes to the allowed periods and falls back to never")
        expect(ScratchpadRetention.never.maxIdleInterval == nil
                && ScratchpadRetention.day.maxIdleInterval == 86_400
                && ScratchpadRetention.week.maxIdleInterval == 7 * 86_400
                && ScratchpadRetention.month.maxIdleInterval == 30 * 86_400,
               "scratchpad retention periods are a day, a week and thirty days")
        let scratchpadNow = Date(timeIntervalSince1970: 1_784_000_000)
        expect(!ScratchpadSupport.shouldClear(lastEdited: nil, now: scratchpadNow, retention: .day)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                  now: scratchpadNow, retention: .never)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-3_600),
                                                  now: scratchpadNow, retention: .day)
                && ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                 now: scratchpadNow, retention: .day)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                  now: scratchpadNow, retention: .week)
                && ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-8 * 86_400),
                                                 now: scratchpadNow, retention: .week)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(60),
                                                  now: scratchpadNow, retention: .day),
               "the scratchpad only clears when a period is chosen and the last edit is older than it")
        let scratchpadExportName = ScratchpadSupport.exportFileName(title: "Scratchpad",
                                                                    date: scratchpadNow)
        expect(scratchpadExportName.hasPrefix("Scratchpad 20")
                && scratchpadExportName.hasSuffix(".txt")
                && scratchpadExportName.count == "Scratchpad ".count + 14,
               "scratchpad export file name is the title plus the local date")

        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuEnabled] as? Bool == false,
               "the radial menu ships off by default")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuShortcut] as? String
                == "control+option+command:49",
               "the default radial menu shortcut is control option command space")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuAtPointer] as? Bool == true,
               "the radial menu opens at the pointer by default")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuMouseButton] as? String == "off",
               "the side button trigger ships off")
        expect(RadialMenuMouseTrigger.sanitized("back") == .back
                && RadialMenuMouseTrigger.sanitized("forward").buttonNumber == 4
                && RadialMenuMouseTrigger.back.buttonNumber == 3
                && RadialMenuMouseTrigger.sanitized(nil) == .off
                && RadialMenuMouseTrigger.sanitized("teleport") == .off
                && RadialMenuMouseTrigger.off.buttonNumber == nil,
               "the side button trigger maps to the HID numbers and falls back to off")
        expect(RadialMenuMouseTrigger.back.buttonNumber == MouseNavigationSupport.backButtonNumber
                && RadialMenuMouseTrigger.forward.buttonNumber == MouseNavigationSupport.forwardButtonNumber,
               "the wheel and mouse navigation agree on which button is which")
        expect(!RadialMenuSupport.claimsMouseButton(3) && !RadialMenuSupport.claimsMouseButton(4),
               "with the feature off no side button is claimed away from navigation")
        expect(Defaults.registeredDefaults[DefaultsKey.panelControlRadialMenu] as? Bool == true,
               "the radial menu panel row ships visible like its siblings")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuItems] == nil,
               "the items blob has no registered default so a fresh install detects the starter wheel")
        expect(GlobalShortcutRole.radialMenu.requiredEnableKeys == [DefaultsKey.radialMenuEnabled]
                && GlobalShortcutRole.radialMenu.feature == .radialMenu,
               "the radial menu shortcut role gates on the feature toggle")

        // MARK: Settings backup

        let backupKeys = SettingsBackupSupport.exportKeys()
        expect(backupKeys.contains(DefaultsKey.switcherEnabled)
                && backupKeys.contains(DefaultsKey.menuBarCPU)
                && backupKeys.contains(DefaultsKey.language)
                && backupKeys.contains(DefaultsKey.appVolumes)
                && backupKeys.contains(DefaultsKey.mixerShowFinder)
                && backupKeys.contains(DefaultsKey.keepAwakeActiveIcon)
                && backupKeys.contains(AppFeature.dockPreview.availabilityKey),
               "backup carries preferences, menu bar pins, Keep Awake appearance, language and hub availability")
        expect(backupKeys.contains(DefaultsKey.launchAtLoginWanted),
               "the launch at login choice travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.textSnippets)
                && backupKeys.contains(DefaultsKey.textSnippetsEnabled),
               "snippets travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.windowGestureEnabled)
                && backupKeys.contains(DefaultsKey.windowGestureModifiers)
                && backupKeys.contains(DefaultsKey.windowGestureRaiseWindow),
               "window gesture choices travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.screenshotFreeze)
                && backupKeys.contains(DefaultsKey.screenshotSaveFolder)
                && backupKeys.contains(DefaultsKey.screenshotToolOrder)
                && backupKeys.contains(DefaultsKey.screenshotToolShortcutsEnabled)
                && backupKeys.contains(DefaultsKey.panelUtilityScreenshot),
               "screenshot preferences travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.cameraPreviewShortcut)
                && backupKeys.contains(DefaultsKey.cameraPreviewShortcutEnabled)
                && backupKeys.contains(DefaultsKey.panelUtilityCameraPreview),
               "camera preview preferences travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.scratchpadShortcut)
                && backupKeys.contains(DefaultsKey.scratchpadShortcutEnabled)
                && backupKeys.contains(DefaultsKey.scratchpadRetention)
                && backupKeys.contains(DefaultsKey.panelUtilityScratchpad),
               "scratchpad preferences travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.radialMenuEnabled)
                && backupKeys.contains(DefaultsKey.radialMenuShortcut)
                && backupKeys.contains(DefaultsKey.radialMenuAtPointer)
                && backupKeys.contains(DefaultsKey.radialMenuMouseButton)
                && backupKeys.contains(DefaultsKey.radialMenuItems)
                && backupKeys.contains(DefaultsKey.panelControlRadialMenu),
               "the radial menu wheel and choices travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.panelShowToggles)
                && backupKeys.contains(DefaultsKey.panelToggleOrder)
                && backupKeys.contains(DefaultsKey.panelToggleDarkMode),
               "the quick toggles layout travels with the settings backup")
        expect(!backupKeys.contains(DefaultsKey.clipboardHistoryEntries)
                && !backupKeys.contains(DefaultsKey.shelfItems)
                && !backupKeys.contains(DefaultsKey.sleepDisabledFlag)
                && !backupKeys.contains(DefaultsKey.micMuteActive)
                && !backupKeys.contains(DefaultsKey.cleanerLastAutoRun)
                && !backupKeys.contains(DefaultsKey.statusItemPlacementGeneration),
               "backup never carries private content, live state or machine markers")
        expect(backupKeys.contains(DefaultsKey.hasOnboarded)
                && backupKeys.contains(DefaultsKey.dockPreviewIntroVersion)
                && backupKeys.contains(DefaultsKey.featuresOnboardingVersion)
                && backupKeys.contains(DefaultsKey.lastUpdateIntroVersion),
               "a restored Mac does not replay onboarding or the intros already seen")
        let backupPayload = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.switcherEnabled ? true : nil
        }
        expect(backupPayload[SettingsBackupSupport.formatVersionKey] as? Int
                == SettingsBackupSupport.formatVersion,
               "backup envelope carries the format version")
        let roundTrip = SettingsBackupSupport.sanitizedSettings(from: backupPayload)
        expect(roundTrip?[DefaultsKey.switcherEnabled] as? Bool == true,
               "a backup round-trips its settings")
        expect(SettingsBackupSupport.sanitizedSettings(from: [SettingsBackupSupport.settingsKey: [String: Any]()]) == nil,
               "a file without the version envelope is rejected")
        let tampered: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: ["evilKey": "x", DefaultsKey.autoQuitEnabled: true] as [String: Any],
        ]
        let filteredImport = SettingsBackupSupport.sanitizedSettings(from: tampered)
        expect(filteredImport?["evilKey"] == nil
                && filteredImport?[DefaultsKey.autoQuitEnabled] as? Bool == true,
               "unknown keys are dropped on import")
        expect(SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: 99,
            SettingsBackupSupport.settingsKey: [String: Any](),
        ]) == nil, "a future format version is rejected")

        // MARK: Result

        if failures.isEmpty {
            print("TESTS OK (\(checks) checks)")
            exit(0)
        } else {
            print("TESTS FAILED (\(failures.count) of \(checks)):")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }

    private static func formatSpecifiers(in format: String) -> [String] {
        var specifiers: [String] = []
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                index = format.index(after: index)
                continue
            }
            index = format.index(after: index)
            if index < format.endIndex, format[index] == "%" {
                index = format.index(after: index)
                continue
            }
            while index < format.endIndex {
                let character = format[index]
                if character.isLetter || character == "@" {
                    specifiers.append(String(character))
                    index = format.index(after: index)
                    break
                }
                index = format.index(after: index)
            }
        }
        return specifiers
    }

}
