// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the volume of a monitor’s own speakers. Same contract as the
/// other FeatureStrings structs: memberwise init in declaration order, one
/// static per language, all in this file.
struct MonitorVolumeStrings {
    let title: String
    let keysToggle: String
    let keysCaption: String
    let monitorToggle: String
    let monitorCaption: String
    let mute: String
}

extension FeatureStrings {
    static func monitorVolume(_ language: AppLanguage) -> MonitorVolumeStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension MonitorVolumeStrings {
    static let enUS = MonitorVolumeStrings(
        title: "Volume",
        keysToggle: "Volume keys for the monitor’s speakers",
        keysCaption: "When the Mac plays sound through an external monitor, F10, F11 and F12 change that monitor’s own volume over DDC/CI. Needs the monitor’s volume turned on below.",
        monitorToggle: "Control this monitor’s volume",
        monitorCaption: "This monitor does not report its volume, so support cannot be checked. Turn it on, press a volume key and listen for a change.",
        mute: "Mute")
    static let ptBR = MonitorVolumeStrings(
        title: "Volume",
        keysToggle: "Teclas de volume para os alto-falantes do monitor",
        keysCaption: "Quando o Mac toca o som por um monitor externo, F10, F11 e F12 mudam o volume do próprio monitor por DDC/CI. Exige ativar o volume do monitor abaixo.",
        monitorToggle: "Controlar o volume deste monitor",
        monitorCaption: "Este monitor não informa o volume, então o suporte não pode ser verificado. Ative, pressione uma tecla de volume e ouça se muda.",
        mute: "Silenciar")
    static let tr = MonitorVolumeStrings(
        title: "Ses",
        keysToggle: "Monitörün hoparlörleri için ses tuşları",
        keysCaption: "Mac sesi harici bir monitörden çaldığında F10, F11 ve F12 monitörün kendi sesini DDC/CI ile değiştirir. Aşağıda monitörün ses kontrolünün açık olması gerekir.",
        monitorToggle: "Bu monitörün sesini denetle",
        monitorCaption: "Bu monitör sesini bildirmediği için destek doğrulanamaz. Açın, bir ses tuşuna basın ve değişip değişmediğini dinleyin.",
        mute: "Sessize al")
    static let ru = MonitorVolumeStrings(
        title: "Громкость",
        keysToggle: "Клавиши громкости для динамиков монитора",
        keysCaption: "Когда Mac воспроизводит звук через внешний монитор, F10, F11 и F12 меняют громкость самого монитора через DDC/CI. Нужно включить громкость монитора ниже.",
        monitorToggle: "Управлять громкостью этого монитора",
        monitorCaption: "Этот монитор не сообщает свою громкость, поэтому поддержку нельзя проверить. Включите, нажмите клавишу громкости и послушайте, меняется ли звук.",
        mute: "Выключить звук")
    static let es = MonitorVolumeStrings(
        title: "Volumen",
        keysToggle: "Teclas de volumen para los altavoces del monitor",
        keysCaption: "Cuando el Mac reproduce sonido por un monitor externo, F10, F11 y F12 cambian el volumen del propio monitor por DDC/CI. Requiere activar abajo el volumen del monitor.",
        monitorToggle: "Controlar el volumen de este monitor",
        monitorCaption: "Este monitor no informa su volumen, así que no se puede comprobar si lo admite. Actívalo, pulsa una tecla de volumen y escucha si cambia.",
        mute: "Silenciar")
    static let sk = MonitorVolumeStrings(
        title: "Hlasitosť",
        keysToggle: "Klávesy hlasitosti pre reproduktory monitora",
        keysCaption: "Keď Mac prehráva zvuk cez externý monitor, F10, F11 a F12 menia hlasitosť samotného monitora cez DDC/CI. Vyžaduje zapnutú hlasitosť monitora nižšie.",
        monitorToggle: "Ovládať hlasitosť tohto monitora",
        monitorCaption: "Tento monitor nehlási svoju hlasitosť, preto sa podpora nedá overiť. Zapnite ju, stlačte kláves hlasitosti a počúvajte, či sa zmení.",
        mute: "Stlmiť")
    static let de = MonitorVolumeStrings(
        title: "Lautstärke",
        keysToggle: "Lautstärketasten für die Lautsprecher des Monitors",
        keysCaption: "Gibt der Mac den Ton über einen externen Monitor aus, ändern F10, F11 und F12 die eigene Lautstärke des Monitors per DDC/CI. Dafür muss unten die Lautstärke des Monitors aktiviert sein.",
        monitorToggle: "Lautstärke dieses Monitors steuern",
        monitorCaption: "Dieser Monitor meldet seine Lautstärke nicht, daher lässt sich die Unterstützung nicht prüfen. Einschalten, eine Lautstärketaste drücken und auf eine Änderung hören.",
        mute: "Stummschalten")
    static let fr = MonitorVolumeStrings(
        title: "Volume",
        keysToggle: "Touches de volume pour les haut-parleurs du moniteur",
        keysCaption: "Quand le Mac joue le son par un moniteur externe, F10, F11 et F12 modifient le volume du moniteur lui-même via DDC/CI. Il faut activer ci-dessous le volume du moniteur.",
        monitorToggle: "Contrôler le volume de ce moniteur",
        monitorCaption: "Ce moniteur ne communique pas son volume, la prise en charge ne peut donc pas être vérifiée. Activez-le, appuyez sur une touche de volume et écoutez si le son change.",
        mute: "Muet")
    static let it = MonitorVolumeStrings(
        title: "Volume",
        keysToggle: "Tasti del volume per gli altoparlanti del monitor",
        keysCaption: "Quando il Mac riproduce l’audio da un monitor esterno, F10, F11 e F12 cambiano il volume del monitor stesso via DDC/CI. Richiede di attivare qui sotto il volume del monitor.",
        monitorToggle: "Controlla il volume di questo monitor",
        monitorCaption: "Questo monitor non comunica il proprio volume, quindi il supporto non si può verificare. Attivalo, premi un tasto del volume e ascolta se cambia.",
        mute: "Silenzia")
    static let ja = MonitorVolumeStrings(
        title: "音量",
        keysToggle: "モニターのスピーカー用の音量キー",
        keysCaption: "Macが外部モニターから音を出しているとき、F10・F11・F12でDDC/CI経由でモニター自身の音量を変えます。下でモニターの音量をオンにする必要があります。",
        monitorToggle: "このモニターの音量を操作",
        monitorCaption: "このモニターは音量を報告しないため、対応しているか確認できません。オンにして音量キーを押し、音が変わるか聞いてください。",
        mute: "ミュート")
    static let ko = MonitorVolumeStrings(
        title: "볼륨",
        keysToggle: "모니터 스피커용 볼륨 키",
        keysCaption: "Mac이 외부 모니터로 소리를 내보낼 때 F10, F11, F12가 DDC/CI로 모니터 자체의 볼륨을 바꿉니다. 아래에서 모니터 볼륨을 켜야 합니다.",
        monitorToggle: "이 모니터의 볼륨 제어",
        monitorCaption: "이 모니터는 볼륨을 알려 주지 않아 지원 여부를 확인할 수 없습니다. 켜고 볼륨 키를 눌러 소리가 바뀌는지 들어 보세요.",
        mute: "음소거")
    static let zhHans = MonitorVolumeStrings(
        title: "音量",
        keysToggle: "显示器扬声器的音量键",
        keysCaption: "当 Mac 通过外接显示器播放声音时，F10、F11 和 F12 会通过 DDC/CI 调节显示器自身的音量。需要先在下方开启该显示器的音量。",
        monitorToggle: "控制此显示器的音量",
        monitorCaption: "此显示器不会报告音量，因此无法确认是否支持。开启后按音量键，听听声音是否变化。",
        mute: "静音")
    static let zhTW = MonitorVolumeStrings(
        title: "音量",
        keysToggle: "顯示器喇叭的音量鍵",
        keysCaption: "當 Mac 透過外接顯示器播放聲音時，F10、F11 和 F12 會透過 DDC/CI 調整顯示器本身的音量。需要先在下方開啟該顯示器的音量。",
        monitorToggle: "控制此顯示器的音量",
        monitorCaption: "此顯示器不會回報音量，因此無法確認是否支援。開啟後按音量鍵，聽聽聲音是否改變。",
        mute: "靜音")
    static let zhHK = MonitorVolumeStrings(
        title: "音量",
        keysToggle: "顯示器喇叭的音量鍵",
        keysCaption: "當 Mac 透過外接顯示器播放聲音時，F10、F11 和 F12 會透過 DDC/CI 調整顯示器本身的音量。需要先在下方開啟該顯示器的音量。",
        monitorToggle: "控制此顯示器的音量",
        monitorCaption: "此顯示器不會回報音量，因此無法確認是否支援。開啟後按音量鍵，聽聽聲音是否改變。",
        mute: "靜音")
    static let uk = MonitorVolumeStrings(
        title: "Гучність",
        keysToggle: "Клавіші гучності для динаміків монітора",
        keysCaption: "Коли Mac відтворює звук через зовнішній монітор, F10, F11 і F12 змінюють гучність самого монітора через DDC/CI. Потрібно ввімкнути гучність монітора нижче.",
        monitorToggle: "Керувати гучністю цього монітора",
        monitorCaption: "Цей монітор не повідомляє свою гучність, тому підтримку не можна перевірити. Увімкніть, натисніть клавішу гучності й послухайте, чи змінюється звук.",
        mute: "Вимкнути звук")
}
