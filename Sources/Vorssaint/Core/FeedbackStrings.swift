// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FeedbackStrings {
    let sectionTitle: String
    let sectionCaption: String
    let openButton: String
    let windowTitle: String
    let bugTitle: String
    let featureTitle: String
    let messageLabel: String
    let bugPlaceholder: String
    let featurePlaceholder: String
    let charactersFormat: String
    let includeDiagnostics: String
    let includeDiagnosticsCaption: String
    let whatSentTitle: String
    let whatSentBasic: String
    let whatSentDiagnostics: String
    let privacyNote: String
    let retentionNote: String
    let sendButton: String
    let sending: String
    let sentTitle: String
    let sentCaption: String
    let unavailableError: String
    let rateLimitError: String
    let genericError: String
    let done: String
    let commandBug: String
    let commandFeature: String
    let commandSubtitle: String
    let diagnosticsChannelLabel: String
}

extension FeatureStrings {
    static func feedback(_ language: AppLanguage) -> FeedbackStrings {
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

extension FeedbackStrings {
    static let enUS = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Send a bug report or feature idea directly to the person who maintains Vorssaint.",
        openButton: "Send feedback",
        windowTitle: "Send feedback",
        bugTitle: "Bug",
        featureTitle: "Feature idea",
        messageLabel: "What would you like to share?",
        bugPlaceholder: "Tell me what happened and what you expected.",
        featurePlaceholder: "Describe the idea and how it would help.",
        charactersFormat: "%d of 2000 characters",
        includeDiagnostics: "Include technical details",
        includeDiagnosticsCaption: "Adds only the technical details shown below. It does not include logs.",
        whatSentTitle: "What will be sent",
        whatSentBasic: "Your chosen category and the text above.",
        whatSentDiagnostics: "The technical details listed below.",
        privacyNote: "No name, account, email, device identifier, logs, screenshots, files or clipboard content are included. Your public IP is temporarily processed for abuse protection and is not attached to the feedback.",
        retentionNote: "After delivery, the text remains in private support channels until the service owner deletes it. An undelivered copy is permanently deleted after 7 days.",
        sendButton: "Send feedback",
        sending: "Sending…",
        sentTitle: "Feedback sent",
        sentCaption: "Thank you. No contact information was sent, so you will not receive a direct reply.",
        unavailableError: "Could not connect. Check your internet connection and try again.",
        rateLimitError: "Too many submissions from this network. Please try again later.",
        genericError: "Could not send the feedback right now.",
        done: "Done",
        commandBug: "Report a bug",
        commandFeature: "Suggest a feature",
        commandSubtitle: "Send feedback",
        diagnosticsChannelLabel: "Update channel"
    )

    static let ptBR = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Envie um relato de bug ou uma ideia de recurso diretamente para quem mantém o Vorssaint.",
        openButton: "Enviar feedback",
        windowTitle: "Enviar feedback",
        bugTitle: "Bug",
        featureTitle: "Ideia de recurso",
        messageLabel: "O que você gostaria de compartilhar?",
        bugPlaceholder: "Conte o que aconteceu e o que você esperava.",
        featurePlaceholder: "Descreva a ideia e como ela ajudaria.",
        charactersFormat: "%d de 2000 caracteres",
        includeDiagnostics: "Incluir dados técnicos",
        includeDiagnosticsCaption: "Adiciona somente os dados técnicos mostrados abaixo. Não inclui logs.",
        whatSentTitle: "O que será enviado",
        whatSentBasic: "A categoria escolhida e o texto acima.",
        whatSentDiagnostics: "Os dados técnicos listados abaixo.",
        privacyNote: "Não são incluídos nome, conta, e-mail, identificador do aparelho, logs, capturas, arquivos ou conteúdo da área de transferência. Seu IP público é processado temporariamente contra abuso e não é anexado ao feedback.",
        retentionNote: "Após a entrega, o texto fica em canais privados de suporte até o responsável pelo serviço apagá-lo. Uma cópia não entregue é apagada definitivamente após 7 dias.",
        sendButton: "Enviar feedback",
        sending: "Enviando…",
        sentTitle: "Feedback enviado",
        sentCaption: "Obrigado. Nenhum contato foi enviado, então você não receberá uma resposta direta.",
        unavailableError: "Não foi possível conectar. Confira a internet e tente novamente.",
        rateLimitError: "Muitos envios desta rede. Tente novamente mais tarde.",
        genericError: "Não foi possível enviar o feedback agora.",
        done: "Concluído",
        commandBug: "Relatar um bug",
        commandFeature: "Sugerir um recurso",
        commandSubtitle: "Enviar feedback",
        diagnosticsChannelLabel: "Canal de atualização"
    )

    static let tr = FeedbackStrings(
        sectionTitle: "Geri bildirim",
        sectionCaption: "Bir hata bildirimini veya özellik fikrini doğrudan Vorssaint bakımcısına gönderin.",
        openButton: "Geri bildirim gönder",
        windowTitle: "Geri bildirim gönder",
        bugTitle: "Hata",
        featureTitle: "Özellik fikri",
        messageLabel: "Ne paylaşmak istersiniz?",
        bugPlaceholder: "Ne olduğunu ve ne beklediğinizi anlatın.",
        featurePlaceholder: "Fikri ve nasıl yardımcı olacağını açıklayın.",
        charactersFormat: "2000 karakterden %d",
        includeDiagnostics: "Teknik ayrıntıları ekle",
        includeDiagnosticsCaption: "Yalnızca aşağıda gösterilen teknik ayrıntıları ekler. Günlükler eklenmez.",
        whatSentTitle: "Gönderilecekler",
        whatSentBasic: "Seçtiğiniz kategori ve yukarıdaki metin.",
        whatSentDiagnostics: "Aşağıda listelenen teknik ayrıntılar.",
        privacyNote: "Ad, hesap, e-posta, aygıt kimliği, günlük, ekran görüntüsü, dosya veya pano içeriği eklenmez. Genel IP adresiniz kötüye kullanımı önlemek için geçici olarak işlenir ve geri bildirime eklenmez.",
        retentionNote: "Teslimden sonra metin, hizmet sahibi silene kadar özel destek kanallarında kalır. Teslim edilmeyen kopya 7 gün sonra kalıcı olarak silinir.",
        sendButton: "Geri bildirim gönder",
        sending: "Gönderiliyor…",
        sentTitle: "Geri bildirim gönderildi",
        sentCaption: "Teşekkürler. İletişim bilgisi gönderilmediği için doğrudan yanıt alamazsınız.",
        unavailableError: "Bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.",
        rateLimitError: "Bu ağdan çok fazla gönderim yapıldı. Daha sonra tekrar deneyin.",
        genericError: "Geri bildirim şu anda gönderilemedi.",
        done: "Bitti",
        commandBug: "Hata bildir",
        commandFeature: "Özellik öner",
        commandSubtitle: "Geri bildirim gönder",
        diagnosticsChannelLabel: "Güncelleme kanalı"
    )

    static let ru = FeedbackStrings(
        sectionTitle: "Обратная связь",
        sectionCaption: "Отправьте сообщение об ошибке или идею функции напрямую разработчику Vorssaint.",
        openButton: "Отправить отзыв",
        windowTitle: "Отправить отзыв",
        bugTitle: "Ошибка",
        featureTitle: "Идея функции",
        messageLabel: "Чем вы хотите поделиться?",
        bugPlaceholder: "Опишите, что произошло и чего вы ожидали.",
        featurePlaceholder: "Опишите идею и чем она поможет.",
        charactersFormat: "%d из 2000 символов",
        includeDiagnostics: "Добавить технические данные",
        includeDiagnosticsCaption: "Добавляет только технические данные, показанные ниже. Журналы не добавляются.",
        whatSentTitle: "Что будет отправлено",
        whatSentBasic: "Выбранная категория и текст выше.",
        whatSentDiagnostics: "Технические данные, перечисленные ниже.",
        privacyNote: "Имя, учётная запись, почта, идентификатор устройства, журналы, снимки, файлы и буфер обмена не добавляются. Публичный IP временно обрабатывается для защиты от злоупотреблений и не прикрепляется к отзыву.",
        retentionNote: "После доставки текст хранится в закрытых каналах поддержки, пока владелец сервиса его не удалит. Недоставленная копия безвозвратно удаляется через 7 дней.",
        sendButton: "Отправить отзыв",
        sending: "Отправка…",
        sentTitle: "Отзыв отправлен",
        sentCaption: "Спасибо. Контактные данные не отправлялись, поэтому прямого ответа не будет.",
        unavailableError: "Не удалось подключиться. Проверьте интернет и повторите попытку.",
        rateLimitError: "Слишком много отправок из этой сети. Повторите позже.",
        genericError: "Сейчас не удалось отправить отзыв.",
        done: "Готово",
        commandBug: "Сообщить об ошибке",
        commandFeature: "Предложить функцию",
        commandSubtitle: "Отправить отзыв",
        diagnosticsChannelLabel: "Канал обновлений"
    )

    static let es = FeedbackStrings(
        sectionTitle: "Comentarios",
        sectionCaption: "Envía un informe de error o una idea directamente a quien mantiene Vorssaint.",
        openButton: "Enviar comentarios",
        windowTitle: "Enviar comentarios",
        bugTitle: "Error",
        featureTitle: "Idea de función",
        messageLabel: "¿Qué quieres compartir?",
        bugPlaceholder: "Cuenta qué ocurrió y qué esperabas.",
        featurePlaceholder: "Describe la idea y cómo ayudaría.",
        charactersFormat: "%d de 2000 caracteres",
        includeDiagnostics: "Incluir datos técnicos",
        includeDiagnosticsCaption: "Añade solo los datos técnicos mostrados abajo. No incluye registros.",
        whatSentTitle: "Qué se enviará",
        whatSentBasic: "La categoría elegida y el texto anterior.",
        whatSentDiagnostics: "Los datos técnicos indicados abajo.",
        privacyNote: "No se incluyen nombre, cuenta, correo, identificador del dispositivo, registros, capturas, archivos ni portapapeles. Tu IP pública se procesa temporalmente contra abusos y no se adjunta al comentario.",
        retentionNote: "Tras la entrega, el texto queda en canales privados de soporte hasta que el responsable lo elimine. Una copia no entregada se borra definitivamente tras 7 días.",
        sendButton: "Enviar comentarios",
        sending: "Enviando…",
        sentTitle: "Comentarios enviados",
        sentCaption: "Gracias. No se envió información de contacto, así que no recibirás una respuesta directa.",
        unavailableError: "No se pudo conectar. Comprueba internet e inténtalo de nuevo.",
        rateLimitError: "Demasiados envíos desde esta red. Inténtalo más tarde.",
        genericError: "No se pudieron enviar los comentarios ahora.",
        done: "Listo",
        commandBug: "Informar de un error",
        commandFeature: "Sugerir una función",
        commandSubtitle: "Enviar comentarios",
        diagnosticsChannelLabel: "Canal de actualización"
    )

    static let de = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Sende einen Fehlerbericht oder eine Funktionsidee direkt an den Vorssaint-Entwickler.",
        openButton: "Feedback senden",
        windowTitle: "Feedback senden",
        bugTitle: "Fehler",
        featureTitle: "Funktionsidee",
        messageLabel: "Was möchtest du mitteilen?",
        bugPlaceholder: "Beschreibe, was passiert ist und was du erwartet hast.",
        featurePlaceholder: "Beschreibe die Idee und wie sie helfen würde.",
        charactersFormat: "%d von 2000 Zeichen",
        includeDiagnostics: "Technische Daten mitsenden",
        includeDiagnosticsCaption: "Fügt nur die unten gezeigten technischen Daten hinzu. Keine Protokolle.",
        whatSentTitle: "Was gesendet wird",
        whatSentBasic: "Die gewählte Kategorie und der Text oben.",
        whatSentDiagnostics: "Die unten aufgeführten technischen Daten.",
        privacyNote: "Name, Konto, E-Mail, Gerätekennung, Protokolle, Bildschirmfotos, Dateien und Zwischenablage werden nicht mitgesendet. Die öffentliche IP wird kurzzeitig gegen Missbrauch verarbeitet und nicht ans Feedback angehängt.",
        retentionNote: "Nach der Zustellung bleibt der Text in privaten Supportkanälen, bis der Betreiber ihn löscht. Eine nicht zugestellte Kopie wird nach 7 Tagen endgültig gelöscht.",
        sendButton: "Feedback senden",
        sending: "Wird gesendet…",
        sentTitle: "Feedback gesendet",
        sentCaption: "Danke. Es wurden keine Kontaktdaten gesendet, daher erhältst du keine direkte Antwort.",
        unavailableError: "Keine Verbindung. Prüfe das Internet und versuche es erneut.",
        rateLimitError: "Zu viele Einsendungen aus diesem Netzwerk. Versuche es später erneut.",
        genericError: "Das Feedback konnte gerade nicht gesendet werden.",
        done: "Fertig",
        commandBug: "Fehler melden",
        commandFeature: "Funktion vorschlagen",
        commandSubtitle: "Feedback senden",
        diagnosticsChannelLabel: "Update-Kanal"
    )

    static let fr = FeedbackStrings(
        sectionTitle: "Avis",
        sectionCaption: "Envoyez un rapport de bug ou une idée directement à la personne qui maintient Vorssaint.",
        openButton: "Envoyer un avis",
        windowTitle: "Envoyer un avis",
        bugTitle: "Bug",
        featureTitle: "Idée de fonction",
        messageLabel: "Que souhaitez-vous partager ?",
        bugPlaceholder: "Décrivez ce qui s'est passé et ce que vous attendiez.",
        featurePlaceholder: "Décrivez l'idée et son utilité.",
        charactersFormat: "%d caractères sur 2000",
        includeDiagnostics: "Inclure les données techniques",
        includeDiagnosticsCaption: "Ajoute uniquement les données techniques affichées ci-dessous. Aucun journal.",
        whatSentTitle: "Ce qui sera envoyé",
        whatSentBasic: "La catégorie choisie et le texte ci-dessus.",
        whatSentDiagnostics: "Les données techniques listées ci-dessous.",
        privacyNote: "Aucun nom, compte, e-mail, identifiant d'appareil, journal, capture, fichier ou presse-papiers n'est inclus. Votre IP publique est traitée temporairement contre les abus et n'est pas jointe à l'avis.",
        retentionNote: "Après livraison, le texte reste dans des canaux privés jusqu'à sa suppression par le responsable. Une copie non livrée est définitivement supprimée après 7 jours.",
        sendButton: "Envoyer l'avis",
        sending: "Envoi…",
        sentTitle: "Avis envoyé",
        sentCaption: "Merci. Aucune coordonnée n'a été envoyée, vous ne recevrez donc pas de réponse directe.",
        unavailableError: "Connexion impossible. Vérifiez Internet et réessayez.",
        rateLimitError: "Trop d'envois depuis ce réseau. Réessayez plus tard.",
        genericError: "Impossible d'envoyer l'avis maintenant.",
        done: "Terminé",
        commandBug: "Signaler un bug",
        commandFeature: "Suggérer une fonction",
        commandSubtitle: "Envoyer un avis",
        diagnosticsChannelLabel: "Canal de mise à jour"
    )

    static let it = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Invia una segnalazione o un'idea direttamente a chi mantiene Vorssaint.",
        openButton: "Invia feedback",
        windowTitle: "Invia feedback",
        bugTitle: "Bug",
        featureTitle: "Idea per una funzione",
        messageLabel: "Cosa vuoi condividere?",
        bugPlaceholder: "Descrivi cosa è successo e cosa ti aspettavi.",
        featurePlaceholder: "Descrivi l'idea e come potrebbe aiutare.",
        charactersFormat: "%d di 2000 caratteri",
        includeDiagnostics: "Includi dati tecnici",
        includeDiagnosticsCaption: "Aggiunge solo i dati tecnici mostrati sotto. Non include registri.",
        whatSentTitle: "Cosa verrà inviato",
        whatSentBasic: "La categoria scelta e il testo qui sopra.",
        whatSentDiagnostics: "I dati tecnici elencati qui sotto.",
        privacyNote: "Non vengono inclusi nome, account, e-mail, identificatore del dispositivo, registri, schermate, file o appunti. L'IP pubblico viene elaborato temporaneamente contro gli abusi e non è allegato al feedback.",
        retentionNote: "Dopo la consegna, il testo resta in canali privati finché il responsabile non lo elimina. Una copia non consegnata viene eliminata definitivamente dopo 7 giorni.",
        sendButton: "Invia feedback",
        sending: "Invio…",
        sentTitle: "Feedback inviato",
        sentCaption: "Grazie. Non sono stati inviati contatti, quindi non riceverai una risposta diretta.",
        unavailableError: "Connessione non riuscita. Controlla Internet e riprova.",
        rateLimitError: "Troppi invii da questa rete. Riprova più tardi.",
        genericError: "Impossibile inviare il feedback ora.",
        done: "Fine",
        commandBug: "Segnala un bug",
        commandFeature: "Suggerisci una funzione",
        commandSubtitle: "Invia feedback",
        diagnosticsChannelLabel: "Canale di aggiornamento"
    )

    static let ja = FeedbackStrings(
        sectionTitle: "フィードバック",
        sectionCaption: "不具合の報告や機能のアイデアを Vorssaint の開発者へ直接送信します。",
        openButton: "フィードバックを送信",
        windowTitle: "フィードバックを送信",
        bugTitle: "不具合",
        featureTitle: "機能のアイデア",
        messageLabel: "共有したい内容を入力してください",
        bugPlaceholder: "何が起き、どうなることを期待していたかを説明してください。",
        featurePlaceholder: "アイデアと、どのように役立つかを説明してください。",
        charactersFormat: "2000文字中%d文字",
        includeDiagnostics: "技術情報を含める",
        includeDiagnosticsCaption: "下に表示される技術情報だけを追加します。ログは含みません。",
        whatSentTitle: "送信される内容",
        whatSentBasic: "選択した種類と上の文章。",
        whatSentDiagnostics: "下に表示される技術情報。",
        privacyNote: "名前、アカウント、メール、端末識別子、ログ、画像、ファイル、クリップボードは含まれません。公開 IP は不正利用対策のため一時的に処理され、フィードバックには添付されません。",
        retentionNote: "送信後、文章は管理者が削除するまで非公開のサポートチャンネルに残ります。未配信のコピーは7日後に完全に削除されます。",
        sendButton: "送信",
        sending: "送信中…",
        sentTitle: "送信しました",
        sentCaption: "ありがとうございます。連絡先は送信されないため、直接の返信はありません。",
        unavailableError: "接続できませんでした。インターネット接続を確認して再試行してください。",
        rateLimitError: "このネットワークからの送信が多すぎます。後でもう一度お試しください。",
        genericError: "現在フィードバックを送信できません。",
        done: "完了",
        commandBug: "不具合を報告",
        commandFeature: "機能を提案",
        commandSubtitle: "フィードバックを送信",
        diagnosticsChannelLabel: "アップデートチャンネル"
    )

    static let ko = FeedbackStrings(
        sectionTitle: "피드백",
        sectionCaption: "버그 신고나 기능 아이디어를 Vorssaint 관리자에게 직접 보냅니다.",
        openButton: "피드백 보내기",
        windowTitle: "피드백 보내기",
        bugTitle: "버그",
        featureTitle: "기능 아이디어",
        messageLabel: "무엇을 공유하시겠습니까?",
        bugPlaceholder: "무슨 일이 있었고 무엇을 기대했는지 알려 주세요.",
        featurePlaceholder: "아이디어와 도움이 되는 이유를 설명해 주세요.",
        charactersFormat: "2000자 중 %d자",
        includeDiagnostics: "기술 정보 포함",
        includeDiagnosticsCaption: "아래에 표시된 기술 정보만 추가합니다. 로그는 포함하지 않습니다.",
        whatSentTitle: "전송되는 내용",
        whatSentBasic: "선택한 종류와 위의 글.",
        whatSentDiagnostics: "아래에 표시된 기술 정보.",
        privacyNote: "이름, 계정, 이메일, 기기 식별자, 로그, 스크린샷, 파일, 클립보드 내용은 포함되지 않습니다. 공개 IP는 악용 방지를 위해 잠시 처리되며 피드백에 첨부되지 않습니다.",
        retentionNote: "전달 후 글은 서비스 관리자가 삭제할 때까지 비공개 지원 채널에 남습니다. 전달되지 않은 사본은 7일 후 영구적으로 삭제됩니다.",
        sendButton: "피드백 보내기",
        sending: "보내는 중…",
        sentTitle: "피드백을 보냈습니다",
        sentCaption: "감사합니다. 연락처를 보내지 않았으므로 직접 답변은 받을 수 없습니다.",
        unavailableError: "연결할 수 없습니다. 인터넷 연결을 확인하고 다시 시도하세요.",
        rateLimitError: "이 네트워크에서 너무 많이 보냈습니다. 나중에 다시 시도하세요.",
        genericError: "지금은 피드백을 보낼 수 없습니다.",
        done: "완료",
        commandBug: "버그 신고",
        commandFeature: "기능 제안",
        commandSubtitle: "피드백 보내기",
        diagnosticsChannelLabel: "업데이트 채널"
    )

    static let zhHans = FeedbackStrings(
        sectionTitle: "反馈",
        sectionCaption: "将错误报告或功能建议直接发送给 Vorssaint 的维护者。",
        openButton: "发送反馈",
        windowTitle: "发送反馈",
        bugTitle: "错误",
        featureTitle: "功能建议",
        messageLabel: "你想分享什么？",
        bugPlaceholder: "说明发生了什么以及你原本的预期。",
        featurePlaceholder: "说明你的想法以及它能带来什么帮助。",
        charactersFormat: "已输入 %d/2000 个字符",
        includeDiagnostics: "包含技术信息",
        includeDiagnosticsCaption: "仅添加下方显示的技术信息。不包含日志。",
        whatSentTitle: "将发送的内容",
        whatSentBasic: "所选类别和上方文字。",
        whatSentDiagnostics: "下方列出的技术信息。",
        privacyNote: "不会包含姓名、账户、邮箱、设备标识符、日志、截图、文件或剪贴板内容。公共 IP 仅为防止滥用而临时处理，不会附加到反馈。",
        retentionNote: "送达后，文字会保留在私密支持频道中，直到服务负责人删除。未送达的副本会在 7 天后永久删除。",
        sendButton: "发送反馈",
        sending: "正在发送…",
        sentTitle: "反馈已发送",
        sentCaption: "谢谢。由于未发送联系方式，你不会收到直接回复。",
        unavailableError: "无法连接。请检查网络后重试。",
        rateLimitError: "此网络提交次数过多，请稍后再试。",
        genericError: "目前无法发送反馈。",
        done: "完成",
        commandBug: "报告错误",
        commandFeature: "建议功能",
        commandSubtitle: "发送反馈",
        diagnosticsChannelLabel: "更新渠道"
    )

    static let zhTW = FeedbackStrings(
        sectionTitle: "意見回饋",
        sectionCaption: "將錯誤回報或功能建議直接傳送給 Vorssaint 的維護者。",
        openButton: "傳送意見",
        windowTitle: "傳送意見",
        bugTitle: "錯誤",
        featureTitle: "功能建議",
        messageLabel: "你想分享什麼？",
        bugPlaceholder: "說明發生了什麼以及你原本的預期。",
        featurePlaceholder: "說明你的想法以及它能帶來什麼幫助。",
        charactersFormat: "已輸入 %d/2000 個字元",
        includeDiagnostics: "包含技術資訊",
        includeDiagnosticsCaption: "只加入下方顯示的技術資料。不包含記錄。",
        whatSentTitle: "將傳送的內容",
        whatSentBasic: "所選類別與上方文字。",
        whatSentDiagnostics: "下方列出的技術資訊。",
        privacyNote: "不會包含姓名、帳號、電郵、裝置識別碼、記錄、截圖、檔案或剪貼簿內容。公開 IP 只為防止濫用而暫時處理，不會附加到意見。",
        retentionNote: "送達後，文字會留在私人支援頻道，直到服務負責人刪除。未送達的副本會在 7 天後永久刪除。",
        sendButton: "傳送意見",
        sending: "正在傳送…",
        sentTitle: "意見已傳送",
        sentCaption: "謝謝。由於未傳送聯絡資料，你不會收到直接回覆。",
        unavailableError: "無法連線。請檢查網路後再試一次。",
        rateLimitError: "此網路提交次數過多，請稍後再試。",
        genericError: "目前無法傳送意見。",
        done: "完成",
        commandBug: "回報錯誤",
        commandFeature: "建議功能",
        commandSubtitle: "傳送意見",
        diagnosticsChannelLabel: "更新頻道"
    )

    static let zhHK = FeedbackStrings(
        sectionTitle: "意見回饋",
        sectionCaption: "將錯誤報告或功能建議直接傳送給 Vorssaint 的維護者。",
        openButton: "傳送意見",
        windowTitle: "傳送意見",
        bugTitle: "錯誤",
        featureTitle: "功能建議",
        messageLabel: "你想分享甚麼？",
        bugPlaceholder: "說明發生了甚麼以及你原本的預期。",
        featurePlaceholder: "說明你的想法以及它能帶來甚麼幫助。",
        charactersFormat: "已輸入 %d/2000 個字元",
        includeDiagnostics: "包含技術資料",
        includeDiagnosticsCaption: "只加入下方顯示的技術資料。不包含記錄。",
        whatSentTitle: "將傳送的內容",
        whatSentBasic: "所選類別與上方文字。",
        whatSentDiagnostics: "下方列出的技術資料。",
        privacyNote: "不會包含姓名、帳戶、電郵、裝置識別碼、記錄、截圖、檔案或剪貼簿內容。公開 IP 只為防止濫用而暫時處理，不會附加到意見。",
        retentionNote: "送達後，文字會留在私人支援頻道，直到服務負責人刪除。未送達的副本會在 7 天後永久刪除。",
        sendButton: "傳送意見",
        sending: "正在傳送…",
        sentTitle: "意見已傳送",
        sentCaption: "謝謝。由於未傳送聯絡資料，你不會收到直接回覆。",
        unavailableError: "無法連線。請檢查網絡後再試一次。",
        rateLimitError: "此網絡提交次數過多，請稍後再試。",
        genericError: "目前無法傳送意見。",
        done: "完成",
        commandBug: "報告錯誤",
        commandFeature: "建議功能",
        commandSubtitle: "傳送意見",
        diagnosticsChannelLabel: "更新頻道"
    )
}
