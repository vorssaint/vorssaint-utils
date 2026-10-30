// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The select-all control's three states and what a click does. The service's
/// bulk setter runs against the real body through the generated flow fixture
/// (UninstallerFlowTests); this covers the state rules themselves.
enum UninstallerBulkSelectionTests {
    static func run(_ suite: TestSuite) {
        typealias Bulk = UninstallerSupport.BulkSelection

        suite.expect(Bulk(included: 0, total: 0) == .none,
                     "an empty results list shows an empty box")
        suite.expect(Bulk(included: 0, total: 3) == .none,
                     "no chosen rows show an empty box")
        suite.expect(Bulk(included: 1, total: 3) == .some,
                     "some chosen rows show a mixed box")
        suite.expect(Bulk(included: 3, total: 3) == .all,
                     "every chosen row shows a checked box")
        suite.expect(Bulk(included: 2, total: 2) == .all,
                     "a full list of two reads the same as a full list of many")

        suite.expect(Bulk.none.nextInclude && Bulk.some.nextInclude,
                     "clicking an empty or mixed box selects everything")
        suite.expect(!Bulk.all.nextInclude,
                     "clicking a full box clears the selection")
    }
}
