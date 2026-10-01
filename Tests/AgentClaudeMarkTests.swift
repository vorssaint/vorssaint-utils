// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AgentClaudeMarkTests {
    static func run(_ suite: TestSuite) {
        let path = AgentClaudeMark.path(AgentClaudeMark.data)
        suite.expect(path != nil, "Claude's mark reads as a path")
        if let bounds = path?.bounds {
            // The spark spans its whole canvas, with no stray point outside it.
            suite.expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 24 && bounds.maxY <= 24,
                         "Claude's mark stays inside its canvas")
            suite.expect(bounds.width > 23 && bounds.height > 23, "Claude's mark fills its canvas")
        }
        let image = AgentClaudeMark.image
        suite.expect(image?.isTemplate == true, "Claude's mark takes the agent's color")
        suite.expect(image?.size == CGSize(width: 24, height: 24), "Claude's mark keeps its canvas size")

        // Relative and absolute commands, implicit lines after a move, and
        // numbers that start with a sign or a second point.
        let square = AgentClaudeMark.path("m1 1 2 0v2H.5l.5-1 1 1Z")
        // A move, five lines, and a close, which AppKit follows with a move back.
        suite.expect(square?.elementCount == 8, "a path reads every command it is given")
        suite.expect(square?.bounds == CGRect(x: 0.5, y: 1, width: 2.5, height: 2),
                     "relative and absolute points land where they say")
        let curve = AgentClaudeMark.path("M0 0c1 0 2 1 2 2")
        suite.expect(curve?.bounds.maxX == 2 && curve?.bounds.maxY == 2, "a relative curve ends where it says")

        for broken in ["", "m1", "m1 1 z 2", "m1 1q1 1 2 2", "1 1", "m1 1l.x"] {
            suite.expect(AgentClaudeMark.path(broken) == nil, "malformed path data reads as nothing: \(broken)")
        }
    }
}
