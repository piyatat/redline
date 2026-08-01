import Foundation
import RedlineShared
import XCTest

final class WireCodecTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let request = InspectorRequest(type: .ping)
        let data = try WireCodec.encode(request)
        var buffer = data
        let decoded = try XCTUnwrap(try WireCodec.decodeOne(InspectorRequest.self, from: &buffer))
        XCTAssertEqual(decoded.type, .ping)
        XCTAssertEqual(decoded.id, request.id)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testPartialBufferWaitsForMoreBytes() throws {
        let request = InspectorRequest(type: .hierarchy)
        let data = try WireCodec.encode(request)
        var buffer = data.prefix(6)
        XCTAssertNil(try WireCodec.decodeOne(InspectorRequest.self, from: &buffer))
        buffer.append(data.dropFirst(6))
        XCTAssertNotNil(try WireCodec.decodeOne(InspectorRequest.self, from: &buffer))
    }

    func testMultipleMessagesInOneBuffer() throws {
        let first = InspectorRequest(id: "a", type: .ping)
        let second = InspectorRequest(id: "b", type: .highlight, nodeId: "obj:1")
        var buffer = try WireCodec.encode(first)
        buffer.append(try WireCodec.encode(second))

        let decodedFirst = try XCTUnwrap(try WireCodec.decodeOne(InspectorRequest.self, from: &buffer))
        let decodedSecond = try XCTUnwrap(try WireCodec.decodeOne(InspectorRequest.self, from: &buffer))
        XCTAssertEqual(decodedFirst.id, "a")
        XCTAssertEqual(decodedSecond.id, "b")
        XCTAssertEqual(decodedSecond.nodeId, "obj:1")
    }
}
