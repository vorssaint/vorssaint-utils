// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SettingsNavigationStrings {
    let go: String
    let back: String
    let forward: String
    /// The names macOS gives its own sidebar command in each language.
    let showSidebar: String
    let hideSidebar: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(go: "Go", back: "Back", forward: "Forward",
                        showSidebar: "Show Sidebar", hideSidebar: "Hide Sidebar")
        case .ptBR:
            return Self(go: "Ir", back: "Voltar", forward: "Avançar",
                        showSidebar: "Mostrar Barra Lateral", hideSidebar: "Ocultar Barra Lateral")
        case .tr:
            return Self(go: "Git", back: "Geri", forward: "İleri",
                        showSidebar: "Kenar Çubuğunu Göster", hideSidebar: "Kenar Çubuğunu Gizle")
        case .ru:
            return Self(go: "Переход", back: "Назад", forward: "Вперёд",
                        showSidebar: "Показать боковое меню", hideSidebar: "Скрыть боковое меню")
        case .es:
            return Self(go: "Ir", back: "Atrás", forward: "Adelante",
                        showSidebar: "Mostrar barra lateral", hideSidebar: "Ocultar barra lateral")
        case .sk:
            return Self(go: "Prejsť", back: "Späť", forward: "Vpred",
                        showSidebar: "Zobraziť postranný panel", hideSidebar: "Skryť postranný panel")
        case .de:
            return Self(go: "Gehe zu", back: "Zurück", forward: "Vorwärts",
                        showSidebar: "Seitenleiste einblenden", hideSidebar: "Seitenleiste ausblenden")
        case .fr:
            return Self(go: "Aller", back: "Précédent", forward: "Suivant",
                        showSidebar: "Afficher la barre latérale", hideSidebar: "Masquer la barre latérale")
        case .it:
            return Self(go: "Vai", back: "Indietro", forward: "Avanti",
                        showSidebar: "Mostra barra laterale", hideSidebar: "Nascondi barra laterale")
        case .ja:
            return Self(go: "移動", back: "戻る", forward: "進む",
                        showSidebar: "サイドバーを表示", hideSidebar: "サイドバーを非表示")
        case .ko:
            return Self(go: "이동", back: "뒤로", forward: "앞으로",
                        showSidebar: "사이드바 보기", hideSidebar: "사이드바 가리기")
        case .uk:
            return Self(go: "Перейти", back: "Назад", forward: "Уперед",
                        showSidebar: "Показати бічну панель", hideSidebar: "Сховати бічну панель")
        case .zhHans:
            return Self(go: "前往", back: "后退", forward: "前进",
                        showSidebar: "显示边栏", hideSidebar: "隐藏边栏")
        case .zhTW, .zhHK:
            return Self(go: "前往", back: "上一頁", forward: "下一頁",
                        showSidebar: "顯示側邊欄", hideSidebar: "隱藏側邊欄")
        }
    }
}
