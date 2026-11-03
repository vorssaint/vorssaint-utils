// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct UpdateInstallFailure: Codable, Equatable {
    let code: String
    let installedVersion: String
    let attemptedVersion: String?
    var dismissed = false

    func releaseURL(repositoryURL: URL) -> URL {
        let releases = repositoryURL.appendingPathComponent("releases")
        guard let version = attemptedVersion,
              UpdateServiceSupport.SemanticVersion(raw: version) != nil else { return releases }
        return releases.appendingPathComponent("tag").appendingPathComponent("v\(version)")
    }

    /// Diagnostic text contains versions and a step code, never paths or account data.
    func diagnostics(currentVersion: String, macOSVersion: String) -> String {
        "Vorssaint update failure\nCurrent version: \(currentVersion)\n"
            + "Version before attempt: \(installedVersion)\n"
            + "Attempted version: \(attemptedVersion ?? "unknown")\n"
            + "Installer step: \(code)\nmacOS: \(macOSVersion)"
    }
}

/// Local update history is independent of the transient check/download state.
/// Neither a successful update check nor dismissing the banner erases a failure.
struct UpdateFailureStore {
    let defaults: UserDefaults

    struct Attempt: Codable {
        let installedVersion: String
        let offeredVersion: String
    }

    var failure: UpdateInstallFailure? {
        defaults.data(forKey: DefaultsKey.updateInstallFailure)
            .flatMap { try? JSONDecoder().decode(UpdateInstallFailure.self, from: $0) }
    }

    func restore(currentVersion: String) -> UpdateInstallFailure? {
        if let failure {
            // A manual upgrade can succeed without producing an installer marker.
            if UpdateServiceSupport.isNewer(currentVersion, than: failure.installedVersion) {
                clear()
                return nil
            }
            return failure
        }
        // Older builds' saved retry code has no associated version and can
        // survive a manual upgrade. It is not evidence of a current failure.
        // A fresh legacy installer marker is still handled by consume().
        return nil
    }

    func beginAttempt(installedVersion: String, offeredVersion: String) {
        let attempt = Attempt(installedVersion: installedVersion, offeredVersion: offeredVersion)
        defaults.set(try? JSONEncoder().encode(attempt), forKey: DefaultsKey.updateInstallAttempt)
    }

    func cancelAttempt() {
        defaults.removeObject(forKey: DefaultsKey.updateInstallAttempt)
    }

    @discardableResult
    func consume(marker: String, currentVersion: String) -> UpdateInstallFailure? {
        let marker = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        if marker == "ok" {
            clear()
            return nil
        }
        guard let code = UpdateInstallerSupport.installFailureCode(fromMarker: marker) else {
            return failure
        }
        let attempt = defaults.data(forKey: DefaultsKey.updateInstallAttempt)
            .flatMap { try? JSONDecoder().decode(Attempt.self, from: $0) }
        let failure = UpdateInstallFailure(code: code,
                                           installedVersion: attempt?.installedVersion ?? currentVersion,
                                           attemptedVersion: attempt?.offeredVersion)
        save(failure)
        defaults.set(code, forKey: DefaultsKey.updateLastInstallFailure)
        cancelAttempt()
        return restore(currentVersion: currentVersion)
    }

    func dismiss() {
        guard var failure else { return }
        failure.dismissed = true
        save(failure)
    }

    private func save(_ failure: UpdateInstallFailure) {
        defaults.set(try? JSONEncoder().encode(failure), forKey: DefaultsKey.updateInstallFailure)
    }

    private func clear() {
        defaults.removeObject(forKey: DefaultsKey.updateInstallFailure)
        defaults.removeObject(forKey: DefaultsKey.updateLastInstallFailure)
        cancelAttempt()
    }
}
