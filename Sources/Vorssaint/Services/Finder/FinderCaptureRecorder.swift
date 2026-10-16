// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Combine

/// A user-started microphone or camera recording. Device/session work is
/// serialized, and publication waits for AVFoundation's file-finished callback.
/// Public controls/published properties are main-thread-only. Capture state is
/// queue-only. A request token is assigned before dispatch and remains stable
/// until completion publishes an idle state; its cancellation is lock-protected.
final class FinderCaptureRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum State: Equatable {
        case idle, preparing, recording, finishing, saved(URL), failed(String)
        var isBusy: Bool {
            switch self { case .preparing, .recording, .finishing: return true; default: return false }
        }
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var previewSession: AVCaptureSession?
    private let queue = DispatchQueue(label: "com.vorssaint.finder-recording", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var output: AVCaptureFileOutput?
    private var staged: URL?
    private var destination: URL?
    private var stopRequested = false
    private var cancellation = FinderToolsCancellation()

    func start(video: Bool, microphone: Bool, destination: URL) {
        precondition(Thread.isMainThread)
        guard AppFeature.finderTools.isAvailable, !state.isBusy else { return }
        state = .preparing
        let cancellation = FinderToolsCancellation()
        self.cancellation = cancellation
        Task {
            do {
                try cancellation.check()
                if video { try await Self.authorize(.video) }
                if microphone || !video { try await Self.authorize(.audio) }
                try cancellation.check()
                queue.async { [self] in
                    do { try configure(video: video, microphone: microphone || !video, destination: destination, cancellation: cancellation) }
                    catch { complete(error: error) }
                }
            } catch {
                queue.async { [self] in complete(error: error) }
            }
        }
    }

    func stop(discard: Bool = false) {
        precondition(Thread.isMainThread)
        guard state.isBusy else { return }
        if discard || state == .preparing { cancellation.cancel() }
        state = .finishing
        queue.async { [self] in
            stopRequested = true
            if output?.isRecording == true { output?.stopRecording() }
        }
    }

    private static func authorize(_ type: AVMediaType) async throws {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: type) else { throw CocoaError(.fileReadNoPermission) }
        default: throw CocoaError(.fileReadNoPermission)
        }
    }

    private func configure(video: Bool, microphone: Bool, destination: URL,
                           cancellation: FinderToolsCancellation) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        try cancellation.check()
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FinderFileActionError.destinationExists(destination)
        }
        self.destination = destination
        staged = try MediaSupport.temporaryOutputURL(for: destination)
        stopRequested = false
        let session = AVCaptureSession()
        self.session = session
        session.beginConfiguration()
        if video, session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        do {
            for type: AVMediaType in ([video ? .video : nil, microphone ? .audio : nil].compactMap { $0 }) {
                guard let device = AVCaptureDevice.default(for: type) else {
                    throw FinderFileActionError.invalidRequest("No capture device is available for the selected source.")
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
                session.addInput(input)
            }
            let output: AVCaptureFileOutput = video ? AVCaptureMovieFileOutput() : AVCaptureAudioFileOutput()
            guard session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
            session.addOutput(output)
            self.output = output
            output.minFreeDiskSpaceLimit = 50 * 1024 * 1024
            if let audio = output as? AVCaptureAudioFileOutput {
                guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(.m4a) else { throw CocoaError(.featureUnsupported) }
                audio.audioSettings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 128_000]
            }
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }
        try cancellation.check()
        if video { DispatchQueue.main.async { self.previewSession = session } }
        session.startRunning()
        try cancellation.check()
        guard session.isRunning, let output, let staged else { throw CocoaError(.featureUnsupported) }
        if let audio = output as? AVCaptureAudioFileOutput {
            audio.startRecording(to: staged, outputFileType: .m4a, recordingDelegate: self)
        } else { output.startRecording(to: staged, recordingDelegate: self) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { [self] in
            guard self.output === output else { return }
            do { try cancellation.check() }
            catch { stopRequested = true }
            if stopRequested { output.stopRecording() }
            else { DispatchQueue.main.async { self.state = .recording } }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async { [self] in
            guard self.output === output else { return }
            let finishedSuccessfully = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            complete(error: finishedSuccessfully ? nil : error)
        }
    }

    private func complete(error: Error?) {
        dispatchPrecondition(condition: .onQueue(queue))
        session?.stopRunning()
        session = nil
        output = nil
        let outcome: State
        do {
            try cancellation.check()
            if let error { throw error }
            guard let staged, let destination else { throw CocoaError(.fileWriteUnknown) }
            try MediaSupport.installStagedOutput(staged, at: destination, replacingExisting: false)
            outcome = .saved(destination)
        } catch is CancellationError { outcome = .idle }
        catch { outcome = .failed(error.localizedDescription) }
        if let staged { MediaSupport.discardStagedOutput(staged) }
        staged = nil
        destination = nil
        stopRequested = false
        DispatchQueue.main.async {
            self.previewSession = nil
            self.state = outcome
            Permissions.shared.refresh()
        }
    }
}
