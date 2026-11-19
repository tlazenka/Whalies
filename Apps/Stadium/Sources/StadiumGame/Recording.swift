// Replay consumes saved native Whaley observations alongside Stadium input.

import StadiumCore

public struct StadiumRecording: Hashable, Sendable, Codable {
    /// Version 6 keeps the phone open until a recorded Done input. Earlier timed
    /// visits produce different snapshots and digests.
    public static let currentVersion = 6
    public let version: Int
    public var parameters: StadiumParameters
    public var inputs: [StadiumInput]

    public init(parameters: StadiumParameters, inputs: [StadiumInput]) {
        version = Self.currentVersion
        self.parameters = parameters; self.inputs = inputs
    }

    private enum CodingKeys: String, CodingKey { case version, parameters, inputs }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let recordedVersion = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard recordedVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values,
                debugDescription: "This Stadium recording uses different gameplay rules. Record a new run with this version of Stadium.")
        }
        version = recordedVersion
        parameters = try values.decode(StadiumParameters.self, forKey: .parameters)
        inputs = try values.decode([StadiumInput].self, forKey: .inputs)
    }

    public func makeGame() -> StadiumGame { StadiumGame(parameters: parameters) }

    public func replay() -> [StadiumSnapshot] {
        var game = makeGame()
        var out: [StadiumSnapshot] = []
        out.reserveCapacity(inputs.count)
        for input in inputs { out.append(game.step(input)) }
        return out
    }
}
