// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowCustomZoneStrings {
    let section: String
    let enabled: String
    let instructions: String
    let preset: String
    let twoColumns: String
    let threeColumns: String
    let fourColumns: String
    let fourTiles: String
    let sixTiles: String
    let tile: String
    let addTile: String
    let remove: String
    let left: String
    let top: String
    let width: String
    let height: String
    let editTile: String
    let tilePreview: String

    static func localized(_ language: AppLanguage) -> Self {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension WindowCustomZoneStrings {
    static let enUS = Self(
        section: "Custom tiles by display", enabled: "Show tile zones while holding Option (⌥)",
        instructions: "Hold Option to show the zones, drag a window into a tile and release. Each display has its own layout.",
        preset: "Preset", twoColumns: "Two columns", threeColumns: "Three columns",
        fourColumns: "Four columns", fourTiles: "Four tiles (2 × 2)", sixTiles: "Six tiles (3 × 2)",
        tile: "Tile", addTile: "Add tile", remove: "Remove",
        left: "Left", top: "Top", width: "Width", height: "Height",
        editTile: "Edit tile %d", tilePreview: "Tile preview for %@")
    static let ptBR = Self(
        section: "Áreas personalizadas por tela", enabled: "Mostrar áreas ao segurar Option (⌥)",
        instructions: "Segure Option para ver as áreas, arraste uma janela para uma delas e solte. Cada tela tem seu próprio layout.",
        preset: "Predefinição", twoColumns: "Duas colunas", threeColumns: "Três colunas",
        fourColumns: "Quatro colunas", fourTiles: "Quatro áreas (2 × 2)", sixTiles: "Seis áreas (3 × 2)",
        tile: "Área", addTile: "Adicionar área", remove: "Remover",
        left: "Esquerda", top: "Topo", width: "Largura", height: "Altura",
        editTile: "Editar área %d", tilePreview: "Prévia das áreas de %@")
    static let tr = Self(
        section: "Ekrana göre özel bölgeler", enabled: "Option (⌥) basılıyken bölgeleri göster",
        instructions: "Bölgeleri görmek için Option tuşunu basılı tutun, pencereyi bir bölgeye sürükleyip bırakın. Her ekranın ayrı düzeni vardır.",
        preset: "Hazır düzen", twoColumns: "İki sütun", threeColumns: "Üç sütun",
        fourColumns: "Dört sütun", fourTiles: "Dört bölge (2 × 2)", sixTiles: "Altı bölge (3 × 2)",
        tile: "Bölge", addTile: "Bölge ekle", remove: "Kaldır",
        left: "Sol", top: "Üst", width: "Genişlik", height: "Yükseklik",
        editTile: "%d. bölgeyi düzenle", tilePreview: "%@ için bölge önizlemesi")
    static let ru = Self(
        section: "Свои области для каждого экрана", enabled: "Показывать области при удержании Option (⌥)",
        instructions: "Удерживайте Option, чтобы увидеть области, затем перетащите окно в нужную область и отпустите. У каждого экрана своя раскладка.",
        preset: "Шаблон", twoColumns: "Два столбца", threeColumns: "Три столбца",
        fourColumns: "Четыре столбца", fourTiles: "Четыре области (2 × 2)", sixTiles: "Шесть областей (3 × 2)",
        tile: "Область", addTile: "Добавить область", remove: "Удалить",
        left: "Слева", top: "Сверху", width: "Ширина", height: "Высота",
        editTile: "Изменить область %d", tilePreview: "Области экрана %@")
    static let es = Self(
        section: "Zonas personalizadas por pantalla", enabled: "Mostrar zonas al mantener Option (⌥)",
        instructions: "Mantén Option para ver las zonas, arrastra una ventana a una zona y suéltala. Cada pantalla tiene su propia distribución.",
        preset: "Preajuste", twoColumns: "Dos columnas", threeColumns: "Tres columnas",
        fourColumns: "Cuatro columnas", fourTiles: "Cuatro zonas (2 × 2)", sixTiles: "Seis zonas (3 × 2)",
        tile: "Zona", addTile: "Añadir zona", remove: "Eliminar",
        left: "Izquierda", top: "Arriba", width: "Anchura", height: "Altura",
        editTile: "Editar zona %d", tilePreview: "Vista previa de zonas de %@")
    static let sk = Self(
        section: "Vlastné zóny podľa obrazovky", enabled: "Zobraziť zóny pri podržaní Option (⌥)",
        instructions: "Podržte Option, zobrazte zóny, presuňte okno do zóny a pustite ho. Každá obrazovka má vlastné rozloženie.",
        preset: "Predvoľba", twoColumns: "Dva stĺpce", threeColumns: "Tri stĺpce",
        fourColumns: "Štyri stĺpce", fourTiles: "Štyri zóny (2 × 2)", sixTiles: "Šesť zón (3 × 2)",
        tile: "Zóna", addTile: "Pridať zónu", remove: "Odstrániť",
        left: "Zľava", top: "Zhora", width: "Šírka", height: "Výška",
        editTile: "Upraviť zónu %d", tilePreview: "Náhľad zón pre %@")
    static let de = Self(
        section: "Eigene Kacheln pro Bildschirm", enabled: "Kachelzonen bei gedrückter Option-Taste (⌥) anzeigen",
        instructions: "Option gedrückt halten, um Zonen anzuzeigen. Ein Fenster in eine Zone ziehen und loslassen. Jeder Bildschirm hat sein eigenes Layout.",
        preset: "Vorlage", twoColumns: "Zwei Spalten", threeColumns: "Drei Spalten",
        fourColumns: "Vier Spalten", fourTiles: "Vier Kacheln (2 × 2)", sixTiles: "Sechs Kacheln (3 × 2)",
        tile: "Kachel", addTile: "Kachel hinzufügen", remove: "Entfernen",
        left: "Links", top: "Oben", width: "Breite", height: "Höhe",
        editTile: "Kachel %d bearbeiten", tilePreview: "Kachelvorschau für %@")
    static let fr = Self(
        section: "Zones personnalisées par écran", enabled: "Afficher les zones en maintenant Option (⌥)",
        instructions: "Maintenez Option pour afficher les zones, glissez une fenêtre dans une zone et relâchez. Chaque écran possède sa propre disposition.",
        preset: "Préréglage", twoColumns: "Deux colonnes", threeColumns: "Trois colonnes",
        fourColumns: "Quatre colonnes", fourTiles: "Quatre zones (2 × 2)", sixTiles: "Six zones (3 × 2)",
        tile: "Zone", addTile: "Ajouter une zone", remove: "Supprimer",
        left: "Gauche", top: "Haut", width: "Largeur", height: "Hauteur",
        editTile: "Modifier la zone %d", tilePreview: "Aperçu des zones pour %@")
    static let it = Self(
        section: "Zone personalizzate per schermo", enabled: "Mostra le zone tenendo premuto Opzione (⌥)",
        instructions: "Tieni premuto Opzione per mostrare le zone, trascina una finestra in una zona e rilasciala. Ogni schermo ha la propria disposizione.",
        preset: "Predefinito", twoColumns: "Due colonne", threeColumns: "Tre colonne",
        fourColumns: "Quattro colonne", fourTiles: "Quattro zone (2 × 2)", sixTiles: "Sei zone (3 × 2)",
        tile: "Zona", addTile: "Aggiungi zona", remove: "Rimuovi",
        left: "Sinistra", top: "Alto", width: "Larghezza", height: "Altezza",
        editTile: "Modifica zona %d", tilePreview: "Anteprima zone per %@")
    static let ja = Self(
        section: "ディスプレイ別のカスタム領域", enabled: "Option (⌥) キーを押している間、領域を表示",
        instructions: "Option キーを押して領域を表示し、ウインドウを領域へドラッグして離します。ディスプレイごとに別の配置を設定できます。",
        preset: "プリセット", twoColumns: "2 列", threeColumns: "3 列",
        fourColumns: "4 列", fourTiles: "4 領域 (2 × 2)", sixTiles: "6 領域 (3 × 2)",
        tile: "領域", addTile: "領域を追加", remove: "削除",
        left: "左", top: "上", width: "幅", height: "高さ",
        editTile: "領域 %d を編集", tilePreview: "%@ の領域プレビュー")
    static let ko = Self(
        section: "디스플레이별 사용자 지정 영역", enabled: "Option(⌥) 키를 누르는 동안 영역 표시",
        instructions: "Option 키를 눌러 영역을 표시하고 창을 원하는 영역으로 드래그한 뒤 놓으세요. 디스플레이마다 별도 레이아웃을 설정할 수 있습니다.",
        preset: "사전 설정", twoColumns: "2열", threeColumns: "3열",
        fourColumns: "4열", fourTiles: "4개 영역(2 × 2)", sixTiles: "6개 영역(3 × 2)",
        tile: "영역", addTile: "영역 추가", remove: "제거",
        left: "왼쪽", top: "위쪽", width: "너비", height: "높이",
        editTile: "영역 %d 편집", tilePreview: "%@ 영역 미리보기")
    static let uk = Self(
        section: "Власні зони для кожного екрана", enabled: "Показувати зони під час утримання Option (⌥)",
        instructions: "Утримуйте Option, щоб побачити зони, перетягніть вікно в потрібну зону й відпустіть. Кожен екран має власне компонування.",
        preset: "Шаблон", twoColumns: "Два стовпці", threeColumns: "Три стовпці",
        fourColumns: "Чотири стовпці", fourTiles: "Чотири зони (2 × 2)", sixTiles: "Шість зон (3 × 2)",
        tile: "Зона", addTile: "Додати зону", remove: "Вилучити",
        left: "Ліворуч", top: "Згори", width: "Ширина", height: "Висота",
        editTile: "Змінити зону %d", tilePreview: "Перегляд зон екрана %@")
    static let zhHans = Self(
        section: "按显示器自定义平铺区域", enabled: "按住 Option (⌥) 时显示平铺区域",
        instructions: "按住 Option 显示区域，将窗口拖入区域后松开。每台显示器都可使用独立布局。",
        preset: "预设", twoColumns: "两列", threeColumns: "三列",
        fourColumns: "四列", fourTiles: "四个区域 (2 × 2)", sixTiles: "六个区域 (3 × 2)",
        tile: "区域", addTile: "添加区域", remove: "移除",
        left: "左", top: "上", width: "宽度", height: "高度",
        editTile: "编辑区域 %d", tilePreview: "%@ 的区域预览")
    static let zhTW = Self(
        section: "依顯示器自訂平鋪區域", enabled: "按住 Option (⌥) 時顯示平鋪區域",
        instructions: "按住 Option 顯示區域，將視窗拖曳至區域後放開。每部顯示器均可使用獨立配置。",
        preset: "預設", twoColumns: "兩欄", threeColumns: "三欄",
        fourColumns: "四欄", fourTiles: "四個區域 (2 × 2)", sixTiles: "六個區域 (3 × 2)",
        tile: "區域", addTile: "新增區域", remove: "移除",
        left: "左", top: "上", width: "寬度", height: "高度",
        editTile: "編輯區域 %d", tilePreview: "%@ 的區域預覽")
    static let zhHK = Self(
        section: "按顯示器自訂平鋪區域", enabled: "按住 Option (⌥) 時顯示平鋪區域",
        instructions: "按住 Option 顯示區域，將視窗拖入區域後放開。每個顯示器均有獨立佈局。",
        preset: "預設", twoColumns: "兩欄", threeColumns: "三欄",
        fourColumns: "四欄", fourTiles: "四個區域 (2 × 2)", sixTiles: "六個區域 (3 × 2)",
        tile: "區域", addTile: "加入區域", remove: "移除",
        left: "左", top: "上", width: "闊度", height: "高度",
        editTile: "編輯區域 %d", tilePreview: "%@ 的區域預覽")
}
