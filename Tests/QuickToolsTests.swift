// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

enum QuickToolsTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            expect(actual == expected, "\(label): got \"\(actual)\", expected \"\(expected)\"")
        }
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

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

        // Sample known pixels, including an ICC profile, through the same
        // path used by color confirmation and the magnifier's readout/copy.
        for profile in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let space = CGColorSpace(name: profile)!
            let bytes: [UInt8] = [0, 0, 255, 255, 153, 102, 51, 255]
            let image = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: 8, space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                                    .union(.byteOrder32Little),
                                provider: CGDataProvider(data: Data(bytes) as CFData)!,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let sampled = QuickToolsSupport.sampledColor(in: image, x: 1, y: 0)?.usingColorSpace(.sRGB)
            let expected = NSColor(cgColor: CGColor(colorSpace: space,
                                                   components: [0.2, 0.4, 0.6, 1])!)!
                .usingColorSpace(.sRGB)!
            expect(sampled != nil, "color picker reads the chosen pixel in \(profile)")
            if let sampled {
                expectClose(sampled.redComponent, expected.redComponent, "sampled red respects \(profile)")
                expectClose(sampled.greenComponent, expected.greenComponent, "sampled green respects \(profile)")
                expectClose(sampled.blueComponent, expected.blueComponent, "sampled blue respects \(profile)")
                if profile == CGColorSpace.sRGB {
                    expectEqual(QuickToolsSupport.colorString(red: sampled.redComponent,
                                                             green: sampled.greenComponent,
                                                             blue: sampled.blueComponent,
                                                             format: .hex),
                                "#336699", "color picker preserves a known sRGB hex")
                }
            }
        }

        let ocrLines = [
            QuickToolsSupport.RecognizedLine(text: "world", x: 0.5, y: 0.8),
            QuickToolsSupport.RecognizedLine(text: "hello", x: 0.1, y: 0.81),
            QuickToolsSupport.RecognizedLine(text: "below", x: 0.1, y: 0.4),
            QuickToolsSupport.RecognizedLine(text: "   ", x: 0.2, y: 0.6),
        ]
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines, removingLineBreaks: false),
                    "hello\nworld\nbelow",
                    "screen OCR joins lines top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines, removingLineBreaks: true),
                    "hello world below",
                    "screen OCR can join lines with spaces")
        let joinedOCRPair: (String, String, Bool) -> String = { first, second, removingLineBreaks in
            QuickToolsSupport.joinedRecognizedText([
                .init(text: first, x: 0.1, y: 0.8),
                .init(text: second, x: 0.1, y: 0.4),
            ], removingLineBreaks: removingLineBreaks)
        }
        expectEqual(joinedOCRPair("这是", "测试", true), "这是测试",
                    "screen OCR joins Chinese lines without spaces")
        expectEqual(joinedOCRPair("これは", "テストです", true), "これはテストです",
                    "screen OCR joins Japanese lines without spaces")
        expectEqual(joinedOCRPair("これは", "ﾃｽﾄです", true), "これはﾃｽﾄです",
                    "screen OCR joins halfwidth Japanese kana without spaces")
        expectEqual(joinedOCRPair("이것은", "테스트입니다", true), "이것은 테스트입니다",
                    "screen OCR keeps Korean word spaces at line seams")
        expectEqual(joinedOCRPair("ㅋㅋ", "ㅎㅎ", true), "ㅋㅋ ㅎㅎ",
                    "screen OCR keeps spaces between Hangul compatibility jamo")
        expectEqual(joinedOCRPair("version", "版本", true), "version 版本",
                    "screen OCR separates mixed Latin and CJK seams")
        expectEqual(joinedOCRPair("Hello ", " world", true), "Hello world",
                    "screen OCR normalizes spaced-script boundary whitespace")
        expectEqual(joinedOCRPair("这是 ", " 测试", true), "这是测试",
                    "screen OCR trims boundary whitespace before a tight CJK seam")
        expectEqual(joinedOCRPair("이것은 ", " 테스트", true), "이것은 테스트",
                    "screen OCR normalizes Korean boundary whitespace to one separator")
        expectEqual(joinedOCRPair("这是", "测试", false), "这是\n测试",
                    "screen OCR preserves Chinese line breaks when removal is off")
        expectEqual(joinedOCRPair("这是 ", " 测试", false), "这是 \n 测试",
                    "screen OCR preserves boundary whitespace when line removal is off")
        expectEqual(QuickToolsSupport.joinedRecognizedText([], removingLineBreaks: false), "",
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

        // Paste plain delegates only to the universal ⌥⇧⌘V equivalent
        // (shift = 1, option = 2 in the AX modifier mask); anything else in
        // an app's menus is some other edit command and must not be pressed.
        expect(QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                        modifierMask: 3,
                                                        isEnabled: true),
               "V with shift+option is an app's own matching-style paste")
        expect(QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "v",
                                                        modifierMask: 3,
                                                        isEnabled: true),
               "the command character match ignores case")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 0,
                                                         isEnabled: true),
               "plain ⌘V is the regular paste, never pressed as match style")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 1,
                                                         isEnabled: true),
               "⇧⌘V alone is a different command in several apps")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3 | 4,
                                                         isEnabled: true),
               "a control variant is not the matching-style paste")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3 | 8,
                                                         isEnabled: true),
               "an equivalent without the command key does not qualify")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "C",
                                                         modifierMask: 3,
                                                         isEnabled: true),
               "other command characters never match")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: nil,
                                                         modifierMask: 3,
                                                         isEnabled: true),
               "an item with no key equivalent never matches")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: nil,
                                                         isEnabled: true),
               "an unreadable modifier mask never matches")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3,
                                                         isEnabled: false),
               "a disabled item is left alone so the fallback paste still runs")

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
    }

    static func runToggles(expect: (Bool, String) -> Void) {
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
                                                    isEjectable: false, isLocal: true,
                                                    isRootFileSystem: false)
                && QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                        isEjectable: true, isLocal: true,
                                                        isRootFileSystem: false),
               "external removable or ejectable local volumes are offered")
        expect(QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                    isEjectable: false, isLocal: true,
                                                    isRootFileSystem: false),
               "an external drive with fixed media is offered, the common desk drive")
        expect(QuickTogglesSupport.shouldOfferEject(isInternal: true, isRemovable: true,
                                                    isEjectable: true, isLocal: true,
                                                    isRootFileSystem: false),
               "media that comes out of an internal reader is offered")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: true, isRemovable: false,
                                                     isEjectable: false, isLocal: true,
                                                     isRootFileSystem: false),
               "internal fixed drives are never ejected")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: false,
                                                     isRootFileSystem: false),
               "network volumes are never ejected")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: true,
                                                     isRootFileSystem: true),
               "the volume the Mac booted from is never ejected, even on an external drive")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: false,
                                                     isEjectable: true, isLocal: true,
                                                     isRootFileSystem: false,
                                                     volumeName: "Time Machine",
                                                     excludedVolumes: ["time machine"]),
               "a volume matching an excluded name case-insensitively is not offered for eject")
        expect(!QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                     isEjectable: true, isLocal: true,
                                                     isRootFileSystem: false,
                                                     volumeName: "SD Card",
                                                     volumeUUID: "1234-5678-ABCD",
                                                     excludedVolumes: ["1234-5678-abcd"]),
               "a volume matching an excluded UUID is not offered for eject")
        expect(QuickTogglesSupport.shouldOfferEject(isInternal: false, isRemovable: true,
                                                    isEjectable: true, isLocal: true,
                                                    isRootFileSystem: false,
                                                    volumeName: "USB Flash",
                                                    excludedVolumes: ["Time Machine"]),
               "a volume not on the exclusion list is offered for eject")
        expect(Defaults.sanitizedDiskExclusionList(["  Backup  ", "backup", "", "  ", "Photos", "PHOTOS"])
                == ["Backup", "Photos"],
               "sanitized disk exclusion list trims and deduplicates case-insensitively")
        expect(Defaults.registeredDefaults[DefaultsKey.diskEjectExcludedVolumes] is [String],
               "disk eject exclusions are registered as an empty string array")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.diskEjectExcludedVolumes),
               "disk eject exclusions travel in backups")
    }

    static func runMicrophone(expect: (Bool, String) -> Void) {
        // Muting every microphone, not just the one the Mac is set to: an app
        // pointed at a device of its own has to go silent too.
        expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Mixer")
                && !MicMuteSupport.isOwnDevice(name: "MacBook Air Microphone"),
               "the mute skips the app's own mixing device and no other")
        expect(!MicMuteSupport.shouldSaveVolume(nil)
                && !MicMuteSupport.shouldSaveVolume(0)
                && !MicMuteSupport.shouldSaveVolume(0.005)
                && MicMuteSupport.shouldSaveVolume(0.4),
               "a level worth restoring is remembered and a silent one never is")
        expect(MicMuteSupport.volumeToRestore(uid: "mic-a",
                                              saved: ["mic-a": 0.4, "mic-b": 0.9],
                                              legacy: 0.6) == 0.4
                && MicMuteSupport.volumeToRestore(uid: "mic-c",
                                                  saved: ["mic-a": 0.4],
                                                  legacy: 0.6) == 0.6
                && MicMuteSupport.volumeToRestore(uid: "mic-c", saved: [:], legacy: 0)
                    == MicMuteSupport.fallbackVolume
                && MicMuteSupport.volumeToRestore(uid: "mic-a",
                                                  saved: ["mic-a": 0],
                                                  legacy: 0) == MicMuteSupport.fallbackVolume,
               "each microphone gets its own level back, then the older single level, then a usable one")
        expect(MicMuteSupport.restoreTargets(recorded: ["mic-a", "gone"],
                                             present: ["mic-a", "mic-b"]) == ["mic-a"]
                && MicMuteSupport.restoreTargets(recorded: nil,
                                                 present: ["mic-a", "mic-b"]) == ["mic-a", "mic-b"]
                && MicMuteSupport.restoreTargets(recorded: [],
                                                 present: ["mic-a", "mic-b"]).isEmpty
                && MicMuteSupport.restoreTargets(recorded: ["mic-a"], present: []).isEmpty,
               "unmuting touches the microphones this app muted, every one with no record, and none when the record is empty")
    }

    static func runDiskExclusions(expect: (Bool, String) -> Void) {
        // MARK: A dropped identifier
        expect(QuickTogglesSupport.isExcluded(volumeName: "SD Card",
                                              volumeUUID: "1234-5678-ABCD",
                                              mountPath: "/Volumes/SD Card",
                                              excludedVolumes: ["1234-5678-abcd"])
                && !QuickTogglesSupport.isExcluded(volumeName: "SD Card",
                                                   volumeUUID: nil,
                                                   mountPath: "/Volumes/SD Card",
                                                   excludedVolumes: ["1234-5678-abcd"]),
               "an excluded volume UUID is honoured only when the caller hands the UUID over")
        let diskExclusionsListCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/DiskExclusionsList.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(diskExclusionsListCode.contains(".volumeUUIDStringKey")
                && diskExclusionsListCode.contains("QuickTogglesSupport.isExcluded("),
               "the exclusions picker asks the shared exclusion test, UUID included, not a name-only one")
    }
}
