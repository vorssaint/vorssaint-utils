// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit conversion for the command bar: "100 km to mi", "20c to f",
/// "5 gb to mb". Foundation does the arithmetic and writes the result in the
/// person's own language; this file only decides what the words mean.
///
/// Deliberately strict. A conversion needs a measurement, one of the little
/// words that mean "to", and another unit of the SAME family.
/// Anything else is left to the search, because a launcher that guesses at
/// conversions turns every sentence into a wrong answer.
enum CommandBarUnits {
    struct Result: Equatable {
        /// The answer, already written the way this Mac writes numbers.
        let formatted: String
        let value: Double
    }

    /// The words that mean "convert into", across the languages the app
    /// speaks. Parser vocabulary, not visible text.
    ///
    /// "in" is on this list and is also the symbol for inches. That collision
    /// is the classic trap, and it is why the parser only accepts "in" as a
    /// keyword when a real unit follows it and a number with a unit precedes
    /// it: "5 in to cm" reads the first as inches and the second as the verb.
    static let conversionWords: Set<String> = [
        "to", "in", "into", "as", "em", "para", "pra", "en", "a", "nach", "zu",
        "à", "su", "->", ">", "→",
    ]

    /// Everything the bar can convert, grouped so two units only meet when
    /// they measure the same thing.
    private enum Family {
        case temperature, length, mass, data, duration, volume
    }

    private struct KnownUnit {
        let family: Family
        let unit: Dimension
    }

    /// The lexicon. Symbols are matched exactly after folding, never fuzzily:
    /// "mi" must be miles and nothing else, and a near miss has to fall
    /// through to the search rather than convert the wrong thing.
    private static let lexicon: [String: KnownUnit] = {
        var map: [String: KnownUnit] = [:]
        func add(_ names: [String], _ family: Family, _ unit: Dimension) {
            for name in names { map[name] = KnownUnit(family: family, unit: unit) }
        }
        // Temperature. Absolute readings, never increments: 20 °C is 68 °F.
        add(["c", "celsius", "°c", "centigrade"], .temperature, UnitTemperature.celsius)
        add(["f", "fahrenheit", "°f"], .temperature, UnitTemperature.fahrenheit)
        add(["k", "kelvin"], .temperature, UnitTemperature.kelvin)
        // Length
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres", "milimetro", "milimetros"],
            .length, UnitLength.millimeters)
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres", "centimetro", "centimetros"],
            .length, UnitLength.centimeters)
        add(["m", "meter", "meters", "metro", "metros", "metre", "metres"], .length, UnitLength.meters)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres", "quilometro", "quilometros"],
            .length, UnitLength.kilometers)
        add(["in", "inch", "inches", "polegada", "polegadas", "\"", "″", "”"], .length, UnitLength.inches)
        add(["ft", "foot", "feet", "pe", "pes", "'", "′", "’"], .length, UnitLength.feet)
        add(["yd", "yard", "yards", "jarda", "jardas"], .length, UnitLength.yards)
        add(["mi", "mile", "miles", "milha", "milhas"], .length, UnitLength.miles)
        // Mass
        add(["mg", "milligram", "milligrams"], .mass, UnitMass.milligrams)
        add(["g", "gram", "grams", "grama", "gramas"], .mass, UnitMass.grams)
        add(["kg", "kilogram", "kilograms", "quilo", "quilos"], .mass, UnitMass.kilograms)
        add(["t", "ton", "tons", "tonne", "tonelada", "toneladas"], .mass, UnitMass.metricTons)
        add(["oz", "ounce", "ounces", "onca", "oncas"], .mass, UnitMass.ounces)
        add(["lb", "lbs", "pound", "pounds", "libra", "libras"], .mass, UnitMass.pounds)
        // Data. Decimal and binary are separate units on purpose: the whole
        // reason someone asks is to settle which one they meant.
        add(["b", "byte", "bytes"], .data, UnitInformationStorage.bytes)
        add(["kb", "kilobyte", "kilobytes"], .data, UnitInformationStorage.kilobytes)
        add(["mb", "megabyte", "megabytes"], .data, UnitInformationStorage.megabytes)
        add(["gb", "gigabyte", "gigabytes"], .data, UnitInformationStorage.gigabytes)
        add(["tb", "terabyte", "terabytes"], .data, UnitInformationStorage.terabytes)
        add(["kib", "kibibyte", "kibibytes"], .data, UnitInformationStorage.kibibytes)
        add(["mib", "mebibyte", "mebibytes"], .data, UnitInformationStorage.mebibytes)
        add(["gib", "gibibyte", "gibibytes"], .data, UnitInformationStorage.gibibytes)
        add(["tib", "tebibyte", "tebibytes"], .data, UnitInformationStorage.tebibytes)
        add(["bit", "bits"], .data, UnitInformationStorage.bits)
        // Duration
        add(["ms", "millisecond", "milliseconds"], .duration, UnitDuration.milliseconds)
        add(["s", "sec", "secs", "second", "seconds", "segundo", "segundos"], .duration, UnitDuration.seconds)
        add(["min", "mins", "minute", "minutes", "minuto", "minutos"], .duration, UnitDuration.minutes)
        add(["h", "hr", "hrs", "hour", "hours", "hora", "horas"], .duration, UnitDuration.hours)
        add(["d", "day", "days", "dia", "dias"], .duration, UnitDuration.days)
        add(["wk", "wks", "week", "weeks", "semana", "semanas"], .duration, UnitDuration.weeks)
        add(["yr", "yrs", "year", "years", "ano", "anos"], .duration, UnitDuration.years)
        // Volume
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililitro", "mililitros"],
            .volume, UnitVolume.milliliters)
        add(["l", "liter", "liters", "litre", "litres", "litro", "litros"], .volume, UnitVolume.liters)
        add(["gal", "gallon", "gallons", "galao", "galoes"], .volume, UnitVolume.gallons)
        add(["qt", "quart", "quarts"], .volume, UnitVolume.quarts)
        add(["floz", "fl oz", "fluidounce", "fluidounces", "fluid ounce", "fluid ounces"],
            .volume, UnitVolume.fluidOunces)
        add(["cup", "cups", "xicara", "xicaras"], .volume, UnitVolume.cups)
        return map
    }()

    /// The conversion for `input`, or nil when it is not one.
    static func convert(_ input: String,
                        decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                        groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                        locale: Locale = .current) -> Result? {
        let words = CommandBarSearch.normalized(input).split(separator: " ")
        guard words.count >= 3, words.count <= 8 else { return nil }

        // A connector is a whole word. In "5ft 11in in cm" only the second
        // "in" separates the measurement from its target.
        for position in stride(from: words.count - 2, through: 1, by: -1)
        where conversionWords.contains(String(words[position])) {
            guard let target = lexicon[words[(position + 1)...].joined(separator: " ")] else { continue }
            guard let source = parseValue(words[..<position].joined(separator: " "),
                                          decimalSeparator: decimalSeparator,
                                          groupingSeparator: groupingSeparator)
            else { continue }
            guard source.unit.family == target.family else { continue }
            let measurement = Measurement(value: source.value, unit: source.unit.unit)
            let converted = measurement.converted(to: target.unit)
            guard converted.value.isFinite else { continue }
            let formatted = feetAndInches(converted, locale: locale)
                ?? format(converted, locale: locale)
            return Result(formatted: formatted, value: converted.value)
        }
        return nil
    }

    private static func parseValue(_ text: String,
                                   decimalSeparator: String,
                                   groupingSeparator: String) -> (value: Double, unit: KnownUnit)? {
        var rest = text[...]
        func isNumberCharacter(_ c: Character) -> Bool {
            c.isNumber || c == "." || c == "," || c == "-"
        }
        func readNumber() -> Double? {
            let digits = rest.prefix(while: isNumberCharacter)
            rest = rest[digits.endIndex...].drop(while: \.isWhitespace)
            return number(String(digits), decimalSeparator: decimalSeparator, groupingSeparator: groupingSeparator)
        }

        guard let value = readNumber() else { return nil }
        if let unit = lexicon[String(rest)] { return (value, unit) }

        // Only whole feet can introduce an inch remainder. The inch mark is
        // optional in height shorthand such as "5ft 11" or "5′11".
        let footName = rest.prefix { !$0.isWhitespace && !isNumberCharacter($0) }
        guard let feet = lexicon[String(footName)], feet.unit == UnitLength.feet,
              value == value.rounded(.towardZero) else { return nil }
        rest = rest[footName.endIndex...].drop(while: \.isWhitespace)
        // An apostrophe followed by three digits can be a thousands separator.
        guard rest.first != "-", rest.prefix(while: \.isNumber).count <= 2,
              let inches = readNumber(), (0..<12).contains(inches),
              rest.isEmpty || lexicon[String(rest)]?.unit == UnitLength.inches
        else { return nil }
        let totalFeet = abs(value) + inches / 12
        return (value.sign == .minus ? -totalFeet : totalFeet, feet)
    }

    /// Like the calculator, accepts an alternate decimal separator unless it
    /// forms grouped thousands. When both separators occur, the last is decimal.
    /// Numeric components never include a space or an apostrophe, so
    /// where thousands are grouped with one of those the alternate is whichever
    /// of "." and "," is not the decimal, as in the calculator.
    private static func number(_ token: String,
                               decimalSeparator: String,
                               groupingSeparator: String) -> Double? {
        let groupsWithPunctuation = (groupingSeparator == "." || groupingSeparator == ",")
            && groupingSeparator != decimalSeparator
        let alternate = groupsWithPunctuation ? groupingSeparator : (decimalSeparator == "," ? "." : ",")
        var normalized = token
        let hasDecimal = token.contains(decimalSeparator)
        let hasAlternate = token.contains(alternate)
        if hasDecimal, hasAlternate {
            let decimalRange = token.range(of: decimalSeparator, options: .backwards)
            let alternateRange = token.range(of: alternate, options: .backwards)
            if let decimalRange, let alternateRange, alternateRange.lowerBound > decimalRange.lowerBound {
                normalized = token.replacingOccurrences(of: decimalSeparator, with: "")
                    .replacingOccurrences(of: alternate, with: ".")
            } else {
                normalized = token.replacingOccurrences(of: alternate, with: "")
                    .replacingOccurrences(of: decimalSeparator, with: ".")
            }
        } else if hasAlternate {
            // No grouped number opens with a 0 group, so "0,250" is a decimal.
            let unsigned = token.hasPrefix("-") ? String(token.dropFirst()) : token
            let groups = unsigned.components(separatedBy: alternate)
            let isGrouping = groups.count >= 2 && (1...3).contains(groups[0].count)
                && !groups[0].hasPrefix("0")
                && groups.dropFirst().allSatisfy { $0.count == 3 }
            normalized = token.replacingOccurrences(of: alternate, with: isGrouping ? "" : ".")
        } else if hasDecimal {
            normalized = token.replacingOccurrences(of: decimalSeparator, with: ".")
        }
        guard !normalized.isEmpty, normalized.filter({ $0 == "." }).count <= 1,
              normalized.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return Double(normalized)
    }

    /// Mixed units are useful once there is a whole foot to show. Smaller and
    /// negative values stay in decimal feet so the conversion keeps its meaning.
    private static func feetAndInches(_ measurement: Measurement<Dimension>,
                                      locale: Locale) -> String? {
        guard measurement.unit.symbol == UnitLength.feet.symbol,
              measurement.value >= 1
        else { return nil }

        var wholeFeet = measurement.value.rounded(.down)
        let rawInches = (measurement.value - wholeFeet) * 12
        let scale = pow(10, Double(fractionDigits(for: rawInches)))
        var inches = (rawInches * scale).rounded() / scale
        if inches >= 12 {
            wholeFeet += 1
            inches = 0
        }

        let feet = format(Measurement<Dimension>(value: wholeFeet, unit: UnitLength.feet),
                          locale: locale)
        guard inches != 0 else { return feet }
        let remainder = format(Measurement<Dimension>(value: inches, unit: UnitLength.inches),
                               locale: locale)
        return "\(feet) \(remainder)"
    }

    private static func format(_ measurement: Measurement<Dimension>, locale: Locale) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        // The unit asked for is the unit shown; nobody types "to mb" hoping
        // for gigabytes.
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.locale = locale
        formatter.numberFormatter.maximumFractionDigits = fractionDigits(for: measurement.value)
        formatter.numberFormatter.minimumFractionDigits = 0
        // Four decimals would print a millionth as "0", which reads as a
        // wrong answer, so a tiny value keeps its significant digits instead.
        // Temperature offsets can leave a tiny rounding remainder at zero;
        // keep their existing decimal precision instead of exposing it.
        let magnitude = abs(measurement.value)
        if magnitude != 0, magnitude < 0.001, !(measurement.unit is UnitTemperature) {
            formatter.numberFormatter.usesSignificantDigits = true
            formatter.numberFormatter.maximumSignificantDigits = 4
        }
        return formatter.string(from: measurement)
    }

    /// Small numbers keep their decimals, big ones lose the noise.
    private static func fractionDigits(for value: Double) -> Int {
        let magnitude = abs(value)
        if magnitude == 0 { return 0 }
        if magnitude < 1 { return 4 }
        if magnitude < 100 { return 2 }
        return 1
    }
}

// ponytail: Foundation defines UnitDuration only up to .hours; larger spans
// are fixed multipliers of seconds (365 days for year).
private extension UnitDuration {
    static let days = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    static let weeks = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    static let years = UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_536_000))
}
