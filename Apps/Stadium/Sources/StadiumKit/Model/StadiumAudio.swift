// AVAudioEnvironmentNode spatializes mono inputs; its -z forward/+y up frame matches the scene.

import Foundation
#if canImport(simd)
import simd
#endif
#if canImport(AVFAudio)
import AVFAudio
#endif

enum AudioOutput: String, CaseIterable, Identifiable {
    case headphones = "Headphones"
    case speakers = "Speakers"
    case off = "Off"
    var id: String { rawValue }
}

enum Groove {
    static let tempo = 90.0
    static let steps = 32
    static let kicks: Set<Int> = [0, 6, 8, 11, 16, 22, 24, 27, 30]
    static let snares: Set<Int> = [4, 12, 20, 28]
    static let ghosts: Set<Int> = [15, 31]
    // Original E-minor pentatonic line; length is in sixteenths.
    static let bass: [(step: Int, length: Int, hz: Double)] = [
        (0, 3, 41.20), (3, 1, 82.41), (6, 2, 49.00), (8, 2, 55.00), (10, 1, 41.20), (11, 1, 41.20), (14, 1, 73.42), (15, 1, 61.74),
        (16, 3, 41.20), (19, 1, 82.41), (22, 2, 49.00), (24, 2, 61.74), (26, 1, 55.00), (27, 1, 49.00), (28, 2, 41.20), (30, 2, 36.71),
    ]
    static func rate(bpm: Double) -> Float { Float(min(4, max(0.25, bpm / tempo))) }
    static func segment(beat: Int64) -> Int { Int(((beat % 8) + 8) % 8) }
}

#if canImport(AVFAudio)
final class StadiumAudio {
    enum Cue: CaseIterable { case bloop, swell, pop, boing, boingOnBeat, lock, hotDog, bun, mustard, cheer, groan }

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let crowdPlayer = AVAudioPlayerNode()
    private let groovePlayer = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var beepBuffer: AVAudioPCMBuffer?
    private var crowdBuffer: AVAudioPCMBuffer?
    private var grooveBeats: [AVAudioPCMBuffer] = []
    // Rotate through players so overlapping cues do not cut each other off.
    private var cueBuffers: [Cue: AVAudioPCMBuffer] = [:]
    private var cuePlayers: [AVAudioPlayerNode] = []
    private var nextCue = 0
    private var beepers: [Int: AVAudioPlayerNode] = [:]
    private var started = false
    private var failed = false

    var output: AudioOutput = .headphones {
        didSet {
            if output == .off { silence() }
            for p in Array(beepers.values) { p.renderingAlgorithm = algorithm }
        }
    }

    private var algorithm: AVAudio3DMixingRenderingAlgorithm { output == .speakers ? .equalPowerPanning : .HRTFHQ }

    private func startIfNeeded() -> Bool {
        if started {
            // Interruptions can stop the engine; playing a node before restarting it raises an exception.
            if !engine.isRunning {
                #if os(iOS)
                try? AVAudioSession.sharedInstance().setActive(true)
                #endif
                try? engine.start()
                // Restart the crowd loop; beeps and groove resume on their next tick or beat.
                if engine.isRunning, let crowdBuffer {
                    crowdPlayer.stop()
                    crowdPlayer.scheduleBuffer(crowdBuffer, at: nil, options: .loops)
                    crowdPlayer.play()
                }
            }
            return engine.isRunning
        }
        if failed { return false }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            failed = true
            return false
        }
        #endif
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        engine.attach(crowdPlayer)
        engine.connect(crowdPlayer, to: engine.mainMixerNode, format: format)
        crowdPlayer.volume = 0
        engine.attach(groovePlayer)
        engine.attach(varispeed)
        engine.connect(groovePlayer, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
        groovePlayer.volume = 0.55
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            p.volume = 0.7
            cuePlayers.append(p)
        }
        let distance = environment.distanceAttenuationParameters
        distance.distanceAttenuationModel = .inverse
        distance.referenceDistance = 10          // Full volume at the front row.
        distance.maximumDistance = 150
        distance.rolloffFactor = 0.7
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.largeHall)
        environment.reverbParameters.level = -18
        beepBuffer = Self.beep(format: format)
        crowdBuffer = Self.crowd(format: format)
        grooveBeats = Self.groove(format: format)
        for cue in Cue.allCases { cueBuffers[cue] = Self.cue(cue, format: format) }
        do {
            try engine.start()
            started = true
            if let crowdBuffer {
                crowdPlayer.scheduleBuffer(crowdBuffer, at: nil, options: .loops)
                crowdPlayer.play()
            }
            groovePlayer.play()
            return true
        } catch {
            failed = true
            return false
        }
    }

    private func spatialPlayer() -> AVAudioPlayerNode {
        let p = AVAudioPlayerNode()
        engine.attach(p)
        engine.connect(p, to: environment, format: format)
        p.renderingAlgorithm = algorithm
        p.sourceMode = .pointSource
        p.reverbBlend = 0.25
        p.volume = 0.8
        return p
    }

    private func face(_ listener: SIMD3<Float>, _ facing: SIMD3<Float>) {
        environment.listenerPosition = AVAudio3DPoint(x: listener.x, y: listener.y, z: listener.z)
        let ground = SIMD3<Float>(facing.x, 0, facing.z)
        if simd_length(ground) > 0.0001 {
            let f = simd_normalize(ground)
            environment.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: f.x, y: 0, z: f.z),
                                                                               up: AVAudio3DVector(x: 0, y: 1, z: 0))
        }
    }

    func update(listener: SIMD3<Float>, facing: SIMD3<Float>, crowd: Float) {
        guard output != .off, startIfNeeded() else { return }
        face(listener, facing)
        crowdPlayer.volume += max(-0.05, min(0.05, max(0, min(1, crowd)) * 0.55 - crowdPlayer.volume))
    }

    func beeps(listener: SIMD3<Float>, facing: SIMD3<Float>, beeping: [(figure: Int, position: SIMD3<Float>)]) {
        guard output != .off else { return }
        if beeping.isEmpty && !beepers.values.contains(where: { $0.isPlaying }) { return }
        guard startIfNeeded(), let buffer = beepBuffer else { return }
        face(listener, facing)
        let now = Set(beeping.map { $0.figure })
        for (i, p) in beepers where !now.contains(i) && p.isPlaying { p.stop() }
        for b in beeping {
            let p = beepers[b.figure] ?? spatialPlayer()
            beepers[b.figure] = p
            p.position = AVAudio3DPoint(x: b.position.x, y: b.position.y, z: b.position.z)
            if !p.isPlaying {
                p.scheduleBuffer(buffer, at: nil, options: .loops)
                p.play()
            }
        }
    }

    // Schedule one beat at a time so the groove follows the simulation's changing tempo.
    func groove(tempo bpm: Double, beat: Int64?) {
        guard output != .off, startIfNeeded() else { return }
        varispeed.rate = Groove.rate(bpm: bpm)
        guard let beat, !grooveBeats.isEmpty else { return }
        groovePlayer.scheduleBuffer(grooveBeats[Groove.segment(beat: beat)], at: nil, options: .interrupts)
        if !groovePlayer.isPlaying { groovePlayer.play() }
    }

    func cue(_ cue: Cue) {
        guard output != .off, startIfNeeded(), let buffer = cueBuffers[cue], !cuePlayers.isEmpty else { return }
        let p = cuePlayers[nextCue % cuePlayers.count]
        nextCue += 1
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: [])
        p.play()
    }

    func silence() {
        for p in Array(beepers.values) + cuePlayers + [groovePlayer] where p.isPlaying { p.stop() }
        crowdPlayer.volume = 0
    }

    private static func make(_ format: AVAudioFormat, seconds: Double, _ sample: (Double, inout UInt32) -> Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var noise: UInt32 = 0x9E37_79B9
        for n in 0..<Int(frames) { out[n] = Float(sample(Double(n) / rate, &noise)) }
        return buffer
    }

    private static func white(_ noise: inout UInt32) -> Double {
        noise = noise &* 1_664_525 &+ 1_013_904_223
        return Double(noise >> 8) / Double(1 << 24) * 2 - 1
    }

    static func beep(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        make(format, seconds: 1.0) { t, _ in
            let on = (t < 0.12) || (t >= 0.2 && t < 0.32)
            guard on else { return 0 }
            let k = t < 0.12 ? t : t - 0.2
            let amp = min(1, k / 0.005) * min(1, (0.12 - k) / 0.01)
            return amp * (sin(2 * Double.pi * 2400 * t) >= 0 ? 0.32 : -0.32)
        }
    }

    static func crowd(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var low = 0.0
        return make(format, seconds: 4) { t, noise in
            low += (white(&noise) - low) * 0.08
            let swell = 0.7 + 0.3 * sin(2 * Double.pi * t / 4)
            return low * swell * 1.6
        }
    }

    // Render twice and slice the second pass so notes ring across the loop boundary.
    static func groove(format: AVAudioFormat) -> [AVAudioPCMBuffer] {
        let rate = format.sampleRate
        let step = 60 / Groove.tempo / 4
        let bars = step * Double(Groove.steps)
        guard let whole = make(format, seconds: bars * 2, { t, noise in
            let s = t / step
            let at = Int(s.rounded(.down)) % Groove.steps
            let into = (s - s.rounded(.down)) * step          // Seconds within this sixteenth.
            var v = 0.0
            // Kick: pitch falls from 120 to 45 Hz.
            for k in [0, 1] {
                let i = (at - k + Groove.steps) % Groove.steps, dt = into + Double(k) * step
                if Groove.kicks.contains(i) && dt < 0.25 { v += sin(2 * Double.pi * (45 * dt + 75 * 0.04 * (1 - exp(-dt / 0.04)))) * exp(-dt / 0.09) * 0.9 }
            }
            // Snare: noise over a 190 Hz body.
            if Groove.snares.contains(at) || Groove.ghosts.contains(at) {
                let level = Groove.snares.contains(at) ? 0.5 : 0.15
                v += (0.7 * white(&noise) + 0.3 * sin(2 * Double.pi * 190 * into)) * exp(-into / 0.06) * level
            }
            if at % 2 == 0 { v += white(&noise) * exp(-into / 0.012) * (at % 4 == 0 ? 0.12 : 0.07) }
            // Bass: plucked envelope with a falling initial pitch.
            for note in Groove.bass {
                let start = Double(note.step) * step, length = Double(note.length) * step
                var dt = t.truncatingRemainder(dividingBy: bars) - start
                if dt < 0 { dt += bars }
                guard dt < length + 0.08 else { continue }
                let release = dt < length ? 1 : exp(-(dt - length) / 0.025)
                let hz = note.hz * (1 + 0.06 * exp(-dt / 0.03))
                let phase = 2 * Double.pi * hz * dt
                v += (sin(phase) + 0.35 * sin(2 * phase) + 0.12 * sin(3 * phase)) * min(1, dt / 0.006) * (0.55 + 0.45 * exp(-dt / 0.18)) * release * 0.55
            }
            return max(-1, min(1, v * 0.8))
        }), let source = whole.floatChannelData?[0] else { return [] }
        let beat = AVAudioFrameCount(rate * step * 4)
        var out: [AVAudioPCMBuffer] = []
        for b in 0..<8 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: beat), let dest = buffer.floatChannelData?[0] else { return [] }
            buffer.frameLength = beat
            let from = Int(rate * bars) + b * Int(beat)
            for n in 0..<Int(beat) where from + n < Int(whole.frameLength) { dest[n] = source[from + n] }
            out.append(buffer)
        }
        return out
    }

    private static func glide(_ format: AVAudioFormat, seconds: Double, from f0: Double, to f1: Double, level: Double,
                              envelope: @escaping (Double) -> Double) -> AVAudioPCMBuffer? {
        var phase = 0.0
        let rate = format.sampleRate
        return make(format, seconds: seconds) { t, _ in
            let k = t / seconds
            phase += (f0 + (f1 - f0) * k) / rate
            phase -= phase.rounded(.down)
            return envelope(t) * level * (sin(2 * Double.pi * phase) + 0.2 * sin(4 * Double.pi * phase))
        }
    }

    static func cue(_ cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        switch cue {
        case .bloop:
            return glide(format, seconds: 0.18, from: 300, to: 900, level: 0.35) { t in min(1, t / 0.01) * exp(-t / 0.08) }
        case .swell:
            return glide(format, seconds: 0.12, from: 500, to: 700, level: 0.25) { t in min(1, t / 0.06) * min(1, (0.12 - t) / 0.03) }
        case .pop:
            return make(format, seconds: 0.08) { t, noise in min(1, t / 0.002) * exp(-t / 0.015) * (0.6 * white(&noise) + 0.4 * sin(2 * Double.pi * 1400 * t)) * 0.7 }
        case .boing, .boingOnBeat:
            let chime = cue == .boingOnBeat
            return make(format, seconds: 0.35) { t, _ in
                let wobble = 1 + 0.25 * sin(2 * Double.pi * 14 * t) * exp(-t / 0.12)
                var v = sin(2 * Double.pi * 150 * wobble * t) * min(1, t / 0.004) * exp(-t / 0.12) * 0.45
                if chime { v += sin(2 * Double.pi * 1568 * t) * min(1, t / 0.002) * exp(-t / 0.09) * 0.18 }
                return v
            }
        case .lock:
            return glide(format, seconds: 0.14, from: 900, to: 1800, level: 0.22) { t in min(1, t / 0.004) * min(1, (0.14 - t) / 0.04) }
        case .hotDog:
            return glide(format, seconds: 0.25, from: 140, to: 50, level: 0.8) { t in min(1, t / 0.004) * exp(-t / 0.07) }
        case .bun:
            var low = 0.0
            return make(format, seconds: 0.22) { t, noise in
                low += (white(&noise) - low) * 0.05
                return min(1, t / 0.01) * exp(-t / 0.06) * low * 2.2
            }
        case .mustard:
            var low = 0.0
            return make(format, seconds: 0.3) { t, noise in
                low += (white(&noise) - low) * (0.1 + 1.5 * t)
                return min(1, t / 0.01) * min(1, (0.3 - t) / 0.08) * low * 0.9
            }
        case .cheer:
            return make(format, seconds: 0.9) { t, _ in
                let env = min(1, t / 0.02) * min(1, (0.9 - t) / 0.3)
                let chord = [523.25, 659.25, 783.99].reduce(0.0) { $0 + sin(2 * Double.pi * $1 * t) }
                return env * chord * 0.15
            }
        case .groan:
            return glide(format, seconds: 0.7, from: 330, to: 180, level: 0.3) { t in min(1, t / 0.03) * min(1, (0.7 - t) / 0.25) }
        }
    }
}
#else
final class StadiumAudio {
    enum Cue: CaseIterable { case bloop, swell, pop, boing, boingOnBeat, lock, hotDog, bun, mustard, cheer, groan }

    var output: AudioOutput = .headphones

    func update(listener: SIMD3<Float>, facing: SIMD3<Float>, crowd: Float) {}
    func beeps(listener: SIMD3<Float>, facing: SIMD3<Float>, beeping: [(figure: Int, position: SIMD3<Float>)]) {}
    func groove(tempo bpm: Double, beat: Int64?) {}
    func cue(_ cue: Cue) {}
    func silence() {}
}
#endif
