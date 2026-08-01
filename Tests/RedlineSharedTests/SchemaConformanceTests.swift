import Foundation
import RedlineShared
import XCTest

final class SchemaConformanceTests: XCTestCase {
    func testFeedbackSampleMatchesRequiredFields() throws {
        let payload = FeedbackPayload(
            screen: "home",
            region: "Header",
            platform: "ios",
            capturedTs: "2026-06-18T03:27:59Z",
            comment: "test",
            pins: [DesignerPin(component: "Title", pin: "size=lg")],
            strokes: [],
            compositePngBase64: "aGVsbG8=",
            inspector: InspectorBridgePayload(nodeId: "obj:1", hierarchyPath: ["Window", "Header"])
        )
        let data = try payload.encode()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["schema"] as? Int, 1)
        XCTAssertNotNil(json["screen"])
        XCTAssertNotNil(json["region"])
        XCTAssertNotNil(json["platform"])
        XCTAssertNotNil(json["capturedTs"])
        XCTAssertNotNil(json["comment"])
        XCTAssertNotNil(json["strokes"])
        XCTAssertNotNil(json["compositePngBase64"])
        XCTAssertNotNil(json["inspector"])
    }

    func testInspectorRequestEncodesNewRPCs() throws {
        let request = InspectorRequest(
            type: .setAttribute,
            nodeId: "obj:1",
            attributeKey: "alpha",
            attributeValue: "0.5"
        )
        let data = try WireCodec.encode(request)
        var buffer = data
        let decoded = try XCTUnwrap(try WireCodec.decodeOne(InspectorRequest.self, from: &buffer))
        XCTAssertEqual(decoded.type, .setAttribute)
        XCTAssertEqual(decoded.attributeKey, "alpha")
    }
}
