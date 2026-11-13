// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's production handling of the Command Bar's measured height runs
/// against plain doubles. No island is shown and nothing is resized.
enum NotchCommandBarHeightTests {
    final class Bar {
        var closings = 0
        func islandDidClose() { closings += 1 }
    }
    enum CommandBarService { static let shared = Bar() }

    class State {
        var showingCommandBar = true
        var commandBarHeight: CGFloat?
        var measuredCommandBarHeight: CGFloat?
        /// The bar's height each time the island was asked to fit it.
        var resizes: [CGFloat?] = []
        func refreshPresentation() { resizes.append(commandBarHeight) }
    }

    static func run(_ suite: TestSuite) {
        /// Lets the main queue run everything sent to it so far, however busy the runner.
        func nextTurn() {
            var reached = false
            DispatchQueue.main.async { reached = true }
            let deadline = Date(timeIntervalSinceNow: 2)
            while !reached && Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
            }
            suite.expect(reached, "the Command Bar height fixture drains the main queue")
        }
        let service = Service()
        // Measured while SwiftUI draws the rows: the field alone, then the rows.
        service.updateCommandBarHeight(50)
        service.updateCommandBarHeight(608.4)
        suite.expect(service.resizes.isEmpty && service.commandBarHeight == nil,
                     "the bar's measured height waits for the next turn of the main loop, not the pass that drew the rows")
        nextTurn()
        suite.expect(service.resizes == [609] && service.commandBarHeight == 609,
                     "the island fits the bar once, at the latest height measured in that pass")
        service.updateCommandBarHeight(608.9)
        nextTurn()
        suite.expect(service.resizes.count == 1, "a height the island already fits asks for no resize")
        service.updateCommandBarHeight(320)
        service.commandBarDidClose()
        nextTurn()
        suite.expect(service.resizes.count == 1 && service.commandBarHeight == nil
                         && service.measuredCommandBarHeight == nil && CommandBarService.shared.closings == 1,
                     "a height measured as the bar closes goes with it")
        service.showingCommandBar = false
        service.updateCommandBarHeight(400)
        nextTurn()
        suite.expect(service.resizes.count == 1 && service.measuredCommandBarHeight == nil,
                     "a bar the island no longer shows leaves no height behind")
    }
}
