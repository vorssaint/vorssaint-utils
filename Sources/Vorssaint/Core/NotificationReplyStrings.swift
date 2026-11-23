// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotificationReplyStrings {
    let reply: String
    let send: String
    let placeholder: String
    let sent: String
    /// The app's reply is no longer there, as when the message has left Notification Centre.
    let unavailable: String
    /// Opens the app's notification settings, to make its alerts Persistent.
    var keepAlerts: String { Self.keepAlerts[reply] ?? "Keep alerts" }

    private static let keepAlerts = [
        "Reply": "Make alerts Persistent", "Responder": "Alertas persistentes", "Odpovedať": "Trvalé upozornenia",
        "Antworten": "Hinweise dauerhaft", "Répondre": "Alertes persistantes", "Rispondi": "Avvisi persistenti",
        "Ответить": "Постоянные оповещения", "Yanıtla": "Kalıcı uyarılar", "返信": "通知を持続表示に", "답장": "지속적 알림으로",
        "回复": "设为持续提醒", "回覆": "設為持續提示", "Відповісти": "Постійні сповіщення",
    ]

    static func localized(_ language: AppLanguage) -> NotificationReplyStrings {
        switch language {
        case .enUS: return .init(reply: "Reply", send: "Send", placeholder: "Message", sent: "Sent", unavailable: "Can’t reply here any more. Open the app to reply.")
        case .ptBR: return .init(reply: "Responder", send: "Enviar", placeholder: "Mensagem", sent: "Enviada", unavailable: "Não é mais possível responder aqui. Abra o app para responder.")
        case .es: return .init(reply: "Responder", send: "Enviar", placeholder: "Mensaje", sent: "Enviado", unavailable: "Ya no se puede responder aquí. Abre la app para responder.")
        case .sk: return .init(reply: "Odpovedať", send: "Odoslať", placeholder: "Správa", sent: "Odoslané", unavailable: "Tu už nie je možné odpovedať. Otvorte aplikáciu.")
        case .de: return .init(reply: "Antworten", send: "Senden", placeholder: "Nachricht", sent: "Gesendet", unavailable: "Hier kann nicht mehr geantwortet werden. Öffne die App zum Antworten.")
        case .fr: return .init(reply: "Répondre", send: "Envoyer", placeholder: "Message", sent: "Envoyé", unavailable: "Impossible de répondre ici. Ouvrez l’app pour répondre.")
        case .it: return .init(reply: "Rispondi", send: "Invia", placeholder: "Messaggio", sent: "Inviato", unavailable: "Non è più possibile rispondere qui. Apri l’app per rispondere.")
        case .ru: return .init(reply: "Ответить", send: "Отправить", placeholder: "Сообщение", sent: "Отправлено", unavailable: "Ответить здесь больше нельзя. Откройте приложение.")
        case .tr: return .init(reply: "Yanıtla", send: "Gönder", placeholder: "Mesaj", sent: "Gönderildi", unavailable: "Buradan artık yanıtlanamıyor. Yanıtlamak için uygulamayı açın.")
        case .ja: return .init(reply: "返信", send: "送信", placeholder: "メッセージ", sent: "送信しました", unavailable: "ここからは返信できなくなりました。アプリを開いて返信してください。")
        case .ko: return .init(reply: "답장", send: "보내기", placeholder: "메시지", sent: "보냄", unavailable: "여기서는 더 이상 답장할 수 없습니다. 앱을 열어 답장하세요.")
        case .zhHans: return .init(reply: "回复", send: "发送", placeholder: "消息", sent: "已发送", unavailable: "无法再在此处回复。请打开 App 回复。")
        case .zhTW: return .init(reply: "回覆", send: "傳送", placeholder: "訊息", sent: "已傳送", unavailable: "無法再在此處回覆。請打開 App 回覆。")
        case .zhHK: return .init(reply: "回覆", send: "傳送", placeholder: "訊息", sent: "已傳送", unavailable: "無法再喺度回覆。請打開 App 回覆。")
        case .uk: return .init(reply: "Відповісти", send: "Надіслати", placeholder: "Повідомлення", sent: "Надіслано", unavailable: "Відповісти тут уже не можна. Відкрийте програму.")
        }
    }
}
