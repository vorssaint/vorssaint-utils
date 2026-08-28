// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure contract checks for the selected-text translation feature.  The
/// standalone test harness passes its assertion function in so this file can
/// stay free of a second @main entry point.
func runSelectionTranslationTests(_ check: (Bool, String) -> Void) {
    check(SelectionTranslationLanguage.allCases.count == 12,
          "selection translation exposes the complete language set")
    check(SelectionTranslationLanguage.simplifiedChinese.rawValue == "zh-Hans",
          "language persistence uses a stable simplified-Chinese code")
    check(SelectionTranslationLanguage.simplifiedChinese.displayName == "简体中文",
          "simplified Chinese has the expected display name")

    let secure = try? SelectionTranslationProviderConfiguration(
        baseURL: URL(string: "https://api.example.com/v1")!,
        model: " gpt-test ",
        apiKey: " secret "
    )
    check(secure?.model == "gpt-test" && secure?.apiKey == "secret",
          "provider configuration trims credentials")
    check(secure?.chatCompletionsURL.absoluteString == "https://api.example.com/v1/chat/completions",
          "provider configuration appends chat completions path")
    check((try? SelectionTranslationProviderConfiguration(
        baseURL: URL(string: "http://api.example.com/v1")!,
        model: "model",
        apiKey: "key")) == nil,
          "provider configuration rejects non-loopback HTTP")
    check((try? SelectionTranslationProviderConfiguration(
        baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
        model: "model",
        apiKey: "key")) != nil,
          "provider configuration allows loopback HTTP")

    check((try? SelectionTranslationPromptTemplates(
        systemPrompt: "translate",
        userPrompt: "{{text}}")) != nil,
          "prompt templates require the source placeholder")
    check((try? SelectionTranslationPromptTemplates(
        systemPrompt: "translate",
        userPrompt: "no source")) == nil,
          "prompt templates reject a missing source placeholder")

    let estimated = SelectionTranslationTokenEstimator.estimate(
        inputText: "你好",
        outputText: "hello"
    )
    check(estimated.inputTokens == 2 && estimated.outputTokens == 2 && estimated.isEstimated,
          "token estimator counts CJK scalars and marks estimates")
}
