// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Shared labels for discovery controls.
struct SettingsDiscoveryStrings {
    let simple: String
    let advanced: String
    let expert: String
    let capture: String
    let applications: String
    let included: String
    private let controls: [String]

    enum Control: Int, CaseIterable {
        case show, visibility, hidden, shown, hiddenBy, filterHelp, searchVisible, category, allCategories
        case includedOnly, includedFirst, notIncluded, parentRequired, behaviorOff, behaviorOn, onDemand
        case turnOn, includeHelp, showEverything
    }

    func text(_ control: Control) -> String { controls[control.rawValue] }

    func name(_ level: SettingsExperience) -> String {
        switch level {
        case .simple: return simple
        case .advanced: return advanced
        case .expert: return expert
        }
    }

    static func localized(_ language: AppLanguage) -> Self {
        let words: [String]
        switch language {
        case .enUS: words = ["Focused", "Expanded", "Everything", "Capture & media", "Apps & maintenance", "Included in app"]
        case .ptBR: words = ["Focado", "Ampliado", "Tudo", "Captura e mídia", "Apps e manutenção", "Incluído no app"]
        case .es: words = ["Enfocado", "Ampliado", "Todo", "Captura y medios", "Apps y mantenimiento", "Incluido en la app"]
        case .sk: words = ["Zamerané", "Rozšírené", "Všetko", "Zachytávanie a médiá", "Aplikácie a údržba", "Zahrnuté v aplikácii"]
        case .de: words = ["Fokussiert", "Erweitert", "Alles", "Aufnahme & Medien", "Apps & Wartung", "In App enthalten"]
        case .fr: words = ["Ciblé", "Étendu", "Tout", "Capture et médias", "Apps et maintenance", "Inclus dans l’app"]
        case .it: words = ["Mirato", "Esteso", "Tutto", "Acquisizione e media", "App e manutenzione", "Incluso nell’app"]
        case .ru: words = ["Избранное", "Расширенное", "Всё", "Захват и медиа", "Приложения и обслуживание", "Включено в приложение"]
        case .tr: words = ["Odaklı", "Genişletilmiş", "Tümü", "Yakalama ve medya", "Uygulamalar ve bakım", "Uygulamaya dahil"]
        case .ja: words = ["厳選", "拡張", "すべて", "キャプチャとメディア", "アプリとメンテナンス", "アプリに含める"]
        case .ko: words = ["집중", "확장", "전체", "캡처 및 미디어", "앱 및 유지 관리", "앱에 포함"]
        case .uk: words = ["Вибране", "Розширене", "Все", "Захоплення й медіа", "Програми й обслуговування", "Включено в програму"]
        case .zhHans: words = ["精选", "扩展", "全部", "捕捉与媒体", "应用与维护", "包含在应用中"]
        case .zhTW, .zhHK: words = ["精選", "擴展", "全部", "擷取與媒體", "應用程式與維護", "包含在應用程式中"]
        }
        return Self(simple: words[0], advanced: words[1], expert: words[2], capture: words[3],
                    applications: words[4], included: words[5],
                    controls: controlLabels(language))
    }
    private static func controlLabels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return [
            "Show",
            "Feature visibility",
            "%d features hidden",
            "%d features shown",
            "%1$d hidden by %2$@",
            "This view filters the list only. Inclusion and activity are unchanged.",
            "Search visible features",
            "Category",
            "All categories",
            "Included only",
            "Included first",
            "Not included",
            "Requires Dynamic Island to be on",
            "Included · behavior off",
            "Included · behavior on",
            "Included · available on demand",
            "Turn on",
            "Include or remove this feature throughout the app. Saved settings are kept.",
            "Show everything"
        ]
        case .ptBR: return [
            "Mostrar",
            "Visibilidade de recursos",
            "%d recursos ocultos",
            "%d recursos exibidos",
            "%1$d ocultos por %2$@",
            "Esta visualização só filtra a lista. A inclusão e a atividade não mudam.",
            "Buscar recursos visíveis",
            "Categoria",
            "Todas as categorias",
            "Somente incluídos",
            "Incluídos primeiro",
            "Não incluído",
            "Requer Dynamic Island ativada",
            "Incluído · desativado",
            "Incluído · ativado",
            "Incluído · disponível sob demanda",
            "Ativar",
            "Inclua ou remova este recurso no app. As configurações salvas são mantidas.",
            "Mostrar tudo"
        ]
        case .es: return [
            "Mostrar",
            "Visibilidad de funciones",
            "%d funciones ocultas",
            "%d funciones visibles",
            "%1$d ocultas por %2$@",
            "Esta vista solo filtra la lista. La inclusión y la actividad no cambian.",
            "Buscar funciones visibles",
            "Categoría",
            "Todas las categorías",
            "Solo incluidas",
            "Incluidas primero",
            "No incluida",
            "Requiere Dynamic Island activada",
            "Incluida · desactivada",
            "Incluida · activada",
            "Incluida · disponible bajo demanda",
            "Activar",
            "Incluye o elimina esta función en la app. Se conservan los ajustes guardados.",
            "Mostrar todo"
        ]
        case .sk: return [
            "Zobraziť",
            "Viditeľnosť funkcií",
            "%d skrytých funkcií",
            "%d zobrazených funkcií",
            "%1$d skrytých v režime %2$@",
            "Tento pohľad iba filtruje zoznam. Zahrnutie a činnosť sa nemenia.",
            "Hľadať viditeľné funkcie",
            "Kategória",
            "Všetky kategórie",
            "Len zahrnuté",
            "Zahrnuté najprv",
            "Nezahrnuté",
            "Vyžaduje zapnutý Dynamic Island",
            "Zahrnuté · vypnuté",
            "Zahrnuté · zapnuté",
            "Zahrnuté · dostupné na požiadanie",
            "Zapnúť",
            "Zahrnúť alebo odstrániť túto funkciu v aplikácii. Uložené nastavenia sa zachovajú.",
            "Zobraziť všetko"
        ]
        case .de: return [
            "Anzeigen",
            "Funktionsanzeige",
            "%d Funktionen ausgeblendet",
            "%d Funktionen angezeigt",
            "%1$d durch %2$@ ausgeblendet",
            "Diese Ansicht filtert nur die Liste. Einbindung und Aktivität bleiben unverändert.",
            "Sichtbare Funktionen suchen",
            "Kategorie",
            "Alle Kategorien",
            "Nur enthaltene",
            "Enthaltene zuerst",
            "Nicht enthalten",
            "Erfordert aktiviertes Dynamic Island",
            "Enthalten · deaktiviert",
            "Enthalten · aktiviert",
            "Enthalten · bei Bedarf verfügbar",
            "Aktivieren",
            "Diese Funktion in der App hinzufügen oder entfernen. Gespeicherte Einstellungen bleiben erhalten.",
            "Alles anzeigen"
        ]
        case .fr: return [
            "Afficher",
            "Visibilité des fonctions",
            "%d fonctions masquées",
            "%d fonctions affichées",
            "%1$d masquées par %2$@",
            "Cette vue filtre seulement la liste. L’inclusion et l’activité restent inchangées.",
            "Rechercher les fonctions visibles",
            "Catégorie",
            "Toutes les catégories",
            "Incluses uniquement",
            "Incluses en premier",
            "Non incluse",
            "Nécessite Dynamic Island activée",
            "Incluse · désactivée",
            "Incluse · activée",
            "Incluse · disponible à la demande",
            "Activer",
            "Inclure ou retirer cette fonction dans l’app. Les réglages enregistrés sont conservés.",
            "Tout afficher"
        ]
        case .it: return [
            "Mostra",
            "Visibilità delle funzioni",
            "%d funzioni nascoste",
            "%d funzioni mostrate",
            "%1$d nascoste da %2$@",
            "Questa vista filtra solo l’elenco. Inclusione e attività non cambiano.",
            "Cerca funzioni visibili",
            "Categoria",
            "Tutte le categorie",
            "Solo incluse",
            "Incluse prima",
            "Non inclusa",
            "Richiede Dynamic Island attiva",
            "Inclusa · disattivata",
            "Inclusa · attivata",
            "Inclusa · disponibile su richiesta",
            "Attiva",
            "Includi o rimuovi questa funzione nell’app. Le impostazioni salvate vengono conservate.",
            "Mostra tutto"
        ]
        case .ru: return [
            "Показать",
            "Видимость функций",
            "Скрыто функций: %d",
            "Показано функций: %d",
            "Скрыто: %1$d · %2$@",
            "Этот режим фильтрует только список. Доступность и работа функций не меняются.",
            "Поиск видимых функций",
            "Категория",
            "Все категории",
            "Только включённые",
            "Сначала включённые",
            "Не включено",
            "Требуется включить Dynamic Island",
            "Включено · действие выключено",
            "Включено · действие включено",
            "Включено · доступно по запросу",
            "Включить",
            "Добавить или убрать эту функцию во всём приложении. Сохранённые настройки останутся.",
            "Показать всё"
        ]
        case .uk: return [
            "Показати",
            "Видимість функцій",
            "Приховано функцій: %d",
            "Показано функцій: %d",
            "Приховано: %1$d · %2$@",
            "Цей режим фільтрує лише список. Доступність і робота функцій не змінюються.",
            "Пошук видимих функцій",
            "Категорія",
            "Усі категорії",
            "Лише включені",
            "Спочатку включені",
            "Не включено",
            "Потрібно ввімкнути Dynamic Island",
            "Включено · дію вимкнено",
            "Включено · дію ввімкнено",
            "Включено · доступно на запит",
            "Увімкнути",
            "Додати або прибрати цю функцію в усьому застосунку. Збережені налаштування залишаться.",
            "Показати все"
        ]
        case .tr: return [
            "Göster",
            "Özellik görünürlüğü",
            "%d özellik gizli",
            "%d özellik gösteriliyor",
            "%2$@ ile %1$d gizli",
            "Bu görünüm yalnızca listeyi filtreler. Dahil edilme ve etkinlik değişmez.",
            "Görünür özellikleri ara",
            "Kategori",
            "Tüm kategoriler",
            "Yalnızca dahil olanlar",
            "Dahil olanlar önce",
            "Dahil değil",
            "Dynamic Island açık olmalı",
            "Dahil · kapalı",
            "Dahil · açık",
            "Dahil · istek üzerine kullanılabilir",
            "Aç",
            "Bu özelliği uygulamaya dahil et veya kaldır. Kaydedilen ayarlar korunur.",
            "Tümünü göster"
        ]
        case .ja: return [
            "表示",
            "機能の表示範囲",
            "%d個の機能を非表示",
            "%d個の機能を表示",
            "%1$d個を%2$@で非表示",
            "この表示はリストのみを絞り込みます。機能の追加状態や動作は変わりません。",
            "表示中の機能を検索",
            "カテゴリ",
            "すべてのカテゴリ",
            "含まれる機能のみ",
            "含まれる機能を先に",
            "含まれていません",
            "Dynamic Islandをオンにする必要があります",
            "含まれる機能 · 動作オフ",
            "含まれる機能 · 動作オン",
            "含まれる機能 · 必要時に使用可能",
            "オンにする",
            "アプリ全体でこの機能を追加または削除します。保存した設定は保持されます。",
            "すべて表示"
        ]
        case .ko: return [
            "표시",
            "기능 표시 범위",
            "기능 %d개 숨김",
            "기능 %d개 표시",
            "%2$@에서 %1$d개 숨김",
            "이 보기는 목록만 필터링합니다. 포함 여부와 동작은 바뀌지 않습니다.",
            "표시된 기능 검색",
            "카테고리",
            "모든 카테고리",
            "포함된 기능만",
            "포함된 기능 먼저",
            "포함되지 않음",
            "Dynamic Island를 켜야 합니다",
            "포함됨 · 동작 꺼짐",
            "포함됨 · 동작 켜짐",
            "포함됨 · 필요할 때 사용 가능",
            "켜기",
            "앱 전체에서 이 기능을 포함하거나 제거합니다. 저장된 설정은 유지됩니다.",
            "모두 표시"
        ]
        case .zhHans: return [
            "显示",
            "功能显示范围",
            "已隐藏 %d 项功能",
            "已显示 %d 项功能",
            "%2$@隐藏 %1$d 项",
            "此视图只筛选列表。功能的包含状态和运行状态不变。",
            "搜索显示的功能",
            "类别",
            "所有类别",
            "仅已包含",
            "已包含优先",
            "未包含",
            "需要开启 Dynamic Island",
            "已包含 · 行为关闭",
            "已包含 · 行为开启",
            "已包含 · 按需使用",
            "开启",
            "在整个应用中包含或移除此功能。已保存的设置会保留。",
            "显示全部"
        ]
        case .zhTW, .zhHK: return [
            "顯示",
            "功能顯示範圍",
            "已隱藏 %d 項功能",
            "已顯示 %d 項功能",
            "%2$@隱藏 %1$d 項",
            "此檢視只篩選清單。功能的包含狀態和執行狀態不變。",
            "搜尋顯示的功能",
            "類別",
            "所有類別",
            "僅已包含",
            "已包含優先",
            "未包含",
            "需要開啟 Dynamic Island",
            "已包含 · 行為關閉",
            "已包含 · 行為開啟",
            "已包含 · 按需使用",
            "開啟",
            "在整個應用程式中包含或移除此功能。已儲存的設定會保留。",
            "顯示全部"
        ]
        }
    }

}
