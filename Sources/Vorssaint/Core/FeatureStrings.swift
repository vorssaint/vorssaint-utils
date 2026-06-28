// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureStrings {
    static func settingsCategories(_ language: AppLanguage) -> SettingsCategoryStrings {
        switch language {
        case .ptBR: return .ptBR
        case .zhHans: return .zhHans
        default: return .enUS
        }
    }

    static func clipboard(_ language: AppLanguage) -> ClipboardFeatureStrings {
        switch language {
        case .ptBR: return .ptBR
        case .zhHans: return .zhHans
        default: return .enUS
        }
    }

    static func windowLayout(_ language: AppLanguage) -> WindowLayoutFeatureStrings {
        switch language {
        case .ptBR: return .ptBR
        case .zhHans: return .zhHans
        default: return .enUS
        }
    }

    static func monitorAlerts(_ language: AppLanguage) -> MonitorAlertFeatureStrings {
        switch language {
        case .ptBR: return .ptBR
        case .zhHans: return .zhHans
        default: return .enUS
        }
    }
}

struct SettingsCategoryStrings {
    let essentials: String
    let windowsControls: String
    let utilities: String
    let app: String

    static let ptBR = SettingsCategoryStrings(
        essentials: "Essenciais",
        windowsControls: "Janelas e controles",
        utilities: "Utilitários",
        app: "App"
    )

    static let zhHans = SettingsCategoryStrings(
        essentials: "基础功能",
        windowsControls: "窗口与控制",
        utilities: "实用工具",
        app: "App"
    )

    static let enUS = SettingsCategoryStrings(
        essentials: "Essentials",
        windowsControls: "Window controls",
        utilities: "Utilities",
        app: "App"
    )
}

struct ClipboardFeatureStrings {
    let title: String
    let enable: String
    let caption: String
    let localNote: String
    let skipSensitive: String
    let skipSensitiveCaption: String
    let limit: String
    let showInPanel: String
    let shortcut: String
    let shortcutCaption: String
    let shortcutHint: String
    let pinned: String
    let recent: String
    let pin: String
    let unpin: String
    let clearRecent: String
    let clearAll: String
    let empty: String
    let disabled: String
    let search: String
    let copy: String
    let copied: String
    let delete: String
    let moveUp: String
    let moveDown: String
    let noResults: String
    let newestFirst: String
    let active: String

    static let ptBR = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Guardar histórico de clipboard",
        caption: "Guarda textos copiados para reutilizar depois. Tudo fica local e pode ser apagado a qualquer momento.",
        localNote: "Somente texto entra no histórico. Imagens, arquivos e itens grandes são ignorados.",
        skipSensitive: "Ignorar textos com aparência sensível",
        skipSensitiveCaption: "Evita salvar textos curtos sem espaços que parecem senha, token ou chave.",
        limit: "Limite",
        showInPanel: "Mostrar no painel",
        shortcut: "Atalho do histórico",
        shortcutCaption: "Abre uma janela rápida com busca, favoritos e atalhos ⌘1 a ⌘9 para colar no app anterior.",
        shortcutHint: "Na janela rápida: Enter cola, Shift+Enter só copia. Setas escolhem, ⌘1 a ⌘9 colam, Option+P fixa, Option+Delete apaga.",
        pinned: "Fixados",
        recent: "Recentes",
        pin: "Fixar",
        unpin: "Desfixar",
        clearRecent: "Limpar recentes",
        clearAll: "Limpar não fixados",
        empty: "Nenhum texto salvo",
        disabled: "Ative o histórico para começar a guardar textos copiados.",
        search: "Buscar textos copiados",
        copy: "Copiar",
        copied: "Copiado",
        delete: "Apagar item",
        moveUp: "Mover para cima",
        moveDown: "Mover para baixo",
        noResults: "Nenhum resultado",
        newestFirst: "Mais recentes primeiro",
        active: "Guardando novos textos"
    )

    static let zhHans = ClipboardFeatureStrings(
        title: "剪贴板",
        enable: "保存剪贴板历史",
        caption: "保存复制过的文本，方便之后再次使用。所有内容都保存在本机，可随时清除。",
        localNote: "只保存文本。图片、文件和特别大的内容会被忽略。",
        skipSensitive: "跳过疑似敏感文本",
        skipSensitiveCaption: "避免保存像密码、令牌或密钥的短文本。",
        limit: "数量上限",
        showInPanel: "在面板中显示",
        shortcut: "历史快捷键",
        shortcutCaption: "打开快速窗口，支持搜索、固定项目，以及用 ⌘1 到 ⌘9 粘贴到上一个 App。",
        shortcutHint: "快速窗口中：Enter 粘贴，Shift+Enter 仅复制。方向键选择，⌘1 到 ⌘9 粘贴，Option+P 固定，Option+Delete 删除。",
        pinned: "已固定",
        recent: "最近",
        pin: "固定",
        unpin: "取消固定",
        clearRecent: "清除最近项目",
        clearAll: "清除未固定项目",
        empty: "没有保存的文本",
        disabled: "启用历史记录后即可开始保存复制的文本。",
        search: "搜索复制的文本",
        copy: "复制",
        copied: "已复制",
        delete: "删除项目",
        moveUp: "上移",
        moveDown: "下移",
        noResults: "没有结果",
        newestFirst: "最新优先",
        active: "正在保存新文本"
    )

    static let enUS = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Save clipboard history",
        caption: "Stores copied text so you can reuse it later. Everything stays local and can be cleared anytime.",
        localNote: "Only text is saved. Images, files and very large items are ignored.",
        skipSensitive: "Skip text that looks sensitive",
        skipSensitiveCaption: "Avoids saving short no-space strings that look like passwords, tokens or keys.",
        limit: "Limit",
        showInPanel: "Show in panel",
        shortcut: "History shortcut",
        shortcutCaption: "Opens a quick window with search, pinned items and ⌘1 to ⌘9 shortcuts for pasting into the previous app.",
        shortcutHint: "In the quick window: Enter pastes, Shift+Enter only copies. Arrows choose, ⌘1 to ⌘9 paste, Option+P pins, Option+Delete deletes.",
        pinned: "Pinned",
        recent: "Recent",
        pin: "Pin",
        unpin: "Unpin",
        clearRecent: "Clear recent",
        clearAll: "Clear unpinned",
        empty: "No saved text",
        disabled: "Enable history to start saving copied text.",
        search: "Search copied text",
        copy: "Copy",
        copied: "Copied",
        delete: "Delete item",
        moveUp: "Move up",
        moveDown: "Move down",
        noResults: "No results",
        newestFirst: "Newest first",
        active: "Saving new text"
    )
}

struct WindowLayoutFeatureStrings {
    let title: String
    let caption: String
    let showInPanel: String
    let shortcuts: String
    let shortcutsCaption: String
    let permissionCaption: String
    let noWindow: String
    let missingPermission: String
    let failed: String
    let done: String
    let restored: String
    let noRestore: String
    let target: String
    let halves: String
    let thirds: String
    let corners: String
    let other: String
    let leftHalf: String
    let rightHalf: String
    let topHalf: String
    let bottomHalf: String
    let leftThird: String
    let centerThird: String
    let rightThird: String
    let leftTwoThirds: String
    let rightTwoThirds: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    let maximize: String
    let center: String
    let nextDisplay: String
    let restore: String

    static let ptBR = WindowLayoutFeatureStrings(
        title: "Layout de janelas",
        caption: "Reposiciona a janela ativa em metades, terços, cantos, outro display, centro ou tela útil.",
        showInPanel: "Mostrar no painel",
        shortcuts: "Atalhos",
        shortcutsCaption: "Use atalhos globais para organizar a janela ativa sem abrir o painel.",
        permissionCaption: "Usa Acessibilidade para mover apenas a janela ativa.",
        noWindow: "Nenhuma janela ativa encontrada.",
        missingPermission: "Conceda Acessibilidade para mover janelas.",
        failed: "Não foi possível mover esta janela.",
        done: "Janela organizada.",
        restored: "Janela restaurada.",
        noRestore: "Nenhum layout anterior para restaurar.",
        target: "Janela ativa",
        halves: "Metades",
        thirds: "Terços",
        corners: "Cantos",
        other: "Ações",
        leftHalf: "Esquerda",
        rightHalf: "Direita",
        topHalf: "Topo",
        bottomHalf: "Base",
        leftThird: "1/3 esquerda",
        centerThird: "1/3 centro",
        rightThird: "1/3 direita",
        leftTwoThirds: "2/3 esquerda",
        rightTwoThirds: "2/3 direita",
        topLeft: "Topo esquerdo",
        topRight: "Topo direito",
        bottomLeft: "Base esquerda",
        bottomRight: "Base direita",
        maximize: "Maximizar",
        center: "Centralizar",
        nextDisplay: "Próximo display",
        restore: "Restaurar"
    )

    static let zhHans = WindowLayoutFeatureStrings(
        title: "窗口布局",
        caption: "将当前窗口移动到半屏、三分屏、角落、另一台显示器、居中位置或可用屏幕区域。",
        showInPanel: "在面板中显示",
        shortcuts: "快捷键",
        shortcutsCaption: "使用全局快捷键整理当前窗口，无需打开面板。",
        permissionCaption: "使用辅助功能权限，仅移动当前窗口。",
        noWindow: "未找到当前窗口。",
        missingPermission: "请授予辅助功能权限以移动窗口。",
        failed: "无法移动此窗口。",
        done: "窗口已整理。",
        restored: "窗口已恢复。",
        noRestore: "没有可恢复的上一个布局。",
        target: "当前窗口",
        halves: "半屏",
        thirds: "三分屏",
        corners: "角落",
        other: "操作",
        leftHalf: "左半屏",
        rightHalf: "右半屏",
        topHalf: "上半屏",
        bottomHalf: "下半屏",
        leftThird: "左侧 1/3",
        centerThird: "中间 1/3",
        rightThird: "右侧 1/3",
        leftTwoThirds: "左侧 2/3",
        rightTwoThirds: "右侧 2/3",
        topLeft: "左上角",
        topRight: "右上角",
        bottomLeft: "左下角",
        bottomRight: "右下角",
        maximize: "最大化",
        center: "居中",
        nextDisplay: "下一台显示器",
        restore: "恢复"
    )

    static let enUS = WindowLayoutFeatureStrings(
        title: "Window layout",
        caption: "Moves the active window to halves, thirds, corners, another display, center or the usable screen.",
        showInPanel: "Show in panel",
        shortcuts: "Shortcuts",
        shortcutsCaption: "Use global shortcuts to arrange the active window without opening the panel.",
        permissionCaption: "Uses Accessibility to move only the active window.",
        noWindow: "No active window found.",
        missingPermission: "Grant Accessibility to move windows.",
        failed: "Could not move this window.",
        done: "Window arranged.",
        restored: "Window restored.",
        noRestore: "No previous layout to restore.",
        target: "Active window",
        halves: "Halves",
        thirds: "Thirds",
        corners: "Corners",
        other: "Actions",
        leftHalf: "Left",
        rightHalf: "Right",
        topHalf: "Top",
        bottomHalf: "Bottom",
        leftThird: "Left 1/3",
        centerThird: "Center 1/3",
        rightThird: "Right 1/3",
        leftTwoThirds: "Left 2/3",
        rightTwoThirds: "Right 2/3",
        topLeft: "Top left",
        topRight: "Top right",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        maximize: "Maximize",
        center: "Center",
        nextDisplay: "Next display",
        restore: "Restore"
    )
}

struct MonitorAlertFeatureStrings {
    let section: String
    let caption: String
    let cpu: String
    let cpuTemperature: String
    let memory: String
    let disk: String
    let battery: String
    let cpuThreshold: String
    let cpuTemperatureThreshold: String
    let diskThreshold: String
    let batteryThreshold: String
    let cooldown: String
    let cooldown5: String
    let cooldown15: String
    let cooldown30: String
    let cooldown60: String
    let cpuTitle: String
    let cpuBodyFormat: String
    let cpuTemperatureTitle: String
    let cpuTemperatureBodyFormat: String
    let memoryTitle: String
    let memoryBody: String
    let diskTitle: String
    let diskBodyFormat: String
    let batteryTitle: String
    let batteryBodyFormat: String

    static let ptBR = MonitorAlertFeatureStrings(
        section: "Alertas",
        caption: "Desligado por padrão. Quando ligado, o Monitor avisa só depois de uma condição relevante e respeita o intervalo entre avisos.",
        cpu: "CPU alta",
        cpuTemperature: "Temperatura alta da CPU",
        memory: "Pressão de memória crítica",
        disk: "Pouco espaço em disco",
        battery: "Bateria baixa",
        cpuThreshold: "CPU acima de",
        cpuTemperatureThreshold: "Temperatura acima de",
        diskThreshold: "Espaço livre abaixo de",
        batteryThreshold: "Bateria abaixo de",
        cooldown: "Intervalo entre avisos",
        cooldown5: "5 minutos",
        cooldown15: "15 minutos",
        cooldown30: "30 minutos",
        cooldown60: "1 hora",
        cpuTitle: "CPU alta",
        cpuBodyFormat: "A CPU ficou acima de %d%% por alguns segundos.",
        cpuTemperatureTitle: "CPU quente",
        cpuTemperatureBodyFormat: "A CPU chegou a %d °C.",
        memoryTitle: "Memória crítica",
        memoryBody: "A pressão de memória chegou ao nível crítico.",
        diskTitle: "Pouco espaço em disco",
        diskBodyFormat: "%@ está com menos de %d%% livre.",
        batteryTitle: "Bateria baixa",
        batteryBodyFormat: "A bateria está em %d%%."
    )

    static let zhHans = MonitorAlertFeatureStrings(
        section: "提醒",
        caption: "默认关闭。启用后，监视器只会在出现有意义的状态时提醒，并遵守提醒间隔。",
        cpu: "CPU 过高",
        cpuTemperature: "CPU 温度过高",
        memory: "内存压力严重",
        disk: "磁盘空间不足",
        battery: "电池电量低",
        cpuThreshold: "CPU 高于",
        cpuTemperatureThreshold: "温度高于",
        diskThreshold: "可用空间低于",
        batteryThreshold: "电量低于",
        cooldown: "提醒间隔",
        cooldown5: "5 分钟",
        cooldown15: "15 分钟",
        cooldown30: "30 分钟",
        cooldown60: "1 小时",
        cpuTitle: "CPU 过高",
        cpuBodyFormat: "CPU 已连续几秒高于 %d%%。",
        cpuTemperatureTitle: "CPU 过热",
        cpuTemperatureBodyFormat: "CPU 已达到 %d °C。",
        memoryTitle: "内存严重",
        memoryBody: "内存压力已达到严重级别。",
        diskTitle: "磁盘空间不足",
        diskBodyFormat: "%@ 的可用空间低于 %d%%。",
        batteryTitle: "电池电量低",
        batteryBodyFormat: "电池电量为 %d%%。"
    )

    static let enUS = MonitorAlertFeatureStrings(
        section: "Alerts",
        caption: "Off by default. When enabled, Monitor warns only after a useful condition and respects the alert interval.",
        cpu: "High CPU",
        cpuTemperature: "High CPU temperature",
        memory: "Critical memory pressure",
        disk: "Low disk space",
        battery: "Low battery",
        cpuThreshold: "CPU above",
        cpuTemperatureThreshold: "Temperature above",
        diskThreshold: "Free space below",
        batteryThreshold: "Battery below",
        cooldown: "Alert interval",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 hour",
        cpuTitle: "High CPU",
        cpuBodyFormat: "CPU stayed above %d%% for a few seconds.",
        cpuTemperatureTitle: "Hot CPU",
        cpuTemperatureBodyFormat: "CPU reached %d °C.",
        memoryTitle: "Critical memory",
        memoryBody: "Memory pressure reached the critical level.",
        diskTitle: "Low disk space",
        diskBodyFormat: "%@ has less than %d%% free.",
        batteryTitle: "Low battery",
        batteryBodyFormat: "Battery is at %d%%."
    )
}
