// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureStrings {
    static func settingsCategories(_ language: AppLanguage) -> SettingsCategoryStrings {
        language == .ptBR ? .ptBR : .enUS
    }

    static func clipboard(_ language: AppLanguage) -> ClipboardFeatureStrings {
        language == .ptBR ? .ptBR : .enUS
    }

    static func windowLayout(_ language: AppLanguage) -> WindowLayoutFeatureStrings {
        language == .ptBR ? .ptBR : .enUS
    }

    static func monitorAlerts(_ language: AppLanguage) -> MonitorAlertFeatureStrings {
        language == .ptBR ? .ptBR : .enUS
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
        shortcutHint: "Na janela rápida: Enter cola o primeiro item, ⌘1 a ⌘9 colam, e os botões dos itens apagam ou reordenam.",
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
        shortcutHint: "In the quick window: Enter pastes the first item, ⌘1 to ⌘9 paste items, and item buttons delete or reorder.",
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
    let corners: String
    let other: String
    let leftHalf: String
    let rightHalf: String
    let topHalf: String
    let bottomHalf: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    let maximize: String
    let center: String
    let restore: String

    static let ptBR = WindowLayoutFeatureStrings(
        title: "Layout de janelas",
        caption: "Reposiciona a janela ativa em metades, cantos, centro ou tela útil.",
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
        corners: "Cantos",
        other: "Ações",
        leftHalf: "Esquerda",
        rightHalf: "Direita",
        topHalf: "Topo",
        bottomHalf: "Base",
        topLeft: "Topo esquerdo",
        topRight: "Topo direito",
        bottomLeft: "Base esquerda",
        bottomRight: "Base direita",
        maximize: "Maximizar",
        center: "Centralizar",
        restore: "Restaurar"
    )

    static let enUS = WindowLayoutFeatureStrings(
        title: "Window layout",
        caption: "Moves the active window to halves, corners, center or the usable screen.",
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
        corners: "Corners",
        other: "Actions",
        leftHalf: "Left",
        rightHalf: "Right",
        topHalf: "Top",
        bottomHalf: "Bottom",
        topLeft: "Top left",
        topRight: "Top right",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        maximize: "Maximize",
        center: "Center",
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
