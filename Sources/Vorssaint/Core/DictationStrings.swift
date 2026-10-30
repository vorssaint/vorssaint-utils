// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DictationStrings {
    let title: String
    let recording: String
    let processing: String
    let copied: String
    let history: String
    let start: String
    let stop: String
    let cancel: String
    let empty: String
    let failed: String

    static func localized(_ language: AppLanguage) -> DictationStrings {
        let words: [String]
        switch language {
        case .enUS: words = ["Dictation", "Listening", "Transcribing", "Text copied", "Speech history", "Start dictation", "Finish", "Cancel", "Your speech, saved here", "Dictation needs attention"]
        case .ptBR: words = ["Ditado", "Ouvindo", "Transcrevendo", "Texto copiado", "Histórico de voz", "Iniciar ditado", "Concluir", "Cancelar", "Sua fala, salva aqui", "O ditado precisa de atenção"]
        case .tr: words = ["Dikte", "Dinleniyor", "Yazıya dönüştürülüyor", "Metin kopyalandı", "Konuşma geçmişi", "Dikteyi başlat", "Bitir", "İptal", "Konuşmanız burada kaydedilir", "Dikte için işlem gerekiyor"]
        case .ru: words = ["Диктовка", "Слушаю", "Распознавание", "Текст скопирован", "История речи", "Начать диктовку", "Готово", "Отмена", "Ваша речь сохраняется здесь", "Диктовка требует внимания"]
        case .es: words = ["Dictado", "Escuchando", "Transcribiendo", "Texto copiado", "Historial de voz", "Iniciar dictado", "Finalizar", "Cancelar", "Tu voz, guardada aquí", "El dictado necesita atención"]
        case .sk: words = ["Diktovanie", "Počúvam", "Prepisujem", "Text skopírovaný", "História reči", "Spustiť diktovanie", "Dokončiť", "Zrušiť", "Vaša reč uložená tu", "Diktovanie vyžaduje pozornosť"]
        case .de: words = ["Diktat", "Hört zu", "Transkribiert", "Text kopiert", "Sprachverlauf", "Diktat starten", "Fertig", "Abbrechen", "Ihre Sprache wird hier gespeichert", "Diktat erfordert Aufmerksamkeit"]
        case .fr: words = ["Dictée", "À l’écoute", "Transcription", "Texte copié", "Historique vocal", "Commencer la dictée", "Terminer", "Annuler", "Votre parole, enregistrée ici", "La dictée nécessite votre attention"]
        case .it: words = ["Dettatura", "In ascolto", "Trascrizione", "Testo copiato", "Cronologia vocale", "Avvia dettatura", "Termina", "Annulla", "La tua voce, salvata qui", "La dettatura richiede attenzione"]
        case .ja: words = ["音声入力", "聞き取り中", "文字起こし中", "テキストをコピーしました", "音声履歴", "音声入力を開始", "完了", "キャンセル", "音声がここに保存されます", "音声入力を確認してください"]
        case .ko: words = ["음성 입력", "듣는 중", "변환 중", "텍스트 복사됨", "음성 기록", "음성 입력 시작", "완료", "취소", "음성이 여기에 저장됩니다", "음성 입력 확인 필요"]
        case .uk: words = ["Диктування", "Слухаю", "Розпізнавання", "Текст скопійовано", "Історія мовлення", "Почати диктування", "Готово", "Скасувати", "Ваше мовлення зберігається тут", "Диктування потребує уваги"]
        case .zhHans: words = ["语音输入", "正在聆听", "正在转写", "文本已复制", "语音历史", "开始语音输入", "完成", "取消", "您的语音将保存在此处", "请检查语音输入"]
        case .zhTW: words = ["語音輸入", "正在聆聽", "正在轉寫", "文字已複製", "語音記錄", "開始語音輸入", "完成", "取消", "您的語音將儲存在此處", "請檢查語音輸入"]
        case .zhHK: words = ["語音輸入", "聆聽中", "轉寫中", "文字已複製", "語音記錄", "開始語音輸入", "完成", "取消", "你的語音會儲存在這裡", "請檢查語音輸入"]
        }
        return DictationStrings(title: words[0], recording: words[1], processing: words[2], copied: words[3], history: words[4],
                                start: words[5], stop: words[6], cancel: words[7], empty: words[8], failed: words[9])
    }
}
