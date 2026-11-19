#if canImport(UIKit) && os(iOS)
import CBLinearHierarchy
import Testing
import UIKit
@testable import JSONViewKit

@MainActor
@Test func retainedHierarchyRowsRefreshAndClearMetadataWithoutReplacingTheCellOrScrubGesture() async throws {
    let root = JSONNode.feed(items: [
        ["id": "moment/0", "properties": ["points": 10]],
    ])
    let path = "$.properties.points"
    let controller = CBLinearHierarchyViewController(rootNode: HierarchyNode(
        node: root, markers: [:], activeFilter: nil, resultCount: 1
    ))
    let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    let window: UIWindow
    if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
        window = UIWindow(windowScene: scene)
        window.frame = frame
    } else {
        window = UIWindow(frame: frame)
    }
    window.rootViewController = controller
    window.isHidden = false
    defer {
        window.isHidden = true
        window.rootViewController = nil
    }
    window.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    let collection = try #require(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
    let scrub = try #require(collection.gestureRecognizers?.first {
        $0 is UIPanGestureRecognizer && $0 !== collection.panGestureRecognizer
    })
    let original = try await visiblePointsCell(in: collection) { cell in
        cell.accessibilityValue == "10"
    }
    #expect((original.contentConfiguration as? UIListContentConfiguration)?.secondaryText == "10")

    let filter = FieldFilter.minimum(path: path, value: 10, values: [10, 20])
    controller.setRootNode(HierarchyNode(
        node: root, markers: [path: FieldMarker(label: "POPULAR")], activeFilter: filter, resultCount: 1
    ), animated: false)
    let updated = try await visiblePointsCell(in: collection) { cell in
        (cell.contentConfiguration as? UIListContentConfiguration)?.secondaryText == "10   [POPULAR]"
            && cell.accessibilityValue == "Active filter: \(filter.description), 1 results"
    }
    #expect(updated === original)
    #expect(collection.gestureRecognizers?.contains { $0 === scrub } == true)

    controller.setRootNode(HierarchyNode(
        node: root, markers: [:], activeFilter: nil, resultCount: 1
    ), animated: false)
    let cleared = try await visiblePointsCell(in: collection) { cell in
        (cell.contentConfiguration as? UIListContentConfiguration)?.secondaryText == "10"
            && cell.accessibilityValue == "10"
    }
    #expect(cleared === original)
    #expect(collection.gestureRecognizers?.contains { $0 === scrub } == true)
}

@MainActor
@Test func loadedHierarchyControllersAreReleasedWhenTheirHostDropsThem() async throws {
    weak var released: CBLinearHierarchyViewController?
    autoreleasepool {
        let root = JSONNode.feed(items: [["id": "moment/0", "properties": ["points": 10]]])
        let controller = CBLinearHierarchyViewController(rootNode: HierarchyNode(
            node: root, markers: [:], activeFilter: nil, resultCount: 1
        ))
        released = controller
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
    }

    // Initial snapshot work may briefly retain the loaded view. The data source's registration handlers must not
    // keep the controller alive once that work has finished and the host has released it.
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while released != nil && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(released == nil, "The hierarchy controller was retained after its host released it")
}

/// Diffable snapshots finish asynchronously. Wait for the visible row's actual state, with a bounded deadline.
@MainActor
private func visiblePointsCell(
    in collection: UICollectionView,
    matching expected: (UICollectionViewListCell) -> Bool
) async throws -> UICollectionViewListCell {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    func matchingCell() -> UICollectionViewListCell? {
        collection.superview?.layoutIfNeeded()
        collection.layoutIfNeeded()
        return collection.visibleCells.compactMap { $0 as? UICollectionViewListCell }
            .first { $0.accessibilityLabel == "points" && expected($0) }
    }
    repeat {
        if let cell = matchingCell() { return cell }
        try await Task.sleep(for: .milliseconds(10))
    } while clock.now < deadline
    return try #require(matchingCell(), "The visible hierarchy row did not receive the current metadata")
}
#endif
