#if canImport(UIKit) && os(iOS)
import ScopedUserDefaults
import SwiftUI
import UIKit

/// Hosts supply a document and presentation policy; filtering and gesture behavior stay shared.
@MainActor
public struct JSONNodeView: View {
    let root: JSONNode
    var model: JSONNodeViewModel { JSONNodeViewModel(root: root) }

    let analytics: AnalyticsStore?
    let title: String
    let copiesCommand: Bool
    let remembersFacet: Bool
    let onEvent: (@MainActor (String, [String: Any]) -> Void)?

    let defaults: Defaults2<ExplorerDefaults, SearchDefaults>

    var explorerDefaults: ExplorerDefaults {
        defaults(ExplorerDefaults.self)
    }

    var searchDefaults: SearchDefaults {
        defaults(SearchDefaults.self)
    }

    public init(
        root: JSONNode,
        analytics: AnalyticsStore? = nil,
        initialFilter: FieldFilter? = nil,
        title: String = "Whaley JSON Explorer",
        copiesCommand: Bool = true,
        remembersFacet: Bool = true,
        preferences: UserDefaults = .standard,
        onEvent: (@MainActor (String, [String: Any]) -> Void)? = nil
    ) {
        self.root = root
        self.analytics = analytics
        self.title = title
        self.copiesCommand = copiesCommand
        self.remembersFacet = remembersFacet
        self.defaults = preferences.providing(ExplorerDefaults.self, SearchDefaults.self)
        self.onEvent = onEvent
        _filter = State(initialValue: initialFilter)
    }

    @State private var filter: FieldFilter?
    @State private var scrubOrigin: FieldFilter?
    @State private var scrubStartTouchPoint: CGPoint?
    @State private var feedback = UISelectionFeedbackGenerator()
    @State private var markers: [String: FieldMarker] = [:]
    @State private var searchText = ""
    @State private var tokens: [SearchToken] = []
    @State private var suggestedTokens: [SearchToken] = []
    @State private var synchronizingTokens = false
    @State private var suggestionScores: [String: Int] = [:]
    @State private var didRestoreDefaults = false
    @State private var signalsRevision = 0

    private struct SignalsRequest: Equatable {
        let store: ObjectIdentifier?
        let revision: Int
    }

    var filteredDataRoot: JSONNode {
        guard let filter else { return root }
        return root.filtering(filter) ?? root
    }

    var displayedRoot: JSONNode {
        if let fieldName = selectedFieldName {
            return filteredDataRoot.filtering(
                fieldName: fieldName,
                categoricalValue: selectedValue
            ) ?? emptyRoot(from: filteredDataRoot)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filteredDataRoot }
        return filteredDataRoot.filtering(query) ?? emptyRoot(from: filteredDataRoot)
    }

    func emptyRoot(from root: JSONNode) -> JSONNode {
        JSONNode(id: root.id, name: root.name, path: root.path, value: root.value, children: [])
    }

    var resultCount: Int {
        displayedRoot.children.first(where: { $0.name == "items" })?.children.count ?? 0
    }

    var isScrubbing: Bool { scrubOrigin != nil }

    var selectedFieldName: String? {
        guard case .fieldName(let name)? = tokens.first else { return nil }
        return name
    }

    var selectedValue: String? {
        guard tokens.count >= 2,
            case .categoricalValue(let value) = tokens[1]
        else { return nil }
        return value
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(resultCount) results")
                    .font(.headline)
                Spacer()
                if selectedValue != nil {
                    Button(isCurrentFacetSaved ? "Saved" : "Save") {
                        saveCurrentFacet()
                    }
                    .disabled(isCurrentFacetSaved)
                }
                if filter != nil || !tokens.isEmpty {
                    Button("Clear") {
                        record("filter_cleared")
                        filter = nil
                        tokens = []
                        refreshSuggestedTokens()
                    }
                }
            }
            .padding(.horizontal)

            CBLinearHierarchyViewControllerRepresentable(
                root: displayedRoot,
                markers: markers,
                activeFilter: filter,
                resultCount: resultCount,
                onScrub: { node, translation, touchPoint, state in
                    scrub(node: node, translationX: translation, touchPoint: touchPoint, state: state)
                },
                onAdjust: { node, direction in
                    adjustAccessibility(node: node, direction: direction)
                }
            )
        }
        .navigationTitle(title)
        .searchable(
            text: $searchText,
            tokens: $tokens,
            suggestedTokens: $suggestedTokens,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search by node and filter"
        ) { token in
            SearchTokenLabel(token: token, searchDefaults: searchDefaults)
        }
        .onChange(of: searchText) { _, _ in
            refreshSuggestedTokens()
        }
        .onChange(of: tokens) { oldTokens, newTokens in
            tokensChanged(from: oldTokens, to: newTokens)
        }
        .onSubmit(of: .search) {
            searchSubmitted()
        }
        .task {
            defaults.register()
            restoreDefaultsIfNeeded()
        }
        .task(id: SignalsRequest(store: analytics.map(ObjectIdentifier.init), revision: signalsRevision)) {
            await loadWarehouseSignals()
        }
        .onReceive(explorerDefaults.didChangePublisher) {
            refreshSuggestedTokens()
            reloadWarehouseSignals()
        }
        .overlay {
            GeometryReader { geometryProxy in
                if isScrubbing, let filter, let startTouch = scrubStartTouchPoint {
                    FeedbackHUD(message: filter.description, monospaced: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: max(0, geometryProxy.size.width - 24))
                        .position(
                            x: geometryProxy.size.width / 2,
                            y: scrubHUDY(startTouch: startTouch, in: geometryProxy)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // Start off the HUD a bit above the finger, and keep it stable
    func scrubHUDY(startTouch: CGPoint, in geometry: GeometryProxy) -> CGFloat {
        let centerY = geometry.size.height / 2
        let startY = startTouch.y - geometry.frame(in: .global).minY
        // TODO: Dynamic Type, safe area
        return startY < centerY ? max(16, startY - 100) : centerY
    }

    func scrub(node: JSONNode, translationX: CGFloat, touchPoint: CGPoint, state: UIGestureRecognizer.State) {
        guard let relativePath = model.featureRelativePath(from: node.path) else { return }
        switch state {
        case .began:
            scrubStartTouchPoint = touchPoint
            feedback.prepare()
            scrubOrigin = model.initialFilter(path: relativePath, value: node.value)
            filter = scrubOrigin
            record(
                "scrub_started",
                properties: [
                    "path": relativePath,
                    "kind": node.value.analyticsKind,
                ]
            )
        case .changed:
            guard let origin = scrubOrigin else { return }
            let next = model.adjusted(origin, translationX: translationX)
            if next != filter {
                feedback.selectionChanged()
                feedback.prepare()
                record("filter_changed", properties: next.analyticsProperties)
            }
            filter = next
        case .ended:
            if let filter {
                applyFilter(filter, source: "touch")
                if copiesCommand {
                    UIPasteboard.general.string = dockerCommand(for: filter)
                    record("docker_command_copied", properties: ["path": filter.path])
                }
            }
            scrubOrigin = nil
            scrubStartTouchPoint = nil
        case .cancelled, .failed:
            scrubOrigin = nil
            scrubStartTouchPoint = nil
        default:
            break
        }
    }

    /// Observes this view's interactions even when persistence is unavailable. It is not a write confirmation.
    func record(_ event: String, properties: [String: Any] = [:]) {
        analytics?.record(event, properties: properties)
        onEvent?(event, properties)
    }

    func reloadWarehouseSignals() {
        // A new request cancels the preceding view task, including a query for an old store.
        signalsRevision &+= 1
    }

    func loadWarehouseSignals() async {
        guard let analytics else {
            markers = [:]
            suggestionScores = [:]
            refreshSuggestedTokens()
            return
        }
        async let loadedMarkers = analytics.fieldMarkers()
        async let loadedScores = analytics.suggestionScores()
        let nextMarkers = (try? await loadedMarkers) ?? [:]
        let nextScores = (try? await loadedScores) ?? [:]
        guard !Task.isCancelled else { return }
        markers = nextMarkers
        suggestionScores = nextScores
        refreshSuggestedTokens()
    }

    func searchSubmitted() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let fieldName = selectedFieldName {
            let values = model.categoricalValues(named: fieldName)
            guard
                let value = values.first(where: {
                    $0.localizedCaseInsensitiveCompare(query) == .orderedSame
                })
                    ?? values.first(where: {
                        $0.localizedCaseInsensitiveContains(query)
                    })
            else { return }

            tokens = [.fieldName(fieldName), .categoricalValue(value)]
            Task { @MainActor in searchText = "" }
            return
        }

        let fields = categoricalFieldNames()
        guard
            let field = fields.first(where: {
                $0.localizedCaseInsensitiveCompare(query) == .orderedSame
            })
                ?? fields.first(where: {
                    $0.localizedCaseInsensitiveContains(query)
                })
        else { return }

        tokens = [.fieldName(field)]
        Task { @MainActor in searchText = "" }
    }

    func refreshSuggestedTokens() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let fieldName = selectedFieldName {
            var values = model.categoricalValues(named: fieldName)
                .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }

            if searchDefaults.savedField == fieldName,
                let saved = searchDefaults.savedValue,
                let index = values.firstIndex(of: saved)
            {
                values.remove(at: index)
                values.insert(saved, at: 0)
            }
            suggestedTokens = values.prefix(12).map(SearchToken.categoricalValue)
            return
        }

        var fields = categoricalFieldNames()
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }

        if let saved = searchDefaults.savedField,
            let index = fields.firstIndex(of: saved)
        {
            fields.remove(at: index)
            fields.insert(saved, at: 0)
        }
        suggestedTokens = fields.prefix(12).map(SearchToken.fieldName)
    }

    func tokensChanged(from oldTokens: [SearchToken], to newTokens: [SearchToken]) {
        guard !synchronizingTokens, oldTokens != newTokens else { return }

        if newTokens.isEmpty {
            filter = nil
            refreshSuggestedTokens()
            return
        }

        guard case .fieldName(let fieldName) = newTokens[0] else {
            synchronizingTokens = true
            tokens = []
            synchronizingTokens = false
            filter = nil
            refreshSuggestedTokens()
            return
        }

        if newTokens.count > 2 {
            synchronizingTokens = true
            tokens = Array(newTokens.prefix(2))
            synchronizingTokens = false
        }

        if newTokens.count == 1 {
            filter = nil
            record(
                "filter_field_selected",
                properties: [
                    "fieldName": fieldName,
                    "source": "faceted_search",
                ]
            )
            suggestedTokens = model.categoricalValues(named: fieldName)
                .prefix(12)
                .map(SearchToken.categoricalValue)
            return
        }

        guard case .categoricalValue(let value) = newTokens[1] else {
            synchronizingTokens = true
            tokens = [.fieldName(fieldName)]
            synchronizingTokens = false
            filter = nil
            refreshSuggestedTokens()
            return
        }

        filter = nil
        if remembersFacet {
            explorerDefaults.lastField = fieldName
            explorerDefaults.lastValue = value
        }
        record(
            "filter_suggestion_selected",
            properties: [
                "fieldName": fieldName,
                "value": value,
                "source": "field_name_value_tokens",
                "resultsAfter": model.facetedResultCount(fieldName: fieldName, value: value),
            ]
        )
        reloadWarehouseSignals()
    }

    func categoricalFieldNames() -> [String] {
        var names = Set<String>()
        for feature in model.featureNodes() {
            model.collectCategoricalNames(in: feature, into: &names)
        }
        return names.sorted {
            let left = bestScore(forFieldName: $0)
            let right = bestScore(forFieldName: $1)
            if left != right { return left > right }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func bestScore(forFieldName name: String) -> Int {
        categoricalFields()
            .filter { $0.name == name }
            .map(\.score)
            .max() ?? 0
    }

    func categoricalFields() -> [FieldChoice] {
        var valuesByPath: [String: Set<String>] = [:]
        var namesByPath: [String: String] = [:]

        for feature in model.featureNodes() {
            model.collectCategoricalFields(in: feature, valuesByPath: &valuesByPath, namesByPath: &namesByPath)
        }

        return valuesByPath.compactMap { path, values in
            guard !values.isEmpty else { return nil }
            return FieldChoice(
                path: path,
                name: namesByPath[path] ?? model.fieldName(for: path),
                values: values.sorted(),
                marker: markers[path]?.label,
                score: suggestionScores[path] ?? 0
            )
        }
    }

    var isCurrentFacetSaved: Bool {
        guard let field = selectedFieldName, let value = selectedValue else { return false }
        return searchDefaults.savedField == field && searchDefaults.savedValue == value
    }

    func saveCurrentFacet() {
        guard let field = selectedFieldName, let value = selectedValue else { return }
        searchDefaults.savedField = field
        searchDefaults.savedValue = value
        refreshSuggestedTokens()
    }

    func restoreDefaultsIfNeeded() {
        guard remembersFacet, !didRestoreDefaults else { return }
        didRestoreDefaults = true
        guard
            let field = explorerDefaults.lastField,
            let value = explorerDefaults.lastValue,
            model.categoricalValues(named: field).contains(value)
        else { return }
        synchronizingTokens = true
        tokens = [.fieldName(field), .categoricalValue(value)]
        synchronizingTokens = false
    }

    // TODO: VoiceOver
    func adjustAccessibility(node: JSONNode, direction: Int) {
        guard let relativePath = model.featureRelativePath(from: node.path),
            let origin = model.initialFilter(path: relativePath, value: node.value)
        else { return }

        let base = filter?.path == relativePath ? filter! : origin
        let next = base.stepped(by: direction)
        guard next != base else { return }
        feedback.selectionChanged()
        applyFilter(next, source: "accessibility")
        UIAccessibility.post(notification: .announcement, argument: "\(next.description), \(resultCount) results")
    }

    func applyFilter(_ next: FieldFilter, source: String) {
        filter = next
        synchronizingTokens = true
        if case .category(let path, let value, let values) = next {
            let field = FieldChoice(
                path: path,
                name: model.fieldName(for: path),
                values: values,
                marker: markers[path]?.label,
                score: suggestionScores[path] ?? 0
            )
            tokens = [.fieldName(field.name), .categoricalValue(value)]
        } else {
            tokens = []
        }
        synchronizingTokens = false
        record(
            "filter_changed",
            properties: next.analyticsProperties.merging([
                "source": source
            ]) { _, new in new }
        )
        record(
            "filter_finished",
            properties:
                next.analyticsProperties.merging([
                    "description": next.description,
                    "resultsAfter": resultCount,
                    "source": source,
                ]) { _, new in new }
        )
        reloadWarehouseSignals()
    }

}

struct FieldChoice: Hashable {
    let path: String
    let name: String
    let values: [String]
    let marker: String?
    let score: Int

    static func == (lhs: FieldChoice, rhs: FieldChoice) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

enum SearchToken: Identifiable, Hashable {
    case fieldName(String)
    case categoricalValue(String)

    var id: String {
        switch self {
        case .fieldName(let name): return "field-name:\(name)"
        case .categoricalValue(let value): return "categorical-value:\(value)"
        }
    }
}

struct SearchTokenLabel: View {
    @Environment(\.searchSuggestionsPlacement) private var placement
    let token: SearchToken
    let searchDefaults: SearchDefaults

    var isSaved: Bool {
        switch token {
        case .fieldName(let name):
            return searchDefaults.savedField == name
        case .categoricalValue(let value):
            return searchDefaults.savedValue == value
        }
    }

    var body: some View {
        switch token {
        case .fieldName(let name):
            if placement == .menu {
                HStack(spacing: 6) {
                    Text(name)
                    if isSaved {
                        Text("Saved")
                            .textCase(.uppercase)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text("field")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .categoricalValue(let value):
            if placement == .menu {
                HStack(spacing: 6) {
                    Text(value)
                    if isSaved {
                        Text("Saved")
                            .textCase(.uppercase)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                    Text("equals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        JSONNodeView(root: JSONNode.make(name: "$", path: "$", value: ["type": "whaley", "items": [["id": "demo", "type": "run", "properties": ["level": 1]]]]))
    }
}
#endif

struct FeedbackHUD: View {
    let message: String
    var monospaced = false

    var body: some View {
        Text(message)
            .font(monospaced ? .title3.monospaced().weight(.semibold) : .headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 8)
    }
}
#endif
