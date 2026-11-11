// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The seats' card's own controls on the AI page, and what Spending says of
/// a model the price list does not know.
struct AgentSeatMenuStrings {
    /// Opens the seats' settings, where a seat is added.
    let addSeat: String
    let moveLeft: String
    let moveRight: String
    /// In place of a model's value when no price is known for it.
    let noPrice: String
}

extension FeatureStrings {
    static func agentSeatMenu(_ language: AppLanguage) -> AgentSeatMenuStrings {
        switch language {
        case .enUS: return AgentSeatMenuStrings(
            addSeat: "Add Team seat", moveLeft: "Move left", moveRight: "Move right", noPrice: "no price")
        case .ptBR: return AgentSeatMenuStrings(
            addSeat: "Adicionar assento", moveLeft: "Mover para a esquerda", moveRight: "Mover para a direita",
            noPrice: "sem preço")
        case .tr: return AgentSeatMenuStrings(
            addSeat: "Team koltuğu ekle", moveLeft: "Sola taşı", moveRight: "Sağa taşı", noPrice: "fiyat yok")
        case .ru: return AgentSeatMenuStrings(
            addSeat: "Добавить место Team", moveLeft: "Сдвинуть влево", moveRight: "Сдвинуть вправо",
            noPrice: "нет цены")
        case .es: return AgentSeatMenuStrings(
            addSeat: "Añadir puesto de Team", moveLeft: "Mover a la izquierda", moveRight: "Mover a la derecha",
            noPrice: "sin precio")
        case .sk: return AgentSeatMenuStrings(
            addSeat: "Pridať miesto Team", moveLeft: "Posunúť doľava", moveRight: "Posunúť doprava",
            noPrice: "bez ceny")
        case .de: return AgentSeatMenuStrings(
            addSeat: "Team-Platz hinzufügen", moveLeft: "Nach links", moveRight: "Nach rechts", noPrice: "kein Preis")
        case .fr: return AgentSeatMenuStrings(
            addSeat: "Ajouter un siège Team", moveLeft: "Déplacer à gauche", moveRight: "Déplacer à droite",
            noPrice: "sans prix")
        case .it: return AgentSeatMenuStrings(
            addSeat: "Aggiungi posto Team", moveLeft: "Sposta a sinistra", moveRight: "Sposta a destra",
            noPrice: "senza prezzo")
        case .ja: return AgentSeatMenuStrings(
            addSeat: "Teamシートを追加", moveLeft: "左へ移動", moveRight: "右へ移動", noPrice: "価格なし")
        case .ko: return AgentSeatMenuStrings(
            addSeat: "Team 시트 추가", moveLeft: "왼쪽으로 이동", moveRight: "오른쪽으로 이동", noPrice: "가격 없음")
        case .uk: return AgentSeatMenuStrings(
            addSeat: "Додати місце Team", moveLeft: "Зсунути ліворуч", moveRight: "Зсунути праворуч",
            noPrice: "немає ціни")
        case .zhHans: return AgentSeatMenuStrings(
            addSeat: "添加 Team 席位", moveLeft: "左移", moveRight: "右移", noPrice: "无价格")
        case .zhTW: return AgentSeatMenuStrings(
            addSeat: "加入 Team 席位", moveLeft: "左移", moveRight: "右移", noPrice: "無價格")
        case .zhHK: return AgentSeatMenuStrings(
            addSeat: "加入 Team 席位", moveLeft: "左移", moveRight: "右移", noPrice: "無價格")
        }
    }
}
