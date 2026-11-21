// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Follows the chosen teams' and athletes' games on ESPN's public
/// scoreboards: their fixtures every few hours, and the scoreboards that
/// hold them while they are under way.
final class NotchScoresService: ObservableObject {
    static let shared = NotchScoresService()

    enum Phase: Equatable { case idle, loading, ready, unavailable }

    @Published private(set) var games: [NotchScoreGame] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var follows: [NotchScoreFollow] = []
    /// When each game was seen ending, so its result stays a while.
    @Published private(set) var finishedAt: [String: Date] = [:]
    /// Who can be followed, by league, as last loaded.
    @Published private(set) var choices: [String: [NotchScoreFollow]] = [:]
    /// Each league's conferences, where it has them.
    @Published private(set) var conferences: [String: [NotchScoreConference]] = [:]
    /// Each league's tables, by "sport/league", read when a game of it is opened.
    @Published private(set) var standings: [String: [NotchScoreStandingGroup]] = [:]
    private var standingsRead: [String: Date] = [:]
    private var loadingStandings = Set<String>()
    @Published private(set) var loadingChoices: Set<String> = []
    @Published private(set) var failedChoices: Set<String> = []
    /// Racing drivers' cars by "league/driver", read once a session.
    @Published private(set) var liveries: [String: NotchScoreLivery] = [:]
    private var liveriesRead: [String: Date] = [:]
    /// The scores page is open: a game under way is read every few seconds,
    /// and opening it reads one at once.
    var pageVisible = false {
        didSet {
            guard pageVisible, !oldValue, running, !polling, games.contains(where: { $0.state == .live }),
                  (timer?.fireDate.timeIntervalSinceNow ?? 0) > 1 else { return }
            schedule(after: 0)
        }
    }

    private var pace: NotchScorePace {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .saving }
        return pageVisible ? .watching : .glancing
    }

    private var store: [String: NotchScoreGame] = [:]
    private var lastDiscovery: Date?
    private var timer: Timer?
    private var running = false
    private var polling = false
    /// Bumped on every stop and change of follows, so an answer to an
    /// older question is dropped.
    private var generation = 0
    private var sessions: [URLSession] = []

    private init() {}

    /// The game the closed island shows, if any.
    var featured: NotchScoreGame? {
        NotchScoresSupport.featured(games, finishedAt: finishedAt, now: Date())
    }

    var isActive: Bool { running && featured != nil }

    /// Cheap to call often: it publishes only what changed, so the island
    /// redraws only for news.
    func syncWithPreferences() {
        guard NotchScoresSupport.isEnabled() else { stop(); return }
        let saved = NotchScoresSupport.follows()
        let changed = saved != follows
        if changed {
            follows = saved
            generation += 1
            polling = false
            lastDiscovery = nil
            store = NotchScoresSupport.kept(store, follows: saved, now: Date())
            publish()
        }
        guard !saved.isEmpty else {
            if running || changed {
                running = false
                timer?.invalidate(); timer = nil
                cancelDownloads()
            }
            if phase != .idle { phase = .idle }
            return
        }
        if !running || changed {
            running = true
            schedule(after: 0)
        }
    }

    /// Drops the games and stops every reading. Lists of who can be followed
    /// are public and stay, so Settings does not ask for them again.
    func stop() {
        guard running || !store.isEmpty || !follows.isEmpty || timer != nil || !sessions.isEmpty else { return }
        generation += 1
        running = false
        polling = false
        timer?.invalidate(); timer = nil
        cancelDownloads()
        store = [:]
        lastDiscovery = nil
        if !games.isEmpty { games = [] }
        if !finishedAt.isEmpty { finishedAt = [:] }
        if !follows.isEmpty { follows = [] }
        if phase != .idle { phase = .idle }
    }

    /// Lists the fixtures again now, as when the page asks.
    func refresh() {
        guard running, !polling else { return }
        lastDiscovery = nil
        schedule(after: 0)
    }

    func toggle(_ follow: NotchScoreFollow) {
        var saved = NotchScoresSupport.follows()
        if let index = saved.firstIndex(where: { $0.id == follow.id }) { saved.remove(at: index) }
        else { saved.append(follow) }
        // Settings reads the saved list itself, so it is current even while
        // the section is off.
        NotchScoresSupport.save(saved)
        syncWithPreferences()
    }

    /// Who can be followed in `league`, loaded once a session.
    func loadChoices(for league: NotchScoreLeague) {
        guard choices[league.id] == nil, !loadingChoices.contains(league.id),
              let url = NotchScoresSupport.choicesURL(for: league) else { return }
        loadingChoices.insert(league.id)
        failedChoices.remove(league.id)
        download(url, tracked: false, maximumBytes: NotchScoresSupport.choicesMaximumBytes) { [weak self] data in
            // A college league's standings take a moment to read; the
            // Settings window keeps moving meanwhile.
            DispatchQueue.global(qos: .userInitiated).async {
                let list = data.flatMap { NotchScoresSupport.choiceList(from: $0, league: league) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loadingChoices.remove(league.id)
                    if let list, !list.teams.isEmpty {
                        self.choices[league.id] = list.teams
                        self.conferences[league.id] = list.conferences
                    } else {
                        self.failedChoices.insert(league.id)
                    }
                }
            }
        }
    }

    /// The tables of a game's league, read again after ten minutes, and as
    /// soon as one of its games ends; a table changes only between games.
    func loadStandings(for game: NotchScoreGame) {
        let key = game.sport.rawValue + "/" + game.league
        guard !loadingStandings.contains(key),
              Date().timeIntervalSince(standingsRead[key] ?? .distantPast) > NotchScoresSupport.standingsInterval,
              let url = NotchScoresSupport.standingsURL(sport: game.sport, league: game.league) else { return }
        loadingStandings.insert(key)
        let sport = game.sport, league = game.league
        download(url, tracked: false, maximumBytes: NotchScoresSupport.choicesMaximumBytes) { [weak self] data in
            DispatchQueue.global(qos: .userInitiated).async {
                let tables = data.flatMap { NotchScoresSupport.standings(from: $0, sport: sport, league: league) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loadingStandings.remove(key)
                    // A cup without a table answers too; it is not asked again soon.
                    self.standingsRead[key] = Date()
                    if let tables { self.standings[key] = tables }
                }
            }
        }
    }

    func retryChoices(for league: NotchScoreLeague) {
        failedChoices.remove(league.id)
        loadChoices(for: league)
    }

    // MARK: Polling

    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { [weak self] _ in self?.poll() }
        timer.tolerance = min(15, max(0, delay) * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard running, !polling, !follows.isEmpty else { return }
        polling = true
        let generation = self.generation
        let follows = self.follows
        let now = Date()
        let discovers = NotchScoresSupport.discoveryIsDue(lastDiscovery: lastDiscovery, now: now)
        if store.isEmpty { phase = .loading }
        let discovery = discovers ? NotchScoresSupport.discoveryRequests(for: follows) : []
        fetch(discovery, follows: follows, generation: generation) { [weak self] listed, listedFailures in
            guard let self, generation == self.generation else { return }
            // Fixtures just listed may start now, so the scoreboards are
            // chosen from them too. A tour's scoreboard read to list its
            // matches is not read twice.
            let known = NotchScoresSupport.sorted(NotchScoresSupport.merge(self.store, with: listed))
            let read = Set(discovery.map(\.url))
            let boards = NotchScoresSupport.dueScoreboards(known, now: Date())
                .compactMap(NotchScoresSupport.request(for:)).filter { !read.contains($0.url) }
            self.fetch(boards, follows: follows, generation: generation) { [weak self] live, liveFailures in
                guard let self, generation == self.generation else { return }
                let attempts = discovery.count + boards.count
                self.qualifying(listed + live, generation: generation) { [weak self] games in
                    guard let self, generation == self.generation else { return }
                    self.apply(games, discovered: discovers && listedFailures < discovery.count,
                               failed: attempts > 0 && listedFailures + liveFailures == attempts)
                }
            }
        }
    }

    private func fetch(_ requests: [NotchScoreRequest], follows: [NotchScoreFollow], generation: Int,
                       completion: @escaping ([NotchScoreGame], Int) -> Void) {
        guard !requests.isEmpty else { completion([], 0); return }
        var games: [NotchScoreGame] = []
        var failures = 0
        var remaining = requests.count
        for request in requests {
            download(request.url) { [weak self] data in
                guard let self, generation == self.generation else { return }
                if let data, let found = NotchScoresSupport.games(from: data, request: request, follows: follows) {
                    games += found
                } else {
                    failures += 1
                }
                remaining -= 1
                if remaining == 0 { completion(games, failures) }
            }
        }
    }

    /// A live qualifying's part, read from two drivers' timing, since the
    /// scoreboard says only that it is under way.
    private func qualifying(_ games: [NotchScoreGame], generation: Int, completion: @escaping ([NotchScoreGame]) -> Void) {
        var games = games.map { game -> NotchScoreGame in
            var game = game
            game.segment = max(game.segment, store[game.id]?.segment ?? 0)
            return game
        }
        let probes = games.indices.flatMap { index in NotchScoresSupport.segmentProbes(games[index]).map { (index, $0) } }
        guard !probes.isEmpty else { completion(games); return }
        var finished: [Int: [Int: Bool]] = [:]
        var remaining = probes.count
        for (index, probe) in probes {
            download(probe.url) { [weak self] data in
                guard let self, generation == self.generation else { return }
                if let found = data.flatMap({ NotchScoresSupport.hasQualifyingTime($0, part: probe.part) }) {
                    finished[index, default: [:]][probe.part] = found
                }
                remaining -= 1
                guard remaining == 0 else { return }
                for (index, parts) in finished {
                    games[index].segment = NotchScoresSupport.segment(previous: games[index].segment, finished: parts)
                }
                completion(games)
            }
        }
    }

    private func apply(_ incoming: [NotchScoreGame], discovered: Bool, failed: Bool) {
        polling = false
        guard running else { return }
        let now = Date()
        if discovered { lastDiscovery = now }
        let previous = store
        store = NotchScoresSupport.kept(NotchScoresSupport.merge(store, with: incoming), follows: follows, now: now)
        var changes: [(NotchScoreChange, NotchScoreGame)] = []
        for id in Set(incoming.map(\.id)) {
            guard let old = previous[id], let new = store[id] else { continue }
            if old.state == .live, new.state == .finished {
                finishedAt[id] = now
                // The result moves the table: one already shown is read again.
                let key = new.sport.rawValue + "/" + new.league
                if standings[key] != nil {
                    standingsRead[key] = nil
                    loadStandings(for: new)
                }
            }
            if let change = NotchScoresSupport.change(from: old, to: new) { changes.append((change, new)) }
        }
        finishedAt = finishedAt.filter { store[$0.key] != nil && now.timeIntervalSince($0.value) < NotchScoresSupport.finalHold }
        phase = failed && store.isEmpty ? .unavailable : .ready
        publish()
        // The latest change speaks last, so it is the one left on screen.
        for (change, game) in changes.sorted(by: { $0.1.start < $1.1.start }) { announce(change, in: game) }
        loadLiveries()
        let next = NotchScoresSupport.nextPoll(games, lastDiscovery: lastDiscovery, now: now, pace: pace)
        // A failed reading waits a little longer, without losing a game under way.
        schedule(after: failed ? max(next, 60) : next)
        // A result leaves the island once its time there is up.
        if let hold = finishedAt.values.map({ $0.addingTimeInterval(NotchScoresSupport.finalHold).timeIntervalSince(now) })
            .filter({ $0 > 0 }).min(), hold < next {
            DispatchQueue.main.asyncAfter(deadline: .now() + hold + 1) { [weak self] in
                guard let self, self.running else { return }
                self.finishedAt = self.finishedAt.filter { Date().timeIntervalSince($0.value) < NotchScoresSupport.finalHold }
            }
        }
    }

    /// Each racing session's cars, once its drivers are listed: their team
    /// colors behind the drivers on the page and the island. A session
    /// whose cars are all known is not asked; one that did not answer
    /// waits ten minutes.
    private func loadLiveries() {
        for game in store.values where game.sport == .racing && !game.sides.isEmpty {
            guard game.sides.contains(where: { liveries[game.league + "/" + $0.id] == nil }),
                  Date().timeIntervalSince(liveriesRead[game.id] ?? .distantPast) > 10 * 60,
                  let url = NotchScoresSupport.liveryURL(game) else { continue }
            liveriesRead[game.id] = Date()
            let league = game.league
            download(url, tracked: false) { [weak self] data in
                guard let self, let found = data.flatMap(NotchScoresSupport.liveries(from:)), !found.isEmpty else { return }
                var merged = self.liveries
                for (id, livery) in found { merged[league + "/" + id] = livery }
                if merged != self.liveries { self.liveries = merged }
            }
        }
    }

    func livery(_ side: NotchScoreSide, in game: NotchScoreGame) -> NotchScoreLivery? {
        liveries[game.league + "/" + side.id]
    }

    private func publish() {
        let sorted = NotchScoresSupport.sorted(store)
        if sorted != games { games = sorted }
    }

    private func announce(_ change: NotchScoreChange, in game: NotchScoreGame) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchScoresAlerts) else { return }
        let notch = NotchService.shared
        // The page already shows it.
        guard !(notch.expanded && notch.selected == .scores) else { return }
        let language = L10n.shared.language
        let text = FeatureStrings.notchScores(language)
        var title = text.headline(change)
        var detail: String?
        let reaction: NotchMascotReaction
        switch change {
        case .bout(let index, let winner):
            guard game.bouts.indices.contains(index), game.bouts[index].sides.indices.contains(winner) else { return }
            let bout = game.bouts[index]
            title = text.wins(bout.sides[winner].abbreviation)
            detail = [bout.division, bout.round > 0 ? "R\(bout.round) " + bout.clock : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            reaction = .perk
        case .scored(let index, _), .set(let index):
            guard game.sides.indices.contains(index) else { return }
            let side = game.sides[index]
            title += " · " + side.abbreviation
            // A game followed only through its league has no side to root for.
            reaction = game.followed.isEmpty ? .perk : game.followed.contains(side.id) ? .celebrate : .surprised
        case .started:
            reaction = .bounce
        case .finished:
            let won = game.sides.contains { game.followed.contains($0.id) && $0.winner }
            reaction = won ? .celebrate : .perk
        }
        let strip = NotchScoresSupport.stripText(game, text: text, locale: language.formattingLocale(), now: Date())
        _ = notch.show(NotchNotice(event: .score, title: title,
                                   detail: detail ?? NotchScoresSupport.capsuleText(strip, sport: game.sport),
                                   symbol: game.sport.symbol,
                                   mascot: reaction))
        notch.reactMascot(reaction)
    }

    // MARK: Network

    /// Readings are tracked so stopping cancels them; a list asked for in
    /// Settings finishes on its own, whatever happens to the games.
    private func download(_ url: URL, tracked: Bool = true, maximumBytes: Int = NotchScoresSupport.maximumBytes,
                          completion: @escaping (Data?) -> Void) {
        var session: URLSession?
        session = NotchScoresDownload.load(url, maximumBytes: maximumBytes) { [weak self] data in
            DispatchQueue.main.async {
                if let self, let session { self.sessions.removeAll { $0 === session } }
                completion(data)
            }
        }
        if tracked, let session { sessions.append(session) }
    }

    private func cancelDownloads() {
        sessions.forEach { $0.invalidateAndCancel() }
        sessions = []
    }
}

/// Crests and flags, small and in memory, each loaded once. The island
/// draws them on every frame, so they never wait on the network twice.
final class NotchScoresCrests: ObservableObject {
    static let shared = NotchScoresCrests()

    @Published private(set) var images: [String: NSImage] = [:]
    private var loading = Set<String>()
    private var missing = Set<String>()
    private static let limit = 400

    private init() {}

    private static func key(_ url: URL, dark: Bool) -> String { (dark ? "dark " : "light ") + url.absoluteString }

    func image(_ url: URL?, dark: Bool) -> NSImage? {
        url.flatMap { images[Self.key($0, dark: dark)] }
    }

    func load(_ url: URL?, dark: Bool) {
        guard let url, NotchScoresSupport.image(url.absoluteString) != nil else { return }
        let key = Self.key(url, dark: dark)
        guard images[key] == nil, !loading.contains(key), !missing.contains(key) else { return }
        loading.insert(key)
        attempt(NotchScoresSupport.crestURLs(url, dark: dark), key: key)
    }

    /// The next address when one has no image, as for a team without a
    /// crest drawn for dark backgrounds.
    private func attempt(_ candidates: [URL], key: String) {
        guard let url = candidates.first else {
            loading.remove(key)
            missing.insert(key)
            return
        }
        _ = NotchScoresDownload.load(url, accept: "image/*") { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, let image = NSImage(data: data), image.isValid else {
                    self.attempt(Array(candidates.dropFirst()), key: key)
                    return
                }
                self.loading.remove(key)
                if self.images.count >= Self.limit { self.images.removeAll() }
                self.images[key] = image
            }
        }
    }
}

/// One bounded request: no cookies, no cache, no redirects.
private final class NotchScoresDownload: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private let completion: (Data?) -> Void
    private let maximumBytes: Int

    private init(maximumBytes: Int, completion: @escaping (Data?) -> Void) {
        self.maximumBytes = maximumBytes
        self.completion = completion
    }

    static func load(_ url: URL, accept: String = "application/json", maximumBytes: Int = NotchScoresSupport.maximumBytes,
                     completion: @escaping (Data?) -> Void) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Developer"
        configuration.httpAdditionalHeaders = ["User-Agent": "Vorssaint/\(version) (https://github.com/vorssaint/vorssaint-utils)",
                                               "Accept": accept]
        let delegate = NotchScoresDownload(maximumBytes: maximumBytes, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        accepted = (response as? HTTPURLResponse)?.statusCode == 200
            && response.expectedContentLength <= maximumBytes
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= maximumBytes - data.count else {
            accepted = false
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && accepted ? data : nil)
    }
}
