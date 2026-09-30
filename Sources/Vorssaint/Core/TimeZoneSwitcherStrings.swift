// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the Time Zone Switcher feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct TimeZoneSwitcherFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let currentLabel: String
    let panelCaption: String
    let automaticHint: String
    let searchPlaceholder: String
    let favoritesHeader: String
    let emptyFavoritesTitle: String
    let emptyFavoritesHint: String
    let addFavoriteHelp: String
    let removeFavoriteHelp: String
    let switchButton: String
    let switchingLabel: String
    let currentBadge: String
    let switchFailedTitle: String
    let switchFailedMessage: String
    let adminSetupPrompt: String
    let adminRemovePrompt: String
    let commandBarToggle: String
    let commandBarCaption: String
}

extension FeatureStrings {
    static func timeZoneSwitcher(_ language: AppLanguage) -> TimeZoneSwitcherFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension TimeZoneSwitcherFeatureStrings {
    static let enUS = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Time Zone Switcher",
        hubDescription: "Switch the Mac’s system time zone in one click, with a list of favorites",
        currentLabel: "Current Time Zone",
        panelCaption: "Switch between your favorite time zones",
        automaticHint: "If your Mac sets its time zone automatically by location, switching it here may be overridden. Turn that off in System Settings › General › Date & Time.",
        searchPlaceholder: "Search cities and regions",
        favoritesHeader: "Favorites",
        emptyFavoritesTitle: "No Favorites Yet",
        emptyFavoritesHint: "Search for a city above and add it to switch to it in one click.",
        addFavoriteHelp: "Add to Favorites",
        removeFavoriteHelp: "Remove",
        switchButton: "Switch",
        switchingLabel: "Switching…",
        currentBadge: "Current",
        switchFailedTitle: "Couldn’t Switch Time Zone",
        switchFailedMessage: "The change may have been cancelled or require additional privileges.",
        adminSetupPrompt: "Vorssaint will create a restricted rule (systemsetup -settimezone only) so you can switch time zones without entering your password every time. This is the only time the password is needed.",
        adminRemovePrompt: "Vorssaint will remove the time zone switching rule it created.",
        commandBarToggle: "Show in Command Bar",
        commandBarCaption: "Adds your favorite time zones to the Command Bar, so you can switch without opening Settings."
    )

    static let ptBR = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Trocar Fuso Horário",
        hubDescription: "Troque o fuso horário do sistema com um clique, a partir de uma lista de favoritos",
        currentLabel: "Fuso Horário Atual",
        panelCaption: "Alterne entre seus fusos horários favoritos",
        automaticHint: "Se o seu Mac define o fuso horário automaticamente pela localização, trocar aqui pode ser revertido. Desative isso em Ajustes do Sistema › Geral › Data e Hora.",
        searchPlaceholder: "Buscar cidades e regiões",
        favoritesHeader: "Favoritos",
        emptyFavoritesTitle: "Nenhum favorito ainda",
        emptyFavoritesHint: "Busque uma cidade acima e adicione-a para trocar com um clique.",
        addFavoriteHelp: "Adicionar aos Favoritos",
        removeFavoriteHelp: "Remover",
        switchButton: "Trocar",
        switchingLabel: "Trocando…",
        currentBadge: "Atual",
        switchFailedTitle: "Não foi possível trocar o fuso horário",
        switchFailedMessage: "A alteração pode ter sido cancelada ou exigir privilégios adicionais.",
        adminSetupPrompt: "O Vorssaint vai criar uma regra restrita (somente systemsetup -settimezone) para você trocar de fuso horário sem digitar a senha toda vez. Esta é a única vez que a senha será necessária.",
        adminRemovePrompt: "O Vorssaint vai remover a regra de troca de fuso horário que ele criou.",
        commandBarToggle: "Mostrar na Barra de Comandos",
        commandBarCaption: "Adiciona seus fusos horários favoritos à Barra de Comandos, para trocar sem abrir os Ajustes."
    )

    static let tr = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Saat Dilimi Değiştirici",
        hubDescription: "Favori listenizden tek tıkla Mac’in sistem saat dilimini değiştirin",
        currentLabel: "Geçerli Saat Dilimi",
        panelCaption: "Favori saat dilimleriniz arasında geçiş yapın",
        automaticHint: "Mac’iniz saat dilimini konuma göre otomatik ayarlıyorsa, burada yaptığınız değişiklik geçersiz kılınabilir. Bunu Sistem Ayarları › Genel › Tarih ve Saat’ten kapatın.",
        searchPlaceholder: "Şehir ve bölge ara",
        favoritesHeader: "Favoriler",
        emptyFavoritesTitle: "Henüz Favori Yok",
        emptyFavoritesHint: "Yukarıdan bir şehir arayın ve tek tıkla geçiş yapmak için ekleyin.",
        addFavoriteHelp: "Favorilere Ekle",
        removeFavoriteHelp: "Kaldır",
        switchButton: "Değiştir",
        switchingLabel: "Değiştiriliyor…",
        currentBadge: "Geçerli",
        switchFailedTitle: "Saat Dilimi Değiştirilemedi",
        switchFailedMessage: "Değişiklik iptal edilmiş veya ek yetkiler gerektiriyor olabilir.",
        adminSetupPrompt: "Vorssaint, saat dilimini her seferinde şifre girmeden değiştirebilmeniz için kısıtlı bir kural (yalnızca systemsetup -settimezone) oluşturacak. Şifre yalnızca bu sefer gerekiyor.",
        adminRemovePrompt: "Vorssaint, oluşturduğu saat dilimi değiştirme kuralını kaldıracak.",
        commandBarToggle: "Komut Çubuğunda Göster",
        commandBarCaption: "Favori saat dilimlerinizi Komut Çubuğuna ekler, böylece Ayarları açmadan değiştirebilirsiniz."
    )

    static let ru = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Переключение часового пояса",
        hubDescription: "Переключайте системный часовой пояс Mac в один клик, используя список избранного",
        currentLabel: "Текущий часовой пояс",
        panelCaption: "Переключайтесь между избранными часовыми поясами",
        automaticHint: "Если Mac устанавливает часовой пояс автоматически по местоположению, изменение здесь может быть отменено. Отключите это в «Настройки системы» › «Основные» › «Дата и время».",
        searchPlaceholder: "Поиск городов и регионов",
        favoritesHeader: "Избранное",
        emptyFavoritesTitle: "Пока нет избранного",
        emptyFavoritesHint: "Найдите город выше и добавьте его, чтобы переключаться одним кликом.",
        addFavoriteHelp: "Добавить в избранное",
        removeFavoriteHelp: "Удалить",
        switchButton: "Переключить",
        switchingLabel: "Переключение…",
        currentBadge: "Текущий",
        switchFailedTitle: "Не удалось переключить часовой пояс",
        switchFailedMessage: "Изменение могло быть отменено или требует дополнительных прав.",
        adminSetupPrompt: "Vorssaint создаст ограниченное правило (только systemsetup -settimezone), чтобы вы могли переключать часовые пояса без ввода пароля каждый раз. Пароль нужен только сейчас.",
        adminRemovePrompt: "Vorssaint удалит созданное им правило переключения часового пояса.",
        commandBarToggle: "Показывать в панели команд",
        commandBarCaption: "Добавляет избранные часовые пояса в панель команд, чтобы переключаться без открытия настроек."
    )

    static let es = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Cambiar Zona Horaria",
        hubDescription: "Cambia la zona horaria del sistema del Mac con un clic, desde una lista de favoritos",
        currentLabel: "Zona Horaria Actual",
        panelCaption: "Cambia entre tus zonas horarias favoritas",
        automaticHint: "Si tu Mac define la zona horaria automáticamente según la ubicación, el cambio aquí puede revertirse. Desactívalo en Ajustes del Sistema › General › Fecha y Hora.",
        searchPlaceholder: "Buscar ciudades y regiones",
        favoritesHeader: "Favoritos",
        emptyFavoritesTitle: "Aún no hay favoritos",
        emptyFavoritesHint: "Busca una ciudad arriba y añádela para cambiar con un clic.",
        addFavoriteHelp: "Añadir a Favoritos",
        removeFavoriteHelp: "Quitar",
        switchButton: "Cambiar",
        switchingLabel: "Cambiando…",
        currentBadge: "Actual",
        switchFailedTitle: "No se pudo cambiar la zona horaria",
        switchFailedMessage: "El cambio pudo haberse cancelado o requerir privilegios adicionales.",
        adminSetupPrompt: "Vorssaint creará una regla restringida (solo systemsetup -settimezone) para que puedas cambiar de zona horaria sin introducir tu contraseña cada vez. Esta es la única vez que se necesita la contraseña.",
        adminRemovePrompt: "Vorssaint eliminará la regla de cambio de zona horaria que creó.",
        commandBarToggle: "Mostrar en la Barra de Comandos",
        commandBarCaption: "Añade tus zonas horarias favoritas a la Barra de Comandos, para cambiar sin abrir los Ajustes."
    )

    static let sk = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Prepínač časového pásma",
        hubDescription: "Jedným kliknutím prepnite systémové časové pásmo Macu zo zoznamu obľúbených",
        currentLabel: "Aktuálne časové pásmo",
        panelCaption: "Prepínajte medzi obľúbenými časovými pásmami",
        automaticHint: "Ak Mac nastavuje časové pásmo automaticky podľa polohy, zmena tu môže byť prepísaná. Vypnite to v Nastaveniach systému › Všeobecné › Dátum a čas.",
        searchPlaceholder: "Hľadať mestá a regióny",
        favoritesHeader: "Obľúbené",
        emptyFavoritesTitle: "Zatiaľ žiadne obľúbené",
        emptyFavoritesHint: "Vyhľadajte mesto vyššie a pridajte ho, aby ste naň mohli prepnúť jedným kliknutím.",
        addFavoriteHelp: "Pridať medzi obľúbené",
        removeFavoriteHelp: "Odstrániť",
        switchButton: "Prepnúť",
        switchingLabel: "Prepína sa…",
        currentBadge: "Aktuálne",
        switchFailedTitle: "Časové pásmo sa nepodarilo prepnúť",
        switchFailedMessage: "Zmena mohla byť zrušená alebo vyžaduje ďalšie oprávnenia.",
        adminSetupPrompt: "Vorssaint vytvorí obmedzené pravidlo (iba systemsetup -settimezone), aby ste mohli prepínať časové pásma bez zadávania hesla zakaždým. Heslo je potrebné iba teraz.",
        adminRemovePrompt: "Vorssaint odstráni pravidlo na prepínanie časového pásma, ktoré vytvoril.",
        commandBarToggle: "Zobraziť v príkazovej lište",
        commandBarCaption: "Pridá vaše obľúbené časové pásma do príkazovej lišty, aby ste mohli prepínať bez otvárania Nastavení."
    )

    static let de = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Zeitzonen-Umschalter",
        hubDescription: "Wechsle die Systemzeitzone des Mac mit einem Klick aus einer Liste von Favoriten",
        currentLabel: "Aktuelle Zeitzone",
        panelCaption: "Wechsle zwischen deinen bevorzugten Zeitzonen",
        automaticHint: "Wenn dein Mac die Zeitzone automatisch anhand des Standorts festlegt, kann eine hier vorgenommene Änderung überschrieben werden. Schalte das in den Systemeinstellungen › Allgemein › Datum & Uhrzeit aus.",
        searchPlaceholder: "Städte und Regionen suchen",
        favoritesHeader: "Favoriten",
        emptyFavoritesTitle: "Noch keine Favoriten",
        emptyFavoritesHint: "Suche oben nach einer Stadt und füge sie hinzu, um mit einem Klick zu wechseln.",
        addFavoriteHelp: "Zu Favoriten hinzufügen",
        removeFavoriteHelp: "Entfernen",
        switchButton: "Wechseln",
        switchingLabel: "Wird gewechselt…",
        currentBadge: "Aktuell",
        switchFailedTitle: "Zeitzone konnte nicht gewechselt werden",
        switchFailedMessage: "Die Änderung wurde möglicherweise abgebrochen oder benötigt zusätzliche Rechte.",
        adminSetupPrompt: "Vorssaint erstellt eine eingeschränkte Regel (nur systemsetup -settimezone), damit du Zeitzonen wechseln kannst, ohne jedes Mal dein Passwort einzugeben. Das Passwort wird nur dieses eine Mal benötigt.",
        adminRemovePrompt: "Vorssaint entfernt die von ihm erstellte Regel zum Zeitzonenwechsel.",
        commandBarToggle: "In der Befehlsleiste anzeigen",
        commandBarCaption: "Fügt deine bevorzugten Zeitzonen der Befehlsleiste hinzu, sodass du wechseln kannst, ohne die Einstellungen zu öffnen."
    )

    static let fr = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Changement de Fuseau Horaire",
        hubDescription: "Changez le fuseau horaire système du Mac en un clic, depuis une liste de favoris",
        currentLabel: "Fuseau Horaire Actuel",
        panelCaption: "Changez entre vos fuseaux horaires favoris",
        automaticHint: "Si votre Mac définit le fuseau horaire automatiquement selon la localisation, le changement effectué ici peut être annulé. Désactivez cela dans Réglages Système › Général › Date et heure.",
        searchPlaceholder: "Rechercher des villes et régions",
        favoritesHeader: "Favoris",
        emptyFavoritesTitle: "Aucun favori pour l’instant",
        emptyFavoritesHint: "Recherchez une ville ci-dessus et ajoutez-la pour basculer en un clic.",
        addFavoriteHelp: "Ajouter aux favoris",
        removeFavoriteHelp: "Retirer",
        switchButton: "Changer",
        switchingLabel: "Changement…",
        currentBadge: "Actuel",
        switchFailedTitle: "Impossible de changer le fuseau horaire",
        switchFailedMessage: "Le changement a peut-être été annulé ou nécessite des privilèges supplémentaires.",
        adminSetupPrompt: "Vorssaint va créer une règle restreinte (systemsetup -settimezone uniquement) pour que vous puissiez changer de fuseau horaire sans saisir votre mot de passe à chaque fois. C’est la seule fois où le mot de passe est nécessaire.",
        adminRemovePrompt: "Vorssaint va supprimer la règle de changement de fuseau horaire qu’il a créée.",
        commandBarToggle: "Afficher dans la Barre de Commandes",
        commandBarCaption: "Ajoute vos fuseaux horaires favoris à la Barre de Commandes, pour changer sans ouvrir les Réglages."
    )

    static let it = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Cambio Fuso Orario",
        hubDescription: "Cambia il fuso orario di sistema del Mac con un clic, da un elenco di preferiti",
        currentLabel: "Fuso Orario Attuale",
        panelCaption: "Passa tra i tuoi fusi orari preferiti",
        automaticHint: "Se il Mac imposta il fuso orario automaticamente in base alla posizione, la modifica qui potrebbe essere annullata. Disattivalo in Impostazioni di Sistema › Generali › Data e Ora.",
        searchPlaceholder: "Cerca città e regioni",
        favoritesHeader: "Preferiti",
        emptyFavoritesTitle: "Nessun preferito ancora",
        emptyFavoritesHint: "Cerca una città qui sopra e aggiungila per cambiare con un clic.",
        addFavoriteHelp: "Aggiungi ai preferiti",
        removeFavoriteHelp: "Rimuovi",
        switchButton: "Cambia",
        switchingLabel: "Cambio in corso…",
        currentBadge: "Attuale",
        switchFailedTitle: "Impossibile cambiare il fuso orario",
        switchFailedMessage: "La modifica potrebbe essere stata annullata o richiedere privilegi aggiuntivi.",
        adminSetupPrompt: "Vorssaint creerà una regola limitata (solo systemsetup -settimezone) per permetterti di cambiare fuso orario senza inserire la password ogni volta. La password serve solo questa volta.",
        adminRemovePrompt: "Vorssaint rimuoverà la regola per il cambio di fuso orario che ha creato.",
        commandBarToggle: "Mostra nella Barra dei Comandi",
        commandBarCaption: "Aggiunge i tuoi fusi orari preferiti alla Barra dei Comandi, per cambiare senza aprire le Impostazioni."
    )

    static let ja = TimeZoneSwitcherFeatureStrings(
        pageTitle: "タイムゾーン切り替え",
        hubDescription: "お気に入りのリストからワンクリックでMacのシステムタイムゾーンを切り替えます",
        currentLabel: "現在のタイムゾーン",
        panelCaption: "お気に入りのタイムゾーンを切り替えます",
        automaticHint: "Macが位置情報に基づいてタイムゾーンを自動設定している場合、ここでの変更が上書きされることがあります。システム設定 › 一般 › 日付と時刻でオフにしてください。",
        searchPlaceholder: "都市や地域を検索",
        favoritesHeader: "お気に入り",
        emptyFavoritesTitle: "お気に入りはまだありません",
        emptyFavoritesHint: "上で都市を検索して追加すると、ワンクリックで切り替えられます。",
        addFavoriteHelp: "お気に入りに追加",
        removeFavoriteHelp: "削除",
        switchButton: "切り替え",
        switchingLabel: "切り替え中…",
        currentBadge: "現在",
        switchFailedTitle: "タイムゾーンを切り替えられませんでした",
        switchFailedMessage: "変更がキャンセルされたか、追加の権限が必要な可能性があります。",
        adminSetupPrompt: "Vorssaintは、毎回パスワードを入力せずにタイムゾーンを切り替えられるよう、制限付きのルール（systemsetup -settimezoneのみ）を作成します。パスワードが必要なのはこの一度だけです。",
        adminRemovePrompt: "Vorssaintは作成したタイムゾーン切り替え用のルールを削除します。",
        commandBarToggle: "コマンドバーに表示",
        commandBarCaption: "お気に入りのタイムゾーンをコマンドバーに追加し、設定を開かずに切り替えられるようにします。"
    )

    static let ko = TimeZoneSwitcherFeatureStrings(
        pageTitle: "시간대 전환",
        hubDescription: "즐겨찾기 목록에서 한 번의 클릭으로 Mac의 시스템 시간대를 전환하세요",
        currentLabel: "현재 시간대",
        panelCaption: "즐겨찾는 시간대 간에 전환합니다",
        automaticHint: "Mac이 위치에 따라 시간대를 자동으로 설정하는 경우, 여기서의 변경이 되돌려질 수 있습니다. 시스템 설정 › 일반 › 날짜 및 시간에서 이를 꺼주세요.",
        searchPlaceholder: "도시 및 지역 검색",
        favoritesHeader: "즐겨찾기",
        emptyFavoritesTitle: "아직 즐겨찾기가 없습니다",
        emptyFavoritesHint: "위에서 도시를 검색하고 추가하면 한 번의 클릭으로 전환할 수 있습니다.",
        addFavoriteHelp: "즐겨찾기에 추가",
        removeFavoriteHelp: "제거",
        switchButton: "전환",
        switchingLabel: "전환 중…",
        currentBadge: "현재",
        switchFailedTitle: "시간대를 전환할 수 없습니다",
        switchFailedMessage: "변경이 취소되었거나 추가 권한이 필요할 수 있습니다.",
        adminSetupPrompt: "Vorssaint가 매번 비밀번호를 입력하지 않고도 시간대를 전환할 수 있도록 제한된 규칙(systemsetup -settimezone만 허용)을 만듭니다. 비밀번호는 지금 한 번만 필요합니다.",
        adminRemovePrompt: "Vorssaint가 생성한 시간대 전환 규칙을 제거합니다.",
        commandBarToggle: "명령 막대에 표시",
        commandBarCaption: "즐겨찾는 시간대를 명령 막대에 추가하여 설정을 열지 않고도 전환할 수 있습니다."
    )

    static let zhHans = TimeZoneSwitcherFeatureStrings(
        pageTitle: "时区切换",
        hubDescription: "从收藏列表一键切换 Mac 的系统时区",
        currentLabel: "当前时区",
        panelCaption: "在您收藏的时区之间切换",
        automaticHint: "如果你的 Mac 会根据位置自动设置时区，这里所做的更改可能会被覆盖。请在系统设置 › 通用 › 日期与时间中将其关闭。",
        searchPlaceholder: "搜索城市和地区",
        favoritesHeader: "收藏",
        emptyFavoritesTitle: "暂无收藏",
        emptyFavoritesHint: "在上方搜索城市并添加，即可一键切换。",
        addFavoriteHelp: "添加到收藏",
        removeFavoriteHelp: "移除",
        switchButton: "切换",
        switchingLabel: "正在切换…",
        currentBadge: "当前",
        switchFailedTitle: "无法切换时区",
        switchFailedMessage: "更改可能已被取消，或需要额外的权限。",
        adminSetupPrompt: "Vorssaint 将创建一条受限规则（仅限 systemsetup -settimezone），让您无需每次输入密码即可切换时区。密码只需在此输入一次。",
        adminRemovePrompt: "Vorssaint 将移除它创建的时区切换规则。",
        commandBarToggle: "在命令栏中显示",
        commandBarCaption: "将您收藏的时区加入命令栏，无需打开设置即可切换。"
    )

    static let zhTW = TimeZoneSwitcherFeatureStrings(
        pageTitle: "時區切換",
        hubDescription: "從收藏清單一鍵切換 Mac 的系統時區",
        currentLabel: "目前時區",
        panelCaption: "在你收藏的時區之間切換",
        automaticHint: "如果你的 Mac 會依據位置自動設定時區，這裡的變更可能會被覆寫。請在系統設定 › 一般 › 日期與時間中將其關閉。",
        searchPlaceholder: "搜尋城市與地區",
        favoritesHeader: "收藏",
        emptyFavoritesTitle: "尚無收藏",
        emptyFavoritesHint: "在上方搜尋城市並加入，即可一鍵切換。",
        addFavoriteHelp: "加入收藏",
        removeFavoriteHelp: "移除",
        switchButton: "切換",
        switchingLabel: "切換中…",
        currentBadge: "目前",
        switchFailedTitle: "無法切換時區",
        switchFailedMessage: "變更可能已被取消，或需要額外的權限。",
        adminSetupPrompt: "Vorssaint 將建立一條受限規則（僅限 systemsetup -settimezone），讓你不必每次輸入密碼即可切換時區。密碼只需要在此輸入一次。",
        adminRemovePrompt: "Vorssaint 將移除它建立的時區切換規則。",
        commandBarToggle: "在指令列中顯示",
        commandBarCaption: "將你收藏的時區加入指令列，不必開啟設定即可切換。"
    )

    static let zhHK = TimeZoneSwitcherFeatureStrings(
        pageTitle: "時區切換",
        hubDescription: "從收藏清單一鍵切換 Mac 的系統時區",
        currentLabel: "目前時區",
        panelCaption: "在你收藏的時區之間切換",
        automaticHint: "如果你的 Mac 會依據位置自動設定時區，這裡的變更可能會被覆寫。請在系統設定 › 一般 › 日期與時間中將其關閉。",
        searchPlaceholder: "搜尋城市與地區",
        favoritesHeader: "收藏",
        emptyFavoritesTitle: "尚無收藏",
        emptyFavoritesHint: "在上方搜尋城市並加入，即可一鍵切換。",
        addFavoriteHelp: "加入收藏",
        removeFavoriteHelp: "移除",
        switchButton: "切換",
        switchingLabel: "切換中…",
        currentBadge: "目前",
        switchFailedTitle: "無法切換時區",
        switchFailedMessage: "變更可能已被取消，或需要額外的權限。",
        adminSetupPrompt: "Vorssaint 將建立一條受限規則（僅限 systemsetup -settimezone），讓你不必每次輸入密碼即可切換時區。密碼只需要在此輸入一次。",
        adminRemovePrompt: "Vorssaint 將移除它建立的時區切換規則。",
        commandBarToggle: "在指令列中顯示",
        commandBarCaption: "將你收藏的時區加入指令列，不必開啟設定即可切換。"
    )

    static let uk = TimeZoneSwitcherFeatureStrings(
        pageTitle: "Перемикання часового поясу",
        hubDescription: "Перемикайте системний часовий пояс Mac в один клік зі списку обраного",
        currentLabel: "Поточний часовий пояс",
        panelCaption: "Перемикайтеся між обраними часовими поясами",
        automaticHint: "Якщо Mac встановлює часовий пояс автоматично за місцезнаходженням, зміна тут може бути скасована. Вимкніть це в Налаштуваннях системи › Основні › Дата і час.",
        searchPlaceholder: "Пошук міст і регіонів",
        favoritesHeader: "Обране",
        emptyFavoritesTitle: "Поки що немає обраного",
        emptyFavoritesHint: "Знайдіть місто вище та додайте його, щоб перемикатися одним кліком.",
        addFavoriteHelp: "Додати до обраного",
        removeFavoriteHelp: "Вилучити",
        switchButton: "Перемкнути",
        switchingLabel: "Перемикання…",
        currentBadge: "Поточний",
        switchFailedTitle: "Не вдалося перемкнути часовий пояс",
        switchFailedMessage: "Зміну могло бути скасовано, або вона потребує додаткових прав.",
        adminSetupPrompt: "Vorssaint створить обмежене правило (лише systemsetup -settimezone), щоб ви могли перемикати часові пояси без введення пароля щоразу. Пароль потрібен лише зараз.",
        adminRemovePrompt: "Vorssaint вилучить створене ним правило перемикання часового поясу.",
        commandBarToggle: "Показувати в Панелі команд",
        commandBarCaption: "Додає ваші обрані часові пояси в Панель команд, щоб перемикатися без відкриття Налаштувань."
    )
}
