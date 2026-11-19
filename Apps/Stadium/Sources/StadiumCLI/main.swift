import Foundation
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

let args = Array(CommandLine.arguments.dropFirst())
let maximumSeed = Int64.max - 1_000_000
let usage = """
Usage: stadium [--hand KIND | --pitcher KIND | --repeat N] [options]
       stadium --replay FILE [--every N]

Generate a deterministic Stadium scenario, or replay a saved app/CLI recording.
  --hand KIND     ride, right, wrong, early, cancel, none (default: ride)
  --pitcher KIND  plate, base, pickoff, wild, drop, hold, self, cancel
  --repeat N      0 normal, 1 cannon, 2 Whaley, 3 pitcher, 4 interlude
  --static        Park the cart; requires --repeat 1 through 4
  --ticks N       Nonnegative scenario length in 60 Hz ticks
                  Defaults: \(StadiumScript.rideTicks) ride, \(StadiumScript.variantTicks) other hands,
                  \(StadiumScript.balkTicks) pitcher, 6000 repeat
  --seed N        Signed 64-bit seed, at most \(maximumSeed)
  --every N       Positive interval for status lines (default: 600 ticks)
  --record FILE   Write the generated input recording
  --replay FILE   Read a recording; cannot combine with scenario options or --record
  --help, -h      Show this help without running a scenario

Events, the final tally and a replay digest are printed. --every only limits
status lines. Native Whaley outcomes require --replay with an app recording;
--whaley does not run a headless copy of the native game.
"""

func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("stadium: \(message)\n".utf8))
    exit(status)
}

if args.contains("--help") || args.contains("-h") {
    print(usage)
    exit(0)
}

let valueOptions: Set<String> = ["--hand", "--pitcher", "--repeat", "--ticks", "--seed", "--every", "--record", "--replay"]
var options: [String: String] = [:]
var flags: Set<String> = []
var seen: Set<String> = []
var argumentIndex = 0
while argumentIndex < args.count {
    let name = args[argumentIndex]
    guard seen.insert(name).inserted else { fail("Duplicate option \(name).") }
    if valueOptions.contains(name) {
        guard argumentIndex + 1 < args.count, !args[argumentIndex + 1].hasPrefix("--"),
              !args[argumentIndex + 1].isEmpty else { fail("Missing value for \(name).") }
        options[name] = args[argumentIndex + 1]
        argumentIndex += 2
    } else if name == "--static" {
        flags.insert(name)
        argumentIndex += 1
    } else if name == "--whaley" {
        fail("Use --replay with a Stadium recording to replay observed Whaley outcomes.")
    } else {
        fail("Unknown argument '\(name)'. Use --help for usage.")
    }
}

func integer(_ name: String) -> Int? {
    guard let text = options[name] else { return nil }
    guard let value = Int(text) else { fail("\(name) requires an integer, got '\(text)'.") }
    return value
}

let ticks = integer("--ticks")
if let ticks, ticks < 0 { fail("--ticks must be nonnegative.") }
let every = integer("--every") ?? 600
guard every > 0 else { fail("--every must be positive.") }
let seed = options["--seed"].flatMap { Int64($0) }
if options["--seed"] != nil && seed == nil { fail("--seed requires a signed 64-bit integer.") }
if let seed, seed > maximumSeed { fail("--seed must be at most \(maximumSeed) to leave room for the pitcher seed.") }
let hand = options["--hand"].flatMap(StadiumScript.Kind.init(rawValue:))
if options["--hand"] != nil && hand == nil {
    fail("--hand must be one of: \(StadiumScript.Kind.allCases.map(\.rawValue).joined(separator: ", ")).")
}
let pitcher = options["--pitcher"].flatMap(StadiumScript.PitcherKind.init(rawValue:))
if options["--pitcher"] != nil && pitcher == nil {
    fail("--pitcher must be one of: \(StadiumScript.PitcherKind.allCases.map(\.rawValue).joined(separator: ", ")).")
}
let repeated = integer("--repeat").flatMap(RepeatState.init(rawValue:))
if options["--repeat"] != nil && repeated == nil { fail("--repeat must be in 0...4. Use --help for the sections.") }
let modes = ["--hand", "--pitcher", "--repeat", "--replay"].filter { options[$0] != nil }
guard modes.count <= 1 else { fail("Choose only one of --hand, --pitcher, --repeat or --replay.") }
if flags.contains("--static") && (repeated == nil || repeated == .off) {
    fail("--static requires --repeat 1 through 4.")
}
if options["--replay"] != nil {
    if options["--record"] != nil { fail("--record and --replay cannot be combined.") }
    if ticks != nil || seed != nil { fail("--ticks and --seed apply only to generated scenarios, not --replay.") }
}

var recording: StadiumRecording
if let path = options["--replay"] {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        recording = try JSONDecoder().decode(StadiumRecording.self, from: data)
    } catch DecodingError.dataCorrupted(let context) {
        fail("Cannot replay this Stadium recording: \(context.debugDescription)")
    } catch {
        fail("Cannot read this Stadium recording: \(error.localizedDescription)")
    }
    guard recording.parameters.seed <= maximumSeed else { fail("The recording's seed exceeds \(maximumSeed).") }
} else if let state = repeated {
    var p = StadiumScript.balkParameters()
    if let seed { p.seed = seed }
    let parks: [Int: Bool] = flags.contains("--static") ? [0: true] : [:]
    recording = StadiumRecording(parameters: p, inputs: StadiumScript.repeatInputs(toggles: [0: state], parks: parks, ticks: ticks ?? 6000))
} else if let pitcher {
    var p = StadiumScript.balkParameters()
    if let seed { p.seed = seed }
    recording = StadiumRecording(parameters: p, inputs: StadiumScript.pitcherInputs(kind: pitcher, parameters: p, ticks: ticks ?? StadiumScript.balkTicks))
} else {
    let kind = hand ?? .ride
    var p = StadiumParameters.stadium
    if let v = StadiumScript.variants.first(where: { $0.kind == kind }) { p = StadiumScript.parameters(v) }
    if let seed { p.seed = seed }
    recording = StadiumScript.recording(kind: kind, parameters: p, ticks: ticks)
}

if let path = options["--record"] {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(recording).write(to: URL(fileURLWithPath: path))
    } catch {
        fail("Cannot write the recording to '\(path)': \(error.localizedDescription)", status: 1)
    }
    print("recorded \(recording.inputs.count) ticks to \(path)")
}

let f = TextFormat.fmt
func u(_ v: Double, _ places: Int) -> String { let s = f(v, places); return s.hasPrefix("+") ? String(s.dropFirst()) : s }
let p = recording.parameters
func point(_ x: Fixed, _ y: Fixed) -> String { "(\(f(x.double, 1)), \(f(y.double, 1)))" }
let wheelNames = ["rear left", "rear right", "front left", "front right"]
print("the Bullpen Cart: \(recording.inputs.count) ticks, seed \(p.seed), picture \(u(p.picture.width.double, 0)) by \(u(p.picture.height.double, 0)), \(p.sponsor) Stadium")
func describe(_ e: RideEvent) -> String {
    switch e {
    case .bubble(let id, let pipe, let x, let y): "bubble \(id) out of the \(pipe == 0 ? "left" : "right") exhaust pipe, to \(point(x, y))"
    case .grabbed(let id): "bubble \(id) taken"
    case .released(let id): "bubble \(id) let go"
    case .popped(let id): "bubble \(id) popped"
    case .hop(let wheel, let bubble, let onBeat): "the \(wheelNames[wheel.rawValue]) wheel bounces off bubble \(bubble)\(onBeat ? ", on the beat" : "")"
    case .beep(let figure, let garden): "the thought reel starts for fan \(figure)\(garden ? ", in the garden section" : "")"
    case .locked(let id): "bubble \(id) locks on the fan"
    case .unlocked: "the lock let go, nothing fired"
    case .fired(let item, let figure, let part, let distance):
        figure >= 0 ? "the \(item.name) on fan \(figure)'s \(part == 0 ? "head" : "torso"), \(u(distance.double, 1)) m off" : "the \(item.name) on nobody"
    case .result(let r): r.headline
    case .lap(let n): "lap \(n)"
    case .captured(let id): "the pitcher's ball captured in bubble \(id)"
    case .thrown(let how, let speed, let way):
        switch how {
        case .thrown: "the ball thrown, \(u(speed.double, 1)) m/s heading \(u(way.double * 360, 0)) degrees"
        case .dropped: "the ball dropped"
        case .held: "the ball kept too long, dropped"
        }
    case .fielded(let who, let by, _, let outcome):
        switch who {
        case .atPlate, .atBase, .outfield: "caught by the \(Fielder.all[by].name): \(outcome.headline)"
        case .fan: "caught by fan \(by): \(outcome.headline)"
        case .pitcherHimself: "the pitcher has it: \(outcome.headline)"
        case .nobody: "settled, nobody near: \(outcome.headline)"
        }
    case .balk(let type, let points, let until): "BALK, \(type.headline), \(points) points, every camera on the pitcher until t=\(until)"
    case .newBall(let runners): "a new ball, runners on " + runners.map(\.name).joined(separator: ", ")
    case .repeat(let state): "the debug toggle set to \(state.rawValue) (\(state.name))"
    case .turnaround(let direction): "the kart turns around, now driving \(direction > 0 ? "forward" : "back")"
    case .crew(let subject): subject == .free ? "the Jumbotron back to its program" : "the Jumbotron on \(subject.name)"
    case .parked(let on): "the debug toggle's static mode \(on ? "on" : "off")"
    case .zoom(let inward, let bubble): inward ? "the camera zooms in on the Jumbotron, bubble \(bubble) carried in" : "the camera zooms back out"
    case .interlude(let begun, let fan, let number):
        begun ? "interlude \(number) begins, the ride paused, the camera turning to fan \(fan) and his phone" : "interlude \(number) over, the ride on"
    }
}
func describe(_ event: WhaleyEvent) -> String {
    switch event {
    case .bubbleContact(let id, let uses, let popped, let bounced):
        return "bubble \(id): \(bounced ? "bounce" : "contact"), \(uses) uses left\(popped ? ", popped" : "")"
    case .coin: return "coin taken"
    case .died: return "Whaley dies"
    case .goal: return "level completed"
    }
}
let snapshots = recording.replay()
for s in snapshots {
    let c = s.car
    let r = s.ride
    if s.tick % every == 0 {
        var line = "t=\(s.tick) \(TextFormat.clock(s.tick)) kart (\(f(c.x.double, 1)), \(f(c.z.double, 1))) \(u(c.speed.double, 1)) m/s, lap \(r.lap + 1), "
            + "\(r.bubbles.count) bubbles, \(u(r.tempo.double, 0)) bpm, \(r.tally.points) points" + (r.zoom == .one ? "" : (r.zoom > .one ? ", zoomed out \(u(r.zoom.double, 2))" : ", zoomed in \(u(1 / r.zoom.double, 2))"))
        if let inc = r.incident, inc.isLive {
            let thought = s.tick < inc.start ? "reel spinning" : "thinking of \(inc.symbol.label)"
            line += ", fan \(inc.figure) \(thought)\(inc.isLocked ? ", locked on" : "")"
        }
        if r.pitcher.inView || r.pitcher.fade > .zero {
            line += ", the pitcher \(r.pitcher.inView ? "on the picture" : "leaving")"
            line += String(format: ", the Bullpen Cart faded %.2f, the view in %.2f", r.pitcher.fade.double, 1 / r.zoom.double)
        }
        if r.pitcher.ball.state != .tossing { line += ", the ball \(r.pitcher.ball.state)" }
        if r.pitcher.crew != .free { line += ", the Jumbotron on \(r.pitcher.crew.name)" }
        if r.pitcher.camerasOnHim(at: s.tick) { line += ", every camera on the pitcher" }
        if r.repeat.state == .interlude {
            line += ", the interlude's level"
        } else if r.repeat.state != .off {
            line += ", the \(r.repeat.state.name)'s stretch repeated, driving \(r.repeat.direction > 0 ? "forward" : "back")"
        }
        if let i = r.interlude.on {
            switch i.phase {
            case .turningIn: line += ", the camera turning to fan \(i.fan)"
            case .browsing: line += ", fan \(i.fan) on his phone, waiting for Done"
            case .catchWatched: line += ", the hot dog fired at fan \(i.fan)"
            case .turningBack: line += ", the camera turning back"
            }
        } else if r.interlude.pending {
            line += ", the interlude due, waiting for the ride to be quiet"
        }
        if let j = r.jumbo.zoom {
            line += j.out ? ", the camera on its way back from the Jumbotron" : (j.isIn(ticks: p.ride.whaley.zoomTicks) ? ", the camera on the Jumbotron" : ", the camera on its way to the Jumbotron")
        }
        if r.whaley.shown {
            let g = r.whaley.observation
            line += ", Gray Whale 2010 on the Jumbotron: level \(g.number), Whaley at (\(u(g.x.double, 0)), \(u(g.y.double, 0)))\(g.dead ? ", dead" : "")"
                + ", \(r.whaley.over.count) stadium bubbles over the screen"
        }
        print(line)
    }
    for e in r.events { print("  t=\(s.tick) \(describe(e))") }
    for e in r.whaley.events { print("  t=\(s.tick) the Jumbotron's game: \(describe(e))") }
    for e in r.events {
        guard case .result = e, let q = r.lastResult else { continue }
        print("result at t=\(q.endTick): \(q.result.headline): fan \(q.figure)\(q.garden ? " (garden)" : ""), \(q.symbol.label), "
              + "beeped at t=\(q.beep)\(q.shot >= 0 ? ", the \(q.item.name) at t=\(q.shot)" : ", nothing fired")")
    }
}
let tally = snapshots.last?.ride.tally ?? RideTally()
print("tally: laps \(tally.laps), fan thoughts \(tally.alarms) (\(tally.garden) in the garden section), hot dogs served \(tally.served), correct holds \(tally.heldFire)"
      + (tally.tooSoon > 0 ? ", early shots \(tally.tooSoon)" : "")
      + ", wrong calls \(tally.wrong); bounces \(tally.bounces), on the beat \(tally.onBeat), "
      + "points \(tally.points), best streak \(tally.bestStreak)"
      + (tally.balks > 0 ? "; balks \(tally.balks), \(tally.balkPoints) points" : "")
      + (tally.coins > 0 || tally.goals > 0 ? "; the Jumbotron's game: coins \(tally.coins), goals \(tally.goals)" : ""))
print("digest \(StadiumDigest.digest(snapshots).hex)")
