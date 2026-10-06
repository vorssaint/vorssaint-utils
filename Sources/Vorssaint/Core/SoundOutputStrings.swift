// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Copy for the output-routing hotkeys. Its own table rather than the base
/// catalog because the mute shortcut's name is read by the shortcut recorder,
/// which has no business knowing about the mixer's own vocabulary, and because
/// the next output feature should find these here instead of growing the base
/// catalog a field at a time.
struct SoundOutputStrings {
    let systemMute: String
    let systemMuteCaption: String

    static func localized(_ language: AppLanguage) -> SoundOutputStrings {
        switch language {
        case .enUS: return .init(systemMute: "Mute system sound", systemMuteCaption: "Cuts the default output, so every app goes quiet until the next press.")
        case .ptBR: return .init(systemMute: "Silenciar o som do sistema", systemMuteCaption: "Corta a saída padrão, então todos os apps ficam mudos até o próximo atalho.")
        case .tr: return .init(systemMute: "Sistem sesini kapat", systemMuteCaption: "Standart çıkışı sessize alır, böylece her uygulama bir sonraki kısayola kadar sessiz kalır.")
        case .ru: return .init(systemMute: "Отключить системный звук", systemMuteCaption: "Заглушает стандартный выход, поэтому все приложения молчат до следующего нажатия.")
        case .es: return .init(systemMute: "Silenciar el sonido del sistema", systemMuteCaption: "Corta la salida predeterminada, así que todas las apps quedan en silencio hasta la siguiente pulsación.")
        case .sk: return .init(systemMute: "Stlmiť systémový zvuk", systemMuteCaption: "Stlmí predvolený výstup, takže všetky aplikácie budú ticho, kým znova nestlačíte skratku.")
        case .de: return .init(systemMute: "Systemton stummschalten", systemMuteCaption: "Schaltet den Standardausgang stumm, sodass alle Apps bis zum nächsten Mal still bleiben.")
        case .fr: return .init(systemMute: "Couper le son du système", systemMuteCaption: "Coupe la sortie par défaut, donc toutes les applications se taisent jusqu’à l’appui suivant.")
        case .it: return .init(systemMute: "Disattiva l’audio di sistema", systemMuteCaption: "Muta l’uscita predefinita, così tutte le app restano silenziose fino alla pressione successiva.")
        case .ja: return .init(systemMute: "システムサウンドをミュート", systemMuteCaption: "標準出力をミュートにして、次のショートカットまですべてのアプリの音が止まります。")
        case .ko: return .init(systemMute: "시스템 사운드 음소거", systemMuteCaption: "기본 출력 소리를 음소거하여 다음 단축키를 누르기 전까지 모든 앱이 조용해집니다.")
        case .uk: return .init(systemMute: "Вимкнути системний звук", systemMuteCaption: "Заглушує стандартний вихід, тож усі застосунки мовчать до наступного натискання.")
        case .zhHans: return .init(systemMute: "静音系统声音", systemMuteCaption: "静音默认输出，所有 App 都会安静下来，直到再次按下快捷键。")
        case .zhTW: return .init(systemMute: "靜音系統聲音", systemMuteCaption: "靜音預設輸出，所有 App 都會安靜下來，直到再次按下快速鍵。")
        case .zhHK: return .init(systemMute: "靜音系統聲音", systemMuteCaption: "靜音預設輸出，所有 App 都會安靜下來，直到再次按下快速鍵。")
        }
    }
}
