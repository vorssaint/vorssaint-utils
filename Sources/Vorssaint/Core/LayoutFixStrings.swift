// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct LayoutFixStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let activeNow: String
    let triggerSection: String
    let triggerCaption: String
    let triggerRightOption: String
    let triggerLeftOption: String
    let triggerDoubleShift: String
    let layoutsSection: String
    let layoutsCaption: String

    func triggerLabel(_ trigger: LayoutFixTrigger) -> String {
        switch trigger {
        case .rightOption: return triggerRightOption
        case .leftOption: return triggerLeftOption
        case .doubleShift: return triggerDoubleShift
        }
    }
}

extension FeatureStrings {
    static func layoutFix(_ language: AppLanguage) -> LayoutFixStrings {
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

extension LayoutFixStrings {
    static let enUS = LayoutFixStrings(
        pageTitle: "Layout Fix",
        hubDescription: "Retypes a word typed in the wrong keyboard layout.",
        enableToggle: "Fix words typed in the wrong layout",
        enableCaption: "Tap the trigger key after a word typed in the wrong layout, or with text selected. Tap again for the next layout; the last tap brings the original back. The input source switches too.",
        activeNow: "Active",
        triggerSection: "Trigger",
        triggerCaption: "A quick tap on its own. Held with another key, the key works as usual.",
        triggerRightOption: "Right ⌥ tap",
        triggerLeftOption: "Left ⌥ tap",
        triggerDoubleShift: "Double ⇧ tap",
        layoutsSection: "Layouts",
        layoutsCaption: "Layouts the fix chooses from, in the Input menu order."
    )

    static let ptBR = LayoutFixStrings(
        pageTitle: "Correção de layout",
        hubDescription: "Redigita uma palavra digitada no layout de teclado errado.",
        enableToggle: "Corrigir palavras digitadas no layout errado",
        enableCaption: "Toque na tecla de ativação depois de uma palavra digitada no layout errado, ou com texto selecionado. Toque de novo para o próximo layout; o último toque restaura o original. A fonte de entrada também muda.",
        activeNow: "Ativo",
        triggerSection: "Ativação",
        triggerCaption: "Um toque rápido e isolado. Segurada com outra tecla, ela funciona normalmente.",
        triggerRightOption: "Toque no ⌥ direito",
        triggerLeftOption: "Toque no ⌥ esquerdo",
        triggerDoubleShift: "Toque duplo no ⇧",
        layoutsSection: "Layouts",
        layoutsCaption: "Layouts entre os quais a correção escolhe, na ordem do menu de entrada."
    )

    static let tr = LayoutFixStrings(
        pageTitle: "Düzen Düzeltme",
        hubDescription: "Yanlış klavye düzeninde yazılan bir kelimeyi yeniden yazar.",
        enableToggle: "Yanlış düzende yazılan kelimeleri düzelt",
        enableCaption: "Yanlış düzende yazılan bir kelimeden sonra veya metin seçiliyken tetik tuşuna dokunun. Sonraki düzen için tekrar dokunun; son dokunuş orijinali geri getirir. Giriş kaynağı da değişir.",
        activeNow: "Etkin",
        triggerSection: "Tetik",
        triggerCaption: "Tek başına hızlı bir dokunuş. Başka bir tuşla basılı tutulursa tuş normal çalışır.",
        triggerRightOption: "Sağ ⌥ dokunuşu",
        triggerLeftOption: "Sol ⌥ dokunuşu",
        triggerDoubleShift: "Çift ⇧ dokunuşu",
        layoutsSection: "Düzenler",
        layoutsCaption: "Düzeltmenin seçtiği düzenler, Giriş menüsü sırasıyla."
    )

    static let ru = LayoutFixStrings(
        pageTitle: "Исправление раскладки",
        hubDescription: "Перепечатывает слово, набранное не в той раскладке.",
        enableToggle: "Исправлять слова, набранные не в той раскладке",
        enableCaption: "Нажмите клавишу после слова, набранного не в той раскладке, или выделив текст. Повторное нажатие выбирает следующую раскладку, а последнее возвращает исходный текст. Источник ввода тоже переключается.",
        activeNow: "Работает",
        triggerSection: "Клавиша",
        triggerCaption: "Быстрое одиночное нажатие. Вместе с другой клавишей она работает как обычно.",
        triggerRightOption: "Правый ⌥",
        triggerLeftOption: "Левый ⌥",
        triggerDoubleShift: "Двойной ⇧",
        layoutsSection: "Раскладки",
        layoutsCaption: "Раскладки, из которых выбирает исправление, в порядке меню ввода."
    )

    static let es = LayoutFixStrings(
        pageTitle: "Corrección de distribución",
        hubDescription: "Vuelve a escribir una palabra tecleada con la distribución equivocada.",
        enableToggle: "Corregir palabras escritas con la distribución equivocada",
        enableCaption: "Pulsa la tecla de activación tras una palabra escrita con la distribución equivocada, o con texto seleccionado. Vuelve a pulsar para la siguiente distribución; la última pulsación recupera el original. La fuente de entrada también cambia.",
        activeNow: "Activo",
        triggerSection: "Activación",
        triggerCaption: "Una pulsación rápida y sola. Mantenida con otra tecla, funciona como siempre.",
        triggerRightOption: "Pulsar ⌥ derecha",
        triggerLeftOption: "Pulsar ⌥ izquierda",
        triggerDoubleShift: "Doble pulsación de ⇧",
        layoutsSection: "Distribuciones",
        layoutsCaption: "Distribuciones entre las que elige la corrección, en el orden del menú de entrada."
    )

    static let sk = LayoutFixStrings(
        pageTitle: "Oprava rozloženia",
        hubDescription: "Prepíše slovo napísané v nesprávnom rozložení klávesnice.",
        enableToggle: "Opravovať slová napísané v nesprávnom rozložení",
        enableCaption: "Ťuknite na spúšťací kláves po slove napísanom v nesprávnom rozložení alebo s vybraným textom. Ďalšie ťuknutie prepne na ďalšie rozloženie; posledné vráti pôvodný text. Prepne sa aj zdroj vstupu.",
        activeNow: "Aktívne",
        triggerSection: "Spúšťač",
        triggerCaption: "Rýchle samostatné ťuknutie. Podržaný s iným klávesom funguje ako zvyčajne.",
        triggerRightOption: "Ťuknutie na pravý ⌥",
        triggerLeftOption: "Ťuknutie na ľavý ⌥",
        triggerDoubleShift: "Dvojité ťuknutie na ⇧",
        layoutsSection: "Rozloženia",
        layoutsCaption: "Rozloženia, z ktorých oprava vyberá, v poradí ponuky vstupu."
    )

    static let de = LayoutFixStrings(
        pageTitle: "Layout-Korrektur",
        hubDescription: "Tippt ein Wort neu, das im falschen Tastaturlayout eingegeben wurde.",
        enableToggle: "Im falschen Layout getippte Wörter korrigieren",
        enableCaption: "Tippe nach einem im falschen Layout geschriebenen Wort oder bei markiertem Text auf die Auslösetaste. Erneut tippen für das nächste Layout; das letzte Tippen stellt das Original wieder her. Die Eingabequelle wechselt mit.",
        activeNow: "Aktiv",
        triggerSection: "Auslöser",
        triggerCaption: "Ein kurzes Tippen allein. Mit einer anderen Taste gehalten, funktioniert sie wie gewohnt.",
        triggerRightOption: "Rechte ⌥ tippen",
        triggerLeftOption: "Linke ⌥ tippen",
        triggerDoubleShift: "Doppelt ⇧ tippen",
        layoutsSection: "Layouts",
        layoutsCaption: "Layouts, aus denen die Korrektur wählt, in der Reihenfolge des Eingabemenüs."
    )

    static let fr = LayoutFixStrings(
        pageTitle: "Correction de disposition",
        hubDescription: "Retape un mot saisi avec la mauvaise disposition de clavier.",
        enableToggle: "Corriger les mots saisis avec la mauvaise disposition",
        enableCaption: "Touchez la touche de déclenchement après un mot saisi avec la mauvaise disposition, ou avec du texte sélectionné. Touchez à nouveau pour la disposition suivante ; la dernière touche rétablit l’original. La source de saisie change aussi.",
        activeNow: "Actif",
        triggerSection: "Déclencheur",
        triggerCaption: "Un appui bref et isolé. Maintenue avec une autre touche, elle fonctionne normalement.",
        triggerRightOption: "Appui sur ⌥ droite",
        triggerLeftOption: "Appui sur ⌥ gauche",
        triggerDoubleShift: "Double appui sur ⇧",
        layoutsSection: "Dispositions",
        layoutsCaption: "Dispositions parmi lesquelles la correction choisit, dans l’ordre du menu de saisie."
    )

    static let it = LayoutFixStrings(
        pageTitle: "Correzione layout",
        hubDescription: "Riscrive una parola digitata con il layout di tastiera sbagliato.",
        enableToggle: "Correggi le parole digitate con il layout sbagliato",
        enableCaption: "Tocca il tasto di attivazione dopo una parola digitata con il layout sbagliato, o con del testo selezionato. Tocca di nuovo per il layout successivo; l’ultimo tocco ripristina l’originale. Cambia anche la sorgente di input.",
        activeNow: "Attivo",
        triggerSection: "Attivazione",
        triggerCaption: "Un tocco rapido e isolato. Tenuto premuto con un altro tasto, funziona come sempre.",
        triggerRightOption: "Tocco su ⌥ destro",
        triggerLeftOption: "Tocco su ⌥ sinistro",
        triggerDoubleShift: "Doppio tocco su ⇧",
        layoutsSection: "Layout",
        layoutsCaption: "Layout tra cui sceglie la correzione, nell’ordine del menu di input."
    )

    static let ja = LayoutFixStrings(
        pageTitle: "レイアウト修正",
        hubDescription: "間違ったキーボードレイアウトで入力した単語を打ち直します。",
        enableToggle: "間違ったレイアウトで入力した単語を修正",
        enableCaption: "間違ったレイアウトで単語を入力した後、またはテキストを選択した状態でトリガーキーを押します。もう一度押すと次のレイアウト、最後に押すと元に戻ります。入力ソースも切り替わります。",
        activeNow: "動作中",
        triggerSection: "トリガー",
        triggerCaption: "単独ですばやく押します。ほかのキーと一緒に押した場合は通常どおり動作します。",
        triggerRightOption: "右⌥を押す",
        triggerLeftOption: "左⌥を押す",
        triggerDoubleShift: "⇧を2回押す",
        layoutsSection: "レイアウト",
        layoutsCaption: "修正の候補となるレイアウト（入力メニューの順）。"
    )

    static let ko = LayoutFixStrings(
        pageTitle: "자판 수정",
        hubDescription: "잘못된 키보드 자판으로 입력한 단어를 다시 입력합니다.",
        enableToggle: "잘못된 자판으로 입력한 단어 수정",
        enableCaption: "잘못된 자판으로 단어를 입력한 뒤 또는 텍스트를 선택한 상태에서 실행 키를 누르세요. 다시 누르면 다음 자판, 마지막으로 누르면 원래대로 돌아갑니다. 입력 소스도 바뀝니다.",
        activeNow: "작동 중",
        triggerSection: "실행 키",
        triggerCaption: "단독으로 짧게 누르세요. 다른 키와 함께 누르면 평소처럼 작동합니다.",
        triggerRightOption: "오른쪽 ⌥ 누르기",
        triggerLeftOption: "왼쪽 ⌥ 누르기",
        triggerDoubleShift: "⇧ 두 번 누르기",
        layoutsSection: "자판",
        layoutsCaption: "수정 시 선택하는 자판(입력 메뉴 순서)."
    )

    static let zhHans = LayoutFixStrings(
        pageTitle: "键盘布局纠正",
        hubDescription: "重新输入用错键盘布局打出的单词。",
        enableToggle: "纠正用错布局输入的单词",
        enableCaption: "在用错布局输入单词后，或选中文本时，轻按触发键。再按一次换到下一个布局；最后一次恢复原文。输入法也会随之切换。",
        activeNow: "运行中",
        triggerSection: "触发键",
        triggerCaption: "单独快速轻按。与其他键一起按住时照常使用。",
        triggerRightOption: "轻按右侧 ⌥",
        triggerLeftOption: "轻按左侧 ⌥",
        triggerDoubleShift: "连按两次 ⇧",
        layoutsSection: "布局",
        layoutsCaption: "纠正时可选的布局，按输入法菜单顺序。"
    )

    static let zhTW = LayoutFixStrings(
        pageTitle: "鍵盤配置修正",
        hubDescription: "重新輸入用錯鍵盤配置打出的單字。",
        enableToggle: "修正用錯配置輸入的單字",
        enableCaption: "在用錯配置輸入單字後，或選取文字時，輕按觸發鍵。再按一次換到下一個配置；最後一次還原原文。輸入方式也會隨之切換。",
        activeNow: "執行中",
        triggerSection: "觸發鍵",
        triggerCaption: "單獨快速輕按。與其他鍵一起按住時照常使用。",
        triggerRightOption: "輕按右側 ⌥",
        triggerLeftOption: "輕按左側 ⌥",
        triggerDoubleShift: "連按兩次 ⇧",
        layoutsSection: "配置",
        layoutsCaption: "修正時可選的配置，依輸入法選單順序。"
    )

    static let zhHK = LayoutFixStrings(
        pageTitle: "鍵盤配置修正",
        hubDescription: "重新輸入用錯鍵盤配置打出的字詞。",
        enableToggle: "修正用錯配置輸入的字詞",
        enableCaption: "在用錯配置輸入字詞後，或選取文字時，輕按觸發鍵。再按一次換到下一個配置；最後一次還原原文。輸入法亦會隨之切換。",
        activeNow: "運作中",
        triggerSection: "觸發鍵",
        triggerCaption: "單獨快速輕按。與其他鍵一起按住時照常使用。",
        triggerRightOption: "輕按右邊 ⌥",
        triggerLeftOption: "輕按左邊 ⌥",
        triggerDoubleShift: "連按兩次 ⇧",
        layoutsSection: "配置",
        layoutsCaption: "修正時可選的配置，依輸入法選單次序。"
    )

    static let uk = LayoutFixStrings(
        pageTitle: "Виправлення розкладки",
        hubDescription: "Передруковує слово, набране не в тій розкладці.",
        enableToggle: "Виправляти слова, набрані не в тій розкладці",
        enableCaption: "Натисніть клавішу після слова, набраного не в тій розкладці, або виділивши текст. Повторне натискання вибирає наступну розкладку, а останнє повертає початковий текст. Джерело введення теж перемикається.",
        activeNow: "Працює",
        triggerSection: "Клавіша",
        triggerCaption: "Швидке одиночне натискання. Разом з іншою клавішею вона працює як звичайно.",
        triggerRightOption: "Правий ⌥",
        triggerLeftOption: "Лівий ⌥",
        triggerDoubleShift: "Подвійний ⇧",
        layoutsSection: "Розкладки",
        layoutsCaption: "Розкладки, з яких вибирає виправлення, у порядку меню введення."
    )
}
