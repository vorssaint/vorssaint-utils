// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where agents work and what their current window is worth, on the AI page
/// and in the closed island.
struct NotchAgentPlaceStrings {
    let inTerminal: String
    /// "In %@ app", with the agent's name.
    let inAppFormat: String
    let noSessions: String
    let inIsland: String
    let thisSession: String
    let thisMonth: String
    /// "%@ this month", with an amount.
    let monthCaptionFormat: String
    let allAgentsLifetime: String
    /// "%d in terminal" and "%d in app", for VoiceOver.
    let terminalCountFormat: String
    let appCountFormat: String

    func inApp(_ provider: AgentProvider) -> String { String(format: inAppFormat, provider.displayName) }
    func monthCaption(_ amount: String) -> String { String(format: monthCaptionFormat, amount) }
    func count(_ place: AgentSessionPlace, _ count: Int) -> String {
        String(format: place == .terminal ? terminalCountFormat : appCountFormat, count)
    }
}

extension FeatureStrings {
    static func notchAgentPlaces(_ language: AppLanguage) -> NotchAgentPlaceStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NotchAgentPlaceStrings {
    static let enUS = NotchAgentPlaceStrings(
        inTerminal: "In terminal", inAppFormat: "In %@ app", noSessions: "No sessions running", inIsland: "In island",
        thisSession: "This session", thisMonth: "This month", monthCaptionFormat: "%@ this month",
        allAgentsLifetime: "all time · all agents", terminalCountFormat: "%d in terminal", appCountFormat: "%d in app")

    static let ptBR = NotchAgentPlaceStrings(
        inTerminal: "No terminal", inAppFormat: "No app %@", noSessions: "Nenhuma sessão em andamento", inIsland: "Na ilha",
        thisSession: "Esta sessão", thisMonth: "Este mês", monthCaptionFormat: "%@ este mês",
        allAgentsLifetime: "desde sempre · todos os agentes", terminalCountFormat: "%d no terminal", appCountFormat: "%d no app")

    static let es = NotchAgentPlaceStrings(
        inTerminal: "En la terminal", inAppFormat: "En la app de %@", noSessions: "No hay sesiones en curso", inIsland: "En la isla",
        thisSession: "Esta sesión", thisMonth: "Este mes", monthCaptionFormat: "%@ este mes",
        allAgentsLifetime: "desde siempre · todos los agentes", terminalCountFormat: "%d en la terminal", appCountFormat: "%d en la app")

    static let sk = NotchAgentPlaceStrings(
        inTerminal: "V termináli", inAppFormat: "V aplikácii %@", noSessions: "Nebežia žiadne relácie", inIsland: "Na ostrove",
        thisSession: "Táto relácia", thisMonth: "Tento mesiac", monthCaptionFormat: "%@ tento mesiac",
        allAgentsLifetime: "celkovo · všetci agenti", terminalCountFormat: "%d v termináli", appCountFormat: "%d v aplikácii")

    static let de = NotchAgentPlaceStrings(
        inTerminal: "Im Terminal", inAppFormat: "In der %@-App", noSessions: "Keine laufenden Sitzungen", inIsland: "In der Insel",
        thisSession: "Diese Sitzung", thisMonth: "Diesen Monat", monthCaptionFormat: "%@ diesen Monat",
        allAgentsLifetime: "insgesamt · alle Agenten", terminalCountFormat: "%d im Terminal", appCountFormat: "%d in der App")

    static let fr = NotchAgentPlaceStrings(
        inTerminal: "Dans le terminal", inAppFormat: "Dans l’app %@", noSessions: "Aucune session en cours", inIsland: "Dans l’île",
        thisSession: "Cette session", thisMonth: "Ce mois-ci", monthCaptionFormat: "%@ ce mois-ci",
        allAgentsLifetime: "depuis toujours · tous les agents", terminalCountFormat: "%d dans le terminal", appCountFormat: "%d dans l’app")

    static let it = NotchAgentPlaceStrings(
        inTerminal: "Nel terminale", inAppFormat: "Nell’app %@", noSessions: "Nessuna sessione in corso", inIsland: "Nell’isola",
        thisSession: "Questa sessione", thisMonth: "Questo mese", monthCaptionFormat: "%@ questo mese",
        allAgentsLifetime: "in totale · tutti gli agenti", terminalCountFormat: "%d nel terminale", appCountFormat: "%d nell’app")

    static let ru = NotchAgentPlaceStrings(
        inTerminal: "В терминале", inAppFormat: "В приложении %@", noSessions: "Нет активных сеансов", inIsland: "На острове",
        thisSession: "Этот сеанс", thisMonth: "Этот месяц", monthCaptionFormat: "%@ за этот месяц",
        allAgentsLifetime: "за всё время · все агенты", terminalCountFormat: "В терминале: %d", appCountFormat: "В приложении: %d")

    static let tr = NotchAgentPlaceStrings(
        inTerminal: "Terminalde", inAppFormat: "%@ uygulamasında", noSessions: "Çalışan oturum yok", inIsland: "Adada",
        thisSession: "Bu oturum", thisMonth: "Bu ay", monthCaptionFormat: "Bu ay %@",
        allAgentsLifetime: "tüm zamanlar · tüm ajanlar", terminalCountFormat: "Terminalde %d", appCountFormat: "Uygulamada %d")

    static let ja = NotchAgentPlaceStrings(
        inTerminal: "ターミナル", inAppFormat: "%@ アプリ", noSessions: "実行中のセッションはありません", inIsland: "アイランド表示中",
        thisSession: "このセッション", thisMonth: "今月", monthCaptionFormat: "今月 %@",
        allAgentsLifetime: "累計 · すべてのエージェント", terminalCountFormat: "ターミナルで%d件", appCountFormat: "アプリで%d件")

    static let ko = NotchAgentPlaceStrings(
        inTerminal: "터미널", inAppFormat: "%@ 앱", noSessions: "실행 중인 세션 없음", inIsland: "아일랜드에 표시 중",
        thisSession: "이번 세션", thisMonth: "이번 달", monthCaptionFormat: "이번 달 %@",
        allAgentsLifetime: "전체 기간 · 모든 에이전트", terminalCountFormat: "터미널 %d개", appCountFormat: "앱 %d개")

    static let uk = NotchAgentPlaceStrings(
        inTerminal: "У терміналі", inAppFormat: "У застосунку %@", noSessions: "Немає активних сеансів", inIsland: "На острові",
        thisSession: "Цей сеанс", thisMonth: "Цей місяць", monthCaptionFormat: "%@ за цей місяць",
        allAgentsLifetime: "за весь час · усі агенти", terminalCountFormat: "У терміналі: %d", appCountFormat: "У застосунку: %d")

    static let zhHans = NotchAgentPlaceStrings(
        inTerminal: "终端中", inAppFormat: "%@ App 中", noSessions: "没有正在运行的会话", inIsland: "灵动岛中",
        thisSession: "本次会话", thisMonth: "本月", monthCaptionFormat: "本月 %@",
        allAgentsLifetime: "累计 · 所有代理", terminalCountFormat: "终端中 %d 个", appCountFormat: "App 中 %d 个")

    static let zhTW = NotchAgentPlaceStrings(
        inTerminal: "終端機中", inAppFormat: "%@ App 中", noSessions: "沒有執行中的工作階段", inIsland: "動態島中",
        thisSession: "本次工作階段", thisMonth: "本月", monthCaptionFormat: "本月 %@",
        allAgentsLifetime: "累計 · 所有代理", terminalCountFormat: "終端機中 %d 個", appCountFormat: "App 中 %d 個")

    static let zhHK = NotchAgentPlaceStrings(
        inTerminal: "終端機中", inAppFormat: "%@ App 中", noSessions: "沒有執行中的工作階段", inIsland: "動態島中",
        thisSession: "今次工作階段", thisMonth: "本月", monthCaptionFormat: "本月 %@",
        allAgentsLifetime: "累計 · 所有代理", terminalCountFormat: "終端機中 %d 個", appCountFormat: "App 中 %d 個")
}
