// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if VORSSAINT_DEVELOPMENT
import CryptoKit
import Security
#endif

enum ChargeControlIdentifiers {
    static let teamID = "3D485NHW29"

    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.utils.dev"
    #else
    static let appBundleID = "com.vorssaint.utils"
    #endif

    static let helperID = "\(appBundleID).charge-control"
    static let plistName = "\(helperID).plist"

    #if VORSSAINT_DEVELOPMENT
    // Developer builds may use Apple Development or a local signing identity.
    // Pin the actual signer on both sides; a bundle identifier alone is spoofable.
    private static let signerRequirement: String = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return "never" }
        // The macOS requirement language represents certificate pins as SHA-1.
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "certificate leaf = H\"\(hex)\""
    }()
    static let appCodeRequirement = "\(signerRequirement) and identifier \"\(appBundleID)\""
    static let helperCodeRequirement = "\(signerRequirement) and identifier \"\(helperID)\""
    #else
    static let appCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(appBundleID)\""
    static let helperCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(helperID)\""
    #endif
}

@objc protocol ChargeControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func apply(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreNormal(withReply reply: @escaping (Data) -> Void)
}

enum ChargeControlIPC {
    static func encode(_ response: ChargeControlResponse) -> Data {
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"gate":"allowCharging","isDischarging":false},"error":"controlFailed"}"#.utf8)
    }

    static func decodeResponse(_ data: Data) -> ChargeControlResponse? {
        try? JSONDecoder().decode(ChargeControlResponse.self, from: data)
    }

    static func encode(_ request: ChargeControlRequest) -> Data {
        (try? JSONEncoder().encode(request))
            ?? Data(#"{"gate":"allowCharging","limitPercent":80}"#.utf8)
    }

    static func decodeRequest(_ data: Data) -> ChargeControlRequest? {
        try? JSONDecoder().decode(ChargeControlRequest.self, from: data)
    }
}
