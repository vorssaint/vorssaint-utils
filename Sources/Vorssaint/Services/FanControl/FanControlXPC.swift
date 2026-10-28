// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if VORSSAINT_DEVELOPMENT
import Security
import CryptoKit
#endif

enum FanControlIdentifiers {
    static let teamID = "3D485NHW29"
    /// The stable identity Tools/setup-signing.sh issues for local builds of
    /// this repository. A self-signed leaf cannot anchor to anything Apple
    /// trusts, so its branch pins the identifier and the identity's own name
    /// instead of the team.
    static let localSigningIdentity = "Vorssaint Utils Signing"

    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.utils.dev"
    #else
    static let appBundleID = "com.vorssaint.utils"
    #endif

    static let helperID = "\(appBundleID).fan-control"
    static let plistName = "\(helperID).plist"

    static var appCodeRequirement: String {
        #if VORSSAINT_DEVELOPMENT
        guard let hash = self.currentLeafCertificateSHA1() else {
            return "identifier \"\(appBundleID)\" and certificate leaf = H\"0000000000000000000000000000000000000000\""
        }
        return "identifier \"\(appBundleID)\" and certificate leaf = H\"\(hash)\""
        #else
        // shortcut: an install signed with the stable local identity names that
        // identity instead of the team, <when local builds are signed by Apple>.
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(appBundleID)\""
            + " or (identifier \"\(appBundleID)\" and certificate leaf[subject.CN] = \"\(localSigningIdentity)\")"
        #endif
    }

    static var helperCodeRequirement: String {
        #if VORSSAINT_DEVELOPMENT
        guard let hash = self.currentLeafCertificateSHA1() else {
            return "identifier \"\(helperID)\" and certificate leaf = H\"0000000000000000000000000000000000000000\""
        }
        return "identifier \"\(helperID)\" and certificate leaf = H\"\(hash)\""
        #else
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(helperID)\""
            + " or (identifier \"\(helperID)\" and certificate leaf[subject.CN] = \"\(localSigningIdentity)\")"
        #endif
    }
}

@objc protocol FanControlXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func startMaximumCooling(withReply reply: @escaping (Data) -> Void)
    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
    func heartbeat(withReply reply: @escaping (Data) -> Void)
    func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
}

enum FanControlIPC {
    static func encode(_ response: FanControlResponse) -> Data {
        // Every value in this closed response model is JSON encodable. Keeping
        // one deterministic fallback avoids ever violating the XPC reply shape.
        (try? JSONEncoder().encode(response))
            ?? Data(#"{"succeeded":false,"snapshot":{"fans":[],"isCooling":false},"error":"controlFailed"}"#.utf8)
    }

    static func decode(_ data: Data) -> FanControlResponse? {
        try? JSONDecoder().decode(FanControlResponse.self, from: data)
    }

    static func encode(_ configuration: FanControlConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    static func decodeConfiguration(_ data: Data) -> FanControlConfiguration? {
        guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self,
                                                              from: data),
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}