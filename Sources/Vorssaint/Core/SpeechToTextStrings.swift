// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Small, feature-local catalog for dictation and its contextual permissions.
struct SpeechToTextStrings {
    enum Status { case requesting, finishing, failed }
    let title: String
    let description: String
    let start: String
    let stop: String
    let listening: String
    let unavailable: String
    let microphonePermission: String
    let microphoneExplanation: String
    let speechPermission: String
    let speechExplanation: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return .init(title: "Voice typing", description: "Dictate into the frontmost app using on-device speech recognition.", start: "Start dictation", stop: "Stop and insert text", listening: "Listening… press again to finish.", unavailable: "On-device recognition is unavailable for the system language.", microphonePermission: "Microphone", microphoneExplanation: "Captures audio only while dictation is active.", speechPermission: "Speech recognition", speechExplanation: "Recognizes dictation on this Mac; audio is not sent to a server.")
        case .ptBR:
            return .init(title: "Digitação por voz", description: "Dite no app em primeiro plano com reconhecimento no dispositivo.", start: "Iniciar ditado", stop: "Parar e inserir texto", listening: "Ouvindo… pressione novamente para terminar.", unavailable: "O reconhecimento no dispositivo não está disponível para o idioma do sistema.", microphonePermission: "Microfone", microphoneExplanation: "Captura áudio somente durante o ditado.", speechPermission: "Reconhecimento de fala", speechExplanation: "Reconhece o ditado neste Mac; o áudio não é enviado a um servidor.")
        case .tr:
            return .init(title: "Sesle yazma", description: "Cihaz içi konuşma tanımayla öndeki uygulamaya dikte edin.", start: "Dikteyi başlat", stop: "Durdur ve metni ekle", listening: "Dinleniyor… bitirmek için tekrar basın.", unavailable: "Sistem dili için cihaz içi tanıma kullanılamıyor.", microphonePermission: "Mikrofon", microphoneExplanation: "Sesi yalnızca dikte etkinken alır.", speechPermission: "Konuşma tanıma", speechExplanation: "Dikteyi bu Mac'te tanır; ses sunucuya gönderilmez.")
        case .ru:
            return .init(title: "Голосовой ввод", description: "Диктуйте в активное приложение с распознаванием на устройстве.", start: "Начать диктовку", stop: "Остановить и вставить текст", listening: "Прослушивание… нажмите ещё раз, чтобы завершить.", unavailable: "Распознавание на устройстве недоступно для системного языка.", microphonePermission: "Микрофон", microphoneExplanation: "Запись звука ведётся только во время диктовки.", speechPermission: "Распознавание речи", speechExplanation: "Речь распознаётся на этом Mac; аудио не отправляется на сервер.")
        case .es:
            return .init(title: "Escritura por voz", description: "Dicta en la app activa con reconocimiento en el dispositivo.", start: "Iniciar dictado", stop: "Detener e insertar texto", listening: "Escuchando… pulsa otra vez para terminar.", unavailable: "El reconocimiento en el dispositivo no está disponible para el idioma del sistema.", microphonePermission: "Micrófono", microphoneExplanation: "Captura audio solo mientras el dictado está activo.", speechPermission: "Reconocimiento de voz", speechExplanation: "Reconoce el dictado en este Mac; el audio no se envía a un servidor.")
        case .sk:
            return .init(title: "Hlasové písanie", description: "Diktujte do aktívnej aplikácie pomocou rozpoznávania v zariadení.", start: "Spustiť diktovanie", stop: "Zastaviť a vložiť text", listening: "Počúvam… opätovným stlačením skončíte.", unavailable: "Rozpoznávanie v zariadení nie je dostupné pre jazyk systému.", microphonePermission: "Mikrofón", microphoneExplanation: "Zvuk zaznamenáva iba počas diktovania.", speechPermission: "Rozpoznávanie reči", speechExplanation: "Reč rozpoznáva tento Mac; zvuk sa neposiela na server.")
        case .de:
            return .init(title: "Spracheingabe", description: "Diktiere mit lokaler Spracherkennung in die aktive App.", start: "Diktat starten", stop: "Stoppen und Text einsetzen", listening: "Höre zu … erneut drücken zum Beenden.", unavailable: "Lokale Erkennung ist für die Systemsprache nicht verfügbar.", microphonePermission: "Mikrofon", microphoneExplanation: "Nimmt Audio nur während des Diktats auf.", speechPermission: "Spracherkennung", speechExplanation: "Erkennt das Diktat auf diesem Mac; Audio wird nicht an einen Server gesendet.")
        case .fr:
            return .init(title: "Saisie vocale", description: "Dictez dans l’app active avec la reconnaissance sur l’appareil.", start: "Démarrer la dictée", stop: "Arrêter et insérer le texte", listening: "Écoute… appuyez à nouveau pour terminer.", unavailable: "La reconnaissance sur l’appareil n’est pas disponible pour la langue du système.", microphonePermission: "Microphone", microphoneExplanation: "Capture le son uniquement pendant la dictée.", speechPermission: "Reconnaissance vocale", speechExplanation: "La dictée est reconnue sur ce Mac ; l’audio n’est pas envoyé à un serveur.")
        case .it:
            return .init(title: "Scrittura vocale", description: "Detta nell’app in primo piano con il riconoscimento sul dispositivo.", start: "Avvia dettatura", stop: "Interrompi e inserisci il testo", listening: "In ascolto… premi di nuovo per terminare.", unavailable: "Il riconoscimento sul dispositivo non è disponibile per la lingua di sistema.", microphonePermission: "Microfono", microphoneExplanation: "Acquisisce audio solo durante la dettatura.", speechPermission: "Riconoscimento vocale", speechExplanation: "Riconosce la dettatura su questo Mac; l’audio non viene inviato a un server.")
        case .ja:
            return .init(title: "音声入力", description: "デバイス上の音声認識で最前面のアプリに入力します。", start: "音声入力を開始", stop: "停止してテキストを入力", listening: "聞き取り中…もう一度押すと終了します。", unavailable: "システム言語ではデバイス上の音声認識を利用できません。", microphonePermission: "マイク", microphoneExplanation: "音声入力中のみ音声を取得します。", speechPermission: "音声認識", speechExplanation: "このMac上で音声を認識します。音声はサーバーに送信されません。")
        case .ko:
            return .init(title: "음성 입력", description: "기기 내 음성 인식으로 현재 앱에 받아씁니다.", start: "받아쓰기 시작", stop: "중지하고 텍스트 입력", listening: "듣는 중… 다시 누르면 완료됩니다.", unavailable: "시스템 언어에서 기기 내 음성 인식을 사용할 수 없습니다.", microphonePermission: "마이크", microphoneExplanation: "받아쓰기 중에만 오디오를 캡처합니다.", speechPermission: "음성 인식", speechExplanation: "이 Mac에서 음성을 인식하며 오디오는 서버로 전송되지 않습니다.")
        case .uk:
            return .init(title: "Голосове введення", description: "Диктуйте в активну програму з розпізнаванням на пристрої.", start: "Почати диктування", stop: "Зупинити й вставити текст", listening: "Слухаю… натисніть ще раз, щоб завершити.", unavailable: "Розпізнавання на пристрої недоступне для системної мови.", microphonePermission: "Мікрофон", microphoneExplanation: "Записує звук лише під час диктування.", speechPermission: "Розпізнавання мовлення", speechExplanation: "Розпізнає диктування на цьому Mac; аудіо не надсилається на сервер.")
        case .zhHans:
            return .init(title: "语音输入", description: "使用设备端语音识别，在当前应用中听写。", start: "开始听写", stop: "停止并插入文本", listening: "正在聆听…再次按下以完成。", unavailable: "系统语言不支持设备端语音识别。", microphonePermission: "麦克风", microphoneExplanation: "仅在听写期间采集音频。", speechPermission: "语音识别", speechExplanation: "在此 Mac 上识别语音；音频不会发送到服务器。")
        case .zhTW:
            return .init(title: "語音輸入", description: "使用裝置端語音辨識，在目前的 App 中聽寫。", start: "開始聽寫", stop: "停止並插入文字", listening: "正在聆聽…再次按下即可完成。", unavailable: "系統語言不支援裝置端語音辨識。", microphonePermission: "麥克風", microphoneExplanation: "僅在聽寫期間擷取音訊。", speechPermission: "語音辨識", speechExplanation: "在此 Mac 上辨識語音；音訊不會傳送至伺服器。")
        case .zhHK:
            return .init(title: "語音輸入", description: "使用裝置端語音辨識，在目前的 App 中聽寫。", start: "開始聽寫", stop: "停止並插入文字", listening: "正在聆聽…再次按下即可完成。", unavailable: "系統語言不支援裝置端語音辨識。", microphonePermission: "咪高峰", microphoneExplanation: "只會在聽寫期間擷取音訊。", speechPermission: "語音辨識", speechExplanation: "在此 Mac 上辨識語音；音訊不會傳送至伺服器。")
        }
    }

    static func status(_ language: AppLanguage, _ status: Status) -> String {
        switch (language, status) {
        case (.enUS, .requesting): return "Waiting for permission…"
        case (.enUS, .finishing): return "Finishing dictation…"
        case (.enUS, .failed): return "Dictation failed. Check permissions and try again."
        case (.ptBR, .requesting): return "Aguardando permissão…"
        case (.ptBR, .finishing): return "Finalizando o ditado…"
        case (.ptBR, .failed): return "O ditado falhou. Verifique as permissões e tente novamente."
        case (.tr, .requesting): return "İzin bekleniyor…"
        case (.tr, .finishing): return "Dikte tamamlanıyor…"
        case (.tr, .failed): return "Dikte başarısız. İzinleri kontrol edip yeniden deneyin."
        case (.ru, .requesting): return "Ожидание разрешения…"
        case (.ru, .finishing): return "Завершение диктовки…"
        case (.ru, .failed): return "Не удалось выполнить диктовку. Проверьте разрешения и попробуйте снова."
        case (.es, .requesting): return "Esperando permiso…"
        case (.es, .finishing): return "Terminando el dictado…"
        case (.es, .failed): return "El dictado ha fallado. Comprueba los permisos e inténtalo de nuevo."
        case (.sk, .requesting): return "Čakám na povolenie…"
        case (.sk, .finishing): return "Dokončujem diktovanie…"
        case (.sk, .failed): return "Diktovanie zlyhalo. Skontrolujte povolenia a skúste znova."
        case (.de, .requesting): return "Warte auf Berechtigung …"
        case (.de, .finishing): return "Diktat wird beendet …"
        case (.de, .failed): return "Diktat fehlgeschlagen. Prüfe die Berechtigungen und versuche es erneut."
        case (.fr, .requesting): return "En attente de l’autorisation…"
        case (.fr, .finishing): return "Fin de la dictée…"
        case (.fr, .failed): return "La dictée a échoué. Vérifiez les autorisations et réessayez."
        case (.it, .requesting): return "In attesa dell’autorizzazione…"
        case (.it, .finishing): return "Completamento della dettatura…"
        case (.it, .failed): return "Dettatura non riuscita. Controlla i permessi e riprova."
        case (.ja, .requesting): return "アクセス許可を待っています…"
        case (.ja, .finishing): return "音声入力を終了しています…"
        case (.ja, .failed): return "音声入力に失敗しました。アクセス許可を確認して再試行してください。"
        case (.ko, .requesting): return "권한을 기다리는 중…"
        case (.ko, .finishing): return "받아쓰기 마무리 중…"
        case (.ko, .failed): return "받아쓰기에 실패했습니다. 권한을 확인하고 다시 시도하세요."
        case (.uk, .requesting): return "Очікування дозволу…"
        case (.uk, .finishing): return "Завершення диктування…"
        case (.uk, .failed): return "Не вдалося виконати диктування. Перевірте дозволи й повторіть спробу."
        case (.zhHans, .requesting): return "正在等待权限…"
        case (.zhHans, .finishing): return "正在完成听写…"
        case (.zhHans, .failed): return "听写失败。请检查权限后重试。"
        case (.zhTW, .requesting): return "正在等待權限…"
        case (.zhTW, .finishing): return "正在完成聽寫…"
        case (.zhTW, .failed): return "聽寫失敗。請檢查權限後再試。"
        case (.zhHK, .requesting): return "正在等候權限…"
        case (.zhHK, .finishing): return "正在完成聽寫…"
        case (.zhHK, .failed): return "聽寫失敗。請檢查權限後再試。"
        }
    }
}
