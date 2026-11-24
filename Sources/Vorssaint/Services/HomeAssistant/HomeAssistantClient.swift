// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

protocol HomeAssistantTransport: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

/// Credentials are sent only after HA's authentication challenge. Never follow redirects.
final class HomeAssistantWebSocket: NSObject, HomeAssistantTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    init(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 16 * 1024 * 1024
        super.init()
        socket.resume()
    }
    func send(_ text: String) async throws { try await socket.send(.string(text)) }
    func receive() async throws -> String {
        switch try await socket.receive() {
        case .string(let text): return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { throw HomeAssistantFailure.protocolError }
            return text
        @unknown default: throw HomeAssistantFailure.protocolError
        }
    }
    func close() { socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}

enum HomeAssistantEvent: Sendable {
    case snapshot([HomeAssistantEntity])
    case changed(String, HomeAssistantValue)
}

/// One actor owns message IDs, continuations and socket lifetime. No command is retried.
actor HomeAssistantClient {
    private let transport: any HomeAssistantTransport
    private let timeout: UInt64
    private var nextID = 1
    private var receiver: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<HomeAssistantValue, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var events: AsyncThrowingStream<HomeAssistantEvent, Error>.Continuation?
    private var closed = false
    private(set) var temperatureUnit = ""

    init(transport: any HomeAssistantTransport, timeout: UInt64 = 10_000_000_000) {
        self.transport = transport; self.timeout = timeout
    }

    func connect(token: String) async throws -> AsyncThrowingStream<HomeAssistantEvent, Error> {
        guard !closed, receiver == nil else { throw HomeAssistantFailure.network }
        let watchdog = Task { [transport, timeout] in
            try? await Task.sleep(nanoseconds: timeout)
            if !Task.isCancelled { transport.close() }
        }
        defer { watchdog.cancel() }
        do {
            let challenge = try await read()
            guard challenge["type"]?.string == "auth_required" else { throw HomeAssistantFailure.protocolError }
            try await write(["type": .string("auth"), "access_token": .string(token)])
            let authentication = try await read()
            if authentication["type"]?.string == "auth_invalid" { throw HomeAssistantFailure.credentials }
            guard authentication["type"]?.string == "auth_ok" else { throw HomeAssistantFailure.protocolError }
            guard !closed, !Task.isCancelled else { throw CancellationError() }
            let stream = AsyncThrowingStream<HomeAssistantEvent, Error> { events = $0 }
            receiver = Task { [weak self] in await self?.receiveLoop() }
            let configuration = try await request(["type": .string("get_config")])
            temperatureUnit = configuration.object?["unit_system"]?.object?["temperature"]?.string ?? ""
            _ = try await request(["type": .string("subscribe_events"), "event_type": .string("state_changed")])
            try await refresh()
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                        guard let self else { return }
                        _ = try await self.request(["type": .string("ping")])
                    } catch {
                        await self?.close(error: HomeAssistantFailure.network)
                        return
                    }
                }
            }
            return stream
        } catch {
            close(error: error)
            throw error
        }
    }

    func refresh() async throws {
        let states = try await request(["type": .string("get_states")])
        let data = try JSONEncoder().encode(states)
        let entities = try JSONDecoder().decode([HomeAssistantEntity].self, from: data)
        events?.yield(.snapshot(entities))
    }

    func perform(_ action: HomeAssistantAction) async throws { _ = try await request(action.message) }

    private func request(_ message: [String: HomeAssistantValue]) async throws -> HomeAssistantValue {
        guard !closed else { throw HomeAssistantFailure.network }
        let id = nextID; nextID += 1
        var message = message; message["id"] = .number(Double(id))
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task { [weak self, timeout] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                await self?.expire(id)
            }
            Task { [weak self] in
                do { try await self?.write(message) }
                catch { await self?.close(error: HomeAssistantFailure.network) }
            }
        }
    }

    private func expire(_ id: Int) {
        deadlines.removeValue(forKey: id)
        pending.removeValue(forKey: id)?.resume(throwing: HomeAssistantFailure.timeout)
    }
    private func write(_ message: [String: HomeAssistantValue]) async throws {
        guard !closed else { throw CancellationError() }
        let data = try JSONEncoder().encode(message)
        try await transport.send(String(decoding: data, as: UTF8.self))
    }
    private func read() async throws -> [String: HomeAssistantValue] {
        let text = try await transport.receive()
        return try JSONDecoder().decode([String: HomeAssistantValue].self, from: Data(text.utf8))
    }
    private func receiveLoop() async {
        do {
            while !Task.isCancelled, !closed {
                let message = try await read()
                if message["type"]?.string == "event",
                   let data = message["event"]?.object?["data"]?.object,
                   let id = data["entity_id"]?.string, let value = data["new_state"] {
                    events?.yield(.changed(id, value))
                } else if ["result", "pong"].contains(message["type"]?.string ?? ""),
                          let number = message["id"]?.number, number >= 1, number < Double(Int.max), number.rounded() == number {
                    let id = Int(number)
                    guard let continuation = pending.removeValue(forKey: id) else { continue }
                    deadlines.removeValue(forKey: id)?.cancel()
                    if message["type"]?.string == "pong" || message["success"] == .bool(true) {
                        continuation.resume(returning: message["result"] ?? .null)
                    } else { continuation.resume(throwing: HomeAssistantFailure.rejected) }
                }
            }
        } catch { close(error: HomeAssistantFailure.network) }
    }

    func close(error: Error = CancellationError()) {
        guard !closed else { return }
        closed = true
        transport.close()
        receiver?.cancel(); receiver = nil
        heartbeat?.cancel(); heartbeat = nil
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        let waiting = pending.values; pending.removeAll()
        waiting.forEach { $0.resume(throwing: error) }
        events?.finish(throwing: error); events = nil
    }
}
