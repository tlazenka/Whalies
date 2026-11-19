@main
struct FrameTimelineChecks {
    static func main() {
        let t = SpriteFrameTimeline(count: 4, interval: 0.1)!
        precondition(t.duration == 0.4)
        for (time, expected) in [(0.0,0),(0.099,0),(0.1,1),(0.199,1),(0.2,2),
                                  (0.299,2),(0.3,3),(0.399,3),(0.4,3),(9.0,3)] {
            precondition(t.index(at: time) == expected, "frame at \(time)")
        }
        precondition(t.index(at: -.infinity) == 0)
        precondition(t.index(at: .nan) == 0)
        precondition(t.index(at: .infinity) == 3)
        // Reuse/repetition restarts from elapsed zero, not retained state.
        precondition(t.index(at: 0) == 0)
        precondition(SpriteFrameTimeline(count: 0, interval: 0.1) == nil)
        precondition(SpriteFrameTimeline(count: -1, interval: 0.1) == nil)
        precondition(SpriteFrameTimeline(count: 1, interval: -1) == nil)
        precondition(SpriteFrameTimeline(count: 1, interval: .nan) == nil)
        precondition(SpriteFrameTimeline(count: 1, interval: .infinity) == nil)
        precondition(SpriteFrameTimeline(count: 4, interval: .greatestFiniteMagnitude) == nil)
        precondition(SpriteFrameTimeline(count: 4, interval: 0)!.index(at: 0) == 3)
        precondition(SpriteFrameTimeline(count: 1, interval: 0.1)!.index(at: 0.5) == 0)
        print("PASS: production frame timeline boundaries, repeats, zero duration and invalid input.")
    }
}
