// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// ESPN answers captured on 18 November 2026 and trimmed to what is read,
/// with some unrelated fields left in to show they are ignored.
enum NotchScoresTests {
    static func run(_ suite: TestSuite) {
        guard let fixtures = loadFixtures() else {
            suite.expect(false, "the ESPN fixtures load")
            return
        }
        teamContracts(suite, fixtures)
        tennisContracts(suite, fixtures)
        racingContracts(suite, fixtures)
        leagueContracts(suite, fixtures)
        detailContracts(suite, fixtures)
        moreSportsContracts(suite, fixtures)
        standingsContracts(suite, fixtures)
        choiceContracts(suite, fixtures)
        changeContracts(suite)
        scheduleContracts(suite)
        presentationContracts(suite, fixtures)
        storageContracts(suite)
        catalogContracts(suite)
    }

    private typealias Fixtures = [String: Data]

    private static func loadFixtures() -> Fixtures? {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotchScoresESPN.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var fixtures: Fixtures = [:]
        for (key, value) in root {
            fixtures[key] = try? JSONSerialization.data(withJSONObject: value)
        }
        return fixtures
    }

    private static func follow(_ sport: NotchScoreSport, _ league: String, _ id: String, _ name: String,
                               _ code: String) -> NotchScoreFollow {
        NotchScoreFollow(sport: sport, league: league, espnID: id, name: name, abbreviation: code)
    }

    private static let flamengo = follow(.soccer, "bra.1", "819", "Flamengo", "FLA")
    private static let corinthians = follow(.soccer, "bra.1", "874", "Corinthians", "COR")
    private static let chiefs = follow(.football, "nfl", "12", "Kansas City Chiefs", "KC")
    private static let zverev = follow(.tennis, "atp", "2375", "Alexander Zverev", "Zverev")
    private static let jodar = follow(.tennis, "atp", "12657", "Rafael Jodar", "Jodar")
    private static let luz = follow(.tennis, "atp", "2725", "Orlando Luz", "Luz")
    private static func whole(_ slug: String) -> NotchScoreFollow {
        NotchScoreFollow(league: NotchScoreLeague.catalog.first { $0.slug == slug }!)
    }
    private static let formulaOne = whole("f1")
    private static let brasileirao = whole("bra.1")
    private static let atpTour = whole("atp")

    private static func request(_ sport: NotchScoreSport, _ league: String) -> NotchScoreRequest {
        NotchScoreRequest(url: URL(string: "https://site.api.espn.com/")!, sport: sport, league: league)
    }

    private static func date(_ text: String) -> Date { NotchScoresSupport.date(text)! }

    // MARK: Parsing

    private static func teamContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let board = fixtures["brasileirao"]!
        let games = NotchScoresSupport.games(from: board, request: request(.soccer, "bra.1"), follows: [flamengo]) ?? []
        let game = games.first
        suite.expect(games.count == 1 && game?.id == "soccer/bra.1#401841313" && game?.state == .live
                        && game?.title == "Brasileirão Série A" && game?.followed == ["819"],
                     "a scoreboard yields only the followed team's game, named as the catalog names its league")
        suite.expect(game?.sides.map(\.abbreviation) == ["FLA", "CAP"] && game?.sides.map(\.score) == ["2", "1"]
                        && game?.clock.isEmpty == false && game?.link?.host?.hasSuffix("espn.com") == true,
                     "a soccer game reads home first, with its scores, clock and ESPN's page for it")
        suite.expect(game?.sides.allSatisfy { $0.logo?.host == "a.espncdn.com" } == true
                        && NotchScoresSupport.image("https://a.espncdn.com/i/teamlogos/soccer/500/819.png") != nil
                        && NotchScoresSupport.image("http://a.espncdn.com/x.png") == nil
                        && NotchScoresSupport.image("https://espncdn.com.example.net/x.png") == nil
                        && NotchScoresSupport.image("https://example.net/x.png") == nil,
                     "crests load only from ESPN's image servers over HTTPS")
        let crest = URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/819.png")!
        suite.expect(NotchScoresSupport.crestURLs(crest, dark: true).map(\.absoluteString) == [
                        "https://a.espncdn.com/combiner/i?img=/i/teamlogos/soccer/500-dark/819.png&w=64&h=64",
                        "https://a.espncdn.com/combiner/i?img=/i/teamlogos/soccer/500/819.png&w=64&h=64",
                        crest.absoluteString]
                        && NotchScoresSupport.crestURLs(crest, dark: false).count == 2,
                     "crests come small from ESPN's resizer, the dark-background version first on the island")
        let scheduled = NotchScoresSupport.games(from: board, request: request(.soccer, "bra.1"), follows: [corinthians])?.first
        suite.expect(scheduled?.state == .scheduled && scheduled?.clock == "" && scheduled?.sides.first?.abbreviation == "COR",
                     "a game still to come has no clock of its own: the island writes its local start")
        suite.expect(NotchScoresSupport.games(from: board, request: request(.soccer, "bra.1"), follows: [zverev]) == [],
                     "follows of another sport find nothing in a soccer scoreboard")
        suite.expect(NotchScoresSupport.games(from: Data("<html>".utf8), request: request(.soccer, "bra.1"),
                                              follows: [flamengo]) == nil,
                     "an answer ESPN would not send is told apart from an empty one")

        let fixturesList = NotchScoresSupport.games(from: fixtures["flamengoFixtures"]!, request: request(.soccer, "all"),
                                                    follows: [flamengo]) ?? []
        suite.expect(fixturesList.count == 3 && fixturesList.allSatisfy { $0.league == "bra.1" }
                        && fixturesList[1].sides.map(\.abbreviation) == ["PAL", "FLA"]
                        && fixturesList[1].sides.allSatisfy { $0.score == nil },
                     "a club's fixtures across competitions take each game's own league, and future games no score")
        suite.expect(fixturesList.first?.sides.map(\.score) == ["2", "1"],
                     "a schedule's scores, sent as objects, read as the scoreboard's text scores")
        suite.expect(fixturesList.first?.id == game?.id,
                     "a game listed in fixtures and read on the scoreboard is one game")

        let chiefsGames = NotchScoresSupport.games(from: fixtures["chiefsSchedule"]!, request: request(.football, "nfl"),
                                                   follows: [chiefs]) ?? []
        suite.expect(chiefsGames.count == 2 && chiefsGames.allSatisfy { $0.league == "nfl" }
                        && chiefsGames[0].sides.map(\.abbreviation) == ["KC", "ATL"]
                        && chiefsGames[0].state == .finished && chiefsGames[0].sides.map(\.score) == ["35", "13"]
                        && chiefsGames[1].sides.map(\.abbreviation) == ["ARI", "KC"],
                     "American football reads away first, and a team's schedule keeps its league")

        let postponed = """
        {"events":[{"id":"9","date":"2026-11-18T23:00Z","competitions":[{"status":{"type":{"name":"STATUS_POSTPONED",
        "state":"post","shortDetail":"Postponed"}},"competitors":[{"id":"819","homeAway":"home","score":"0",
        "team":{"id":"819","abbreviation":"FLA","displayName":"Flamengo"}},{"id":"1","homeAway":"away","score":"0",
        "team":{"id":"1","abbreviation":"ABC","displayName":"Other"}}]}]}]}
        """
        let called = NotchScoresSupport.games(from: Data(postponed.utf8), request: request(.soccer, "bra.1"), follows: [flamengo])?.first
        suite.expect(called?.state == .called && called?.clock == "Postponed",
                     "a postponed game is over without a result, and says why")
    }

    private static func tennisContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let board = fixtures["atpFinals"]!
        let match = NotchScoresSupport.games(from: board, request: request(.tennis, "atp"), follows: [zverev])?.first
        suite.expect(match?.id == "tennis/atp#187505" && match?.state == .finished && match?.title == "Nitto ATP Finals"
                        && match?.detail == "Group Stage" && match?.sides.first?.abbreviation == "Zverev",
                     "a followed player's match is found inside the tournament's groupings")
        suite.expect(match.map(NotchScoresSupport.setsText) == "6-4 6-4",
                     "sets read from the followed player's side")
        let reversed = NotchScoresSupport.games(from: board, request: request(.tennis, "atp"), follows: [jodar])?.first
        suite.expect(reversed?.sides.first?.abbreviation == "Jodar" && reversed.map(NotchScoresSupport.setsText) == "4-6 4-6",
                     "the followed player comes first even when ESPN lists them second")
        let doubles = NotchScoresSupport.games(from: board, request: request(.tennis, "atp"), follows: [luz])?.first
        suite.expect(doubles?.id == "tennis/atp#187517" && doubles?.sides.first?.abbreviation == "Luz/Matos"
                        && doubles?.sides.first?.sets.last?.tiebreak == 4 && doubles?.followed == ["2725-2434", "2725"],
                     "a followed player's doubles count, with the pair named by surnames and its match tiebreak")
        suite.expect(doubles.map { NotchScoresSupport.kept([$0.id: $0], follows: [luz], now: $0.start).count } == 1,
                     "a doubles match stays while its followed player does")
    }

    private static func racingContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let mexico = NotchScoresSupport.games(from: fixtures["mexicoGrandPrix"]!, request: request(.racing, "f1"),
                                              follows: [formulaOne]) ?? []
        suite.expect(mexico.map(\.detail) == ["FP1", "Qual", "Race"] && mexico.map(\.isPractice) == [true, false, false]
                        && mexico.first?.sides.map(\.position) == [1, 2, 3, 4],
                     "Formula 1 is followed through its practice, qualifying and races, practice in running order")
        if let practice = mexico.first, let race = mexico.last {
            let text = FeatureStrings.notchScores(.enUS)
            let running = NotchScoreGame(id: practice.id, sport: .racing, league: "f1", title: practice.title,
                                         detail: practice.detail, start: practice.start, state: .live, period: 12,
                                         sides: practice.sides, followed: [])
            let scheduled = NotchScoreGame(id: practice.id, sport: .racing, league: "f1", title: practice.title,
                                           detail: practice.detail, start: practice.start, state: .scheduled,
                                           sides: [], followed: [])
            let racing = NotchScoreGame(id: race.id, sport: .racing, league: "f1", title: race.title, detail: race.detail,
                                        start: race.start, state: .live, period: 12, sides: race.sides, followed: [])
            suite.expect(NotchScoresSupport.change(from: scheduled, to: running) == nil
                            && NotchScoresSupport.change(from: running, to: practice) == nil,
                         "practice never speaks up as it starts or ends")
            suite.expect(NotchScoresSupport.compactText(running, text: text).trailing == "FP1"
                            && NotchScoresSupport.statusText(running, text: text, locale: Locale(identifier: "en_US"), now: Date()) == text.live
                            && text.session("FP2") == "Practice 2"
                            && FeatureStrings.notchScores(.ptBR).session("FP3") == "Treino Livre 3"
                            && text.session("FPX") == "FPX",
                         "practice reads by its session, not a lap count, and is named in the person's language")
            suite.expect(NotchScoresSupport.featured([running, racing], finishedAt: [:], now: Date())?.id == race.id
                            && NotchScoresSupport.featured([running], finishedAt: [:], now: Date())?.id == practice.id,
                         "a live practice takes the closed island only when nothing else is under way")
        }
        let race = mexico.last
        suite.expect(race?.sides.map(\.abbreviation) == ["VER", "HAM", "ANT", "LEC"]
                        && race?.sides.map(\.position) == [1, 2, 3, 4] && race?.followed.isEmpty == true,
                     "drivers run in order, with the three letters timing screens use")
        let winner = race?.sides.first
        let photo = winner?.portrait.map { NotchScoresSupport.crestURLs($0, dark: true) }?.first?.absoluteString ?? ""
        suite.expect(winner?.portrait?.absoluteString == "https://a.espncdn.com/i/headshots/rpm/players/full/\(winner?.id ?? "").png"
                        && race.flatMap(NotchScoresSupport.compactPortrait) == winner?.portrait
                        && photo.contains("scale=crop") && !photo.contains("500-dark")
                        && NotchScoresSupport.portrait(athlete: "12/../x") == nil,
                     "the closed island pictures P1 by ESPN's photo of them, cropped square")
        let future = NotchScoreGame(id: "r", sport: .racing, league: "f1", title: "", start: Date(), state: .scheduled,
                                    sides: race?.sides ?? [], followed: [])
        suite.expect(NotchScoresSupport.compactPortrait(future) == nil
                        && race.map { NotchScoresSupport.crestURLs($0.sides[0].logo!, dark: true) }?.first?.absoluteString
                            .contains("scale=crop") == false,
                     "no one is pictured before a session has an order, and flags are not cropped")
        suite.expect(race?.event == "600057447", "a session keeps its race weekend, which its timing is kept under")
        suite.expect(race.flatMap(NotchScoresSupport.liveryURL)?.absoluteString
                        == "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/600057447/competitions/401839127/competitors?limit=60",
                     "a session's cars are asked for in one list")
        let cars = Data("""
        {"count":3,"items":[\
        {"id":"4665","order":1,"vehicle":{"number":"3","manufacturer":"Red Bull","teamColor":"00327D"}},\
        {"id":"5503","order":3,"vehicle":{"number":"63","manufacturer":"Mercedes","team":"Mercedes-AMG","teamColor":"00D2BE"}},\
        {"id":"9","order":4,"vehicle":{"number":"9","manufacturer":"Nobody","teamColor":"not-a-color"}},\
        {"id":"10","order":5}]}
        """.utf8)
        let liveries = NotchScoresSupport.liveries(from: cars)
        suite.expect(liveries?.count == 2
                        && liveries?["4665"] == NotchScoreLivery(color: ColorValue(red: 0, green: 50.0 / 255, blue: 125.0 / 255),
                                                                 team: "Red Bull", number: "3")
                        && liveries?["5503"]?.team == "Mercedes-AMG" && liveries?["5503"]?.number == "63"
                        && NotchScoresSupport.liveries(from: Data("[]".utf8)) == nil,
                     "each car's team color, team and number are read, and a car without a valid color is left plain")
        let grid = (1...22).map { NotchScoreSide(id: String(5000 + $0), name: "", abbreviation: "", position: $0) }
        var qualifying = NotchScoreGame(id: "racing/f1#401839136", sport: .racing, league: "f1", title: "Las Vegas",
                                        detail: "Qual", start: Date(), state: .live, period: 11, sides: grid, followed: [],
                                        event: "600057449")
        let probes = NotchScoresSupport.segmentProbes(qualifying)
        suite.expect(probes.map(\.part) == [1, 2]
                        && probes.first?.url.absoluteString == "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/"
                            + "600057449/competitions/401839136/competitors/5017/statistics"
                        && probes.last?.url.absoluteString.hasSuffix("/competitors/5011/statistics") == true,
                     "a live qualifying asks after P17, the best out in Q1 of 22 cars, and P11, the best out in Q2")
        let timing = { (q1: Int, q2: Int) -> Data in
            Data("""
            {"splits":{"categories":[{"name":"general","stats":[{"name":"place","value":17.0},\
            {"name":"qual1TimeMS","value":\(q1).0,"displayValue":"1:36.220"},\
            {"name":"qual2TimeMS","value":\(q2).0,"displayValue":"0.000"}]}]}}
            """.utf8)
        }
        suite.expect(NotchScoresSupport.hasQualifyingTime(timing(96220, 0), part: 1) == true
                        && NotchScoresSupport.hasQualifyingTime(timing(96220, 0), part: 2) == false
                        && NotchScoresSupport.hasQualifyingTime(Data("{}".utf8), part: 1) == nil,
                     "a knocked-out driver's time tells that part is over")
        suite.expect(NotchScoresSupport.segment(previous: 0, finished: [1: false, 2: false]) == 1
                        && NotchScoresSupport.segment(previous: 0, finished: [1: true, 2: false]) == 2
                        && NotchScoresSupport.segment(previous: 2, finished: [2: true]) == 3
                        && NotchScoresSupport.segment(previous: 2, finished: [:]) == 2
                        && NotchScoresSupport.segment(previous: 3, finished: [1: false]) == 3,
                     "qualifying moves from Q1 to Q3 and never back, a failed reading keeping where it was")
        let text = FeatureStrings.notchScores(.enUS)
        suite.expect(NotchScoresSupport.compactText(qualifying, text: text).trailing == "QUAL",
                     "a live qualifying not yet placed reads by its short name, not by laps")
        qualifying.segment = 2
        suite.expect(NotchScoresSupport.segmentProbes(qualifying).map(\.part) == [2]
                        && NotchScoresSupport.compactText(qualifying, text: text).trailing == "Q2"
                        && NotchScoresSupport.statusText(qualifying, text: text, locale: Locale(identifier: "en_US"), now: Date()) == "Q2"
                        && NotchScoresSupport.stripText(qualifying, text: text, locale: Locale(identifier: "en_US"), now: Date()).status == "Q2",
                     "the island reads Q2, and only P11 is asked after then")
        qualifying.segment = 3
        suite.expect(NotchScoresSupport.segmentProbes(qualifying).isEmpty, "nothing is asked once Q3 is on")
        let vegas = NotchScoresSupport.games(from: fixtures["lasVegasGrandPrix"]!, request: request(.racing, "f1"),
                                             follows: [formulaOne]) ?? []
        suite.expect(vegas.count == 5 && vegas.allSatisfy { $0.state == .scheduled && $0.sides.isEmpty }
                        && NotchScoresSupport.kept(Dictionary(uniqueKeysWithValues: vegas.map { ($0.id, $0) }),
                                                   follows: [formulaOne], now: vegas[0].start).count == 5,
                     "the coming weekend's sessions are kept before any driver is listed")
        suite.expect(NotchScoresSupport.games(from: fixtures["mexicoGrandPrix"]!, request: request(.racing, "f1"),
                                              follows: [flamengo]) == [],
                     "races are not read for someone who follows no championship")
    }

    private static func leagueContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let round = NotchScoresSupport.games(from: fixtures["brasileirao"]!, request: request(.soccer, "bra.1"),
                                             follows: [brasileirao]) ?? []
        suite.expect(round.count == 3 && round.allSatisfy { $0.followed.isEmpty }
                        && NotchScoresSupport.kept(Dictionary(uniqueKeysWithValues: round.map { ($0.id, $0) }),
                                                   follows: [brasileirao], now: round[0].start).count == 3,
                     "a league followed whole brings every one of its games")
        let mixed = NotchScoresSupport.games(from: fixtures["brasileirao"]!, request: request(.soccer, "bra.1"),
                                             follows: [brasileirao, flamengo]) ?? []
        let ended = mixed.map { game -> NotchScoreGame in
            NotchScoreGame(id: game.id, sport: game.sport, league: game.league, title: game.title, start: game.start,
                           state: game.state == .scheduled ? .scheduled : .live, sides: game.sides, followed: game.followed)
        }
        suite.expect(NotchScoresSupport.featured(ended, finishedAt: [:], now: Date())?.followed == ["819"],
                     "a followed team's game takes the island before the rest of its league")
        suite.expect(NotchScoresSupport.games(from: fixtures["brasileirao"]!, request: request(.soccer, "bra.1"),
                                              follows: [whole("eng.1")]) == [],
                     "another league followed whole brings nothing from this one")
        let tour = NotchScoresSupport.games(from: fixtures["atpFinals"]!, request: request(.tennis, "atp"), follows: [atpTour]) ?? []
        suite.expect(tour.map(\.id) == ["tennis/atp#187505", "tennis/atp#187506"],
                     "a tour followed whole brings its singles, not its doubles")
        let soon = date("2026-11-18T23:40Z"), monthEnd = date("2026-11-27T15:00Z")
        suite.expect(NotchScoresSupport.scoreboardMonths(from: soon) == ["202611"]
                        && NotchScoresSupport.scoreboardMonths(from: monthEnd) == ["202611", "202612"],
                     "a league's games are listed by month, the next one too in a month's last week")
        suite.expect(NotchScoresSupport.discoveryRequests(for: [brasileirao, formulaOne, atpTour, zverev], now: monthEnd)
                        .map(\.url.absoluteString) == [
                            "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard?dates=202611",
                            "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard?dates=202612",
                            "https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard",
                            "https://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard",
                        ],
                     "a whole league asks for its months; a tour serves its players and itself with one request")
        suite.expect(brasileirao.id == "league:soccer/bra.1" && brasileirao.id != flamengo.id
                        && formulaOne.wholeLeague && formulaOne.espnID == "f1",
                     "a league followed whole is a follow of its own")
    }

    private static func detailContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let game = NotchScoresSupport.games(from: fixtures["brasileirao"]!, request: request(.soccer, "bra.1"),
                                            follows: [flamengo])?.first
        suite.expect(game?.moments.map(\.kind) == [.goal, .goal, .yellowCard, .penalty, .yellowCard]
                        && game?.moments.map(\.side) == [1, 0, 1, 0, 0]
                        && game?.moments.map(\.minute) == ["11'", "17'", "24'", "27'", "28'"]
                        && game?.moments.first?.player.isEmpty == false,
                     "goals and cards line up by minute on the side they count for, a penalty told apart")
        suite.expect(game?.stats.map(\.kind) == [.possession, .shots, .shotsOnTarget, .corners, .fouls]
                        && game?.stats.first?.values == ["67.4", "32.6"]
                        && game.map { abs(($0.stats.first?.shares.reduce(0, +) ?? 0) - 1) < 0.001 } == true
                        && game?.venue == "Estadio do Maracana, Rio de Janeiro",
                     "the statistics both teams report are listed in the page's order, with where the game is played")
        let nfl = NotchScoresSupport.games(from: fixtures["nflFinal"]!, request: request(.football, "nfl"),
                                           follows: [whole("nfl")])?.first
        suite.expect(nfl?.sides.map(\.abbreviation) == ["NE", "DET"]
                        && nfl?.sides.map(\.periods) == [["3", "0", "0", "7"], ["7", "14", "7", "7"]]
                        && nfl?.sides.map(\.record) == ["5-5", "7-2"],
                     "American football keeps each quarter's points and each team's record")
        suite.expect(nfl?.leaders.map(\.category) == [.passing, .rushing, .receiving]
                        && nfl?.leaders.first?.player == "Jared Goff" && nfl?.leaders.allSatisfy { $0.side == 1 } == true
                        && nfl?.situation == nil && nfl?.moments.isEmpty == true,
                     "leaders belong to their team, and a finished game has no drive to follow")
        // Synthetic: a drive under way, as ESPN describes one.
        let drive = """
        {"events":[{"id":"7","date":"2026-11-22T18:00Z","competitions":[{"status":{"type":{"state":"in",
        "shortDetail":"Q3 4:12"}},"situation":{"downDistanceText":"3rd & 4 at KC 31","possession":"12",
        "lastPlay":{"text":"Pass complete for 6 yards"},"isRedZone":true},"competitors":[
        {"id":"12","homeAway":"home","score":"17","team":{"id":"12","abbreviation":"KC","displayName":"Chiefs"}},
        {"id":"22","homeAway":"away","score":"14","team":{"id":"22","abbreviation":"ARI","displayName":"Cardinals"}}]}]}]}
        """
        let live = NotchScoresSupport.games(from: Data(drive.utf8), request: request(.football, "nfl"), follows: [chiefs])?.first
        suite.expect(live?.situation == NotchScoreSituation(downDistance: "3rd & 4 at KC 31", possession: 1,
                                                            lastPlay: "Pass complete for 6 yards", redZone: true),
                     "a drive under way says the down, who has the ball and the last play")

        if let game {
            let bare = NotchScoreGame(id: game.id, sport: game.sport, league: game.league, title: game.title,
                                      start: game.start, state: game.state, sides: game.sides, followed: game.followed)
            suite.expect(NotchScoresSupport.merge([game.id: game], with: [bare])[game.id]?.stats == game.stats,
                         "a team's fixtures, which carry no statistics, do not erase the scoreboard's")
            let text = FeatureStrings.notchScores(.enUS)
            let compact = NotchScoresSupport.compactText(game, text: text)
            suite.expect(compact.leading == "2" && compact.trailing == "1" && compact.status.isEmpty
                            && NotchScoresSupport.compactCore(game, text: text) == "2 – 1",
                         "the closed island keeps only the score beside each crest")
        }
        let match = NotchScoresSupport.games(from: fixtures["atpFinals"]!, request: request(.tennis, "atp"), follows: [zverev])?.first
        let race = NotchScoresSupport.games(from: fixtures["mexicoGrandPrix"]!, request: request(.racing, "f1"), follows: [formulaOne])?.last
        let text = FeatureStrings.notchScores(.enUS)
        suite.expect(match.map { NotchScoresSupport.compactText($0, text: text) } == NotchScoreStripText(leading: "6 6", trailing: "4 4", status: "")
                        && race.map { NotchScoresSupport.compactText($0, text: text).trailing } == "Race"
                        && NotchScoresSupport.compactText(Self.game(state: .scheduled, scores: ["0", "0"]), text: text).leading.isEmpty,
                     "a player's games per set, a race's session, and nothing before kickoff")
    }

    private static func moreSportsContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        typealias Support = NotchScoresSupport
        let text = FeatureStrings.notchScores(.enUS)
        func parse(_ key: String, _ sport: NotchScoreSport, _ slug: String) -> [NotchScoreGame] {
            Support.games(from: fixtures[key]!, request: request(sport, slug),
                          follows: [NotchScoreFollow(league: NotchScoreLeague.catalog.first { $0.sport == sport && $0.slug == slug }!)]) ?? []
        }

        let nba = parse("nbaLive", .basketball, "nba").first
        suite.expect(nba?.state == .live && nba?.sides.map(\.abbreviation) == ["MEM", "CLE"]
                        && nba?.sides.map(\.periods) == [["30", "41", "26"], ["37", "35", "24"]] && nba?.regulation == 4
                        && nba?.stats.map(\.kind) == [.fieldGoals, .threePointers, .freeThrows, .rebounds, .assists]
                        && nba?.situation?.lastPlay?.isEmpty == false,
                     "basketball reads away first, by quarter, with shooting, rebounds, assists and the last play")
        suite.expect(nba?.leaders.map(\.category) == [.points, .points, .rebounds, .rebounds, .assists, .assists]
                        && nba?.leaders.map(\.side) == [0, 1, 0, 1, 0, 1],
                     "each team's leaders stand side by side, category by category")
        suite.expect(nba.map { Support.compactCore($0, text: text) } == "97 – 96"
                        && nba.flatMap { Support.compactMarks($0)?.count } == 2,
                     "the closed island shows the score between the two crests")

        let mlb = parse("mlbFinal", .baseball, "mlb").first
        suite.expect(mlb?.sides.map(\.hits) == ["11", "9"] && mlb?.sides.map(\.errors) == ["0", "0"]
                        && mlb?.sides.map(\.periods.count) == [9, 8] && mlb?.regulation == 9
                        && mlb?.leaders.first?.category == .topPerformer,
                     "baseball keeps the line score inning by inning, with hits and errors beside the runs")
        let nhl = parse("nhlLive", .hockey, "nhl").first
        suite.expect(nhl?.stats.map(\.kind) == [.saves, .savePercentage] && nhl?.leaders.first?.category == .goals
                        && nhl?.regulation == 3,
                     "hockey reads by period, with saves and the goal scorers first")

        let race = parse("nascarRace", .racing, "nascar-premier").first
        suite.expect(race?.detail == nil && race?.sides.map(\.position) == [1, 2, 3, 4]
                        && race?.sides.first?.abbreviation == "BLA" && race.flatMap(Support.compactMarks) == nil
                        && race.map { Support.stripText($0, text: text, locale: Locale(identifier: "en_US"), now: Date()).leading } == "P1 BLA",
                     "a NASCAR race reads as one session, its field in order")

        let golf = parse("golfFinal", .golf, "pga").first
        suite.expect(golf?.title == "World Wide Technology Championship" && golf?.state == .finished && golf?.end != nil
                        && golf?.sides.first?.periods == ["-6", "-4", "-4", "-9", "-2"]
                        && golf.map { Support.places($0.sides) } == ["1", "2", "3", "4", "5"]
                        && golf.map { Support.compactCore($0, text: text) } == "-25",
                     "a tournament is its leaderboard, rounds and the leader's score to par")
        if let golf, let end = golf.end {
            let kept = Support.kept([golf.id: golf], follows: [whole("pga")], now: end.addingTimeInterval(3600))
            suite.expect(kept.count == 1, "a four-day tournament's result counts from its last day")
        }
        let field = [-5, -3, -3, -1].enumerated().map { NotchScoreSide(id: "\($0.offset)", name: "", abbreviation: "",
                                                                     score: String($0.element)) }
        suite.expect(Support.places(field) == ["1", "T2", "T2", "4"], "tied golfers share a place, and the next skips it")

        let card = parse("ufcCard", .mma, "ufc").first
        suite.expect(card?.bouts.count == 4 && card?.bouts.first?.division == "Lightweight"
                        && card?.sides.map(\.name) == ["Ciryl Gane", "Josh Hokit"] && card?.sides.first?.record == "15-2-0"
                        && card?.state == .finished && card?.currentBout?.id == card?.bouts.last?.id,
                     "a fight card holds its bouts, the main event last and in the header")
        if let card {
            let main = card.bouts[3]
            let underway = NotchScoreBout(id: main.id, division: main.division,
                                          sides: main.sides.map { NotchScoreSide(id: $0.id, name: $0.name, abbreviation: $0.abbreviation) },
                                          state: .live, round: 5, clock: "2:00", rounds: 5)
            let before = NotchScoreGame(id: card.id, sport: .mma, league: "ufc", title: card.title, start: card.start,
                                        state: .live, sides: card.sides, followed: [], bouts: Array(card.bouts.prefix(3)) + [underway])
            let after = NotchScoreGame(id: card.id, sport: .mma, league: "ufc", title: card.title, start: card.start,
                                       state: .live, sides: card.sides, followed: [], bouts: card.bouts)
            suite.expect(Support.change(from: before, to: after) == .bout(index: 3, side: 0)
                            && Support.compactText(before, text: text).leading == "R5",
                         "a main-card fight speaks up as it is decided; one under way shows its round")
        }

        suite.expect(Support.change(from: game(.basketball, state: .live, scores: ["50", "48"]),
                                    to: game(.basketball, state: .live, scores: ["52", "48"])) == nil
                        && Support.change(from: game(.baseball, state: .live, scores: ["1", "0"]),
                                          to: game(.baseball, state: .live, scores: ["3", "0"])) == .scored(side: 0, kind: .run)
                        && Support.change(from: game(.hockey, state: .live, scores: ["1", "0"]),
                                          to: game(.hockey, state: .live, scores: ["1", "1"])) == .scored(side: 1, kind: .goal),
                     "baskets come too often to announce; runs and hockey goals do not")

        let now = date("2026-11-18T23:40Z")
        let nbaWhole = whole("nba")
        let celtics = NotchScoreFollow(sport: .basketball, league: "nba", espnID: "2", name: "Boston Celtics", abbreviation: "BOS")
        let requests = Support.discoveryRequests(for: [nbaWhole, celtics], now: now).map(\.url.absoluteString)
        suite.expect(requests.count == 8 && requests.first == "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=20261118"
                        && requests[6].hasSuffix("dates=20261124")
                        && requests.last == "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/2/schedule",
                     "a whole league that plays daily is read day by day for the week; a team by its schedule")
        suite.expect(Support.choicesURL(for: NotchScoreLeague.catalog.first { $0.slug == "college-football" }!)?
                        .path.hasSuffix("/college-football/standings") == true
                        && Support.choicesURL(for: NotchScoreLeague.catalog.first { $0.slug == "ufc" }!) == nil,
                     "college leagues are listed by conference; a promotion is followed whole")
        suite.expect(NotchScoreCategory.allCases.map { $0.title(text) } == [
                        "Soccer", "NFL", "College Football", "NBA", "WNBA", "College Basketball", "MLB", "NHL",
                        "Tennis", "Golf", "Racing", "UFC"]
                        && NotchScoreCategory.racing.leagues.map { $0.title(text) } == ["Formula 1", "NASCAR Cup Series"]
                        && NotchScoreCategory.collegeBasketball.leagues.count == 2
                        && NotchScoreCategory.allCases.allSatisfy { !$0.leagues.isEmpty },
                     "the Sport menu names each American league as fans do, and puts both series under Racing")
        suite.expect(NotchScoreLeague.catalog.allSatisfy { league in
                        NotchScoreCategory.allCases.filter { $0.allLeagues.contains(league) }.count == 1
                     } && NotchScoreCategory.containing(sport: .football, league: "college-football") == .collegeFootball,
                     "every league belongs to exactly one choice of the menu")
        let soccer = NotchScoreCategory.soccer.leagues
        suite.expect(NotchScoreRegion.allCases.allSatisfy { region in soccer.contains { $0.region == region } }
                        && NotchScoreRegion.allCases.filter { $0 != .international }
                            .allSatisfy { region in soccer.filter { $0.region == region }.count == 1 }
                        && soccer.filter { $0.region == .international }.map(\.slug)
                            == ["conmebol.libertadores", "conmebol.sudamericana", "uefa.champions", "fifa.friendly"]
                        && soccer.allSatisfy { $0.region != nil },
                     "soccer is browsed by country, each with its top division, and the international cups apart")
        let international = soccer.filter { $0.region == .international }
        suite.expect(international.filter(\.picksTeams).map(\.slug) == ["fifa.friendly"]
                        && international.filter(\.followsWhole).map(\.slug)
                            == ["conmebol.libertadores", "conmebol.sudamericana", "uefa.champions"]
                        && soccer.filter { $0.region != .international }.allSatisfy { $0.picksTeams && $0.followsWhole },
                     "a continental cup is followed whole, its clubs picked in their country; national teams one by one")
        suite.expect(!soccer.contains { $0.slug == "bra.2" || $0.slug == "bra.copa_do_brazil" }
                        && NotchScoreLeague.name(sport: .soccer, slug: "bra.copa_do_brazil") == "Copa do Brasil"
                        && NotchScoreCategory.containing(sport: .soccer, league: "bra.2") == .soccer,
                     "lower divisions and cups leave the menu but keep their names for a club's games")
        let portuguese = FeatureStrings.notchScores(.ptBR)
        let brazilian = Locale(identifier: "pt-BR")
        suite.expect(NotchScoreRegion.brazil.title(portuguese, locale: brazilian) == "Brasil"
                        && NotchScoreRegion.england.title(portuguese, locale: brazilian) == "Inglaterra"
                        && NotchScoreRegion.international.title(portuguese, locale: brazilian) == "Internacional"
                        && NotchScoreRegion.preferred(Locale(identifier: "en_US")) == .unitedStates
                        && NotchScoreRegion.preferred(Locale(identifier: "pt_BR")) == .brazil
                        && NotchScoreRegion.preferred(Locale(identifier: "ja_JP")) == .brazil
                        && NotchScoreLeague.catalog.first { $0.slug == "f1" }?.title(portuguese) == "Fórmula 1",
                     "countries and Formula 1 are named in the person's language; the list opens at their own country")
        let golfLive = NotchScoreGame(id: "golf/pga#1", sport: .golf, league: "pga", title: "", start: now, state: .live,
                                      sides: [], followed: [])
        suite.expect(Support.nextPoll([golfLive], lastDiscovery: now, now: now) == Support.golfInterval
                        && Support.nextPoll([golfLive, game(state: .live)], lastDiscovery: now, now: now) == Support.liveInterval,
                     "a leaderboard alone is read every minute; any game beside it every ten seconds")
        let live = [game(state: .live)]
        suite.expect(Support.nextPoll(live, lastDiscovery: now, now: now, pace: .watching) == 5
                        && Support.nextPoll(live, lastDiscovery: now, now: now, pace: .glancing) == 10
                        && Support.nextPoll(live, lastDiscovery: now, now: now, pace: .saving) == 20
                        && Support.nextPoll([golfLive], lastDiscovery: now, now: now, pace: .watching) == 30
                        && Support.nextPoll([golfLive], lastDiscovery: now, now: now, pace: .saving) == 90,
                     "a game under way is read every 5 seconds with the page open, 10 from the closed island, 20 in Low Power Mode")
        suite.expect(NotchScoreSport.allCases.filter(\.followsWhole) == [.golf, .racing, .mma]
                        && NotchScoreSport.allCases.filter(\.hasTeams) == [.soccer, .football, .basketball, .baseball, .hockey],
                     "teams are picked one by one; tours, series and promotions are followed whole")
        let sample = Support.sample(text: FeatureStrings.notchScores(.ptBR), now: now)
        suite.expect(sample.state == .live && sample.sides.map(\.name) == ["Mandante", "Visitante"]
                        && sample.sides.allSatisfy { $0.logo == nil } && sample.link == nil && sample.venue == nil
                        && !sample.moments.isEmpty && !sample.stats.isEmpty,
                     "the Settings preview's sample game reads in the person's language and fetches nothing")
    }

    private static func standingsContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        typealias Support = NotchScoresSupport
        func side(_ id: String) -> NotchScoreSide { NotchScoreSide(id: id, name: "", abbreviation: "") }
        func upcoming(_ sport: NotchScoreSport, _ league: String, _ ids: [String]) -> NotchScoreGame {
            NotchScoreGame(id: "\(sport.rawValue)/\(league)#1", sport: sport, league: league, title: "", start: Date(),
                           state: .scheduled, sides: ids.map(side), followed: [])
        }

        let table = Support.standings(from: fixtures["brasileiraoStandings"]!, sport: .soccer, league: "bra.1")
        suite.expect(table?.count == 1 && table?.first?.rows.map(\.abbreviation) == ["FLA", "PAL", "CRU", "FLU"]
                        && table?.first?.rows.map(\.place) == [1, 2, 3, 4]
                        && table?.first?.columns == ["gamesplayed", "wins", "ties", "losses", "pointdifferential", "points"]
                        && table?.first?.rows.first?.values == ["35", "24", "7", "4", "+43", "79"]
                        && table?.first?.rows.first?.logo?.host == "a.espncdn.com",
                     "a soccer table goes by rank, with games, results, goal difference and points")
        let ptBR = FeatureStrings.notchScores(.ptBR)
        suite.expect(table?.first?.columns.map { ptBR.standingColumn($0, sport: .soccer) } == ["J", "V", "E", "D", "SG", "Pts"]
                        && ptBR.standingColumn("winpercent", sport: .basketball) == "PCT"
                        && ptBR.standingColumn("wins", sport: .basketball) == "W",
                     "a soccer table is headed in the person's language; American tables in their own letters")

        let nba = Support.standings(from: fixtures["nbaStandings"]!, sport: .basketball, league: "nba") ?? []
        suite.expect(nba.map(\.name) == ["Eastern Conference", "Western Conference"]
                        && nba.first?.rows.map(\.abbreviation) == ["WSH", "CHA", "BKN", "MIL"]
                        && nba.last?.rows.map(\.abbreviation) == ["NO", "LAC", "UTAH", "SAC"]
                        && nba.first?.columns == ["wins", "losses", "winpercent", "gamesbehind"],
                     "American conferences are sorted by seed, whatever order ESPN lists them in")
        suite.expect(Support.standings(nba, for: upcoming(.basketball, "nba", ["15", "17"])).map(\.name) == ["Eastern Conference"]
                        && Support.standings(nba, for: upcoming(.basketball, "nba", ["15", "3"])).count == 2
                        && Support.standings(nba, for: upcoming(.basketball, "nba", ["999", "998"])).isEmpty,
                     "a game shows its teams' tables: one conference, both, or none for a cup without one")
        suite.expect(Support.standingColumns(sport: .football, league: "college-football") == ["vsconf", "total"]
                        && Support.standingColumns(sport: .basketball, league: "womens-college-basketball") == ["vsconf", "total"]
                        && Support.standingColumns(sport: .hockey, league: "nhl") == ["gamesplayed", "wins", "losses", "otlosses", "points"]
                        && Support.standingColumns(sport: .tennis, league: "atp").isEmpty,
                     "college teams read their conference and overall records; hockey its points")
        suite.expect(Support.standingsURL(sport: .soccer, league: "bra.1")?.absoluteString
                        == "https://site.api.espn.com/apis/v2/sports/soccer/bra.1/standings"
                        && Support.standingsURL(sport: .golf, league: "pga") == nil
                        && Support.standingsURL(sport: .soccer, league: "../x") == nil,
                     "only a team league's table is asked for, by its own name")
    }

    private static func choiceContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let league = NotchScoreLeague.catalog.first { $0.slug == "bra.1" }!
        let teams = NotchScoresSupport.choices(from: fixtures["brasileiraoTeams"]!, league: league) ?? []
        suite.expect(teams.map(\.name) == ["Corinthians", "Flamengo", "Palmeiras"]
                        && teams.map(\.abbreviation) == ["COR", "FLA", "PAL"] && teams.allSatisfy { $0.league == "bra.1" },
                     "a league's teams are offered by name, keeping ESPN's IDs and codes")
        suite.expect(teams.allSatisfy { $0.logo?.hasPrefix("https://a.espncdn.com/") == true },
                     "each team offered carries its crest")
        let atp = NotchScoreLeague.catalog.first { $0.slug == "atp" }!
        let ranked = NotchScoresSupport.choices(from: fixtures["atpRankings"]!, league: atp) ?? []
        suite.expect(ranked.map(\.espnID) == ["2375", "3623", "3782"] && ranked.first?.abbreviation == "Zverev",
                     "players are offered in ranking order, named by surname")
        suite.expect(NotchScoresSupport.choicesURL(for: NotchScoreLeague.catalog.first { $0.slug == "f1" }!) == nil,
                     "a championship is followed whole, with no drivers to pick")

        let nflLeague = NotchScoreLeague.catalog.first { $0.slug == "nfl" }!
        let nfl = NotchScoresSupport.choiceList(from: fixtures["nflStandings"]!, league: nflLeague)
        suite.expect(nfl?.conferences.map(\.name) == ["American Football Conference", "National Football Conference"]
                        && nfl?.conferences.map(\.teams.count) == [3, 3]
                        && nfl?.teams.count == 6 && nfl?.teams.first?.name == "Buffalo Bills"
                        && nfl?.teams.allSatisfy { $0.sport == .football && $0.league == "nfl" && $0.logo != nil } == true,
                     "a league's teams come with the conference each plays in")
        suite.expect(nfl.map { list in
                        list.conferences[0].teams.compactMap { id in list.teams.first { $0.id == id }?.name }
                     } == ["Buffalo Bills", "Jacksonville Jaguars", "Kansas City Chiefs"],
                     "a conference lists its teams by name, not by standing")
        let college = NotchScoresSupport.choiceList(from: fixtures["collegeFootballStandings"]!,
                                                    league: NotchScoreLeague.catalog.first { $0.slug == "college-football" }!)
        suite.expect(college?.conferences.map(\.name) == ["Southeastern Conference", "Sun Belt Conference"]
                        && college?.conferences.last?.teams.count == 6,
                     "a conference split in divisions gathers the teams of both")
        suite.expect(NotchScoresSupport.choicesURL(for: nflLeague)?.absoluteString
                        == "https://site.api.espn.com/apis/v2/sports/football/nfl/standings"
                        && NotchScoresSupport.choicesURL(for: NotchScoreLeague.catalog.first { $0.slug == "bra.1" }!)?
                            .absoluteString == "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/teams",
                     "American leagues are picked from their standings; soccer leagues from their teams")
        suite.expect(NotchScoresSupport.matches(teams[1], query: "flamen") && NotchScoresSupport.matches(teams[1], query: "fla")
                        && NotchScoresSupport.matches(follow(.soccer, "bra.1", "1", "São Paulo", "SAO"), query: "sao paulo")
                        && !NotchScoresSupport.matches(teams[1], query: "pal"),
                     "search matches names and codes, ignoring case and accents")
    }

    // MARK: Changes

    private static func game(_ sport: NotchScoreSport = .soccer, state: NotchScoreState, scores: [String] = ["0", "0"],
                             sets: [[(Int, Bool)]] = [[], []], start: Date = Date(timeIntervalSince1970: 1_800_000_000),
                             id: String = "soccer/bra.1#1", followed: Set<String> = ["a"]) -> NotchScoreGame {
        let sides = ["a", "b"].enumerated().map { index, side in
            NotchScoreSide(id: side, name: side.uppercased(), abbreviation: side.uppercased(), score: scores[index],
                           sets: sets[index].map { NotchScoreSet(games: $0.0, tiebreak: nil, won: $0.1) })
        }
        return NotchScoreGame(id: id, sport: sport, league: sport == .tennis ? "atp" : "bra.1", title: "T",
                              start: start, state: state, sides: sides, followed: followed)
    }

    private static func changeContracts(_ suite: TestSuite) {
        typealias Support = NotchScoresSupport
        suite.expect(Support.change(from: game(state: .scheduled), to: game(state: .live)) == .started
                        && Support.change(from: game(state: .live), to: game(state: .finished)) == .finished
                        && Support.change(from: game(state: .finished), to: game(state: .finished)) == nil,
                     "a game speaks up as it starts and as it ends, once")
        suite.expect(Support.change(from: game(state: .live, scores: ["1", "1"]), to: game(state: .live, scores: ["1", "2"]))
                        == .scored(side: 1, kind: .goal)
                        && Support.change(from: game(state: .live, scores: ["1", "1"]), to: game(state: .live, scores: ["1", "1"])) == nil
                        && Support.change(from: game(state: .live, scores: ["2", "1"]), to: game(state: .live, scores: ["1", "1"])) == nil,
                     "a goal names who scored; an unchanged or overturned score says nothing")
        func football(_ before: String, _ after: String) -> NotchScoreChange? {
            Support.change(from: game(.football, state: .live, scores: [before, "0"]),
                           to: game(.football, state: .live, scores: [after, "0"]))
        }
        suite.expect(football("0", "6") == .scored(side: 0, kind: .touchdown) && football("0", "7") == .scored(side: 0, kind: .touchdown)
                        && football("7", "10") == .scored(side: 0, kind: .fieldGoal)
                        && football("10", "12") == .scored(side: 0, kind: .safety)
                        && football("6", "7") == nil,
                     "American football names the score, and the point after a touchdown stays quiet")
        let before = game(.tennis, state: .live, sets: [[(6, true), (2, false)], [(4, false), (5, false)]], id: "tennis/atp#1")
        let after = game(.tennis, state: .live, sets: [[(6, true), (4, false)], [(4, false), (6, true)]], id: "tennis/atp#1")
        suite.expect(Support.change(from: before, to: after) == .set(side: 1) && Support.change(from: before, to: before) == nil,
                     "tennis speaks up when a set is won")
    }

    // MARK: Schedule

    private static func scheduleContracts(_ suite: TestSuite) {
        typealias Support = NotchScoresSupport
        suite.expect(Support.scoreboardDay(for: date("2026-11-19T00:30Z")) == "20261118"
                        && Support.scoreboardDay(for: date("2026-11-19T12:00Z")) == "20261119",
                     "a scoreboard's day is ESPN's, in US Eastern time")
        suite.expect(Support.date("2026-11-18T22:30Z") != nil && Support.date("2026-11-18T22:30:00Z") != nil
                        && Support.date("yesterday") == nil,
                     "ESPN's times read to the minute or to the second")

        let now = date("2026-11-18T23:40Z")
        let live = game(state: .live, start: date("2026-11-18T23:30Z"), id: "soccer/bra.1#live")
        let soon = game(state: .scheduled, start: date("2026-11-18T23:45Z"), id: "soccer/bra.1#soon")
        let later = game(state: .scheduled, start: date("2026-11-19T02:00Z"), id: "soccer/bra.1#later")
        let set = game(.tennis, state: .live, start: date("2026-11-18T20:00Z"), id: "tennis/atp#1")
        let boards = Support.dueScoreboards([later, soon, live, set], now: now)
        suite.expect(boards == [NotchScoreboard(sport: .tennis, league: "atp", day: nil),
                                NotchScoreboard(sport: .soccer, league: "bra.1", day: "20261118")],
                     "games under way or about to start share their league's scoreboard; a tour's has no day")
        suite.expect(Support.request(for: boards[1])?.url.absoluteString
                        == "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard?dates=20261118",
                     "a day's scoreboard is asked for by its day")
        suite.expect(Support.nextPoll([live, later], lastDiscovery: now, now: now) == Support.liveInterval
                        && Support.nextPoll([soon], lastDiscovery: now, now: now) == Support.startingInterval,
                     "a game under way is read every 20 seconds, one starting every 30")
        let wait = Support.nextPoll([later], lastDiscovery: now, now: now)
        suite.expect(abs(wait - (later.start.timeIntervalSince(now) - Support.leadTime)) < 1,
                     "with nothing on, the next reading waits until shortly before the next game")
        suite.expect(Support.nextPoll([], lastDiscovery: now.addingTimeInterval(-Support.discoveryInterval + 60), now: now) == 60
                        && Support.discoveryIsDue(lastDiscovery: nil, now: now)
                        && !Support.discoveryIsDue(lastDiscovery: now.addingTimeInterval(-60), now: now),
                     "fixtures are listed again every few hours")

        let finished = game(state: .finished, start: date("2026-11-18T21:00Z"), id: "soccer/bra.1#live")
        let merged = Support.merge(["soccer/bra.1#live": finished], with: [live])
        suite.expect(merged["soccer/bra.1#live"]?.state == .finished
                        && Support.merge(["soccer/bra.1#live": live], with: [finished])["soccer/bra.1#live"]?.state == .finished,
                     "a game moves forward only: a late listing never reopens a result")
        let stale = game(state: .finished, start: date("2026-11-17T01:00Z"), id: "soccer/bra.1#stale")
        let far = game(state: .scheduled, start: date("2026-12-05T20:00Z"), id: "soccer/bra.1#far")
        let other = game(state: .live, start: date("2026-11-18T23:00Z"), id: "soccer/bra.1#other", followed: ["z"])
        let follows = [follow(.soccer, "bra.1", "a", "A", "A")]
        let kept = Support.kept(Dictionary(uniqueKeysWithValues: [live, soon, stale, far, other].map { ($0.id, $0) }),
                                follows: follows, now: now)
        suite.expect(Set(kept.keys) == ["soccer/bra.1#live", "soccer/bra.1#soon"],
                     "old results, games beyond the week and games of someone no longer followed are let go")

        let requests = Support.discoveryRequests(for: [flamengo, chiefs, zverev, jodar, formulaOne])
        suite.expect(requests.map(\.url.absoluteString) == [
            "https://site.api.espn.com/apis/site/v2/sports/soccer/all/teams/819/schedule?fixture=true",
            "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule",
            "https://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard",
            "https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard",
        ], "a club's fixtures span its competitions, and one tour's scoreboard serves all its players")
    }

    // MARK: Presentation

    private static func presentationContracts(_ suite: TestSuite, _ fixtures: Fixtures) {
        let text = FeatureStrings.notchScores(.enUS)
        let locale = Locale(identifier: "en_US")
        let now = date("2026-11-18T23:40Z")
        let live = NotchScoresSupport.games(from: fixtures["brasileirao"]!, request: request(.soccer, "bra.1"), follows: [flamengo])!.first!
        let strip = NotchScoresSupport.stripText(live, text: text, locale: locale, now: now)
        suite.expect(strip.leading == "FLA 2" && strip.trailing == "1 CAP" && strip.status == live.clock
                        && NotchScoresSupport.capsuleText(strip, sport: .soccer) == "FLA 2 – 1 CAP · " + live.clock,
                     "each side and its score take a wing beside the camera, the clock after them")
        let race = NotchScoresSupport.games(from: fixtures["mexicoGrandPrix"]!, request: request(.racing, "f1"), follows: [formulaOne])!.last!
        let raceStrip = NotchScoresSupport.stripText(race, text: text, locale: locale, now: now)
        suite.expect(raceStrip.leading == "P1 VER" && raceStrip.trailing == "Race"
                        && FeatureStrings.notchScores(.ptBR).session("Race") == "Corrida",
                     "a race shows its leader and the session, named in the person's language")
        let match = NotchScoresSupport.games(from: fixtures["atpFinals"]!, request: request(.tennis, "atp"), follows: [zverev])!.first!
        let matchStrip = NotchScoresSupport.stripText(match, text: text, locale: locale, now: now)
        suite.expect(matchStrip.leading == "Zverev" && matchStrip.trailing == "6-4 6-4" && matchStrip.status == text.final,
                     "a player's name and the sets, then the result")
        let kickoff = game(state: .scheduled, scores: ["0", "0"], start: now.addingTimeInterval(600))
        let kickoffStrip = NotchScoresSupport.stripText(kickoff, text: text, locale: locale, now: now)
        suite.expect(kickoffStrip.leading == "A" && kickoffStrip.trailing == "B",
                     "the 0–0 a scoreboard lists before kickoff is not shown as a score")
        let upcoming = game(.tennis, state: .scheduled, start: now.addingTimeInterval(600), id: "tennis/atp#2")
        let upcomingStrip = NotchScoresSupport.stripText(upcoming, text: text, locale: locale, now: now)
        suite.expect(upcomingStrip.trailing == "B"
                        && NotchScoresSupport.capsuleText(upcomingStrip, sport: .tennis).hasPrefix("A – B · "),
                     "a match still to come names the opponent where its sets will be")

        let ended = game(state: .finished, id: "soccer/bra.1#ended")
        suite.expect(NotchScoresSupport.featured([ended, live], finishedAt: [:], now: now)?.id == live.id
                        && NotchScoresSupport.featured([ended], finishedAt: [ended.id: now.addingTimeInterval(-60)], now: now)?.id == ended.id
                        && NotchScoresSupport.featured([ended], finishedAt: [ended.id: now.addingTimeInterval(-NotchScoresSupport.finalHold - 1)], now: now) == nil
                        && NotchScoresSupport.featured([ended], finishedAt: [:], now: now) == nil,
                     "the island shows a game under way, or one that just ended, for a while")
        let calendar = Calendar(identifier: .gregorian)
        let today = NotchScoresSupport.startText(now.addingTimeInterval(600), locale: locale, now: now, calendar: calendar)
        let later = NotchScoresSupport.startText(now.addingTimeInterval(3 * 86400), locale: locale, now: now, calendar: calendar)
        suite.expect(!today.isEmpty && later.count > today.count,
                     "a start today is its time; later in the week it adds the day")
    }

    // MARK: Storage

    private static func storageContracts(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "com.vorssaint.tests.notch-scores")!
        defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-scores")
        defer { defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-scores") }
        suite.expect(NotchScoresSupport.follows(in: defaults).isEmpty, "nobody is followed at first")
        NotchScoresSupport.save([flamengo, zverev, flamengo], in: defaults)
        suite.expect(NotchScoresSupport.follows(in: defaults) == [flamengo, zverev],
                     "follows survive a relaunch, once each")
        let unsafe = follow(.soccer, "bra.1", "../../x", "X", "X")
        NotchScoresSupport.save([unsafe, chiefs], in: defaults)
        suite.expect(NotchScoresSupport.follows(in: defaults) == [chiefs],
                     "an ID that is not ESPN's shape never reaches a request")
        suite.expect(NotchScoresSupport.follows(stored: "not json").isEmpty, "a damaged list reads as empty")
        let earlier = #"[{"sport":"soccer","league":"bra.1","espnID":"819","name":"Flamengo","abbreviation":"FLA"},"#
            + #"{"sport":"racing","league":"f1","espnID":"868","name":"Lewis Hamilton","abbreviation":"HAM"},"#
            + #"{"sport":"racing","league":"f1","espnID":"5829","name":"Kimi Antonelli","abbreviation":"ANT"}]"#
        let migrated = NotchScoresSupport.follows(stored: earlier)
        suite.expect(migrated.map(\.id) == ["soccer:819", "league:racing/f1"] && migrated[0].logo == nil && !migrated[0].wholeLeague,
                     "follows saved before whole leagues still read, and followed drivers become the championship")
        NotchScoresSupport.save([brasileirao, flamengo], in: defaults)
        suite.expect(NotchScoresSupport.follows(in: defaults) == [brasileirao, flamengo],
                     "a league followed whole survives a relaunch beside a team")
        NotchScoresSupport.save([], in: defaults)
        suite.expect(defaults.string(forKey: DefaultsKey.notchScoresFollows) == "", "an empty list is stored empty")
    }

    private static func catalogContracts(_ suite: TestSuite) {
        suite.expect(NotchScoreSport.allCases.allSatisfy { !NotchScoreLeague.leagues(for: $0).isEmpty }
                        && Set(NotchScoreLeague.catalog.map(\.id)).count == NotchScoreLeague.catalog.count
                        && NotchScoreLeague.catalog.allSatisfy { NotchScoresSupport.isValidID($0.slug) },
                     "every sport has a league to choose from, and each league is listed once")
        suite.expect(NotchScoreLeague.catalog.contains { $0.slug == "fifa.friendly" && $0.name == nil }
                        && FeatureStrings.notchScores(.ptBR).nationalTeams == "Seleções",
                     "national teams are named in the person's language")
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let text = FeatureStrings.notchScores(language)
            return [text.title, text.description, text.summary, text.soccer, text.final, text.goal, text.source]
                .allSatisfy { !$0.isEmpty } && text.lapFormat.contains("%@")
                && text.lap(42).contains("42") && NotchScoreSport.allCases.allSatisfy { !text.sport($0).isEmpty }
        }, "every language names the section, its sports and its notices")
        suite.expect(NotchSupport.compactActivities(timer: false, downloads: false, agents: true, scores: true,
                                                    calendar: true, music: true) == [.agents, .scores, .calendar, .music],
                     "a game under way comes after agents and before an upcoming event and music")
        suite.expect(NotchEvent.score.preferenceKey == DefaultsKey.notchScoresAlerts && NotchEvent.score.priority == 1,
                     "score notices follow their own switch and give way to volume and timers")
    }
}
