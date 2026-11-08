// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SettingsSidebarStrings {
    let favorites: String
    let organize: String
    let sortBy: String
    let defaultOrder: String
    let mostUsed: String
    let name: String
    let manual: String
    let addToFavorites: String
    let removeFromFavorites: String

    static func resetUsageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: "Reset Most Used"
        case .ptBR: "Redefinir Mais usados"
        case .tr: "En Çok Kullanılanları Sıfırla"
        case .ru: "Сбросить частоту использования"
        case .es: "Restablecer más usados"
        case .sk: "Obnoviť najpoužívanejšie"
        case .de: "Am häufigsten verwendet zurücksetzen"
        case .fr: "Réinitialiser les plus utilisés"
        case .it: "Reimposta i più usati"
        case .ja: "使用頻度をリセット"
        case .ko: "사용 빈도 초기화"
        case .uk: "Скинути найуживаніші"
        case .zhHans: "重置使用频率"
        case .zhTW, .zhHK: "重設使用頻率"
        }
    }

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            Self(favorites: "Favorites", organize: "Organize Sidebar", sortBy: "Sort By",
                 defaultOrder: "Default", mostUsed: "Most Used", name: "Name", manual: "Manual",
                 addToFavorites: "Add to Favorites", removeFromFavorites: "Remove from Favorites")
        case .ptBR:
            Self(favorites: "Favoritos", organize: "Organizar Barra Lateral", sortBy: "Ordenar por",
                 defaultOrder: "Padrão", mostUsed: "Mais usados", name: "Nome", manual: "Manual",
                 addToFavorites: "Adicionar aos Favoritos", removeFromFavorites: "Remover dos Favoritos")
        case .tr:
            Self(favorites: "Favoriler", organize: "Kenar Çubuğunu Düzenle", sortBy: "Sıralama",
                 defaultOrder: "Varsayılan", mostUsed: "En Çok Kullanılan", name: "Ad", manual: "Elle",
                 addToFavorites: "Favorilere Ekle", removeFromFavorites: "Favorilerden Kaldır")
        case .ru:
            Self(favorites: "Избранное", organize: "Упорядочить боковое меню", sortBy: "Сортировка",
                 defaultOrder: "По умолчанию", mostUsed: "По частоте использования", name: "По имени", manual: "Вручную",
                 addToFavorites: "Добавить в избранное", removeFromFavorites: "Убрать из избранного")
        case .es:
            Self(favorites: "Favoritos", organize: "Organizar barra lateral", sortBy: "Ordenar por",
                 defaultOrder: "Predeterminado", mostUsed: "Más usados", name: "Nombre", manual: "Manual",
                 addToFavorites: "Añadir a favoritos", removeFromFavorites: "Quitar de favoritos")
        case .sk:
            Self(favorites: "Obľúbené", organize: "Usporiadať bočný panel", sortBy: "Zoradiť podľa",
                 defaultOrder: "Predvolené", mostUsed: "Najpoužívanejšie", name: "Názov", manual: "Ručne",
                 addToFavorites: "Pridať medzi obľúbené", removeFromFavorites: "Odstrániť z obľúbených")
        case .de:
            Self(favorites: "Favoriten", organize: "Seitenleiste organisieren", sortBy: "Sortieren nach",
                 defaultOrder: "Standard", mostUsed: "Am häufigsten verwendet", name: "Name", manual: "Manuell",
                 addToFavorites: "Zu Favoriten hinzufügen", removeFromFavorites: "Aus Favoriten entfernen")
        case .fr:
            Self(favorites: "Favoris", organize: "Organiser la barre latérale", sortBy: "Trier par",
                 defaultOrder: "Par défaut", mostUsed: "Les plus utilisés", name: "Nom", manual: "Manuel",
                 addToFavorites: "Ajouter aux favoris", removeFromFavorites: "Retirer des favoris")
        case .it:
            Self(favorites: "Preferiti", organize: "Organizza barra laterale", sortBy: "Ordina per",
                 defaultOrder: "Predefinito", mostUsed: "Più usati", name: "Nome", manual: "Manuale",
                 addToFavorites: "Aggiungi ai preferiti", removeFromFavorites: "Rimuovi dai preferiti")
        case .ja:
            Self(favorites: "お気に入り", organize: "サイドバーを整理", sortBy: "並べ替え",
                 defaultOrder: "デフォルト", mostUsed: "使用頻度順", name: "名前順", manual: "手動",
                 addToFavorites: "お気に入りに追加", removeFromFavorites: "お気に入りから削除")
        case .ko:
            Self(favorites: "즐겨찾기", organize: "사이드바 정리", sortBy: "정렬 기준",
                 defaultOrder: "기본값", mostUsed: "사용 빈도순", name: "이름순", manual: "수동",
                 addToFavorites: "즐겨찾기에 추가", removeFromFavorites: "즐겨찾기에서 제거")
        case .uk:
            Self(favorites: "Вибране", organize: "Упорядкувати бічну панель", sortBy: "Сортувати за",
                 defaultOrder: "За замовчуванням", mostUsed: "За частотою використання", name: "За назвою", manual: "Вручну",
                 addToFavorites: "Додати до вибраного", removeFromFavorites: "Вилучити з вибраного")
        case .zhHans:
            Self(favorites: "个人收藏", organize: "整理边栏", sortBy: "排序方式",
                 defaultOrder: "默认", mostUsed: "使用频率", name: "名称", manual: "手动",
                 addToFavorites: "添加到个人收藏", removeFromFavorites: "从个人收藏中移除")
        case .zhTW, .zhHK:
            Self(favorites: "喜好項目", organize: "整理側邊欄", sortBy: "排序方式",
                 defaultOrder: "預設", mostUsed: "使用頻率", name: "名稱", manual: "手動",
                 addToFavorites: "加入喜好項目", removeFromFavorites: "從喜好項目中移除")
        }
    }
}
