import Foundation
import Testing
import MuttniksParsers
import SQLiteJSONBlaster
import WhaleyCore

@Test func WhaleyDocumentQueriesUseJSONPathAndBoundSQLiteParameters() async throws {
    let snapshot = WhaleySceneSnapshot(
        sequence: 1, session: "test", level: 2, gameTime: 5,
        dead: false, player: .init(x: 1, y: 2),
        elements: [.init(kind: .coin, x: 3, y: 4)]
    )
    let data = try WhaleyJSONDocument.data(snapshot: snapshot)
    let document = try #require(String(data: data, encoding: .utf8))
    let db = try Database(path: ":memory:")
    try await db.execute("CREATE TABLE whaley_feed (document TEXT NOT NULL CHECK(json_valid(document)))")
    try await db.execute("INSERT INTO whaley_feed(document) VALUES (\(document))")

    let expression = try parseQueryExpression(#"$.properties.kind = "coin""#)
    let sql = SQL.whaleyIDs(matching: expression)
    #expect(sql.text.contains("json_each(document, '$.items')"))
    #expect(sql.bindings.contains(.text("$.properties.kind")))
    #expect(sql.bindings.contains(.text("coin")))
    let results = try await db.query(sql) { $0.string(at: 0) ?? "" }
    #expect(results == ["cell-0"])
}
