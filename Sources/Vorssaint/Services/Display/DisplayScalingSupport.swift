// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A logical (point) size macOS can offer as a display mode.
struct ScaledResolution: Hashable, Comparable {
    let width: Int
    let height: Int

    static func < (lhs: ScaledResolution, rhs: ScaledResolution) -> Bool {
        (lhs.width, lhs.height) < (rhs.width, rhs.height)
    }
}

/// Who owns the override macOS reads for a display model.
enum DisplayScalingOverrideState: Equatable {
    case none
    /// Written by Vorssaint; `sizes` HiDPI point sizes.
    case vorssaint(sizes: Int)
    /// Placed by another app (BetterDisplay, SwitchResX) or by hand.
    case foreign(sizes: Int)
}

/// The override property list WindowServer reads for one display model, the
/// flexible resolution list Vorssaint offers through it, and the one-shot
/// administrator commands that install and remove it.
enum DisplayScalingSupport {
    static let overridesDirectory = "/Library/Displays/Contents/Resources/Overrides"
    /// Marks a file Vorssaint wrote. WindowServer ignores keys it does not know.
    static let managedKey = "VorssaintManaged"
    static let scaleResolutionsKey = "scale-resolutions"
    /// The trailing words macOS uses in a 16-byte entry to mark a HiDPI mode.
    static let hiDPIFlags: [UInt32] = [0x0000_0009, 0x0020_0000]

    /// Narrower than this the panel is not worth scaling (and the list
    /// would start below 720p points).
    static let minimumNativeWidth = 1_280
    /// The 2x backing store of the largest size stays inside what current
    /// Apple silicon GPUs scan out (8K wide).
    static let maximumBackingDimension = 8_192
    static let defaultMinimumPercent = 50

    // MARK: - Paths

    static func directoryPath(vendorID: UInt32) -> String {
        "\(overridesDirectory)/DisplayVendorID-\(String(vendorID, radix: 16))"
    }

    static func overridePath(vendorID: UInt32, productID: UInt32) -> String {
        "\(directoryPath(vendorID: vendorID))/DisplayProductID-\(String(productID, radix: 16))"
    }

    /// Where a foreign override waits while Vorssaint's replaces it.
    static func originalPath(vendorID: UInt32, productID: UInt32) -> String {
        overridePath(vendorID: vendorID, productID: productID) + ".vorssaint-original"
    }

    // MARK: - Resolutions

    /// Every point size with the panel's aspect ratio from `minimumPercent` of
    /// the native size up to the native size itself, one step per percent of
    /// width, largest first. Each is offered at 2x, so text stays sharp at any
    /// scale the user picks.
    static func flexibleResolutions(nativeWidth: Int, nativeHeight: Int,
                                    minimumPercent: Int = defaultMinimumPercent) -> [ScaledResolution] {
        guard nativeWidth >= minimumNativeWidth, nativeHeight > 0,
              (1...100).contains(minimumPercent) else { return [] }
        var seen = Set<ScaledResolution>()
        var sizes: [ScaledResolution] = []
        for percent in stride(from: 100, through: minimumPercent, by: -1) {
            let width = Int((Double(nativeWidth) * Double(percent) / 100).rounded())
            let height = Int((Double(width) * Double(nativeHeight) / Double(nativeWidth)).rounded())
            let size = ScaledResolution(width: width, height: height)
            guard fitsBacking(size), seen.insert(size).inserted else { continue }
            sizes.append(size)
        }
        return sizes
    }

    /// How big a "looks like" size is next to the native panel, by width:
    /// 2442 points on a 3440-pixel-wide panel is 71 %.
    static func percentOfNative(_ size: ScaledResolution, nativeWidth: Int) -> Int {
        guard nativeWidth > 0 else { return 0 }
        return Int((Double(size.width) * 100 / Double(nativeWidth)).rounded())
    }

    /// Sizes with the panel's own shape. Others would letterbox or stretch, so
    /// the slider leaves them to System Settings.
    static func matchesNativeAspect(_ size: ScaledResolution, nativeWidth: Int, nativeHeight: Int) -> Bool {
        guard size.height > 0, nativeHeight > 0 else { return false }
        let native = Double(nativeWidth) / Double(nativeHeight)
        return abs(Double(size.width) / Double(size.height) - native) / native < 0.01
    }

    /// The slider stop for `current`, or the nearest one when the display runs
    /// a size the list does not hold.
    static func sliderIndex(of current: ScaledResolution?, in sizes: [ScaledResolution]) -> Int? {
        guard let current, !sizes.isEmpty else { return nil }
        return sizes.indices.min { abs(sizes[$0].width - current.width) < abs(sizes[$1].width - current.width) }
    }

    static func fitsBacking(_ size: ScaledResolution) -> Bool {
        size.width > 0 && size.height > 0
            && size.width * 2 <= maximumBackingDimension
            && size.height * 2 <= maximumBackingDimension
    }

    // MARK: - Property list

    /// Three entries per size, in the order macOS lists them: the HiDPI mode
    /// (a 2x backing store shown as `width x height` points), the same pixel
    /// size as a plain mode, and the low-resolution mode at `width x height`.
    /// Each word is a big-endian UInt32.
    static func scaleResolutionEntries(_ sizes: [ScaledResolution]) -> [Data] {
        var seen = Set<Data>()
        var entries: [Data] = []
        func add(_ words: [UInt32]) {
            let data = encode(words)
            if seen.insert(data).inserted { entries.append(data) }
        }
        for size in sizes where fitsBacking(size) {
            let doubledWidth = UInt32(size.width * 2), doubledHeight = UInt32(size.height * 2)
            add([doubledWidth, doubledHeight] + hiDPIFlags)
            add([doubledWidth, doubledHeight])
            add([UInt32(size.width), UInt32(size.height)])
        }
        return entries
    }

    static func overrideData(vendorID: UInt32, productID: UInt32,
                             sizes: [ScaledResolution]) -> Data? {
        let entries = scaleResolutionEntries(sizes)
        guard vendorID != 0, productID != 0, !entries.isEmpty else { return nil }
        let plist: [String: Any] = [
            "DisplayVendorID": Int(vendorID),
            "DisplayProductID": Int(productID),
            scaleResolutionsKey: entries,
            managedKey: true,
        ]
        return try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// What an existing override (from `Data(contentsOf:)`, nil when absent)
    /// means for this model.
    static func state(ofOverride plist: Data?) -> DisplayScalingOverrideState {
        guard let plist else { return .none }
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil),
              let dictionary = object as? [String: Any] else { return .foreign(sizes: 0) }
        let sizes = hiDPIResolutions(in: dictionary).count
        return dictionary[managedKey] as? Bool == true ? .vorssaint(sizes: sizes) : .foreign(sizes: sizes)
    }

    static func hiDPIResolutions(in dictionary: [String: Any]) -> [ScaledResolution] {
        guard let entries = dictionary[scaleResolutionsKey] as? [Data] else { return [] }
        return entries.compactMap { entry -> ScaledResolution? in
            let words = decode(entry)
            guard words.count == 4, Array(words[2...]) == hiDPIFlags else { return nil }
            return ScaledResolution(width: Int(words[0] / 2), height: Int(words[1] / 2))
        }
    }

    static func encode(_ words: [UInt32]) -> Data {
        var data = Data(capacity: words.count * 4)
        for word in words {
            withUnsafeBytes(of: word.bigEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decode(_ data: Data) -> [UInt32] {
        guard data.count % 4 == 0 else { return [] }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            bytes[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
    }

    // MARK: - Administrator commands

    /// One `do shell script` body that installs the override. The property list
    /// travels inside the command as base64, so root never reads a file the
    /// user could swap mid-write; every path is built from integers. A foreign
    /// override is moved aside, never deleted, and only when no earlier one is
    /// already waiting there.
    static func installCommand(vendorID: UInt32, productID: UInt32, plist: Data) -> String? {
        guard vendorID != 0, productID != 0, !plist.isEmpty else { return nil }
        let directory = directoryPath(vendorID: vendorID)
        let file = overridePath(vendorID: vendorID, productID: productID)
        let original = originalPath(vendorID: vendorID, productID: productID)
        let staged = file + ".vorssaint-new"
        return [
            "/bin/mkdir -p '\(directory)'",
            "/bin/chmod 0755 '\(directory)'",
            "{ [ ! -f '\(file)' ] || /usr/bin/grep -q \(managedKey) '\(file)' || [ -e '\(original)' ] || /bin/mv '\(file)' '\(original)'; }",
            "/usr/bin/printf %s '\(plist.base64EncodedString())' | /usr/bin/base64 -D -o '\(staged)'",
            "/usr/bin/plutil -lint -s '\(staged)'",
            "/usr/sbin/chown root:wheel '\(staged)'",
            "/bin/chmod 0644 '\(staged)'",
            "/bin/mv -f '\(staged)' '\(file)'",
        ].joined(separator: " && ") + " || { /bin/rm -f '\(staged)'; exit 1; }"
    }

    /// Removes Vorssaint's override and puts back the one it moved aside.
    /// Leaves any file Vorssaint did not write exactly where it is.
    static func removeCommand(vendorID: UInt32, productID: UInt32) -> String? {
        guard vendorID != 0, productID != 0 else { return nil }
        let directory = directoryPath(vendorID: vendorID)
        let file = overridePath(vendorID: vendorID, productID: productID)
        let original = originalPath(vendorID: vendorID, productID: productID)
        return [
            "if [ -f '\(file)' ] && /usr/bin/grep -q \(managedKey) '\(file)'; then /bin/rm -f '\(file)' || exit 1; fi",
            "if [ -f '\(original)' ] && [ ! -e '\(file)' ]; then /bin/mv '\(original)' '\(file)' || exit 1; fi",
            "/bin/rmdir '\(directory)' 2>/dev/null",
            "exit 0",
        ].joined(separator: "; ")
    }
}
