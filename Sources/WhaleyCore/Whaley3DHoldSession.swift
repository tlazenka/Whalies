/// Arbitrates one native shot attempt per physical press. This value owns no
/// projectile and does not recognize gestures or advance gameplay. Keep it on
/// the same executor as the input bridge (the main actor in the app).
public struct Whaley3DHoldSession: Sendable, Equatable {
    private struct Clock: Sendable, Equatable {
        let session: String
        let beganAt: Double
        var lastSample: Double
    }

    private enum State: Sendable, Equatable {
        case idle
        case holding(Clock)
        case waitingForRelease
    }

    private var state: State = .idle

    public init() {}

    public var acceptsNewPress: Bool {
        if case .idle = state { return true }
        return false
    }

    public var isHolding: Bool {
        if case .holding = state { return true }
        return false
    }

    /// Consumes this press even when its initial capture is invalid. The caller
    /// may attempt a native shot only after true, and must cancel on rejection.
    @discardableResult
    public mutating func begin(session: String, simulationTime: Double) -> Bool {
        guard acceptsNewPress else { return false }
        state = .waitingForRelease
        guard !session.isEmpty, simulationTime.isFinite, simulationTime >= 0 else { return false }
        state = .holding(Clock(session: session, beganAt: simulationTime, lastSample: simulationTime))
        return true
    }

    /// Elapsed *simulation* time, not wall time. Repeated paused samples do not
    /// add growth. A new scene, a rewind, or a bad capture invalidates the hold
    /// before the caller is allowed to issue another native growth update.
    public mutating func elapsed(session: String, simulationTime: Double,
                                 canContinue: Bool = true) -> Double? {
        guard case .holding(var clock) = state else { return nil }
        guard canContinue, session == clock.session,
              simulationTime.isFinite, simulationTime >= clock.lastSample else {
            cancel()
            return nil
        }
        let duration = simulationTime - clock.beganAt
        guard duration.isFinite, duration >= 0 else {
            cancel()
            return nil
        }
        clock.lastSample = simulationTime
        state = .holding(clock)
        return duration
    }

    /// An interruption is NOT a new press. Further movement of the same finger
    /// cannot respawn a shot, even after a scene retry or application resume.
    public mutating func cancel() {
        if !acceptsNewPress { state = .waitingForRelease }
    }

    /// Called on physical release or gesture reset, and on view teardown.
    public mutating func release() {
        state = .idle
    }
}
