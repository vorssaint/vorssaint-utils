// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TMobileGatewayIntegrationTests {
    static func run(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.monitorNetTMobile] as? Bool == false,
                     "gateway polling requires an explicit opt-in on each Mac")
        let exportedKeys = SettingsBackupSupport.exportKeys()
        suite.expect(!exportedKeys.contains(DefaultsKey.menuBarTMobile)
                     && SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.menuBarTMobile),
                     "portable backups cannot enable background radio polling")
        suite.expect(!exportedKeys.contains(DefaultsKey.monitorNetTMobile)
                     && !exportedKeys.contains(DefaultsKey.tMobileGatewayAddress),
                     "restoring a backup cannot enable requests to another network's gateway")
        let info = NSDictionary(contentsOfFile: "Resources/Info.plist")
        let transport = info?["NSAppTransportSecurity"] as? [String: Any]
        suite.expect(transport?["NSAllowsLocalNetworking"] as? Bool == true
                     && transport?["NSAllowsArbitraryLoads"] as? Bool != true,
                     "HTTP gateway reads use the local ATS exception without disabling internet ATS")
        for language in AppLanguage.allCases {
            let strings = TMobileGatewayStrings.localized(language)
            let fields = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(!fields.isEmpty && fields.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                         "gateway labels and recovery instructions exist for \(language.rawValue)")
        }
        let english = Mirror(reflecting: TMobileGatewayStrings.localized(.enUS)).children
        for language in AppLanguage.allCases {
            let localized = Mirror(reflecting: TMobileGatewayStrings.localized(language)).children
            for (base, field) in zip(english, localized) where base.label?.hasSuffix("Format") == true {
                let placeholders = { (value: Any) in (value as? String)?.components(separatedBy: "%@").count }
                suite.expect(placeholders(base.value) == placeholders(field.value),
                             "\(base.label ?? "") keeps its placeholders in \(language.rawValue)")
            }
        }
        for language in info?["CFBundleLocalizations"] as? [String] ?? [] {
            let localized = language == "en" ? info
                : NSDictionary(contentsOfFile: "Resources/\(language).lproj/InfoPlist.strings")
            let prompt = localized?["NSLocalNetworkUsageDescription"] as? String ?? ""
            suite.expect(!prompt.isEmpty, "local network consent explains gateway reads in \(language)")
        }
    }
}
