// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the Bluetooth on sleep feature. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct BluetoothSleepStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let restoreToggle: String
    let restoreCaption: String
    let unsupported: String
}

extension FeatureStrings {
    static func bluetoothSleep(_ language: AppLanguage) -> BluetoothSleepStrings {
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

extension BluetoothSleepStrings {
    static let enUS = BluetoothSleepStrings(
        pageTitle: "Bluetooth on sleep",
        hubDescription: "Switches Bluetooth off while the Mac sleeps, so headphones in a bag stop connecting to it.",
        enable: "Turn Bluetooth off when the Mac sleeps",
        enableCaption: "Bluetooth already off before sleep is left alone and stays off on wake.",
        restoreToggle: "Turn Bluetooth back on when the Mac wakes",
        restoreCaption: "Only when Vorssaint was the one that switched it off.",
        unsupported: "This Mac has no Bluetooth controller."
    )

    static let ptBR = BluetoothSleepStrings(
        pageTitle: "Bluetooth ao dormir",
        hubDescription: "Desliga o Bluetooth enquanto o Mac dorme, para que os fones na mochila parem de se conectar.",
        enable: "Desligar o Bluetooth quando o Mac dormir",
        enableCaption: "O Bluetooth que já estava desligado antes do repouso não é tocado e continua desligado ao acordar.",
        restoreToggle: "Ligar o Bluetooth de volta quando o Mac acordar",
        restoreCaption: "Apenas quando foi o Vorssaint que o desligou.",
        unsupported: "Este Mac não tem controlador Bluetooth."
    )

    static let tr = BluetoothSleepStrings(
        pageTitle: "Uykuda Bluetooth",
        hubDescription: "Mac uyurken Bluetooth'u kapatır, böylece çantadaki kulaklıklar bağlanmayı bırakır.",
        enable: "Mac uyuduğunda Bluetooth'u kapat",
        enableCaption: "Uykudan önce zaten kapalı olan Bluetooth'a dokunulmaz ve uyanışta kapalı kalır.",
        restoreToggle: "Mac uyandığında Bluetooth'u yeniden aç",
        restoreCaption: "Yalnızca kapatan Vorssaint olduğunda.",
        unsupported: "Bu Mac'te Bluetooth denetleyicisi yok."
    )

    static let ru = BluetoothSleepStrings(
        pageTitle: "Bluetooth при сне",
        hubDescription: "Выключает Bluetooth на время сна Mac, чтобы наушники в сумке перестали к нему подключаться.",
        enable: "Выключать Bluetooth, когда Mac засыпает",
        enableCaption: "Bluetooth, уже выключенный до сна, не трогается и остаётся выключенным после пробуждения.",
        restoreToggle: "Включать Bluetooth обратно при пробуждении Mac",
        restoreCaption: "Только если его выключил сам Vorssaint.",
        unsupported: "На этом Mac нет контроллера Bluetooth."
    )

    static let es = BluetoothSleepStrings(
        pageTitle: "Bluetooth al reposo",
        hubDescription: "Apaga el Bluetooth mientras el Mac duerme, para que los auriculares en la mochila dejen de conectarse.",
        enable: "Apagar el Bluetooth cuando el Mac entre en reposo",
        enableCaption: "El Bluetooth que ya estaba apagado antes del reposo no se toca y sigue apagado al despertar.",
        restoreToggle: "Volver a encender el Bluetooth cuando el Mac despierte",
        restoreCaption: "Solo cuando fue Vorssaint quien lo apagó.",
        unsupported: "Este Mac no tiene controlador Bluetooth."
    )

    static let de = BluetoothSleepStrings(
        pageTitle: "Bluetooth im Ruhezustand",
        hubDescription: "Schaltet Bluetooth aus, während der Mac schläft, damit Kopfhörer in der Tasche sich nicht mehr verbinden.",
        enable: "Bluetooth ausschalten, wenn der Mac in den Ruhezustand geht",
        enableCaption: "Bereits vor dem Ruhezustand ausgeschaltetes Bluetooth bleibt unberührt und beim Aufwachen aus.",
        restoreToggle: "Bluetooth wieder einschalten, wenn der Mac aufwacht",
        restoreCaption: "Nur wenn Vorssaint es ausgeschaltet hat.",
        unsupported: "Dieser Mac hat keinen Bluetooth-Controller."
    )

    static let fr = BluetoothSleepStrings(
        pageTitle: "Bluetooth en veille",
        hubDescription: "Coupe le Bluetooth pendant que le Mac dort, pour que les écouteurs rangés dans un sac cessent de s’y connecter.",
        enable: "Couper le Bluetooth quand le Mac se met en veille",
        enableCaption: "Un Bluetooth déjà coupé avant la veille n’est pas touché et reste coupé au réveil.",
        restoreToggle: "Rallumer le Bluetooth au réveil du Mac",
        restoreCaption: "Uniquement si c’est Vorssaint qui l’a coupé.",
        unsupported: "Ce Mac n’a pas de contrôleur Bluetooth."
    )

    static let it = BluetoothSleepStrings(
        pageTitle: "Bluetooth in stop",
        hubDescription: "Spegne il Bluetooth mentre il Mac dorme, così le cuffie nello zaino smettono di collegarsi.",
        enable: "Spegni il Bluetooth quando il Mac va in stop",
        enableCaption: "Il Bluetooth già spento prima dello stop resta intoccato e spento alla riattivazione.",
        restoreToggle: "Riaccendi il Bluetooth quando il Mac si riattiva",
        restoreCaption: "Solo quando è stato Vorssaint a spegnerlo.",
        unsupported: "Questo Mac non ha un controller Bluetooth."
    )

    static let ja = BluetoothSleepStrings(
        pageTitle: "スリープ時のBluetooth",
        hubDescription: "Macのスリープ中にBluetoothを切り、カバンの中のヘッドホンが勝手につながらないようにします。",
        enable: "Macがスリープしたら Bluetooth を切る",
        enableCaption: "スリープ前からオフだったBluetoothはそのままで、復帰後もオフのままです。",
        restoreToggle: "Macの復帰時に Bluetooth を戻す",
        restoreCaption: "Vorssaintが切った場合のみ戻します。",
        unsupported: "このMacにはBluetoothコントローラがありません。"
    )

    static let ko = BluetoothSleepStrings(
        pageTitle: "잠자기 시 Bluetooth",
        hubDescription: "Mac이 잠자는 동안 Bluetooth를 꺼서 가방 속 헤드폰이 계속 연결되지 않도록 합니다.",
        enable: "Mac이 잠자기에 들어가면 Bluetooth 끄기",
        enableCaption: "잠자기 전에 이미 꺼져 있던 Bluetooth는 건드리지 않고 깨어난 뒤에도 꺼진 채로 둡니다.",
        restoreToggle: "Mac이 깨어나면 Bluetooth 다시 켜기",
        restoreCaption: "Vorssaint가 껐을 때만 다시 켭니다.",
        unsupported: "이 Mac에는 Bluetooth 컨트롤러가 없습니다."
    )

    static let zhHans = BluetoothSleepStrings(
        pageTitle: "睡眠时的蓝牙",
        hubDescription: "Mac 睡眠期间关闭蓝牙，包里的耳机不再自动连上来。",
        enable: "Mac 进入睡眠时关闭蓝牙",
        enableCaption: "睡眠前就已关闭的蓝牙不会被改动，唤醒后仍保持关闭。",
        restoreToggle: "Mac 唤醒时重新打开蓝牙",
        restoreCaption: "仅在蓝牙是由 Vorssaint 关闭时。",
        unsupported: "这台 Mac 没有蓝牙控制器。"
    )

    static let zhTW = BluetoothSleepStrings(
        pageTitle: "睡眠時的藍牙",
        hubDescription: "Mac 睡眠期間關閉藍牙，包包裡的耳機不會再自動連上來。",
        enable: "Mac 進入睡眠時關閉藍牙",
        enableCaption: "睡眠前就已關閉的藍牙不會被更動，喚醒後仍保持關閉。",
        restoreToggle: "Mac 喚醒時重新開啟藍牙",
        restoreCaption: "僅在藍牙是由 Vorssaint 關閉時。",
        unsupported: "這台 Mac 沒有藍牙控制器。"
    )

    static let zhHK = BluetoothSleepStrings(
        pageTitle: "睡眠時的藍牙",
        hubDescription: "Mac 睡眠期間關閉藍牙，袋裡的耳機不會再自動連上來。",
        enable: "Mac 進入睡眠時關閉藍牙",
        enableCaption: "睡眠前已經關閉的藍牙不會被更動，喚醒後仍然保持關閉。",
        restoreToggle: "Mac 喚醒時重新開啟藍牙",
        restoreCaption: "只在藍牙是由 Vorssaint 關閉時。",
        unsupported: "這部 Mac 沒有藍牙控制器。"
    )
}
