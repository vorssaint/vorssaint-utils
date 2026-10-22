// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import Foundation
import NaturalLanguage
import Speech

struct SpeechLanguageSuggestion: Equatable {
    let detectedLanguageIdentifier: String
    let languageCode: String
    let localeIdentifier: String
    let confidence: Double

    var languageName: String {
        Locale.current.localizedString(forIdentifier: detectedLanguageIdentifier)
            ?? Locale.current.localizedString(forLanguageCode: languageCode)
            ?? detectedLanguageIdentifier
    }

    var localeName: String {
        Locale.current.localizedString(forIdentifier: localeIdentifier) ?? languageName
    }
}

enum SpeechLocaleSupport {
    static let supportedLocales = SFSpeechRecognizer.supportedLocales()
        .sorted { $0.identifier < $1.identifier }

    static func closestSupportedLocale(to identifier: String) -> Locale? {
        let normalizedIdentifier = normalized(identifier)
        if let exact = supportedLocales.first(where: { normalized($0.identifier) == normalizedIdentifier }) {
            return exact
        }

        let locale = Locale(identifier: identifier)
        guard let languageCode = locale.language.languageCode?.identifier else { return nil }
        return closestSupportedLocale(
            for: Locale.Language(identifier: languageCode),
            preferredRegion: locale.region ?? Locale.current.region
        )
    }

    static func closestSupportedLocale(
        for language: Locale.Language,
        preferredRegion: Locale.Region? = Locale.current.region
    ) -> Locale? {
        guard let languageCode = language.languageCode?.identifier else { return nil }
        let candidates = supportedLocales.filter {
            $0.language.languageCode?.identifier == languageCode
        }
        guard !candidates.isEmpty else { return nil }

        let target = Locale.Language(identifier: language.maximalIdentifier)
        return candidates.sorted { lhs, rhs in
            let lhsScore = score(lhs, target: target, preferredRegion: preferredRegion)
            let rhsScore = score(rhs, target: target, preferredRegion: preferredRegion)
            if lhsScore == rhsScore {
                return lhs.identifier < rhs.identifier
            }
            return lhsScore > rhsScore
        }.first
    }

    static func matches(language: Locale.Language, localeIdentifier: String) -> Bool {
        let selected = Locale.Language(identifier: localeIdentifier)
        guard language.languageCode?.identifier == selected.languageCode?.identifier else {
            return false
        }

        let detectedScript = Locale.Language(identifier: language.maximalIdentifier).script?.identifier
        let selectedScript = Locale.Language(identifier: selected.maximalIdentifier).script?.identifier
        return detectedScript == nil || selectedScript == nil || detectedScript == selectedScript
    }

    private static func score(
        _ locale: Locale,
        target: Locale.Language,
        preferredRegion: Locale.Region?
    ) -> Int {
        let candidate = Locale.Language(identifier: locale.language.maximalIdentifier)
        var result = 0

        if candidate.script?.identifier == target.script?.identifier {
            result += 200
        }
        if let preferredRegion,
           locale.region?.identifier == preferredRegion.identifier {
            result += 100
        }
        if candidate.region?.identifier == target.region?.identifier {
            result += 50
        }
        return result
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

enum SpeechLanguageDetector {
    static func suggestion(
        for text: String,
        currentLocaleIdentifier: String
    ) -> SpeechLanguageSuggestion? {
        let scrubbed = text.replacingOccurrences(
            of: "\\[[^\\]]*\\]",
            with: " ",
            options: .regularExpression
        )
        let sample = String(scrubbed.prefix(6_000))
        guard sample.lazy.filter(\.isLetter).prefix(20).count == 20 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominantLanguage = recognizer.dominantLanguage,
              dominantLanguage != .undetermined,
              let confidence = recognizer.languageHypotheses(withMaximum: 3)[dominantLanguage],
              confidence >= 0.75 else {
            return nil
        }

        let detectedLanguage = Locale.Language(identifier: dominantLanguage.rawValue)
        guard !SpeechLocaleSupport.matches(
            language: detectedLanguage,
            localeIdentifier: currentLocaleIdentifier
        ),
        let languageCode = detectedLanguage.languageCode?.identifier,
        let locale = SpeechLocaleSupport.closestSupportedLocale(for: detectedLanguage) else {
            return nil
        }

        return SpeechLanguageSuggestion(
            detectedLanguageIdentifier: dominantLanguage.rawValue,
            languageCode: languageCode,
            localeIdentifier: locale.identifier,
            confidence: confidence
        )
    }
}
