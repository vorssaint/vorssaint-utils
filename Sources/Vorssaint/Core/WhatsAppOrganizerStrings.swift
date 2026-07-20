// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WhatsAppOrganizerStrings {
    let title: String
    let experimental: String
    let description: String
    let enabled: String
    let enabledCaption: String
    let destination: String
    let chooseFolder: String
    let useDefault: String
    let invalidDestination: String
    let organization: String
    let flat: String
    let byType: String
    let byMonth: String
    let delay: String
    let minutesFormat: String
    let duplicateAction: String
    let trashDuplicate: String
    let keepBoth: String
    let replaceExisting: String
    let duplicateCaption: String
    let organizeNow: String
    let undo: String
    let waiting: String
    let working: String
    let resultFormat: String
    let lastRunFormat: String
    let neverRun: String
    let notificationTitle: String
    let notificationFormat: String
    let privacyNote: String

    static func localized(_ language: AppLanguage) -> WhatsAppOrganizerStrings {
        switch language {
        case .es: return .es
        case .ptBR: return .ptBR
        default: return .enUS
        }
    }
}

extension WhatsAppOrganizerStrings {
    static let enUS = WhatsAppOrganizerStrings(
        title: "Automatic organization",
        experimental: "Experimental",
        description: "Moves stable WhatsApp downloads to a dedicated folder and detects exact repeat downloads.",
        enabled: "Organize automatically",
        enabledCaption: "WhatsApp may download a moved file again. Vorssaint cannot prevent the network download, but it can detect and discard an identical extra copy.",
        destination: "Destination folder",
        chooseFolder: "Choose…",
        useDefault: "Use Downloads/WhatsApp",
        invalidDestination: "Choose a folder other than Downloads itself.",
        organization: "Folder structure",
        flat: "No subfolders",
        byType: "By file type",
        byMonth: "By year and month",
        delay: "Wait before moving",
        minutesFormat: "%d minutes",
        duplicateAction: "When the same file is downloaded again",
        trashDuplicate: "Move the new copy to Trash",
        keepBoth: "Keep both copies",
        replaceExisting: "Replace the organized copy",
        duplicateCaption: "Duplicates are confirmed with a private SHA-256 digest. The organized copy is rechecked before another copy is discarded.",
        organizeNow: "Organize eligible files now",
        undo: "Undo last organization",
        waiting: "Watching Downloads",
        working: "Organizing WhatsApp files…",
        resultFormat: "%1$d moved · %2$d duplicates · %3$d failed",
        lastRunFormat: "Last organization %@: %d moved · %d duplicates · %d failed",
        neverRun: "No organization has run yet.",
        notificationTitle: "WhatsApp organization",
        notificationFormat: "%1$d files organized. %2$d duplicate downloads handled. %3$d failed.",
        privacyNote: "To identify exact duplicates, file bytes are read locally only while calculating a cryptographic digest. Contents and chats are never stored or uploaded."
    )

    static let es = WhatsAppOrganizerStrings(
        title: "Organización automática",
        experimental: "Experimental",
        description: "Mueve las descargas estables de WhatsApp a una carpeta específica y detecta las descargas repetidas exactas.",
        enabled: "Organizar automáticamente",
        enabledCaption: "WhatsApp puede volver a descargar un archivo movido. Vorssaint no puede impedir esa descarga, pero sí detectar y descartar una nueva copia idéntica.",
        destination: "Carpeta de destino",
        chooseFolder: "Elegir…",
        useDefault: "Usar Descargas/WhatsApp",
        invalidDestination: "Elige una carpeta distinta de la propia carpeta Descargas.",
        organization: "Estructura de carpetas",
        flat: "Sin subcarpetas",
        byType: "Por tipo de archivo",
        byMonth: "Por año y mes",
        delay: "Esperar antes de mover",
        minutesFormat: "%d minutos",
        duplicateAction: "Si se vuelve a descargar el mismo archivo",
        trashDuplicate: "Enviar la nueva copia a la Papelera",
        keepBoth: "Conservar las dos copias",
        replaceExisting: "Reemplazar la copia organizada",
        duplicateCaption: "Los duplicados se confirman con una huella SHA-256 privada. La copia organizada se vuelve a comprobar antes de descartar otra.",
        organizeNow: "Organizar ahora los archivos disponibles",
        undo: "Deshacer la última organización",
        waiting: "Vigilando Descargas",
        working: "Organizando archivos de WhatsApp…",
        resultFormat: "%1$d movidos · %2$d duplicados · %3$d fallidos",
        lastRunFormat: "Última organización %@: %d movidos · %d duplicados · %d fallidos",
        neverRun: "Todavía no se ha realizado ninguna organización.",
        notificationTitle: "Organización de WhatsApp",
        notificationFormat: "%1$d archivos organizados. %2$d descargas duplicadas gestionadas. %3$d fallidos.",
        privacyNote: "Para reconocer duplicados exactos, los bytes del archivo solo se leen localmente mientras se calcula una huella criptográfica. El contenido y los chats nunca se guardan ni se envían."
    )

    static let ptBR = WhatsAppOrganizerStrings(
        title: "Organização automática",
        experimental: "Experimental",
        description: "Move downloads estáveis do WhatsApp para uma pasta dedicada e detecta downloads repetidos idênticos.",
        enabled: "Organizar automaticamente",
        enabledCaption: "O WhatsApp pode baixar novamente um arquivo movido. O Vorssaint não impede o download, mas detecta e descarta uma nova cópia idêntica.",
        destination: "Pasta de destino",
        chooseFolder: "Escolher…",
        useDefault: "Usar Downloads/WhatsApp",
        invalidDestination: "Escolha uma pasta diferente da própria pasta Downloads.",
        organization: "Estrutura de pastas",
        flat: "Sem subpastas",
        byType: "Por tipo de arquivo",
        byMonth: "Por ano e mês",
        delay: "Aguardar antes de mover",
        minutesFormat: "%d minutos",
        duplicateAction: "Ao baixar o mesmo arquivo novamente",
        trashDuplicate: "Mover a nova cópia para a Lixeira",
        keepBoth: "Manter as duas cópias",
        replaceExisting: "Substituir a cópia organizada",
        duplicateCaption: "Duplicados são confirmados com um resumo SHA-256 privado. A cópia organizada é verificada antes de outra ser descartada.",
        organizeNow: "Organizar agora os arquivos disponíveis",
        undo: "Desfazer a última organização",
        waiting: "Monitorando Downloads",
        working: "Organizando arquivos do WhatsApp…",
        resultFormat: "%1$d movidos · %2$d duplicados · %3$d falharam",
        lastRunFormat: "Última organização %@: %d movidos · %d duplicados · %d falharam",
        neverRun: "Nenhuma organização foi executada ainda.",
        notificationTitle: "Organização do WhatsApp",
        notificationFormat: "%1$d arquivos organizados. %2$d downloads duplicados tratados. %3$d falharam.",
        privacyNote: "Para identificar duplicados exatos, os bytes do arquivo são lidos localmente apenas durante o cálculo do resumo criptográfico. Conteúdos e conversas nunca são salvos nem enviados."
    )
}
