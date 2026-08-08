// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarOrganizerStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let setupTitle: String
    let setupCaption: String
    let finishSetup: String
    let visible: String
    let hidden: String
    let alwaysHidden: String
    let emptySection: String
    let dragHint: String
    let manualHint: String
    let refresh: String
    let undo: String
    let search: String
    let secondaryBar: String
    let searchPlaceholder: String
    let searchEmptyTitle: String
    let searchEmptyCaption: String
    let searchShow: String
    let searchOpen: String
    let accessibilityCaption: String
    let screenRecordingCaption: String
    let automaticMoveUnavailable: String
    let sectionsTitle: String
    let alwaysHiddenToggle: String
    let showDividers: String
    let capturePreviews: String
    let presentationTitle: String
    let presentationAutomatic: String
    let presentationMenuBar: String
    let presentationSecondary: String
    let rehideTitle: String
    let rehideNever: String
    let rehideDelay: String
    let rehideFocusedApp: String
    let delayFormat: String
    let triggersTitle: String
    let showOnHover: String
    let showOnEmptyClick: String
    let showOnScroll: String
    let smartNotchMode: String
    let smartNotchCaption: String
    let advancedTriggersCaption: String
    let triggerPreset: String
    let triggerLowBattery: String
    let triggerCharging: String
    let triggerExternalDisplay: String
    let triggerWorkHours: String
    let triggerWorkHoursWeekdays: String
    let presetsTitle: String
    let presetsCaption: String
    let namedPresetsTitle: String
    let namedPresetName: String
    let namedPresetSave: String
    let namedPresetDelete: String
    let presetWork: String
    let presetHome: String
    let presetPresenting: String
    let presetMinimal: String
    let presetUnsaved: String
    let presetSave: String
    let presetApply: String
    let presetClear: String
    let groupsTitle: String
    let groupsCaption: String
    let customGroupsTitle: String
    let customGroupName: String
    let customGroupSymbol: String
    let customGroupCreate: String
    let customGroupDelete: String
    let groupCloud: String
    let groupAudio: String
    let groupWork: String
    let groupCustom: String
    let groupEmpty: String
    let groupAddTo: String
    let groupRemoveFrom: String
    let groupOpen: String
    let groupClear: String
    let groupStatusItems: String
    let groupStatusItemsCaption: String
    let groupAutoHide: String
    let groupAutoHideCaption: String
    let spacingTitle: String
    let spacerCount: String
    let spacerWidth: String
    let barStyle: String
    let barStyleSystem: String
    let barStyleTinted: String
    let barStyleGraphite: String
    let barStyleVibrant: String
    let shortcutsTitle: String
    let toggleHiddenShortcut: String
    let toggleAlwaysShortcut: String
    let searchShortcut: String
    let inspiredByIce: String
}

extension FeatureStrings {
    static func menuBarOrganizer(_ language: AppLanguage) -> MenuBarOrganizerStrings {
        switch language {
        case .es: return .es
        case .enUS: return .enUS
        case .ptBR: return .ptBR
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
        }
    }
}

extension MenuBarOrganizerStrings {
    static let enUS = MenuBarOrganizerStrings(
        pageTitle: "Menu Bar",
        hubDescription: "Hide, reveal, search and arrange menu bar items",
        enable: "Manage menu bar items",
        enableCaption: "Creates movable section dividers. Your layout remains managed by macOS.",
        setupTitle: "Set up your sections",
        setupCaption: "Drag items between the three sections. Nothing is hidden until you finish setup.",
        finishSetup: "Finish setup and hide items",
        visible: "Visible",
        hidden: "Hidden",
        alwaysHidden: "Always hidden",
        emptySection: "Drop menu bar items here",
        dragHint: "Drag to reorder. Changes are applied to the real menu bar immediately.",
        manualHint: "If automatic movement fails, hold Command and drag the real item across the visible dividers.",
        refresh: "Refresh",
        undo: "Undo last move",
        search: "Search items",
        secondaryBar: "Show secondary bar",
        searchPlaceholder: "Search menu bar items",
        searchEmptyTitle: "No menu bar items",
        searchEmptyCaption: "Try another search.",
        searchShow: "Show",
        searchOpen: "Open",
        accessibilityCaption: "Accessibility lets Vorssaint perform the same Command-drag gesture you can do manually.",
        screenRecordingCaption: "Optional. Allows exact previews; names and app icons are used without it.",
        automaticMoveUnavailable: "Automatic arranging is unavailable. Manual Command-drag remains available.",
        sectionsTitle: "Sections",
        alwaysHiddenToggle: "Enable the always-hidden section",
        showDividers: "Keep section dividers visible",
        capturePreviews: "Show exact item previews",
        presentationTitle: "How to show hidden items",
        presentationAutomatic: "Automatic",
        presentationMenuBar: "In the menu bar",
        presentationSecondary: "In a secondary bar",
        rehideTitle: "Rehide",
        rehideNever: "Never automatically",
        rehideDelay: "After a delay",
        rehideFocusedApp: "When the focused app changes",
        delayFormat: "%d seconds",
        triggersTitle: "Triggers",
        showOnHover: "Show when hovering over the menu bar",
        showOnEmptyClick: "Toggle by clicking empty menu bar space",
        showOnScroll: "Toggle by scrolling or swiping over the menu bar",
        smartNotchMode: "Make room near the notch automatically",
        smartNotchCaption: "When Automatic is selected, Vorssaint can temporarily tuck lower-priority visible items away before revealing hidden items in the real menu bar.",
        advancedTriggersCaption: "Apply saved presets automatically when these conditions become true.",
        triggerPreset: "Preset",
        triggerLowBattery: "Low battery",
        triggerCharging: "Charging or on power",
        triggerExternalDisplay: "External display connected",
        triggerWorkHours: "Work hours",
        triggerWorkHoursWeekdays: "Weekdays only",
        presetsTitle: "Presets",
        presetsCaption: "Save and restore complete menu bar layouts for different contexts.",
        namedPresetsTitle: "Named presets",
        namedPresetName: "Preset name",
        namedPresetSave: "Save named preset",
        namedPresetDelete: "Delete",
        presetWork: "Work",
        presetHome: "Home",
        presetPresenting: "Presenting",
        presetMinimal: "Minimal",
        presetUnsaved: "Not saved yet",
        presetSave: "Save",
        presetApply: "Apply",
        presetClear: "Clear",
        groupsTitle: "Groups",
        groupsCaption: "Collect related items so they can be opened together from Search or the secondary bar.",
        customGroupsTitle: "Custom groups",
        customGroupName: "Group name",
        customGroupSymbol: "SF Symbol",
        customGroupCreate: "Create group",
        customGroupDelete: "Delete group",
        groupCloud: "Cloud",
        groupAudio: "Audio",
        groupWork: "Work",
        groupCustom: "Custom",
        groupEmpty: "No items in this group yet",
        groupAddTo: "Add to group",
        groupRemoveFrom: "Remove from group",
        groupOpen: "Open group",
        groupClear: "Clear",
        groupStatusItems: "Show group icons in the menu bar",
        groupStatusItemsCaption: "Each group with available items gets its own compact icon. Click it to open that group.",
        groupAutoHide: "Move grouped items to Hidden",
        groupAutoHideCaption: "When enabled, visible items added to a group are tucked into Hidden so the group icon becomes their main access point.",
        spacingTitle: "Spacing and style",
        spacerCount: "Spacer items",
        spacerWidth: "Spacer width",
        barStyle: "Secondary bar style",
        barStyleSystem: "System",
        barStyleTinted: "Tinted",
        barStyleGraphite: "Graphite",
        barStyleVibrant: "Vibrant",
        shortcutsTitle: "Keyboard shortcuts",
        toggleHiddenShortcut: "Toggle hidden items",
        toggleAlwaysShortcut: "Toggle always-hidden items",
        searchShortcut: "Search menu bar items",
        inspiredByIce: "Inspired by Ice, independently implemented for Vorssaint."
    )

    static let es = MenuBarOrganizerStrings(
        pageTitle: "Barra de menús",
        hubDescription: "Oculta, muestra, busca y ordena los elementos de la barra",
        enable: "Gestionar los elementos de la barra de menús",
        enableCaption: "Crea separadores móviles. macOS sigue siendo quien conserva la disposición.",
        setupTitle: "Configura tus secciones",
        setupCaption: "Arrastra elementos entre las tres secciones. No se ocultará nada hasta que termines.",
        finishSetup: "Terminar y ocultar los elementos",
        visible: "Visible",
        hidden: "Oculta",
        alwaysHidden: "Siempre oculta",
        emptySection: "Suelta aquí elementos de la barra",
        dragHint: "Arrastra para reordenar. Los cambios se aplican inmediatamente a la barra real.",
        manualHint: "Si falla el movimiento automático, mantén Comando y arrastra el elemento real entre los separadores visibles.",
        refresh: "Actualizar",
        undo: "Deshacer último movimiento",
        search: "Buscar elementos",
        secondaryBar: "Mostrar barra secundaria",
        searchPlaceholder: "Buscar elementos de la barra",
        searchEmptyTitle: "No hay elementos",
        searchEmptyCaption: "Prueba con otra búsqueda.",
        searchShow: "Mostrar",
        searchOpen: "Abrir",
        accessibilityCaption: "Accesibilidad permite que Vorssaint realice el mismo gesto Comando-arrastrar que puedes hacer manualmente.",
        screenRecordingCaption: "Opcional. Permite vistas exactas; sin el permiso se usan nombres e iconos de aplicación.",
        automaticMoveUnavailable: "El reordenado automático no está disponible. Puedes seguir usando Comando-arrastrar.",
        sectionsTitle: "Secciones",
        alwaysHiddenToggle: "Activar la sección siempre oculta",
        showDividers: "Mantener visibles los separadores",
        capturePreviews: "Mostrar vistas exactas de los elementos",
        presentationTitle: "Cómo mostrar los elementos ocultos",
        presentationAutomatic: "Automático",
        presentationMenuBar: "En la barra de menús",
        presentationSecondary: "En una barra secundaria",
        rehideTitle: "Volver a ocultar",
        rehideNever: "Nunca automáticamente",
        rehideDelay: "Tras una espera",
        rehideFocusedApp: "Al cambiar la aplicación activa",
        delayFormat: "%d segundos",
        triggersTitle: "Activadores",
        showOnHover: "Mostrar al pasar por la barra de menús",
        showOnEmptyClick: "Alternar al pulsar un espacio vacío de la barra",
        showOnScroll: "Alternar al desplazar o deslizar sobre la barra",
        smartNotchMode: "Hacer sitio junto al notch automáticamente",
        smartNotchCaption: "Con el modo Automático, Vorssaint puede apartar temporalmente elementos visibles de menor prioridad antes de mostrar los ocultos en la barra real.",
        advancedTriggersCaption: "Aplica presets guardados automáticamente cuando se cumplan estas condiciones.",
        triggerPreset: "Preset",
        triggerLowBattery: "Batería baja",
        triggerCharging: "Cargando o con corriente",
        triggerExternalDisplay: "Pantalla externa conectada",
        triggerWorkHours: "Horario de trabajo",
        triggerWorkHoursWeekdays: "Sólo laborables",
        presetsTitle: "Presets",
        presetsCaption: "Guarda y restaura disposiciones completas de la barra para distintos contextos.",
        namedPresetsTitle: "Presets con nombre",
        namedPresetName: "Nombre del preset",
        namedPresetSave: "Guardar preset con nombre",
        namedPresetDelete: "Eliminar",
        presetWork: "Trabajo",
        presetHome: "Casa",
        presetPresenting: "Presentando",
        presetMinimal: "Mínima",
        presetUnsaved: "Sin guardar",
        presetSave: "Guardar",
        presetApply: "Aplicar",
        presetClear: "Borrar",
        groupsTitle: "Grupos",
        groupsCaption: "Agrupa elementos relacionados para abrirlos juntos desde la búsqueda o la barra secundaria.",
        customGroupsTitle: "Grupos personalizados",
        customGroupName: "Nombre del grupo",
        customGroupSymbol: "Símbolo SF",
        customGroupCreate: "Crear grupo",
        customGroupDelete: "Eliminar grupo",
        groupCloud: "Cloud",
        groupAudio: "Audio",
        groupWork: "Trabajo",
        groupCustom: "Custom",
        groupEmpty: "Este grupo todavía no tiene elementos",
        groupAddTo: "Añadir a grupo",
        groupRemoveFrom: "Quitar del grupo",
        groupOpen: "Abrir grupo",
        groupClear: "Borrar",
        groupStatusItems: "Mostrar iconos de grupo en la barra de menús",
        groupStatusItemsCaption: "Cada grupo con elementos disponibles tiene su propio icono compacto. Pulsa para abrirlo.",
        groupAutoHide: "Mover elementos agrupados a Oculta",
        groupAutoHideCaption: "Al activarlo, los elementos visibles que añadas a un grupo se apartan a Oculta para que el icono del grupo sea su acceso principal.",
        spacingTitle: "Espaciado y estilo",
        spacerCount: "Espaciadores",
        spacerWidth: "Anchura del espaciador",
        barStyle: "Estilo de la barra secundaria",
        barStyleSystem: "Sistema",
        barStyleTinted: "Tintado",
        barStyleGraphite: "Grafito",
        barStyleVibrant: "Vibrante",
        shortcutsTitle: "Atajos de teclado",
        toggleHiddenShortcut: "Alternar elementos ocultos",
        toggleAlwaysShortcut: "Alternar elementos siempre ocultos",
        searchShortcut: "Buscar elementos de la barra",
        inspiredByIce: "Inspirado en Ice e implementado de forma independiente para Vorssaint."
    )

    // English is the deliberate fallback until community translations land;
    // the app never exposes an empty or mismatched localization contract.
    static let ptBR = enUS
    static let tr = enUS
    static let ru = enUS
    static let de = enUS
    static let fr = enUS
    static let it = enUS
    static let ja = enUS
    static let ko = enUS
    static let zhHans = enUS
    static let zhTW = enUS
    static let zhHK = enUS
}
