// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchAppleMusicLyricsStrings {
    let provider: String
    let appleMusic: String
    let hint: String
    let connect: String
    let disconnect: String
    let signIn: String
    let subscription: String
    let denied: String
    let only: String
    let accessActive: String
    let accessInactive: String
    let enabling: String
    let accountHint: String
    let experimentalHint: String
    let permissionDenied: String
    let permissionHint: String
    let verified: String
    let refreshHint: String
}

extension FeatureStrings {
    static func notchAppleMusicLyrics(_ language: AppLanguage) -> NotchAppleMusicLyricsStrings {
        switch language {
        case .enUS: return .init(provider: "Lyrics provider", appleMusic: "Apple Music",
            hint: "Synchronized lyrics from Apple Music for songs playing in Music.app. Requires an active subscription.",
            connect: "Enable Apple Music access…", disconnect: "Disable Apple Music access", signIn: "Allow Apple Music access to load lyrics.",
            subscription: "An active Apple Music subscription is required.", denied: "Apple Music denied access to lyrics. Reconnect or try again later.",
            only: "Play a song in Music.app to use Apple Music lyrics.",
            accessActive: "Access enabled",
            accessInactive: "Access disabled",
            enabling: "Enabling access…",
            accountHint: "Uses the account in Music.app. Disabling access does not sign out or revoke macOS permission. To change accounts, use Music.app, then disable and enable access here.",
            experimentalHint: "Experimental: Apple service changes may interrupt lyric access.",
            permissionDenied: "Apple Music permission required",
            permissionHint: "Allow Apple Music access for Vorssaint in macOS privacy settings.",
            verified: "Apple Music lyrics loaded for the current song.",
            refreshHint: "Disable and enable access again to refresh Apple Music access.")
        case .ptBR: return .init(provider: "Fonte das letras", appleMusic: "Apple Music",
            hint: "Letras sincronizadas do Apple Music para músicas no app Música. Requer uma assinatura ativa.",
            connect: "Ativar acesso ao Apple Music…", disconnect: "Desativar acesso ao Apple Music", signIn: "Permita o acesso ao Apple Music para carregar as letras.",
            subscription: "É necessária uma assinatura ativa do Apple Music.", denied: "O Apple Music negou acesso às letras. Reconecte ou tente mais tarde.", only: "Toque uma música no app Música para usar letras do Apple Music.",
            accessActive: "Acesso ativado",
            accessInactive: "Acesso desativado",
            enabling: "Ativando acesso…",
            accountHint: "Usa a conta do app Música. Desativar o acesso não encerra a sessão nem revoga a permissão do macOS. Para trocar de conta, use o app Música e depois desative e reative o acesso aqui.",
            experimentalHint: "Experimental: mudanças no serviço da Apple podem interromper o acesso às letras.",
            permissionDenied: "Permissão do Apple Music necessária",
            permissionHint: "Permita o acesso do Vorssaint ao Apple Music nos ajustes de privacidade do macOS.",
            verified: "Letras do Apple Music carregadas para a música atual.",
            refreshHint: "Desative e reative o acesso para atualizar o acesso ao Apple Music.")
        case .tr: return .init(provider: "Şarkı sözü kaynağı", appleMusic: "Apple Music",
            hint: "Müzik uygulamasında çalan şarkılar için Apple Music’ten eşzamanlı sözler. Etkin abonelik gerekir.",
            connect: "Apple Music erişimini etkinleştir…", disconnect: "Apple Music erişimini kapat", signIn: "Sözleri yüklemek için Apple Music erişimine izin verin.",
            subscription: "Etkin Apple Music aboneliği gerekir.", denied: "Apple Music sözlere erişimi reddetti. Yeniden bağlanın veya daha sonra deneyin.", only: "Apple Music sözlerini kullanmak için Müzik uygulamasında bir şarkı çalın.",
            accessActive: "Erişim açık",
            accessInactive: "Erişim kapalı",
            enabling: "Erişim etkinleştiriliyor…",
            accountHint: "Müzik uygulamasındaki hesabı kullanır. Erişimi kapatmak oturumu kapatmaz veya macOS iznini kaldırmaz. Hesabı Müzik uygulamasında değiştirin, ardından buradaki erişimi kapatıp yeniden açın.",
            experimentalHint: "Deneysel: Apple hizmetindeki değişiklikler sözlere erişimi kesebilir.",
            permissionDenied: "Apple Music izni gerekli",
            permissionHint: "macOS gizlilik ayarlarında Vorssaint için Apple Music erişimine izin verin.",
            verified: "Geçerli şarkının Apple Music sözleri yüklendi.",
            refreshHint: "Apple Music erişimini yenilemek için erişimi kapatıp yeniden açın.")
        case .ru: return .init(provider: "Источник текстов", appleMusic: "Apple Music",
            hint: "Синхронизированные тексты Apple Music для песен в приложении «Музыка». Нужна активная подписка.",
            connect: "Включить доступ к Apple Music…", disconnect: "Выключить доступ к Apple Music", signIn: "Разрешите доступ к Apple Music для загрузки текстов.",
            subscription: "Требуется активная подписка Apple Music.", denied: "Apple Music отказал в доступе к текстам. Подключитесь заново или попробуйте позже.", only: "Для текстов Apple Music включите песню в приложении «Музыка».",
            accessActive: "Доступ включён",
            accessInactive: "Доступ выключен",
            enabling: "Включение доступа…",
            accountHint: "Используется аккаунт приложения «Музыка». Выключение доступа не выходит из аккаунта и не отзывает разрешение macOS. Смените аккаунт в «Музыке», затем выключите и включите доступ здесь.",
            experimentalHint: "Экспериментально: изменения сервиса Apple могут нарушить доступ к текстам.",
            permissionDenied: "Нужно разрешение Apple Music",
            permissionHint: "Разрешите Vorssaint доступ к Apple Music в настройках конфиденциальности macOS.",
            verified: "Текст Apple Music для текущей песни загружен.",
            refreshHint: "Выключите и включите доступ, чтобы обновить доступ к Apple Music.")
        case .es: return .init(provider: "Proveedor de letras", appleMusic: "Apple Music",
            hint: "Letras sincronizadas de Apple Music para canciones reproducidas en Música. Requiere una suscripción activa.",
            connect: "Activar acceso a Apple Music…", disconnect: "Desactivar acceso a Apple Music", signIn: "Permite el acceso a Apple Music para cargar letras.",
            subscription: "Se requiere una suscripción activa a Apple Music.", denied: "Apple Music denegó el acceso a las letras. Vuelve a conectar o inténtalo más tarde.", only: "Reproduce una canción en Música para usar letras de Apple Music.",
            accessActive: "Acceso activado",
            accessInactive: "Acceso desactivado",
            enabling: "Activando acceso…",
            accountHint: "Usa la cuenta de Música. Desactivar el acceso no cierra la sesión ni revoca el permiso de macOS. Para cambiar de cuenta, usa Música y después desactiva y reactiva el acceso aquí.",
            experimentalHint: "Experimental: los cambios del servicio de Apple pueden interrumpir el acceso a las letras.",
            permissionDenied: "Se requiere permiso de Apple Music",
            permissionHint: "Permite el acceso de Vorssaint a Apple Music en los ajustes de privacidad de macOS.",
            verified: "Letras de Apple Music cargadas para la canción actual.",
            refreshHint: "Desactiva y reactiva el acceso para actualizar el acceso a Apple Music.")
        case .sk: return .init(provider: "Poskytovateľ textov", appleMusic: "Apple Music",
            hint: "Synchronizované texty z Apple Music pre skladby v apke Hudba. Vyžaduje aktívne predplatné.",
            connect: "Povoliť prístup k Apple Music…", disconnect: "Vypnúť prístup k Apple Music", signIn: "Na načítanie textov povoľte prístup k Apple Music.",
            subscription: "Vyžaduje sa aktívne predplatné Apple Music.", denied: "Apple Music odmietol prístup k textom. Znovu sa pripojte alebo skúste neskôr.", only: "Pre texty Apple Music pustite skladbu v apke Hudba.",
            accessActive: "Prístup zapnutý",
            accessInactive: "Prístup vypnutý",
            enabling: "Povoľovanie prístupu…",
            accountHint: "Používa účet v apke Hudba. Vypnutie prístupu vás neodhlási ani neodoberie povolenie macOS. Ak chcete zmeniť účet, použite apku Hudba a potom tu prístup vypnite a znovu zapnite.",
            experimentalHint: "Experimentálne: zmeny služby Apple môžu prerušiť prístup k textom.",
            permissionDenied: "Vyžaduje sa povolenie Apple Music",
            permissionHint: "Povoľte aplikácii Vorssaint prístup k Apple Music v nastaveniach súkromia macOS.",
            verified: "Texty z Apple Music pre aktuálnu skladbu boli načítané.",
            refreshHint: "Vypnite a znovu zapnite prístup na obnovenie prístupu k Apple Music.")
        case .de: return .init(provider: "Liedtextanbieter", appleMusic: "Apple Music",
            hint: "Synchronisierte Liedtexte von Apple Music für Songs in der Musik-App. Ein aktives Abo ist erforderlich.",
            connect: "Apple Music Zugriff aktivieren…", disconnect: "Apple Music Zugriff deaktivieren", signIn: "Erlaube den Zugriff auf Apple Music, um Liedtexte zu laden.",
            subscription: "Ein aktives Apple Music Abo ist erforderlich.", denied: "Apple Music hat den Zugriff auf Liedtexte verweigert. Verbinde dich erneut oder versuche es später.", only: "Spiele einen Song in der Musik-App, um Apple Music Liedtexte zu verwenden.",
            accessActive: "Zugriff aktiviert",
            accessInactive: "Zugriff deaktiviert",
            enabling: "Zugriff wird aktiviert…",
            accountHint: "Nutzt den Account in der Musik-App. Das Deaktivieren meldet dich nicht ab und widerruft keine macOS-Berechtigung. Ändere den Account in der Musik-App und deaktiviere und aktiviere danach hier den Zugriff.",
            experimentalHint: "Experimentell: Änderungen bei Apple können den Liedtextzugriff unterbrechen.",
            permissionDenied: "Apple Music Berechtigung erforderlich",
            permissionHint: "Erlaube Vorssaint den Apple Music Zugriff in den macOS-Datenschutzeinstellungen.",
            verified: "Apple Music Liedtexte für den aktuellen Song geladen.",
            refreshHint: "Deaktiviere und aktiviere den Zugriff, um den Apple Music Zugriff zu erneuern.")
        case .fr: return .init(provider: "Fournisseur de paroles", appleMusic: "Apple Music",
            hint: "Paroles synchronisées d’Apple Music pour les morceaux lus dans Musique. Un abonnement actif est requis.",
            connect: "Activer l’accès à Apple Music…", disconnect: "Désactiver l’accès à Apple Music", signIn: "Autorisez l’accès à Apple Music pour charger les paroles.",
            subscription: "Un abonnement Apple Music actif est requis.", denied: "Apple Music a refusé l’accès aux paroles. Reconnectez-vous ou réessayez plus tard.", only: "Lisez un morceau dans Musique pour utiliser les paroles Apple Music.",
            accessActive: "Accès activé",
            accessInactive: "Accès désactivé",
            enabling: "Activation de l’accès…",
            accountHint: "Utilise le compte de Musique. Désactiver l’accès ne déconnecte pas le compte et ne révoque pas l’autorisation macOS. Changez de compte dans Musique, puis désactivez et réactivez l’accès ici.",
            experimentalHint: "Expérimental : les changements du service Apple peuvent interrompre l’accès aux paroles.",
            permissionDenied: "Autorisation Apple Music requise",
            permissionHint: "Autorisez Vorssaint à accéder à Apple Music dans les réglages de confidentialité de macOS.",
            verified: "Paroles Apple Music chargées pour le morceau actuel.",
            refreshHint: "Désactivez et réactivez l’accès pour renouveler l’accès à Apple Music.")
        case .it: return .init(provider: "Fonte dei testi", appleMusic: "Apple Music",
            hint: "Testi sincronizzati da Apple Music per i brani riprodotti in Musica. Richiede un abbonamento attivo.",
            connect: "Attiva accesso ad Apple Music…", disconnect: "Disattiva accesso ad Apple Music", signIn: "Consenti l’accesso ad Apple Music per caricare i testi.",
            subscription: "È richiesto un abbonamento Apple Music attivo.", denied: "Apple Music ha negato l’accesso ai testi. Ricollegati o riprova più tardi.", only: "Riproduci un brano in Musica per usare i testi di Apple Music.",
            accessActive: "Accesso attivo",
            accessInactive: "Accesso disattivato",
            enabling: "Attivazione dell’accesso…",
            accountHint: "Usa l’account di Musica. Disattivare l’accesso non esegue il logout né revoca il permesso macOS. Cambia account in Musica, poi disattiva e riattiva l’accesso qui.",
            experimentalHint: "Sperimentale: le modifiche del servizio Apple possono interrompere l’accesso ai testi.",
            permissionDenied: "Permesso Apple Music necessario",
            permissionHint: "Consenti a Vorssaint l’accesso ad Apple Music nelle impostazioni di privacy di macOS.",
            verified: "Testi Apple Music caricati per il brano attuale.",
            refreshHint: "Disattiva e riattiva l’accesso per aggiornare l’accesso ad Apple Music.")
        case .ja: return .init(provider: "歌詞の提供元", appleMusic: "Apple Music",
            hint: "ミュージックアプリで再生中の曲の同期歌詞をApple Musicから取得します。有効なサブスクリプションが必要です。",
            connect: "Apple Musicへのアクセスを有効にする…", disconnect: "Apple Musicへのアクセスを無効にする", signIn: "歌詞を読み込むにはApple Musicへのアクセスを許可してください。",
            subscription: "有効なApple Musicのサブスクリプションが必要です。", denied: "Apple Musicが歌詞へのアクセスを拒否しました。再接続するか、後でお試しください。", only: "Apple Musicの歌詞を使うにはミュージックアプリで曲を再生してください。",
            accessActive: "アクセス有効",
            accessInactive: "アクセス無効",
            enabling: "アクセスを有効にしています…",
            accountHint: "ミュージックアプリのアカウントを使用します。アクセスを無効にしてもサインアウトやmacOSの許可の取り消しは行いません。アカウントを変更する場合はミュージックアプリで変更し、ここでアクセスを無効にしてから再び有効にしてください。",
            experimentalHint: "実験的機能：Appleのサービス変更で歌詞にアクセスできなくなる場合があります。",
            permissionDenied: "Apple Musicの許可が必要です",
            permissionHint: "macOSのプライバシー設定でVorssaintにApple Musicへのアクセスを許可してください。",
            verified: "現在の曲のApple Music歌詞を読み込みました。",
            refreshHint: "アクセスを無効にしてから再び有効にしてApple Musicへのアクセスを更新してください。")
        case .ko: return .init(provider: "가사 제공자", appleMusic: "Apple Music",
            hint: "음악 앱에서 재생 중인 곡의 동기화된 가사를 Apple Music에서 가져옵니다. 활성 구독이 필요합니다.",
            connect: "Apple Music 접근 활성화…", disconnect: "Apple Music 접근 비활성화", signIn: "가사를 불러오려면 Apple Music 접근을 허용하세요.",
            subscription: "활성 Apple Music 구독이 필요합니다.", denied: "Apple Music이 가사 접근을 거부했습니다. 다시 연결하거나 나중에 시도하세요.", only: "Apple Music 가사를 사용하려면 음악 앱에서 곡을 재생하세요.",
            accessActive: "접근 활성화됨",
            accessInactive: "접근 비활성화됨",
            enabling: "접근 활성화 중…",
            accountHint: "음악 앱의 계정을 사용합니다. 접근을 비활성화해도 로그아웃하거나 macOS 권한을 취소하지 않습니다. 음악 앱에서 계정을 변경한 후 여기서 접근을 비활성화하고 다시 활성화하세요.",
            experimentalHint: "실험적 기능: Apple 서비스 변경 시 가사 접근이 중단될 수 있습니다.",
            permissionDenied: "Apple Music 권한 필요",
            permissionHint: "macOS 개인정보 보호 설정에서 Vorssaint의 Apple Music 접근을 허용하세요.",
            verified: "현재 곡의 Apple Music 가사를 불러왔습니다.",
            refreshHint: "접근을 비활성화하고 다시 활성화하여 Apple Music 접근을 갱신하세요.")
        case .uk: return .init(provider: "Джерело текстів", appleMusic: "Apple Music",
            hint: "Синхронізовані тексти Apple Music для пісень у програмі «Музика». Потрібна активна підписка.",
            connect: "Увімкнути доступ до Apple Music…", disconnect: "Вимкнути доступ до Apple Music", signIn: "Дозвольте доступ до Apple Music для завантаження текстів.",
            subscription: "Потрібна активна підписка Apple Music.", denied: "Apple Music відмовив у доступі до текстів. Підключіться знову або спробуйте пізніше.", only: "Для текстів Apple Music увімкніть пісню в програмі «Музика».",
            accessActive: "Доступ увімкнено",
            accessInactive: "Доступ вимкнено",
            enabling: "Увімкнення доступу…",
            accountHint: "Використовує обліковий запис програми «Музика». Вимкнення доступу не виходить з облікового запису й не відкликає дозвіл macOS. Змініть запис у «Музиці», потім вимкніть та увімкніть доступ тут.",
            experimentalHint: "Експериментально: зміни сервісу Apple можуть порушити доступ до текстів.",
            permissionDenied: "Потрібен дозвіл Apple Music",
            permissionHint: "Дозвольте Vorssaint доступ до Apple Music у налаштуваннях приватності macOS.",
            verified: "Текст Apple Music для поточної пісні завантажено.",
            refreshHint: "Вимкніть та увімкніть доступ, щоб оновити доступ до Apple Music.")
        case .zhHans: return .init(provider: "歌词提供商", appleMusic: "Apple Music",
            hint: "从 Apple Music 获取音乐 App 中播放歌曲的同步歌词。需要有效订阅。",
            connect: "启用 Apple Music 访问…", disconnect: "停用 Apple Music 访问", signIn: "请允许访问 Apple Music 以载入歌词。",
            subscription: "需要有效的 Apple Music 订阅。", denied: "Apple Music 拒绝了歌词访问。请重新连接或稍后再试。", only: "请在音乐 App 中播放歌曲以使用 Apple Music 歌词。",
            accessActive: "访问已启用",
            accessInactive: "访问已停用",
            enabling: "正在启用访问…",
            accountHint: "使用音乐 App 中的账户。停用访问不会退出账户或撤销 macOS 权限。请在音乐 App 中更换账户，然后在此停用并重新启用访问。",
            experimentalHint: "实验性功能：Apple 服务变更可能中断歌词访问。",
            permissionDenied: "需要 Apple Music 权限",
            permissionHint: "请在 macOS 隐私设置中允许 Vorssaint 访问 Apple Music。",
            verified: "已载入当前歌曲的 Apple Music 歌词。",
            refreshHint: "停用并重新启用访问以刷新 Apple Music 访问。")
        case .zhTW: return .init(provider: "歌詞提供者", appleMusic: "Apple Music",
            hint: "從 Apple Music 取得音樂 App 中播放歌曲的同步歌詞。需要有效訂閱。",
            connect: "啟用 Apple Music 存取…", disconnect: "停用 Apple Music 存取", signIn: "請允許存取 Apple Music 以載入歌詞。",
            subscription: "需要有效的 Apple Music 訂閱。", denied: "Apple Music 拒絕了歌詞存取。請重新連接或稍後再試。", only: "請在音樂 App 中播放歌曲以使用 Apple Music 歌詞。",
            accessActive: "存取已啟用",
            accessInactive: "存取已停用",
            enabling: "正在啟用存取…",
            accountHint: "使用音樂 App 中的帳號。停用存取不會登出帳號或撤銷 macOS 權限。請在音樂 App 中更換帳號，然後在此停用並重新啟用存取。",
            experimentalHint: "實驗性功能：Apple 服務變更可能中斷歌詞存取。",
            permissionDenied: "需要 Apple Music 權限",
            permissionHint: "請在 macOS 隱私設定中允許 Vorssaint 存取 Apple Music。",
            verified: "已載入目前歌曲的 Apple Music 歌詞。",
            refreshHint: "停用並重新啟用存取以重新整理 Apple Music 存取。")
        case .zhHK: return .init(provider: "歌詞供應商", appleMusic: "Apple Music",
            hint: "從 Apple Music 取得音樂 App 中播放歌曲的同步歌詞。需要有效訂閱。",
            connect: "啟用 Apple Music 存取…", disconnect: "停用 Apple Music 存取", signIn: "請允許存取 Apple Music 以載入歌詞。",
            subscription: "需要有效的 Apple Music 訂閱。", denied: "Apple Music 拒絕了歌詞存取。請重新連接或稍後再試。", only: "請在音樂 App 中播放歌曲以使用 Apple Music 歌詞。",
            accessActive: "存取已啟用",
            accessInactive: "存取已停用",
            enabling: "正在啟用存取…",
            accountHint: "使用音樂 App 中的帳戶。停用存取不會登出帳戶或撤銷 macOS 權限。請在音樂 App 中更換帳戶，然後在此停用並重新啟用存取。",
            experimentalHint: "實驗性功能：Apple 服務更改可能中斷歌詞存取。",
            permissionDenied: "需要 Apple Music 權限",
            permissionHint: "請在 macOS 私隱設定中允許 Vorssaint 存取 Apple Music。",
            verified: "已載入目前歌曲的 Apple Music 歌詞。",
            refreshHint: "停用並重新啟用存取以重新整理 Apple Music 存取。")
        }
    }
}
