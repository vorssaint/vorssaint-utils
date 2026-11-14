// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import Foundation
import Network
import Security

/// A small, local-only control surface for the separate Developer build.
/// Requests are newline-delimited JSON, authenticated with a per-launch token,
/// and handled on the main queue because the services below are AppKit-owned.
final class AgentBridgeService {
    static let shared = AgentBridgeService()

    private static let maximumRequestBytes = 64 * 1024

    private var listener: NWListener?
    private var token: String?
    private var endpointURL: URL? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("AgentBridge", isDirectory: true)
            .appendingPathComponent("endpoint.json")
    }

    private init() {}

    func start() {
        guard listener == nil else { return }
        do {
            token = try Self.makeToken()
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            let listener = try NWListener(using: parameters, on: .any)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publishEndpoint(port: self.listener?.port)
                case .failed(let error):
                    NSLog("Vorssaint agent bridge failed to start: %@", error.localizedDescription)
                    self.removeEndpointIfOwned()
                case .cancelled:
                    self.removeEndpointIfOwned()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                self?.receiveRequest(from: connection)
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            token = nil
            NSLog("Vorssaint agent bridge could not start: %@", error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        removeEndpointIfOwned()
        token = nil
    }

    private func publishEndpoint(port: NWEndpoint.Port?) {
        guard let port, let token, let endpointURL else { return }
        let directory = endpointURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                  ofItemAtPath: directory.path)
            let payload: [String: Any] = [
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "pid": ProcessInfo.processInfo.processIdentifier,
                "port": Int(port.rawValue),
                "token": token,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: endpointURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: endpointURL.path)
        } catch {
            NSLog("Vorssaint agent bridge could not publish its local endpoint: %@",
                  error.localizedDescription)
        }
    }

    private func removeEndpointIfOwned() {
        guard let endpointURL,
              let data = try? Data(contentsOf: endpointURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ownerPID = payload["pid"] as? Int,
              ownerPID == Int(ProcessInfo.processInfo.processIdentifier) else {
            return
        }
        try? FileManager.default.removeItem(at: endpointURL)
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: Self.maximumRequestBytes) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }
            guard buffer.count <= Self.maximumRequestBytes else {
                self.send(["ok": false, "error": "Request is too large."], on: connection)
                return
            }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                self.handleRequest(Data(line), on: connection)
            } else if isComplete || error != nil {
                self.send(["ok": false, "error": "Request ended before its JSON line was complete."],
                          on: connection)
            } else {
                self.receiveRequest(from: connection, accumulated: buffer)
            }
        }
    }

    private func handleRequest(_ data: Data, on connection: NWConnection) {
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let suppliedToken = request["token"] as? String,
                  let token,
                  Self.constantTimeEqual(suppliedToken, token) else {
                send(["ok": false, "error": "Authentication failed."], on: connection)
                return
            }
            let method = request["method"] as? String ?? ""
            let params = request["params"] as? [String: Any] ?? [:]
            let result = try perform(method: method, params: params)
            send(["ok": true, "result": result], on: connection)
        } catch {
            send(["ok": false, "error": error.localizedDescription], on: connection)
        }
    }

    private func perform(method: String, params: [String: Any]) throws -> Any {
        switch method {
        case "status":
            let darkMode: Any
            if let isDark = QuickTogglesService.shared.systemAppearanceIsDark {
                darkMode = isDark ? "dark" : "light"
            } else {
                darkMode = NSNull()
            }
            return [
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "version": AppInfo.version,
                "availableFeatureCount": FeatureRuntime.shared.availableCount,
                "featureCount": AppFeature.allCases.count,
                "keepAwakeActive": KeepAwakeManager.shared.isActive,
                "darkMode": darkMode,
                "bridge": "developer-build-local-only",
            ]

        case "list_features":
            let defaults = UserDefaults.standard
            return AppFeature.allCases.map { feature in
                let enabled = feature.enabledKeys.isEmpty
                    ? feature.isAvailable
                    : feature.enabledKeys.contains { defaults.bool(forKey: $0) }
                return [
                    "id": feature.rawValue,
                    "group": feature.group.rawValue,
                    "available": feature.isAvailable,
                    "enabled": enabled,
                    "permissions": feature.permissions.map(\.rawValue),
                ] as [String: Any]
            }

        case "set_feature_available":
            guard let rawID = params["feature"] as? String,
                  let feature = AppFeature(rawValue: rawID),
                  let available = params["available"] as? Bool else {
                throw BridgeError.invalidArguments("Expected a known feature id and an available boolean.")
            }
            FeatureRuntime.shared.setAvailable([feature], available)
            guard feature.isAvailable == available else {
                throw BridgeError.featureUnavailable(rawID)
            }
            return [
                "feature": feature.rawValue,
                "available": feature.isAvailable,
                "runtimeRevision": FeatureRuntime.shared.revision,
            ]

        case "set_keep_awake":
            guard let active = params["active"] as? Bool else {
                throw BridgeError.invalidArguments("Expected an active boolean.")
            }
            guard AppFeature.keepAwake.isAvailable else {
                throw BridgeError.featureUnavailable(AppFeature.keepAwake.rawValue)
            }
            if active {
                if let minutes = params["durationMinutes"] as? Int {
                    guard (0...1440).contains(minutes) else {
                        throw BridgeError.invalidArguments("durationMinutes must be from 0 to 1440; 0 means indefinite.")
                    }
                    KeepAwakeManager.shared.activate(minutes: minutes)
                } else {
                    KeepAwakeManager.shared.startLastPick()
                }
            } else if KeepAwakeManager.shared.isActive {
                KeepAwakeManager.shared.deactivate(reason: .manual)
            }
            return ["active": KeepAwakeManager.shared.isActive]

        case "set_appearance":
            guard let appearance = params["appearance"] as? String,
                  appearance == "light" || appearance == "dark" else {
                throw BridgeError.invalidArguments("appearance must be 'light' or 'dark'.")
            }
            guard AppFeature.quickToggles.isAvailable else {
                throw BridgeError.featureUnavailable(AppFeature.quickToggles.rawValue)
            }
            guard let current = QuickTogglesService.shared.systemAppearanceIsDark else {
                throw BridgeError.actionUnavailable("System appearance could not be read on this Mac.")
            }
            let wantedDark = appearance == "dark"
            if current != wantedDark {
                QuickTogglesService.shared.toggleDarkMode()
            }
            guard QuickTogglesService.shared.systemAppearanceIsDark == wantedDark else {
                throw BridgeError.actionUnavailable("System appearance did not change to the requested mode.")
            }
            return ["appearance": wantedDark ? "dark" : "light"]

        default:
            throw BridgeError.unknownMethod(method)
        }
    }

    private func send(_ response: [String: Any], on connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])) ??
            Data("{\"ok\":false,\"error\":\"Could not encode response.\"}".utf8)
        var line = data
        line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw BridgeError.tokenGenerationFailed }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

private enum BridgeError: LocalizedError {
    case invalidArguments(String)
    case featureUnavailable(String)
    case actionUnavailable(String)
    case unknownMethod(String)
    case tokenGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return message
        case .featureUnavailable(let id): return "Feature '\(id)' is unavailable on this Mac or could not be changed."
        case .actionUnavailable(let message): return message
        case .unknownMethod(let method): return "Unknown Vorssaint bridge method '\(method)'."
        case .tokenGenerationFailed: return "A secure local bridge token could not be created."
        }
    }
}
#endif
