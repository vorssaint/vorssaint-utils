// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SettingsNavigationStrings {
    let go: String
    let back: String
    let forward: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return Self(go: "Go", back: "Back", forward: "Forward")
        case .ptBR: return Self(go: "Ir", back: "Voltar", forward: "Avan\u{e7}ar")
        case .tr: return Self(go: "Git", back: "Geri", forward: "\u{130}leri")
        case .ru: return Self(go: "\u{41f}\u{435}\u{440}\u{435}\u{445}\u{43e}\u{434}",
                              back: "\u{41d}\u{430}\u{437}\u{430}\u{434}",
                              forward: "\u{412}\u{43f}\u{435}\u{440}\u{451}\u{434}")
        case .es: return Self(go: "Ir", back: "Atr\u{e1}s", forward: "Adelante")
        case .de: return Self(go: "Gehe zu", back: "Zur\u{fc}ck", forward: "Vorw\u{e4}rts")
        case .fr: return Self(go: "Aller", back: "Pr\u{e9}c\u{e9}dent", forward: "Suivant")
        case .it: return Self(go: "Vai", back: "Indietro", forward: "Avanti")
        case .ja: return Self(go: "\u{79fb}\u{52d5}", back: "\u{623b}\u{308b}", forward: "\u{9032}\u{3080}")
        case .ko: return Self(go: "\u{c774}\u{b3d9}", back: "\u{b4a4}\u{b85c}", forward: "\u{c55e}\u{c73c}\u{b85c}")
        case .zhHans: return Self(go: "\u{524d}\u{5f80}", back: "\u{540e}\u{9000}", forward: "\u{524d}\u{8fdb}")
        case .zhTW, .zhHK:
            return Self(go: "\u{524d}\u{5f80}", back: "\u{4e0a}\u{4e00}\u{9801}", forward: "\u{4e0b}\u{4e00}\u{9801}")
        }
    }
}
