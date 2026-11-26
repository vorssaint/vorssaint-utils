// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for Audio Transcription summary and system-wide voice
/// dictation controls across all 15 supported languages.
struct AudioTranscriptionExtrasStrings {
    let summarySectionHeader: String
    let summaryToggle: String
    let summaryCaption: String
    let summaryPromptLabel: String
    let resetPromptButton: String
    let summarizeButton: String
    let regenerateSummaryButton: String
    let summarizingStatus: String
    let summaryTitle: String
    let copySummaryButton: String
    let saveSummaryButton: String
    let summaryCopiedHUD: String
    let summarySavedHUD: String
    let summaryFallbackNote: String
    let dictationSectionHeader: String
    let dictationTitle: String
    let dictationToggle: String
    let dictationCaption: String
    let dictationShortcutLabel: String
    let startDictationButton: String
    let stopDictationButton: String
    let dictatingStatusFormat: String
    let dictationListeningHUD: String
    let dictationInsertedHUD: String
    let dictationCopiedHUD: String
    let dictationModelMissingHUD: String
    let dictationMicDeniedError: String
    let dictationAccessibilityHint: String

    static func localized(_ language: AppLanguage) -> AudioTranscriptionExtrasStrings {
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

extension AudioTranscriptionExtrasStrings {
    static let enUS = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Summary",
        summaryToggle: "Generate summary",
        summaryCaption: "Automatically summarizes finished transcripts locally using your custom prompt and saves a summary beside the transcript.",
        summaryPromptLabel: "Summary prompt",
        resetPromptButton: "Reset prompt",
        summarizeButton: "Summarize",
        regenerateSummaryButton: "Regenerate",
        summarizingStatus: "Summarizing…",
        summaryTitle: "Summary",
        copySummaryButton: "Copy summary",
        saveSummaryButton: "Save summary…",
        summaryCopiedHUD: "Summary copied",
        summarySavedHUD: "Summary saved",
        summaryFallbackNote: "Generated locally on device.",
        dictationSectionHeader: "System-wide dictation",
        dictationTitle: "Voice dictation",
        dictationToggle: "Enable system-wide dictation",
        dictationCaption: "Press the shortcut in any app to speak into Parakeet Unified English 0.6B, then press it again to insert the transcript at your cursor.",
        dictationShortcutLabel: "Dictation shortcut",
        startDictationButton: "Dictate",
        stopDictationButton: "Stop",
        dictatingStatusFormat: "Listening… %@",
        dictationListeningHUD: "Listening… press shortcut again to insert",
        dictationInsertedHUD: "Dictation inserted",
        dictationCopiedHUD: "Dictation copied to clipboard",
        dictationModelMissingHUD: "Download Parakeet 0.6B in Transcription first",
        dictationMicDeniedError: "Microphone permission is required for voice dictation.",
        dictationAccessibilityHint: "Grant Accessibility permission to insert directly at the cursor; without it, dictation copies to your clipboard."
    )

    static let ptBR = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Resumo",
        summaryToggle: "Gerar resumo",
        summaryCaption: "Resume automaticamente transcrições concluídas no Mac usando seu prompt personalizado e salva o resumo ao lado da transcrição.",
        summaryPromptLabel: "Prompt do resumo",
        resetPromptButton: "Restaurar prompt",
        summarizeButton: "Resumir",
        regenerateSummaryButton: "Gerar novamente",
        summarizingStatus: "Resumindo…",
        summaryTitle: "Resumo",
        copySummaryButton: "Copiar resumo",
        saveSummaryButton: "Salvar resumo…",
        summaryCopiedHUD: "Resumo copiado",
        summarySavedHUD: "Resumo salvo",
        summaryFallbackNote: "Gerado localmente neste Mac.",
        dictationSectionHeader: "Ditado em todo o sistema",
        dictationTitle: "Ditado por voz",
        dictationToggle: "Ativar ditado em todo o sistema",
        dictationCaption: "Pressione o atalho em qualquer app para falar com o Parakeet Unified English 0.6B e pressione novamente para inserir o texto no cursor.",
        dictationShortcutLabel: "Atalho de ditado",
        startDictationButton: "Ditar",
        stopDictationButton: "Parar",
        dictatingStatusFormat: "Ouvindo… %@",
        dictationListeningHUD: "Ouvindo… pressione o atalho novamente para inserir",
        dictationInsertedHUD: "Ditado inserido",
        dictationCopiedHUD: "Ditado copiado para a área de transferência",
        dictationModelMissingHUD: "Baixe o Parakeet 0.6B em Transcrição primeiro",
        dictationMicDeniedError: "É necessária permissão do microfone para o ditado por voz.",
        dictationAccessibilityHint: "Conceda permissão de Acessibilidade para inserir direto no cursor; sem ela, o ditado é copiado."
    )

    static let es = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Resumen",
        summaryToggle: "Generar resumen",
        summaryCaption: "Resume automáticamente las transcripciones terminadas en tu Mac usando tu prompt personalizado y guarda un resumen junto a la transcripción.",
        summaryPromptLabel: "Prompt del resumen",
        resetPromptButton: "Restablecer prompt",
        summarizeButton: "Resumir",
        regenerateSummaryButton: "Regenerar",
        summarizingStatus: "Resumiendo…",
        summaryTitle: "Resumen",
        copySummaryButton: "Copiar resumen",
        saveSummaryButton: "Guardar resumen…",
        summaryCopiedHUD: "Resumen copiado",
        summarySavedHUD: "Resumen guardado",
        summaryFallbackNote: "Generado localmente en este Mac.",
        dictationSectionHeader: "Dictado en todo el sistema",
        dictationTitle: "Dictado por voz",
        dictationToggle: "Activar dictado en todo el sistema",
        dictationCaption: "Pulsa el atajo en cualquier app para dictar con Parakeet Unified English 0.6B y vuelve a pulsarlo para insertar el texto en el cursor.",
        dictationShortcutLabel: "Atajo de dictado",
        startDictationButton: "Dictar",
        stopDictationButton: "Detener",
        dictatingStatusFormat: "Escuchando… %@",
        dictationListeningHUD: "Escuchando… vuelve a pulsar el atajo para insertar",
        dictationInsertedHUD: "Dictado insertado",
        dictationCopiedHUD: "Dictado copiado al portapapeles",
        dictationModelMissingHUD: "Descarga primero Parakeet 0.6B en Transcripción",
        dictationMicDeniedError: "Se requiere permiso de micrófono para el dictado por voz.",
        dictationAccessibilityHint: "Concede permiso de Accesibilidad para insertar en el cursor; sin él, se copia al portapapeles."
    )

    static let sk = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Súhrn",
        summaryToggle: "Vytvoriť súhrn",
        summaryCaption: "Automaticky zhrnie dokončené prepisy lokálne podľa vlastného promptu a uloží súhrn vedľa prepisu.",
        summaryPromptLabel: "Prompt pre súhrn",
        resetPromptButton: "Obnoviť prompt",
        summarizeButton: "Zhrnúť",
        regenerateSummaryButton: "Vygenerovať znova",
        summarizingStatus: "Vytvára sa súhrn…",
        summaryTitle: "Súhrn",
        copySummaryButton: "Kopírovať súhrn",
        saveSummaryButton: "Uložiť súhrn…",
        summaryCopiedHUD: "Súhrn skopírovaný",
        summarySavedHUD: "Súhrn uložený",
        summaryFallbackNote: "Vytvorené lokálne v tomto Macu.",
        dictationSectionHeader: "Celosystémové diktovanie",
        dictationTitle: "Hlasové diktovanie",
        dictationToggle: "Zapnúť celosystémové diktovanie",
        dictationCaption: "Stlačte skratku v ľubovoľnej aplikácii na hovorenie do modelu Parakeet Unified English 0.6B a znova ju stlačte na vloženie textu ku kurzoru.",
        dictationShortcutLabel: "Skratka diktovania",
        startDictationButton: "Diktovať",
        stopDictationButton: "Zastaviť",
        dictatingStatusFormat: "Počúva sa… %@",
        dictationListeningHUD: "Počúva sa… stlačte skratku znova pre vloženie",
        dictationInsertedHUD: "Diktát vložený",
        dictationCopiedHUD: "Diktát skopírovaný do schránky",
        dictationModelMissingHUD: "Najprv stiahnite Parakeet 0.6B v nastaveniach Prepisu",
        dictationMicDeniedError: "Pre hlasové diktovanie je potrebné povolenie mikrofónu.",
        dictationAccessibilityHint: "Udeľte prístupnosť na priame vkladanie ku kurzoru; bez nej sa text skopíruje do schránky."
    )

    static let tr = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Özet",
        summaryToggle: "Özet oluştur",
        summaryCaption: "Tamamlanan transkriptleri özel isteminizle yerel olarak otomatik özetler ve transkriptin yanına kaydeder.",
        summaryPromptLabel: "Özet istemi",
        resetPromptButton: "İstemi sıfırla",
        summarizeButton: "Özetle",
        regenerateSummaryButton: "Yeniden oluştur",
        summarizingStatus: "Özetleniyor…",
        summaryTitle: "Özet",
        copySummaryButton: "Özeti kopyala",
        saveSummaryButton: "Özeti kaydet…",
        summaryCopiedHUD: "Özet kopyalandı",
        summarySavedHUD: "Özet kaydedildi",
        summaryFallbackNote: "Bu Mac’te yerel olarak oluşturuldu.",
        dictationSectionHeader: "Sistem genelinde dikte",
        dictationTitle: "Sesli dikte",
        dictationToggle: "Sistem genelinde dikteyi etkinleştir",
        dictationCaption: "Herhangi bir uygulamada kısayola basarak Parakeet Unified English 0.6B ile konuşun, ardından metni imlece eklemek için tekrar basın.",
        dictationShortcutLabel: "Dikte kısayolu",
        startDictationButton: "Dikte et",
        stopDictationButton: "Durdur",
        dictatingStatusFormat: "Dinleniyor… %@",
        dictationListeningHUD: "Dinleniyor… eklemek için kısayola tekrar basın",
        dictationInsertedHUD: "Dikte eklendi",
        dictationCopiedHUD: "Dikte panoya kopyalandı",
        dictationModelMissingHUD: "Önce Transkripsiyon bölümünden Parakeet 0.6B modelini indirin",
        dictationMicDeniedError: "Sesli dikte için mikrofon izni gereklidir.",
        dictationAccessibilityHint: "İmlece doğrudan eklemek için Erişilebilirlik izni verin; izin yoksa panoya kopyalanır."
    )

    static let ru = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Краткое содержание",
        summaryToggle: "Создавать краткое содержание",
        summaryCaption: "Автоматически подводит итоги готовых расшифровок локально по вашему промпту и сохраняет файл рядом с текстом.",
        summaryPromptLabel: "Промпт для резюме",
        resetPromptButton: "Сбросить промпт",
        summarizeButton: "Резюмировать",
        regenerateSummaryButton: "Обновить",
        summarizingStatus: "Создание резюме…",
        summaryTitle: "Резюме",
        copySummaryButton: "Копировать резюме",
        saveSummaryButton: "Сохранить резюме…",
        summaryCopiedHUD: "Резюме скопировано",
        summarySavedHUD: "Резюме сохранено",
        summaryFallbackNote: "Создано локально на устройстве.",
        dictationSectionHeader: "Системная диктовка",
        dictationTitle: "Голосовая диктовка",
        dictationToggle: "Включить системную диктовку",
        dictationCaption: "Нажмите сочетание клавиш в любом приложении, чтобы продиктовать текст через Parakeet Unified English 0.6B, и нажмите снова для вставки в позицию курсора.",
        dictationShortcutLabel: "Сочетание диктовки",
        startDictationButton: "Диктовать",
        stopDictationButton: "Стоп",
        dictatingStatusFormat: "Слушаю… %@",
        dictationListeningHUD: "Слушаю… нажмите сочетание снова для вставки",
        dictationInsertedHUD: "Текст вставлен",
        dictationCopiedHUD: "Диктовка скопирована в буфер обмена",
        dictationModelMissingHUD: "Сначала загрузите Parakeet 0.6B в разделе Расшифровка",
        dictationMicDeniedError: "Для голосовой диктовки нужен доступ к микрофону.",
        dictationAccessibilityHint: "Предоставьте доступ в Универсальном доступе для прямой вставки; иначе текст копируется в буфер."
    )

    static let de = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Zusammenfassung",
        summaryToggle: "Zusammenfassung erstellen",
        summaryCaption: "Fasst fertige Transkripte automatisch lokal mit deinem eigenen Prompt zusammen und speichert die Zusammenfassung daneben.",
        summaryPromptLabel: "Prompt für Zusammenfassung",
        resetPromptButton: "Prompt zurücksetzen",
        summarizeButton: "Zusammenfassen",
        regenerateSummaryButton: "Neu erstellen",
        summarizingStatus: "Wird zusammengefasst…",
        summaryTitle: "Zusammenfassung",
        copySummaryButton: "Zusammenfassung kopieren",
        saveSummaryButton: "Zusammenfassung sichern…",
        summaryCopiedHUD: "Zusammenfassung kopiert",
        summarySavedHUD: "Zusammenfassung gesichert",
        summaryFallbackNote: "Lokal auf diesem Mac erstellt.",
        dictationSectionHeader: "Systemweites Diktieren",
        dictationTitle: "Sprachdiktat",
        dictationToggle: "Systemweites Diktieren aktivieren",
        dictationCaption: "Drücke den Kurzbefehl in beliebigen Apps, um mit Parakeet Unified English 0.6B zu sprechen, und drücke erneut, um den Text am Cursor einzufügen.",
        dictationShortcutLabel: "Kurzbefehl zum Diktieren",
        startDictationButton: "Diktieren",
        stopDictationButton: "Stopp",
        dictatingStatusFormat: "Hört zu… %@",
        dictationListeningHUD: "Hört zu… Kurzbefehl erneut drücken zum Einfügen",
        dictationInsertedHUD: "Diktat eingefügt",
        dictationCopiedHUD: "Diktat in die Zwischenablage kopiert",
        dictationModelMissingHUD: "Lade zuerst Parakeet 0.6B in den Transkriptions-Einstellungen",
        dictationMicDeniedError: "Für das Sprachdiktat ist Mikrofonzugriff erforderlich.",
        dictationAccessibilityHint: "Erlaube Bedienungshilfen für direktes Einfügen am Cursor; andernfalls wird in die Zwischenablage kopiert."
    )

    static let fr = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Résumé",
        summaryToggle: "Générer un résumé",
        summaryCaption: "Résume automatiquement les transcriptions terminées en local avec votre prompt personnalisé et enregistre un résumé à côté.",
        summaryPromptLabel: "Prompt de résumé",
        resetPromptButton: "Réinitialiser le prompt",
        summarizeButton: "Résumer",
        regenerateSummaryButton: "Régénérer",
        summarizingStatus: "Résumé en cours…",
        summaryTitle: "Résumé",
        copySummaryButton: "Copier le résumé",
        saveSummaryButton: "Enregistrer le résumé…",
        summaryCopiedHUD: "Résumé copié",
        summarySavedHUD: "Résumé enregistré",
        summaryFallbackNote: "Généré localement sur ce Mac.",
        dictationSectionHeader: "Dictée système",
        dictationTitle: "Dictée vocale",
        dictationToggle: "Activer la dictée dans tout le système",
        dictationCaption: "Appuyez sur le raccourci dans n’importe quelle app pour dicter avec Parakeet Unified English 0.6B, puis appuyez de nouveau pour insérer le texte au curseur.",
        dictationShortcutLabel: "Raccourci de dictée",
        startDictationButton: "Dicter",
        stopDictationButton: "Arrêter",
        dictatingStatusFormat: "Écoute… %@",
        dictationListeningHUD: "Écoute… appuyez à nouveau pour insérer",
        dictationInsertedHUD: "Dictée insérée",
        dictationCopiedHUD: "Dictée copiée dans le presse-papiers",
        dictationModelMissingHUD: "Téléchargez d’abord Parakeet 0.6B dans Transcription",
        dictationMicDeniedError: "L’autorisation du microphone est requise pour la dictée vocale.",
        dictationAccessibilityHint: "Accordez l’Accessibilité pour insérer directement au curseur; sinon, le texte est copié."
    )

    static let it = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Riepilogo",
        summaryToggle: "Genera riepilogo",
        summaryCaption: "Riassume automaticamente le trascrizioni completate in locale usando il tuo prompt personalizzato e salva il riepilogo accanto al testo.",
        summaryPromptLabel: "Prompt del riepilogo",
        resetPromptButton: "Ripristina prompt",
        summarizeButton: "Riassumi",
        regenerateSummaryButton: "Rigenera",
        summarizingStatus: "Creazione riepilogo…",
        summaryTitle: "Riepilogo",
        copySummaryButton: "Copia riepilogo",
        saveSummaryButton: "Salva riepilogo…",
        summaryCopiedHUD: "Riepilogo copiato",
        summarySavedHUD: "Riepilogo salvato",
        summaryFallbackNote: "Generato localmente su questo Mac.",
        dictationSectionHeader: "Dettatura di sistema",
        dictationTitle: "Dettatura vocale",
        dictationToggle: "Abilita dettatura di sistema",
        dictationCaption: "Premi la scorciatoia in qualsiasi app per dettare con Parakeet Unified English 0.6B, poi premila di nuovo per inserire il testo al cursore.",
        dictationShortcutLabel: "Scorciatoia dettatura",
        startDictationButton: "Detta",
        stopDictationButton: "Ferma",
        dictatingStatusFormat: "In ascolto… %@",
        dictationListeningHUD: "In ascolto… premi di nuovo la scorciatoia per inserire",
        dictationInsertedHUD: "Dettatura inserita",
        dictationCopiedHUD: "Dettatura copiata negli appunti",
        dictationModelMissingHUD: "Scarica prima Parakeet 0.6B nelle impostazioni di Trascrizione",
        dictationMicDeniedError: "È necessaria l’autorizzazione del microfono per la dettatura vocale.",
        dictationAccessibilityHint: "Concedi Accessibilità per inserire direttamente al cursore; altrimenti il testo viene copiato."
    )

    static let ja = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "要約",
        summaryToggle: "要約を生成",
        summaryCaption: "完了した文字起こしをカスタムプロンプトでローカル要約し、文字起こしの隣に保存します。",
        summaryPromptLabel: "要約プロンプト",
        resetPromptButton: "プロンプトをリセット",
        summarizeButton: "要約する",
        regenerateSummaryButton: "再生成",
        summarizingStatus: "要約中…",
        summaryTitle: "要約",
        copySummaryButton: "要約をコピー",
        saveSummaryButton: "要約を保存…",
        summaryCopiedHUD: "要約をコピーしました",
        summarySavedHUD: "要約を保存しました",
        summaryFallbackNote: "この Mac 上でローカル生成されました。",
        dictationSectionHeader: "システム全体の音声入力",
        dictationTitle: "音声入力",
        dictationToggle: "システム全体の音声入力を有効にする",
        dictationCaption: "どのアプリでもショートカットを押して Parakeet Unified English 0.6B で話し、もう一度押すとカーソル位置に挿入します。",
        dictationShortcutLabel: "音声入力ショートカット",
        startDictationButton: "音声入力",
        stopDictationButton: "停止",
        dictatingStatusFormat: "聞き取り中… %@",
        dictationListeningHUD: "聞き取り中… もう一度ショートカットを押して挿入",
        dictationInsertedHUD: "音声入力を挿入しました",
        dictationCopiedHUD: "音声入力をクリップボードにコピーしました",
        dictationModelMissingHUD: "先に文字起こし設定で Parakeet 0.6B をダウンロードしてください",
        dictationMicDeniedError: "音声入力にはマイクのアクセス許可が必要です。",
        dictationAccessibilityHint: "カーソル位置へ直接挿入するにはアクセシビリティ許可が必要です。未許可時はクリップボードにコピーされます。"
    )

    static let ko = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "요약",
        summaryToggle: "요약 생성",
        summaryCaption: "완료된 전사 내용을 사용자 지정 프롬프트로 로컬에서 자동 요약하고 전사 파일 옆에 저장합니다.",
        summaryPromptLabel: "요약 프롬프트",
        resetPromptButton: "프롬프트 재설정",
        summarizeButton: "요약하기",
        regenerateSummaryButton: "다시 생성",
        summarizingStatus: "요약 중…",
        summaryTitle: "요약",
        copySummaryButton: "요약 복사",
        saveSummaryButton: "요약 저장…",
        summaryCopiedHUD: "요약이 복사되었습니다",
        summarySavedHUD: "요약이 저장되었습니다",
        summaryFallbackNote: "이 Mac에서 로컬로 생성되었습니다.",
        dictationSectionHeader: "시스템 전역 받아쓰기",
        dictationTitle: "음성 받아쓰기",
        dictationToggle: "시스템 전역 받아쓰기 활성화",
        dictationCaption: "어느 앱에서든 단축키를 눌러 Parakeet Unified English 0.6B로 말하고, 다시 눌러 커서 위치에 텍스트를 삽입합니다.",
        dictationShortcutLabel: "받아쓰기 단축키",
        startDictationButton: "받아쓰기",
        stopDictationButton: "중지",
        dictatingStatusFormat: "듣는 중… %@",
        dictationListeningHUD: "듣는 중… 단축키를 다시 눌러 삽입",
        dictationInsertedHUD: "받아쓰기가 삽입되었습니다",
        dictationCopiedHUD: "받아쓰기가 클립보드에 복사되었습니다",
        dictationModelMissingHUD: "먼저 전사 설정에서 Parakeet 0.6B 모델을 다운로드하세요",
        dictationMicDeniedError: "음성 받아쓰기를 사용하려면 마이크 권한이 필요합니다.",
        dictationAccessibilityHint: "커서에 바로 삽입하려면 손쉬운 사용 권한을 허용하세요. 권한이 없으면 클립보드에 복사됩니다."
    )

    static let uk = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "Підсумок",
        summaryToggle: "Створювати підсумок",
        summaryCaption: "Автоматично підсумовує готові розшифровки локально за вашим промптом і зберігає підсумок поруч із текстом.",
        summaryPromptLabel: "Промпт для підсумку",
        resetPromptButton: "Скинути промпт",
        summarizeButton: "Підсумувати",
        regenerateSummaryButton: "Перегенерувати",
        summarizingStatus: "Створення підсумку…",
        summaryTitle: "Підсумок",
        copySummaryButton: "Копіювати підсумок",
        saveSummaryButton: "Зберегти підсумок…",
        summaryCopiedHUD: "Підсумок скопійовано",
        summarySavedHUD: "Підсумок збережено",
        summaryFallbackNote: "Створено локально на цьому Mac.",
        dictationSectionHeader: "Системне диктування",
        dictationTitle: "Голосове диктування",
        dictationToggle: "Увімкнути системне диктування",
        dictationCaption: "Натисніть комбінацію клавіш у будь-якій програмі, щоб продиктувати текст через Parakeet Unified English 0.6B, і натисніть знову для вставлення у позицію курсора.",
        dictationShortcutLabel: "Комбінація диктування",
        startDictationButton: "Диктувати",
        stopDictationButton: "Зупинити",
        dictatingStatusFormat: "Слухаю… %@",
        dictationListeningHUD: "Слухаю… натисніть комбінацію знову для вставлення",
        dictationInsertedHUD: "Диктування вставлено",
        dictationCopiedHUD: "Диктування скопійовано в буфер обміну",
        dictationModelMissingHUD: "Спочатку завантажте Parakeet 0.6B у налаштуваннях Розшифровки",
        dictationMicDeniedError: "Для голосового диктування потрібен дозвіл на мікрофон.",
        dictationAccessibilityHint: "Надайте дозвіл Спеціальних можливостей для прямого вставлення; інакше текст копіюється в буфер."
    )

    static let zhHans = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "摘要",
        summaryToggle: "生成摘要",
        summaryCaption: "使用你的自定义提示词在本地自动总结已完成的转写内容，并将摘要保存在转写文件旁。",
        summaryPromptLabel: "摘要提示词",
        resetPromptButton: "重置提示词",
        summarizeButton: "生成摘要",
        regenerateSummaryButton: "重新生成",
        summarizingStatus: "正在生成摘要…",
        summaryTitle: "摘要",
        copySummaryButton: "复制摘要",
        saveSummaryButton: "保存摘要…",
        summaryCopiedHUD: "摘要已复制",
        summarySavedHUD: "摘要已保存",
        summaryFallbackNote: "已在本机本地生成。",
        dictationSectionHeader: "系统级语音听写",
        dictationTitle: "语音听写",
        dictationToggle: "启用系统级语音听写",
        dictationCaption: "在任意 App 中按下快捷键即可通过 Parakeet Unified English 0.6B 语音输入，再次按下即可将文本插入光标处。",
        dictationShortcutLabel: "听写快捷键",
        startDictationButton: "听写",
        stopDictationButton: "停止",
        dictatingStatusFormat: "正在聆听… %@",
        dictationListeningHUD: "正在聆听… 再次按下快捷键插入文本",
        dictationInsertedHUD: "听写内容已插入",
        dictationCopiedHUD: "听写内容已复制到剪贴板",
        dictationModelMissingHUD: "请先在音频转写设置中下载 Parakeet 0.6B 模型",
        dictationMicDeniedError: "语音听写需要麦克风权限。",
        dictationAccessibilityHint: "授予辅助功能权限即可直接插入光标处；未授予时将复制到剪贴板。"
    )

    static let zhTW = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "摘要",
        summaryToggle: "產生摘要",
        summaryCaption: "使用你的自訂提示詞在本機自動整理完成的轉錄內容，並將摘要儲存在轉錄檔旁。",
        summaryPromptLabel: "摘要提示詞",
        resetPromptButton: "重設提示詞",
        summarizeButton: "產生摘要",
        regenerateSummaryButton: "重新產生",
        summarizingStatus: "正在產生摘要…",
        summaryTitle: "摘要",
        copySummaryButton: "複製摘要",
        saveSummaryButton: "儲存摘要…",
        summaryCopiedHUD: "摘要已複製",
        summarySavedHUD: "摘要已儲存",
        summaryFallbackNote: "已在此 Mac 本機產生。",
        dictationSectionHeader: "系統全域語音聽寫",
        dictationTitle: "語音聽寫",
        dictationToggle: "啟用系統全域語音聽寫",
        dictationCaption: "在任何 App 中按下快速鍵即可透過 Parakeet Unified English 0.6B 口述，再按一次即可將文字插入游標處。",
        dictationShortcutLabel: "聽寫快速鍵",
        startDictationButton: "聽寫",
        stopDictationButton: "停止",
        dictatingStatusFormat: "正在聆聽… %@",
        dictationListeningHUD: "正在聆聽… 再按一次快速鍵以插入",
        dictationInsertedHUD: "聽寫文字已插入",
        dictationCopiedHUD: "聽寫文字已複製到剪貼簿",
        dictationModelMissingHUD: "請先在音訊轉錄設定中下載 Parakeet 0.6B 模型",
        dictationMicDeniedError: "語音聽寫需要麥克風權限。",
        dictationAccessibilityHint: "授予輔助使用權限即可直接插入游標處；未授予時會複製到剪貼簿。"
    )

    static let zhHK = AudioTranscriptionExtrasStrings(
        summarySectionHeader: "摘要",
        summaryToggle: "產生摘要",
        summaryCaption: "用你嘅自訂提示詞喺本機自動整理完成嘅轉錄內容，並將摘要儲存喺轉錄檔隔離。",
        summaryPromptLabel: "摘要提示詞",
        resetPromptButton: "重設提示詞",
        summarizeButton: "產生摘要",
        regenerateSummaryButton: "重新產生",
        summarizingStatus: "正在產生摘要…",
        summaryTitle: "摘要",
        copySummaryButton: "複製摘要",
        saveSummaryButton: "儲存摘要…",
        summaryCopiedHUD: "摘要已複製",
        summarySavedHUD: "摘要已儲存",
        summaryFallbackNote: "已喺呢部 Mac 本機產生。",
        dictationSectionHeader: "系統全域語音聽寫",
        dictationTitle: "語音聽寫",
        dictationToggle: "啟用系統全域語音聽寫",
        dictationCaption: "喺任何 App 按快速鍵即可用 Parakeet Unified English 0.6B 講嘢，再按一次就會將文字插入游標位置。",
        dictationShortcutLabel: "聽寫快速鍵",
        startDictationButton: "聽寫",
        stopDictationButton: "停止",
        dictatingStatusFormat: "正在聆聽… %@",
        dictationListeningHUD: "正在聆聽… 再按一次快速鍵插入",
        dictationInsertedHUD: "聽寫文字已插入",
        dictationCopiedHUD: "聽寫文字已複製到剪貼簿",
        dictationModelMissingHUD: "請先喺音訊轉錄設定下載 Parakeet 0.6B 模型",
        dictationMicDeniedError: "語音聽寫需要咪高峰權限。",
        dictationAccessibilityHint: "授予輔助使用權限即可直接插入游標位置；未授予時會複製到剪貼簿。"
    )
}
