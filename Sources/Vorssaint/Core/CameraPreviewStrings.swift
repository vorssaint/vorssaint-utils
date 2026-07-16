// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the camera preview mirror.
struct CameraPreviewFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let cameraMenuLabel: String
    let deniedMessage: String
    let noCameraMessage: String
    let permName: String
    let permExplain: String
}

extension FeatureStrings {
    static func cameraPreview(_ language: AppLanguage) -> CameraPreviewFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
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

extension CameraPreviewFeatureStrings {
    static let enUS = CameraPreviewFeatureStrings(
        pageTitle: "Camera preview",
        hubDescription: "Opens a floating mirror with your camera",
        panelCaption: "Check how you look before a call",
        openButton: "Open preview",
        cameraMenuLabel: "Camera",
        deniedMessage: "Camera access for Vorssaint is turned off in System Settings.",
        noCameraMessage: "No camera detected",
        permName: "Camera",
        permExplain: "Shows your camera only in the preview window, so you can check how you look before a call. Nothing is recorded or leaves your Mac."
    )

    static let ptBR = CameraPreviewFeatureStrings(
        pageTitle: "Prévia da câmera",
        hubDescription: "Abre um espelho flutuante com a sua câmera",
        panelCaption: "Veja como você está antes de uma chamada",
        openButton: "Abrir prévia",
        cameraMenuLabel: "Câmera",
        deniedMessage: "O acesso à câmera para o Vorssaint está desativado nos Ajustes do Sistema.",
        noCameraMessage: "Nenhuma câmera detectada",
        permName: "Câmera",
        permExplain: "Mostra a sua câmera somente na janela de prévia, para você conferir como está antes de uma chamada. Nada é gravado nem sai do seu Mac."
    )

    static let tr = CameraPreviewFeatureStrings(
        pageTitle: "Kamera önizlemesi",
        hubDescription: "Kameranızı gösteren yüzen bir ayna açar",
        panelCaption: "Aramadan önce nasıl göründüğünüzü kontrol edin",
        openButton: "Önizlemeyi aç",
        cameraMenuLabel: "Kamera",
        deniedMessage: "Vorssaint için kamera erişimi Sistem Ayarları'nda kapalı.",
        noCameraMessage: "Kamera bulunamadı",
        permName: "Kamera",
        permExplain: "Kameranızı yalnızca önizleme penceresinde gösterir; böylece aramadan önce nasıl göründüğünüzü kontrol edebilirsiniz. Hiçbir şey kaydedilmez ve Mac'inizden çıkmaz."
    )

    static let ru = CameraPreviewFeatureStrings(
        pageTitle: "Предпросмотр камеры",
        hubDescription: "Открывает парящее зеркало с изображением с камеры",
        panelCaption: "Проверьте, как вы выглядите, перед звонком",
        openButton: "Открыть предпросмотр",
        cameraMenuLabel: "Камера",
        deniedMessage: "Доступ к камере для Vorssaint отключен в Системных настройках.",
        noCameraMessage: "Камера не обнаружена",
        permName: "Камера",
        permExplain: "Показывает изображение с камеры только в окне предпросмотра, чтобы вы могли проверить, как выглядите перед звонком. Ничего не записывается и не покидает ваш Mac."
    )

    static let es = CameraPreviewFeatureStrings(
        pageTitle: "Vista previa de la cámara",
        hubDescription: "Abre un espejo flotante con tu cámara",
        panelCaption: "Mira cómo te ves antes de una llamada",
        openButton: "Abrir vista previa",
        cameraMenuLabel: "Cámara",
        deniedMessage: "El acceso a la cámara para Vorssaint está desactivado en Ajustes del Sistema.",
        noCameraMessage: "No se detectó ninguna cámara",
        permName: "Cámara",
        permExplain: "Muestra tu cámara solo en la ventana de vista previa, para que compruebes cómo te ves antes de una llamada. No se graba nada y nada sale de tu Mac."
    )

    static let de = CameraPreviewFeatureStrings(
        pageTitle: "Kameravorschau",
        hubDescription: "Öffnet einen schwebenden Spiegel mit deiner Kamera",
        panelCaption: "Prüfe vor einem Anruf, wie du aussiehst",
        openButton: "Vorschau öffnen",
        cameraMenuLabel: "Kamera",
        deniedMessage: "Der Kamerazugriff für Vorssaint ist in den Systemeinstellungen deaktiviert.",
        noCameraMessage: "Keine Kamera gefunden",
        permName: "Kamera",
        permExplain: "Zeigt deine Kamera nur im Vorschaufenster, damit du vor einem Anruf prüfen kannst, wie du aussiehst. Nichts wird aufgezeichnet und nichts verlässt deinen Mac."
    )

    static let fr = CameraPreviewFeatureStrings(
        pageTitle: "Aperçu de la caméra",
        hubDescription: "Ouvre un miroir flottant avec votre caméra",
        panelCaption: "Vérifiez votre apparence avant un appel",
        openButton: "Ouvrir l'aperçu",
        cameraMenuLabel: "Caméra",
        deniedMessage: "L'accès à la caméra pour Vorssaint est désactivé dans Réglages Système.",
        noCameraMessage: "Aucune caméra détectée",
        permName: "Caméra",
        permExplain: "Affiche votre caméra uniquement dans la fenêtre d'aperçu, pour vérifier votre apparence avant un appel. Rien n'est enregistré et rien ne quitte votre Mac."
    )

    static let it = CameraPreviewFeatureStrings(
        pageTitle: "Anteprima della fotocamera",
        hubDescription: "Apre uno specchio fluttuante con la tua fotocamera",
        panelCaption: "Controlla il tuo aspetto prima di una chiamata",
        openButton: "Apri anteprima",
        cameraMenuLabel: "Fotocamera",
        deniedMessage: "L'accesso alla fotocamera per Vorssaint è disattivato in Impostazioni di Sistema.",
        noCameraMessage: "Nessuna fotocamera rilevata",
        permName: "Fotocamera",
        permExplain: "Mostra la tua fotocamera solo nella finestra di anteprima, così controlli il tuo aspetto prima di una chiamata. Nulla viene registrato e nulla lascia il tuo Mac."
    )

    static let ja = CameraPreviewFeatureStrings(
        pageTitle: "カメラプレビュー",
        hubDescription: "カメラを映すフローティングミラーを開きます",
        panelCaption: "通話の前に写り方を確認できます",
        openButton: "プレビューを開く",
        cameraMenuLabel: "カメラ",
        deniedMessage: "システム設定でVorssaintのカメラへのアクセスがオフになっています。",
        noCameraMessage: "カメラが見つかりません",
        permName: "カメラ",
        permExplain: "プレビューウインドウにのみカメラを表示し、通話前に写り方を確認できます。録画されることはなく、Macの外に出ることもありません。"
    )

    static let ko = CameraPreviewFeatureStrings(
        pageTitle: "카메라 미리보기",
        hubDescription: "카메라를 비추는 떠 있는 거울을 엽니다",
        panelCaption: "통화 전에 내 모습을 확인하세요",
        openButton: "미리보기 열기",
        cameraMenuLabel: "카메라",
        deniedMessage: "시스템 설정에서 Vorssaint의 카메라 접근이 꺼져 있습니다.",
        noCameraMessage: "카메라를 찾을 수 없습니다",
        permName: "카메라",
        permExplain: "미리보기 윈도우에만 카메라를 표시하여 통화 전에 모습을 확인할 수 있습니다. 아무것도 녹화되지 않으며 Mac 밖으로 나가지 않습니다."
    )

    static let zhHans = CameraPreviewFeatureStrings(
        pageTitle: "相机预览",
        hubDescription: "打开一面显示相机画面的浮动镜子",
        panelCaption: "通话前看看自己的状态",
        openButton: "打开预览",
        cameraMenuLabel: "相机",
        deniedMessage: "Vorssaint 的相机访问权限已在系统设置中关闭。",
        noCameraMessage: "未检测到相机",
        permName: "相机",
        permExplain: "仅在预览窗口中显示相机画面，方便你在通话前查看自己的状态。不会录制任何内容，也不会离开你的 Mac。"
    )

    static let zhTW = CameraPreviewFeatureStrings(
        pageTitle: "相機預覽",
        hubDescription: "打開一面顯示相機畫面的浮動鏡子",
        panelCaption: "通話前看看自己的狀態",
        openButton: "打開預覽",
        cameraMenuLabel: "相機",
        deniedMessage: "Vorssaint 的相機取用權限已在系統設定中關閉。",
        noCameraMessage: "未偵測到相機",
        permName: "相機",
        permExplain: "只在預覽視窗中顯示相機畫面，讓你在通話前確認自己的狀態。不會錄製任何內容，也不會離開你的 Mac。"
    )

    static let zhHK = CameraPreviewFeatureStrings(
        pageTitle: "相機預覽",
        hubDescription: "打開一面顯示相機畫面的浮動鏡子",
        panelCaption: "通話前看看自己的狀態",
        openButton: "打開預覽",
        cameraMenuLabel: "相機",
        deniedMessage: "Vorssaint 的相機取用權限已在系統設定中關閉。",
        noCameraMessage: "未偵測到相機",
        permName: "相機",
        permExplain: "只在預覽視窗中顯示相機畫面，讓你在通話前確認自己的狀態。不會錄製任何內容，也不會離開你的 Mac。"
    )
}
