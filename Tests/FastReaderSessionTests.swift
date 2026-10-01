// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

private extension FastReaderSession {
    func expectRemaining(_ expected: TimeInterval, _ suite: TestSuite, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        suite.expectClose(remainingSeconds, expected, label, tol: 0.0005, file: file, line: line)
    }
}

enum FastReaderSessionTests {
    static func run(_ suite: TestSuite) {
        suite.run("fast reader session navigation") { navigation(suite) }
    }

    private static func navigation(_ suite: TestSuite) {
        let session = FastReaderSession()
        session.load("bir iki üç dört", options: .default)
        suite.expect(session.chunks.count == 4, "four words load as four chunks")
        suite.expect(session.index == 0, "a fresh load starts at the first chunk")
        suite.expect(session.isPlaying == false, "a fresh load does not play by itself")
        suite.expect(session.isFinished == false, "a fresh load is not finished")

        session.stepBackward()
        suite.expect(session.index == 0, "stepping back from the first chunk stays put")

        session.stepForward()
        session.stepForward()
        suite.expect(session.index == 2, "stepping forward twice lands on the third chunk")

        session.seek(to: 99)
        suite.expect(session.index == 3, "seeking past the end clamps to the last chunk")
        suite.expect(session.isFinished, "reaching the last chunk finishes the session")

        session.seek(to: -5)
        suite.expect(session.index == 0, "seeking before the start clamps to zero")
        suite.expect(session.isFinished == false, "seeking back from the end unfinishes it")

        session.setWordsPerMinute(700)
        suite.expect(session.wordsPerMinute == 700, "the speed follows what was set")
        suite.expect(session.index == 0, "changing the speed leaves the position alone")

        session.setWordsPerMinute(99_999)
        suite.expect(FastReaderEngine.wordsPerMinuteRange.contains(session.wordsPerMinute),
                     "an out-of-range speed clamps into the supported range")

        session.restart()
        suite.expect(session.index == 0 && !session.isFinished,
                     "restarting returns to the first chunk")

        let empty = FastReaderSession()
        empty.load("   ", options: .default)
        suite.expect(empty.chunks.isEmpty, "a selection with no words loads no chunks")
        suite.expect(empty.currentChunk == nil, "an empty session has no current chunk")
        suite.expectClose(empty.progress, 0, "an empty session reports no progress")
        empty.play()
        suite.expect(empty.isPlaying == false, "an empty session refuses to play")

        let timed = FastReaderSession()
        var slow = ReaderOptions.default
        slow.punctuationPause = false
        slow.longWordScaling = false
        slow.chunkSize = 1
        slow.wordsPerMinute = 300
        timed.load("bir iki uc dort", options: slow)
        // Four words at 300 a minute is a fifth of a second each.
        timed.expectRemaining(0.8, suite, "a fresh load counts the whole read")
        timed.stepForward()
        timed.expectRemaining(0.6, suite, "a step spends one chunk of it")
        timed.seek(to: 3)
        timed.expectRemaining(0.2, suite, "the last chunk still has itself left")

        // The speed divides out, so doubling it halves what is left without
        // the weights being rebuilt.
        timed.seek(to: 0)
        timed.setWordsPerMinute(600)
        timed.expectRemaining(0.4, suite, "twice the speed is half the time")

        let paused = FastReaderSession()
        var withPauses = slow
        withPauses.punctuationPause = true
        paused.load("bir iki.", options: withPauses)
        // The second word ends a sentence, so it holds twice as long.
        paused.expectRemaining(0.2 + 0.4, suite, "a sentence ending is counted")

        let nothing = FastReaderSession()
        nothing.load("   ", options: slow)
        nothing.expectRemaining(0, suite, "an empty session has nothing left")

        let single = FastReaderSession()
        single.load("tek", options: .default)
        suite.expect(single.chunks.count == 1, "one word loads one chunk")
        suite.expect(single.isFinished, "a single chunk is already at the end")
    }
}
