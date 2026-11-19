import Foundation
import Testing
import StadiumGame
@testable import StadiumKit

private func idlePose(phase: Int64, tick: Int = 0, spray: WaterSpray? = nil,
                      target: SIMD3<Float>? = nil) -> WhaleyMotion.Pose {
    WhaleyMotion.pose(origin: .zero, headingTurns: 0, target: target,
                      spray: spray, tick: tick, beatPhase: phase)
}

@Test
func whaleysIdleHopAndLimbsFollowTheMusicBeat() {
    let rest = idlePose(phase: 0)
    #expect(rest.position == .zero && rest.finAngle == 0 && rest.tailAngle == 0)
    let rising = idlePose(phase: 16_384)
    let peak = idlePose(phase: 32_768)
    let falling = idlePose(phase: 49_152)
    #expect(abs(rising.position.y - 0.025) < 0.000001)
    #expect(abs(peak.position.y - 0.05) < 0.000001)
    #expect(abs(falling.position.y - rising.position.y) < 0.000001)
    #expect(rising.finAngle > 0 && rising.tailAngle < 0)
    #expect(falling.finAngle < 0 && falling.tailAngle > 0)
    #expect(idlePose(phase: 65_536) == rest, "Whaley lands on the next musical beat")

    for phase in stride(from: Int64(0), through: 65_536, by: 256) {
        let pose = idlePose(phase: phase)
        #expect(pose.position.y >= 0 && pose.position.y <= 0.050001)
        #expect(pose.position.x == 0 && pose.position.z == 0)
        #expect(abs(pose.finAngle) <= 6 * .pi / 180 + 0.000001)
        #expect(abs(pose.tailAngle) <= 4 * .pi / 180 + 0.000001)
        #expect(pose.yaw == 0 && pose.pitch == 0 && pose.gaze == SIMD3<Float>(0, 0, -1))
    }
}

@Test
func idleAnimationUsesBeatPhaseInsteadOfAWallClockOrTickRate() {
    let first = idlePose(phase: 16_384, tick: 17)
    #expect(idlePose(phase: 16_384, tick: 1_000_000) == first,
            "A paused musical phase keeps exactly the same pose")
    #expect(idlePose(phase: 16_384 + 65_536) == first)
    let longPhase = (Int64.max & ~Int64(0xFFFF)) | 16_384
    #expect(idlePose(phase: longPhase) == first,
            "Long recordings keep their fractional-beat precision")
    #expect(idlePose(phase: 32_768, tick: 17).position.y > first.position.y,
            "Faster beat-phase progress changes the pose even at the same tick")
    let beforeWrap = idlePose(phase: 65_535)
    #expect(beforeWrap.position.y < 0.000001)
    #expect(abs(beforeWrap.finAngle) < 0.00002 && abs(beforeWrap.tailAngle) < 0.00002)
}

@Test
func waterJumpTakesOverIdleAndReturnsWithoutAnEndpointSnap() {
    let spray = WaterSpray(round: 1, startTick: 100)
    for phase in [Int64(0), 16_384, 32_768, 49_152] {
        let normal = idlePose(phase: phase)
        #expect(idlePose(phase: phase, tick: 100, spray: spray) == normal)
        #expect(idlePose(phase: phase, tick: 145, spray: spray) == normal)
        #expect(idlePose(phase: phase, tick: 200, spray: spray) == normal,
                "The wet lens does not suppress the restored idle motion")
        for age in 6...39 {
            let active = idlePose(phase: phase, tick: 100 + age, spray: spray)
            let waterOnly = idlePose(phase: 0, tick: 100 + age, spray: spray)
            #expect(active == waterOnly, "The middle of the spray owns the whole pose")
        }
        let first = idlePose(phase: phase, tick: 101, spray: spray)
        let last = idlePose(phase: phase, tick: 144, spray: spray)
        #expect(abs(first.position.y - normal.position.y) < 0.005)
        #expect(abs(last.position.y - normal.position.y) < 0.005)
        #expect(abs(first.finAngle - normal.finAngle) < 0.008)
        #expect(abs(last.finAngle - normal.finAngle) < 0.008)
        #expect(abs(first.tailAngle - normal.tailAngle) < 0.006)
        #expect(abs(last.tailAngle - normal.tailAngle) < 0.006)
    }
}

@Test
func idleGazeStillConvergesOnTheReticleFromTheBouncingBody() {
    let target = SIMD3<Float>(8, 4, -16)
    for phase in [Int64(0), 16_384, 32_768, 49_152] {
        let pose = idlePose(phase: phase, target: target)
        let delta = target - pose.position
        let expected = delta / sqrt((delta * delta).sum())
        let actual = pose.worldPoint(pose.gaze) - pose.position
        let error = actual - expected
        #expect((error * error).sum() < 0.00000001)
        #expect(pose.finAngle == idlePose(phase: phase).finAngle,
                "Aiming keeps the small idle fin animation")
        #expect(pose.tailAngle == idlePose(phase: phase).tailAngle)
        #expect(idlePose(phase: phase, target: target) == pose,
                "Redraw and replay produce the same body, gaze and limbs")
    }
}
