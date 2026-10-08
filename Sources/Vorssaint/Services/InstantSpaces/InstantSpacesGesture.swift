// SPDX-License-Identifier: MPL-2.0 OR GPL-3.0-or-later
// Copyright (C) 2026 Yaël Guilloux & Valerian Saliou and Space Rabbit contributors
// Modifications Copyright (C) 2026 Vorssaint
// Adapted from Space Rabbit (54d6eb4), App/SpaceSwitching.swift and PrivateAPI.swift.
// Distributed with Vorssaint under MPL-2.0 and GPL-3.0-or-later, under MPL
// section 3.3. Recipients may use this file under either license.
// See Resources/Licenses/SpaceRabbit.txt.

import CoreGraphics
import Darwin
import Foundation

/// The private DockSwipe wire format is isolated here. Prepare every phase
/// before posting, so an allocation or serialization failure leaves native
/// input untouched instead of opening an unfinished gesture in the Dock.
enum InstantSpacesGesture {
    static let marker: Int64 = 0x5653_5350 // VSSP
    static let augmented = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    static var isSupported: Bool {
        (15...27).contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    private static let kIOHIDEventTypeDockSwipe: Int64 = 23
    private static let kCGSEventDockControl: Int64 = 30
    private static let kCGSGesturePhaseBegan: Int64 = 1
    private static let kCGSGesturePhaseEnded: Int64 = 4
    private static let kGestureMotionHorizontal: Int64 = 1
    private static let kMissionControlEpsilon = 1.0 / 65536.0
    private static let kIOHIDGestureFlavorDockPrimary: UInt16 = 3
    private static let kIOHIDFluidTouchGestureDataSize: UInt32 = 40
    private static let kIOHIDVelocityEventDataSize: UInt32 = 28
    private static let kIOHIDEventTypeFluidTouchGesture: UInt32 = 23
    private static let kIOHIDEventTypeVelocity: UInt32 = 9

    private static func augmentedHorizontalSign(isRight: Bool) -> Double {
        let natural = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                                kCFPreferencesAnyApplication) as? Bool ?? true
        let inverted = earlyBeta || natural
        return (isRight != inverted) ? 1 : -1
    }

    // Only early macOS 27.0 seeds ignored Natural scrolling. The release's
    // lower build number (26A428) must not be mistaken for an earlier beta.
    private static let earlyBeta: Bool = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return false }
        let build = String(cString: bytes)
        guard build.hasPrefix("26A"),
              let number = Int(build.dropFirst(3).prefix(while: { $0.isNumber })) else { return false }
        return (5000..<5416).contains(number)
    }()

    static func events(direction: Int) -> [CGEvent]? {
        guard isSupported, direction == -1 || direction == 1 else { return nil }
        if augmented {
            CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                     kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        var events: [CGEvent] = []
        for phase: Int64 in augmented ? [1, 2, 4] : [1, 4] {
            let dock: CGEvent
            if augmented {
                guard let raw = makeAugmentedDockEvent(phase: phase, isRight: direction > 0,
                                                       velocity: 9999),
                      let rebuilt = augmentDockSwipeEvent(raw) else { return nil }
                dock = rebuilt
            } else {
                guard let raw = CGEvent(source: nil) else { return nil }
                dock = raw
                dock.setIntegerValueField(kCGSEventTypeField, value: 30)
                dock.setIntegerValueField(kCGEventGestureHIDType, value: 23)
                dock.setIntegerValueField(kCGEventGesturePhase, value: phase)
                dock.setIntegerValueField(kCGEventScrollGestureFlagBits, value: direction > 0 ? 1 : 0)
                dock.setIntegerValueField(kCGEventGestureSwipeMotion, value: 1)
                dock.setDoubleValueField(kCGEventGestureZoomDeltaX, value: Double(Float.leastNonzeroMagnitude))
                if phase == 4 {
                    dock.setDoubleValueField(kCGEventGestureSwipeProgress, value: Double(direction) * 2)
                    dock.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: Double(direction) * 400)
                }
            }
            guard let envelope = CGEvent(source: nil) else { return nil }
            envelope.setIntegerValueField(kCGSEventTypeField, value: 29)
            for event in [dock, envelope] {
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                events.append(event)
            }
        }
        return events
    }

    static func cleanup(_ event: CGEvent) -> CGEvent? {
        guard let copy = event.copy() else { return nil }
        copy.setDoubleValueField(kCGEventGestureSwipeProgress, value: 0)
        copy.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: 0)
        copy.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 0)
        return augmented ? augmentDockSwipeEvent(copy, mayCarryExistingPayload: true) : copy
    }
    private static let kCGSEventTypeField            = CGEventField(rawValue: 55)!
    private static let kCGEventGestureHIDType        = CGEventField(rawValue: 110)!
    private static let kCGEventGestureScrollY        = CGEventField(rawValue: 119)!
    private static let kCGEventGestureSwipeMotion    = CGEventField(rawValue: 123)!
    private static let kCGEventGestureSwipeProgress  = CGEventField(rawValue: 124)!
    private static let kCGEventGestureSwipeVelocityX = CGEventField(rawValue: 129)!
    private static let kCGEventGestureSwipeVelocityY = CGEventField(rawValue: 130)!
    private static let kCGEventGesturePhase          = CGEventField(rawValue: 132)!
    private static let kCGEventScrollGestureFlagBits = CGEventField(rawValue: 135)!
    private static let kCGEventGestureZoomDeltaX     = CGEventField(rawValue: 139)!
    private static let kCGEventGestureSwipeMask      = CGEventField(rawValue: 115)!
    private static let kCGEventGesturePositionX      = CGEventField(rawValue: 125)!
    private static let kCGEventGesturePositionY      = CGEventField(rawValue: 126)!
    private static let kCGEventGesturePhase2         = CGEventField(rawValue: 134)!
    private static let kCGEventGestureFlavor         = CGEventField(rawValue: 138)!
    private static let kCGEventGestureTimestamp      = CGEventField(rawValue: 169)!
    private static let kCGEventIOHIDPayloadField: UInt16 = 4205

    private static func doubleToFixed1616(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }

        let scaled  = (value * 65536.0).rounded(.towardZero)
        let clamped = min(max(scaled, Double(Int32.min)), Double(Int32.max))
        let fixed   = Int32(clamped)

        if fixed == 0 && value != 0.0 { return value > 0.0 ? 1 : -1 }
        return fixed
    }

    private static func generateIOHIDPayload(from event: CGEvent) -> Data {
        let phase     = event.getIntegerValueField(kCGEventGesturePhase)
        let motion    = event.getIntegerValueField(kCGEventGestureSwipeMotion)
        let progress  = event.getDoubleValueField(kCGEventGestureSwipeProgress)
        let posX      = event.getDoubleValueField(kCGEventGesturePositionX)
        let posY      = event.getDoubleValueField(kCGEventGesturePositionY)
        let velX      = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)
        let velY      = event.getDoubleValueField(kCGEventGestureSwipeVelocityY)
        let swipeMask = event.getIntegerValueField(kCGEventGestureSwipeMask)

        let includeVelocity = velX != 0.0 || velY != 0.0 || phase == kCGSGesturePhaseEnded

        var payload = Data()

        let timestamp = event.timestamp != 0 ? UInt64(event.timestamp) : mach_absolute_time()
        payload.appendLE(timestamp)                               // timestamp
        payload.appendLE(UInt64(0))                               // sender_id
        payload.appendLE(UInt32(0))                               // options
        payload.appendLE(UInt32(0))                               // attribute_length
        payload.appendLE(UInt32(includeVelocity ? 2 : 1))         // event_count

        payload.appendLE(kIOHIDFluidTouchGestureDataSize)         // base.size
        payload.appendLE(kIOHIDEventTypeFluidTouchGesture)        // base.type
        payload.appendLE(UInt32((phase & 0xFF) << 24))            // base.options: phase in high byte
        payload.appendLE(UInt8(0))                                // base.depth
        payload.append(contentsOf: [0, 0, 0])                     // base.reserved
        payload.appendLE(doubleToFixed1616(posX))                 // position_x
        payload.appendLE(doubleToFixed1616(posY))                 // position_y
        payload.appendLE(Int32(0))                                // position_z
        payload.appendLE(UInt32(truncatingIfNeeded: swipeMask))   // swipe_mask
        payload.appendLE(UInt16(truncatingIfNeeded: motion))      // gesture_motion
        payload.appendLE(kIOHIDGestureFlavorDockPrimary)          // gesture_flavor
        payload.appendLE(doubleToFixed1616(progress))             // swipe_progress

        if includeVelocity {
            payload.appendLE(kIOHIDVelocityEventDataSize)         // base.size
            payload.appendLE(kIOHIDEventTypeVelocity)             // base.type
            payload.appendLE(UInt32(0))                           // base.options
            payload.appendLE(UInt8(1))                            // base.depth
            payload.append(contentsOf: [0, 0, 0])                 // base.reserved
            payload.appendLE(doubleToFixed1616(velX))             // velocity_x
            payload.appendLE(doubleToFixed1616(velY))             // velocity_y
            payload.appendLE(Int32(0))                            // velocity_z
        }

        return payload
    }

    private static func augmentDockSwipeEvent(_ event: CGEvent,
                                       mayCarryExistingPayload: Bool = false) -> CGEvent? {
        guard let cfData = event.data else { return nil }
        let bytes = cfData as Data

        guard bytes.count >= 4,
              bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 2
        else { return nil }

        let payload = generateIOHIDPayload(from: event)
        let augmented: Data

        if let replaced = replacingBinaryField(kCGEventIOHIDPayloadField,
                                               in: bytes, with: payload) {
            augmented = replaced
        } else if mayCarryExistingPayload {
            return nil
        } else {
            guard let appended = appendingBinaryField(kCGEventIOHIDPayloadField,
                                                      to: bytes, with: payload)
            else { return nil }
            augmented = appended
        }

        return CGEvent(withDataAllocator: kCFAllocatorDefault, data: augmented as CFData)
    }

    private static func appendingBinaryField(_ fieldID: UInt16, to bytes: Data,
                                      with payload: Data) -> Data? {
        guard payload.count <= Int(UInt16.max) else { return nil }

        var result = bytes
        result.append(UInt8(payload.count >> 8))                  // payload length (BE)
        result.append(UInt8(payload.count & 0xFF))
        result.append(UInt8(fieldID >> 8))                        // binary tag is zero
        result.append(UInt8(fieldID & 0xFF))
        result.append(payload)
        return result
    }

    private static func replacingBinaryField(_ fieldID: UInt16, in bytes: Data,
                                      with payload: Data) -> Data? {
        let base = bytes.startIndex
        let end  = bytes.endIndex

        guard bytes.count >= 4 else { return nil }

        var result = Data(bytes.prefix(4))
        var offset = base + 4

        while offset < end {
            guard offset + 4 <= end else { return nil }

            let elementSize = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
            let tagAndField = (UInt16(bytes[offset + 2]) << 8) | UInt16(bytes[offset + 3])
            let tag = tagAndField >> 14
            let currentFieldID = tagAndField & 0x3FFF

            let valueSize: Int
            switch tag {
            case 0 where elementSize == 1: valueSize = 8
            case 0 where elementSize > 1: valueSize = Int(elementSize)
            case 1 where elementSize == 1: valueSize = 4
            case 3 where elementSize == 1: valueSize = 4
            case 3 where elementSize == 2: valueSize = 8
            default: return nil
            }

            let recordEnd = offset + 4 + valueSize
            guard recordEnd <= end else { return nil }
            if currentFieldID != fieldID {
                result.append(bytes.subdata(in: offset..<recordEnd))
            }
            offset = recordEnd
        }

        return appendingBinaryField(fieldID, to: result, with: payload)
    }

    private static func makeAugmentedDockEvent(phase: Int64, isRight: Bool,
                                        velocity: Double) -> CGEvent? {
        guard let ev = CGEvent(source: nil) else { return nil }

        let fullSign = augmentedHorizontalSign(isRight: isRight)
        let sign = phase == kCGSGesturePhaseBegan
            ? fullSign * kMissionControlEpsilon : fullSign

        ev.setIntegerValueField(kCGSEventTypeField,          value: kCGSEventDockControl)
        ev.setIntegerValueField(kCGEventGestureHIDType,      value: kIOHIDEventTypeDockSwipe)
        ev.setIntegerValueField(kCGEventGesturePhase,        value: phase)
        ev.setDoubleValueField(kCGEventGestureSwipeProgress, value: sign)
        ev.setIntegerValueField(kCGEventGestureSwipeMotion,  value: kGestureMotionHorizontal)
        ev.setIntegerValueField(kCGEventGesturePhase2,       value: phase)
        ev.setDoubleValueField(kCGEventGestureFlavor,        value: Double(kIOHIDGestureFlavorDockPrimary))
        ev.setDoubleValueField(kCGEventGestureTimestamp,     value: Double(mach_absolute_time()))
        ev.setDoubleValueField(kCGEventGesturePositionX,     value: 0.1)

        if phase == kCGSGesturePhaseEnded {
            ev.setDoubleValueField(kCGEventGestureSwipeVelocityX,
                                   value: fullSign * velocity)
        }
        return ev
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
