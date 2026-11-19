import StadiumCore

public enum TextRenderer {
    public static func frame(_ s: WorldSnapshot, track: Track, cols: Int = 61, rows: Int = 25, metresPerCell: Double = 2.0) -> String {
        var grid = TextGrid(cols: cols, rows: rows)
        let cx = s.car.x.double, cz = s.car.z.double
        func cell(_ x: Double, _ z: Double) -> (Int, Int) {
            let c = TextFormat.roundToInt((x - cx) / metresPerCell) + cols / 2
            let r = rows / 2 - TextFormat.roundToInt((z - cz) / metresPerCell)
            return (r, c)
        }
        let n = track.points.count
        for i in 0..<n {
            let a = track.points[i], b = track.points[(i + 1) % n]
            let steps = max(1, Int(track.segmentLength[i].double / metresPerCell))
            for k in 0...steps {
                let x = a.x.double + (b.x.double - a.x.double) * Double(k) / Double(steps)
                let z = a.z.double + (b.z.double - a.z.double) * Double(k) / Double(steps)
                let (r, c) = cell(x, z)
                grid.put(".", row: r, col: c)
            }
        }
        for can in s.cans {
            let (r, c) = cell(can.position.x.double, can.position.z.double)
            grid.put(can.held ? "O" : (can.grounded ? "o" : "*"), row: r, col: c)
        }
        let (r, c) = cell(cx, cz)
        grid.put("W", row: r, col: c)
        return grid.text
    }

    public static func status(_ s: WorldSnapshot) -> String {
        let taut = s.cans.map { $0.taut ? "1" : "0" }.joined(separator: ",")
        let f = TextFormat.fmt
        return "t=\(s.tick) x=\(f(s.car.x.double, 1)) z=\(f(s.car.z.double, 1)) heading=\(f(TextFormat.degrees(s.car.heading), 0))deg "
            + "yaw=\(f(s.car.yawRate.double, 4)) speed=\(f(s.car.speed.double, 1)) s=\(f(s.car.progress.double, 0)) "
            + "side=\(f(s.car.side.double, 2))\(s.car.offTrack ? "!" : "") held=\(s.heldIndex) taut=[\(taut)]"
    }
}
