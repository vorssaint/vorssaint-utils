// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import AppKit
import Carbon.HIToolbox

/// Test-only seam required by `TransientPaste`; the standalone harness does
/// not compile the full clipboard-history service.
final class ClipboardHistoryService {
    static let shared = ClipboardHistoryService()

    func ignoreNextChange(upTo _: Int) {}
}

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
    check(SelectionTranslationLanguage.matching("English") == .english
          && SelectionTranslationLanguage.matching("简体中文") == .simplifiedChinese,
          "language matching accepts persisted display names")
    check(SelectionTranslationLanguage.sourceOptions.contains(.automatic)
          && !SelectionTranslationLanguage.targetOptions.contains(.automatic),
          "automatic detection is available only for the source language")
    let swapped = SelectionTranslationLanguageSelection(source: .english, target: .simplifiedChinese).swapped()
    check(swapped.source == .simplifiedChinese && swapped.target == .english,
          "language exchange swaps source and target")
    let automaticSwap = SelectionTranslationLanguageSelection(source: .automatic, target: .simplifiedChinese).swapped()
    check(automaticSwap.source == .simplifiedChinese && automaticSwap.target == .english,
          "language exchange gives automatic source a concrete source language")

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

    let originalLanguage = L10n.shared.language
    L10n.shared.language = .enUS
    let englishURLMessage = SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL.errorDescription ?? ""
    let englishModelMessage = SelectionTranslationProviderConfiguration.ValidationError.emptyModel.errorDescription ?? ""
    let englishAPIKeyMessage = SelectionTranslationProviderConfiguration.ValidationError.emptyAPIKey.errorDescription ?? ""
    let englishKeychainMessage = SelectionTranslationKeychain.Error.writeFailed(-1).errorDescription ?? ""
    check(englishURLMessage == "Base URL must use HTTPS, or HTTP on the local loopback address.",
          "provider validation errors use the active English localization")
    check(englishModelMessage == "Enter a model name.",
          "empty model errors use the active English localization")
    check(englishAPIKeyMessage == "Enter an API key in Selection Translation settings.",
          "empty API key errors use the active English localization")
    check(englishKeychainMessage == "The API key could not be saved. Check Keychain access and try again.",
          "keychain errors use the active English localization")
    L10n.shared.language = .zhHans
    let chineseURLMessage = SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL.errorDescription ?? ""
    let chineseKeychainMessage = SelectionTranslationKeychain.Error.writeFailed(-1).errorDescription ?? ""
    check(chineseURLMessage == "服务地址必须是 HTTPS，或本机回环地址。",
          "provider validation errors use the active Simplified Chinese localization")
    check(chineseKeychainMessage == "无法保存 API 密钥，请检查钥匙串权限后重试。",
          "keychain errors use the active Simplified Chinese localization")
    L10n.shared.language = .ptBR
    let fallbackURLMessage = SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL.errorDescription ?? ""
    check(!fallbackURLMessage.contains("服务地址"),
          "unsupported languages do not receive hard-coded Chinese errors")
    L10n.shared.language = originalLanguage

    check((try? SelectionTranslationPromptTemplates(
        systemPrompt: "translate",
        userPrompt: "{{text}}")) != nil,
          "prompt templates require the source placeholder")
    check((try? SelectionTranslationPromptTemplates(
        systemPrompt: "translate",
        userPrompt: "no source")) == nil,
          "prompt templates reject a missing source placeholder")

    let qwenMessages = SelectionTranslationMessageBuilder.messages(
        model: "qwen-mt-flash",
        source: "Hello source",
        systemPrompt: "SYSTEM_SENTINEL",
        userPrompt: "USER_SENTINEL"
    )
    check(qwenMessages.count == 1
          && qwenMessages.first?["role"] == "user"
          && qwenMessages.first?["content"] == "Hello source",
          "Qwen MT messages contain only the source text")
    let qwenBody = SelectionTranslationRequestBodyBuilder.body(
        model: "qwen-mt-flash",
        messages: qwenMessages,
        sourceLanguage: .automatic,
        targetLanguage: .simplifiedChinese,
        stream: true
    )
    let qwenOptions = qwenBody["translation_options"] as? [String: String]
    check(qwenOptions?["source_lang"] == "auto"
          && qwenOptions?["target_lang"] == "Chinese",
          "Qwen MT requests include the required translation language options")

    let genericMessages = SelectionTranslationMessageBuilder.messages(
        model: "gpt-4o-mini",
        source: "Hello source",
        systemPrompt: "SYSTEM_RENDERED",
        userPrompt: "USER_RENDERED"
    )
    check(genericMessages.count == 2
          && genericMessages[0]["role"] == "system"
          && genericMessages[0]["content"] == "SYSTEM_RENDERED"
          && genericMessages[1]["role"] == "user"
          && genericMessages[1]["content"] == "USER_RENDERED",
          "generic chat models receive separate system and user messages")
    let genericBody = SelectionTranslationRequestBodyBuilder.body(
        model: "gpt-4o-mini",
        messages: genericMessages,
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese,
        stream: true
    )
    check(genericBody["translation_options"] == nil,
          "generic chat models do not receive Qwen translation options")
    let renderedPrompt = try! SelectionTranslationPromptTemplates(
        systemPrompt: "from={{from}} to={{to}}",
        userPrompt: "text={{text}} from={{from}} to={{to}}"
    )
    let renderedGenericMessages = SelectionTranslationMessageBuilder.messages(
        model: "gpt-4o-mini",
        source: "Hello source",
        systemPrompt: renderedPrompt.renderSystemPrompt(sourceLanguage: "English", targetLanguage: "简体中文"),
        userPrompt: renderedPrompt.renderUserPrompt(source: "Hello source", sourceLanguage: "English", targetLanguage: "简体中文")
    )
    check(renderedGenericMessages[0]["content"] == "from=English to=简体中文"
          && renderedGenericMessages[1]["content"] == "text=Hello source from=English to=简体中文",
          "generic model prompts replace source, target, and text placeholders")

    let estimated = SelectionTranslationTokenEstimator.estimate(
        inputText: "你好",
        outputText: "hello"
    )
    check(estimated.inputTokens == 2 && estimated.outputTokens == 2 && estimated.isEstimated,
          "token estimator counts CJK scalars and marks estimates")

    let board = NSPasteboard(name: NSPasteboard.Name("Vorssaint.SelectionTranslationTests"))
    board.clearContents()
    let item = NSPasteboardItem()
    item.setString("selected", forType: .string)
    item.setData(Data([0x01, 0x02]), forType: NSPasteboard.PasteboardType("com.example.binary"))
    board.writeObjects([item])
    let snapshot = TransientPaste.snapshot(of: board)
    check(snapshot?.first?.data(forType: NSPasteboard.PasteboardType.string) == Data("selected".utf8)
          && snapshot?.first?.data(forType: NSPasteboard.PasteboardType("com.example.binary")) == Data([0x01, 0x02]),
          "pasteboard snapshots preserve every advertised flavor")
    check(SelectionTranslationPasteboardSupport.copyKeyCode == CGKeyCode(kVK_ANSI_C),
          "selection fallback copies with Command-C")
    check(SelectionTranslationPasteboardSupport.shouldRestore(originalChangeCount: 40,
                                                               copyChangeCount: 41,
                                                               currentChangeCount: 41),
          "selection fallback restores only its own pasteboard change")
    check(!SelectionTranslationPasteboardSupport.shouldRestore(originalChangeCount: 40,
                                                                copyChangeCount: 41,
                                                                currentChangeCount: 42),
          "selection fallback leaves a newer user copy untouched")
    check(SelectionTranslationConstants.quickToolHotkeyID == 21,
          "selection translation uses the reserved quick-tool hotkey id")
    let draft = SelectionTranslationDraft(source: "hello",
                                          languages: .init(source: .english, target: .simplifiedChinese))
    check(SelectionTranslationWorkflow.shouldSubmit(draft: draft),
          "a non-empty manual draft can be submitted")
    check(SelectionTranslationWorkflow.retryDraft(current: .init(source: "edited", languages: .init()),
                                                   committed: draft) == draft,
          "retry uses the last committed draft")

    let timingStart = Date(timeIntervalSince1970: 100)
    let runningTiming = SelectionTranslationTiming.running(at: timingStart)
    check(runningTiming.isRunning && runningTiming.startedAt == timingStart && runningTiming.elapsed == 0,
          "translation timing starts with a running zero elapsed state")
    let stoppedTiming = runningTiming.stopped(at: Date(timeIntervalSince1970: 102.4))
    check(!stoppedTiming.isRunning && abs(stoppedTiming.elapsed - 2.4) < 0.000_001,
          "translation timing freezes elapsed time when stopped")
    check(stoppedTiming.stopped(at: Date(timeIntervalSince1970: 999)) == stoppedTiming,
          "stopping an already stopped timer does not change its elapsed time")

    check(SelectionTranslationPanelSizing.defaultWidth == 500
          && SelectionTranslationPanelSizing.minimumWidth == 500
          && SelectionTranslationPanelSizing.maximumWidth == 760,
          "translation panel defaults to the shelf width while retaining a resizable range")

    let settingsSuite = "com.vorssaint.tests.selectionTranslationSettings"
    let isolatedDefaults = UserDefaults(suiteName: settingsSuite)!
    isolatedDefaults.removePersistentDomain(forName: settingsSuite)
    isolatedDefaults.register(defaults: Defaults.registeredDefaults)
    let defaultSettings = SelectionTranslationSettingsStore.snapshot(defaults: isolatedDefaults,
                                                                       apiKey: "test-key")
    check(defaultSettings.baseURL == SelectionTranslationSettingsStore.defaultBaseURL
          && defaultSettings.model == SelectionTranslationSettingsStore.defaultModel
          && defaultSettings.providerName == SelectionTranslationSettingsStore.defaultProviderName
          && defaultSettings.languages.target == SelectionTranslationSettingsStore.defaultTargetLanguage
          && defaultSettings.apiKey == "test-key",
          "settings snapshot reads the registered Vorssaint defaults")
    isolatedDefaults.set("https://example.com/v1", forKey: DefaultsKey.selectionTranslationBaseURL)
    isolatedDefaults.set("custom-model", forKey: DefaultsKey.selectionTranslationModel)
    let savedSettings = SelectionTranslationSettingsStore.snapshot(defaults: isolatedDefaults,
                                                                     apiKey: "test-key")
    check(savedSettings.baseURL == "https://example.com/v1" && savedSettings.model == "custom-model",
          "settings snapshot reads saved Vorssaint values")
    isolatedDefaults.removePersistentDomain(forName: settingsSuite)
}
