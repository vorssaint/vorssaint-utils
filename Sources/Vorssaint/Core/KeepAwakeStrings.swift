// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct KeepAwakeAutomationStrings {
    let automationSection: String
    let automationCaption: String
    let automationOff: String
    let externalDisplayToggle: String
    let externalDisplayActive: String
    let powerToggle: String
    let powerActive: String
    let automationActive: String

    func activeStatus(for conditions: Set<KeepAwakeAutomationCondition>) -> String {
        if conditions == [.externalDisplay] { return externalDisplayActive }
        if conditions == [.power] { return powerActive }
        return automationActive
    }
}

extension FeatureStrings {
    static func keepAwakeAutomation(_ language: AppLanguage) -> KeepAwakeAutomationStrings {
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

extension KeepAwakeAutomationStrings {
    static let enUS = KeepAwakeAutomationStrings(
        automationSection: "Automation",
        automationCaption: "Starts when any selected condition is active.",
        automationOff: "Off",
        externalDisplayToggle: "External display",
        externalDisplayActive: "Active while an external display is connected",
        powerToggle: "Power",
        powerActive: "Active while connected to power",
        automationActive: "Active because an automatic condition is met"
    )

    static let ptBR = KeepAwakeAutomationStrings(
        automationSection: "Automação",
        automationCaption: "Inicia quando qualquer condição selecionada estiver ativa.",
        automationOff: "Desligado",
        externalDisplayToggle: "Monitor externo",
        externalDisplayActive: "Ativo enquanto há um monitor externo conectado",
        powerToggle: "Energia",
        powerActive: "Ativo enquanto está conectado à energia",
        automationActive: "Ativo porque uma condição automática foi atendida"
    )

    static let tr = KeepAwakeAutomationStrings(
        automationSection: "Otomasyon",
        automationCaption: "Seçilen koşullardan biri etkinken başlar.",
        automationOff: "Kapalı",
        externalDisplayToggle: "Harici ekran",
        externalDisplayActive: "Harici ekran bağlı olduğu sürece etkin",
        powerToggle: "Güç",
        powerActive: "Güce bağlı olduğu sürece etkin",
        automationActive: "Otomatik bir koşul sağlandığı için etkin"
    )

    static let ru = KeepAwakeAutomationStrings(
        automationSection: "Автоматизация",
        automationCaption: "Запускается при выполнении любого выбранного условия.",
        automationOff: "Выкл.",
        externalDisplayToggle: "Внешний дисплей",
        externalDisplayActive: "Активно, пока подключён внешний дисплей",
        powerToggle: "Питание",
        powerActive: "Активно, пока подключено питание",
        automationActive: "Активно по автоматическому условию"
    )

    static let es = KeepAwakeAutomationStrings(
        automationSection: "Automatización",
        automationCaption: "Se inicia cuando se cumple cualquier condición seleccionada.",
        automationOff: "Desactivado",
        externalDisplayToggle: "Pantalla externa",
        externalDisplayActive: "Activo mientras haya una pantalla externa conectada",
        powerToggle: "Corriente",
        powerActive: "Activo mientras está conectado a la corriente",
        automationActive: "Activo porque se cumple una condición automática"
    )

    static let de = KeepAwakeAutomationStrings(
        automationSection: "Automatik",
        automationCaption: "Startet, wenn eine ausgewählte Bedingung erfüllt ist.",
        automationOff: "Aus",
        externalDisplayToggle: "Externes Display",
        externalDisplayActive: "Aktiv, solange ein externes Display verbunden ist",
        powerToggle: "Strom",
        powerActive: "Aktiv, solange Strom verbunden ist",
        automationActive: "Aktiv, weil eine automatische Bedingung erfüllt ist"
    )

    static let fr = KeepAwakeAutomationStrings(
        automationSection: "Automatisation",
        automationCaption: "Démarre lorsqu'une condition sélectionnée est remplie.",
        automationOff: "Désactivé",
        externalDisplayToggle: "Écran externe",
        externalDisplayActive: "Actif tant qu'un écran externe est connecté",
        powerToggle: "Secteur",
        powerActive: "Actif tant que le Mac est branché sur secteur",
        automationActive: "Actif car une condition automatique est remplie"
    )

    static let it = KeepAwakeAutomationStrings(
        automationSection: "Automazione",
        automationCaption: "Si avvia quando una condizione selezionata è soddisfatta.",
        automationOff: "Disattivato",
        externalDisplayToggle: "Schermo esterno",
        externalDisplayActive: "Attivo mentre è collegato uno schermo esterno",
        powerToggle: "Alimentazione",
        powerActive: "Attivo mentre è collegato all'alimentazione",
        automationActive: "Attivo perché una condizione automatica è soddisfatta"
    )

    static let ja = KeepAwakeAutomationStrings(
        automationSection: "自動化",
        automationCaption: "選択した条件のいずれかが満たされると開始します。",
        automationOff: "オフ",
        externalDisplayToggle: "外部ディスプレイ",
        externalDisplayActive: "外部ディスプレイ接続中は有効",
        powerToggle: "電源",
        powerActive: "電源に接続されている間は有効",
        automationActive: "自動条件が満たされているため有効"
    )

    static let ko = KeepAwakeAutomationStrings(
        automationSection: "자동화",
        automationCaption: "선택한 조건 중 하나가 충족되면 시작합니다.",
        automationOff: "꺼짐",
        externalDisplayToggle: "외부 디스플레이",
        externalDisplayActive: "외부 디스플레이가 연결된 동안 활성화",
        powerToggle: "전원",
        powerActive: "전원에 연결된 동안 활성화",
        automationActive: "자동 조건이 충족되어 활성화"
    )

    static let zhHans = KeepAwakeAutomationStrings(
        automationSection: "自动化",
        automationCaption: "任一所选条件满足时自动启动。",
        automationOff: "关闭",
        externalDisplayToggle: "外接显示器",
        externalDisplayActive: "外接显示器连接期间保持唤醒",
        powerToggle: "电源",
        powerActive: "连接电源期间保持唤醒",
        automationActive: "因满足自动条件而保持唤醒"
    )

    static let zhTW = KeepAwakeAutomationStrings(
        automationSection: "自動化",
        automationCaption: "任一所選條件符合時自動啟動。",
        automationOff: "關閉",
        externalDisplayToggle: "外接顯示器",
        externalDisplayActive: "外接顯示器連接期間保持喚醒",
        powerToggle: "電源",
        powerActive: "連接電源期間保持喚醒",
        automationActive: "因符合自動條件而保持喚醒"
    )

    static let zhHK = KeepAwakeAutomationStrings(
        automationSection: "自動化",
        automationCaption: "任何所選條件符合時自動啟動。",
        automationOff: "關閉",
        externalDisplayToggle: "外置顯示器",
        externalDisplayActive: "外置顯示器連接期間保持喚醒",
        powerToggle: "電源",
        powerActive: "連接電源期間保持喚醒",
        automationActive: "因符合自動條件而保持喚醒"
    )
}
