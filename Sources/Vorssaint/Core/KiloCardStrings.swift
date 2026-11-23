// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Kilo Code card's own labels: short, so a figure follows each.
struct KiloCardStrings {
    let tokens: String
    let input: String
    let output: String
    let cache: String
    let prompts: String
    let steps: String
    let activeNow: String
    /// "Used %@", where %@ is how long ago, as "3 min ago".
    let usedFormat: String

    func used(_ ago: String) -> String { String(format: usedFormat, ago) }

    static func localized(_ language: AppLanguage) -> KiloCardStrings {
        switch language {
        case .enUS: return .init(tokens: "tokens", input: "In", output: "Out", cache: "cache", prompts: "Prompts", steps: "Steps", activeNow: "Active now", usedFormat: "Used %@")
        case .ptBR: return .init(tokens: "tokens", input: "Entrada", output: "Saída", cache: "cache", prompts: "Prompts", steps: "Etapas", activeNow: "Ativo agora", usedFormat: "Usado %@")
        case .es: return .init(tokens: "tokens", input: "Entrada", output: "Salida", cache: "caché", prompts: "Prompts", steps: "Pasos", activeNow: "Activo ahora", usedFormat: "Usado %@")
        case .sk: return .init(tokens: "tokenov", input: "Vstup", output: "Výstup", cache: "cache", prompts: "Výzvy", steps: "Kroky", activeNow: "Aktívne teraz", usedFormat: "Použité %@")
        case .de: return .init(tokens: "Tokens", input: "Ein", output: "Aus", cache: "Cache", prompts: "Prompts", steps: "Schritte", activeNow: "Jetzt aktiv", usedFormat: "Genutzt %@")
        case .fr: return .init(tokens: "jetons", input: "Entrée", output: "Sortie", cache: "cache", prompts: "Requêtes", steps: "Étapes", activeNow: "Actif", usedFormat: "Utilisé %@")
        case .it: return .init(tokens: "token", input: "Input", output: "Output", cache: "cache", prompts: "Prompt", steps: "Passi", activeNow: "Attivo ora", usedFormat: "Usato %@")
        case .ru: return .init(tokens: "токенов", input: "Вход", output: "Выход", cache: "кэш", prompts: "Запросы", steps: "Шаги", activeNow: "Активен", usedFormat: "Использован %@")
        case .tr: return .init(tokens: "token", input: "Giriş", output: "Çıkış", cache: "önbellek", prompts: "İstemler", steps: "Adımlar", activeNow: "Şu an etkin", usedFormat: "Kullanıldı: %@")
        case .ja: return .init(tokens: "トークン", input: "入力", output: "出力", cache: "キャッシュ", prompts: "プロンプト", steps: "ステップ", activeNow: "使用中", usedFormat: "%@に使用")
        case .ko: return .init(tokens: "토큰", input: "입력", output: "출력", cache: "캐시", prompts: "프롬프트", steps: "단계", activeNow: "사용 중", usedFormat: "%@ 사용")
        case .zhHans: return .init(tokens: "令牌", input: "输入", output: "输出", cache: "缓存", prompts: "提示", steps: "步骤", activeNow: "正在使用", usedFormat: "%@使用")
        case .zhTW: return .init(tokens: "權杖", input: "輸入", output: "輸出", cache: "快取", prompts: "提示", steps: "步驟", activeNow: "使用中", usedFormat: "%@使用")
        case .zhHK: return .init(tokens: "權杖", input: "輸入", output: "輸出", cache: "快取", prompts: "提示", steps: "步驟", activeNow: "使用中", usedFormat: "%@使用")
        case .uk: return .init(tokens: "токенів", input: "Вхід", output: "Вихід", cache: "кеш", prompts: "Запити", steps: "Кроки", activeNow: "Активний", usedFormat: "Використано %@")
        }
    }
}
