// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import CoreAudio
import Foundation
import SwiftUI

// MARK: - Guidance Mode

enum GuidanceMode: String, CaseIterable, Identifiable {
    case wordTracking
    case classic
    case voiceActivated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wordTracking:   return "Word Tracking"
        case .classic:        return "Classic"
        case .voiceActivated: return "Voice-Activated"
        }
    }

    var subtitle: String {
        switch self {
        case .wordTracking:   return "Highlights words as you speak"
        case .classic:        return "Scrolls at a steady pace"
        case .voiceActivated: return "Scrolls while speaking, pauses on silence"
        }
    }

    var icon: String {
        switch self {
        case .wordTracking:   return "waveform.and.mic"
        case .classic:        return "clock.arrow.circlepath"
        case .voiceActivated: return "mic.fill"
        }
    }
}

// MARK: - Typography & Styling Presets

enum TeleprompterFontSizePreset: String, CaseIterable, Identifiable {
    case xs, sm, lg, xl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .xs: return "XS"
        case .sm: return "SM"
        case .lg: return "LG"
        case .xl: return "XL"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .xs: return 14
        case .sm: return 16
        case .lg: return 20
        case .xl: return 24
        }
    }
}

enum TeleprompterFontFamilyPreset: String, CaseIterable, Identifiable {
    case sans, serif, mono, dyslexia

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sans:     return "Sans"
        case .serif:    return "Serif"
        case .mono:     return "Mono"
        case .dyslexia: return "Dyslexia"
        }
    }

    func font(ofSize size: CGFloat) -> Font {
        switch self {
        case .sans:
            return .system(size: size, design: .default)
        case .serif:
            return .system(size: size, design: .serif)
        case .mono:
            return .system(size: size, design: .monospaced)
        case .dyslexia:
            if NSFont(name: "OpenDyslexic3-Regular", size: size) != nil {
                return .custom("OpenDyslexic3-Regular", size: size)
            }
            return .system(size: size, design: .rounded)
        }
    }

    func nsFont(ofSize size: CGFloat) -> NSFont {
        switch self {
        case .sans:
            return .systemFont(ofSize: size)
        case .serif:
            return NSFont(descriptor: NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor, size: size) ?? .systemFont(ofSize: size)
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .dyslexia:
            return NSFont(name: "OpenDyslexic3-Regular", size: size)
                ?? NSFont(descriptor: NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.rounded) ?? NSFont.systemFont(ofSize: size).fontDescriptor, size: size)
                ?? .systemFont(ofSize: size)
        }
    }
}

enum TeleprompterHighlightColorPreset: String, CaseIterable, Identifiable {
    case white, yellow, green, blue, pink, orange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white:  return "White"
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        case .orange: return "Orange"
        }
    }

    var color: Color {
        switch self {
        case .white:  return .white
        case .yellow: return Color(red: 1.0, green: 0.85, blue: 0.2)
        case .green:  return Color(red: 0.3, green: 0.9, blue: 0.45)
        case .blue:   return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .pink:   return Color(red: 1.0, green: 0.4, blue: 0.7)
        case .orange: return Color(red: 1.0, green: 0.6, blue: 0.2)
        }
    }

    var hexString: String {
        switch self {
        case .white:  return "#FFFFFF"
        case .yellow: return "#FFD700"
        case .green:  return "#4CD964"
        case .blue:   return "#5AC8FA"
        case .pink:   return "#FF2D55"
        case .orange: return "#FF9500"
        }
    }
}

// MARK: - Cue Color & Brightness

enum TeleprompterCueColorPreset: String, CaseIterable, Identifiable {
    case yellow, cyan, purple, orange, green

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Yellow"
        case .cyan:   return "Cyan"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .green:  return "Green"
        }
    }

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.85, blue: 0.2)
        case .cyan:   return Color(red: 0.2, green: 0.8, blue: 1.0)
        case .purple: return Color(red: 0.75, green: 0.4, blue: 1.0)
        case .orange: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .green:  return Color(red: 0.3, green: 0.9, blue: 0.45)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        case .cyan:   return NSColor(calibratedRed: 0.2, green: 0.8, blue: 1.0, alpha: 1.0)
        case .purple: return NSColor(calibratedRed: 0.75, green: 0.4, blue: 1.0, alpha: 1.0)
        case .orange: return NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case .green:  return NSColor(calibratedRed: 0.3, green: 0.9, blue: 0.45, alpha: 1.0)
        }
    }
}

enum TeleprompterCueBrightness: String, CaseIterable, Identifiable {
    case dim, low, medium, bright

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dim:    return "Dim"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .bright: return "Bright"
        }
    }

    var alpha: CGFloat {
        switch self {
        case .dim:    return 0.35
        case .low:    return 0.55
        case .medium: return 0.80
        case .bright: return 1.00
        }
    }
}

// MARK: - Reading Options

enum TeleprompterReadingPosition: String, CaseIterable, Identifiable {
    case centered, nearTop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .centered: return "Centered"
        case .nearTop:  return "Near Top"
        }
    }
}

// MARK: - Audio Device

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    static func allInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }

        var result: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            var nameRef: CFString = "" as CFString
            let deviceName = read(deviceID, kAudioObjectPropertyName, &nameRef) ? (nameRef as String) : "Unknown Device"

            var uidRef: CFString = "" as CFString
            let deviceUID = read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) ? (uidRef as String) : "\(deviceID)"

            result.append(AudioInputDevice(id: deviceID, uid: deviceUID, name: deviceName))
        }
        return result
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allInputDevices().first(where: { $0.uid == uid })?.id
    }
}

// MARK: - CJK-aware word splitting

extension Unicode.Scalar {
    var isCJK: Bool {
        let v = value
        return (v >= 0x4E00 && v <= 0x9FFF)    // CJK Unified Ideographs
            || (v >= 0x3400 && v <= 0x4DBF)    // CJK Extension A
            || (v >= 0x20000 && v <= 0x2A6DF)  // CJK Extension B
            || (v >= 0xF900 && v <= 0xFAFF)    // CJK Compatibility Ideographs
            || (v >= 0x3040 && v <= 0x309F)    // Hiragana
            || (v >= 0x30A0 && v <= 0x30FF)    // Katakana
            || (v >= 0xAC00 && v <= 0xD7AF)    // Hangul Syllables
    }
}

/// Splits text into display-ready words. CJK characters (Chinese, Japanese, Korean)
/// are split into individual characters so the flow layout can wrap them properly.
func splitTextIntoWords(_ text: String) -> [String] {
    let tokens = text.replacingOccurrences(of: "\n", with: " ")
        .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        .map { String($0) }

    var result: [String] = []
    for token in tokens {
        guard token.unicodeScalars.contains(where: { $0.isCJK }) else {
            result.append(token)
            continue
        }
        var buffer = ""
        for char in token {
            if char.unicodeScalars.first.map({ $0.isCJK }) == true {
                if !buffer.isEmpty {
                    result.append(buffer)
                    buffer = ""
                }
                result.append(String(char))
            } else {
                buffer.append(char)
            }
        }
        if !buffer.isEmpty {
            result.append(buffer)
        }
    }
    return result
}

// MARK: - External Display Modes

enum ExternalDisplayMode: String, CaseIterable, Identifiable {
    case off
    case fullscreen
    case mirror

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:        return "Off"
        case .fullscreen: return "Second Monitor"
        case .mirror:     return "Mirror (Prompter Glass)"
        }
    }

    var icon: String {
        switch self {
        case .off:        return "display.slash"
        case .fullscreen: return "display.2"
        case .mirror:     return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        }
    }
}

enum ExternalMirrorAxis: String, CaseIterable, Identifiable {
    case horizontal
    case vertical
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical:   return "Vertical"
        case .both:       return "Both"
        }
    }
}

