// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SelectionTranslationFeatureStrings {
    let title: String
    let hubDescription: String
    let pageCaption: String
    let shortcut: String
    let providerSection: String
    let providerName: String
    let baseURL: String
    let apiKey: String
    let model: String
    let targetLanguage: String
    let sourceLanguage: String
    let promptsSection: String
    let systemPrompt: String
    let userPrompt: String
    let availableVariables: String
    let charactersFormat: String
    let savePrompts: String
    let restoreDefaults: String
    let sourceVariable: String
    let targetVariable: String
    let textVariable: String
    let save: String
    let testConnection: String
    let permissionRequired: String
    let noSelection: String
    let translating: String
    let retry: String
    let sourceText: String
    let translationText: String
    let permissions: String
    let accessibilityGranted: String
    let openAccessibilitySettings: String
    let savedStatus: String
    let connectedStatus: String
    let tokensFormat: String
    let elapsedFormat: String
    let estimatedSuffix: String
    let invalidResponse: String
    let requestFailed: String
    let unsupportedURL: String
    let emptyModel: String
    let emptyAPIKey: String
    let keychainWriteFailed: String
    let emptyTranslation: String
    let cancelled: String
    let httpStatusFormat: String
    let sourcePlaceholder: String
    let swapLanguages: String
    let translate: String
    let interrupt: String
    let pin: String
    let unpin: String
    let shortcutConflict: String
    let openTranslationSettings: String

    static let enUS = SelectionTranslationFeatureStrings(
        title: "Selection Translation", hubDescription: "Translate selected text with your OpenAI-compatible provider",
        pageCaption: "Select text anywhere, then press the shortcut to translate it.", shortcut: "Shortcut",
        providerSection: "Provider", providerName: "Name", baseURL: "Base URL", apiKey: "API key", model: "Model",
        targetLanguage: "Target language", sourceLanguage: "Source language", promptsSection: "Prompts",
        systemPrompt: "System prompt", userPrompt: "User prompt (use {{text}})", availableVariables: "Available variables",
        charactersFormat: "%d characters", savePrompts: "Save prompts", restoreDefaults: "Restore defaults",
        sourceVariable: "{{from}} source language", targetVariable: "{{to}} target language", textVariable: "{{text}} selected text",
        save: "Save",
        testConnection: "Test connection", permissionRequired: "Accessibility permission is required to read selected text.",
        noSelection: "No text was selected.", translating: "Translating…", retry: "Retry",
        sourceText: "Source text", translationText: "Translation", permissions: "Permissions",
        accessibilityGranted: "Accessibility granted", openAccessibilitySettings: "Open Accessibility Settings",
        savedStatus: "Saved", connectedStatus: "Connected", tokensFormat: "Tokens: %d in · %d out · %d total",
        elapsedFormat: "Elapsed: %.1fs", estimatedSuffix: "estimated",
        invalidResponse: "The translation service returned an invalid response.", requestFailed: "Request failed",
        unsupportedURL: "Base URL must use HTTPS, or HTTP on the local loopback address.",
        emptyModel: "Enter a model name.",
        emptyAPIKey: "Enter an API key in Selection Translation settings.",
        keychainWriteFailed: "The API key could not be saved. Check Keychain access and try again.",
        emptyTranslation: "The translation service returned no text.", cancelled: "Translation cancelled.",
        httpStatusFormat: "Translation service returned HTTP %d: %@",
        sourcePlaceholder: "Type or paste text to translate", swapLanguages: "Swap languages",
        translate: "Translate", interrupt: "Interrupt", pin: "Pin panel", unpin: "Unpin panel",
        shortcutConflict: "The shortcut is unavailable. Choose another shortcut in settings.",
        openTranslationSettings: "Open Selection Translation settings")
    static let zhHans = SelectionTranslationFeatureStrings(
        title: "划词翻译", hubDescription: "使用兼容 OpenAI 的服务翻译选中的文本",
        pageCaption: "在任意应用中选中文本，然后按下快捷键即可翻译。", shortcut: "快捷键",
        providerSection: "服务提供商", providerName: "名称", baseURL: "服务地址", apiKey: "API 密钥", model: "模型",
        targetLanguage: "目标语言", sourceLanguage: "源语言", promptsSection: "提示词",
        systemPrompt: "系统提示词", userPrompt: "用户提示词（使用 {{text}}）", availableVariables: "可用变量",
        charactersFormat: "%d 字符", savePrompts: "保存提示词", restoreDefaults: "恢复默认提示词",
        sourceVariable: "{{from}} 源语言", targetVariable: "{{to}} 目标语言", textVariable: "{{text}} 选中的原文",
        save: "保存",
        testConnection: "测试连接", permissionRequired: "读取选中文本需要辅助功能权限。",
        noSelection: "未选中文本。", translating: "翻译中…", retry: "重试",
        sourceText: "原文", translationText: "译文", permissions: "权限",
        accessibilityGranted: "已获得辅助功能权限", openAccessibilitySettings: "打开辅助功能设置",
        savedStatus: "已保存", connectedStatus: "已连接", tokensFormat: "Token：输入 %d · 输出 %d · 总计 %d",
        elapsedFormat: "耗时：%.1f 秒", estimatedSuffix: "估算",
        invalidResponse: "翻译服务返回了无效响应。", requestFailed: "请求失败",
        unsupportedURL: "服务地址必须是 HTTPS，或本机回环地址。",
        emptyModel: "请填写模型名称。",
        emptyAPIKey: "请在划词翻译设置中填写 API 密钥。",
        keychainWriteFailed: "无法保存 API 密钥，请检查钥匙串权限后重试。",
        emptyTranslation: "翻译服务没有返回文本。",
        cancelled: "翻译已取消。", httpStatusFormat: "翻译服务返回 HTTP %d：%@",
        sourcePlaceholder: "输入或粘贴需要翻译的内容", swapLanguages: "交换语言",
        translate: "翻译", interrupt: "中断", pin: "固定面板", unpin: "取消固定",
        shortcutConflict: "快捷键不可用，请在设置中更换一个快捷键。", openTranslationSettings: "打开划词翻译设置")
    static let zhTW = zhHans
    static let zhHK = zhHans
}
