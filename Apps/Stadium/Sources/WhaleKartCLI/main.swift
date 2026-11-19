import Foundation
import StadiumCore
import WhaleKartCore

let args = Array(CommandLine.arguments.dropFirst())
let usage = """
Usage: whalekart [--model a|b] [--ticks N] [--record FILE] [output options]
       whalekart --replay FILE [--model a|b] [output options]

Run the deterministic kart/rope demo, or replay recorded inputs.
  --model a|b    a: rules-chain rope; b: position-based dynamics (default: b)
                 With --replay, explicitly overrides the recorded model
  --ticks N      Demo prefix length, 0...\(DemoScript.ticks) (default: \(DemoScript.ticks))
  --record FILE  Write the generated input recording
  --replay FILE  Read a recording; cannot combine with --ticks or --record
  --ascii        Print status lines and ASCII frames
  --every N      Positive ASCII frame interval (default: 60); requires --ascii
  --trace        Print every tick's raw fixed-point CSV trace
  --help, -h     Show this help without running the demo

ASCII and trace output may be combined. A summary, events and replay digest
are printed for every run.
"""

func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("whalekart: \(message)\n".utf8))
    exit(status)
}

if args.contains("--help") || args.contains("-h") {
    print(usage)
    exit(0)
}

let valueOptions: Set<String> = ["--model", "--ticks", "--every", "--record", "--replay"]
let flagOptions: Set<String> = ["--ascii", "--trace"]
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
    } else if flagOptions.contains(name) {
        flags.insert(name)
        argumentIndex += 1
    } else {
        fail("Unknown argument '\(name)'. Use --help for usage.")
    }
}

func integer(_ name: String) -> Int? {
    guard let text = options[name] else { return nil }
    guard let value = Int(text) else { fail("\(name) requires an integer, got '\(text)'.") }
    return value
}

guard let model = RopeModel(rawValue: options["--model"] ?? "b") else { fail("--model must be a or b.") }
let ticks = integer("--ticks") ?? DemoScript.ticks
guard (0...DemoScript.ticks).contains(ticks) else { fail("--ticks must be in 0...\(DemoScript.ticks), the available demo length.") }
let every = integer("--every") ?? 60
guard every > 0 else { fail("--every must be positive.") }
if options["--every"] != nil && !flags.contains("--ascii") { fail("--every requires --ascii.") }
if options["--replay"] != nil {
    if options["--record"] != nil { fail("--record and --replay cannot be combined.") }
    if options["--ticks"] != nil { fail("--ticks selects a generated demo prefix and cannot be combined with --replay.") }
}

var recording: Recording
if let path = options["--replay"] {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        recording = try JSONDecoder().decode(Recording.self, from: data)
    } catch {
        fail("Cannot read this kart recording: \(error.localizedDescription)")
    }
    if options["--model"] != nil { recording.model = model }
} else {
    recording = DemoScript.recording(model: model)
    if ticks < recording.inputs.count { recording.inputs = Array(recording.inputs.prefix(ticks)) }
}

if let path = options["--record"] {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(recording).write(to: URL(fileURLWithPath: path))
    } catch {
        fail("Cannot write the recording to '\(path)': \(error.localizedDescription)", status: 1)
    }
    print("recorded \(recording.inputs.count) ticks of model \(recording.model.rawValue) to \(path)")
}

let track = Track(parameters: recording.parameters)
let snapshots = recording.replay()

if flags.contains("--ascii") {
    for s in snapshots where s.tick % every == 0 {
        print(TextRenderer.status(s))
        print(TextRenderer.frame(s, track: track))
    }
}
if flags.contains("--trace") {
    print("tick,x,z,heading,yawRate,speed,progress,offset,side,held")
    for s in snapshots {
        let c = s.car
        print("\(s.tick),\(c.x.raw),\(c.z.raw),\(c.heading.raw),\(c.yawRate.raw),\(c.speed.raw),\(c.progress.raw),\(c.offset.raw),\(c.side.raw),\(s.heldIndex)")
    }
}

let events = snapshots.flatMap { s in s.events.map { (s.tick, $0) } }
let worst = snapshots.dropFirst(180).map { $0.car.offset }.max() ?? .zero
let offTrack = snapshots.filter { $0.car.offTrack }.count
var travelled = 0.0
for (a, b) in zip(snapshots, snapshots.dropFirst()) {
    var step = b.car.progress.double - a.car.progress.double
    if step < -track.total.double / 2 { step += track.total.double }
    travelled += step
}
print("model \(recording.model.rawValue): \(snapshots.count) ticks, \(TextFormat.fmt(travelled / track.total.double, 2)) laps, "
      + "furthest from the line once under way \(TextFormat.fmt(worst.double, 3)) m, off the road \(offTrack) ticks, events \(events.count)")
for (tick, event) in events { print("  t=\(tick) \(event)") }
print("digest \(WhaleKartDigest.digest(snapshots).hex)")
