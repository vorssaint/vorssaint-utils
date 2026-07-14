// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the floating permission guide: the little card that walks the
/// person through System Settings and notices the grant by itself. Same
/// contract as the other FeatureStrings structs: memberwise init in
/// declaration order, one static per language, all in this file.
struct PermissionGuideStrings {
    let title: String
    let stepOpen: String
    let stepToggle: String
    let stepReturn: String
    let waiting: String
    let granted: String
    let closeHelp: String
}

extension FeatureStrings {
    static func permissionGuide(_ language: AppLanguage) -> PermissionGuideStrings {
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

extension PermissionGuideStrings {
    static let ko = PermissionGuideStrings(
        title: "한 단계만 남았습니다",
        stepOpen: "macOS가 시스템 설정의 올바른 목록을 열었습니다.",
        stepToggle: "그 목록에서 Vorssaint를 켜세요.",
        stepReturn: "여기로 돌아오세요. 이 카드가 자동으로 확인합니다.",
        waiting: "권한을 기다리는 중…",
        granted: "권한이 허용되었습니다!",
        closeHelp: "닫기"
    )
}

extension PermissionGuideStrings {
    static let enUS = PermissionGuideStrings(
        title: "One step left",
        stepOpen: "macOS opened System Settings on the right list.",
        stepToggle: "Turn Vorssaint on in that list.",
        stepReturn: "Come back. This card notices by itself.",
        waiting: "Waiting for the permission…",
        granted: "Permission granted!",
        closeHelp: "Close"
    )

    static let ptBR = PermissionGuideStrings(
        title: "Falta um passo",
        stepOpen: "O macOS abriu os Ajustes do Sistema na lista certa.",
        stepToggle: "Ligue o Vorssaint nessa lista.",
        stepReturn: "Volte para cá. Este cartão percebe sozinho.",
        waiting: "Esperando a permissão…",
        granted: "Permissão concedida!",
        closeHelp: "Fechar"
    )

    static let tr = PermissionGuideStrings(
        title: "Bir adım kaldı",
        stepOpen: "macOS, Sistem Ayarları'nı doğru listede açtı.",
        stepToggle: "O listede Vorssaint'i açın.",
        stepReturn: "Buraya dönün. Bu kart kendiliğinden fark eder.",
        waiting: "İzin bekleniyor…",
        granted: "İzin verildi!",
        closeHelp: "Kapat"
    )

    static let ru = PermissionGuideStrings(
        title: "Остался один шаг",
        stepOpen: "macOS открыл Системные настройки на нужном списке.",
        stepToggle: "Включите Vorssaint в этом списке.",
        stepReturn: "Вернитесь сюда. Карточка заметит сама.",
        waiting: "Ожидание разрешения…",
        granted: "Разрешение получено!",
        closeHelp: "Закрыть"
    )

    static let es = PermissionGuideStrings(
        title: "Falta un paso",
        stepOpen: "macOS abrió los Ajustes del Sistema en la lista correcta.",
        stepToggle: "Activa Vorssaint en esa lista.",
        stepReturn: "Vuelve aquí. Esta tarjeta lo nota sola.",
        waiting: "Esperando el permiso…",
        granted: "¡Permiso concedido!",
        closeHelp: "Cerrar"
    )

    static let de = PermissionGuideStrings(
        title: "Ein Schritt fehlt",
        stepOpen: "macOS hat die Systemeinstellungen mit der richtigen Liste geöffnet.",
        stepToggle: "Schalte Vorssaint in dieser Liste ein.",
        stepReturn: "Komm zurück. Diese Karte merkt es von selbst.",
        waiting: "Warten auf die Berechtigung…",
        granted: "Berechtigung erteilt!",
        closeHelp: "Schließen"
    )

    static let fr = PermissionGuideStrings(
        title: "Plus qu'une étape",
        stepOpen: "macOS a ouvert les Réglages Système sur la bonne liste.",
        stepToggle: "Activez Vorssaint dans cette liste.",
        stepReturn: "Revenez ici. Cette carte le remarque toute seule.",
        waiting: "En attente de l'autorisation…",
        granted: "Autorisation accordée !",
        closeHelp: "Fermer"
    )

    static let it = PermissionGuideStrings(
        title: "Manca un passo",
        stepOpen: "macOS ha aperto le Impostazioni di Sistema sull'elenco giusto.",
        stepToggle: "Attiva Vorssaint in quell'elenco.",
        stepReturn: "Torna qui. Questa scheda se ne accorge da sola.",
        waiting: "In attesa del permesso…",
        granted: "Permesso concesso!",
        closeHelp: "Chiudi"
    )

    static let ja = PermissionGuideStrings(
        title: "あと一歩",
        stepOpen: "macOSがシステム設定の該当リストを開きました。",
        stepToggle: "そのリストでVorssaintをオンにしてください。",
        stepReturn: "ここに戻ってください。このカードが自動で気づきます。",
        waiting: "許可を待っています…",
        granted: "許可されました！",
        closeHelp: "閉じる"
    )

    static let zhHans = PermissionGuideStrings(
        title: "还差一步",
        stepOpen: "macOS 已打开系统设置的对应列表。",
        stepToggle: "在列表中开启 Vorssaint。",
        stepReturn: "回到这里，本卡片会自动察觉。",
        waiting: "正在等待权限…",
        granted: "权限已授予！",
        closeHelp: "关闭"
    )

    static let zhTW = PermissionGuideStrings(
        title: "只差一步",
        stepOpen: "macOS 已開啟系統設定的對應清單。",
        stepToggle: "在清單中開啟 Vorssaint。",
        stepReturn: "回到這裡，本卡片會自動察覺。",
        waiting: "正在等待權限…",
        granted: "已授予權限！",
        closeHelp: "關閉"
    )

    static let zhHK = PermissionGuideStrings(
        title: "只差一步",
        stepOpen: "macOS 已開啟系統設定的對應清單。",
        stepToggle: "在清單中開啟 Vorssaint。",
        stepReturn: "回到這裡，本卡片會自動察覺。",
        waiting: "正在等待權限…",
        granted: "已授予權限！",
        closeHelp: "關閉"
    )
}
