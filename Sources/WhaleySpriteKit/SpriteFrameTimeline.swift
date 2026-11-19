/// Frame selection shared by the production SpriteKit action and portable tests.
/// Zero duration installs the final frame without inventing a minimum interval.
struct SpriteFrameTimeline: Sendable {
    let count: Int
    let interval: Double
    let duration: Double

    init?(count: Int, interval: Double) {
        let duration = Double(count) * interval
        guard count > 0, interval.isFinite, interval >= 0, duration.isFinite else { return nil }
        self.count = count
        self.interval = interval
        self.duration = duration
    }

    func index(at elapsed: Double) -> Int {
        if duration == 0 { return count - 1 }
        if elapsed.isNaN || elapsed <= 0 { return 0 }
        if elapsed >= duration { return count - 1 }
        // Recover the representational boundary in values such as 0.3 / 0.1.
        let position = (elapsed / interval).nextUp
        return position >= Double(count - 1) ? count - 1 : Int(position)
    }
}
