import Foundation
import RedlineShared
import XCTest

final class GateRunnerTests: XCTestCase {
    func testValidateFeedbackScriptPassesForSampleBundle() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let payload = FeedbackPayload(
            screen: "demo",
            region: "Header",
            platform: "ios",
            capturedTs: "2026-07-06T00:00:00Z",
            comment: "Increase title size",
            compositePngBase64: "aGVsbG8="
        )
        try payload.encode().write(to: temp.appendingPathComponent("feedback.json"))

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let result = GateRunner.run(workspaceRoot: repoRoot, bundleDirectory: temp)
        let feedbackStage = result.stages.first { $0.name == "validate-feedback" }
        XCTAssertNotNil(feedbackStage)
        XCTAssertEqual(feedbackStage?.exitCode, 0)
    }
}
