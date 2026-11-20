// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchInputFeedbackStrings {
    let pasted: String
    let capsLock: String
    let shiftHeld: String

    static func localized(_ language: AppLanguage) -> NotchInputFeedbackStrings {
        switch language {
        case .enUS:
            return NotchInputFeedbackStrings(pasted: "Pasted", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .ptBR:
            return NotchInputFeedbackStrings(pasted: "Colado", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .tr:
            return NotchInputFeedbackStrings(pasted: "Yapistirildi", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .ru:
            return NotchInputFeedbackStrings(pasted: "Вставлено", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .es:
            return NotchInputFeedbackStrings(pasted: "Pegado", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .sk:
            return NotchInputFeedbackStrings(pasted: "Vlozene", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .de:
            return NotchInputFeedbackStrings(pasted: "Eingefugt", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .fr:
            return NotchInputFeedbackStrings(pasted: "Colle", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .it:
            return NotchInputFeedbackStrings(pasted: "Incollato", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .ja:
            return NotchInputFeedbackStrings(pasted: "ペースト済み", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .ko:
            return NotchInputFeedbackStrings(pasted: "붙여넣음", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .uk:
            return NotchInputFeedbackStrings(pasted: "Вставлено", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .zhHans:
            return NotchInputFeedbackStrings(pasted: "已粘贴", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .zhTW:
            return NotchInputFeedbackStrings(pasted: "已貼上", capsLock: "CAPS", shiftHeld: "SHIFT")
        case .zhHK:
            return NotchInputFeedbackStrings(pasted: "已貼上", capsLock: "CAPS", shiftHeld: "SHIFT")
        }
    }
}
