// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import SwiftUI

/// Face Unlock's page: whether it is on, what is missing before it can work,
/// the saved password and enrolled faces, and how it behaves at the lock
/// screen. The scan itself is drawn by the island's padlock.
struct FaceUnlockSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FaceUnlockService.shared
    @ObservedObject private var store = FaceEnrollmentStore.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.faceUnlockEnabled) private var enabled = false
    @AppStorage(DefaultsKey.faceUnlockOnWake) private var onWake = true
    @AppStorage(DefaultsKey.faceUnlockOnLock) private var onLock = true
    @AppStorage(DefaultsKey.faceUnlockStrictness) private var strictness = FaceUnlockStrictness.standard.rawValue
    @AppStorage(DefaultsKey.faceUnlockLiveness) private var liveness = FaceUnlockLiveness.light.rawValue
    @AppStorage(DefaultsKey.faceUnlockScanSeconds) private var scanSeconds = FaceUnlockSupport.defaultScanSeconds
    @AppStorage(DefaultsKey.faceUnlockRetryOnce) private var retryOnce = false
    @AppStorage(DefaultsKey.faceUnlockShowOnLockScreen) private var showOnLockScreen = true
    @AppStorage(DefaultsKey.faceUnlockSessionLimit) private var sessionLimit = FaceUnlockSessionLimit.thirtyDays.rawValue
    @AppStorage(DefaultsKey.faceUnlockCameraID) private var cameraID = ""

    @State private var password = ""
    @State private var sessionOpen = FaceUnlockVault.isSessionUnlocked
    @State private var hasPassword = FaceUnlockVault.hasStoredPassword()
    @State private var blocker: FaceUnlockBlocker?
    @State private var busy = false
    @State private var message: String?
    @State private var enrollment: EnrollmentRequest?
    @State private var confirmRemoveAll = false
    @State private var cameras: [FaceUnlockCameraDevice] = []

    private struct EnrollmentRequest: Identifiable {
        let id = UUID()
        let replacing: FaceIdentity?
    }

    private var text: FaceUnlockFeatureStrings { FeatureStrings.faceUnlock(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                cautionCard
                if enabled { statusCard }
                setupCard
                facesCard
                recognitionCard
                lockScreenCard
                removeCard
            }
            .padding(22)
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .faceUnlockSessionDidChange)) { _ in refresh() }
        .sheet(item: $enrollment) { request in
            FaceUnlockEnrollmentSheet(replacing: request.replacing) { enrollment = nil; refresh() }
        }
        .confirmationDialog(text.removeAllTitle, isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button(text.removeAll, role: .destructive, action: removeEverything)
            Button(text.cancel, role: .cancel) {}
        } message: {
            Text(text.removeAllMessage)
        }
    }

    // MARK: - Header and status

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text.title).font(.title2.bold())
                Text(text.hint).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(text.title, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                .accessibilityLabel(text.title)
                .onChange(of: enabled) { _, _ in apply() }
        }
    }

    private var cautionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 26, height: 26)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text.caution).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusCard: some View {
        SettingsCard {
            SettingsRow(symbol: blocker == nil ? "checkmark.circle" : "info.circle",
                        title: blocker.map(blockerText) ?? text.ready) {
                if let action = blockerAction {
                    Button(action.title, action: action.run).disabled(busy)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private func blockerText(_ blocker: FaceUnlockBlocker) -> String {
        switch blocker {
        case .notEnabled: return text.ready
        case .modelUnavailable: return text.blockModel
        case .passwordOutdated: return text.blockOutdated
        case .needsAccessibility: return text.blockAccessibility
        case .needsCamera: return text.blockCamera
        case .sessionLocked: return text.blockSession
        case .needsPassword: return text.blockPassword
        case .needsFace: return text.blockFace
        }
    }

    private var blockerAction: (title: String, run: () -> Void)? {
        switch blocker {
        case .needsAccessibility:
            return (l10n.s.permissionRequest, { Permissions.shared.requestAccessibility() })
        case .needsCamera:
            return (l10n.s.permissionRequest, {
                if Permissions.shared.camera == .undetermined {
                    Permissions.shared.requestCamera()
                } else {
                    Permissions.shared.openCameraSettings()
                }
            })
        case .sessionLocked:
            return (text.confirm, unlockSession)
        case .needsFace:
            return (text.addFace, { beginEnrollment(replacing: nil) })
        default:
            return nil
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        SettingsCard(title: text.passwordTitle) {
            SettingsRow(symbol: "touchid", title: text.sessionTitle,
                        caption: sessionOpen ? nil : text.blockSession) {
                if sessionOpen {
                    HStack(spacing: 8) {
                        Text(text.sessionOpen).foregroundStyle(.secondary)
                        Button(text.lockNow) { FaceUnlockVault.lockSession(); refresh() }
                    }
                } else {
                    Button(text.confirm, action: unlockSession).disabled(busy)
                }
            }
            SettingsRow(symbol: "key", title: text.passwordTitle, caption: text.passwordHint) {
                if hasPassword {
                    HStack(spacing: 8) {
                        Label(text.passwordSaved, systemImage: "checkmark")
                            .labelStyle(.titleAndIcon).foregroundStyle(.secondary)
                        Button(text.remove, action: removePassword).disabled(busy)
                    }
                } else {
                    EmptyView()
                }
            }
            HStack(spacing: 8) {
                SecureField(text.passwordPlaceholder, text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePassword)
                Button(text.save, action: savePassword)
                    .disabled(password.isEmpty || busy)
            }
            .padding(.leading, settingsRowTextInset)
        }
    }

    // MARK: - Faces

    private var facesCard: some View {
        SettingsCard(title: text.facesTitle) {
            if store.isLocked {
                SettingsRow(symbol: "lock", title: text.blockSession) {
                    Button(text.confirm, action: unlockSession).disabled(busy)
                }
            } else if store.identities.isEmpty {
                Text(text.noFaces).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.identities) { identity in
                    SettingsRow(symbol: "person.crop.circle", title: identity.name) {
                        HStack(spacing: 10) {
                            Toggle(identity.name, isOn: Binding(
                                get: { identity.isEnabled },
                                set: { try? store.setEnabled($0, for: identity.id) }))
                                .labelsHidden().toggleStyle(.switch)
                            Button(text.recapture) { beginEnrollment(replacing: identity) }
                            Button(text.delete, role: .destructive) { try? store.delete(identity) }
                        }
                    }
                }
            }
            if !store.isLocked {
                Button {
                    beginEnrollment(replacing: nil)
                } label: {
                    Label(text.addFace, systemImage: "plus")
                }
                .padding(.leading, settingsRowTextInset)
                .disabled(busy)
            }
        }
    }

    // MARK: - Recognition

    private var recognitionCard: some View {
        SettingsCard {
            SettingsChoiceRow(symbol: "scope", title: text.strictnessTitle,
                              selection: $strictness) {
                Text(text.relaxed).tag(FaceUnlockStrictness.relaxed.rawValue)
                Text(text.standard).tag(FaceUnlockStrictness.standard.rawValue)
                Text(text.strict).tag(FaceUnlockStrictness.strict.rawValue)
            }
            SettingsChoiceRow(symbol: "waveform.path.ecg", title: text.livenessTitle,
                              selection: $liveness) {
                Text(text.livenessOff).tag(FaceUnlockLiveness.off.rawValue)
                Text(text.livenessLight).tag(FaceUnlockLiveness.light.rawValue)
                Text(text.livenessHeavy).tag(FaceUnlockLiveness.heavy.rawValue)
            }
            Text(text.livenessCaption).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
            SettingsRow(symbol: "timer", title: String(format: text.scanSecondsFormat, scanSeconds)) {
                Stepper("", value: $scanSeconds, in: FaceUnlockSupport.scanSecondsRange).labelsHidden()
            }
            SettingsRow(symbol: "arrow.counterclockwise", title: text.retryOnce) {
                Toggle(text.retryOnce, isOn: $retryOnce).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: - Lock screen

    private var lockScreenCard: some View {
        SettingsCard(title: text.triggersTitle) {
            SettingsRow(symbol: "sun.max", title: text.onWake) {
                Toggle(text.onWake, isOn: Binding(
                    get: { onWake },
                    set: { onWake = $0; if !$0 && !onLock { onLock = true } })).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(symbol: "lock", title: text.onLock) {
                Toggle(text.onLock, isOn: Binding(
                    get: { onLock },
                    set: { onLock = $0; if !$0 && !onWake { onWake = true } })).labelsHidden().toggleStyle(.switch)
            }
            SettingsFeatureSwitchRow(symbol: AppFeature.notch.symbolName, title: text.showOnLockScreen,
                                     caption: text.showOnLockScreenCaption,
                                     isOn: Binding(get: { showOnLockScreen }, set: { showOnLockScreen = $0; apply() }),
                                     feature: .notch)
            SettingsMenuRow(symbol: "camera", title: text.cameraTitle, selection: $cameraID) {
                Text(text.cameraAutomatic).tag("")
                ForEach(cameras) { camera in Text(camera.name).tag(camera.id) }
            }
            SettingsMenuRow(symbol: "clock.arrow.circlepath", title: text.sessionLimitTitle,
                            selection: $sessionLimit) {
                Text(text.limit7).tag(FaceUnlockSessionLimit.sevenDays.rawValue)
                Text(text.limit14).tag(FaceUnlockSessionLimit.fourteenDays.rawValue)
                Text(text.limit30).tag(FaceUnlockSessionLimit.thirtyDays.rawValue)
                Text(text.limitNever).tag(FaceUnlockSessionLimit.never.rawValue)
            }
        }
    }

    private var removeCard: some View {
        HStack {
            Spacer()
            Button(text.removeAll, role: .destructive) { confirmRemoveAll = true }
                .disabled(!hasPassword && store.identities.isEmpty && !FaceUnlockFaceStore.exists)
        }
    }

    // MARK: - Actions

    private func refresh() {
        sessionOpen = FaceUnlockVault.isSessionUnlocked
        hasPassword = FaceUnlockVault.hasStoredPassword()
        blocker = enabled ? service.currentBlocker() : nil
        cameras = FaceUnlockCamera.availableDevices()
    }

    private func apply() {
        service.syncWithPreferences()
        NotchLockScreenService.shared.faceUnlockDidChange()
        refresh()
    }

    private func unlockSession() {
        guard !busy else { return }
        busy = true
        message = nil
        Task {
            do {
                try await FaceUnlockVault.unlockSession(reason: text.touchIDReason)
            } catch {
                message = error.localizedDescription
            }
            busy = false
            refresh()
        }
    }

    private func savePassword() {
        let plaintext = password
        guard !plaintext.isEmpty, !busy else { return }
        busy = true
        message = nil
        password = ""
        Task {
            do {
                if !FaceUnlockVault.isSessionUnlocked {
                    try await FaceUnlockVault.unlockSession(reason: text.touchIDReason)
                }
                try await Task.detached(priority: .userInitiated) {
                    guard var bytes = plaintext.data(using: .utf8) else { throw FaceUnlockVaultError.emptyPassword }
                    defer { bytes.resetBytes(in: 0..<bytes.count) }
                    try FaceUnlockVault.savePassword(bytes)
                }.value
                service.passwordWasSaved()
            } catch {
                message = error.localizedDescription
            }
            busy = false
            refresh()
        }
    }

    private func removePassword() {
        try? FaceUnlockVault.deletePassword()
        // The key sealed the faces too, so they cannot be read again.
        FaceEnrollmentStore.shared.deleteAll()
        service.passwordWasSaved()
        refresh()
    }

    private func removeEverything() {
        enabled = false
        FaceEnrollmentStore.shared.deleteAll()
        FaceUnlockFaceStore.deleteAll()
        try? FaceUnlockVault.deletePassword()
        service.passwordWasSaved()
        apply()
    }

    private func beginEnrollment(replacing identity: FaceIdentity?) {
        guard !busy else { return }
        if FaceUnlockVault.isSessionUnlocked {
            enrollment = EnrollmentRequest(replacing: identity)
            return
        }
        busy = true
        Task {
            do {
                try await FaceUnlockVault.unlockSession(reason: text.touchIDReason)
                enrollment = EnrollmentRequest(replacing: identity)
            } catch {
                message = error.localizedDescription
            }
            busy = false
            refresh()
        }
    }
}

// MARK: - Enrollment

private struct FaceUnlockEnrollmentSheet: View {
    let replacing: FaceIdentity?
    let onFinish: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var capture = FaceUnlockEnrollment()
    @State private var name = ""
    @State private var error: String?

    private var text: FaceUnlockFeatureStrings { FeatureStrings.faceUnlock(l10n.language) }

    var body: some View {
        VStack(spacing: 16) {
            Text(text.enrollTitle).font(.headline)
            ZStack {
                if capture.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64)).foregroundStyle(.green)
                } else {
                    FaceUnlockPreview(session: capture.camera.session)
                }
            }
            .frame(width: 220, height: 220)
            .background(Color.black.opacity(0.85))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2))

            Text(hintText).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(minHeight: 36)
            ProgressView(value: capture.progress).frame(width: 220)

            if capture.isComplete {
                TextField(text.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                    .onSubmit(save)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Button(text.cancel) { capture.stop(); onFinish() }
                    .keyboardShortcut(.cancelAction)
                if capture.isComplete {
                    Button(text.save, action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            name = replacing?.name ?? ""
            capture.start()
        }
        .onDisappear { capture.stop() }
    }

    private var hintText: String {
        switch capture.hint {
        case .starting, .pose(.center): return text.poseCenter
        case .pose(.left): return text.poseLeft
        case .pose(.right): return text.poseRight
        case .pose(.up): return text.poseUp
        case .pose(.down): return text.poseDown
        case .noFace: return text.noFaceHint
        case .tooFar: return text.tooFarHint
        case .turnedTooFar: return text.turnedTooFarHint
        case .done: return text.doneHint
        case .cameraProblem: return text.cameraDenied
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if FaceEnrollmentStore.shared.nameIsTaken(trimmed, excluding: replacing?.id) {
            error = text.nameTaken
            return
        }
        do {
            try capture.commit(name: trimmed, replacing: replacing?.id)
            capture.stop()
            onFinish()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The camera's own picture, mirrored like a mirror and cropped to fill.
private struct FaceUnlockPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewHost { PreviewHost(session: session) }
    func updateNSView(_ nsView: PreviewHost, context: Context) {}

    final class PreviewHost: NSView {
        private let layerView: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            layerView = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layerView.videoGravity = .resizeAspectFill
            layer?.addSublayer(layerView)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layerView.bounds = CGRect(origin: .zero, size: bounds.size)
            layerView.position = CGPoint(x: bounds.midX, y: bounds.midY)
            layerView.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            CATransaction.commit()
        }
    }
}
