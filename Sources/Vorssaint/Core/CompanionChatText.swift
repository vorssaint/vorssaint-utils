// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// short chat strings for every language, {ai} gets swapped for the ai name
enum CompanionChatText {
    // ask, refresh, open, send, closed early msg
    static func values(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Ask {ai}", "Refresh", "Open {ai}", "Send", "Closed before an answer arrived. Ask again if you still need it."]
        case .ptBR: return ["Perguntar a {ai}", "Atualizar", "Abrir {ai}", "Enviar", "Fechado antes de chegar uma resposta. Pergunte de novo se ainda precisar."]
        case .es: return ["Preguntar a {ai}", "Actualizar", "Abrir {ai}", "Enviar", "Se cerró antes de recibir una respuesta. Vuelve a preguntar si aún lo necesitas."]
        case .fr: return ["Demander à {ai}", "Actualiser", "Ouvrir {ai}", "Envoyer", "Fermé avant l’arrivée d’une réponse. Redemandez si besoin."]
        case .de: return ["{ai} fragen", "Aktualisieren", "{ai} öffnen", "Senden", "Geschlossen, bevor eine Antwort kam. Frag erneut, falls nötig."]
        case .it: return ["Chiedi a {ai}", "Aggiorna", "Apri {ai}", "Invia", "Chiuso prima dell’arrivo di una risposta. Richiedi di nuovo se serve."]
        case .tr: return ["Soru sor: {ai}", "Yenile", "{ai} uygulamasını aç", "Gönder", "Yanıt gelmeden kapatıldı. Hâlâ gerekiyorsa tekrar sorun."]
        case .ru: return ["Спросить {ai}", "Обновить", "Открыть {ai}", "Отправить", "Закрыто до получения ответа. Спросите снова, если нужно."]
        case .uk: return ["Запитати {ai}", "Оновити", "Відкрити {ai}", "Надіслати", "Закрито до отримання відповіді. Запитайте знову, якщо потрібно."]
        case .sk: return ["Opýtať sa: {ai}", "Obnoviť", "Otvoriť {ai}", "Odoslať", "Zatvorené pred príchodom odpovede. Opýtajte sa znova, ak treba."]
        case .ja: return ["{ai} に質問", "更新", "{ai} を開く", "送信", "回答が届く前に閉じました。必要なら、もう一度質問してください。"]
        case .ko: return ["질문: {ai}", "새로 고침", "{ai} 열기", "보내기", "답변이 오기 전에 닫혔습니다. 필요하면 다시 질문하세요."]
        case .zhHans: return ["询问 {ai}", "刷新", "打开 {ai}", "发送", "在收到回答前已关闭。如仍需要，请再问一次。"]
        case .zhTW: return ["詢問 {ai}", "重新整理", "開啟 {ai}", "傳送", "在收到回答前已關閉。如仍需要，請再詢問一次。"]
        case .zhHK: return ["詢問 {ai}", "重新整理", "開啟 {ai}", "傳送", "在收到回答前已關閉。如仍需要，請再詢問一次。"]
        }
    }
    private static var strings: [String] { values(L10n.shared.language) }
    private static func named(_ text: String, _ agentTitle: String) -> String {
        text.replacingOccurrences(of: "{ai}", with: agentTitle)
    }
    /// the box prompt like Ask Claude
    static func ask(_ agentTitle: String) -> String { named(strings[0], agentTitle) }
    static var refresh: String { strings[1] }
    static func openApp(_ agentTitle: String) -> String { named(strings[2], agentTitle) }
    static var send: String { strings[3] }
    static var uncertain: String { strings[4] }
}
