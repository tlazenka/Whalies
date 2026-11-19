// Fixtures come from python/whaley_tools/stadium/ballgame.py and must match Swift bit for bit.

import Foundation
import Testing
import StadiumCore
@testable import BallgameCore

struct SeasonFixture: Decodable {
    let games: [BallgameRecord]
}

struct BallgameFixture: Decodable {
    struct Run: Decodable {
        let samples: [[Int]]
        let events: [[FixtureValue]]
        let awayScore: Int
        let homeScore: Int
        let over: Bool
        let firedErrors: Int
        let digest: String
    }
    let parameters: BallgameParameters
    let gamePk: Int
    let ticks: Int
    let run: Run
}

enum FixtureValue: Decodable, Equatable {
    case int(Int), string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        self = .string(try c.decode(String.self))
    }
}

func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

func fixtureEvents(_ snapshots: [BallgameSnapshot]) -> [[FixtureValue]] {
    snapshots.flatMap { s -> [[FixtureValue]] in
        s.events.map { e in
            switch e {
            case .start(let inning, let half): [.int(s.tick), .string("start"), .int(inning), .int(half)]
            case .error(let index, let inning, let half, let home, let run):
                [.int(s.tick), .string("error"), .int(index), .int(inning), .int(half), .int(home ? 1 : 0), .int(run ? 1 : 0)]
            case .runs(let team, let count, let inning, let half): [.int(s.tick), .string("runs"), .int(team), .int(count), .int(inning), .int(half)]
            case .final(let away, let home): [.int(s.tick), .string("final"), .int(away), .int(home)]
            case .end(let inning, let half, let errors): [.int(s.tick), .string("end"), .int(inning), .int(half), .int(errors)]
            }
        }
    }
}

func play(_ fixture: BallgameFixture) throws -> (game: Ballgame, snapshots: [BallgameSnapshot]) {
    let record = try #require(Ballgame.record(gamePk: fixture.gamePk))
    var game = Ballgame(record: record, parameters: fixture.parameters)
    var snapshots: [BallgameSnapshot] = []
    for _ in 0..<fixture.ticks { snapshots.append(game.step()) }
    return (game, snapshots)
}

@Test
func theSeasonTableIsTheDataset() throws {
    let fixture = try load("season-2026", as: SeasonFixture.self)
    #expect(Season2026.games == fixture.games)
    #expect(Season2026.games.count == 162)
    #expect(Season2026.games.reduce(0) { $0 + $1.errors.count } == 198)
    #expect(Season2026.games.reduce(0) { $0 + $1.halves.count } == 2865)
    for g in Season2026.games {
        #expect(g.innings.map { $0[0] }.reduce(0, +) == g.awayScore, "\(g.gamePk) away runs")
        #expect(g.innings.map { max(0, $0[1]) }.reduce(0, +) == g.homeScore, "\(g.gamePk) home runs")
        if let last = g.innings.last, last[1] < 0 { #expect(g.homeScore > g.awayScore, "\(g.gamePk) unplayed bottom") }
        #expect(g.innings.count >= 9, "\(g.gamePk) innings")
        for (a, b) in zip(g.errors, g.errors.dropFirst()) { #expect((a.inning, a.half) <= (b.inning, b.half), "\(g.gamePk) errors in order") }
    }
    #expect(Ballgame.record(gamePk: 823884)?.date == "2026-04-09")
    #expect(Ballgame.record(gamePk: 1) == nil)
}

@Test
func swiftBallgameReproducesThePythonReferenceBitForBit() throws {
    let fixture = try load("ballgame-823884", as: BallgameFixture.self)
    let (game, snapshots) = try play(fixture)
    for sample in fixture.run.samples {
        let s = snapshots[sample[0]]
        #expect([s.tick, s.halfIndex, s.ticksIntoHalf, s.inning, s.half, s.awayScore, s.homeScore, s.over ? 1 : 0] == sample, "tick \(sample[0])")
    }
    #expect(fixtureEvents(snapshots) == fixture.run.events)
    #expect(game.awayScore == fixture.run.awayScore && game.homeScore == fixture.run.homeScore)
    #expect(game.over == fixture.run.over)
    #expect(game.firedErrors == fixture.run.firedErrors)
    #expect(BallgameDigest.digest(snapshots).hex == fixture.run.digest)
    #expect(BallgameParameters.demo == fixture.parameters)
}

@Test
func theScoreBeforeAHalfIsTheRecords() throws {
    let record = try #require(Ballgame.record(gamePk: 823884))
    #expect(record.score(beforeHalf: 0) == (away: 0, home: 0))
    let bottomOfTheSeventh = try #require(record.halfIndex(of: HalfInning(inning: 7, half: 1)))
    #expect(bottomOfTheSeventh == 13)
    #expect(record.score(beforeHalf: bottomOfTheSeventh) == (away: 1, home: 5))
    #expect(record.score(beforeHalf: record.halves.count) == (away: record.awayScore, home: record.homeScore))
    #expect(record.halfIndex(of: HalfInning(inning: 9, half: 1)) == nil, "the bottom of the 9th was not played")
    #expect(HalfInning(inning: 2, half: 0).title == "top of the 2nd" && HalfInning(inning: 11, half: 1).title == "bottom of the 11th")
}

// Includes the stretch break and ticks before, at, and after a recorded error.
@Test(arguments: [(12, 140), (2, 0), (1, 69), (1, 70), (1, 71), (5, 139), (16, 100)])
func aGameStartedPartOfTheWayIsTheReplays(half: Int, tick: Int) throws {
    let record = try #require(Ballgame.record(gamePk: 823884))
    var replayed = Ballgame(record: record)
    while replayed.halfIndex != half || replayed.ticksIntoHalf != tick { replayed.step() }
    var started = Ballgame(record: record, parameters: BallgameParameters(halfInningTicks: 140, breakTicks: 20, startHalf: half, startTick: tick))
    #expect(started.halfIndex == half && started.ticksIntoHalf == tick && started.tick == 0)
    #expect(started.awayScore == replayed.awayScore && started.homeScore == replayed.homeScore && started.firedErrors == replayed.firedErrors)
    for _ in 0..<600 {
        let a = replayed.step(), b = started.step()
        #expect(a.events == b.events && a.halfIndex == b.halfIndex && a.ticksIntoHalf == b.ticksIntoHalf && a.awayScore == b.awayScore
                && a.homeScore == b.homeScore && a.over == b.over)
    }
    // Older recordings omit the starting half and tick.
    let old = try JSONDecoder().decode(BallgameParameters.self, from: Data(#"{"halfInningTicks": 140, "breakTicks": 20}"#.utf8))
    #expect(old == .demo && old.startHalf == 0 && old.startTick == 0)
}

@Test
func theErrorTimelineIsTheRecords() throws {
    for record in Season2026.games.prefix(40) {
        var game = Ballgame(record: record)
        var fired: [Int: (Int, Int)] = [:]
        var final: (Int, Int)? = nil
        let length = record.halves.count * (BallgameParameters.demo.halfInningTicks + BallgameParameters.demo.breakTicks)
        for _ in 0..<(length + 10) {
            for e in game.step().events {
                switch e {
                case .error(let index, let inning, let half, _, _):
                    #expect(!fired.keys.contains(index), "\(record.gamePk) error \(index) fired twice")
                    fired[index] = (inning, half)
                case .final(let away, let home): final = (away, home)
                default: break
                }
            }
        }
        #expect(fired.count == record.errors.count, "\(record.gamePk) every error fires")
        for (index, where_) in fired { #expect(where_ == (record.errors[index].inning, record.errors[index].half), "\(record.gamePk) error \(index) at its half") }
        #expect(final?.0 == record.awayScore && final?.1 == record.homeScore, "\(record.gamePk) final")
        #expect(game.over)
        let quiet = game.step()
        #expect(quiet.events.isEmpty && quiet.over, "\(record.gamePk) nothing after the final")
    }
}

@Test
func replayIsIdenticalRunToRun() throws {
    let record = try #require(Ballgame.record(gamePk: 822981))      // Extra-inning fixture with five errors.
    func run() -> [BallgameSnapshot] {
        var game = Ballgame(record: record)
        return (0..<4000).map { _ in game.step() }
    }
    let a = run(), b = run()
    #expect(a == b)
    #expect(BallgameDigest.digest(a).hex == BallgameDigest.digest(b).hex)
    #expect(record.halves.count == 20)
}
