import Foundation
import Testing
@testable import StadiumKit

private func eyeGaze(yawDegrees: Float, pitchDegrees: Float) -> SIMD3<Float> {
    let yaw = yawDegrees * .pi / 180, pitch = pitchDegrees * .pi / 180
    return SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
}

@Test
func whaleyPupilsLookTowardTheAimAndTheirGlintsFollow() throws {
    let parts = WhaleyMascot.parts
    for side in [Float(-1), 1] {
        let pupil = try #require(parts.first { $0.name == "pupil" && $0.centre.x * side > 0 })
        let glint = try #require(parts.first { $0.name == "eye-glint" && $0.centre.x * side > 0 })
        #expect(WhaleyMascot.gazeOffset(for: pupil, toward: SIMD3(0, 0, -1)) == .zero)
        for yaw in [Float(-40), -12, 0, 12, 40] {
            for pitch in [Float(-35), 0, 35] {
                let gaze = eyeGaze(yawDegrees: yaw, pitchDegrees: pitch)
                let offset = WhaleyMascot.gazeOffset(for: pupil, toward: gaze)
                #expect(WhaleyMascot.gazeOffset(for: glint, toward: gaze) == offset,
                        "The highlight stays attached to its pupil")
                #expect(yaw == 0 ? offset.x == 0 : offset.x * yaw > 0)
                #expect(pitch == 0 ? offset.y == 0 : offset.y * pitch > 0)
                #expect(abs(offset.x) <= 0.03501 && abs(offset.y) <= 0.04001)
                #expect(offset.z.isFinite)
                #expect(WhaleyMascot.gazeOffset(for: pupil, toward: gaze) == offset,
                        "Repeated rendering does not accumulate eye motion")
            }
        }
    }
}

@Test
func whaleyPupilsStayWithinTheirWhitesAndFollowTheirCurvature() throws {
    let parts = WhaleyMascot.parts
    for side in [Float(-1), 1] {
        let pupil = try #require(parts.first { $0.name == "pupil" && $0.centre.x * side > 0 })
        let eye = try #require(parts.first { $0.name == "eye" && $0.centre.x * side > 0 })
        func surface(at point: SIMD3<Float>) -> Float {
            let x = (point.x - eye.centre.x) / eye.radii.x
            let y = (point.y - eye.centre.y) / eye.radii.y
            return eye.centre.z - eye.radii.z * sqrt(1 - x * x - y * y)
        }
        let restInset = pupil.centre.z - surface(at: pupil.centre)
        for yaw in stride(from: -40, through: 40, by: 10) {
            for pitch in stride(from: -35, through: 35, by: 7) {
                let offset = WhaleyMascot.gazeOffset(for: pupil, toward: eyeGaze(yawDegrees: Float(yaw), pitchDegrees: Float(pitch)))
                let centre = pupil.centre + offset
                #expect(abs(centre.z - surface(at: centre) - restInset) < 0.000001,
                        "The pupil retains its inset into the white ellipsoid")
                for sample in 0..<72 {
                    let angle = Float(sample) / 72 * 2 * .pi
                    let x = (centre.x + pupil.radii.x * cos(angle) - eye.centre.x) / eye.radii.x
                    let y = (centre.y + pupil.radii.y * sin(angle) - eye.centre.y) / eye.radii.y
                    #expect(x * x + y * y < 1, "The pupil silhouette must remain inside its eye")
                }
            }
        }
    }
}

@Test
func whaleyGazeLeavesRestArtworkAndInvalidInputAlone() throws {
    let before = WhaleyMascot.parts
    let pupil = try #require(before.first { $0.name == "pupil" })
    for direction in [SIMD3<Float>.zero, SIMD3(.nan, 0, -1), SIMD3(0, .infinity, -1), SIMD3(0, 0, -.infinity)] {
        #expect(WhaleyMascot.gazeOffset(for: pupil, toward: direction) == .zero)
    }
    for part in before {
        #expect(WhaleyMascot.gazeOffset(for: part, toward: SIMD3(0, 0, -1)) == .zero)
        if part.name != "pupil" && part.name != "eye-glint" {
            #expect(WhaleyMascot.gazeOffset(for: part, toward: eyeGaze(yawDegrees: 40, pitchDegrees: 35)) == .zero)
        }
    }
    #expect(WhaleyMascot.parts == before, "Gaze cannot mutate the body, face or hat rest geometry")
}
