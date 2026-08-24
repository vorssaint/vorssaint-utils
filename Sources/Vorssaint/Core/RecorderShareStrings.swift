// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct RecorderShareStrings {
    let caption: String
    let privacyData: String
    let privacyStorage: String
    let privacyAccess: String
    let compressing: String
    let uploading: String
    let tooLarge: String
    let failed: String
    let tourCaption: String
}

extension FeatureStrings {
    static func recorderShare(_ language: AppLanguage) -> RecorderShareStrings {
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

extension RecorderShareStrings {
    static let enUS = RecorderShareStrings(
        caption: "Choose 1 or 6 hours. The final video is compressed on this Mac to fit under 100 MB and deleted automatically.",
        privacyData: "Vorssaint sends only the final video created from this recording, including the audio you kept, and the expiration you choose. It does not send your name, account or device identifier.",
        privacyStorage: "Network providers and the service temporarily process your public IP to prevent abuse. The video and link metadata are permanently deleted when you delete the link or its time ends. The service does not create backups.",
        privacyAccess: "Anyone with the link can view, download, save or redistribute the video. Active links are available to the service operator for abuse moderation. Share only with people you trust.",
        compressing: "Compressing for sharing…",
        uploading: "Uploading securely…",
        tooLarge: "This recording cannot fit under 100 MB without losing too much quality.",
        failed: "The temporary link could not be created",
        tourCaption: "Compress a finished recording on this Mac and share it for 1 or 6 hours."
    )

    static let ptBR = RecorderShareStrings(
        caption: "Escolha 1 ou 6 horas. O vídeo final é comprimido neste Mac para ficar abaixo de 100 MB e apagado automaticamente.",
        privacyData: "O Vorssaint envia somente o vídeo final criado desta gravação, incluindo o áudio que você manteve, e o prazo escolhido. Não envia seu nome, conta nem identificador do aparelho.",
        privacyStorage: "Os provedores de rede e o serviço processam temporariamente seu IP público para impedir abusos. O vídeo e os metadados do link são apagados definitivamente quando você apagar o link ou o prazo terminar. O serviço não cria backups.",
        privacyAccess: "Qualquer pessoa com o link pode ver, baixar, salvar ou redistribuir o vídeo. Os links ativos ficam disponíveis ao operador do serviço para moderação de abuso. Compartilhe somente com pessoas de confiança.",
        compressing: "Comprimindo para compartilhar…",
        uploading: "Enviando com segurança…",
        tooLarge: "Esta gravação não cabe em 100 MB sem perder qualidade demais.",
        failed: "Não foi possível criar o link temporário",
        tourCaption: "Comprima uma gravação final neste Mac e compartilhe por 1 ou 6 horas."
    )

    static let tr = RecorderShareStrings(
        caption: "1 veya 6 saat seçin. Son video bu Mac'te 100 MB altında kalacak şekilde sıkıştırılır ve otomatik olarak silinir.",
        privacyData: "Vorssaint yalnızca bu kayıttan oluşturulan son videoyu, koruduğunuz sesle ve seçtiğiniz süreyle birlikte gönderir. Adınızı, hesabınızı veya aygıt kimliğinizi göndermez.",
        privacyStorage: "Ağ sağlayıcıları ve hizmet, kötüye kullanımı önlemek için genel IP adresinizi geçici olarak işler. Video ve bağlantı verileri, bağlantıyı sildiğinizde veya süresi dolduğunda kalıcı olarak silinir. Hizmet yedek oluşturmaz.",
        privacyAccess: "Bağlantıya sahip herkes videoyu izleyebilir, indirebilir, kaydedebilir veya yeniden dağıtabilir. Etkin bağlantılar kötüye kullanım denetimi için hizmet operatörüne açıktır. Yalnızca güvendiğiniz kişilerle paylaşın.",
        compressing: "Paylaşım için sıkıştırılıyor…",
        uploading: "Güvenli şekilde yükleniyor…",
        tooLarge: "Bu kayıt, kaliteden çok fazla ödün vermeden 100 MB altına sığmıyor.",
        failed: "Geçici bağlantı oluşturulamadı",
        tourCaption: "Tamamlanan kaydı bu Mac'te sıkıştırıp 1 veya 6 saatliğine paylaşın."
    )

    static let ru = RecorderShareStrings(
        caption: "Выберите 1 или 6 часов. Готовое видео сжимается на этом Mac до размера менее 100 МБ и удаляется автоматически.",
        privacyData: "Vorssaint отправляет только готовое видео из этой записи, включая оставленный вами звук, и выбранный срок. Имя, учётная запись и идентификатор устройства не отправляются.",
        privacyStorage: "Сетевые провайдеры и сервис временно обрабатывают ваш публичный IP-адрес для защиты от злоупотреблений. Видео и данные ссылки безвозвратно удаляются при удалении ссылки или истечении срока. Сервис не создаёт резервных копий.",
        privacyAccess: "Любой, у кого есть ссылка, может посмотреть, скачать, сохранить или распространить видео. Активные ссылки доступны оператору сервиса для модерации злоупотреблений. Делитесь только с теми, кому доверяете.",
        compressing: "Сжатие для публикации…",
        uploading: "Безопасная отправка…",
        tooLarge: "Эту запись нельзя уменьшить до 100 МБ без слишком большой потери качества.",
        failed: "Не удалось создать временную ссылку",
        tourCaption: "Сожмите готовую запись на этом Mac и поделитесь ею на 1 или 6 часов."
    )

    static let es = RecorderShareStrings(
        caption: "Elige 1 o 6 horas. El vídeo final se comprime en este Mac para quedar por debajo de 100 MB y se elimina automáticamente.",
        privacyData: "Vorssaint envía solo el vídeo final creado a partir de esta grabación, incluido el audio que conservaste, y el plazo elegido. No envía tu nombre, cuenta ni identificador del dispositivo.",
        privacyStorage: "Los proveedores de red y el servicio procesan temporalmente tu IP pública para evitar abusos. El vídeo y los datos del enlace se eliminan para siempre cuando borras el enlace o vence. El servicio no crea copias de seguridad.",
        privacyAccess: "Cualquiera que tenga el enlace puede ver, descargar, guardar o redistribuir el vídeo. El operador del servicio puede acceder a los enlaces activos para moderar abusos. Compártelos solo con personas de confianza.",
        compressing: "Comprimiendo para compartir…",
        uploading: "Subiendo de forma segura…",
        tooLarge: "Esta grabación no cabe en 100 MB sin perder demasiada calidad.",
        failed: "No se pudo crear el enlace temporal",
        tourCaption: "Comprime una grabación terminada en este Mac y compártela durante 1 o 6 horas."
    )

    static let de = RecorderShareStrings(
        caption: "Wähle 1 oder 6 Stunden. Das fertige Video wird auf diesem Mac auf unter 100 MB komprimiert und automatisch gelöscht.",
        privacyData: "Vorssaint sendet nur das fertige Video aus dieser Aufnahme, einschließlich des beibehaltenen Tons, und die gewählte Dauer. Name, Konto und Gerätekennung werden nicht gesendet.",
        privacyStorage: "Netzwerkanbieter und der Dienst verarbeiten deine öffentliche IP vorübergehend zum Schutz vor Missbrauch. Video und Linkdaten werden beim Löschen oder nach Ablauf dauerhaft entfernt. Der Dienst erstellt keine Sicherungskopien.",
        privacyAccess: "Jeder mit dem Link kann das Video ansehen, laden, speichern oder weitergeben. Aktive Links sind für den Dienstbetreiber zur Missbrauchsprüfung verfügbar. Teile sie nur mit vertrauenswürdigen Personen.",
        compressing: "Wird zum Teilen komprimiert…",
        uploading: "Wird sicher hochgeladen…",
        tooLarge: "Diese Aufnahme passt nicht ohne zu großen Qualitätsverlust unter 100 MB.",
        failed: "Der temporäre Link konnte nicht erstellt werden",
        tourCaption: "Komprimiere eine fertige Aufnahme auf diesem Mac und teile sie für 1 oder 6 Stunden."
    )

    static let fr = RecorderShareStrings(
        caption: "Choisissez 1 ou 6 heures. La vidéo finale est compressée sur ce Mac à moins de 100 Mo, puis supprimée automatiquement.",
        privacyData: "Vorssaint envoie uniquement la vidéo finale créée à partir de cet enregistrement, avec l'audio conservé, et la durée choisie. Votre nom, compte et identifiant d'appareil ne sont pas envoyés.",
        privacyStorage: "Les fournisseurs réseau et le service traitent temporairement votre adresse IP publique pour prévenir les abus. La vidéo et les données du lien sont définitivement supprimées quand vous effacez le lien ou à son expiration. Le service ne crée aucune sauvegarde.",
        privacyAccess: "Toute personne disposant du lien peut voir, télécharger, enregistrer ou redistribuer la vidéo. Les liens actifs sont accessibles à l'opérateur du service pour modérer les abus. Partagez-les uniquement avec des personnes de confiance.",
        compressing: "Compression pour le partage…",
        uploading: "Envoi sécurisé…",
        tooLarge: "Cet enregistrement ne peut pas tenir sous 100 Mo sans perdre trop de qualité.",
        failed: "Impossible de créer le lien temporaire",
        tourCaption: "Compressez un enregistrement terminé sur ce Mac et partagez-le pendant 1 ou 6 heures."
    )

    static let it = RecorderShareStrings(
        caption: "Scegli 1 o 6 ore. Il video finale viene compresso su questo Mac sotto i 100 MB ed eliminato automaticamente.",
        privacyData: "Vorssaint invia solo il video finale creato da questa registrazione, incluso l'audio mantenuto, e la durata scelta. Non invia nome, account o identificativo del dispositivo.",
        privacyStorage: "I fornitori di rete e il servizio elaborano temporaneamente il tuo IP pubblico per prevenire abusi. Il video e i dati del link vengono eliminati definitivamente quando cancelli il link o alla scadenza. Il servizio non crea backup.",
        privacyAccess: "Chiunque abbia il link può vedere, scaricare, salvare o ridistribuire il video. I link attivi sono disponibili al gestore del servizio per moderare gli abusi. Condividili solo con persone fidate.",
        compressing: "Compressione per la condivisione…",
        uploading: "Caricamento sicuro…",
        tooLarge: "Questa registrazione non può restare sotto i 100 MB senza perdere troppa qualità.",
        failed: "Impossibile creare il link temporaneo",
        tourCaption: "Comprimi una registrazione finita su questo Mac e condividila per 1 o 6 ore."
    )

    static let ja = RecorderShareStrings(
        caption: "1時間または6時間を選びます。完成した動画はこのMacで100 MB未満に圧縮され、自動的に削除されます。",
        privacyData: "Vorssaintが送信するのは、この録画から作成した完成動画、残した音声、選んだ有効期限だけです。名前、アカウント、デバイス識別子は送信しません。",
        privacyStorage: "不正利用を防ぐため、ネットワーク事業者とサービスは公開IPアドレスを一時的に処理します。動画とリンク情報は、リンクの削除時または期限切れ時に完全に削除されます。サービスはバックアップを作成しません。",
        privacyAccess: "リンクを知っている人は誰でも動画を閲覧、ダウンロード、保存、再配布できます。不正利用の確認のため、運営者は有効なリンクを確認できます。信頼できる相手とのみ共有してください。",
        compressing: "共有用に圧縮中…",
        uploading: "安全にアップロード中…",
        tooLarge: "この録画は、品質を大きく落とさずに100 MB未満にできません。",
        failed: "一時リンクを作成できませんでした",
        tourCaption: "完成した録画をこのMacで圧縮し、1時間または6時間だけ共有できます。"
    )

    static let ko = RecorderShareStrings(
        caption: "1시간 또는 6시간을 선택하세요. 완성된 동영상은 이 Mac에서 100MB 미만으로 압축되고 자동으로 삭제됩니다.",
        privacyData: "Vorssaint는 이 녹화에서 만든 최종 동영상과 유지한 오디오, 선택한 만료 시간만 전송합니다. 이름, 계정 또는 기기 식별자는 전송하지 않습니다.",
        privacyStorage: "오용을 막기 위해 네트워크 제공업체와 서비스가 공개 IP 주소를 일시적으로 처리합니다. 동영상과 링크 정보는 링크를 삭제하거나 만료되면 영구 삭제됩니다. 서비스는 백업을 만들지 않습니다.",
        privacyAccess: "링크가 있는 사람은 누구나 동영상을 보고 다운로드하고 저장하거나 재배포할 수 있습니다. 서비스 운영자는 오용 검토를 위해 활성 링크를 볼 수 있습니다. 신뢰하는 사람에게만 공유하세요.",
        compressing: "공유용으로 압축 중…",
        uploading: "안전하게 업로드 중…",
        tooLarge: "이 녹화는 품질을 너무 많이 낮추지 않고 100MB 미만으로 만들 수 없습니다.",
        failed: "임시 링크를 만들 수 없습니다",
        tourCaption: "완성된 녹화를 이 Mac에서 압축해 1시간 또는 6시간 동안 공유하세요."
    )

    static let zhHans = RecorderShareStrings(
        caption: "选择1小时或6小时。最终视频会在这台Mac上压缩到100 MB以内，并自动删除。",
        privacyData: "Vorssaint只会发送由这段录制生成的最终视频、你保留的音频和所选有效期，不会发送姓名、账户或设备标识符。",
        privacyStorage: "网络服务商和本服务会临时处理你的公网IP地址以防止滥用。删除链接或到期后，视频和链接信息会被永久删除。本服务不会创建备份。",
        privacyAccess: "任何获得链接的人都能查看、下载、保存或再次分发视频。服务运营者可查看有效链接以处理滥用问题。请只与信任的人分享。",
        compressing: "正在压缩以便分享…",
        uploading: "正在安全上传…",
        tooLarge: "这段录制无法在不过度损失画质的情况下压缩到100 MB以内。",
        failed: "无法创建临时链接",
        tourCaption: "在这台Mac上压缩完成的录制，并分享1小时或6小时。"
    )

    static let zhTW = RecorderShareStrings(
        caption: "選擇1小時或6小時。最終影片會在這台Mac上壓縮至100 MB以內，並自動刪除。",
        privacyData: "Vorssaint只會傳送由這段錄製建立的最終影片、你保留的音訊和所選期限，不會傳送姓名、帳號或裝置識別碼。",
        privacyStorage: "網路服務商與本服務會暫時處理你的公開IP位址以防止濫用。刪除連結或到期後，影片與連結資料會被永久刪除。本服務不會建立備份。",
        privacyAccess: "任何取得連結的人都能檢視、下載、儲存或再次散佈影片。服務營運者可檢視有效連結以處理濫用問題。請只與信任的人分享。",
        compressing: "正在壓縮以供分享…",
        uploading: "正在安全上傳…",
        tooLarge: "這段錄製無法在不過度損失畫質的情況下壓縮至100 MB以內。",
        failed: "無法建立暫時連結",
        tourCaption: "在這台Mac上壓縮完成的錄製，並分享1小時或6小時。"
    )

    static let zhHK = RecorderShareStrings(
        caption: "選擇1小時或6小時。最終影片會在這部Mac上壓縮至100 MB以內，並自動刪除。",
        privacyData: "Vorssaint只會傳送由這段錄製建立的最終影片、你保留的音訊和所選期限，不會傳送姓名、帳戶或裝置識別碼。",
        privacyStorage: "網絡供應商與本服務會暫時處理你的公開IP位址以防止濫用。刪除連結或到期後，影片與連結資料會被永久刪除。本服務不會建立備份。",
        privacyAccess: "任何取得連結的人都能檢視、下載、儲存或再次分發影片。服務營運者可檢視有效連結以處理濫用問題。請只與信任的人分享。",
        compressing: "正在壓縮以供分享…",
        uploading: "正在安全上載…",
        tooLarge: "這段錄製無法在不過度損失畫質的情況下壓縮至100 MB以內。",
        failed: "無法建立暫時連結",
        tourCaption: "在這部Mac上壓縮完成的錄製，並分享1小時或6小時。"
    )
}
