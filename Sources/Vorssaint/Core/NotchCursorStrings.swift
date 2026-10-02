// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCursorStrings {
    let title: String
    let hubDescription: String
    let settingsDescription: String
    let connectTitle: String
    let connectBody: String
    let approvalOverflow: String
}

extension FeatureStrings {
    static func notchCursor(_ language: AppLanguage) -> NotchCursorStrings {
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

extension NotchCursorStrings {
    static let enUS = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Follow the Cursor app’s agent in the Dynamic Island, with simple controls from the island.",
        settingsDescription: "An optional page for the agent in the Cursor app on this Mac. It stays off until you connect it. Prompts and command output stay on this Mac.",
        connectTitle: "Connect Cursor",
        connectBody: "Connect Vorssaint to the Cursor app to follow the agent from the island.",
        approvalOverflow: "An approval was answered automatically."
    )
    static let ptBR = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Acompanhe o agente do app Cursor no Dynamic Island, com controles simples a partir da ilha.",
        settingsDescription: "Uma página opcional para o agente do app Cursor neste Mac. Ela fica desligada até você conectá-la. Os prompts e a saída dos comandos ficam neste Mac.",
        connectTitle: "Conectar o Cursor",
        connectBody: "Conecte o Vorssaint ao app Cursor para acompanhar o agente pela ilha.",
        approvalOverflow: "Uma aprovação foi respondida automaticamente."
    )
    static let es = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Sigue al agente de la app Cursor en el Dynamic Island, con controles sencillos desde la isla.",
        settingsDescription: "Una página opcional para el agente de la app Cursor en este Mac. Permanece apagada hasta que la conectes. Los prompts y la salida de los comandos se quedan en este Mac.",
        connectTitle: "Conectar Cursor",
        connectBody: "Conecta Vorssaint con la app Cursor para seguir al agente desde la isla.",
        approvalOverflow: "Una aprobación se respondió automáticamente."
    )
    static let sk = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Sledujte agenta aplikácie Cursor v Dynamic Island a ovládajte ho jednoducho z ostrova.",
        settingsDescription: "Voliteľná stránka pre agenta aplikácie Cursor na tomto Macu. Zostáva vypnutá, kým ju nepripojíte. Výzvy a výstup príkazov zostávajú na tomto Macu.",
        connectTitle: "Pripojiť Cursor",
        connectBody: "Pripojte Vorssaint k aplikácii Cursor a sledujte agenta z Dynamic Island.",
        approvalOverflow: "Schválenie bolo zodpovedané automaticky."
    )
    static let de = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Verfolge den Agenten der Cursor-App im Dynamic Island und nutze einfache Steuerungen von der Insel.",
        settingsDescription: "Eine optionale Seite für den Agenten der Cursor-App auf diesem Mac. Sie bleibt aus, bis du sie verbindest. Prompts und Befehlsausgaben bleiben auf diesem Mac.",
        connectTitle: "Cursor verbinden",
        connectBody: "Verbinde Vorssaint mit der Cursor-App, um den Agenten über die Insel zu verfolgen.",
        approvalOverflow: "Eine Freigabe wurde automatisch beantwortet."
    )
    static let fr = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Suivez l’agent de l’app Cursor dans le Dynamic Island, avec des commandes simples depuis l’îlot.",
        settingsDescription: "Une page facultative pour l’agent de l’app Cursor sur ce Mac. Elle reste désactivée tant que vous ne la connectez pas. Les invites et la sortie des commandes restent sur ce Mac.",
        connectTitle: "Connecter Cursor",
        connectBody: "Connectez Vorssaint à l’app Cursor pour suivre l’agent depuis l’îlot.",
        approvalOverflow: "Une approbation a été traitée automatiquement."
    )
    static let it = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Segui l’agente dell’app Cursor nel Dynamic Island, con controlli semplici dall’isola.",
        settingsDescription: "Una pagina facoltativa per l’agente dell’app Cursor su questo Mac. Resta spenta finché non la colleghi. I prompt e l’output dei comandi restano su questo Mac.",
        connectTitle: "Collega Cursor",
        connectBody: "Collega Vorssaint all’app Cursor per seguire l’agente dall’isola.",
        approvalOverflow: "Un’approvazione è stata gestita automaticamente."
    )
    static let ru = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Следите за агентом приложения Cursor в Dynamic Island и пользуйтесь простыми действиями с острова.",
        settingsDescription: "Необязательная страница для агента приложения Cursor на этом Mac. Она выключена, пока вы её не подключите. Запросы и вывод команд остаются на этом Mac.",
        connectTitle: "Подключить Cursor",
        connectBody: "Подключите Vorssaint к приложению Cursor, чтобы следить за агентом с острова.",
        approvalOverflow: "Подтверждение обработано автоматически."
    )
    static let tr = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Cursor uygulamasının aracısını Dynamic Island’da izleyin ve adadan basit denetimler kullanın.",
        settingsDescription: "Bu Mac’teki Cursor uygulamasının aracısı için isteğe bağlı bir sayfa. Siz bağlayana kadar kapalı kalır. İstemler ve komut çıktısı bu Mac’te kalır.",
        connectTitle: "Cursor’ı bağla",
        connectBody: "Aracıyı adadan izlemek için Vorssaint’i Cursor uygulamasına bağlayın.",
        approvalOverflow: "Bir onay otomatik olarak yanıtlandı."
    )
    static let ja = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "CursorアプリのエージェントをDynamic Islandで追い、島から簡単な操作ができます。",
        settingsDescription: "このMacのCursorアプリのエージェントのための任意のページです。接続するまでオフのままです。プロンプトとコマンドの出力はこのMacに残ります。",
        connectTitle: "Cursorを接続",
        connectBody: "島からエージェントを追うには、VorssaintをCursorアプリに接続します。",
        approvalOverflow: "承認は自動的に応答されました。"
    )
    static let ko = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Cursor 앱의 에이전트를 Dynamic Island에서 보고, 섬에서 간단한 조작을 할 수 있습니다.",
        settingsDescription: "이 Mac의 Cursor 앱 에이전트를 위한 선택 페이지입니다. 연결하기 전까지는 꺼져 있습니다. 프롬프트와 명령 출력은 이 Mac에 남습니다.",
        connectTitle: "Cursor 연결",
        connectBody: "섬에서 에이전트를 보려면 Vorssaint를 Cursor 앱에 연결하세요.",
        approvalOverflow: "승인이 자동으로 응답되었습니다."
    )
    static let uk = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "Стежте за агентом програми Cursor у Dynamic Island і керуйте простими діями з острівця.",
        settingsDescription: "Необов’язкова сторінка для агента програми Cursor на цьому Mac. Вона вимкнена, доки ви її не підключите. Запити й вивід команд залишаються на цьому Mac.",
        connectTitle: "Підключити Cursor",
        connectBody: "Підключіть Vorssaint до програми Cursor, щоб стежити за агентом з острівця.",
        approvalOverflow: "Підтвердження оброблено автоматично."
    )
    static let zhHans = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "在 Dynamic Island 中查看 Cursor 应用的代理，并从岛上使用简单控制。",
        settingsDescription: "用于这台 Mac 上 Cursor 应用代理的可选页面。连接之前保持关闭。提示词和命令输出留在这台 Mac 上。",
        connectTitle: "连接 Cursor",
        connectBody: "将 Vorssaint 连接到 Cursor 应用，以便从岛上查看代理。",
        approvalOverflow: "一项审批已自动回复。"
    )
    static let zhTW = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "在 Dynamic Island 中查看 Cursor App 的代理，並從島上使用簡單控制。",
        settingsDescription: "用於這部 Mac 上 Cursor App 代理的可選頁面。連接之前保持關閉。提示詞和指令輸出留在這部 Mac 上。",
        connectTitle: "連接 Cursor",
        connectBody: "將 Vorssaint 連接到 Cursor App，以便從島上查看代理。",
        approvalOverflow: "一項核准已自動回覆。"
    )
    static let zhHK = NotchCursorStrings(
        title: "Cursor",
        hubDescription: "在 Dynamic Island 中查看 Cursor App 的代理，並從島上使用簡單控制。",
        settingsDescription: "用於這部 Mac 上 Cursor App 代理的可選頁面。連接之前保持關閉。提示詞和指令輸出留在這部 Mac 上。",
        connectTitle: "連接 Cursor",
        connectBody: "將 Vorssaint 連接到 Cursor App，以便從島上查看代理。",
        approvalOverflow: "一項核准已自動回覆。"
    )
}
