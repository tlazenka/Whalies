import StadiumCore
import WhaleKartCore
import CrowdCore

/// Viewport dimensions are recorded because bubbles and touch input use screen points.
public struct PictureParameters: Hashable, Sendable, Codable {
    public var width: Fixed
    public var height: Fixed
    public init(width: Fixed, height: Fixed) { self.width = width; self.height = height }
    public static let phone = PictureParameters(width: Fixed(390.0), height: Fixed(844.0))
}

public struct StadiumParameters: Hashable, Sendable, Codable {
    public var jumbotron: Vec3
    public var jumbotronWidth: Fixed
    public var jumbotronHeight: Fixed
    public var muzzleHeight: Fixed
    public var seed: Int64
    public var sponsor: String
    public var stands: StandsParameters
    public var crowd: CrowdParameters
    public var picture: PictureParameters
    public var ride: RideParameters

    public init(jumbotron: Vec3, jumbotronWidth: Fixed, jumbotronHeight: Fixed, muzzleHeight: Fixed, seed: Int64, sponsor: String,
                stands: StandsParameters, crowd: CrowdParameters, picture: PictureParameters, ride: RideParameters) {
        self.jumbotron = jumbotron; self.jumbotronWidth = jumbotronWidth; self.jumbotronHeight = jumbotronHeight; self.muzzleHeight = muzzleHeight
        self.seed = seed; self.sponsor = sponsor; self.stands = stands; self.crowd = crowd; self.picture = picture; self.ride = ride
    }

    /// Leave enough room inside the stands for the camera to stay clear of the crowd.
    public var kart: KartParameters {
        var k = KartParameters.stadium
        k.cruiseSpeed = ride.cruiseSpeed
        k.trackPoints = KartParameters.ringPoints(centre: KartParameters.fieldCentre, radius: ride.ringRadius, count: 64,
                                                  start: Fixed(raw: 2 * Trig.quarter))
        return k
    }

    public static let stadium = StadiumParameters(
        jumbotron: Vec3(Fixed(43.0), Fixed(24.0), Fixed(119.5)),
        jumbotronWidth: Fixed(24.0),
        jumbotronHeight: Fixed(13.5),
        muzzleHeight: Fixed(1.9),
        seed: 20261101,
        sponsor: "Acme Snacks",
        stands: .stadium,
        crowd: .stadium,
        picture: .phone,
        ride: .stadium
    )

    public func picture(width: Fixed, height: Fixed) -> StadiumParameters {
        var p = self
        p.picture = PictureParameters(width: width, height: height)
        return p
    }
}
