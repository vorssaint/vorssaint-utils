// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct MenuBarIconStrings {
    let staticCategory: String
    let animatedCategory: String
    private let names: RunnerNames

    private typealias RunnerNames = (cat: String, dog: String, slime: String, drop: String,
                                     coffee: String, newtonCradle: String, engine: String, mochi: String)

    private init(_ staticCategory: String, _ animatedCategory: String, _ names: RunnerNames) {
        self.staticCategory = staticCategory
        self.animatedCategory = animatedCategory
        self.names = names
    }

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return .init("Static", "Animated", ("Cat", "Dog", "Slime", "Water drop", "Coffee", "Newton’s cradle", "Engine", "Mochi"))
        case .ptBR:
            return .init("Estáticos", "Animados", ("Gato", "Cachorro", "Slime", "Gota d’água", "Café", "Pêndulo de Newton", "Motor", "Mochi"))
        case .tr:
            return .init("Sabit", "Animasyonlu", ("Kedi", "Köpek", "Balçık", "Su damlası", "Kahve", "Newton beşiği", "Motor", "Moçi"))
        case .ru:
            return .init("Статичные", "Анимированные", ("Кот", "Собака", "Слизь", "Капля воды", "Кофе", "Маятник Ньютона", "Двигатель", "Моти"))
        case .es:
            return .init("Estáticos", "Animados", ("Gato", "Perro", "Slime", "Gota de agua", "Café", "Péndulo de Newton", "Motor", "Mochi"))
        case .sk:
            return .init("Statické", "Animované", ("Mačka", "Pes", "Sliz", "Kvapka vody", "Káva", "Newtonova kolíska", "Motor", "Moči"))
        case .de:
            return .init("Statisch", "Animiert", ("Katze", "Hund", "Schleim", "Wassertropfen", "Kaffee", "Kugelstoßpendel", "Motor", "Mochi"))
        case .fr:
            return .init("Statiques", "Animées", ("Chat", "Chien", "Slime", "Goutte d’eau", "Café", "Pendule de Newton", "Moteur", "Mochi"))
        case .it:
            return .init("Statiche", "Animate", ("Gatto", "Cane", "Slime", "Goccia d’acqua", "Caffè", "Pendolo di Newton", "Motore", "Mochi"))
        case .ja:
            return .init("静止", "アニメーション", ("猫", "犬", "スライム", "水滴", "コーヒー", "ニュートンのゆりかご", "エンジン", "もち"))
        case .ko:
            return .init("정적", "애니메이션", ("고양이", "강아지", "슬라임", "물방울", "커피", "뉴턴의 요람", "엔진", "모치"))
        case .uk:
            return .init("Статичні", "Анімовані", ("Кіт", "Собака", "Слиз", "Крапля води", "Кава", "Маятник Ньютона", "Двигун", "Мочі"))
        case .zhHans:
            return .init("静态", "动画", ("猫咪", "狗狗", "史莱姆", "水滴", "咖啡", "牛顿摆", "引擎", "麻薯"))
        case .zhTW, .zhHK:
            return .init("靜態", "動畫", ("貓咪", "狗狗", "史萊姆", "水滴", "咖啡", "牛頓擺", "引擎", "麻糬"))
        }
    }

    func title(for runner: MenuBarIconAnimation) -> String {
        switch runner {
        case .cat: return names.cat
        case .dog: return names.dog
        case .slime: return names.slime
        case .drop: return names.drop
        case .coffee: return names.coffee
        case .newtonCradle: return names.newtonCradle
        case .engine: return names.engine
        case .mochi: return names.mochi
        }
    }
}
