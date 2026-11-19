import Foundation
import JSONViewKit
import SQLiteJSONBlaster
import Testing

@Test func sharedBrowsingAnalyticsPreservesQueriesAndUsesHostRecordLabels() async throws {
    let database = try Database(path: ":memory:")
    let whaley = AnalyticsStore(database: database)
    try await whaley.prepare()

    for (time, count) in [(1.0, 10), (2.0, 1), (3.0, 3)] {
        let properties = try String(decoding: JSONSerialization.data(withJSONObject: [
            "path": "$.properties.points",
            "description": "points filter",
            "resultsAfter": count,
        ]), as: UTF8.self)
        try await database.execute(
            "INSERT INTO analytics(occurred_at, event, properties) VALUES (\(time), 'filter_finished', \(properties))"
        )
    }

    let whaleyCards = try await whaley.wrapped()
    let stadiumCards = try await AnalyticsStore(database: database, recordName: "moment").wrapped()
    #expect(whaleyCards.first { $0.id == "medianResultCount" }?.value == "3 median Whaley records")
    #expect(stadiumCards.first { $0.id == "medianResultCount" }?.value == "3 median moments")
    #expect(stadiumCards.first { $0.id == "totalScrubs" }?.value == "3 scrubs")
    #expect(stadiumCards.first { $0.id == "effectiveFilter" }?.detail == "left 1 moment(s) remaining")
}
