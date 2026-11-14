// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The units the command bar calculator knows, and how they relate.
///
/// One unit is one name for one point on one dimension: a scale factor from
/// the SI base unit, an offset for the affine temperature scales, and the
/// names people actually type (symbols, spelled-out words, and the Portuguese
/// spellings the app already answered before the calculator grew an engine).
///
/// Dimensions are vectors of six base exponents, so derived quantities like
/// km/h (L·T⁻¹), kg/m³ (M·L⁻³) or kWh (M·L²·T⁻²) fall out of arithmetic
/// instead of being listed. Two quantities convert when their dimensions are
/// equal, or when one is the exact reciprocal of the other: pace (min/km) is
/// the reciprocal of speed (km/h) and fuel economy (km/L) the reciprocal of
/// fuel consumption (L/100km). Everything else is refused, because a launcher
/// that guesses at conversions turns sentences into wrong answers.
///
/// Temperature is its own dimension and adds an offset to the conversion, so
/// 20 °C is 68 °F and multiplying a temperature is never an answer.
enum CommandBarUnitCatalog {
    // MARK: - Dimensions

    /// Exponents over the base dimensions. Hashable so it keys lookups. Seven
    /// of them: the six mechanical ones plus electric current, so volts, ohms
    /// and farads compose the same way kilometers per hour does.
    struct Dimensions: Hashable, Equatable {
        var length = 0
        var mass = 0
        var time = 0
        var temperature = 0
        var data = 0
        var angle = 0
        var current = 0

        static let none = Dimensions()

        var isNone: Bool {
            length == 0 && mass == 0 && time == 0 && temperature == 0 && data == 0
                && angle == 0 && current == 0
        }

        var isNegated: Bool {
            length < 0 && mass < 0 && time < 0 && temperature < 0 && data < 0
                && angle < 0 && current < 0
        }

        static func * (left: Dimensions, right: Dimensions) -> Dimensions {
            Dimensions(length: left.length + right.length,
                       mass: left.mass + right.mass,
                       time: left.time + right.time,
                       temperature: left.temperature + right.temperature,
                       data: left.data + right.data,
                       angle: left.angle + right.angle,
                       current: left.current + right.current)
        }

        static func / (left: Dimensions, right: Dimensions) -> Dimensions {
            Dimensions(length: left.length - right.length,
                       mass: left.mass - right.mass,
                       time: left.time - right.time,
                       temperature: left.temperature - right.temperature,
                       data: left.data - right.data,
                       angle: left.angle - right.angle,
                       current: left.current - right.current)
        }

        func negated() -> Dimensions {
            Dimensions(length: -length, mass: -mass, time: -time,
                       temperature: -temperature, data: -data, angle: -angle,
                       current: -current)
        }

        func scaled(by factor: Int) -> Dimensions {
            Dimensions(length: length * factor, mass: mass * factor, time: time * factor,
                       temperature: temperature * factor, data: data * factor, angle: angle * factor,
                       current: current * factor)
        }

        /// True when every exponent is divisible by `n`, so an n-th root stays
        /// a whole-number exponent: sqrt(25m2) halves area to length.
        func allDivisible(by n: Int) -> Bool {
            length % n == 0 && mass % n == 0 && time % n == 0
                && temperature % n == 0 && data % n == 0 && angle % n == 0
                && current % n == 0
        }

        func dividedExponents(by n: Int) -> Dimensions {
            Dimensions(length: length / n, mass: mass / n, time: time / n,
                       temperature: temperature / n, data: data / n, angle: angle / n,
                       current: current / n)
        }
    }

    // MARK: - Units

    /// One unit. Identity is the `id`; the Double fields exist only to do
    /// arithmetic, so two instances of the same unit always compare equal.
    struct Unit: Hashable {
        /// The canonical id, also the ASCII symbol used to reuse an answer.
        let id: String
        let dimensions: Dimensions
        /// `value * scale + offset` is the SI base value (offset is nonzero
        /// only for the temperature scales).
        let scale: Double
        let offset: Double
        /// The Foundation unit used to write a localized answer, when the
        /// system has one. A missing one (mpg, L/100km) falls back to writing
        /// the symbol after the number.
        let foundation: Foundation.Dimension?
        /// The symbol reused in answers, always one the parser reads back.
        /// Foundation symbols like "oz t" and "NM" would not round-trip, so
        /// those units carry their own.
        let symbol: String
        /// Names matched after case/accent folding.
        let names: [String]
        /// Names that must match their exact case: MW is megawatts and mW is
        /// milliwatts, and folding both to "mw" would lose the difference.
        let exactNames: [String]

        init(_ id: String, _ dimensions: Dimensions, scale: Double, offset: Double = 0,
             foundation: Foundation.Dimension? = nil, symbol: String? = nil,
             names: [String], exactNames: [String] = []) {
            self.id = id
            self.dimensions = dimensions
            self.scale = scale
            self.offset = offset
            self.foundation = foundation
            self.symbol = symbol ?? foundation?.symbol ?? id
            self.names = names
            self.exactNames = exactNames
        }

        static func == (left: Unit, right: Unit) -> Bool { left.id == right.id }

        func hash(into hasher: inout Hasher) { hasher.combine(id) }

        /// The value of a quantity of this unit, given its SI base value.
        func displayValue(siValue: Double) -> Double { (siValue - offset) / scale }

        /// The SI base value of a quantity of this unit.
        func siValue(displayValue: Double) -> Double { displayValue * scale + offset }
    }

    // MARK: - Relationships

    /// Units people write side by side as one amount ("5ft 11in", "1hr 30min").
    /// The larger unit comes first and the remainder must stay under one of
    /// it; anything else is two numbers that never multiply, i.e. a search.
    static let mixedPairs: [String: (remainder: Unit, ratio: Double)] = [
        "ft": (unit(byID: "in")!, 12),
        "h": (unit(byID: "min")!, 60),
        "hr": (unit(byID: "min")!, 60),
        "min": (unit(byID: "s")!, 60),
        "lb": (unit(byID: "oz")!, 16),
        "kg": (unit(byID: "g")!, 1000),
        "wk": (unit(byID: "d")!, 7),
    ]

    /// Two units asked for together split the answer between them ("to feet
    /// and inches", "to lb oz"). Only the pairs that people actually say.
    static let splitPairs: Set<String> = [
        "ft|in", "lb|oz", "h|min", "hr|min", "yr|mo", "wk|d", "d|h",
    ]

    /// A squared base unit reads as the area unit when one exists, so 5m * 4m
    /// is "20 m²" written by the system's own formatter.
    static let squaredPartners: [String: Unit] = [
        "mm": unit(byID: "mm2")!, "cm": unit(byID: "cm2")!, "m": unit(byID: "m2")!,
        "km": unit(byID: "km2")!, "in": unit(byID: "sqin")!, "ft": unit(byID: "sqft")!,
        "yd": unit(byID: "sqyd")!, "mi": unit(byID: "sqmi")!,
    ]

    /// And a cubed one reads as the volume unit: 2m * 3m * 4m is 24 m³.
    static let cubedPartners: [String: Unit] = [
        "mm": unit(byID: "mm3")!, "cm": unit(byID: "cm3")!, "m": unit(byID: "m3")!,
        "in": unit(byID: "in3")!, "ft": unit(byID: "ft3")!, "yd": unit(byID: "yd3")!,
    ]

    /// The inverse of the square/cube maps above, so roots shrink back to the
    /// base unit: sqrt(25m2) is 5 m.
    static let rootedPartners: [String: Unit] = [
        "mm2": unit(byID: "mm")!, "cm2": unit(byID: "cm")!, "m2": unit(byID: "m")!,
        "km2": unit(byID: "km")!, "sqin": unit(byID: "in")!, "sqft": unit(byID: "ft")!,
        "sqyd": unit(byID: "yd")!, "sqmi": unit(byID: "mi")!,
        "mm3": unit(byID: "mm")!, "cm3": unit(byID: "cm")!, "m3": unit(byID: "m")!,
        "in3": unit(byID: "in")!, "ft3": unit(byID: "ft")!, "yd3": unit(byID: "yd")!,
    ]

    /// Ways a derived unit is written that plain symbol composition would
    /// not produce: "l/100km" carries its 100, "w|h" reads as Wh.
    /// The key is the unit ids sorted, joined with "|".
    static let derivedSymbols: [String: String] = [
        "km|l": "km/L", "l|km": "L/100km", "w|h": "Wh", "kw|h": "kWh",
    ]

    // MARK: - Lookup

    private static let byID: [String: Unit] = {
        var map: [String: Unit] = [:]
        for unit in all { map[unit.id] = unit }
        return map
    }()

    private static let byName: [String: Unit] = {
        var map: [String: Unit] = [:]
        for unit in all {
            for name in unit.names { map[name] = unit }
        }
        return map
    }()

    private static let byExactName: [String: Unit] = {
        var map: [String: Unit] = [:]
        for unit in all {
            for name in unit.exactNames { map[name] = unit }
        }
        return map
    }()

    static func unit(byID id: String) -> Unit? { byID[id] }

    /// A unit by a word as typed: exact case first (MW vs mW), then folded.
    /// Multi-word names arrive space-joined, already folded.
    static func unit(named folded: String, exact: String? = nil) -> Unit? {
        if let exact, let unit = byExactName[exact] { return unit }
        return byName[folded]
    }

    // MARK: - The lexicon

    /// Every unit, built once. Spelled-out names repeat the symbols and the
    /// Portuguese words the old conversion path already accepted; the
    /// British spellings sit beside the American ones.
    static let all: [Unit] = {
        var units: [Unit] = []
        func add(_ id: String, _ dimensions: Dimensions, scale: Double, offset: Double = 0,
                 foundation: Foundation.Dimension? = nil, symbol: String? = nil, _ names: [String],
                 exact: [String] = []) {
            units.append(Unit(id, dimensions, scale: scale, offset: offset,
                              foundation: foundation, symbol: symbol, names: names, exactNames: exact))
        }
        let l = Dimensions(length: 1), a = Dimensions(length: 2), v = Dimensions(length: 3)
        let m = Dimensions(mass: 1), t = Dimensions(time: 1), temp = Dimensions(temperature: 1)
        let d = Dimensions(data: 1), ang = Dimensions(angle: 1), i = Dimensions(current: 1)
        // Volt, ohm, farad, weber, siemens, henry and tesla derive from the
        // same power dimensions watts already carry.
        let voltDims = m * l * l / (t * t * t) / i
        let ohmDims = voltDims / i
        let faradDims = i * t * i * t * t * t / (m * l * l)
        let weberDims = voltDims * t
        let siemensDims = i * i * t * t * t / (m * l * l)
        let henryDims = weberDims / i
        let teslaDims = m / (t * t) / i

        // Length.
        add("mm", l, scale: 1e-3, foundation: UnitLength.millimeters,
            ["mm", "millimeter", "millimeters", "millimetre", "millimetres", "milimetro", "milimetros"])
        add("cm", l, scale: 1e-2, foundation: UnitLength.centimeters,
            ["cm", "centimeter", "centimeters", "centimetre", "centimetres", "centimetro", "centimetros"])
        add("m", l, scale: 1, foundation: UnitLength.meters,
            ["m", "meter", "meters", "metre", "metres", "metro", "metros"])
        add("km", l, scale: 1e3, foundation: UnitLength.kilometers,
            ["km", "kilometer", "kilometers", "kilometre", "kilometres", "quilometro", "quilometros"])
        add("in", l, scale: 0.0254, foundation: UnitLength.inches,
            ["in", "inch", "inches", "polegada", "polegadas", "\"", "″", "”"])
        add("ft", l, scale: 0.3048, foundation: UnitLength.feet,
            ["ft", "foot", "feet", "pe", "pes", "'", "′", "’"])
        add("yd", l, scale: 0.9144, foundation: UnitLength.yards,
            ["yd", "yard", "yards", "jarda", "jardas"])
        add("mi", l, scale: 1609.344, foundation: UnitLength.miles,
            ["mi", "mile", "miles", "milha", "milhas"])
        add("nmi", l, scale: 1852, foundation: UnitLength.nauticalMiles, symbol: "nmi",
            ["nmi", "nauticalmile", "nauticalmiles", "nautical mile", "nautical miles",
             "milha nautica", "milhas nauticas"])
        add("fathom", l, scale: 1.8288, foundation: UnitLength.fathoms,
            ["fathom", "fathoms"])
        add("furlong", l, scale: 201.168, foundation: UnitLength.furlongs,
            ["furlong", "furlongs"])
        add("ly", l, scale: 9.46073047258e15, foundation: UnitLength.lightyears,
            ["ly", "lightyear", "lightyears", "light year", "light years"])
        add("au", l, scale: 1.495978707e11, foundation: UnitLength.astronomicalUnits,
            ["au", "astronomicalunit", "astronomicalunits", "astronomical unit", "astronomical units"])
        add("pc", l, scale: 3.08567758149137e16, foundation: UnitLength.parsecs,
            ["pc", "parsec", "parsecs"])
        add("um", l, scale: 1e-6, foundation: UnitLength.micrometers,
            ["um", "µm", "μm", "micrometer", "micrometers", "micrometre", "micrometres"])

        // Mass.
        add("mg", m, scale: 1e-6, foundation: UnitMass.milligrams,
            ["mg", "milligram", "milligrams"])
        add("g", m, scale: 1e-3, foundation: UnitMass.grams,
            ["g", "gram", "grams", "grama", "gramas"])
        add("kg", m, scale: 1, foundation: UnitMass.kilograms,
            ["kg", "kilogram", "kilograms", "quilo", "quilos"])
        add("t", m, scale: 1e3, foundation: UnitMass.metricTons,
            ["t", "ton", "tons", "tonne", "tonnes", "tonelada", "toneladas"])
        add("oz", m, scale: 0.028349523125, foundation: UnitMass.ounces,
            ["oz", "ounce", "ounces", "onca", "oncas"])
        add("lb", m, scale: 0.45359237, foundation: UnitMass.pounds,
            ["lb", "lbs", "pound", "pounds", "libra", "libras"])
        add("st", m, scale: 6.35029318, foundation: UnitMass.stones,
            ["st", "stone", "stones"])
        add("ct", m, scale: 2e-4, foundation: UnitMass.carats,
            ["ct", "carat", "carats", "quilate", "quilates"])
        add("ozt", m, scale: 0.0311034768, foundation: UnitMass.ouncesTroy, symbol: "ozt",
            ["ozt", "troyounce", "troyounces", "troy ounce", "troy ounces"])

        // Temperature: affine scales, never increments.
        add("c", temp, scale: 1, offset: 273.15, foundation: UnitTemperature.celsius,
            ["c", "celsius", "°c", "centigrade"], exact: ["C"])
        add("f", temp, scale: 5.0 / 9.0, offset: 255.3722222222222, foundation: UnitTemperature.fahrenheit,
            ["f", "fahrenheit", "°f"], exact: ["F"])
        add("k", temp, scale: 1, offset: 0, foundation: UnitTemperature.kelvin,
            ["k", "kelvin"], exact: ["K"])

        // Duration. Foundation stops at hours, so the larger spans are fixed
        // multipliers of a second, like the old conversion path had them:
        // a year stays 365 days because the existing answers pin it.
        add("ms", t, scale: 1e-3, foundation: UnitDuration.milliseconds,
            ["ms", "millisecond", "milliseconds"])
        add("s", t, scale: 1, foundation: UnitDuration.seconds,
            ["s", "sec", "secs", "second", "seconds", "segundo", "segundos"])
        add("min", t, scale: 60, foundation: UnitDuration.minutes,
            ["min", "mins", "minute", "minutes", "minuto", "minutos"])
        add("h", t, scale: 3600, foundation: UnitDuration.hours,
            ["h", "hr", "hrs", "hour", "hours", "hora", "horas"])
        add("d", t, scale: 86_400, foundation: CommandBarUnitCatalog.customDays,
            ["d", "day", "days", "dia", "dias"])
        add("wk", t, scale: 604_800, foundation: CommandBarUnitCatalog.customWeeks,
            ["wk", "wks", "week", "weeks", "semana", "semanas"])
        add("mo", t, scale: 2_628_000, foundation: CommandBarUnitCatalog.customMonths,
            ["mo", "mos", "month", "months", "mes", "meses"])
        add("yr", t, scale: 31_536_000, foundation: CommandBarUnitCatalog.customYears,
            ["yr", "yrs", "year", "years", "ano", "anos"])

        // Volume.
        add("ml", v, scale: 1e-6, foundation: UnitVolume.milliliters,
            ["ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililitro", "mililitros"])
        add("cl", v, scale: 1e-5, foundation: UnitVolume.centiliters,
            ["cl", "centiliter", "centiliters", "centilitre", "centilitres"])
        add("dl", v, scale: 1e-4, foundation: UnitVolume.deciliters,
            ["dl", "deciliter", "deciliters", "decilitre", "decilitres"])
        add("l", v, scale: 1e-3, foundation: UnitVolume.liters,
            ["l", "liter", "liters", "litre", "litres", "litro", "litros"], exact: ["L"])
        add("kl", v, scale: 1, foundation: UnitVolume.kiloliters,
            ["kl", "kiloliter", "kiloliters", "kilolitre", "kilolitres"])
        add("ul", v, scale: 1e-9, foundation: UnitVolume.milliliters,
            ["ul", "µl", "μl", "microliter", "microliters", "microlitre", "microlitres"])
        add("m3", v, scale: 1, foundation: UnitVolume.cubicMeters,
            ["m3", "m³", "cubicmeter", "cubicmeters", "cubicmetre", "cubicmetres",
             "cubic meter", "cubic meters", "cubic metre", "cubic metres"])
        add("cm3", v, scale: 1e-6, foundation: UnitVolume.cubicCentimeters,
            ["cm3", "cm³", "cc", "cubiccentimeter", "cubiccentimeters", "cubic centimetre", "cubic centimetres",
             "cubic centimeter", "cubic centimeters"])
        add("mm3", v, scale: 1e-9, foundation: UnitVolume.cubicMillimeters,
            ["mm3", "mm³", "cubicmillimeter", "cubicmillimeters"])
        add("in3", v, scale: 1.6387064e-5, foundation: UnitVolume.cubicInches,
            ["in3", "in³", "cubicinch", "cubicinches", "cubic inch", "cubic inches"])
        add("ft3", v, scale: 0.028316846592, foundation: UnitVolume.cubicFeet,
            ["ft3", "ft³", "cubicfoot", "cubicfeet", "cubic foot", "cubic feet"])
        add("yd3", v, scale: 0.764554857984, foundation: UnitVolume.cubicYards,
            ["yd3", "yd³", "cubicyard", "cubicyards", "cubic yard", "cubic yards"])
        add("gal", v, scale: 3.785411784e-3, foundation: UnitVolume.gallons,
            ["gal", "gallon", "gallons", "galao", "galoes"])
        add("qt", v, scale: 9.46352946e-4, foundation: UnitVolume.quarts,
            ["qt", "quart", "quarts"])
        add("pt", v, scale: 4.73176473e-4, foundation: UnitVolume.pints,
            ["pt", "pint", "pints"])
        add("cup", v, scale: 2.365882365e-4, foundation: UnitVolume.cups,
            ["cup", "cups", "xicara", "xicaras", "metriccup", "metriccups",
             "metric cup", "metric cups"])
        add("floz", v, scale: 2.95735295625e-5, foundation: UnitVolume.fluidOunces,
            ["floz", "fl oz", "fluidounce", "fluidounces", "fluid ounce", "fluid ounces"])
        add("tbsp", v, scale: 1.47867647813e-5, foundation: UnitVolume.tablespoons,
            ["tbsp", "tablespoon", "tablespoons"])
        add("tsp", v, scale: 4.92892159375e-6, foundation: UnitVolume.teaspoons,
            ["tsp", "teaspoon", "teaspoons"])
        add("ukgal", v, scale: 4.54609e-3, foundation: UnitVolume.imperialGallons, symbol: "ukgal",
            ["ukgal", "ukgallon", "ukgallons", "uk gallon", "uk gallons",
             "imperialgallon", "imperialgallons", "imperial gallon", "imperial gallons"])
        add("ukqt", v, scale: 1.1365225e-3, foundation: UnitVolume.imperialQuarts, symbol: "ukqt",
            ["ukqt", "imperialquart", "imperialquarts", "imperial quart", "imperial quarts"])
        add("ukpint", v, scale: 5.6826125e-4, foundation: UnitVolume.imperialPints, symbol: "ukpint",
            ["ukpint", "imperialpint", "imperialpints", "imperial pint", "imperial pints"])
        add("ukfloz", v, scale: 2.84130625e-5, foundation: UnitVolume.imperialFluidOunces, symbol: "ukfloz",
            ["ukfloz", "imperialfluidounce", "imperialfluidounces",
             "imperial fluid ounce", "imperial fluid ounces"])
        add("ukbsp", v, scale: 1.7758e-5, foundation: UnitVolume.imperialTablespoons, symbol: "ukbsp",
            ["ukbsp", "imperialtablespoon", "imperialtablespoons",
             "imperial tablespoon", "imperial tablespoons"])
        add("bbl", v, scale: 0.158987294928,
            ["bbl", "barrel", "barrels"])
        add("bu", v, scale: 0.03523907016688,
            ["bu", "bushel", "bushels"])

        // Area.
        add("m2", a, scale: 1, foundation: UnitArea.squareMeters,
            ["m2", "m²", "sqm", "sq m", "squaremeter", "squaremeters", "squaremetre", "squaremetres",
             "square meter", "square meters", "square metre", "square metres"])
        add("cm2", a, scale: 1e-4, foundation: UnitArea.squareCentimeters,
            ["cm2", "cm²", "sqcm", "sq cm", "squarecentimeter", "squarecentimeters", "square centimetre", "square centimetres",
             "square centimeter", "square centimeters"])
        add("mm2", a, scale: 1e-6, foundation: UnitArea.squareMillimeters,
            ["mm2", "mm²", "sqmm", "squaremillimeter", "squaremillimeters"])
        add("km2", a, scale: 1e6, foundation: UnitArea.squareKilometers,
            ["km2", "km²", "sqkm", "sq km", "squarekilometer", "squarekilometers", "square kilometre", "square kilometres",
             "square kilometer", "square kilometers"])
        add("sqin", a, scale: 6.4516e-4, foundation: UnitArea.squareInches,
            ["sqin", "sq in", "squareinch", "squareinches", "square inch", "square inches"])
        add("sqft", a, scale: 0.09290304, foundation: UnitArea.squareFeet,
            ["sqft", "sq ft", "squarefoot", "squarefeet", "square foot", "square feet"])
        add("sqyd", a, scale: 0.83612736, foundation: UnitArea.squareYards,
            ["sqyd", "sq yd", "squareyard", "squareyards", "square yard", "square yards"])
        add("sqmi", a, scale: 2.589988110336e6, foundation: UnitArea.squareMiles,
            ["sqmi", "sq mi", "squaremile", "squaremiles", "square mile", "square miles"])
        add("ha", a, scale: 1e4, foundation: UnitArea.hectares,
            ["ha", "hectare", "hectares"])
        add("acre", a, scale: 4046.8564224, foundation: UnitArea.acres,
            ["acre", "acres"])

        // Data: the bit is the base, so bytes and their SI prefixes are
        // multiples of eight. Decimal and binary units stay separate on
        // purpose — the whole reason someone asks is to settle which one.
        add("b", d, scale: 8, foundation: UnitInformationStorage.bytes,
            ["b", "byte", "bytes"], exact: ["B"])
        add("kb", d, scale: 8e3, foundation: UnitInformationStorage.kilobytes,
            ["kb", "kilobyte", "kilobytes"])
        add("mb", d, scale: 8e6, foundation: UnitInformationStorage.megabytes,
            ["mb", "megabyte", "megabytes"])
        add("gb", d, scale: 8e9, foundation: UnitInformationStorage.gigabytes,
            ["gb", "gigabyte", "gigabytes"])
        add("tb", d, scale: 8e12, foundation: UnitInformationStorage.terabytes,
            ["tb", "terabyte", "terabytes"])
        add("kib", d, scale: 8192, foundation: UnitInformationStorage.kibibytes,
            ["kib", "kibibyte", "kibibytes"])
        add("mib", d, scale: 8.388608e6, foundation: UnitInformationStorage.mebibytes,
            ["mib", "mebibyte", "mebibytes"])
        add("gib", d, scale: 8.589934592e9, foundation: UnitInformationStorage.gibibytes,
            ["gib", "gibibyte", "gibibytes"])
        add("tib", d, scale: 8.796093022208e12, foundation: UnitInformationStorage.tebibytes,
            ["tib", "tebibyte", "tebibytes"])
        add("bit", d, scale: 1, foundation: UnitInformationStorage.bits,
            ["bit", "bits"])
        add("kbit", d, scale: 1e3, foundation: UnitInformationStorage.kilobits,
            ["kbit", "kilobit", "kilobits"])
        add("mbit", d, scale: 1e6, foundation: UnitInformationStorage.megabits,
            ["mbit", "megabit", "megabits"])
        add("gbit", d, scale: 1e9, foundation: UnitInformationStorage.gigabits,
            ["gbit", "gigabit", "gigabits"])
        add("tbit", d, scale: 1e12, foundation: UnitInformationStorage.terabits,
            ["tbit", "terabit", "terabits"])
        // Bit rates carry their own symbol because "megabit per second" is
        // written Mbps, not Mbit/s, on every cable box.
        add("mbps", d / t, scale: 1e6,
            ["mbps", "megabitpersecond", "megabit per second"])
        add("kbps", d / t, scale: 1e3, ["kbps"])
        add("gbps", d / t, scale: 1e9, ["gbps", "gigabitpersecond", "gigabit per second"])

        // Speed and pace.
        add("kmh", l / t, scale: 1 / 3.6, foundation: UnitSpeed.kilometersPerHour,
            ["kmh", "kmph", "kph", "kilometersperhour", "kilometresperhour",
             "kilometers per hour", "kilometres per hour"])
        add("mph", l / t, scale: 0.44704, foundation: UnitSpeed.milesPerHour,
            ["mph", "milesperhour", "miles per hour"])
        add("kn", l / t, scale: 0.5144444444444444, foundation: UnitSpeed.knots,
            ["kn", "knot", "knots"])
        // Fuel: consumption is volume over distance (L²), economy its
        // reciprocal (L⁻²), so the two convert through the reciprocal rule.
        add("l100km", a, scale: 1e-8,
            ["l100km", "l/100km", "litersper100kilometers", "liters per 100 kilometers"])
        add("kml", a.negated(), scale: 1e6,
            ["kml", "km/l", "kmpl", "kilometersperliter", "kilometers per liter"])
        add("mpg", a.negated(), scale: 425143.7074303,
            ["mpg", "milespergallon", "miles per gallon"])

        // Pressure.
        add("pa", m / l * t * t, scale: 1, foundation: UnitPressure.newtonsPerMetersSquared, symbol: "pa",
            ["pa", "pascal", "pascals"])
        add("kpa", m / l * t * t, scale: 1e3, foundation: UnitPressure.kilopascals,
            ["kpa", "kilopascal", "kilopascals"])
        add("mpa", m / l * t * t, scale: 1e6, foundation: UnitPressure.megapascals,
            ["mpa", "megapascal", "megapascals"])
        add("hpa", m / l * t * t, scale: 100, foundation: UnitPressure.hectopascals,
            ["hpa", "hectopascal", "hectopascals"])
        add("bar", m / l * t * t, scale: 1e5, foundation: UnitPressure.bars,
            ["bar", "bars"])
        add("atm", m / l * t * t, scale: 101325, foundation: CommandBarUnitCatalog.customAtmosphere,
            ["atm", "atmosphere", "atmospheres"])
        add("psi", m / l * t * t, scale: 6894.757293168, foundation: UnitPressure.poundsForcePerSquareInch,
            ["psi", "poundsperSquareinch", "pounds per square inch"])
        add("mmhg", m / l * t * t, scale: 133.322387415, foundation: UnitPressure.millimetersOfMercury,
            ["mmhg", "millimetersofmercury", "millimeters of mercury"])
        add("inhg", m / l * t * t, scale: 3386.389, foundation: UnitPressure.inchesOfMercury,
            ["inhg", "inchesofmercury", "inches of mercury"])

        // Energy.
        add("j", m * l * l / (t * t), scale: 1, foundation: UnitEnergy.joules,
            ["j", "joule", "joules"], exact: ["J"])
        add("kj", m * l * l / (t * t), scale: 1e3, foundation: UnitEnergy.kilojoules,
            ["kj", "kilojoule", "kilojoules"])
        add("mj", m * l * l / (t * t), scale: 1e6, foundation: CommandBarUnitCatalog.customMegajoule,
            ["mj", "megajoule", "megajoules"])
        add("cal", m * l * l / (t * t), scale: 4.184, foundation: UnitEnergy.calories,
            ["cal", "calorie", "calories"])
        add("kcal", m * l * l / (t * t), scale: 4184, foundation: UnitEnergy.kilocalories,
            ["kcal", "kilocalorie", "kilocalories"])
        add("wh", m * l * l / (t * t), scale: 3600, foundation: CommandBarUnitCatalog.customWattHour,
            ["wh", "watthour", "watthours", "watt hour", "watt hours"])
        add("kwh", m * l * l / (t * t), scale: 3.6e6, foundation: CommandBarUnitCatalog.customKilowattHour,
            ["kwh", "kilowatthour", "kilowatthours", "kilowatt hour", "kilowatt hours"])
        add("mwh", m * l * l / (t * t), scale: 3.6e9, foundation: CommandBarUnitCatalog.customMegawattHour,
            ["mwh", "megawatthour", "megawatthours", "megawatt hour", "megawatt hours"])
        add("gwh", m * l * l / (t * t), scale: 3.6e12, foundation: CommandBarUnitCatalog.customGigawattHour,
            ["gwh", "gigawatthour", "gigawatthours", "gigawatt hour", "gigawatt hours"])
        add("btu", m * l * l / (t * t), scale: 1055.05585262, foundation: CommandBarUnitCatalog.customBTU,
            ["btu", "btus"])

        // Power: milli and mega are the one case where the letter matters.
        add("w", m * l * l / (t * t * t), scale: 1, foundation: UnitPower.watts,
            ["w", "watt", "watts"], exact: ["W"])
        add("mw", m * l * l / (t * t * t), scale: 1e-3, foundation: UnitPower.milliwatts,
            ["mw", "milliwatt", "milliwatts"], exact: ["mW"])
        add("megawatt", m * l * l / (t * t * t), scale: 1e6, foundation: UnitPower.megawatts,
            ["megawatt", "megawatts"], exact: ["MW"])
        add("kw", m * l * l / (t * t * t), scale: 1e3, foundation: UnitPower.kilowatts,
            ["kw", "kilowatt", "kilowatts"])
        add("gw", m * l * l / (t * t * t), scale: 1e9, foundation: UnitPower.gigawatts,
            ["gw", "gigawatt", "gigawatts"])
        add("hp", m * l * l / (t * t * t), scale: 745.6998715822702, foundation: UnitPower.horsepower,
            ["hp", "horsepower"])

        // Angle. The SI base is the radian, so a degree is its fraction and
        // the trig functions just read the stored value.
        add("rad", ang, scale: 1, foundation: UnitAngle.radians,
            ["rad", "radian", "radians"])
        add("deg", ang, scale: Double.pi / 180, foundation: UnitAngle.degrees,
            ["deg", "degree", "degrees", "°"])

        // Frequency.
        add("hz", t.negated(), scale: 1, foundation: UnitFrequency.hertz,
            ["hz", "hertz"], exact: ["Hz"])
        add("khz", t.negated(), scale: 1e3, foundation: UnitFrequency.kilohertz,
            ["khz", "kilohertz"])
        add("mhz", t.negated(), scale: 1e6, foundation: UnitFrequency.megahertz,
            ["mhz", "megahertz"])
        add("ghz", t.negated(), scale: 1e9, foundation: UnitFrequency.gigahertz,
            ["ghz", "gigahertz"])
        add("rpm", t.negated(), scale: 1.0 / 60.0, foundation: CommandBarUnitCatalog.customRPM,
            ["rpm"])
        add("rps", t.negated(), scale: 1, foundation: CommandBarUnitCatalog.customRPS,
            ["rps"])

        // Electrical. The ampere is the base, so volts, ohms, farads and the
        // rest fall out of the same exponent arithmetic as km/h. The bare
        // letters stay reserved for their older meanings: F is Fahrenheit, C
        // Celsius, H hours, S seconds and T tonnes, so those quantities are
        // only ever written out ("farad", "coulomb as As").
        add("a", i, scale: 1, foundation: UnitElectricCurrent.amperes,
            ["a", "amp", "amps", "ampere", "amperes"], exact: ["A"])
        add("ma", i, scale: 1e-3, foundation: UnitElectricCurrent.milliamperes,
            ["ma", "milliamp", "milliamps", "milliampere", "milliamperes"], exact: ["mA"])
        add("ka", i, scale: 1e3, foundation: UnitElectricCurrent.kiloamperes,
            ["ka", "kiloamp", "kiloamps", "kiloampere", "kiloamperes"], exact: ["kA"])
        add("v", voltDims, scale: 1, foundation: UnitElectricPotentialDifference.volts,
            ["v", "volt", "volts"], exact: ["V"])
        add("mv", voltDims, scale: 1e-3, foundation: UnitElectricPotentialDifference.millivolts,
            ["mv", "millivolt", "millivolts"], exact: ["mV"])
        add("kv", voltDims, scale: 1e3, foundation: UnitElectricPotentialDifference.kilovolts,
            ["kv", "kilovolt", "kilovolts"], exact: ["kV"])
        add("ohm", ohmDims, scale: 1, foundation: UnitElectricResistance.ohms,
            ["ohm", "ohms", "ω", "Ω"], exact: ["Ω"])
        add("kohm", ohmDims, scale: 1e3,
            ["kohm", "kohms", "kiloohm", "kiloohms", "kω", "kΩ"], exact: ["kΩ"])
        add("mohm", ohmDims, scale: 1e-3,
            ["mohm", "mohms", "milliohm", "milliohms", "mω", "mΩ"], exact: ["mΩ"])
        add("farad", faradDims, scale: 1, foundation: UnitElectricCapacitance.farads,
            ["farad", "farads"])
        add("uf", faradDims, scale: 1e-6, foundation: UnitElectricCapacitance.microfarads,
            ["uf", "µf", "μf", "microfarad", "microfarads"], exact: ["µF", "μF", "uF"])
        add("nf", faradDims, scale: 1e-9, foundation: UnitElectricCapacitance.nanofarads,
            ["nf", "nanofarad", "nanofarads"], exact: ["nF"])
        add("pf", faradDims, scale: 1e-12, foundation: UnitElectricCapacitance.picofarads,
            ["pf", "picofarad", "picofarads"], exact: ["pF"])
        add("weber", weberDims, scale: 1, symbol: "Wb",
            ["wb", "weber", "webers"], exact: ["Wb"])
        add("tesla", teslaDims, scale: 1, symbol: "T",
            ["tesla", "teslas"])
        add("mt", teslaDims, scale: 1e-3, symbol: "mT",
            ["mt", "millitesla", "milliteslas"], exact: ["mT"])
        add("gauss", teslaDims, scale: 1e-4,
            ["gauss"])
        add("henry", henryDims, scale: 1, foundation: UnitElectricInductance.henries,
            ["henry", "henries"])
        add("mh", henryDims, scale: 1e-3, foundation: UnitElectricInductance.millihenries,
            ["mh", "millihenry", "millihenries"], exact: ["mH"])
        add("siemens", siemensDims, scale: 1, foundation: UnitElectricConductance.siemens,
            ["siemens"])
        // Charge: the coulomb is the base, written out because C is Celsius.
        add("mah", i * t, scale: 3.6, foundation: UnitElectricCharge.milliampereHours,
            ["mah", "milliamphour", "milliamphours", "milliamp hour", "milliamp hours"], exact: ["mAh"])
        add("ah", i * t, scale: 3600,
            ["ah", "amphour", "amphours", "amp hour", "amp hours"], exact: ["Ah"])

        return units
    }()

    // MARK: - Custom Foundation units

    // Units the system does not carry, built with the symbol people expect so
    // the MeasurementFormatter prints "2 wk" and "3 kWh" instead of an
    // invented word. The coefficients are fixed multipliers of the base unit.
    static let customDays = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    static let customWeeks = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    static let customMonths = UnitDuration(symbol: "mo", converter: UnitConverterLinear(coefficient: 2_628_000))
    static let customYears = UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_536_000))
    static let customAtmosphere = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101325))
    static let customWattHour = UnitEnergy(symbol: "Wh", converter: UnitConverterLinear(coefficient: 3600))
    static let customKilowattHour = UnitEnergy(symbol: "kWh", converter: UnitConverterLinear(coefficient: 3.6e6))
    static let customMegawattHour = UnitEnergy(symbol: "MWh", converter: UnitConverterLinear(coefficient: 3.6e9))
    static let customGigawattHour = UnitEnergy(symbol: "GWh", converter: UnitConverterLinear(coefficient: 3.6e12))
    static let customMegajoule = UnitEnergy(symbol: "MJ", converter: UnitConverterLinear(coefficient: 1e6))
    static let customBTU = UnitEnergy(symbol: "BTU", converter: UnitConverterLinear(coefficient: 1055.05585262))
    static let customRPM = UnitFrequency(symbol: "rpm", converter: UnitConverterLinear(coefficient: 1.0 / 60.0))
    static let customRPS = UnitFrequency(symbol: "rps", converter: UnitConverterLinear(coefficient: 1))
}

// MARK: - Electrical quantities the system does not carry

// Foundation defines current, potential difference, resistance and charge,
// but not capacitance, inductance or conductance. They are still `Dimension`
// values, so the catalog treats them like every other unit: a scale from the
// SI base unit and nothing else.
final class UnitElectricCapacitance: Dimension, @unchecked Sendable {
    override class func baseUnit() -> UnitElectricCapacitance { farads }

    static let farads = UnitElectricCapacitance(symbol: "F",
                                                converter: UnitConverterLinear(coefficient: 1))
    static let microfarads = UnitElectricCapacitance(symbol: "µF",
                                                     converter: UnitConverterLinear(coefficient: 1e-6))
    static let nanofarads = UnitElectricCapacitance(symbol: "nF",
                                                    converter: UnitConverterLinear(coefficient: 1e-9))
    static let picofarads = UnitElectricCapacitance(symbol: "pF",
                                                    converter: UnitConverterLinear(coefficient: 1e-12))
}

final class UnitElectricInductance: Dimension, @unchecked Sendable {
    override class func baseUnit() -> UnitElectricInductance { henries }

    static let henries = UnitElectricInductance(symbol: "H",
                                                converter: UnitConverterLinear(coefficient: 1))
    static let millihenries = UnitElectricInductance(symbol: "mH",
                                                     converter: UnitConverterLinear(coefficient: 1e-3))
}

final class UnitElectricConductance: Dimension, @unchecked Sendable {
    override class func baseUnit() -> UnitElectricConductance { siemens }

    static let siemens = UnitElectricConductance(symbol: "S",
                                                 converter: UnitConverterLinear(coefficient: 1))
}
