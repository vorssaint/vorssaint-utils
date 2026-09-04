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
    /// Shown once the wait has gone on a while: the usual cause is an entry
    /// left by an earlier copy of the app, which macOS shows as on but no
    /// longer honours.
    let staleHint: String
    let startOver: String
    let relaunch: String
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
        closeHelp: "닫기",
        staleHint: "목록에서 이미 켜져 있나요? 그 항목은 이전 앱 사본의 것입니다. 다시 시작하여 교체하세요.",
        startOver: "다시 시작",
        relaunch: "적용하려면 다시 실행"
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
        closeHelp: "Close",
        staleHint: "Already on in that list? That entry belongs to an earlier copy of the app. Start over to replace it.",
        startOver: "Start over",
        relaunch: "Relaunch to apply"
    )

    static let ptBR = PermissionGuideStrings(
        title: "Falta um passo",
        stepOpen: "O macOS abriu os Ajustes do Sistema na lista certa.",
        stepToggle: "Ligue o Vorssaint nessa lista.",
        stepReturn: "Volte para cá. Este cartão percebe sozinho.",
        waiting: "Esperando a permissão…",
        granted: "Permissão concedida!",
        closeHelp: "Fechar",
        staleHint: "Já está ativado nessa lista? Essa entrada pertence a uma cópia anterior do app. Recomece para substituí-la.",
        startOver: "Recomeçar",
        relaunch: "Reabrir para aplicar"
    )

    static let tr = PermissionGuideStrings(
        title: "Bir adım kaldı",
        stepOpen: "macOS, Sistem Ayarları’nı doğru listede açtı.",
        stepToggle: "O listede Vorssaint’i açın.",
        stepReturn: "Buraya dönün. Bu kart kendiliğinden fark eder.",
        waiting: "İzin bekleniyor…",
        granted: "İzin verildi!",
        closeHelp: "Kapat",
        staleHint: "Bu listede zaten açık mı? O kayıt uygulamanın önceki bir kopyasına ait. Değiştirmek için baştan başlayın.",
        startOver: "Baştan başla",
        relaunch: "Uygulamak için yeniden başlat"
    )

    static let ru = PermissionGuideStrings(
        title: "Остался один шаг",
        stepOpen: "macOS открыл Системные настройки на нужном списке.",
        stepToggle: "Включите Vorssaint в этом списке.",
        stepReturn: "Вернитесь сюда. Карточка заметит сама.",
        waiting: "Ожидание разрешения…",
        granted: "Разрешение получено!",
        closeHelp: "Закрыть",
        staleHint: "Уже включено в этом списке? Эта запись относится к прежней копии приложения. Начните заново, чтобы заменить её.",
        startOver: "Начать заново",
        relaunch: "Перезапустить для применения"
    )

    static let es = PermissionGuideStrings(
        title: "Falta un paso",
        stepOpen: "macOS abrió los Ajustes del Sistema en la lista correcta.",
        stepToggle: "Activa Vorssaint en esa lista.",
        stepReturn: "Vuelve aquí. Esta tarjeta lo nota sola.",
        waiting: "Esperando el permiso…",
        granted: "¡Permiso concedido!",
        closeHelp: "Cerrar",
        staleHint: "¿Ya está activado en esa lista? Esa entrada pertenece a una copia anterior de la app. Empieza de nuevo para reemplazarla.",
        startOver: "Empezar de nuevo",
        relaunch: "Reabrir para aplicar"
    )

    static let de = PermissionGuideStrings(
        title: "Ein Schritt fehlt",
        stepOpen: "macOS hat die Systemeinstellungen mit der richtigen Liste geöffnet.",
        stepToggle: "Schalte Vorssaint in dieser Liste ein.",
        stepReturn: "Komm zurück. Diese Karte merkt es von selbst.",
        waiting: "Warten auf die Berechtigung…",
        granted: "Berechtigung erteilt!",
        closeHelp: "Schließen",
        staleHint: "In der Liste schon eingeschaltet? Dieser Eintrag gehört zu einer früheren Kopie der App. Neu beginnen, um ihn zu ersetzen.",
        startOver: "Neu beginnen",
        relaunch: "Zum Übernehmen neu starten"
    )

    static let fr = PermissionGuideStrings(
        title: "Plus qu’une étape",
        stepOpen: "macOS a ouvert les Réglages Système sur la bonne liste.",
        stepToggle: "Activez Vorssaint dans cette liste.",
        stepReturn: "Revenez ici. Cette carte le remarque toute seule.",
        waiting: "En attente de l’autorisation…",
        granted: "Autorisation accordée\u{00A0}!",
        closeHelp: "Fermer",
        staleHint: "Déjà activé dans cette liste\u{00A0}? Cette entrée appartient à une copie précédente de l’app. Recommencez pour la remplacer.",
        startOver: "Recommencer",
        relaunch: "Relancer pour appliquer"
    )

    static let it = PermissionGuideStrings(
        title: "Manca un passo",
        stepOpen: "macOS ha aperto le Impostazioni di Sistema sull’elenco giusto.",
        stepToggle: "Attiva Vorssaint in quell’elenco.",
        stepReturn: "Torna qui. Questa scheda se ne accorge da sola.",
        waiting: "In attesa del permesso…",
        granted: "Permesso concesso!",
        closeHelp: "Chiudi",
        staleHint: "Già attivo in quell’elenco? Quella voce appartiene a una copia precedente dell’app. Ricomincia per sostituirla.",
        startOver: "Ricomincia",
        relaunch: "Riavvia per applicare"
    )

    static let ja = PermissionGuideStrings(
        title: "あと一歩",
        stepOpen: "macOSがシステム設定の該当リストを開きました。",
        stepToggle: "そのリストでVorssaintをオンにしてください。",
        stepReturn: "ここに戻ってください。このカードが自動で気づきます。",
        waiting: "許可を待っています…",
        granted: "許可されました！",
        closeHelp: "閉じる",
        staleHint: "リストではすでにオンになっていますか？その項目は以前のコピーのものです。やり直して置き換えてください。",
        startOver: "やり直す",
        relaunch: "再起動して適用"
    )

    static let zhHans = PermissionGuideStrings(
        title: "还差一步",
        stepOpen: "macOS 已打开系统设置的对应列表。",
        stepToggle: "在列表中开启 Vorssaint。",
        stepReturn: "回到这里，本卡片会自动察觉。",
        waiting: "正在等待权限…",
        granted: "权限已授予！",
        closeHelp: "关闭",
        staleHint: "列表里已经打开了？那条记录属于此 App 的早期副本。重新开始以替换它。",
        startOver: "重新开始",
        relaunch: "重新启动以生效"
    )

    static let zhTW = PermissionGuideStrings(
        title: "只差一步",
        stepOpen: "macOS 已開啟系統設定的對應清單。",
        stepToggle: "在清單中開啟 Vorssaint。",
        stepReturn: "回到這裡，本卡片會自動察覺。",
        waiting: "正在等待權限…",
        granted: "已授予權限！",
        closeHelp: "關閉",
        staleHint: "清單裡已經開啟了？那筆項目屬於此 App 的早期副本。重新開始以取代它。",
        startOver: "重新開始",
        relaunch: "重新啟動以套用"
    )

    static let zhHK = PermissionGuideStrings(
        title: "只差一步",
        stepOpen: "macOS 已開啟系統設定的對應清單。",
        stepToggle: "在清單中開啟 Vorssaint。",
        stepReturn: "回到這裡，本卡片會自動察覺。",
        waiting: "正在等待權限…",
        granted: "已授予權限！",
        closeHelp: "關閉",
        staleHint: "清單裡已經開啟了？那筆項目屬於此 App 的早期副本。重新開始以取代它。",
        startOver: "重新開始",
        relaunch: "重新啟動以套用"
    )
}
