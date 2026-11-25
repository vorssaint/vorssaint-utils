// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchScoresStrings {
    let title: String
    let description: String
    let summary: String
    let soccer: String
    let football: String
    let tennis: String
    let racing: String
    let nationalTeams: String
    let following: String
    let follow: String
    let unfollow: String
    let add: String
    let league: String
    let search: String
    let loading: String
    let unavailable: String
    let noneFollowed: String
    let emptyPage: String
    let chooseTeams: String
    let nothingSoon: String
    let live: String
    let upNext: String
    let results: String
    let liveActivity: String
    let alerts: String
    let source: String
    let refresh: String
    let goal: String
    let touchdown: String
    let fieldGoal: String
    let safety: String
    let scored: String
    let started: String
    let final: String
    let setWon: String
    let race: String
    let qualifying: String
    let sprint: String
    let lapFormat: String
    let sportLabel: String
    /// What following a whole league, tour or championship brings.
    let everyGame: String
    let everyMatch: String
    let everySession: String
    let possession: String
    let shots: String
    let shotsOnTarget: String
    let corners: String
    let fouls: String
    let offsides: String
    let saves: String
    let moments: String
    let stats: String
    let leaders: String
    let passing: String
    let rushing: String
    let receiving: String
    let ownGoal: String
    let penalty: String
    let lastPlay: String
    let openESPN: String
    let basketball: String
    let baseball: String
    let hockey: String
    let golf: String
    let mma: String
    let everyTournament: String
    let everyCard: String
    let run: String
    let fieldGoals: String
    let threePointers: String
    let freeThrows: String
    let rebounds: String
    let assists: String
    let savePercentage: String
    let points: String
    let goals: String
    let topPerformer: String
    let roundFormat: String
    let thru: String
    let leaderboard: String
    let fights: String
    let winsFormat: String
    let collegeFootball: String
    let collegeBasketball: String
    let conference: String
    let standings: String
    let playedShort: String
    let wonShort: String
    let drawnShort: String
    let lostShort: String
    let goalDifferenceShort: String
    let pointsShort: String
    let motorsport: String
    let country: String
    let international: String
    let england: String
    /// The Settings preview’s game, before anything followed is on.
    let sampleHome: String
    let sampleAway: String
    let sampleGame: String
    /// A free practice session by its number: Practice 2.
    let practiceFormat: String

    func sport(_ sport: NotchScoreSport) -> String {
        switch sport {
        case .soccer: return soccer
        case .football: return football
        case .basketball: return basketball
        case .baseball: return baseball
        case .hockey: return hockey
        case .tennis: return tennis
        case .golf: return golf
        case .racing: return motorsport
        case .mma: return mma
        }
    }

    func whole(_ sport: NotchScoreSport) -> String {
        switch sport {
        case .soccer, .football, .basketball, .baseball, .hockey: return everyGame
        case .tennis: return everyMatch
        case .golf: return everyTournament
        case .racing: return everySession
        case .mma: return everyCard
        }
    }

    func stat(_ kind: NotchScoreStatKind) -> String {
        switch kind {
        case .possession: return possession
        case .shots: return shots
        case .shotsOnTarget: return shotsOnTarget
        case .corners: return corners
        case .fouls: return fouls
        case .offsides: return offsides
        case .saves: return saves
        case .fieldGoals: return fieldGoals
        case .threePointers: return threePointers
        case .freeThrows: return freeThrows
        case .rebounds: return rebounds
        case .assists: return assists
        case .savePercentage: return savePercentage
        }
    }

    func leader(_ category: NotchScoreLeader.Category) -> String {
        switch category {
        case .passing: return passing
        case .rushing: return rushing
        case .receiving: return receiving
        case .points: return points
        case .rebounds: return rebounds
        case .assists: return assists
        case .goals: return goals
        case .topPerformer: return topPerformer
        }
    }

    func round(_ round: Int) -> String { String(format: roundFormat, String(round)) }
    func wins(_ name: String) -> String { String(format: winsFormat, name) }

    /// A table's column heading: a soccer table's in the person's language,
    /// the American leagues' in the letters every fan of them reads.
    func standingColumn(_ type: String, sport: NotchScoreSport) -> String {
        if sport == .soccer {
            switch type {
            case "gamesplayed": return playedShort
            case "wins": return wonShort
            case "ties": return drawnShort
            case "losses": return lostShort
            case "pointdifferential": return goalDifferenceShort
            case "points": return pointsShort
            default: break
            }
        }
        switch type {
        case "gamesplayed": return "GP"
        case "wins": return "W"
        case "losses": return "L"
        case "ties": return "T"
        case "winpercent": return "PCT"
        case "gamesbehind": return "GB"
        case "otlosses": return "OTL"
        case "points": return "PTS"
        case "vsconf": return "CONF"
        case "total": return "OVR"
        default: return type.uppercased()
        }
    }

    func lap(_ lap: Int) -> String { String(format: lapFormat, String(lap)) }

    /// ESPN names its sessions in English; the island names them in the
    /// person's language and keeps practice sessions' short codes.
    func session(_ abbreviation: String) -> String {
        switch abbreviation.lowercased() {
        case "race": return race
        case "qual", "qualifying": return qualifying
        case "sprint", "sr": return sprint
        case let name where name.hasPrefix("fp") && name.dropFirst(2).allSatisfy(\.isNumber):
            return String(format: practiceFormat, String(name.dropFirst(2)))
        default: return abbreviation
        }
    }

    func headline(_ change: NotchScoreChange) -> String {
        switch change {
        case .started: return started
        case .finished: return final
        case .set: return setWon
        case .bout: return final
        case .scored(_, let kind):
            switch kind {
            case .goal: return goal
            case .touchdown: return touchdown
            case .fieldGoal: return fieldGoal
            case .safety: return safety
            case .points: return scored
            case .run: return run
            }
        }
    }
}

extension FeatureStrings {
    static func notchScores(_ language: AppLanguage) -> NotchScoresStrings {
        switch language {
        case .enUS: return NotchScoresStrings(
            title: "Scores",
            description: "Follow live scores for your teams and athletes in the Dynamic Island: soccer, American football, tennis and Formula 1.",
            summary: "Live scores for the teams and athletes you follow.",
            soccer: "Soccer", football: "American Football", tennis: "Tennis", racing: "Formula 1",
            nationalTeams: "National Teams",
            following: "Following", follow: "Follow", unfollow: "Stop Following",
            add: "Add Teams and Athletes", league: "League", search: "Search",
            loading: "Loading…", unavailable: "ESPN can’t be reached right now.",
            noneFollowed: "You aren’t following any team or athlete yet.",
            emptyPage: "Follow teams and athletes in Settings to see their games here.",
            chooseTeams: "Choose Teams", nothingSoon: "No games in the next week.",
            live: "Live", upNext: "Up Next", results: "Results",
            liveActivity: "Show live games in the closed island",
            alerts: "Alert me when a game starts, someone scores and it ends",
            source: "Scores come from ESPN’s public scoreboards. Only the leagues, teams and athletes you follow are requested, and nothing about you is sent.",
            refresh: "Refresh",
            goal: "Goal", touchdown: "Touchdown", fieldGoal: "Field Goal", safety: "Safety", scored: "Score",
            started: "Started", final: "Final", setWon: "Set",
            race: "Race", qualifying: "Qualifying", sprint: "Sprint", lapFormat: "Lap %@",
            sportLabel: "Sport", everyGame: "Every game", everyMatch: "Every singles match", everySession: "Practice, qualifying, sprints and races",
            possession: "Possession", shots: "Shots", shotsOnTarget: "On Target", corners: "Corners", fouls: "Fouls", offsides: "Offsides", saves: "Saves", moments: "Key Moments", stats: "Stats", leaders: "Leaders", passing: "Passing", rushing: "Rushing", receiving: "Receiving", ownGoal: "OG", penalty: "pen.", lastPlay: "Last play", openESPN: "Open in ESPN",
            basketball: "Basketball", baseball: "Baseball", hockey: "Hockey", golf: "Golf", mma: "MMA", everyTournament: "Every tournament", everyCard: "Every fight card", run: "Run", fieldGoals: "Field Goals", threePointers: "3-Pointers", freeThrows: "Free Throws", rebounds: "Rebounds", assists: "Assists", savePercentage: "Save %", points: "Points", goals: "Goals", topPerformer: "Top Performer", roundFormat: "Round %@", thru: "Thru", leaderboard: "Leaderboard", fights: "Fights", winsFormat: "%@ wins",
            collegeFootball: "College Football", collegeBasketball: "College Basketball", conference: "Conference",
            standings: "Standings", playedShort: "P", wonShort: "W", drawnShort: "D", lostShort: "L", goalDifferenceShort: "GD", pointsShort: "Pts",
            motorsport: "Racing", country: "Country", international: "International", england: "England", sampleHome: "Home", sampleAway: "Away", sampleGame: "Sample game", practiceFormat: "Practice %@")
        case .ptBR: return NotchScoresStrings(
            title: "Placar",
            description: "Acompanhe ao vivo o placar dos seus times e atletas na Dynamic Island: futebol, futebol americano, tênis e Fórmula 1.",
            summary: "Placar ao vivo dos times e atletas que você segue.",
            soccer: "Futebol", football: "Futebol Americano", tennis: "Tênis", racing: "Fórmula 1",
            nationalTeams: "Seleções",
            following: "Seguindo", follow: "Seguir", unfollow: "Deixar de Seguir",
            add: "Adicionar Times e Atletas", league: "Campeonato", search: "Buscar",
            loading: "Carregando…", unavailable: "Não foi possível acessar a ESPN agora.",
            noneFollowed: "Você ainda não segue nenhum time ou atleta.",
            emptyPage: "Siga times e atletas nos Ajustes para ver os jogos deles aqui.",
            chooseTeams: "Escolher Times", nothingSoon: "Nenhum jogo nos próximos sete dias.",
            live: "Ao vivo", upNext: "Próximos", results: "Resultados",
            liveActivity: "Mostrar jogos ao vivo com a ilha fechada",
            alerts: "Avisar quando um jogo começar, alguém marcar e quando terminar",
            source: "O placar vem dos placares públicos da ESPN. Só são consultados os campeonatos, times e atletas que você segue, e nada sobre você é enviado.",
            refresh: "Atualizar",
            goal: "Gol", touchdown: "Touchdown", fieldGoal: "Field Goal", safety: "Safety", scored: "Pontos",
            started: "Começou", final: "Fim de jogo", setWon: "Set",
            race: "Corrida", qualifying: "Classificação", sprint: "Sprint", lapFormat: "Volta %@",
            sportLabel: "Esporte", everyGame: "Todos os jogos", everyMatch: "Todas as partidas de simples", everySession: "Treinos, classificações, sprints e corridas",
            possession: "Posse de bola", shots: "Finalizações", shotsOnTarget: "No gol", corners: "Escanteios", fouls: "Faltas", offsides: "Impedimentos", saves: "Defesas", moments: "Lances", stats: "Estatísticas", leaders: "Destaques", passing: "Passes", rushing: "Corridas", receiving: "Recepções", ownGoal: "contra", penalty: "pên.", lastPlay: "Última jogada", openESPN: "Abrir na ESPN",
            basketball: "Basquete", baseball: "Beisebol", hockey: "Hóquei", golf: "Golfe", mma: "MMA", everyTournament: "Todos os torneios", everyCard: "Todos os eventos", run: "Corrida", fieldGoals: "Arremessos", threePointers: "Bolas de 3", freeThrows: "Lances livres", rebounds: "Rebotes", assists: "Assistências", savePercentage: "% de defesas", points: "Pontos", goals: "Gols", topPerformer: "Destaque", roundFormat: "Rodada %@", thru: "Buracos", leaderboard: "Classificação", fights: "Lutas", winsFormat: "%@ vence",
            collegeFootball: "Futebol Americano Universitário", collegeBasketball: "Basquete Universitário", conference: "Conferência",
            standings: "Classificação", playedShort: "J", wonShort: "V", drawnShort: "E", lostShort: "D", goalDifferenceShort: "SG", pointsShort: "Pts",
            motorsport: "Automobilismo", country: "País", international: "Internacional", england: "Inglaterra", sampleHome: "Mandante", sampleAway: "Visitante", sampleGame: "Jogo de exemplo", practiceFormat: "Treino Livre %@")
        case .es: return NotchScoresStrings(
            title: "Marcadores",
            description: "Sigue en vivo los marcadores de tus equipos y deportistas en la Dynamic Island: fútbol, fútbol americano, tenis y Fórmula 1.",
            summary: "Marcadores en vivo de los equipos y deportistas que sigues.",
            soccer: "Fútbol", football: "Fútbol Americano", tennis: "Tenis", racing: "Fórmula 1",
            nationalTeams: "Selecciones",
            following: "Siguiendo", follow: "Seguir", unfollow: "Dejar de Seguir",
            add: "Añadir Equipos y Deportistas", league: "Competición", search: "Buscar",
            loading: "Cargando…", unavailable: "No se puede acceder a ESPN en este momento.",
            noneFollowed: "Todavía no sigues a ningún equipo ni deportista.",
            emptyPage: "Sigue equipos y deportistas en Ajustes para ver sus partidos aquí.",
            chooseTeams: "Elegir Equipos", nothingSoon: "No hay partidos en los próximos siete días.",
            live: "En vivo", upNext: "Próximos", results: "Resultados",
            liveActivity: "Mostrar los partidos en vivo con la isla cerrada",
            alerts: "Avisarme cuando empiece un partido, alguien marque y termine",
            source: "Los marcadores vienen de los marcadores públicos de ESPN. Solo se consultan las competiciones, equipos y deportistas que sigues, y no se envía nada sobre ti.",
            refresh: "Actualizar",
            goal: "Gol", touchdown: "Touchdown", fieldGoal: "Gol de campo", safety: "Safety", scored: "Puntos",
            started: "Empezó", final: "Final", setWon: "Set",
            race: "Carrera", qualifying: "Clasificación", sprint: "Sprint", lapFormat: "Vuelta %@",
            sportLabel: "Deporte", everyGame: "Todos los partidos", everyMatch: "Todos los partidos individuales", everySession: "Libres, clasificaciones, sprints y carreras",
            possession: "Posesión", shots: "Tiros", shotsOnTarget: "A puerta", corners: "Córneres", fouls: "Faltas", offsides: "Fueras de juego", saves: "Atajadas", moments: "Momentos clave", stats: "Estadísticas", leaders: "Líderes", passing: "Pases", rushing: "Carreras", receiving: "Recepciones", ownGoal: "p. p.", penalty: "pen.", lastPlay: "Última jugada", openESPN: "Abrir en ESPN",
            basketball: "Baloncesto", baseball: "Béisbol", hockey: "Hockey", golf: "Golf", mma: "MMA", everyTournament: "Todos los torneos", everyCard: "Todas las veladas", run: "Carrera", fieldGoals: "Tiros de campo", threePointers: "Triples", freeThrows: "Tiros libres", rebounds: "Rebotes", assists: "Asistencias", savePercentage: "% de paradas", points: "Puntos", goals: "Goles", topPerformer: "Figura", roundFormat: "Ronda %@", thru: "Hoyos", leaderboard: "Clasificación", fights: "Combates", winsFormat: "Gana %@",
            collegeFootball: "Fútbol Americano Universitario", collegeBasketball: "Baloncesto Universitario", conference: "Conferencia",
            standings: "Clasificación", playedShort: "PJ", wonShort: "G", drawnShort: "E", lostShort: "P", goalDifferenceShort: "DG", pointsShort: "Pts",
            motorsport: "Automovilismo", country: "País", international: "Internacional", england: "Inglaterra", sampleHome: "Local", sampleAway: "Visitante", sampleGame: "Partido de ejemplo", practiceFormat: "Libres %@")
        case .sk: return NotchScoresStrings(
            title: "Výsledky",
            description: "Sledujte živé výsledky svojich tímov a športovcov v Dynamic Island: futbal, americký futbal, tenis a Formula 1.",
            summary: "Živé výsledky tímov a športovcov, ktorých sledujete.",
            soccer: "Futbal", football: "Americký futbal", tennis: "Tenis", racing: "Formula 1",
            nationalTeams: "Reprezentácie",
            following: "Sledované", follow: "Sledovať", unfollow: "Prestať sledovať",
            add: "Pridať tímy a športovcov", league: "Súťaž", search: "Hľadať",
            loading: "Načítava sa…", unavailable: "ESPN teraz nie je dostupné.",
            noneFollowed: "Zatiaľ nesledujete žiadny tím ani športovca.",
            emptyPage: "V Nastaveniach začnite sledovať tímy a športovcov a ich zápasy uvidíte tu.",
            chooseTeams: "Vybrať tímy", nothingSoon: "Najbližší týždeň nie sú žiadne zápasy.",
            live: "Naživo", upNext: "Nasleduje", results: "Výsledky",
            liveActivity: "Zobraziť zápasy naživo v zatvorenom ostrove",
            alerts: "Upozorniť, keď zápas začne, niekto skóruje a keď skončí",
            source: "Výsledky pochádzajú z verejných výsledkových tabúľ ESPN. Požadujú sa len súťaže, tímy a športovci, ktorých sledujete, a nič o vás sa neodosiela.",
            refresh: "Obnoviť",
            goal: "Gól", touchdown: "Touchdown", fieldGoal: "Field goal", safety: "Safety", scored: "Body",
            started: "Začalo sa", final: "Koniec", setWon: "Set",
            race: "Preteky", qualifying: "Kvalifikácia", sprint: "Šprint", lapFormat: "Kolo %@",
            sportLabel: "Šport", everyGame: "Všetky zápasy", everyMatch: "Všetky zápasy dvojhry", everySession: "Tréningy, kvalifikácie, šprinty a preteky",
            possession: "Držanie lopty", shots: "Strely", shotsOnTarget: "Na bránu", corners: "Rohy", fouls: "Fauly", offsides: "Ofsajdy", saves: "Zákroky", moments: "Kľúčové momenty", stats: "Štatistiky", leaders: "Najlepší", passing: "Prihrávky", rushing: "Behy", receiving: "Chytenia", ownGoal: "vl.", penalty: "pen.", lastPlay: "Posledná akcia", openESPN: "Otvoriť v ESPN",
            basketball: "Basketbal", baseball: "Bejzbal", hockey: "Hokej", golf: "Golf", mma: "MMA", everyTournament: "Všetky turnaje", everyCard: "Všetky galavečery", run: "Bod", fieldGoals: "Streľba z hry", threePointers: "Trojky", freeThrows: "Trestné hody", rebounds: "Doskoky", assists: "Asistencie", savePercentage: "Úspešnosť zákrokov", points: "Body", goals: "Góly", topPerformer: "Najlepší hráč", roundFormat: "%@. kolo", thru: "Jamky", leaderboard: "Poradie", fights: "Zápasy", winsFormat: "Vyhráva %@",
            collegeFootball: "Univerzitný americký futbal", collegeBasketball: "Univerzitný basketbal", conference: "Konferencia",
            standings: "Tabuľka", playedShort: "Z", wonShort: "V", drawnShort: "R", lostShort: "P", goalDifferenceShort: "+/-", pointsShort: "B",
            motorsport: "Motorizmus", country: "Krajina", international: "Medzinárodné", england: "Anglicko", sampleHome: "Domáci", sampleAway: "Hostia", sampleGame: "Ukážkový zápas", practiceFormat: "Tréning %@")
        case .de: return NotchScoresStrings(
            title: "Spielstände",
            description: "Verfolge die Live-Spielstände deiner Teams und Sportler in der Dynamic Island: Fußball, American Football, Tennis und Formel 1.",
            summary: "Live-Spielstände der Teams und Sportler, denen du folgst.",
            soccer: "Fußball", football: "American Football", tennis: "Tennis", racing: "Formel 1",
            nationalTeams: "Nationalteams",
            following: "Gefolgt", follow: "Folgen", unfollow: "Nicht mehr folgen",
            add: "Teams und Sportler hinzufügen", league: "Wettbewerb", search: "Suchen",
            loading: "Wird geladen …", unavailable: "ESPN ist gerade nicht erreichbar.",
            noneFollowed: "Du folgst noch keinem Team und keinem Sportler.",
            emptyPage: "Folge in den Einstellungen Teams und Sportlern, um ihre Spiele hier zu sehen.",
            chooseTeams: "Teams wählen", nothingSoon: "In den nächsten sieben Tagen keine Spiele.",
            live: "Live", upNext: "Demnächst", results: "Ergebnisse",
            liveActivity: "Live-Spiele in der geschlossenen Insel zeigen",
            alerts: "Melden, wenn ein Spiel beginnt, jemand trifft und es endet",
            source: "Die Spielstände stammen aus den öffentlichen Anzeigetafeln von ESPN. Abgefragt werden nur die Wettbewerbe, Teams und Sportler, denen du folgst, und nichts über dich wird gesendet.",
            refresh: "Aktualisieren",
            goal: "Tor", touchdown: "Touchdown", fieldGoal: "Field Goal", safety: "Safety", scored: "Punkte",
            started: "Angepfiffen", final: "Ende", setWon: "Satz",
            race: "Rennen", qualifying: "Qualifying", sprint: "Sprint", lapFormat: "Runde %@",
            sportLabel: "Sportart", everyGame: "Alle Spiele", everyMatch: "Alle Einzelmatches", everySession: "Trainings, Qualifyings, Sprints und Rennen",
            possession: "Ballbesitz", shots: "Schüsse", shotsOnTarget: "Aufs Tor", corners: "Ecken", fouls: "Fouls", offsides: "Abseits", saves: "Paraden", moments: "Schlüsselmomente", stats: "Statistiken", leaders: "Bestwerte", passing: "Pässe", rushing: "Läufe", receiving: "Fänge", ownGoal: "ET", penalty: "Elfm.", lastPlay: "Letzter Spielzug", openESPN: "In ESPN öffnen",
            basketball: "Basketball", baseball: "Baseball", hockey: "Eishockey", golf: "Golf", mma: "MMA", everyTournament: "Alle Turniere", everyCard: "Alle Kampfabende", run: "Run", fieldGoals: "Würfe aus dem Feld", threePointers: "Dreier", freeThrows: "Freiwürfe", rebounds: "Rebounds", assists: "Assists", savePercentage: "Fangquote", points: "Punkte", goals: "Tore", topPerformer: "Bester Spieler", roundFormat: "Runde %@", thru: "Loch", leaderboard: "Rangliste", fights: "Kämpfe", winsFormat: "%@ gewinnt",
            collegeFootball: "College Football", collegeBasketball: "College-Basketball", conference: "Conference",
            standings: "Tabelle", playedShort: "Sp.", wonShort: "S", drawnShort: "U", lostShort: "N", goalDifferenceShort: "Diff.", pointsShort: "Pkt.",
            motorsport: "Motorsport", country: "Land", international: "International", england: "England", sampleHome: "Heim", sampleAway: "Gast", sampleGame: "Beispielspiel", practiceFormat: "Training %@")
        case .fr: return NotchScoresStrings(
            title: "Scores",
            description: "Suivez en direct les scores de vos équipes et sportifs dans la Dynamic Island : football, football américain, tennis et Formule 1.",
            summary: "Les scores en direct des équipes et sportifs que vous suivez.",
            soccer: "Football", football: "Football américain", tennis: "Tennis", racing: "Formule 1",
            nationalTeams: "Sélections nationales",
            following: "Suivis", follow: "Suivre", unfollow: "Ne plus suivre",
            add: "Ajouter des équipes et sportifs", league: "Compétition", search: "Rechercher",
            loading: "Chargement…", unavailable: "ESPN est injoignable pour le moment.",
            noneFollowed: "Vous ne suivez encore aucune équipe ni aucun sportif.",
            emptyPage: "Suivez des équipes et des sportifs dans les Réglages pour voir leurs matchs ici.",
            chooseTeams: "Choisir des équipes", nothingSoon: "Aucun match dans les sept prochains jours.",
            live: "En direct", upNext: "À venir", results: "Résultats",
            liveActivity: "Afficher les matchs en direct dans l’îlot fermé",
            alerts: "M’avertir quand un match commence, quand quelqu’un marque et quand il se termine",
            source: "Les scores proviennent des tableaux de scores publics d’ESPN. Seules les compétitions, équipes et sportifs que vous suivez sont demandés, et rien vous concernant n’est envoyé.",
            refresh: "Actualiser",
            goal: "But", touchdown: "Touchdown", fieldGoal: "Field goal", safety: "Safety", scored: "Points",
            started: "Coup d’envoi", final: "Fin du match", setWon: "Set",
            race: "Course", qualifying: "Qualifications", sprint: "Sprint", lapFormat: "Tour %@",
            sportLabel: "Sport", everyGame: "Tous les matchs", everyMatch: "Tous les matchs en simple", everySession: "Essais, qualifications, sprints et courses",
            possession: "Possession", shots: "Tirs", shotsOnTarget: "Cadrés", corners: "Corners", fouls: "Fautes", offsides: "Hors-jeu", saves: "Arrêts", moments: "Temps forts", stats: "Statistiques", leaders: "Meilleurs joueurs", passing: "Passes", rushing: "Courses", receiving: "Réceptions", ownGoal: "c.s.c.", penalty: "pén.", lastPlay: "Dernière action", openESPN: "Ouvrir dans ESPN",
            basketball: "Basket-ball", baseball: "Baseball", hockey: "Hockey", golf: "Golf", mma: "MMA", everyTournament: "Tous les tournois", everyCard: "Tous les galas", run: "Point", fieldGoals: "Tirs", threePointers: "Tirs à 3 points", freeThrows: "Lancers francs", rebounds: "Rebonds", assists: "Passes décisives", savePercentage: "% d’arrêts", points: "Points", goals: "Buts", topPerformer: "Meilleur joueur", roundFormat: "Tour %@", thru: "Trou", leaderboard: "Classement", fights: "Combats", winsFormat: "%@ l’emporte",
            collegeFootball: "Football américain universitaire", collegeBasketball: "Basket-ball universitaire", conference: "Conférence",
            standings: "Classement", playedShort: "J", wonShort: "G", drawnShort: "N", lostShort: "P", goalDifferenceShort: "Diff.", pointsShort: "Pts",
            motorsport: "Sport automobile", country: "Pays", international: "International", england: "Angleterre", sampleHome: "Domicile", sampleAway: "Extérieur", sampleGame: "Match d’exemple", practiceFormat: "Essais libres %@")
        case .it: return NotchScoresStrings(
            title: "Risultati",
            description: "Segui in diretta i risultati delle tue squadre e dei tuoi atleti nella Dynamic Island: calcio, football americano, tennis e Formula 1.",
            summary: "Risultati in diretta delle squadre e degli atleti che segui.",
            soccer: "Calcio", football: "Football americano", tennis: "Tennis", racing: "Formula 1",
            nationalTeams: "Nazionali",
            following: "Seguiti", follow: "Segui", unfollow: "Non seguire più",
            add: "Aggiungi squadre e atleti", league: "Competizione", search: "Cerca",
            loading: "Caricamento…", unavailable: "Al momento ESPN non è raggiungibile.",
            noneFollowed: "Non segui ancora nessuna squadra né atleta.",
            emptyPage: "Segui squadre e atleti in Impostazioni per vedere qui le loro partite.",
            chooseTeams: "Scegli squadre", nothingSoon: "Nessuna partita nei prossimi sette giorni.",
            live: "In diretta", upNext: "Prossime", results: "Risultati",
            liveActivity: "Mostra le partite in diretta con l’isola chiusa",
            alerts: "Avvisami quando una partita inizia, qualcuno segna e quando finisce",
            source: "I risultati arrivano dai tabellini pubblici di ESPN. Vengono richiesti solo le competizioni, le squadre e gli atleti che segui, e non viene inviato nulla su di te.",
            refresh: "Aggiorna",
            goal: "Gol", touchdown: "Touchdown", fieldGoal: "Field goal", safety: "Safety", scored: "Punti",
            started: "Iniziata", final: "Finale", setWon: "Set",
            race: "Gara", qualifying: "Qualifiche", sprint: "Sprint", lapFormat: "Giro %@",
            sportLabel: "Sport", everyGame: "Tutte le partite", everyMatch: "Tutti gli incontri di singolare", everySession: "Prove libere, qualifiche, sprint e gare",
            possession: "Possesso palla", shots: "Tiri", shotsOnTarget: "In porta", corners: "Calci d’angolo", fouls: "Falli", offsides: "Fuorigioco", saves: "Parate", moments: "Momenti chiave", stats: "Statistiche", leaders: "Migliori", passing: "Passaggi", rushing: "Corse", receiving: "Ricezioni", ownGoal: "aut.", penalty: "rig.", lastPlay: "Ultima azione", openESPN: "Apri in ESPN",
            basketball: "Basket", baseball: "Baseball", hockey: "Hockey", golf: "Golf", mma: "MMA", everyTournament: "Tutti i tornei", everyCard: "Tutte le serate", run: "Punto", fieldGoals: "Tiri dal campo", threePointers: "Tiri da 3", freeThrows: "Tiri liberi", rebounds: "Rimbalzi", assists: "Assist", savePercentage: "% parate", points: "Punti", goals: "Gol", topPerformer: "Migliore in campo", roundFormat: "Giro %@", thru: "Buca", leaderboard: "Classifica", fights: "Incontri", winsFormat: "Vince %@",
            collegeFootball: "Football americano universitario", collegeBasketball: "Basket universitario", conference: "Conference",
            standings: "Classifica", playedShort: "G", wonShort: "V", drawnShort: "N", lostShort: "P", goalDifferenceShort: "DR", pointsShort: "Pt",
            motorsport: "Motori", country: "Paese", international: "Internazionale", england: "Inghilterra", sampleHome: "Casa", sampleAway: "Ospiti", sampleGame: "Partita di esempio", practiceFormat: "Prove libere %@")
        case .ru: return NotchScoresStrings(
            title: "Счёт",
            description: "Следите за счётом своих команд и спортсменов в Dynamic Island в реальном времени: футбол, американский футбол, теннис и «Формула-1».",
            summary: "Счёт в реальном времени для команд и спортсменов, за которыми вы следите.",
            soccer: "Футбол", football: "Американский футбол", tennis: "Теннис", racing: "Формула-1",
            nationalTeams: "Сборные",
            following: "Отслеживаются", follow: "Следить", unfollow: "Не следить",
            add: "Добавить команды и спортсменов", league: "Турнир", search: "Поиск",
            loading: "Загрузка…", unavailable: "Сейчас ESPN недоступен.",
            noneFollowed: "Вы пока не следите ни за одной командой или спортсменом.",
            emptyPage: "Выберите команды и спортсменов в Настройках, чтобы видеть их матчи здесь.",
            chooseTeams: "Выбрать команды", nothingSoon: "В ближайшие семь дней матчей нет.",
            live: "В эфире", upNext: "Скоро", results: "Результаты",
            liveActivity: "Показывать матчи в эфире в закрытом острове",
            alerts: "Сообщать, когда матч начинается, кто-то забивает и когда он заканчивается",
            source: "Счёт берётся из открытых табло ESPN. Запрашиваются только турниры, команды и спортсмены, за которыми вы следите, и никакие сведения о вас не отправляются.",
            refresh: "Обновить",
            goal: "Гол", touchdown: "Тачдаун", fieldGoal: "Филд-гол", safety: "Сейфти", scored: "Очки",
            started: "Начался", final: "Конец", setWon: "Сет",
            race: "Гонка", qualifying: "Квалификация", sprint: "Спринт", lapFormat: "Круг %@",
            sportLabel: "Вид спорта", everyGame: "Все матчи", everyMatch: "Все одиночные матчи", everySession: "Практики, квалификации, спринты и гонки",
            possession: "Владение", shots: "Удары", shotsOnTarget: "В створ", corners: "Угловые", fouls: "Фолы", offsides: "Офсайды", saves: "Сейвы", moments: "Ключевые моменты", stats: "Статистика", leaders: "Лидеры", passing: "Пасы", rushing: "Выносы", receiving: "Приёмы", ownGoal: "авт.", penalty: "пен.", lastPlay: "Последний розыгрыш", openESPN: "Открыть в ESPN",
            basketball: "Баскетбол", baseball: "Бейсбол", hockey: "Хоккей", golf: "Гольф", mma: "ММА", everyTournament: "Все турниры", everyCard: "Все бойцовские вечера", run: "Ран", fieldGoals: "Броски с игры", threePointers: "Трёхочковые", freeThrows: "Штрафные", rebounds: "Подборы", assists: "Передачи", savePercentage: "% отражённых", points: "Очки", goals: "Голы", topPerformer: "Лучший игрок", roundFormat: "Раунд %@", thru: "Лунка", leaderboard: "Таблица лидеров", fights: "Бои", winsFormat: "Победа: %@",
            collegeFootball: "Студенческий американский футбол", collegeBasketball: "Студенческий баскетбол", conference: "Конференция",
            standings: "Таблица", playedShort: "И", wonShort: "В", drawnShort: "Н", lostShort: "П", goalDifferenceShort: "РМ", pointsShort: "О",
            motorsport: "Автоспорт", country: "Страна", international: "Международные", england: "Англия", sampleHome: "Хозяева", sampleAway: "Гости", sampleGame: "Пример матча", practiceFormat: "Практика %@")
        case .tr: return NotchScoresStrings(
            title: "Skorlar",
            description: "Takımlarının ve sporcularının skorlarını Dynamic Island’da canlı takip et: futbol, Amerikan futbolu, tenis ve Formula 1.",
            summary: "Takip ettiğin takım ve sporcuların canlı skorları.",
            soccer: "Futbol", football: "Amerikan Futbolu", tennis: "Tenis", racing: "Formula 1",
            nationalTeams: "Milli Takımlar",
            following: "Takip Edilenler", follow: "Takip Et", unfollow: "Takibi Bırak",
            add: "Takım ve Sporcu Ekle", league: "Turnuva", search: "Ara",
            loading: "Yükleniyor…", unavailable: "ESPN’e şu anda ulaşılamıyor.",
            noneFollowed: "Henüz hiçbir takımı veya sporcuyu takip etmiyorsun.",
            emptyPage: "Maçlarını burada görmek için Ayarlar’dan takım ve sporcu takip et.",
            chooseTeams: "Takım Seç", nothingSoon: "Önümüzdeki yedi günde maç yok.",
            live: "Canlı", upNext: "Sıradaki", results: "Sonuçlar",
            liveActivity: "Canlı maçları kapalı adada göster",
            alerts: "Maç başladığında, biri skor yaptığında ve maç bittiğinde haber ver",
            source: "Skorlar ESPN’in herkese açık skor tablolarından gelir. Yalnızca takip ettiğin turnuvalar, takımlar ve sporcular istenir ve seninle ilgili hiçbir şey gönderilmez.",
            refresh: "Yenile",
            goal: "Gol", touchdown: "Touchdown", fieldGoal: "Field Goal", safety: "Safety", scored: "Sayı",
            started: "Başladı", final: "Maç Sonu", setWon: "Set",
            race: "Yarış", qualifying: "Sıralama", sprint: "Sprint", lapFormat: "Tur %@",
            sportLabel: "Spor", everyGame: "Tüm maçlar", everyMatch: "Tüm tekler maçları", everySession: "Antrenmanlar, sıralamalar, sprintler ve yarışlar",
            possession: "Topla oynama", shots: "Şut", shotsOnTarget: "İsabetli", corners: "Korner", fouls: "Faul", offsides: "Ofsayt", saves: "Kurtarış", moments: "Önemli anlar", stats: "İstatistikler", leaders: "Liderler", passing: "Pas", rushing: "Koşu", receiving: "Top tutma", ownGoal: "k.k.", penalty: "pen.", lastPlay: "Son oyun", openESPN: "ESPN’de aç",
            basketball: "Basketbol", baseball: "Beyzbol", hockey: "Hokey", golf: "Golf", mma: "MMA", everyTournament: "Tüm turnuvalar", everyCard: "Tüm dövüş geceleri", run: "Sayı", fieldGoals: "Saha içi atış", threePointers: "Üçlük", freeThrows: "Serbest atış", rebounds: "Ribaunt", assists: "Asist", savePercentage: "Kurtarış %", points: "Puan", goals: "Gol", topPerformer: "En iyi oyuncu", roundFormat: "%@. tur", thru: "Delik", leaderboard: "Sıralama", fights: "Dövüşler", winsFormat: "%@ kazandı",
            collegeFootball: "Üniversite Amerikan Futbolu", collegeBasketball: "Üniversite Basketbolu", conference: "Konferans",
            standings: "Puan Durumu", playedShort: "O", wonShort: "G", drawnShort: "B", lostShort: "M", goalDifferenceShort: "AV", pointsShort: "P",
            motorsport: "Motor Sporları", country: "Ülke", international: "Uluslararası", england: "İngiltere", sampleHome: "Ev Sahibi", sampleAway: "Deplasman", sampleGame: "Örnek maç", practiceFormat: "Antrenman %@")
        case .ja: return NotchScoresStrings(
            title: "スコア",
            description: "応援しているチームや選手のスコアをDynamic Islandでライブ表示します。サッカー、アメフト、テニス、F1に対応。",
            summary: "フォロー中のチームや選手のライブスコア。",
            soccer: "サッカー", football: "アメフト", tennis: "テニス", racing: "F1",
            nationalTeams: "代表チーム",
            following: "フォロー中", follow: "フォロー", unfollow: "フォローをやめる",
            add: "チームと選手を追加", league: "大会", search: "検索",
            loading: "読み込み中…", unavailable: "現在ESPNに接続できません。",
            noneFollowed: "まだチームや選手をフォローしていません。",
            emptyPage: "設定でチームや選手をフォローすると、ここに試合が表示されます。",
            chooseTeams: "チームを選択", nothingSoon: "今後7日間に試合はありません。",
            live: "ライブ", upNext: "次の試合", results: "結果",
            liveActivity: "閉じたアイランドにライブの試合を表示",
            alerts: "試合開始、得点、試合終了を知らせる",
            source: "スコアはESPNの公開スコアボードから取得します。リクエストされるのはフォロー中の大会、チーム、選手だけで、あなたに関する情報は送信されません。",
            refresh: "更新",
            goal: "ゴール", touchdown: "タッチダウン", fieldGoal: "フィールドゴール", safety: "セーフティ", scored: "得点",
            started: "試合開始", final: "試合終了", setWon: "セット",
            race: "決勝", qualifying: "予選", sprint: "スプリント", lapFormat: "%@周",
            sportLabel: "スポーツ", everyGame: "すべての試合", everyMatch: "すべてのシングルスの試合", everySession: "フリー走行、予選、スプリント、決勝",
            possession: "ボール支配率", shots: "シュート", shotsOnTarget: "枠内", corners: "コーナー", fouls: "ファウル", offsides: "オフサイド", saves: "セーブ", moments: "主な出来事", stats: "スタッツ", leaders: "リーダー", passing: "パス", rushing: "ラン", receiving: "レシーブ", ownGoal: "OG", penalty: "PK", lastPlay: "直前のプレー", openESPN: "ESPNで開く",
            basketball: "バスケットボール", baseball: "野球", hockey: "アイスホッケー", golf: "ゴルフ", mma: "総合格闘技", everyTournament: "すべての大会", everyCard: "すべての興行", run: "得点", fieldGoals: "フィールドゴール", threePointers: "3ポイント", freeThrows: "フリースロー", rebounds: "リバウンド", assists: "アシスト", savePercentage: "セーブ率", points: "得点", goals: "ゴール", topPerformer: "最優秀選手", roundFormat: "ラウンド%@", thru: "ホール", leaderboard: "リーダーボード", fights: "試合", winsFormat: "%@の勝利",
            collegeFootball: "カレッジフットボール", collegeBasketball: "カレッジバスケットボール", conference: "カンファレンス",
            standings: "順位表", playedShort: "試合", wonShort: "勝", drawnShort: "分", lostShort: "敗", goalDifferenceShort: "得失", pointsShort: "勝点",
            motorsport: "モータースポーツ", country: "国", international: "国際", england: "イングランド", sampleHome: "ホーム", sampleAway: "アウェー", sampleGame: "サンプルの試合", practiceFormat: "フリー走行%@")
        case .ko: return NotchScoresStrings(
            title: "스코어",
            description: "응원하는 팀과 선수의 스코어를 Dynamic Island에서 실시간으로 확인하세요. 축구, 미식축구, 테니스, F1을 지원합니다.",
            summary: "팔로우하는 팀과 선수의 실시간 스코어.",
            soccer: "축구", football: "미식축구", tennis: "테니스", racing: "F1",
            nationalTeams: "국가대표",
            following: "팔로잉", follow: "팔로우", unfollow: "팔로우 취소",
            add: "팀 및 선수 추가", league: "대회", search: "검색",
            loading: "불러오는 중…", unavailable: "지금은 ESPN에 연결할 수 없습니다.",
            noneFollowed: "아직 팔로우하는 팀이나 선수가 없습니다.",
            emptyPage: "설정에서 팀과 선수를 팔로우하면 여기에 경기가 표시됩니다.",
            chooseTeams: "팀 선택", nothingSoon: "앞으로 7일 동안 경기가 없습니다.",
            live: "라이브", upNext: "다음 경기", results: "결과",
            liveActivity: "닫힌 아일랜드에 진행 중인 경기 표시",
            alerts: "경기 시작, 득점, 경기 종료 시 알림",
            source: "스코어는 ESPN의 공개 스코어보드에서 가져옵니다. 팔로우하는 대회, 팀, 선수만 요청하며 사용자에 관한 정보는 전송하지 않습니다.",
            refresh: "새로 고침",
            goal: "골", touchdown: "터치다운", fieldGoal: "필드골", safety: "세이프티", scored: "득점",
            started: "경기 시작", final: "경기 종료", setWon: "세트",
            race: "결승", qualifying: "예선", sprint: "스프린트", lapFormat: "%@랩",
            sportLabel: "종목", everyGame: "모든 경기", everyMatch: "모든 단식 경기", everySession: "연습 주행, 예선, 스프린트, 결승",
            possession: "점유율", shots: "슈팅", shotsOnTarget: "유효 슈팅", corners: "코너킥", fouls: "파울", offsides: "오프사이드", saves: "선방", moments: "주요 장면", stats: "기록", leaders: "리더", passing: "패싱", rushing: "러싱", receiving: "리시빙", ownGoal: "자책", penalty: "PK", lastPlay: "마지막 플레이", openESPN: "ESPN에서 열기",
            basketball: "농구", baseball: "야구", hockey: "아이스하키", golf: "골프", mma: "종합격투기", everyTournament: "모든 대회", everyCard: "모든 이벤트", run: "득점", fieldGoals: "야투", threePointers: "3점슛", freeThrows: "자유투", rebounds: "리바운드", assists: "어시스트", savePercentage: "세이브율", points: "득점", goals: "골", topPerformer: "최고 선수", roundFormat: "%@라운드", thru: "홀", leaderboard: "리더보드", fights: "경기", winsFormat: "%@ 승리",
            collegeFootball: "대학 미식축구", collegeBasketball: "대학 농구", conference: "콘퍼런스",
            standings: "순위", playedShort: "경기", wonShort: "승", drawnShort: "무", lostShort: "패", goalDifferenceShort: "득실", pointsShort: "승점",
            motorsport: "모터스포츠", country: "국가", international: "국제", england: "잉글랜드", sampleHome: "홈", sampleAway: "원정", sampleGame: "예시 경기", practiceFormat: "연습 주행 %@")
        case .uk: return NotchScoresStrings(
            title: "Рахунок",
            description: "Стежте за рахунком своїх команд і спортсменів у Dynamic Island наживо: футбол, американський футбол, теніс і «Формула-1».",
            summary: "Рахунок наживо для команд і спортсменів, за якими ви стежите.",
            soccer: "Футбол", football: "Американський футбол", tennis: "Теніс", racing: "Формула-1",
            nationalTeams: "Збірні",
            following: "Відстежуються", follow: "Стежити", unfollow: "Не стежити",
            add: "Додати команди й спортсменів", league: "Турнір", search: "Пошук",
            loading: "Завантаження…", unavailable: "Зараз ESPN недоступний.",
            noneFollowed: "Ви поки не стежите за жодною командою чи спортсменом.",
            emptyPage: "Оберіть команди й спортсменів у Параметрах, щоб бачити їхні матчі тут.",
            chooseTeams: "Вибрати команди", nothingSoon: "Найближчі сім днів матчів немає.",
            live: "Наживо", upNext: "Незабаром", results: "Результати",
            liveActivity: "Показувати матчі наживо в закритому острові",
            alerts: "Повідомляти, коли матч починається, хтось забиває і коли він закінчується",
            source: "Рахунок береться з відкритих табло ESPN. Запитуються лише турніри, команди й спортсмени, за якими ви стежите, і жодні відомості про вас не надсилаються.",
            refresh: "Оновити",
            goal: "Гол", touchdown: "Тачдаун", fieldGoal: "Філд-гол", safety: "Сейфті", scored: "Очки",
            started: "Почався", final: "Кінець", setWon: "Сет",
            race: "Гонка", qualifying: "Кваліфікація", sprint: "Спринт", lapFormat: "Коло %@",
            sportLabel: "Вид спорту", everyGame: "Усі матчі", everyMatch: "Усі одиночні матчі", everySession: "Практики, кваліфікації, спринти й гонки",
            possession: "Володіння", shots: "Удари", shotsOnTarget: "У площину", corners: "Кутові", fouls: "Фоли", offsides: "Офсайди", saves: "Сейви", moments: "Ключові моменти", stats: "Статистика", leaders: "Лідери", passing: "Паси", rushing: "Виноси", receiving: "Прийоми", ownGoal: "авт.", penalty: "пен.", lastPlay: "Останній розіграш", openESPN: "Відкрити в ESPN",
            basketball: "Баскетбол", baseball: "Бейсбол", hockey: "Хокей", golf: "Гольф", mma: "ММА", everyTournament: "Усі турніри", everyCard: "Усі бійцівські вечори", run: "Ран", fieldGoals: "Кидки з гри", threePointers: "Триочкові", freeThrows: "Штрафні", rebounds: "Підбирання", assists: "Передачі", savePercentage: "% відбитих", points: "Очки", goals: "Голи", topPerformer: "Найкращий гравець", roundFormat: "Раунд %@", thru: "Лунка", leaderboard: "Таблиця лідерів", fights: "Бої", winsFormat: "Перемога: %@",
            collegeFootball: "Студентський американський футбол", collegeBasketball: "Студентський баскетбол", conference: "Конференція",
            standings: "Таблиця", playedShort: "І", wonShort: "В", drawnShort: "Н", lostShort: "П", goalDifferenceShort: "РМ", pointsShort: "О",
            motorsport: "Автоспорт", country: "Країна", international: "Міжнародні", england: "Англія", sampleHome: "Господарі", sampleAway: "Гості", sampleGame: "Приклад матчу", practiceFormat: "Практика %@")
        case .zhHans: return NotchScoresStrings(
            title: "比分",
            description: "在灵动岛中实时关注你喜爱的球队和运动员的比分：足球、美式橄榄球、网球和 F1。",
            summary: "你关注的球队和运动员的实时比分。",
            soccer: "足球", football: "美式橄榄球", tennis: "网球", racing: "F1",
            nationalTeams: "国家队",
            following: "已关注", follow: "关注", unfollow: "取消关注",
            add: "添加球队和运动员", league: "赛事", search: "搜索",
            loading: "正在载入…", unavailable: "目前无法连接 ESPN。",
            noneFollowed: "你还没有关注任何球队或运动员。",
            emptyPage: "在设置中关注球队和运动员，即可在此查看他们的比赛。",
            chooseTeams: "选择球队", nothingSoon: "未来七天没有比赛。",
            live: "直播中", upNext: "即将开始", results: "赛果",
            liveActivity: "在收起的岛中显示进行中的比赛",
            alerts: "在比赛开始、有人得分和比赛结束时提醒我",
            source: "比分来自 ESPN 的公开比分板。只会请求你关注的赛事、球队和运动员，不会发送任何关于你的信息。",
            refresh: "刷新",
            goal: "进球", touchdown: "达阵", fieldGoal: "射门得分", safety: "安防", scored: "得分",
            started: "比赛开始", final: "比赛结束", setWon: "盘",
            race: "正赛", qualifying: "排位赛", sprint: "冲刺赛", lapFormat: "第 %@ 圈",
            sportLabel: "运动", everyGame: "所有比赛", everyMatch: "所有单打比赛", everySession: "练习赛、排位赛、冲刺赛和正赛",
            possession: "控球率", shots: "射门", shotsOnTarget: "射正", corners: "角球", fouls: "犯规", offsides: "越位", saves: "扑救", moments: "关键事件", stats: "统计", leaders: "数据王", passing: "传球", rushing: "冲球", receiving: "接球", ownGoal: "乌龙", penalty: "点球", lastPlay: "上一回合", openESPN: "在 ESPN 中打开",
            basketball: "篮球", baseball: "棒球", hockey: "冰球", golf: "高尔夫", mma: "综合格斗", everyTournament: "所有赛事", everyCard: "所有格斗赛事", run: "得分", fieldGoals: "投篮", threePointers: "三分球", freeThrows: "罚球", rebounds: "篮板", assists: "助攻", savePercentage: "扑救率", points: "得分", goals: "进球", topPerformer: "最佳球员", roundFormat: "第 %@ 轮", thru: "洞", leaderboard: "排行榜", fights: "对决", winsFormat: "%@ 获胜",
            collegeFootball: "大学橄榄球", collegeBasketball: "大学篮球", conference: "联盟",
            standings: "积分榜", playedShort: "赛", wonShort: "胜", drawnShort: "平", lostShort: "负", goalDifferenceShort: "净胜", pointsShort: "积分",
            motorsport: "赛车", country: "国家/地区", international: "国际", england: "英格兰", sampleHome: "主队", sampleAway: "客队", sampleGame: "示例比赛", practiceFormat: "练习赛 %@")
        case .zhTW: return NotchScoresStrings(
            title: "比分",
            description: "在動態島中即時追蹤你支持的球隊和選手的比分：足球、美式足球、網球和 F1。",
            summary: "你追蹤的球隊和選手的即時比分。",
            soccer: "足球", football: "美式足球", tennis: "網球", racing: "F1",
            nationalTeams: "國家隊",
            following: "追蹤中", follow: "追蹤", unfollow: "取消追蹤",
            add: "加入球隊和選手", league: "賽事", search: "搜尋",
            loading: "正在載入…", unavailable: "目前無法連線至 ESPN。",
            noneFollowed: "你尚未追蹤任何球隊或選手。",
            emptyPage: "在設定中追蹤球隊和選手，即可在這裡查看他們的比賽。",
            chooseTeams: "選擇球隊", nothingSoon: "未來七天沒有比賽。",
            live: "直播中", upNext: "即將開始", results: "賽果",
            liveActivity: "在收合的島中顯示進行中的比賽",
            alerts: "在比賽開始、有人得分和比賽結束時提醒我",
            source: "比分來自 ESPN 的公開記分板。只會要求你追蹤的賽事、球隊和選手，不會傳送任何關於你的資訊。",
            refresh: "重新整理",
            goal: "進球", touchdown: "達陣", fieldGoal: "射門得分", safety: "安全分", scored: "得分",
            started: "比賽開始", final: "比賽結束", setWon: "盤",
            race: "正賽", qualifying: "排位賽", sprint: "衝刺賽", lapFormat: "第 %@ 圈",
            sportLabel: "運動", everyGame: "所有比賽", everyMatch: "所有單打比賽", everySession: "練習賽、排位賽、衝刺賽和正賽",
            possession: "控球率", shots: "射門", shotsOnTarget: "射正", corners: "角球", fouls: "犯規", offsides: "越位", saves: "撲救", moments: "關鍵事件", stats: "統計", leaders: "數據王", passing: "傳球", rushing: "衝球", receiving: "接球", ownGoal: "烏龍", penalty: "點球", lastPlay: "上一次進攻", openESPN: "在 ESPN 中打開",
            basketball: "籃球", baseball: "棒球", hockey: "冰球", golf: "高爾夫", mma: "綜合格鬥", everyTournament: "所有賽事", everyCard: "所有格鬥賽事", run: "得分", fieldGoals: "投籃", threePointers: "三分球", freeThrows: "罰球", rebounds: "籃板", assists: "助攻", savePercentage: "撲救率", points: "得分", goals: "進球", topPerformer: "最佳球員", roundFormat: "第 %@ 輪", thru: "洞", leaderboard: "排行榜", fights: "對決", winsFormat: "%@ 獲勝",
            collegeFootball: "大學美式足球", collegeBasketball: "大學籃球", conference: "聯盟",
            standings: "積分榜", playedShort: "賽", wonShort: "勝", drawnShort: "和", lostShort: "負", goalDifferenceShort: "淨勝", pointsShort: "積分",
            motorsport: "賽車", country: "國家/地區", international: "國際", england: "英格蘭", sampleHome: "主隊", sampleAway: "客隊", sampleGame: "範例比賽", practiceFormat: "練習賽 %@")
        case .zhHK: return NotchScoresStrings(
            title: "比分",
            description: "在動態島中即時追蹤你支持的球隊和選手的比分：足球、美式足球、網球和 F1。",
            summary: "你追蹤的球隊和選手的即時比分。",
            soccer: "足球", football: "美式足球", tennis: "網球", racing: "F1",
            nationalTeams: "國家隊",
            following: "追蹤中", follow: "追蹤", unfollow: "取消追蹤",
            add: "加入球隊和選手", league: "賽事", search: "搜尋",
            loading: "正在載入…", unavailable: "目前無法連線至 ESPN。",
            noneFollowed: "你尚未追蹤任何球隊或選手。",
            emptyPage: "在設定中追蹤球隊和選手，即可在這裏查看他們的比賽。",
            chooseTeams: "選擇球隊", nothingSoon: "未來七日沒有比賽。",
            live: "直播中", upNext: "即將開始", results: "賽果",
            liveActivity: "在收合的島中顯示進行中的比賽",
            alerts: "在比賽開始、有人得分和比賽完結時提醒我",
            source: "比分來自 ESPN 的公開記分板。只會要求你追蹤的賽事、球隊和選手，不會傳送任何關於你的資料。",
            refresh: "重新整理",
            goal: "入球", touchdown: "達陣", fieldGoal: "射門得分", safety: "安全分", scored: "得分",
            started: "比賽開始", final: "比賽完結", setWon: "盤",
            race: "正賽", qualifying: "排位賽", sprint: "衝刺賽", lapFormat: "第 %@ 圈",
            sportLabel: "運動", everyGame: "所有比賽", everyMatch: "所有單打比賽", everySession: "練習賽、排位賽、衝刺賽和正賽",
            possession: "控球率", shots: "射門", shotsOnTarget: "射正", corners: "角球", fouls: "犯規", offsides: "越位", saves: "撲救", moments: "關鍵事件", stats: "統計", leaders: "數據王", passing: "傳球", rushing: "衝球", receiving: "接球", ownGoal: "烏龍", penalty: "十二碼", lastPlay: "上一次進攻", openESPN: "在 ESPN 中打開",
            basketball: "籃球", baseball: "棒球", hockey: "冰球", golf: "高爾夫球", mma: "綜合格鬥", everyTournament: "所有賽事", everyCard: "所有格鬥賽事", run: "得分", fieldGoals: "投籃", threePointers: "三分球", freeThrows: "罰球", rebounds: "籃板", assists: "助攻", savePercentage: "撲救率", points: "得分", goals: "入球", topPerformer: "最佳球員", roundFormat: "第 %@ 輪", thru: "洞", leaderboard: "排行榜", fights: "對決", winsFormat: "%@ 勝出",
            collegeFootball: "大學美式足球", collegeBasketball: "大學籃球", conference: "聯盟",
            standings: "積分榜", playedShort: "賽", wonShort: "勝", drawnShort: "和", lostShort: "負", goalDifferenceShort: "得失球", pointsShort: "積分",
            motorsport: "賽車", country: "國家/地區", international: "國際", england: "英格蘭", sampleHome: "主隊", sampleAway: "客隊", sampleGame: "示範比賽", practiceFormat: "練習賽 %@")
        }
    }
}
