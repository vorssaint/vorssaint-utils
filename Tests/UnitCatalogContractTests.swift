// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The calculator's unit lexicon and the side tables that describe how units
/// combine. `CommandBarUnitCatalog.all` is a hand-written list, so nothing in
/// the compiler notices a typo in a partner id, a square whose scale is not
/// the base squared, or a symbol that the parser cannot read back. These
/// contracts pin the four promises the catalog makes:
///
/// - one identity per unit: unique ids, symbols and names, each name parsing
///   back to the unit that declares it;
/// - every side table names units that exist;
/// - the partner tables agree dimensionally and numerically with the base
///   units (area = length², volume = length³, root = the inverse);
/// - every unit's reuse symbol is a spelling the parser reads back to it.
enum UnitCatalogContractTests {
    static func run(_ suite: TestSuite) {
        let units = CommandBarUnitCatalog.all
        suite.expect(units.count > 100, "the unit lexicon is not empty (\(units.count) units)")

        // MARK: Identity

        let ids = units.map(\.id)
        suite.expect(Set(ids).count == ids.count,
                     "unit ids are unique: "
                        + "\(duplicates(ids).joined(separator: ", "))")

        let symbols = units.map(\.symbol)
        suite.expect(Set(symbols).count == symbols.count,
                     "unit symbols are unique: "
                        + "\(duplicates(symbols).joined(separator: ", "))")

        for unit in units {
            suite.expect(CommandBarUnitCatalog.unit(byID: unit.id) == unit,
                         "\(unit.id) resolves through its id")
            suite.expect(!unit.reuseSymbol.isEmpty,
                         "\(unit.id) has a spelling the parser can reuse")
            let symbol = unit.reuseSymbol
            suite.expect(CommandBarUnitCatalog.unit(
                named: CommandBarSearch.normalized(symbol), exact: symbol) == unit,
                         "\(unit.id): reuse symbol \"\(symbol)\" parses back to the unit")
            for name in unit.names {
                suite.expect(CommandBarUnitCatalog.unit(
                    named: CommandBarSearch.normalized(name)) == unit,
                             "\(unit.id): name \"\(name)\" parses back to the unit")
            }
            for name in unit.exactNames {
                suite.expect(CommandBarUnitCatalog.unit(
                    named: CommandBarSearch.normalized(name), exact: name) == unit,
                             "\(unit.id): exact name \"\(name)\" parses back to the unit")
            }
        }

        // MARK: Mixed and split pairs

        for (id, pair) in CommandBarUnitCatalog.mixedPairs {
            guard let larger = CommandBarUnitCatalog.unit(byID: id) else {
                suite.expect(false, "mixed pair key \(id) names a unit")
                continue
            }
            suite.expect(CommandBarUnitCatalog.unit(byID: pair.remainder.id) == pair.remainder,
                         "mixed pair \(id) keeps a real remainder unit")
            suite.expect(larger.dimensions == pair.remainder.dimensions,
                         "mixed pair \(id)/\(pair.remainder.id) measures one dimension")
            suite.expect(close(pair.ratio, larger.scale / pair.remainder.scale),
                         "mixed pair \(id)/\(pair.remainder.id) ratio matches the scales")
        }

        for pair in CommandBarUnitCatalog.splitPairs {
            let parts = pair.split(separator: "|").map(String.init)
            guard parts.count == 2,
                  let larger = CommandBarUnitCatalog.unit(byID: parts[0]),
                  let smaller = CommandBarUnitCatalog.unit(byID: parts[1]) else {
                suite.expect(false, "split pair \(pair) names two units")
                continue
            }
            suite.expect(larger.dimensions == smaller.dimensions,
                         "split pair \(pair) measures one dimension")
            suite.expect(larger.scale > smaller.scale,
                         "split pair \(pair) puts the larger unit first")
        }

        // MARK: Squared, cubed and rooted partners

        for (id, square) in CommandBarUnitCatalog.squaredPartners {
            guard let base = CommandBarUnitCatalog.unit(byID: id) else {
                suite.expect(false, "squared partner key \(id) names a unit")
                continue
            }
            suite.expect(CommandBarUnitCatalog.unit(byID: square.id) == square,
                         "squared partner of \(id) is the catalog's \(square.id)")
            suite.expect(square.dimensions == base.dimensions.scaled(by: 2),
                         "\(square.id) is the area of \(id)")
            suite.expect(square.offset == 0 && close(square.scale, base.scale * base.scale),
                         "\(square.id) scale is \(id) squared")
            suite.expect(CommandBarUnitCatalog.rootedPartners[square.id] == base,
                         "root of \(square.id) returns to \(id)")
        }

        for (id, cube) in CommandBarUnitCatalog.cubedPartners {
            guard let base = CommandBarUnitCatalog.unit(byID: id) else {
                suite.expect(false, "cubed partner key \(id) names a unit")
                continue
            }
            suite.expect(CommandBarUnitCatalog.unit(byID: cube.id) == cube,
                         "cubed partner of \(id) is the catalog's \(cube.id)")
            suite.expect(cube.dimensions == base.dimensions.scaled(by: 3),
                         "\(cube.id) is the volume of \(id)")
            suite.expect(cube.offset == 0 && close(cube.scale, base.scale * base.scale * base.scale),
                         "\(cube.id) scale is \(id) cubed")
            suite.expect(CommandBarUnitCatalog.rootedPartners[cube.id] == base,
                         "root of \(cube.id) returns to \(id)")
        }

        let derivedUnits = Set(CommandBarUnitCatalog.squaredPartners.values.map(\.id))
            .union(CommandBarUnitCatalog.cubedPartners.values.map(\.id))
        suite.expect(Set(CommandBarUnitCatalog.rootedPartners.keys) == derivedUnits,
                     "the rooted table is exactly the inverse of the squared and cubed tables")

        for (id, base) in CommandBarUnitCatalog.rootedPartners {
            guard let derived = CommandBarUnitCatalog.unit(byID: id) else {
                suite.expect(false, "rooted partner key \(id) names a unit")
                continue
            }
            let degrees = [2, 3].filter { derived.dimensions == base.dimensions.scaled(by: $0) }
            suite.expect(degrees.count == 1,
                         "\(id) is a square or cube of \(base.id), not both or neither")
            if let degree = degrees.first {
                suite.expect(close(base.scale, pow(derived.scale, 1 / Double(degree))),
                             "root of \(id) scale returns to \(base.id)")
            }
        }

        // MARK: Derived symbols

        // `derivedSymbols` is not read anywhere in the app today (kept for a
        // pending decision), so this only keeps its keys honest: every part of
        // a key is a real unit id.
        for (key, symbol) in CommandBarUnitCatalog.derivedSymbols {
            suite.expect(!symbol.isEmpty, "derived symbol for \(key) is not empty")
            for part in key.split(separator: "|").map(String.init) {
                suite.expect(CommandBarUnitCatalog.unit(byID: part) != nil,
                             "derived symbol key \(key) names the unit \(part)")
            }
        }
    }

    private static func duplicates(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var repeated = Set<String>()
        for value in values where !seen.insert(value).inserted { repeated.insert(value) }
        return repeated.sorted()
    }

    private static func close(_ actual: Double, _ expected: Double) -> Bool {
        guard actual.isFinite, expected.isFinite else { return false }
        return abs(actual - expected) <= max(abs(actual), abs(expected), 1e-12) * 1e-9
    }
}
