import Foundation
import JSONViewKit
import SQLiteJSONBlaster
import SwiftUI
import WhaleyCore
import WhaleyHost

/// A destination in Debug's NavigationStack; never installs another stack.
/// JSON exploration, Wrapped insights, refresh and export retain their data flow.
struct WhaleyDataWorkspaceView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case json = "JSON", wrapped = "Wrapped"
        var id: Self { self }
    }
    @State private var page: Page = .json
    @State private var root: JSONNode?
    @State private var analytics: AnalyticsStore?
    @State private var highlights: [WrappedInsight] = []
    @State private var errorMessage: String?
    @State private var reloadID = 0
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Data view", selection: $page) {
                ForEach(Page.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                if let errorMessage {
                    ContentUnavailableView("Explorer unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if page == .json {
                    if let root {
                        JSONNodeView(root: root, analytics: analytics)
                            .id(reloadID)
                    } else {
                        ProgressView("Reading Whaley data")
                    }
                } else if let analytics {
                    WrappedView(analytics: analytics, supplemental: highlights)
                } else {
                    ProgressView("Preparing analytics")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Data Explorer")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink("Export JSON", item: exportURL)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
            }
        }
        .task { await reload() }
    }

    @MainActor private func reload() async {
        do {
            if analytics == nil {
                let directory = URL.applicationSupportDirectory
                    .appendingPathComponent("Whaley", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let db = try Database(path: directory.appendingPathComponent("ExplorerAnalytics.sqlite").path)
                let store = AnalyticsStore(database: db)
                try await store.prepare()
                analytics = store
            }

            let runs = WhaleyRunRecorder.shared.recordedRuns
            let snapshot = WhaleyLiveSceneCapture.current()?.snapshot
            let data = try WhaleyJSONDocument.data(snapshot: snapshot, runs: Array(runs.suffix(12)))
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("whaley-data.json")
            try data.write(to: destination, options: .atomic)
            exportURL = destination
            let document = try JSONSerialization.jsonObject(with: data)
            root = JSONNode.make(name: "$", path: "$", value: document)
            highlights = [
                WrappedInsight(id: "recordedRuns", eyebrow: "Recorded attempts",
                               value: "\(runs.count) runs", detail: "Available for JSON exploration"),
                WrappedInsight(id: "levels", eyebrow: "Levels explored",
                               value: "\(Set(runs.map(\.level)).count) levels",
                               detail: "Across recorded gameplay attempts"),
                WrappedInsight(id: "bounces", eyebrow: "Bubble-assisted movement",
                               value: "\(runs.flatMap(\.gameplayEvents).filter { $0.action == .bubbleBounce }.count) bounces",
                               detail: "Confirmed upward bounce events")
            ]
            reloadID += 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
