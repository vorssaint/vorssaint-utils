// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Flexible scaling builds the override macOS reads and the administrator
/// commands that place it. Pure values only: nothing here touches /Library.
enum DisplayScalingTests {
    static func run(_ suite: TestSuite) {
        typealias Support = DisplayScalingSupport

        // A 3440x1440 ultrawide, 50 % to 100 % of native: the same 51 sizes
        // macOS lists for this panel when another scaling tool configures it.
        let ultrawide = Support.flexibleResolutions(nativeWidth: 3440, nativeHeight: 1440)
        suite.expect(ultrawide.count == 51
                && ultrawide.first == ScaledResolution(width: 3440, height: 1440)
                && ultrawide.last == ScaledResolution(width: 1720, height: 720)
                && ultrawide.contains(ScaledResolution(width: 3371, height: 1411))
                && ultrawide.contains(ScaledResolution(width: 2442, height: 1022)),
               "flexible scaling offers every native-aspect size from half to full native, one percent apart")
        suite.expect(ultrawide == ultrawide.sorted(by: >) && Set(ultrawide).count == ultrawide.count,
               "the size list is largest first without duplicates")
        suite.expect(Support.flexibleResolutions(nativeWidth: 1024, nativeHeight: 768).isEmpty
                && Support.flexibleResolutions(nativeWidth: 3440, nativeHeight: 1440, minimumPercent: 0).isEmpty,
               "a panel too small to scale, or a nonsensical range, gets no list")
        suite.expect(Support.flexibleResolutions(nativeWidth: 7680, nativeHeight: 4320)
                    .allSatisfy { $0.width * 2 <= 8_192 && $0.height * 2 <= 8_192 },
               "no size needs a backing store wider than the GPU scans out")

        // The resolution slider.
        let current = ScaledResolution(width: 2442, height: 1022)
        suite.expect(Support.percentOfNative(current, nativeWidth: 3440) == 71
                && Support.percentOfNative(ScaledResolution(width: 3440, height: 1440), nativeWidth: 3440) == 100
                && Support.percentOfNative(current, nativeWidth: 0) == 0,
               "the slider reads 2442 x 1022 on a 3440-wide panel as 71 % of native")
        suite.expect(Support.matchesNativeAspect(current, nativeWidth: 3440, nativeHeight: 1440)
                && !Support.matchesNativeAspect(ScaledResolution(width: 2560, height: 1440),
                                                nativeWidth: 3440, nativeHeight: 1440),
               "only sizes with the panel's own shape become slider stops")
        let ascending = ultrawide.sorted()
        suite.expect(Support.sliderIndex(of: current, in: ascending).map { ascending[$0] } == current
                && Support.sliderIndex(of: ScaledResolution(width: 2440, height: 1021), in: ascending)
                    .map { ascending[$0] } == current
                && Support.sliderIndex(of: current, in: []) == nil
                && Support.sliderIndex(of: nil, in: ascending) == nil,
               "the slider sits on the current size, or the nearest stop when it is not listed")

        // Encoding: three entries per size, big-endian words.
        let size = ScaledResolution(width: 2442, height: 1022)
        let entries = Support.scaleResolutionEntries([size])
        suite.expect(entries == [
                    Data([0x00, 0x00, 0x13, 0x14, 0x00, 0x00, 0x07, 0xFC,
                          0x00, 0x00, 0x00, 0x09, 0x00, 0x20, 0x00, 0x00]),
                    Data([0x00, 0x00, 0x13, 0x14, 0x00, 0x00, 0x07, 0xFC]),
                    Data([0x00, 0x00, 0x09, 0x8A, 0x00, 0x00, 0x03, 0xFE]),
                ],
               "each size becomes a HiDPI entry, its pixel twin and its low-resolution twin")
        let allEntries = Support.scaleResolutionEntries(ultrawide)
        suite.expect(allEntries.count == 152 && Set(allEntries).count == 152
                && allEntries.filter { $0.count == 16 }.count == 51,
               "a full ultrawide list shares twins between neighbours instead of repeating them")
        suite.expect(Support.decode(Support.encode([0x1314, 0x07FC, 9, 0x0020_0000])) == [0x1314, 0x07FC, 9, 0x0020_0000]
                && Support.decode(Data([1, 2, 3])).isEmpty,
               "words round-trip and a truncated entry decodes to nothing")

        // Ownership of an existing override.
        let ours = Support.overrideData(vendorID: 0x10AC, productID: 0xA1E3, sizes: ultrawide)
        suite.expect(Support.state(ofOverride: ours) == .vorssaint(sizes: 51),
               "an override Vorssaint wrote reads back as its own, with every HiDPI size")
        let foreignPlist = try? PropertyListSerialization.data(
            fromPropertyList: ["DisplayVendorID": 0x10AC, "DisplayProductID": 0xA1E3,
                               "scale-resolutions": Support.scaleResolutionEntries(Array(ultrawide.prefix(3)))],
            format: .binary, options: 0)
        suite.expect(Support.state(ofOverride: foreignPlist) == .foreign(sizes: 3)
                && Support.state(ofOverride: Data("not a plist".utf8)) == .foreign(sizes: 0)
                && Support.state(ofOverride: nil) == .none,
               "another tool's override, or an unreadable one, is never mistaken for Vorssaint's")
        suite.expect(Support.overrideData(vendorID: 0, productID: 1, sizes: ultrawide) == nil
                && Support.overrideData(vendorID: 1, productID: 1, sizes: []) == nil,
               "no override is built without a real model or any size")

        // Paths and administrator commands.
        suite.expect(Support.overridePath(vendorID: 0x10AC, productID: 0xA1E3)
                == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a1e3",
               "the override lands where WindowServer looks, with lowercase hex names")
        let install = Support.installCommand(vendorID: 0x10AC, productID: 0xA1E3, plist: ours ?? Data()) ?? ""
        let base64 = ours?.base64EncodedString() ?? "missing"
        suite.expect(install.contains("'\(base64)'")
                && install.contains("/usr/bin/plutil -lint -s")
                && install.contains("/usr/sbin/chown root:wheel")
                && install.contains("/bin/mv '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a1e3' '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a1e3.vorssaint-original'"),
               "installing carries the plist inline, checks it, makes it root-owned and moves a foreign one aside")
        suite.expect(!install.contains("rm -rf") && !install.contains("/bin/rm -f '/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-10ac/DisplayProductID-a1e3'"),
               "installing never deletes an existing override")
        let remove = Support.removeCommand(vendorID: 0x10AC, productID: 0xA1E3) ?? ""
        suite.expect(remove.contains("/usr/bin/grep -q VorssaintManaged")
                && remove.contains(".vorssaint-original")
                && !remove.contains("rm -rf"),
               "removing deletes only Vorssaint's own file and restores the one it replaced")
        suite.expect(Support.installCommand(vendorID: 0, productID: 1, plist: Data([1])) == nil
                && Support.removeCommand(vendorID: 1, productID: 0) == nil,
               "no command is built for an unidentified display")
        let base64Alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        suite.expect(base64.unicodeScalars.allSatisfy(base64Alphabet.contains),
               "the inline payload cannot break out of its single quotes")
    }
}
