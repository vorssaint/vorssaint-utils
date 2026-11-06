// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

/// Runs the production stream callback with the tap and the writer replaced,
/// then settles the tap's trust as the session does when it stops. An app's
/// tap is built when the app first plays and made again as its processes
/// change, so the stream can hear the app before the tap can. A tap that
/// stays silent once it runs has lost its permission, which macOS answers
/// with silence rather than an error.
enum RecorderSystemAudioTrustTests {
    final class Tap {
        let hearsOneApp: Bool
        // The tap's own storage, so its atomic reads and writes run here too.
        let pipelineStarted = RecorderAudioHostTime()
        let ran = RecorderAudioFlag()
        var pipelineStart: UInt64 { pipelineStarted.value }
        var ranPipeline: Bool { ran.value }

        init(hearsOneApp: Bool) {
            self.hearsOneApp = hearsOneApp
        }

        func start(at hostTime: UInt64) {
            pipelineStarted.value = hostTime
            ran.raise()
        }
    }

    typealias RecorderSystemAudioTap = Tap

    class Fixture {
        let streamHeard = RecorderAudioFlag()
        let streamHeardSinceTap = RecorderAudioFlag()
        let tapReaderLost = RecorderAudioFlag()
        let systemAudioTap: Tap?
        let writesTapAudio: Bool
        private(set) var written: [RecorderCaptureEngine.Kind] = []

        init(tap: Tap?, trusted: Bool) {
            systemAudioTap = tap
            writesTapAudio = trusted
        }

        func append(_ sampleBuffer: CMSampleBuffer, kind: RecorderCaptureEngine.Kind) {
            written.append(kind)
        }
    }

    static func run(_ suite: TestSuite) {
        let engine = RecorderCaptureEngine()
        // Host clock times around one pipeline start, which the stream's
        // sound is retimed onto before the session sees it.
        let origin = CMTime(value: 1_000, timescale: 1)
        func at(_ seconds: Double) -> CMTime {
            origin + CMTime(seconds: seconds, preferredTimescale: 48_000)
        }
        func hostTime(_ seconds: Double) -> UInt64 {
            CMClockConvertHostTimeToSystemUnits(at(seconds))
        }
        func hear(_ session: Session, at times: [Double], sound: Bool = true) {
            for time in times {
                session.captureEngine(engine, didOutput: audio(at: at(time), sound: sound), of: .systemAudio)
            }
        }
        func trust(_ session: Session, _ tap: Tap, previously trusted: Bool) -> Bool {
            RecorderSupport.trustsSystemAudioTap(previously: trusted, tapHeardSound: false,
                                                 streamHeardSound: session.streamHeardSound(against: tap))
        }

        suite.expect(!RecorderSupport.streamSoundCountsAgainstTap(at: at(0.5), hearsOneApp: true,
                                                                   pipelineStart: hostTime(0))
                        && RecorderSupport.streamSoundCountsAgainstTap(at: at(0.51), hearsOneApp: true,
                                                                       pipelineStart: hostTime(0)),
                     "an app's tap answers for the stream's sound from half a second after its pipeline started")

        // A browser opens an audio helper when a video starts, so its tap is
        // made again around it: the stream hears the video while the old
        // pipeline is gone and before the new one has settled. The sound is
        // short and ends before the tap could hear it.
        let rebuiltTap = Tap(hearsOneApp: true)
        let rebuilt = Session(tap: rebuiltTap, trusted: true)
        rebuiltTap.start(at: hostTime(-5))
        hear(rebuilt, at: [-4, -1], sound: false)
        rebuiltTap.pipelineStarted.value = 0
        hear(rebuilt, at: [-0.3, -0.2])
        rebuiltTap.start(at: hostTime(0))
        hear(rebuilt, at: [-0.1, 0.2, 0.5])
        hear(rebuilt, at: [0.8, 3], sound: false)
        suite.expect(rebuilt.streamHeard.value && trust(rebuilt, rebuiltTap, previously: true),
                     "an app's tap made again mid recording keeps its trust when the stream's sound predates it")

        let revokedTap = Tap(hearsOneApp: true)
        revokedTap.start(at: hostTime(0))
        let revoked = Session(tap: revokedTap, trusted: true)
        hear(revoked, at: [0.2, 0.5])
        let trustedWhileSettling = trust(revoked, revokedTap, previously: true)
        hear(revoked, at: [0.6])
        suite.expect(trustedWhileSettling && !trust(revoked, revokedTap, previously: true),
                     "a trusted app tap that stays silent through sound the stream heard after it started loses its trust")
        // Joining late is no exemption for the rest of the recording.
        let lateTap = Tap(hearsOneApp: true)
        let late = Session(tap: lateTap, trusted: true)
        hear(late, at: [-0.4])
        lateTap.start(at: hostTime(0))
        hear(late, at: [0.3, 1, 2])
        suite.expect(!trust(late, lateTap, previously: true),
                     "a trusted app tap built late that then hears only silence loses its trust")
        // An app whose sound comes from a process its tap cannot tell apart
        // leaves the tap waiting through the whole recording.
        let waitingTap = Tap(hearsOneApp: true)
        let waiting = Session(tap: waitingTap, trusted: true)
        hear(waiting, at: [1, 2])
        suite.expect(!trust(waiting, waitingTap, previously: true),
                     "an app's tap that never ran is held to all of the stream's sound, as before")

        // Display and area recordings hear the whole Mac, whose tap answers
        // for all of the stream's sound, before its pipeline starts included.
        let displayTap = Tap(hearsOneApp: false)
        let display = Session(tap: displayTap, trusted: true)
        hear(display, at: [-0.2])
        let startedDisplayTap = Tap(hearsOneApp: false)
        startedDisplayTap.start(at: hostTime(0))
        let startedDisplay = Session(tap: startedDisplayTap, trusted: true)
        hear(startedDisplay, at: [-0.2, 0.1])
        let quietDisplay = Session(tap: displayTap, trusted: true)
        hear(quietDisplay, at: [1, 2], sound: false)
        suite.expect(!trust(display, displayTap, previously: true)
                        && !trust(startedDisplay, startedDisplayTap, previously: true)
                        && trust(quietDisplay, displayTap, previously: true),
                     "display and area recordings hold the tap to all of the stream's sound, as before")

        let untrusted = Session(tap: Tap(hearsOneApp: true), trusted: false)
        hear(untrusted, at: [0.1, 0.2])
        untrusted.captureEngine(engine, didOutput: audio(at: at(0.3), sound: false), of: .video)
        suite.expect(revoked.written.isEmpty && display.written.isEmpty
                        && untrusted.written == [.systemAudio, .systemAudio, .video],
                     "the stream's sound is written only while the tap's is not")

        // The tap's pipeline is Core Audio, so its bookkeeping is read as
        // source text.
        let tapSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/RecorderSystemAudioTap.swift",
            encoding: .utf8)) ?? ""
        let started = ["        self.sampleRate = sampleRate\n", "        pipelineStarted.value = mach_absolute_time()\n",
                       "        ran.raise()\n"].joined()
        suite.expect(tapSource.contains("var hearsOneApp: Bool { pid != nil }")
                        && tapSource.contains("var pipelineStart: UInt64 { pipelineStarted.value }")
                        && tapSource.contains("var ranPipeline: Bool { ran.value }")
                        && tapSource.contains(started)
                        && tapSource.contains("        hostDeviceUID = nil\n        pipelineStarted.value = 0\n"),
                     "the tap marks when each pipeline starts, reports it and forgets it when the pipeline goes")
    }

    /// A tenth of a second of the stream's stereo float sound, silent or not.
    static func audio(at time: CMTime, sound: Bool) -> CMSampleBuffer {
        let frames = 4_800
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description) == noErr)
        var samples = [Float](repeating: 0, count: frames * 2)
        if sound { samples[frames] = 0.25 }
        let bytes = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
            blockBufferOut: &block) == noErr)
        precondition(samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!,
                                          offsetIntoDestination: 0, dataLength: bytes)
        } == noErr)
        var buffer: CMSampleBuffer?
        precondition(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: block!, formatDescription: description!, sampleCount: frames,
            presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &buffer) == noErr)
        return buffer!
    }
}
