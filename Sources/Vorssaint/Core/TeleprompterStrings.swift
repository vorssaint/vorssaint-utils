// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

public struct TeleprompterStrings {
    public let title: String
    public let hubDescription: String
    public let guidanceMode: String
    public let wordTracking: String
    public let wordTrackingDesc: String
    public let classic: String
    public let classicDesc: String
    public let voiceActivated: String
    public let voiceActivatedDesc: String
    public let scrollSpeed: String
    public let fontSize: String
    public let fontFamily: String
    public let highlightColor: String
    public let speechLanguage: String
    public let autoDetect: String
    public let microphone: String
    public let defaultMic: String
    public let importNotes: String
    public let importNotesDesc: String
    public let remoteServer: String
    public let remoteServerDesc: String
    public let hideFromScreenSharing: String
    public let hideFromScreenSharingDesc: String
    public let scanQRCode: String
    public let start: String
    public let pause: String
    public let resume: String
    public let stop: String
    public let editScript: String
    public let scriptPlaceholder: String
    public let slide: String
    public let prevSlide: String
    public let nextSlide: String
    public let noScript: String
    public let listening: String
    public let paused: String
    public let ready: String
    public let stopped: String

    public static let enUS = TeleprompterStrings(
        title: "Teleprompter",
        hubDescription: "Voice-activated, word-tracking teleprompter in the notch with remote control.",
        guidanceMode: "Guidance Mode",
        wordTracking: "Word Tracking",
        wordTrackingDesc: "Highlights words in real time as you speak them using speech recognition.",
        classic: "Continuous Scroll",
        classicDesc: "Scrolls the script smoothly at a constant adjustable speed.",
        voiceActivated: "Voice Activated",
        voiceActivatedDesc: "Advances scrolling only while your voice is actively detected.",
        scrollSpeed: "Scroll Speed",
        fontSize: "Font Size",
        fontFamily: "Font Family",
        highlightColor: "Highlight Color",
        speechLanguage: "Speech Language",
        autoDetect: "Auto Detect",
        microphone: "Microphone",
        defaultMic: "System Default",
        importNotes: "Import Presentation (.pptx)",
        importNotesDesc: "Extracts presenter notes slide-by-slide from a PowerPoint presentation file.",
        remoteServer: "Remote Prompter Server",
        remoteServerDesc: "Stream script and control prompter wirelessly from mobile browsers or tablets on your local network.",
        hideFromScreenSharing: "Hide from screen sharing",
        hideFromScreenSharingDesc: "Exclude the running teleprompter from screen sharing and capture. To hide the ready Notch too, turn off Show in screenshots and videos under Dynamic Island → Behavior → Privacy.",
        scanQRCode: "Scan with your phone or tablet to open:",
        start: "Start Prompter",
        pause: "Pause",
        resume: "Resume",
        stop: "Stop",
        editScript: "Edit Script",
        scriptPlaceholder: "Paste or write your speech script here...\n\nSupports cue tags like [pause], [smile], or slide breaks ---",
        slide: "Slide",
        prevSlide: "Previous Slide",
        nextSlide: "Next Slide",
        noScript: "No script loaded. Click Edit Script to enter text or import slides.",
        listening: "Listening...",
        paused: "Paused",
        ready: "Ready",
        stopped: "Stopped"
    )

    public static let tr = TeleprompterStrings(
        title: "Teleprompter",
        hubDescription: "Ses algılama ve kelime takibiyle notch üzerinde teleprompter.",
        guidanceMode: "Yönlendirme Modu",
        wordTracking: "Kelime Takibi",
        wordTrackingDesc: "Konuşma tanıma ile konuştukça kelimeleri gerçek zamanlı vurgular.",
        classic: "Sürekli Kaydırma",
        classicDesc: "Metni ayarlanabilir sabit bir hızda kaydırır.",
        voiceActivated: "Sesle Etkinleşen",
        voiceActivatedDesc: "Sadece sesiniz algılandığında kaydırmayı sürdürür.",
        scrollSpeed: "Kaydırma Hızı",
        fontSize: "Yazı Boyutu",
        fontFamily: "Yazı Tipi",
        highlightColor: "Vurgu Rengi",
        speechLanguage: "Konuşma Dili",
        autoDetect: "Otomatik Algıla",
        microphone: "Mikrofon",
        defaultMic: "Sistem Varsayılanı",
        importNotes: "Sunum İçe Aktar (.pptx)",
        importNotesDesc: "PowerPoint sunum dosyasından slayt notlarını ayıklar.",
        remoteServer: "Uzaktan Prompter Sunucusu",
        remoteServerDesc: "Yerel ağınızdaki telefon veya tablet tarayıcısından kablosuz prompter yayını yapın.",
        hideFromScreenSharing: "Ekran paylaşımında gizle",
        hideFromScreenSharingDesc: "Teleprompter çalışırken ekran paylaşımında ve yakalamalarda görünmesini engeller. Hazır durumundaki Notch’u da gizlemek için Dynamic Island → Behavior → Privacy bölümündeki Show in screenshots and videos seçeneğini kapatın.",
        scanQRCode: "Telefonunuzla taratarak açın:",
        start: "Başlat",
        pause: "Duraklat",
        resume: "Devam Et",
        stop: "Durdur",
        editScript: "Metni Düzenle",
        scriptPlaceholder: "Metninizi buraya yazın veya yapıştırın...\n\n[pause], [smile] gibi ipuçları veya --- ile slayt ayrımları kullanabilirsiniz",
        slide: "Slayt",
        prevSlide: "Önceki Slayt",
        nextSlide: "Sonraki Slayt",
        noScript: "Metin girilmedi. Metin girmek için Metni Düzenle’ye tıklayın.",
        listening: "Dinleniyor...",
        paused: "Duraklatıldı",
        ready: "Hazır",
        stopped: "Durduruldu"
    )
}

extension FeatureStrings {
    public static func teleprompter(_ language: AppLanguage) -> TeleprompterStrings {
        switch language {
        case .tr: return .tr
        default: return .enUS
        }
    }
}
