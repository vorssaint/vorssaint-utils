// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the Wi-Fi on sleep feature. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct WiFiSleepStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let restoreToggle: String
    let restoreCaption: String
    let unsupported: String
}

extension FeatureStrings {
    static func wifiSleep(_ language: AppLanguage) -> WiFiSleepStrings {
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

extension WiFiSleepStrings {
    static let enUS = WiFiSleepStrings(
        pageTitle: "Wi-Fi on sleep",
        hubDescription: "Switches Wi-Fi off while the Mac sleeps, so a closed laptop goes dark on networks it is not using.",
        enable: "Turn Wi-Fi off when the Mac sleeps",
        enableCaption: "Wi-Fi already off before sleep is left alone and stays off on wake.",
        restoreToggle: "Turn Wi-Fi back on when the Mac wakes",
        restoreCaption: "Only when Vorssaint was the one that switched it off.",
        unsupported: "This Mac has no Wi-Fi adapter."
    )

    static let ptBR = WiFiSleepStrings(
        pageTitle: "Wi-Fi ao dormir",
        hubDescription: "Desliga o Wi-Fi enquanto o Mac dorme, para que um laptop fechado fique invisível nas redes que não usa.",
        enable: "Desligar o Wi-Fi quando o Mac dormir",
        enableCaption: "O Wi-Fi que já estava desligado antes do repouso não é tocado e continua desligado ao acordar.",
        restoreToggle: "Ligar o Wi-Fi de volta quando o Mac acordar",
        restoreCaption: "Apenas quando foi o Vorssaint que o desligou.",
        unsupported: "Este Mac não tem adaptador Wi-Fi."
    )

    static let tr = WiFiSleepStrings(
        pageTitle: "Uykuda Wi-Fi",
        hubDescription: "Mac uyurken Wi-Fi’ı kapatır, böylece kapalı dizüstü kullanmadığı ağlarda görünmez olur.",
        enable: "Mac uykuya girdiğinde Wi-Fi’ı kapat",
        enableCaption: "Uykudan önce zaten kapalı olan Wi-Fi’a dokunulmaz ve uyanınca da kapalı kalır.",
        restoreToggle: "Mac uyandığında Wi-Fi’ı yeniden aç",
        restoreCaption: "Sadece Vorssaint kapatmışsa yeniden açılır.",
        unsupported: "Bu Mac’te Wi-Fi adaptörü yok."
    )

    static let ru = WiFiSleepStrings(
        pageTitle: "Wi-Fi при сне",
        hubDescription: "Выключает Wi-Fi на время сна Mac, чтобы закрытый ноутбук не светился в сетях, которыми не пользуется.",
        enable: "Выключать Wi-Fi, когда Mac засыпает",
        enableCaption: "Wi-Fi, выключенный до сна, не трогается и остаётся выключенным после пробуждения.",
        restoreToggle: "Включать Wi-Fi обратно, когда Mac просыпается",
        restoreCaption: "Только если его выключил сам Vorssaint.",
        unsupported: "На этом Mac нет адаптера Wi-Fi."
    )

    static let es = WiFiSleepStrings(
        pageTitle: "Wi-Fi en reposo",
        hubDescription: "Apaga el Wi-Fi mientras el Mac duerme, para que un portátil cerrado no aparezca en las redes que no usa.",
        enable: "Apagar el Wi-Fi cuando el Mac entre en reposo",
        enableCaption: "El Wi-Fi ya apagado antes del reposo no se toca y sigue apagado al despertar.",
        restoreToggle: "Volver a encender el Wi-Fi cuando el Mac despierte",
        restoreCaption: "Solo cuando fue Vorssaint el que lo apagó.",
        unsupported: "Este Mac no tiene adaptador Wi-Fi."
    )

    static let de = WiFiSleepStrings(
        pageTitle: "WLAN im Ruhezustand",
        hubDescription: "Schaltet das WLAN aus, während der Mac schläft, damit ein geschlossenes Laptop in Netzwerken, die es nicht nutzt, unsichtbar bleibt.",
        enable: "WLAN ausschalten, wenn der Mac schläft",
        enableCaption: "WLAN, das vor dem Ruhezustand schon aus war, bleibt unberührt und nach dem Aufwachen aus.",
        restoreToggle: "WLAN wieder einschalten, wenn der Mac aufwacht",
        restoreCaption: "Nur wenn Vorssaint es ausgeschaltet hat.",
        unsupported: "Dieser Mac hat kein WLAN-Modul."
    )

    static let fr = WiFiSleepStrings(
        pageTitle: "Wi-Fi en veille",
        hubDescription: "Coupe le Wi-Fi pendant que le Mac dort, pour qu’un ordinateur fermé reste invisible sur les réseaux qu’il n’utilise pas.",
        enable: "Couper le Wi-Fi quand le Mac se met en veille",
        enableCaption: "Le Wi-Fi déjà coupé avant la veille n’est pas touché et reste coupé au réveil.",
        restoreToggle: "Rallumer le Wi-Fi quand le Mac se réveille",
        restoreCaption: "Seulement si c’est Vorssaint qui l’avait coupé.",
        unsupported: "Ce Mac n’a pas de carte Wi-Fi."
    )

    static let it = WiFiSleepStrings(
        pageTitle: "Wi-Fi in stop",
        hubDescription: "Spegne il Wi-Fi mentre il Mac dorme, così un laptop chiuso resta invisibile nelle reti che non usa.",
        enable: "Spegni il Wi-Fi quando il Mac va in stop",
        enableCaption: "Il Wi-Fi già spento prima dello stop non viene toccato e resta spento al risveglio.",
        restoreToggle: "Riaccendi il Wi-Fi quando il Mac si sveglia",
        restoreCaption: "Solo se è stato Vorssaint a spegnerlo.",
        unsupported: "Questo Mac non ha una scheda Wi-Fi."
    )

    static let ja = WiFiSleepStrings(
        pageTitle: "スリープ時のWi-Fi",
        hubDescription: "Macのスリープ中はWi-Fiを切るので、閉じたノートブックは使っていないネットワークに姿を現しません。",
        enable: "Macがスリープに入ったらWi-Fiを切る",
        enableCaption: "スリープ前にすでに切っていたWi-Fiには触れず、目覚めた後も切ったままにします。",
        restoreToggle: "Macが目覚めたらWi-Fiをもう一度入れる",
        restoreCaption: "Vorssaintが切ったときだけ入れ直します。",
        unsupported: "このMacにはWi-Fiアダプタがありません。"
    )

    static let ko = WiFiSleepStrings(
        pageTitle: "잠자는 동안의 Wi-Fi",
        hubDescription: "Mac이 잠자는 동안 Wi-Fi를 꺼서 닫힌 노트북이 쓰지 않는 네트워크에 나타나지 않게 합니다.",
        enable: "Mac이 잠자기에 들어가면 Wi-Fi 끄기",
        enableCaption: "잠자기 전에 이미 꺼져 있던 Wi-Fi는 건드리지 않고 깨어난 뒤에도 꺼진 채로 둡니다.",
        restoreToggle: "Mac이 깨어나면 Wi-Fi 다시 켜기",
        restoreCaption: "Vorssaint가 껐을 때만 다시 켭니다.",
        unsupported: "이 Mac에는 Wi-Fi 어댑터가 없습니다."
    )

    static let zhHans = WiFiSleepStrings(
        pageTitle: "睡眠时的 Wi-Fi",
        hubDescription: "Mac 睡眠期间关闭 Wi-Fi，合上的笔记本不会出现在没在使用的网络里。",
        enable: "Mac 进入睡眠时关闭 Wi-Fi",
        enableCaption: "睡前已经关闭的 Wi-Fi 不会被改动，醒来后也保持关闭。",
        restoreToggle: "Mac 唤醒时重新打开 Wi-Fi",
        restoreCaption: "只有 Vorssaint 关掉的情况下才会重新打开。",
        unsupported: "这台 Mac 没有 Wi-Fi 适配器。"
    )

    static let zhTW = WiFiSleepStrings(
        pageTitle: "睡眠時的 Wi-Fi",
        hubDescription: "Mac 睡眠期間關閉 Wi-Fi，合上的筆電不會出現在沒在使用的網路裡。",
        enable: "Mac 進入睡眠時關閉 Wi-Fi",
        enableCaption: "睡前已經關閉的 Wi-Fi 不會被更動，醒來後也保持關閉。",
        restoreToggle: "Mac 喚醒時重新開啟 Wi-Fi",
        restoreCaption: "只有 Vorssaint 關掉的情況下才會重新開啟。",
        unsupported: "這台 Mac 沒有 Wi-Fi 介面卡。"
    )

    static let zhHK = WiFiSleepStrings(
        pageTitle: "睡眠時的 Wi-Fi",
        hubDescription: "Mac 睡眠期間關閉 Wi-Fi，合上嘅手提電腦唔會喺無用緊嘅網絡出現。",
        enable: "Mac 進入睡眠時關閉 Wi-Fi",
        enableCaption: "睡前已經關閉嘅 Wi-Fi 唔會被改動，醒返之後都保持關閉。",
        restoreToggle: "Mac 醒返時重新開啟 Wi-Fi",
        restoreCaption: "只有 Vorssaint 關咗嘅情況下先會重新開啟。",
        unsupported: "呢部 Mac 冇 Wi-Fi 卡。"
    )
}
