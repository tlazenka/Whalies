import StadiumCore

public enum ThoughtSymbol: Int, Hashable, Sendable, Codable, CaseIterable {
    case hotDog = 0
    case baseball = 1
    case music = 2
    case star = 3

    public var requiresHotDog: Bool { self == .hotDog }

    /// Use one RNG draw per thought so cosmetic variation cannot change replay randomness.
    public static func draw(using rng: inout Rng, variation: Int) -> ThoughtSymbol {
        guard rng.below(2) == 1 else { return .hotDog }
        let others: [ThoughtSymbol] = [.baseball, .music, .star]
        let index = (variation % others.count + others.count) % others.count
        return others[index]
    }

    public var label: String {
        switch self {
        case .hotDog: "hot dog"
        case .baseball: "baseball"
        case .music: "music"
        case .star: "star"
        }
    }
}

public enum ThoughtPhase: Int, Hashable, Sendable, Codable {
    case spinning = 0
    case requesting = 1
    case watching = 2
}

/// A stopped reel has identical symbols and zero progress.
public struct ThoughtFrame: Hashable, Sendable {
    public let symbol: ThoughtSymbol
    public let nextSymbol: ThoughtSymbol
    public let progress: Double
    public let isSpinning: Bool
}

/// The reel spins before start; the final symbol remains visible until end.
public struct FanThought: Hashable, Sendable, Codable {
    /// Repeat hot dogs to match the 50/50 request probability.
    private static let reel: [ThoughtSymbol] = [.hotDog, .baseball, .hotDog, .music, .hotDog, .star]

    public var figure: Int
    public var start: Int
    public var end: Int
    public var spinTicks: Int
    public var symbol: ThoughtSymbol

    public init(figure: Int, start: Int, end: Int, spinTicks: Int, symbol: ThoughtSymbol = .hotDog) {
        self.figure = figure
        self.start = start
        self.end = end
        self.spinTicks = max(0, spinTicks)
        self.symbol = symbol
    }

    public func phase(at tick: Int) -> ThoughtPhase? {
        guard tick < end else { return nil }
        if start - spinTicks <= tick && tick < start { return .spinning }
        if start <= tick && tick < end { return symbol.requiresHotDog ? .requesting : .watching }
        return nil
    }

    public func frame(at tick: Int) -> ThoughtFrame? {
        guard let phase = phase(at: tick) else { return nil }
        guard phase == .spinning else {
            return ThoughtFrame(symbol: symbol, nextSymbol: symbol, progress: 0, isSpinning: false)
        }
        let remaining = start - tick
        // Count backward from the reveal so every lead duration lands on the final symbol.
        let finalDurations = [24, 18, 12, 9]
        var boundary = 0
        var transitions = 0
        var duration = 6
        while boundary < remaining {
            duration = transitions < finalDurations.count ? finalDurations[transitions] : 6
            boundary += duration
            transitions += 1
        }
        let landing: Int
        switch symbol {
        // Vary the stop without consuming another random draw.
        case .hotDog: landing = 2 * ((figure % 3 + 3) % 3)
        case .baseball: landing = 1
        case .music: landing = 3
        case .star: landing = 5
        }
        let count = Self.reel.count
        let index = ((landing - transitions) % count + count) % count
        let current = Self.reel[index]
        let next = Self.reel[(index + 1) % count]
        let progress = Double(boundary - remaining) / Double(duration)
        return ThoughtFrame(symbol: current, nextSymbol: next, progress: progress, isSpinning: true)
    }

    public func isCalledOff(at tick: Int, for duration: Int) -> Bool {
        start - spinTicks < tick + duration && tick < end
    }
}
