// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Network

/// Just enough MQTT 3.1.1 to follow a Bambu Lab printer through Bambu
/// Cloud's broker: connect over TLS, subscribe to its report topic, publish
/// a request and keep the session alive. The broker's certificate is checked
/// like any other server's.
final class BambuMQTTClient {
    enum Event {
        case connected
        case message(topic: String, payload: Data)
        /// The broker turned down the user name or password.
        case refused
        case disconnected(String?)
    }

    static let port: UInt16 = 8883
    private static let keepAlive: UInt16 = 30

    private let host: String
    private let username: String
    private let password: String
    private let clientID: String
    private let queue = DispatchQueue(label: "com.vorssaint.bambu-mqtt")
    private let onEvent: (Event) -> Void
    private var connection: NWConnection?
    private var buffer = Data()
    private var packetID: UInt16 = 0
    private var pingTimer: DispatchSourceTimer?
    private var finished = false

    init(host: String, username: String, password: String, onEvent: @escaping (Event) -> Void) {
        self.host = host
        self.username = username
        self.password = password
        clientID = "vorssaint-" + String(UUID().uuidString.prefix(8)).lowercased()
        self.onEvent = onEvent
    }

    func start() {
        queue.async { [self] in
            guard connection == nil, !finished, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
            let tls = NWProtocolTLS.Options()
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 10
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port,
                                          using: NWParameters(tls: tls, tcp: tcp))
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
            connection.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            pingTimer?.cancel()
            pingTimer = nil
            guard let connection else { return }
            // Say goodbye first, so the printer frees the session at once
            // instead of waiting out the keep-alive.
            connection.send(content: Data([0xE0, 0x00]), completion: .contentProcessed { [weak self] _ in
                self?.teardown()
            })
        }
    }

    func subscribe(_ topic: String) {
        queue.async { [self] in
            var body = Data()
            body.append(uint16: nextPacketID())
            body.append(mqttString: topic)
            body.append(0x00)
            send(Self.packet(type: 0x82, body: body))
        }
    }

    func publish(_ topic: String, payload: Data) {
        queue.async { [self] in
            var body = Data()
            body.append(mqttString: topic)
            body.append(payload)
            send(Self.packet(type: 0x30, body: body))
        }
    }

    // MARK: Connection

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            send(connectPacket())
            receive()
        case .failed(let error):
            fail(error.localizedDescription)
        case .waiting(let error):
            fail(error.localizedDescription)
        case .cancelled:
            if !finished { fail(nil) }
        default:
            break
        }
    }

    private func fail(_ reason: String?) {
        guard !finished else { return }
        finished = true
        teardown()
        onEvent(.disconnected(reason))
    }

    private func teardown() {
        pingTimer?.cancel()
        pingTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail(error.localizedDescription) }
        })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                buffer.append(data)
                drainPackets()
            }
            if let error { fail(error.localizedDescription); return }
            if done { fail(nil); return }
            if !finished { receive() }
        }
    }

    private func startPing() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.seconds(Int(Self.keepAlive) * 2 / 3)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.send(Data([0xC0, 0x00])) }
        timer.resume()
        pingTimer = timer
    }

    // MARK: Packets

    private func drainPackets() {
        while let (header, body, used) = Self.nextPacket(in: buffer) {
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + used))
            handlePacket(header: header, body: body)
            if finished { return }
        }
    }

    private func handlePacket(header: UInt8, body: Data) {
        switch header >> 4 {
        case 2: // CONNACK
            let code = body.count >= 2 ? body[body.startIndex + 1] : 0xFF
            guard code == 0 else {
                if code == 4 || code == 5 {
                    finished = true
                    teardown()
                    onEvent(.refused)
                } else {
                    fail(Self.refusal(code))
                }
                return
            }
            startPing()
            onEvent(.connected)
        case 3: // PUBLISH
            guard let (topic, payload, id) = Self.parsePublish(header: header, body: body) else { return }
            if let id {
                var ack = Data([0x40, 0x02])
                ack.append(uint16: id)
                send(ack)
            }
            onEvent(.message(topic: topic, payload: payload))
        default: // SUBACK, PINGRESP and the rest need no answer.
            break
        }
    }

    private func connectPacket() -> Data {
        var body = Data()
        body.append(mqttString: "MQTT")
        body.append(0x04)            // protocol level 3.1.1
        body.append(0xC2)            // user name, password, clean session
        body.append(uint16: Self.keepAlive)
        body.append(mqttString: clientID)
        body.append(mqttString: username)
        body.append(mqttString: password)
        return Self.packet(type: 0x10, body: body)
    }

    private func nextPacketID() -> UInt16 {
        packetID = packetID == .max ? 1 : packetID + 1
        return packetID
    }

    static func packet(type: UInt8, body: Data) -> Data {
        var data = Data([type])
        data.append(remainingLength(body.count))
        data.append(body)
        return data
    }

    static func remainingLength(_ value: Int) -> Data {
        var data = Data()
        var value = value
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            data.append(byte)
        } while value > 0
        return data
    }

    /// The first whole packet at the start of `data`: its fixed header byte,
    /// its body and how many bytes it took. Nil until all of it arrived.
    static func nextPacket(in data: Data) -> (UInt8, Data, Int)? {
        guard let header = data.first else { return nil }
        var length = 0
        var multiplier = 1
        var index = data.startIndex + 1
        while true {
            guard index < data.endIndex else { return nil }
            let byte = data[index]
            length += Int(byte & 0x7F) * multiplier
            index += 1
            if byte & 0x80 == 0 { break }
            multiplier *= 128
            guard multiplier <= 128 * 128 * 128 else { return nil }
        }
        guard data.endIndex - index >= length else { return nil }
        let body = data.subdata(in: index..<(index + length))
        return (header, body, index + length - data.startIndex)
    }

    static func parsePublish(header: UInt8, body: Data) -> (String, Data, UInt16?)? {
        guard body.count >= 2 else { return nil }
        let start = body.startIndex
        let topicLength = Int(body[start]) << 8 | Int(body[start + 1])
        var index = start + 2 + topicLength
        guard index <= body.endIndex,
              let topic = String(data: body.subdata(in: (start + 2)..<index), encoding: .utf8) else { return nil }
        var id: UInt16?
        if (header >> 1) & 0x03 > 0 {
            guard index + 2 <= body.endIndex else { return nil }
            id = UInt16(body[index]) << 8 | UInt16(body[index + 1])
            index += 2
        }
        return (topic, body.subdata(in: index..<body.endIndex), id)
    }

    static func refusal(_ code: UInt8) -> String {
        switch code {
        case 4, 5: return "Sign-in was refused"
        case 2: return "Client was refused"
        case 3: return "Printer is not accepting connections"
        default: return "Connection refused (\(code))"
        }
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func append(mqttString string: String) {
        let bytes = Data(string.utf8)
        append(uint16: UInt16(bytes.count))
        append(bytes)
    }
}
