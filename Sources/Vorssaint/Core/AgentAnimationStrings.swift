// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The AI section's words for the working agents' mark: the menu and the
/// name of each dot animation.
struct AgentAnimationStrings {
    let animationTitle: String
    let classic: String
    let bloom: String
    let snake: String
    let sweep: String
    let gears: String
    let equalizer: String
    let rain: String
    let twinkle: String

    /// A thinking animation's name in the settings menu.
    func name(_ id: String) -> String {
        switch id {
        case "bloom": return bloom
        case "snake": return snake
        case "sweep": return sweep
        case "gears": return gears
        case "equalizer": return equalizer
        case "rain": return rain
        case "twinkle": return twinkle
        default: return classic
        }
    }
}

extension FeatureStrings {
    static func agentAnimations(_ language: AppLanguage) -> AgentAnimationStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhHK: return .zhHK
        case .zhTW: return .zhTW
        }
    }
}

private extension AgentAnimationStrings {
    static let enUS = AgentAnimationStrings(
        animationTitle: "Thinking animation",
        classic: "Classic",
        bloom: "Bloom",
        snake: "Snake",
        sweep: "Sweep",
        gears: "Gears",
        equalizer: "Equalizer",
        rain: "Rain",
        twinkle: "Twinkle"
    )

    static let ptBR = AgentAnimationStrings(
        animationTitle: "Animação de trabalho",
        classic: "Clássica",
        bloom: "Florescer",
        snake: "Cobra",
        sweep: "Varredura",
        gears: "Engrenagens",
        equalizer: "Equalizador",
        rain: "Chuva",
        twinkle: "Cintilar"
    )

    static let tr = AgentAnimationStrings(
        animationTitle: "Çalışma animasyonu",
        classic: "Klasik",
        bloom: "Çiçek",
        snake: "Yılan",
        sweep: "Tarama",
        gears: "Dişliler",
        equalizer: "Ekolayzer",
        rain: "Yağmur",
        twinkle: "Pırıltı"
    )

    static let ru = AgentAnimationStrings(
        animationTitle: "Анимация работы",
        classic: "Классическая",
        bloom: "Цветение",
        snake: "Змейка",
        sweep: "Развёртка",
        gears: "Шестерни",
        equalizer: "Эквалайзер",
        rain: "Дождь",
        twinkle: "Мерцание"
    )

    static let es = AgentAnimationStrings(
        animationTitle: "Animación de trabajo",
        classic: "Clásica",
        bloom: "Floración",
        snake: "Serpiente",
        sweep: "Barrido",
        gears: "Engranajes",
        equalizer: "Ecualizador",
        rain: "Lluvia",
        twinkle: "Destellos"
    )

    static let sk = AgentAnimationStrings(
        animationTitle: "Animácia práce",
        classic: "Klasická",
        bloom: "Kvet",
        snake: "Had",
        sweep: "Zametanie",
        gears: "Ozubené kolesá",
        equalizer: "Ekvalizér",
        rain: "Dážď",
        twinkle: "Trblietanie"
    )

    static let de = AgentAnimationStrings(
        animationTitle: "Arbeitsanimation",
        classic: "Klassisch",
        bloom: "Blüte",
        snake: "Schlange",
        sweep: "Wischen",
        gears: "Zahnräder",
        equalizer: "Equalizer",
        rain: "Regen",
        twinkle: "Funkeln"
    )

    static let fr = AgentAnimationStrings(
        animationTitle: "Animation de travail",
        classic: "Classique",
        bloom: "Éclosion",
        snake: "Serpent",
        sweep: "Balayage",
        gears: "Engrenages",
        equalizer: "Égaliseur",
        rain: "Pluie",
        twinkle: "Scintillement"
    )

    static let it = AgentAnimationStrings(
        animationTitle: "Animazione di lavoro",
        classic: "Classica",
        bloom: "Fioritura",
        snake: "Serpente",
        sweep: "Scansione",
        gears: "Ingranaggi",
        equalizer: "Equalizzatore",
        rain: "Pioggia",
        twinkle: "Scintillio"
    )

    static let ja = AgentAnimationStrings(
        animationTitle: "作業中のアニメーション",
        classic: "クラシック",
        bloom: "ブルーム",
        snake: "スネーク",
        sweep: "スイープ",
        gears: "ギア",
        equalizer: "イコライザ",
        rain: "レイン",
        twinkle: "トゥインクル"
    )

    static let ko = AgentAnimationStrings(
        animationTitle: "작업 애니메이션",
        classic: "클래식",
        bloom: "블룸",
        snake: "스네이크",
        sweep: "스윕",
        gears: "기어",
        equalizer: "이퀄라이저",
        rain: "레인",
        twinkle: "트윙클"
    )

    static let uk = AgentAnimationStrings(
        animationTitle: "Анімація роботи",
        classic: "Класична",
        bloom: "Цвітіння",
        snake: "Змійка",
        sweep: "Розгортка",
        gears: "Шестерні",
        equalizer: "Еквалайзер",
        rain: "Дощ",
        twinkle: "Мерехтіння"
    )

    static let zhHans = AgentAnimationStrings(
        animationTitle: "工作动画",
        classic: "经典",
        bloom: "绽放",
        snake: "蛇行",
        sweep: "扫描",
        gears: "齿轮",
        equalizer: "均衡器",
        rain: "雨滴",
        twinkle: "闪烁"
    )

    static let zhHK = AgentAnimationStrings(
        animationTitle: "工作動畫",
        classic: "經典",
        bloom: "綻放",
        snake: "蛇行",
        sweep: "掃描",
        gears: "齒輪",
        equalizer: "等化器",
        rain: "雨點",
        twinkle: "閃爍"
    )

    static let zhTW = AgentAnimationStrings(
        animationTitle: "工作動畫",
        classic: "經典",
        bloom: "綻放",
        snake: "蛇行",
        sweep: "掃描",
        gears: "齒輪",
        equalizer: "等化器",
        rain: "雨滴",
        twinkle: "閃爍"
    )
}
