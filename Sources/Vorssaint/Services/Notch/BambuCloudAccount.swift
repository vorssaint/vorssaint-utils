// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Signing in to Bambu Cloud from Settings: password, then the emailed or
/// authenticator code, then the account's printers. Only the resulting
/// token is kept, in the keychain; the password is used once and dropped.
@MainActor
final class BambuCloudAccount: ObservableObject {
    enum Step: Equatable {
        case signedOut
        case emailCode
        case twoFactor(key: String)
        case signedIn
    }

    static let shared = BambuCloudAccount()

    @Published private(set) var step: Step
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var devices: [BambuCloudAPI.Device] = []
    @Published private(set) var email: String

    private var pendingEmail = ""

    private init() {
        email = PrinterKeychain.read(.cloudEmail)
        step = PrinterKeychain.read(.cloudToken).isEmpty ? .signedOut : .signedIn
    }

    func signIn(email: String, password: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else { return }
        pendingEmail = email
        run {
            switch try await BambuCloudAPI.login(email: email, password: password) {
            case .token(let token): try await self.finish(token: token)
            case .needsEmailCode:
                try await BambuCloudAPI.sendEmailCode(email: email)
                self.step = .emailCode
            case .needsTwoFactor(let key): self.step = .twoFactor(key: key)
            }
        }
    }

    func verify(code: String) {
        let code = code.filter(\.isNumber)
        guard !code.isEmpty else { return }
        let step = step
        run {
            switch step {
            case .emailCode:
                try await self.finish(token: BambuCloudAPI.login(email: self.pendingEmail, code: code))
            case .twoFactor(let key):
                try await self.finish(token: BambuCloudAPI.login(twoFactorKey: key, code: code))
            case .signedOut, .signedIn:
                break
            }
        }
    }

    func resendCode() {
        guard step == .emailCode, !pendingEmail.isEmpty else { return }
        let email = pendingEmail
        run { try await BambuCloudAPI.sendEmailCode(email: email) }
    }

    func cancel() {
        step = PrinterKeychain.read(.cloudToken).isEmpty ? .signedOut : .signedIn
        error = nil
    }

    func refreshDevices() {
        let token = PrinterKeychain.read(.cloudToken)
        guard !token.isEmpty else { return }
        run {
            self.devices = try await BambuCloudAPI.devices(token: token)
            self.chooseDeviceIfNeeded()
        }
    }

    func choose(serial: String) {
        UserDefaults.standard.set(serial, forKey: DefaultsKey.notchPrinterSerial)
        NotchPrinterService.shared.reconnectNow()
    }

    func signOut() {
        PrinterKeychain.signOut()
        devices = []
        email = ""
        error = nil
        step = .signedOut
        NotchPrinterService.shared.reconnectNow()
    }

    private func finish(token: String) async throws {
        let username = try await BambuCloudAPI.mqttUsername(token: token)
        PrinterKeychain.save(token, for: .cloudToken)
        PrinterKeychain.save(username, for: .cloudUsername)
        PrinterKeychain.save(pendingEmail, for: .cloudEmail)
        email = pendingEmail
        step = .signedIn
        devices = try await BambuCloudAPI.devices(token: token)
        chooseDeviceIfNeeded()
        NotchService.shared.syncWithPreferences()
        NotchPrinterService.shared.reconnectNow()
    }

    /// The account's only printer, or its first, when none on it is chosen.
    private func chooseDeviceIfNeeded() {
        let chosen = NotchPrinterSupport.serial()
        guard !devices.contains(where: { $0.serial == chosen }), let first = devices.first else { return }
        choose(serial: first.serial)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { self.busy = false }
            do { try await work() } catch let failure as BambuCloudAPI.Failure {
                self.error = failure.errorDescription ?? FeatureStrings.notchPrinter(L10n.shared.language).signInFailed
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
