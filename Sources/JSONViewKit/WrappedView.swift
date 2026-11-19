#if canImport(UIKit) && os(iOS)
import SwiftUI

/// Render inside the host's navigation stack, including when switching between
/// JSON and Wrapped. The host owns its navigation and any Done action.
@MainActor
public struct WrappedView: View {
    let analytics: AnalyticsStore?
    let supplemental: [WrappedInsight]
    let title: String
    let emptyMessage: String
    @State private var insights: [WrappedInsight] = []
    @State private var error: String?

    public init(
        analytics: AnalyticsStore?,
        supplemental: [WrappedInsight] = [],
        title: String = "Whaley Wrapped",
        emptyMessage: String = "Explore Whaley runs or use search and scrub to build your Wrapped history."
    ) {
        self.analytics = analytics
        self.supplemental = supplemental
        self.title = title
        self.emptyMessage = emptyMessage
    }

    public var body: some View {
        List {
            ForEach(supplemental + insights) { insight in
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.eyebrow)
                        .textCase(.uppercase)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(insight.value)
                        .font(.largeTitle.bold())
                    Text(insight.detail)
                        .font(.body)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .task(id: analytics.map(ObjectIdentifier.init)) {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .overlay {
            if insights.isEmpty && supplemental.isEmpty && error == nil {
                ContentUnavailableView(
                    "Nothing to wrap yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text(emptyMessage)
                )
            }
        }
    }

    func refresh() async {
        guard let analytics else {
            insights = []
            error = nil
            return
        }
        do {
            let loaded = try await analytics.wrapped()
            guard !Task.isCancelled else { return }
            insights = loaded
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
#endif
