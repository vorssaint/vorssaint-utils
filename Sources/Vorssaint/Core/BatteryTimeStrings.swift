// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct BatteryTimeFeatureStrings {
    let title: String
    let systemEstimate: String
    let calculating: String
}

extension FeatureStrings {
    static func batteryTime(_ language: AppLanguage) -> BatteryTimeFeatureStrings {
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

extension BatteryTimeFeatureStrings {
    static let enUS = BatteryTimeFeatureStrings(
        title: "Battery time remaining",
        systemEstimate: "System estimate",
        calculating: "Calculating…"
    )

    static let ptBR = BatteryTimeFeatureStrings(
        title: "Tempo restante da bateria",
        systemEstimate: "Estimativa do sistema",
        calculating: "Calculando…"
    )

    static let tr = BatteryTimeFeatureStrings(
        title: "Kalan pil süresi",
        systemEstimate: "Sistem tahmini",
        calculating: "Hesaplanıyor…"
    )

    static let ru = BatteryTimeFeatureStrings(
        title: "Оставшееся время работы",
        systemEstimate: "Оценка системы",
        calculating: "Расчёт…"
    )

    static let es = BatteryTimeFeatureStrings(
        title: "Tiempo restante de batería",
        systemEstimate: "Estimación del sistema",
        calculating: "Calculando…"
    )

    static let de = BatteryTimeFeatureStrings(
        title: "Verbleibende Batterielaufzeit",
        systemEstimate: "Systemschätzung",
        calculating: "Wird berechnet…"
    )

    static let fr = BatteryTimeFeatureStrings(
        title: "Autonomie restante",
        systemEstimate: "Estimation du système",
        calculating: "Calcul…"
    )

    static let it = BatteryTimeFeatureStrings(
        title: "Autonomia residua",
        systemEstimate: "Stima del sistema",
        calculating: "Calcolo…"
    )

    static let ja = BatteryTimeFeatureStrings(
        title: "バッテリー残り時間",
        systemEstimate: "システムの推定",
        calculating: "計算中…"
    )

    static let ko = BatteryTimeFeatureStrings(
        title: "남은 배터리 시간",
        systemEstimate: "시스템 예상치",
        calculating: "계산 중…"
    )

    static let zhHans = BatteryTimeFeatureStrings(
        title: "电池剩余时间",
        systemEstimate: "系统估算",
        calculating: "正在计算…"
    )

    static let zhTW = BatteryTimeFeatureStrings(
        title: "電池剩餘時間",
        systemEstimate: "系統估算",
        calculating: "正在計算…"
    )

    static let zhHK = BatteryTimeFeatureStrings(
        title: "電池剩餘時間",
        systemEstimate: "系統估算",
        calculating: "正在計算…"
    )
}
