// SPDX-License-Identifier: GPL-3.0-or-later
import AudioToolbox
import Foundation
import SoftwareVolumePCM

enum SoftwareVolumeFormatTests {
    enum HAL {}
    static func run(_ suite: TestSuite) {
        let layouts: [(UInt32, UInt32, UInt32)] = [
            (kAudioChannelLayoutTag_Stereo, 0, 2),
            (kAudioChannelLayoutTag_MPEG_5_1_A, 0, 6),
            (kAudioChannelLayoutTag_MPEG_7_1_A, 0, 8),
            (kAudioChannelLayoutTag_UseChannelBitmap, AudioChannelBitmap.bit_Left.rawValue | AudioChannelBitmap.bit_Right.rawValue, 2)
        ]
        for (tag, bitmap, channels) in layouts {
            let header: [UInt32] = [tag, bitmap, 0]
            let data = header.withUnsafeBytes { Data($0) }
            guard let expanded = HAL.normalizedLayout(data) else {
                suite.expect(false, "a standard Core Audio layout expands")
                continue
            }
            var format = vs_format_default(channels)
            let valid = expanded.withUnsafeBytes { vs_format_layout(&format, $0.baseAddress!, $0.count) }
            suite.expect(valid != 0, "expanded stereo/5.1/7.1/bitmap layout is accepted by the actual driver protocol")
        }
        suite.expect(HAL.normalizedLayout(Data(repeating: 0, count: 8)) == nil,
                     "truncated channel-layout metadata fails before reading its header")
        for language in AppLanguage.allCases {
            let stereo = VirtualOutputStrings.outputLayout(.init(labels: [1,2]), language: language)
            let surround = VirtualOutputStrings.outputLayout(.init(labels: [1,2,3,4,5,6]), language: language)
            suite.expect(!stereo.title.isEmpty && !stereo.help.isEmpty && surround.title == "5.1",
                         "active-layout badge is localized and preserves the standard channel notation")
        }
    }
}
