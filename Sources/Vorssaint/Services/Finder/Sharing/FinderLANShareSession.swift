// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import Network

/// All listener, connection and descriptor ownership lives on one serial queue.
/// A session ends when its window closes, the feature stops, or ten minutes pass.
final class FinderLANShareSession: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var error: String?
    @Published private(set) var stopped = false
    private let queue = DispatchQueue(label: "com.vorssaint.finder-share", qos: .utility)
    private var listener: NWListener?
    private var expiry: DispatchWorkItem?
    private var clients: [UUID: NWConnection] = [:]
    private var lastActivity: [UUID: Date] = [:]
    private var files: [(name: String, descriptor: Int32, bytes: Int64)] = []
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var active = false
    private var host = ""

    func start(_ selection: [URL]) {
        queue.async { [self] in
            guard !active else { return }
            active = true
            do {
                guard !selection.isEmpty, selection.count <= 128 else {
                    throw FinderFileActionError.invalidRequest("Select between 1 and 128 files. Archive folders before sharing them.")
                }
                for item in selection {
                    let descriptor = open(item.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                    guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
                    var info = stat()
                    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                        close(descriptor)
                        throw FinderFileActionError.unsupported(item, "Share regular files; create an archive to share a folder")
                    }
                    files.append((item.lastPathComponent, descriptor, info.st_size))
                }
                guard let address = Self.localIPv4Address() else {
                    throw FinderFileActionError.invalidRequest("Connect to a local Wi-Fi or Ethernet network to share files.")
                }
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: .any)
                let server = try NWListener(using: parameters)
                listener = server
                server.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                server.stateUpdateHandler = { [weak self, weak server] state in
                    guard let self, self.active else { return }
                    switch state {
                    case .ready:
                        guard let port = server?.port else { return }
                        self.host = "\(address):\(port.rawValue)"
                        let url = URL(string: "http://\(self.host)/\(self.token)/")
                        DispatchQueue.main.async { self.url = url }
                    case .failed(let error): self.fail(error)
                    default: break
                    }
                }
                server.start(queue: queue)
                let timeout = DispatchWorkItem { [weak self] in self?.stopOnQueue() }
                expiry = timeout
                queue.asyncAfter(deadline: .now() + 600, execute: timeout)
            } catch { fail(error) }
        }
    }

    func stop() { queue.async { [self] in stopOnQueue() } }

    private func stopOnQueue() {
        active = false
        expiry?.cancel()
        expiry = nil
        listener?.cancel()
        listener = nil
        for client in clients.values { client.cancel() }
        clients.removeAll()
        lastActivity.removeAll()
        for file in files { close(file.descriptor) }
        files.removeAll()
        DispatchQueue.main.async { self.url = nil; self.stopped = true }
    }

    private func fail(_ error: Error) {
        stopOnQueue()
        DispatchQueue.main.async { self.error = error.localizedDescription }
    }

    private func accept(_ connection: NWConnection) {
        guard active, clients.count < 4 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        lastActivity[id] = Date()
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.closeClient(id) }
            if case .cancelled = state { self?.clients.removeValue(forKey: id); self?.lastActivity.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        expireIdleClient(id)
        receive(id, header: Data())
    }

    private func receive(_ id: UUID, header: Data) {
        guard let connection = clients[id], active else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: FinderLANShareProtocol.maximumHeaderBytes) { [weak self] bytes, _, complete, error in
            guard let self, self.active, self.clients[id] != nil else { return }
            var header = header
            if let bytes { header.append(bytes); self.lastActivity[id] = Date() }
            guard error == nil, header.count <= FinderLANShareProtocol.maximumHeaderBytes else { self.closeClient(id); return }
            if header.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(id, header: header) }
            else if complete { self.closeClient(id) }
            else { self.receive(id, header: header) }
        }
    }

    private func respond(_ id: UUID, header: Data) {
        switch FinderLANShareProtocol.route(header, token: token, host: host, fileCount: files.count) {
        case .rejected: closeClient(id)
        case .index:
            let body = FinderLANShareProtocol.index(names: files.map(\.name), token: token)
            let response = FinderLANShareProtocol.responseHeader(length: Int64(body.count), html: true) + body
            clients[id]?.send(content: response, completion: .contentProcessed { [weak self] _ in self?.closeClient(id) })
        case .file(let index):
            let file = files[index]
            let header = FinderLANShareProtocol.responseHeader(length: file.bytes, html: false, filename: file.name)
            clients[id]?.send(content: header, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil { self.closeClient(id) }
                else { self.sendFile(id, index: index, offset: 0) }
            })
        }
    }

    private func sendFile(_ id: UUID, index: Int, offset: Int64) {
        guard active, let connection = clients[id], files.indices.contains(index) else { return }
        let file = files[index]
        guard offset < file.bytes else { closeClient(id); return }
        var data = Data(count: Int(min(65_536, file.bytes - offset)))
        let count = data.withUnsafeMutableBytes { pread(file.descriptor, $0.baseAddress, $0.count, offset) }
        guard count > 0 else { closeClient(id); return }
        data.count = count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil { self.closeClient(id) }
            else {
                self.lastActivity[id] = Date()
                self.sendFile(id, index: index, offset: offset + Int64(count))
            }
        })
    }

    private func closeClient(_ id: UUID) {
        lastActivity.removeValue(forKey: id)
        clients.removeValue(forKey: id)?.cancel()
    }

    private func expireIdleClient(_ id: UUID) {
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, let last = self.lastActivity[id] else { return }
            if Date().timeIntervalSince(last) >= 30 { self.closeClient(id) }
            else { self.expireIdleClient(id) }
        }
    }

    private static func localIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }
        var current = interfaces
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  item.pointee.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            let parts = ip.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 4 else { continue }
            if parts[0] == 10 || (parts[0] == 192 && parts[1] == 168)
                || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254) { return ip }
        }
        return nil
    }
}
