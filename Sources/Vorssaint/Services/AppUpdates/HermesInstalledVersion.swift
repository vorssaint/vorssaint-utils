// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Hermes-Setup is a fixed-version bootstrap launcher, not the agent it opens.
/// Read the agent's own install stamp on each scan, without starting Hermes
/// (its --version command also checks the network). Never change a signed bundle.
enum HermesInstalledVersion {
    static let bootstrapBundleID = "com.nousresearch.hermes.setup"

    static func resolve(bundleID: String, bundleVersion: String,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        guard bundleID == bootstrapBundleID else { return bundleVersion }
        let repo = home.appendingPathComponent(".hermes/hermes-agent", isDirectory: true)
        let stamp = repo.appendingPathComponent("install-stamp.json")
        guard let size = try? stamp.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 64 * 1_024, let data = try? Data(contentsOf: stamp) else { return "" }
        // No external hooks, checkout execution or network; bound the local Git probe.
        let result = BoundedProcessRunner.run(
            "/usr/bin/git", ["--no-optional-locks", "-C", repo.path, "rev-parse", "--verify", "HEAD"],
            timeout: 2, maxOutputBytes: 256)
        guard result.status == 0 else { return "" }
        let head = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty means uncomparable in the existing update/coverage pipeline.
        return version(stamp: data, head: head) ?? ""
    }

    static func version(stamp: Data, head: String) -> String? {
        guard stamp.count <= 64 * 1_024,
              let fields = try? JSONSerialization.jsonObject(with: stamp) as? [String: Any],
              fields["schemaVersion"] as? Int == 2,
              fields["source"] as? String == "git",
              fields["updateMechanism"] as? String == "self",
              fields["payload"] as? String == "bootstrap",
              let commit = fields["commit"] as? String, commit == head,
              [40, 64].contains(commit.count),
              commit.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              commit.contains(where: { $0 != "0" }),
              let version = fields["baseVersion"] as? String,
              version.range(of: #"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z"#,
                            options: .regularExpression) != nil else { return nil }
        return version
    }
}
