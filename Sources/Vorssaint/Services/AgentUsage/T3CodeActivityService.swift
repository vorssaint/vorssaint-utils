// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum T3CodeConnectionState: Equatable {
    case notConfigured
    case connecting
    case connected
    case reconnecting
    case needsPairing
    case unavailable
}

enum T3CodeConnectionError: Error, Equatable {
    case invalidEndpoint
    case unsupportedServer
    case pairingRejected
    case readPermissionMissing
    case authenticationExpired
    case serverUnavailable
    case invalidResponse
}

protocol T3CredentialStore: Sendable {
    func read(account: String) -> String?
    func write(_ token: String, account: String) -> Bool
    func remove(account: String)
}

struct T3KeychainCredentialStore: T3CredentialStore {
    private let service = "com.vorssaint.notch.t3-code"

    static func account(endpoint: URL, environmentID: String, credentialID: String? = nil) -> String {
        var origin = URLComponents()
        origin.scheme = endpoint.scheme?.lowercased()
        origin.host = endpoint.host?.lowercased()
        origin.port = endpoint.port
        let credentialBinding = credentialID.map { "\n\($0)" } ?? ""
        let binding = "\(origin.string ?? endpoint.absoluteString)\n\(environmentID)\(credentialBinding)"
        let digest = SHA256.hash(data: Data(binding.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func read(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String, account: String) -> Bool {
        let data = Data(token.utf8)
        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func remove(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseAuthenticationContext as String: context]
    }
}

protocol T3CodeHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private final class T3NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct T3URLSessionTransport: T3CodeHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: T3NoRedirectDelegate(), delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

struct T3CodeClient {
    let transport: T3CodeHTTPTransport

    init(transport: T3CodeHTTPTransport = T3URLSessionTransport()) {
        self.transport = transport
    }

    func validateEndpoint(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw T3CodeConnectionError.invalidEndpoint
        }
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let loopback = normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1"
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw T3CodeConnectionError.invalidEndpoint
        }
        var safeComponents = components
        safeComponents.scheme = scheme
        safeComponents.path = ""
        guard let url = safeComponents.url else { throw T3CodeConnectionError.invalidEndpoint }
        return url
    }

    func pair(endpoint: URL, credential: String) async throws -> (T3EnvironmentIdentity, String, Date) {
        guard !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw T3CodeConnectionError.pairingRejected
        }
        let identity = try await fetchDescriptor(endpoint: endpoint)

        var request = URLRequest(url: endpoint.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token": credential.trimmingCharacters(in: .whitespacesAndNewlines),
            "subject_token_type": "urn:t3:params:oauth:token-type:environment-bootstrap",
            "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "scope": "orchestration:read",
            "client_label": "Vorssaint",
            "client_device_type": "desktop",
            "client_os": "macOS"
        ]
        request.httpBody = form.map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        let (tokenData, tokenResponse) = try await transport.data(for: request)
        guard let tokenHTTP = tokenResponse as? HTTPURLResponse else { throw T3CodeConnectionError.serverUnavailable }
        guard tokenHTTP.statusCode == 200 else { throw T3CodeConnectionError.pairingRejected }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: tokenData),
              token.issuedTokenType == "urn:ietf:params:oauth:token-type:access_token",
              token.tokenType == "Bearer", token.scope.split(separator: " ").contains("orchestration:read"),
              !token.scope.split(separator: " ").contains("orchestration:operate"),
              token.expiresIn > 0 else { throw T3CodeConnectionError.readPermissionMissing }
        return (identity, token.accessToken, Date().addingTimeInterval(token.expiresIn))
    }

    func fetchDescriptor(endpoint: URL) async throws -> T3EnvironmentIdentity {
        let url = endpoint.appendingPathComponent(".well-known").appendingPathComponent("t3")
            .appendingPathComponent("environment")
        let (data, response) = try await transport.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let descriptor = try? JSONDecoder().decode(Descriptor.self, from: data),
              descriptor.orchestrationProtocolVersion == 2,
              !descriptor.environmentID.isEmpty, !descriptor.label.isEmpty else {
            throw T3CodeConnectionError.unsupportedServer
        }
        return T3EnvironmentIdentity(id: descriptor.environmentID, label: descriptor.label,
                                     machine: descriptor.platform.machine)
    }

    func fetchSnapshot(endpoint: URL, token: String) async throws -> T3ShellSnapshot {
        var request = URLRequest(url: endpoint.appendingPathComponent("api/orchestration/shell"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "x-t3-orchestration-protocol")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw T3CodeConnectionError.serverUnavailable }
        if http.statusCode == 401 { throw T3CodeConnectionError.authenticationExpired }
        if http.statusCode == 403 { throw T3CodeConnectionError.readPermissionMissing }
        guard http.statusCode == 200,
              let snapshot = try? JSONDecoder().decode(T3ShellSnapshot.self, from: data) else {
            throw T3CodeConnectionError.invalidResponse
        }
        return snapshot
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private struct Descriptor: Decodable {
        struct Platform: Decodable { let machine: String? }
        let environmentID: String
        let label: String
        let platform: Platform
        let orchestrationProtocolVersion: Int?
        enum CodingKeys: String, CodingKey {
            case label, platform, orchestrationProtocolVersion
            case environmentID = "environmentId"
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let issuedTokenType: String
        let tokenType: String
        let expiresIn: TimeInterval
        let scope: String
        enum CodingKeys: String, CodingKey {
            case scope
            case accessToken = "access_token"
            case issuedTokenType = "issued_token_type"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }
}

final class T3CodeActivityService: ObservableObject {
    static let shared = T3CodeActivityService()

    @Published private(set) var state: T3CodeConnectionState = .notConfigured
    @Published private(set) var activities: [T3ThreadActivity] = []
    @Published private(set) var lastUpdated: Date?
    let completed = PassthroughSubject<T3ActivityCompletion, Never>()

    private let client: T3CodeClient
    private let credentials: T3CredentialStore
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var generation = 0
    private var reducer = T3ActivityReducer()
    private var endpointURL: URL?
    private var environment: T3EnvironmentIdentity?
    private var accessToken: String?
    private var expiresAt: Date?
    private var pairingInProgress = false

    init(client: T3CodeClient = T3CodeClient(), credentials: T3CredentialStore = T3KeychainCredentialStore(),
         defaults: UserDefaults = .standard) {
        self.client = client
        self.credentials = credentials
        self.defaults = defaults
    }

    var endpoint: String { defaults.string(forKey: DefaultsKey.notchAgentsT3Endpoint) ?? "" }
    var configuredEnvironment: String { defaults.string(forKey: DefaultsKey.notchAgentsT3Environment) ?? "" }

    @MainActor func connect(endpoint rawEndpoint: String, pairingCode: String) async throws {
        let endpoint = try client.validateEndpoint(rawEndpoint)
        stop(clearActivity: true)
        pairingInProgress = true
        state = .connecting
        let operationGeneration = generation
        do {
            let (identity, token, expiry) = try await client.pair(endpoint: endpoint, credential: pairingCode)
            guard !Task.isCancelled, operationGeneration == generation else { throw CancellationError() }
            let credentialID = UUID().uuidString
            let account = T3KeychainCredentialStore.account(endpoint: endpoint, environmentID: identity.id,
                                                            credentialID: credentialID)
            let credentialStore = credentials
            let saved = await Task.detached(priority: .utility) {
                credentialStore.write(token, account: account)
            }.value
            guard !Task.isCancelled, operationGeneration == generation else {
                Task.detached(priority: .utility) { credentialStore.remove(account: account) }
                throw CancellationError()
            }
            guard saved else {
                throw T3CodeConnectionError.readPermissionMissing
            }
            let previousEnvironment = defaults.string(forKey: DefaultsKey.notchAgentsT3Environment) ?? ""
            let previousCredentialID = defaults.string(forKey: DefaultsKey.notchAgentsT3CredentialID)
                .flatMap { $0.isEmpty ? nil : $0 }
            let previousEndpoint = defaults.string(forKey: DefaultsKey.notchAgentsT3Endpoint)
                .flatMap { try? client.validateEndpoint($0) }
            let previousAccount = previousEndpoint.flatMap { previousEndpoint in
                previousEnvironment.isEmpty ? nil : T3KeychainCredentialStore.account(
                    endpoint: previousEndpoint, environmentID: previousEnvironment,
                    credentialID: previousCredentialID)
            }
            if let previousAccount, previousAccount != account {
                let credentialStore = credentials
                Task.detached(priority: .utility) {
                    credentialStore.remove(account: previousAccount)
                }
            }
            defaults.set(endpoint.absoluteString, forKey: DefaultsKey.notchAgentsT3Endpoint)
            defaults.set(identity.id, forKey: DefaultsKey.notchAgentsT3Environment)
            defaults.set(credentialID, forKey: DefaultsKey.notchAgentsT3CredentialID)
            defaults.set(identity.label, forKey: DefaultsKey.notchAgentsT3Label)
            defaults.set(identity.machine ?? "", forKey: DefaultsKey.notchAgentsT3Machine)
            defaults.set(expiry, forKey: DefaultsKey.notchAgentsT3Expiry)
            self.endpointURL = endpoint
            environment = identity
            accessToken = token
            expiresAt = expiry
            pairingInProgress = false
            state = .connected
            startPolling()
        } catch {
            guard operationGeneration == generation else { throw CancellationError() }
            pairingInProgress = false
            syncWithPreferences()
            throw (error as? T3CodeConnectionError) ?? .serverUnavailable
        }
    }

    func disconnect() {
        stop(clearActivity: true)
        let environmentID = configuredEnvironment
        let endpointURL = try? client.validateEndpoint(endpoint)
        if !environmentID.isEmpty, let endpointURL {
            let credentialStore = credentials
            let credentialID = defaults.string(forKey: DefaultsKey.notchAgentsT3CredentialID)
                .flatMap { $0.isEmpty ? nil : $0 }
            let account = T3KeychainCredentialStore.account(endpoint: endpointURL, environmentID: environmentID,
                                                            credentialID: credentialID)
            Task.detached(priority: .utility) { credentialStore.remove(account: account) }
        }
        defaults.removeObject(forKey: DefaultsKey.notchAgentsT3Endpoint)
        defaults.removeObject(forKey: DefaultsKey.notchAgentsT3Environment)
        defaults.removeObject(forKey: DefaultsKey.notchAgentsT3CredentialID)
        defaults.removeObject(forKey: DefaultsKey.notchAgentsT3Label)
        defaults.removeObject(forKey: DefaultsKey.notchAgentsT3Machine)
        defaults.removeObject(forKey: DefaultsKey.notchAgentsT3Expiry)
        state = .notConfigured
    }

    func syncWithPreferences() {
        guard NotchAgentSupport.isEnabled() else { stop(clearActivity: true); return }
        if task != nil || pairingInProgress { return }
        guard let endpointURL = try? client.validateEndpoint(endpoint),
              !configuredEnvironment.isEmpty,
              let expiry = defaults.object(forKey: DefaultsKey.notchAgentsT3Expiry) as? Date,
              expiry > Date() else {
            clearActivities()
            state = endpoint.isEmpty ? .notConfigured : .needsPairing
            return
        }
        let environmentID = configuredEnvironment
        let credentialID = defaults.string(forKey: DefaultsKey.notchAgentsT3CredentialID)
            .flatMap { $0.isEmpty ? nil : $0 }
        let account = T3KeychainCredentialStore.account(endpoint: endpointURL, environmentID: environmentID,
                                                        credentialID: credentialID)
        let identity = T3EnvironmentIdentity(
            id: environmentID,
            label: defaults.string(forKey: DefaultsKey.notchAgentsT3Label).flatMap { $0.isEmpty ? nil : $0 } ?? "T3 Code",
            machine: defaults.string(forKey: DefaultsKey.notchAgentsT3Machine).flatMap { $0.isEmpty ? nil : $0 })
        state = .reconnecting
        generation += 1
        let currentGeneration = generation
        let credentials = self.credentials
        task = Task { @MainActor [weak self] in
            let token = await Task.detached(priority: .utility) {
                credentials.read(account: account)
            }.value
            guard let self, !Task.isCancelled, currentGeneration == self.generation else { return }
            self.task = nil
            guard let token else {
                self.clearActivities()
                self.state = .needsPairing
                return
            }
            self.endpointURL = endpointURL
            self.expiresAt = expiry
            self.accessToken = token
            self.environment = identity
            self.startPolling()
        }
    }

    func pause() { stop(clearActivity: false) }

    func stop(clearActivity: Bool) {
        generation += 1
        task?.cancel()
        task = nil
        pairingInProgress = false
        if clearActivity {
            activities = []
            reducer = T3ActivityReducer()
            lastUpdated = nil
            endpointURL = nil
            environment = nil
            accessToken = nil
            expiresAt = nil
        }
    }

    private func startPolling() {
        guard Self.shouldStartPolling(featureEnabled: NotchAgentSupport.isEnabled(),
                                      taskAlreadyRunning: task != nil,
                                      hasConnection: endpointURL != nil && environment != nil && accessToken != nil),
              let endpointURL, let environment, let accessToken else { return }
        generation += 1
        let currentGeneration = generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var delay: UInt64 = 3
            while !Task.isCancelled, currentGeneration == self.generation {
                do {
                    guard self.expiresAt.map({ $0 > Date() }) == true else {
                        self.clearActivities()
                        self.state = .needsPairing
                        self.task = nil
                        return
                    }
                    let snapshot = try await self.client.fetchSnapshot(endpoint: endpointURL, token: accessToken)
                    guard !Task.isCancelled, currentGeneration == self.generation else { return }
                    let next = snapshot.activities(environment: environment)
                    for event in self.reducer.apply(next) { self.completed.send(event) }
                    self.activities = next
                    self.lastUpdated = Date()
                    self.state = .connected
                    delay = 3
                } catch let error as T3CodeConnectionError {
                    guard !Task.isCancelled, currentGeneration == self.generation else { return }
                    if error == .authenticationExpired || error == .readPermissionMissing {
                        self.clearActivities()
                        self.accessToken = nil
                        self.state = .needsPairing
                        self.task = nil
                        return
                    } else {
                        self.clearActivities()
                        self.state = .reconnecting
                    }
                    delay = min(delay * 2, 30)
                } catch {
                    guard !Task.isCancelled, currentGeneration == self.generation else { return }
                    self.clearActivities()
                    self.state = .reconnecting
                    delay = min(delay * 2, 30)
                }
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
            }
            if currentGeneration == self.generation { self.task = nil }
        }
    }

    static func shouldStartPolling(featureEnabled: Bool, taskAlreadyRunning: Bool,
                                   hasConnection: Bool) -> Bool {
        featureEnabled && !taskAlreadyRunning && hasConnection
    }

    private func clearActivities() {
        activities = []
        reducer = T3ActivityReducer()
        lastUpdated = nil
    }
}
