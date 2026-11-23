// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The keys an island answer types into Claude Code's terminal prompt, and the
/// hook's note of which terminal that is.
enum AgentTerminalKeysTests {
    static func run(_ suite: TestSuite) {
        suite.expect(AgentTerminalKeys.permission(allow: true) == [.enter]
                        && AgentTerminalKeys.permission(allow: false) == [.escape],
                     "Allow takes the prompt's first choice; Deny is Escape")
        suite.expect(AgentTerminalKeys.answers([0]) == [.enter, .enter]
                        && AgentTerminalKeys.answers([2]) == [.down, .down, .enter, .enter],
                     "a single answer moves down to its option and confirms")
        suite.expect(AgentTerminalKeys.answers([1, 0]) == [.down, .enter, .enter, .enter],
                     "several questions are answered in turn, then sent")
        suite.expect(AgentTerminalKeys.answers([]) == nil && AgentTerminalKeys.answers([-1]) == nil,
                     "nothing is typed for an answer that is not an option")
        suite.expect(AgentTerminalKey.down.bytes == "\u{1B}[B" && AgentTerminalKey.enter.bytes == "\r"
                        && AgentTerminalKey.enter.keyCode == 36 && AgentTerminalKey.escape.keyCode == 53,
                     "the keys are the ones a terminal and the keyboard send")

        let message = "tty:/dev/ttys003\n{\"hook_event_name\":\"PermissionRequest\"}\n"
        let split = AgentTerminalKeys.split(message)
        suite.expect(split.tty == "/dev/ttys003" && split.payload.hasPrefix("{\"hook_event_name\""),
                     "the hook's first line names the terminal; the event follows")
        suite.expect(AgentTerminalKeys.split("tty:\n{}").tty == nil
                        && AgentTerminalKeys.split("tty:/etc/passwd\n{}").tty == nil
                        && AgentTerminalKeys.split("{}").payload == "{}",
                     "no terminal, anything that is not one, or an older hook's bare event, types nowhere")
    }
}
