public struct TextGrid {
    public let cols: Int
    public let rows: Int
    public private(set) var cells: [[Character]]

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
    }

    public mutating func put(_ c: Character, row: Int, col: Int) {
        guard (0..<rows).contains(row), (0..<cols).contains(col) else { return }
        cells[row][col] = c
    }

    public var text: String { cells.map { String($0) }.joined(separator: "\n") }
}

public enum TextFormat {
    /// Formats 60 Hz ticks as mm:ss.cc.
    public static func clock(_ tick: Int) -> String {
        let centiseconds = max(0, tick) * 100 / 60
        let minutes = centiseconds / 6000
        let seconds = (centiseconds / 100) % 60
        let hundredths = centiseconds % 100
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(two(minutes)):\(two(seconds)).\(two(hundredths))"
    }

    public static func fmt(_ value: Double, _ places: Int) -> String {
        var scale = 1.0
        for _ in 0..<places { scale *= 10 }
        let scaled = Int64((value * scale).rounded())
        let sign = scaled < 0 ? "-" : (value > 0 ? "+" : "")
        let magnitude = abs(scaled)
        let whole = magnitude / Int64(scale)
        var frac = String(magnitude % Int64(scale))
        while frac.count < places { frac = "0" + frac }
        return places == 0 ? "\(sign)\(whole)" : "\(sign)\(whole).\(frac)"
    }

    /// Rounding here affects text placement only, never replay state.
    public static func roundToInt(_ value: Double) -> Int { Int(value.rounded()) }

    public static func degrees(_ turns: Fixed) -> Double { turns.double * 360.0 }
}
