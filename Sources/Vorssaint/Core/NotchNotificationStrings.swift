// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchNotificationStrings {
    let title: String
    let description: String
    let privacy: String
    let empty: String
    let waiting: String
    let open: String
    let dismiss: String
    let unavailable: String
    let dismissSystemBanner: String
    let dismissSystemBannerHint: String
}

extension FeatureStrings {
    static func notchNotifications(_ language: AppLanguage) -> NotchNotificationStrings {
        switch language {
        case .enUS: return NotchNotificationStrings(
            title: "Notifications",
            description: "New system notifications in the Dynamic Island.",
            privacy: "Show new visible banners only. Messages stay in memory and are cleared when you lock this Mac or turn this off.",
            empty: "New notifications will appear here",
            waiting: "Waiting for the system notification service",
            open: "Open",
            dismiss: "Dismiss",
            unavailable: "This notification can no longer accept this action.",
            dismissSystemBanner: "Dismiss the system banner",
            dismissSystemBannerHint: "Dismiss the original once the Dynamic Island shows it and its sound has played. It still appears briefly.")
        case .ptBR: return NotchNotificationStrings(
            title: "Notificações",
            description: "Novas notificações do sistema no Dynamic Island.",
            privacy: "Mostre apenas os novos avisos visíveis. As mensagens ficam na memória e somem ao bloquear este Mac ou desligar o recurso.",
            empty: "As novas notificações vão aparecer aqui",
            waiting: "Aguardando as notificações do sistema",
            open: "Abrir",
            dismiss: "Dispensar",
            unavailable: "Esta notificação não aceita mais esta ação.",
            dismissSystemBanner: "Recolher aviso do sistema",
            dismissSystemBannerHint: "Dispensa o aviso original depois que o Dynamic Island o mostra e o som dele termina. Ele ainda aparece brevemente.")
        case .es: return NotchNotificationStrings(
            title: "Notificaciones",
            description: "Nuevas notificaciones del sistema en el Dynamic Island.",
            privacy: "Muestra solo los avisos nuevos visibles. Los mensajes se guardan en memoria y se borran al bloquear este Mac o desactivar la función.",
            empty: "Las nuevas notificaciones aparecerán aquí",
            waiting: "Esperando las notificaciones del sistema",
            open: "Abrir",
            dismiss: "Descartar",
            unavailable: "Esta notificación ya no admite esta acción.",
            dismissSystemBanner: "Cerrar el aviso del sistema",
            dismissSystemBannerHint: "Cierra el aviso original después de que el Dynamic Island lo muestre y su sonido termine. Aún se ve brevemente.")
        case .de: return NotchNotificationStrings(
            title: "Mitteilungen",
            description: "Neue Systemmitteilungen im Dynamic Island.",
            privacy: "Zeigt nur neue sichtbare Hinweise. Nachrichten bleiben im Arbeitsspeicher und werden beim Sperren oder Ausschalten gelöscht.",
            empty: "Neue Mitteilungen erscheinen hier",
            waiting: "Warten auf den Mitteilungsdienst des Systems",
            open: "Öffnen",
            dismiss: "Verwerfen",
            unavailable: "Diese Mitteilung unterstützt diese Aktion nicht mehr.",
            dismissSystemBanner: "Systemhinweis schließen",
            dismissSystemBannerHint: "Schließt den ursprünglichen Hinweis, sobald die Dynamic Island ihn zeigt und sein Ton verklungen ist. Er ist kurz sichtbar.")
        case .fr: return NotchNotificationStrings(
            title: "Notifications",
            description: "Les nouvelles notifications système dans le Dynamic Island.",
            privacy: "Affiche uniquement les nouvelles alertes visibles. Les messages restent en mémoire et sont effacés au verrouillage ou à la désactivation.",
            empty: "Les nouvelles notifications apparaîtront ici",
            waiting: "En attente du service de notifications système",
            open: "Ouvrir",
            dismiss: "Ignorer",
            unavailable: "Cette notification ne permet plus cette action.",
            dismissSystemBanner: "Fermer la bannière système",
            dismissSystemBannerHint: "Ferme la bannière d’origine une fois affichée dans l’encoche et son signal sonore terminé. Elle apparaît brièvement.")
        case .it: return NotchNotificationStrings(
            title: "Notifiche",
            description: "Nuove notifiche di sistema nel Dynamic Island.",
            privacy: "Mostra solo i nuovi avvisi visibili. I messaggi restano in memoria e vengono cancellati al blocco o alla disattivazione.",
            empty: "Le nuove notifiche appariranno qui",
            waiting: "In attesa del servizio notifiche di sistema",
            open: "Apri",
            dismiss: "Ignora",
            unavailable: "Questa notifica non consente più questa azione.",
            dismissSystemBanner: "Chiudi l’avviso di sistema",
            dismissSystemBannerHint: "Chiude l’avviso originale dopo che il Dynamic Island lo mostra e il suo suono termina. Appare comunque brevemente.")
        case .ru: return NotchNotificationStrings(
            title: "Уведомления",
            description: "Новые системные уведомления в вырезе экрана.",
            privacy: "Только новые видимые уведомления. Сообщения хранятся в памяти и удаляются при блокировке Mac или отключении функции.",
            empty: "Здесь появятся новые уведомления",
            waiting: "Ожидание службы системных уведомлений",
            open: "Открыть",
            dismiss: "Убрать",
            unavailable: "Это уведомление больше не поддерживает данное действие.",
            dismissSystemBanner: "Закрывать системное уведомление",
            dismissSystemBannerHint: "Закрывает исходное уведомление после показа в вырезе и окончания его звука. Оно ненадолго появляется.")
        case .tr: return NotchNotificationStrings(
            title: "Bildirimler",
            description: "Yeni sistem bildirimleri çentikte.",
            privacy: "Yalnızca yeni ve görünür bildirimleri gösterir. Mesajlar bellekte kalır ve Mac kilitlendiğinde veya özellik kapatıldığında silinir.",
            empty: "Yeni bildirimler burada görünecek",
            waiting: "Sistem bildirim hizmeti bekleniyor",
            open: "Aç",
            dismiss: "Kapat",
            unavailable: "Bu bildirim artık bu işlemi desteklemiyor.",
            dismissSystemBanner: "Sistem bildirimini kapat",
            dismissSystemBannerHint: "Çentikte gösterildikten ve sesi çaldıktan sonra asıl bildirimi kapatır. Bildirim kısa süre görünür.")
        case .ja: return NotchNotificationStrings(
            title: "通知",
            description: "新しいシステム通知をDynamic Islandに表示します。",
            privacy: "新しく表示された通知のみを表示します。メッセージはメモリ内に保持され、Macのロック時や機能をオフにしたときに消去されます。",
            empty: "新しい通知がここに表示されます",
            waiting: "システムの通知サービスを待機中",
            open: "開く",
            dismiss: "閉じる",
            unavailable: "この通知では、この操作を実行できなくなりました。",
            dismissSystemBanner: "システムの通知を閉じる",
            dismissSystemBannerHint: "Dynamic Islandに表示し、通知音が鳴り終わってから元の通知を閉じます。一瞬表示されます。")
        case .ko: return NotchNotificationStrings(
            title: "알림",
            description: "새 시스템 알림을 Dynamic Island에서 확인하세요.",
            privacy: "새로 표시된 알림만 보여줍니다. 메시지는 메모리에 보관되며 Mac을 잠그거나 기능을 끄면 지워집니다.",
            empty: "새 알림이 여기에 표시됩니다",
            waiting: "시스템 알림 서비스를 기다리는 중",
            open: "열기",
            dismiss: "닫기",
            unavailable: "이 알림에서는 더 이상 이 동작을 사용할 수 없습니다.",
            dismissSystemBanner: "시스템 알림 닫기",
            dismissSystemBannerHint: "Dynamic Island에 표시하고 알림음이 끝난 뒤 원래 알림을 닫습니다. 잠시 표시됩니다.")
        case .zhHans: return NotchNotificationStrings(
            title: "通知",
            description: "在Dynamic Island中查看新的系统通知。",
            privacy: "仅显示新出现的通知。消息只保存在内存中，锁定此 Mac 或关闭功能时会清除。",
            empty: "新通知将显示在这里",
            waiting: "正在等待系统通知服务",
            open: "打开",
            dismiss: "忽略",
            unavailable: "此通知已无法执行此操作。",
            dismissSystemBanner: "收起系统通知",
            dismissSystemBannerHint: "在Dynamic Island中显示并播放完提示音后关闭原通知。原通知仍会短暂出现。")
        case .zhTW: return NotchNotificationStrings(
            title: "通知",
            description: "在Dynamic Island中查看新的系統通知。",
            privacy: "只顯示新出現的通知。訊息僅保留在記憶體中，鎖定這部 Mac 或關閉功能時會清除。",
            empty: "新通知會顯示在這裡",
            waiting: "正在等待系統通知服務",
            open: "打開",
            dismiss: "關閉",
            unavailable: "此通知已無法執行此操作。",
            dismissSystemBanner: "收起系統通知",
            dismissSystemBannerHint: "在Dynamic Island中顯示並播放完提示音後關閉原通知。原通知仍會短暫出現。")
        case .zhHK: return NotchNotificationStrings(
            title: "通知",
            description: "在Dynamic Island中查看新的系統通知。",
            privacy: "只顯示新出現的通知。訊息只保留在記憶體中，鎖定此 Mac 或關閉功能時會清除。",
            empty: "新通知會顯示在這裏",
            waiting: "正在等候系統通知服務",
            open: "開啟",
            dismiss: "關閉",
            unavailable: "此通知已無法執行此操作。",
            dismissSystemBanner: "收起系統通知",
            dismissSystemBannerHint: "在Dynamic Island顯示並播放完提示音後關閉原通知。原通知仍會短暫出現。")
        }
    }
}
