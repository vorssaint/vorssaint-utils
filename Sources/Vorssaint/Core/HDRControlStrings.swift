// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the HDR switches. Same contract as the other FeatureStrings
/// structs: memberwise init with labeled arguments in declaration order, one
/// static per language, all in this file.
struct HDRControlStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let noDisplays: String
    let unsupported: String
    let unnamedDisplay: String
    let displayCaption: String
    let failedNote: String
    let tileTitle: String
}

extension FeatureStrings {
    static func hdrControl(_ language: AppLanguage) -> HDRControlStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension HDRControlStrings {
    static let enUS = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Turn HDR on and off for HDR-capable displays from Settings and Quick Toggles.",
        enable: "HDR switches",
        enableCaption: "Shows an HDR switch for every display that supports HDR in its current mode. Uses a private macOS interface.",
        noDisplays: "No connected display supports HDR in its current mode.",
        unsupported: "This version of macOS doesn’t offer the HDR switch to apps.",
        unnamedDisplay: "Display",
        displayCaption: "Switches this display between HDR and SDR, like System Settings › Displays.",
        failedNote: "macOS didn’t change HDR on this display.",
        tileTitle: "HDR"
    )

    static let ptBR = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Ative e desative o HDR em telas compatíveis pelos Ajustes e pelos Atalhos rápidos.",
        enable: "Chaves de HDR",
        enableCaption: "Mostra uma chave de HDR para cada tela compatível com HDR no modo atual. Usa uma interface privada do macOS.",
        noDisplays: "Nenhuma tela conectada é compatível com HDR no modo atual.",
        unsupported: "Esta versão do macOS não oferece a chave de HDR aos apps.",
        unnamedDisplay: "Tela",
        displayCaption: "Alterna esta tela entre HDR e SDR, como em Ajustes do Sistema › Telas.",
        failedNote: "O macOS não alterou o HDR nesta tela.",
        tileTitle: "HDR"
    )

    static let tr = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "HDR destekli ekranlarda HDR’yi Ayarlar’dan ve Hızlı Geçişler’den açıp kapatın.",
        enable: "HDR anahtarları",
        enableCaption: "Geçerli modunda HDR destekleyen her ekran için bir HDR anahtarı gösterir. Özel bir macOS arabirimi kullanır.",
        noDisplays: "Bağlı hiçbir ekran geçerli modunda HDR desteklemiyor.",
        unsupported: "Bu macOS sürümü HDR anahtarını uygulamalara sunmuyor.",
        unnamedDisplay: "Ekran",
        displayCaption: "Bu ekranı Sistem Ayarları › Ekranlar’daki gibi HDR ile SDR arasında değiştirir.",
        failedNote: "macOS bu ekranda HDR’yi değiştirmedi.",
        tileTitle: "HDR"
    )

    static let ru = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Включайте и выключайте HDR на совместимых дисплеях из настроек и быстрых переключателей.",
        enable: "Переключатели HDR",
        enableCaption: "Показывает переключатель HDR для каждого дисплея, поддерживающего HDR в текущем режиме. Использует закрытый интерфейс macOS.",
        noDisplays: "Ни один подключённый дисплей не поддерживает HDR в текущем режиме.",
        unsupported: "Эта версия macOS не даёт приложениям переключать HDR.",
        unnamedDisplay: "Дисплей",
        displayCaption: "Переключает этот дисплей между HDR и SDR, как в Системных настройках › Дисплеи.",
        failedNote: "macOS не изменила HDR на этом дисплее.",
        tileTitle: "HDR"
    )

    static let es = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Activa y desactiva el HDR en pantallas compatibles desde Ajustes y los Interruptores rápidos.",
        enable: "Interruptores de HDR",
        enableCaption: "Muestra un interruptor de HDR para cada pantalla compatible con HDR en su modo actual. Usa una interfaz privada de macOS.",
        noDisplays: "Ninguna pantalla conectada admite HDR en su modo actual.",
        unsupported: "Esta versión de macOS no ofrece el interruptor de HDR a las apps.",
        unnamedDisplay: "Pantalla",
        displayCaption: "Cambia esta pantalla entre HDR y SDR, como en Ajustes del Sistema › Pantallas.",
        failedNote: "macOS no cambió el HDR en esta pantalla.",
        tileTitle: "HDR"
    )

    static let sk = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Zapínajte a vypínajte HDR na kompatibilných displejoch z Nastavení a Rýchlych prepínačov.",
        enable: "Prepínače HDR",
        enableCaption: "Zobrazí prepínač HDR pre každý displej, ktorý v aktuálnom režime podporuje HDR. Používa súkromné rozhranie macOS.",
        noDisplays: "Žiadny pripojený displej v aktuálnom režime nepodporuje HDR.",
        unsupported: "Táto verzia macOS neposkytuje aplikáciám prepínač HDR.",
        unnamedDisplay: "Displej",
        displayCaption: "Prepína tento displej medzi HDR a SDR, ako v Systémových nastaveniach › Displeje.",
        failedNote: "macOS na tomto displeji HDR nezmenil.",
        tileTitle: "HDR"
    )

    static let de = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "HDR auf HDR-fähigen Displays in den Einstellungen und in den Schnellschaltern ein- und ausschalten.",
        enable: "HDR-Schalter",
        enableCaption: "Zeigt einen HDR-Schalter für jedes Display, das im aktuellen Modus HDR unterstützt. Nutzt eine private macOS-Schnittstelle.",
        noDisplays: "Kein angeschlossenes Display unterstützt HDR im aktuellen Modus.",
        unsupported: "Diese macOS-Version bietet Apps den HDR-Schalter nicht an.",
        unnamedDisplay: "Display",
        displayCaption: "Schaltet dieses Display zwischen HDR und SDR um, wie in Systemeinstellungen › Displays.",
        failedNote: "macOS hat HDR auf diesem Display nicht geändert.",
        tileTitle: "HDR"
    )

    static let fr = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Activez et désactivez le HDR sur les écrans compatibles depuis les Réglages et les Bascules rapides.",
        enable: "Interrupteurs HDR",
        enableCaption: "Affiche un interrupteur HDR pour chaque écran compatible HDR dans son mode actuel. Utilise une interface privée de macOS.",
        noDisplays: "Aucun écran connecté ne prend en charge le HDR dans son mode actuel.",
        unsupported: "Cette version de macOS ne propose pas l’interrupteur HDR aux apps.",
        unnamedDisplay: "Écran",
        displayCaption: "Fait passer cet écran du HDR au SDR et inversement, comme dans Réglages Système › Moniteurs.",
        failedNote: "macOS n’a pas modifié le HDR sur cet écran.",
        tileTitle: "HDR"
    )

    static let it = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Attiva e disattiva l’HDR sui monitor compatibili da Impostazioni e dagli Interruttori rapidi.",
        enable: "Interruttori HDR",
        enableCaption: "Mostra un interruttore HDR per ogni monitor che supporta l’HDR nella modalità attuale. Usa un’interfaccia privata di macOS.",
        noDisplays: "Nessun monitor collegato supporta l’HDR nella modalità attuale.",
        unsupported: "Questa versione di macOS non offre l’interruttore HDR alle app.",
        unnamedDisplay: "Monitor",
        displayCaption: "Passa questo monitor da HDR a SDR e viceversa, come in Impostazioni di Sistema › Monitor.",
        failedNote: "macOS non ha cambiato l’HDR su questo monitor.",
        tileTitle: "HDR"
    )

    static let ja = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "HDR対応ディスプレイのHDRを、設定とクイックトグルからオン/オフします。",
        enable: "HDRスイッチ",
        enableCaption: "現在のモードでHDRに対応するディスプレイごとにHDRスイッチを表示します。macOSの非公開インターフェイスを使用します。",
        noDisplays: "接続中のディスプレイで、現在のモードでHDRに対応するものはありません。",
        unsupported: "このバージョンのmacOSでは、アプリからHDRを切り替えられません。",
        unnamedDisplay: "ディスプレイ",
        displayCaption: "システム設定 › ディスプレイと同じように、このディスプレイをHDRとSDRで切り替えます。",
        failedNote: "macOSはこのディスプレイのHDRを変更しませんでした。",
        tileTitle: "HDR"
    )

    static let ko = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "HDR 지원 디스플레이의 HDR을 설정과 빠른 토글에서 켜고 끕니다.",
        enable: "HDR 스위치",
        enableCaption: "현재 모드에서 HDR을 지원하는 디스플레이마다 HDR 스위치를 표시합니다. macOS 비공개 인터페이스를 사용합니다.",
        noDisplays: "연결된 디스플레이 중 현재 모드에서 HDR을 지원하는 디스플레이가 없습니다.",
        unsupported: "이 macOS 버전은 앱에 HDR 스위치를 제공하지 않습니다.",
        unnamedDisplay: "디스플레이",
        displayCaption: "시스템 설정 › 디스플레이처럼 이 디스플레이를 HDR과 SDR 간에 전환합니다.",
        failedNote: "macOS가 이 디스플레이의 HDR을 변경하지 않았습니다.",
        tileTitle: "HDR"
    )

    static let zhHans = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "在设置和快捷开关中为支持 HDR 的显示器打开或关闭 HDR。",
        enable: "HDR 开关",
        enableCaption: "为每台在当前模式下支持 HDR 的显示器显示一个 HDR 开关。使用 macOS 私有接口。",
        noDisplays: "没有已连接的显示器在当前模式下支持 HDR。",
        unsupported: "此版本的 macOS 不向应用提供 HDR 开关。",
        unnamedDisplay: "显示器",
        displayCaption: "像“系统设置 › 显示器”一样，在 HDR 和 SDR 之间切换此显示器。",
        failedNote: "macOS 未更改此显示器的 HDR。",
        tileTitle: "HDR"
    )

    static let zhTW = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "在設定和快速切換中為支援 HDR 的顯示器開啟或關閉 HDR。",
        enable: "HDR 開關",
        enableCaption: "為每台在目前模式下支援 HDR 的顯示器顯示一個 HDR 開關。使用 macOS 私有介面。",
        noDisplays: "沒有已連接的顯示器在目前模式下支援 HDR。",
        unsupported: "此版本的 macOS 不向 App 提供 HDR 開關。",
        unnamedDisplay: "顯示器",
        displayCaption: "如同「系統設定 › 顯示器」，在 HDR 與 SDR 之間切換此顯示器。",
        failedNote: "macOS 未變更此顯示器的 HDR。",
        tileTitle: "HDR"
    )

    static let zhHK = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "在設定和快速切換中為支援 HDR 的顯示器開啟或關閉 HDR。",
        enable: "HDR 開關",
        enableCaption: "為每部在目前模式下支援 HDR 的顯示器顯示一個 HDR 開關。使用 macOS 私有介面。",
        noDisplays: "沒有已連接的顯示器在目前模式下支援 HDR。",
        unsupported: "此版本的 macOS 不向 App 提供 HDR 開關。",
        unnamedDisplay: "顯示器",
        displayCaption: "如同「系統設定 › 顯示器」，在 HDR 與 SDR 之間切換此顯示器。",
        failedNote: "macOS 未有更改此顯示器的 HDR。",
        tileTitle: "HDR"
    )

    static let uk = HDRControlStrings(
        pageTitle: "HDR",
        hubDescription: "Вмикайте й вимикайте HDR на сумісних дисплеях у Параметрах і швидких перемикачах.",
        enable: "Перемикачі HDR",
        enableCaption: "Показує перемикач HDR для кожного дисплея, що підтримує HDR у поточному режимі. Використовує закритий інтерфейс macOS.",
        noDisplays: "Жоден підключений дисплей не підтримує HDR у поточному режимі.",
        unsupported: "Ця версія macOS не дає програмам перемикати HDR.",
        unnamedDisplay: "Дисплей",
        displayCaption: "Перемикає цей дисплей між HDR і SDR, як у Системних параметрах › Дисплеї.",
        failedNote: "macOS не змінила HDR на цьому дисплеї.",
        tileTitle: "HDR"
    )
}
