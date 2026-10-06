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
    case credentialStoreUnavailable(Int32)
}

protocol T3CredentialStore: Sendable {
    func read(account: String) -> T3CredentialLookup
    func write(_ token: String, account: String) -> Bool
    func remove(account: String)
}

enum T3CredentialLookup: Equatable, Sendable {
    case found(String)
    case missing
    case retryable(Int32)
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

    func read(account: String) -> T3CredentialLookup {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                return .retryable(errSecDecode)
            }
            return .found(token)
        case errSecItemNotFound:
            return .missing
        default:
            // Keychain can temporarily refuse access while the device is locked or
            // the security service is unavailable. Keep retrying without prompting.
            return .retryable(status)
        }
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
              token.tokenType == "Bearer", Self.hasReadOnlyScope(token.scope),
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

    static func hasReadOnlyScope(_ scope: String) -> Bool {
        Set(scope.split(whereSeparator: \.isWhitespace).map(String.init)) == ["orchestration:read"]
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

struct T3ConfiguredConnection: Codable, Equatable, Identifiable {
    var id: String
    var endpoint: String
    var environmentID: String
    var label: String
    var machine: String?
    var credentialID: String?
    var expiresAt: Date

    var identity: T3EnvironmentIdentity {
        T3EnvironmentIdentity(id: environmentID, label: label, machine: machine)
    }
}

struct T3ConnectionStatus: Equatable, Identifiable {
    let connection: T3ConfiguredConnection
    let state: T3CodeConnectionState
    let error: T3CodeConnectionError?
    var id: String { connection.id }
}

struct T3ConfiguredConnectionStore {
    let defaults: UserDefaults
    let client: T3CodeClient

    private struct Document: Codable {
        let version: Int
        let connections: [T3ConfiguredConnection]
    }

    func load() -> [T3ConfiguredConnection] {
        if let data = defaults.data(forKey: DefaultsKey.notchAgentsT3Connections) {
            if let decoded = try? JSONDecoder().decode(Document.self, from: data) {
                return decoded.version == 1 ? Self.uniqueEnvironments(decoded.connections) : []
            }
            // Early multi-environment builds stored the connections array directly.
            // Upgrade it in place before considering the legacy single-endpoint keys.
            if let connections = try? JSONDecoder().decode([T3ConfiguredConnection].self, from: data) {
                let uniqueConnections = Self.uniqueEnvironments(connections)
                save(uniqueConnections)
                return uniqueConnections
            }
        }

        guard let rawEndpoint = defaults.string(forKey: DefaultsKey.notchAgentsT3Endpoint),
              let endpoint = try? client.validateEndpoint(rawEndpoint),
              let environmentID = defaults.string(forKey: DefaultsKey.notchAgentsT3Environment),
              !environmentID.isEmpty,
              let expiresAt = defaults.object(forKey: DefaultsKey.notchAgentsT3Expiry) as? Date else { return [] }
        let record = T3ConfiguredConnection(
            id: UUID().uuidString, endpoint: endpoint.absoluteString, environmentID: environmentID,
            label: defaults.string(forKey: DefaultsKey.notchAgentsT3Label).flatMap { $0.isEmpty ? nil : $0 } ?? "T3 Code",
            machine: defaults.string(forKey: DefaultsKey.notchAgentsT3Machine).flatMap { $0.isEmpty ? nil : $0 },
            credentialID: defaults.string(forKey: DefaultsKey.notchAgentsT3CredentialID).flatMap { $0.isEmpty ? nil : $0 },
            expiresAt: expiresAt)
        // Keep the legacy Keychain account binding intact until this list is durable.
        save([record])
        removeLegacyValues()
        return [record]
    }

    func save(_ connections: [T3ConfiguredConnection]) {
        let document = Document(version: 1, connections: Self.uniqueEnvironments(connections))
        guard let data = try? JSONEncoder().encode(document) else { return }
        defaults.set(data, forKey: DefaultsKey.notchAgentsT3Connections)
    }

    func removeLegacyValues() {
        [DefaultsKey.notchAgentsT3Endpoint, DefaultsKey.notchAgentsT3Environment,
         DefaultsKey.notchAgentsT3CredentialID, DefaultsKey.notchAgentsT3Label,
         DefaultsKey.notchAgentsT3Machine, DefaultsKey.notchAgentsT3Expiry]
            .forEach(defaults.removeObject(forKey:))
    }

    static func uniqueEnvironments(_ connections: [T3ConfiguredConnection]) -> [T3ConfiguredConnection] {
        var seen = Set<String>()
        return connections.filter { seen.insert($0.environmentID).inserted }
    }
}

final class T3CodeActivityService: ObservableObject {
    static let shared = T3CodeActivityService()
    static let transientFailureActivityGrace: TimeInterval = 10

    @Published private(set) var state: T3CodeConnectionState = .notConfigured
    @Published private(set) var activities: [T3ThreadActivity] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var connectionStatuses: [T3ConnectionStatus] = []
    let completed = PassthroughSubject<T3ActivityCompletion, Never>()

    private let client: T3CodeClient
    private let credentials: T3CredentialStore
    private let defaults: UserDefaults
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private var reducers: [String: T3ActivityReducer] = [:]
    private var activitiesByConnection: [String: [T3ThreadActivity]] = [:]
    private var runtimeStates: [String: T3CodeConnectionState] = [:]
    private var errorsByConnection: [String: T3CodeConnectionError] = [:]
    private var tokens: [String: String] = [:]
    private var lastSuccessfulPollAt: [String: Date] = [:]
    private var activityExpiryTasks: [String: Task<Void, Never>] = [:]
    private var pairingInProgress = false
    private var pairingGeneration = UUID()

    private var connectionStore: T3ConfiguredConnectionStore {
        T3ConfiguredConnectionStore(defaults: defaults, client: client)
    }

    private var configuredConnections: [T3ConfiguredConnection] { connectionStore.load() }

    init(client: T3CodeClient = T3CodeClient(), credentials: T3CredentialStore = T3KeychainCredentialStore(),
         defaults: UserDefaults = .standard) {
        self.client = client
        self.credentials = credentials
        self.defaults = defaults
    }

    var endpoint: String { configuredConnections.first?.endpoint ?? "" }
    var configuredEnvironment: String { configuredConnections.first?.environmentID ?? "" }
    var hasSavedConnection: Bool { !configuredConnections.isEmpty }

    static func hasSavedConnection(endpoint: String, environmentID: String) -> Bool {
        !endpoint.isEmpty && !environmentID.isEmpty
    }

    @MainActor func connect(endpoint rawEndpoint: String, pairingCode: String) async throws {
        let endpoint = try client.validateEndpoint(rawEndpoint)
        let generation = UUID()
        pairingGeneration = generation
        pairingInProgress = true
        state = .connecting
        updateConnectionState()
        do {
            let (identity, token, expiry) = try await client.pair(endpoint: endpoint, credential: pairingCode)
            guard !Task.isCancelled, pairingGeneration == generation else { throw CancellationError() }
            let existing = configuredConnections.first { $0.environmentID == identity.id }
            let connectionID = existing?.id ?? UUID().uuidString
            let credentialID = UUID().uuidString
            let account = T3KeychainCredentialStore.account(endpoint: endpoint, environmentID: identity.id,
                                                            credentialID: credentialID)
            let credentialStore = credentials
            let saved = await Task.detached(priority: .utility) {
                credentialStore.write(token, account: account)
            }.value
            guard !Task.isCancelled, pairingGeneration == generation else {
                Task.detached(priority: .utility) { credentialStore.remove(account: account) }
                throw CancellationError()
            }
            guard saved else {
                throw T3CodeConnectionError.readPermissionMissing
            }
            var connections = configuredConnections
            let replacement = T3ConfiguredConnection(id: connectionID, endpoint: endpoint.absoluteString,
                                                     environmentID: identity.id, label: identity.label,
                                                     machine: identity.machine, credentialID: credentialID,
                                                     expiresAt: expiry)
            connections.removeAll { $0.environmentID == identity.id }
            connections.append(replacement)
            connectionStore.save(connections)
            connectionStore.removeLegacyValues()
            if let existing, let oldEndpoint = try? client.validateEndpoint(existing.endpoint) {
                let oldAccount = T3KeychainCredentialStore.account(endpoint: oldEndpoint,
                    environmentID: existing.environmentID, credentialID: existing.credentialID)
                if oldAccount != account {
                    Task.detached(priority: .utility) { credentialStore.remove(account: oldAccount) }
                }
            }
            cancelRuntime(connectionID: connectionID, clearActivity: true)
            tokens[connectionID] = token
            reducers[connectionID] = T3ActivityReducer()
            runtimeStates[connectionID] = .connected
            errorsByConnection[connectionID] = nil
            pairingInProgress = false
            pairingGeneration = UUID()
            publishAggregate()
            updateConnectionState()
            startPolling(replacement)
        } catch {
            if pairingGeneration == generation {
                pairingInProgress = false
                pairingGeneration = UUID()
                syncWithPreferences()
            }
            if error is CancellationError { throw error }
            throw (error as? T3CodeConnectionError) ?? .serverUnavailable
        }
    }

    func disconnect() {
        for connection in configuredConnections { disconnect(connectionID: connection.id) }
    }

    func disconnect(connectionID: String) {
        guard let connection = configuredConnections.first(where: { $0.id == connectionID }) else { return }
        invalidatePairing()
        cancelRuntime(connectionID: connectionID, clearActivity: true)
        connectionStore.save(configuredConnections.filter { $0.id != connectionID })
        if let endpoint = try? client.validateEndpoint(connection.endpoint) {
            let account = T3KeychainCredentialStore.account(endpoint: endpoint,
                environmentID: connection.environmentID, credentialID: connection.credentialID)
            let credentials = self.credentials
            Task.detached(priority: .utility) { credentials.remove(account: account) }
        }
        connectionStatuses.removeAll { $0.id == connectionID }
        updateConnectionState()
        publishAggregate()
    }

    func syncWithPreferences() {
        guard NotchAgentSupport.isEnabled() else { stop(clearActivity: true); return }
        let connections = configuredConnections
        let validIDs = Set(connections.map(\.id))
        for id in Array(tasks.keys) where !validIDs.contains(id) { cancelRuntime(connectionID: id, clearActivity: true) }
        if connections.isEmpty {
            clearAllActivities()
            state = .notConfigured
            connectionStatuses = []
            return
        }
        for connection in connections where tasks[connection.id] == nil && runtimeStates[connection.id] != .needsPairing {
            restoreAndPoll(connection)
        }
        updateConnectionState()
    }

    func pause() { stop(clearActivity: false) }

    func stop(clearActivity: Bool) {
        invalidatePairing()
        for id in Array(tasks.keys) { cancelRuntime(connectionID: id, clearActivity: clearActivity) }
        if clearActivity {
            clearAllActivities()
        }
        updateConnectionState()
    }

    private func restoreAndPoll(_ connection: T3ConfiguredConnection) {
        guard let endpoint = try? client.validateEndpoint(connection.endpoint), connection.expiresAt > Date() else {
            runtimeStates[connection.id] = .needsPairing
            errorsByConnection[connection.id] = nil
            clearActivity(connectionID: connection.id)
            updateConnectionState()
            return
        }
        let account = T3KeychainCredentialStore.account(endpoint: endpoint,
            environmentID: connection.environmentID, credentialID: connection.credentialID)
        let credentials = self.credentials
        runtimeStates[connection.id] = .reconnecting
        let generation = UUID()
        generations[connection.id] = generation
        let id = connection.id
        tasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            var delay: UInt64 = 3
            while !Task.isCancelled, self.generations[id] == generation {
                let lookup = await Task.detached(priority: .utility) { credentials.read(account: account) }.value
                guard !Task.isCancelled, self.generations[id] == generation else { return }
                switch lookup {
                case .found(let token):
                    self.tasks[id] = nil
                    self.tokens[id] = token
                    self.runtimeStates[id] = .connected
                    self.errorsByConnection[id] = nil
                    self.startPolling(connection)
                    return
                case .missing:
                    self.tasks[id] = nil
                    self.runtimeStates[id] = .needsPairing
                    self.errorsByConnection[id] = nil
                    self.clearActivity(connectionID: id)
                    self.updateConnectionState()
                    return
                case .retryable(let status):
                    self.runtimeStates[id] = .reconnecting
                    self.errorsByConnection[id] = .credentialStoreUnavailable(status)
                    self.updateConnectionState()
                    do { try await Task.sleep(for: .seconds(delay)) }
                    catch { return }
                    delay = min(delay * 2, 30)
                }
            }
        }
        updateConnectionState()
    }

    private func startPolling(_ connection: T3ConfiguredConnection) {
        guard let endpoint = try? client.validateEndpoint(connection.endpoint),
              let token = tokens[connection.id],
              Self.shouldStartPolling(featureEnabled: NotchAgentSupport.isEnabled(),
                                      taskAlreadyRunning: tasks[connection.id] != nil,
                                      hasConnection: true) else { return }
        let identity = connection.identity
        let id = connection.id
        let generation = UUID()
        generations[id] = generation
        runtimeStates[id] = .connecting
        tasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            var delay: UInt64 = 3
            while !Task.isCancelled, generation == self.generations[id] {
                do {
                    guard connection.expiresAt > Date() else {
                        self.runtimeStates[id] = .needsPairing
                        self.errorsByConnection[id] = nil
                        self.tokens[id] = nil
                        self.clearActivity(connectionID: id)
                        self.tasks[id] = nil
                        self.updateConnectionState()
                        return
                    }
                    let snapshot = try await self.client.fetchSnapshot(endpoint: endpoint, token: token)
                    guard !Task.isCancelled, generation == self.generations[id] else { return }
                    let next = snapshot.activities(environment: identity)
                    var reducer = self.reducers[id] ?? T3ActivityReducer()
                    for event in reducer.apply(next) { self.completed.send(event) }
                    self.reducers[id] = reducer
                    self.activitiesByConnection[id] = next
                    let successfulPollAt = Date()
                    self.lastUpdated = successfulPollAt
                    self.activityExpiryTasks[id]?.cancel()
                    self.activityExpiryTasks[id] = nil
                    self.lastSuccessfulPollAt[id] = successfulPollAt
                    self.runtimeStates[id] = .connected
                    self.errorsByConnection[id] = nil
                    self.publishAggregate()
                    self.updateConnectionState()
                    delay = 3
                } catch let error as T3CodeConnectionError {
                    guard !Task.isCancelled, generation == self.generations[id] else { return }
                    if error == .authenticationExpired || error == .readPermissionMissing {
                        self.clearActivity(connectionID: id)
                        self.tokens[id] = nil
                        self.runtimeStates[id] = .needsPairing
                        self.errorsByConnection[id] = nil
                        self.tasks[id] = nil
                        self.updateConnectionState()
                        return
                    } else {
                        self.clearActivityAfterTransientFailure(connectionID: id, generation: generation)
                        self.runtimeStates[id] = .reconnecting
                        self.errorsByConnection[id] = error
                    }
                    delay = min(delay * 2, 30)
                } catch {
                    guard !Task.isCancelled, generation == self.generations[id] else { return }
                    self.clearActivityAfterTransientFailure(connectionID: id, generation: generation)
                    self.runtimeStates[id] = .reconnecting
                    self.errorsByConnection[id] = .serverUnavailable
                    delay = min(delay * 2, 30)
                }
                self.updateConnectionState()
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
            }
            if generation == self.generations[id] { self.tasks[id] = nil }
        }
        updateConnectionState()
    }

    private func cancelRuntime(connectionID: String, clearActivity: Bool) {
        generations[connectionID] = UUID()
        tasks[connectionID]?.cancel()
        tasks[connectionID] = nil
        activityExpiryTasks[connectionID]?.cancel()
        activityExpiryTasks[connectionID] = nil
        tokens[connectionID] = nil
        runtimeStates[connectionID] = nil
        errorsByConnection[connectionID] = nil
        if clearActivity {
            reducers[connectionID] = nil
            activitiesByConnection[connectionID] = nil
            lastSuccessfulPollAt[connectionID] = nil
        }
    }

    private func invalidatePairing() {
        pairingGeneration = UUID()
        pairingInProgress = false
    }

    private func clearActivity(connectionID: String) {
        activityExpiryTasks[connectionID]?.cancel()
        activityExpiryTasks[connectionID] = nil
        activitiesByConnection[connectionID] = nil
        reducers[connectionID] = T3ActivityReducer()
        lastSuccessfulPollAt[connectionID] = nil
        publishAggregate()
    }

    private func clearActivityAfterTransientFailure(connectionID: String, generation: UUID, now: Date = .now) {
        guard let lastSuccess = lastSuccessfulPollAt[connectionID],
              let delay = Self.activityExpiryDelay(lastSuccessfulPollAt: lastSuccess, now: now), delay > 0 else {
            clearActivity(connectionID: connectionID)
            return
        }
        guard activityExpiryTasks[connectionID] == nil else { return }
        activityExpiryTasks[connectionID] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, self.generations[connectionID] == generation,
                  self.lastSuccessfulPollAt[connectionID] == lastSuccess else { return }
            self.activityExpiryTasks[connectionID] = nil
            self.clearActivity(connectionID: connectionID)
        }
    }

    private func clearAllActivities() {
        activitiesByConnection.removeAll()
        reducers.removeAll()
        lastSuccessfulPollAt.removeAll()
        activityExpiryTasks.values.forEach { $0.cancel() }
        activityExpiryTasks.removeAll()
        activities = []
        lastUpdated = nil
    }

    private func publishAggregate() {
        activities = T3ActivityAggregator.merge(activitiesByConnection)
    }

    private func updateConnectionState() {
        let connections = configuredConnections
        connectionStatuses = connections.map { connection in
            T3ConnectionStatus(connection: connection,
                state: runtimeStates[connection.id] ?? (connection.expiresAt > Date() ? .reconnecting : .needsPairing),
                error: errorsByConnection[connection.id])
        }
        state = Self.aggregateConnectionState(connectionStatuses.map(\.state), pairingInProgress: pairingInProgress)
    }

    static func aggregateConnectionState(_ states: [T3CodeConnectionState], pairingInProgress: Bool = false)
        -> T3CodeConnectionState {
        if pairingInProgress { return .connecting }
        if states.isEmpty { return .notConfigured }
        if states.contains(.connected) { return .connected }
        if states.contains(.connecting) { return .connecting }
        if states.contains(.reconnecting) { return .reconnecting }
        if states.contains(.needsPairing) { return .needsPairing }
        return .unavailable
    }

    static func shouldStartPolling(featureEnabled: Bool, taskAlreadyRunning: Bool,
                                   hasConnection: Bool) -> Bool {
        featureEnabled && !taskAlreadyRunning && hasConnection
    }

    static func shouldRetainActivityAfterTransientFailure(lastSuccessfulPollAt: Date?, now: Date = .now) -> Bool {
        activityExpiryDelay(lastSuccessfulPollAt: lastSuccessfulPollAt, now: now) != nil
    }

    static func activityExpiryDate(lastSuccessfulPollAt: Date?) -> Date? {
        lastSuccessfulPollAt?.addingTimeInterval(transientFailureActivityGrace)
    }

    static func activityExpiryDelay(lastSuccessfulPollAt: Date?, now: Date) -> TimeInterval? {
        guard let lastSuccessfulPollAt, now >= lastSuccessfulPollAt,
              let expiry = activityExpiryDate(lastSuccessfulPollAt: lastSuccessfulPollAt), now < expiry else { return nil }
        return expiry.timeIntervalSince(now)
    }

}
