// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the text snippets feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct SnippetFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let addButton: String
    let newTitle: String
    let editTitle: String
    let nameLabel: String
    let namePlaceholder: String
    let triggerLabel: String
    let triggerPlaceholder: String
    let replacementLabel: String
    let replacementPlaceholder: String
    let expansionLabel: String
    let expansionImmediate: String
    let expansionDelimiter: String
    let variablesHint: String
    let variablesCaption: String
    let emptyList: String
    let duplicateTrigger: String
    let triggerTooShort: String
    let deleteButton: String
    let saveButton: String
    let manageButton: String
}

extension FeatureStrings {
    static func snippets(_ language: AppLanguage) -> SnippetFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension SnippetFeatureStrings {
    static let ko = SnippetFeatureStrings(
        pageTitle: "텍스트 스니펫",
        hubDescription: "짧은 트리거를 전체 텍스트로 확장합니다",
        enable: "입력 중 스니펫 확장",
        enableCaption: "어디에서나 트리거를 입력하면 해당 텍스트로 바뀝니다. 모든 내용은 이 Mac에만 남습니다.",
        addButton: "스니펫 추가",
        newTitle: "새 스니펫",
        editTitle: "스니펫 편집",
        nameLabel: "이름",
        namePlaceholder: "개인 이메일",
        triggerLabel: "트리거",
        triggerPlaceholder: ";email",
        replacementLabel: "텍스트",
        replacementPlaceholder: "myemail@example.com",
        expansionLabel: "확장",
        expansionImmediate: "즉시",
        expansionDelimiter: "Space, Tab 또는 Return 뒤에",
        variablesHint: "변수: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "확장 시점에 날짜, 시간 및 복사한 텍스트로 바뀝니다.",
        emptyList: "아직 스니펫이 없습니다. 첫 번째 스니펫을 추가하세요.",
        duplicateTrigger: "다른 스니펫이 이미 이 트리거를 사용하고 있습니다.",
        triggerTooShort: "트리거는 2자 이상이어야 합니다.",
        deleteButton: "삭제",
        saveButton: "저장",
        manageButton: "스니펫 관리"
    )
}

extension SnippetFeatureStrings {
    static let enUS = SnippetFeatureStrings(
        pageTitle: "Text snippets",
        hubDescription: "Short triggers expand into full text",
        enable: "Expand snippets while typing",
        enableCaption: "Type a trigger anywhere and it becomes its text. Everything stays on this Mac.",
        addButton: "Add snippet",
        newTitle: "New snippet",
        editTitle: "Edit snippet",
        nameLabel: "Name",
        namePlaceholder: "Personal email",
        triggerLabel: "Trigger",
        triggerPlaceholder: ";email",
        replacementLabel: "Text",
        replacementPlaceholder: "myemail@example.com",
        expansionLabel: "Expand",
        expansionImmediate: "Right away",
        expansionDelimiter: "After space, Tab or Return",
        variablesHint: "Variables: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "They become the date, the time and the copied text at the moment of expansion.",
        emptyList: "No snippets yet. Add the first one.",
        duplicateTrigger: "Another snippet already uses this trigger.",
        triggerTooShort: "The trigger needs at least 2 characters.",
        deleteButton: "Delete",
        saveButton: "Save",
        manageButton: "Manage snippets"
    )

    static let ptBR = SnippetFeatureStrings(
        pageTitle: "Snippets de texto",
        hubDescription: "Gatilhos curtos viram textos completos",
        enable: "Expandir snippets enquanto digita",
        enableCaption: "Digite um gatilho em qualquer lugar e ele vira o texto dele. Tudo fica neste Mac.",
        addButton: "Adicionar snippet",
        newTitle: "Novo snippet",
        editTitle: "Editar snippet",
        nameLabel: "Nome",
        namePlaceholder: "Email pessoal",
        triggerLabel: "Gatilho",
        triggerPlaceholder: ";email",
        replacementLabel: "Texto",
        replacementPlaceholder: "meuemail@exemplo.com",
        expansionLabel: "Expandir",
        expansionImmediate: "Na hora",
        expansionDelimiter: "Após espaço, Tab ou Enter",
        variablesHint: "Variáveis: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "Elas viram a data, a hora e o texto copiado no momento da expansão.",
        emptyList: "Nenhum snippet ainda. Adicione o primeiro.",
        duplicateTrigger: "Outro snippet já usa esse gatilho.",
        triggerTooShort: "O gatilho precisa de pelo menos 2 caracteres.",
        deleteButton: "Apagar",
        saveButton: "Salvar",
        manageButton: "Gerenciar snippets"
    )

    static let tr = SnippetFeatureStrings(
        pageTitle: "Metin parçacıkları",
        hubDescription: "Kısa tetikleyiciler tam metne dönüşür",
        enable: "Yazarken parçacıkları genişlet",
        enableCaption: "Herhangi bir yerde bir tetikleyici yazın, metnine dönüşsün. Her şey bu Mac'te kalır.",
        addButton: "Parçacık ekle",
        newTitle: "Yeni parçacık",
        editTitle: "Parçacığı düzenle",
        nameLabel: "Ad",
        namePlaceholder: "Kişisel e-posta",
        triggerLabel: "Tetikleyici",
        triggerPlaceholder: ";eposta",
        replacementLabel: "Metin",
        replacementPlaceholder: "epostam@ornek.com",
        expansionLabel: "Genişletme",
        expansionImmediate: "Hemen",
        expansionDelimiter: "Boşluk, Tab veya Enter'dan sonra",
        variablesHint: "Değişkenler: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "Genişletme anında tarihe, saate ve kopyalanan metne dönüşürler.",
        emptyList: "Henüz parçacık yok. İlkini ekleyin.",
        duplicateTrigger: "Bu tetikleyiciyi başka bir parçacık kullanıyor.",
        triggerTooShort: "Tetikleyici en az 2 karakter olmalı.",
        deleteButton: "Sil",
        saveButton: "Kaydet",
        manageButton: "Parçacıkları yönet"
    )

    static let ru = SnippetFeatureStrings(
        pageTitle: "Текстовые сниппеты",
        hubDescription: "Короткие триггеры превращаются в готовый текст",
        enable: "Разворачивать сниппеты при вводе",
        enableCaption: "Наберите триггер где угодно, и он станет своим текстом. Всё остаётся на этом Mac.",
        addButton: "Добавить сниппет",
        newTitle: "Новый сниппет",
        editTitle: "Изменить сниппет",
        nameLabel: "Название",
        namePlaceholder: "Личная почта",
        triggerLabel: "Триггер",
        triggerPlaceholder: ";почта",
        replacementLabel: "Текст",
        replacementPlaceholder: "moyapochta@primer.ru",
        expansionLabel: "Разворачивать",
        expansionImmediate: "Сразу",
        expansionDelimiter: "После пробела, Tab или Enter",
        variablesHint: "Переменные: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "В момент развёртывания они становятся датой, временем и скопированным текстом.",
        emptyList: "Сниппетов пока нет. Добавьте первый.",
        duplicateTrigger: "Этот триггер уже занят другим сниппетом.",
        triggerTooShort: "Триггеру нужно не меньше 2 символов.",
        deleteButton: "Удалить",
        saveButton: "Сохранить",
        manageButton: "Управление сниппетами"
    )

    static let es = SnippetFeatureStrings(
        pageTitle: "Fragmentos de texto",
        hubDescription: "Disparadores cortos se convierten en texto completo",
        enable: "Expandir fragmentos al escribir",
        enableCaption: "Escribe un disparador en cualquier lugar y se convierte en su texto. Todo queda en este Mac.",
        addButton: "Añadir fragmento",
        newTitle: "Nuevo fragmento",
        editTitle: "Editar fragmento",
        nameLabel: "Nombre",
        namePlaceholder: "Correo personal",
        triggerLabel: "Disparador",
        triggerPlaceholder: ";correo",
        replacementLabel: "Texto",
        replacementPlaceholder: "micorreo@ejemplo.com",
        expansionLabel: "Expandir",
        expansionImmediate: "Al instante",
        expansionDelimiter: "Tras espacio, Tab o Enter",
        variablesHint: "Variables: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "Se convierten en la fecha, la hora y el texto copiado al momento de expandir.",
        emptyList: "Aún no hay fragmentos. Añade el primero.",
        duplicateTrigger: "Otro fragmento ya usa ese disparador.",
        triggerTooShort: "El disparador necesita al menos 2 caracteres.",
        deleteButton: "Eliminar",
        saveButton: "Guardar",
        manageButton: "Gestionar fragmentos"
    )

    static let de = SnippetFeatureStrings(
        pageTitle: "Textbausteine",
        hubDescription: "Kurze Kürzel werden zu ganzem Text",
        enable: "Bausteine beim Tippen ausschreiben",
        enableCaption: "Tippe ein Kürzel irgendwo und es wird zu seinem Text. Alles bleibt auf diesem Mac.",
        addButton: "Baustein hinzufügen",
        newTitle: "Neuer Baustein",
        editTitle: "Baustein bearbeiten",
        nameLabel: "Name",
        namePlaceholder: "Private E-Mail",
        triggerLabel: "Kürzel",
        triggerPlaceholder: ";mail",
        replacementLabel: "Text",
        replacementPlaceholder: "meinemail@beispiel.de",
        expansionLabel: "Ausschreiben",
        expansionImmediate: "Sofort",
        expansionDelimiter: "Nach Leerzeichen, Tab oder Enter",
        variablesHint: "Variablen: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "Sie werden beim Ausschreiben zu Datum, Uhrzeit und dem kopierten Text.",
        emptyList: "Noch keine Bausteine. Füge den ersten hinzu.",
        duplicateTrigger: "Ein anderer Baustein nutzt dieses Kürzel bereits.",
        triggerTooShort: "Das Kürzel braucht mindestens 2 Zeichen.",
        deleteButton: "Löschen",
        saveButton: "Sichern",
        manageButton: "Textbausteine verwalten"
    )

    static let fr = SnippetFeatureStrings(
        pageTitle: "Extraits de texte",
        hubDescription: "Des déclencheurs courts deviennent du texte complet",
        enable: "Développer les extraits pendant la frappe",
        enableCaption: "Tapez un déclencheur n'importe où et il devient son texte. Tout reste sur ce Mac.",
        addButton: "Ajouter un extrait",
        newTitle: "Nouvel extrait",
        editTitle: "Modifier l'extrait",
        nameLabel: "Nom",
        namePlaceholder: "E-mail personnel",
        triggerLabel: "Déclencheur",
        triggerPlaceholder: ";mail",
        replacementLabel: "Texte",
        replacementPlaceholder: "monmail@exemple.fr",
        expansionLabel: "Développer",
        expansionImmediate: "Immédiatement",
        expansionDelimiter: "Après espace, Tab ou Entrée",
        variablesHint: "Variables : {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "Elles deviennent la date, l'heure et le texte copié au moment du développement.",
        emptyList: "Aucun extrait pour l'instant. Ajoutez le premier.",
        duplicateTrigger: "Un autre extrait utilise déjà ce déclencheur.",
        triggerTooShort: "Le déclencheur doit faire au moins 2 caractères.",
        deleteButton: "Supprimer",
        saveButton: "Enregistrer",
        manageButton: "Gérer les extraits"
    )

    static let it = SnippetFeatureStrings(
        pageTitle: "Frammenti di testo",
        hubDescription: "Trigger brevi diventano testo completo",
        enable: "Espandi i frammenti mentre scrivi",
        enableCaption: "Digita un trigger ovunque e diventa il suo testo. Tutto resta su questo Mac.",
        addButton: "Aggiungi frammento",
        newTitle: "Nuovo frammento",
        editTitle: "Modifica frammento",
        nameLabel: "Nome",
        namePlaceholder: "Email personale",
        triggerLabel: "Trigger",
        triggerPlaceholder: ";email",
        replacementLabel: "Testo",
        replacementPlaceholder: "miamail@esempio.it",
        expansionLabel: "Espandi",
        expansionImmediate: "Subito",
        expansionDelimiter: "Dopo spazio, Tab o Invio",
        variablesHint: "Variabili: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "Diventano la data, l'ora e il testo copiato al momento dell'espansione.",
        emptyList: "Ancora nessun frammento. Aggiungi il primo.",
        duplicateTrigger: "Un altro frammento usa già questo trigger.",
        triggerTooShort: "Il trigger richiede almeno 2 caratteri.",
        deleteButton: "Elimina",
        saveButton: "Salva",
        manageButton: "Gestisci frammenti"
    )

    static let ja = SnippetFeatureStrings(
        pageTitle: "テキストスニペット",
        hubDescription: "短いトリガーが文章に展開されます",
        enable: "入力中にスニペットを展開",
        enableCaption: "どこでもトリガーを入力すると、その本文に変わります。すべてこのMacの中だけで完結します。",
        addButton: "スニペットを追加",
        newTitle: "新規スニペット",
        editTitle: "スニペットを編集",
        nameLabel: "名前",
        namePlaceholder: "個人用メール",
        triggerLabel: "トリガー",
        triggerPlaceholder: ";mail",
        replacementLabel: "テキスト",
        replacementPlaceholder: "mymail@example.com",
        expansionLabel: "展開のタイミング",
        expansionImmediate: "すぐに",
        expansionDelimiter: "スペース、Tab、Returnの後",
        variablesHint: "変数: {{date}}, {{time}}, {{datetime}}, {{clipboard}}",
        variablesCaption: "展開した瞬間の日付、時刻、コピー中のテキストになります。",
        emptyList: "スニペットはまだありません。最初のひとつを追加してください。",
        duplicateTrigger: "このトリガーは別のスニペットが使っています。",
        triggerTooShort: "トリガーは2文字以上必要です。",
        deleteButton: "削除",
        saveButton: "保存",
        manageButton: "スニペットを管理"
    )

    static let zhHans = SnippetFeatureStrings(
        pageTitle: "文本片段",
        hubDescription: "短触发词展开为完整文本",
        enable: "输入时展开片段",
        enableCaption: "在任何地方输入触发词,它就会变成对应文本。一切都只在这台 Mac 上。",
        addButton: "添加片段",
        newTitle: "新建片段",
        editTitle: "编辑片段",
        nameLabel: "名称",
        namePlaceholder: "个人邮箱",
        triggerLabel: "触发词",
        triggerPlaceholder: ";email",
        replacementLabel: "文本",
        replacementPlaceholder: "mymail@example.com",
        expansionLabel: "展开时机",
        expansionImmediate: "立即",
        expansionDelimiter: "空格、Tab 或回车后",
        variablesHint: "变量:{{date}}、{{time}}、{{datetime}}、{{clipboard}}",
        variablesCaption: "展开那一刻,它们会变成日期、时间和已复制的文本。",
        emptyList: "还没有片段。添加第一个吧。",
        duplicateTrigger: "另一个片段已在使用该触发词。",
        triggerTooShort: "触发词至少需要 2 个字符。",
        deleteButton: "删除",
        saveButton: "存储",
        manageButton: "管理文本片段"
    )

    static let zhTW = SnippetFeatureStrings(
        pageTitle: "文字片段",
        hubDescription: "簡短觸發詞展開為完整文字",
        enable: "輸入時展開片段",
        enableCaption: "在任何地方輸入觸發詞,它就會變成對應文字。一切都只在這台 Mac 上。",
        addButton: "加入片段",
        newTitle: "新增片段",
        editTitle: "編輯片段",
        nameLabel: "名稱",
        namePlaceholder: "個人電郵",
        triggerLabel: "觸發詞",
        triggerPlaceholder: ";email",
        replacementLabel: "文字",
        replacementPlaceholder: "mymail@example.com",
        expansionLabel: "展開時機",
        expansionImmediate: "立即",
        expansionDelimiter: "空格、Tab 或 Return 後",
        variablesHint: "變數:{{date}}、{{time}}、{{datetime}}、{{clipboard}}",
        variablesCaption: "展開那一刻,它們會變成日期、時間和已拷貝的文字。",
        emptyList: "還沒有片段。加入第一個吧。",
        duplicateTrigger: "另一個片段已使用此觸發詞。",
        triggerTooShort: "觸發詞至少需要 2 個字元。",
        deleteButton: "刪除",
        saveButton: "儲存",
        manageButton: "管理文字片段"
    )

    static let zhHK = SnippetFeatureStrings(
        pageTitle: "文字片段",
        hubDescription: "簡短觸發詞展開為完整文字",
        enable: "輸入時展開片段",
        enableCaption: "在任何地方輸入觸發詞,它就會變成對應文字。一切都只在這台 Mac 上。",
        addButton: "加入片段",
        newTitle: "新增片段",
        editTitle: "編輯片段",
        nameLabel: "名稱",
        namePlaceholder: "個人電郵",
        triggerLabel: "觸發詞",
        triggerPlaceholder: ";email",
        replacementLabel: "文字",
        replacementPlaceholder: "mymail@example.com",
        expansionLabel: "展開時機",
        expansionImmediate: "立即",
        expansionDelimiter: "空格、Tab 或 Return 後",
        variablesHint: "變數:{{date}}、{{time}}、{{datetime}}、{{clipboard}}",
        variablesCaption: "展開嗰一刻,佢哋會變成日期、時間同已複製嘅文字。",
        emptyList: "仲未有片段。加入第一個啦。",
        duplicateTrigger: "另一個片段已使用此觸發詞。",
        triggerTooShort: "觸發詞至少需要 2 個字元。",
        deleteButton: "刪除",
        saveButton: "儲存",
        manageButton: "管理文字片段"
    )
}
