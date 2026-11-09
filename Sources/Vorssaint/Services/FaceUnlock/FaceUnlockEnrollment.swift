// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import Combine
import Foundation

/// The head positions asked for while enrolling a face, in order. Five are
/// enough for a stable template without a long hold.
enum FaceUnlockPose: Int, CaseIterable {
    case center, left, right, up, down

    /// Stored with each sample so an identity records where it came from.
    var name: String {
        switch self {
        case .center: return "center"
        case .left: return "left"
        case .right: return "right"
        case .up: return "top"
        case .down: return "bottom"
        }
    }
}

/// What the person is told to do while the camera looks.
enum FaceUnlockEnrollmentHint: Equatable {
    case starting
    case pose(FaceUnlockPose)
    case noFace
    case tooFar
    case turnedTooFar
    case done
    case cameraProblem(FaceUnlockCameraError)
}

/// The pose bands, in radians. Vision reports a left turn as positive yaw and
/// looking up as negative pitch.
enum FaceUnlockPoseBands {
    static let yawInner: Float = 0.24
    static let yawCenter: Float = 0.18
    static let yawOuter: Float = 0.51
    static let pitchInner: Float = 0.17
    static let pitchCenter: Float = 0.15
    static let pitchOuter: Float = 0.37

    /// `factor` above 1 relaxes the bands, for a pose that is taking too long.
    static func matches(yaw: Float, pitch: Float, pose: FaceUnlockPose, factor: Float = 1) -> Bool {
        switch pose {
        case .center:
            return abs(yaw) < yawCenter * factor && abs(pitch) < pitchCenter * factor
        case .left:
            return yaw > yawInner / factor && yaw < yawOuter && abs(pitch) < pitchCenter * factor
        case .right:
            return yaw < -yawInner / factor && yaw > -yawOuter && abs(pitch) < pitchCenter * factor
        case .up:
            return pitch < -pitchInner / factor && pitch > -pitchOuter && abs(yaw) < yawCenter * factor
        case .down:
            return pitch > pitchInner / factor && pitch < pitchOuter && abs(yaw) < yawCenter * factor
        }
    }

    static func isExcessive(yaw: Float, pitch: Float) -> Bool {
        abs(yaw) >= yawOuter || abs(pitch) >= pitchOuter
    }
}

/// Runs one guided capture: the person looks at the camera and turns their
/// head as asked, and a sample is taken for each pose once it is held steady.
/// Nothing is stored until `commit`.
@MainActor
final class FaceUnlockEnrollment: ObservableObject {
    @Published private(set) var hint: FaceUnlockEnrollmentHint = .starting
    @Published private(set) var progress: Double = 0
    @Published private(set) var isComplete = false

    let camera = FaceUnlockCamera()

    private let samplesPerPose = 2
    private let requiredStreak = 3
    private let holdDuration: Duration = .milliseconds(500)
    private let qualityFloor: Float = 0.2
    private let settleDelay: Duration = .seconds(1.5)
    private let stallTimeout: Duration = .seconds(12)
    private let minimumFaceWidth: Float = 0.2

    private var task: Task<Void, Never>?
    private var samples: [FaceSample] = []
    private var poseIndex = 0
    private var capturedForPose = 0
    private var streak = 0
    private var poseStartedAt = ContinuousClock.now
    private var holdStartedAt: ContinuousClock.Instant?
    private var readyAt = ContinuousClock.now

    func start() {
        guard task == nil else { return }
        samples = []
        poseIndex = 0
        capturedForPose = 0
        streak = 0
        progress = 0
        isComplete = false
        hint = .starting
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        camera.stop()
    }

    private func run() async {
        await camera.start()
        if let error = camera.error {
            hint = .cameraProblem(error)
            camera.stop()
            task = nil
            return
        }
        readyAt = .now + settleDelay
        poseStartedAt = .now
        hint = .pose(.center)
        var lastFrame: UInt64?
        let pipeline = FaceUnlockService.shared.pipeline
        while !Task.isCancelled, !isComplete {
            guard let frame = camera.currentFrame, frame.id != lastFrame else {
                try? await Task.sleep(nanoseconds: 30_000_000)
                continue
            }
            lastFrame = frame.id
            let image = frame.image
            let width = minimumFaceWidth
            let outcome = await Task.detached(priority: .userInitiated) { () -> Frame in
                guard let faces = try? FaceDetector.detectFaces(in: image),
                      let face = FaceRecognitionPipeline.largestFace(in: faces) else { return .none }
                if Float(face.normalizedBoundingBox.width) < width { return .far }
                guard let result = try? pipeline.recognize(face, in: image) else { return .none }
                return .face(result)
            }.value
            handle(outcome)
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        camera.stop()
        task = nil
    }

    private enum Frame {
        case none, far
        case face(FaceRecognitionResult)
    }

    private func reset() {
        streak = 0
        holdStartedAt = nil
    }

    private func handle(_ frame: Frame) {
        guard let pose = FaceUnlockPose(rawValue: poseIndex) else { return }
        switch frame {
        case .none:
            hint = .noFace; reset(); return
        case .far:
            hint = .tooFar; reset(); return
        case .face(let result):
            guard let yaw = result.face.yaw, let pitch = result.face.pitch else {
                hint = .noFace; reset(); return
            }
            if FaceUnlockPoseBands.isExcessive(yaw: yaw, pitch: pitch) {
                hint = .turnedTooFar; reset(); return
            }
            hint = .pose(pose)
            guard ContinuousClock.now >= readyAt else { reset(); return }
            let widened = ContinuousClock.now - poseStartedAt > stallTimeout
            let matches = FaceUnlockPoseBands.matches(yaw: yaw, pitch: pitch, pose: pose,
                                                      factor: widened ? 1.25 : 1)
            let qualityOK = result.quality.map { $0 >= qualityFloor } ?? true
            // Only a five point alignment is canonical enough to enroll.
            guard matches, qualityOK, result.alignmentTier == .fivePoint else { reset(); return }
            if holdStartedAt == nil { holdStartedAt = .now }
            guard ContinuousClock.now - holdStartedAt! >= holdDuration else { return }
            streak += 1
            guard streak >= requiredStreak else { return }
            streak = 0
            samples.append(FaceSample(embedding: result.embedding, pose: pose.name,
                                      capturedAt: Date(), quality: result.quality))
            capturedForPose += 1
            guard capturedForPose >= samplesPerPose else { return }
            capturedForPose = 0
            poseIndex += 1
            poseStartedAt = .now
            holdStartedAt = nil
            progress = Double(poseIndex) / Double(FaceUnlockPose.allCases.count)
            if poseIndex >= FaceUnlockPose.allCases.count {
                isComplete = true
                hint = .done
            }
        }
    }

    /// Saves the capture as `name`, replacing the identity `existingID` when
    /// one is being recaptured. Needs the session to be unlocked.
    @discardableResult
    func commit(name: String, replacing existingID: UUID?) throws -> Bool {
        guard isComplete else { return false }
        let saved = try FaceEnrollmentStore.shared.commitEnrollment(
            replacing: existingID, name: name, samples: samples,
            embedder: FaceUnlockService.shared.pipeline.embedder)
        return saved != nil
    }
}
