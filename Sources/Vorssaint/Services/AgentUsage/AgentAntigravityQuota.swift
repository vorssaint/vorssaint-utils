// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Reads the Gemini quota Antigravity's language server reports. Antigravity
/// keeps no quota on disk: while it runs, its server announces a loopback port
/// and a CSRF token in `~/.gemini/antigravity/daemon/hub_<port>.json`, and
/// answers the same quota summary its own usage panel shows.
enum AgentAntigravityQuota {
    /// How often the running server is asked.
    static let interval: TimeInterval = 60

    struct Endpoint: Equatable {
        let port: Int
        let token: String
    }

    /// The announcement of a server that is still running, newest first.
    static func endpoint(home: URL) -> Endpoint? {
        let folder = home.appending(path: ".gemini/antigravity/daemon", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let modified = { (url: URL) in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        for file in files.filter({ $0.lastPathComponent.hasPrefix("hub_") && $0.pathExtension == "json" })
            .sorted(by: { modified($0) > modified($1) }) {
            guard let data = try? Data(contentsOf: file), data.count <= 4096,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (object["pid"] as? NSNumber)?.int32Value, pid > 0, kill(pid, 0) == 0,
                  let port = (object["httpPort"] as? NSNumber)?.intValue, (1...65_535).contains(port),
                  let token = object["csrfToken"] as? String, !token.isEmpty, token.count <= 256,
                  !token.contains(where: { $0.isNewline }) else { continue }
            return Endpoint(port: port, token: token)
        }
        return nil
    }

    static func request(_ endpoint: Endpoint) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(endpoint.token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = Data(#"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}"#.utf8)
        return request
    }

    /// Loopback only: a proxy must never see the token.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    /// Gemini models only: their group's five-hour and weekly buckets, which
    /// every Gemini model shares. Other groups, such as Claude, are left out.
    static func limits(_ data: Data, observed: Date) -> AgentLimits? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = (object["response"] as? [String: Any])?["groups"] as? [[String: Any]] else { return nil }
        let parser = ISO8601DateFormatter()
        let windows = groups.flatMap { ($0["buckets"] as? [[String: Any]]) ?? [] }.compactMap { bucket -> AgentLimitWindow? in
            guard (bucket["bucketId"] as? String)?.hasPrefix("gemini-") == true else { return nil }
            let (kind, minutes): (AgentLimitWindow.Kind, Int)
            switch bucket["window"] as? String {
            case "5h": (kind, minutes) = (.session, 5 * 60)
            case "weekly": (kind, minutes) = (.weekly, 7 * 24 * 60)
            default: return nil
            }
            // Protobuf JSON leaves out a zero fraction: an exhausted bucket.
            let remaining = min(1, max(0, (bucket["remainingFraction"] as? NSNumber)?.doubleValue ?? 0))
            return AgentLimitWindow(id: "antigravity.gemini.\(kind.rawValue)", kind: kind, minutes: minutes, scope: nil,
                                    usedPercent: (1 - remaining) * 100,
                                    resetsAt: (bucket["resetTime"] as? String).flatMap(parser.date(from:)))
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account)
    }
}
