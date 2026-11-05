// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension FeatureStrings {
    /// The power section of the Sounds page.
    static func powerSounds(_ language: AppLanguage) -> SoundGroupStrings {
        switch language {
        case .enUS: return SoundGroupStrings(
            title: "Power",
            note: "Battery and charger sounds need a Mac with a battery.",
            moments: [
                .batteryLow: SoundMoment(title: "Low battery",
                                         caption: "When the battery falls to 20% while unplugged."),
                .chargerConnected: SoundMoment(title: "Charger connected",
                                               caption: "When you plug in a charger."),
                .chargerDisconnected: SoundMoment(title: "Charger disconnected",
                                                  caption: "When you unplug the charger."),
                .keepAwakeEnded: SoundMoment(title: "Keep awake ended",
                                             caption: "When a timed Keep awake session runs out."),
            ])
        case .ptBR: return SoundGroupStrings(
            title: "Energia",
            note: "Os sons de bateria e carregador precisam de um Mac com bateria.",
            moments: [
                .batteryLow: SoundMoment(title: "Bateria fraca",
                                         caption: "Quando a bateria cai para 20% fora da tomada."),
                .chargerConnected: SoundMoment(title: "Carregador conectado",
                                               caption: "Quando você conecta um carregador."),
                .chargerDisconnected: SoundMoment(title: "Carregador desconectado",
                                                  caption: "Quando você desconecta o carregador."),
                .keepAwakeEnded: SoundMoment(title: "Manter acordado terminou",
                                             caption: "Quando uma sessão com tempo de Manter acordado acaba."),
            ])
        case .tr: return SoundGroupStrings(
            title: "Güç",
            note: "Pil ve şarj aleti sesleri için pilli bir Mac gerekir.",
            moments: [
                .batteryLow: SoundMoment(title: "Düşük pil",
                                         caption: "Fişe takılı değilken pil %20’ye düştüğünde."),
                .chargerConnected: SoundMoment(title: "Şarj aleti takıldı",
                                               caption: "Bir şarj aleti taktığınızda."),
                .chargerDisconnected: SoundMoment(title: "Şarj aleti çıkarıldı",
                                                  caption: "Şarj aletini çıkardığınızda."),
                .keepAwakeEnded: SoundMoment(title: "Uyanık tutma bitti",
                                             caption: "Süreli bir Uyanık tut oturumu sona erdiğinde."),
            ])
        case .ru: return SoundGroupStrings(
            title: "Питание",
            note: "Звуки батареи и зарядки работают только на Mac с батареей.",
            moments: [
                .batteryLow: SoundMoment(title: "Низкий заряд",
                                         caption: "Когда заряд без зарядки падает до 20%."),
                .chargerConnected: SoundMoment(title: "Зарядка подключена",
                                               caption: "Когда вы подключаете зарядку."),
                .chargerDisconnected: SoundMoment(title: "Зарядка отключена",
                                                  caption: "Когда вы отключаете зарядку."),
                .keepAwakeEnded: SoundMoment(title: "Режим без сна завершён",
                                             caption: "Когда истекает время сеанса «Не давать Mac уснуть»."),
            ])
        case .es: return SoundGroupStrings(
            title: "Energía",
            note: "Los sonidos de batería y cargador necesitan un Mac con batería.",
            moments: [
                .batteryLow: SoundMoment(title: "Batería baja",
                                         caption: "Cuando la batería baja al 20% sin el cargador."),
                .chargerConnected: SoundMoment(title: "Cargador conectado",
                                               caption: "Cuando conectas un cargador."),
                .chargerDisconnected: SoundMoment(title: "Cargador desconectado",
                                                  caption: "Cuando desconectas el cargador."),
                .keepAwakeEnded: SoundMoment(title: "Mantener activo terminado",
                                             caption: "Cuando se acaba una sesión con tiempo de Mantener activo."),
            ])
        case .sk: return SoundGroupStrings(
            title: "Napájanie",
            note: "Zvuky batérie a nabíjačky potrebujú Mac s batériou.",
            moments: [
                .batteryLow: SoundMoment(title: "Nízky stav batérie",
                                         caption: "Keď batéria bez nabíjačky klesne na 20 %."),
                .chargerConnected: SoundMoment(title: "Nabíjačka pripojená",
                                               caption: "Keď pripojíte nabíjačku."),
                .chargerDisconnected: SoundMoment(title: "Nabíjačka odpojená",
                                                  caption: "Keď odpojíte nabíjačku."),
                .keepAwakeEnded: SoundMoment(title: "Bdelý režim skončil",
                                             caption: "Keď uplynie časovaná relácia bdelého režimu."),
            ])
        case .de: return SoundGroupStrings(
            title: "Strom",
            note: "Töne für Batterie und Ladegerät brauchen einen Mac mit Batterie.",
            moments: [
                .batteryLow: SoundMoment(title: "Niedriger Batteriestand",
                                         caption: "Wenn die Batterie ohne Ladegerät auf 20 % fällt."),
                .chargerConnected: SoundMoment(title: "Ladegerät angeschlossen",
                                               caption: "Wenn du ein Ladegerät anschließt."),
                .chargerDisconnected: SoundMoment(title: "Ladegerät getrennt",
                                                  caption: "Wenn du das Ladegerät trennst."),
                .keepAwakeEnded: SoundMoment(title: "Wachhalten beendet",
                                             caption: "Wenn eine zeitlich begrenzte Wachhalten-Sitzung abläuft."),
            ])
        case .fr: return SoundGroupStrings(
            title: "Alimentation",
            note: "Les sons de batterie et de chargeur demandent un Mac avec batterie.",
            moments: [
                .batteryLow: SoundMoment(title: "Batterie faible",
                                         caption: "Quand la batterie descend à 20 % sans chargeur."),
                .chargerConnected: SoundMoment(title: "Chargeur branché",
                                               caption: "Quand vous branchez un chargeur."),
                .chargerDisconnected: SoundMoment(title: "Chargeur débranché",
                                                  caption: "Quand vous débranchez le chargeur."),
                .keepAwakeEnded: SoundMoment(title: "Fin de Garder éveillé",
                                             caption: "Quand une session minutée de Garder éveillé se termine."),
            ])
        case .it: return SoundGroupStrings(
            title: "Alimentazione",
            note: "I suoni di batteria e caricatore richiedono un Mac con batteria.",
            moments: [
                .batteryLow: SoundMoment(title: "Batteria scarica",
                                         caption: "Quando la batteria scende al 20% senza caricatore."),
                .chargerConnected: SoundMoment(title: "Caricatore collegato",
                                               caption: "Quando colleghi un caricatore."),
                .chargerDisconnected: SoundMoment(title: "Caricatore scollegato",
                                                  caption: "Quando scolleghi il caricatore."),
                .keepAwakeEnded: SoundMoment(title: "Mantieni attivo terminato",
                                             caption: "Quando finisce una sessione a tempo di Mantieni attivo."),
            ])
        case .ja: return SoundGroupStrings(
            title: "電源",
            note: "バッテリーと充電器のサウンドには、バッテリー搭載のMacが必要です。",
            moments: [
                .batteryLow: SoundMoment(title: "バッテリー残量低下",
                                         caption: "電源につないでいないときにバッテリーが20%まで下がったとき。"),
                .chargerConnected: SoundMoment(title: "充電器を接続",
                                               caption: "充電器をつないだとき。"),
                .chargerDisconnected: SoundMoment(title: "充電器を取り外し",
                                                  caption: "充電器を外したとき。"),
                .keepAwakeEnded: SoundMoment(title: "スリープ防止が終了",
                                             caption: "時間指定のスリープ防止が終わったとき。"),
            ])
        case .ko: return SoundGroupStrings(
            title: "전원",
            note: "배터리와 충전기 사운드는 배터리가 있는 Mac에서만 재생됩니다.",
            moments: [
                .batteryLow: SoundMoment(title: "배터리 부족",
                                         caption: "전원에 연결하지 않은 상태에서 배터리가 20%로 떨어질 때."),
                .chargerConnected: SoundMoment(title: "충전기 연결됨",
                                               caption: "충전기를 연결할 때."),
                .chargerDisconnected: SoundMoment(title: "충전기 분리됨",
                                                  caption: "충전기를 분리할 때."),
                .keepAwakeEnded: SoundMoment(title: "절전 방지 종료",
                                             caption: "시간을 정한 절전 방지가 끝날 때."),
            ])
        case .uk: return SoundGroupStrings(
            title: "Живлення",
            note: "Звуки батареї та зарядки працюють лише на Mac з батареєю.",
            moments: [
                .batteryLow: SoundMoment(title: "Низький заряд",
                                         caption: "Коли заряд без зарядки падає до 20%."),
                .chargerConnected: SoundMoment(title: "Зарядку під’єднано",
                                               caption: "Коли ви під’єднуєте зарядку."),
                .chargerDisconnected: SoundMoment(title: "Зарядку від’єднано",
                                                  caption: "Коли ви від’єднуєте зарядку."),
                .keepAwakeEnded: SoundMoment(title: "Режим без сну завершено",
                                             caption: "Коли спливає час сеансу «Не давати Mac заснути»."),
            ])
        case .zhHans: return SoundGroupStrings(
            title: "电源",
            note: "电池和充电器声音需要带电池的 Mac。",
            moments: [
                .batteryLow: SoundMoment(title: "电量不足",
                                         caption: "未接电源时电池降到 20% 时。"),
                .chargerConnected: SoundMoment(title: "已接上充电器",
                                               caption: "当你接上充电器时。"),
                .chargerDisconnected: SoundMoment(title: "已拔下充电器",
                                                  caption: "当你拔下充电器时。"),
                .keepAwakeEnded: SoundMoment(title: "保持唤醒已结束",
                                             caption: "定时的保持唤醒结束时。"),
            ])
        case .zhTW: return SoundGroupStrings(
            title: "電源",
            note: "電池和充電器的聲音需要有電池的 Mac。",
            moments: [
                .batteryLow: SoundMoment(title: "電量不足",
                                         caption: "未接電源時電池降到 20% 時。"),
                .chargerConnected: SoundMoment(title: "已接上充電器",
                                               caption: "當你接上充電器時。"),
                .chargerDisconnected: SoundMoment(title: "已拔下充電器",
                                                  caption: "當你拔下充電器時。"),
                .keepAwakeEnded: SoundMoment(title: "保持喚醒已結束",
                                             caption: "定時的保持喚醒結束時。"),
            ])
        case .zhHK: return SoundGroupStrings(
            title: "電源",
            note: "電池和充電器的聲音需要有電池的 Mac。",
            moments: [
                .batteryLow: SoundMoment(title: "電量不足",
                                         caption: "未接電源時電池跌到 20% 時。"),
                .chargerConnected: SoundMoment(title: "已接上充電器",
                                               caption: "當你接上充電器時。"),
                .chargerDisconnected: SoundMoment(title: "已拔走充電器",
                                                  caption: "當你拔走充電器時。"),
                .keepAwakeEnded: SoundMoment(title: "保持喚醒已結束",
                                             caption: "定時的保持喚醒完結時。"),
            ])
        }
    }
}
