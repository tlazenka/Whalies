import StadiumCore
import WhaleKartCore
import CrowdCore

func degrees(_ d: Double) -> Fixed { Fixed(d / 360.0) }

public struct ViewParameters: Hashable, Sendable, Codable {
    public var behind: Fixed
    public var up: Fixed
    public var tanHalfV: Fixed
    public var yawOffset: Fixed
    public var pitchBelow: Fixed
    public var pitchMin: Fixed
    public var pitchMax: Fixed
    public var zoomMarginX: Fixed
    public var zoomMarginY: Fixed
    public var zoomMax: Fixed
    public var zoomEase: Fixed
    public var zoomSnap: Fixed
    public init(behind: Fixed, up: Fixed, tanHalfV: Fixed, yawOffset: Fixed, pitchBelow: Fixed, pitchMin: Fixed, pitchMax: Fixed, zoomMarginX: Fixed,
                zoomMarginY: Fixed, zoomMax: Fixed, zoomEase: Fixed, zoomSnap: Fixed) {
        self.behind = behind; self.up = up; self.tanHalfV = tanHalfV; self.yawOffset = yawOffset; self.pitchBelow = pitchBelow
        self.pitchMin = pitchMin; self.pitchMax = pitchMax; self.zoomMarginX = zoomMarginX; self.zoomMarginY = zoomMarginY; self.zoomMax = zoomMax
        self.zoomEase = zoomEase; self.zoomSnap = zoomSnap
    }
}

public struct BullpenCartParameters: Hashable, Sendable, Codable {
    public var wheelBack: Fixed
    public var wheelFront: Fixed
    public var wheelSide: Fixed
    public var wheelHeight: Fixed
    public var wheelRadius: Fixed
    public var pipeBack: Fixed
    public var pipeSide: Fixed
    public var pipeHeight: Fixed
    public init(wheelBack: Fixed, wheelFront: Fixed, wheelSide: Fixed, wheelHeight: Fixed, wheelRadius: Fixed, pipeBack: Fixed, pipeSide: Fixed,
                pipeHeight: Fixed) {
        self.wheelBack = wheelBack; self.wheelFront = wheelFront; self.wheelSide = wheelSide; self.wheelHeight = wheelHeight
        self.wheelRadius = wheelRadius; self.pipeBack = pipeBack; self.pipeSide = pipeSide; self.pipeHeight = pipeHeight
    }
}

/// Keep bubble dimensions and action timing aligned with WhaleyScene.m and Projectile.m.
public struct BubbleParameters: Hashable, Sendable, Codable {
    public var image: Fixed
    public var smallScale: Fixed
    public var normalScale: Fixed
    public var actionTicks: Int
    public var touchFudge: Int
    public var uses: Int
    public var maxBubbles: Int
    public init(image: Fixed, smallScale: Fixed, normalScale: Fixed, actionTicks: Int, touchFudge: Int, uses: Int, maxBubbles: Int) {
        self.image = image; self.smallScale = smallScale; self.normalScale = normalScale; self.actionTicks = actionTicks
        self.touchFudge = touchFudge; self.uses = uses; self.maxBubbles = maxBubbles
    }
    public var small: Fixed { image * smallScale }
}

public struct HopParameters: Hashable, Sendable, Codable {
    public var ticks: Int
    public var rise: Fixed
    public var fall: Fixed
    public init(ticks: Int, rise: Fixed, fall: Fixed) { self.ticks = ticks; self.rise = rise; self.fall = fall }
}

public struct BeatParameters: Hashable, Sendable, Codable {
    public var slowBPM: Fixed
    public var fastBPM: Fixed
    public var window: Fixed
    public var basePoints: Int
    public var streakCap: Int
    public init(slowBPM: Fixed, fastBPM: Fixed, window: Fixed, basePoints: Int, streakCap: Int) {
        self.slowBPM = slowBPM; self.fastBPM = fastBPM; self.window = window; self.basePoints = basePoints; self.streakCap = streakCap
    }
}

/// lead is reel duration, fit is settled-picture duration, and leniency is the response window.
public struct AlarmParameters: Hashable, Sendable, Codable {
    public var firstLo: Int
    public var firstHi: Int
    public var gapLo: Int
    public var gapHi: Int
    public var lead: Int
    public var fit: Int
    public var leniency: Int
    public var flashTicks: Int
    public var maxDepth: Fixed
    public var bandLeft: Fixed
    public var bandRight: Fixed
    public var bandTop: Fixed
    public var bandBottom: Fixed
    public var clearHeight: Fixed
    public var clearMargin: Fixed
    public var lockRadius: Fixed
    public var itemRadius: Fixed
    public var resultShown: Int
    public init(firstLo: Int, firstHi: Int, gapLo: Int, gapHi: Int, lead: Int, fit: Int, leniency: Int, flashTicks: Int, maxDepth: Fixed,
                bandLeft: Fixed, bandRight: Fixed, bandTop: Fixed, bandBottom: Fixed, clearHeight: Fixed, clearMargin: Fixed, lockRadius: Fixed,
                itemRadius: Fixed, resultShown: Int) {
        self.firstLo = firstLo; self.firstHi = firstHi; self.gapLo = gapLo; self.gapHi = gapHi; self.lead = lead; self.fit = fit
        self.leniency = leniency; self.flashTicks = flashTicks; self.maxDepth = maxDepth; self.bandLeft = bandLeft; self.bandRight = bandRight
        self.bandTop = bandTop; self.bandBottom = bandBottom; self.clearHeight = clearHeight; self.clearMargin = clearMargin
        self.lockRadius = lockRadius; self.itemRadius = itemRadius; self.resultShown = resultShown
    }
}

public struct GardenParameters: Hashable, Sendable, Codable {
    public var firstSeat: Int
    public var seats: Int
    public var oneIn: Int
    public init(firstSeat: Int, seats: Int, oneIn: Int) { self.firstSeat = firstSeat; self.seats = seats; self.oneIn = oneIn }

    public func contains(figure i: Int, seatsARow: Int) -> Bool {
        let seat = i % seatsARow
        return firstSeat <= seat && seat < firstSeat + seats
    }
}

/// Stretches are [start, end] arc lengths in metres; endpoints may extend past a lap.
public struct RepeatParameters: Hashable, Sendable, Codable {
    public var cannon: [Fixed]
    public var pitcher: [Fixed]
    public var whaley: [Fixed]
    public var spots: RepeatSpots
    public var turnYaw: Fixed
    public var turnSpeed: Fixed
    public init(cannon: [Fixed], pitcher: [Fixed], whaley: [Fixed], spots: RepeatSpots, turnYaw: Fixed, turnSpeed: Fixed) {
        self.cannon = cannon; self.pitcher = pitcher; self.whaley = whaley; self.spots = spots; self.turnYaw = turnYaw; self.turnSpeed = turnSpeed
    }

    public func stretch(_ state: RepeatState) -> (lo: Fixed, hi: Fixed)? {
        switch state {
        case .off: nil
        case .cannon: (cannon[0], cannon[1])
        case .whaley: (whaley[0], whaley[1])
        case .pitcher: (pitcher[0], pitcher[1])
        case .interlude: nil
        }
    }

    public func spot(_ state: RepeatState) -> Fixed? {
        switch state {
        case .off: nil
        case .cannon: spots.cannon
        case .whaley: spots.whaley
        case .pitcher: spots.pitcher
        case .interlude: spots.interlude
        }
    }
}

/// Parking positions are arc lengths in metres from the start of the ring.
public struct RepeatSpots: Hashable, Sendable, Codable {
    public var cannon: Fixed
    public var pitcher: Fixed
    public var whaley: Fixed
    public var interlude: Fixed
    public init(cannon: Fixed, pitcher: Fixed, whaley: Fixed, interlude: Fixed) {
        self.cannon = cannon; self.pitcher = pitcher; self.whaley = whaley; self.interlude = interlude
    }
}

public enum RepeatState: Int, Hashable, Sendable, Codable, CaseIterable {
    case off = 0
    case cannon = 1
    case whaley = 2
    case pitcher = 3
    case interlude = 4

    public var name: String {
        switch self {
        case .off: "normal"
        case .cannon: "cannon"
        case .whaley: "whaley"
        case .pitcher: "pitcher"
        case .interlude: "interlude"
        }
    }

    public var next: RepeatState {
        switch self {
        case .off: .cannon
        case .cannon: .whaley
        case .whaley: .pitcher
        case .pitcher: .interlude
        case .interlude: .off
        }
    }
}

/// The normal interlude begins after the first lap, once play is quiet, and waits for Done; debug mode repeats it.
public struct InterludeParameters: Hashable, Sendable, Codable {
    public var at: Fixed
    public var turnTicks: Int
    public var holdTicks: Int
    public var gapTicks: Int
    public var headRadius: Fixed
    public var headAt: Fixed
    public init(at: Fixed, turnTicks: Int, holdTicks: Int, gapTicks: Int, headRadius: Fixed, headAt: Fixed) {
        self.at = at; self.turnTicks = turnTicks; self.holdTicks = holdTicks; self.gapTicks = gapTicks
        self.headRadius = headRadius; self.headAt = headAt
    }

    public static let stadium = InterludeParameters(at: Fixed(354.0), turnTicks: 90, holdTicks: 60, gapTicks: 120,
                                                    headRadius: Fixed(40.0), headAt: Fixed(0.3))
}

public struct RideParameters: Hashable, Sendable, Codable {
    /// Metres per second.
    public var cruiseSpeed: Fixed
    public var ringRadius: Fixed
    public var railHalf: Fixed
    /// A fraction of the kart yawMax.
    public var steer: Fixed
    public var view: ViewParameters
    public var bullpenCart: BullpenCartParameters
    public var bubbles: BubbleParameters
    public var hop: HopParameters
    public var beat: BeatParameters
    public var alarm: AlarmParameters
    public var garden: GardenParameters
    public var pitcher: PitcherParameters
    public var whaley: WhaleyParameters
    public var `repeat`: RepeatParameters
    public var interlude: InterludeParameters

    public init(cruiseSpeed: Fixed, ringRadius: Fixed, railHalf: Fixed, steer: Fixed, view: ViewParameters, bullpenCart: BullpenCartParameters,
                bubbles: BubbleParameters, hop: HopParameters, beat: BeatParameters, alarm: AlarmParameters, garden: GardenParameters,
                pitcher: PitcherParameters, whaley: WhaleyParameters, repeat: RepeatParameters, interlude: InterludeParameters) {
        self.cruiseSpeed = cruiseSpeed; self.ringRadius = ringRadius; self.railHalf = railHalf; self.steer = steer; self.view = view
        self.bullpenCart = bullpenCart; self.bubbles = bubbles; self.hop = hop; self.beat = beat; self.alarm = alarm; self.garden = garden
        self.pitcher = pitcher; self.whaley = whaley; self.repeat = `repeat`; self.interlude = interlude
    }

    public static let stadium = RideParameters(
        cruiseSpeed: Fixed(6.0),
        ringRadius: Fixed(50.0),
        railHalf: Fixed(4.4),
        steer: .one,
        view: ViewParameters(behind: Fixed(9.0), up: Fixed(3.2), tanHalfV: Fixed(0.57735), yawOffset: degrees(10), pitchBelow: degrees(18),
                             pitchMin: degrees(-12), pitchMax: degrees(12), zoomMarginX: Fixed(0.1), zoomMarginY: Fixed(0.1), zoomMax: Fixed(2.5),
                             zoomEase: Fixed(0.125), zoomSnap: Fixed(1.0 / 256.0)),
        bullpenCart: BullpenCartParameters(wheelBack: Fixed(1.1), wheelFront: Fixed(1.1), wheelSide: Fixed(0.78), wheelHeight: Fixed(0.34),
                                 wheelRadius: Fixed(0.34), pipeBack: Fixed(1.45), pipeSide: Fixed(0.4), pipeHeight: Fixed(0.32)),
        bubbles: BubbleParameters(image: Fixed(128.0), smallScale: Fixed(raw: 22528), normalScale: .one, actionTicks: 6, touchFudge: 5, uses: 2,
                                  maxBubbles: 500),
        hop: HopParameters(ticks: 20, rise: Fixed(1.0 / 30.0), fall: Fixed(1.0 / 120.0)),
        beat: BeatParameters(slowBPM: Fixed(76.0), fastBPM: Fixed(104.0), window: Fixed(0.15), basePoints: 10, streakCap: 8),
        alarm: AlarmParameters(firstLo: 480, firstHi: 720, gapLo: 360, gapHi: 600, lead: 300, fit: 60, leniency: 60, flashTicks: 15,
                               maxDepth: Fixed(110.0), bandLeft: Fixed(0.08), bandRight: Fixed(0.92), bandTop: Fixed(0.12), bandBottom: Fixed(0.62),
                               clearHeight: Fixed(2.8), clearMargin: Fixed(20.0), lockRadius: Fixed(12.0), itemRadius: Fixed(0.15), resultShown: 240),
        garden: GardenParameters(firstSeat: 20, seats: 5, oneIn: 3),
        pitcher: .stadium,
        whaley: .stadium,
        repeat: RepeatParameters(cannon: [Fixed(-3.0), Fixed(236.0)], pitcher: [Fixed(282.0), Fixed(310.0)], whaley: [Fixed(312.0), Fixed(351.0)],
                                 spots: RepeatSpots(cannon: Fixed(42.0), pitcher: Fixed(298.0), whaley: Fixed(30.0), interlude: Fixed(40.0)),
                                 turnYaw: Fixed(0.5), turnSpeed: Fixed(3.0)),
        interlude: .stadium
    )
}

/// Screen points with y down; encodes as [x, y, width, height].
public struct PictureRect: Hashable, Sendable, Codable {
    public var x: Fixed
    public var y: Fixed
    public var w: Fixed
    public var h: Fixed
    public init(x: Fixed, y: Fixed, w: Fixed, h: Fixed) { self.x = x; self.y = y; self.w = w; self.h = h }

    public var midX: Fixed { x + Fixed(raw: w.raw >> 1) }
    public var midY: Fixed { y + Fixed(raw: h.raw >> 1) }
    public var maxX: Fixed { x + w }
    public var maxY: Fixed { y + h }
    public func contains(x px: Fixed, y py: Fixed) -> Bool { x <= px && px < x + w && y <= py && py < y + h }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Fixed.self); y = try c.decode(Fixed.self); w = try c.decode(Fixed.self); h = try c.decode(Fixed.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x); try c.encode(y); try c.encode(w); try c.encode(h)
    }
}

public struct PicturePoint: Hashable, Sendable, Codable {
    public var x: Fixed
    public var y: Fixed
    public init(x: Fixed, y: Fixed) { self.x = x; self.y = y }

    public static let far = Fixed(16384.0)

    /// Far-off projections can overflow when squared. Beyond far, use the larger
    /// offset; callers only need to know the point is outside screen-sized bounds.
    public func distance(to q: PicturePoint) -> Fixed {
        let dx = q.x - x, dy = q.y - y
        let far = max(dx.magnitude, dy.magnitude)
        if far >= PicturePoint.far { return far }
        return Fixed.sqrt(dx * dx + dy * dy)
    }
}

public enum HitBox {
    /// Match legacy Helpers.m: inset the far rectangle edges by one point.
    public static func rectIntersectsCircle(_ r: PictureRect, x cx: Fixed, y cy: Fixed, diameter: Fixed, radiusOffset: Int, widthOffset: Int,
                                            heightOffset: Int) -> Bool {
        let radius = Fixed(raw: diameter.raw >> 1) + Fixed(raw: Int64(radiusOffset) << 16)
        let wo = Fixed(raw: Int64(widthOffset) << 16), ho = Fixed(raw: Int64(heightOffset) << 16)
        let closestX = cx.clamped(r.x - wo, r.x + r.w + wo - .one)
        let closestY = cy.clamped(r.y - ho, r.y + r.h + ho - .one)
        let dx = cx - closestX, dy = cy - closestY
        // Reject distant points before squaring can overflow Int64.
        if dx.magnitude >= radius.magnitude || dy.magnitude >= radius.magnitude { return false }
        return dx * dx + dy * dy < radius * radius
    }
}

/// Use the same pinhole projection for rendering and hit testing.
/// zoom > 1 widens the view; zoom < 1 narrows it.
public struct TurretCamera: Hashable, Sendable {
    public let turret: Fixed
    public let eye: Vec3
    public let target: Vec3
    public let basis: CameraBasis
    public let halfWidth: Fixed
    public let halfHeight: Fixed
    /// tanHalf is the zoomed half-field tangent; focal is screen points per unit tangent.
    public let tanHalf: Fixed
    public let focal: Fixed
    public let yaw: Fixed
    public let pitch: Fixed

    public init(x: Fixed, z: Fixed, parameters p: StadiumParameters, zoom: Fixed = .one, onHim: Fixed = .zero, jumbo: JumboAim? = nil) {
        let v = p.ride.view, pz = p.ride.pitcher, j = p.jumbotron
        turret = Trig.bearing(dx: j.x - x, dz: j.z - z)
        var yaw = Fixed(raw: Trig.normalize(turret.raw + v.yawOffset.raw))
        let f = Trig.forward(yaw)
        let behind = v.behind + (pz.onHimBehind - v.behind) * onHim
        let up = v.up + (pz.onHimUp - v.up) * onHim
        eye = Vec3(x - f.x * behind, up, z - f.z * behind)
        let d = j - eye
        var pitch = (Trig.elevation(dy: d.y, horizontal: Fixed.sqrt(d.x * d.x + d.z * d.z)) - v.pitchBelow).clamped(v.pitchMin, v.pitchMax)
        var zoom = zoom
        if let a = jumbo {
            yaw = Fixed(raw: Trig.normalize(yaw.raw + (turnBetween(yaw, a.yaw) * a.share).raw))
            pitch = pitch + (a.pitch - pitch) * a.share
            zoom = zoom + (a.zoom - zoom) * a.share
        }
        self.yaw = yaw
        self.pitch = pitch
        target = eye + Trig.direction(yaw: yaw, pitch: pitch).scaled(by: Fixed(10.0))
        basis = Camera(eye: eye, tanHalfH: v.tanHalfV, tanHalfV: v.tanHalfV, range: .one).basis(lookingAt: target)
        halfWidth = Fixed(raw: p.picture.width.raw >> 1)
        halfHeight = Fixed(raw: p.picture.height.raw >> 1)
        tanHalf = v.tanHalfV * zoom
        focal = halfHeight / tanHalf
    }

    public init(car: Car, parameters p: StadiumParameters, zoom: Fixed = .one, onHim: Fixed = .zero, jumbo: JumboAim? = nil) {
        self.init(x: car.x, z: car.z, parameters: p, zoom: zoom, onHim: onHim, jumbo: jumbo)
    }

    /// The flick compass projects camera directions onto the ground plane.
    public var compass: (rightX: Fixed, rightZ: Fixed, forwardX: Fixed, forwardZ: Fixed) {
        let f = basis.forward
        let fl = Fixed.sqrt(f.x * f.x + f.z * f.z)
        return (basis.right.x, basis.right.z, f.x / fl, f.z / fl)
    }

    /// Reject points less than one metre in front of the camera plane.
    public func project(_ p: Vec3) -> (x: Fixed, y: Fixed, depth: Fixed)? {
        let v = p - eye
        let fc = v.dot(basis.forward)
        guard Fixed.one <= fc else { return nil }
        return (halfWidth + (v.dot(basis.right) * focal) / fc, halfHeight - (v.dot(basis.up) * focal) / fc, fc)
    }

    public func point(_ p: Vec3) -> PicturePoint? { project(p).map { PicturePoint(x: $0.x, y: $0.y) } }

    public func rect(centre: Vec3, radius: Fixed) -> PictureRect? {
        guard let q = project(centre) else { return nil }
        let r = (radius * focal) / q.depth
        return PictureRect(x: q.x - r, y: q.y - r, w: r + r, h: r + r)
    }

    public func ray(x: Fixed, y: Fixed) -> Vec3 {
        let d = basis.forward + basis.right.scaled(by: (x - halfWidth) / focal) + basis.up.scaled(by: (halfHeight - y) / focal)
        let length = Fixed.sqrt(d.dot(d))
        return Vec3(d.x / length, d.y / length, d.z / length)
    }
}

public enum Wheel: Int, Hashable, Sendable, Codable, CaseIterable {
    case rearLeft = 0, rearRight = 1, frontLeft = 2, frontRight = 3

    /// A left wheel bounce steers right; a right wheel bounce steers left.
    public var steer: Int { self == .rearLeft || self == .frontLeft ? 1 : -1 }
    public var isLeft: Bool { steer > 0 }
}

public func kartPoint(_ car: Car, right dx: Fixed, forward dz: Fixed, up h: Fixed) -> Vec3 {
    let f = Trig.forward(car.heading), r = Trig.right(car.heading)
    return Vec3(car.x + r.x * dx + f.x * dz, h, car.z + r.z * dx + f.z * dz)
}

/// Return the shortest signed turn, within half a turn either way.
func turnBetween(_ a: Fixed, _ b: Fixed) -> Fixed {
    let d = Trig.normalize(b.raw - a.raw)
    return Fixed(raw: d > Trig.turn / 2 ? d - Trig.turn : d)
}

/// Smoothstep has zero slope at both ends, keeping camera transitions continuous.
public func ease(_ k: Int, of n: Int) -> Fixed {
    let t = Fixed(raw: (Int64(k) << 16) / Int64(n))
    return (t * t) * Fixed(raw: 3 * Fixed.one.raw - 2 * t.raw)
}

public struct JumboAim: Hashable, Sendable {
    public var share: Fixed
    public var yaw: Fixed
    public var pitch: Fixed
    public var zoom: Fixed
    public init(share: Fixed, yaw: Fixed, pitch: Fixed, zoom: Fixed) { self.share = share; self.yaw = yaw; self.pitch = pitch; self.zoom = zoom }
}

/// k counts zoom ticks; out reverses the same transition.
public struct JumboZoom: Hashable, Sendable {
    public var bubble: Int
    public var k: Int
    public var out: Bool
    public var yaw: Fixed
    public var pitch: Fixed
    public var zoom: Fixed

    public func aim(ticks: Int) -> JumboAim { JumboAim(share: ease(k, of: ticks), yaw: yaw, pitch: pitch, zoom: zoom) }
    public func isIn(ticks: Int) -> Bool { !out && k >= ticks }
}

public struct JumboSnapshot: Hashable, Sendable {
    public var zoom: JumboZoom?
    public var on: Bool
    public var ever: Bool
    public init(zoom: JumboZoom? = nil, on: Bool = false, ever: Bool = false) { self.zoom = zoom; self.on = on; self.ever = ever }
}

/// Wheel rectangles follow Wheel raw-value order; pipe points are left, then right.
public struct BullpenCartOnPicture: Hashable, Sendable {
    public let wheels: [PictureRect?]
    public let pipes: [PicturePoint?]

    public init(camera cam: TurretCamera, car: Car, bullpenCart h: BullpenCartParameters) {
        var wheels: [PictureRect?] = []
        for dz in [-h.wheelBack, h.wheelFront] {
            for dx in [-h.wheelSide, h.wheelSide] {
                wheels.append(cam.rect(centre: kartPoint(car, right: dx, forward: dz, up: h.wheelHeight), radius: h.wheelRadius))
            }
        }
        self.wheels = wheels
        pipes = [-h.pipeSide, h.pipeSide].map { dx in cam.point(kartPoint(car, right: dx, forward: -h.pipeBack, up: h.pipeHeight)) }
    }

    public static let none = BullpenCartOnPicture()
    private init() { wheels = [nil, nil, nil, nil]; pipes = [nil, nil] }
}

public enum TouchPhase: Int, Hashable, Sendable, Codable {
    case none = 0
    case began = 1
    case moved = 2
    case ended = 3
    case cancelled = 4
}

/// Screen points with y down.
public struct FingerInput: Hashable, Sendable, Codable {
    public var phase: TouchPhase
    public var x: Fixed
    public var y: Fixed
    public init(phase: TouchPhase = .none, x: Fixed = .zero, y: Fixed = .zero) { self.phase = phase; self.x = x; self.y = y }
    public static let none = FingerInput()
}

public enum BubbleCallback: Int, Hashable, Sendable, Codable {
    case moveDone = 0
    case enlargeOrRemove = 1
}

public enum BubbleAction: Hashable, Sendable, Codable {
    case scale(to: Fixed, from: Fixed?, step: Int)
    case move(toX: Fixed, toY: Fixed, fromX: Fixed?, fromY: Fixed?, step: Int)
    case callback(BubbleCallback)
}

public struct Bubble: Hashable, Sendable, Codable {
    public var id: Int
    public var x: Fixed
    public var y: Fixed
    public var scale: Fixed
    public var isFrozen: Bool
    public var isBeingMoved: Bool
    public var usesLeft: Int
    public var offsetX = Fixed.zero
    public var offsetY = Fixed.zero
    /// Tracks run in insertion order; later tracks win when writing the same property.
    public var tracks: [[BubbleAction]] = []

    public init(id: Int, x: Fixed, y: Fixed, scale: Fixed, isFrozen: Bool, isBeingMoved: Bool, usesLeft: Int) {
        self.id = id; self.x = x; self.y = y; self.scale = scale; self.isFrozen = isFrozen; self.isBeingMoved = isBeingMoved; self.usesLeft = usesLeft
    }

    public func size(_ p: BubbleParameters) -> Fixed { p.image * scale }

    public enum Tint: Int, Hashable, Sendable, Codable { case purple, red }
    public var tint: Tint { usesLeft == 1 ? .red : .purple }
}

public enum Item: Int, Hashable, Sendable, Codable, CaseIterable {
    case hotDog = 0
    case bun = 1
    case mustard = 2

    public var name: String {
        switch self {
        case .hotDog: "hot dog"
        case .bun: "bun"
        case .mustard: "mustard"
        }
    }
}

public enum ShotResult: Int, Hashable, Sendable, Codable, CaseIterable {
    case served = 0
    case tooSoon = 1
    case unwanted = 2
    case wrongItem = 3
    case wrongFan = 4
    case miss = 5
    case missedRequest = 6
    case heldFire = 7

    public var headline: String {
        switch self {
        case .served: "HOT DOG SERVED!"
        case .tooSoon: "WAIT FOR THE REEL"
        case .unwanted: "NO HOT DOG WANTED"
        case .wrongItem: "HOT DOG NEEDED"
        case .wrongFan: "WRONG FAN"
        case .miss: "MISSED"
        case .missedRequest: "HOT DOG MISSED"
        case .heldFire: "GOOD CALL! HELD FIRE"
        }
    }

    public var success: Bool { self == .served || self == .heldFire }

    /// Judge only the settled symbol; non-hot-dog symbols require holding fire.
    public static func judge(hit: Int?, figure: Int, symbol: ThoughtSymbol, item: Item, revealed: Bool) -> ShotResult {
        guard let hit else { return .miss }
        guard hit == figure else { return .wrongFan }
        guard revealed else { return .tooSoon }
        guard symbol.requiresHotDog else { return .unwanted }
        return item == .hotDog ? .served : .wrongItem
    }
}

/// start is the reveal tick; end is the exclusive end of the response window.
public struct Incident: Hashable, Sendable, Codable {
    public var beep: Int
    public var figure: Int
    public var garden: Bool
    public var symbol: ThoughtSymbol
    public var start: Int
    public var end: Int
    public var aim = Fixed.zero
    public var locked = -1
    public var lockTick = -1
    public var item = Item.hotDog
    public var shot = -1
    public var ended = -1
    public var result: ShotResult?

    public init(beep: Int, figure: Int, garden: Bool, symbol: ThoughtSymbol, start: Int, end: Int) {
        self.beep = beep; self.figure = figure; self.garden = garden; self.symbol = symbol; self.start = start; self.end = end
    }

    public var isLive: Bool { ended < 0 }
    public var isLocked: Bool { ended < 0 && locked >= 0 }
    public static let crewReveal = 90, crewCatch = 60

    /// Includes catches made before the reel stops, even when the shot is scored too soon.
    public var caughtTick: Int? {
        shot >= 0 && item == .hotDog && (result == .served || result == .unwanted || result == .tooSoon) ? shot : nil
    }

    public var crewEnd: Int {
        if let caughtTick { return caughtTick + Self.crewCatch }
        return max(end, start + Self.crewReveal)
    }

    public func onJumbotron(at tick: Int) -> Bool { isLive || tick < crewEnd }

    /// Keep the final picture visible through the camera result hold.
    public func thought(at tick: Int) -> ThoughtFrame? {
        FanThought(figure: figure, start: start, end: crewEnd,
                   spinTicks: max(0, start - beep), symbol: symbol).frame(at: tick)
    }
}

public struct AlarmResult: Hashable, Sendable, Codable {
    public var beep: Int
    public var figure: Int
    public var garden: Bool
    public var symbol: ThoughtSymbol
    public var item: Item
    public var result: ShotResult
    public var endTick: Int
    public var shot: Int

    public init(beep: Int, figure: Int, garden: Bool, symbol: ThoughtSymbol, item: Item, result: ShotResult, endTick: Int, shot: Int) {
        self.beep = beep; self.figure = figure; self.garden = garden; self.symbol = symbol; self.item = item; self.result = result
        self.endTick = endTick; self.shot = shot
    }
}

public struct RideTally: Hashable, Sendable, Codable {
    public var laps = 0
    public var alarms = 0
    public var served = 0
    public var tooSoon = 0
    public var wrong = 0
    public var heldFire = 0
    public var garden = 0
    public var bounces = 0
    public var onBeat = 0
    public var points = 0
    public var bestStreak = 0
    public var balks = 0
    public var balkPoints = 0
    public var coins = 0
    public var goals = 0
    public init() {}
}

public enum RideEvent: Hashable, Sendable, Codable {
    /// pipe is 0 for left, 1 for right.
    case bubble(id: Int, pipe: Int, x: Fixed, y: Fixed)
    case grabbed(id: Int)
    case released(id: Int)
    case popped(id: Int)
    case hop(wheel: Wheel, bubble: Int, onBeat: Bool)
    case beep(figure: Int, garden: Bool)
    case locked(id: Int)
    case unlocked
    /// figure is -1 when the shot misses.
    case fired(item: Item, figure: Int, part: Int, distance: Fixed)
    case result(ShotResult)
    case lap(Int)
    case captured(id: Int)
    case thrown(how: ReleaseKind, speed: Fixed, way: Fixed)
    /// by indexes the fielder or fan, or is -1 for nobody.
    case fielded(who: Catcher, by: Int, base: Base?, outcome: ThrowOutcome)
    case balk(ThrowOutcome, points: Int, until: Int)
    case newBall(runners: [Base])
    case `repeat`(RepeatState)
    /// 1 drives forward around the ring; -1 drives backward.
    case turnaround(direction: Int)
    case crew(CrewSubject)
    case parked(Bool)
    case zoom(inward: Bool, bubble: Int)
    case interlude(begun: Bool, fan: Int, number: Int)
}

/// lo, hi, and unwrapped include completed laps; direction is 1 forward or -1 backward.
public struct RepeatSnapshot: Hashable, Sendable {
    public var state: RepeatState
    public var lo: Fixed
    public var hi: Fixed
    public var direction: Int
    public var turning: Fixed
    public var unwrapped: Fixed
    public var ever: Bool
    public var parked = false
    public var parkedAt: Fixed? = nil
    public var parkedEver = false
    public var isTurning: Bool { turning > .zero }
    public var isHeld: Bool { parkedAt != nil }
}

public struct RideSnapshot: Hashable, Sendable {
    public var bubbles: [Bubble]
    /// Geometry from the start of the tick, before the kart moves.
    public var bullpenCart: BullpenCartOnPicture
    /// 1 is the base view; larger values widen it.
    public var zoom: Fixed
    public var steer: Int
    public var railed: Bool
    public var hops: [Int]
    /// level is 0...1, tempo is beats per minute, and beatPhase counts 16.16 beats.
    public var level: Fixed
    public var tempo: Fixed
    public var beatPhase: Int64
    public var beat: Bool
    public var streak: Int
    public var lastBeat: Int64
    public var lap: Int
    public var nextAlarm: Int
    /// Retain the resolved incident until the next one so presentation can finish.
    public var incident: Incident?
    public var lit: Bool
    public var tally: RideTally
    public var lastResult: AlarmResult?
    public var lastResultTick: Int
    public var events: [RideEvent]
    public var pitcher: PitcherSnapshot
    public var lastThrow: ThrowStatus?
    public var lastThrowTick: Int
    public var `repeat`: RepeatSnapshot
    public var whaley: WhaleySnapshot
    public var jumbo = JumboSnapshot()
    public var interlude = InterludeSnapshot()
    public var waterSpray: WaterSpray? = nil
}

public enum InterludePhase: Int, Hashable, Sendable, Codable {
    case turningIn = 1, browsing = 2, catchWatched = 3, turningBack = 4
}

/// number starts at 1; shot is -1 until the hot dog fires.
public struct Interlude: Hashable, Sendable {
    public var fan: Int
    public var number: Int
    public var phase: InterludePhase
    public var k: Int
    /// Ticks remaining in the catch animation; browsing itself has no timer.
    public var left: Int
    public var shot: Int
    public var yaw: Fixed
    public var pitch: Fixed
    public var zoom: Fixed

    public func aim(ticks: Int) -> JumboAim {
        JumboAim(share: phase == .turningIn || phase == .turningBack ? ease(k, of: ticks) : .one, yaw: yaw, pitch: pitch, zoom: zoom)
    }
    /// The phone remains interactive until the player selects Done.
    public var isBrowsing: Bool { phase == .browsing }
}

public struct InterludeSnapshot: Hashable, Sendable {
    public var pending: Bool
    public var count: Int
    public var on: Interlude?
    public var next: Fixed
    public var gapUntil: Int
    public var ever: Bool
    /// An interlude closes its numbered round; the next begins when it ends.
    public var round: Int { on?.number ?? count + 1 }
    public init(pending: Bool = false, count: Int = 0, on: Interlude? = nil, next: Fixed = .zero, gapUntil: Int = 0, ever: Bool = false) {
        self.pending = pending; self.count = count; self.on = on; self.next = next; self.gapUntil = gapUntil; self.ever = ever
    }
}
