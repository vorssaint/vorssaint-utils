// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// MARK: - What can be followed

enum NotchScoreSport: String, CaseIterable, Codable, Identifiable {
    case soccer, football, basketball, baseball, hockey, tennis, golf, racing, mma

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .soccer: return "soccerball"
        case .football: return "football.fill"
        case .basketball: return "basketball.fill"
        case .baseball: return "baseball.fill"
        case .hockey: return "hockey.puck.fill"
        case .tennis: return "tennisball.fill"
        case .golf: return "figure.golf"
        case .racing: return "flag.checkered"
        case .mma: return "figure.martial.arts"
        }
    }

    /// Two teams meet, each with a crest and a score.
    var hasTeams: Bool {
        switch self {
        case .soccer, .football, .basketball, .baseball, .hockey: return true
        case .tennis, .golf, .racing, .mma: return false
        }
    }

    /// A tour's or a series' scoreboard holds its current event, with no day to ask for.
    var readsCurrentEvent: Bool { !hasTeams }

    /// Followed as a whole: a race, a tournament or a fight card is the news,
    /// not one driver, golfer or fighter.
    var followsWhole: Bool { self == .racing || self == .golf || self == .mma }

    /// A field rather than two sides: drivers and golfers in order.
    var isField: Bool { self == .racing || self == .golf }
}

/// Where a soccer competition is played: a country's top division, or the
/// continental cups and national teams, which belong to none.
enum NotchScoreRegion: String, CaseIterable, Identifiable {
    case brazil, england, spain, italy, germany, france, portugal, unitedStates, international

    var id: String { rawValue }

    /// The country's name in the person's language, as the system names
    /// it. England is a nation within a country the system does not name
    /// apart, so the strings do.
    func title(_ text: NotchScoresStrings, locale: Locale) -> String {
        let code: String
        switch self {
        case .brazil: code = "BR"
        case .england: return text.england
        case .spain: code = "ES"
        case .italy: code = "IT"
        case .germany: code = "DE"
        case .france: code = "FR"
        case .portugal: code = "PT"
        case .unitedStates: code = "US"
        case .international: return text.international
        }
        return locale.localizedString(forRegionCode: code) ?? code
    }

    /// The person's own country when its league is offered, so the list
    /// opens where they most likely look; otherwise Brazil's.
    static func preferred(_ locale: Locale = .current) -> NotchScoreRegion {
        switch locale.region?.identifier {
        case "GB": return .england
        case "ES": return .spain
        case "IT": return .italy
        case "DE": return .germany
        case "FR": return .france
        case "PT": return .portugal
        case "US": return .unitedStates
        default: return .brazil
        }
    }
}

/// A competition the picker browses. ESPN identifies it by sport and slug.
struct NotchScoreLeague: Hashable, Identifiable {
    let sport: NotchScoreSport
    let slug: String
    /// Competitions keep their own names in every language. The national
    /// teams are a list rather than a competition, and Formula 1 is
    /// written in each language, so the strings name those two.
    let name: String?
    /// A soccer competition's country, or the international ones.
    var region: NotchScoreRegion? = nil
    /// Offered in the picker. A lower division or a cup is still named
    /// when a followed club plays in it, and an earlier follow still reads.
    var listed = true
    /// Lists its teams to pick from. A continental cup's clubs are picked
    /// in their own country, so the cup is only followed whole.
    var picksTeams = true
    /// Can be followed whole. The national teams are a list, not a
    /// competition: all of them would be every friendly in the world.
    var followsWhole = true

    var id: String { sport.rawValue + "/" + slug }

    func title(_ text: NotchScoresStrings) -> String {
        if let name { return name }
        return slug == "f1" ? text.racing : text.nationalTeams
    }

    static let catalog: [NotchScoreLeague] = [
        // A country's top division; a club followed there brings its cup
        // and continental games too, as its fixtures span them all.
        NotchScoreLeague(sport: .soccer, slug: "bra.1", name: "Brasileirão Série A", region: .brazil),
        NotchScoreLeague(sport: .soccer, slug: "bra.2", name: "Brasileirão Série B", region: .brazil, listed: false),
        NotchScoreLeague(sport: .soccer, slug: "bra.copa_do_brazil", name: "Copa do Brasil", region: .brazil, listed: false),
        NotchScoreLeague(sport: .soccer, slug: "eng.1", name: "Premier League", region: .england),
        NotchScoreLeague(sport: .soccer, slug: "esp.1", name: "LaLiga", region: .spain),
        NotchScoreLeague(sport: .soccer, slug: "ita.1", name: "Serie A", region: .italy),
        NotchScoreLeague(sport: .soccer, slug: "ger.1", name: "Bundesliga", region: .germany),
        NotchScoreLeague(sport: .soccer, slug: "fra.1", name: "Ligue 1", region: .france),
        NotchScoreLeague(sport: .soccer, slug: "por.1", name: "Primeira Liga", region: .portugal),
        NotchScoreLeague(sport: .soccer, slug: "usa.1", name: "MLS", region: .unitedStates),
        NotchScoreLeague(sport: .soccer, slug: "conmebol.libertadores", name: "CONMEBOL Libertadores",
                         region: .international, picksTeams: false),
        NotchScoreLeague(sport: .soccer, slug: "conmebol.sudamericana", name: "CONMEBOL Sudamericana",
                         region: .international, picksTeams: false),
        NotchScoreLeague(sport: .soccer, slug: "uefa.champions", name: "UEFA Champions League",
                         region: .international, picksTeams: false),
        // Friendlies list nearly every national side, and a national team's
        // fixtures are found across all its competitions, as a club's are.
        NotchScoreLeague(sport: .soccer, slug: "fifa.friendly", name: nil, region: .international, followsWhole: false),
        NotchScoreLeague(sport: .football, slug: "nfl", name: "NFL"),
        NotchScoreLeague(sport: .football, slug: "college-football", name: "College Football"),
        NotchScoreLeague(sport: .basketball, slug: "nba", name: "NBA"),
        NotchScoreLeague(sport: .basketball, slug: "wnba", name: "WNBA"),
        NotchScoreLeague(sport: .basketball, slug: "mens-college-basketball", name: "NCAA Men’s Basketball"),
        NotchScoreLeague(sport: .basketball, slug: "womens-college-basketball", name: "NCAA Women’s Basketball"),
        NotchScoreLeague(sport: .baseball, slug: "mlb", name: "MLB"),
        NotchScoreLeague(sport: .hockey, slug: "nhl", name: "NHL"),
        NotchScoreLeague(sport: .tennis, slug: "atp", name: "ATP"),
        NotchScoreLeague(sport: .tennis, slug: "wta", name: "WTA"),
        NotchScoreLeague(sport: .golf, slug: "pga", name: "PGA Tour"),
        NotchScoreLeague(sport: .golf, slug: "lpga", name: "LPGA Tour"),
        NotchScoreLeague(sport: .racing, slug: "f1", name: nil),
        NotchScoreLeague(sport: .racing, slug: "nascar-premier", name: "NASCAR Cup Series"),
        NotchScoreLeague(sport: .mma, slug: "ufc", name: "UFC"),
    ]

    static func leagues(for sport: NotchScoreSport) -> [NotchScoreLeague] {
        catalog.filter { $0.sport == sport }
    }

    /// The catalog's name for a competition ESPN names in English.
    static func name(sport: NotchScoreSport, slug: String) -> String? {
        catalog.first { $0.sport == sport && $0.slug == slug }?.name
    }
}

/// What the Sport menu lists. Each American league is its own choice, as
/// fans name them, and a choice may hold several leagues of one kind.
enum NotchScoreCategory: String, CaseIterable, Identifiable {
    case soccer, nfl, collegeFootball, nba, wnba, collegeBasketball, mlb, nhl, tennis, golf, racing, ufc

    var id: String { rawValue }

    var sport: NotchScoreSport {
        switch self {
        case .soccer: return .soccer
        case .nfl, .collegeFootball: return .football
        case .nba, .wnba, .collegeBasketball: return .basketball
        case .mlb: return .baseball
        case .nhl: return .hockey
        case .tennis: return .tennis
        case .golf: return .golf
        case .racing: return .racing
        case .ufc: return .mma
        }
    }

    private var slugs: [String]? {
        switch self {
        case .soccer, .tennis, .golf, .racing: return nil
        case .nfl: return ["nfl"]
        case .collegeFootball: return ["college-football"]
        case .nba: return ["nba"]
        case .wnba: return ["wnba"]
        case .collegeBasketball: return ["mens-college-basketball", "womens-college-basketball"]
        case .mlb: return ["mlb"]
        case .nhl: return ["nhl"]
        case .ufc: return ["ufc"]
        }
    }

    /// Every league it holds, offered or not, so an earlier follow still
    /// finds its place.
    var allLeagues: [NotchScoreLeague] {
        let all = NotchScoreLeague.leagues(for: sport)
        guard let slugs else { return all }
        return slugs.compactMap { slug in all.first { $0.slug == slug } }
    }

    /// The leagues the picker offers.
    var leagues: [NotchScoreLeague] { allLeagues.filter(\.listed) }

    /// Soccer is browsed country by country.
    var browsesByRegion: Bool { self == .soccer }

    var symbol: String { sport.symbol }

    /// Leagues name themselves; sports and college levels are translated.
    func title(_ text: NotchScoresStrings) -> String {
        switch self {
        case .soccer: return text.soccer
        case .tennis: return text.tennis
        case .golf: return text.golf
        case .collegeFootball: return text.collegeFootball
        case .collegeBasketball: return text.collegeBasketball
        case .racing: return text.motorsport
        case .nfl: return "NFL"
        case .nba: return "NBA"
        case .wnba: return "WNBA"
        case .mlb: return "MLB"
        case .nhl: return "NHL"
        case .ufc: return "UFC"
        }
    }

    static func containing(sport: NotchScoreSport, league: String) -> NotchScoreCategory? {
        allCases.first { $0.sport == sport && $0.allLeagues.contains { $0.slug == league } }
    }
}

/// A conference, league or division's teams, so a long list is browsed in parts.
struct NotchScoreConference: Hashable, Identifiable {
    let name: String
    let teams: [String]

    var id: String { name }
}

/// One team's line in a table.
struct NotchScoreStandingRow: Hashable, Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    let logo: URL?
    /// Its place, as the league ranks or seeds it.
    let place: Int
    /// One reading per column of its table.
    let values: [String]
}

/// A league's table, or one conference's, group's or division's.
struct NotchScoreStandingGroup: Hashable, Identifiable {
    let name: String
    /// ESPN's names for the columns, which the page heads by sport.
    let columns: [String]
    let rows: [NotchScoreStandingRow]

    var id: String { name }
}

/// Who can be followed in a league, and the conferences they play in.
struct NotchScoreChoiceList: Equatable {
    let teams: [NotchScoreFollow]
    var conferences: [NotchScoreConference] = []
}

/// A team or an athlete the person follows, as ESPN identifies them.
struct NotchScoreFollow: Codable, Hashable, Identifiable {
    let sport: NotchScoreSport
    /// The league it was chosen from. A soccer team's games are found in
    /// every competition it plays; an athlete's in this tour.
    let league: String
    /// The team's or athlete's; a whole league's is its slug.
    let espnID: String
    let name: String
    let abbreviation: String
    /// A team's crest or a player's flag, for the lists in Settings.
    var logo: String? = nil
    /// Every game of `league`, rather than one team's or athlete's.
    var wholeLeague = false

    init(sport: NotchScoreSport, league: String, espnID: String, name: String, abbreviation: String,
         logo: String? = nil, wholeLeague: Bool = false) {
        self.sport = sport
        self.league = league
        self.espnID = espnID
        self.name = name
        self.abbreviation = abbreviation
        self.logo = logo
        self.wholeLeague = wholeLeague
    }

    /// All of a league's games.
    init(league: NotchScoreLeague) {
        self.init(sport: league.sport, league: league.slug, espnID: league.slug, name: league.name ?? league.slug,
                  abbreviation: league.name ?? league.slug, wholeLeague: true)
    }

    private enum CodingKeys: String, CodingKey { case sport, league, espnID, name, abbreviation, logo, wholeLeague }

    /// Follows saved before crests and whole leagues read as they were.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sport = try container.decode(NotchScoreSport.self, forKey: .sport)
        league = try container.decode(String.self, forKey: .league)
        espnID = try container.decode(String.self, forKey: .espnID)
        name = try container.decode(String.self, forKey: .name)
        abbreviation = try container.decode(String.self, forKey: .abbreviation)
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        wholeLeague = try container.decodeIfPresent(Bool.self, forKey: .wholeLeague) ?? false
    }

    /// Soccer teams keep one ID across competitions, so a club chosen from
    /// two leagues is one follow.
    var id: String { wholeLeague ? "league:\(sport.rawValue)/\(league)" : sport.rawValue + ":" + espnID }

    /// The key a game of this league is kept by.
    var leagueKey: String { sport.rawValue + "/" + league }
}

// MARK: - Games

enum NotchScoreState: Equatable {
    case scheduled, live, finished
    /// Postponed, suspended or canceled: over without a result.
    case called

    /// A game only moves forward: a late reading never takes it back.
    var rank: Int {
        switch self {
        case .scheduled: return 0
        case .live: return 1
        case .finished, .called: return 2
        }
    }
}

struct NotchScoreSet: Hashable {
    let games: Int
    let tiebreak: Int?
    let won: Bool
}

struct NotchScoreSide: Hashable, Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    var score: String? = nil
    var sets: [NotchScoreSet] = []
    /// A driver's place in the session.
    var position: Int? = nil
    var winner = false
    var logo: URL? = nil
    /// A driver's photo, which ESPN keeps by athlete though its scoreboard
    /// names only the flag.
    var portrait: URL? = nil
    /// The athletes a doubles pair is made of, so either one followed counts.
    var members: [String] = []
    /// Points in each quarter, half, period or inning.
    var periods: [String] = []
    /// The season's record, such as 7-2, or a fighter's 20-1-0.
    var record: String? = nil
    /// A baseball team's hits and errors, beside its runs.
    var hits: String? = nil
    var errors: String? = nil
    /// Holes a golfer has played in the current round.
    var thru: Int? = nil

    var setsWon: Int { sets.filter(\.won).count }
}

/// Team statistics a scoreboard carries, in the order the page lists them.
enum NotchScoreStatKind: String, CaseIterable {
    case possession = "possessionPct"
    case shots = "totalShots"
    case shotsOnTarget = "shotsOnTarget"
    case corners = "wonCorners"
    case fouls = "foulsCommitted"
    case offsides
    case saves
    case fieldGoals = "fieldGoalPct"
    case threePointers = "threePointPct"
    case freeThrows = "freeThrowPct"
    case rebounds
    case assists
    case savePercentage = "savePct"

    /// What each sport's scoreboard reports for both teams.
    static func kinds(for sport: NotchScoreSport) -> [NotchScoreStatKind] {
        switch sport {
        case .soccer: return [.possession, .shots, .shotsOnTarget, .corners, .fouls, .offsides, .saves]
        case .basketball: return [.fieldGoals, .threePointers, .freeThrows, .rebounds, .assists]
        case .hockey: return [.saves, .savePercentage]
        case .football, .baseball, .tennis, .golf, .racing, .mma: return []
        }
    }

    /// Shares written as percentages.
    var isPercentage: Bool { [.possession, .fieldGoals, .threePointers, .freeThrows].contains(self) }
}

struct NotchScoreStat: Hashable {
    let kind: NotchScoreStatKind
    /// One reading per side, in the game's order.
    let values: [String]

    /// Each side's share of the bar, even when neither has any.
    var shares: [Double] {
        let numbers = values.map { Double($0.filter { $0.isNumber || $0 == "." }) ?? 0 }
        let total = numbers.reduce(0, +)
        return total > 0 ? numbers.map { $0 / total } : numbers.map { _ in 1 / Double(max(numbers.count, 1)) }
    }
}

/// A goal or a card on a soccer game's timeline.
struct NotchScoreMoment: Hashable {
    enum Kind: Hashable { case goal, penalty, ownGoal, yellowCard, redCard }
    let minute: String
    let kind: Kind
    /// The side it counts for, in the game's order.
    let side: Int
    let player: String
}

/// Where a game stands between plays: an American football drive, the
/// count and the bases of an at-bat, or just the last play.
struct NotchScoreSituation: Hashable {
    var downDistance: String?
    /// The side with the ball, in the game's order.
    var possession: Int?
    var lastPlay: String?
    var redZone = false
    var balls: Int? = nil
    var strikes: Int? = nil
    var outs: Int? = nil
    /// First, second and third.
    var bases: [Bool] = []
    var batter: String? = nil
    var pitcher: String? = nil
}

struct NotchScoreLeader: Hashable {
    enum Category: String, CaseIterable {
        case passing, rushing, receiving, goals, points, rebounds, assists, topPerformer

        /// ESPN's names for it, by sport, across game and season leaders.
        static func named(_ name: String, sport: NotchScoreSport) -> Category? {
            switch (sport, name) {
            case (.football, "passingYards"), (.football, "passingLeader"): return .passing
            case (.football, "rushingYards"), (.football, "rushingLeader"): return .rushing
            case (.football, "receivingYards"), (.football, "receivingLeader"): return .receiving
            case (.basketball, "points"), (.hockey, "points"): return .points
            case (.basketball, "rebounds"): return .rebounds
            case (.basketball, "assists"), (.hockey, "assists"): return .assists
            case (.hockey, "goals"): return .goals
            case (.baseball, "MLBRating"): return .topPerformer
            default: return nil
            }
        }
    }
    let category: Category
    let side: Int?
    let player: String
    /// ESPN's line for it, such as 20/31, 303 YDS, 3 TD.
    let line: String
}

struct NotchScoreGame: Identifiable, Equatable {
    let id: String
    let sport: NotchScoreSport
    let league: String
    /// The competition, tournament or Grand Prix.
    let title: String
    /// A tennis round, or a race weekend's session.
    var detail: String? = nil
    let start: Date
    let state: NotchScoreState
    /// ESPN's reading while under way, such as 68', HT or Q3 4:12, and its
    /// reason when called off.
    var clock = ""
    /// Laps in a race; the half or quarter elsewhere.
    var period = 0
    /// Soccer reads home first and American football away first; a
    /// followed athlete comes first; drivers in running order.
    let sides: [NotchScoreSide]
    let followed: Set<String>
    var link: URL? = nil
    /// The stadium or court, and its city.
    var venue: String? = nil
    var stats: [NotchScoreStat] = []
    var moments: [NotchScoreMoment] = []
    var situation: NotchScoreSituation? = nil
    var leaders: [NotchScoreLeader] = []
    /// Quarters, halves, periods or innings before overtime or extras.
    var regulation = 0
    /// When a tournament or a card is due to end, beyond its start.
    var end: Date? = nil
    /// A fight card's bouts, the main event last.
    var bouts: [NotchScoreBout] = []
    /// ESPN's race weekend a session belongs to, which its drivers'
    /// timing is kept under.
    var event: String? = nil
    /// The part of a Formula 1 qualifying under way, Q1 to Q3; 0 unknown.
    var segment = 0

    var followedSide: NotchScoreSide? { sides.first { followed.contains($0.id) } }

    /// A race weekend's free practice: on the page and the closed island,
    /// in running order, but never a notice, and behind any game that counts.
    var isPractice: Bool { sport == .racing && (detail ?? "").uppercased().hasPrefix("FP") }

    /// A Formula 1 qualifying, run in three parts that knock drivers out.
    var isQualifying: Bool { sport == .racing && league == "f1" && (detail ?? "").lowercased().hasPrefix("qual") }

    /// Where a live qualifying stands, Q2, when it is known.
    var segmentText: String? { isQualifying && state == .live && segment > 0 ? "Q\(segment)" : nil }

    /// Whether it carries what only a scoreboard tells, beyond the score.
    var hasDetail: Bool { !stats.isEmpty || !moments.isEmpty || !leaders.isEmpty || situation != nil }

    /// The bout a card is on: the one under way, else the last decided,
    /// else the first to come.
    var currentBout: NotchScoreBout? {
        bouts.first { $0.state == .live }
            ?? bouts.last { $0.state == .finished || $0.state == .called } ?? bouts.first
    }
}

/// One fight of a card.
struct NotchScoreBout: Hashable, Identifiable {
    let id: String
    /// The weight class, as ESPN names it.
    let division: String
    let sides: [NotchScoreSide]
    let state: NotchScoreState
    let round: Int
    let clock: String
    let rounds: Int
}

enum NotchScoreKind: Equatable {
    case goal, touchdown, fieldGoal, safety, points, run
}

/// What a new reading of a followed game has to tell.
enum NotchScoreChange: Equatable {
    case started
    case finished
    case scored(side: Int, kind: NotchScoreKind)
    case set(side: Int)
    /// A main-card fight was decided; `side` is its winner's.
    case bout(index: Int, side: Int)
}

/// The two readings beside the camera and what follows them.
struct NotchScoreStripText: Equatable {
    let leading: String
    let trailing: String
    let status: String
}

/// One scoreboard read while games are under way.
struct NotchScoreboard: Hashable {
    let sport: NotchScoreSport
    let league: String
    /// ESPN's day, in US Eastern time; nil reads the tour's current event.
    let day: String?
}

/// A request and what its answer is about.
struct NotchScoreRequest: Hashable {
    let url: URL
    let sport: NotchScoreSport
    let league: String
}

/// How closely the scores are being followed, which sets how often a
/// game under way is read. ESPN moves a live scoreboard every few seconds
/// and lets it be cached for one.
enum NotchScorePace: Equatable {
    /// The scores page is open.
    case watching
    /// The closed island shows the game, or nothing does.
    case glancing
    /// Low Power Mode is on.
    case saving

    var live: TimeInterval {
        switch self {
        case .watching: return 5
        case .glancing: return NotchScoresSupport.liveInterval
        case .saving: return 20
        }
    }

    /// A golf leaderboard of 150 players moves a stroke at a time over
    /// four days; it is read less often.
    var golf: TimeInterval {
        switch self {
        case .watching: return 30
        case .glancing: return NotchScoresSupport.golfInterval
        case .saving: return 90
        }
    }
}

/// A racing driver's car: the team's color, its name and the number.
struct NotchScoreLivery: Equatable {
    let color: ColorValue
    let team: String?
    let number: String?
}

enum NotchScoresSupport {
    static let liveInterval: TimeInterval = 10
    static let startingInterval: TimeInterval = 30
    static let golfInterval: TimeInterval = 60
    /// Standings are read again after this, and as soon as a game of
    /// their league ends.
    static let standingsInterval: TimeInterval = 10 * 60
    static let discoveryInterval: TimeInterval = 3 * 3600
    /// Scoreboards are read from shortly before a game is due to start.
    static let leadTime: TimeInterval = 10 * 60
    /// A start that slipped is still awaited this long.
    static let lateStart: TimeInterval = 6 * 3600
    static let resultsKept: TimeInterval = 18 * 3600
    static let upcomingWindow: TimeInterval = 8 * 86400
    /// A result stays in the closed island a while after the game ends.
    static let finalHold: TimeInterval = 10 * 60
    static let stripWingRange: ClosedRange<CGFloat> = 44...160
    static let maximumBytes = 4 * 1024 * 1024
    /// College basketball's standings list every Division I conference in
    /// one answer of about 6 MB, read once when its list is opened.
    static let choicesMaximumBytes = 12 * 1024 * 1024

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchScores.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchScoresEnabled)
            && NotchSupport.modules(in: defaults).contains(.scores)
    }

    static func showsActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchScoresLiveActivity)
    }

    // MARK: Follows

    static func follows(in defaults: UserDefaults = .standard) -> [NotchScoreFollow] {
        follows(stored: defaults.string(forKey: DefaultsKey.notchScoresFollows))
    }

    static func follows(stored: String?) -> [NotchScoreFollow] {
        guard let stored, let data = stored.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([NotchScoreFollow].self, from: data) else { return [] }
        var seen = Set<String>()
        // Formula 1 is followed as a whole, its sessions with every driver;
        // a driver followed by an earlier build stands for the championship.
        let followed = decoded.map { follow -> NotchScoreFollow in
            guard follow.sport == .racing, !follow.wholeLeague,
                  let league = NotchScoreLeague.leagues(for: .racing).first(where: { $0.slug == follow.league })
                    ?? NotchScoreLeague.leagues(for: .racing).first else { return follow }
            return NotchScoreFollow(league: league)
        }
        // An ID goes into a request's path, so only ESPN's own shape is kept.
        return followed.filter { isValidID($0.espnID) && isValidID($0.league) && seen.insert($0.id).inserted }
    }

    static func save(_ follows: [NotchScoreFollow], in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(follows), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(follows.isEmpty ? "" : text, forKey: DefaultsKey.notchScoresFollows)
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 40 && id.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "." || $0 == "_"
        }
    }

    // MARK: Requests

    static let base = "https://site.api.espn.com/apis/site/v2/sports/"

    /// What lists each follow's games: a team's fixtures, or the tour's
    /// current event for athletes. Requests shared by several follows are
    /// made once.
    /// A whole league's games come from its scoreboard for the month, and
    /// the next month's too in the last week of one, as ESPN lists no range
    /// of days.
    static func discoveryRequests(for follows: [NotchScoreFollow], now: Date = Date()) -> [NotchScoreRequest] {
        var seen = Set<NotchScoreRequest>()
        return follows.flatMap { follow -> [NotchScoreRequest] in
            let paths: [String]
            let league: String
            let sport = follow.sport.rawValue
            switch (follow.sport, follow.wholeLeague) {
            case (.soccer, false):
                paths = ["soccer/all/teams/\(follow.espnID)/schedule?fixture=true"]
                league = "all"
            case (.soccer, true):
                paths = scoreboardMonths(from: now).map { "soccer/\(follow.league)/scoreboard?dates=\($0)" }
                league = follow.league
            // A month of basketball or hockey is more than ESPN lists in one
            // answer, so the week ahead is asked for day by day.
            case (_, true) where follow.sport.hasTeams:
                paths = scoreboardDays(from: now).map { "\(sport)/\(follow.league)/scoreboard?dates=\($0)" }
                league = follow.league
            case (_, false) where follow.sport.hasTeams:
                paths = ["\(sport)/\(follow.league)/teams/\(follow.espnID)/schedule"]
                league = follow.league
            default:
                paths = ["\(sport)/\(follow.league)/scoreboard"]
                league = follow.league
            }
            return paths.compactMap { path in
                guard let url = URL(string: base + path) else { return nil }
                let request = NotchScoreRequest(url: url, sport: follow.sport, league: league)
                return seen.insert(request).inserted ? request : nil
            }
        }
    }

    /// Today and the six days after it, as ESPN dates them.
    static func scoreboardDays(from now: Date) -> [String] {
        (0..<7).map { scoreboardDay(for: now.addingTimeInterval(Double($0) * 86400)) }
    }

    private static let easternMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyyMM"
        return formatter
    }()

    /// This month, in ESPN's Eastern time, and the next one once the coming
    /// week reaches into it.
    static func scoreboardMonths(from now: Date) -> [String] {
        let current = easternMonth.string(from: now)
        let ahead = easternMonth.string(from: now.addingTimeInterval(upcomingWindow))
        return current == ahead ? [current] : [current, ahead]
    }

    static func request(for board: NotchScoreboard) -> NotchScoreRequest? {
        let query = board.day.map { "?dates=" + $0 } ?? ""
        guard let url = URL(string: base + "\(board.sport.rawValue)/\(board.league)/scoreboard" + query) else { return nil }
        return NotchScoreRequest(url: url, sport: board.sport, league: board.league)
    }

    /// The teams of a league, a tour's ranking, or the drivers' standings.
    static func choicesURL(for league: NotchScoreLeague) -> URL? {
        switch league.sport {
        case .soccer: return URL(string: base + "soccer/\(league.slug)/teams")
        // The standings list each team in its conference, the way the
        // league is followed, and a college league's whole top division.
        case .football, .basketball, .baseball, .hockey:
            return URL(string: "https://site.api.espn.com/apis/v2/sports/\(league.sport.rawValue)/\(league.slug)/standings")
        case .tennis: return URL(string: base + "tennis/\(league.slug)/rankings")
        // Followed whole: there is no one to pick.
        case .golf, .mma, .racing: return nil
        }
    }

    private static let easternDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// ESPN files a game under its day in US Eastern time, so an evening
    /// kickoff in Brazil sits on the previous day's scoreboard in UTC terms.
    static func scoreboardDay(for date: Date) -> String { easternDay.string(from: date) }

    // MARK: Schedule

    static func needsWatching(_ game: NotchScoreGame, now: Date) -> Bool {
        switch game.state {
        case .live: return true
        case .scheduled:
            return game.start.timeIntervalSince(now) <= leadTime && now.timeIntervalSince(game.start) < lateStart
        case .finished, .called: return false
        }
    }

    /// Scoreboards that hold games under way or about to start. Tennis and
    /// racing read the tour's current event, which has no day.
    static func dueScoreboards(_ games: [NotchScoreGame], now: Date) -> [NotchScoreboard] {
        var seen = Set<NotchScoreboard>()
        return games.filter { needsWatching($0, now: now) }.sorted { $0.start < $1.start }.compactMap { game in
            let day = game.sport.readsCurrentEvent ? nil : scoreboardDay(for: game.start)
            let board = NotchScoreboard(sport: game.sport, league: game.league, day: day)
            return seen.insert(board).inserted ? board : nil
        }
    }

    /// Seconds until the next reading: often while a game is on, then not
    /// before the next one is due or the fixtures are listed again.
    static func nextPoll(_ games: [NotchScoreGame], lastDiscovery: Date?, now: Date,
                         pace: NotchScorePace = .glancing) -> TimeInterval {
        let live = games.filter { $0.state == .live }
        if live.contains(where: { $0.sport != .golf }) { return pace.live }
        if !live.isEmpty { return pace.golf }
        if games.contains(where: { needsWatching($0, now: now) }) { return startingInterval }
        let discovery = (lastDiscovery ?? .distantPast).addingTimeInterval(discoveryInterval)
        let nextStart = games.filter { $0.state == .scheduled }
            .map { $0.start.addingTimeInterval(-leadTime) }.filter { $0 > now }.min()
        let target = min(discovery, nextStart ?? discovery)
        return max(liveInterval, target.timeIntervalSince(now))
    }

    static func discoveryIsDue(lastDiscovery: Date?, now: Date) -> Bool {
        guard let lastDiscovery else { return true }
        return now.timeIntervalSince(lastDiscovery) >= discoveryInterval || lastDiscovery > now
    }

    /// Newer readings replace older ones, except that a game never moves
    /// back: a schedule that has not caught up does not reopen a result.
    static func merge(_ current: [String: NotchScoreGame], with incoming: [NotchScoreGame]) -> [String: NotchScoreGame] {
        var merged = current
        for game in incoming {
            if let existing = merged[game.id] {
                if existing.state.rank > game.state.rank { continue }
                // A team's fixtures list no statistics: during a game they
                // do not erase the scoreboard's.
                if existing.state == game.state, existing.hasDetail, !game.hasDetail { continue }
            }
            merged[game.id] = game
        }
        return merged
    }

    /// What the page and the island keep: games coming within the week,
    /// those under way, and results from the last hours, all of them
    /// involving someone still followed.
    static func kept(_ games: [String: NotchScoreGame], follows: [NotchScoreFollow], now: Date) -> [String: NotchScoreGame] {
        let followed = Set(follows.filter { !$0.wholeLeague }.map { $0.sport.rawValue + ":" + $0.espnID })
        let leagues = Set(follows.filter(\.wholeLeague).map(\.leagueKey))
        return games.filter { _, game in
            guard leagues.contains(game.sport.rawValue + "/" + game.league)
                    || game.followed.contains(where: { followed.contains(game.sport.rawValue + ":" + $0) }) else { return false }
            switch game.state {
            case .live: return true
            case .scheduled:
                return game.start.timeIntervalSince(now) <= upcomingWindow && now.timeIntervalSince(game.start) < lateStart
            // A tournament's result counts from its last day, not its first.
            case .finished, .called:
                return now.timeIntervalSince(game.end ?? game.start) <= resultsKept
            }
        }
    }

    static func sorted(_ games: [String: NotchScoreGame]) -> [NotchScoreGame] {
        games.values.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    // MARK: Changes

    static func change(from old: NotchScoreGame, to new: NotchScoreGame) -> NotchScoreChange? {
        // Three practices a weekend would speak up six times for nothing decided.
        guard !new.isPractice else { return nil }
        if old.state == .scheduled, new.state == .live { return .started }
        if old.state == .live, new.state == .finished { return .finished }
        guard old.state == .live, new.state == .live else { return nil }
        switch new.sport {
        // Baskets come every few seconds; only the start and the end are news.
        case .basketball:
            return nil
        case .soccer, .football, .hockey, .baseball:
            for (index, side) in new.sides.enumerated() {
                guard let before = old.sides.first(where: { $0.id == side.id })?.score.flatMap({ Int($0) }),
                      let after = side.score.flatMap({ Int($0) }), after > before else { continue }
                if new.sport == .soccer || new.sport == .hockey { return .scored(side: index, kind: .goal) }
                if new.sport == .baseball { return .scored(side: index, kind: .run) }
                switch after - before {
                case 6, 7, 8: return .scored(side: index, kind: .touchdown)
                case 3: return .scored(side: index, kind: .fieldGoal)
                case 2: return .scored(side: index, kind: .safety)
                // The point after a touchdown follows the notice about it.
                case 1: continue
                default: return .scored(side: index, kind: .points)
                }
            }
            return nil
        case .tennis:
            for (index, side) in new.sides.enumerated() {
                guard let before = old.sides.first(where: { $0.id == side.id })?.setsWon,
                      side.setsWon > before else { continue }
                return .set(side: index)
            }
            return nil
        // A main card's fights, the last five, each as it is decided.
        case .mma:
            for (index, bout) in new.bouts.enumerated() where index >= new.bouts.count - 5 && bout.state == .finished {
                guard old.bouts.first(where: { $0.id == bout.id })?.state == .live,
                      let winner = bout.sides.firstIndex(where: \.winner) else { continue }
                return .bout(index: index, side: winner)
            }
            return nil
        case .racing, .golf:
            return nil
        }
    }

    // MARK: Presentation

    /// What the Settings preview shows when nothing followed is on: a
    /// soccer game under way, with the moments and statistics the page
    /// lays out, and no crest, link or venue to fetch or open.
    static func sample(text: NotchScoresStrings, now: Date) -> NotchScoreGame {
        NotchScoreGame(
            id: "sample", sport: .soccer, league: "sample", title: text.sampleGame,
            start: now.addingTimeInterval(-70 * 60), state: .live, clock: "67'", period: 2,
            sides: [NotchScoreSide(id: "sample-home", name: text.sampleHome, abbreviation: "HOM", score: "2"),
                    NotchScoreSide(id: "sample-away", name: text.sampleAway, abbreviation: "AWY", score: "1")],
            followed: ["sample-home"],
            stats: [NotchScoreStat(kind: .possession, values: ["58", "42"]),
                    NotchScoreStat(kind: .shots, values: ["14", "7"]),
                    NotchScoreStat(kind: .shotsOnTarget, values: ["6", "3"]),
                    NotchScoreStat(kind: .corners, values: ["5", "2"])],
            moments: [NotchScoreMoment(minute: "12'", kind: .goal, side: 0, player: "Silva"),
                      NotchScoreMoment(minute: "34'", kind: .yellowCard, side: 1, player: "Moreau"),
                      NotchScoreMoment(minute: "51'", kind: .goal, side: 1, player: "Martín"),
                      NotchScoreMoment(minute: "63'", kind: .penalty, side: 0, player: "Costa")])
    }

    /// The game the closed island shows: the first under way, or one that
    /// just ended, for a while.
    /// A followed team's or athlete's game goes before others of a league
    /// followed as a whole.
    static func featured(_ games: [NotchScoreGame], finishedAt: [String: Date], now: Date) -> NotchScoreGame? {
        let live = games.filter { $0.state == .live }
        if let game = live.first(where: { !$0.followed.isEmpty }) ?? live.first(where: { !$0.isPractice }) ?? live.first {
            return game
        }
        return games.filter { $0.state == .finished }
            .compactMap { game in finishedAt[game.id].map { (game, $0) } }
            .filter { now.timeIntervalSince($0.1) < finalHold }
            .max { ($0.0.followed.isEmpty ? 0 : 1, $0.1) < ($1.0.followed.isEmpty ? 0 : 1, $1.1) }?.0
    }

    /// The full reading, for notices and VoiceOver: names, score and clock.
    static func stripText(_ game: NotchScoreGame, text: NotchScoresStrings, locale: Locale, now: Date) -> NotchScoreStripText {
        let status = statusText(game, text: text, locale: locale, now: now)
        switch game.sport {
        case .soccer, .football, .basketball, .baseball, .hockey:
            let first = game.sides.first, second = game.sides.dropFirst().first
            // A scoreboard lists 0–0 before kickoff; nothing is scored yet.
            let scored = game.state != .scheduled
            return NotchScoreStripText(
                leading: [first?.abbreviation, scored ? first?.score : nil].compactMap { $0 }.joined(separator: " "),
                trailing: [scored ? second?.score : nil, second?.abbreviation].compactMap { $0 }.joined(separator: " "),
                status: status)
        case .tennis:
            // Before the first game, the opponent stands where the sets will be.
            let sets = setsText(game)
            return NotchScoreStripText(leading: game.sides.first?.abbreviation ?? game.title,
                                       trailing: sets.isEmpty ? (game.sides.dropFirst().first?.abbreviation ?? "") : sets,
                                       status: game.state == .live ? "" : status)
        case .racing:
            // The leader, once a session has an order.
            let driver = game.followedSide ?? (game.state == .scheduled ? nil : game.sides.first)
            let leading = [driver?.position.map { "P\($0)" }, driver?.abbreviation].compactMap { $0 }.joined(separator: " ")
            return NotchScoreStripText(leading: leading.isEmpty ? game.title : leading,
                                       trailing: text.session(game.detail ?? ""),
                                       status: game.segmentText
                                        ?? (game.state == .live && game.period > 0 && !game.isPractice && !game.isQualifying
                                            ? "L\(game.period)" : ""))
        case .golf:
            let leader = game.state == .scheduled ? nil : game.sides.first
            return NotchScoreStripText(leading: leader.map { $0.abbreviation + " " + ($0.score ?? "") } ?? game.title,
                                       trailing: game.period > 0 ? text.round(game.period) : "",
                                       status: game.state == .live ? "" : status)
        case .mma:
            let bout = game.currentBout
            return NotchScoreStripText(leading: bout?.sides.first?.abbreviation ?? game.title,
                                       trailing: bout?.sides.dropFirst().first?.abbreviation ?? "", status: status)
        }
    }

    /// The closed capsule's single row.
    static func capsuleText(_ strip: NotchScoreStripText, sport: NotchScoreSport) -> String {
        let core = capsuleCore(strip, sport: sport)
        return strip.status.isEmpty ? core : core + " · " + strip.status
    }

    /// The closed island's readings, beside each side's crest: its score,
    /// a player's games in each set, a race's lap, a leader's score to
    /// par or a fight's round. Names, clocks and times wait for the open
    /// island.
    static func compactText(_ game: NotchScoreGame, text: NotchScoresStrings) -> NotchScoreStripText {
        switch game.sport {
        case .soccer, .football, .basketball, .baseball, .hockey:
            let scored = game.state != .scheduled
            return NotchScoreStripText(leading: scored ? game.sides.first?.score ?? "" : "",
                                       trailing: scored ? game.sides.dropFirst().first?.score ?? "" : "", status: "")
        case .tennis:
            func games(_ side: NotchScoreSide?) -> String { (side?.sets ?? []).map { String($0.games) }.joined(separator: " ") }
            return NotchScoreStripText(leading: games(game.sides.first), trailing: games(game.sides.dropFirst().first),
                                       status: "")
        case .racing:
            // Practice runs to the clock, not to a lap count; its short name
            // fits the wing where Practice 2 would not.
            // Qualifying runs to the clock too: its part, or its short name.
            let reading = game.segmentText
                ?? (game.isPractice || (game.isQualifying && game.state == .live) ? (game.detail ?? "").uppercased()
                    : game.state == .live && game.period > 0 ? "L\(game.period)" : text.session(game.detail ?? ""))
            return NotchScoreStripText(leading: "", trailing: reading, status: "")
        case .golf:
            return NotchScoreStripText(leading: "", trailing: game.state == .scheduled ? "" : game.sides.first?.score ?? "",
                                       status: "")
        case .mma:
            let bout = game.currentBout
            return NotchScoreStripText(leading: bout?.state == .live && (bout?.round ?? 0) > 0 ? "R\(bout?.round ?? 0)" : "",
                                       trailing: "", status: "")
        }
    }

    /// The crests or flags the closed island sets at each end; nil for a
    /// field of drivers or golfers, which shows its sport's mark instead.
    static func compactMarks(_ game: NotchScoreGame) -> [URL?]? {
        guard !game.sport.isField else { return nil }
        let sides = game.sport == .mma ? (game.currentBout?.sides ?? []) : game.sides
        return [sides.first?.logo, sides.dropFirst().first?.logo]
    }

    // MARK: Qualifying

    /// A driver's timing, whose qualifying times ESPN fills in only for
    /// those knocked out, as each part ends.
    static func timingURL(_ game: NotchScoreGame, driver: String) -> URL? {
        guard let event = game.event, event.allSatisfy(\.isNumber), driver.allSatisfy(\.isNumber),
              let session = game.id.split(separator: "#").last, session.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://sports.core.api.espn.com/v2/sports/racing/leagues/\(game.league)/events/\(event)"
                   + "/competitions/\(session)/competitors/\(driver)/statistics")
    }

    /// The drivers that tell which part a live qualifying is in: the best
    /// knocked out in Q1, who has a Q1 time once Q2 is on, and P11, the
    /// best knocked out in Q2, once Q3 is. Ten reach Q3 and half the rest
    /// Q2: 16 of 22 cars, 15 of 20. Nothing is asked once Q3 is known.
    static func segmentProbes(_ game: NotchScoreGame) -> [(part: Int, url: URL)] {
        let field = game.sides.count
        guard game.isQualifying, game.state == .live, game.segment < 3, field > 10 else { return [] }
        let outInQ1 = 10 + (field - 10) / 2
        var probes: [(Int, Int)] = []
        if game.segment < 2, outInQ1 < field { probes.append((1, outInQ1)) }
        probes.append((2, 10))
        return probes.compactMap { part, index in timingURL(game, driver: game.sides[index].id).map { (part, $0) } }
    }

    /// Whether a driver's timing holds a time for that part of qualifying;
    /// nil when it can't be read.
    static func hasQualifyingTime(_ data: Data, part: Int) -> Bool? {
        guard let timing = try? JSONDecoder().decode(ESPNTiming.self, from: data) else { return nil }
        let stats = (timing.splits?.categories?.elements ?? []).flatMap { $0.stats?.elements ?? [] }
        guard let stat = stats.first(where: { $0.name == "qual\(part)TimeMS" }) else { return nil }
        return (stat.value?.number ?? 0) > 0
    }

    /// The part under way from what the probes found: past Q2, past Q1, or
    /// the first. It never goes back, so a reading that fails keeps it.
    static func segment(previous: Int, finished: [Int: Bool]) -> Int {
        let found = finished[2] == true ? 3 : finished[1] == true ? 2 : finished.isEmpty ? 0 : 1
        return max(previous, found)
    }

    // MARK: Liveries

    /// Every driver of a session with their car, in one short answer.
    static func liveryURL(_ game: NotchScoreGame) -> URL? {
        guard game.sport == .racing, let event = game.event, event.allSatisfy(\.isNumber),
              game.league.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              let session = game.id.split(separator: "#").last, session.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://sports.core.api.espn.com/v2/sports/racing/leagues/\(game.league)/events/\(event)"
                   + "/competitions/\(session)/competitors?limit=60")
    }

    /// Each driver's car by their ESPN id; nil when it can't be read.
    static func liveries(from data: Data) -> [String: NotchScoreLivery]? {
        guard let page = try? JSONDecoder().decode(ESPNCompetitorPage.self, from: data) else { return nil }
        var found: [String: NotchScoreLivery] = [:]
        for item in page.items?.elements ?? [] {
            guard let id = item.id?.text, let vehicle = item.vehicle, let hex = vehicle.teamColor,
                  hex.count == 6, let color = ColorValue(text: "#" + hex) else { continue }
            let team = vehicle.team ?? vehicle.manufacturer
            found[id] = NotchScoreLivery(color: color, team: team?.isEmpty == false ? team : nil, number: vehicle.number?.text)
        }
        return found
    }

    /// The driver the closed island pictures in place of the checkered
    /// flag: whoever is P1 once a session has an order.
    static func compactPortrait(_ game: NotchScoreGame) -> URL? { compactLeader(game)?.portrait }

    /// P1, once a session has an order.
    static func compactLeader(_ game: NotchScoreGame) -> NotchScoreSide? {
        guard game.sport == .racing, game.state != .scheduled else { return nil }
        return game.sides.first { $0.position == 1 }
    }

    /// The capsule's one row between its marks: 2 – 1, 6-4 3-2, a lap, a
    /// score to par or a round.
    static func compactCore(_ game: NotchScoreGame, text: NotchScoresStrings) -> String {
        let compact = compactText(game, text: text)
        switch game.sport {
        case .soccer, .football, .basketball, .baseball, .hockey: return compact.leading + " – " + compact.trailing
        case .tennis: return setsText(game)
        case .racing, .golf: return compact.trailing
        case .mma: return compact.leading.isEmpty ? "–" : compact.leading
        }
    }

    /// The row without its clock, which the capsule sets after the second crest.
    static func capsuleCore(_ strip: NotchScoreStripText, sport: NotchScoreSport) -> String {
        switch sport {
        case .soccer, .football, .basketball, .baseball, .hockey, .mma:
            return [strip.leading, strip.trailing].filter { !$0.isEmpty }.joined(separator: " – ")
        // Sets follow the player; an opponent is set apart from them.
        case .tennis:
            return strip.trailing.first?.isNumber == false ? strip.leading + " – " + strip.trailing
                : [strip.leading, strip.trailing].filter { !$0.isEmpty }.joined(separator: " ")
        case .racing, .golf: return [strip.leading, strip.trailing].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// Places as a leaderboard writes them, ties shared: 1, T2, T2, 4.
    static func places(_ field: [NotchScoreSide]) -> [String] {
        var counts: [String: Int] = [:]
        for side in field { if let score = side.score { counts[score, default: 0] += 1 } }
        return field.enumerated().map { index, side in
            guard let score = side.score else { return "" }
            let first = field.firstIndex { $0.score == score } ?? index
            return ((counts[score] ?? 0) > 1 ? "T" : "") + String(first + 1)
        }
    }

    /// Games in each set, the first side's first: 6-4 3-2.
    static func setsText(_ game: NotchScoreGame) -> String {
        guard game.sides.count >= 2 else { return "" }
        let first = game.sides[0].sets, second = game.sides[1].sets
        return zip(first, second).map { "\($0.games)-\($1.games)" }.joined(separator: " ")
    }

    static func statusText(_ game: NotchScoreGame, text: NotchScoresStrings, locale: Locale, now: Date) -> String {
        switch game.state {
        case .live:
            switch game.sport {
            case .racing where game.segmentText != nil: return game.segmentText ?? ""
            case .racing where game.period > 0 && !game.isPractice && !game.isQualifying: return text.lap(game.period)
            case .golf where game.period > 0: return text.round(game.period)
            case .mma:
                guard let bout = game.currentBout, bout.state == .live, bout.round > 0 else { return text.live }
                return "R\(bout.round) " + bout.clock
            default: return game.clock.isEmpty ? text.live : game.clock
            }
        case .finished: return text.final
        case .called: return game.clock
        case .scheduled: return startText(game.start, locale: locale, now: now)
        }
    }

    /// The time alone today; the weekday and time within the week.
    static func startText(_ start: Date, locale: Locale, now: Date, calendar: Calendar = .current) -> String {
        let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        guard !calendar.isDate(start, inSameDayAs: now) else { return time }
        let day = start.formatted(Date.FormatStyle().weekday(.abbreviated).locale(locale))
        return day + " " + time
    }

    // MARK: Reading ESPN

    private static let minuteDates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return formatter
    }()

    private static let secondDates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"
        return formatter
    }()

    /// ESPN writes most times to the minute, some to the second.
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return minuteDates.date(from: text) ?? secondDates.date(from: text)
    }

    /// The followed teams' and athletes' games in a scoreboard or a team's
    /// schedule. nil when the answer is not one ESPN would send.
    static func games(from data: Data, request: NotchScoreRequest, follows: [NotchScoreFollow]) -> [NotchScoreGame]? {
        guard let root = try? JSONDecoder().decode(ESPNRoot.self, from: data) else { return nil }
        let sport = follows.filter { $0.sport == request.sport }
        let followed = Set(sport.filter { !$0.wholeLeague }.map(\.espnID))
        let leagues = Set(sport.filter(\.wholeLeague).map(\.league))
        guard !followed.isEmpty || !leagues.isEmpty else { return [] }
        let leagueName = root.leagues?.elements.first?.name
        let events = root.events?.elements ?? []
        switch request.sport {
        case .soccer, .football, .basketball, .baseball, .hockey:
            return events.compactMap {
                teamGame($0, request: request, leagueName: leagueName, followed: followed, leagues: leagues)
            }
        case .tennis:
            return events.flatMap {
                tennisGames($0, request: request, followed: followed, wholeTour: leagues.contains(request.league))
            }
        case .racing:
            guard leagues.contains(request.league) else { return [] }
            return events.flatMap { racingGames($0, request: request) }
        case .golf:
            guard leagues.contains(request.league) else { return [] }
            return events.compactMap { golfGame($0, request: request) }
        case .mma:
            guard leagues.contains(request.league) else { return [] }
            return events.compactMap { fightCard($0, request: request) }
        }
    }

    private static func teamGame(_ event: ESPNEvent, request: NotchScoreRequest, leagueName: String?,
                                 followed: Set<String>, leagues: Set<String>) -> NotchScoreGame? {
        guard let eventID = event.id?.text, let competition = event.competitions?.elements.first,
              let start = date(competition.date ?? event.date) else { return nil }
        let slug = event.league?.slug ?? request.league
        guard isValidID(slug), slug != "all" else { return nil }
        let competitors = competition.competitors?.elements ?? []
        // Home first in soccer, away first in the American sports, as each is read.
        let ordered = competitors.sorted { lhs, rhs in
            let home = request.sport == .soccer ? "home" : "away"
            return (lhs.homeAway == home ? 0 : 1) < (rhs.homeAway == home ? 0 : 1)
        }
        let sides = ordered.compactMap { competitor -> NotchScoreSide? in
            guard let id = competitor.id?.text ?? competitor.team?.id?.text, let team = competitor.team else { return nil }
            let name = team.displayName ?? team.shortDisplayName ?? id
            return NotchScoreSide(id: id, name: name, abbreviation: team.abbreviation ?? String(name.prefix(3)).uppercased(),
                                  score: competitor.score?.text, winner: competitor.winner ?? false,
                                  logo: image(team.logo ?? team.logos?.elements.first?.href),
                                  periods: request.sport == .soccer
                                    ? [] : (competitor.linescores?.elements ?? []).compactMap { $0.value?.text },
                                  record: competitor.records?.elements.first?.summary,
                                  hits: request.sport == .baseball ? competitor.hits?.text : nil,
                                  errors: request.sport == .baseball ? competitor.errors?.text : nil)
        }
        let ids = Set(sides.map(\.id))
        guard sides.count == 2, !ids.isDisjoint(with: followed) || leagues.contains(slug) else { return nil }
        let status = competition.status ?? event.status
        let state = state(status)
        let both = Array(ordered.prefix(2))
        let index = Dictionary(sides.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return NotchScoreGame(
            id: "\(request.sport.rawValue)/\(slug)#\(eventID)", sport: request.sport, league: slug,
            title: NotchScoreLeague.name(sport: request.sport, slug: slug) ?? event.league?.name ?? leagueName ?? "",
            start: start, state: state,
            // A scheduled game's detail is ESPN's own US time; the island writes its own.
            clock: state == .scheduled ? "" : (status?.type?.shortDetail ?? status?.displayClock ?? ""),
            period: status?.period?.integer ?? 0, sides: sides, followed: ids.intersection(followed),
            link: link(event), venue: venue(competition.venue),
            stats: stats(both, sport: request.sport), moments: moments(competition.details?.elements ?? [], index: index),
            situation: state == .live ? situation(competition.situation, index: index) : nil,
            leaders: leaders(competition.leaders?.elements ?? [], competitors: both, sides: sides, index: index,
                             sport: request.sport),
            regulation: competition.format?.regulation?.periods?.integer ?? 0)
    }

    private static func venue(_ venue: ESPNCompetition.Venue?) -> String? {
        guard let name = venue?.fullName, !name.isEmpty else { return nil }
        guard let city = venue?.address?.city, !city.isEmpty, !name.contains(city) else { return name }
        return name + ", " + city
    }

    /// The statistics both sides report, in the page's order.
    private static func stats(_ competitors: [ESPNCompetitor], sport: NotchScoreSport) -> [NotchScoreStat] {
        guard competitors.count == 2 else { return [] }
        let readings = competitors.map { competitor in
            Dictionary((competitor.statistics?.elements ?? []).compactMap { stat in
                stat.name.flatMap { name in stat.displayValue.map { (name, $0) } }
            }, uniquingKeysWith: { first, _ in first })
        }
        return NotchScoreStatKind.kinds(for: sport).compactMap { kind in
            let values = readings.compactMap { $0[kind.rawValue] }
            return values.count == 2 ? NotchScoreStat(kind: kind, values: values) : nil
        }
    }

    /// Goals and cards, in the order they came. Shootouts and missed
    /// penalties change no score on the timeline.
    private static func moments(_ details: [ESPNCompetition.Detail], index: [String: Int]) -> [NotchScoreMoment] {
        details.compactMap { detail in
            guard detail.shootout != true, let team = detail.team?.id?.text, let side = index[team] else { return nil }
            let kind: NotchScoreMoment.Kind
            if detail.scoringPlay == true {
                kind = detail.ownGoal == true ? .ownGoal : detail.penaltyKick == true ? .penalty : .goal
            } else if detail.redCard == true {
                kind = .redCard
            } else if detail.yellowCard == true {
                kind = .yellowCard
            } else {
                return nil
            }
            let player = detail.athletesInvolved?.elements.first.map { $0.displayName ?? $0.shortName ?? "" } ?? ""
            return NotchScoreMoment(minute: detail.clock?.displayValue ?? "", kind: kind, side: side, player: player)
        }
    }

    private static func situation(_ situation: ESPNCompetition.Situation?, index: [String: Int]) -> NotchScoreSituation? {
        guard let situation else { return nil }
        let bases = [situation.onFirst, situation.onSecond, situation.onThird]
        var reading = NotchScoreSituation(downDistance: situation.downDistanceText,
                                          possession: situation.possession?.text.flatMap { index[$0] },
                                          lastPlay: situation.lastPlay?.text, redZone: situation.isRedZone ?? false)
        // An at-bat: the count, the outs, who is on and who faces whom.
        if let outs = situation.outs?.integer {
            reading.outs = outs
            reading.balls = situation.balls?.integer
            reading.strikes = situation.strikes?.integer
            reading.bases = bases.map { $0 == true }
            reading.batter = situation.batter?.athlete?.displayName
            reading.pitcher = situation.pitcher?.athlete?.displayName
        }
        return reading.downDistance == nil && reading.lastPlay == nil && reading.outs == nil ? nil : reading
    }

    /// The game's leaders, as American football lists them, or each team's,
    /// as basketball, hockey and baseball do: one line per side and category.
    private static func leaders(_ categories: [ESPNCompetition.LeaderCategory], competitors: [ESPNCompetitor],
                                sides: [NotchScoreSide], index: [String: Int], sport: NotchScoreSport) -> [NotchScoreLeader] {
        func leader(_ entry: ESPNCompetition.LeaderCategory.Leader?, category: NotchScoreLeader.Category,
                    side: Int?) -> NotchScoreLeader? {
            guard let entry, let player = entry.athlete?.displayName ?? entry.athlete?.shortName,
                  let line = entry.displayValue else { return nil }
            return NotchScoreLeader(category: category, side: side ?? entry.team?.id?.text.flatMap { index[$0] },
                                    player: player, line: line)
        }
        let game = categories.compactMap { category -> NotchScoreLeader? in
            guard let kind = category.name.flatMap({ NotchScoreLeader.Category.named($0, sport: sport) }) else { return nil }
            return leader(category.leaders?.elements.first, category: kind, side: nil)
        }
        guard game.isEmpty else { return sortedLeaders(game) }
        let teams = competitors.enumerated().flatMap { side, competitor -> [NotchScoreLeader] in
            var seen = Set<NotchScoreLeader.Category>()
            return (competitor.leaders?.elements ?? []).compactMap { category in
                guard let kind = category.name.flatMap({ NotchScoreLeader.Category.named($0, sport: sport) }),
                      seen.insert(kind).inserted else { return nil }
                return leader(category.leaders?.elements.first, category: kind, side: side)
            }
        }
        return sortedLeaders(teams)
    }

    private static func sortedLeaders(_ leaders: [NotchScoreLeader]) -> [NotchScoreLeader] {
        let order = NotchScoreLeader.Category.allCases
        return leaders.sorted {
            (order.firstIndex(of: $0.category) ?? 0, $0.side ?? 0) < (order.firstIndex(of: $1.category) ?? 0, $1.side ?? 0)
        }
    }

    /// A tournament's leaderboard: each golfer's place, score to par,
    /// rounds and holes played in the round under way.
    private static func golfGame(_ event: ESPNEvent, request: NotchScoreRequest) -> NotchScoreGame? {
        guard let eventID = event.id?.text, let competition = event.competitions?.elements.first,
              let start = date(event.date ?? competition.date) else { return nil }
        let status = competition.status ?? event.status
        let state = state(status)
        let field = (competition.competitors?.elements ?? []).compactMap { competitor -> NotchScoreSide? in
            guard let id = competitor.id?.text, let athlete = competitor.athlete else { return nil }
            let rounds = (competitor.linescores?.elements ?? []).filter { $0.value != nil }
            return NotchScoreSide(id: id, name: athlete.displayName ?? id, abbreviation: surname(athlete),
                                  score: competitor.score?.text, position: competitor.order?.integer,
                                  winner: competitor.winner ?? false, logo: image(athlete.flag?.href),
                                  periods: rounds.compactMap { $0.displayValue ?? $0.value?.text },
                                  thru: state == .live ? competitor.linescores?.elements.last?.linescores?.elements.count : nil)
        }.sorted { ($0.position ?? .max) < ($1.position ?? .max) }
        return NotchScoreGame(
            id: "golf/\(request.league)#\(eventID)", sport: .golf, league: request.league,
            title: event.name ?? event.shortName ?? "", start: start, state: state,
            clock: state == .called ? (status?.type?.shortDetail ?? "") : "",
            period: status?.period?.integer ?? 0, sides: Array(field.prefix(60)), followed: [], link: link(event),
            end: date(event.endDate))
    }

    /// A fight card: its bouts in the order they are fought, the main event
    /// last, each with its division, fighters, records and result.
    private static func fightCard(_ event: ESPNEvent, request: NotchScoreRequest) -> NotchScoreGame? {
        guard let eventID = event.id?.text, let start = date(event.date) else { return nil }
        let bouts = (event.competitions?.elements ?? []).compactMap { competition -> NotchScoreBout? in
            guard let id = competition.id?.text else { return nil }
            let fighters = (competition.competitors?.elements ?? [])
                .sorted { ($0.order?.integer ?? 0) < ($1.order?.integer ?? 0) }
                .compactMap { competitor -> NotchScoreSide? in
                    guard let fighter = competitor.id?.text, let athlete = competitor.athlete else { return nil }
                    return NotchScoreSide(id: fighter, name: athlete.displayName ?? fighter, abbreviation: surname(athlete),
                                          winner: competitor.winner ?? false, logo: image(athlete.flag?.href),
                                          record: competitor.records?.elements.first?.summary)
                }
            guard fighters.count == 2 else { return nil }
            let status = competition.status
            return NotchScoreBout(id: id, division: competition.type?.abbreviation ?? "", sides: fighters,
                                  state: state(status), round: status?.period?.integer ?? 0,
                                  clock: status?.displayClock ?? "",
                                  rounds: competition.format?.regulation?.periods?.integer ?? 3)
        }
        guard let main = bouts.last else { return nil }
        // The card is on from its first bout to its last decision.
        let state: NotchScoreState = bouts.contains { $0.state == .live }
            || (bouts.contains { $0.state == .finished } && bouts.contains { $0.state == .scheduled })
            ? .live : bouts.allSatisfy { $0.state == .finished || $0.state == .called } ? .finished : .scheduled
        let last = (event.competitions?.elements ?? []).compactMap { date($0.date) }.max() ?? start
        return NotchScoreGame(
            id: "mma/\(request.league)#\(eventID)", sport: .mma, league: request.league,
            title: event.name ?? event.shortName ?? "", start: start, state: state,
            sides: main.sides, followed: [], link: link(event), end: last.addingTimeInterval(2 * 3600), bouts: bouts)
    }

    /// A whole tour follows its singles: doubles too would double the news.
    private static func tennisGames(_ event: ESPNEvent, request: NotchScoreRequest, followed: Set<String>,
                                    wholeTour: Bool) -> [NotchScoreGame] {
        let tournament = event.shortName ?? event.name ?? ""
        let grouped = (event.groupings?.elements ?? []).flatMap { grouping in
            (grouping.competitions?.elements ?? []).map { ($0, grouping.grouping?.slug?.contains("doubles") == true) }
        }
        let competitions = grouped + (event.competitions?.elements ?? []).map { ($0, false) }
        return competitions.compactMap { competition, doubles in
            guard let matchID = competition.id?.text, let start = date(competition.date ?? event.date) else { return nil }
            let sides = (competition.competitors?.elements ?? [])
                .sorted { ($0.order?.integer ?? 0) < ($1.order?.integer ?? 0) }
                .compactMap(tennisSide)
            guard sides.count == 2 else { return nil }
            let matching = sides.filter { !Set([$0.id] + $0.members).isDisjoint(with: followed) }
            guard !matching.isEmpty || (wholeTour && !doubles) else { return nil }
            // The followed player reads first, with the sets from their side.
            let ordered = matching.count == 1 && matching[0].id == sides[1].id ? Array(sides.reversed()) : sides
            let status = competition.status ?? event.status
            let state = state(status)
            return NotchScoreGame(
                id: "tennis/\(request.league)#\(matchID)", sport: .tennis, league: request.league,
                title: tournament, detail: competition.round?.displayName, start: start, state: state,
                clock: state == .called ? (status?.type?.shortDetail ?? "") : "",
                // A pair is followed through its player, whom the list of
                // follows knows, and is drawn as followed by its own ID.
                sides: Array(ordered),
                followed: Set(matching.map(\.id)).union(matching.flatMap(\.members).filter(followed.contains)),
                link: link(event), venue: venue(competition.venue))
        }
    }

    private static func tennisSide(_ competitor: ESPNCompetitor) -> NotchScoreSide? {
        guard let id = competitor.id?.text else { return nil }
        let sets = (competitor.linescores?.elements ?? []).compactMap { line -> NotchScoreSet? in
            guard let games = line.value?.integer else { return nil }
            return NotchScoreSet(games: games, tiebreak: line.tiebreak?.integer, won: line.winner ?? false)
        }
        if let athlete = competitor.athlete {
            let name = athlete.displayName ?? athlete.shortName ?? id
            return NotchScoreSide(id: id, name: name, abbreviation: surname(athlete), sets: sets,
                                  winner: competitor.winner ?? false, logo: image(athlete.flag?.href))
        }
        guard let roster = competitor.roster else { return nil }
        let players = roster.athletes?.elements ?? []
        // A pair's ID joins its players' IDs.
        return NotchScoreSide(id: id, name: roster.displayName ?? roster.shortDisplayName ?? id,
                              abbreviation: players.isEmpty ? (roster.shortDisplayName ?? id)
                                : players.map(surname).joined(separator: "/"),
                              sets: sets, winner: competitor.winner ?? false,
                              members: id.split(separator: "-").map(String.init))
    }

    /// The family name a scoreboard shows: Zverev for A. Zverev.
    static func surname(_ athlete: ESPNAthlete) -> String {
        if let last = athlete.lastName, !last.isEmpty { return last }
        let short = athlete.shortName ?? athlete.displayName ?? ""
        if let range = short.range(of: ". ") { return String(short[range.upperBound...]) }
        return short.split(separator: " ").last.map(String.init) ?? short
    }

    /// A followed championship's practice, qualifying, sprints and races.
    private static func racingGames(_ event: ESPNEvent, request: NotchScoreRequest) -> [NotchScoreGame] {
        let grandPrix = event.shortName ?? event.name ?? ""
        return (event.competitions?.elements ?? []).compactMap { session in
            guard let sessionID = session.id?.text, let start = date(session.date ?? event.date) else { return nil }
            let kind = session.type?.abbreviation ?? ""
            // A series that races once a weekend names no session.
            let sides = (session.competitors?.elements ?? []).compactMap { competitor -> NotchScoreSide? in
                guard let id = competitor.id?.text, let athlete = competitor.athlete else { return nil }
                let name = athlete.displayName ?? id
                return NotchScoreSide(id: id, name: name,
                                      abbreviation: athlete.abbreviation ?? driverCode(athlete),
                                      position: competitor.order?.integer, winner: competitor.winner ?? false,
                                      logo: image(athlete.flag?.href), portrait: portrait(athlete: id))
            }.sorted { ($0.position ?? .max) < ($1.position ?? .max) }
            let status = session.status ?? event.status
            let state = state(status)
            return NotchScoreGame(
                id: "racing/\(request.league)#\(sessionID)", sport: .racing, league: request.league,
                title: grandPrix, detail: kind.isEmpty ? nil : kind, start: start, state: state,
                clock: state == .called ? (status?.type?.shortDetail ?? "") : "",
                period: status?.period?.integer ?? 0, sides: sides, followed: [], link: link(event),
                event: event.id?.text)
        }
    }

    /// Where ESPN keeps a racing driver's photo, Formula 1's and NASCAR's alike.
    static func portrait(athlete id: String) -> URL? {
        guard !id.isEmpty, id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://a.espncdn.com/i/headshots/rpm/players/full/\(id).png")
    }

    /// Scoreboards name drivers without the three letters timing screens
    /// use; those are the first three of the surname, as for VER or HAM.
    static func driverCode(_ athlete: ESPNAthlete) -> String {
        String(surname(athlete).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter(\.isLetter).prefix(3)).uppercased()
    }

    static func state(_ status: ESPNStatus?) -> NotchScoreState {
        let name = status?.type?.name?.uppercased() ?? ""
        let phase = status?.type?.state
        // A delay, such as rain in tennis, still leads to a result.
        if name.contains("DELAY") { return phase == "in" ? .live : .scheduled }
        if ["POSTPONED", "CANCELED", "CANCELLED", "SUSPENDED", "ABANDONED", "FORFEIT"].contains(where: name.contains) {
            return .called
        }
        switch phase {
        case "in": return .live
        case "post": return .finished
        default: return .scheduled
        }
    }

    /// Where to load a crest, best first: ESPN's resizer makes a 2 KB image
    /// of a 30 KB one. On the island's black, the version drawn for dark
    /// backgrounds comes first; a team without one falls back to its own.
    static func crestURLs(_ url: URL, dark: Bool, pixels: Int = 64) -> [URL] {
        guard url.host == "a.espncdn.com", url.path.hasPrefix("/i/") else { return [url] }
        var paths = [url.path]
        if dark, url.path.contains("/500/") {
            paths.insert(url.path.replacingOccurrences(of: "/500/", with: "/500-dark/"), at: 0)
        }
        let resized = paths.compactMap { path -> URL? in
            var components = URLComponents(string: "https://a.espncdn.com/combiner/i")
            components?.queryItems = [URLQueryItem(name: "img", value: path),
                                      URLQueryItem(name: "w", value: String(pixels)),
                                      URLQueryItem(name: "h", value: String(pixels))]
            // A photo is wider than tall: cropped square around the face,
            // not squeezed, so it fills a circle.
            if path.hasPrefix("/i/headshots/") {
                components?.queryItems? += [URLQueryItem(name: "scale", value: "crop"),
                                            URLQueryItem(name: "location", value: "origin")]
            }
            return components?.url
        }
        return resized + [url]
    }

    /// Crests and flags come only from ESPN's image servers, over HTTPS.
    static func image(_ href: String?) -> URL? {
        guard let href, let url = URL(string: href), url.scheme == "https",
              url.host?.hasSuffix(".espncdn.com") == true else { return nil }
        return url
    }

    private static func link(_ event: ESPNEvent) -> URL? {
        let links = event.links?.elements ?? []
        let page = links.first { $0.rel?.contains("summary") == true || $0.rel?.contains("live") == true } ?? links.first
        guard let href = page?.href, let url = URL(string: href), url.scheme == "https",
              url.host?.hasSuffix("espn.com") == true else { return nil }
        return url
    }

    // MARK: Standings

    static func standingsURL(sport: NotchScoreSport, league: String) -> URL? {
        guard sport.hasTeams, isValidID(league) else { return nil }
        return URL(string: "https://site.api.espn.com/apis/v2/sports/\(sport.rawValue)/\(league)/standings")
    }

    /// The columns a table shows, by ESPN's stat type: a soccer table's
    /// games and points, a college conference's records, a pro league's
    /// wins, losses and how far behind.
    static func standingColumns(sport: NotchScoreSport, league: String) -> [String] {
        switch sport {
        case .soccer: return ["gamesplayed", "wins", "ties", "losses", "pointdifferential", "points"]
        case .football where league == "nfl": return ["wins", "losses", "ties", "winpercent"]
        // College teams are ranked within their conference, then overall.
        case .football: return ["vsconf", "total"]
        case .basketball where league.contains("college"): return ["vsconf", "total"]
        case .basketball, .baseball: return ["wins", "losses", "winpercent", "gamesbehind"]
        case .hockey: return ["gamesplayed", "wins", "losses", "otlosses", "points"]
        default: return []
        }
    }

    /// Every table in a league's standings: a soccer league's one, a cup's
    /// groups, or each conference or division of the American leagues, in
    /// the order the league ranks them.
    static func standings(from data: Data, sport: NotchScoreSport, league: String) -> [NotchScoreStandingGroup]? {
        guard let root = try? JSONDecoder().decode(ESPNStandingsRoot.self, from: data) else { return nil }
        let columns = standingColumns(sport: sport, league: league)
        guard !columns.isEmpty else { return [] }
        func tables(_ group: ESPNStandingsRoot.Group) -> [NotchScoreStandingGroup] {
            let entries = group.standings?.entries?.elements ?? []
            // A conference split in divisions, as the Sun Belt is, ranks each division.
            let below = (group.children?.elements ?? []).flatMap(tables)
            guard !entries.isEmpty, let name = group.name else { return below }
            let lines = entries.compactMap { entry -> (row: NotchScoreStandingRow, order: Double)? in
                guard let team = entry.team, let id = team.id?.text, let teamName = team.displayName else { return nil }
                var stats: [String: ESPNStandingsRoot.Stat] = [:]
                for stat in entry.stats?.elements ?? [] {
                    guard let type = stat.type?.lowercased(), stats[type] == nil else { continue }
                    stats[type] = stat
                }
                // Soccer ranks; the American leagues seed, or only seed the
                // teams headed for the playoffs, so the rest go by winning share.
                let rank = stats["rank"]?.value?.number ?? stats["playoffseed"]?.value?.number
                let order = rank.flatMap { $0 > 0 ? $0 : nil }
                    ?? 1000 - (stats["winpercent"]?.value?.number ?? stats["leaguewinpercent"]?.value?.number ?? 0) * 100
                let row = NotchScoreStandingRow(
                    id: id, name: teamName, abbreviation: team.abbreviation ?? String(teamName.prefix(3)).uppercased(),
                    logo: image(team.logo ?? team.logos?.elements.first?.href), place: 0,
                    values: columns.map { stats[$0]?.displayValue ?? "–" })
                return (row, order)
            }
            let ranked = lines.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
                .enumerated().map { place, line in
                    let row = line.element.row
                    return NotchScoreStandingRow(id: row.id, name: row.name, abbreviation: row.abbreviation, logo: row.logo,
                                                 place: place + 1, values: row.values)
                }
            return [NotchScoreStandingGroup(name: name, columns: columns, rows: ranked)] + below
        }
        return (root.children?.elements ?? []).flatMap(tables)
    }

    /// The tables a game's teams play in: the whole table of a soccer
    /// league, the group of a cup, or each team's conference.
    static func standings(_ groups: [NotchScoreStandingGroup], for game: NotchScoreGame) -> [NotchScoreStandingGroup] {
        let teams = Set(game.sides.map(\.id))
        return groups.filter { group in group.rows.contains { teams.contains($0.id) } }
    }

    // MARK: Choices

    /// Who can be followed in a league: its teams, the tour's ranked
    /// players in ranking order, or the season's drivers in standings order.
    static func choices(from data: Data, league: NotchScoreLeague) -> [NotchScoreFollow]? {
        choiceList(from: data, league: league)?.teams
    }

    /// Teams by conference where the league has them: an American league's
    /// standings group its teams, and each conference is listed by name.
    static func choiceList(from data: Data, league: NotchScoreLeague) -> NotchScoreChoiceList? {
        guard league.sport.hasTeams, league.sport != .soccer else {
            return plainChoices(from: data, league: league).map { NotchScoreChoiceList(teams: $0) }
        }
        guard let root = try? JSONDecoder().decode(ESPNStandingsRoot.self, from: data) else { return nil }
        var teams: [NotchScoreFollow] = []
        func members(_ group: ESPNStandingsRoot.Group) -> [NotchScoreFollow] {
            let own = (group.standings?.entries?.elements ?? []).compactMap { entry -> NotchScoreFollow? in
                guard let team = entry.team, let id = team.id?.text, isValidID(id), let name = team.displayName else { return nil }
                return NotchScoreFollow(sport: league.sport, league: league.slug, espnID: id, name: name,
                                        abbreviation: team.abbreviation ?? String(name.prefix(3)).uppercased(),
                                        logo: image(team.logo ?? team.logos?.elements.first?.href)?.absoluteString)
            }
            // A conference split in divisions, as the Sun Belt is, lists its teams below them.
            return own + (group.children?.elements ?? []).flatMap(members)
        }
        let conferences = (root.children?.elements ?? []).compactMap { group -> NotchScoreConference? in
            let list = unique(members(group)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard let name = group.name, !list.isEmpty else { return nil }
            teams += list
            return NotchScoreConference(name: name, teams: list.map(\.id))
        }
        let sorted = unique(teams).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !sorted.isEmpty else { return nil }
        return NotchScoreChoiceList(teams: sorted, conferences: conferences)
    }

    private static func plainChoices(from data: Data, league: NotchScoreLeague) -> [NotchScoreFollow]? {
        let decoder = JSONDecoder()
        switch league.sport {
        case .golf, .mma, .racing:
            return nil
        case .soccer, .football, .basketball, .baseball, .hockey:
            guard let root = try? decoder.decode(ESPNTeamsRoot.self, from: data) else { return nil }
            let teams = (root.sports?.elements ?? []).flatMap { $0.leagues?.elements ?? [] }
                .flatMap { $0.teams?.elements ?? [] }.compactMap(\.team)
            return unique(teams.compactMap { team in
                guard let id = team.id?.text, isValidID(id), let name = team.displayName else { return nil }
                return NotchScoreFollow(sport: league.sport, league: league.slug, espnID: id, name: name,
                                        abbreviation: team.abbreviation ?? String(name.prefix(3)).uppercased(),
                                        logo: image(team.logo ?? team.logos?.elements.first?.href)?.absoluteString)
            }).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .tennis:
            guard let root = try? decoder.decode(ESPNRankingsRoot.self, from: data) else { return nil }
            let ranks = root.rankings?.elements.first?.ranks?.elements ?? []
            return unique(ranks.compactMap { rank in
                guard let athlete = rank.athlete, let id = athlete.id?.text, isValidID(id),
                      let name = athlete.displayName else { return nil }
                return NotchScoreFollow(sport: .tennis, league: league.slug, espnID: id, name: name,
                                        abbreviation: surname(athlete), logo: image(athlete.flag?.href)?.absoluteString)
            })
        }
    }

    private static func unique(_ follows: [NotchScoreFollow]) -> [NotchScoreFollow] {
        var seen = Set<String>()
        return follows.filter { seen.insert($0.id).inserted }
    }

    /// Matches a name, its short form or its letters, ignoring case and accents.
    static func matches(_ follow: NotchScoreFollow, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return follow.name.range(of: query, options: options) != nil
            || follow.abbreviation.range(of: query, options: options) != nil
    }
}

// MARK: - ESPN's answers, read leniently

/// Reads each element on its own, so one ESPN changed does not lose the rest.
struct ESPNList<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(ESPNSkip.self)) == nil {
                break
            }
        }
        self.elements = elements
    }
}

struct ESPNSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

/// A value ESPN sends as text in one answer and as a number, or an object
/// holding both, in another.
struct ESPNValue: Decodable {
    let text: String?
    let number: Double?

    var integer: Int? {
        guard let number, number.isFinite, abs(number) < 1_000_000_000 else { return text.flatMap { Int($0) } }
        return Int(number.rounded())
    }

    private struct Holder: Decodable {
        let value: Double?
        let displayValue: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.text = text
            number = Double(text)
        } else if let number = try? container.decode(Double.self) {
            self.number = number
            text = number.isFinite && number == number.rounded() && abs(number) < 1_000_000_000
                ? String(Int(number)) : String(number)
        } else if let holder = try? container.decode(Holder.self) {
            number = holder.value
            text = holder.displayValue ?? holder.value.map { $0 == $0.rounded() && abs($0) < 1_000_000_000 ? String(Int($0)) : String($0) }
        } else {
            text = nil
            number = nil
        }
    }
}

struct ESPNRoot: Decodable {
    let leagues: ESPNList<ESPNLeague>?
    let events: ESPNList<ESPNEvent>?
}

struct ESPNLeague: Decodable {
    let name: String?
    let slug: String?
}

/// A session's drivers with their cars, from ESPN's core API.
struct ESPNCompetitorPage: Decodable {
    struct Item: Decodable {
        let id: ESPNValue?
        let vehicle: Vehicle?
    }
    struct Vehicle: Decodable {
        let number: ESPNValue?
        let manufacturer: String?
        let team: String?
        let teamColor: String?
    }
    let items: ESPNList<Item>?
}

/// A driver's timing in a session, from ESPN's core API.
struct ESPNTiming: Decodable {
    struct Splits: Decodable { let categories: ESPNList<Category>? }
    struct Category: Decodable { let stats: ESPNList<Stat>? }
    struct Stat: Decodable {
        let name: String?
        let value: ESPNValue?
    }
    let splits: Splits?
}

struct ESPNEvent: Decodable {
    let id: ESPNValue?
    let date: String?
    let endDate: String?
    let name: String?
    let shortName: String?
    let status: ESPNStatus?
    let competitions: ESPNList<ESPNCompetition>?
    let groupings: ESPNList<ESPNGrouping>?
    let league: ESPNLeague?
    let links: ESPNList<ESPNLink>?
}

struct ESPNGrouping: Decodable {
    struct Name: Decodable { let slug: String? }
    let grouping: Name?
    let competitions: ESPNList<ESPNCompetition>?
}

struct ESPNCompetition: Decodable {
    struct Kind: Decodable { let abbreviation: String? }
    struct Round: Decodable { let displayName: String? }
    struct Venue: Decodable {
        struct Address: Decodable { let city: String? }
        let fullName: String?
        let address: Address?
    }
    struct Reference: Decodable { let id: ESPNValue? }
    struct Detail: Decodable {
        struct Clock: Decodable { let displayValue: String? }
        let clock: Clock?
        let team: Reference?
        let scoringPlay: Bool?
        let redCard: Bool?
        let yellowCard: Bool?
        let penaltyKick: Bool?
        let ownGoal: Bool?
        let shootout: Bool?
        let athletesInvolved: ESPNList<ESPNAthlete>?
    }
    struct Situation: Decodable {
        struct Play: Decodable { let text: String? }
        struct Player: Decodable { let athlete: ESPNAthlete? }
        let downDistanceText: String?
        let possession: ESPNValue?
        let lastPlay: Play?
        let isRedZone: Bool?
        let balls: ESPNValue?
        let strikes: ESPNValue?
        let outs: ESPNValue?
        let onFirst: Bool?
        let onSecond: Bool?
        let onThird: Bool?
        let batter: Player?
        let pitcher: Player?
    }
    struct LeaderCategory: Decodable {
        struct Leader: Decodable {
            let displayValue: String?
            let athlete: ESPNAthlete?
            let team: Reference?
        }
        let name: String?
        let leaders: ESPNList<Leader>?
    }

    let id: ESPNValue?
    let date: String?
    let status: ESPNStatus?
    let competitors: ESPNList<ESPNCompetitor>?
    let type: Kind?
    let round: Round?
    let venue: Venue?
    let details: ESPNList<Detail>?
    let situation: Situation?
    let leaders: ESPNList<LeaderCategory>?
    let format: ESPNFormat?
}

/// How many periods, rounds or innings make a game before overtime.
struct ESPNFormat: Decodable {
    struct Regulation: Decodable { let periods: ESPNValue? }
    let regulation: Regulation?
}

struct ESPNStatus: Decodable {
    struct Kind: Decodable {
        let name: String?
        let state: String?
        let completed: Bool?
        let shortDetail: String?
    }

    let displayClock: String?
    let period: ESPNValue?
    let type: Kind?
}

struct ESPNCompetitor: Decodable {
    struct Line: Decodable {
        let value: ESPNValue?
        let displayValue: String?
        let tiebreak: ESPNValue?
        let winner: Bool?
        /// A golf round's holes.
        let linescores: ESPNList<Line>?
    }

    let id: ESPNValue?
    let homeAway: String?
    let order: ESPNValue?
    let winner: Bool?
    let score: ESPNValue?
    let team: ESPNTeam?
    let athlete: ESPNAthlete?
    let roster: ESPNRoster?
    let linescores: ESPNList<Line>?
    struct Stat: Decodable {
        let name: String?
        let displayValue: String?
    }
    struct Record: Decodable { let summary: String? }
    let statistics: ESPNList<Stat>?
    let records: ESPNList<Record>?
    let leaders: ESPNList<ESPNCompetition.LeaderCategory>?
    let hits: ESPNValue?
    let errors: ESPNValue?
}

/// A picture's address, sent as an object in scoreboards and as plain
/// text in rankings.
struct ESPNImage: Decodable {
    let href: String?

    private enum Keys: String, CodingKey { case href }

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            href = text
        } else {
            href = try? decoder.container(keyedBy: Keys.self).decodeIfPresent(String.self, forKey: .href)
        }
    }
}

struct ESPNTeam: Decodable {
    let id: ESPNValue?
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
    let logo: String?
    let logos: ESPNList<ESPNImage>?
}

struct ESPNAthlete: Decodable {
    let id: ESPNValue?
    let displayName: String?
    let shortName: String?
    let lastName: String?
    let abbreviation: String?
    let flag: ESPNImage?
}

struct ESPNRoster: Decodable {
    let displayName: String?
    let shortDisplayName: String?
    let athletes: ESPNList<ESPNAthlete>?
}

struct ESPNLink: Decodable {
    let href: String?
    let rel: [String]?
}

struct ESPNTeamsRoot: Decodable {
    struct Sport: Decodable { let leagues: ESPNList<League>? }
    struct League: Decodable { let teams: ESPNList<Entry>? }
    struct Entry: Decodable { let team: ESPNTeam? }
    let sports: ESPNList<Sport>?
}

struct ESPNRankingsRoot: Decodable {
    struct Ranking: Decodable { let ranks: ESPNList<Rank>? }
    struct Rank: Decodable { let athlete: ESPNAthlete? }
    let rankings: ESPNList<Ranking>?
}

struct ESPNStandingsRoot: Decodable {
    /// A conference, or a division within one.
    struct Group: Decodable {
        let name: String?
        let standings: Standings?
        let children: ESPNList<Group>?
    }
    struct Standings: Decodable { let entries: ESPNList<Entry>? }
    struct Stat: Decodable {
        let type: String?
        let value: ESPNValue?
        let displayValue: String?
    }
    struct Entry: Decodable {
        let team: ESPNTeam?
        let stats: ESPNList<Stat>?
    }
    let children: ESPNList<Group>?
}
