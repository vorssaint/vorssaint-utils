// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchTourStrings {
    let preview: String
    let caption: String
}

extension FeatureStrings {
    static func notchTour(_ language: AppLanguage) -> NotchTourStrings {
        switch language {
        case .enUS: return NotchTourStrings(preview: "Preview for 3.4",
            caption: "Control music, timers, volume and brightness. Choose the floating shortcuts you use most.")
        case .ptBR: return NotchTourStrings(preview: "Prévia da 3.4",
            caption: "Controle música, temporizadores, volume e brilho. Escolha os atalhos flutuantes que você mais usa.")
        case .es: return NotchTourStrings(preview: "Vista previa de 3.4",
            caption: "Controla la música, los temporizadores, el volumen y el brillo. Elige los accesos flotantes que más usas.")
        case .sk: return NotchTourStrings(preview: "Ukážka verzie 3.4",
            caption: "Ovládajte hudbu, časovače, hlasitosť a jas. Vyberte plávajúce skratky, ktoré používate najčastejšie.")
        case .de: return NotchTourStrings(preview: "Vorschau auf 3.4",
            caption: "Steuere Musik, Timer, Lautstärke und Helligkeit. Wähle die schwebenden Kurzbefehle, die du am häufigsten nutzt.")
        case .fr: return NotchTourStrings(preview: "Aperçu de la version 3.4",
            caption: "Contrôlez la musique, les minuteurs, le volume et la luminosité. Choisissez les raccourcis flottants que vous utilisez le plus.")
        case .it: return NotchTourStrings(preview: "Anteprima della 3.4",
            caption: "Controlla musica, timer, volume e luminosità. Scegli le scorciatoie mobili che usi di più.")
        case .ru: return NotchTourStrings(preview: "Предпросмотр версии 3.4",
            caption: "Управляйте музыкой, таймерами, громкостью и яркостью. Выберите плавающие кнопки для частых действий.")
        case .tr: return NotchTourStrings(preview: "3.4 önizlemesi",
            caption: "Müziği, zamanlayıcıları, sesi ve parlaklığı kontrol edin. En çok kullandığınız yüzen kısayolları seçin.")
        case .ja: return NotchTourStrings(preview: "3.4のプレビュー",
            caption: "音楽、タイマー、音量、明るさを操作できます。よく使うフローティングショートカットを選べます。")
        case .ko: return NotchTourStrings(preview: "3.4 미리보기",
            caption: "음악, 타이머, 음량, 밝기를 조절하세요. 자주 쓰는 플로팅 단축키를 선택할 수 있습니다.")
        case .zhHans: return NotchTourStrings(preview: "3.4 预览",
            caption: "控制音乐、计时器、音量和亮度。选择常用的悬浮快捷按钮。")
        case .zhTW: return NotchTourStrings(preview: "3.4 預覽",
            caption: "控制音樂、計時器、音量和亮度。選擇常用的浮動快捷按鈕。")
        case .zhHK: return NotchTourStrings(preview: "3.4 預覽",
            caption: "控制音樂、計時器、音量和亮度。選擇常用的浮動快捷按鈕。")
        case .uk: return NotchTourStrings(preview: "Прев’ю версії 3.4",
            caption: "Керуйте музикою, таймерами, гучністю та яскравістю. Виберіть плаваючі кнопки для ваших найчастіших дій.")
        }
    }
}
