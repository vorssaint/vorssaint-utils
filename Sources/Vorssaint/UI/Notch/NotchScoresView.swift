// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

// MARK: - Settings

/// Whether the section is on, how it speaks up, and who it follows: the
/// current follows, then a sport or league, a conference where it has
/// them, and the league as a whole or its teams or players. Racing series,
/// golf tours and the UFC are followed whole. Every row stacks when the
/// window is narrow, so no menu is cut.
struct NotchScoresSettingsControls: View {
    @ObservedObject private var scores = NotchScoresService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchScoresEnabled) private var enabled = true
    @AppStorage(DefaultsKey.notchScoresLiveActivity) private var liveActivity = true
    @AppStorage(DefaultsKey.notchScoresAlerts) private var alerts = true
    @AppStorage(DefaultsKey.notchScoresFollows) private var storedFollows = ""
    @State private var category: NotchScoreCategory = .soccer
    @State private var region = NotchScoreRegion.preferred()
    @State private var leagueID = NotchScoreCategory.soccer.leagues.first { $0.region == NotchScoreRegion.preferred() }?.id ?? ""
    @State private var conference = ""
    @State private var query = ""

    private var text: NotchScoresStrings { FeatureStrings.notchScores(l10n.language) }
    private var follows: [NotchScoreFollow] { NotchScoresSupport.follows(stored: storedFollows) }
    /// Soccer's leagues of the chosen country; every other choice's own.
    private var leagues: [NotchScoreLeague] {
        category.browsesByRegion ? category.leagues.filter { $0.region == region } : category.leagues
    }
    private var league: NotchScoreLeague? {
        leagues.first { $0.id == leagueID } ?? leagues.first
    }
    private var leagueConferences: [NotchScoreConference] { league.flatMap { scores.conferences[$0.id] } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.title, isOn: $enabled)
                .disabled(!AppFeature.notchScores.isAvailable)
            Text(text.description).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                Toggle(text.liveActivity, isOn: $liveActivity)
                Toggle(text.alerts, isOn: $alerts)
                Divider()
                followingList
                Divider()
                picker
                Text(text.source).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: enabled) { _, on in
            NotchService.shared.syncWithPreferences()
            if on { loadChoices() }
        }
        .onChange(of: liveActivity) { NotchService.shared.syncWithPreferences() }
        .onChange(of: category) {
            query = ""
            conference = ""
            leagueID = leagues.first?.id ?? ""
            loadChoices()
        }
        .onChange(of: region) {
            query = ""
            leagueID = leagues.first?.id ?? ""
            loadChoices()
        }
        .onChange(of: leagueID) {
            conference = ""
            loadChoices()
        }
        .onChange(of: leagueConferences) { _, conferences in
            if !conferences.contains(where: { $0.name == conference }) { conference = conferences.first?.name ?? "" }
        }
        .onAppear { if enabled { loadChoices() } }
    }

    @ViewBuilder private var followingList: some View {
        Text(text.following).font(.subheadline.weight(.medium))
        if follows.isEmpty {
            Text(text.noneFollowed).font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(follows) { follow in
                HStack(spacing: 8) {
                    mark(follow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(follow.wholeLeague ? leagueTitle(follow) : follow.name).lineLimit(1)
                        Text(follow.wholeLeague ? text.whole(follow.sport) : leagueTitle(follow))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button { scores.toggle(follow) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(text.unfollow)
                    .accessibilityLabel(text.unfollow + ", " + (follow.wholeLeague ? leagueTitle(follow) : follow.name))
                }
            }
        }
    }

    @ViewBuilder private var picker: some View {
        Text(text.add).font(.subheadline.weight(.medium))
        Group {
            SettingsMenuRow(symbol: category.symbol, title: text.sportLabel, selection: $category) {
                ForEach(NotchScoreCategory.allCases) { Text($0.title(text)).tag($0) }
            }
            if category.browsesByRegion {
                SettingsMenuRow(symbol: "globe", title: text.country, selection: $region) {
                    ForEach(NotchScoreRegion.allCases) {
                        Text($0.title(text, locale: l10n.language.formattingLocale())).tag($0)
                    }
                }
            }
            if leagues.count > 1 {
                SettingsMenuRow(symbol: "trophy", title: text.league, selection: $leagueID) {
                    ForEach(leagues) { Text($0.title(text)).tag($0.id) }
                }
            }
            if let league {
                if league.followsWhole { wholeLeagueRow(league) }
                // A championship, a tour or a promotion has no one to pick: its
                // races, tournaments and cards are the news. A continental
                // cup's clubs are picked in their own country.
                if !category.sport.followsWhole, league.picksTeams {
                    if leagueConferences.count > 1 {
                        SettingsMenuRow(symbol: "rectangle.3.group", title: text.conference, selection: $conference) {
                            ForEach(leagueConferences) { Text($0.name).tag($0.name) }
                        }
                    }
                    TextField(text.search, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                    choiceList(league)
                }
            }
        }
        .disabled(!AppFeature.notchScores.isAvailable)
    }

    private func wholeLeagueRow(_ league: NotchScoreLeague) -> some View {
        let follow = NotchScoreFollow(league: league)
        let following = follows.contains { $0.id == follow.id }
        let title = leagueTitle(follow)
        return Button { scores.toggle(follow) } label: {
            HStack(spacing: 8) {
                Image(systemName: following ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(following ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(text.whole(league.sport)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((following ? text.unfollow : text.follow) + ", " + title + ", " + text.whole(league.sport))
    }

    /// The chosen conference's teams; a search looks through the whole league.
    private func shown(_ league: NotchScoreLeague) -> [NotchScoreFollow] {
        let teams = scores.choices[league.id] ?? []
        guard query.trimmingCharacters(in: .whitespaces).isEmpty,
              let members = leagueConferences.first(where: { $0.name == conference })?.teams else {
            return teams.filter { NotchScoresSupport.matches($0, query: query) }
        }
        let wanted = Set(members)
        return teams.filter { wanted.contains($0.id) }
    }

    @ViewBuilder private func choiceList(_ league: NotchScoreLeague) -> some View {
        let list = shown(league)
        if scores.loadingChoices.contains(league.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(text.loading).font(.caption).foregroundStyle(.secondary)
            }
        } else if scores.failedChoices.contains(league.id) {
            HStack(spacing: 8) {
                Text(text.unavailable).font(.caption).foregroundStyle(.secondary)
                Button(text.refresh) { scores.retryChoices(for: league) }.controlSize(.small)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(list) { choice in choiceRow(choice) }
                }
            }
            .frame(height: min(220, CGFloat(max(list.count, 1)) * 26))
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func choiceRow(_ choice: NotchScoreFollow) -> some View {
        // Read from storage so the mark follows every change at once.
        let following = follows.contains { $0.id == choice.id }
        return Button { scores.toggle(choice) } label: {
            HStack(spacing: 8) {
                Image(systemName: following ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(following ? Color.accentColor : .secondary)
                NotchScoreCrest(url: choice.logo.flatMap(URL.init(string:)), size: 16, dark: false)
                Text(choice.name).lineLimit(1)
                Text(choice.abbreviation).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((following ? text.unfollow : text.follow) + ", " + choice.name)
    }

    @ViewBuilder private func mark(_ follow: NotchScoreFollow) -> some View {
        if follow.wholeLeague || follow.logo == nil {
            Image(systemName: follow.sport.symbol).foregroundStyle(.secondary).frame(width: 18, height: 18)
        } else {
            NotchScoreCrest(url: follow.logo.flatMap(URL.init(string:)), size: 18, dark: false,
                            placeholder: follow.sport.symbol)
        }
    }

    /// The league's own name, or the menu's when the menu names it alone,
    /// as College Football does in every language.
    private func leagueTitle(_ follow: NotchScoreFollow) -> String {
        guard let category = NotchScoreCategory.containing(sport: follow.sport, league: follow.league) else {
            return text.sport(follow.sport)
        }
        if category.leagues.count == 1 { return category.title(text) }
        // A league no longer offered, as Série B, still reads by its name.
        return category.allLeagues.first { $0.slug == follow.league }?.title(text) ?? category.title(text)
    }

    private func loadChoices() {
        guard enabled, AppFeature.notchScores.isAvailable, !category.sport.followsWhole, let league, league.picksTeams else { return }
        scores.loadChoices(for: league)
    }
}

// MARK: - Page

/// The open island: the games side by side to switch between, and the one
/// chosen in full, with its clock, its moments and its statistics.
struct NotchScoresView: View {
    let size: CGSize
    @ObservedObject private var scores = NotchScoresService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchScoresEnabled) private var enabled = true
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chosen: String?
    private var text: NotchScoresStrings { FeatureStrings.notchScores(l10n.language) }

    var body: some View {
        Group {
            if preview {
                // The games followed as they stand, or a sample of the page
                // until one is on, so Settings shows what the island will.
                page(enabled && !scores.follows.isEmpty ? shown ?? sample : sample)
            } else if !enabled || scores.follows.isEmpty {
                NotchEmptyView(symbol: "sportscourt", message: text.emptyPage) {
                    NotchPillButton(title: text.chooseTeams, prominent: true) {
                        NotchService.shared.openSettings(showing: .scores)
                    }
                }
            } else if let game = shown {
                page(game)
            } else {
                switch scores.phase {
                case .loading, .idle:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    NotchEmptyView(symbol: "wifi.exclamationmark", message: text.unavailable) {
                        NotchPillButton(title: text.refresh, prominent: true) { scores.refresh() }
                    }
                case .ready:
                    NotchEmptyView(symbol: "calendar", message: text.nothingSoon)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if !preview { scores.pageVisible = true } }
        .onDisappear { if !preview { scores.pageVisible = false } }
    }

    private var sample: NotchScoreGame { NotchScoresSupport.sample(text: text, now: Date()) }

    /// The chips to switch games, and the one chosen in full. A new choice
    /// cross-fades in place; nothing slides, so the page never jumps.
    private func page(_ game: NotchScoreGame) -> some View {
        let games = game.id == sample.id ? [game] : ordered
        return VStack(alignment: .leading, spacing: 8) {
            if games.count > 1 {
                NotchScoreChips(games: games, selected: game.id) { id in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { chosen = id }
                }
            }
            ScrollView {
                NotchScoreDetail(game: game, wide: size.width >= 440)
                    .padding(.bottom, 4)
                    .id(game.id)
                    .transition(.opacity)
            }
            .scrollIndicators(.never)
        }
        .notchBand(trailing: {
            NotchIconButton(symbol: "arrow.clockwise", title: text.refresh) { scores.refresh() }
        })
    }

    /// Games under way, then the next ones, then the latest results.
    private var ordered: [NotchScoreGame] {
        let games = scores.games
        let live = games.filter { $0.state == .live }.sorted { !$0.followed.isEmpty && $1.followed.isEmpty }
        let upcoming = games.filter { $0.state == .scheduled }.prefix(10)
        let results = games.filter { $0.state == .finished || $0.state == .called }.reversed().prefix(8)
        return live + upcoming + results
    }

    /// The game chosen, or the island's own, or the first worth showing.
    private var shown: NotchScoreGame? {
        let games = ordered
        if let chosen, let game = games.first(where: { $0.id == chosen }) { return game }
        if let featured = scores.featured, games.contains(where: { $0.id == featured.id }) { return featured }
        return games.first
    }
}

/// Every game as a small chip: crests and the score, or the start time.
private struct NotchScoreChips: View {
    let games: [NotchScoreGame]
    let selected: String
    let choose: (String) -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(games) { game in
                        Button { choose(game.id) } label: { chip(game) }
                            .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
                            .id(game.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .onAppear { reader.scrollTo(selected, anchor: .center) }
        }
        .frame(height: 26)
    }

    private func chip(_ game: NotchScoreGame) -> some View {
        let text = FeatureStrings.notchScores(l10n.language)
        let isSelected = game.id == selected
        return HStack(spacing: 5) {
            if game.state == .live { Circle().fill(.red).frame(width: 5, height: 5) }
            if game.sport.isField || game.sport == .mma {
                Image(systemName: game.sport.symbol).font(.system(size: 10, weight: .semibold))
                Text(game.sport == .racing
                     ? [text.session(game.detail ?? game.title), game.segmentText].compactMap { $0 }.joined(separator: " · ")
                     : game.title)
                    .frame(maxWidth: 150)
            } else {
                NotchScoreCrest(url: game.sides.first?.logo, size: 14, placeholder: game.sport.symbol)
                Text(reading(game, text: text)).monospacedDigit()
                    .modifier(NotchScoreRolling(value: reading(game, text: text)))
                NotchScoreCrest(url: game.sides.dropFirst().first?.logo, size: 14, placeholder: game.sport.symbol)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(.white.opacity(isSelected ? 0.16 : 0.06), in: Capsule())
        .contentShape(Capsule())
        .accessibilityLabel(NotchScoresSupport.capsuleText(
            NotchScoresSupport.stripText(game, text: text, locale: l10n.language.formattingLocale(), now: Date()),
            sport: game.sport))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func reading(_ game: NotchScoreGame, text: NotchScoresStrings) -> String {
        guard game.state != .scheduled else {
            return NotchScoresSupport.startText(game.start, locale: l10n.language.formattingLocale(), now: Date())
        }
        if game.sport == .tennis, game.sides.count == 2 { return "\(game.sides[0].setsWon)–\(game.sides[1].setsWon)" }
        return (game.sides.first?.score ?? "") + "–" + (game.sides.dropFirst().first?.score ?? "")
    }
}

/// One game in full: who plays, the score and the clock, where, and what
/// the scoreboard tells of it so far.
private struct NotchScoreDetail: View {
    let game: NotchScoreGame
    /// Wide enough to set moments and statistics side by side.
    let wide: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var scores = NotchScoresService.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchScoresStrings { FeatureStrings.notchScores(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    /// The page's quieter text, brought up near full white with Increase
    /// Contrast so the small print still reads on the black.
    private func faint(_ opacity: Double) -> Color {
        .white.opacity(contrast == .increased ? max(opacity, 0.85) : opacity)
    }

    /// The tables the two teams play in, under a game still to come.
    private var tables: [NotchScoreStandingGroup] {
        guard game.state == .scheduled, game.sport.hasTeams else { return [] }
        return NotchScoresSupport.standings(scores.standings[game.sport.rawValue + "/" + game.league] ?? [], for: game)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch game.sport {
            case .racing: raceHeader
            case .golf, .mma: eventHeader
            default: header
            }
            switch game.sport {
            case .soccer: soccer
            case .football, .basketball, .baseball, .hockey: teamSections
            case .tennis: tennis
            case .racing: running
            case .golf: leaderboard
            case .mma: card
            }
            ForEach(tables) { table in
                section(tables.count > 1 || game.sport != .soccer ? text.standings + " · " + table.name : text.standings) {
                    standings(table)
                }
            }
            if let link = game.link {
                HStack {
                    Spacer()
                    NotchPillButton(title: text.openESPN) {
                        NotchService.shared.perform { NSWorkspace.shared.open(link) }
                    }
                    Spacer()
                }
            }
        }
        .onAppear { load() }
        .onChange(of: game.id) { load() }
    }

    private func load() {
        guard game.state == .scheduled, game.sport.hasTeams else { return }
        scores.loadStandings(for: game)
    }

    // MARK: Standings

    /// Place, crest, name and the league's columns, both teams of the game
    /// lit, so where each stands reads at a glance.
    private func standings(_ table: NotchScoreStandingGroup) -> some View {
        let teams = Set(game.sides.map(\.id))
        let width: CGFloat = game.sport == .soccer ? 24 : 34
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text("#").frame(width: 18, alignment: .leading)
                Spacer(minLength: 4)
                ForEach(table.columns, id: \.self) { column in
                    Text(text.standingColumn(column, sport: game.sport)).frame(width: width, alignment: .trailing)
                }
            }
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(faint(0.45))
            ForEach(table.rows) { row in
                let playing = teams.contains(row.id)
                HStack(spacing: 6) {
                    Text("\(row.place)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(faint(0.5)).frame(width: 18, alignment: .leading)
                    NotchScoreCrest(url: row.logo, size: 14, placeholder: game.sport.symbol)
                    Text(row.name).font(.system(size: 11, weight: playing ? .bold : .regular)).lineLimit(1)
                    Spacer(minLength: 4)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                        Text(value)
                            .font(.system(size: 11, weight: index == row.values.count - 1 && game.sport == .soccer
                                          ? .bold : .regular)).monospacedDigit()
                            .frame(width: width, alignment: .trailing)
                    }
                }
                .foregroundStyle(faint(playing ? 1 : 0.75))
                .padding(.vertical, 2).padding(.horizontal, 4)
                .background(playing ? Color.white.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                side(0)
                VStack(spacing: 3) {
                    Text(centerReading)
                        .font(.system(size: game.state == .scheduled ? 20 : 28, weight: .bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .modifier(NotchScoreRolling(value: centerReading))
                    status
                }
                .frame(minWidth: 96)
                side(1)
            }
            Text(caption).font(.system(size: 10)).foregroundStyle(faint(0.45))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
    }

    private var centerReading: String {
        switch game.state {
        case .scheduled:
            return game.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        default:
            if game.sport == .tennis, game.sides.count == 2 { return "\(game.sides[0].setsWon) – \(game.sides[1].setsWon)" }
            return (game.sides.first?.score ?? "–") + " – " + (game.sides.dropFirst().first?.score ?? "–")
        }
    }

    @ViewBuilder private var status: some View {
        switch game.state {
        case .live:
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text(game.segmentText ?? (game.clock.isEmpty ? text.live : game.clock)).foregroundStyle(.red)
            }
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
        case .scheduled:
            Text(game.start.formatted(Date.FormatStyle().weekday(.wide).day().month(.abbreviated).locale(locale)))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(faint(0.6))
        case .finished:
            Text(text.final).font(.system(size: 11, weight: .semibold)).foregroundStyle(faint(0.6))
        case .called:
            Text(game.clock).font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
        }
    }

    private func side(_ index: Int) -> some View {
        let side = game.sides.indices.contains(index) ? game.sides[index] : nil
        let lost = game.state == .finished && side?.winner == false && game.sides.contains(where: \.winner)
        return VStack(spacing: 4) {
            NotchScoreCrest(url: side?.logo, size: 34, placeholder: game.sport.symbol)
            Text(side?.name ?? "")
                .font(.system(size: 12, weight: game.followed.contains(side?.id ?? "") ? .bold : .semibold))
                .multilineTextAlignment(.center).lineLimit(2)
            if let record = side?.record {
                Text(record).font(.system(size: 10)).foregroundStyle(faint(0.45)).monospacedDigit()
            }
        }
        .opacity(lost ? 0.6 : 1)
        .frame(maxWidth: .infinity)
    }

    private var caption: String {
        [game.title, game.detail.map(text.session), game.venue].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var raceHeader: some View {
        VStack(spacing: 4) {
            Text(game.title).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                Text(text.session(game.detail ?? "")).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(faint(0.75))
                if game.state == .scheduled {
                    Text(NotchScoresSupport.startText(game.start, locale: locale, now: Date()))
                        .font(.system(size: 11)).foregroundStyle(faint(0.6))
                } else {
                    status
                }
            }
            if let venue = game.venue {
                Text(venue).font(.system(size: 10)).foregroundStyle(faint(0.45)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Soccer

    @ViewBuilder private var soccer: some View {
        if wide, !game.moments.isEmpty, !game.stats.isEmpty {
            HStack(alignment: .top, spacing: 16) {
                section(text.moments) { moments }.frame(maxWidth: .infinity, alignment: .top)
                section(text.stats) { stats }.frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            if !game.moments.isEmpty { section(text.moments) { moments } }
            if !game.stats.isEmpty { section(text.stats) { stats } }
        }
    }

    private var moments: some View {
        VStack(spacing: 5) {
            ForEach(Array(game.moments.enumerated()), id: \.offset) { _, moment in
                HStack(spacing: 6) {
                    if moment.side == 1 { Spacer(minLength: 0) }
                    if moment.side == 0 { minute(moment) }
                    momentMark(moment)
                    VStack(alignment: moment.side == 0 ? .leading : .trailing, spacing: 0) {
                        Text(moment.player).font(.system(size: 11, weight: isGoal(moment) ? .semibold : .regular))
                            .lineLimit(1)
                        if let note = note(moment) {
                            Text(note).font(.system(size: 9)).foregroundStyle(faint(0.5))
                        }
                    }
                    if moment.side == 1 { minute(moment) }
                    if moment.side == 0 { Spacer(minLength: 0) }
                }
            }
        }
    }

    private func isGoal(_ moment: NotchScoreMoment) -> Bool {
        [.goal, .penalty, .ownGoal].contains(moment.kind)
    }

    private func note(_ moment: NotchScoreMoment) -> String? {
        switch moment.kind {
        case .penalty: return text.penalty
        case .ownGoal: return text.ownGoal
        default: return nil
        }
    }

    private func minute(_ moment: NotchScoreMoment) -> some View {
        Text(moment.minute).font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(faint(0.55)).frame(minWidth: 26, alignment: moment.side == 0 ? .leading : .trailing)
    }

    @ViewBuilder private func momentMark(_ moment: NotchScoreMoment) -> some View {
        switch moment.kind {
        case .goal, .penalty:
            Image(systemName: "soccerball").font(.system(size: 11))
        case .ownGoal:
            Image(systemName: "soccerball").font(.system(size: 11)).foregroundStyle(.red)
        case .yellowCard:
            RoundedRectangle(cornerRadius: 1.5).fill(.yellow).frame(width: 8, height: 11)
        case .redCard:
            RoundedRectangle(cornerRadius: 1.5).fill(.red).frame(width: 8, height: 11)
        }
    }

    private var stats: some View {
        VStack(spacing: 7) {
            ForEach(game.stats, id: \.kind) { stat in
                let shares = stat.shares
                VStack(spacing: 3) {
                    HStack {
                        Text(stat.values.first.map { stat.kind.isPercentage ? $0 + "%" : $0 } ?? "")
                        Spacer(minLength: 4)
                        Text(text.stat(stat.kind)).foregroundStyle(faint(0.6)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(stat.values.last.map { stat.kind.isPercentage ? $0 + "%" : $0 } ?? "")
                    }
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            Capsule().fill(.white.opacity(0.85))
                                .frame(width: max(2, (proxy.size.width - 2) * (shares.first ?? 0.5)))
                            Capsule().fill(.white.opacity(0.3))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    /// A tournament or a card: its name, where it stands and where it is.
    private var eventHeader: some View {
        VStack(spacing: 4) {
            Text(game.title).font(.system(size: 15, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                if game.sport == .golf, game.period > 0, game.state != .scheduled {
                    Text(text.round(game.period)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(faint(0.75))
                }
                status
            }
            if let venue = game.venue {
                Text(venue).font(.system(size: 10)).foregroundStyle(faint(0.45)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Team sports

    /// Where play stands, the score by period, the teams' statistics and
    /// their leaders, as far as the scoreboard has them.
    @ViewBuilder private var teamSections: some View {
        if let situation = game.situation {
            section(nil) {
                VStack(alignment: .leading, spacing: 4) {
                    if let outs = situation.outs { atBat(situation, outs: outs) }
                    if let down = situation.downDistance {
                        HStack(spacing: 6) {
                            if let side = situation.possession, game.sides.indices.contains(side) {
                                NotchScoreCrest(url: game.sides[side].logo, size: 16, placeholder: game.sport.symbol)
                            }
                            Text(down).font(.system(size: 13, weight: .bold))
                                .foregroundStyle(situation.redZone ? .red : .white)
                        }
                    }
                    if let play = situation.lastPlay {
                        Text(text.lastPlay).font(.system(size: 9, weight: .semibold)).foregroundStyle(faint(0.5))
                        Text(play).font(.system(size: 11)).foregroundStyle(faint(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if game.sides.contains(where: { !$0.periods.isEmpty }) {
            section(nil) { periods }
        }
        if !game.stats.isEmpty {
            section(text.stats) { stats }
        }
        if !game.leaders.isEmpty {
            section(text.leaders) {
                VStack(spacing: 6) {
                    ForEach(game.leaders, id: \.self) { leader in
                        HStack(spacing: 8) {
                            Text(text.leader(leader.category)).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(faint(0.5)).frame(width: 70, alignment: .leading)
                            if let side = leader.side, game.sides.indices.contains(side) {
                                NotchScoreCrest(url: game.sides[side].logo, size: 14, placeholder: game.sport.symbol)
                            }
                            Text(leader.player).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(leader.line).font(.system(size: 10)).foregroundStyle(faint(0.7))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                }
            }
        }
    }

    /// The count, the outs and the bases of an at-bat, and who faces whom.
    private func atBat(_ situation: NotchScoreSituation, outs: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NotchScoreBases(bases: situation.bases)
            VStack(alignment: .leading, spacing: 3) {
                Text("B \(situation.balls ?? 0)  S \(situation.strikes ?? 0)  O \(outs)")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                if let batter = situation.batter {
                    Text(batter).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                if let pitcher = situation.pitcher {
                    Text(pitcher).font(.system(size: 10)).foregroundStyle(faint(0.6)).lineLimit(1)
                }
            }
        }
    }

    /// Each period's heading: its number in regulation, then overtime.
    /// Baseball numbers every inning, extras included.
    private func periodLabel(_ index: Int) -> String {
        let fallback: Int
        switch game.sport {
        case .hockey: fallback = 3
        case .baseball: fallback = 9
        default: fallback = 4
        }
        let regulation = game.regulation > 0 ? game.regulation : fallback
        guard game.sport != .baseball, index >= regulation else { return "\(index + 1)" }
        let extra = index - regulation + 1
        return extra == 1 ? "OT" : "\(extra)OT"
    }

    /// Points by period, overtime included, then the total; runs by inning,
    /// then runs, hits and errors.
    private var periods: some View {
        let count = game.sides.map(\.periods.count).max() ?? 0
        let totals = game.sport == .baseball ? ["R", "H", "E"] : ["T"]
        return Grid(alignment: .trailing, horizontalSpacing: game.sport == .baseball ? 7 : 10, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(0..<count, id: \.self) { index in
                    Text(periodLabel(index))
                }
                ForEach(totals, id: \.self) { Text($0) }
            }
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(faint(0.5))
            ForEach(game.sides) { side in
                GridRow {
                    HStack(spacing: 5) {
                        NotchScoreCrest(url: side.logo, size: 14, placeholder: game.sport.symbol)
                        Text(side.abbreviation).font(.system(size: 11, weight: .semibold))
                    }
                    .gridColumnAlignment(.leading)
                    ForEach(0..<count, id: \.self) { index in
                        Text(side.periods.indices.contains(index) ? side.periods[index] : "–")
                    }
                    Text(side.score ?? "–").fontWeight(.bold)
                    if game.sport == .baseball {
                        Text(side.hits ?? "–")
                        Text(side.errors ?? "–")
                    }
                }
                .font(.system(size: 11)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tennis

    private var tennis: some View {
        section(nil) {
            VStack(spacing: 6) {
                ForEach(Array(game.sides.enumerated()), id: \.element.id) { index, side in
                    let other = game.sides.indices.contains(1 - index) ? game.sides[1 - index] : nil
                    HStack(spacing: 8) {
                        NotchScoreCrest(url: side.logo, size: 16, placeholder: game.sport.symbol)
                        Text(side.name).font(.system(size: 12, weight: side.winner ? .bold : .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        ForEach(Array(side.sets.enumerated()), id: \.offset) { set, games in
                            let lost = other.map { $0.sets.indices.contains(set) && $0.sets[set].won } ?? false
                            HStack(alignment: .top, spacing: 0) {
                                Text(String(games.games))
                                if let tiebreak = games.tiebreak { Text(String(tiebreak)).font(.system(size: 8)) }
                            }
                            .font(.system(size: 14, weight: .bold)).monospacedDigit()
                            .opacity(lost ? 0.45 : 1)
                            .frame(minWidth: 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: Racing

    /// The whole field, in order, in as many columns as fit.
    private var running: some View {
        section(nil) {
            if game.sides.isEmpty {
                Text(NotchScoresSupport.startText(game.start, locale: locale, now: Date()))
                    .font(.system(size: 12)).foregroundStyle(faint(0.6))
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading),
                                         count: wide ? 2 : 1), spacing: 4) {
                    ForEach(game.sides) { driver in
                        let livery = scores.livery(driver, in: game)
                        HStack(spacing: 6) {
                            Text(driver.position.map { "P\($0)" } ?? "–")
                                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                                .foregroundStyle(faint(driver.position.map { $0 <= 3 } == true ? 0.9 : 0.5))
                                .frame(width: 26, alignment: .leading)
                            NotchScoreCrest(url: driver.logo, size: 14, placeholder: game.sport.symbol)
                            Text(driver.name).font(.system(size: 11, weight: driver.position == 1 ? .bold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let number = livery?.number {
                                Text(number).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(faint(0.6))
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.leading, livery == nil ? 0 : 9)
                        .padding(.trailing, livery == nil ? 0 : 6)
                        .background { if let livery { NotchScoreLiveryBand(color: livery.swiftColor) } }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(livery?.team ?? "")
                    }
                }
                // A driver who gains or loses a place slides into it.
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: game.sides.map(\.id))
            }
        }
    }

    // MARK: Golf

    /// The field in order: each golfer's place, ties shown, score to par,
    /// and holes played in the round under way or the last round's score.
    private var leaderboard: some View {
        // Before the first tee shot everyone is level: no places yet.
        let places = game.state == .scheduled ? [] : NotchScoresSupport.places(game.sides)
        return section(text.leaderboard) {
            if game.sides.isEmpty {
                Text(NotchScoresSupport.startText(game.start, locale: locale, now: Date()))
                    .font(.system(size: 12)).foregroundStyle(faint(0.6)).frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 4) {
                    HStack {
                        Spacer()
                        if game.state == .live {
                            Text(text.thru).frame(width: 34, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(faint(0.45))
                    ForEach(Array(game.sides.enumerated()), id: \.element.id) { index, golfer in
                        HStack(spacing: 6) {
                            Text(places.indices.contains(index) ? places[index] : "").font(.system(size: 10, weight: .bold)).monospacedDigit()
                                .foregroundStyle(faint(0.6)).frame(width: 30, alignment: .leading)
                            NotchScoreCrest(url: golfer.logo, size: 14, placeholder: game.sport.symbol)
                            Text(golfer.name).font(.system(size: 11, weight: index == 0 ? .bold : .regular)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(golfer.score ?? "–").font(.system(size: 12, weight: .bold)).monospacedDigit()
                                .foregroundStyle((golfer.score ?? "").hasPrefix("-") ? Color.red : .white)
                            if game.state == .live {
                                Text(golfer.thru.map { $0 >= 18 ? "F" : String($0) } ?? "–")
                                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(faint(0.6))
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Fights

    /// The bouts, main event first: the fighters, their records, and the
    /// round and time it ended, or when it is due.
    private var card: some View {
        section(text.fights) {
            VStack(spacing: 8) {
                ForEach(game.bouts.reversed()) { bout in
                    VStack(spacing: 3) {
                        HStack {
                            Text(bout.division.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4)
                                .foregroundStyle(faint(0.45))
                            Spacer()
                            boutStatus(bout)
                        }
                        HStack(spacing: 6) {
                            fighter(bout, 0)
                            Text("vs").font(.system(size: 9)).foregroundStyle(faint(0.4))
                            fighter(bout, 1)
                        }
                    }
                    if bout.id != game.bouts.first?.id { Divider().overlay(.white.opacity(0.08)) }
                }
            }
        }
    }

    private func fighter(_ bout: NotchScoreBout, _ index: Int) -> some View {
        let side = bout.sides.indices.contains(index) ? bout.sides[index] : nil
        let lost = bout.state == .finished && side?.winner == false && bout.sides.contains(where: \.winner)
        return HStack(spacing: 5) {
            if index == 1 { Spacer(minLength: 0) }
            if index == 0 { NotchScoreCrest(url: side?.logo, size: 14, placeholder: game.sport.symbol) }
            VStack(alignment: index == 0 ? .leading : .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    if side?.winner == true, index == 1 { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                    Text(side?.name ?? "").font(.system(size: 11, weight: side?.winner == true ? .bold : .medium))
                        .lineLimit(1)
                    if side?.winner == true, index == 0 { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                }
                if let record = side?.record {
                    Text(record).font(.system(size: 9)).monospacedDigit().foregroundStyle(faint(0.45))
                }
            }
            if index == 1 { NotchScoreCrest(url: side?.logo, size: 14, placeholder: game.sport.symbol) }
            if index == 0 { Spacer(minLength: 0) }
        }
        .opacity(lost ? 0.55 : 1)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func boutStatus(_ bout: NotchScoreBout) -> some View {
        switch bout.state {
        case .live:
            HStack(spacing: 3) {
                Circle().fill(.red).frame(width: 5, height: 5)
                Text(bout.round > 0 ? "R\(bout.round) \(bout.clock)" : text.live)
            }
            .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.red)
        case .finished:
            Text(bout.round > 0 ? "R\(bout.round) \(bout.clock)" : text.final)
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(faint(0.6))
        case .called:
            Text(bout.clock).font(.system(size: 10)).foregroundStyle(.orange)
        case .scheduled:
            Text(NotchScoresSupport.startText(game.start, locale: locale, now: Date()))
                .font(.system(size: 10)).foregroundStyle(faint(0.5))
        }
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(faint(0.45))
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A team's crest or an athlete's flag, kept in memory once loaded. On the
/// island's black it takes the version drawn for dark backgrounds.
struct NotchScoreCrest: View {
    let url: URL?
    let size: CGFloat
    var dark = true
    /// Shown until the picture arrives, or for good when there is none.
    var placeholder: String? = nil
    /// The placeholder's size, when it stands where a symbol of its own did.
    var placeholderSize: CGFloat? = nil
    /// A person's photo, filled into a circle.
    var round = false
    /// Behind a photo cut out of its background, as a team's color.
    var backdrop: Color? = nil
    @ObservedObject private var crests = NotchScoresCrests.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let image = crests.image(url, dark: dark)
        Group {
            if let image, round {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                    .frame(width: size, height: size)
                    .background(backdrop ?? .clear)
                    .clipShape(Circle())
            } else if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else if let placeholder {
                Image(systemName: placeholder)
                    .font(.system(size: placeholderSize ?? size * 0.55, weight: placeholderSize == nil ? .regular : .semibold))
                    .foregroundStyle(placeholderSize == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        // A crest that arrives fades in over its placeholder, not in a pop.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: image != nil)
        .onAppear { crests.load(url, dark: dark) }
        .onChange(of: url) { _, url in crests.load(url, dark: dark) }
        .accessibilityHidden(true)
    }
}

/// A driver's row in their team's color: a wash of it behind the name and
/// a solid edge, as timing screens mark each car.
private struct NotchScoreLiveryBand: View {
    let color: Color
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(contrast == .increased ? 0.4 : 0.26))
            Capsule().fill(color).frame(width: 3).padding(.vertical, 3).padding(.leading, 2)
        }
    }
}

extension NotchScoreLivery {
    var swiftColor: Color { Color(red: color.red, green: color.green, blue: color.blue) }
}

/// A score that changes rolls its digits over, the way a scoreboard
/// ticks; Reduce Motion changes it in place.
struct NotchScoreRolling: ViewModifier {
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
    }
}

extension View {
    /// Centers the digits themselves, not the line they sit on, on the
    /// mark beside them: a line leaves room below for descenders, so its
    /// middle sits under the middle of a score.
    func notchCapCentered(_ font: NSFont) -> some View {
        alignmentGuide(VerticalAlignment.center) { $0[.firstTextBaseline] - font.capHeight / 2 }
    }
}

/// The diamond: first, second and third, lit when a runner is on.
private struct NotchScoreBases: View {
    let bases: [Bool]

    var body: some View {
        ZStack {
            base(1).offset(y: -8)
            base(2).offset(x: -8)
            base(0).offset(x: 8)
        }
        .frame(width: 30, height: 26)
        .accessibilityHidden(true)
    }

    private func base(_ index: Int) -> some View {
        let on = bases.indices.contains(index) && bases[index]
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(on ? Color.yellow : Color.white.opacity(0.2))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(45))
    }
}

// MARK: - Closed island

/// A game under way beside the camera, kept to what reads at a glance:
/// each side's crest or flag and its score on its own wing. Names, the
/// clock and the statistics are on the open island.
struct NotchScoresStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var scores = NotchScoresService.shared
    @ObservedObject private var l10n = L10n.shared

    static let spacing: CGFloat = 5

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var textInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) }

    static func mainFont(_ size: CGFloat) -> NSFont { .monospacedDigitSystemFont(ofSize: size + 1, weight: .bold) }
    /// A crest a little taller than the score beside it.
    static func crestSize(_ textSize: CGFloat) -> CGFloat { (textSize * 1.35).rounded() }

    /// The wider wing: a mark and its score, measured as they are drawn.
    static func readingWidth(_ compact: NotchScoreStripText, sport: NotchScoreSport, textSize: CGFloat) -> CGFloat {
        func width(_ text: String) -> CGFloat {
            text.isEmpty ? 0 : (text as NSString).size(withAttributes: [.font: mainFont(textSize)]).width.rounded(.up)
        }
        let mark = crestSize(textSize) + spacing
        let trailingMark = sport.isField ? 0 : mark
        return max(width(compact.leading) + mark, width(compact.trailing) + trailingMark)
    }

    var body: some View {
        let game = scores.featured
        let compact = game.map { NotchScoresSupport.compactText($0, text: FeatureStrings.notchScores(l10n.language)) }
        let mark = Self.crestSize(textSize)
        Button { service.openActivity(.scores) } label: {
            HStack(spacing: 0) {
                HStack(spacing: Self.spacing) {
                    if let game, let marks = NotchScoresSupport.compactMarks(game) {
                        NotchScoreCrest(url: marks.first ?? nil, size: mark)
                    } else if let game, let leader = NotchScoresSupport.compactLeader(game), let portrait = leader.portrait {
                        NotchScoreCrest(url: portrait, size: mark, placeholder: game.sport.symbol,
                                        placeholderSize: textSize, round: true,
                                        backdrop: scores.livery(leader, in: game)?.swiftColor)
                    } else {
                        Image(systemName: game?.sport.symbol ?? NotchModule.scores.symbol)
                            .font(.system(size: textSize, weight: .semibold))
                            .frame(width: mark, height: mark)
                    }
                    Text(compact?.leading ?? "").font(Font(Self.mainFont(textSize)))
                        .notchCapCentered(Self.mainFont(textSize))
                        .modifier(NotchScoreRolling(value: compact?.leading ?? ""))
                }
                .lineLimit(1)
                .padding(.leading, textInset)
                .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
                .clipped()
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                HStack(spacing: Self.spacing) {
                    Text(compact?.trailing ?? "").font(Font(Self.mainFont(textSize)))
                        .notchCapCentered(Self.mainFont(textSize))
                        .modifier(NotchScoreRolling(value: compact?.trailing ?? ""))
                    if let game, let marks = NotchScoresSupport.compactMarks(game) {
                        NotchScoreCrest(url: marks.last ?? nil, size: mark)
                    }
                }
                .lineLimit(1)
                .padding(.trailing, textInset)
                .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                .clipped()
            }
            .foregroundStyle(.white)
            .frame(height: geometry.compactActivityContentHeight)
            .padding(.horizontal, geometry.compactActivityHorizontalPadding)
            .padding(.top, geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FeatureStrings.notchScores(l10n.language).title)
        .accessibilityValue(game.map {
            NotchScoresSupport.capsuleText(NotchScoresSupport.stripText($0, text: FeatureStrings.notchScores(l10n.language),
                                                                        locale: l10n.language.formattingLocale(), now: Date()),
                                           sport: $0.sport)
        } ?? "")
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}
