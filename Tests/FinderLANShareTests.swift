// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderLANShareTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder local sharing request boundary") {
            let token = "opaque-token"
            let host = "192.168.1.2:8080"
            func route(_ path: String, method: String = "GET", host suppliedHost: String? = nil) -> FinderLANShareProtocol.Route {
                FinderLANShareProtocol.route(Data("\(method) \(path) HTTP/1.1\r\nHost: \(suppliedHost ?? host)\r\n\r\n".utf8),
                    token: token, host: host, fileCount: 2)
            }
            suite.expect(route("/opaque-token/") == .index && route("/opaque-token/file/1") == .file(1),
                         "authorized requests address only the explicit selection")
            for path in ["/", "/other-token/file/0", "/opaque-token/file/2", "/opaque-token/file/-1",
                         "/opaque-token/file/00", "/opaque-token/file/../0", "/opaque-token/file/%30", "/opaque-token/file/0?x=1"] {
                suite.expect(route(path) == .rejected, "route rejects unselected or ambiguous resource: \(path)")
            }
            suite.expect(route("/opaque-token/", method: "POST") == .rejected
                         && route("/opaque-token/", host: "attacker.example") == .rejected,
                         "uploads and browser DNS-rebinding hosts are rejected")
            let index = String(decoding: FinderLANShareProtocol.index(names: ["<script>alert(1)</script>.txt"], token: token), as: UTF8.self)
            suite.expect(!index.contains("<script>") && index.contains("&lt;script&gt;"),
                         "shared filenames are HTML data rather than script")
            let header = String(decoding: FinderLANShareProtocol.responseHeader(length: 3, html: false,
                filename: "bad\r\nInjected: true.txt"), as: UTF8.self)
            suite.expect(!header.contains("\r\nInjected:"), "download names cannot inject HTTP response headers")
        }
    }
}
