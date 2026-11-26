// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TelemetryPolicyStrings {
    let refuseButton: String
    let refusedBadge: String
    let onboardingCaption: String
    let onboardingRefusedCaption: String
    let settingsSection: String
    let settingsToggle: String
    let settingsCaption: String
    let blockedNote: String

    static func localized(_ language: AppLanguage) -> TelemetryPolicyStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .tr: return .tr
        case .ru: return .ru
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension TelemetryPolicyStrings {
    static let enUS = TelemetryPolicyStrings(
        refuseButton: "I refuse all telemetry",
        refusedBadge: "All telemetry refused",
        onboardingCaption: "Turns off automatic update checks, diagnostics, usage learning, online lookups and background data collection across all features from this moment on.",
        onboardingRefusedCaption: "Nothing will be collected across any interaction or feature. You can review this anytime in Settings.",
        settingsSection: "Privacy & telemetry",
        settingsToggle: "Refuse all telemetry",
        settingsCaption: "Blocks automatic update checks, diagnostics, Command Bar usage learning, online lyric and cover lookups, remote price downloads and tool telemetry across all features.",
        blockedNote: "Disabled because all telemetry is refused."
    )

    static let ptBR = TelemetryPolicyStrings(
        refuseButton: "Recuso toda telemetria",
        refusedBadge: "Toda telemetria recusada",
        onboardingCaption: "Desativa verificações automáticas de atualização, diagnósticos, aprendizado de uso, buscas online e coleta em segundo plano em todos os recursos a partir deste momento.",
        onboardingRefusedCaption: "Nada será coletado em nenhuma interação ou recurso. Você pode revisar isso a qualquer momento nos Ajustes.",
        settingsSection: "Privacidade e telemetria",
        settingsToggle: "Recusar toda telemetria",
        settingsCaption: "Bloqueia verificações automáticas de atualização, diagnósticos, aprendizado de uso da Barra de Comandos, buscas online de letras e capas, downloads remotos de preços e telemetria de ferramentas em todos os recursos.",
        blockedNote: "Desativado porque toda telemetria foi recusada."
    )

    static let es = TelemetryPolicyStrings(
        refuseButton: "Rechazo toda la telemetría",
        refusedBadge: "Toda la telemetría rechazada",
        onboardingCaption: "Desactiva las comprobaciones automáticas de actualizaciones, los diagnósticos, el aprendizaje de uso, las búsquedas en línea y la recopilación en segundo plano en todas las funciones desde este momento.",
        onboardingRefusedCaption: "No se recopilará nada en ninguna interacción ni función. Puedes revisarlo en cualquier momento en Ajustes.",
        settingsSection: "Privacidad y telemetría",
        settingsToggle: "Rechazar toda la telemetría",
        settingsCaption: "Bloquea las comprobaciones automáticas de actualizaciones, los diagnósticos, el aprendizaje de uso de la Barra de comandos, las búsquedas en línea de letras y portadas, las descargas remotas de precios y la telemetría de herramientas en todas las funciones.",
        blockedNote: "Desactivado porque toda la telemetría está rechazada."
    )

    static let sk = TelemetryPolicyStrings(
        refuseButton: "Odmietam všetku telemetriu",
        refusedBadge: "Všetka telemetria odmietnutá",
        onboardingCaption: "Od tejto chvíle vypne automatické kontroly aktualizácií, diagnostiku, učenie používania, online vyhľadávanie a zber údajov na pozadí vo všetkých funkciách.",
        onboardingRefusedCaption: "Pri žiadnej interakcii ani funkcii sa nebude nič zbierať. Môžete to kedykoľvek skontrolovať v Nastaveniach.",
        settingsSection: "Súkromie a telemetria",
        settingsToggle: "Odmietnuť všetku telemetriu",
        settingsCaption: "Blokuje automatické kontroly aktualizácií, diagnostiku, učenie používania Príkazového riadku, online vyhľadávanie textov a obalov, sťahovanie cenníkov a telemetriu nástrojov vo všetkých funkciách.",
        blockedNote: "Vypnuté, pretože všetka telemetria je odmietnutá."
    )

    static let tr = TelemetryPolicyStrings(
        refuseButton: "Tüm telemetriyi reddediyorum",
        refusedBadge: "Tüm telemetri reddedildi",
        onboardingCaption: "Bu andan itibaren tüm özelliklerde otomatik güncelleme denetimlerini, tanılama bilgilerini, kullanım öğrenmeyi, çevrimiçi aramaları ve arka plan veri toplamayı kapatır.",
        onboardingRefusedCaption: "Hiçbir etkileşimde veya özellikte hiçbir veri toplanmayacak. Bunu istediğiniz zaman Ayarlar’dan gözden geçirebilirsiniz.",
        settingsSection: "Gizlilik ve telemetri",
        settingsToggle: "Tüm telemetriyi reddet",
        settingsCaption: "Tüm özelliklerde otomatik güncelleme denetimlerini, tanılamayı, Komut Çubuğu kullanım öğrenmeyi, çevrimiçi şarkı sözü ve kapak aramalarını, uzaktan fiyat indirmelerini ve araç telemetrisini engeller.",
        blockedNote: "Tüm telemetri reddedildiği için devre dışı."
    )

    static let ru = TelemetryPolicyStrings(
        refuseButton: "Я отказываюсь от всей телеметрии",
        refusedBadge: "Вся телеметрия отключена",
        onboardingCaption: "С этого момента отключает автоматическую проверку обновлений, диагностику, обучение по использованию, онлайн-поиск и фоновый сбор данных во всех функциях.",
        onboardingRefusedCaption: "Никакие данные не будут собираться ни в одном взаимодействии или функции. Вы всегда можете изменить это в Настройках.",
        settingsSection: "Конфиденциальность и телеметрия",
        settingsToggle: "Отказаться от всей телеметрии",
        settingsCaption: "Блокирует автоматическую проверку обновлений, диагностику, обучение Панели команд, онлайн-поиск текстов и обложек, загрузку удалённых цен и телеметрию инструментов во всех функциях.",
        blockedNote: "Отключено, так как вся телеметрия запрещена."
    )

    static let de = TelemetryPolicyStrings(
        refuseButton: "Ich lehne jede Telemetrie ab",
        refusedBadge: "Alle Telemetrie abgelehnt",
        onboardingCaption: "Deaktiviert ab sofort automatische Update-Prüfungen, Diagnosedaten, Nutzungslernen, Online-Abfragen und Datenerfassung im Hintergrund in allen Funktionen.",
        onboardingRefusedCaption: "Bei keiner Interaktion und keiner Funktion werden Daten erfasst. Du kannst dies jederzeit in den Einstellungen prüfen.",
        settingsSection: "Datenschutz und Telemetrie",
        settingsToggle: "Alle Telemetrie ablehnen",
        settingsCaption: "Blockiert automatische Update-Prüfungen, Diagnosedaten, das Nutzungslernen der Befehlsleiste, Online-Suche nach Liedtexten und Covern, externe Preis-Downloads und Tool-Telemetrie in allen Funktionen.",
        blockedNote: "Deaktiviert, da alle Telemetrie abgelehnt wurde."
    )

    static let fr = TelemetryPolicyStrings(
        refuseButton: "Je refuse toute télémétrie",
        refusedBadge: "Toute télémétrie refusée",
        onboardingCaption: "Désactive dès maintenant les vérifications automatiques de mise à jour, les diagnostics, l’apprentissage d’usage, les recherches en ligne et toute collecte en arrière-plan dans toutes les fonctionnalités.",
        onboardingRefusedCaption: "Rien ne sera collecté lors d’aucune interaction ni fonctionnalité. Vous pouvez vérifier ce choix à tout moment dans les Réglages.",
        settingsSection: "Confidentialité et télémétrie",
        settingsToggle: "Refuser toute télémétrie",
        settingsCaption: "Bloque les vérifications automatiques de mise à jour, les diagnostics, l’apprentissage d’usage de la Barre de commandes, les recherches en ligne de paroles et pochettes, les téléchargements distants de tarifs et la télémétrie des outils.",
        blockedNote: "Désactivé car toute télémétrie est refusée."
    )

    static let it = TelemetryPolicyStrings(
        refuseButton: "Rifiuto tutta la telemetria",
        refusedBadge: "Tutta la telemetria rifiutata",
        onboardingCaption: "Disattiva da questo momento i controlli automatici degli aggiornamenti, la diagnostica, l’apprendimento dell’uso, le ricerche online e la raccolta dati in background in tutte le funzioni.",
        onboardingRefusedCaption: "Non verrà raccolto nulla in nessuna interazione o funzione. Puoi rivedere questa scelta in qualsiasi momento nelle Impostazioni.",
        settingsSection: "Privacy e telemetria",
        settingsToggle: "Rifiuta tutta la telemetria",
        settingsCaption: "Blocca i controlli automatici degli aggiornamenti, la diagnostica, l’apprendimento dell’uso della Barra comandi, le ricerche online di testi e copertine, i download remoti dei prezzi e la telemetria degli strumenti.",
        blockedNote: "Disattivato perché tutta la telemetria è rifiutata."
    )

    static let ja = TelemetryPolicyStrings(
        refuseButton: "すべてのテレメトリを拒否する",
        refusedBadge: "すべてのテレメトリを拒否済み",
        onboardingCaption: "この瞬間から、すべての機能で自動アップデート確認、診断情報、使用履歴の学習、オンライン検索、バックグラウンドでのデータ収集を無効にします。",
        onboardingRefusedCaption: "あらゆる操作や機能でデータが収集されることはありません。設定からいつでも確認できます。",
        settingsSection: "プライバシーとテレメトリ",
        settingsToggle: "すべてのテレメトリを拒否する",
        settingsCaption: "すべての機能で自動アップデート確認、診断情報、コマンドバーの使用学習、オンラインの歌詞とアートワーク検索、リモート価格表の取得、ツールのテレメトリを遮断します。",
        blockedNote: "すべてのテレメトリが拒否されているため無効です。"
    )

    static let ko = TelemetryPolicyStrings(
        refuseButton: "모든 텔레메트리 거부",
        refusedBadge: "모든 텔레메트리 거부됨",
        onboardingCaption: "이 순간부터 모든 기능에서 자동 업데이트 확인, 진단 정보, 사용 학습, 온라인 조회 및 백그라운드 데이터 수집을 끕니다.",
        onboardingRefusedCaption: "모든 상호작용과 기능에서 아무것도 수집되지 않습니다. 설정에서 언제든 다시 확인할 수 있습니다.",
        settingsSection: "개인정보 보호 및 텔레메트리",
        settingsToggle: "모든 텔레메트리 거부",
        settingsCaption: "모든 기능에서 자동 업데이트 확인, 진단 정보, 명령 막대 사용 학습, 온라인 가사 및 앨범 아트 조회, 원격 가격표 다운로드 및 도구 텔레메트리를 차단합니다.",
        blockedNote: "모든 텔레메트리가 거부되어 비활성화되었습니다."
    )

    static let zhHans = TelemetryPolicyStrings(
        refuseButton: "我拒绝所有遥测",
        refusedBadge: "已拒绝所有遥测",
        onboardingCaption: "从此刻起，在所有功能中关闭自动更新检查、诊断信息、使用习惯学习、在线查询以及后台数据收集。",
        onboardingRefusedCaption: "在所有交互和功能中都不会收集任何信息。你可以随时在设置中查看。",
        settingsSection: "隐私与遥测",
        settingsToggle: "拒绝所有遥测",
        settingsCaption: "在所有功能中阻止自动更新检查、诊断信息、命令栏使用学习、在线歌词与封面查询、远程价格表下载及工具遥测。",
        blockedNote: "因已拒绝所有遥测而停用。"
    )

    static let zhTW = TelemetryPolicyStrings(
        refuseButton: "我拒絕所有遙測",
        refusedBadge: "已拒絕所有遙測",
        onboardingCaption: "從此刻起，在所有功能中關閉自動更新檢查、診斷資訊、使用習慣學習、線上查詢與背景資料收集。",
        onboardingRefusedCaption: "在所有互動與功能中都不會收集任何資料。你可以隨時在設定中檢視。",
        settingsSection: "隱私與遙測",
        settingsToggle: "拒絕所有遙測",
        settingsCaption: "在所有功能中封鎖自動更新檢查、診斷資訊、指令列使用學習、線上歌詞與封面查詢、遠端價格表下載及工具遙測。",
        blockedNote: "因已拒絕所有遙測而停用。"
    )

    static let zhHK = TelemetryPolicyStrings(
        refuseButton: "我拒絕所有遙測",
        refusedBadge: "已拒絕所有遙測",
        onboardingCaption: "由呢一刻起，喺所有功能中關閉自動更新檢查、診斷資訊、使用習慣學習、網上查詢同背景資料收集。",
        onboardingRefusedCaption: "喺所有互動同功能中都唔會收集任何資料。你可以隨時喺設定中檢視。",
        settingsSection: "私隱與遙測",
        settingsToggle: "拒絕所有遙測",
        settingsCaption: "喺所有功能中封鎖自動更新檢查、診斷資訊、指令列使用學習、網上歌詞與封面查詢、遠端價格表下載及工具遙測。",
        blockedNote: "因已拒絕所有遙測而停用。"
    )

    static let uk = TelemetryPolicyStrings(
        refuseButton: "Я відмовляюся від усієї телеметрії",
        refusedBadge: "Усю телеметрію відхилено",
        onboardingCaption: "Відтепер вимикає автоматичну перевірку оновлень, діагностику, навчання за використанням, онлайн-пошук і фоновий збір даних у всіх функціях.",
        onboardingRefusedCaption: "Жодні дані не збиратимуться в жодній взаємодії чи функції. Ви завжди можете переглянути це в Налаштуваннях.",
        settingsSection: "Приватність і телеметрія",
        settingsToggle: "Відмовитися від усієї телеметрії",
        settingsCaption: "Блокує автоматичну перевірку оновлень, діагностику, навчання Панелі команд, онлайн-пошук текстів і обкладинок, віддалене завантаження цін і телеметрію інструментів у всіх функціях.",
        blockedNote: "Вимкнено, оскільки всю телеметрію відхилено."
    )
}
