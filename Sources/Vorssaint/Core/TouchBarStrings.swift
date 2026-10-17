// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TouchBarFeatureStrings {
    let title: String
    let hubDescription: String
    let unavailable: String
    let keepAwake: String
    let microphoneMute: String
    let systemMetrics: String
    let quickLauncher: String
    let freeRAM: String
    let ramCleanupCompleted: String
}

extension TouchBarFeatureStrings {
    static let enUS = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Customize controls and information shown on the Touch Bar",
        unavailable: "This Mac does not have a Touch Bar.",
        keepAwake: "Keep Awake",
        microphoneMute: "Microphone Mute",
        systemMetrics: "System Metrics",
        quickLauncher: "Quick Launcher",
        freeRAM: "Free RAM",
        ramCleanupCompleted: "RAM cleanup completed"
    )

    static let ptBR = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personalize os controles e as informações exibidos na Touch Bar",
        unavailable: "Este Mac não possui uma Touch Bar.",
        keepAwake: "Manter Ativo",
        microphoneMute: "Silenciar Microfone",
        systemMetrics: "Métricas do Sistema",
        quickLauncher: "Acesso Rápido",
        freeRAM: "Liberar RAM",
        ramCleanupCompleted: "Limpeza de RAM concluída"
    )

    static let tr = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Touch Bar'da gösterilen denetimleri ve bilgileri özelleştirin",
        unavailable: "Bu Mac'te Touch Bar yok.",
        keepAwake: "Uyanık Tut",
        microphoneMute: "Mikrofonu Sessize Al",
        systemMetrics: "Sistem Ölçümleri",
        quickLauncher: "Hızlı Başlatıcı",
        freeRAM: "RAM'i Boşalt",
        ramCleanupCompleted: "RAM temizleme tamamlandı"
    )

    static let ru = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Настройте элементы управления и информацию на Touch Bar",
        unavailable: "На этом Mac нет Touch Bar.",
        keepAwake: "Не выключать",
        microphoneMute: "Выключить микрофон",
        systemMetrics: "Показатели системы",
        quickLauncher: "Быстрый запуск",
        freeRAM: "Освободить RAM",
        ramCleanupCompleted: "Очистка RAM завершена"
    )

    static let es = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personaliza los controles y la información que se muestran en la Touch Bar",
        unavailable: "Este Mac no tiene Touch Bar.",
        keepAwake: "Mantener Activo",
        microphoneMute: "Silenciar Micrófono",
        systemMetrics: "Métricas del Sistema",
        quickLauncher: "Inicio Rápido",
        freeRAM: "Liberar RAM",
        ramCleanupCompleted: "Limpieza de RAM completada"
    )

    static let de = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Passe die Steuerelemente und Informationen auf der Touch Bar an",
        unavailable: "Dieser Mac hat keine Touch Bar.",
        keepAwake: "Wach halten",
        microphoneMute: "Mikrofon stummschalten",
        systemMetrics: "Systemmetriken",
        quickLauncher: "Schnellstarter",
        freeRAM: "RAM freigeben",
        ramCleanupCompleted: "RAM-Bereinigung abgeschlossen"
    )

    static let fr = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personnalisez les commandes et les informations affichées sur la Touch Bar",
        unavailable: "Ce Mac ne possède pas de Touch Bar.",
        keepAwake: "Maintenir Éveillé",
        microphoneMute: "Couper le Micro",
        systemMetrics: "Métriques Système",
        quickLauncher: "Lancement Rapide",
        freeRAM: "Libérer la RAM",
        ramCleanupCompleted: "Nettoyage de la RAM terminé"
    )

    static let it = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Personalizza i controlli e le informazioni mostrati sulla Touch Bar",
        unavailable: "Questo Mac non dispone di Touch Bar.",
        keepAwake: "Mantieni Attivo",
        microphoneMute: "Disattiva Microfono",
        systemMetrics: "Metriche di Sistema",
        quickLauncher: "Avvio Rapido",
        freeRAM: "Libera RAM",
        ramCleanupCompleted: "Pulizia RAM completata"
    )

    static let ja = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Touch Bar に表示するコントロールと情報をカスタマイズ",
        unavailable: "このMacにはTouch Barがありません。",
        keepAwake: "スリープを防止",
        microphoneMute: "マイクをミュート",
        systemMetrics: "システム情報",
        quickLauncher: "クイックランチャー",
        freeRAM: "RAMを解放",
        ramCleanupCompleted: "RAMのクリーンアップが完了しました"
    )

    static let ko = TouchBarFeatureStrings(
        title: "Touch Bar",
        hubDescription: "Touch Bar에 표시되는 제어 항목과 정보를 사용자화합니다",
        unavailable: "이 Mac에는 Touch Bar가 없습니다.",
        keepAwake: "잠자기 방지",
        microphoneMute: "마이크 음소거",
        systemMetrics: "시스템 정보",
        quickLauncher: "빠른 실행",
        freeRAM: "RAM 확보",
        ramCleanupCompleted: "RAM 정리가 완료되었습니다"
    )

    static let zhHans = TouchBarFeatureStrings(
        title: "触控栏",
        hubDescription: "自定义触控栏上显示的控制项和信息",
        unavailable: "此 Mac 没有触控栏。",
        keepAwake: "保持唤醒",
        microphoneMute: "麦克风静音",
        systemMetrics: "系统指标",
        quickLauncher: "快速启动",
        freeRAM: "释放 RAM",
        ramCleanupCompleted: "RAM 清理完成"
    )

    static let zhTW = TouchBarFeatureStrings(
        title: "觸控列",
        hubDescription: "自訂觸控列上顯示的控制項目與資訊",
        unavailable: "此 Mac 沒有觸控列。",
        keepAwake: "保持喚醒",
        microphoneMute: "麥克風靜音",
        systemMetrics: "系統指標",
        quickLauncher: "快速啟動",
        freeRAM: "釋放 RAM",
        ramCleanupCompleted: "RAM 清理完成"
    )

    static let zhHK = TouchBarFeatureStrings(
        title: "觸控欄",
        hubDescription: "自訂觸控欄上顯示的控制項目與資料",
        unavailable: "此 Mac 沒有觸控欄。",
        keepAwake: "保持喚醒",
        microphoneMute: "咪高峰靜音",
        systemMetrics: "系統指標",
        quickLauncher: "快速啟動",
        freeRAM: "釋放 RAM",
        ramCleanupCompleted: "RAM 清理完成"
    )
}