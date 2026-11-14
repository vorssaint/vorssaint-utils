// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentDotAnimationContract {
    static func run(_ suite: TestSuite) {
        let all = AgentDotAnimation.all
        suite.expect(AgentDotAnimation.thinking.map(\.id) == ["bloom", "snake", "sweep", "gears", "equalizer", "rain", "twinkle"]
                        && Set(all.map(\.id)).count == all.count,
                     "the thinking animations keep the designer's order and every id is unique")
        for dots in all {
            let shaped = dots.frames.allSatisfy { frame in
                frame.count == dots.rows && frame.allSatisfy { $0.count == dots.columns && $0.allSatisfy("012".contains) }
            }
            suite.expect(shaped && dots.rows > 0 && dots.columns > 0 && dots.frames.indices.contains(dots.still)
                            && (6...12).contains(dots.fps),
                         "\(dots.id) has same-sized frames of 0, 1 and 2, a still frame and a calm frame rate")
        }
        let bloom = AgentDotAnimation.bloom
        suite.expect(bloom.frameIndex(elapsed: 0) == 0 && bloom.frameIndex(elapsed: 0.35) == 3
                        && bloom.frameIndex(elapsed: bloom.duration + 0.15) == 1,
                     "a looping animation steps at its own pace and starts over")
        let done = AgentDotAnimation.done
        suite.expect(!done.loops && done.frameIndex(elapsed: 60) == done.frames.count - 1,
                     "the done tick plays once and holds its last frame")
        suite.expect(AgentDotAnimation.question.level(frame: 0, column: 2, row: 4) == 1
                        && AgentDotAnimation.question.level(frame: 12, column: 2, row: 4) == AgentDotAnimation.dimLevel
                        && AgentDotAnimation.question.level(frame: 0, column: 0, row: 0) == 0
                        && AgentDotAnimation.question.level(frame: 99, column: 9, row: 9) == 0,
                     "dots are on, dim or off, and anything outside the grid is off")
        suite.expect(AgentDotAnimation.forNotice(symbol: AgentDotAnimation.done.noticeSymbol) == done
                        && AgentDotAnimation.forNotice(symbol: "sparkle") == nil
                        && AgentDotAnimation.forNotice(symbol: "agentdots.unknown") == nil,
                     "a notice finds its dots by symbol, and an ordinary symbol stays a symbol")
        let defaults = UserDefaults(suiteName: "com.vorssaint.tests.agent-dots")!
        defaults.removePersistentDomain(forName: "com.vorssaint.tests.agent-dots")
        suite.expect(AgentDotAnimation.chosenThinking(in: defaults) == nil, "the classic mark stays the default")
        defaults.set("rain", forKey: DefaultsKey.notchAgentsAnimation)
        suite.expect(AgentDotAnimation.chosenThinking(in: defaults)?.id == "rain", "a chosen animation replaces it")
        defaults.set("question", forKey: DefaultsKey.notchAgentsAnimation)
        suite.expect(AgentDotAnimation.chosenThinking(in: defaults) == nil,
                     "only a thinking animation can be chosen for working")
        let strings = FeatureStrings.agentAnimations(.enUS)
        suite.expect(AgentDotAnimation.thinking.allSatisfy { strings.name($0.id) != strings.classic }
                        && strings.name(AgentDotAnimation.classicID) == strings.classic,
                     "every thinking animation has a name of its own in the settings")
    }
}

