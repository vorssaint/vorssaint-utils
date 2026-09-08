// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum CommandBarSearchTests {
    static func run(expect: (Bool, String) -> Void) {
        // Dates and places, answered by the calendar this Mac carries.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let english = Locale(identifier: "en_US")
        let tuesday = Date(timeIntervalSince1970: 1_785_240_000)   // 2026-07-28
        func dated(_ input: String, _ locale: Locale = english) -> String? {
            CommandBarDates.evaluate(input, now: tuesday, calendar: gregorian, locale: locale)?.formatted
        }
        expect(dated("in 3 weeks") == "August 18, 2026",
               "three weeks from now is a date, not a search")
        expect(dated("daqui 10 dias", Locale(identifier: "pt_BR")) == "7 de agosto de 2026",
               "the same question in the person's own words, written their way")
        expect(dated("3 days ago") == "July 25, 2026" && dated("ha 3 dias") == "July 25, 2026",
               "backwards counts backwards, before or after the number")
        expect(dated("today + 10 days") == "August 7, 2026"
                && dated("today - 10 days") == "July 18, 2026",
               "a plain sign decides the direction")
        expect(dated("3 days") == nil && dated("2+2") == nil && dated("100 km to mi") == nil,
               "without a direction it is not a question, and a sum is not a date")
        expect(CommandBarDates.evaluate("in 3 weeks", now: tuesday, calendar: gregorian,
                                        locale: english)?.detail == "Tuesday",
               "the answer says which weekday it lands on")
        expect(dated("days until 12/25")?.contains("150") == true,
               "how far away a written date is, counted in whole days")
        expect(CommandBarDates.evaluate("time in tokyo", now: tuesday, calendar: gregorian,
                                        locale: english)?.detail.hasPrefix("Tokyo") == true,
               "the clock somewhere else, from the time zones the Mac already knows")
        expect(CommandBarDates.evaluate("hora em londres", now: tuesday, calendar: gregorian,
                                        locale: english)?.detail.hasPrefix("London") == true,
               "a city named the way the person's language names it")
        expect(CommandBarDates.evaluate("time", now: tuesday, calendar: gregorian,
                                        locale: english) == nil,
               "a time word with nowhere to look is not an answer")
        // The gate is the whole safety of this: anything a person might be
        // searching for that happens to carry a number must fall through.
        for innocent in ["1password", "2 monitors", "3 tags", "notes", "day one",
                         "5 minutes", "2026-07-28", "the 3 body problem"] {
            expect(CommandBarDates.evaluate(innocent, now: tuesday, calendar: gregorian,
                                            locale: english) == nil,
                   "\"\(innocent)\" is a search, not a date")
        }

        // The places the person saves themselves.
        expect(CommandBarLinks.expand("https://x.com/search?q={query}", kind: .link,
                                      query: "café com leite")
                == "https://x.com/search?q=caf%C3%A9%20com%20leite",
               "what goes into a web address is escaped")
        expect(CommandBarLinks.expand("~/Projects/{query}", kind: .place, query: "my folder")
                == "~/Projects/my folder",
               "a path is not a URL and is never escaped")
        expect(CommandBarLinks.expand("https://x.com/{clipboard}", kind: .link,
                                      clipboard: "a+b") == "https://x.com/a%2Bb",
               "a plus sign inside a search is escaped, not read as a space")
        expect(CommandBarLinks.trailingArgument(query: "gh vorssaint utils", name: "gh")
                == "vorssaint utils",
               "what comes after the name is what the saved search opens with")
        expect(CommandBarLinks.trailingArgument(query: "GH Vorssaint", name: "gh") == "Vorssaint",
               "the name is matched without case; the argument keeps its own")
        expect(CommandBarLinks.trailingArgument(query: "ghost writer", name: "gh") == nil
                && CommandBarLinks.trailingArgument(query: "gh", name: "gh") == nil,
               "a longer word is not the name, and the name alone is not an argument")
        expect(CommandBarLinks.trailingArgument(query: "bd\u{3000}123", name: "bd") == "123",
               "a full-width space separates the name from its argument")
        expect(CommandBarLink(name: "gh", kind: .link, destination: "https://x/{query}").takesQuery
                && !CommandBarLink(name: "a", kind: .link, destination: "https://x").takesQuery,
               "a destination that waits for a query is a search")
        expect(CommandBarLinks.url(for: CommandBarLink(name: "a", kind: .link, destination: "x.com"),
                                   expanded: "x.com")?.scheme == "https",
               "a destination pasted without a scheme is still a site")
        expect(CommandBarLinks.decode(CommandBarLinks.encode([
            CommandBarLink(name: "", kind: .link, destination: "x"),
            CommandBarLink(name: "ok", kind: .link, destination: "x"),
        ])).count == 1, "a half-written shortcut never survives a round trip")
        // MARK: The other names macOS knows an app by
        expect(SpotlightNamesSupport.usableAlternateNames(["Legacy Planner", "Planner.app"],
                                                          displayName: "Planner",
                                                          fileName: "Planner.app")
                == ["Legacy Planner"],
               "a real alias is kept and the bundle's own file name is not")
        expect(SpotlightNamesSupport.usableAlternateNames(
                ["Preferences", "Settings", "Configuration.app", "Previous Settings",
                 "Configuration"],
                displayName: "Configuration",
                fileName: "Configuration.app")
                == ["Preferences", "Settings", "Previous Settings"],
               "an alias repeating the name under the icon teaches the search nothing")
        expect(SpotlightNamesSupport.usableAlternateNames(["ALTERNATE_NAME_1", "  ", "browser"],
                                                          displayName: "Navigator",
                                                          fileName: "Navigator.app") == ["browser"],
               "an untranslated placeholder is not a name anybody types")
        expect(SpotlightNamesSupport.usableAlternateNames(["Café", "cafe"],
                                                          displayName: "Reader",
                                                          fileName: "Reader.app") == ["Café"],
               "two aliases that differ only by accent or case are one alias")

        expect(CommandBarLinks.revealPath(for: CommandBarLink(name: "notes", kind: .place,
                                                              destination: "~/Notes"))
                == NSHomeDirectory() + "/Notes",
               "a saved folder can be shown where it lives")
        expect(CommandBarLinks.revealPath(for: CommandBarLink(name: "site", kind: .link,
                                                              destination: "https://example.invalid")) == nil,
               "a site has no place on the disk to show")
        expect(CommandBarLinks.revealPath(for: CommandBarLink(name: "day", kind: .place,
                                                              destination: "~/Notes/{date}.md")) == nil,
               "a place still holding a placeholder is a different file every time it runs")
        expect(CommandBarLinks.rankingTitle(name: "gh", query: "gh vorssaint utils")
                == "gh vorssaint utils",
               "once an argument follows the name, the row is scored against the whole query")
        expect(CommandBarLinks.rankingTitle(name: "gh", query: "gh") == "gh",
               "the name alone still scores against its own name")
        expect(CommandBarLinks.rankingTitle(name: "gh", query: "ghost writer") == "gh",
               "a word that only starts with the name is not an argument, so scoring is untouched")
        // The defect itself: scored against its own name, a saved search left
        // the list on the first word of the argument, which is the moment it
        // was about to run.
        expect(CommandBarSearch.score(title: "gh", keywords: "Link",
                                      query: "gh vorssaint utils") == nil
                && CommandBarSearch.score(
                    title: CommandBarLinks.rankingTitle(name: "gh", query: "gh vorssaint utils"),
                    keywords: "Link", query: "gh vorssaint utils") != nil,
               "a saved search stays in the list while what to look for is typed")

        expect(CommandBarLink.Kind.script.symbolName == "terminal",
               "a script link gets its own icon")
        expect(CommandBarLink(name: "cur", kind: .script, destination: "/tmp/x").takesArgument
                && !CommandBarLink(name: "a", kind: .place, destination: "/tmp").takesArgument,
               "a script always takes its argument; a plain place or link does not")
        expect(CommandBarLink(name: "gh", kind: .link, destination: "https://x/{query}").takesArgument,
               "a query link still takes its argument through the existing placeholder check")
        expect(CommandBarLinks.url(for: CommandBarLink(name: "cur", kind: .script,
                                                        destination: "/tmp/x"),
                                   expanded: "/tmp/x") == nil,
               "a script has nothing to open")
        let scriptLinks = [
            CommandBarLink(name: "a", kind: .link, destination: "https://x"),
            CommandBarLink(name: "cur", kind: .script, destination: "/tmp/currency-convert.sh"),
        ]
        expect(CommandBarLinks.matchingScriptLink(in: scriptLinks, query: "cur 100 usd eur")?.argument
                == "100 usd eur",
               "a script link matches once something follows its name")
        expect(CommandBarLinks.matchingScriptLink(in: scriptLinks, query: "cur") == nil,
               "the bare name alone has nothing to run yet")
        let bareRunnable = [
            CommandBarLink(name: "clean", kind: .script, destination: "/tmp/clean",
                           runsWithoutArgument: true),
        ]
        expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "clean")?.argument == "",
               "a script marked as needing nothing runs on its bare name")
        expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "  Clean  ")?.argument
                == "",
               "the bare name is matched the same way every other name is")
        expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "clean code")?.argument
                == "code",
               "that same script still receives an argument when one is typed")
        expect(CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "cle") == nil
                && CommandBarLinks.matchingScriptLink(in: bareRunnable, query: "cleaner") == nil,
               "a script never runs off a prefix of its name, or a longer word starting with it")
        // The list drops a script's own row once the answer row stands in for
        // it. That has to use the same rule that decided the script would run,
        // or a bare name shows the script twice: once as an answer and once as
        // the plain row nothing removed.
        expect(CommandBarLinks.matchingScriptLinks(in: bareRunnable, query: "clean")
                .map(\.name) == ["clean"],
               "a bare-name match is dropped from the list, like any other script match")
        expect(CommandBarLinks.matchingScriptLinks(in: scriptLinks, query: "cur 100 usd eur")
                .map(\.name) == ["cur"],
               "a script named with an argument is dropped from the list")
        expect(CommandBarLinks.matchingScriptLinks(in: scriptLinks, query: "cur").isEmpty
                && CommandBarLinks.matchingScriptLinks(in: scriptLinks, query: "a 1").isEmpty,
               "nothing is dropped for a script that did not match, or for a non-script link")
        expect(CommandBarLinks.matchingScriptLink(in: scriptLinks, query: "a 100 usd eur") == nil,
               "a non-script link never matches, even with an argument")
        let overlappingScripts = [
            CommandBarLink(name: "run", kind: .script, destination: "/tmp/short"),
            CommandBarLink(name: "run report", kind: .script, destination: "/tmp/specific"),
        ]
        expect(CommandBarLinks.matchingScriptLink(in: overlappingScripts,
                                                   query: "run report today")?.link.name
                == "run report",
               "the most specific script name wins over a shorter prefix")
        expect(CommandBarLinks.matchingScriptLinks(in: overlappingScripts, query: "run report x")
                .map(\.name).sorted() == ["run", "run report"],
               "both overlapping names are dropped, so only the answer row is left")
        expect(CommandBarLinks.resultText("  100 USD = 86.70 EUR\n") == "100 USD = 86.70 EUR",
               "a script's output loses its wrapping whitespace")
        expect(CommandBarLinks.resultText("   \n") == nil,
               "empty output means nothing is ready yet")

        let savedBeforeTheField = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"gh","#
            + #""kind":"link","destination":"https://x"}]"#
        let loadedOldShortcuts = CommandBarLinks.decode(Data(savedBeforeTheField.utf8))
        expect(loadedOldShortcuts.count == 1 && loadedOldShortcuts.first?.name == "gh"
                && loadedOldShortcuts.first?.runsWithoutArgument == false,
               "a shortcut saved before runsWithoutArgument existed still loads, defaulting to off")
        let roundTripped = CommandBarLinks.decode(
            CommandBarLinks.encode([CommandBarLink(name: "clean", kind: .script,
                                                   destination: "/tmp/clean",
                                                   runsWithoutArgument: true)]))
        expect(roundTripped.first?.runsWithoutArgument == true,
               "the flag survives being saved and loaded again")

        // MARK: Open what was typed as a URL
        for address in ["example.com", "example.com/x", "https://example.com",
                        "example.com:8080/path", "http://example.com/path?q=1",
                        "sub.domain.co.uk", "https://example.museum", "https://例子.中国"] {
            expect(CommandBarLinks.typedURL(address) != nil,
                   "\"\(address)\" reads like a URL")
        }
        for plain in ["hello", "file.txt", "3.14", "version 2.0", "notes",
                      "a b c", "", "  ", "v1.2", "localhost",
                      "user@example.com", "something/else", "https://", "http:notes",
                      "https://exa mple.com", "ftp://files.example.org"] {
            expect(CommandBarLinks.typedURL(plain) == nil,
                   "\"\(plain)\" is a search, not a URL")
        }
        expect(CommandBarLinks.typedURL("example.com")?.absoluteString == "https://example.com",
               "a typed bare domain is opened with an https scheme")
        expect(CommandBarLinks.typedURL("example.com:8080/path")?.absoluteString
                == "https://example.com:8080/path",
               "a port on a bare domain does not become a fake scheme")
        expect(CommandBarLinks.typedURL("https://example.com/x")?.absoluteString
                == "https://example.com/x",
               "a typed address with a scheme keeps its scheme")

        expect(CommandBarText.wordCount("uma frase com cinco palavras") == 5
                && CommandBarText.wordCount("  espaços   demais  ") == 2
                && CommandBarText.wordCount("") == 0,
               "words are counted the way a person counts them")
        expect(CommandBarText.characterCount("café") == 4,
               "an accented letter is one character, not two")
        expect(CommandBarText.preview("uma linha\ncom quebra") == "uma linha com quebra",
               "a preview of a paragraph stays on one line")
        expect(CommandBarText.preview(String(repeating: "a", count: 60), limit: 10)
                == String(repeating: "a", count: 10) + "…",
               "a long selection is cut with an ellipsis")
        expect(CommandBarText.changesCase("abc", to: { $0.localizedUppercase })
                && !CommandBarText.changesCase("ABC", to: { $0.localizedUppercase }),
               "a case row is only offered when the case would change")

        expect(CommandBarSearch.splitTrailingNumber("brilho 40")
                == CommandBarNumberSplit(text: "brilho", number: 40),
               "a trailing number splits off the verb")
        expect(CommandBarSearch.splitTrailingNumber("volume 20%")
                == CommandBarNumberSplit(text: "volume", number: 20),
               "a percent sign on the number is fine")
        expect(CommandBarSearch.splitTrailingNumber("brilho")
                == CommandBarNumberSplit(text: "brilho", number: nil),
               "a bare verb carries no number")
        expect(CommandBarSearch.splitTrailingNumber("40")
                == CommandBarNumberSplit(text: "40", number: nil),
               "a number alone is a search, not a command")
        expect(CommandBarSearch.splitTrailingNumber("manter acordado 30")
                == CommandBarNumberSplit(text: "manter acordado", number: 30),
               "multi-word verbs keep their words")
        expect(CommandBarSearch.argumentValue("40", in: 0...100) == 40
                && CommandBarSearch.argumentValue("140", in: 0...100) == 100
                && CommandBarSearch.argumentValue("35%", in: 0...100) == 35
                && CommandBarSearch.argumentValue("abc", in: 0...100) == nil
                && CommandBarSearch.argumentValue("", in: 0...100) == nil,
               "inline arguments accept digits, clamp and reject the rest")

        let barNow: Double = 1_800_000_000
        var barUsage: [String: CommandBarUse] = [:]
        barUsage = CommandBarUsage.recording(barUsage, id: "action.screenshot", now: barNow)
        barUsage = CommandBarUsage.recording(barUsage, id: "action.screenshot", now: barNow + 10)
        barUsage = CommandBarUsage.recording(barUsage, id: "action.darkMode", now: barNow + 20)
        expect(barUsage["action.screenshot"]?.count == 2
                && barUsage["action.screenshot"]?.lastUsed == barNow + 10,
               "recording a run counts it and stamps the time")
        let barEncoded = CommandBarUsage.encode(barUsage)
        expect(CommandBarUsage.decode(barEncoded) == barUsage,
               "usage survives the round trip")
        expect(CommandBarUsage.decode("not json").isEmpty && CommandBarUsage.decode(nil).isEmpty,
               "corrupt usage decodes as a clean slate")
        var crowded: [String: CommandBarUse] = [:]
        for index in 0..<(CommandBarUsage.storedIDLimit + 5) {
            crowded = CommandBarUsage.recording(crowded, id: "app.\(index)", now: barNow + Double(index))
        }
        expect(crowded.count == CommandBarUsage.storedIDLimit && crowded["app.0"] == nil
                && crowded["app.\(CommandBarUsage.storedIDLimit + 4)"] != nil,
               "the usage store caps by dropping the oldest ids")
        expect(CommandBarUsage.boost(for: CommandBarUse(count: 3, lastUsed: barNow), now: barNow + 60)
                > CommandBarUsage.boost(for: CommandBarUse(count: 3, lastUsed: barNow), now: barNow + 30 * 86400),
               "a habit fades as it ages")
        expect(CommandBarUsage.boost(for: CommandBarUse(count: 999, lastUsed: barNow), now: barNow) < 700,
               "no habit outruns a literal text hit")
        expect(CommandBarUsage.boost(for: nil, now: barNow) == 0,
               "no usage, no boost")
        let categoryOrder = CommandBarUsage.categoryIDs(
            usage: [
                "emoji.fire": CommandBarUse(count: 3, lastUsed: barNow),
                "emoji.heart": CommandBarUse(count: 3, lastUsed: barNow + 10),
                "emoji.wave": CommandBarUse(count: 1, lastUsed: barNow + 20),
            ],
            available: ["emoji.grin", "emoji.fire", "emoji.wave", "emoji.heart", "emoji.star"])
        expect(categoryOrder == [
            "emoji.heart", "emoji.fire", "emoji.wave", "emoji.grin", "emoji.star",
        ], "empty categories lead with frequent and recent choices, then keep catalog order")
        expect(CommandBarUsage.categoryIDs(usage: [:],
                                           available: ["emoji.grin", "emoji.fire", "emoji.wave"])
                == ["emoji.grin", "emoji.fire", "emoji.wave"],
               "an unlearned category preserves its useful catalog order")

        let officialHabitService = CommandBarQueryHabits.installationKeyService(
            bundleID: "com.vorssaint.utils")
        let developerHabitService = CommandBarQueryHabits.installationKeyService(
            bundleID: "com.vorssaint.utils.dev")
        expect(officialHabitService == "com.vorssaint.utils.command-bar-query-habits"
                && officialHabitService != developerHabitService,
               "uninstalling one app variant cannot target the other variant's query key")

        let habitKey = Data(repeating: 0x31, count: 32)
        let otherHabitKey = Data(repeating: 0x72, count: 32)
        for shortQuery in ["w", "wa"] {
            let prepared = CommandBarQueryHabits.prepare(shortQuery, key: habitKey)
            let recorded = CommandBarQueryHabits.recording(
                [:], preparedQuery: prepared, resultID: "app.whatever", now: barNow)
            let restored = CommandBarQueryHabits.decode(CommandBarQueryHabits.encode(recorded))
            expect(CommandBarQueryHabits.boost(
                for: "app.whatever", preparedQuery: prepared, store: restored, now: barNow) > 0,
                "one- and two-character choices survive a storage round trip")
        }
        let preparedWhat = CommandBarQueryHabits.prepare("what", key: habitKey)
        let preparedWhatever = CommandBarQueryHabits.prepare("whatever", key: habitKey)
        var queryHabits: CommandBarQueryHabits.Store = [:]
        queryHabits = CommandBarQueryHabits.recording(
            queryHabits, preparedQuery: preparedWhat,
            resultID: "app./Applications/Whatever.app", now: barNow)
        queryHabits = CommandBarQueryHabits.recording(
            queryHabits, preparedQuery: preparedWhat,
            resultID: "app./Applications/Whatever.app", now: barNow + 10)
        let learnedExact = CommandBarQueryHabits.boost(
            for: "app./Applications/Whatever.app", preparedQuery: preparedWhat,
            store: queryHabits, now: barNow + 20)
        let learnedRelated = CommandBarQueryHabits.boost(
            for: "app./Applications/Whatever.app", preparedQuery: preparedWhatever,
            store: queryHabits, now: barNow + 20)
        expect(learnedExact > 0 && learnedRelated > 0,
               "repeated choices teach the exact query and a longer related query")
        expect(CommandBarQueryHabits.boost(
                    for: "app./Applications/Whatever Beta.app", preparedQuery: preparedWhat,
                    store: queryHabits,
                    now: barNow + 20) == 0,
               "a learned query lifts only the selected result")
        let encodedQueryHabits = CommandBarQueryHabits.encode(queryHabits)
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        let otherPreparedWhat = CommandBarQueryHabits.prepare("what", key: otherHabitKey)
        let otherKeyHabits = CommandBarQueryHabits.recording(
            [:], preparedQuery: otherPreparedWhat, resultID: "app.test", now: barNow)
        let encodedKeysAreDigests = queryHabits.keys.allSatisfy { key in
            key.count == 24 && key.unicodeScalars.allSatisfy(hexadecimal.contains)
        }
        let keysAreInstallationSpecific = Set(queryHabits.keys)
            .isDisjoint(with: Set(otherKeyHabits.keys))
        let habitsRoundTrip = CommandBarQueryHabits.decode(encodedQueryHabits) == queryHabits
        expect(encodedKeysAreDigests && preparedWhat.keyCount == 4
                && keysAreInstallationSpecific && habitsRoundTrip,
               "query habits round-trip as per-install keyed digests, prepared once per query")
        expect(CommandBarQueryHabits.removing(
                    resultID: "app./Applications/Whatever.app", from: queryHabits).isEmpty,
               "forgetting a result removes its learned query choices")

        var maximumHabitStore: CommandBarQueryHabits.Store = [:]
        for queryIndex in 0..<CommandBarQueryHabits.storedQueryLimit {
            let queryKey = String(format: "%024x", queryIndex)
            var choices: [String: CommandBarUse] = [:]
            for resultIndex in 0..<4 {
                choices["app.\(resultIndex)"] = CommandBarUse(
                    count: resultIndex + 1,
                    lastUsed: barNow + Double(queryIndex * 4 + resultIndex))
            }
            maximumHabitStore[queryKey] = choices
        }
        let maximumHabitPayload = CommandBarQueryHabits.encode(maximumHabitStore)
        var habitDecodeCount = 0
        var habitStoreCache = CommandBarQueryHabitStoreCache()
        habitStoreCache.reload(maximumHabitPayload) { raw in
            habitDecodeCount += 1
            return CommandBarQueryHabits.decode(raw)
        }
        for length in 3...24 {
            let prepared = CommandBarQueryHabits.prepare(
                String("abcdefghijklmnopqrstuvwx".prefix(length)), key: habitKey)
            _ = CommandBarQueryHabits.boost(
                for: "app.0", preparedQuery: prepared,
                store: habitStoreCache.store, now: barNow)
        }
        expect(habitDecodeCount == 1 && habitStoreCache.store.count == 320,
               "a maximum learned-query store is decoded once, not once per keystroke")

        var digestCount = 0
        var preparationCache = CommandBarQueryHabits.PreparationCache()
        var lastPrepared = CommandBarQueryHabits.prepare("", key: habitKey)
        for length in 3...24 {
            lastPrepared = CommandBarQueryHabits.prepare(
                String("abcdefghijklmnopqrstuvwx".prefix(length)),
                key: habitKey,
                cache: &preparationCache) { prefix, _ in
                    digestCount += 1
                    return String(repeating: "0", count: 24 - String(prefix.count).count)
                        + String(prefix.count)
                }
        }
        expect(digestCount == 24 && lastPrepared.keyCount == 24,
               "extending a query hashes only each newly-added prefix")
        _ = CommandBarQueryHabits.prepare(
            "abcdefghijkl", key: habitKey, cache: &preparationCache) { _, _ in
                digestCount += 1
                return "unused"
            }
        expect(digestCount == 24,
               "deleting from a prepared query reuses its matching prefix slice")

        habitStoreCache.forgetAll()
        expect(habitStoreCache.store.isEmpty,
               "forgetting all learned choices clears the decoded store immediately")
        habitStoreCache.record(preparedQuery: preparedWhat,
                               resultID: "action.screenshot", now: barNow)
        expect(!habitStoreCache.store.isEmpty,
               "recording any durable result updates the decoded store immediately")
        habitStoreCache.remove(resultID: "action.screenshot")
        expect(habitStoreCache.store.isEmpty,
               "forgetting one result updates the decoded store immediately")
        habitStoreCache.reload(encodedQueryHabits)
        expect(habitStoreCache.store == queryHabits,
               "reloading preferences replaces the decoded store with persisted learning")

        let persistedHabitKey = Data(repeating: 0x44, count: 32)
        var keyReads: [(OSStatus, Data?)] = [(errSecSuccess, persistedHabitKey)]
        var generatedKeyCount = 0
        var addedKeyCount = 0
        var updatedKeyCount = 0
        func habitKeyStore() -> CommandBarQueryHabitKeyStore {
            CommandBarQueryHabitKeyStore(
                read: { keyReads.removeFirst() },
                randomKey: {
                    generatedKeyCount += 1
                    return persistedHabitKey
                },
                add: { _ in addedKeyCount += 1; return errSecSuccess },
                update: { _ in updatedKeyCount += 1; return errSecSuccess })
        }
        expect(CommandBarQueryHabits.loadInstallationKey(using: habitKeyStore())
                == persistedHabitKey
                && generatedKeyCount == 0 && addedKeyCount == 0 && updatedKeyCount == 0,
               "a valid stored query key is used without mutation")

        keyReads = [(errSecInteractionNotAllowed, nil)]
        expect(CommandBarQueryHabits.loadInstallationKey(using: habitKeyStore()) == nil
                && generatedKeyCount == 0,
               "a transient Keychain read error never creates an ephemeral query key")

        keyReads = [(errSecItemNotFound, nil), (errSecSuccess, persistedHabitKey)]
        expect(CommandBarQueryHabits.loadInstallationKey(using: habitKeyStore())
                == persistedHabitKey && generatedKeyCount == 1 && addedKeyCount == 1,
               "a new query key is published only after successful read-back")

        keyReads = [(errSecItemNotFound, nil), (errSecSuccess, persistedHabitKey)]
        let duplicateStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { Data(repeating: 0x55, count: 32) },
            add: { _ in errSecDuplicateItem },
            update: { _ in errSecInternalError })
        expect(CommandBarQueryHabits.loadInstallationKey(using: duplicateStore)
                == persistedHabitKey,
               "a duplicate-item race uses the other writer's persisted query key")

        keyReads = [(errSecSuccess, Data([0x01]))]
        let failedRepairStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { persistedHabitKey },
            add: { _ in errSecInternalError },
            update: { _ in errSecInteractionNotAllowed })
        expect(CommandBarQueryHabits.loadInstallationKey(using: failedRepairStore) == nil,
               "a malformed query key is not replaced or published when repair fails")

        keyReads = [(errSecSuccess, Data([0x01])), (errSecSuccess, persistedHabitKey)]
        let repairedStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { persistedHabitKey },
            add: { _ in errSecInternalError },
            update: { _ in errSecSuccess })
        expect(CommandBarQueryHabits.loadInstallationKey(using: repairedStore)
                == persistedHabitKey,
               "a repaired query key is published only after successful read-back")

        keyReads = [(errSecItemNotFound, nil)]
        let randomFailureStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { nil },
            add: { _ in errSecSuccess },
            update: { _ in errSecSuccess })
        expect(CommandBarQueryHabits.loadInstallationKey(using: randomFailureStore) == nil,
               "random generation failure leaves query learning without a key")

        keyReads = [(errSecItemNotFound, nil)]
        let addFailureStore = CommandBarQueryHabitKeyStore(
            read: { keyReads.removeFirst() },
            randomKey: { persistedHabitKey },
            add: { _ in errSecInteractionNotAllowed },
            update: { _ in errSecSuccess })
        expect(CommandBarQueryHabits.loadInstallationKey(using: addFailureStore) == nil,
               "a failed query-key insert never publishes its random candidate")

        let loadStarted = DispatchSemaphore(value: 0)
        let letLoadFinish = DispatchSemaphore(value: 0)
        let cache = CommandBarQueryHabitKeyCache(
            queue: DispatchQueue(label: "org.vorssaint.tests.command-bar-query-key")) {
                loadStarted.signal()
                letLoadFinish.wait()
                return persistedHabitKey
            }
        let keyReady = DispatchSemaphore(value: 0)
        cache.warm { keyReady.signal() }
        expect(loadStarted.wait(timeout: .now() + 1) == .success && cache.cachedKey == nil,
               "query-key warm-up never waits on the typing path")
        letLoadFinish.signal()
        expect(keyReady.wait(timeout: .now() + 1) == .success
                && cache.cachedKey == persistedHabitKey,
               "a background query-key load publishes a validated key and announces readiness")

        let removalQueue = DispatchQueue(label: "org.vorssaint.tests.query-key-removal")
        let removalLoadStarted = DispatchSemaphore(value: 0)
        let finishRemovalLoad = DispatchSemaphore(value: 0)
        let removedKeyReady = DispatchSemaphore(value: 0)
        var keyLifecycle: [String] = []
        let removalCache = CommandBarQueryHabitKeyCache(queue: removalQueue) {
            keyLifecycle.append("load started")
            removalLoadStarted.signal()
            finishRemovalLoad.wait()
            keyLifecycle.append("load finished")
            return persistedHabitKey
        }
        removalCache.warm { removedKeyReady.signal() }
        expect(removalLoadStarted.wait(timeout: .now() + 1) == .success,
               "the uninstall race starts with a key load in flight")
        let keyRemoval = removalCache.stopAndRemove { keyLifecycle.append("removed") }
        removalCache.warm { removedKeyReady.signal() }
        finishRemovalLoad.signal()
        expect(keyRemoval.wait(timeout: .now() + 1) == .success,
               "uninstall waits for key deletion after the pending load")
        removalCache.warm { removedKeyReady.signal() }
        removalQueue.sync {}
        expect(keyLifecycle == ["load started", "load finished", "removed"]
                && removalCache.cachedKey == nil
                && removedKeyReady.wait(timeout: .now()) == .timedOut,
               "uninstall suppresses readiness and later warm-ups without recreating the key")

        var retryCount = 0
        let retryCache = CommandBarQueryHabitKeyCache(
            queue: DispatchQueue(label: "org.vorssaint.tests.command-bar-query-key-retry")) {
                retryCount += 1
                return retryCount == 1 ? nil : persistedHabitKey
            }
        retryCache.warm()
        let secondRetryDeadline = Date().addingTimeInterval(1)
        while retryCache.cachedKey == nil && Date() < secondRetryDeadline {
            retryCache.warm()
            Thread.sleep(forTimeInterval: 0.001)
        }
        expect(retryCount == 2 && retryCache.cachedKey == persistedHabitKey,
               "a failed query-key warm-up remains retryable")
        let completedEmoji = CommandBarCompletion.completedQuery(
            current: ":fire", title: "🔥  fire", matchTitle: "fire")
        expect(completedEmoji == ":fire"
                && CommandBarSearch.emojiQuery(from: completedEmoji) == "fire",
               "Tab completion retains emoji scope and the searchable name")
        for categoryQuery in ["fir", ""] {
            let completedCategoryEmoji = CommandBarCompletion.completedQuery(
                current: categoryQuery, title: "🔥  fire", matchTitle: "fire")
            expect(completedCategoryEmoji == "fire"
                    && CommandBarSearch.emojiQuery(from: completedCategoryEmoji) == nil
                    && CommandBarSearch.rankedIndexes(
                        candidates: [CommandBarCandidate(index: 0, title: "fire")],
                        matching: completedCategoryEmoji) == [0],
                   "Tab keeps a selected Emoji category result searchable from a query or browse")
        }
        expect(CommandBarCompletion.completedQuery(
            current: "whts", title: "Whatever", matchTitle: nil) == "Whatever",
               "ordinary Tab completion still uses the selected title")
        let learnedCompletion = CommandBarCompletion.queryForLearning(
            current: "Whatever", beforeCompletion: "whts")
        let retainedCompletion = CommandBarCompletion.retainedOriginal(
            "whts", completedValue: "Whatever", afterChangingTo: "Whatever")
        let editedCompletion = CommandBarCompletion.retainedOriginal(
            "whts", completedValue: "Whatever", afterChangingTo: "Whatever b")
        expect(learnedCompletion == "whts" && retainedCompletion == "whts"
                && editedCompletion == nil,
               "Tab remembers the fuzzy search unless the completed field is edited")

        let learningDefaultsName = "com.vorssaint.tests.command-bar-learning"
        let learningDefaults = UserDefaults(suiteName: learningDefaultsName)!
        learningDefaults.set("usage", forKey: DefaultsKey.commandBarUsage)
        learningDefaults.set("habits", forKey: DefaultsKey.commandBarQueryHabits)
        CommandBarLearning.forgetAll(in: learningDefaults)
        expect(learningDefaults.object(forKey: DefaultsKey.commandBarUsage) == nil
                && learningDefaults.object(forKey: DefaultsKey.commandBarQueryHabits) == nil,
               "forgetting all learned use clears usage and query choices together")
        learningDefaults.removePersistentDomain(forName: learningDefaultsName)

        let barSuggestions = CommandBarUsage.suggestionIDs(
            usage: barUsage,
            available: ["action.screenshot", "action.darkMode", "action.colorPicker", "action.ocr"],
            curated: ["action.colorPicker", "action.gone", "action.ocr"],
            limit: 3)
        expect(barSuggestions == ["action.screenshot", "action.darkMode", "action.colorPicker"],
               "suggestions lead with the most used and fill with curated ones")
        expect(CommandBarUsage.suggestionIDs(usage: [:],
                                             available: ["a", "b"],
                                             curated: ["c", "b", "a"],
                                             limit: 5) == ["b", "a"],
               "curated suggestions skip whatever is unavailable")
    }

    static func runNormalization(expect: (Bool, String) -> Void) {
        let commandBarSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift",
            encoding: .utf8)) ?? ""
        let commandBarCode = commandBarSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // The ranking folds what was typed once and hands the folded letters to
        // every row in the pool. Both readings have to agree, or a name the
        // person gave would rank differently depending on which one asked.
        var foldedMemory = CommandBarQueryMemory()
        expect(foldedMemory.boost(normalizedQuery: "pri", id: "app.primary") == 0,
               "a memory holding nothing is worth nothing for folded letters either")
        foldedMemory.record(query: "Primary", id: "app.primary", step: 1)
        expect(foldedMemory.boost(normalizedQuery: CommandBarSearch.normalized("PRÍ"),
                                  id: "app.primary") > 0
                && foldedMemory.boost(normalizedQuery: CommandBarSearch.normalized("PRÍ"),
                                      id: "app.primary")
                    == foldedMemory.boost(query: "PRÍ", id: "app.primary"),
               "folded letters ask the query memory the same question the raw ones do")
        expect(CommandBarPreferences.aliasHit(
                    "Códex", normalizedQuery: CommandBarSearch.normalized("CÓD")) == .prefix
                && CommandBarPreferences.aliasHit(
                    "Códex", normalizedQuery: CommandBarSearch.normalized("CÓD"))
                    == CommandBarPreferences.aliasHit("Códex", query: "CÓD"),
               "folded letters ask an alias the same question the raw ones do")

        // Both background passes guard on a few fields of a tuple they store
        // whole. Returning before the store would leave every field the guard
        // does not name at the reading it had when the named ones last moved.
        for (pass, marker) in [("refreshStorageAnswer", "cachedBootVolumeSpace = space"),
                               ("refreshSystemAnswers", "cachedMemory = memory")] {
            let parts = (commandBarCode
                .components(separatedBy: "private func \(pass)(").last ?? "")
                .components(separatedBy: "\n    private func ")
            let body = parts.first ?? ""
            expect(parts.count > 1, "\(pass) finds the end of its own body")
            func offset(_ needle: String) -> Int {
                body.range(of: needle)
                    .map { body.distance(from: body.startIndex, to: $0.lowerBound) } ?? -1
            }
            let stored = offset(marker)
            let guarded = offset("guard changed else { return }")
            expect(stored >= 0 && guarded > stored,
                   "\(pass) stores the whole sample before it decides whether the rows changed")
        }
    }
}
