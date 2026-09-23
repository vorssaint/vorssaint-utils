// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// US dollars per million tokens, from each provider's published API list.
struct AgentPrice: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double
    /// Short-lived cache writes. Providers that do not bill writes separately
    /// charge the input price.
    let cacheWrite: Double
    /// One-hour cache writes.
    let cacheWriteLong: Double
    /// Premium for the fast tier, on every token category, where it is sold.
    var fastMultiplier: Double = 1
    /// A premium on the whole request once the prompt passes a threshold,
    /// for the models that charge one.
    var longContext: AgentLongContext?
}

/// Past `above` prompt tokens, input and cache rates are multiplied by
/// `input` and output by `output`, on top of any fast tier.
struct AgentLongContext: Equatable {
    let above: Int
    let input: Double
    let output: Double
}

/// What one response bills, beyond its model.
struct AgentBillable: Equatable {
    var tokens = AgentTokens()
    /// The part of `tokens.cacheWrite` kept for an hour.
    var longCacheWrite = 0
    var fast = false
    /// Inference pinned to the United States.
    var domestic = false
    var webSearches = 0
}

/// Every price the island knows, kept out of the code: a copy ships with the
/// app, and a newer one published with the project replaces it, so a model
/// launched after a release gets its API value without an update. Fields a
/// later list adds are ignored; a list that breaks these rules is refused as a
/// whole, and the last good one stays.
struct AgentPriceList: Equatable {
    struct Model: Equatable {
        let id: String
        let price: AgentPrice
    }

    struct Plan: Equatable {
        /// Found inside the plan the agents record, like "max_20x".
        let match: String
        let name: String
        let monthly: Double?
    }

    /// Only a list written for this reader is used; a later, incompatible
    /// one waits for an app that understands it.
    static let schema = 1
    static let maximumSize = 256 << 10

    /// The day the list was last reviewed; the newer of two lists wins.
    let updated: Date
    let claude: [Model]
    let codex: [Model]
    let claudePlans: [Plan]
    let codexPlans: [Plan]
    let webSearch: Double
    let usOnlyMultiplier: Double

    static let empty = AgentPriceList(updated: .distantPast, claude: [], codex: [], claudePlans: [], codexPlans: [],
                                      webSearch: 0, usOnlyMultiplier: 1)

    static func decode(_ data: Data) -> AgentPriceList? {
        guard data.count <= maximumSize,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              number(json["schema"], in: 1...1_000) == Double(schema),
              let updated = (json["updated"] as? String).flatMap(day),
              let claude = json["claude"] as? [String: Any], let codex = json["codex"] as? [String: Any],
              let claudeModels = models(claude["models"], prefix: "claude-"),
              let codexModels = models(codex["models"], prefix: nil),
              let claudePlans = plans(claude["plans"]), let codexPlans = plans(codex["plans"]),
              let webSearch = number(claude["webSearch"], in: 0...1),
              let usOnly = number(claude["usOnlyMultiplier"], in: 1...3) else { return nil }
        return AgentPriceList(updated: updated, claude: claudeModels, codex: codexModels,
                              claudePlans: claudePlans, codexPlans: codexPlans, webSearch: webSearch,
                              usOnlyMultiplier: usOnly)
    }

    /// The newer of the list inside the app and the last one downloaded. On
    /// the same day the download wins, since it may carry a correction.
    static func newer(_ shipped: AgentPriceList?, _ downloaded: AgentPriceList?) -> AgentPriceList? {
        guard let downloaded else { return shipped }
        guard let shipped else { return downloaded }
        return downloaded.updated >= shipped.updated ? downloaded : shipped
    }

    private static func models(_ value: Any?, prefix: String?) -> [Model]? {
        guard let entries = value as? [[String: Any]], (1...500).contains(entries.count) else { return nil }
        var result: [Model] = []
        var seen = Set<String>()
        for entry in entries {
            guard let id = entry["id"] as? String, identifier(id, length: 64), seen.insert(id).inserted,
                  prefix.map(id.hasPrefix) ?? !id.hasPrefix("claude-"),
                  let input = number(entry["input"], in: 0...1_000),
                  let output = number(entry["output"], in: 0...1_000),
                  let cacheRead = number(entry["cacheRead"], in: 0...1_000) else { return nil }
            // Fields left out fall back to plain input pricing, the way
            // providers without separate cache writes bill them.
            let cacheWrite = entry["cacheWrite"] == nil ? input : number(entry["cacheWrite"], in: 0...1_000)
            let cacheWriteLong = entry["cacheWriteLong"] == nil ? cacheWrite : number(entry["cacheWriteLong"], in: 0...1_000)
            let fast = entry["fastMultiplier"] == nil ? 1 : number(entry["fastMultiplier"], in: 1...10)
            guard let cacheWrite, let cacheWriteLong, let fast else { return nil }
            var long: AgentLongContext?
            if let value = entry["longContext"] {
                guard let object = value as? [String: Any],
                      let above = number(object["above"], in: 1_000...10_000_000),
                      let longInput = number(object["inputMultiplier"], in: 1...10),
                      let longOutput = number(object["outputMultiplier"], in: 1...10) else { return nil }
                long = AgentLongContext(above: Int(above), input: longInput, output: longOutput)
            }
            result.append(Model(id: id, price: AgentPrice(input: input, output: output, cacheRead: cacheRead,
                                                          cacheWrite: cacheWrite, cacheWriteLong: cacheWriteLong,
                                                          fastMultiplier: fast, longContext: long)))
        }
        return result
    }

    private static func plans(_ value: Any?) -> [Plan]? {
        guard let entries = value as? [[String: Any]], entries.count <= 50 else { return nil }
        var result: [Plan] = []
        for entry in entries {
            guard let match = entry["match"] as? String, identifier(match, length: 40),
                  let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  (1...24).contains(name.count) else { return nil }
            let monthly = entry["monthly"] == nil ? nil : number(entry["monthly"], in: 0...100_000)
            guard entry["monthly"] == nil || monthly != nil else { return nil }
            result.append(Plan(match: match, name: name, monthly: monthly))
        }
        return result
    }

    /// Lowercase letters, digits, dots, dashes and underscores: the shape of
    /// every model and plan the agents record.
    private static func identifier(_ text: String, length: Int) -> Bool {
        (1...length).contains(text.count) && text.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" || $0 == "_"
        }
    }

    /// A finite number inside `range`; a JSON true or false is not one.
    private static func number(_ value: Any?, in range: ClosedRange<Double>) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite && range.contains(double) ? double : nil
    }

    /// "2026-09-22", read as that day in UTC.
    private static func day(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (2024...2100).contains(parts[0]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }
}

/// Costs are what the same traffic would bill through the API. A plan pays a
/// flat price instead, so the island presents them as API value.
enum AgentPricing {
    private static let lock = NSLock()
    private static var installed = AgentPriceList.empty

    /// The list prices come from, safe to read from any thread.
    static var list: AgentPriceList { lock.withLock { installed } }

    /// Makes `list` the one prices come from; false when nothing changes.
    @discardableResult
    static func install(_ list: AgentPriceList) -> Bool {
        lock.withLock {
            guard installed != list else { return false }
            installed = list
            return true
        }
    }

    /// Provider prefixes, snapshot dates and context tags vary by where the
    /// model runs; the family name in the middle does not.
    static func normalized(_ model: String) -> String {
        var id = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = id.range(of: "claude-") { id = String(id[range.lowerBound...]) }
        if let slash = id.lastIndex(of: "/") { id = String(id[id.index(after: slash)...]) }
        for marker in ["@", "["] {
            if let index = id.firstIndex(of: Character(marker)) { id = String(id[..<index]) }
        }
        return id
    }

    /// Words that make a variant a model of its own, with its own price.
    static let siblings = ["mini", "nano", "pro", "lite", "research", "search", "audio", "realtime",
                           "transcribe", "tts", "cyber", "image"]

    /// The longest matching family wins, so a point release the list names
    /// never inherits the price of the version it extends.
    static func price(for model: String, in list: AgentPriceList = AgentPricing.list) -> AgentPrice? {
        let id = normalized(model)
        let table = id.hasPrefix("claude-") ? list.claude : list.codex
        guard let match = table.filter({ matches(id, family: $0.id) })
            .max(by: { $0.id.count < $1.id.count }) else { return nil }
        // A smaller, larger or specialized sibling the list does not name is
        // priced very differently from its family; better no figure than a
        // wrong one.
        let rest = id.dropFirst(match.id.count)
        if siblings.contains(where: { rest.contains($0) }) { return nil }
        return match.price
    }

    /// A family matches at a word boundary: "gpt-5" is not "gpt-5.1", and a
    /// number after it names another version, so "claude-opus-5" is not a
    /// later "claude-opus-5-6". A snapshot date after it is the same model.
    private static func matches(_ id: String, family: String) -> Bool {
        guard id.hasPrefix(family) else { return false }
        let rest = id.dropFirst(family.count)
        guard let next = rest.first else { return true }
        guard next == "-" || next == "_" || next == ":" else { return false }
        let number = rest.dropFirst().prefix { $0.isNumber }
        return number.isEmpty || number.count >= 4
    }

    static func cost(_ billable: AgentBillable, model: String) -> (cost: Double?, savings: Double) {
        let list = self.list
        guard let price = price(for: model, in: list) else { return (nil, 0) }
        let tokens = billable.tokens
        let long = min(max(0, billable.longCacheWrite), tokens.cacheWrite)
        var multiplier = billable.fast ? price.fastMultiplier : 1
        if billable.domestic { multiplier *= list.usOnlyMultiplier }
        var inputRate = multiplier
        var outputRate = multiplier
        if let long = price.longContext, tokens.prompt > long.above {
            inputRate *= long.input
            outputRate *= long.output
        }
        let cost = (Double(tokens.input) * price.input * inputRate
                    + Double(tokens.cacheWrite - long) * price.cacheWrite * inputRate
                    + Double(long) * price.cacheWriteLong * inputRate
                    + Double(tokens.cacheRead) * price.cacheRead * inputRate
                    + Double(tokens.output) * price.output * outputRate) / 1_000_000
            + Double(max(0, billable.webSearches)) * list.webSearch
        let savings = Double(tokens.cacheRead) * max(0, price.input - price.cacheRead) * inputRate / 1_000_000
        return (cost, savings)
    }

    /// Readable model names: "claude-opus-5-5" reads "Opus 5.5" and
    /// "gpt-6-astra" reads "GPT-6 Astra". Built from the name itself, so a
    /// model no list knows yet still reads well.
    static func displayName(_ model: String) -> String {
        let id = normalized(model)
        guard !id.isEmpty else { return "" }
        if id.hasPrefix("claude-") {
            var parts = id.dropFirst(7).split(separator: "-").map(String.init)
            // Snapshot dates and version suffixes add nothing to a name.
            parts.removeAll { $0.count >= 6 && $0.allSatisfy(\.isNumber) }
            parts.removeAll { $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }
            parts.removeAll { $0 == "latest" }
            let words = parts.filter { !$0.allSatisfy(\.isNumber) }
            let version = parts.filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
            let name = [words.first?.capitalized ?? "", version] + words.dropFirst().map(\.capitalized)
            return name.filter { !$0.isEmpty }.joined(separator: " ")
        }
        guard id.hasPrefix("gpt-") else { return id }
        var parts = id.dropFirst(4).split(separator: "-").map(String.init)
        // An alias names whatever it points to today.
        parts.removeAll { $0 == "latest" }
        // A dated snapshot, "-2026-10-01" or "-20261001", is the same model.
        parts.removeAll { $0.count >= 6 && $0.allSatisfy(\.isNumber) }
        if parts.count >= 4, let year = Int(parts[parts.count - 3]), (2000...2100).contains(year),
           parts.suffix(2).allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }) {
            parts.removeLast(3)
        }
        guard let first = parts.first else { return "GPT" }
        let head = first.first?.isNumber == true ? "GPT-" + first : "GPT " + first.capitalized
        return ([head] + parts.dropFirst().map(\.capitalized)).joined(separator: " ")
    }
}

/// Subscriptions, recognized from what the agents keep on disk.
enum AgentPlans {
    static func claude(organizationType: String?, rateLimitTier: String?,
                       list: AgentPriceList = AgentPricing.list) -> AgentPlan? {
        let type = (organizationType ?? "").lowercased()
        let recorded = (rateLimitTier ?? "").lowercased() + " " + type
        if let plan = list.claudePlans.first(where: { recorded.contains($0.match) }) {
            return AgentPlan(name: plan.name, monthlyPrice: plan.monthly)
        }
        // A plan newer than the list still shows its own name.
        let name = type.replacingOccurrences(of: "claude_", with: "").replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : AgentPlan(name: name.capitalized, monthlyPrice: nil)
    }

    static func codex(planType: String?, list: AgentPriceList = AgentPricing.list) -> AgentPlan? {
        guard let raw = planType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        if let plan = list.codexPlans.first(where: { $0.match == raw }) {
            return AgentPlan(name: plan.name, monthlyPrice: plan.monthly)
        }
        return AgentPlan(name: raw.prefix(1).uppercased() + raw.dropFirst(), monthlyPrice: nil)
    }
}
