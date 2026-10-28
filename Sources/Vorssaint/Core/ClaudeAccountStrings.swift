// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Claude Code profiles the AI page gives limits cards of their own.
struct ClaudeAccountStrings {
    let title: String
    let explanation: String
}

extension FeatureStrings {
    static func claudeAccounts(_ language: AppLanguage) -> ClaudeAccountStrings {
        switch language {
        case .enUS: return ClaudeAccountStrings(
            title: "Claude Code accounts",
            explanation: "Each Claude Code profile folder on this Mac, such as ~/.claude-work, gets its own limits card. Turn off the ones you don’t want to see; they are no longer checked.")
        case .ptBR: return ClaudeAccountStrings(
            title: "Contas do Claude Code",
            explanation: "Cada pasta de perfil do Claude Code neste Mac, como ~/.claude-work, ganha o próprio cartão de limites. Desative as que não quiser ver; elas deixam de ser verificadas.")
        case .tr: return ClaudeAccountStrings(
            title: "Claude Code hesapları",
            explanation: "Bu Mac’teki her Claude Code profil klasörünün, örneğin ~/.claude-work, kendi sınır kartı olur. Görmek istemediklerinizi kapatın; artık denetlenmezler.")
        case .ru: return ClaudeAccountStrings(
            title: "Аккаунты Claude Code",
            explanation: "У каждой папки профиля Claude Code на этом Mac, например ~/.claude-work, своя карточка лимитов. Выключите ненужные: они больше не проверяются.")
        case .es: return ClaudeAccountStrings(
            title: "Cuentas de Claude Code",
            explanation: "Cada carpeta de perfil de Claude Code en este Mac, como ~/.claude-work, tiene su propia tarjeta de límites. Desactiva las que no quieras ver; dejarán de consultarse.")
        case .sk: return ClaudeAccountStrings(
            title: "Účty Claude Code",
            explanation: "Každý priečinok profilu Claude Code v tomto Macu, napríklad ~/.claude-work, má vlastnú kartu limitov. Vypnite tie, ktoré nechcete vidieť; prestanú sa kontrolovať.")
        case .de: return ClaudeAccountStrings(
            title: "Claude Code-Konten",
            explanation: "Jeder Claude Code-Profilordner auf diesem Mac, etwa ~/.claude-work, erhält eine eigene Limitkarte. Schalte die aus, die du nicht sehen möchtest; sie werden dann nicht mehr geprüft.")
        case .fr: return ClaudeAccountStrings(
            title: "Comptes Claude Code",
            explanation: "Chaque dossier de profil Claude Code sur ce Mac, comme ~/.claude-work, a sa propre carte de limites. Désactivez ceux que vous ne voulez pas voir ; ils ne sont plus vérifiés.")
        case .it: return ClaudeAccountStrings(
            title: "Account Claude Code",
            explanation: "Ogni cartella di profilo di Claude Code su questo Mac, come ~/.claude-work, ha la propria scheda dei limiti. Disattiva quelle che non vuoi vedere; non vengono più controllate.")
        case .ja: return ClaudeAccountStrings(
            title: "Claude Codeアカウント",
            explanation: "このMacにあるClaude Codeのプロファイルフォルダ（~/.claude-workなど）ごとに上限カードが表示されます。表示しないものはオフにすると、確認も行われなくなります。")
        case .ko: return ClaudeAccountStrings(
            title: "Claude Code 계정",
            explanation: "이 Mac에 있는 Claude Code 프로필 폴더(예: ~/.claude-work)마다 한도 카드가 따로 표시됩니다. 보고 싶지 않은 항목을 끄면 더 이상 확인하지 않습니다.")
        case .uk: return ClaudeAccountStrings(
            title: "Облікові записи Claude Code",
            explanation: "Кожна папка профілю Claude Code на цьому Mac, наприклад ~/.claude-work, має власну картку лімітів. Вимкніть непотрібні: їх більше не перевіряють.")
        case .zhHans: return ClaudeAccountStrings(
            title: "Claude Code 账户",
            explanation: "这台 Mac 上的每个 Claude Code 配置文件夹（例如 ~/.claude-work）都有自己的额度卡片。关闭不想看到的项目后，将不再检查它们。")
        case .zhTW: return ClaudeAccountStrings(
            title: "Claude Code 帳號",
            explanation: "這台 Mac 上的每個 Claude Code 設定檔資料夾（例如 ~/.claude-work）都有自己的額度卡片。關閉不想看到的項目後，將不再檢查它們。")
        case .zhHK: return ClaudeAccountStrings(
            title: "Claude Code 帳戶",
            explanation: "這部 Mac 上的每個 Claude Code 設定檔資料夾（例如 ~/.claude-work）都有自己的額度卡片。關閉不想看到的項目後，將不再檢查它們。")
        }
    }
}
