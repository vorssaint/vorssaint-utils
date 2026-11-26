// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for hold-to-talk dictation, bilingual per-segment
/// detection, Meeting Recorder summary shortcuts, and local CLI summary
/// inference providers across all 15 supported languages.
struct SummaryProviderStrings {
    let languageMixed: String
    let dictationModeLabel: String
    let dictationModeToggle: String
    let dictationModeHold: String
    let dictationHoldListeningHUD: String
    let openSummaryTooltip: String
    let summaryProviderLabel: String
    let summaryModelLabel: String
    let summaryProviderAuto: String
    let summaryProviderClaude: String
    let summaryProviderCodex: String
    let summaryProviderGemini: String
    let summaryProviderOllama: String
    let summaryProviderApple: String
    let summaryProviderCaption: String
    let checkUpdatesToggle: String
    let refreshProvidersButton: String
    let checkUpdatesButton: String
    let updateButton: String
    let updatingStatus: String
    let providerReadyFormat: String
    let providerReadyNoVersion: String
    let providerNotInstalled: String
    let providerNotRunning: String
    let providerUpdateAvailableFormat: String
    let summaryGeneratedWithFormat: String

    static func localized(_ language: AppLanguage) -> SummaryProviderStrings {
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

extension SummaryProviderStrings {
    static let enUS = SummaryProviderStrings(
        languageMixed: "English & Hebrew",
        dictationModeLabel: "Trigger mode",
        dictationModeToggle: "Press to toggle",
        dictationModeHold: "Hold to talk",
        dictationHoldListeningHUD: "Listening… release shortcut to insert",
        openSummaryTooltip: "Open summary",
        summaryProviderLabel: "Summary provider",
        summaryModelLabel: "Summary model",
        summaryProviderAuto: "Auto (Best available)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Local)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Uses your local CLI subscriptions (Claude Code, Codex, Gemini CLI) or local Ollama, falling back to Apple Intelligence and local extractive summarization.",
        checkUpdatesToggle: "Check provider CLI updates",
        refreshProvidersButton: "Refresh",
        checkUpdatesButton: "Check updates",
        updateButton: "Update",
        updatingStatus: "Updating…",
        providerReadyFormat: "Ready · v%@",
        providerReadyNoVersion: "Ready",
        providerNotInstalled: "Not installed",
        providerNotRunning: "Installed · service not running",
        providerUpdateAvailableFormat: "Update available: v%@",
        summaryGeneratedWithFormat: "Generated with %@"
    )

    static let ptBR = SummaryProviderStrings(
        languageMixed: "Inglês e Hebraico",
        dictationModeLabel: "Modo de ativação",
        dictationModeToggle: "Pressionar para alternar",
        dictationModeHold: "Segurar para falar",
        dictationHoldListeningHUD: "Ouvindo… solte o atalho para inserir",
        openSummaryTooltip: "Abrir resumo",
        summaryProviderLabel: "Provedor de resumo",
        summaryModelLabel: "Modelo de resumo",
        summaryProviderAuto: "Automático (Melhor disponível)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Local)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Usa suas assinaturas locais de CLI (Claude Code, Codex, Gemini CLI) ou Ollama local, com fallback para Apple Intelligence e resumo local.",
        checkUpdatesToggle: "Verificar atualizações das CLIs",
        refreshProvidersButton: "Atualizar",
        checkUpdatesButton: "Verificar atualizações",
        updateButton: "Atualizar CLI",
        updatingStatus: "Atualizando…",
        providerReadyFormat: "Pronto · v%@",
        providerReadyNoVersion: "Pronto",
        providerNotInstalled: "Não instalado",
        providerNotRunning: "Instalado · serviço parado",
        providerUpdateAvailableFormat: "Atualização disponível: v%@",
        summaryGeneratedWithFormat: "Gerado com %@"
    )

    static let es = SummaryProviderStrings(
        languageMixed: "Inglés y Hebreo",
        dictationModeLabel: "Modo de activación",
        dictationModeToggle: "Pulsar para alternar",
        dictationModeHold: "Mantener para hablar",
        dictationHoldListeningHUD: "Escuchando… suelta el atajo para insertar",
        openSummaryTooltip: "Abrir resumen",
        summaryProviderLabel: "Proveedor de resumen",
        summaryModelLabel: "Modelo de resumen",
        summaryProviderAuto: "Automático (Mejor disponible)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Local)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Usa tus suscripciones locales de CLI (Claude Code, Codex, Gemini CLI) u Ollama local, con respaldo en Apple Intelligence y resumen extractivo local.",
        checkUpdatesToggle: "Comprobar actualizaciones de CLI",
        refreshProvidersButton: "Actualizar",
        checkUpdatesButton: "Buscar actualizaciones",
        updateButton: "Actualizar CLI",
        updatingStatus: "Actualizando…",
        providerReadyFormat: "Listo · v%@",
        providerReadyNoVersion: "Listo",
        providerNotInstalled: "No instalado",
        providerNotRunning: "Instalado · servicio detenido",
        providerUpdateAvailableFormat: "Actualización disponible: v%@",
        summaryGeneratedWithFormat: "Generado con %@"
    )

    static let sk = SummaryProviderStrings(
        languageMixed: "Angličtina a Hebrejčina",
        dictationModeLabel: "Režim spustenia",
        dictationModeToggle: "Stlačiť na prepnutie",
        dictationModeHold: "Podržať pre hovorenie",
        dictationHoldListeningHUD: "Počúva sa… uvoľnite skratku pre vloženie",
        openSummaryTooltip: "Otvoriť súhrn",
        summaryProviderLabel: "Poskytovateľ súhrnu",
        summaryModelLabel: "Model súhrnu",
        summaryProviderAuto: "Automaticky (Najlepší dostupný)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Lokálny)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Používa vaše lokálne CLI predplatné (Claude Code, Codex, Gemini CLI) alebo lokálnu Ollamu so zálohou na Apple Intelligence a lokálny extraktívny súhrn.",
        checkUpdatesToggle: "Kontrolovať aktualizácie CLI",
        refreshProvidersButton: "Obnoviť",
        checkUpdatesButton: "Skontrolovať aktualizácie",
        updateButton: "Aktualizovať",
        updatingStatus: "Aktualizuje sa…",
        providerReadyFormat: "Pripravené · v%@",
        providerReadyNoVersion: "Pripravené",
        providerNotInstalled: "Nenainštalované",
        providerNotRunning: "Nainštalované · služba nebeží",
        providerUpdateAvailableFormat: "Dostupná aktualizácia: v%@",
        summaryGeneratedWithFormat: "Vytvorené cez %@"
    )

    static let tr = SummaryProviderStrings(
        languageMixed: "İngilizce ve İbranice",
        dictationModeLabel: "Tetikleme modu",
        dictationModeToggle: "Aç/kapat için bas",
        dictationModeHold: "Konuşmak için basılı tut",
        dictationHoldListeningHUD: "Dinleniyor… eklemek için kısayolu bırakın",
        openSummaryTooltip: "Özeti aç",
        summaryProviderLabel: "Özet sağlayıcısı",
        summaryModelLabel: "Özet modeli",
        summaryProviderAuto: "Otomatik (En uygun)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Yerel)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Yerel CLI aboneliklerinizi (Claude Code, Codex, Gemini CLI) veya yerel Ollama’yı kullanır; aksi halde Apple Intelligence ve yerel özetlemeye geçer.",
        checkUpdatesToggle: "CLI güncellemelerini denetle",
        refreshProvidersButton: "Yenile",
        checkUpdatesButton: "Güncellemeleri denetle",
        updateButton: "Güncelle",
        updatingStatus: "Güncelleniyor…",
        providerReadyFormat: "Hazır · v%@",
        providerReadyNoVersion: "Hazır",
        providerNotInstalled: "Yüklü değil",
        providerNotRunning: "Yüklü · servis çalışmıyor",
        providerUpdateAvailableFormat: "Güncelleme mevcut: v%@",
        summaryGeneratedWithFormat: "%@ ile oluşturuldu"
    )

    static let ru = SummaryProviderStrings(
        languageMixed: "Английский и Иврит",
        dictationModeLabel: "Режим запуска",
        dictationModeToggle: "Нажатие для переключения",
        dictationModeHold: "Удерживать для диктовки",
        dictationHoldListeningHUD: "Слушаю… отпустите сочетание для вставки",
        openSummaryTooltip: "Открыть резюме",
        summaryProviderLabel: "Провайдер резюме",
        summaryModelLabel: "Модель резюме",
        summaryProviderAuto: "Авто (Лучший доступный)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Локально)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Использует локальные CLI-подписки (Claude Code, Codex, Gemini CLI) или локальную Ollama с резервным переходом на Apple Intelligence и локальное извлечение.",
        checkUpdatesToggle: "Проверять обновления CLI",
        refreshProvidersButton: "Обновить",
        checkUpdatesButton: "Проверить обновления",
        updateButton: "Обновить CLI",
        updatingStatus: "Обновление…",
        providerReadyFormat: "Готово · v%@",
        providerReadyNoVersion: "Готово",
        providerNotInstalled: "Не установлено",
        providerNotRunning: "Установлено · сервис не запущен",
        providerUpdateAvailableFormat: "Доступно обновление: v%@",
        summaryGeneratedWithFormat: "Создано с помощью %@"
    )

    static let de = SummaryProviderStrings(
        languageMixed: "Englisch & Hebräisch",
        dictationModeLabel: "Auslösemodus",
        dictationModeToggle: "Zum Umschalten drücken",
        dictationModeHold: "Zum Sprechen halten",
        dictationHoldListeningHUD: "Hört zu… Kurzbefehl loslassen zum Einfügen",
        openSummaryTooltip: "Zusammenfassung öffnen",
        summaryProviderLabel: "Zusammenfassungs-Anbieter",
        summaryModelLabel: "Zusammenfassungs-Modell",
        summaryProviderAuto: "Automatisch (Beste Option)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Lokal)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Nutzt deine lokalen CLI-Abonnements (Claude Code, Codex, Gemini CLI) oder lokales Ollama und fällt sonst auf Apple Intelligence und lokale Zusammenfassung zurück.",
        checkUpdatesToggle: "CLI-Updates prüfen",
        refreshProvidersButton: "Aktualisieren",
        checkUpdatesButton: "Nach Updates suchen",
        updateButton: "Aktualisieren",
        updatingStatus: "Wird aktualisiert…",
        providerReadyFormat: "Bereit · v%@",
        providerReadyNoVersion: "Bereit",
        providerNotInstalled: "Nicht installiert",
        providerNotRunning: "Installiert · Dienst gestoppt",
        providerUpdateAvailableFormat: "Update verfügbar: v%@",
        summaryGeneratedWithFormat: "Erstellt mit %@"
    )

    static let fr = SummaryProviderStrings(
        languageMixed: "Anglais et Hébreu",
        dictationModeLabel: "Mode de déclenchement",
        dictationModeToggle: "Appuyer pour basculer",
        dictationModeHold: "Maintenir pour parler",
        dictationHoldListeningHUD: "Écoute… relâchez le raccourci pour insérer",
        openSummaryTooltip: "Ouvrir le résumé",
        summaryProviderLabel: "Fournisseur de résumé",
        summaryModelLabel: "Modèle de résumé",
        summaryProviderAuto: "Auto (Meilleur disponible)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Local)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Utilise vos abonnements CLI locaux (Claude Code, Codex, Gemini CLI) ou Ollama local, avec repli sur Apple Intelligence et le résumé local.",
        checkUpdatesToggle: "Vérifier les mises à jour CLI",
        refreshProvidersButton: "Actualiser",
        checkUpdatesButton: "Vérifier les mises à jour",
        updateButton: "Mettre à jour",
        updatingStatus: "Mise à jour…",
        providerReadyFormat: "Prêt · v%@",
        providerReadyNoVersion: "Prêt",
        providerNotInstalled: "Non installé",
        providerNotRunning: "Installé · service arrêté",
        providerUpdateAvailableFormat: "Mise à jour disponible\u{00A0}: v%@",
        summaryGeneratedWithFormat: "Généré avec %@"
    )

    static let it = SummaryProviderStrings(
        languageMixed: "Inglese ed Ebraico",
        dictationModeLabel: "Modalità attivazione",
        dictationModeToggle: "Premi per attivare/disattivare",
        dictationModeHold: "Tieni premuto per parlare",
        dictationHoldListeningHUD: "In ascolto… rilascia la scorciatoia per inserire",
        openSummaryTooltip: "Apri riepilogo",
        summaryProviderLabel: "Provider riepilogo",
        summaryModelLabel: "Modello riepilogo",
        summaryProviderAuto: "Automatico (Migliore disponibile)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Locale)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Usa i tuoi abbonamenti CLI locali (Claude Code, Codex, Gemini CLI) o Ollama locale, con fallback su Apple Intelligence e riepilogo locale.",
        checkUpdatesToggle: "Controlla aggiornamenti CLI",
        refreshProvidersButton: "Aggiorna",
        checkUpdatesButton: "Controlla aggiornamenti",
        updateButton: "Aggiorna CLI",
        updatingStatus: "Aggiornamento…",
        providerReadyFormat: "Pronto · v%@",
        providerReadyNoVersion: "Pronto",
        providerNotInstalled: "Non installato",
        providerNotRunning: "Installato · servizio fermo",
        providerUpdateAvailableFormat: "Aggiornamento disponibile: v%@",
        summaryGeneratedWithFormat: "Generato con %@"
    )

    static let ja = SummaryProviderStrings(
        languageMixed: "英語・ヘブライ語",
        dictationModeLabel: "起動モード",
        dictationModeToggle: "押して切替",
        dictationModeHold: "押し続けて話す",
        dictationHoldListeningHUD: "聞き取り中… キーを離して挿入",
        openSummaryTooltip: "要約を開く",
        summaryProviderLabel: "要約プロバイダ",
        summaryModelLabel: "要約モデル",
        summaryProviderAuto: "自動（最適なもの）",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama（ローカル）",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "ローカルの CLI サブスクリプション（Claude Code、Codex、Gemini CLI）やローカル Ollama を使用し、利用不可時は Apple Intelligence とローカル要約にフォールバックします。",
        checkUpdatesToggle: "CLI のアップデートを確認",
        refreshProvidersButton: "更新",
        checkUpdatesButton: "アップデート確認",
        updateButton: "アップデート",
        updatingStatus: "アップデート中…",
        providerReadyFormat: "利用可能 · v%@",
        providerReadyNoVersion: "利用可能",
        providerNotInstalled: "未インストール",
        providerNotRunning: "インストール済み · サービス停止中",
        providerUpdateAvailableFormat: "アップデートあり: v%@",
        summaryGeneratedWithFormat: "%@ で生成"
    )

    static let ko = SummaryProviderStrings(
        languageMixed: "영어 및 히브리어",
        dictationModeLabel: "동작 방식",
        dictationModeToggle: "눌러서 전환",
        dictationModeHold: "누르고 말하기",
        dictationHoldListeningHUD: "듣는 중… 단축키를 놓아 삽입",
        openSummaryTooltip: "요약 열기",
        summaryProviderLabel: "요약 제공자",
        summaryModelLabel: "요약 모델",
        summaryProviderAuto: "자동 (최적 선택)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (로컬)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "로컬 CLI 구독(Claude Code, Codex, Gemini CLI) 또는 로컬 Ollama를 사용하며, 없을 경우 Apple Intelligence 및 로컬 요약으로 대체합니다.",
        checkUpdatesToggle: "CLI 업데이트 확인",
        refreshProvidersButton: "새로고침",
        checkUpdatesButton: "업데이트 확인",
        updateButton: "업데이트",
        updatingStatus: "업데이트 중…",
        providerReadyFormat: "준비됨 · v%@",
        providerReadyNoVersion: "준비됨",
        providerNotInstalled: "설치되지 않음",
        providerNotRunning: "설치됨 · 서비스 중지됨",
        providerUpdateAvailableFormat: "업데이트 가능: v%@",
        summaryGeneratedWithFormat: "%@로 생성됨"
    )

    static let uk = SummaryProviderStrings(
        languageMixed: "Англійська та Іврит",
        dictationModeLabel: "Режим запуску",
        dictationModeToggle: "Натиснути для перемикання",
        dictationModeHold: "Утримувати, щоб говорити",
        dictationHoldListeningHUD: "Слухаю… відпустіть комбінацію для вставлення",
        openSummaryTooltip: "Відкрити підсумок",
        summaryProviderLabel: "Провайдер підсумку",
        summaryModelLabel: "Модель підсумку",
        summaryProviderAuto: "Авто (Найкращий доступний)",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama (Локально)",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "Використовує ваші локальні CLI-підписки (Claude Code, Codex, Gemini CLI) або локальну Ollama з резервним переходом на Apple Intelligence та локальний підсумок.",
        checkUpdatesToggle: "Перевіряти оновлення CLI",
        refreshProvidersButton: "Оновити",
        checkUpdatesButton: "Перевірити оновлення",
        updateButton: "Оновити CLI",
        updatingStatus: "Оновлення…",
        providerReadyFormat: "Готово · v%@",
        providerReadyNoVersion: "Готово",
        providerNotInstalled: "Не встановлено",
        providerNotRunning: "Встановлено · сервіс не запущено",
        providerUpdateAvailableFormat: "Доступне оновлення: v%@",
        summaryGeneratedWithFormat: "Створено за допомогою %@"
    )

    static let zhHans = SummaryProviderStrings(
        languageMixed: "英语和希伯来语",
        dictationModeLabel: "触发方式",
        dictationModeToggle: "按一下切换",
        dictationModeHold: "按住说话",
        dictationHoldListeningHUD: "正在聆听… 松开快捷键插入文本",
        openSummaryTooltip: "打开摘要",
        summaryProviderLabel: "摘要提供商",
        summaryModelLabel: "摘要模型",
        summaryProviderAuto: "自动（最佳可用）",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama（本地）",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "使用本地 CLI 订阅（Claude Code、Codex、Gemini CLI）或本地 Ollama，不可用时自动回退至 Apple Intelligence 和本地摘要。",
        checkUpdatesToggle: "检查 CLI 提供商更新",
        refreshProvidersButton: "刷新",
        checkUpdatesButton: "检查更新",
        updateButton: "更新",
        updatingStatus: "正在更新…",
        providerReadyFormat: "就绪 · v%@",
        providerReadyNoVersion: "就绪",
        providerNotInstalled: "未安装",
        providerNotRunning: "已安装 · 服务未运行",
        providerUpdateAvailableFormat: "有可用更新：v%@",
        summaryGeneratedWithFormat: "由 %@ 生成"
    )

    static let zhTW = SummaryProviderStrings(
        languageMixed: "英語與希伯來語",
        dictationModeLabel: "觸發方式",
        dictationModeToggle: "按一下切換",
        dictationModeHold: "按住說話",
        dictationHoldListeningHUD: "正在聆聽… 放開快速鍵以插入",
        openSummaryTooltip: "開啟摘要",
        summaryProviderLabel: "摘要提供者",
        summaryModelLabel: "摘要模型",
        summaryProviderAuto: "自動（最佳可用）",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama（本機）",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "使用本機 CLI 訂閱（Claude Code、Codex、Gemini CLI）或本機 Ollama，無法使用時自動回退至 Apple Intelligence 與本機摘要。",
        checkUpdatesToggle: "檢查 CLI 提供者更新",
        refreshProvidersButton: "重新整理",
        checkUpdatesButton: "檢查更新",
        updateButton: "更新",
        updatingStatus: "正在更新…",
        providerReadyFormat: "就緒 · v%@",
        providerReadyNoVersion: "就緒",
        providerNotInstalled: "未安裝",
        providerNotRunning: "已安裝 · 服務未執行",
        providerUpdateAvailableFormat: "有可用更新：v%@",
        summaryGeneratedWithFormat: "由 %@ 產生"
    )

    static let zhHK = SummaryProviderStrings(
        languageMixed: "英語同希伯來語",
        dictationModeLabel: "觸發方式",
        dictationModeToggle: "按一下切換",
        dictationModeHold: "按住講嘢",
        dictationHoldListeningHUD: "正在聆聽… 放開快速鍵插入",
        openSummaryTooltip: "打開摘要",
        summaryProviderLabel: "摘要提供者",
        summaryModelLabel: "摘要模型",
        summaryProviderAuto: "自動（最佳可用）",
        summaryProviderClaude: "Claude Code",
        summaryProviderCodex: "Codex",
        summaryProviderGemini: "Gemini CLI",
        summaryProviderOllama: "Ollama（本機）",
        summaryProviderApple: "Apple Intelligence",
        summaryProviderCaption: "使用本機 CLI 訂閱（Claude Code、Codex、Gemini CLI）或者本機 Ollama，唔可用嗰陣自動退回 Apple Intelligence 同本機摘要。",
        checkUpdatesToggle: "檢查 CLI 提供者更新",
        refreshProvidersButton: "重新整理",
        checkUpdatesButton: "檢查更新",
        updateButton: "更新",
        updatingStatus: "更新緊…",
        providerReadyFormat: "就緒 · v%@",
        providerReadyNoVersion: "就緒",
        providerNotInstalled: "未安裝",
        providerNotRunning: "已安裝 · 服務未啟動",
        providerUpdateAvailableFormat: "有新版本：v%@",
        summaryGeneratedWithFormat: "由 %@ 產生"
    )
}
