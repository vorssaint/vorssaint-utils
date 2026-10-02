// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The fields a viewing update needs. Unknown keys are ignored. A payload that
/// is not an object produces nothing, and the raw JSON is not kept.
struct CursorDecodedHook: Equatable {
    var hook: String
    var source: CursorSessionOrigin
    var remote: Bool
    var conversationID: String?
    var parentConversationID: String?
    var childConversationID: String?
    var generationID: String?
    var model: String?
    var cursorVersion: String?
    var roots: [String]
    var mode: String?
    var background: Bool?
    var prompt: String?
    var text: String?
    var command: String?
    var cwd: String?
    var sandbox: Bool?
    var output: String?
    var durationMS: Int?
    var thoughtDurationMS: Int?
    var toolName: String?
    var toolUseID: String?
    var path: String?
    var query: String?
    var server: String?
    var failureType: String?
    var interrupted: Bool
    var status: String?
    var loopCount: Int
    var reason: String?
    var sessionDurationMS: Int?
    var edits: [CursorDecodedEdit]
    var subagentType: String?
    var task: String?
    var summary: String?
    var modifiedFiles: [String]
    var contextPercent: Double?
    var contextTokens: Int?
    var contextWindow: Int?
    var tokens: CursorTokenCounts
    var truncated: Bool

    /// The chat this event belongs to. A subagent stays on its parent.
    var sessionID: String? {
        if hook == "subagentStart" || hook == "subagentStop" {
            return parentConversationID ?? conversationID
        }
        return conversationID
    }
}

struct CursorDecodedEdit: Equatable {
    var path: String?
    var oldText: String
    var newText: String
    var truncated: Bool
}

enum CursorHookDecoder {
    static func decode(_ message: CursorHookMessage) -> CursorDecodedHook? {
        guard let object = try? JSONSerialization.jsonObject(with: message.payload) as? [String: Any] else {
            return nil
        }
        let input = dictionary(object["tool_input"]) ?? dictionary(object["input"]) ?? [:]
        let shellDuration = message.hook == "afterShellExecution" ? int(object["duration"]) : nil
        let thoughtDuration = message.hook == "afterAgentThought" ? int(object["duration_ms"]) : nil
        let toolDuration = message.hook == "postToolUse" || message.hook == "postToolUseFailure"
            ? int(object["duration_ms"]) : nil
        return CursorDecodedHook(
            hook: message.hook,
            source: message.source == "app" ? .app : .terminal,
            remote: message.remote,
            conversationID: string(object["conversation_id"]),
            parentConversationID: string(object["parent_conversation_id"]),
            childConversationID: string(object["child_conversation_id"]),
            generationID: string(object["generation_id"]),
            model: string(object["model_id"]) ?? string(object["model"]),
            cursorVersion: string(object["cursor_version"]),
            roots: strings(object["workspace_roots"]),
            mode: string(object["composer_mode"]),
            background: bool(object["is_background_agent"]),
            prompt: string(object["prompt"]),
            text: string(object["text"]),
            command: string(object["command"]) ?? string(input["command"]),
            cwd: string(object["cwd"]),
            sandbox: bool(object["sandbox"]),
            output: message.hook == "afterShellExecution" ? string(object["output"]) : nil,
            durationMS: shellDuration ?? toolDuration,
            thoughtDurationMS: thoughtDuration,
            toolName: string(object["tool_name"]) ?? string(input["tool_name"]),
            toolUseID: string(object["tool_use_id"]),
            path: first(input, ["file_path", "path", "target_file", "file"]) ?? first(object, ["file_path", "path"]),
            query: first(input, ["pattern", "query", "glob", "glob_pattern", "url", "search_term"]),
            server: first(object, ["server", "server_name", "mcp_server"]) ?? first(input, ["server"]),
            failureType: string(object["failure_type"]),
            interrupted: bool(object["is_interrupt"]) ?? false,
            status: string(object["status"]),
            loopCount: int(object["loop_count"]) ?? 0,
            reason: string(object["reason"]),
            sessionDurationMS: message.hook == "sessionEnd" ? int(object["duration_ms"]) : nil,
            edits: edits(in: object),
            subagentType: string(object["subagent_type"]) ?? string(object["type"]),
            task: first(object, ["task", "description", "prompt", "name"]),
            summary: string(object["summary"]) ?? string(object["result"]),
            modifiedFiles: fileList(object["modified_files"] ?? object["files"]),
            contextPercent: double(object["context_usage_percent"]),
            contextTokens: int(object["context_tokens"]),
            contextWindow: int(object["context_window_size"]),
            tokens: CursorTokenCounts(
                input: int(object["input_tokens"]),
                output: int(object["output_tokens"]),
                cacheRead: int(object["cache_read_tokens"]),
                cacheWrite: int(object["cache_write_tokens"])
            ),
            truncated: bool(object["truncated"]) ?? false
        )
    }

    private static func edits(in object: [String: Any]) -> [CursorDecodedEdit] {
        let path = first(object, ["file_path", "path"])
        guard let items = object["edits"] as? [Any] else { return [] }
        return items.compactMap { item in
            guard let edit = item as? [String: Any] else { return nil }
            return CursorDecodedEdit(
                path: first(edit, ["file_path", "path"]) ?? path,
                oldText: string(edit["old_string"]) ?? string(edit["old"]) ?? "",
                newText: string(edit["new_string"]) ?? string(edit["new"]) ?? "",
                truncated: bool(edit["truncated"]) ?? false
            )
        }
    }

    private static func fileList(_ value: Any?) -> [String] {
        if let names = value as? [String] { return names }
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            if let name = item as? String { return name }
            guard let object = item as? [String: Any] else { return nil }
            return first(object, ["file_path", "path", "file"])
        }
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func first(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let text = string(object[key]), !text.isEmpty { return text }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func strings(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let value = value as? String, !value.isEmpty { return [value] }
        return []
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, bool(value) == nil else { return nil }
        return number.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, bool(value) == nil else { return nil }
        return number.doubleValue
    }
}
