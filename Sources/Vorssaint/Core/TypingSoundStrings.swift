// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the snippets page sends you for the snippet sound.
struct SnippetSoundHintStrings {
    let hint: String
}

extension FeatureStrings {
    /// The text snippets section of the Sounds page.
    static func typingSounds(_ language: AppLanguage) -> SoundGroupStrings {
        switch language {
        case .enUS: return SoundGroupStrings(
            title: "Text snippets",
            note: "The snippet sound plays while text snippets are on.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Snippet expanded",
                                              caption: "When a trigger you type expands into its snippet."),
            ])
        case .ptBR: return SoundGroupStrings(
            title: "Trechos de texto",
            note: "O som dos trechos toca enquanto os trechos de texto estão ativados.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Trecho expandido",
                                              caption: "Quando um gatilho digitado se expande no trecho."),
            ])
        case .tr: return SoundGroupStrings(
            title: "Metin parçacıkları",
            note: "Parçacık sesi, metin parçacıkları açıkken çalar.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Parçacık genişletildi",
                                              caption: "Yazdığınız bir tetikleyici parçacığına genişlediğinde."),
            ])
        case .ru: return SoundGroupStrings(
            title: "Текстовые фрагменты",
            note: "Звук фрагментов воспроизводится, пока включены текстовые фрагменты.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Фрагмент вставлен",
                                              caption: "Когда введённый триггер разворачивается во фрагмент."),
            ])
        case .es: return SoundGroupStrings(
            title: "Fragmentos de texto",
            note: "El sonido de los fragmentos suena mientras los fragmentos de texto están activados.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Fragmento expandido",
                                              caption: "Cuando un activador que escribes se expande en su fragmento."),
            ])
        case .sk: return SoundGroupStrings(
            title: "Textové úryvky",
            note: "Zvuk úryvkov znie, kým sú textové úryvky zapnuté.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Úryvok rozbalený",
                                              caption: "Keď sa napísaný spúšťač rozbalí na úryvok."),
            ])
        case .de: return SoundGroupStrings(
            title: "Textbausteine",
            note: "Der Bausteinton spielt, solange Textbausteine aktiviert sind.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Baustein eingesetzt",
                                              caption: "Wenn ein getippter Auslöser zu seinem Baustein erweitert wird."),
            ])
        case .fr: return SoundGroupStrings(
            title: "Extraits de texte",
            note: "Le son des extraits est lu tant que les extraits de texte sont activés.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Extrait développé",
                                              caption: "Quand un déclencheur que vous tapez se développe en son extrait."),
            ])
        case .it: return SoundGroupStrings(
            title: "Frammenti di testo",
            note: "Il suono dei frammenti viene riprodotto mentre i frammenti di testo sono attivi.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Frammento espanso",
                                              caption: "Quando un attivatore digitato si espande nel suo frammento."),
            ])
        case .ja: return SoundGroupStrings(
            title: "テキストスニペット",
            note: "スニペットのサウンドはテキストスニペットがオンのときに再生されます。",
            moments: [
                .snippetExpanded: SoundMoment(title: "スニペット展開",
                                              caption: "入力したトリガーがスニペットに展開されたとき。"),
            ])
        case .ko: return SoundGroupStrings(
            title: "텍스트 스니펫",
            note: "스니펫 사운드는 텍스트 스니펫이 켜져 있을 때 재생됩니다.",
            moments: [
                .snippetExpanded: SoundMoment(title: "스니펫 확장",
                                              caption: "입력한 트리거가 스니펫으로 확장될 때."),
            ])
        case .uk: return SoundGroupStrings(
            title: "Текстові фрагменти",
            note: "Звук фрагментів відтворюється, поки ввімкнено текстові фрагменти.",
            moments: [
                .snippetExpanded: SoundMoment(title: "Фрагмент вставлено",
                                              caption: "Коли введений тригер розгортається у фрагмент."),
            ])
        case .zhHans: return SoundGroupStrings(
            title: "文本片段",
            note: "文本片段开启时会播放片段声音。",
            moments: [
                .snippetExpanded: SoundMoment(title: "片段已展开",
                                              caption: "当你输入的触发词展开为片段时。"),
            ])
        case .zhTW: return SoundGroupStrings(
            title: "文字片段",
            note: "文字片段開啟時會播放片段聲音。",
            moments: [
                .snippetExpanded: SoundMoment(title: "片段已展開",
                                              caption: "當你輸入的觸發字展開為片段時。"),
            ])
        case .zhHK: return SoundGroupStrings(
            title: "文字片段",
            note: "文字片段開啟時會播放片段聲音。",
            moments: [
                .snippetExpanded: SoundMoment(title: "片段已展開",
                                              caption: "當你輸入的觸發字展開為片段時。"),
            ])
        }
    }

    /// Under the snippet sound's switch on the snippets page, where its
    /// sound was once chosen.
    static func snippetSoundHint(_ language: AppLanguage) -> SnippetSoundHintStrings {
        switch language {
        case .enUS: return SnippetSoundHintStrings(hint: "Choose its sound, volume and repeats on the Sounds page.")
        case .ptBR: return SnippetSoundHintStrings(hint: "Escolha o som, o volume e as repetições na página Sons.")
        case .tr: return SnippetSoundHintStrings(hint: "Sesini, ses düzeyini ve tekrarını Sesler sayfasından seçin.")
        case .ru: return SnippetSoundHintStrings(hint: "Звук, громкость и повторы выбираются на странице «Звуки».")
        case .es: return SnippetSoundHintStrings(hint: "Elige su sonido, volumen y repeticiones en la página Sonidos.")
        case .sk: return SnippetSoundHintStrings(hint: "Zvuk, hlasitosť a opakovania vyberte na stránke Zvuky.")
        case .de: return SnippetSoundHintStrings(hint: "Ton, Lautstärke und Wiederholungen wählst du auf der Seite „Töne“.")
        case .fr: return SnippetSoundHintStrings(hint: "Choisissez son son, son volume et ses répétitions dans la page Sons.")
        case .it: return SnippetSoundHintStrings(hint: "Scegli suono, volume e ripetizioni nella pagina Suoni.")
        case .ja: return SnippetSoundHintStrings(hint: "サウンド、音量、繰り返しは「サウンド」ページで選べます。")
        case .ko: return SnippetSoundHintStrings(hint: "사운드, 음량, 반복은 사운드 페이지에서 선택하세요.")
        case .uk: return SnippetSoundHintStrings(hint: "Звук, гучність і повтори вибираються на сторінці «Звуки».")
        case .zhHans: return SnippetSoundHintStrings(hint: "在“声音”页面选择它的声音、音量和重复次数。")
        case .zhTW: return SnippetSoundHintStrings(hint: "在「聲音」頁面選擇它的聲音、音量和重複次數。")
        case .zhHK: return SnippetSoundHintStrings(hint: "在「聲音」頁面選擇它的聲音、音量和重複次數。")
        }
    }
}
