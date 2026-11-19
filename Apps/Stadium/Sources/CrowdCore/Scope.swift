import StadiumCore

public enum AimPhase: Int, Sendable, Codable {
    case none = 0
    case began = 1
    case moved = 2
    case ended = 3
    /// Cancellation ends the hold without firing.
    case cancelled = 4
}

/// Displacement is in screen points with y down; mag indexes the magnification list.
public struct AimInput: Hashable, Sendable, Codable {
    public var phase: AimPhase
    public var dx: Fixed
    public var dy: Fixed
    public var mag: Int

    public init(phase: AimPhase = .none, dx: Fixed = .zero, dy: Fixed = .zero, mag: Int = 0) {
        self.phase = phase; self.dx = dx; self.dy = dy; self.mag = mag
    }

    public static let none = AimInput()

    /// Invert fixed-point multiplication so (drag(k, s) * s).raw == k.
    public static func drag(_ k: Int64, sensitivity s: Fixed) -> Fixed {
        k >= 0 ? Fixed(raw: (k * Fixed.one.raw + s.raw - 1) / s.raw) : Fixed(raw: -((-k) * Fixed.one.raw / s.raw))
    }

    public static func move(_ kYaw: Int64, _ kPitch: Int64, sensitivity s: Fixed, mag: Int = 0) -> AimInput {
        AimInput(phase: .moved, dx: drag(kYaw, sensitivity: s), dy: drag(-kPitch, sensitivity: s), mag: mag)
    }
}

public struct AimParameters: Hashable, Sendable, Codable {
    public var magnifications: [Int]
    /// Raw turn units per screen point, indexed by magnification.
    public var sensitivity: [Fixed]
    public var pitchLimit: Fixed
    public init(magnifications: [Int], sensitivity: [Fixed], pitchLimit: Fixed) {
        self.magnifications = magnifications; self.sensitivity = sensitivity; self.pitchLimit = pitchLimit
    }
}

public struct Scope: Hashable, Sendable, Codable {
    /// Yaw and pitch are turns: zero yaw faces +z, positive yaw turns right, positive pitch looks up.
    public var yaw: Fixed
    public var pitch: Fixed
    public var holding: Bool = false
    public var mag: Int = 0

    public init(yaw: Fixed = .zero, pitch: Fixed = .zero) { self.yaw = yaw; self.pitch = pitch }

    /// Returns true only on the tick that fires.
    public mutating func step(aim p: AimParameters, input: AimInput) -> Bool {
        mag = min(max(input.mag, 0), p.magnifications.count - 1)
        var fire = false
        switch input.phase {
        case .began:
            holding = true
        case .moved:
            if holding {
                let s = p.sensitivity[mag]
                yaw = Fixed(raw: Trig.normalize((yaw + input.dx * s).raw))
                pitch = (pitch - input.dy * s).clamped(-p.pitchLimit, p.pitchLimit)
            }
        case .ended:
            if holding { fire = true }
            holding = false
        case .cancelled:
            holding = false
        case .none:
            break
        }
        return fire
    }

    public var direction: Vec3 { Trig.direction(yaw: yaw, pitch: pitch) }
}
