import Foundation

/// The shared JSON document consumed by Whaley's faceted explorer and CLI.
/// It deliberately has one item schema for a live world and recorded runs.
public enum WhaleyJSONDocument {
    public static func data(
        snapshot: WhaleySceneSnapshot? = nil,
        runs: [WhaleyRecordedRun] = []
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var items = [[String: Any]]()

        for run in runs {
            let data = try encoder.encode(run)
            guard let properties = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            items.append([
                "id": run.id.uuidString,
                "type": "recorded-run",
                "properties": properties
            ])
        }

        if let snapshot {
            let data = try encoder.encode(snapshot)
            guard let properties = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            items.append(["id": "live-world", "type": "live-world", "properties": properties])
            if let liveEntities = snapshot.liveEntities, !liveEntities.isEmpty {
                for entity in liveEntities {
                    let data = try encoder.encode(entity)
                    guard let properties = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    items.append([
                        "id": entity.id,
                        "type": "live-entity",
                        "properties": properties
                    ])
                }
            } else {
                for (index, cell) in snapshot.elements.enumerated() {
                    items.append([
                        "id": "cell-\(index)",
                        "type": "map-cell",
                        "properties": [
                            "kind": cell.kind.rawValue,
                            "x": cell.x,
                            "y": cell.y,
                            "level": snapshot.level
                        ]
                    ])
                }
            }
        }
        return try JSONSerialization.data(
            withJSONObject: ["type": "whaley", "items": items],
            options: [.sortedKeys]
        )
    }
}
