// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DictationFeatureStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let intro: String
    let shortcut: String
    let provider: String
    let openAI: String
    let groq: String
    let model: String
    let apiKey: String
    let saveKey: String
    let removeKey: String
    let keySaved: String
    let keyRemoved: String
    let testConfiguration: String
    let testing: String
    let testSucceeded: String
    let externalWarning: String
    let microphoneNote: String
    let listening: String
    let processing: String
    let stopHint: String
    let cancelHint: String
    let openSettings: String
    let missingKey: String
    let keychainError: String
    let microphoneDenied: String
    let microphoneUnavailable: String
    let audioTooLarge: String
    let noSpeech: String
    let invalidKey: String
    let rateLimited: String
    let networkError: String
    let serverError: String
    let requestRejected: String
    let invalidResponse: String
    let accessibilityCopied: String
    let focusChangedCopied: String
    let pasteFailedCopied: String

    func providerName(_ provider: DictationProvider) -> String {
        provider == .openAI ? openAI : groq
    }

    func failureMessage(_ failure: DictationFailure) -> String {
        switch failure {
        case .missingKey: return missingKey
        case .keychain: return keychainError
        case .microphoneDenied: return microphoneDenied
        case .microphoneUnavailable: return microphoneUnavailable
        case .audioTooLarge: return audioTooLarge
        case .noSpeech: return noSpeech
        case .invalidKey: return invalidKey
        case .rateLimited: return rateLimited
        case .network: return networkError
        case .server: return serverError
        case .requestRejected: return requestRejected
        case .invalidResponse: return invalidResponse
        case .accessibilityRequiredCopied: return accessibilityCopied
        case .focusChangedCopied: return focusChangedCopied
        case .pasteFailedCopied: return pasteFailedCopied
        case .cancelled: return cancelHint
        }
    }
}

extension FeatureStrings {
    static func dictation(_ language: AppLanguage) -> DictationFeatureStrings {
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

extension DictationFeatureStrings {
    static let enUS = DictationFeatureStrings(
        title: "Dictation", hubDescription: "Types what you say into the field you were using",
        enable: "Enable dictation", intro: "Press the shortcut, speak, then press it again to transcribe and type.",
        shortcut: "Dictation shortcut", provider: "Provider", openAI: "OpenAI", groq: "Groq", model: "Model",
        apiKey: "API key", saveKey: "Save key", removeKey: "Remove key", keySaved: "Key saved in Keychain",
        keyRemoved: "Key removed", testConfiguration: "Test configuration", testing: "Testing…",
        testSucceeded: "Configuration works", externalWarning: "Your recording is sent to the selected provider for transcription. It is deleted from this Mac as soon as the request ends.",
        microphoneNote: "The default microphone is used only while the listening indicator is visible.",
        listening: "Listening…", processing: "Transcribing…", stopHint: "Press the shortcut again to stop",
        cancelHint: "Press Esc to cancel", openSettings: "Open System Settings",
        missingKey: "Save an API key for the selected provider first.", keychainError: "The API key could not be read from Keychain.",
        microphoneDenied: "Microphone access is turned off.", microphoneUnavailable: "The default microphone could not be recorded.",
        audioTooLarge: "The recording is too large to transcribe.", noSpeech: "No speech was detected.",
        invalidKey: "The provider rejected the API key.", rateLimited: "The provider rate limit was reached. Try again later.",
        networkError: "The provider could not be reached.", serverError: "The provider had a server error. Try again later.",
        requestRejected: "The provider rejected this transcription request.", invalidResponse: "The provider returned an invalid response.",
        accessibilityCopied: "Accessibility is off, so the transcription was copied. Paste it with Command-V.",
        focusChangedCopied: "The active field changed, so the transcription was copied. Paste it where you want it.",
        pasteFailedCopied: "The text could not be pasted, so the transcription was copied."
    )

    static let ptBR = DictationFeatureStrings(
        title: "Ditado", hubDescription: "Digita o que você fala no campo que estava usando",
        enable: "Ativar ditado", intro: "Pressione o atalho, fale e pressione de novo para transcrever e digitar.",
        shortcut: "Atalho do ditado", provider: "Provedor", openAI: "OpenAI", groq: "Groq", model: "Modelo",
        apiKey: "Chave de API", saveKey: "Salvar chave", removeKey: "Remover chave", keySaved: "Chave salva com segurança no Mac",
        keyRemoved: "Chave removida", testConfiguration: "Testar configuração", testing: "Testando…",
        testSucceeded: "A configuração funciona", externalWarning: "Sua gravação é enviada ao provedor selecionado para transcrição. Ela é apagada deste Mac assim que a solicitação termina.",
        microphoneNote: "O microfone padrão é usado somente enquanto o indicador de escuta está visível.",
        listening: "Ouvindo…", processing: "Transcrevendo…", stopHint: "Pressione o atalho de novo para parar",
        cancelHint: "Pressione Esc para cancelar", openSettings: "Abrir Ajustes do Sistema",
        missingKey: "Salve primeiro uma chave de API para o provedor selecionado.", keychainError: "Não foi possível ler a chave de API nas Chaves.",
        microphoneDenied: "O acesso ao microfone está desativado.", microphoneUnavailable: "Não foi possível gravar o microfone padrão.",
        audioTooLarge: "A gravação é grande demais para transcrever.", noSpeech: "Nenhuma fala foi detectada.",
        invalidKey: "O provedor recusou a chave de API.", rateLimited: "O limite do provedor foi atingido. Tente mais tarde.",
        networkError: "Não foi possível acessar o provedor.", serverError: "O provedor apresentou um erro de servidor. Tente mais tarde.",
        requestRejected: "O provedor recusou esta solicitação de transcrição.", invalidResponse: "O provedor retornou uma resposta inválida.",
        accessibilityCopied: "A Acessibilidade está desativada, então a transcrição foi copiada. Cole com Command-V.",
        focusChangedCopied: "O campo ativo mudou, então a transcrição foi copiada. Cole onde quiser.",
        pasteFailedCopied: "Não foi possível colar o texto, então a transcrição foi copiada."
    )

    static let tr = DictationFeatureStrings(
        title: "Dikte", hubDescription: "Söylediklerinizi kullandığınız alana yazar",
        enable: "Dikteyi etkinleştir", intro: "Kısayola basın, konuşun ve yazıya döküp yazmak için tekrar basın.",
        shortcut: "Dikte kısayolu", provider: "Sağlayıcı", openAI: "OpenAI", groq: "Groq", model: "Model",
        apiKey: "API anahtarı", saveKey: "Anahtarı kaydet", removeKey: "Anahtarı kaldır", keySaved: "Anahtar Anahtar Zinciri'ne kaydedildi",
        keyRemoved: "Anahtar kaldırıldı", testConfiguration: "Yapılandırmayı test et", testing: "Test ediliyor…",
        testSucceeded: "Yapılandırma çalışıyor", externalWarning: "Kaydınız yazıya dökülmek üzere seçilen sağlayıcıya gönderilir. İstek biter bitmez bu Mac'ten silinir.",
        microphoneNote: "Varsayılan mikrofon yalnızca dinleme göstergesi görünürken kullanılır.",
        listening: "Dinleniyor…", processing: "Yazıya dökülüyor…", stopHint: "Durdurmak için kısayola tekrar basın",
        cancelHint: "İptal etmek için Esc'ye basın", openSettings: "Sistem Ayarları'nı aç",
        missingKey: "Önce seçilen sağlayıcı için bir API anahtarı kaydedin.", keychainError: "API anahtarı Anahtar Zinciri'nden okunamadı.",
        microphoneDenied: "Mikrofon erişimi kapalı.", microphoneUnavailable: "Varsayılan mikrofon kaydedilemedi.",
        audioTooLarge: "Kayıt yazıya dökmek için çok büyük.", noSpeech: "Konuşma algılanmadı.",
        invalidKey: "Sağlayıcı API anahtarını reddetti.", rateLimited: "Sağlayıcı hız sınırına ulaşıldı. Daha sonra tekrar deneyin.",
        networkError: "Sağlayıcıya ulaşılamadı.", serverError: "Sağlayıcıda sunucu hatası oluştu. Daha sonra tekrar deneyin.",
        requestRejected: "Sağlayıcı bu yazıya dökme isteğini reddetti.", invalidResponse: "Sağlayıcı geçersiz bir yanıt döndürdü.",
        accessibilityCopied: "Erişilebilirlik kapalı olduğu için metin kopyalandı. Command-V ile yapıştırın.",
        focusChangedCopied: "Etkin alan değiştiği için metin kopyalandı. İstediğiniz yere yapıştırın.",
        pasteFailedCopied: "Metin yapıştırılamadı, bu yüzden kopyalandı."
    )

    static let ru = DictationFeatureStrings(
        title: "Диктовка", hubDescription: "Вводит произнесённое в поле, которым вы пользовались",
        enable: "Включить диктовку", intro: "Нажмите сочетание, говорите и нажмите его снова для распознавания и ввода.",
        shortcut: "Сочетание для диктовки", provider: "Провайдер", openAI: "OpenAI", groq: "Groq", model: "Модель",
        apiKey: "Ключ API", saveKey: "Сохранить ключ", removeKey: "Удалить ключ", keySaved: "Ключ сохранён в Связке ключей",
        keyRemoved: "Ключ удалён", testConfiguration: "Проверить настройку", testing: "Проверка…",
        testSucceeded: "Настройка работает", externalWarning: "Запись отправляется выбранному провайдеру для распознавания. Она удаляется с этого Mac сразу после завершения запроса.",
        microphoneNote: "Микрофон по умолчанию используется только пока виден индикатор прослушивания.",
        listening: "Слушаю…", processing: "Распознавание…", stopHint: "Нажмите сочетание снова, чтобы остановить",
        cancelHint: "Нажмите Esc для отмены", openSettings: "Открыть Системные настройки",
        missingKey: "Сначала сохраните ключ API выбранного провайдера.", keychainError: "Не удалось прочитать ключ API из Связки ключей.",
        microphoneDenied: "Доступ к микрофону отключён.", microphoneUnavailable: "Не удалось записать микрофон по умолчанию.",
        audioTooLarge: "Запись слишком велика для распознавания.", noSpeech: "Речь не обнаружена.",
        invalidKey: "Провайдер отклонил ключ API.", rateLimited: "Достигнут лимит запросов провайдера. Повторите позже.",
        networkError: "Не удалось связаться с провайдером.", serverError: "Ошибка сервера провайдера. Повторите позже.",
        requestRejected: "Провайдер отклонил запрос на распознавание.", invalidResponse: "Провайдер вернул недопустимый ответ.",
        accessibilityCopied: "Универсальный доступ выключен, поэтому текст скопирован. Вставьте его через Command-V.",
        focusChangedCopied: "Активное поле изменилось, поэтому текст скопирован. Вставьте его куда нужно.",
        pasteFailedCopied: "Не удалось вставить текст, поэтому он скопирован."
    )

    static let es = DictationFeatureStrings(
        title: "Dictado", hubDescription: "Escribe lo que dices en el campo que estabas usando",
        enable: "Activar dictado", intro: "Pulsa el atajo, habla y vuelve a pulsarlo para transcribir y escribir.",
        shortcut: "Atajo de dictado", provider: "Proveedor", openAI: "OpenAI", groq: "Groq", model: "Modelo",
        apiKey: "Clave de API", saveKey: "Guardar clave", removeKey: "Eliminar clave", keySaved: "Clave guardada en el Llavero",
        keyRemoved: "Clave eliminada", testConfiguration: "Probar configuración", testing: "Probando…",
        testSucceeded: "La configuración funciona", externalWarning: "Tu grabación se envía al proveedor seleccionado para transcribirla. Se elimina de este Mac en cuanto termina la solicitud.",
        microphoneNote: "El micrófono predeterminado solo se usa mientras se muestra el indicador de escucha.",
        listening: "Escuchando…", processing: "Transcribiendo…", stopHint: "Pulsa el atajo otra vez para detener",
        cancelHint: "Pulsa Esc para cancelar", openSettings: "Abrir Ajustes del Sistema",
        missingKey: "Primero guarda una clave de API para el proveedor seleccionado.", keychainError: "No se pudo leer la clave de API del Llavero.",
        microphoneDenied: "El acceso al micrófono está desactivado.", microphoneUnavailable: "No se pudo grabar el micrófono predeterminado.",
        audioTooLarge: "La grabación es demasiado grande para transcribirla.", noSpeech: "No se detectó voz.",
        invalidKey: "El proveedor rechazó la clave de API.", rateLimited: "Se alcanzó el límite del proveedor. Inténtalo más tarde.",
        networkError: "No se pudo contactar con el proveedor.", serverError: "El proveedor tuvo un error de servidor. Inténtalo más tarde.",
        requestRejected: "El proveedor rechazó esta solicitud de transcripción.", invalidResponse: "El proveedor devolvió una respuesta no válida.",
        accessibilityCopied: "Accesibilidad está desactivada, así que se copió la transcripción. Pégala con Command-V.",
        focusChangedCopied: "El campo activo cambió, así que se copió la transcripción. Pégala donde quieras.",
        pasteFailedCopied: "No se pudo pegar el texto, así que se copió la transcripción."
    )

    static let de = DictationFeatureStrings(
        title: "Diktat", hubDescription: "Tippt Gesprochenes in das zuvor verwendete Feld",
        enable: "Diktat aktivieren", intro: "Drücke das Tastenkürzel, sprich und drücke es erneut zum Transkribieren und Einfügen.",
        shortcut: "Diktat-Tastenkürzel", provider: "Anbieter", openAI: "OpenAI", groq: "Groq", model: "Modell",
        apiKey: "API-Schlüssel", saveKey: "Schlüssel sichern", removeKey: "Schlüssel entfernen", keySaved: "Schlüssel im Schlüsselbund gesichert",
        keyRemoved: "Schlüssel entfernt", testConfiguration: "Konfiguration testen", testing: "Wird getestet…",
        testSucceeded: "Konfiguration funktioniert", externalWarning: "Deine Aufnahme wird zur Transkription an den gewählten Anbieter gesendet. Nach Ende der Anfrage wird sie sofort von diesem Mac gelöscht.",
        microphoneNote: "Das Standardmikrofon wird nur verwendet, solange die Höranzeige sichtbar ist.",
        listening: "Hört zu…", processing: "Wird transkribiert…", stopHint: "Zum Stoppen das Tastenkürzel erneut drücken",
        cancelHint: "Zum Abbrechen Esc drücken", openSettings: "Systemeinstellungen öffnen",
        missingKey: "Speichere zuerst einen API-Schlüssel für den gewählten Anbieter.", keychainError: "Der API-Schlüssel konnte nicht aus dem Schlüsselbund gelesen werden.",
        microphoneDenied: "Der Mikrofonzugriff ist deaktiviert.", microphoneUnavailable: "Das Standardmikrofon konnte nicht aufgenommen werden.",
        audioTooLarge: "Die Aufnahme ist zu groß zum Transkribieren.", noSpeech: "Keine Sprache erkannt.",
        invalidKey: "Der Anbieter hat den API-Schlüssel abgelehnt.", rateLimited: "Das Anfragelimit des Anbieters ist erreicht. Versuche es später erneut.",
        networkError: "Der Anbieter konnte nicht erreicht werden.", serverError: "Serverfehler beim Anbieter. Versuche es später erneut.",
        requestRejected: "Der Anbieter hat diese Transkriptionsanfrage abgelehnt.", invalidResponse: "Der Anbieter hat eine ungültige Antwort geliefert.",
        accessibilityCopied: "Bedienungshilfen sind aus, daher wurde der Text kopiert. Füge ihn mit Command-V ein.",
        focusChangedCopied: "Das aktive Feld hat sich geändert, daher wurde der Text kopiert. Füge ihn am gewünschten Ort ein.",
        pasteFailedCopied: "Der Text konnte nicht eingefügt werden und wurde daher kopiert."
    )

    static let fr = DictationFeatureStrings(
        title: "Dictée", hubDescription: "Saisit vos paroles dans le champ que vous utilisiez",
        enable: "Activer la dictée", intro: "Appuyez sur le raccourci, parlez, puis appuyez à nouveau pour transcrire et saisir.",
        shortcut: "Raccourci de dictée", provider: "Fournisseur", openAI: "OpenAI", groq: "Groq", model: "Modèle",
        apiKey: "Clé API", saveKey: "Enregistrer la clé", removeKey: "Supprimer la clé", keySaved: "Clé enregistrée dans le Trousseau",
        keyRemoved: "Clé supprimée", testConfiguration: "Tester la configuration", testing: "Test en cours…",
        testSucceeded: "La configuration fonctionne", externalWarning: "Votre enregistrement est envoyé au fournisseur sélectionné pour transcription. Il est supprimé de ce Mac dès la fin de la requête.",
        microphoneNote: "Le micro par défaut est utilisé uniquement tant que l’indicateur d’écoute est visible.",
        listening: "Écoute…", processing: "Transcription…", stopHint: "Appuyez à nouveau sur le raccourci pour arrêter",
        cancelHint: "Appuyez sur Esc pour annuler", openSettings: "Ouvrir Réglages Système",
        missingKey: "Enregistrez d’abord une clé API pour le fournisseur sélectionné.", keychainError: "Impossible de lire la clé API dans le Trousseau.",
        microphoneDenied: "L’accès au micro est désactivé.", microphoneUnavailable: "Impossible d’enregistrer le micro par défaut.",
        audioTooLarge: "L’enregistrement est trop volumineux pour être transcrit.", noSpeech: "Aucune parole détectée.",
        invalidKey: "Le fournisseur a refusé la clé API.", rateLimited: "La limite du fournisseur est atteinte. Réessayez plus tard.",
        networkError: "Impossible de joindre le fournisseur.", serverError: "Erreur de serveur du fournisseur. Réessayez plus tard.",
        requestRejected: "Le fournisseur a refusé cette demande de transcription.", invalidResponse: "Le fournisseur a renvoyé une réponse non valide.",
        accessibilityCopied: "Accessibilité est désactivée, la transcription a donc été copiée. Collez-la avec Command-V.",
        focusChangedCopied: "Le champ actif a changé, la transcription a donc été copiée. Collez-la où vous voulez.",
        pasteFailedCopied: "Le texte n’a pas pu être collé, la transcription a donc été copiée."
    )

    static let it = DictationFeatureStrings(
        title: "Dettatura", hubDescription: "Scrive ciò che dici nel campo che stavi usando",
        enable: "Attiva dettatura", intro: "Premi la scorciatoia, parla e premila di nuovo per trascrivere e scrivere.",
        shortcut: "Scorciatoia dettatura", provider: "Fornitore", openAI: "OpenAI", groq: "Groq", model: "Modello",
        apiKey: "Chiave API", saveKey: "Salva chiave", removeKey: "Rimuovi chiave", keySaved: "Chiave salvata nel Portachiavi",
        keyRemoved: "Chiave rimossa", testConfiguration: "Verifica configurazione", testing: "Verifica…",
        testSucceeded: "La configurazione funziona", externalWarning: "La registrazione viene inviata al fornitore selezionato per la trascrizione. Viene eliminata da questo Mac appena termina la richiesta.",
        microphoneNote: "Il microfono predefinito viene usato solo mentre l’indicatore di ascolto è visibile.",
        listening: "In ascolto…", processing: "Trascrizione…", stopHint: "Premi di nuovo la scorciatoia per fermare",
        cancelHint: "Premi Esc per annullare", openSettings: "Apri Impostazioni di Sistema",
        missingKey: "Prima salva una chiave API per il fornitore selezionato.", keychainError: "Impossibile leggere la chiave API dal Portachiavi.",
        microphoneDenied: "L’accesso al microfono è disattivato.", microphoneUnavailable: "Impossibile registrare il microfono predefinito.",
        audioTooLarge: "La registrazione è troppo grande da trascrivere.", noSpeech: "Nessun parlato rilevato.",
        invalidKey: "Il fornitore ha rifiutato la chiave API.", rateLimited: "Limite del fornitore raggiunto. Riprova più tardi.",
        networkError: "Impossibile raggiungere il fornitore.", serverError: "Errore del server del fornitore. Riprova più tardi.",
        requestRejected: "Il fornitore ha rifiutato la richiesta di trascrizione.", invalidResponse: "Il fornitore ha restituito una risposta non valida.",
        accessibilityCopied: "Accessibilità è disattivata, quindi la trascrizione è stata copiata. Incollala con Command-V.",
        focusChangedCopied: "Il campo attivo è cambiato, quindi la trascrizione è stata copiata. Incollala dove vuoi.",
        pasteFailedCopied: "Impossibile incollare il testo, quindi la trascrizione è stata copiata."
    )

    static let ja = DictationFeatureStrings(
        title: "音声入力", hubDescription: "話した内容を使用中だった入力欄に入力します",
        enable: "音声入力を有効にする", intro: "ショートカットを押して話し、もう一度押すと文字起こしして入力します。",
        shortcut: "音声入力のショートカット", provider: "プロバイダ", openAI: "OpenAI", groq: "Groq", model: "モデル",
        apiKey: "APIキー", saveKey: "キーを保存", removeKey: "キーを削除", keySaved: "キーをキーチェーンに保存しました",
        keyRemoved: "キーを削除しました", testConfiguration: "設定をテスト", testing: "テスト中…",
        testSucceeded: "設定は正常です", externalWarning: "録音は文字起こしのため選択したプロバイダへ送信されます。リクエスト完了後、直ちにこのMacから削除されます。",
        microphoneNote: "デフォルトのマイクは、聞き取りインジケータが表示されている間だけ使用されます。",
        listening: "聞き取り中…", processing: "文字起こし中…", stopHint: "停止するにはショートカットをもう一度押します",
        cancelHint: "Escキーでキャンセル", openSettings: "システム設定を開く",
        missingKey: "選択したプロバイダのAPIキーを先に保存してください。", keychainError: "キーチェーンからAPIキーを読み取れませんでした。",
        microphoneDenied: "マイクへのアクセスがオフです。", microphoneUnavailable: "デフォルトのマイクを録音できませんでした。",
        audioTooLarge: "録音が大きすぎて文字起こしできません。", noSpeech: "音声が検出されませんでした。",
        invalidKey: "プロバイダがAPIキーを拒否しました。", rateLimited: "プロバイダの利用制限に達しました。しばらくしてから再試行してください。",
        networkError: "プロバイダに接続できませんでした。", serverError: "プロバイダでサーバエラーが発生しました。しばらくしてから再試行してください。",
        requestRejected: "プロバイダが文字起こしリクエストを拒否しました。", invalidResponse: "プロバイダから無効な応答が返されました。",
        accessibilityCopied: "アクセシビリティがオフのため文字起こしをコピーしました。Command-Vで貼り付けてください。",
        focusChangedCopied: "入力欄が変わったため文字起こしをコピーしました。目的の場所に貼り付けてください。",
        pasteFailedCopied: "テキストを貼り付けられなかったため、文字起こしをコピーしました。"
    )

    static let ko = DictationFeatureStrings(
        title: "받아쓰기", hubDescription: "말한 내용을 사용하던 입력란에 입력합니다",
        enable: "받아쓰기 활성화", intro: "단축키를 누르고 말한 다음 다시 눌러 텍스트로 변환하고 입력하세요.",
        shortcut: "받아쓰기 단축키", provider: "제공업체", openAI: "OpenAI", groq: "Groq", model: "모델",
        apiKey: "API 키", saveKey: "키 저장", removeKey: "키 제거", keySaved: "키가 키체인에 저장됨",
        keyRemoved: "키가 제거됨", testConfiguration: "구성 테스트", testing: "테스트 중…",
        testSucceeded: "구성이 정상입니다", externalWarning: "녹음은 텍스트 변환을 위해 선택한 제공업체로 전송됩니다. 요청이 끝나면 이 Mac에서 즉시 삭제됩니다.",
        microphoneNote: "기본 마이크는 듣기 표시가 보이는 동안에만 사용됩니다.",
        listening: "듣는 중…", processing: "텍스트로 변환 중…", stopHint: "중지하려면 단축키를 다시 누르세요",
        cancelHint: "취소하려면 Esc를 누르세요", openSettings: "시스템 설정 열기",
        missingKey: "선택한 제공업체의 API 키를 먼저 저장하세요.", keychainError: "키체인에서 API 키를 읽을 수 없습니다.",
        microphoneDenied: "마이크 접근이 꺼져 있습니다.", microphoneUnavailable: "기본 마이크를 녹음할 수 없습니다.",
        audioTooLarge: "녹음이 너무 커서 변환할 수 없습니다.", noSpeech: "음성이 감지되지 않았습니다.",
        invalidKey: "제공업체가 API 키를 거부했습니다.", rateLimited: "제공업체 사용 한도에 도달했습니다. 나중에 다시 시도하세요.",
        networkError: "제공업체에 연결할 수 없습니다.", serverError: "제공업체 서버 오류입니다. 나중에 다시 시도하세요.",
        requestRejected: "제공업체가 변환 요청을 거부했습니다.", invalidResponse: "제공업체가 잘못된 응답을 반환했습니다.",
        accessibilityCopied: "손쉬운 사용이 꺼져 있어 변환 내용을 복사했습니다. Command-V로 붙여넣으세요.",
        focusChangedCopied: "활성 입력란이 바뀌어 변환 내용을 복사했습니다. 원하는 곳에 붙여넣으세요.",
        pasteFailedCopied: "텍스트를 붙여넣지 못해 변환 내용을 복사했습니다."
    )

    static let zhHans = DictationFeatureStrings(
        title: "听写", hubDescription: "将你说的话输入到刚才使用的文本框中",
        enable: "启用听写", intro: "按下快捷键并说话，再按一次即可转写并输入。",
        shortcut: "听写快捷键", provider: "服务商", openAI: "OpenAI", groq: "Groq", model: "模型",
        apiKey: "API 密钥", saveKey: "保存密钥", removeKey: "移除密钥", keySaved: "密钥已存入钥匙串",
        keyRemoved: "密钥已移除", testConfiguration: "测试配置", testing: "正在测试…",
        testSucceeded: "配置可用", externalWarning: "录音会发送给所选服务商进行转写。请求结束后会立即从这台 Mac 删除。",
        microphoneNote: "仅在显示聆听指示器时使用默认麦克风。",
        listening: "正在聆听…", processing: "正在转写…", stopHint: "再次按快捷键停止",
        cancelHint: "按 Esc 取消", openSettings: "打开系统设置",
        missingKey: "请先保存所选服务商的 API 密钥。", keychainError: "无法从钥匙串读取 API 密钥。",
        microphoneDenied: "麦克风访问已关闭。", microphoneUnavailable: "无法录制默认麦克风。",
        audioTooLarge: "录音太大，无法转写。", noSpeech: "未检测到语音。",
        invalidKey: "服务商拒绝了 API 密钥。", rateLimited: "已达到服务商的速率限制，请稍后再试。",
        networkError: "无法连接到服务商。", serverError: "服务商发生服务器错误，请稍后再试。",
        requestRejected: "服务商拒绝了本次转写请求。", invalidResponse: "服务商返回了无效响应。",
        accessibilityCopied: "辅助功能已关闭，因此转写内容已复制。请用 Command-V 粘贴。",
        focusChangedCopied: "活动文本框已改变，因此转写内容已复制。请粘贴到需要的位置。",
        pasteFailedCopied: "无法粘贴文本，因此转写内容已复制。"
    )

    static let zhTW = DictationFeatureStrings(
        title: "聽寫", hubDescription: "將你說的話輸入到剛才使用的文字欄位",
        enable: "啟用聽寫", intro: "按下快速鍵並說話，再按一次即可轉錄並輸入。",
        shortcut: "聽寫快速鍵", provider: "服務商", openAI: "OpenAI", groq: "Groq", model: "模型",
        apiKey: "API 金鑰", saveKey: "儲存金鑰", removeKey: "移除金鑰", keySaved: "金鑰已存入鑰匙圈",
        keyRemoved: "金鑰已移除", testConfiguration: "測試設定", testing: "正在測試…",
        testSucceeded: "設定可用", externalWarning: "錄音會傳送給所選服務商進行轉錄。要求結束後會立即從這台 Mac 刪除。",
        microphoneNote: "只有在顯示聆聽指示器時才會使用預設麥克風。",
        listening: "正在聆聽…", processing: "正在轉錄…", stopHint: "再次按快速鍵即可停止",
        cancelHint: "按 Esc 取消", openSettings: "打開系統設定",
        missingKey: "請先儲存所選服務商的 API 金鑰。", keychainError: "無法從鑰匙圈讀取 API 金鑰。",
        microphoneDenied: "麥克風取用權限已關閉。", microphoneUnavailable: "無法錄製預設麥克風。",
        audioTooLarge: "錄音太大，無法轉錄。", noSpeech: "未偵測到語音。",
        invalidKey: "服務商拒絕了 API 金鑰。", rateLimited: "已達服務商的速率限制，請稍後再試。",
        networkError: "無法連線到服務商。", serverError: "服務商發生伺服器錯誤，請稍後再試。",
        requestRejected: "服務商拒絕了這次轉錄要求。", invalidResponse: "服務商傳回了無效回應。",
        accessibilityCopied: "輔助使用已關閉，因此轉錄內容已複製。請用 Command-V 貼上。",
        focusChangedCopied: "使用中的文字欄位已改變，因此轉錄內容已複製。請貼到需要的位置。",
        pasteFailedCopied: "無法貼上文字，因此轉錄內容已複製。"
    )

    static let zhHK = DictationFeatureStrings(
        title: "聽寫", hubDescription: "將你講嘅內容輸入到啱啱使用嘅文字欄位",
        enable: "啟用聽寫", intro: "按快速鍵並講話，再按一次即可轉錄及輸入。",
        shortcut: "聽寫快速鍵", provider: "服務商", openAI: "OpenAI", groq: "Groq", model: "模型",
        apiKey: "API 金鑰", saveKey: "儲存金鑰", removeKey: "移除金鑰", keySaved: "金鑰已存入鑰匙圈",
        keyRemoved: "金鑰已移除", testConfiguration: "測試設定", testing: "測試中…",
        testSucceeded: "設定可用", externalWarning: "錄音會傳送畀所選服務商進行轉錄。要求完成後會立即從呢部 Mac 刪除。",
        microphoneNote: "只會喺顯示聆聽指示器期間使用預設咪高風。",
        listening: "聆聽中…", processing: "轉錄中…", stopHint: "再按一次快速鍵即可停止",
        cancelHint: "按 Esc 取消", openSettings: "開啟系統設定",
        missingKey: "請先儲存所選服務商嘅 API 金鑰。", keychainError: "無法從鑰匙圈讀取 API 金鑰。",
        microphoneDenied: "咪高風取用權限已關閉。", microphoneUnavailable: "無法錄製預設咪高風。",
        audioTooLarge: "錄音太大，無法轉錄。", noSpeech: "偵測唔到語音。",
        invalidKey: "服務商拒絕咗 API 金鑰。", rateLimited: "已達服務商速率限制，請稍後再試。",
        networkError: "無法連線到服務商。", serverError: "服務商發生伺服器錯誤，請稍後再試。",
        requestRejected: "服務商拒絕咗呢次轉錄要求。", invalidResponse: "服務商傳回咗無效回應。",
        accessibilityCopied: "輔助使用已關閉，所以轉錄內容已複製。請用 Command-V 貼上。",
        focusChangedCopied: "使用中嘅文字欄位已改變，所以轉錄內容已複製。請貼到需要嘅位置。",
        pasteFailedCopied: "無法貼上文字，所以轉錄內容已複製。"
    )
}
