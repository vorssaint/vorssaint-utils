// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchEditorStrings {
    let layout: String
    let content: String
    let activity: String
    let behavior: String
    let layoutHint: String
    let addButton: String
    let editButton: String
    let removeButton: String
    let buttonName: String
    let position: String
    let bottom: String
    let sectionActions: String
    let quickActions: String
    let findAction: String
    let reorderHint: String
    let opening: String
    let clickOpen: String
    let hoverPreview: String
    let hoverExpand: String
    let resting: String
    let destinations: String
    let separate: String
    let feedback: String
    let privacy: String
}

extension FeatureStrings {
    static func notchEditor(_ language: AppLanguage) -> NotchEditorStrings {
        switch language {
        case .enUS: return NotchEditorStrings(
            layout: "Layout",
            content: "Content",
            activity: "Activity",
            behavior: "Behavior",
            layoutHint: "Click + to add a button. Drag buttons around the island. Click a button to edit it.",
            addButton: "Add button",
            editButton: "Edit button",
            removeButton: "Remove button",
            buttonName: "Name",
            position: "Position",
            bottom: "Bottom",
            sectionActions: "Open a section",
            quickActions: "Quick actions",
            findAction: "Find an action",
            reorderHint: "Drag to reorder. Click the checkmark to show or hide.",
            opening: "Opening",
            clickOpen: "Click to open",
            hoverPreview: "Preview on hover",
            hoverExpand: "Expand on hover",
            resting: "At rest",
            destinations: "Where things open",
            separate: "Separate window",
            feedback: "Indicators",
            privacy: "Privacy"
        )
        case .ptBR: return NotchEditorStrings(
            layout: "Layout",
            content: "Conteúdo",
            activity: "Atividade",
            behavior: "Comportamento",
            layoutHint: "Clique em + para adicionar. Arraste as bolinhas ao redor da ilha. Clique em uma para editar.",
            addButton: "Adicionar bolinha",
            editButton: "Editar bolinha",
            removeButton: "Remover bolinha",
            buttonName: "Nome",
            position: "Posição",
            bottom: "Embaixo",
            sectionActions: "Abrir uma seção",
            quickActions: "Ações rápidas",
            findAction: "Encontrar uma ação",
            reorderHint: "Arraste para reordenar. Clique na marca para mostrar ou ocultar.",
            opening: "Abertura",
            clickOpen: "Abrir por clique",
            hoverPreview: "Prévia ao aproximar",
            hoverExpand: "Expandir ao aproximar",
            resting: "Em repouso",
            destinations: "Onde abrir",
            separate: "Janela separada",
            feedback: "Indicadores",
            privacy: "Privacidade"
        )
        case .es: return NotchEditorStrings(
            layout: "Diseño",
            content: "Contenido",
            activity: "Actividad",
            behavior: "Comportamiento",
            layoutHint: "Pulsa + para añadir un botón. Arrastra los botones alrededor de la isla. Pulsa uno para editarlo.",
            addButton: "Añadir botón",
            editButton: "Editar botón",
            removeButton: "Eliminar botón",
            buttonName: "Nombre",
            position: "Posición",
            bottom: "Abajo",
            sectionActions: "Abrir una sección",
            quickActions: "Acciones rápidas",
            findAction: "Buscar una acción",
            reorderHint: "Arrastra para ordenar. Pulsa la marca para mostrar u ocultar.",
            opening: "Apertura",
            clickOpen: "Abrir con un clic",
            hoverPreview: "Vista previa al acercarse",
            hoverExpand: "Expandir al acercarse",
            resting: "En reposo",
            destinations: "Dónde abrir",
            separate: "Ventana separada",
            feedback: "Indicadores",
            privacy: "Privacidad"
        )
        case .de: return NotchEditorStrings(
            layout: "Layout",
            content: "Inhalt",
            activity: "Aktivität",
            behavior: "Verhalten",
            layoutHint: "Mit + eine Taste hinzufügen. Tasten um die Insel ziehen. Zum Bearbeiten eine Taste anklicken.",
            addButton: "Taste hinzufügen",
            editButton: "Taste bearbeiten",
            removeButton: "Taste entfernen",
            buttonName: "Name",
            position: "Position",
            bottom: "Unten",
            sectionActions: "Bereich öffnen",
            quickActions: "Schnellaktionen",
            findAction: "Aktion finden",
            reorderHint: "Zum Sortieren ziehen. Mit dem Häkchen ein- oder ausblenden.",
            opening: "Öffnen",
            clickOpen: "Per Klick öffnen",
            hoverPreview: "Vorschau bei Annäherung",
            hoverExpand: "Bei Annäherung erweitern",
            resting: "Im Ruhezustand",
            destinations: "Öffnungsort",
            separate: "Eigenes Fenster",
            feedback: "Anzeigen",
            privacy: "Datenschutz"
        )
        case .fr: return NotchEditorStrings(
            layout: "Disposition",
            content: "Contenu",
            activity: "Activité",
            behavior: "Comportement",
            layoutHint: "Cliquez sur + pour ajouter un bouton. Faites glisser les boutons autour de l’îlot. Cliquez pour modifier.",
            addButton: "Ajouter un bouton",
            editButton: "Modifier le bouton",
            removeButton: "Retirer le bouton",
            buttonName: "Nom",
            position: "Position",
            bottom: "En bas",
            sectionActions: "Ouvrir une section",
            quickActions: "Actions rapides",
            findAction: "Rechercher une action",
            reorderHint: "Glissez pour réordonner. Cliquez sur la coche pour afficher ou masquer.",
            opening: "Ouverture",
            clickOpen: "Ouvrir au clic",
            hoverPreview: "Aperçu au survol",
            hoverExpand: "Déployer au survol",
            resting: "Au repos",
            destinations: "Lieu d’ouverture",
            separate: "Fenêtre séparée",
            feedback: "Indicateurs",
            privacy: "Confidentialité"
        )
        case .it: return NotchEditorStrings(
            layout: "Layout",
            content: "Contenuto",
            activity: "Attività",
            behavior: "Comportamento",
            layoutHint: "Fai clic su + per aggiungere un pulsante. Trascina i pulsanti intorno all’isola. Fai clic per modificarli.",
            addButton: "Aggiungi pulsante",
            editButton: "Modifica pulsante",
            removeButton: "Rimuovi pulsante",
            buttonName: "Nome",
            position: "Posizione",
            bottom: "In basso",
            sectionActions: "Apri una sezione",
            quickActions: "Azioni rapide",
            findAction: "Trova un’azione",
            reorderHint: "Trascina per riordinare. Fai clic sulla spunta per mostrare o nascondere.",
            opening: "Apertura",
            clickOpen: "Apri con un clic",
            hoverPreview: "Anteprima al passaggio",
            hoverExpand: "Espandi al passaggio",
            resting: "A riposo",
            destinations: "Dove aprire",
            separate: "Finestra separata",
            feedback: "Indicatori",
            privacy: "Privacy"
        )
        case .ru: return NotchEditorStrings(
            layout: "Макет",
            content: "Содержимое",
            activity: "Активность",
            behavior: "Поведение",
            layoutHint: "Нажмите +, чтобы добавить кнопку. Перетаскивайте кнопки вокруг острова. Нажмите для изменения.",
            addButton: "Добавить кнопку",
            editButton: "Изменить кнопку",
            removeButton: "Удалить кнопку",
            buttonName: "Название",
            position: "Расположение",
            bottom: "Снизу",
            sectionActions: "Открыть раздел",
            quickActions: "Быстрые действия",
            findAction: "Найти действие",
            reorderHint: "Перетащите для сортировки. Нажмите галочку, чтобы показать или скрыть.",
            opening: "Открытие",
            clickOpen: "По щелчку",
            hoverPreview: "Просмотр при наведении",
            hoverExpand: "Развернуть при наведении",
            resting: "В покое",
            destinations: "Где открывать",
            separate: "Отдельное окно",
            feedback: "Индикаторы",
            privacy: "Конфиденциальность"
        )
        case .tr: return NotchEditorStrings(
            layout: "Yerleşim",
            content: "İçerik",
            activity: "Etkinlik",
            behavior: "Davranış",
            layoutHint: "Düğme eklemek için + işaretine tıklayın. Düğmeleri adanın çevresine sürükleyin. Düzenlemek için tıklayın.",
            addButton: "Düğme ekle",
            editButton: "Düğmeyi düzenle",
            removeButton: "Düğmeyi kaldır",
            buttonName: "Ad",
            position: "Konum",
            bottom: "Alt",
            sectionActions: "Bölüm aç",
            quickActions: "Hızlı eylemler",
            findAction: "Eylem bul",
            reorderHint: "Sıralamak için sürükleyin. Göstermek veya gizlemek için onay işaretine tıklayın.",
            opening: "Açılış",
            clickOpen: "Tıklayarak aç",
            hoverPreview: "Üzerine gelince önizle",
            hoverExpand: "Üzerine gelince genişlet",
            resting: "Beklerken",
            destinations: "Açılacak yer",
            separate: "Ayrı pencere",
            feedback: "Göstergeler",
            privacy: "Gizlilik"
        )
        case .ja: return NotchEditorStrings(
            layout: "レイアウト",
            content: "コンテンツ",
            activity: "アクティビティ",
            behavior: "動作",
            layoutHint: "＋でボタンを追加します。島の周りにドラッグして移動し、クリックして編集します。",
            addButton: "ボタンを追加",
            editButton: "ボタンを編集",
            removeButton: "ボタンを削除",
            buttonName: "名前",
            position: "位置",
            bottom: "下",
            sectionActions: "セクションを開く",
            quickActions: "クイックアクション",
            findAction: "アクションを検索",
            reorderHint: "ドラッグして並べ替え、チェックマークで表示を切り替えます。",
            opening: "開き方",
            clickOpen: "クリックで開く",
            hoverPreview: "ポイントでプレビュー",
            hoverExpand: "ポイントで展開",
            resting: "待機中",
            destinations: "開く場所",
            separate: "別のウインドウ",
            feedback: "インジケータ",
            privacy: "プライバシー"
        )
        case .ko: return NotchEditorStrings(
            layout: "레이아웃",
            content: "콘텐츠",
            activity: "활동",
            behavior: "동작",
            layoutHint: "+를 눌러 버튼을 추가하세요. 섬 주변으로 드래그하여 옮기고 클릭하여 편집하세요.",
            addButton: "버튼 추가",
            editButton: "버튼 편집",
            removeButton: "버튼 제거",
            buttonName: "이름",
            position: "위치",
            bottom: "아래",
            sectionActions: "섹션 열기",
            quickActions: "빠른 동작",
            findAction: "동작 찾기",
            reorderHint: "드래그하여 순서를 바꾸고 체크 표시로 표시 여부를 바꾸세요.",
            opening: "열기",
            clickOpen: "클릭하여 열기",
            hoverPreview: "포인터로 미리보기",
            hoverExpand: "포인터로 펼치기",
            resting: "대기 중",
            destinations: "열리는 위치",
            separate: "별도 윈도우",
            feedback: "표시기",
            privacy: "개인정보 보호"
        )
        case .zhHans: return NotchEditorStrings(
            layout: "布局",
            content: "内容",
            activity: "活动",
            behavior: "行为",
            layoutHint: "点击 + 添加按钮。将按钮拖到岛的周围，点击按钮进行编辑。",
            addButton: "添加按钮",
            editButton: "编辑按钮",
            removeButton: "移除按钮",
            buttonName: "名称",
            position: "位置",
            bottom: "底部",
            sectionActions: "打开分区",
            quickActions: "快捷操作",
            findAction: "查找操作",
            reorderHint: "拖动以排序。点击勾选标记来显示或隐藏。",
            opening: "打开方式",
            clickOpen: "点击打开",
            hoverPreview: "悬停时预览",
            hoverExpand: "悬停时展开",
            resting: "空闲时",
            destinations: "打开位置",
            separate: "单独窗口",
            feedback: "提示",
            privacy: "隐私"
        )
        case .zhTW: return NotchEditorStrings(
            layout: "佈局",
            content: "內容",
            activity: "活動",
            behavior: "行為",
            layoutHint: "按一下 + 新增按鈕。將按鈕拖到島的周圍，按一下按鈕即可編輯。",
            addButton: "新增按鈕",
            editButton: "編輯按鈕",
            removeButton: "移除按鈕",
            buttonName: "名稱",
            position: "位置",
            bottom: "下方",
            sectionActions: "開啟區域",
            quickActions: "快速操作",
            findAction: "尋找操作",
            reorderHint: "拖移以排序。按一下勾選標記來顯示或隱藏。",
            opening: "開啟方式",
            clickOpen: "按一下開啟",
            hoverPreview: "停留時預覽",
            hoverExpand: "停留時展開",
            resting: "閒置時",
            destinations: "開啟位置",
            separate: "獨立視窗",
            feedback: "提示",
            privacy: "隱私"
        )
        case .zhHK: return NotchEditorStrings(
            layout: "佈局",
            content: "內容",
            activity: "活動",
            behavior: "行為",
            layoutHint: "按一下 + 新增按鈕。將按鈕拖到島的周圍，按一下按鈕即可編輯。",
            addButton: "新增按鈕",
            editButton: "編輯按鈕",
            removeButton: "移除按鈕",
            buttonName: "名稱",
            position: "位置",
            bottom: "下方",
            sectionActions: "開啟區域",
            quickActions: "快速操作",
            findAction: "尋找操作",
            reorderHint: "拖移以排序。按一下勾選標記來顯示或隱藏。",
            opening: "開啟方式",
            clickOpen: "按一下開啟",
            hoverPreview: "停留時預覽",
            hoverExpand: "停留時展開",
            resting: "閒置時",
            destinations: "開啟位置",
            separate: "獨立視窗",
            feedback: "提示",
            privacy: "私隱"
        )
        }
    }
}
