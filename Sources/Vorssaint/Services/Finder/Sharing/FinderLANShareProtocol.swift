// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A short-lived download link exposes only explicit selection indices. No
/// request path is ever interpreted as a filesystem path.
enum FinderLANShareProtocol {
    enum Route: Equatable { case index, file(Int), rejected }
    static let maximumHeaderBytes = 16_384

    static func route(_ data: Data, token: String, host: String, fileCount: Int) -> Route {
        guard data.count <= maximumHeaderBytes, let text = String(data: data, encoding: .utf8),
              text.hasSuffix("\r\n\r\n") else { return .rejected }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[0] == "GET", first[2] == "HTTP/1.1" else { return .rejected }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard hosts.count == 1,
              hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == host,
              !lines.contains(where: { $0.lowercased().hasPrefix("transfer-encoding:") || $0.lowercased().hasPrefix("content-length:") }) else { return .rejected }
        let path = String(first[1])
        if path == "/\(token)/" { return .index }
        let prefix = "/\(token)/file/"
        guard path.hasPrefix(prefix) else { return .rejected }
        let tail = String(path.dropFirst(prefix.count))
        guard let index = Int(tail), String(index) == tail, (0..<fileCount).contains(index) else { return .rejected }
        return .file(index)
    }

    static func index(names: [String], token: String) -> Data {
        let links = names.enumerated().map { index, name in
            "<li><a href=\"/\(token)/file/\(index)\" download>\(escapeHTML(name))</a></li>"
        }.joined()
        return Data("<!doctype html><html><head><meta charset=\"utf-8\"><title>Vorssaint</title></head><body><h1>Vorssaint</h1><ul>\(links)</ul></body></html>".utf8)
    }

    static func responseHeader(length: Int64, html: Bool, filename: String? = nil) -> Data {
        var header = "HTTP/1.1 200 OK\r\nContent-Length: \(length)\r\nContent-Type: \(html ? "text/html; charset=utf-8" : "application/octet-stream")\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; frame-ancestors 'none'\r\n"
        if let filename {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            header += "Content-Disposition: attachment; filename*=UTF-8''\(filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? "download")\r\n"
        }
        return Data((header + "\r\n").utf8)
    }

    private static func escapeHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
}
