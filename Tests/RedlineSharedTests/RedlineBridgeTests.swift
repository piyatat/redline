import Foundation
import RedlineShared
import XCTest

final class RedlineBridgeTests: XCTestCase {
    func testHierarchyPathAndRegion() {
        let nodes: [String: HierarchyNode] = [
            "a": HierarchyNode(id: "a", framework: "uikit", className: "UIWindow", displayName: "Window", frame: .init(x: 0, y: 0, w: 100, h: 100), children: ["b"]),
            "b": HierarchyNode(id: "b", framework: "uikit", className: "UIView", displayName: "Header", frame: .init(x: 0, y: 0, w: 100, h: 20), children: ["c"], regionName: "Header"),
            "c": HierarchyNode(id: "c", framework: "uikit", className: "UILabel", displayName: "Title", frame: .init(x: 0, y: 0, w: 80, h: 20), children: []),
        ]
        let snapshot = HierarchySnapshot(
            app: InspectableAppInfo(bundleIdentifier: "test", appName: "Test"),
            roots: ["a"],
            nodes: nodes,
            capturedAt: "2026-01-01T00:00:00Z"
        )

        XCTAssertEqual(RedlineBridge.resolveRegion(for: "c", in: snapshot), "Header")
        XCTAssertEqual(RedlineBridge.hierarchyPath(for: "c", in: snapshot), ["Window", "Header", "Title"])
    }

    func testMeasureGap() {
        let from = HierarchyNode(id: "a", framework: "uikit", className: "A", displayName: "A", frame: .init(x: 0, y: 0, w: 100, h: 40), children: [])
        let to = HierarchyNode(id: "b", framework: "uikit", className: "B", displayName: "B", frame: .init(x: 108, y: 0, w: 100, h: 40), children: [])
        let gap = RedlineBridge.measureGap(from: from, to: to)
        XCTAssertEqual(gap.dx, 8)
        XCTAssertEqual(gap.dy, 0)
    }
}
