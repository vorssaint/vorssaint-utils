// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Type-safe accessor wrapper around the localized string catalogs.
/// Centralizes localization lookups for video downloader UI, progress badges, and error banners.
struct VideoDownloaderStrings {
    private let strings: Strings
    private let language: AppLanguage

    init(_ strings: Strings, language: AppLanguage = .enUS) {
        self.strings = strings
        self.language = language
    }

    var pageTitle: String { strings.videoDownloaderPageTitle }
    var hubDescription: String { strings.videoDownloaderHubDescription }
    var panelCaption: String { strings.videoDownloaderPanelCaption }
    var urlPlaceholder: String { strings.videoDownloaderUrlPlaceholder }
    var urlHelp: String { strings.videoDownloaderUrlHelp }
    var paste: String { strings.videoDownloaderPaste }
    var inspecting: String { strings.videoDownloaderInspecting }
    var video: String { strings.videoDownloaderVideo }
    var audio: String { strings.videoDownloaderAudio }
    var quality: String { strings.videoDownloaderQuality }
    var outputOptions: String {
        switch language {
        case .enUS: return "Output & options"
        case .ptBR: return "Saída e opções"
        case .tr: return "Çıktı ve seçenekler"
        case .ru: return "Вывод и параметры"
        case .es: return "Salida y opciones"
        case .de: return "Ausgabe & Optionen"
        case .fr: return "Sortie et options"
        case .it: return "Output e opzioni"
        case .ja: return "出力とオプション"
        case .ko: return "출력 및 옵션"
        case .zhHans: return "输出与选项"
        case .zhTW, .zhHK: return "輸出與選項"
        }
    }
    var heightFormat: String { strings.videoDownloaderHeightFormat }
    var qualityFallbackFormat: String { strings.videoDownloaderQualityFallbackFormat }
    var subtitles: String { strings.videoDownloaderSubtitles }
    var none: String { strings.videoDownloaderNone }
    var manual: String { strings.videoDownloaderManual }
    var automatic: String { strings.videoDownloaderAutomatic }
    var destination: String { strings.videoDownloaderDestination }
    var choose: String { strings.videoDownloaderChoose }
    var showInPanel: String { strings.videoDownloaderShowInPanel }
    var settingsCaption: String { strings.videoDownloaderSettingsCaption }
    var usageNotice: String { strings.videoDownloaderUsageNotice }
    var defaultLocation: String { strings.videoDownloaderDefaultLocation }
    var resetDownloads: String { strings.videoDownloaderResetDownloads }
    var embedThumbnail: String { strings.videoDownloaderEmbedThumbnail }
    var embedMetadata: String { strings.videoDownloaderEmbedMetadata }
    var embedChapters: String { strings.videoDownloaderEmbedChapters }
    var useCookies: String { strings.videoDownloaderUseCookies }
    var cookiesBrowser: String { strings.videoDownloaderCookiesBrowser }
    var cookiesNote: String { strings.videoDownloaderCookiesNote }
    var faq: String { strings.videoDownloaderFAQ }
    var cookiesDiskAccessNote: String { strings.videoDownloaderCookiesDiskAccessNote }
    var errorExtractorFormat: String { strings.videoDownloaderErrorExtractorFormat }
    var dependencies: String { strings.videoDownloaderDependencies }
    var missingToolsFormat: String { strings.videoDownloaderMissingToolsFormat }
    var installMissingTools: String { strings.videoDownloaderInstallMissingTools }
    var setUpDownloader: String { strings.videoDownloaderSetUpDownloader }
    var brewSetupNote: String {
        switch language {
        case .enUS: return "Homebrew installs only the missing downloader tools."
        case .ptBR: return "O Homebrew instala apenas as ferramentas de download ausentes."
        case .tr: return "Homebrew yalnızca eksik indirme araçlarını yükler."
        case .ru: return "Homebrew установит только отсутствующие инструменты загрузки."
        case .es: return "Homebrew solo instala las herramientas de descarga que faltan."
        case .de: return "Homebrew installiert nur die fehlenden Download-Werkzeuge."
        case .fr: return "Homebrew installe uniquement les outils de téléchargement manquants."
        case .it: return "Homebrew installa solo gli strumenti di download mancanti."
        case .ja: return "Homebrew は不足しているダウンロードツールだけをインストールします。"
        case .ko: return "Homebrew는 누락된 다운로드 도구만 설치합니다."
        case .zhHans: return "Homebrew 只安装缺少的下载工具。"
        case .zhTW, .zhHK: return "Homebrew 只會安裝欠缺的下載工具。"
        }
    }
    var terminalSetupNote: String {
        switch language {
        case .enUS: return "Finish the downloader setup in Terminal. It may ask for confirmation or your password, then install any missing downloader tools."
        case .ptBR: return "Conclua a configuração do baixador no Terminal. Ele pode pedir confirmação ou senha e instalar as ferramentas de download ausentes."
        case .tr: return "İndirici kurulumunu Terminal'de tamamlayın. Onay veya parola isteyebilir ve eksik indirme araçlarını yükleyebilir."
        case .ru: return "Завершите настройку загрузчика в Terminal. Он может запросить подтверждение или пароль и установить отсутствующие инструменты загрузки."
        case .es: return "Completa la configuración del descargador en Terminal. Puede pedir confirmación o contraseña e instalar las herramientas de descarga que falten."
        case .de: return "Schließe die Einrichtung des Downloaders im Terminal ab. Dabei können Bestätigung oder Passwort verlangt und fehlende Download-Werkzeuge installiert werden."
        case .fr: return "Terminez la configuration du téléchargeur dans Terminal. Une confirmation ou un mot de passe peut être demandé, puis les outils manquants seront installés."
        case .it: return "Completa la configurazione del downloader in Terminale. Potrebbe chiedere conferma o password e installare gli strumenti mancanti."
        case .ja: return "Terminalでダウンローダーの設定を完了してください。確認やパスワードを求められる場合があり、不足しているツールをインストールします。"
        case .ko: return "Terminal에서 다운로더 설정을 완료하세요. 확인이나 암호를 요청한 후 누락된 다운로드 도구를 설치할 수 있습니다."
        case .zhHans: return "请在 Terminal 中完成下载器设置。系统可能要求确认或输入密码，然后安装缺少的下载工具。"
        case .zhTW, .zhHK: return "請在 Terminal 完成下載器設定。系統可能要求確認或密碼，之後安裝欠缺的下載工具。"
        }
    }
    var checkDependencies: String {
        switch language {
        case .enUS: return "Check again"
        case .ptBR: return "Verificar novamente"
        case .tr: return "Tekrar denetle"
        case .ru: return "Проверить снова"
        case .es: return "Comprobar de nuevo"
        case .de: return "Erneut prüfen"
        case .fr: return "Vérifier à nouveau"
        case .it: return "Controlla di nuovo"
        case .ja: return "もう一度確認"
        case .ko: return "다시 확인"
        case .zhHans: return "再次检查"
        case .zhTW, .zhHK: return "再次檢查"
        }
    }
    var checkingTools: String { strings.videoDownloaderCheckingTools }
    var downloadVideo: String { strings.videoDownloaderDownloadVideo }
    var downloadAudio: String { strings.videoDownloaderDownloadAudio }
    var downloading: String { strings.videoDownloaderDownloading }
    var percentFormat: String { strings.videoDownloaderPercentFormat }
    var speedFormat: String { strings.videoDownloaderSpeedFormat }
    var etaFormat: String { strings.videoDownloaderEtaFormat }
    var finalizing: String { strings.videoDownloaderFinalizing }
    var cancel: String { strings.videoDownloaderCancel }
    var cancelling: String { strings.videoDownloaderCancelling }
    var complete: String { strings.videoDownloaderComplete }
    var downloadAnother: String { strings.videoDownloaderDownloadAnother }
    var revealFinder: String { strings.videoDownloaderRevealFinder }
    var retry: String { strings.videoDownloaderRetry }
    var cancelled: String { strings.videoDownloaderCancelled }
    var failureTitle: String { strings.videoDownloaderFailureTitle }
    var uploader: String { strings.videoDownloaderUploader }
    var duration: String { strings.videoDownloaderDuration }
    var thumbnail: String { strings.videoDownloaderThumbnail }
    var errorURLInvalid: String { strings.videoDownloaderErrorURLInvalid }
    var errorURLTooLong: String { strings.videoDownloaderErrorURLTooLong }
    var errorURLControl: String { strings.videoDownloaderErrorURLControl }
    var errorURLCredentials: String { strings.videoDownloaderErrorURLCredentials }
    var errorInspectionTimeout: String { strings.videoDownloaderErrorInspectionTimeout }
    var errorInspectionFailed: String { strings.videoDownloaderErrorInspectionFailed }
    var errorInspectionTooLarge: String { strings.videoDownloaderErrorInspectionTooLarge }
    var errorInspectionMalformed: String { strings.videoDownloaderErrorInspectionMalformed }
    var inspectionFailedNotice: String { strings.videoDownloaderInspectionFailedNotice }
    var errorPlaylist: String { strings.videoDownloaderErrorPlaylist }
    var errorLive: String { strings.videoDownloaderErrorLive }
    var errorDRM: String { strings.videoDownloaderErrorDRM }
    var errorRestricted: String { strings.videoDownloaderErrorRestricted }
    var errorNoVideo: String { strings.videoDownloaderErrorNoVideo }
    var errorNoAudio: String { strings.videoDownloaderErrorNoAudio }
    var errorMissingDependencies: String { strings.videoDownloaderErrorMissingDependencies }
    var errorSetupBusy: String { strings.videoDownloaderErrorSetupBusy }
    var errorSetupFailed: String { strings.videoDownloaderErrorSetupFailed }
    var errorTerminalPermission: String { strings.videoDownloaderErrorTerminalPermission }
    var errorDownloadFailed: String { strings.videoDownloaderErrorDownloadFailed }
    var errorCookiesPermission: String { strings.videoDownloaderErrorCookiesPermission }
    var errorRateLimited: String {
        switch language {
        case .enUS:
            return "The video site temporarily blocked this request (often HTTP 429/403 or a CAPTCHA). Wait a moment and try again."
        case .ptBR:
            return "O site de vídeo bloqueou temporariamente esta solicitação (geralmente HTTP 429/403 ou CAPTCHA). Aguarde um pouco e tente novamente."
        case .tr:
            return "Video sitesi bu isteği geçici olarak engelledi (genellikle HTTP 429/403 veya CAPTCHA). Bir süre bekleyip tekrar deneyin."
        case .ru:
            return "Видеосайт временно заблокировал этот запрос (часто HTTP 429/403 или CAPTCHA). Подождите немного и повторите попытку."
        case .es:
            return "El sitio de vídeo bloqueó temporalmente esta solicitud (normalmente HTTP 429/403 o un CAPTCHA). Espera un momento y vuelve a intentarlo."
        case .de:
            return "Die Videoseite hat diese Anfrage vorübergehend blockiert (häufig HTTP 429/403 oder ein CAPTCHA). Warte einen Moment und versuche es erneut."
        case .fr:
            return "Le site vidéo a temporairement bloqué cette requête (souvent HTTP 429/403 ou un CAPTCHA). Attendez un instant, puis réessayez."
        case .it:
            return "Il sito video ha temporaneamente bloccato questa richiesta (spesso HTTP 429/403 o un CAPTCHA). Attendi un momento e riprova."
        case .ja:
            return "動画サイトがこのリクエストを一時的にブロックしました（HTTP 429/403 や CAPTCHA のことがあります）。少し待ってからもう一度お試しください。"
        case .ko:
            return "동영상 사이트가 이 요청을 일시적으로 차단했습니다(HTTP 429/403 또는 CAPTCHA일 수 있음). 잠시 후 다시 시도하세요."
        case .zhHans:
            return "视频站点暂时阻止了此请求（通常为 HTTP 429/403 或验证码）。请稍等片刻后重试。"
        case .zhTW, .zhHK:
            return "影片網站暫時封鎖了這次請求（通常是 HTTP 429/403 或驗證碼）。請稍候片刻再試。"
        }
    }
    var errorEJSComponent: String {
        switch language {
        case .enUS:
            return "The JavaScript challenge solver for this site couldn't be fetched from GitHub (needed for some videos). Check your network connection and try again."
        case .ptBR:
            return "O solucionador de desafios JavaScript deste site não pôde ser baixado do GitHub (necessário para alguns vídeos). Verifique sua conexão de rede e tente novamente."
        case .tr:
            return "Bu sitenin JavaScript zorluk çözücüsü GitHub'dan indirilemedi (bazı videolar için gerekli). İnternet bağlantınızı kontrol edip yeniden deneyin."
        case .ru:
            return "Не удалось загрузить решатель JavaScript-задач для этого сайта с GitHub (нужен для некоторых видео). Проверьте подключение к сети и повторите попытку."
        case .es:
            return "No se pudo descargar el solucionador de desafíos de JavaScript de este sitio desde GitHub (necesario para algunos vídeos). Comprueba tu conexión a internet e inténtalo de nuevo."
        case .de:
            return "Der JavaScript-Challenge-Löser für diese Website konnte nicht von GitHub geladen werden (für manche Videos nötig). Prüfe deine Internetverbindung und versuche es erneut."
        case .fr:
            return "Le résolveur de défi JavaScript de ce site n’a pas pu être téléchargé depuis GitHub (nécessaire pour certaines vidéos). Vérifiez votre connexion réseau et réessayez."
        case .it:
            return "Impossibile scaricare il risolutore di challenge JavaScript di questo sito da GitHub (necessario per alcuni video). Controlla la connessione di rete e riprova."
        case .ja:
            return "このサイトのJavaScriptチャレンジ解決スクリプトをGitHubから取得できませんでした（一部の動画で必要）。ネットワーク接続を確認してもう一度お試しください。"
        case .ko:
            return "이 사이트의 JavaScript 챌린지 해결 스크립트를 GitHub에서 가져올 수 없습니다(일부 동영상에 필요). 네트워크 연결을 확인하고 다시 시도하세요."
        case .zhHans:
            return "无法从 GitHub 获取此网站的 JavaScript 挑战解决脚本（某些视频需要）。请检查网络连接后重试。"
        case .zhTW, .zhHK:
            return "無法從 GitHub 取得此網站的 JavaScript 挑戰解決指令碼（部分影片需要）。請檢查網路連線後再試。"
        }
    }
    var cookiesCaptchaNote: String {
        switch language {
        case .enUS:
            return "If a site shows a CAPTCHA, too many requests, or a similar access block, open the same link in the selected browser, solve it there, then enable this setting and retry. Use the same browser and network."
        case .ptBR:
            return "Se o site mostrar um CAPTCHA ou bloqueio semelhante, abra o mesmo link no navegador selecionado, resolva-o lá, ative Usar cookies do navegador nas configurações do Baixador de vídeos e tente novamente."
        case .tr:
            return "Site bir CAPTCHA veya benzer bir erişim engeli gösterirse aynı bağlantıyı seçili tarayıcıda açın, CAPTCHA'yı orada çözün, Video Downloader ayarlarında Tarayıcı çerezlerini kullan seçeneğini açın ve yeniden deneyin."
        case .ru:
            return "Если сайт показывает CAPTCHA или похожую блокировку доступа, откройте ту же ссылку в выбранном браузере, решите CAPTCHA там, включите использование cookies браузера в настройках загрузчика видео и повторите попытку."
        case .es:
            return "Si el sitio muestra un CAPTCHA o un bloqueo similar, abre el mismo enlace en el navegador seleccionado, resuélvelo allí, activa Usar cookies del navegador en los ajustes del descargador de vídeos y vuelve a intentarlo."
        case .de:
            return "Wenn die Website ein CAPTCHA oder eine ähnliche Zugriffssperre zeigt, öffne denselben Link im ausgewählten Browser, löse es dort, aktiviere Browser-Cookies verwenden in den Video-Downloader-Einstellungen und versuche es erneut."
        case .fr:
            return "Si le site affiche un CAPTCHA ou un blocage similaire, ouvrez le même lien dans le navigateur choisi, résolvez-le, activez Utiliser les cookies du navigateur dans les réglages du téléchargeur vidéo, puis réessayez."
        case .it:
            return "Se il sito mostra un CAPTCHA o un blocco simile, apri lo stesso link nel browser selezionato, risolvilo lì, attiva Usa i cookie del browser nelle impostazioni del downloader video e riprova."
        case .ja:
            return "サイトにCAPTCHAや同様のアクセスブロックが表示されたら、選択したブラウザで同じリンクを開いてそこで解決し、ビデオダウンローダーの設定でブラウザCookieを使用を有効にして再試行してください。"
        case .ko:
            return "사이트에 CAPTCHA 또는 유사한 접근 차단이 표시되면 선택한 브라우저에서 같은 링크를 열어 CAPTCHA를 해결하고, 동영상 다운로더 설정에서 브라우저 쿠키 사용을 켠 후 다시 시도하세요."
        case .zhHans:
            return "如果网站显示 CAPTCHA 或类似的访问拦截，请在所选浏览器中打开同一链接并在那里完成验证，然后在视频下载器设置中启用使用浏览器 Cookie，再重试。"
        case .zhTW, .zhHK:
            return "如果網站顯示 CAPTCHA 或類似的存取封鎖，請在所選瀏覽器中開啟相同連結並完成驗證，然後在影片下載器設定中啟用使用瀏覽器 Cookie，再試一次。"
        }
    }
    var errorRemux: String { strings.videoDownloaderErrorRemux }
    var errorSubtitle: String { strings.videoDownloaderErrorSubtitle }
    var errorSubtitleRateLimited: String { strings.videoDownloaderErrorSubtitleRateLimited }
    var errorOptionalData: String { strings.videoDownloaderErrorOptionalData }
    var errorFileSafety: String { strings.videoDownloaderErrorFileSafety }

    var allValues: [String] {
        [
            strings.videoDownloaderPageTitle,
            strings.videoDownloaderHubDescription,
            strings.videoDownloaderPanelCaption,
            strings.videoDownloaderUrlPlaceholder,
            strings.videoDownloaderUrlHelp,
            strings.videoDownloaderPaste,
            strings.videoDownloaderInspecting,
            strings.videoDownloaderVideo,
            strings.videoDownloaderAudio,
            strings.videoDownloaderQuality,
            outputOptions,
            strings.videoDownloaderHeightFormat,
            strings.videoDownloaderQualityFallbackFormat,
            strings.videoDownloaderSubtitles,
            strings.videoDownloaderNone,
            strings.videoDownloaderManual,
            strings.videoDownloaderAutomatic,
            strings.videoDownloaderDestination,
            strings.videoDownloaderChoose,
            strings.videoDownloaderShowInPanel,
            strings.videoDownloaderSettingsCaption,
            strings.videoDownloaderUsageNotice,
            strings.videoDownloaderDefaultLocation,
            strings.videoDownloaderResetDownloads,
            strings.videoDownloaderEmbedThumbnail,
            strings.videoDownloaderEmbedMetadata,
            strings.videoDownloaderEmbedChapters,
            strings.videoDownloaderUseCookies,
            strings.videoDownloaderCookiesBrowser,
            strings.videoDownloaderCookiesNote,
            strings.videoDownloaderFAQ,
            strings.videoDownloaderCookiesDiskAccessNote,
            strings.videoDownloaderErrorExtractorFormat,
            strings.videoDownloaderDependencies,
            strings.videoDownloaderMissingToolsFormat,
            strings.videoDownloaderInstallMissingTools,
            strings.videoDownloaderSetUpDownloader,
            brewSetupNote,
            terminalSetupNote,
            checkDependencies,
            strings.videoDownloaderCheckingTools,
            strings.videoDownloaderDownloadVideo,
            strings.videoDownloaderDownloadAudio,
            strings.videoDownloaderDownloading,
            strings.videoDownloaderPercentFormat,
            strings.videoDownloaderSpeedFormat,
            strings.videoDownloaderEtaFormat,
            strings.videoDownloaderFinalizing,
            strings.videoDownloaderCancel,
            strings.videoDownloaderCancelling,
            strings.videoDownloaderComplete,
            strings.videoDownloaderDownloadAnother,
            strings.videoDownloaderRevealFinder,
            strings.videoDownloaderRetry,
            strings.videoDownloaderCancelled,
            strings.videoDownloaderFailureTitle,
            strings.videoDownloaderUploader,
            strings.videoDownloaderDuration,
            strings.videoDownloaderThumbnail,
            strings.videoDownloaderErrorURLInvalid,
            strings.videoDownloaderErrorURLTooLong,
            strings.videoDownloaderErrorURLControl,
            strings.videoDownloaderErrorURLCredentials,
            strings.videoDownloaderErrorInspectionTimeout,
            strings.videoDownloaderErrorInspectionFailed,
            strings.videoDownloaderErrorInspectionTooLarge,
            strings.videoDownloaderErrorInspectionMalformed,
            strings.videoDownloaderInspectionFailedNotice,
            strings.videoDownloaderErrorPlaylist,
            strings.videoDownloaderErrorLive,
            strings.videoDownloaderErrorDRM,
            strings.videoDownloaderErrorRestricted,
            strings.videoDownloaderErrorNoVideo,
            strings.videoDownloaderErrorNoAudio,
            strings.videoDownloaderErrorMissingDependencies,
            strings.videoDownloaderErrorSetupBusy,
            strings.videoDownloaderErrorSetupFailed,
            strings.videoDownloaderErrorTerminalPermission,
            strings.videoDownloaderErrorDownloadFailed,
            strings.videoDownloaderErrorCookiesPermission,
            errorRateLimited,
            cookiesCaptchaNote,
            errorEJSComponent,
            strings.videoDownloaderErrorRemux,
            strings.videoDownloaderErrorSubtitle,
            strings.videoDownloaderErrorSubtitleRateLimited,
            strings.videoDownloaderErrorOptionalData,
            strings.videoDownloaderErrorFileSafety,
        ]
    }

    var requiredErrors: [String] {
        [
            errorURLInvalid,
            errorURLTooLong,
            errorURLControl,
            errorURLCredentials,
            errorInspectionTimeout,
            errorInspectionFailed,
            errorInspectionTooLarge,
            errorInspectionMalformed,
            errorPlaylist,
            errorLive,
            errorDRM,
            errorRestricted,
            errorNoVideo,
            errorNoAudio,
            errorMissingDependencies,
            errorSetupBusy,
            errorSetupFailed,
            errorTerminalPermission,
            errorDownloadFailed,
            errorCookiesPermission,
            errorRateLimited,
            errorEJSComponent,
            errorRemux,
            errorSubtitle,
            errorSubtitleRateLimited,
            errorOptionalData,
            errorFileSafety,
        ]
    }

    func message(for error: VideoURLValidationError) -> String {
        switch error {
        case .tooLong: return errorURLTooLong
        case .controlCharacter: return errorURLControl
        case .credentials: return errorURLCredentials
        case .empty, .unsupportedScheme, .missingHost, .malformed: return errorURLInvalid
        }
    }

    func message(for error: VideoDownloaderFailure) -> String {
        switch error {
        case .inspectionTimedOut: return errorInspectionTimeout
        case .inspectionFailed: return errorInspectionFailed
        case .inspectionTooLarge: return errorInspectionTooLarge
        case .malformedInspection: return errorInspectionMalformed
        case .playlist: return errorPlaylist
        case .live: return errorLive
        case .drm: return errorDRM
        case .restricted: return errorRestricted
        case .missingDependencies: return errorMissingDependencies
        case .setupBusy: return errorSetupBusy
        case .setupFailed: return errorSetupFailed
        case .terminalPermission: return errorTerminalPermission
        case .downloadFailed: return errorDownloadFailed
        case .cookiesPermission: return errorCookiesPermission
        case .rateLimited: return errorRateLimited
        case .ejsComponentFailure: return errorEJSComponent
        case .mp4Remux: return errorRemux
        case .fileSafety: return errorFileSafety
        case .cancelled: return cancelled
        case let .extractorError(message): return String(format: errorExtractorFormat, message)
        }
    }

    func message(for warning: VideoDownloaderWarning) -> String {
        switch warning {
        case .subtitle: return errorSubtitle
        case .subtitleRateLimited: return errorSubtitleRateLimited
        case .artwork, .metadata, .chapters: return errorOptionalData
        }
    }
}

extension Strings {
    var videoDownloader: VideoDownloaderStrings { VideoDownloaderStrings(self) }
}

extension FeatureStrings {
    static func videoDownloader(_ language: AppLanguage) -> VideoDownloaderStrings {
        switch language {
        case .enUS: return VideoDownloaderStrings(Strings.enUS, language: .enUS)
        case .ptBR: return VideoDownloaderStrings(Strings.ptBR, language: .ptBR)
        case .tr: return VideoDownloaderStrings(Strings.tr, language: .tr)
        case .ru: return VideoDownloaderStrings(Strings.ru, language: .ru)
        case .es: return VideoDownloaderStrings(Strings.es, language: .es)
        case .de: return VideoDownloaderStrings(Strings.de, language: .de)
        case .fr: return VideoDownloaderStrings(Strings.fr, language: .fr)
        case .it: return VideoDownloaderStrings(Strings.it, language: .it)
        case .ja: return VideoDownloaderStrings(Strings.ja, language: .ja)
        case .ko: return VideoDownloaderStrings(Strings.ko, language: .ko)
        case .zhHans: return VideoDownloaderStrings(Strings.zhHans, language: .zhHans)
        case .zhTW: return VideoDownloaderStrings(Strings.zhTW, language: .zhTW)
        case .zhHK: return VideoDownloaderStrings(Strings.zhHK, language: .zhHK)
        }
    }
}
