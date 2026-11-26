// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The parts of Bambu Lab's account service the island needs: signing in,
/// finding the account's MQTT user name and listing its printers. This is
/// the same unofficial service Bambu's own apps use; it is undocumented and
/// can change without notice.
enum BambuCloudAPI {
    static let apiBase = URL(string: "https://api.bambulab.com")!
    static let webBase = URL(string: "https://bambulab.com")!
    /// The global broker; accounts registered in mainland China use another.
    static let mqttHost = "us.mqtt.bambulab.com"

    enum LoginResult: Equatable {
        case token(String)
        /// Bambu emails a six-digit code; sign in again with it.
        case needsEmailCode
        /// The account uses an authenticator app.
        case needsTwoFactor(key: String)
    }

    struct Device: Equatable, Identifiable {
        let serial: String
        let name: String
        let model: String
        let online: Bool
        var id: String { serial }
    }

    enum Failure: LocalizedError, Equatable {
        case rejected(String)
        case unexpected

        var errorDescription: String? {
            switch self {
            case .rejected(let message): return message
            case .unexpected: return nil
            }
        }
    }

    // MARK: Requests

    static func login(email: String, password: String) async throws -> LoginResult {
        let json = try await post("v1/user-service/user/login",
                                  body: ["account": email, "password": password, "apiError": ""])
        return try loginResult(json)
    }

    static func sendEmailCode(email: String) async throws {
        _ = try await post("v1/user-service/user/sendemail/code", body: ["email": email, "type": "codeLogin"])
    }

    static func login(email: String, code: String) async throws -> String {
        let json = try await post("v1/user-service/user/login", body: ["account": email, "code": code])
        guard case .token(let token) = try loginResult(json) else { throw Failure.unexpected }
        return token
    }

    /// The authenticator step answers on the website, which hands the token
    /// back as a cookie rather than in the body.
    static func login(twoFactorKey: String, code: String) async throws -> String {
        var request = URLRequest(url: webBase.appendingPathComponent("api/sign-in/tfa"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tfaKey": twoFactorKey, "tfaCode": code])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.unexpected }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: webBase)
        if let token = cookies.first(where: { $0.name == "token" })?.value, !token.isEmpty { return token }
        throw Failure.rejected(message(in: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
    }

    /// The MQTT user name for the account: its numeric id after `u_`.
    static func mqttUsername(token: String) async throws -> String {
        let json = try await get("v1/design-user-service/my/preference", token: token)
        guard let uid = PrinterStatus.int(json["uid"]) else { throw Failure.unexpected }
        return "u_\(uid)"
    }

    static func devices(token: String) async throws -> [Device] {
        let json = try await get("v1/iot-service/api/user/bind", token: token)
        return parseDevices(json)
    }

    // MARK: Parsing

    static func loginResult(_ json: [String: Any]) throws -> LoginResult {
        if let token = json["accessToken"] as? String, !token.isEmpty { return .token(token) }
        switch json["loginType"] as? String {
        case "verifyCode": return .needsEmailCode
        case "tfa":
            guard let key = json["tfaKey"] as? String, !key.isEmpty else { throw Failure.unexpected }
            return .needsTwoFactor(key: key)
        default:
            if let message = message(in: json) { throw Failure.rejected(message) }
            throw Failure.unexpected
        }
    }

    static func parseDevices(_ json: [String: Any]) -> [Device] {
        let list = json["devices"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let serial = item["dev_id"] as? String, !serial.isEmpty else { return nil }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? serial
            let model = item["dev_product_name"] as? String ?? item["dev_model_name"] as? String ?? ""
            return Device(serial: serial, name: name, model: model, online: item["online"] as? Bool ?? false)
        }
    }

    static func message(in json: [String: Any]) -> String? {
        for key in ["error", "message"] {
            if let text = json[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private static func message(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { message(in: $0) }
    }

    // MARK: Transport

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private static func post(_ path: String, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: apiBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await decode(send(request))
    }

    private static func get(_ path: String, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: apiBase.appendingPathComponent(path))
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return try await decode(send(request))
    }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("Vorssaint", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }

    private static func decode(_ result: (Data, URLResponse)) throws -> [String: Any] {
        let (data, response) = result
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.rejected(message(in: json) ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return json
    }
}
