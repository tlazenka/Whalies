#if canImport(UIKit)
import Foundation
import Observation
import JSONViewKit
import SQLiteJSONBlaster

// Keep persistence session-scoped and callbacks view-scoped so apps cannot replace each other's observers.
@MainActor @Observable
final class StadiumExplorerStore {
    let preferences = UserDefaults(suiteName: "com.muttniks.stadium.explorer") ?? .standard
    private(set) var analytics: AnalyticsStore?
    private(set) var preparationError: String?
    private var preparation: Task<Void, Never>?
    private var prepared = false

    func prepare() async {
        if prepared { return }
        if let preparation { await preparation.value; return }
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let directory = URL.applicationSupportDirectory.appendingPathComponent("Stadium", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let database = try Database(path: directory.appendingPathComponent("Explorer.sqlite").path)
                let store = AnalyticsStore(database: database, recordName: "moment")
                try await store.prepare()
                analytics = store
                prepared = true
                preparationError = nil
            } catch {
                preparationError = error.localizedDescription
            }
        }
        preparation = operation
        await operation.value
        preparation = nil
    }
}
#endif
