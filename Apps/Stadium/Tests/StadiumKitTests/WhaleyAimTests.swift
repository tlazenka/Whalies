import Foundation
#if canImport(simd)
import simd
#endif
import Testing
import StadiumCore
import CrowdCore
@testable import StadiumGame
@testable import StadiumKit

// Fix the fan position so gaze tests are independent of randomized incident scheduling.
private func whaleyAimFixture(parameters p: StadiumParameters = .stadium, zoom: Fixed = .one,
                              fade: Fixed = .zero) -> (snapshot: StadiumSnapshot, figures: [Figure]) {
    var game = StadiumGame(parameters: p)
    var s = game.step(.none)
    s.ride.zoom = zoom
    s.ride.pitcher.fade = fade
    let camera = TurretCamera(car: s.car, parameters: p, zoom: zoom, onHim: fade)
    let head = camera.eye + camera.basis.forward.scaled(by: Fixed(40.0))
                         + camera.basis.right.scaled(by: Fixed(8.0))
                         + camera.basis.up.scaled(by: Fixed(4.0))
    let fan = Figure(x: head.x, base: .zero, z: head.z, headY: head.y,
                     torsoY: head.y - Fixed(0.7), headR: Fixed(0.25), torsoR: Fixed(0.45))
    s.ride.incident = Incident(beep: 0, figure: 0, garden: false, symbol: .hotDog, start: 100, end: 200)
    s.ride.bubbles = [Bubble(id: 7, x: p.picture.width * .half, y: p.picture.height * .half,
                            scale: .one, isFrozen: true, isBeingMoved: true, usesLeft: 2)]
    return (s, [fan])
}

@Test
func whaleyNeedsALiveVisibleReticleToLookAwayFromTheRoad() {
    var (s, figures) = whaleyAimFixture()
    s.ride.incident = nil
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)

    (s, figures) = whaleyAimFixture()
    s.ride.bubbles[0].isBeingMoved = false
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil,
            "an unheld bubble and a live fan request do not create a reticle")

    s.ride.bubbles[0].isBeingMoved = true
    s.ride.bubbles[0].isFrozen = false
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)
}

@Test(arguments: [PictureParameters.phone,
                  PictureParameters(width: Fixed(1194.0), height: Fixed(834.0))])
func whaleyHeldReticleFollowsPicturePointsThroughZoomAndFade(picture: PictureParameters) throws {
    var p = StadiumParameters.stadium
    p.picture = picture
    for zoom in [Fixed.one, Fixed(1.8)] {
        for fade in [Fixed.zero, Fixed.one] {
            var (s, figures) = whaleyAimFixture(parameters: p, zoom: zoom, fade: fade)
            let camera = Cameras.turret(s, parameters: p)
            let size = SIMD2<Float>(Float(p.picture.width.double), Float(p.picture.height.double))
            let head = SceneMapping.scene(figures[0].head)
            var targets: [SIMD3<Float>] = []
            for point in [SIMD2<Float>(0.25, 0.5), SIMD2<Float>(0.75, 0.5),
                          SIMD2<Float>(0.5, 0.25), SIMD2<Float>(0.5, 0.75)] {
                let pixel = point * size
                s.ride.bubbles[0].x = Fixed(Double(pixel.x))
                s.ride.bubbles[0].y = Fixed(Double(pixel.y))
                let target = try #require(RideRig.whaleyAimTarget(s, parameters: p, figures: figures))
                let projected = try #require(camera.project(target, viewSize: size))
                #expect(simd_length(projected - pixel) < 0.2)
                #expect(abs(simd_dot(target - head, camera.forward)) < 0.01,
                        "held targets remain on the fan's depth plane")
                #expect(RideRig.whaleyAimTarget(s, parameters: p, figures: figures) == target,
                        "a redraw does not accumulate pose state")
                targets.append(target)
            }
            #expect(simd_length(targets[1] - targets[0]) > 1)
            #expect(targets[2].y > targets[3].y)
        }
    }
}

@Test
func whaleyLockedReticleUsesTheFansHeadAndKeepsLockPrecedence() throws {
    var (s, figures) = whaleyAimFixture()
    s.ride.incident?.locked = 7
    s.ride.bubbles[0].isBeingMoved = false
    s.ride.bubbles.insert(Bubble(id: 8, x: .zero, y: .zero, scale: .one,
                                 isFrozen: true, isBeingMoved: true, usesLeft: 2), at: 0)
    let target = try #require(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures))
    #expect(target == SceneMapping.scene(figures[0].head))
}

@Test
func whaleyGazeDoesNotChangeDepthWhenTheReticleLocks() throws {
    let p = StadiumParameters.stadium
    var (s, figures) = whaleyAimFixture(parameters: p, zoom: Fixed(1.8), fade: .half)
    let camera = TurretCamera(car: s.car, parameters: p, zoom: s.ride.zoom, onHim: s.ride.pitcher.fade)
    let point = try #require(camera.point(figures[0].head))
    s.ride.bubbles[0].x = point.x
    s.ride.bubbles[0].y = point.y
    let held = try #require(RideRig.whaleyAimTarget(s, parameters: p, figures: figures))
    s.ride.incident?.locked = 7
    let locked = try #require(RideRig.whaleyAimTarget(s, parameters: p, figures: figures))
    #expect(simd_length(held - locked) < 0.02,
            "only fixed-point projection rounding separates held and locked gaze")
}

@Test
func whaleyLostTargetsAndSettledResultsReleaseTheGaze() {
    var (s, figures) = whaleyAimFixture()
    s.ride.incident?.locked = 7
    s.ride.bubbles = []
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)

    (s, figures) = whaleyAimFixture()
    s.ride.incident?.ended = s.tick
    #expect(RideRig.crewDoll(s) != nil, "the result may still have its presentation hold")
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)

    (s, figures) = whaleyAimFixture()
    s.ride.incident?.figure = 99
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)
    s.ride.incident?.locked = 7
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)
}

@Test
func phoneAndWhaleyGameOwnershipSuspendMascotAiming() {
    var (s, figures) = whaleyAimFixture()
    s.ride.jumbo.zoom = JumboZoom(bubble: 7, k: 1, out: false, yaw: .zero, pitch: .zero, zoom: .one)
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)
    s.ride.jumbo.zoom = nil
    s.ride.interlude.on = Interlude(fan: 0, number: 1, phase: .turningIn, k: 1, left: 0, shot: -1,
                                   yaw: .zero, pitch: .zero, zoom: .one)
    #expect(RideRig.whaleyAimTarget(s, parameters: .stadium, figures: figures) == nil)
}

@Test
func whaleyAimHasASafeForwardFallbackAndRejectsInvalidProjection() throws {
    let p = StadiumParameters.stadium
    var (s, figures) = whaleyAimFixture()
    let camera = TurretCamera(car: s.car, parameters: p, zoom: s.ride.zoom, onHim: s.ride.pitcher.fade)
    let behind = camera.eye - camera.basis.forward.scaled(by: Fixed(40.0))
    figures[0].x = behind.x
    figures[0].z = behind.z
    figures[0].headY = behind.y
    let target = try #require(RideRig.whaleyAimTarget(s, parameters: p, figures: figures))
    let distance = simd_length(target - SceneMapping.scene(camera.eye))
    #expect(abs(distance - 60) < 0.01)

    s.ride.zoom = .zero
    #expect(RideRig.whaleyAimTarget(s, parameters: p, figures: figures) == nil)
    s.ride.zoom = Fixed(raw: 1)
    #expect(RideRig.whaleyAimTarget(s, parameters: p, figures: figures) == nil,
            "a zoom that quantizes the field tangent to zero must not divide by zero")
    s.ride.zoom = .one
    var invalid = p
    invalid.picture.height = .zero
    #expect(RideRig.whaleyAimTarget(s, parameters: invalid, figures: figures) == nil)
}
