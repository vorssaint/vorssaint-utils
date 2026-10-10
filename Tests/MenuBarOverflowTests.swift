// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum MenuBarOverflowTests {
    static func run(_ suite: TestSuite) {
        suite.expect(MenuBarOverflowSupport.Layout.resolved("unknown") == .dropdown,
                     "invalid stored layout falls back to the dropdown")
        let right = CGRect(x: 800, y: 1000, width: 640, height: 32)
        let arrow = CGRect(x: 1300, y: 1000, width: 26, height: 32)
        suite.expect(MenuBarOverflowSupport.inlineFreeWidth(rightArea: right, arrowFrame: arrow) == 488,
            "inline expansion fills live space up to a margin beside the camera")
        suite.expect(MenuBarOverflowSupport.inlineFreeWidth(rightArea: right,
            arrowFrame: CGRect(x: 700, y: 1000, width: 26, height: 32)) == 0,
            "an arrow on the other side of the camera never expands across it")
        let all = MenuBarOverflowSupport.inlinePlan(itemCount: 6, freeWidth: 144)
        suite.expect(all.visibleCount == 6 && !all.hasMore && all.extraWidth == 144,
                     "all icons fit directly in the bar when space permits")
        let excess = MenuBarOverflowSupport.inlinePlan(itemCount: 20, freeWidth: 100)
        suite.expect(excess.visibleCount == 2 && excess.hasMore && excess.extraWidth == 80,
                     "excess icons reserve a paging slot while respecting available width")
        let crowded = MenuBarOverflowSupport.inlinePlan(itemCount: 20, freeWidth: 12)
        suite.expect(crowded.usesMenuOnly && crowded.extraWidth == 0,
                     "a completely crowded bar uses a native overflow menu without covering the camera")
        let empty = MenuBarOverflowSupport.inlinePlan(itemCount: 0, freeWidth: 200)
        suite.expect(empty.visibleCount == 0 && !empty.hasMore && empty.extraWidth == 0,
                     "empty drawers add no status bar space")
        let hundred = MenuBarOverflowSupport.inlinePlan(itemCount: 100, freeWidth: 96)
        suite.expect(hundred.visibleCount == 2 && hundred.hasMore && hundred.pageSize == 2,
                     "one hundred icons stay right of the camera with two icons and a readable paging control")
        var starts: [Int] = []
        var start = 0
        repeat {
            starts.append(start)
            start = MenuBarOverflowSupport.nextPageStart(current: start, pageSize: hundred.pageSize, count: 100)
        } while start != 0
        suite.expect(starts == Array(stride(from: 0, to: 100, by: 2)),
                     "paging reaches every icon among one hundred and wraps after the final partial page")
        suite.expect(MenuBarOverflowSupport.allowedBundles(running: ["own.app", "hidden.app", "com.apple.Focus-Settings.extension"],
            selection: ["hidden.app"], ownBundle: "own.app") == ["com.apple.Focus-Settings.extension", "own.app"],
            "unselected UI-service and extension providers stay allowed while selected apps hide")
        let allowed = MenuBarOverflowSupport.allowedSystemItems(selection: ["system:7", "example.app", "system:invalid"])
        suite.expect(allowed.count == 255 && !allowed.contains(NSNumber(value: 7))
                     && allowed.contains(NSNumber(value: 2)) && allowed.contains(NSNumber(value: 255)),
                     "only selected system IDs are hidden; clock and future controls stay visible")
        suite.expect(MenuBarOverflowSupport.allowedSystemItems(selection: []).count == 256,
                     "all system controls remain allowed by default")
        suite.expect(MenuBarOverflowSupport.stableOrder(previous: ["app", "system", "gone"],
                     current: ["system", "new", "app", "new"]) == ["app", "system", "new"],
                     "hiding or showing an icon preserves chooser rows, appends new icons and removes departed icons")
        suite.expect(MenuBarOverflowSupport.allowedBundles(running: ["own.app", "hidden.app", "visible.app"],
                     selection: ["own.app", "hidden.app", "system:7"], ownBundle: "own.app") == ["own.app", "visible.app"],
                     "native visibility always keeps the drawer owner available while hiding selected apps")
        suite.expect(MenuBarOverflowSupport.allowedSystemItems(selection: ["system:2", "system:8", "system:99"]).count == 256,
                     "stored keys cannot hide clock, Control Center or unknown system items")
        suite.expect(MenuBarOverflowSupport.stableOrder(previous: ["c", "a"],
                     current: ["a", "b", "c"]) == ["c", "a", "b"],
                     "saved user order takes precedence over discovery order after restart")
    }
}
