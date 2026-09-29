// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreMedia

enum RecorderSampleTiming {
    static func converted(_ sampleBuffer: CMSampleBuffer,
                          from sourceClock: CMClockOrTimebase,
                          to targetClock: CMClockOrTimebase) -> CMSampleBuffer? {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let target = CMSyncConvertTime(presentation, from: sourceClock, to: targetClock)
        return retimed(sampleBuffer, to: target)
    }

    /// Shift timestamps without changing the cadence. A timing entry's duration
    /// is per sample, even when that entry describes an entire PCM buffer.
    static func retimed(_ sampleBuffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentation.isNumeric, time.isNumeric else { return nil }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0,
            arrayToFill: nil, entriesNeededOut: &count) == noErr, count > 0 else { return nil }
        var timing = Array(repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
            arrayToFill: &timing, entriesNeededOut: nil) == noErr else { return nil }
        let offset = time - presentation
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isNumeric {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp + offset
            }
            if timing[index].decodeTimeStamp.isNumeric {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp + offset
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }
}
