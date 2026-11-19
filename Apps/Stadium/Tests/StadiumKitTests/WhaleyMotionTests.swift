import Foundation
import Testing
import StadiumGame
@testable import StadiumKit

private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 0.0001) -> Bool {
    let delta = a - b
    return (delta * delta).sum() < tolerance * tolerance
}

private func direction(_ pose: WhaleyMotion.Pose) -> SIMD3<Float> {
    pose.worldPoint(SIMD3<Float>(0, 0, -1)) - pose.position
}

@Test
func whaleyFacesTheRoadWhenThereIsNoReticle() {
    let origin = SIMD3<Float>(4, 2, -7)
    let headings: [(Double, SIMD3<Float>)] = [
        (0, SIMD3(0, 0, -1)), (0.25, SIMD3(1, 0, 0)),
        (0.5, SIMD3(0, 0, 1)), (0.75, SIMD3(-1, 0, 0)),
        (-0.25, SIMD3(-1, 0, 0)), (1.25, SIMD3(1, 0, 0)),
    ]
    for (heading, expected) in headings {
        let pose = WhaleyMotion.pose(origin: origin, headingTurns: heading, target: nil, spray: nil, tick: 5)
        #expect(pose.position == origin)
        #expect(pose.pitch == 0)
        #expect(pose.gaze == SIMD3<Float>(0, 0, -1))
        #expect(near(direction(pose), expected))
    }
}

@Test
func whaleyTurnsHisBodyAndEyesTowardTheSameTarget() {
    let origin = SIMD3<Float>(4, 2, -7)
    for side in [Float(-1), Float(1)] {
        let delta = SIMD3<Float>(side * 20, side * 8, -20)
        let pose = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: origin + delta,
                                     spray: nil, tick: 10)
        let body = direction(pose)
        #expect(body.x * side > 0 && body.y * side > 0 && body.z < 0)
        #expect(pose.gaze.x * side > 0 && pose.gaze.y * side > 0 && pose.gaze.z < 0)
        let worldGaze = pose.worldPoint(pose.gaze) - pose.position
        #expect(near(worldGaze, delta / sqrt((delta * delta).sum())),
                "Body and local eye rotations combine to look at the reticle")
    }
    let returned = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: nil, tick: 11)
    #expect(near(direction(returned), SIMD3<Float>(0, 0, -1)))
    #expect(returned.gaze == SIMD3<Float>(0, 0, -1))
}

@Test
func whaleyDoesNotSnapWhenAimCrossesBehindTheRoadHeading() {
    let left = WhaleyMotion.pose(origin: .zero, headingTurns: 0, target: SIMD3(-0.1, 0, 20),
                                 spray: nil, tick: 0)
    let right = WhaleyMotion.pose(origin: .zero, headingTurns: 0, target: SIMD3(0.1, 0, 20),
                                  spray: nil, tick: 0)
    #expect(near(direction(left), direction(right), tolerance: 0.03))
    #expect(near(left.gaze, right.gaze, tolerance: 0.01))
    #expect(direction(left).z > 0 && direction(right).z > 0)
}

@Test
func whaleyGazeStaysFiniteAndOnTheFrontOfHisEyes() {
    let origin = SIMD3<Float>(4, 2, -7)
    let targets: [SIMD3<Float>?] = [nil, origin, SIMD3(.nan, 0, 0), SIMD3(0, .infinity, 0),
                                  origin + SIMD3(0, 100, 0), origin + SIMD3(0, -100, 0),
                                  origin + SIMD3(0, 0, 100), SIMD3(Float.greatestFiniteMagnitude, 0, 0)]
    let spray = WaterSpray(round: 1, startTick: 0)
    for target in targets {
        for tick in [0, 11, 22, 34, 45] {
            let pose = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: target, spray: spray, tick: tick)
            #expect(pose.yaw.isFinite && pose.pitch.isFinite)
            #expect(pose.gaze.x.isFinite && pose.gaze.y.isFinite && pose.gaze.z < 0)
            #expect(abs((pose.gaze * pose.gaze).sum() - 1) < 0.0001)
        }
    }
    let invalid = WhaleyMotion.pose(origin: SIMD3(.nan, 0, 0), headingTurns: .infinity,
                                    target: nil, spray: nil, tick: 0)
    #expect(invalid.position == .zero && invalid.yaw == 0 && invalid.pitch == 0)
    #expect(invalid.gaze == SIMD3<Float>(0, 0, -1))
}

@Test
func aSprayMakesOneFullAirborneTurnAndLandsBackAtRest() {
    let origin = SIMD3<Float>(4, 2, -7)
    let spray = WaterSpray(round: 2, startTick: 100)
    func pose(_ age: Int) -> WhaleyMotion.Pose {
        WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: spray,
                          tick: spray.startTick + age)
    }
    let rest = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: nil, tick: 0)
    #expect(pose(-1) == rest && pose(0) == rest)
    #expect(pose(11).yaw > 0 && pose(11).yaw < .pi)
    #expect(pose(22).yaw < .pi && pose(23).yaw > .pi)
    #expect(pose(34).yaw > .pi && pose(34).yaw < 2 * .pi)
    #expect(pose(22).position.y > origin.y + 0.89)
    #expect(pose(23).position.y > origin.y + 0.89)

    var accumulatedTurn: Float = 0
    var previous = direction(pose(0))
    for age in 1...WaterSpray.sprayTicks {
        let current = pose(age)
        let next = direction(current)
        // Accumulate direction changes across the angle wrap at landing.
        let crossY = previous.z * next.x - previous.x * next.z
        accumulatedTurn += atan2(crossY, previous.x * next.x + previous.z * next.z)
        previous = next
        #expect(current.position.y >= origin.y)
        #expect(current.position.x == origin.x && current.position.z == origin.z)
    }
    #expect(abs(accumulatedTurn - 2 * .pi) < 0.0001)
    #expect(pose(WaterSpray.sprayTicks) == rest)
    #expect(pose(WaterSpray.sprayTicks + 100) == rest,
            "Wet-lens time does not repeat the jump")
    #expect(near(direction(pose(44)), direction(rest), tolerance: 0.01),
            "The last airborne frame approaches the landing direction without snapping")
}

@Test
func theBlowholeMovesWithThePoseAndRepeatedTicksDoNotAccumulateMotion() {
    let origin = SIMD3<Float>(4, 2, -7)
    let spray = WaterSpray(round: 3, startTick: 200)
    let rest = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: nil, tick: 0)
    let first = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: spray, tick: 222)
    let repeated = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: spray, tick: 222)
    #expect(first == repeated)
    let restedHole = rest.worldPoint(WhaleyMascot.blowhole)
    let airborneHole = first.worldPoint(WhaleyMascot.blowhole)
    #expect(near(restedHole, origin + WhaleyMascot.blowhole))
    #expect(airborneHole.y > restedHole.y + 0.89)
    #expect(airborneHole.z > origin.z,
            "At the half-turn, the blowhole has rotated with the body")
    let restored = WhaleyMotion.pose(origin: origin, headingTurns: 0, target: nil, spray: spray, tick: 245)
    #expect(near(restored.worldPoint(WhaleyMascot.blowhole), restedHole))
}
