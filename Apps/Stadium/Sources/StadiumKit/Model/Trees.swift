import Foundation
#if canImport(simd)
import simd
#endif
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

extension RideRig {
    struct Leaves: Equatable {
        var centre: SIMD3<Float>
        var radius: Float
    }

    struct Tree: Equatable {
        var foot: SIMD3<Float>
        var height: Float
        var trunkRadius: Float
        var crown: [Leaves]
        var green: Int
    }

    static let wallBehind = 2.6, wallThickness = 0.6, wallHeight = 12.0

    // Use seat centres so crowns clear the overlaid Jumbotron from every point on the road.
    static func gardenTrees(parameters p: StadiumParameters) -> [Tree] {
        let st = p.stands, section = p.ride.garden
        guard let back = st.rows.last, section.seats > 0 else { return [] }
        let c = st.centre
        let wall = back.radius.double + wallBehind + wallThickness / 2
        let radii: [Float] = [2.9, 3.3, 2.7, 3.5, 3.0, 3.2, 2.8]
        let lifts: [Float] = [0.4, 1.0, 0.6, 1.3, 0.7, 1.1, 0.5]
        let count = radii.count
        let first = Double(section.firstSeat), last = Double(section.firstSeat + section.seats - 1)
        var trees: [Tree] = []
        for i in 0..<count {
            let seat = first + (last - first) * Double(i) / Double(count - 1)
            let turn = st.start.double - seat / Double(st.seats)
            let a = turn * 2 * Double.pi
            let r = wall + 2.5 + (i % 2 == 0 ? 0 : 1.0)
            let foot = SceneMapping.scene(x: c.x.double + r * sin(a), y: 0, z: c.z.double + r * cos(a))
            let along = SIMD3<Float>(Float(cos(a)), 0, Float(sin(a)))
            let big = radii[i]
            let middle = foot + SIMD3(0, Float(wallHeight) + lifts[i] + big, 0)
            let crown = [
                Leaves(centre: middle, radius: big),
                Leaves(centre: middle + along * (0.62 * big) + SIMD3(0, -0.15 * big, 0), radius: 0.68 * big),
                Leaves(centre: middle - along * (0.62 * big) + SIMD3(0, -0.15 * big, 0), radius: 0.68 * big),
                Leaves(centre: middle + SIMD3(0, 0.72 * big, 0), radius: 0.55 * big),
            ]
            trees.append(Tree(foot: foot, height: middle.y - foot.y, trunkRadius: 0.35, crown: crown, green: i % 3))
        }
        return trees
    }
}
