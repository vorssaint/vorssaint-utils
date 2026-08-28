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
    let save: String
    let testConnection: String
    let permissionRequired: String
    let noSelection: String
    let translating: String
    let copy: String
    let retry: String
    let close: String

    static let enUS = SelectionTranslationFeatureStrings(
        title: "Selection Translation", hubDescription: "Translate selected text with your OpenAI-compatible provider",
        pageCaption: "Select text anywhere, then press the shortcut to translate it.", shortcut: "Shortcut",
        providerSection: "Provider", providerName: "Name", baseURL: "Base URL", apiKey: "API key", model: "Model",
        targetLanguage: "Target language", sourceLanguage: "Source language", promptsSection: "Prompts",
        systemPrompt: "System prompt", userPrompt: "User prompt (use {{text}})", save: "Save",
        testConnection: "Test connection", permissionRequired: "Accessibility permission is required to read selected text.",
        noSelection: "No text was selected.", translating: "Translating…", copy: "Copy", retry: "Retry", close: "Close")
    static let zhHans = SelectionTranslationFeatureStrings(
        title: "划词翻译", hubDescription: "使用兼容 OpenAI 的服务翻译选中的文本",
        pageCaption: "在任意应用中选中文本，然后按下快捷键即可翻译。", shortcut: "快捷键",
        providerSection: "服务提供商", providerName: "名称", baseURL: "服务地址", apiKey: "API 密钥", model: "模型",
        targetLanguage: "目标语言", sourceLanguage: "源语言", promptsSection: "提示词",
        systemPrompt: "系统提示词", userPrompt: "用户提示词（使用 {{text}}）", save: "保存",
        testConnection: "测试连接", permissionRequired: "读取选中文本需要辅助功能权限。",
        noSelection: "未选中文本。", translating: "翻译中…", copy: "复制", retry: "重试", close: "关闭")
    static let zhTW = zhHans
    static let zhHK = zhHans
}
