// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MonitorLayoutFeatureStrings {
    /// Heading for the settings shared by the menu bar and the panel.
    let shared: String
}

extension FeatureStrings {
    static func monitorLayout(_ language: AppLanguage) -> MonitorLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension MonitorLayoutFeatureStrings {
    static let enUS = MonitorLayoutFeatureStrings(shared: "Readings and alerts")
    static let ptBR = MonitorLayoutFeatureStrings(shared: "Leituras e alertas")
    static let tr = MonitorLayoutFeatureStrings(shared: "Ölçümler ve uyarılar")
    static let ru = MonitorLayoutFeatureStrings(shared: "Показания и оповещения")
    static let es = MonitorLayoutFeatureStrings(shared: "Lecturas y alertas")
    static let de = MonitorLayoutFeatureStrings(shared: "Messwerte und Warnungen")
    static let fr = MonitorLayoutFeatureStrings(shared: "Mesures et alertes")
    static let it = MonitorLayoutFeatureStrings(shared: "Letture e avvisi")
    static let ja = MonitorLayoutFeatureStrings(shared: "計測と通知")
    static let ko = MonitorLayoutFeatureStrings(shared: "측정값 및 알림")
    static let zhHans = MonitorLayoutFeatureStrings(shared: "读数与提醒")
    static let zhTW = MonitorLayoutFeatureStrings(shared: "讀數與提醒")
    static let zhHK = MonitorLayoutFeatureStrings(shared: "讀數與提醒")
}
