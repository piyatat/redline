import Foundation
import RedlineShared
import XCTest

final class FeedbackPayloadTests: XCTestCase {
    func testRoundTrip() throws {
        let payload = FeedbackPayload(
            screen: "home",
            region: "Header",
            platform: "ios",
            capturedTs: "2026-06-18T03:27:59Z",
            comment: "Increase title size",
            pins: [DesignerPin(component: "Title", pin: "size=lg")],
            toolsUsed: ["pen"],
            strokes: [MarkupStroke(tool: "pen", color: "red", points: [[0, 0], [10, 10]])],
            compositePngBase64: "aGVsbG8="
        )

        let data = try payload.encode()
        let decoded = try FeedbackPayload.decode(from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testRejectUnsupportedSchema() {
        let payload = FeedbackPayload(
            schema: 99,
            screen: "x",
            region: "y",
            platform: "ios",
            capturedTs: "2026-06-18T03:27:59Z",
            comment: "z",
            compositePngBase64: ""
        )

        XCTAssertThrowsError(try payload.validateSchema())
    }

    func testValidateForIngestRequiresComposite() {
        let payload = FeedbackPayload(
            screen: "home",
            region: "Header",
            platform: "ios",
            capturedTs: "2026-06-18T03:27:59Z",
            comment: "fix",
            compositePngBase64: "   "
        )
        XCTAssertThrowsError(try payload.validateForIngest())
    }

    func testPromptBuilderIncludesPins() {
        let payload = FeedbackPayload(
            screen: "home",
            region: "CTA",
            platform: "ios",
            capturedTs: "2026-06-18T03:27:59Z",
            comment: "Widen button",
            pins: [DesignerPin(component: "Button", pin: "fillWidth=true")],
            compositePngBase64: ""
        )

        let prompt = AgentPromptBuilder().makePrompt(for: payload)
        XCTAssertTrue(prompt.contains("Button"))
        XCTAssertTrue(prompt.contains("fillWidth=true"))
    }

    func testPromptBuilderIncludesRuntimeContext() {
        let payload = FeedbackPayload(
            screen: "home",
            region: "CTA",
            platform: "ios",
            capturedTs: "2026-06-18T03:27:59Z",
            comment: "Widen button",
            compositePngBase64: "",
            runtime: AppRuntimeContext(
                bundleId: "dev.redline.demo",
                topViewController: "HomeViewController",
                callStack: ["0   Demo   0x0000000100001234  HomeViewController.save + 48"]
            )
        )
        let prompt = AgentPromptBuilder().makePrompt(for: payload)
        XCTAssertTrue(prompt.contains("App / runtime context"))
        XCTAssertTrue(prompt.contains("HomeViewController"))
        XCTAssertTrue(prompt.contains("Call stack"))
    }
}
