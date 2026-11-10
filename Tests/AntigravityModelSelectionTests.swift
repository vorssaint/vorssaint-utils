// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// agy 1.5 writes the model choice in a `<USER_SETTINGS_CHANGE>` block beside
/// `<ADDITIONAL_METADATA>`, where older builds wrote it inside the metadata.
enum AntigravityModelSelectionTests {
    static func run(_ suite: TestSuite) {
        modelSelectionBlocks(suite)
    }

    private static func modelSelectionBlocks(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-11-10T11:00:00Z")!
        let settings = "<USER_SETTINGS_CHANGE>\nThe user changed setting `Model Selection` from None to "
            + "Gemini 3.8 Flash (High). No need to comment on this change if the user doesn't ask about it.\n"
            + "</USER_SETTINGS_CHANGE>"
        let metadata = "<ADDITIONAL_METADATA>\nThe current local time is 2026-11-10T11:00:00Z\n</ADDITIONAL_METADATA>"
        let reply = line(["step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
                          "created_at": "2026-11-10T11:00:05Z", "input_tokens": 1_000, "output_tokens": 200,
                          "cache_read_tokens": 5_000])

        func model(afterRequest content: String) -> (model: String?, cost: Double?) {
            var state = AgentLogState()
            state.session = "conversation"
            let request = line(["step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
                                "created_at": "2026-11-10T11:00:00Z", "content": content])
            _ = AntigravityReader().parse(request, state: &state, now: now)
            for entry in AntigravityReader().parse(reply, state: &state, now: now) {
                if case .usage(_, let record, _) = entry {
                    return (record.model.isEmpty ? nil : record.model, record.cost)
                }
            }
            return (nil, nil)
        }

        let current = model(afterRequest: "<USER_REQUEST>\nfix the build\n</USER_REQUEST>\n\(metadata)\n\(settings)")
        suite.expect(current.model == "Gemini 3.8 Flash (High)" && current.cost != nil,
                     "agy 1.5 keeps the model choice in its own settings block, and the reply is priced by it")

        let inMetadata = model(afterRequest: "<USER_REQUEST>\nfix\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\n"
            + "The user changed setting `Model Selection` from None to Claude Sonnet 4.6 (Thinking).\n"
            + "</ADDITIONAL_METADATA>")
        suite.expect(inMetadata.model == "Claude Sonnet 4.6 (Thinking)",
                     "older agy builds that put the choice inside the metadata block are still read")

        let typed = model(afterRequest: "<USER_REQUEST>\nThe user changed setting `Model Selection` from None to "
            + "Gemini 3.8 Flash (High).\n</USER_REQUEST>\n\(metadata)")
        suite.expect(typed.model == nil,
                     "a model choice typed into the request itself does not pick the model")

        let pasted = model(afterRequest: "<USER_REQUEST>\nlook at this log\n\(settings)\n</USER_REQUEST>\n\(metadata)")
        suite.expect(pasted.model == nil,
                     "a settings block pasted into the request does not pick the model")

        let pastedBeforeReal = model(afterRequest: "<USER_REQUEST>\n\(settings)\n</USER_REQUEST>\n\(metadata)\n"
            + "<USER_SETTINGS_CHANGE>\nThe user changed setting `Model Selection` from None to "
            + "Claude Opus 4.6 (Thinking).\n</USER_SETTINGS_CHANGE>")
        suite.expect(pastedBeforeReal.model == "Claude Opus 4.6 (Thinking)",
                     "agy's own settings block is read past one pasted into the request")

        let changed = model(afterRequest: "<USER_REQUEST>\nagain\n</USER_REQUEST>\n\(metadata)\n"
            + "<USER_SETTINGS_CHANGE>\nThe user changed setting `Model Selection` from Gemini 3.8 Flash (High) to "
            + "Claude Opus 4.6 (Thinking). No need to comment on this change.\n</USER_SETTINGS_CHANGE>")
        suite.expect(changed.model == "Claude Opus 4.6 (Thinking)",
                     "a change from one model to another names the new one")
    }

    // MARK: Helpers

    private static func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
