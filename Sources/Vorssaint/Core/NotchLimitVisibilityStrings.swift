// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where each limits account shows, in Settings, and the API key's figures
/// in the Claude card's header.
struct NotchLimitVisibilityStrings {
    let title: String
    let explanation: String
    /// The column of switches for the AI page and the resting island.
    let island: String
    let lockScreen: String
    let seatDetailFormat: String
    let claudeDetail: String
    let apiDetail: String
    let codexDetail: String
    /// Why a place has no switch for an account.
    let notShown: String
    /// The API key's spending this month, in a pill with little room.
    let apiMonth: String
    let creditsLeftFormat: String

    func seatDetail(_ folder: String) -> String { String(format: seatDetailFormat, folder) }
    func creditsLeft(_ amount: String) -> String { String(format: creditsLeftFormat, amount) }
}

extension FeatureStrings {
    static func limitVisibility(_ language: AppLanguage) -> NotchLimitVisibilityStrings {
        switch language {
        case .enUS: return NotchLimitVisibilityStrings(
            title: "Show limits",
            explanation: "Choose where each account’s limits appear. An account shown nowhere is not checked.",
            island: "Island",
            lockScreen: "Lock Screen",
            seatDetailFormat: "Seat · %@",
            claudeDetail: "Usual Claude Code sign-in",
            apiDetail: "API key · Claude Code outside the app",
            codexDetail: "Usual Codex home",
            notShown: "This place doesn’t show this account.",
            apiMonth: "Month",
            creditsLeftFormat: "~%@ left")
        case .ptBR: return NotchLimitVisibilityStrings(
            title: "Mostrar limites",
            explanation: "Escolha onde aparecem os limites de cada conta. Uma conta que não aparece em lugar nenhum não é verificada.",
            island: "Ilha",
            lockScreen: "Tela de Bloqueio",
            seatDetailFormat: "Assento · %@",
            claudeDetail: "Login habitual do Claude Code",
            apiDetail: "Chave de API · Claude Code fora do app",
            codexDetail: "Pasta habitual do Codex",
            notShown: "Este lugar não mostra esta conta.",
            apiMonth: "Mês",
            creditsLeftFormat: "~%@ restantes")
        case .tr: return NotchLimitVisibilityStrings(
            title: "Sınırları göster",
            explanation: "Her hesabın sınırlarının nerede görüneceğini seçin. Hiçbir yerde gösterilmeyen hesap denetlenmez.",
            island: "Ada",
            lockScreen: "Kilit Ekranı",
            seatDetailFormat: "Koltuk · %@",
            claudeDetail: "Her zamanki Claude Code oturumu",
            apiDetail: "API anahtarı · Uygulama dışındaki Claude Code",
            codexDetail: "Her zamanki Codex klasörü",
            notShown: "Bu yer bu hesabı göstermez.",
            apiMonth: "Ay",
            creditsLeftFormat: "~%@ kaldı")
        case .ru: return NotchLimitVisibilityStrings(
            title: "Показывать лимиты",
            explanation: "Выберите, где показывать лимиты каждого аккаунта. Аккаунт, который нигде не показан, не проверяется.",
            island: "Остров",
            lockScreen: "Экран блокировки",
            seatDetailFormat: "Место · %@",
            claudeDetail: "Обычный вход в Claude Code",
            apiDetail: "API-ключ · Claude Code вне приложения",
            codexDetail: "Обычная папка Codex",
            notShown: "Здесь этот аккаунт не показывается.",
            apiMonth: "Месяц",
            creditsLeftFormat: "Осталось ~%@")
        case .es: return NotchLimitVisibilityStrings(
            title: "Mostrar límites",
            explanation: "Elige dónde aparecen los límites de cada cuenta. Una cuenta que no aparece en ningún sitio no se comprueba.",
            island: "Isla",
            lockScreen: "Pantalla de bloqueo",
            seatDetailFormat: "Asiento · %@",
            claudeDetail: "Inicio de sesión habitual de Claude Code",
            apiDetail: "Clave de API · Claude Code fuera de la app",
            codexDetail: "Carpeta habitual de Codex",
            notShown: "Este lugar no muestra esta cuenta.",
            apiMonth: "Mes",
            creditsLeftFormat: "Quedan ~%@")
        case .sk: return NotchLimitVisibilityStrings(
            title: "Zobraziť limity",
            explanation: "Vyberte, kde sa zobrazia limity každého účtu. Účet, ktorý sa nikde nezobrazuje, sa nekontroluje.",
            island: "Ostrov",
            lockScreen: "Zamknutá obrazovka",
            seatDetailFormat: "Miesto · %@",
            claudeDetail: "Bežné prihlásenie do Claude Code",
            apiDetail: "Kľúč API · Claude Code mimo aplikácie",
            codexDetail: "Bežný priečinok Codexu",
            notShown: "Toto miesto tento účet nezobrazuje.",
            apiMonth: "Mesiac",
            creditsLeftFormat: "Zostáva ~%@")
        case .de: return NotchLimitVisibilityStrings(
            title: "Limits anzeigen",
            explanation: "Wähle, wo die Limits jedes Kontos erscheinen. Ein Konto, das nirgends erscheint, wird nicht geprüft.",
            island: "Insel",
            lockScreen: "Sperrbildschirm",
            seatDetailFormat: "Platz · %@",
            claudeDetail: "Übliche Claude Code-Anmeldung",
            apiDetail: "API-Schlüssel · Claude Code außerhalb der App",
            codexDetail: "Üblicher Codex-Ordner",
            notShown: "Dieser Ort zeigt dieses Konto nicht.",
            apiMonth: "Monat",
            creditsLeftFormat: "~%@ übrig")
        case .fr: return NotchLimitVisibilityStrings(
            title: "Afficher les limites",
            explanation: "Choisissez où apparaissent les limites de chaque compte. Un compte affiché nulle part n’est pas vérifié.",
            island: "Île",
            lockScreen: "Écran verrouillé",
            seatDetailFormat: "Siège · %@",
            claudeDetail: "Connexion habituelle à Claude Code",
            apiDetail: "Clé API · Claude Code hors de l’app",
            codexDetail: "Dossier Codex habituel",
            notShown: "Cet endroit n’affiche pas ce compte.",
            apiMonth: "Mois",
            creditsLeftFormat: "~%@ restants")
        case .it: return NotchLimitVisibilityStrings(
            title: "Mostra limiti",
            explanation: "Scegli dove compaiono i limiti di ogni account. Un account mostrato da nessuna parte non viene controllato.",
            island: "Isola",
            lockScreen: "Schermata di blocco",
            seatDetailFormat: "Posto · %@",
            claudeDetail: "Accesso abituale a Claude Code",
            apiDetail: "Chiave API · Claude Code fuori dall’app",
            codexDetail: "Cartella abituale di Codex",
            notShown: "Questo posto non mostra questo account.",
            apiMonth: "Mese",
            creditsLeftFormat: "~%@ rimasti")
        case .ja: return NotchLimitVisibilityStrings(
            title: "制限の表示",
            explanation: "各アカウントの制限をどこに表示するかを選びます。どこにも表示しないアカウントは確認しません。",
            island: "アイランド",
            lockScreen: "ロック画面",
            seatDetailFormat: "シート · %@",
            claudeDetail: "通常の Claude Code のサインイン",
            apiDetail: "API キー · アプリ外の Claude Code",
            codexDetail: "通常の Codex フォルダ",
            notShown: "この場所にはこのアカウントは表示されません。",
            apiMonth: "今月",
            creditsLeftFormat: "残り約 %@")
        case .ko: return NotchLimitVisibilityStrings(
            title: "한도 표시",
            explanation: "각 계정의 한도를 어디에 표시할지 선택하세요. 어디에도 표시하지 않는 계정은 확인하지 않습니다.",
            island: "아일랜드",
            lockScreen: "잠금 화면",
            seatDetailFormat: "시트 · %@",
            claudeDetail: "평소의 Claude Code 로그인",
            apiDetail: "API 키 · 앱 밖의 Claude Code",
            codexDetail: "평소의 Codex 폴더",
            notShown: "이곳에는 이 계정이 표시되지 않습니다.",
            apiMonth: "이번 달",
            creditsLeftFormat: "약 %@ 남음")
        case .uk: return NotchLimitVisibilityStrings(
            title: "Показувати ліміти",
            explanation: "Виберіть, де показувати ліміти кожного облікового запису. Обліковий запис, який ніде не показано, не перевіряється.",
            island: "Острів",
            lockScreen: "Екран блокування",
            seatDetailFormat: "Місце · %@",
            claudeDetail: "Звичайний вхід у Claude Code",
            apiDetail: "API-ключ · Claude Code поза застосунком",
            codexDetail: "Звичайна тека Codex",
            notShown: "Тут цей обліковий запис не показується.",
            apiMonth: "Місяць",
            creditsLeftFormat: "Залишилось ~%@")
        case .zhHans: return NotchLimitVisibilityStrings(
            title: "显示限额",
            explanation: "选择每个账户的限额显示在哪里。哪里都不显示的账户不会被检查。",
            island: "灵动岛",
            lockScreen: "锁定屏幕",
            seatDetailFormat: "席位 · %@",
            claudeDetail: "常用的 Claude Code 登录",
            apiDetail: "API 密钥 · App 外的 Claude Code",
            codexDetail: "常用的 Codex 文件夹",
            notShown: "此处不显示该账户。",
            apiMonth: "本月",
            creditsLeftFormat: "剩余约 %@")
        case .zhTW: return NotchLimitVisibilityStrings(
            title: "顯示額度",
            explanation: "選擇每個帳號的額度要顯示在哪裡。哪裡都不顯示的帳號不會被檢查。",
            island: "動態島",
            lockScreen: "鎖定畫面",
            seatDetailFormat: "席位 · %@",
            claudeDetail: "常用的 Claude Code 登入",
            apiDetail: "API 密鑰 · App 外的 Claude Code",
            codexDetail: "常用的 Codex 檔案夾",
            notShown: "此處不顯示這個帳號。",
            apiMonth: "本月",
            creditsLeftFormat: "剩餘約 %@")
        case .zhHK: return NotchLimitVisibilityStrings(
            title: "顯示額度",
            explanation: "選擇每個帳戶的額度要顯示喺邊度。邊度都唔顯示嘅帳戶唔會被檢查。",
            island: "動態島",
            lockScreen: "鎖定畫面",
            seatDetailFormat: "席位 · %@",
            claudeDetail: "常用嘅 Claude Code 登入",
            apiDetail: "API 密鑰 · App 以外嘅 Claude Code",
            codexDetail: "常用嘅 Codex 檔案夾",
            notShown: "呢度唔會顯示呢個帳戶。",
            apiMonth: "本月",
            creditsLeftFormat: "剩餘約 %@")
        }
    }
}
