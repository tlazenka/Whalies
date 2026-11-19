/// Turns one resolved presentation hit into one native request. No gesture
/// recognition, projectile ownership, geometry or physics lives in this type.
public enum Whaley3DPressRouter {
    public enum Direction: Sendable, Equatable { case left, below, right }

    public enum Target: Sendable, Equatable {
        /// No entity was hit; retain the existing three-zone shooting behavior.
        case empty
        /// A visible non-bubble body. It occludes bubbles behind it, but still
        /// permits the normal zone-based shot (e.g. pressing Whaley's body).
        case body(session: String)
        /// A displayed native bubble. Only explicitly player-created bubbles
        /// are editable; foundations and legacy/unknown roles consume the press.
        case bubble(session: String, projectileID: String, canGrow: Bool)
        /// A removed/replaced entity or an otherwise unmappable hit.
        case unavailable
    }

    public enum Intent: Sendable, Equatable {
        case shoot(Direction)
        case grow(session: String, projectileID: String)
        case ignore
    }

    public static func intent(for target: Target, currentSession: String,
                              horizontalFraction: Double) -> Intent {
        guard !currentSession.isEmpty, horizontalFraction.isFinite,
              (0...1).contains(horizontalFraction) else { return .ignore }
        switch target {
        case .unavailable:
            return .ignore
        case let .bubble(session, projectileID, canGrow):
            guard session == currentSession, canGrow, !projectileID.isEmpty else {
                return .ignore
            }
            return .grow(session: session, projectileID: projectileID)
        case let .body(session):
            guard session == currentSession else { return .ignore }
        case .empty:
            break
        }
        return .shoot(horizontalFraction < 0.35 ? .left :
            (horizontalFraction > 0.65 ? .right : .below))
    }
}
