// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SettingsNavigationStrings {
    let go: String
    let back: String
    let forward: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return Self(go: "Go", back: "Back", forward: "Forward")
        case .ptBR: return Self(go: "Ir", back: "Voltar", forward: "Avançar")
        case .tr: return Self(go: "Git", back: "Geri", forward: "İleri")
        case .ru: return Self(go: "Переход", back: "Назад", forward: "Вперёд")
        case .es: return Self(go: "Ir", back: "Atrás", forward: "Adelante")
        case .de: return Self(go: "Gehe zu", back: "Zurück", forward: "Vorwärts")
        case .fr: return Self(go: "Aller", back: "Précédent", forward: "Suivant")
        case .it: return Self(go: "Vai", back: "Indietro", forward: "Avanti")
        case .ja: return Self(go: "移動", back: "戻る", forward: "進む")
        case .ko: return Self(go: "이동", back: "뒤로", forward: "앞으로")
        case .zhHans: return Self(go: "前往", back: "后退", forward: "前进")
        case .zhTW, .zhHK:
            return Self(go: "前往", back: "上一頁", forward: "下一頁")
        }
    }
}
